defmodule VCF.Parser.Metadata do
  @moduledoc false

  alias VCF.Error
  alias VCF.FieldDefinition
  alias VCF.Metadata
  alias VCF.Warning

  @typed_keys ["INFO", "FORMAT"]
  @required_definition_keys ["ID", "Number", "Type", "Description"]

  @spec parse(String.t(), pos_integer(), :strict | :permissive) ::
          {:ok, Metadata.t(), [Warning.t()]} | {:error, Error.t()}
  def parse(line, line_number, mode) when mode in [:strict, :permissive] do
    raw = trim_line_ending(line)

    with "##" <> content <- raw,
         [key, value] when key != "" <- String.split(content, "=", parts: 2) do
      parse_value(key, value, raw, line_number, mode)
    else
      _failure -> metadata_error(raw, line_number, nil, :invalid_syntax)
    end
  end

  defp parse_value(key, "<" <> _rest = value, raw, line_number, mode) do
    with true <- String.ends_with?(value, ">") || :unterminated_structure,
         body <- binary_part(value, 1, byte_size(value) - 2),
         {:ok, parts} <- split_attributes(body),
         {:ok, attributes} <- parse_attributes(parts) do
      structured_metadata(key, attributes, raw, line_number, mode)
    else
      reason when is_atom(reason) -> metadata_error(raw, line_number, nil, reason)
      {:error, reason} -> metadata_error(raw, line_number, nil, reason)
    end
  end

  defp parse_value(key, value, raw, line_number, _mode) do
    {:ok, %Metadata{key: key, value: value, raw: raw, line: line_number}, []}
  end

  defp structured_metadata(key, attributes, raw, line_number, mode) when key in @typed_keys do
    values = Map.new(attributes)

    with {:ok, id} <- required(values, "ID"),
         {:ok, number, number_warnings} <-
           parse_number(Map.get(values, "Number"), id, raw, line_number, mode),
         {:ok, type, type_warnings} <-
           parse_type(Map.get(values, "Type"), id, raw, line_number, mode) do
      definition = %FieldDefinition{
        id: id,
        number: number,
        type: type,
        description: Map.get(values, "Description"),
        attributes:
          Enum.reject(attributes, fn {name, _value} -> name in @required_definition_keys end)
      }

      metadata = %Metadata{key: key, value: definition, raw: raw, line: line_number}
      {:ok, metadata, number_warnings ++ type_warnings}
    else
      {:error, reason} -> metadata_error(raw, line_number, Map.get(values, "ID"), reason)
    end
  end

  defp structured_metadata(key, attributes, raw, line_number, _mode) do
    {:ok, %Metadata{key: key, value: attributes, raw: raw, line: line_number}, []}
  end

  defp required(values, key) do
    case Map.fetch(values, key) do
      {:ok, value} when value != "" -> {:ok, value}
      _missing -> {:error, :missing_id}
    end
  end

  defp parse_number(nil, _id, _raw, _line, _mode), do: {:ok, nil, []}

  defp parse_number(value, id, raw, line, mode) do
    case FieldDefinition.parse_number(value) do
      {:ok, number} -> {:ok, number, []}
      :error -> recover_or_error(mode, id, raw, line, :invalid_number)
    end
  end

  defp parse_type(nil, _id, _raw, _line, _mode), do: {:ok, nil, []}

  defp parse_type(value, id, raw, line, mode) do
    case FieldDefinition.parse_type(value) do
      {:ok, type} -> {:ok, type, []}
      :error -> recover_or_error(mode, id, raw, line, :invalid_type)
    end
  end

  defp recover_or_error(:strict, _id, _raw, _line, reason), do: {:error, reason}

  defp recover_or_error(:permissive, id, raw, line, reason) do
    warning = %Warning{line: line, field: :metadata, key: id, value: raw, reason: reason}
    {:ok, nil, [warning]}
  end

  defp split_attributes(body), do: split_attributes(body, "", [], false, false)

  defp split_attributes(<<>>, current, parts, false, false) when current != "" do
    {:ok, Enum.reverse([current | parts])}
  end

  defp split_attributes(<<>>, _current, _parts, true, _escaped), do: {:error, :unterminated_quote}
  defp split_attributes(<<>>, _current, _parts, _quoted, _escaped), do: {:error, :empty_structure}

  defp split_attributes(<<character::utf8, rest::binary>>, current, parts, quoted, true) do
    split_attributes(rest, current <> <<character::utf8>>, parts, quoted, false)
  end

  defp split_attributes(<<?\\, rest::binary>>, current, parts, true, false) do
    split_attributes(rest, current <> "\\", parts, true, true)
  end

  defp split_attributes(<<?\", rest::binary>>, current, parts, quoted, false) do
    split_attributes(rest, current <> "\"", parts, not quoted, false)
  end

  defp split_attributes(<<?,, rest::binary>>, current, parts, false, false)
       when current != "" do
    split_attributes(rest, "", [current | parts], false, false)
  end

  defp split_attributes(<<character::utf8, rest::binary>>, current, parts, quoted, false) do
    split_attributes(rest, current <> <<character::utf8>>, parts, quoted, false)
  end

  defp parse_attributes(parts) do
    Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, attributes} ->
      case String.split(part, "=", parts: 2) do
        [name, value] when name != "" and value != "" ->
          case decode_value(value) do
            {:ok, decoded} -> {:cont, {:ok, [{name, decoded} | attributes]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        _invalid ->
          {:halt, {:error, :missing_attribute_value}}
      end
    end)
    |> case do
      {:ok, attributes} -> {:ok, Enum.reverse(attributes)}
      error -> error
    end
  end

  defp decode_value(<<?\", rest::binary>>) do
    if String.ends_with?(rest, "\"") do
      inner = binary_part(rest, 0, byte_size(rest) - 1)
      {:ok, unescape(inner, "")}
    else
      {:error, :unterminated_quote}
    end
  end

  defp decode_value(value), do: {:ok, value}

  defp unescape(<<>>, result), do: result

  defp unescape(<<?\\, character::utf8, rest::binary>>, result) when character in [?\\, ?\"] do
    unescape(rest, result <> <<character::utf8>>)
  end

  defp unescape(<<character::utf8, rest::binary>>, result) do
    unescape(rest, result <> <<character::utf8>>)
  end

  defp metadata_error(raw, line, key, reason) do
    {:error,
     %Error{
       kind: :invalid_metadata,
       line: line,
       field: :metadata,
       key: key,
       value: raw,
       reason: reason
     }}
  end

  defp trim_line_ending(line) do
    line
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
  end
end
