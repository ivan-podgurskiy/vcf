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
