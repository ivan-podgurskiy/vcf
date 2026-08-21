defmodule VCF.Error do
  @moduledoc "Machine-readable error produced while parsing, validating, or writing VCF."

  @type t :: %__MODULE__{
          kind: atom(),
          line: pos_integer() | nil,
          column: pos_integer() | nil,
          field: atom() | nil,
          key: String.t() | nil,
          value: term(),
          reason: atom() | nil
        }

  defstruct kind: :invalid_value,
            line: nil,
            column: nil,
            field: nil,
            key: nil,
            value: nil,
            reason: nil

  @doc "Formats an error for display while retaining the struct for programmatic use."
  @spec message(t()) :: String.t()
  def message(%__MODULE__{} = error) do
    [Atom.to_string(error.kind), location(error), field(error), reason(error)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp location(%{line: nil}), do: nil
  defp location(%{line: line, column: nil}), do: "at line #{line}"
  defp location(%{line: line, column: column}), do: "at line #{line}, column #{column}"

  defp field(%{field: nil}), do: nil
  defp field(%{field: field, key: nil}), do: String.upcase(Atom.to_string(field))
  defp field(%{field: field, key: key}), do: "#{String.upcase(Atom.to_string(field))}.#{key}"

  defp reason(%{reason: nil}), do: nil
  defp reason(%{reason: reason}), do: "(#{reason})"
end

defimpl String.Chars, for: VCF.Error do
  def to_string(error), do: VCF.Error.message(error)
end
