defmodule VCF.Genotype do
  @moduledoc """
  A typed VCF genotype with arbitrary ploidy and per-allele phasing.

  Each phasing entry is the optional separator prefix for the allele at the
  same position. This losslessly represents ordinary and VCF 4.4 partial
  phasing.

      iex> {:ok, genotype} = VCF.Genotype.parse("0|1/2")
      iex> genotype.alleles
      [0, 1, 2]
      iex> genotype.phasing
      [nil, :phased, :unphased]
      iex> VCF.Genotype.encode(genotype)
      {:ok, "0|1/2"}
  """

  alias VCF.Error

  @type allele :: non_neg_integer() | nil
  @type phase :: :phased | :unphased | nil
  @type t :: %__MODULE__{alleles: [allele()], phasing: [phase()]}

  @enforce_keys [:alleles, :phasing]
  defstruct [:alleles, :phasing]

  @token ~r{([/|]?)([.]|[0-9]+)}

  @doc "Parses a GT value, including VCF 4.4 partial-phasing prefix notation."
  @spec parse(String.t()) :: {:ok, t()} | {:error, Error.t()}
  def parse(""), do: error("", :empty_genotype)

  def parse(value) when is_binary(value) do
    tokens = Regex.scan(@token, value, capture: :all_but_first)

    with true <- tokens != [],
         true <- reconstructed(tokens) == value,
         {:ok, phasing} <- parse_phasing(tokens) do
      alleles = Enum.map(tokens, fn [_separator, allele] -> parse_allele(allele) end)
      {:ok, %__MODULE__{alleles: alleles, phasing: phasing}}
    else
      _failure -> error(value, :invalid_syntax)
    end
  end

  def parse(value), do: error(value, :invalid_syntax)

  @doc "Encodes a genotype to canonical GT text."
  @spec encode(t()) :: {:ok, String.t()} | {:error, Error.t()}
  def encode(%__MODULE__{alleles: [], phasing: _phasing} = genotype) do
    error(genotype, :empty_genotype)
  end

  def encode(%__MODULE__{alleles: alleles, phasing: phasing} = genotype) do
    with true <- length(alleles) == length(phasing) || :phasing_length_mismatch,
         true <- Enum.all?(alleles, &valid_allele?/1) || :invalid_allele,
         true <- valid_phasing?(phasing) || :missing_separator do
      encoded =
        alleles
        |> Enum.zip(phasing)
        |> Enum.map_join(fn {allele, phase} -> phase_prefix(phase) <> encode_allele(allele) end)

      {:ok, encoded}
    else
      reason when is_atom(reason) -> error(genotype, reason)
    end
  end

  defp reconstructed(tokens), do: Enum.map_join(tokens, &Enum.join/1)

  defp parse_phasing([[first_separator, _allele] | rest]) do
    with {:ok, first} <- parse_phase(first_separator),
         true <- Enum.all?(rest, fn [separator, _allele] -> separator != "" end) do
      {:ok, [first | Enum.map(rest, fn [separator, _allele] -> phase(separator) end)]}
    else
      _failure -> :error
    end
  end

  defp parse_phase(""), do: {:ok, nil}
  defp parse_phase(separator) when separator in ["/", "|"], do: {:ok, phase(separator)}

  defp phase("/"), do: :unphased
  defp phase("|"), do: :phased

  defp parse_allele("."), do: nil
  defp parse_allele(value), do: String.to_integer(value)

  defp valid_allele?(nil), do: true
  defp valid_allele?(allele), do: is_integer(allele) and allele >= 0

  defp valid_phasing?([first | rest]) do
    first in [nil, :phased, :unphased] and
      Enum.all?(rest, &(&1 in [:phased, :unphased]))
  end

  defp phase_prefix(nil), do: ""
  defp phase_prefix(:phased), do: "|"
  defp phase_prefix(:unphased), do: "/"

  defp encode_allele(nil), do: "."
  defp encode_allele(allele), do: Integer.to_string(allele)

  defp error(value, reason) do
    {:error,
     %Error{
       kind: :invalid_genotype,
       field: :genotype,
       value: value,
       reason: reason
     }}
  end
end
