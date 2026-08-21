defmodule VCF.Warning do
  @moduledoc "Machine-readable warning retained when permissive parsing recovers."

  @type t :: %__MODULE__{
          line: pos_integer() | nil,
          field: atom() | nil,
          key: String.t() | nil,
          value: term(),
          reason: atom()
        }

  defstruct line: nil,
            field: nil,
            key: nil,
            value: nil,
            reason: :invalid_value

  @doc "Formats a warning for display while retaining the struct for programmatic use."
  @spec message(t()) :: String.t()
  def message(%__MODULE__{} = warning) do
    ["warning", location(warning.line), field(warning.field, warning.key), "(#{warning.reason})"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp location(nil), do: nil
  defp location(line), do: "at line #{line}"

  defp field(nil, _key), do: nil
  defp field(field, nil), do: String.upcase(Atom.to_string(field))
  defp field(field, key), do: "#{String.upcase(Atom.to_string(field))}.#{key}"
end

defimpl String.Chars, for: VCF.Warning do
  def to_string(warning), do: VCF.Warning.message(warning)
end
