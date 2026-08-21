defmodule VCF.Parser.Header do
  @moduledoc false

  alias VCF.Error
  alias VCF.FieldDefinition
  alias VCF.Header
  alias VCF.Metadata
  alias VCF.Parser.Metadata, as: MetadataParser
  alias VCF.Version
  alias VCF.Warning

  @fixed_columns ["#CHROM", "POS", "ID", "REF", "ALT", "QUAL", "FILTER", "INFO"]
  @fixed_atoms [:chrom, :pos, :id, :ref, :alt, :qual, :filter, :info]

  @spec parse([{pos_integer(), String.t()}], keyword()) ::
          {:ok, Header.t(), [{pos_integer(), String.t()}]} | {:error, Error.t()}
  def parse(lines, options \\ []) do
    mode = Keyword.get(options, :mode, :strict)

    case lines do
      [{line_number, line} | rest] -> parse_fileformat(line_number, line, rest, mode)
      [] -> header_error(:missing_fileformat, 1, :fileformat, nil, :required)
    end
  end

  defp parse_fileformat(line_number, line, rest, mode) do
    raw = trim_line_ending(line)

    case raw do
      "##fileformat=" <> value ->
        case Version.parse(value) do
          {:ok, version} ->
            metadata = %Metadata{key: "fileformat", value: version, raw: raw, line: line_number}
            parse_metadata(rest, mode, version, [metadata], [], %{})

          {:error, error} ->
            {:error, %{error | line: line_number}}
        end

      _other ->
        header_error(:missing_fileformat, line_number, :fileformat, raw, :must_be_first)
    end
  end

  defp parse_metadata([], _mode, _version, _metadata, _warnings, _seen) do
    header_error(:missing_header, nil, :header, nil, :required)
  end

  defp parse_metadata([{line_number, line} | rest], mode, version, metadata, warnings, seen) do
    raw = trim_line_ending(line)

    cond do
      String.starts_with?(raw, "##") ->
        with {:ok, entry, entry_warnings} <- MetadataParser.parse(raw, line_number, mode),
             {:ok, duplicate_warnings, next_seen} <- duplicate_check(entry, seen, mode) do
          parse_metadata(
            rest,
            mode,
            version,
            [entry | metadata],
            Enum.reverse(entry_warnings ++ duplicate_warnings) ++ warnings,
            next_seen
          )
        end

      String.starts_with?(raw, "#CHROM") ->
        with {:ok, columns, samples, sample_warnings} <- parse_columns(raw, line_number, mode) do
          header = %Header{
            version: version,
            metadata: Enum.reverse(metadata),
            columns: columns,
            samples: samples,
            warnings: Enum.reverse(warnings) ++ sample_warnings
          }

          {:ok, header, rest}
        end

      true ->
        header_error(:missing_header, line_number, :header, raw, :required_before_records)
    end
  end

  defp duplicate_check(entry, seen, mode) do
    case identifier(entry) do
      nil ->
        {:ok, [], seen}

      identifier ->
        if Map.has_key?(seen, identifier) do
          duplicate_definition(entry, mode, seen)
        else
          {:ok, [], Map.put(seen, identifier, true)}
        end
    end
  end

  defp duplicate_definition(entry, :strict, _seen) do
    id = identifier_value(entry)
    header_error(:invalid_header, entry.line, :metadata, entry.raw, :duplicate_definition, id)
  end

  defp duplicate_definition(entry, :permissive, seen) do
    id = identifier_value(entry)

    warning = %Warning{
      line: entry.line,
      field: :metadata,
      key: id,
      value: entry.raw,
      reason: :duplicate_definition
    }

    {:ok, [warning], seen}
  end

  defp identifier(%Metadata{key: key, value: %FieldDefinition{id: id}}), do: {key, id}

  defp identifier(%Metadata{key: key, value: attributes}) when is_list(attributes) do
    case List.keyfind(attributes, "ID", 0) do
      {"ID", id} -> {key, id}
      nil -> nil
    end
  end

  defp identifier(_entry), do: nil

  defp identifier_value(%Metadata{value: %FieldDefinition{id: id}}), do: id

  defp identifier_value(%Metadata{value: attributes}) do
    {"ID", id} = List.keyfind(attributes, "ID", 0)
    id
  end

  defp parse_columns(raw, line_number, mode) do
    case String.split(raw, "\t") do
      @fixed_columns ->
        {:ok, @fixed_atoms, [], []}

      @fixed_columns ++ ["FORMAT" | samples] when samples != [] ->
        validate_samples(samples, line_number, mode)

      columns ->
        header_error(:invalid_header, line_number, :columns, columns, :invalid_columns)
    end
  end

  defp validate_samples(samples, line_number, mode) do
    duplicate = duplicate_sample(samples)

    cond do
      Enum.any?(samples, &(&1 == "")) ->
        header_error(:invalid_header, line_number, :samples, "", :empty_sample)

      duplicate == nil ->
        {:ok, @fixed_atoms ++ [:format], samples, []}

      mode == :strict ->
        header_error(:invalid_header, line_number, :samples, duplicate, :duplicate_sample)

      true ->
        warning = %Warning{
          line: line_number,
          field: :samples,
          value: duplicate,
          reason: :duplicate_sample
        }

        {:ok, @fixed_atoms ++ [:format], samples, [warning]}
    end
  end

  defp duplicate_sample(samples) do
    Enum.reduce_while(samples, MapSet.new(), fn sample, seen ->
      if MapSet.member?(seen, sample) do
        {:halt, sample}
      else
        {:cont, MapSet.put(seen, sample)}
      end
    end)
    |> case do
      %MapSet{} -> nil
      sample -> sample
    end
  end

  defp header_error(kind, line, field, value, reason, key \\ nil) do
    {:error,
     %Error{
       kind: kind,
       line: line,
       field: field,
       key: key,
       value: value,
       reason: reason
     }}
  end

  defp trim_line_ending(line) do
    line
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
  end
end
