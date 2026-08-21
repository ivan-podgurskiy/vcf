defmodule VCF.Parser.HeaderTest do
  use ExUnit.Case, async: true

  alias VCF.Error
  alias VCF.FieldDefinition
  alias VCF.Header
  alias VCF.Parser.Header, as: HeaderParser
  alias VCF.Version
  alias VCF.Warning

  test "parses an ordered typed header and returns unconsumed record lines" do
    lines = [
      {1, "##fileformat=VCFv4.3\n"},
      {2, ~s(##INFO=<ID=DP,Number=1,Type=Integer,Description="Depth">\n)},
      {3, "##vendor=kept\n"},
      {4, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tNA12878\n"},
      {5, "1\t10\t.\tA\tC\t.\tPASS\tDP=7\tGT\t0/1\n"}
    ]

    assert {:ok,
            %{
              __struct__: Header,
              version: %{__struct__: Version, major: 4, minor: 3},
              columns: [:chrom, :pos, :id, :ref, :alt, :qual, :filter, :info, :format],
              samples: ["NA12878"],
              warnings: []
            } = header, [{5, _record}]} = HeaderParser.parse(lines, mode: :strict)

    assert Enum.map(header.metadata, & &1.key) == ["fileformat", "INFO", "vendor"]

    assert %FieldDefinition{id: "DP", number: 1, type: :integer} =
             Header.definition(header, :info, "DP")
  end

  test "supports sites-only VCF headers" do
    lines = [
      {1, "##fileformat=VCFv4.1\r\n"},
      {2, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\r\n"}
    ]

    assert {:ok, %{samples: [], columns: columns}, []} = HeaderParser.parse(lines)
    assert columns == [:chrom, :pos, :id, :ref, :alt, :qual, :filter, :info]
  end

  test "requires fileformat first and rejects unsupported versions" do
    assert {:error, %{__struct__: Error, kind: :missing_fileformat, line: 1}} =
             HeaderParser.parse([{1, "##source=test\n"}])

    assert {:error, %{__struct__: Error, kind: :unsupported_version, value: "VCFv3.3"}} =
             HeaderParser.parse([
               {1, "##fileformat=VCFv3.3\n"},
               {2, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"}
             ])
  end

  test "validates fixed columns and sample names" do
    assert {:error, %{__struct__: Error, reason: :invalid_columns}} =
             HeaderParser.parse([
               {1, "##fileformat=VCFv4.2\n"},
               {2, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tINFO\tFILTER\n"}
             ])

    duplicate_samples = [
      {1, "##fileformat=VCFv4.2\n"},
      {2, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\tS1\n"}
    ]

    assert {:error, %{__struct__: Error, reason: :duplicate_sample, value: "S1"}} =
             HeaderParser.parse(duplicate_samples, mode: :strict)

    assert {:ok, %{warnings: [warning]}, []} =
             HeaderParser.parse(duplicate_samples, mode: :permissive)

    assert %{__struct__: Warning, field: :samples, reason: :duplicate_sample, value: "S1"} =
             warning
  end

  test "detects duplicate structured IDs without discarding permissive metadata" do
    lines = [
      {1, "##fileformat=VCFv4.3\n"},
      {2, ~s(##INFO=<ID=DP,Number=1,Type=Integer,Description="One">\n)},
      {3, ~s(##INFO=<ID=DP,Number=1,Type=Integer,Description="Two">\n)},
      {4, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"}
    ]

    assert {:error, %{__struct__: Error, reason: :duplicate_definition, key: "DP"}} =
             HeaderParser.parse(lines, mode: :strict)

    assert {:ok, %{metadata: metadata, warnings: [warning]}, []} =
             HeaderParser.parse(lines, mode: :permissive)

    assert Enum.count(metadata, &(&1.key == "INFO")) == 2
    assert %{__struct__: Warning, reason: :duplicate_definition, key: "DP"} = warning
  end

  test "looks up INFO, FORMAT, FILTER, ALT, and contig declarations by ID" do
    lines = [
      {1, "##fileformat=VCFv4.5\n"},
      {2, ~s(##INFO=<ID=DP,Number=1,Type=Integer,Description="Depth">\n)},
      {3, ~s(##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">\n)},
      {4, ~s(##FILTER=<ID=q10,Description="Low quality">\n)},
      {5, ~s(##ALT=<ID=DEL,Description="Deletion">\n)},
      {6, "##contig=<ID=chr1,length=248956422>\n"},
      {7, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"}
    ]

    assert {:ok, header, []} = HeaderParser.parse(lines)
    assert %FieldDefinition{id: "DP"} = Header.definition(header, :info, "DP")
    assert %FieldDefinition{id: "GT"} = Header.definition(header, :format, "GT")
    assert %{key: "FILTER"} = Header.definition(header, :filter, "q10")
    assert %{key: "ALT"} = Header.definition(header, :alt, "DEL")
    assert %{key: "contig"} = Header.definition(header, :contig, "chr1")
    assert Header.definition(header, :info, "missing") == nil
  end

  test "reports incomplete headers, records before columns, empty samples, and raw duplicate IDs" do
    assert {:error, %Error{reason: :required}} =
             HeaderParser.parse([{1, "##fileformat=VCFv4.5\n"}])

    assert {:error, %Error{reason: :required_before_records}} =
             HeaderParser.parse([
               {1, "##fileformat=VCFv4.5\n"},
               {2, "chr1\t1\t.\tA\tC\t.\tPASS\t.\n"}
             ])

    assert {:error, %Error{reason: :empty_sample}} =
             HeaderParser.parse([
               {1, "##fileformat=VCFv4.5\n"},
               {2, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t\n"}
             ])

    assert {:ok, _header, []} =
             HeaderParser.parse([
               {1, "##fileformat=VCFv4.5\n"},
               {2, "##META=<Description=x>\n"},
               {3, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"}
             ])

    duplicate = [
      {1, "##fileformat=VCFv4.5\n"},
      {2, "##FILTER=<ID=q10,Description=one>\n"},
      {3, "##FILTER=<ID=q10,Description=two>\n"},
      {4, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"}
    ]

    assert {:error, %Error{reason: :duplicate_definition, key: "q10"}} =
             HeaderParser.parse(duplicate)
  end
end
