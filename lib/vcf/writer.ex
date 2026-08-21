defmodule VCF.Writer do
  @moduledoc "Canonical VCF encoding and output destinations."

  alias VCF.Document
  alias VCF.Error
  alias VCF.Field
  alias VCF.FieldDefinition
  alias VCF.Genotype
  alias VCF.Header
  alias VCF.Metadata
  alias VCF.Record
  alias VCF.Sample
  alias VCF.Stream, as: VCFStream
  alias VCF.Validator
  alias VCF.Version

  @fixed_columns "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO"

  @doc "Encodes a document or stream to a canonical VCF binary."
  @spec encode(Document.t() | VCFStream.t(), keyword()) ::
          {:ok, binary()} | {:error, Error.t() | [Error.t()]}
  def encode(data, options \\ [])

  def encode(%Document{header: header, records: records}, options),
    do: encode(header, records, options)

  def encode(%VCFStream{header: header} = stream, options) do
    with {:ok, records} <- collect_stream(stream) do
      encode(header, records, options)
    end
  end

  @doc "Encodes a header and record enumerable to a canonical VCF binary."
  @spec encode(Header.t(), Enumerable.t(), keyword()) ::
          {:ok, binary()} | {:error, Error.t() | [Error.t()]}
  def encode(%Header{} = header, records, options) do
    records = Enum.to_list(records)

    with :ok <- validate(header, records, options),
         {:ok, record_lines} <- encode_records(records, header.version) do
      {:ok, IO.iodata_to_binary([encode_header(header), record_lines])}
    end
  end

  @doc "Encodes and writes to a path or caller-owned I/O device."
  @spec write(term(), Document.t() | VCFStream.t(), keyword()) ::
          :ok | {:error, Error.t() | [Error.t()]}
  def write(destination, data, options \\ [])

  def write(destination, %Document{header: header, records: records}, options),
    do: write_records(destination, header, records, options)

  def write(destination, %VCFStream{header: header} = stream, options),
    do: write_records(destination, header, stream, options)

  @spec write(term(), Header.t(), Enumerable.t(), keyword()) ::
          :ok | {:error, Error.t() | [Error.t()]}
  def write(destination, %Header{} = header, records, options) do
    write_records(destination, header, records, options)
  end

  defp write_records(destination, header, records, options) do
    with :ok <- validate_header_for_write(header, options),
         {:ok, sink} <- open_sink(destination, options) do
      result =
        with :ok <- sink_write(sink, encode_header(header)),
             :ok <- write_record_enumerable(sink, header, records, options),
             :ok <- finish_sink(sink) do
          :ok
        end

      if result == :ok do
        close_owned_device(sink)
        :ok
      else
        abort_sink(sink)
        result
      end
    end
  end

  defp validate_header_for_write(header, options) do
    if Keyword.get(options, :validate, true) do
      case Validator.validate_header(header) do
        [] -> :ok
        errors -> {:error, errors}
      end
    else
      :ok
    end
  end

  defp write_record_enumerable(sink, header, records, options) do
    Enum.reduce_while(records, :ok, fn item, :ok ->
      with {:ok, record} <- normalize_record(item),
           :ok <- validate_record_for_write(record, header, options),
           {:ok, encoded} <- encode_record(record, header.version),
           :ok <- sink_write(sink, encoded) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp normalize_record(%Record{} = record), do: {:ok, record}
  defp normalize_record({:ok, %Record{} = record}), do: {:ok, record}
  defp normalize_record({:error, %Error{} = error}), do: {:error, error}

  defp normalize_record(value),
    do: {:error, %Error{kind: :encoding_error, value: value, reason: :expected_record}}

  defp validate_record_for_write(record, header, options) do
    if Keyword.get(options, :validate, true) do
      case Validator.validate_record(record, header) do
        [] -> :ok
        errors -> {:error, errors}
      end
    else
      :ok
    end
  end

  defp validate(header, records, options) do
    if Keyword.get(options, :validate, true) do
      case Validator.validate(header, records) do
        [] -> :ok
        errors -> {:error, errors}
      end
    else
      :ok
    end
  end

  defp encode_header(%Header{} = header) do
    metadata =
      header.metadata
      |> Enum.reject(&(&1.key == "fileformat"))
      |> Enum.map(&encode_metadata/1)

    columns =
      if header.samples == [] do
        @fixed_columns
      else
        @fixed_columns <> "\tFORMAT\t" <> Enum.join(header.samples, "\t")
      end

    ["##fileformat=", encode_version(header.version), "\n", metadata, columns, "\n"]
  end

  defp encode_metadata(%Metadata{key: key, value: %FieldDefinition{} = definition}) do
    attributes =
      [
        {"ID", definition.id},
        {"Number", encode_number(definition.number)},
        {"Type", encode_type(definition.type)},
        {"Description", definition.description}
      ] ++ definition.attributes

    ["##", key, "=<", encode_attributes(attributes), ">\n"]
  end

  defp encode_metadata(%Metadata{raw: raw, value: value}) when is_binary(raw) and is_list(value),
    do: [raw, "\n"]

  defp encode_metadata(%Metadata{key: key, value: attributes}) when is_list(attributes),
    do: ["##", key, "=<", encode_attributes(attributes), ">\n"]

  defp encode_metadata(%Metadata{key: key, value: value}), do: ["##", key, "=", value, "\n"]

  defp encode_attributes(attributes) do
    Enum.map_join(attributes, ",", fn {key, value} ->
      key <> "=" <> encode_attribute(key, value)
    end)
  end

  defp encode_attribute("Description", value), do: quote_attribute(value)

  defp encode_attribute(_key, value) do
    if String.contains?(value, [",", " ", "\t", "\"", "\\"]) do
      quote_attribute(value)
    else
      value
    end
  end

  defp quote_attribute(value) do
    escaped = value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
    "\"" <> escaped <> "\""
  end

  defp encode_records(records, version) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, lines} ->
      case encode_record(record, version) do
        {:ok, line} -> {:cont, {:ok, [lines, line]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp encode_record(%Record{} = record, version) do
    with {:ok, samples} <- encode_samples(record, version),
         {:ok, info} <- encode_info(record.info, version) do
      fixed = [
        record.chrom,
        Integer.to_string(record.pos),
        encode_list_or_missing(record.ids, ";"),
        record.ref,
        encode_list_or_missing(record.alt, ","),
        encode_qual(record.qual, version),
        encode_filter(record.filter),
        info
      ]

      columns =
        if samples == [], do: fixed, else: fixed ++ [Enum.join(record.format, ":") | samples]

      {:ok, [Enum.intersperse(columns, "\t"), "\n"]}
    end
  end

  defp encode_samples(%Record{format: [], samples: []}, _version), do: {:ok, []}

  defp encode_samples(%Record{format: keys, samples: samples}, version) do
    Enum.reduce_while(samples, {:ok, []}, fn sample, {:ok, encoded} ->
      case encode_sample(sample, keys, version) do
        {:ok, value} -> {:cont, {:ok, [value | encoded]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end

  defp encode_sample(%Sample{values: fields}, keys, version) do
    Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, values} ->
      value = fields |> Enum.find(&(&1.key == key)) |> field_value()

      case encode_value(value, version) do
        {:ok, encoded} -> {:cont, {:ok, [encoded | values]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, values |> Enum.reverse() |> Enum.join(":")}
      error -> error
    end
  end

  defp field_value(nil), do: nil
  defp field_value(%Field{value: value}), do: value

  defp encode_info([], _version), do: {:ok, "."}

  defp encode_info(fields, version) do
    Enum.reduce_while(fields, {:ok, []}, fn
      %Field{key: key, value: true}, {:ok, encoded} ->
        {:cont, {:ok, [key | encoded]}}

      %Field{key: key, value: value}, {:ok, encoded} ->
        case encode_value(value, version) do
          {:ok, item} -> {:cont, {:ok, [key <> "=" <> item | encoded]}}
          {:error, error} -> {:halt, {:error, error}}
        end
    end)
    |> case do
      {:ok, encoded} -> {:ok, encoded |> Enum.reverse() |> Enum.join(";")}
      error -> error
    end
  end

  defp encode_value!(value, version) do
    {:ok, encoded} = encode_value(value, version)
    encoded
  end

  defp encode_value(nil, _version), do: {:ok, "."}
  defp encode_value(:nan, _version), do: {:ok, "NaN"}
  defp encode_value(:positive_infinity, _version), do: {:ok, "Inf"}
  defp encode_value(:negative_infinity, _version), do: {:ok, "-Inf"}
  defp encode_value(value, _version) when is_integer(value), do: {:ok, Integer.to_string(value)}
  defp encode_value(value, _version) when is_float(value), do: {:ok, Float.to_string(value)}

  defp encode_value(value, %Version{minor: minor}) when is_binary(value) and minor >= 3,
    do: {:ok, percent_encode(value, <<>>)}

  defp encode_value(value, _version) when is_binary(value), do: {:ok, value}

  defp encode_value(values, version) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, encoded} ->
      case encode_value(value, version) do
        {:ok, item} -> {:cont, {:ok, [item | encoded]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, encoded |> Enum.reverse() |> Enum.join(",")}
      error -> error
    end
  end

  defp encode_value(%Genotype{} = genotype, _version), do: Genotype.encode(genotype)

  defp encode_value(value, _version),
    do: {:error, %Error{kind: :encoding_error, value: value, reason: :unsupported_value}}

  defp encode_list_or_missing([], _separator), do: "."
  defp encode_list_or_missing(values, separator), do: Enum.join(values, separator)

  defp encode_qual(nil, _version), do: "."
  defp encode_qual(value, version), do: encode_value!(value, version)

  defp percent_encode(<<>>, encoded), do: encoded

  defp percent_encode(<<character, rest::binary>>, encoded) do
    replacement =
      case character do
        ?% -> "%25"
        ?: -> "%3A"
        ?; -> "%3B"
        ?= -> "%3D"
        ?, -> "%2C"
        ?\t -> "%09"
        ?\n -> "%0A"
        ?\r -> "%0D"
        ?\s -> "%20"
        _other -> <<character>>
      end

    percent_encode(rest, <<encoded::binary, replacement::binary>>)
  end

  defp encode_filter(:pass), do: "PASS"
  defp encode_filter(nil), do: "."
  defp encode_filter(filters), do: Enum.join(filters, ";")

  defp encode_version(%Version{major: major, minor: minor}), do: "VCFv#{major}.#{minor}"

  defp encode_number(number) when is_integer(number), do: Integer.to_string(number)
  defp encode_number(:a), do: "A"
  defp encode_number(:r), do: "R"
  defp encode_number(:g), do: "G"
  defp encode_number(:p), do: "P"
  defp encode_number(:la), do: "LA"
  defp encode_number(:lr), do: "LR"
  defp encode_number(:lg), do: "LG"
  defp encode_number(:m), do: "M"
  defp encode_number(:variable), do: "."

  defp encode_type(:integer), do: "Integer"
  defp encode_type(:float), do: "Float"
  defp encode_type(:flag), do: "Flag"
  defp encode_type(:character), do: "Character"
  defp encode_type(:string), do: "String"

  defp collect_stream(stream) do
    Enum.reduce_while(stream, {:ok, []}, fn
      %Record{} = record, {:ok, records} -> {:cont, {:ok, [record | records]}}
      {:ok, %Record{} = record}, {:ok, records} -> {:cont, {:ok, [record | records]}}
      {:error, error}, {:ok, _records} -> {:halt, {:error, error}}
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      error -> error
    end
  end

  defp open_sink(destination, options) do
    compression = Keyword.get(options, :compression, compression_from_destination(destination))

    with true <- compression in [:none, :gzip] || invalid_compression(compression),
         {:ok, device, owned?} <- open_destination(destination),
         {:ok, z} <- open_compressor(compression) do
      {:ok,
       %{
         compression: compression,
         destination: destination,
         device: device,
         owned?: owned?,
         z: z
       }}
    end
  end

  defp open_destination(path) when is_binary(path) do
    case File.open(path, [:write, :binary]) do
      {:ok, device} -> {:ok, device, true}
      {:error, reason} -> {:error, %Error{kind: :write_error, value: path, reason: reason}}
    end
  end

  defp open_destination(device), do: {:ok, device, false}

  defp open_compressor(:none), do: {:ok, nil}

  defp open_compressor(:gzip) do
    z = :zlib.open()

    try do
      :ok = :zlib.deflateInit(z, :default, :deflated, 31, 8, :default)
      {:ok, z}
    catch
      kind, reason ->
        :zlib.close(z)

        {:error,
         %Error{
           kind: :write_error,
           value: {kind, reason},
           reason: :compression_init_failed
         }}
    end
  end

  defp invalid_compression(compression) do
    {:error,
     %Error{
       kind: :invalid_option,
       key: "compression",
       value: compression,
       reason: :unsupported_compression
     }}
  end

  defp sink_write(%{compression: :none, device: device}, data),
    do: write_device(device, data)

  defp sink_write(%{compression: :gzip, device: device, z: z}, data) do
    try do
      z |> :zlib.deflate(data) |> then(&write_device(device, &1))
    catch
      kind, reason ->
        {:error, %Error{kind: :write_error, value: {kind, reason}, reason: :compression_failed}}
    end
  end

  defp finish_sink(%{compression: :none}), do: :ok

  defp finish_sink(%{compression: :gzip, device: device, z: z}) do
    try do
      with :ok <- z |> :zlib.deflate(<<>>, :finish) |> then(&write_device(device, &1)),
           :ok <- :zlib.deflateEnd(z) do
        :zlib.close(z)
      end
    catch
      kind, reason ->
        {:error,
         %Error{
           kind: :write_error,
           value: {kind, reason},
           reason: :compression_finish_failed
         }}
    end
  end

  defp write_device(device, data) do
    case IO.binwrite(device, data) do
      :ok -> :ok
      {:error, reason} -> {:error, %Error{kind: :write_error, value: device, reason: reason}}
    end
  end

  defp abort_sink(%{compression: :gzip, z: z} = sink) do
    try do
      :zlib.close(z)
    catch
      _kind, _reason -> :ok
    end

    close_owned_device(sink)
    remove_failed_path(sink)
  end

  defp abort_sink(sink) do
    close_owned_device(sink)
    remove_failed_path(sink)
  end

  defp close_owned_device(%{owned?: true, device: device}), do: File.close(device)
  defp close_owned_device(%{owned?: false}), do: :ok

  defp remove_failed_path(%{owned?: true, destination: path}), do: File.rm(path)
  defp remove_failed_path(%{owned?: false}), do: :ok

  defp compression_from_destination(path) when is_binary(path) do
    if String.ends_with?(path, ".gz"), do: :gzip, else: :none
  end

  defp compression_from_destination(_device), do: :none
end
