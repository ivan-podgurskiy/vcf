defmodule VCF.GenotypeTest do
  use ExUnit.Case, async: true

  alias VCF.Error
  alias VCF.Genotype

  test "parses ordinary phased, unphased, haploid, missing, and polyploid genotypes" do
    assert {:ok, %{__struct__: Genotype, alleles: [0, 1], phasing: [nil, :unphased]}} =
             Genotype.parse("0/1")

    assert {:ok, %{__struct__: Genotype, alleles: [0, 1], phasing: [nil, :phased]}} =
             Genotype.parse("0|1")

    assert {:ok,
            %{__struct__: Genotype, alleles: [nil, 1, 2], phasing: [nil, :unphased, :unphased]}} =
             Genotype.parse("./1/2")

    assert {:ok, %{__struct__: Genotype, alleles: [nil, nil], phasing: [nil, :phased]}} =
             Genotype.parse(".|.")

    assert {:ok, %{__struct__: Genotype, alleles: [1], phasing: [nil]}} =
             Genotype.parse("1")
  end

  test "preserves VCF 4.4 prefix notation and partial phasing" do
    assert {:ok,
            %{
              __struct__: Genotype,
              alleles: [0, 0, 1, 2],
              phasing: [:phased, :phased, :unphased, :unphased]
            }} = Genotype.parse("|0|0/1/2")

    assert {:ok,
            %{
              __struct__: Genotype,
              alleles: [0, 1, 2],
              phasing: [:unphased, :unphased, :unphased]
            }} =
             Genotype.parse("/0/1/2")
  end

  test "rejects malformed genotypes without raising" do
    for {value, reason} <- [
          {"", :empty_genotype},
          {"0//1", :invalid_syntax},
          {"0/", :invalid_syntax},
          {"0/a", :invalid_syntax},
          {"-1/0", :invalid_syntax}
        ] do
      assert {:error,
              %{__struct__: Error, kind: :invalid_genotype, reason: ^reason, value: ^value}} =
               Genotype.parse(value)
    end
  end

  test "encodes canonical genotype text" do
    genotype =
      struct(Genotype,
        alleles: [0, nil, 2],
        phasing: [:phased, :unphased, :phased]
      )

    assert {:ok, "|0/.|2"} = Genotype.encode(genotype)
  end

  test "rejects inconsistent programmatic genotypes" do
    genotype = struct(Genotype, alleles: [0, 1], phasing: [nil])

    assert {:error, %{__struct__: Error, reason: :phasing_length_mismatch}} =
             Genotype.encode(genotype)

    genotype = struct(Genotype, alleles: [0, 1], phasing: [nil, nil])

    assert {:error, %{__struct__: Error, reason: :missing_separator}} =
             Genotype.encode(genotype)
  end
end
