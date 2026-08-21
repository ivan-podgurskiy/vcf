defmodule VCF.Sample do
  @moduledoc "Ordered FORMAT values for one VCF sample."

  @type t :: %__MODULE__{name: String.t(), values: [VCF.Field.t()]}

  @enforce_keys [:name, :values]
  defstruct [:name, :values]
end
