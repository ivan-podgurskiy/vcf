defmodule VCF.Validator.Record do
  @moduledoc false

  alias VCF.Error
  alias VCF.Field
  alias VCF.FieldDefinition
  alias VCF.Genotype
  alias VCF.Header
  alias VCF.Record
  alias VCF.Sample
  alias VCF.Spec.Common
  alias VCF.Validator.Cardinality

  @spec validate(Record.t(), Header.t(), module()) :: [Error.t()]
  def validate(%Record{} = record, %Header{} = header, profile) do
    validate_fixed(record, profile) ++
      validate_alternates(record, profile) ++
      validate_filters(record, header) ++
      validate_info(record, header, profile) ++
      validate_format(record, header, profile)
  end

  defp validate_fixed(record, profile) do
    []
    |> add_unless(record.chrom != "", record, :chrom, nil, record.chrom, :empty_value)
    |> add_unless(
      valid_contig_name?(record.chrom, profile),
      record,
      :chrom,
      nil,
      record.chrom,
      :invalid_contig_name
    )
    |> add_unless(
      is_integer(record.pos) and record.pos > 0,
      record,
      :pos,
      nil,
      record.pos,
      :must_be_positive
    )
    |> add_unless(record.ref != "", record, :ref, nil, record.ref, :empty_value)
    |> add_unless(Enum.all?(record.ids, &(&1 != "")), record, :id, nil, record.ids, :empty_value)
    |> add_unless(valid_qual?(record.qual), record, :qual, nil, record.qual, :invalid_qual)
  end

  defp validate_alternates(record, profile) do
    Enum.flat_map(record.alt, fn allele ->
      if profile.allowed_alternate?(allele) do
        []
      else
        [error(record, :alt, nil, allele, :unsupported_alternate)]
      end
    end)
  end

  defp validate_filters(%Record{filter: filters} = record, header) when is_list(filters) do
    Enum.flat_map(filters, fn filter ->
      cond do
        filter == "PASS" ->
          [error(record, :filter, filter, filter, :pass_must_be_standalone)]

        is_nil(Header.definition(header, :filter, filter)) ->
          [error(record, :filter, filter, filter, :undeclared_field)]

        true ->
          []
      end
    end)
  end

  defp validate_filters(_record, _header), do: []

  defp validate_info(record, header, profile) do
    Enum.flat_map(record.info, fn field ->
      case Header.definition(header, :info, field.key) do
        %FieldDefinition{} = definition ->
          validate_field(field, definition, record, :info, profile,
            alt_count: length(record.alt),
            ploidy: 2
          )

        nil ->
          [error(record, :info, field.key, field.value, :undeclared_field)]
      end
    end)
  end

  defp validate_format(record, header, profile) do
    key_errors =
      []
      |> add_unless(
        gt_first?(record.format),
        record,
        :format,
        "GT",
        record.format,
        :gt_must_be_first
      )
      |> Kernel.++(undeclared_format_errors(record, header))

    sample_count_errors =
      if length(record.samples) == length(header.samples) do
        []
      else
        [error(record, :samples, nil, length(record.samples), :sample_count_mismatch)]
      end

    key_errors ++
      sample_count_errors ++
      Enum.flat_map(record.samples, &validate_sample(&1, record, header, profile))
  end

  defp undeclared_format_errors(record, header) do
    Enum.flat_map(record.format, fn key ->
      if Header.definition(header, :format, key) do
        []
      else
        [error(record, :format, key, key, :undeclared_field)]
      end
    end)
  end

  defp validate_sample(%Sample{} = sample, record, header, profile) do
    genotype = sample.values |> Enum.find(&(&1.key == "GT")) |> genotype_value()
    ploidy = if genotype, do: length(genotype.alleles), else: 2
    local_alt_count = local_alt_count(sample)

    Enum.flat_map(sample.values, fn field ->
      definition_errors =
        case Header.definition(header, :format, field.key) do
          %FieldDefinition{} = definition ->
            validate_field(field, definition, record, :format, profile,
              alt_count: length(record.alt),
              ploidy: ploidy,
              local_alt_count: local_alt_count,
              modification_count: value_count(field.value)
            )

          nil ->
            []
        end

      genotype_errors =
        case field do
          %Field{key: "GT", value: %Genotype{} = gt} -> validate_genotype(gt, record, profile)
          _other -> []
        end

      definition_errors ++ genotype_errors
    end)
  end

  defp validate_field(%Field{value: nil}, _definition, _record, _scope, _profile, _options),
    do: []

  defp validate_field(field, definition, record, scope, profile, options) do
    type_errors =
      if valid_type?(field.value, definition.type, field.key) do
        []
      else
        [error(record, scope, field.key, field.value, :invalid_type)]
      end

    cardinality_errors =
      case Cardinality.validate(value_count(field.value), definition.number, options) do
        :ok -> []
        {:error, reason} -> [error(record, scope, field.key, field.value, reason)]
      end

    range_errors =
      if valid_numeric_range?(field.value, definition.type, profile.minor()) do
        []
      else
        reason =
          if definition.type == :integer, do: :integer_out_of_range, else: :float_out_of_range

        [error(record, scope, field.key, field.value, reason)]
      end

    type_errors ++ cardinality_errors ++ range_errors
  end

  defp validate_genotype(genotype, record, profile) do
    allele_errors =
      if Enum.all?(genotype.alleles, &valid_allele_index?(&1, length(record.alt))) do
        []
      else
        [error(record, :format, "GT", genotype, :genotype_allele_out_of_bounds)]
      end

    phasing_errors =
      if profile.minor() < 4 and Common.partial_phasing?(genotype) do
        [error(record, :format, "GT", genotype, :partial_phasing_not_supported)]
      else
        []
      end

    allele_errors ++ phasing_errors
  end

  defp valid_allele_index?(nil, _alt_count), do: true

  defp valid_allele_index?(index, alt_count),
    do: is_integer(index) and index >= 0 and index <= alt_count

  defp genotype_value(nil), do: nil
  defp genotype_value(%Field{value: %Genotype{} = genotype}), do: genotype
  defp genotype_value(_field), do: nil

  defp local_alt_count(%Sample{values: values}) do
    case Enum.find(values, &(&1.key == "LAA")) do
      %Field{value: value} when is_list(value) -> length(value)
      _missing -> 0
    end
  end

  defp gt_first?(keys), do: "GT" not in keys or List.first(keys) == "GT"

  defp valid_contig_name?(chrom, profile) do
    profile.minor() < 3 or chrom == "" or Regex.match?(~r/^[^\s:;,=]+$/u, chrom)
  end

  defp valid_qual?(nil), do: true
  defp valid_qual?(:nan), do: true
  defp valid_qual?(:positive_infinity), do: true
  defp valid_qual?(value), do: is_number(value) and value >= 0

  defp valid_type?(%Genotype{}, _type, "GT"), do: true
  defp valid_type?(nil, _type, _key), do: true

  defp valid_type?(values, type, key) when is_list(values),
    do: Enum.all?(values, &valid_type?(&1, type, key))

  defp valid_type?(true, :flag, _key), do: true
  defp valid_type?(value, :integer, _key), do: is_integer(value)

  defp valid_type?(value, :float, _key),
    do: is_number(value) or value in [:nan, :positive_infinity, :negative_infinity]

  defp valid_type?(value, :character, _key), do: is_binary(value) and String.length(value) == 1
  defp valid_type?(value, :string, _key), do: is_binary(value)
  defp valid_type?(_value, _type, _key), do: false

  defp valid_numeric_range?(_value, _type, minor) when minor < 3, do: true
  defp valid_numeric_range?(nil, _type, _minor), do: true

  defp valid_numeric_range?(values, type, minor) when is_list(values),
    do: Enum.all?(values, &valid_numeric_range?(&1, type, minor))

  defp valid_numeric_range?(value, :integer, _minor),
    do: is_integer(value) and value >= -2_147_483_648 and value <= 2_147_483_647

  defp valid_numeric_range?(value, :float, _minor) when is_number(value),
    do: abs(value) <= 3.402_823_5e38

  defp valid_numeric_range?(value, :float, _minor),
    do: value in [:nan, :positive_infinity, :negative_infinity]

  defp valid_numeric_range?(_value, _type, _minor), do: true

  defp value_count(true), do: 0
  defp value_count(values) when is_list(values), do: length(values)
  defp value_count(_scalar), do: 1

  defp add_unless(errors, true, _record, _field, _key, _value, _reason), do: errors

  defp add_unless(errors, false, record, field, key, value, reason),
    do: errors ++ [error(record, field, key, value, reason)]

  defp error(record, field, key, value, reason) do
    %Error{
      kind: :invalid_record,
      line: record.line,
      field: field,
      key: key,
      value: value,
      reason: reason
    }
  end
end
