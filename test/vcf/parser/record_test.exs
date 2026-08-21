defmodule VCF.Parser.RecordTest do
  use ExUnit.Case, async: true

  alias VCF.Error
  alias VCF.Field
  alias VCF.Genotype
  alias VCF.Parser.Header, as: HeaderParser
  alias VCF.Parser.Record, as: RecordParser
  alias VCF.Record
  alias VCF.Sample
  alias VCF.Warning

  test "parses typed INFO, FORMAT, and ordered multi-sample values" do
    line =
      "chr1\t846808\trs4475691;id2\tC\tT,G\t.\tPASS\tDP=14;AF=0.25,0.75;DB\tGT:GQ:AD\t0/1:48:10,4,0\t.|2:.:3,.,7\n"

    assert {:ok,
            %{
              __struct__: Record,
              chrom: "chr1",
              pos: 846_808,
              ids: ["rs4475691", "id2"],
              ref: "C",
              alt: ["T", "G"],
              qual: nil,
              filter: :pass,
              format: ["GT", "GQ", "AD"],
              warnings: []
            } = record} = RecordParser.parse(line, 10, sample_header(), mode: :strict)

    assert Field.get(record.info, "DP") == 14
    assert Field.get(record.info, "AF") == [0.25, 0.75]
    assert Field.get(record.info, "DB") == true

    assert [
             %{__struct__: Sample, name: "S1"} = first,
             %{__struct__: Sample, name: "S2"} = second
           ] = record.samples

    assert %Genotype{alleles: [0, 1], phasing: [nil, :unphased]} =
             Field.get(first.values, "GT")

    assert Field.get(first.values, "GQ") == 48
    assert Field.get(first.values, "AD") == [10, 4, 0]

    assert %Genotype{alleles: [nil, 2], phasing: [nil, :phased]} =
             Field.get(second.values, "GT")

    assert Field.get(second.values, "GQ") == nil
    assert Field.get(second.values, "AD") == [3, nil, 7]
  end

  test "distinguishes PASS, missing filters, and applied filters" do
    header = sites_header()
    prefix = "1\t10\t.\tA\tC\t.\t"

    assert {:ok, %{filter: :pass}} = RecordParser.parse(prefix <> "PASS\t.\n", 3, header)
    assert {:ok, %{filter: nil}} = RecordParser.parse(prefix <> ".\t.\n", 3, header)

    assert {:ok, %{filter: ["q10", "s50"]}} =
             RecordParser.parse(prefix <> "q10;s50\t.\n", 3, header)
  end

  test "parses sites-only missing states without samples" do
    assert {:ok,
            %{
              ids: [],
              alt: [],
              qual: 47.0,
              info: [],
              format: [],
              samples: []
            }} = RecordParser.parse("20\t1230237\t.\tT\t.\t47\tPASS\t.\n", 3, sites_header())
  end

  test "returns contextual strict errors and retains permissive invalid values" do
    line = "1\t10\t.\tA\tC\t.\tPASS\tDP=abc\tGT:GQ:AD\t0/1:4:3,1\t0/0:5:4,0\n"

    assert {:error,
            %{
              __struct__: Error,
              line: 20,
              field: :info,
              key: "DP",
              value: "abc",
              reason: :expected_integer
            }} = RecordParser.parse(line, 20, sample_header(), mode: :strict)

    assert {:ok, %{info: info, warnings: [warning]}} =
             RecordParser.parse(line, 20, sample_header(), mode: :permissive)

    assert Field.get(info, "DP") == "abc"

    assert %{
             __struct__: Warning,
             line: 20,
             field: :info,
             key: "DP",
             value: "abc",
             reason: :expected_integer
           } = warning
  end

  test "rejects invalid record and sample field counts" do
    assert {:error, %{__struct__: Error, reason: :invalid_field_count}} =
             RecordParser.parse("1\t10\t.\tA\tC\t.\tPASS\n", 3, sites_header())

    assert {:error, %{__struct__: Error, reason: :sample_count_mismatch}} =
             RecordParser.parse(
               "1\t10\t.\tA\tC\t.\tPASS\t.\tGT:GQ\t0/1:4\n",
               3,
               sample_header()
             )

    assert {:error, %{__struct__: Error, reason: :too_many_format_values}} =
             RecordParser.parse(
               "1\t10\t.\tA\tC\t.\tPASS\t.\tGT\t0/1:4\t0/0\n",
               3,
               sample_header()
             )
  end

  test "retains values when an incomplete header definition cannot provide a type" do
    header =
      parse_header!([
        {1, "##fileformat=VCFv4.5\n"},
        {2, ~s(##INFO=<ID=X,Number=1,Description="Incomplete">\n)},
        {3, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"}
      ])

    assert {:ok, %{info: info}} =
             RecordParser.parse("1\t10\t.\tA\tC\t.\tPASS\tX=kept\n", 4, header)

    assert Field.get(info, "X") == "kept"
  end

  test "reports invalid positions, alternates, quality, and INFO syntax" do
    header = sites_header()

    for {line, reason} <- [
          {"1\tbad\t.\tA\tC\t.\tPASS\t.\n", :expected_integer},
          {"1\t1\t.\tA\t<>\t.\tPASS\t.\n", :invalid_allele},
          {"1\t1\t.\tA\tC\tbad\tPASS\t.\n", :expected_float},
          {"1\t1\t.\tA\tC\t.\tPASS\t;\n", :invalid_info}
        ] do
      assert {:error, %Error{reason: ^reason}} = RecordParser.parse(line, 9, header)
    end
  end

  test "handles missing samples, invalid genotypes, undeclared missing values, and percent escapes" do
    header = sample_header()

    assert {:ok, %{samples: [%Sample{values: first_values} | _rest]}} =
             RecordParser.parse(
               "1\t1\t.\tA\tC\t.\tPASS\t.\tGT:GQ:AD\t.\t0/0:5:4,0\n",
               10,
               header
             )

    assert %Genotype{alleles: [nil]} = Field.get(first_values, "GT")

    assert {:error, %Error{field: :format, key: "GT", reason: :invalid_syntax}} =
             RecordParser.parse(
               "1\t1\t.\tA\tC\t.\tPASS\t.\tGT\tbad\t0/0\n",
               11,
               header
             )

    unknown_header =
      parse_header!([
        {1, "##fileformat=VCFv4.5\n"},
        {2, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\n"}
      ])

    assert {:ok, %{info: info, samples: [%Sample{values: values}]}} =
             RecordParser.parse(
               "1\t1\t.\tA\tC\t.\tPASS\tX=.;TEXT=%2C%2c%ZZ\tU\t.\n",
               12,
               unknown_header
             )

    assert Field.get(info, "X") == nil
    assert Field.get(info, "TEXT") == ",,%ZZ"
    assert Field.get(values, "U") == nil
  end

  test "rejects an INFO flag without a value when its declaration is not Flag" do
    assert {:error, %Error{field: :info, key: "DP", reason: :expected_integer}} =
             RecordParser.parse(
               "1\t1\t.\tA\tC\t.\tPASS\tDP\tGT\t0/0\t0/0\n",
               13,
               sample_header()
             )
  end

  defp sites_header do
    parse_header!([
      {1, "##fileformat=VCFv4.5\n"},
      {2, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"}
    ])
  end

  defp sample_header do
    parse_header!([
      {1, "##fileformat=VCFv4.5\n"},
      {2, ~s(##INFO=<ID=DP,Number=1,Type=Integer,Description="Depth">\n)},
      {3, ~s(##INFO=<ID=AF,Number=A,Type=Float,Description="Allele frequency">\n)},
      {4, ~s(##INFO=<ID=DB,Number=0,Type=Flag,Description="dbSNP">\n)},
      {5, ~s(##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">\n)},
      {6, ~s(##FORMAT=<ID=GQ,Number=1,Type=Integer,Description="Quality">\n)},
      {7, ~s(##FORMAT=<ID=AD,Number=R,Type=Integer,Description="Depths">\n)},
      {8, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\tS2\n"}
    ])
  end

  defp parse_header!(lines) do
    {:ok, header, []} = HeaderParser.parse(lines)
    header
  end
end
