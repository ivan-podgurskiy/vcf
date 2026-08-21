defmodule VCF.Header do
  @moduledoc "A parsed VCF header with ordered metadata and sample names."

  alias VCF.FieldDefinition
  alias VCF.Metadata

  @type column :: :chrom | :pos | :id | :ref | :alt | :qual | :filter | :info | :format
  @type t :: %__MODULE__{
          version: VCF.Version.t(),
          metadata: [Metadata.t()],
          columns: [column()],
          samples: [String.t()],
          warnings: [VCF.Warning.t()]
        }

  @enforce_keys [:version, :metadata, :columns]
  defstruct [:version, :metadata, :columns, samples: [], warnings: []]

  @doc "Returns the first declaration of `id` for the requested metadata kind."
  @spec definition(t(), :info | :format | :filter | :alt | :contig, String.t()) ::
          FieldDefinition.t() | Metadata.t() | nil
  def definition(%__MODULE__{metadata: metadata}, kind, id) do
    key = metadata_key(kind)

    Enum.find_value(metadata, fn
      %Metadata{key: ^key, value: %FieldDefinition{id: ^id} = definition} ->
        definition

      %Metadata{key: ^key, value: attributes} = entry when is_list(attributes) ->
        if List.keyfind(attributes, "ID", 0) == {"ID", id}, do: entry

      _entry ->
        nil
    end)
  end

  defp metadata_key(:info), do: "INFO"
  defp metadata_key(:format), do: "FORMAT"
  defp metadata_key(:filter), do: "FILTER"
  defp metadata_key(:alt), do: "ALT"
  defp metadata_key(:contig), do: "contig"
end
