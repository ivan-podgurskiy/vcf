defmodule VCF.Validator.HeaderTest do
  use ExUnit.Case, async: true

  alias VCF.FieldDefinition
  alias VCF.Header
  alias VCF.Metadata
  alias VCF.Validator
  alias VCF.Version

  test "returns independent header errors in source order" do
    header = %Header{
      version: %Version{major: 4, minor: 3},
      columns: [:chrom, :pos, :id, :ref, :alt, :qual, :filter, :info, :format],
      samples: ["sample", "sample"],
      metadata: [
        definition("INFO", "bad-id", 1, :integer, 2),
        definition("INFO", "bad-id", 1, :integer, 3),
        definition("INFO", "FLAG", 1, :flag, 4),
        definition("FORMAT", "PL", :p, :integer, 5)
      ]
    }

    assert [
             %VCF.Error{line: 2, reason: :invalid_id},
             %VCF.Error{line: 3, reason: :duplicate_definition},
             %VCF.Error{line: 3, reason: :invalid_id},
             %VCF.Error{line: 4, reason: :flag_requires_number_zero},
             %VCF.Error{line: 5, reason: :unsupported_number},
             %VCF.Error{reason: :duplicate_sample}
           ] = Validator.validate_header(header)
  end

  test "accepts Number P starting in 4.4 and local Numbers starting in 4.5" do
    format_p = definition("FORMAT", "PS", :p, :integer, 2)
    format_la = definition("FORMAT", "LAD", :la, :integer, 3)

    assert [%VCF.Error{reason: :unsupported_number}] =
             Validator.validate_header(header(3, [format_p]))

    assert [] = Validator.validate_header(header(4, [format_p]))

    assert [%VCF.Error{reason: :unsupported_number}] =
             Validator.validate_header(header(4, [format_la]))

    assert [] = Validator.validate_header(header(5, [format_p, format_la]))
  end

  test "enforces the 4.2 trailing INFO attributes and 4.3 META boundaries" do
    info =
      %Metadata{
        key: "INFO",
        line: 2,
        raw: "",
        value: %FieldDefinition{
          id: "DP",
          number: 1,
          type: :integer,
          description: "Depth",
          attributes: [{"Source", "fixture"}]
        }
      }

    meta = %Metadata{key: "META", line: 3, raw: "", value: [{"ID", "Assay"}]}

    assert [%VCF.Error{reason: :unsupported_attributes}] =
             Validator.validate_header(header(1, [info]))

    assert [] = Validator.validate_header(header(2, [info]))

    assert [%VCF.Error{reason: :unsupported_metadata}] =
             Validator.validate_header(header(2, [meta]))

    assert [] = Validator.validate_header(header(3, [meta]))
  end

  defp header(minor, metadata) do
    %Header{
      version: %Version{major: 4, minor: minor},
      columns: [:chrom, :pos, :id, :ref, :alt, :qual, :filter, :info],
      metadata: metadata
    }
  end

  defp definition(key, id, number, type, line) do
    %Metadata{
      key: key,
      line: line,
      raw: "",
      value: %FieldDefinition{id: id, number: number, type: type, description: "test"}
    }
  end
end
