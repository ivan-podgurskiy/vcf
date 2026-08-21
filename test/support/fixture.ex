defmodule VCF.Test.Fixture do
  @moduledoc false

  def path(version) do
    Path.expand("../fixtures/v#{String.replace(version, ".", "_")}/spec.vcf", __DIR__)
  end
end
