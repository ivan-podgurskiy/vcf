defmodule VCF.AcceptanceTest do
  use ExUnit.Case, async: true

  test "parses a representative record for every supported version" do
    for version <- VCF.supported_versions() do
      input = """
      ##fileformat=VCFv#{version}
      ##vendor_note=kept
      ##INFO=<ID=FLAG,Number=0,Type=Flag,Description="Present">
      #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
      chr1\t1\t.\tA\tC\t.\tPASS\tFLAG
      """

      assert {:ok, %VCF.Document{records: [record]}} = VCF.parse(input)
      assert VCF.Field.get(record.info, "FLAG") == true
    end
  end

  test "parses typed multi-sample FORMAT data and partial phasing in 4.4" do
    input = """
    ##fileformat=VCFv4.4
    ##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
    ##FORMAT=<ID=DP,Number=1,Type=Integer,Description="Depth">
    #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\tS2
    chr1\t2\t.\tA\tC,G\t.\tPASS\t.\tGT:DP\t|0|1/2:7\t./.:.
    """

    assert {:ok, %VCF.Document{records: [record]}} = VCF.parse(input)
    assert [%VCF.Sample{name: "S1"}, %VCF.Sample{name: "S2"}] = record.samples
    assert %VCF.Genotype{alleles: [0, 1, 2]} = VCF.Field.get(hd(record.samples).values, "GT")
  end

  test "permissive mode preserves recoverable invalid typed values as warnings" do
    input = """
    ##fileformat=VCFv4.5
    ##INFO=<ID=DP,Number=1,Type=Integer,Description="Depth">
    #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
    chr1\t1\t.\tA\tC\t.\tPASS\tDP=nope
    """

    assert {:error, %VCF.Error{reason: :expected_integer}} = VCF.parse(input)

    assert {:ok, %VCF.Document{records: [record], warnings: [_warning]}} =
             VCF.parse(input, mode: :permissive)

    assert VCF.Field.get(record.info, "DP") == "nope"
  end

  test "reads gzip paths and rejects unsupported binary formats explicitly" do
    content = "##fileformat=VCFv4.5\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"

    path =
      Path.join(System.tmp_dir!(), "vcf-acceptance-#{System.unique_integer([:positive])}.vcf.gz")

    File.write!(path, :zlib.gzip(content))
    on_exit(fn -> File.rm(path) end)

    assert {:ok, %VCF.Document{records: []}} = VCF.read(path)
    assert {:error, %VCF.Error{kind: :missing_fileformat}} = VCF.parse(<<"BCF", 2, 2, 0>>)
  end
end
