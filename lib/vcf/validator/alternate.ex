defmodule VCF.Validator.Alternate do
  @moduledoc false

  alias VCF.Error

  @ordinary ~r{^[ACGTNacgtn]+$}
  @symbolic ~r{^<[A-Za-z0-9_.:*]+>$}
  @breakend_local ~r{^[ACGTNacgtn.]+$}

  @spec validate(String.t(), keyword()) :: :ok | {:error, Error.t()}
  def validate(allele, options \\ []) do
    if valid?(allele) do
      :ok
    else
      {:error,
       %Error{
         kind: :invalid_value,
         line: Keyword.get(options, :line),
         field: :alt,
         value: allele,
         reason: :invalid_allele
       }}
    end
  end

  defp valid?("*"), do: true

  defp valid?(allele) when is_binary(allele) do
    Regex.match?(@ordinary, allele) or
      Regex.match?(@symbolic, allele) or
      breakend?(allele)
  end

  defp valid?(_allele), do: false

  defp breakend?(allele) do
    case first_bracket(allele) do
      :nomatch ->
        false

      {index, 1} ->
        <<prefix::binary-size(index), bracket::binary-size(1), rest::binary>> = allele

        case :binary.match(rest, bracket) do
          {remote_size, 1} ->
            <<remote::binary-size(remote_size), _closing::binary-size(1), suffix::binary>> = rest
            local = prefix <> suffix

            prefix == "" != (suffix == "") and
              Regex.match?(@breakend_local, local) and
              no_brackets?(remote) and
              no_brackets?(suffix) and
              valid_remote?(remote)

          :nomatch ->
            false
        end
    end
  end

  defp first_bracket(allele) do
    matches = :binary.matches(allele, "[") ++ :binary.matches(allele, "]")

    case matches do
      [] -> :nomatch
      matches -> Enum.min_by(matches, &elem(&1, 0))
    end
  end

  defp no_brackets?(value) do
    :binary.match(value, "[") == :nomatch and :binary.match(value, "]") == :nomatch
  end

  defp valid_remote?(remote) do
    case List.pop_at(String.split(remote, ":"), -1) do
      {position, chromosome_parts} when chromosome_parts != [] ->
        chromosome = Enum.join(chromosome_parts, ":")

        case Integer.parse(position) do
          {number, ""} when number >= 0 -> chromosome != ""
          _failure -> false
        end

      _invalid ->
        false
    end
  end
end
