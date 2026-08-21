defmodule VCF.GenotypePropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias VCF.Genotype

  property "canonical genotype text round-trips arbitrary ploidy and per-allele phasing" do
    check all(
            alleles <-
              list_of(one_of([integer(0..20), constant(nil)]), min_length: 1, max_length: 8),
            phasing <- phasing_for(length(alleles))
          ) do
      genotype = struct(Genotype, alleles: alleles, phasing: phasing)

      assert {:ok, encoded} = Genotype.encode(genotype)
      assert Genotype.parse(encoded) == {:ok, genotype}
    end
  end

  defp phasing_for(1) do
    map(one_of([constant(nil), constant(:phased), constant(:unphased)]), &[&1])
  end

  defp phasing_for(length) do
    bind(one_of([constant(nil), constant(:phased), constant(:unphased)]), fn first ->
      map(list_of(member_of([:phased, :unphased]), length: length - 1), &[first | &1])
    end)
  end
end
