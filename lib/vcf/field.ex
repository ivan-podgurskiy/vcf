defmodule VCF.Field do
  @moduledoc "An ordered INFO or sample FORMAT field."

  @type t :: %__MODULE__{key: String.t(), value: term(), raw: String.t() | nil}

  @enforce_keys [:key]
  defstruct [:key, :value, :raw]

  @doc "Returns the first value for `key`, or `default` when it is absent."
  @spec get([t()], String.t(), term()) :: term()
  def get(fields, key, default \\ nil) do
    case fetch(fields, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @doc "Fetches the first value for `key`."
  @spec fetch([t()], String.t()) :: {:ok, term()} | :error
  def fetch(fields, key) do
    case Enum.find(fields, &(&1.key == key)) do
      nil -> :error
      %__MODULE__{value: value} -> {:ok, value}
    end
  end

  @doc "Returns all values for `key` in source order."
  @spec get_all([t()], String.t()) :: [term()]
  def get_all(fields, key) do
    for %__MODULE__{key: ^key, value: value} <- fields, do: value
  end
end
