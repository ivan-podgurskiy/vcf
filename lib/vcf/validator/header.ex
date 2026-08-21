defmodule VCF.Validator.Header do
  @moduledoc false

  alias VCF.Error
  alias VCF.FieldDefinition
  alias VCF.Header
  alias VCF.Metadata

  @id_pattern ~r/^[A-Za-z_][0-9A-Za-z_.]*$/

  @spec validate(Header.t(), module()) :: [Error.t()]
  def validate(%Header{} = header, profile) do
    {definition_errors, _seen} =
      Enum.reduce(header.metadata, {[], MapSet.new()}, fn metadata, {errors, seen} ->
        {new_errors, new_seen} = validate_metadata(metadata, profile, seen)
        {errors ++ new_errors, new_seen}
      end)

    definition_errors ++ validate_samples(header.samples)
  end

  defp validate_metadata(
         %Metadata{key: key, value: %FieldDefinition{} = definition} = entry,
         profile,
         seen
       )
       when key in ["INFO", "FORMAT"] do
    scope = if key == "INFO", do: :info, else: :format
    identity = {key, definition.id}

    errors =
      []
      |> append_if(
        profile.minor() >= 3 and MapSet.member?(seen, identity),
        entry,
        scope,
        definition,
        :duplicate_definition
      )
      |> append_if(
        not valid_id?(definition.id, profile.minor()),
        entry,
        scope,
        definition,
        :invalid_id
      )
      |> append_if(
        not profile.allowed_number?(scope, definition.number),
        entry,
        scope,
        definition,
        :unsupported_number
      )
      |> append_if(
        profile.minor() == 1 and scope == :info and definition.attributes != [],
        entry,
        scope,
        definition,
        :unsupported_attributes
      )
      |> append_if(
        definition.type == :flag and definition.number != 0,
        entry,
        scope,
        definition,
        :flag_requires_number_zero
      )
      |> append_if(
        scope == :format and definition.type == :flag,
        entry,
        scope,
        definition,
        :flag_not_allowed_in_format
      )
      |> append_if(
        is_nil(definition.description) or definition.description == "",
        entry,
        scope,
        definition,
        :missing_description
      )

    {errors, MapSet.put(seen, identity)}
  end

  defp validate_metadata(%Metadata{key: key, value: attributes} = entry, profile, seen)
       when is_list(attributes) do
    case List.keyfind(attributes, "ID", 0) do
      {"ID", id} when key in ["FILTER", "ALT", "contig", "META"] ->
        identity = {key, id}

        errors =
          []
          |> append_structured_if(
            key == "META" and profile.minor() < 3,
            entry,
            id,
            :unsupported_metadata
          )
          |> append_structured_if(
            profile.minor() >= 3 and MapSet.member?(seen, identity),
            entry,
            id,
            :duplicate_definition
          )
          |> append_structured_if(
            profile.minor() >= 3 and not Regex.match?(@id_pattern, id),
            entry,
            id,
            :invalid_id
          )

        {errors, MapSet.put(seen, identity)}

      _not_identified ->
        {[], seen}
    end
  end

  defp validate_metadata(_entry, _profile, seen), do: {[], seen}

  defp valid_id?(id, minor) when minor >= 3, do: Regex.match?(@id_pattern, id)
  defp valid_id?(id, _minor), do: is_binary(id) and id != ""

  defp append_if(errors, true, entry, scope, definition, reason) do
    errors ++
      [
        %Error{
          kind: :invalid_header,
          line: entry.line,
          field: scope,
          key: definition.id,
          value: definition,
          reason: reason
        }
      ]
  end

  defp append_if(errors, false, _entry, _scope, _definition, _reason), do: errors

  defp append_structured_if(errors, true, entry, id, reason) do
    errors ++
      [
        %Error{
          kind: :invalid_header,
          line: entry.line,
          field: :metadata,
          key: id,
          value: entry.value,
          reason: reason
        }
      ]
  end

  defp append_structured_if(errors, false, _entry, _id, _reason), do: errors

  defp validate_samples(samples) do
    {_seen, errors} =
      Enum.reduce(samples, {MapSet.new(), []}, fn sample, {seen, errors} ->
        cond do
          sample == "" ->
            {MapSet.put(seen, sample), errors ++ [sample_error(sample, :empty_sample)]}

          MapSet.member?(seen, sample) ->
            {seen, errors ++ [sample_error(sample, :duplicate_sample)]}

          true ->
            {MapSet.put(seen, sample), errors}
        end
      end)

    errors
  end

  defp sample_error(sample, reason) do
    %Error{kind: :invalid_header, field: :samples, value: sample, reason: reason}
  end
end
