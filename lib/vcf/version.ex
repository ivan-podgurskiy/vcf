defmodule VCF.Version do
  @moduledoc "A supported Variant Call Format specification version."

  alias VCF.Error

  @type t :: %__MODULE__{major: 4, minor: 1..5}
  @enforce_keys [:major, :minor]
  defstruct [:major, :minor]

  @doc "Parses a VCF fileformat value."
  @spec parse(term()) :: {:ok, t()} | {:error, Error.t()}
  def parse("VCFv4.1"), do: {:ok, %__MODULE__{major: 4, minor: 1}}
  def parse("VCFv4.2"), do: {:ok, %__MODULE__{major: 4, minor: 2}}
  def parse("VCFv4.3"), do: {:ok, %__MODULE__{major: 4, minor: 3}}
  def parse("VCFv4.4"), do: {:ok, %__MODULE__{major: 4, minor: 4}}
  def parse("VCFv4.5"), do: {:ok, %__MODULE__{major: 4, minor: 5}}

  def parse("VCFv" <> _ = value) do
    {:error,
     %Error{kind: :unsupported_version, field: :fileformat, value: value, reason: :unsupported}}
  end

  def parse(value) do
    {:error, %Error{kind: :invalid_version, field: :fileformat, value: value, reason: :malformed}}
  end
end

defimpl String.Chars, for: VCF.Version do
  def to_string(%VCF.Version{major: major, minor: minor}), do: "VCFv#{major}.#{minor}"
end
