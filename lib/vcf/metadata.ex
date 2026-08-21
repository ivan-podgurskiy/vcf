defmodule VCF.Metadata do
  @moduledoc "An ordered VCF header metadata entry."

  @type structured_attributes :: [{String.t(), String.t()}]
  @type value :: VCF.Version.t() | VCF.FieldDefinition.t() | structured_attributes() | String.t()

  @type t :: %__MODULE__{
          key: String.t(),
          value: value(),
          raw: String.t() | nil,
          line: pos_integer() | nil
        }

  @enforce_keys [:key, :value]
  defstruct [:key, :value, :raw, :line]
end
