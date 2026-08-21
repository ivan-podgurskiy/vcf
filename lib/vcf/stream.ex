defmodule VCF.Stream do
  @moduledoc "A header-aware lazy record stream."

  alias VCF.Error
  alias VCF.Header
  alias VCF.Parser.Header, as: HeaderParser
  alias VCF.Parser.Record, as: RecordParser
  alias VCF.ParseError
  alias VCF.Source
  alias VCF.Validator
  alias VCF.Warning

  @type mode :: :strict | :permissive
  @type t :: %__MODULE__{
          header: Header.t(),
          records: Enumerable.t(),
          mode: mode(),
          bang?: boolean()
        }

  @enforce_keys [:header, :records, :mode, :bang?]
  defstruct [:header, :records, :mode, :bang?]

  @doc "Opens a source, parses its header eagerly, and returns tagged records lazily."
  @spec open(term(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def open(input, options \\ []) do
    mode = Keyword.get(options, :mode, :strict)
    bang? = Keyword.get(options, :bang, false)

    with true <- mode in [:strict, :permissive] || invalid_mode(mode),
         {:ok, source} <- Source.open(input, options),
         {:ok, header, continuation, header_line_count} <- read_header(source, mode),
         {:ok, header} <- validate_header(header, mode) do
      tagged_records = record_enumerable(source, continuation, header_line_count, header, mode)
      records = if bang?, do: raising_records(tagged_records), else: tagged_records
      {:ok, %__MODULE__{header: header, records: records, mode: mode, bang?: bang?}}
    end
  end

  @doc "Opens a stream or raises `VCF.ParseError` for a structural source/header error."
  @spec open!(term(), keyword()) :: t()
  def open!(input, options \\ []) do
    case open(input, Keyword.put(options, :bang, true)) do
      {:ok, stream} -> stream
      {:error, error} -> raise ParseError, error
    end
  end

  @doc "Returns a stream with the same header and lazily filtered successful records."
  @spec filter(t(), (VCF.Record.t() -> as_boolean(term()))) :: t()
  def filter(%__MODULE__{bang?: true} = stream, predicate) do
    %{stream | records: Elixir.Stream.filter(stream.records, predicate)}
  end

  def filter(%__MODULE__{} = stream, predicate) do
    records =
      Elixir.Stream.filter(stream.records, fn
        {:ok, record} -> predicate.(record)
        {:error, _error} -> true
      end)

    %{stream | records: records}
  end

  defp read_header(source, mode) do
    first = puller(Source.lines(source)).({:cont, nil})
    collect_header(first, [], 1, source, mode)
  end

  defp puller(enumerable) do
    fn command ->
      Enumerable.reduce(enumerable, command, fn item, _accumulator -> {:suspend, item} end)
    end
  end

  defp collect_header({:suspended, {:ok, line}, continuation}, lines, line_number, source, mode) do
    next_lines = [{line_number, line} | lines]

    if line |> trim_line_ending() |> String.starts_with?("#CHROM") do
      ordered = Enum.reverse(next_lines)

      with {:ok, header, []} <- HeaderParser.parse(ordered, mode: mode) do
        if source.reusable? do
          continuation.({:halt, nil})
        end

        {:ok, header, continuation, line_number}
      else
        {:ok, _header, _remaining} -> header_error(line_number, :unexpected_header_remainder)
        {:error, error} -> {:error, error}
      end
    else
      collect_header(continuation.({:cont, nil}), next_lines, line_number + 1, source, mode)
    end
  end

  defp collect_header(
         {:suspended, {:error, error}, continuation},
         _lines,
         _line_number,
         _source,
         _mode
       ) do
    continuation.({:halt, nil})
    {:error, error}
  end

  defp collect_header({:done, _accumulator}, lines, line_number, _source, mode) do
    finalize_incomplete_header(lines, line_number, mode)
  end

  defp collect_header({:halted, _accumulator}, lines, line_number, _source, mode) do
    finalize_incomplete_header(lines, line_number, mode)
  end

  defp finalize_incomplete_header(lines, line_number, mode) do
    case HeaderParser.parse(Enum.reverse(lines), mode: mode) do
      {:error, error} -> {:error, error}
      {:ok, _header, _remaining} -> header_error(line_number, :missing_column_header)
    end
  end

  defp validate_header(header, :strict) do
    case Validator.validate_header(header) do
      [] -> {:ok, header}
      [error | _rest] -> {:error, error}
    end
  end

  defp validate_header(header, :permissive) do
    warnings = Enum.map(Validator.validate_header(header), &warning_from_error/1)
    {:ok, %{header | warnings: header.warnings ++ warnings}}
  end

  defp record_enumerable(source, continuation, header_line_count, header, mode) do
    lines =
      if source.reusable? do
        source |> Source.lines() |> Elixir.Stream.drop(header_line_count)
      else
        continuation_enumerable(continuation)
      end

    lines
    |> Elixir.Stream.with_index(header_line_count + 1)
    |> Elixir.Stream.transform(false, fn
      _item, true ->
        {:halt, true}

      {{:error, error}, _line_number}, false ->
        {[{:error, error}], true}

      {{:ok, line}, line_number}, false ->
        parse_record(line, line_number, header, mode)
    end)
  end

  defp parse_record(line, line_number, header, mode) do
    case RecordParser.parse(line, line_number, header, mode: mode) do
      {:error, error} ->
        {[{:error, error}], true}

      {:ok, record} ->
        validation_errors = Validator.validate_record(record, header)
        validated_record(record, validation_errors, mode)
    end
  end

  defp validated_record(record, [], _mode), do: {[{:ok, record}], false}
  defp validated_record(_record, [error | _rest], :strict), do: {[{:error, error}], true}

  defp validated_record(record, errors, :permissive) do
    warned_fields = MapSet.new(record.warnings, &{&1.field, &1.key})

    warnings =
      errors
      |> Enum.reject(&MapSet.member?(warned_fields, {&1.field, &1.key}))
      |> Enum.map(&warning_from_error/1)

    {[{:ok, %{record | warnings: record.warnings ++ warnings}}], false}
  end

  defp continuation_enumerable(continuation) do
    claim = :atomics.new(1, [])

    Elixir.Stream.resource(
      fn ->
        case :atomics.compare_exchange(claim, 1, 0, 1) do
          :ok -> {:continuation, continuation}
          _claimed -> {:error, %Error{kind: :source_error, reason: :already_consumed}}
        end
      end,
      fn
        {:error, error} ->
          {[{:error, error}], :done}

        :done ->
          {:halt, :done}

        {:continuation, next} ->
          case next.({:cont, nil}) do
            {:suspended, item, following} -> {[item], {:continuation, following}}
            {:done, _accumulator} -> {:halt, :done}
            {:halted, _accumulator} -> {:halt, :done}
          end
      end,
      fn
        {:continuation, next} -> next.({:halt, nil})
        _done_or_error -> :ok
      end
    )
  end

  defp raising_records(records) do
    Elixir.Stream.map(records, fn
      {:ok, record} -> record
      {:error, error} -> raise ParseError, error
    end)
  end

  defp warning_from_error(error) do
    %Warning{
      line: error.line,
      field: error.field,
      key: error.key,
      value: error.value,
      reason: error.reason
    }
  end

  defp invalid_mode(mode) do
    {:error,
     %Error{
       kind: :invalid_option,
       key: "mode",
       value: mode,
       reason: :expected_strict_or_permissive
     }}
  end

  defp header_error(line, reason) do
    {:error, %Error{kind: :invalid_header, line: line, field: :header, reason: reason}}
  end

  defp trim_line_ending(line) do
    line |> String.trim_trailing("\n") |> String.trim_trailing("\r")
  end
end

defimpl Enumerable, for: VCF.Stream do
  def reduce(stream, accumulator, reducer),
    do: Enumerable.reduce(stream.records, accumulator, reducer)

  def member?(_stream, _value), do: {:error, __MODULE__}
  def count(_stream), do: {:error, __MODULE__}
  def slice(_stream), do: {:error, __MODULE__}
end
