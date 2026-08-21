defmodule VCF.Parser.ValueTest do
  use ExUnit.Case, async: true

  alias VCF.Error
  alias VCF.Parser.Value

  test "parses typed scalar values and VCF missing values" do
    assert {:ok, 12} = Value.parse("12", :integer)
    assert {:ok, -1.25e-3} = Value.parse("-1.25e-3", :float)
    assert {:ok, :nan} = Value.parse("NaN", :float)
    assert {:ok, :positive_infinity} = Value.parse("Inf", :float)
    assert {:ok, :negative_infinity} = Value.parse("-Inf", :float)
    assert {:ok, "β"} = Value.parse("β", :character)
    assert {:ok, "text with spaces"} = Value.parse("text with spaces", :string)
    assert {:ok, nil} = Value.parse(".", :integer)
  end

  test "parses typed lists while preserving missing members" do
    assert {:ok, [1, nil, 3]} = Value.parse_list("1,.,3", :integer)
    assert {:ok, [0.1, 0.9]} = Value.parse_list("0.1,0.9", :float)
  end

  test "rejects values whose complete text does not match the declared type" do
    assert {:error, %{__struct__: Error, reason: :expected_integer}} =
             Value.parse("12x", :integer)

    assert {:error, %{__struct__: Error, reason: :expected_float}} =
             Value.parse("1.2x", :float)

    assert {:error, %{__struct__: Error, reason: :expected_character}} =
             Value.parse("AB", :character)

    assert {:error, %{__struct__: Error, reason: :flag_has_value}} =
             Value.parse("yes", :flag)
  end
end
