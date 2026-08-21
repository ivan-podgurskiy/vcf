defmodule VCF.Spec.Common do
  @moduledoc false

  alias VCF.Validator.Alternate

  @spec allowed_number?(1..5, VCF.Spec.scope(), VCF.FieldDefinition.cardinality()) :: boolean()
  def allowed_number?(_minor, _scope, number) when is_integer(number) and number >= 0, do: true
  def allowed_number?(_minor, _scope, number) when number in [:a, :g, :variable], do: true
  def allowed_number?(minor, _scope, :r), do: minor >= 2
  def allowed_number?(minor, :format, :p), do: minor >= 4
  def allowed_number?(minor, :format, number) when number in [:la, :lr, :lg, :m], do: minor >= 5
  def allowed_number?(_minor, _scope, _number), do: false

  @spec allowed_alternate?(1..5, String.t()) :: boolean()
  def allowed_alternate?(minor, "*"), do: minor >= 2
  def allowed_alternate?(minor, "<*>"), do: minor >= 3
  def allowed_alternate?(minor, "<NON_REF>"), do: minor >= 5

  def allowed_alternate?(_minor, allele) do
    Alternate.validate(allele) == :ok
  end

  @spec partial_phasing?(VCF.Genotype.t()) :: boolean()
  def partial_phasing?(%VCF.Genotype{phasing: []}), do: false

  def partial_phasing?(%VCF.Genotype{phasing: [leading | rest]}) do
    leading != nil or rest |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length() > 1
  end
end
