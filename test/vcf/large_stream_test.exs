defmodule VCF.LargeStreamTest do
  use ExUnit.Case, async: false

  @tag :large
  test "enumerates one million generated records with bounded process memory" do
    header = [
      "##fileformat=VCFv4.5\n",
      "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
    ]

    records =
      Elixir.Stream.repeatedly(fn -> "chr1\t1\t.\tA\tC\t.\tPASS\t.\n" end)
      |> Elixir.Stream.take(1_000_000)

    :erlang.garbage_collect()
    before = process_memory()
    count = header |> Elixir.Stream.concat(records) |> VCF.stream!() |> Enum.count()
    :erlang.garbage_collect()
    growth = max(process_memory() - before, 0)

    assert count == 1_000_000
    assert growth < 64 * 1024 * 1024
  end

  defp process_memory do
    {:memory, bytes} = Process.info(self(), :memory)
    bytes
  end
end
