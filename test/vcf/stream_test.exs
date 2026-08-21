defmodule VCF.StreamTest do
  use ExUnit.Case, async: true

  alias VCF.Stream, as: VCFStream

  @header [
    "##fileformat=VCFv4.5\n",
    "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
  ]

  test "parses the header eagerly and records lazily with bounded lookahead" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    records =
      Elixir.Stream.repeatedly(fn -> "chr1\t1\t.\tA\tC\t.\tPASS\t.\n" end)
      |> Elixir.Stream.take(100_000)

    source =
      Elixir.Stream.concat(@header, records)
      |> Elixir.Stream.map(fn line ->
        Agent.update(counter, &(&1 + 1))
        line
      end)

    stream = VCFStream.open!(source)
    assert stream.header.version == %VCF.Version{major: 4, minor: 5}
    assert Enum.map(Enum.take(stream, 2), & &1.pos) == [1, 1]
    assert Agent.get(counter, & &1) <= 5
  end

  test "non-bang streams yield tagged tuples and stop after an error" do
    source =
      @header ++ ["chr1\t1\t.\tA\tC\t.\tPASS\t.\n", "broken\n", "chr1\t2\t.\tA\tG\t.\tPASS\t.\n"]

    assert {:ok, stream} = VCFStream.open(source)

    assert [
             {:ok, %VCF.Record{pos: 1}},
             {:error, %VCF.Error{kind: :invalid_record, line: 4}}
           ] = Enum.to_list(stream)
  end

  test "bang streams raise VCF.ParseError at a malformed record" do
    stream = VCFStream.open!(@header ++ ["broken\n"])

    assert_raise VCF.ParseError, fn -> Enum.to_list(stream) end
  end

  test "file-backed streams can be enumerated repeatedly" do
    path = Path.join(System.tmp_dir!(), "vcf-stream-#{System.unique_integer([:positive])}.vcf")
    File.write!(path, IO.iodata_to_binary(@header ++ ["chr1\t7\t.\tA\tC\t.\tPASS\t.\n"]))
    on_exit(fn -> File.rm(path) end)

    stream = VCFStream.open!(path)
    assert Enum.map(stream, & &1.pos) == [7]
    assert Enum.map(stream, & &1.pos) == [7]
  end

  test "propagates compression errors from header and record input" do
    assert {:error, %VCF.Error{kind: :compression_error, reason: :invalid_chunk}} =
             VCFStream.open([:not_binary])

    assert {:ok, stream} = VCFStream.open(@header ++ [:not_binary])

    assert [{:error, %VCF.Error{kind: :compression_error, reason: :invalid_chunk}}] =
             Enum.to_list(stream)
  end

  test "reports incomplete headers and strict validation failures" do
    assert {:error, %VCF.Error{field: :header}} =
             VCFStream.open(["##fileformat=VCFv4.5\n"])

    invalid_header = [
      "##fileformat=VCFv4.1\n",
      ~s(##INFO=<ID=AD,Number=R,Type=Integer,Description="depths">\n),
      "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
    ]

    assert {:error, %VCF.Error{reason: :unsupported_number}} = VCFStream.open(invalid_header)

    assert {:ok, permissive} = VCFStream.open(invalid_header, mode: :permissive)
    assert [%VCF.Warning{reason: :unsupported_number}] = permissive.header.warnings
  end

  test "strict records stop on validation errors while permissive records retain warnings" do
    source = @header ++ ["chr1\t0\t.\tA\tC\t.\tPASS\t.\n"]

    assert {:ok, strict} = VCFStream.open(source)
    assert [{:error, %VCF.Error{reason: :must_be_positive}}] = Enum.to_list(strict)

    assert {:ok, permissive} = VCFStream.open(source, mode: :permissive)

    assert [{:ok, %VCF.Record{warnings: [%VCF.Warning{reason: :must_be_positive}]}}] =
             Enum.to_list(permissive)
  end

  test "one-shot record continuations report a second enumeration explicitly" do
    assert {:ok, stream} =
             VCFStream.open(@header ++ ["chr1\t1\t.\tA\tC\t.\tPASS\t.\n"])

    assert [{:ok, %VCF.Record{pos: 1}}] = Enum.to_list(stream)

    assert [{:error, %VCF.Error{kind: :source_error, reason: :already_consumed}}] =
             Enum.to_list(stream)
  end
end
