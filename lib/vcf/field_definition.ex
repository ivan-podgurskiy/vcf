defmodule VCF.FieldDefinition do
  @moduledoc "A typed INFO or FORMAT declaration from a VCF header."

  @type cardinality :: non_neg_integer() | :a | :r | :g | :p | :la | :lr | :lg | :m | :variable
  @type field_type :: :integer | :float | :flag | :character | :string

  @type t :: %__MODULE__{
          id: String.t(),
          number: cardinality() | nil,
          type: field_type() | nil,
          description: String.t() | nil,
          attributes: [{String.t(), String.t()}]
        }

  @enforce_keys [:id]
  defstruct [:id, :number, :type, :description, attributes: []]

  @doc "Parses a syntactically recognized VCF Number token."
  @spec parse_number(String.t()) :: {:ok, cardinality()} | :error
  def parse_number("A"), do: {:ok, :a}
  def parse_number("R"), do: {:ok, :r}
  def parse_number("G"), do: {:ok, :g}
  def parse_number("P"), do: {:ok, :p}
  def parse_number("LA"), do: {:ok, :la}
  def parse_number("LR"), do: {:ok, :lr}
  def parse_number("LG"), do: {:ok, :lg}
  def parse_number("M"), do: {:ok, :m}
  def parse_number("."), do: {:ok, :variable}

  def parse_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 -> {:ok, number}
      _other -> :error
    end
  end

  @doc "Parses a VCF field Type token without dynamically creating atoms."
  @spec parse_type(String.t()) :: {:ok, field_type()} | :error
  def parse_type("Integer"), do: {:ok, :integer}
  def parse_type("Float"), do: {:ok, :float}
  def parse_type("Flag"), do: {:ok, :flag}
  def parse_type("Character"), do: {:ok, :character}
  def parse_type("String"), do: {:ok, :string}
  def parse_type(_value), do: :error
end
