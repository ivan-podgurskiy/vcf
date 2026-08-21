defmodule VCF.CompressionTest do
  use ExUnit.Case, async: true

  alias VCF.Compression

  @content "##fileformat=VCFv4.5\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"

  test "enumerates identical physical lines from plain and gzip chunks" do
    expected = [
      {:ok, "##fileformat=VCFv4.5\n"},
      {:ok, "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"}
    ]

    assert Enum.to_list(Compression.lines([@content])) == expected

    gzip = :zlib.gzip(@content)
    <<first::binary-size(7), rest::binary>> = gzip
    assert Enum.to_list(Compression.lines([first, rest])) == expected
  end

  test "decodes concatenated BGZF blocks" do
    bgzf = bgzf_block("first\n") <> bgzf_block("second\n") <> bgzf_block("")

    chunks = for <<chunk::binary-size(5) <- bgzf>>, do: chunk
    remainder_size = rem(byte_size(bgzf), 5)

    chunks =
      if remainder_size == 0,
        do: chunks,
        else: chunks ++ [binary_part(bgzf, byte_size(bgzf) - remainder_size, remainder_size)]

    assert Enum.to_list(Compression.lines(chunks)) == [{:ok, "first\n"}, {:ok, "second\n"}]
  end

  test "returns structured errors for truncated streams and oversized lines" do
    gzip = :zlib.gzip(@content)
    truncated = binary_part(gzip, 0, byte_size(gzip) - 4)

    assert {:error, %VCF.Error{kind: :compression_error}} =
             truncated |> List.wrap() |> Compression.lines() |> Enum.to_list() |> List.last()

    assert [{:error, %VCF.Error{kind: :line_too_long, reason: :max_line_bytes_exceeded}}] =
             Enum.to_list(Compression.lines(["12345"], max_line_bytes: 4))
  end

  defp bgzf_block(data) do
    compressed = raw_deflate(data)
    total_size = 18 + byte_size(compressed) + 8
    bsize = total_size - 1

    header =
      <<0x1F, 0x8B, 8, 4, 0, 0, 0, 0, 0, 255, 6::little-16, "BC", 2::little-16, bsize::little-16>>

    header <>
      compressed <>
      <<:erlang.crc32(data)::little-32, byte_size(data)::little-32>>
  end

  defp raw_deflate(data) do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
    result = IO.iodata_to_binary(:zlib.deflate(z, data, :finish))
    :ok = :zlib.deflateEnd(z)
    :ok = :zlib.close(z)
    result
  end
end
