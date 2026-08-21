defmodule VCF.WriterTest do
  use ExUnit.Case, async: true

  alias VCF.Document
  alias VCF.Field
  alias VCF.FieldDefinition
  alias VCF.Genotype
  alias VCF.Header
  alias VCF.Metadata
  alias VCF.Record
  alias VCF.Sample
  alias VCF.Version

  test "canonically encodes programmatic structs with stable ordering" do
    document = document()

    assert {:ok, encoded} = VCF.encode(document)

    assert encoded == """
           ##fileformat=VCFv4.5
           ##source=unit-test
           ##INFO=<ID=AC,Number=A,Type=Integer,Description="Allele count">
           ##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
           ##FORMAT=<ID=DP,Number=1,Type=Integer,Description="Depth">
           #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\tS2
           chr1\t10\trs1\tA\tC,G\t12.5\tPASS\tAC=2,1\tGT:DP\t0/1:7\t./.:.
           """
  end

  test "writes plain and gzip paths plus caller-owned devices" do
    document = document()
    stem = Path.join(System.tmp_dir!(), "vcf-writer-#{System.unique_integer([:positive])}")
    plain = stem <> ".vcf"
    gzip = stem <> ".vcf.gz"

    on_exit(fn ->
      File.rm(plain)
      File.rm(gzip)
    end)

    assert :ok = VCF.write(plain, document)
    assert {:ok, plain_content} = File.read(plain)
    assert {:ok, ^plain_content} = VCF.encode(document)

    assert :ok = VCF.write(gzip, document)
    assert {:ok, compressed} = File.read(gzip)
    assert :zlib.gunzip(compressed) == plain_content

    {:ok, device} = StringIO.open("")
    assert :ok = VCF.write(device, document)
    assert :ok = IO.write(device, "still-open")
  end

  test "supports stream-first pipe form without discarding header context" do
    {:ok, encoded} = VCF.encode(document())
    source = encoded |> String.split("\n", trim: true) |> Enum.map(&(&1 <> "\n"))
    {:ok, device} = StringIO.open("")

    source
    |> VCF.stream!()
    |> VCF.filter(&(&1.chrom == "chr1"))
    |> VCF.write!(device)

    {_input, output} = StringIO.contents(device)
    assert output == encoded
  end

  test "refuses invalid programmatic data by default" do
    document = document()
    invalid = %{hd(document.records) | pos: 0}

    assert {:error, [%VCF.Error{field: :pos, reason: :must_be_positive}]} =
             VCF.encode(%{document | records: [invalid]})
  end

  test "writes incrementally instead of collecting the record enumerable" do
    document = document()
    record = hd(document.records)
    parent = self()
    {:ok, device} = StringIO.open("")

    records =
      [record, record]
      |> Elixir.Stream.with_index()
      |> Elixir.Stream.map(fn
        {item, 0} ->
          item

        {item, 1} ->
          {_input, output} = StringIO.contents(device)
          send(parent, {:destination_has_output, output != ""})
          item
      end)

    assert :ok = VCF.write(device, document.header, records)
    assert_received {:destination_has_output, true}
  end

  test "returns an encoding error instead of crashing when validation is disabled" do
    document = document()
    record = hd(document.records)
    invalid = %{record | info: [%Field{key: "AC", value: %{bad: true}}]}

    assert {:error, %VCF.Error{kind: :encoding_error, reason: :unsupported_value}} =
             VCF.encode(%{document | records: [invalid]}, validate: false)
  end

  defp document do
    info = %FieldDefinition{id: "AC", number: :a, type: :integer, description: "Allele count"}
    gt = %FieldDefinition{id: "GT", number: 1, type: :string, description: "Genotype"}
    dp = %FieldDefinition{id: "DP", number: 1, type: :integer, description: "Depth"}

    header = %Header{
      version: %Version{major: 4, minor: 5},
      columns: [:chrom, :pos, :id, :ref, :alt, :qual, :filter, :info, :format],
      samples: ["S1", "S2"],
      metadata: [
        %Metadata{key: "source", value: "unit-test"},
        %Metadata{key: "INFO", value: info},
        %Metadata{key: "FORMAT", value: gt},
        %Metadata{key: "FORMAT", value: dp}
      ]
    }

    record = %Record{
      chrom: "chr1",
      pos: 10,
      ids: ["rs1"],
      ref: "A",
      alt: ["C", "G"],
      qual: 12.5,
      filter: :pass,
      info: [%Field{key: "AC", value: [2, 1]}],
      format: ["GT", "DP"],
      samples: [
        %Sample{
          name: "S1",
          values: [
            %Field{key: "GT", value: %Genotype{alleles: [0, 1], phasing: [nil, :unphased]}},
            %Field{key: "DP", value: 7}
          ]
        },
        %Sample{
          name: "S2",
          values: [
            %Field{key: "GT", value: %Genotype{alleles: [nil, nil], phasing: [nil, :unphased]}},
            %Field{key: "DP", value: nil}
          ]
        }
      ]
    }

    %Document{header: header, records: [record]}
  end
end
