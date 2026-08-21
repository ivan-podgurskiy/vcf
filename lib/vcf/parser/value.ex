defmodule VCF.Parser.Value do
  @moduledoc false

  alias VCF.Error

  @type value ::
          integer()
          | float()
          | :nan
          | :positive_infinity
          | :negative_infinity
          | String.t()
          | nil

  @spec parse(String.t(), VCF.FieldDefinition.field_type()) ::
          {:ok, value()} | {:error, Error.t()}
  def parse(".", _type), do: {:ok, nil}

  def parse(value, :integer) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _failure -> error(value, :expected_integer)
    end
  end

  def parse("NaN", :float), do: {:ok, :nan}
  def parse("Inf", :float), do: {:ok, :positive_infinity}
  def parse("+Inf", :float), do: {:ok, :positive_infinity}
  def parse("-Inf", :float), do: {:ok, :negative_infinity}

  def parse(value, :float) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _failure -> error(value, :expected_float)
    end
  end

  def parse(value, :character) do
    if String.length(value) == 1 do
      {:ok, value}
    else
      error(value, :expected_character)
    end
  end

  def parse(value, :string), do: {:ok, value}
  def parse(value, :flag), do: error(value, :flag_has_value)

  @spec parse_list(String.t(), VCF.FieldDefinition.field_type()) ::
          {:ok, [value()]} | {:error, Error.t()}
  def parse_list(value, type) do
    value
    |> String.split(",", trim: false)
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, values} ->
      case parse(item, type) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | values]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp error(value, reason) do
    {:error, %Error{kind: :invalid_value, value: value, reason: reason}}
  end
end
