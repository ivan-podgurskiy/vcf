defmodule VCF.ConformanceTest do
  use ExUnit.Case, async: true

  test "parses compact specification-derived fixtures for VCF 4.1 through 4.5" do
    for version <- VCF.supported_versions() do
      assert {:ok, %VCF.Document{header: header, records: [_record]}} =
               version |> VCF.Test.Fixture.path() |> VCF.read()

      assert to_string(header.version) == "VCFv#{version}"
    end
  end

  test "decodes percent-escaped reserved characters starting in VCF 4.3" do
    document = "4.3" |> VCF.Test.Fixture.path() |> VCF.read!()
    assert VCF.Field.get(hd(document.records).info, "NOTE") == "a;b=c%"
  end

  test "accepts CRLF physical lines and UTF-8 values" do
    source =
      "##fileformat=VCFv4.3\r\n" <>
        "##INFO=<ID=TXT,Number=1,Type=String,Description=\"Text\">\r\n" <>
        "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\r\n" <>
        "chr1\t1\t.\tA\tC\t.\tPASS\tTXT=βeta\r\n"

    assert {:ok, %VCF.Document{records: [record]}} = VCF.parse(source)
    assert VCF.Field.get(record.info, "TXT") == "βeta"
  end
end
