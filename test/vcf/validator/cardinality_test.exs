defmodule VCF.Validator.CardinalityTest do
  use ExUnit.Case, async: true

  alias VCF.Validator.Cardinality

  test "validates fixed and allele-relative cardinalities" do
    assert :ok = Cardinality.validate(2, 2)
    assert :ok = Cardinality.validate(2, :a, alt_count: 2, ploidy: 2)
    assert :ok = Cardinality.validate(3, :r, alt_count: 2, ploidy: 2)
    assert :ok = Cardinality.validate(6, :g, alt_count: 2, ploidy: 2)
    assert :ok = Cardinality.validate(2, :p, alt_count: 2, ploidy: 2)
    assert :ok = Cardinality.validate(2, :la, local_alt_count: 2, ploidy: 2)
    assert :ok = Cardinality.validate(3, :lr, local_alt_count: 2, ploidy: 2)
    assert :ok = Cardinality.validate(6, :lg, local_alt_count: 2, ploidy: 2)
    assert :ok = Cardinality.validate(4, :m, modification_count: 4)
    assert :ok = Cardinality.validate(100, :variable)
  end

  test "uses integer combinations with repetition for Number G and LG" do
    assert :ok = Cardinality.validate(20, :g, alt_count: 3, ploidy: 3)
    assert :ok = Cardinality.validate(10, :lg, local_alt_count: 2, ploidy: 3)

    assert {:error, :invalid_cardinality} =
             Cardinality.validate(5, :g, alt_count: 2, ploidy: 2)
  end

  test "rejects missing context and invalid counts" do
    assert {:error, :missing_cardinality_context} = Cardinality.validate(1, :g, [])
    assert {:error, :invalid_cardinality} = Cardinality.validate(-1, :variable)
  end
end
