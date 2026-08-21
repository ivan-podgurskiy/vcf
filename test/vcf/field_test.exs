defmodule VCF.FieldTest do
  use ExUnit.Case, async: true

  alias VCF.Field
  alias VCF.FieldDefinition

  test "looks up ordered duplicate fields without discarding values" do
    fields = [
      struct(Field, key: "DP", value: 10, raw: "10"),
      struct(Field, key: "AF", value: [0.5], raw: "0.5"),
      struct(Field, key: "DP", value: 11, raw: "11")
    ]

    assert Field.get(fields, "DP") == 10
    assert Field.get_all(fields, "DP") == [10, 11]
    assert Field.fetch(fields, "AF") == {:ok, [0.5]}
    assert Field.fetch(fields, "MISSING") == :error
  end

  test "parses only the closed set of field definition numbers" do
    assert {:ok, 12} = FieldDefinition.parse_number("12")

    for {source, expected} <- [
          {"A", :a},
          {"R", :r},
          {"G", :g},
          {"P", :p},
          {"LA", :la},
          {"LR", :lr},
          {"LG", :lg},
          {"M", :m},
          {".", :variable}
        ] do
      assert {:ok, ^expected} = FieldDefinition.parse_number(source)
    end

    assert :error = FieldDefinition.parse_number("-1")
    assert :error = FieldDefinition.parse_number("anything")
  end

  test "parses field types without creating atoms from input" do
    assert {:ok, :integer} = FieldDefinition.parse_type("Integer")
    assert {:ok, :float} = FieldDefinition.parse_type("Float")
    assert {:ok, :flag} = FieldDefinition.parse_type("Flag")
    assert {:ok, :character} = FieldDefinition.parse_type("Character")
    assert {:ok, :string} = FieldDefinition.parse_type("String")
    assert :error = FieldDefinition.parse_type("UnknownType")
  end
end
