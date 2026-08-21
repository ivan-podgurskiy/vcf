defmodule VCFTest do
  use ExUnit.Case, async: true

  test "reports every supported VCF version in ascending order" do
    assert VCF.supported_versions() == ["4.1", "4.2", "4.3", "4.4", "4.5"]
  end
end
