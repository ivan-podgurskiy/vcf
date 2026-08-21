defmodule VCF.Validator do
  @moduledoc "Validates typed headers and records against their declared VCF version."

  alias VCF.Error
  alias VCF.Header
  alias VCF.Record
  alias VCF.Spec

  @doc "Returns all independently detectable header errors in source order."
  @spec validate_header(Header.t(), keyword()) :: [Error.t()]
  def validate_header(%Header{} = header, _options \\ []) do
    case Spec.for_version(header.version) do
      {:ok, profile} -> profile.validate_header(header)
      {:error, error} -> [error]
    end
  end

  @doc "Returns all independently detectable record errors."
  @spec validate_record(Record.t(), Header.t(), keyword()) :: [Error.t()]
  def validate_record(%Record{} = record, %Header{} = header, _options \\ []) do
    case Spec.for_version(header.version) do
      {:ok, profile} -> profile.validate_record(record, header)
      {:error, error} -> [error]
    end
  end

  @doc "Validates a header and an enumerable of records without stopping at the first error."
  @spec validate(Header.t(), Enumerable.t()) :: [Error.t()]
  def validate(%Header{} = header, records) do
    validate_header(header) ++ Enum.flat_map(records, &validate_record(&1, header))
  end
end
