defmodule VCF.Source do
  @moduledoc "A VCF input source with explicit ownership and repeatability semantics."

  alias VCF.Compression
  alias VCF.Error

  @type kind :: :path | :device | :enumerable
  @type t :: %__MODULE__{
          kind: kind(),
          value: term(),
          options: keyword(),
          reusable?: boolean(),
          claim: reference()
        }

  @enforce_keys [:kind, :value, :options, :reusable?, :claim]
  defstruct [:kind, :value, :options, :reusable?, :claim]

  @doc "Opens a path, caller-owned I/O device, or generic binary enumerable."
  @spec open(term(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def open(source, options \\ [])

  def open(path, options) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{type: :regular}} -> {:ok, new(:path, path, options, true)}
      {:ok, _other} -> source_error(path, :not_a_regular_file)
      {:error, reason} -> source_error(path, reason)
    end
  end

  def open(device, options) when is_pid(device) or is_atom(device) do
    {:ok, new(:device, device, options, false)}
  end

  def open(enumerable, options) do
    if Enumerable.impl_for(enumerable) do
      {:ok, new(:enumerable, enumerable, options, false)}
    else
      source_error(enumerable, :unsupported_source)
    end
  end

  @doc "Returns tagged physical lines, claiming one-shot sources on first use."
  @spec lines(t()) :: Enumerable.t()
  def lines(%__MODULE__{reusable?: false, claim: claim} = source) do
    case :atomics.compare_exchange(claim, 1, 0, 1) do
      :ok -> source |> chunks() |> Compression.lines(source.options)
      _already_claimed -> [{:error, %Error{kind: :source_error, reason: :already_consumed}}]
    end
  end

  def lines(%__MODULE__{} = source) do
    source |> chunks() |> Compression.lines(source.options)
  end

  defp chunks(%__MODULE__{kind: :path, value: path, options: options}) do
    chunk_bytes = Keyword.get(options, :chunk_bytes, 65_536)

    Stream.resource(
      fn -> File.open!(path, [:read, :raw, :binary]) end,
      &read_chunk(&1, chunk_bytes, path),
      &File.close/1
    )
  end

  defp chunks(%__MODULE__{kind: :device, value: device, options: options}) do
    IO.binstream(device, Keyword.get(options, :chunk_bytes, 65_536))
  end

  defp chunks(%__MODULE__{kind: :enumerable, value: enumerable}), do: enumerable

  defp read_chunk(device, chunk_bytes, path) do
    case :file.read(device, chunk_bytes) do
      {:ok, data} -> {[data], device}
      :eof -> {:halt, device}
      {:error, reason} -> raise File.Error, reason: reason, action: "stream data from", path: path
    end
  end

  defp new(kind, value, options, reusable?) do
    %__MODULE__{
      kind: kind,
      value: value,
      options: options,
      reusable?: reusable?,
      claim: :atomics.new(1, [])
    }
  end

  defp source_error(value, reason) do
    {:error, %Error{kind: :source_error, value: value, reason: reason}}
  end
end
