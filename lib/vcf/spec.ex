defmodule VCF.Spec do
  @moduledoc "Version-profile selection for the supported VCF specifications."

  alias VCF.Error
  alias VCF.Header
  alias VCF.Record
  alias VCF.Version

  @type scope :: :info | :format

  @callback minor() :: 1..5
  @callback allowed_number?(scope(), VCF.FieldDefinition.cardinality()) :: boolean()
  @callback allowed_alternate?(String.t()) :: boolean()
  @callback validate_header(Header.t()) :: [Error.t()]
  @callback validate_record(Record.t(), Header.t()) :: [Error.t()]

  @doc "Returns the explicit rules module for a supported version."
  @spec for_version(Version.t()) :: {:ok, module()} | {:error, Error.t()}
  def for_version(%Version{major: 4, minor: 1}), do: profile(VCF.Spec.V4_1)
  def for_version(%Version{major: 4, minor: 2}), do: profile(VCF.Spec.V4_2)
  def for_version(%Version{major: 4, minor: 3}), do: profile(VCF.Spec.V4_3)
  def for_version(%Version{major: 4, minor: 4}), do: profile(VCF.Spec.V4_4)
  def for_version(%Version{major: 4, minor: 5}), do: profile(VCF.Spec.V4_5)

  def for_version(version) do
    {:error,
     %Error{
       kind: :unsupported_version,
       value: version,
       reason: :supported_versions_are_4_1_through_4_5
     }}
  end

  defp profile(module) do
    {:module, ^module} = Code.ensure_loaded(module)
    {:ok, module}
  end
end
