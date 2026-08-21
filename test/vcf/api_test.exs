defmodule VCF.APITest do
  use ExUnit.Case, async: true

  alias VCF.Document

  @valid """
  ##fileformat=VCFv4.5
  ##INFO=<ID=DP,Number=1,Type=Integer,Description="Depth">
  #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
  chr1\t10\trs1\tA\tC\t42\tPASS\tDP=9
  """

  @unsupported """
  ##fileformat=VCFv3.3
  #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
  """

  test "parse treats a binary as content and returns a typed document" do
    assert {:ok, %Document{header: header, records: [record]}} = VCF.parse(@valid)
    assert header.version == %VCF.Version{major: 4, minor: 5}
    assert record.pos == 10
    assert VCF.Field.get(record.info, "DP") == 9
  end

  test "non-bang APIs return errors and bang APIs raise ParseError" do
    assert {:error, %VCF.Error{kind: :unsupported_version}} = VCF.parse(@unsupported)
    assert_raise VCF.ParseError, fn -> VCF.parse!(@unsupported) end

    assert {:error, %VCF.Error{kind: :source_error, reason: :enoent}} =
             VCF.read("/definitely/missing/example.vcf")

    assert_raise VCF.ParseError, fn -> VCF.read!("/definitely/missing/example.vcf") end
  end

  test "read and stream operate on paths while filter stays lazy" do
    path = Path.join(System.tmp_dir!(), "vcf-api-#{System.unique_integer([:positive])}.vcf")
    File.write!(path, @valid <> "chr2\t11\t.\tG\tT\t.\tPASS\tDP=2\n")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, %Document{records: [%VCF.Record{pos: 10}, %VCF.Record{pos: 11}]}} =
             VCF.read(path)

    assert {:ok, stream} = VCF.stream(path)
    filtered = VCF.filter(stream, &(&1.chrom == "chr2"))
    assert [{:ok, %VCF.Record{pos: 11}}] = Enum.to_list(filtered)

    assert [%VCF.Record{pos: 10}, %VCF.Record{pos: 11}] = path |> VCF.stream!() |> Enum.to_list()
  end

  test "validate accumulates programmatically constructed document errors" do
    {:ok, %Document{} = document} = VCF.parse(@valid)
    invalid = %{List.first(document.records) | pos: 0, ref: ""}

    assert {:error,
            [
              %VCF.Error{field: :pos, reason: :must_be_positive},
              %VCF.Error{field: :ref, reason: :empty_value}
            ]} = VCF.validate(%{document | records: [invalid]})

    assert :ok = VCF.validate(document)
  end
end
