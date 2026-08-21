defmodule VCF.DocumentationTest do
  use ExUnit.Case, async: true

  doctest VCF
  doctest VCF.Field
  doctest VCF.Genotype

  test "Hex package allowlist includes user documentation and excludes development notes" do
    files = Mix.Project.config() |> Keyword.fetch!(:package) |> Keyword.fetch!(:files)

    assert "README.md" in files
    assert "CHANGELOG.md" in files
    assert "LICENSE" in files
    refute Enum.any?(files, &String.contains?(&1, "PRD"))
    refute Enum.any?(files, &String.contains?(&1, ".superpowers"))
  end
end
