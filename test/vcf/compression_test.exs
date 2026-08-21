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

  test "detects fragmented gzip headers and non-BGZF gzip extra fields" do
    gzip = :zlib.gzip(@content)
    byte_chunks = for <<byte <- gzip>>, do: <<byte>>

    assert Enum.to_list(Compression.lines(byte_chunks)) ==
             Enum.to_list(Compression.lines([@content]))

    with_extra = gzip_with_extra(@content, <<"XY", 0::little-16>>)

    assert Enum.to_list(Compression.lines([with_extra])) ==
             Enum.to_list(Compression.lines([@content]))
  end

  test "drains inflater output larger than one internal zlib buffer" do
    content = String.duplicate("x", 100_000)
    assert Enum.to_list(Compression.lines([:zlib.gzip(content)])) == [{:ok, content}]
  end

  test "stops after invalid chunks and malformed gzip payloads" do
    assert [{:error, %VCF.Error{kind: :compression_error, reason: :invalid_chunk}}] =
             Enum.to_list(Compression.lines([:invalid, "ignored\n"]))

    malformed = <<0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 255, "not-deflate">>

    assert [{:error, %VCF.Error{kind: :compression_error}}] =
             Enum.to_list(Compression.lines([malformed]))

    assert [{:error, %VCF.Error{kind: :compression_error, reason: :truncated_gzip}}] =
             Enum.to_list(Compression.lines([<<0x1F, 0x8B>>]))
  end

  test "reports malformed, corrupt, and truncated BGZF blocks" do
    prefix = <<"XY", 1::little-16, 0>>
    prefixed = bgzf_block("prefixed\n", prefix)
    assert Enum.to_list(Compression.lines([prefixed])) == [{:ok, "prefixed\n"}]

    missing_size = bgzf_block("ok\n") <> gzip_with_extra("", <<"XY", 0::little-16>>)

    assert {:error, %VCF.Error{kind: :compression_error, reason: :missing_bgzf_block_size}} =
             missing_size |> List.wrap() |> Compression.lines() |> Enum.to_list() |> List.last()

    invalid_header = bgzf_block("ok\n") <> String.duplicate("x", 12)

    assert {:error, %VCF.Error{kind: :compression_error, reason: :invalid_bgzf_header}} =
             invalid_header |> List.wrap() |> Compression.lines() |> Enum.to_list() |> List.last()

    corrupt = corrupt_payload(bgzf_block("corrupt\n"))

    assert [{:error, %VCF.Error{kind: :compression_error}}] =
             Enum.to_list(Compression.lines([corrupt]))

    block = bgzf_block("truncated\n")
    truncated = binary_part(block, 0, 18)

    assert [{:error, %VCF.Error{kind: :compression_error, reason: :truncated_bgzf}}] =
             Enum.to_list(Compression.lines([truncated]))
  end

  defp bgzf_block(data, prefix \\ <<>>) do
    compressed = raw_deflate(data)
    extra_size = byte_size(prefix) + 6
    total_size = 12 + extra_size + byte_size(compressed) + 8
    bsize = total_size - 1

    header =
      <<0x1F, 0x8B, 8, 4, 0, 0, 0, 0, 0, 255, extra_size::little-16, prefix::binary, "BC",
        2::little-16, bsize::little-16>>

    header <>
      compressed <>
      <<:erlang.crc32(data)::little-32, byte_size(data)::little-32>>
  end

  defp gzip_with_extra(data, extra) do
    compressed = raw_deflate(data)

    <<0x1F, 0x8B, 8, 4, 0, 0, 0, 0, 0, 255, byte_size(extra)::little-16, extra::binary,
      compressed::binary, :erlang.crc32(data)::little-32, byte_size(data)::little-32>>
  end

  defp corrupt_payload(block) do
    <<header::binary-size(18), byte, rest::binary>> = block
    header <> <<Bitwise.bxor(byte, 0xFF)>> <> rest
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
