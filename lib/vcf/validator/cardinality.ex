defmodule VCF.Validator.Cardinality do
  @moduledoc "Validates fixed and context-dependent VCF Number cardinalities."

  @spec validate(integer(), VCF.FieldDefinition.cardinality(), keyword()) ::
          :ok | {:error, :invalid_cardinality | :missing_cardinality_context}
  def validate(count, number, options \\ [])

  def validate(count, _number, _options) when not is_integer(count) or count < 0,
    do: {:error, :invalid_cardinality}

  def validate(_count, :variable, _options), do: :ok

  def validate(count, expected, _options) when is_integer(expected) and expected >= 0,
    do: compare(count, expected)

  def validate(count, :a, options), do: from_option(count, options, :alt_count, & &1)
  def validate(count, :r, options), do: from_option(count, options, :alt_count, &(&1 + 1))
  def validate(count, :p, options), do: from_option(count, options, :ploidy, & &1)
  def validate(count, :la, options), do: from_option(count, options, :local_alt_count, & &1)
  def validate(count, :lr, options), do: from_option(count, options, :local_alt_count, &(&1 + 1))
  def validate(count, :m, options), do: from_option(count, options, :modification_count, & &1)

  def validate(count, :g, options) do
    with {:ok, alt_count} <- fetch_count(options, :alt_count),
         {:ok, ploidy} <- fetch_count(options, :ploidy) do
      compare(count, combinations_with_repetition(alt_count + 1, ploidy))
    end
  end

  def validate(count, :lg, options) do
    with {:ok, alt_count} <- fetch_count(options, :local_alt_count),
         {:ok, ploidy} <- fetch_count(options, :ploidy) do
      compare(count, combinations_with_repetition(alt_count + 1, ploidy))
    end
  end

  def validate(_count, _number, _options), do: {:error, :invalid_cardinality}

  defp from_option(count, options, key, transform) do
    with {:ok, value} <- fetch_count(options, key) do
      compare(count, transform.(value))
    end
  end

  defp fetch_count(options, key) do
    case Keyword.fetch(options, key) do
      {:ok, value} when is_integer(value) and value >= 0 -> {:ok, value}
      _missing_or_invalid -> {:error, :missing_cardinality_context}
    end
  end

  defp compare(value, value), do: :ok
  defp compare(_actual, _expected), do: {:error, :invalid_cardinality}

  defp combinations_with_repetition(_items, 0), do: 1

  defp combinations_with_repetition(items, selections),
    do: choose(items + selections - 1, selections)

  defp choose(n, k) do
    k = min(k, n - k)

    if k == 0 do
      1
    else
      Enum.reduce(1..k, 1, fn i, result -> div(result * (n - k + i), i) end)
    end
  end
end
