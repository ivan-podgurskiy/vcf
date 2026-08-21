defmodule VCF.SourceTest do
  use ExUnit.Case, async: true

  alias VCF.Source

  @content "one\ntwo\n"

  test "path sources reopen for every enumeration" do
    path = Path.join(System.tmp_dir!(), "vcf-source-#{System.unique_integer([:positive])}.vcf")
    File.write!(path, @content)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, source} = Source.open(path)
    assert Enum.to_list(Source.lines(source)) == [{:ok, "one\n"}, {:ok, "two\n"}]
    assert Enum.to_list(Source.lines(source)) == [{:ok, "one\n"}, {:ok, "two\n"}]
  end

  test "does not close caller-owned IO devices" do
    {:ok, device} = StringIO.open(@content)
    assert {:ok, source} = Source.open(device)
    assert Enum.to_list(Source.lines(source)) == [{:ok, "one\n"}, {:ok, "two\n"}]
    assert :ok = IO.write(device, "still open")
  end

  test "generic enumerables are explicitly one-shot" do
    assert {:ok, source} = Source.open(["one\n", "two\n"])
    assert Enum.to_list(Source.lines(source)) == [{:ok, "one\n"}, {:ok, "two\n"}]

    assert [{:error, %VCF.Error{kind: :source_error, reason: :already_consumed}}] =
             Enum.to_list(Source.lines(source))
  end

  test "reports missing paths and invalid sources structurally" do
    missing = Path.join(System.tmp_dir!(), "missing-vcf-#{System.unique_integer([:positive])}")
    assert {:error, %VCF.Error{kind: :source_error, reason: :enoent}} = Source.open(missing)

    assert {:error, %VCF.Error{kind: :source_error, reason: :unsupported_source}} =
             Source.open(123)
  end
end
