defmodule VCF do
  @moduledoc """
  Parse, validate, stream, transform, and write Variant Call Format files.
  """

  @supported_versions ~w(4.1 4.2 4.3 4.4 4.5)

  @doc "Returns the supported VCF specification versions."
  @spec supported_versions() :: [String.t()]
  def supported_versions, do: @supported_versions
end
