defmodule VCF.RobustnessPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  property "non-bang parse never crashes on arbitrary binaries" do
    check all(input <- binary(max_length: 512), max_runs: 500) do
      assert match?({:ok, %VCF.Document{}}, VCF.parse(input)) or
               match?({:error, %VCF.Error{}}, VCF.parse(input))
    end
  end

  property "mutated valid record lines return typed results rather than exceptions" do
    prefix = "##fileformat=VCFv4.5\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"

    check all(mutation <- binary(max_length: 128), max_runs: 300) do
      result = VCF.parse(prefix <> mutation <> "\n")
      assert match?({:ok, %VCF.Document{}}, result) or match?({:error, %VCF.Error{}}, result)
    end
  end
end
