defmodule VCF.Parser.MetadataTest do
  use ExUnit.Case, async: true

  alias VCF.Error
  alias VCF.FieldDefinition
  alias VCF.Metadata
  alias VCF.Parser.Metadata, as: MetadataParser
  alias VCF.Warning

  test "parses quoted structured metadata without splitting commas in descriptions" do
    line = ~s(##INFO=<ID=DP,Number=1,Type=Integer,Description="Total Depth, unfiltered">)

    assert {:ok,
            %{
              __struct__: Metadata,
              key: "INFO",
              line: 2,
              value: %{
                __struct__: FieldDefinition,
                id: "DP",
                number: 1,
                type: :integer,
                description: "Total Depth, unfiltered"
              }
            }, []} = MetadataParser.parse(line, 2, :strict)
  end

  test "unescapes quoted values and preserves additional attributes in order" do
    line =
      ~s(##INFO=<ID=CSQ,Number=.,Type=String,Description="A \\"quote\\" and \\\\ slash",Source="tool",Version="1=2">)

    assert {:ok, %{value: definition}, []} = MetadataParser.parse(line, 4, :strict)
    assert definition.description == ~s(A "quote" and \\ slash)
    assert definition.attributes == [{"Source", "tool"}, {"Version", "1=2"}]
  end

  test "preserves unknown and vendor-specific metadata" do
    line = "##GenotekPipelineVersion=17"

    assert {:ok,
            %{
              __struct__: Metadata,
              key: "GenotekPipelineVersion",
              value: "17",
              raw: ^line
            }, []} = MetadataParser.parse(line, 8, :strict)
  end

  test "parses non-field structured metadata as ordered binary attributes" do
    line = ~s(##contig=<ID=chr1,length=248956422,assembly="GRCh38">)

    assert {:ok,
            %{
              key: "contig",
              value: [
                {"ID", "chr1"},
                {"length", "248956422"},
                {"assembly", "GRCh38"}
              ]
            }, []} = MetadataParser.parse(line, 3, :strict)
  end

  test "returns errors in strict mode and warnings with retained data in permissive mode" do
    line = ~s(##INFO=<ID=DP,Number=bad,Type=Integer,Description="Depth">)

    assert {:error,
            %{
              __struct__: Error,
              line: 7,
              field: :metadata,
              key: "DP",
              reason: :invalid_number
            }} = MetadataParser.parse(line, 7, :strict)

    assert {:ok, %{value: %{number: nil}}, [warning]} =
             MetadataParser.parse(line, 7, :permissive)

    assert %{
             __struct__: Warning,
             line: 7,
             field: :metadata,
             key: "DP",
             reason: :invalid_number
           } = warning
  end

  test "rejects malformed structured syntax" do
    assert {:error, %{__struct__: Error, reason: :unterminated_quote}} =
             MetadataParser.parse(~s(##INFO=<ID=X,Description="broken>), 9, :strict)

    assert {:error, %{__struct__: Error, reason: :missing_attribute_value}} =
             MetadataParser.parse("##contig=<ID>", 10, :strict)
  end

  test "reports every malformed metadata boundary" do
    for line <- ["source=x", "##=x"] do
      assert {:error, %Error{reason: :invalid_syntax}} = MetadataParser.parse(line, 1, :strict)
    end

    assert {:error, %Error{reason: :unterminated_structure}} =
             MetadataParser.parse("##contig=<ID=x", 2, :strict)

    assert {:error, %Error{reason: :missing_id}} =
             MetadataParser.parse(
               ~s(##INFO=<Number=1,Type=Integer,Description="missing">),
               3,
               :strict
             )

    assert {:ok, %{value: %{number: nil, type: nil}}, []} =
             MetadataParser.parse(~s(##INFO=<ID=X,Description="incomplete">), 4, :strict)

    assert {:error, %Error{reason: :invalid_type}} =
             MetadataParser.parse(
               ~s(##INFO=<ID=X,Number=1,Type=Unknown,Description="bad">),
               5,
               :strict
             )

    assert {:error, %Error{reason: :empty_structure}} =
             MetadataParser.parse("##contig=<>", 6, :strict)

    assert {:error, %Error{reason: :unterminated_quote}} =
             MetadataParser.parse(~s(##contig=<ID="x"suffix>), 7, :strict)
  end
end
