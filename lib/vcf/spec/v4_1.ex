defmodule VCF.Spec.V4_1 do
  @moduledoc "Validation profile for VCF 4.1."
  @behaviour VCF.Spec

  def minor, do: 1
  def allowed_number?(scope, number), do: VCF.Spec.Common.allowed_number?(minor(), scope, number)
  def allowed_alternate?(allele), do: VCF.Spec.Common.allowed_alternate?(minor(), allele)
  def validate_header(header), do: VCF.Validator.Header.validate(header, __MODULE__)

  def validate_record(record, header),
    do: VCF.Validator.Record.validate(record, header, __MODULE__)
end
