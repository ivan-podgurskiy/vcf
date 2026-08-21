defmodule VCF.Record do
  @moduledoc "A typed VCF data record."

  @type filter_state :: :pass | nil | [String.t()]
  @type t :: %__MODULE__{
          chrom: String.t(),
          pos: integer(),
          ids: [String.t()],
          ref: String.t(),
          alt: [String.t()],
          qual: float() | :nan | :positive_infinity | :negative_infinity | nil,
          filter: filter_state(),
          info: [VCF.Field.t()],
          format: [String.t()],
          samples: [VCF.Sample.t()],
          line: pos_integer() | nil,
          warnings: [VCF.Warning.t()],
          raw: String.t() | nil
        }

  @enforce_keys [:chrom, :pos, :ref]
  defstruct [
    :chrom,
    :pos,
    :ref,
    :qual,
    :filter,
    :line,
    :raw,
    ids: [],
    alt: [],
    info: [],
    format: [],
    samples: [],
    warnings: []
  ]
end
