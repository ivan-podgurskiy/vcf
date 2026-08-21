defmodule VCF.Compression do
  @moduledoc "Incremental physical-line decoding for plain, gzip, and BGZF byte streams."

  import Bitwise

  alias VCF.Error

  @default_max_line_bytes 67_108_864
  @gzip_magic <<0x1F, 0x8B>>

  @doc "Returns a lazy enumerable of tagged physical lines."
  @spec lines(Enumerable.t(), keyword()) :: Enumerable.t()
  def lines(chunks, options \\ []) do
    max_line_bytes = Keyword.get(options, :max_line_bytes, @default_max_line_bytes)

    chunks
    |> decoded_chunks()
    |> split_lines(max_line_bytes)
  end

  defp decoded_chunks(chunks) do
    chunks
    |> Elixir.Stream.concat([:vcf_compression_eof])
    |> Elixir.Stream.transform(
      fn -> %{mode: :detect, buffer: <<>>, z: nil, failed: false} end,
      &decode_chunk/2,
      &close_decoder/1
    )
  end

  defp decode_chunk(_chunk, %{failed: true} = state), do: {[], state}

  defp decode_chunk(:vcf_compression_eof, state) do
    finish_decoder(state)
  end

  defp decode_chunk(chunk, state) when not is_binary(chunk) do
    fail(state, :invalid_chunk, chunk)
  end

  defp decode_chunk(chunk, %{mode: :detect, buffer: buffer} = state) do
    detect(%{state | buffer: buffer <> chunk})
  end

  defp decode_chunk(chunk, %{mode: :plain} = state), do: {[{:data, chunk}], state}
  defp decode_chunk(chunk, %{mode: :gzip} = state), do: inflate_chunk(chunk, state)

  defp decode_chunk(chunk, %{mode: :bgzf, buffer: buffer} = state) do
    decode_bgzf(%{state | buffer: buffer <> chunk})
  end

  defp detect(%{buffer: buffer} = state) when byte_size(buffer) < 2, do: {[], state}

  defp detect(%{buffer: @gzip_magic <> _rest = buffer} = state) do
    cond do
      byte_size(buffer) < 4 ->
        {[], state}

      binary_part(buffer, 3, 1) |> :binary.first() |> band(4) == 0 ->
        start_gzip(state)

      byte_size(buffer) < 12 ->
        {[], state}

      true ->
        <<_fixed::binary-size(10), xlen::little-16, _rest::binary>> = buffer

        if byte_size(buffer) < 12 + xlen do
          {[], state}
        else
          extra = binary_part(buffer, 12, xlen)

          if bgzf_extra?(extra) do
            decode_bgzf(%{state | mode: :bgzf})
          else
            start_gzip(state)
          end
        end
    end
  end

  defp detect(%{buffer: buffer} = state),
    do: {[{:data, buffer}], %{state | mode: :plain, buffer: <<>>}}

  defp start_gzip(%{buffer: buffer} = state) do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z, 47)
    inflate_chunk(buffer, %{state | mode: :gzip, buffer: <<>>, z: z})
  end

  defp inflate_chunk(chunk, %{z: z} = state) do
    try do
      {output, _status} = drain_inflater(z, chunk, [])
      items = if output == <<>>, do: [], else: [{:data, output}]
      {items, state}
    catch
      kind, reason -> fail(state, {kind, reason}, chunk)
    end
  end

  defp drain_inflater(z, input, output) do
    case :zlib.safeInflate(z, input) do
      {:continue, inflated} ->
        drain_inflater(z, [], [output, inflated])

      {:finished, inflated} ->
        {IO.iodata_to_binary([output, inflated]), :finished}
    end
  end

  defp decode_bgzf(%{buffer: buffer} = state) do
    case bgzf_block_size(buffer) do
      :more ->
        {[], state}

      {:error, reason} ->
        fail(state, reason, buffer)

      {:ok, size} when byte_size(buffer) < size ->
        {[], state}

      {:ok, size} ->
        {block, rest} = :erlang.split_binary(buffer, size)

        try do
          output = :zlib.gunzip(block)
          {more_items, next_state} = decode_bgzf(%{state | buffer: rest})
          items = if output == <<>>, do: more_items, else: [{:data, output} | more_items]
          {items, next_state}
        catch
          kind, reason -> fail(state, {kind, reason}, block)
        end
    end
  end

  defp bgzf_block_size(buffer) when byte_size(buffer) < 12, do: :more

  defp bgzf_block_size(<<@gzip_magic, 8, flags, _rest::binary>> = buffer) do
    if band(flags, 4) == 0 do
      {:error, :missing_bgzf_extra}
    else
      <<_fixed::binary-size(10), xlen::little-16, _rest::binary>> = buffer

      if byte_size(buffer) < 12 + xlen do
        :more
      else
        extra = binary_part(buffer, 12, xlen)

        case find_bgzf_size(extra) do
          {:ok, bsize} -> {:ok, bsize + 1}
          :error -> {:error, :missing_bgzf_block_size}
        end
      end
    end
  end

  defp bgzf_block_size(_buffer), do: {:error, :invalid_bgzf_header}

  defp bgzf_extra?(extra), do: match?({:ok, _size}, find_bgzf_size(extra))

  defp find_bgzf_size(<<"BC", 2::little-16, bsize::little-16, _rest::binary>>),
    do: {:ok, bsize}

  defp find_bgzf_size(<<_id::binary-size(2), length::little-16, rest::binary>>)
       when byte_size(rest) >= length do
    {_value, remaining} = :erlang.split_binary(rest, length)
    find_bgzf_size(remaining)
  end

  defp find_bgzf_size(_extra), do: :error

  defp finish_decoder(%{mode: :detect, buffer: <<>>} = state), do: {[], state}

  defp finish_decoder(%{mode: :detect, buffer: @gzip_magic <> _rest = buffer} = state),
    do: fail(state, :truncated_gzip, buffer)

  defp finish_decoder(%{mode: :detect, buffer: buffer} = state),
    do: {[{:data, buffer}], %{state | mode: :plain, buffer: <<>>}}

  defp finish_decoder(%{mode: :plain} = state), do: {[], state}

  defp finish_decoder(%{mode: :bgzf, buffer: <<>>} = state), do: {[], state}

  defp finish_decoder(%{mode: :bgzf, buffer: buffer} = state),
    do: fail(state, :truncated_bgzf, buffer)

  defp finish_decoder(%{mode: :gzip, z: z} = state) do
    try do
      :ok = :zlib.inflateEnd(z)
      {[], state}
    catch
      kind, reason -> fail(state, {kind, reason}, nil)
    end
  end

  defp close_decoder(%{z: nil}), do: :ok

  defp close_decoder(%{z: z}) do
    :zlib.close(z)
  end

  defp fail(state, reason, value) do
    error = %Error{kind: :compression_error, value: value, reason: normalize_reason(reason)}
    {[{:error, error}], %{state | failed: true}}
  end

  defp normalize_reason({_kind, reason}) when is_atom(reason), do: reason
  defp normalize_reason(reason) when is_atom(reason), do: reason

  defp split_lines(decoded, max_line_bytes) do
    decoded
    |> Elixir.Stream.concat([:vcf_lines_eof])
    |> Elixir.Stream.transform({<<>>, false}, fn
      _item, {_carry, true} = state ->
        {[], state}

      {:error, error}, {_carry, false} ->
        {[{:error, error}], {<<>>, true}}

      {:data, data}, {carry, false} ->
        emit_lines(carry <> data, max_line_bytes)

      :vcf_lines_eof, {<<>>, false} ->
        {[], {<<>>, false}}

      :vcf_lines_eof, {carry, false} ->
        {[{:ok, carry}], {<<>>, false}}
    end)
  end

  defp emit_lines(data, max_line_bytes) do
    parts = :binary.split(data, "\n", [:global])
    carry = List.last(parts)
    complete = parts |> Enum.drop(-1) |> Enum.map(&(&1 <> "\n"))

    case Enum.find(complete, &(byte_size(&1) > max_line_bytes)) do
      nil when byte_size(carry) <= max_line_bytes ->
        {Enum.map(complete, &{:ok, &1}), {carry, false}}

      _oversized ->
        line_too_long(max_line_bytes)
    end
  end

  defp line_too_long(max_line_bytes) do
    error = %Error{
      kind: :line_too_long,
      value: max_line_bytes,
      reason: :max_line_bytes_exceeded
    }

    {[{:error, error}], {<<>>, true}}
  end
end
