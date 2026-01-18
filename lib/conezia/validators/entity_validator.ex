defmodule Conezia.Validators.EntityValidator do
  @moduledoc """
  Validation rules for entity-related data.
  """
  import Ecto.Changeset

  @entity_types ~w(person organization service thing animal abstract)

  def validate_type(changeset) do
    changeset
    |> validate_required([:type])
    |> validate_inclusion(:type, @entity_types,
        message: "must be one of: #{Enum.join(@entity_types, ", ")}")
  end

  def validate_name(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_not_blank(:name)
  end

  def validate_description(changeset) do
    validate_length(changeset, :description, max: 10_000)
  end

  def validate_metadata(changeset) do
    validate_change(changeset, :metadata, fn :metadata, metadata ->
      cond do
        !is_map(metadata) ->
          [metadata: "must be a valid JSON object"]
        byte_size(Jason.encode!(metadata)) > 65_536 ->
          [metadata: "must be less than 64KB when serialized"]
        true ->
          []
      end
    end)
  end

  defp validate_not_blank(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if String.trim(value) == "" do
        [{field, "cannot be blank"}]
      else
        []
      end
    end)
  end

  def entity_types, do: @entity_types
end
