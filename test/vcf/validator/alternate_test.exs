defmodule VCF.Validator.AlternateTest do
  use ExUnit.Case, async: true

  alias VCF.Error
  alias VCF.Validator.Alternate

  test "accepts ordinary, symbolic, spanning-deletion, unspecified, and breakend alleles" do
    valid = [
      "A",
      "ACGTN",
      "<DEL>",
      "<INS:ME:ALU>",
      "<DUP>",
      "<INV>",
      "*",
      "<*>",
      "<NON_REF>",
      "N]chr2:321682]",
      "]chr2:321682]N",
      "N[chr2:321682[",
      "[chr2:321682[N",
      "N]HLA:ALT:2:321682]"
    ]

    for allele <- valid do
      assert :ok = Alternate.validate(allele, line: 12)
    end
  end

  test "rejects malformed symbolic and breakend alleles with context" do
    for allele <- [
          "",
          "<>",
          "<DEL",
          "N]chr2]",
          "N]chr2:x]",
          "N]chr2:1[",
          "[chr2:1]N",
          "N]chr[2:1]",
          "A]chr2:1]T",
          "N]chr2:1]]"
        ] do
      assert {:error,
              %{
                __struct__: Error,
                kind: :invalid_value,
                line: 12,
                field: :alt,
                value: ^allele,
                reason: :invalid_allele
              }} = Alternate.validate(allele, line: 12)
    end
  end
end
