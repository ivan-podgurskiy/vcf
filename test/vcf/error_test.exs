defmodule VCF.ErrorTest do
  use ExUnit.Case, async: true

  alias VCF.Error
  alias VCF.ParseError
  alias VCF.Warning

  test "formats populated diagnostic fields for people without losing the struct" do
    error =
      struct(Error,
        kind: :invalid_value,
        line: 123,
        column: 8,
        field: :info,
        key: "DP",
        value: "abc",
        reason: :expected_integer
      )

    assert to_string(error) =~ "invalid_value"
    assert to_string(error) =~ "line 123"
    assert to_string(error) =~ "INFO.DP"

    exception = ParseError.exception(error)
    assert exception.error == error
    assert Exception.message(exception) == to_string(error)
  end

  test "keeps permissive warnings machine-readable" do
    warning =
      struct(Warning,
        line: 172,
        field: :info,
        key: "AF",
        value: "0.1,0.2",
        reason: :invalid_cardinality
      )

    assert warning.reason == :invalid_cardinality
    assert to_string(warning) =~ "warning"
    assert to_string(warning) =~ "line 172"
    assert to_string(warning) =~ "INFO.AF"
  end
end
