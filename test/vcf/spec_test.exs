defmodule VCF.SpecTest do
  use ExUnit.Case, async: true

  alias VCF.Version

  test "selects one explicit profile for every supported version" do
    expected = [VCF.Spec.V4_1, VCF.Spec.V4_2, VCF.Spec.V4_3, VCF.Spec.V4_4, VCF.Spec.V4_5]

    modules =
      for minor <- 1..5 do
        assert {:ok, module} = VCF.Spec.for_version(%Version{major: 4, minor: minor})
        assert function_exported?(module, :validate_header, 1)
        assert function_exported?(module, :validate_record, 2)
        module
      end

    assert modules == expected

    assert {:error, %VCF.Error{kind: :unsupported_version}} =
             VCF.Spec.for_version(%Version{major: 4, minor: 6})
  end

  test "exposes version-specific Number and alternate-allele features" do
    refute VCF.Spec.V4_1.allowed_number?(:info, :r)
    assert VCF.Spec.V4_2.allowed_number?(:info, :r)
    refute VCF.Spec.V4_3.allowed_number?(:format, :p)
    assert VCF.Spec.V4_4.allowed_number?(:format, :p)
    refute VCF.Spec.V4_4.allowed_number?(:format, :la)
    assert VCF.Spec.V4_5.allowed_number?(:format, :la)
    assert VCF.Spec.V4_5.allowed_number?(:format, :lr)
    assert VCF.Spec.V4_5.allowed_number?(:format, :lg)
    assert VCF.Spec.V4_5.allowed_number?(:format, :m)

    refute VCF.Spec.V4_1.allowed_alternate?("*")
    assert VCF.Spec.V4_2.allowed_alternate?("*")
    refute VCF.Spec.V4_2.allowed_alternate?("<*>")
    assert VCF.Spec.V4_3.allowed_alternate?("<*>")
    refute VCF.Spec.V4_4.allowed_alternate?("<NON_REF>")
    assert VCF.Spec.V4_5.allowed_alternate?("<NON_REF>")
  end
end
