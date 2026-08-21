defmodule VCF.Document do
  @moduledoc "A fully collected VCF header, records, and warnings."

  @type t :: %__MODULE__{
          header: VCF.Header.t(),
          records: [VCF.Record.t()],
          warnings: [VCF.Warning.t()]
        }

  @enforce_keys [:header, :records]
  defstruct [:header, records: [], warnings: []]
end
