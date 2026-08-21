defmodule VCF.WriterPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  property "integer INFO values survive canonical encode and parse" do
    check all(value <- integer(-2_147_483_648..2_147_483_647)) do
      source = """
      ##fileformat=VCFv4.5
      ##INFO=<ID=V,Number=1,Type=Integer,Description="Value">
      #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
      chr1\t1\t.\tA\tC\t.\tPASS\tV=#{value}
      """

      document = VCF.parse!(source)
      assert document |> VCF.encode!() |> VCF.parse!() |> hd_record_value() == value
    end
  end

  defp hd_record_value(document) do
    document.records |> hd() |> Map.fetch!(:info) |> VCF.Field.get("V")
  end
end
