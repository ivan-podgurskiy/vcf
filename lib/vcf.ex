defmodule VCF do
  @moduledoc """
  Parse, validate, stream, transform, and write Variant Call Format files.
  """

  @supported_versions ~w(4.1 4.2 4.3 4.4 4.5)

  alias VCF.Document
  alias VCF.Error
  alias VCF.Header
  alias VCF.ParseError
  alias VCF.Stream, as: VCFStream
  alias VCF.Validator

  @doc "Returns the supported VCF specification versions."
  @spec supported_versions() :: [String.t()]
  def supported_versions, do: @supported_versions

  @doc "Parses an in-memory VCF binary into a document."
  @spec parse(binary(), keyword()) :: {:ok, Document.t()} | {:error, Error.t()}
  def parse(content, options \\ []) when is_binary(content) do
    with {:ok, stream} <- VCFStream.open([content], options) do
      collect(stream)
    end
  end

  @doc "Parses an in-memory VCF binary or raises `VCF.ParseError`."
  @spec parse!(binary(), keyword()) :: Document.t()
  def parse!(content, options \\ []) do
    case parse(content, options) do
      {:ok, document} -> document
      {:error, error} -> raise ParseError, error
    end
  end

  @doc "Reads a path, I/O device, or binary enumerable into a document."
  @spec read(term(), keyword()) :: {:ok, Document.t()} | {:error, Error.t()}
  def read(source, options \\ []) do
    with {:ok, stream} <- VCFStream.open(source, options) do
      collect(stream)
    end
  end

  @doc "Reads a complete source or raises `VCF.ParseError`."
  @spec read!(term(), keyword()) :: Document.t()
  def read!(source, options \\ []) do
    case read(source, options) do
      {:ok, document} -> document
      {:error, error} -> raise ParseError, error
    end
  end

  @doc "Opens a non-bang lazy stream whose elements are tagged results."
  @spec stream(term(), keyword()) :: {:ok, VCFStream.t()} | {:error, Error.t()}
  def stream(source, options \\ []), do: VCFStream.open(source, options)

  @doc "Opens a lazy record stream that raises on the first error."
  @spec stream!(term(), keyword()) :: VCFStream.t()
  def stream!(source, options \\ []), do: VCFStream.open!(source, options)

  @doc "Lazily filters records while preserving stream header context."
  @spec filter(VCFStream.t(), (VCF.Record.t() -> as_boolean(term()))) :: VCFStream.t()
  def filter(%VCFStream{} = stream, predicate), do: VCFStream.filter(stream, predicate)

  @doc "Validates every record in a fully collected document."
  @spec validate(Document.t(), keyword()) :: :ok | {:error, [Error.t()]}
  def validate(%Document{header: %Header{} = header, records: records}, _options \\ []) do
    case Validator.validate(header, records) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp collect(%VCFStream{} = stream) do
    case Enum.reduce_while(stream, {:ok, []}, fn
           {:ok, record}, {:ok, records} -> {:cont, {:ok, [record | records]}}
           {:error, error}, {:ok, _records} -> {:halt, {:error, error}}
         end) do
      {:error, error} ->
        {:error, error}

      {:ok, records} ->
        records = Enum.reverse(records)
        warnings = stream.header.warnings ++ Enum.flat_map(records, & &1.warnings)
        {:ok, %Document{header: stream.header, records: records, warnings: warnings}}
    end
  end
end
