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
  alias VCF.Writer

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

  @doc "Encodes a document, stream, or header plus records to canonical VCF text."
  @spec encode(Header.t(), Enumerable.t()) ::
          {:ok, binary()} | {:error, Error.t() | [Error.t()]}
  @spec encode(Document.t() | VCFStream.t(), keyword()) ::
          {:ok, binary()} | {:error, Error.t() | [Error.t()]}
  def encode(data, options \\ [])

  def encode(%Header{} = header, records), do: Writer.encode(header, records, [])
  def encode(data, options), do: Writer.encode(data, options)

  @spec encode(Header.t(), Enumerable.t(), keyword()) ::
          {:ok, binary()} | {:error, Error.t() | [Error.t()]}
  def encode(%Header{} = header, records, options),
    do: Writer.encode(header, records, options)

  @doc "Encodes canonical VCF text or raises `VCF.ParseError`."
  @spec encode!(Header.t(), Enumerable.t()) :: binary()
  @spec encode!(Document.t() | VCFStream.t(), keyword()) :: binary()
  def encode!(data, options \\ [])

  def encode!(%Header{} = header, records),
    do: encode_result!(Writer.encode(header, records, []))

  def encode!(data, options), do: encode_result!(encode(data, options))

  @spec encode!(Header.t(), Enumerable.t(), keyword()) :: binary()
  def encode!(%Header{} = header, records, options),
    do: encode_result!(Writer.encode(header, records, options))

  defp encode_result!(result) do
    case result do
      {:ok, encoded} -> encoded
      {:error, [error | _rest]} -> raise ParseError, error
      {:error, error} -> raise ParseError, error
    end
  end

  @doc "Writes a document or stream to a path or I/O device."
  @spec write(Document.t() | VCFStream.t(), term(), keyword()) ::
          :ok | {:error, Error.t() | [Error.t()]}
  @spec write(term(), Document.t() | VCFStream.t(), keyword()) ::
          :ok | {:error, Error.t() | [Error.t()]}
  def write(data, destination, options \\ [])

  def write(%Document{} = data, destination, options),
    do: Writer.write(destination, data, options)

  def write(%VCFStream{} = data, destination, options),
    do: Writer.write(destination, data, options)

  def write(destination, %Document{} = data, options),
    do: Writer.write(destination, data, options)

  def write(destination, %VCFStream{} = data, options),
    do: Writer.write(destination, data, options)

  @spec write(term(), Header.t(), Enumerable.t()) ::
          :ok | {:error, Error.t() | [Error.t()]}
  def write(destination, %Header{} = header, records),
    do: Writer.write(destination, header, records, [])

  @spec write(term(), Header.t(), Enumerable.t(), keyword()) ::
          :ok | {:error, Error.t() | [Error.t()]}
  def write(destination, %Header{} = header, records, options),
    do: Writer.write(destination, header, records, options)

  @doc "Writes a document or stream or raises `VCF.ParseError`."
  @spec write!(Document.t() | VCFStream.t(), term(), keyword()) :: :ok
  @spec write!(term(), Document.t() | VCFStream.t(), keyword()) :: :ok
  def write!(data, destination, options \\ [])

  def write!(%Document{} = data, destination, options),
    do: write_result!(Writer.write(destination, data, options))

  def write!(%VCFStream{} = data, destination, options),
    do: write_result!(Writer.write(destination, data, options))

  def write!(destination, %Document{} = data, options),
    do: write_result!(Writer.write(destination, data, options))

  def write!(destination, %VCFStream{} = data, options),
    do: write_result!(Writer.write(destination, data, options))

  @spec write!(term(), Header.t(), Enumerable.t()) :: :ok
  def write!(destination, %Header{} = header, records),
    do: write_result!(Writer.write(destination, header, records, []))

  @spec write!(term(), Header.t(), Enumerable.t(), keyword()) :: :ok
  def write!(destination, %Header{} = header, records, options),
    do: write_result!(Writer.write(destination, header, records, options))

  defp write_result!(:ok), do: :ok
  defp write_result!({:error, [error | _rest]}), do: raise(ParseError, error)
  defp write_result!({:error, error}), do: raise(ParseError, error)

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
