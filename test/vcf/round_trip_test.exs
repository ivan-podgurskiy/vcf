defmodule VCF.RoundTripTest do
  use ExUnit.Case, async: true

  test "parse and encode preserve typed semantics and unknown metadata order" do
    source = """
    ##fileformat=VCFv4.5
    ##vendor_a=first
    ##vendor_b=<ID=X,Value="a,b">
    ##INFO=<ID=AF,Number=A,Type=Float,Description="Frequency">
    #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
    chr2\t20\t.\tG\tA,<NON_REF>\t.\t.\tAF=0.25,.
    """

    original = VCF.parse!(source)
    encoded = VCF.encode!(original)
    reparsed = VCF.parse!(encoded)

    assert reparsed.header.version == original.header.version

    assert Enum.map(reparsed.header.metadata, & &1.key) ==
             Enum.map(original.header.metadata, & &1.key)

    assert reparsed.records == Enum.map(original.records, &%{&1 | raw: hd(reparsed.records).raw})
  end

  test "writer percent-escapes reserved decoded string characters for VCF 4.3+" do
    source = """
    ##fileformat=VCFv4.5
    ##INFO=<ID=NOTE,Number=1,Type=String,Description="Note">
    #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
    chr1\t1\t.\tA\tC\t.\tPASS\tNOTE=a%3Bb%3Dc%25
    """

    document = VCF.parse!(source)
    encoded = VCF.encode!(document)

    assert encoded =~ "NOTE=a%3Bb%3Dc%25"
    assert VCF.parse!(encoded).records == document.records
  end
end
