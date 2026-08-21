defmodule VCF.ParseError do
  @moduledoc "Exception raised by bang APIs when VCF input cannot be parsed."

  defexception [:message, :error]

  @type t :: %__MODULE__{message: String.t(), error: VCF.Error.t()}

  @impl Exception
  @spec exception(VCF.Error.t()) :: t()
  def exception(%VCF.Error{} = error) do
    %__MODULE__{message: to_string(error), error: error}
  end
end
