defmodule VCF.Parser.Record do
  @moduledoc false

  alias VCF.Error
  alias VCF.Field
  alias VCF.FieldDefinition
  alias VCF.Genotype
  alias VCF.Header
  alias VCF.Parser.Value
  alias VCF.Record
  alias VCF.Sample
  alias VCF.Validator.Alternate
  alias VCF.Warning

  @spec parse(String.t(), pos_integer(), Header.t(), keyword()) ::
          {:ok, Record.t()} | {:error, Error.t()}
  def parse(line, line_number, %Header{} = header, options \\ []) do
    mode = Keyword.get(options, :mode, :strict)
    raw = trim_line_ending(line)
    columns = String.split(raw, "\t", trim: false)

    with {:ok, fixed, format, sample_columns} <- split_columns(columns, header, line_number),
         [chrom, pos, ids, ref, alt, qual, filter, info] <- fixed,
         {:ok, parsed_pos} <- parse_integer(pos, line_number, :pos),
         {:ok, parsed_alt} <- parse_alt(alt, line_number),
         {:ok, parsed_qual} <- parse_qual(qual, line_number),
         {:ok, info_fields, info_warnings} <- parse_info(info, header, line_number, mode),
         {:ok, format_keys, samples, sample_warnings} <-
           parse_samples(format, sample_columns, header, line_number, mode) do
      record = %Record{
        chrom: chrom,
        pos: parsed_pos,
        ids: split_missing(ids, ";"),
        ref: ref,
        alt: parsed_alt,
        qual: parsed_qual,
        filter: parse_filter(filter),
        info: info_fields,
        format: format_keys,
        samples: samples,
        line: line_number,
        warnings: info_warnings ++ sample_warnings,
        raw: raw
      }

      {:ok, record}
    else
      {:error, %Error{} = error} -> {:error, error}
      _failure -> record_error(line_number, :record, raw, :invalid_field_count)
    end
  end

  defp split_columns(columns, %Header{samples: []}, line_number) do
    case columns do
      [chrom, pos, ids, ref, alt, qual, filter, info] ->
        {:ok, [chrom, pos, ids, ref, alt, qual, filter, info], nil, []}

      _other ->
        record_error(line_number, :record, columns, :invalid_field_count)
    end
  end

  defp split_columns(columns, %Header{samples: sample_names}, line_number) do
    expected_count = 9 + length(sample_names)

    if length(columns) == expected_count do
      {fixed, [format | samples]} = Enum.split(columns, 8)
      {:ok, fixed, format, samples}
    else
      record_error(line_number, :samples, columns, :sample_count_mismatch)
    end
  end

  defp parse_integer(value, line, field) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _failure -> record_error(line, field, value, :expected_integer)
    end
  end

  defp parse_alt(".", _line), do: {:ok, []}

  defp parse_alt(value, line) do
    alleles = String.split(value, ",", trim: false)

    case Enum.find_value(alleles, fn allele ->
           case Alternate.validate(allele, line: line) do
             :ok -> nil
             {:error, error} -> error
           end
         end) do
      nil -> {:ok, alleles}
      error -> {:error, error}
    end
  end

  defp parse_qual(".", _line), do: {:ok, nil}

  defp parse_qual(value, line) do
    case Value.parse(value, :float) do
      {:ok, qual} -> {:ok, qual}
      {:error, error} -> {:error, %{error | line: line, field: :qual}}
    end
  end

  defp parse_info(".", _header, _line, _mode), do: {:ok, [], []}

  defp parse_info(value, header, line, mode) do
    value
    |> String.split(";", trim: false)
    |> Enum.reduce_while({:ok, [], []}, fn entry, {:ok, fields, warnings} ->
      case parse_info_entry(entry, header, line, mode) do
        {:ok, field, entry_warnings} ->
          {:cont, {:ok, [field | fields], Enum.reverse(entry_warnings) ++ warnings}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, fields, warnings} -> {:ok, Enum.reverse(fields), Enum.reverse(warnings)}
      error -> error
    end
  end

  defp parse_info_entry(entry, header, line, mode) do
    case String.split(entry, "=", parts: 2) do
      [key] when key != "" ->
        definition = Header.definition(header, :info, key)

        if match?(%FieldDefinition{type: :flag}, definition) or definition == nil do
          {:ok, %Field{key: key, value: true, raw: nil}, []}
        else
          typed_value("", definition, :info, key, line, mode)
        end

      [key, raw] when key != "" and raw != "" ->
        definition = Header.definition(header, :info, key)
        typed_value(raw, definition, :info, key, line, mode)

      _invalid ->
        record_error(line, :info, entry, :invalid_info)
    end
  end

  defp parse_samples(nil, [], %Header{samples: []}, _line, _mode), do: {:ok, [], [], []}

  defp parse_samples(format, sample_columns, %Header{samples: names} = header, line, mode) do
    keys = String.split(format, ":", trim: false)

    names
    |> Enum.zip(sample_columns)
    |> Enum.reduce_while({:ok, [], []}, fn {name, values}, {:ok, samples, warnings} ->
      case parse_sample(name, values, keys, header, line, mode) do
        {:ok, sample, sample_warnings} ->
          {:cont, {:ok, [sample | samples], Enum.reverse(sample_warnings) ++ warnings}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, samples, warnings} ->
        {:ok, keys, Enum.reverse(samples), Enum.reverse(warnings)}

      error ->
        error
    end
  end

  defp parse_sample(name, ".", keys, header, line, mode) do
    parse_sample(name, Enum.map_join(keys, ":", fn _key -> "." end), keys, header, line, mode)
  end

  defp parse_sample(name, raw_values, keys, header, line, mode) do
    values = String.split(raw_values, ":", trim: false)

    if length(values) > length(keys) do
      record_error(line, :format, raw_values, :too_many_format_values)
    else
      padded = values ++ List.duplicate(".", length(keys) - length(values))

      keys
      |> Enum.zip(padded)
      |> Enum.reduce_while({:ok, [], []}, fn {key, raw}, {:ok, fields, warnings} ->
        definition = Header.definition(header, :format, key)

        case format_value(raw, definition, key, line, mode) do
          {:ok, field, field_warnings} ->
            {:cont, {:ok, [field | fields], Enum.reverse(field_warnings) ++ warnings}}

          {:error, error} ->
            {:halt, {:error, error}}
        end
      end)
      |> case do
        {:ok, fields, warnings} ->
          {:ok, %Sample{name: name, values: Enum.reverse(fields)}, Enum.reverse(warnings)}

        error ->
          error
      end
    end
  end

  defp format_value(raw, definition, "GT", line, mode) do
    case Genotype.parse(raw) do
      {:ok, genotype} -> {:ok, %Field{key: "GT", value: genotype, raw: raw}, []}
      {:error, error} -> recover_value(error, raw, definition, :format, "GT", line, mode)
    end
  end

  defp format_value(raw, definition, key, line, mode) do
    typed_value(raw, definition, :format, key, line, mode)
  end

  defp typed_value(raw, nil, _field, key, _line, _mode) do
    {:ok, %Field{key: key, value: unknown_value(raw), raw: raw}, []}
  end

  defp typed_value(raw, %FieldDefinition{type: nil}, _field, key, _line, _mode) do
    {:ok, %Field{key: key, value: unknown_value(raw), raw: raw}, []}
  end

  defp typed_value(raw, %FieldDefinition{} = definition, field, key, line, mode) do
    parser = if definition.number == 1, do: &Value.parse/2, else: &Value.parse_list/2

    case parser.(raw, definition.type) do
      {:ok, value} -> {:ok, %Field{key: key, value: value, raw: raw}, []}
      {:error, error} -> recover_value(error, raw, definition, field, key, line, mode)
    end
  end

  defp recover_value(error, raw, _definition, field, key, line, :strict) do
    {:error, %{error | line: line, field: field, key: key, value: raw}}
  end

  defp recover_value(error, raw, _definition, field, key, line, :permissive) do
    warning = %Warning{
      line: line,
      field: field,
      key: key,
      value: raw,
      reason: error.reason
    }

    {:ok, %Field{key: key, value: raw, raw: raw}, [warning]}
  end

  defp unknown_value("."), do: nil
  defp unknown_value(raw), do: raw

  defp split_missing(".", _separator), do: []
  defp split_missing(value, separator), do: String.split(value, separator, trim: false)

  defp parse_filter("PASS"), do: :pass
  defp parse_filter("."), do: nil
  defp parse_filter(value), do: String.split(value, ";", trim: false)

  defp record_error(line, field, value, reason) do
    {:error,
     %Error{
       kind: :invalid_record,
       line: line,
       field: field,
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
