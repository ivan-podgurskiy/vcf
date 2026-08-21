defmodule VCF.VersionTest do
  use ExUnit.Case, async: true

  alias VCF.Error
  alias VCF.Version

  test "parses each supported fileformat value" do
    for minor <- 1..5 do
      value = "VCFv4.#{minor}"

      assert {:ok, %{__struct__: Version, major: 4, minor: ^minor}} = Version.parse(value)
    end
  end

  test "returns a structured error for an unsupported version" do
    assert {:error,
            %{
              __struct__: Error,
              kind: :unsupported_version,
              field: :fileformat,
              value: "VCFv3.3"
            }} = Version.parse("VCFv3.3")
  end

  test "rejects malformed fileformat values without raising" do
    assert {:error, %{__struct__: Error, kind: :invalid_version, value: "4.5"}} =
             Version.parse("4.5")

    assert {:error, %{__struct__: Error, kind: :invalid_version, value: nil}} =
             Version.parse(nil)
  end

  test "formats a version as a fileformat value" do
    {:ok, version} = Version.parse("VCFv4.5")

    assert to_string(version) == "VCFv4.5"
  end
end
