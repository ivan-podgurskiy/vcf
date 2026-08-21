defmodule VCF.Validator.RecordTest do
  use ExUnit.Case, async: true

  alias VCF.Field
  alias VCF.FieldDefinition
  alias VCF.Genotype
  alias VCF.Header
  alias VCF.Metadata
  alias VCF.Record
  alias VCF.Sample
  alias VCF.Validator
  alias VCF.Version

  test "validates declarations, cardinality, sample shape, and genotype bounds" do
    header =
      header(
        4,
        [definition("INFO", "AC", :a, :integer), definition("FORMAT", "GT", 1, :string)],
        ["S1"]
      )

    record = %Record{
      chrom: "chr1",
      pos: 0,
      ref: "A",
      alt: ["C", "G"],
      info: [
        %Field{key: "AC", value: [1], raw: "1"},
        %Field{key: "UNKNOWN", value: 3, raw: "3"}
      ],
      format: ["GT"],
      samples: [
        %Sample{
          name: "S1",
          values: [
            %Field{key: "GT", value: %Genotype{alleles: [0, 3], phasing: [nil, :unphased]}}
          ]
        }
      ],
      line: 10
    }

    assert [
             %VCF.Error{line: 10, field: :pos, reason: :must_be_positive},
             %VCF.Error{line: 10, field: :info, key: "AC", reason: :invalid_cardinality},
             %VCF.Error{line: 10, field: :info, key: "UNKNOWN", reason: :undeclared_field},
             %VCF.Error{
               line: 10,
               field: :format,
               key: "GT",
               reason: :genotype_allele_out_of_bounds
             }
           ] = Validator.validate_record(record, header)
  end

  test "enforces alternate and partial-phasing version boundaries" do
    genotype = %Genotype{alleles: [0, 1, 1], phasing: [nil, :phased, :unphased]}
    sample = %Sample{name: "S1", values: [%Field{key: "GT", value: genotype}]}

    record = %Record{
      chrom: "chr1",
      pos: 1,
      ref: "A",
      alt: ["<*>", "<NON_REF>"],
      format: ["GT"],
      samples: [sample]
    }

    metadata = [definition("FORMAT", "GT", 1, :string)]

    errors_43 = Validator.validate_record(record, header(3, metadata, ["S1"]))
    assert Enum.any?(errors_43, &(&1.reason == :unsupported_alternate))
    assert Enum.any?(errors_43, &(&1.reason == :partial_phasing_not_supported))

    errors_44 = Validator.validate_record(record, header(4, metadata, ["S1"]))
    assert Enum.any?(errors_44, &(&1.reason == :unsupported_alternate))
    refute Enum.any?(errors_44, &(&1.reason == :partial_phasing_not_supported))

    assert [] = Validator.validate_record(record, header(5, metadata, ["S1"]))
  end

  test "allows missing members inside a correctly sized typed list" do
    metadata = [definition("INFO", "AD", :r, :integer)]

    record = %Record{
      chrom: "chr1",
      pos: 1,
      ref: "A",
      alt: ["C"],
      info: [%Field{key: "AD", value: [12, nil], raw: "12,."}]
    }

    assert [] = Validator.validate_record(record, header(5, metadata, []))
  end

  test "applies VCF 4.3 contig-name and 32-bit Integer restrictions" do
    metadata = [definition("INFO", "BIG", 1, :integer)]

    record = %Record{
      chrom: "chr1:part",
      pos: 1,
      ref: "A",
      alt: ["C"],
      info: [%Field{key: "BIG", value: 2_147_483_648}]
    }

    assert [] = Validator.validate_record(record, header(2, metadata, []))

    assert [
             %VCF.Error{field: :chrom, reason: :invalid_contig_name},
             %VCF.Error{field: :info, key: "BIG", reason: :integer_out_of_range}
           ] = Validator.validate_record(record, header(3, metadata, []))
  end

  test "accumulates header and record errors in document order" do
    header = header(5, [], [])
    first = %Record{chrom: "", pos: 0, ref: "A", line: 8}
    second = %Record{chrom: "chr1", pos: -1, ref: "", line: 9}

    errors = Validator.validate(header, [first, second])

    assert Enum.map(errors, &{&1.line, &1.field}) == [
             {8, :chrom},
             {8, :pos},
             {9, :pos},
             {9, :ref}
           ]
  end

  test "validates PASS placement and declared filters independently" do
    declared = %Metadata{key: "FILTER", value: [{"ID", "q10"}], raw: ""}
    header = header(5, [declared], [])

    record = %Record{
      chrom: "chr1",
      pos: 1,
      ref: "A",
      filter: ["PASS", "missing", "q10"]
    }

    assert [
             %VCF.Error{field: :filter, key: "PASS", reason: :pass_must_be_standalone},
             %VCF.Error{field: :filter, key: "missing", reason: :undeclared_field}
           ] = Validator.validate_record(record, header)
  end

  test "validates sample counts and FORMAT values without genotypes" do
    metadata = [
      definition("FORMAT", "GT", 1, :string),
      definition("FORMAT", "CH", 1, :character),
      definition("FORMAT", "F", 1, :float)
    ]

    sample = %Sample{
      name: "S1",
      values: [
        %Field{key: "GT", value: "raw"},
        %Field{key: "CH", value: "too long"},
        %Field{key: "F", value: :negative_infinity},
        %Field{key: "UNKNOWN", value: "kept"}
      ]
    }

    record = %Record{
      chrom: "chr1",
      pos: 1,
      ref: "A",
      alt: ["C"],
      format: ["GT", "CH", "F", "UNKNOWN"],
      samples: [sample]
    }

    errors = Validator.validate_record(record, header(5, metadata, ["S1", "S2"]))
    assert Enum.any?(errors, &(&1.reason == :sample_count_mismatch))
    assert Enum.any?(errors, &(&1.key == "UNKNOWN" and &1.reason == :undeclared_field))
    assert Enum.any?(errors, &(&1.key == "CH" and &1.reason == :invalid_type))

    without_gt = %{sample | values: [%Field{key: "F", value: 1.0}]}
    without_gt_record = %{record | format: ["F"], samples: [without_gt]}
    assert [] = Validator.validate_record(without_gt_record, header(5, metadata, ["S1"]))
  end

  test "accepts special qualities and reports float ranges and fallback type errors" do
    metadata = [
      definition("INFO", "F", 1, :float),
      definition("INFO", "S", 1, :string),
      definition("INFO", "C", 1, :character)
    ]

    valid = %Record{
      chrom: "chr1",
      pos: 1,
      ref: "A",
      qual: :nan,
      info: [
        %Field{key: "F", value: :negative_infinity},
        %Field{key: "S", value: "text"},
        %Field{key: "C", value: "x"}
      ]
    }

    assert [] = Validator.validate_record(valid, header(5, metadata, []))

    assert [] =
             Validator.validate_record(
               %{valid | qual: :positive_infinity},
               header(5, metadata, [])
             )

    invalid = %{
      valid
      | info: [
          %Field{key: "F", value: 3.5e38},
          %Field{key: "S", value: %{}},
          %Field{key: "C", value: "xx"}
        ]
    }

    errors = Validator.validate_record(invalid, header(5, metadata, []))
    assert Enum.any?(errors, &(&1.key == "F" and &1.reason == :float_out_of_range))
    assert Enum.count(errors, &(&1.reason == :invalid_type)) == 2

    unknown_type = [definition("INFO", "U", 1, :unknown)]
    unknown_record = %{valid | info: [%Field{key: "U", value: "value"}]}

    assert [%VCF.Error{key: "U", reason: :invalid_type}] =
             Validator.validate_record(unknown_record, header(5, unknown_type, []))
  end

  defp header(minor, metadata, samples) do
    %Header{
      version: %Version{major: 4, minor: minor},
      columns: [:chrom, :pos, :id, :ref, :alt, :qual, :filter, :info],
      metadata: metadata,
      samples: samples
    }
  end

  defp definition(key, id, number, type) do
    %Metadata{
      key: key,
      raw: "",
      value: %FieldDefinition{id: id, number: number, type: type, description: "test"}
    }
  end
end
