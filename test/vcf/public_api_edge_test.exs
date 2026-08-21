defmodule VCF.PublicAPIEdgeTest do
  use ExUnit.Case, async: true

  alias VCF.Document
  alias VCF.Error
  alias VCF.Field
  alias VCF.FieldDefinition
  alias VCF.Genotype
  alias VCF.Header
  alias VCF.Metadata
  alias VCF.Record
  alias VCF.Sample
  alias VCF.Version
  alias VCF.Warning

  @valid """
  ##fileformat=VCFv4.5
  #CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO
  chr1\t10\t.\tA\tC\t.\tPASS\t.
  """

  test "exercises every public encode and write form" do
    document = VCF.parse!(@valid)
    header = document.header
    records = document.records

    assert {:ok, encoded} = VCF.encode(header, records)
    assert {:ok, ^encoded} = VCF.encode(header, records, validate: false)
    assert ^encoded = VCF.encode!(header, records)
    assert ^encoded = VCF.encode!(header, records, validate: false)
    assert {:ok, ^encoded} = VCF.Writer.encode(document)
    assert {:ok, ^encoded} = VCF.encode(VCF.stream!([@valid]))

    assert ExUnit.CaptureIO.capture_io(fn -> assert :ok = VCF.write(:stdio, document) end) ==
             encoded

    assert :ok = VCF.write(document, device())
    assert :ok = VCF.write(device(), document)
    assert :ok = VCF.write(device(), header, records)
    assert :ok = VCF.write(device(), header, records, validate: false)
    assert :ok = VCF.Writer.write(device(), document)

    assert :ok = VCF.write(VCF.stream!([@valid]), device())
    assert :ok = VCF.write(device(), VCF.stream!([@valid]))

    assert :ok = VCF.write!(document, device())
    assert :ok = VCF.write!(device(), document)
    assert :ok = VCF.write!(VCF.stream!([@valid]), device())
    assert :ok = VCF.write!(device(), VCF.stream!([@valid]))
    assert :ok = VCF.write!(device(), header, records)
    assert :ok = VCF.write!(device(), header, records, validate: false)
  end

  test "bang encode and write forms raise for list and scalar errors" do
    document = VCF.parse!(@valid)
    invalid_record = %{hd(document.records) | pos: 0}
    invalid_document = %{document | records: [invalid_record]}

    assert_raise VCF.ParseError, fn -> VCF.encode!(invalid_document) end
    assert_raise VCF.ParseError, fn -> VCF.write!(invalid_document, device()) end

    unsupported = %{hd(document.records) | info: [%Field{key: "X", value: %{}}]}
    unsupported_document = %{document | records: [unsupported]}

    assert_raise VCF.ParseError, fn -> VCF.encode!(unsupported_document, validate: false) end
    assert_raise VCF.ParseError, fn -> VCF.write!(:missing_device, document) end
  end

  test "streams expose protocol fallbacks and preserve lazy errors through filtering and encoding" do
    assert {:ok, stream} = VCF.stream([@valid])
    assert {:error, Enumerable.VCF.Stream} = Enumerable.member?(stream, :anything)
    assert {:error, Enumerable.VCF.Stream} = Enumerable.count(stream)
    assert {:error, Enumerable.VCF.Stream} = Enumerable.slice(stream)

    invalid = @valid <> "broken\trecord\n"
    assert {:ok, invalid_stream} = VCF.stream([invalid])
    filtered = VCF.filter(invalid_stream, fn _record -> false end)

    assert [{:error, %Error{kind: :invalid_record}}] = Enum.to_list(filtered)
    assert {:ok, encoding_stream} = VCF.stream([invalid])
    assert {:error, %Error{kind: :invalid_record}} = VCF.encode(encoding_stream)
  end

  test "reports invalid modes, headers, versions, sources, and devices structurally" do
    assert {:error, %Error{kind: :invalid_option}} = VCF.stream([@valid], mode: :lenient)
    assert_raise VCF.ParseError, fn -> VCF.stream!(["not a header\n"]) end

    header = %Header{version: %Version{major: 3, minor: 3}, metadata: [], columns: []}
    record = %Record{chrom: "chr1", pos: 1, ref: "A"}
    assert [%Error{kind: :unsupported_version}] = VCF.Validator.validate_header(header)
    assert [%Error{kind: :unsupported_version}] = VCF.Validator.validate_record(record, header)

    assert {:error, %Error{reason: :not_a_regular_file}} = VCF.Source.open(System.tmp_dir!())
    assert :error = VCF.Field.fetch([], "missing")
    assert :fallback = VCF.Field.get([], "missing", :fallback)

    path = Path.join(System.tmp_dir!(), "vcf-invalid-chunk-#{System.unique_integer([:positive])}")
    File.write!(path, @valid)
    on_exit(fn -> File.rm(path) end)
    assert {:ok, source} = VCF.Source.open(path, chunk_bytes: -1)
    assert_raise File.Error, fn -> Enum.to_list(VCF.Source.lines(source)) end
  end

  test "formats sparse diagnostics and rejects malformed genotypes and alternates" do
    assert VCF.Error.message(%Error{}) == "invalid_value"
    assert VCF.Warning.message(%Warning{}) == "warning (invalid_value)"

    assert VCF.Warning.message(%Warning{line: 2, field: :info, reason: :bad}) ==
             "warning at line 2 INFO (bad)"

    assert {:error, %Error{reason: :invalid_syntax}} = Genotype.parse(:not_binary)

    assert {:error, %Error{reason: :empty_genotype}} =
             Genotype.encode(%Genotype{alleles: [], phasing: []})

    assert {:error, %Error{reason: :invalid_allele}} =
             VCF.Validator.Alternate.validate(:not_binary)

    refute VCF.Spec.Common.allowed_number?(5, :info, :p)
    refute VCF.Spec.Common.partial_phasing?(%Genotype{alleles: [], phasing: []})
  end

  test "writer handles tagged records, invalid destinations, compression options, and cleanup" do
    %Document{header: header, records: [record]} = VCF.parse!(@valid)

    tagged = %VCF.Stream{header: header, records: [{:ok, record}], mode: :strict, bang?: false}
    assert :ok = VCF.write(device(), tagged)

    error = %Error{kind: :source_error, reason: :boom}
    failed = %{tagged | records: [{:error, error}]}
    assert {:error, ^error} = VCF.write(device(), failed)

    unexpected = %{tagged | records: [:not_a_record]}
    assert {:error, %Error{reason: :expected_record}} = VCF.write(device(), unexpected)

    assert {:error, %Error{kind: :invalid_option, reason: :unsupported_compression}} =
             VCF.write(device(), %Document{header: header, records: [record]}, compression: :bgzf)

    assert {:error, %Error{kind: :write_error}} =
             VCF.write(:missing_device, %Document{header: header, records: [record]},
               compression: :gzip
             )

    directory_destination =
      Path.join(System.tmp_dir!(), "vcf-directory-#{System.unique_integer([:positive])}")

    File.mkdir!(directory_destination)
    on_exit(fn -> File.rmdir(directory_destination) end)

    assert {:error, %Error{kind: :write_error}} =
             VCF.write(directory_destination, %Document{header: header, records: [record]})

    invalid_header = %{header | samples: [""]}

    assert {:error, [%Error{reason: :empty_sample}]} =
             VCF.write(device(), %Document{header: invalid_header, records: []})

    failed_path = directory_destination <> ".vcf"
    invalid = %{record | pos: 0}
    refute File.exists?(failed_path)

    assert {:error, [_error]} =
             VCF.write(failed_path, %Document{header: header, records: [invalid]})

    refute File.exists?(failed_path)
  end

  test "writer encodes metadata cardinalities, types, special values, and escaping" do
    definitions = [
      definition("A", :a, :integer),
      definition("R", :r, :float),
      definition("G", :g, :flag),
      definition("P", :p, :character),
      definition("LA", :la, :string),
      definition("LR", :lr, :string),
      definition("LG", :lg, :string),
      definition("M", :m, :string),
      definition("VAR", :variable, :string)
    ]

    header = %Header{
      version: %Version{major: 4, minor: 5},
      metadata:
        Enum.map(definitions, &%Metadata{key: "INFO", value: &1}) ++
          [
            %Metadata{key: "META", value: [{"ID", "quoted value"}]},
            %Metadata{key: "raw", value: [{"ID", "x"}], raw: "##raw=<ID=x>"},
            %Metadata{key: "source", value: "edge"}
          ],
      columns: [:chrom, :pos, :id, :ref, :alt, :qual, :filter, :info]
    }

    record = %Record{
      chrom: "chr1",
      pos: 1,
      ids: [],
      ref: "A",
      alt: [],
      qual: nil,
      filter: nil,
      info: [
        %Field{key: "FLAG", value: true},
        %Field{key: "SPECIAL", value: [:nan, :positive_infinity, :negative_infinity, 1, 1.5]},
        %Field{key: "TEXT", value: "%:;=,\t\n\r value"}
      ]
    }

    assert {:ok, encoded} = VCF.encode(header, [record], validate: false)
    assert encoded =~ "Number=A,Type=Integer"
    assert encoded =~ "Number=R,Type=Float"
    assert encoded =~ "Number=G,Type=Flag"
    assert encoded =~ "Number=P,Type=Character"
    assert encoded =~ "Number=LA,Type=String"
    assert encoded =~ "Number=LR"
    assert encoded =~ "Number=LG"
    assert encoded =~ "Number=M"
    assert encoded =~ "Number=."
    assert encoded =~ ~s(META=<ID="quoted value">)
    assert encoded =~ "NaN,Inf,-Inf,1,1.5"
    assert encoded =~ "%25%3A%3B%3D%2C%09%0A%0D%20value"
    assert encoded =~ "\t.\tA\t.\t.\t.\tFLAG;"
  end

  test "writer fills absent sample fields and surfaces nested encoding failures" do
    header = %Header{
      version: %Version{major: 4, minor: 2},
      metadata: [
        %Metadata{key: "FORMAT", value: definition("GT", 1, :string)},
        %Metadata{key: "FORMAT", value: definition("X", 1, :string)}
      ],
      columns: [:chrom, :pos, :id, :ref, :alt, :qual, :filter, :info, :format],
      samples: ["S1"]
    }

    record = %Record{
      chrom: "chr1",
      pos: 1,
      ref: "A",
      alt: ["C"],
      filter: ["q10"],
      format: ["GT", "X"],
      samples: [
        %Sample{
          name: "S1",
          values: [
            %Field{key: "GT", value: %Genotype{alleles: [0, 1], phasing: [nil, :unphased]}},
            %Field{key: "X", value: "raw"}
          ]
        }
      ]
    }

    assert {:ok, encoded} = VCF.encode(header, [record], validate: false)
    assert encoded =~ "\tq10\t.\tGT:X\t0/1:raw\n"

    bad = put_in(record.samples, [%{hd(record.samples) | values: [%Field{key: "X", value: %{}}]}])

    assert {:error, %Error{reason: :unsupported_value}} =
             VCF.encode(header, [bad], validate: false)

    bad_list = %{record | info: [%Field{key: "X", value: [1, %{}]}]}

    assert {:error, %Error{reason: :unsupported_value}} =
             VCF.encode(header, [bad_list], validate: false)
  end

  defp device do
    {:ok, device} = StringIO.open("")
    device
  end

  defp definition(id, number, type) do
    %FieldDefinition{id: id, number: number, type: type, description: "edge"}
  end
end
