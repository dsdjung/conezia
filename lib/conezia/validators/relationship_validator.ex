defmodule Conezia.Validators.RelationshipValidator do
  @moduledoc """
  Validation rules for relationship data.
  """
  import Ecto.Changeset

  @relationship_types ~w(friend family colleague client vendor acquaintance service_provider other)
  @statuses ~w(active inactive archived)

  def validate_type(changeset) do
    validate_inclusion(changeset, :type, @relationship_types,
      message: "must be one of: #{Enum.join(@relationship_types, ", ")}")
  end

  def validate_strength(changeset) do
    changeset
    |> validate_number(:strength,
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: 100,
        message: "must be between 0 and 100")
  end

  def validate_status(changeset) do
    changeset
    |> validate_inclusion(:status, @statuses,
        message: "must be one of: #{Enum.join(@statuses, ", ")}")
  end

  def validate_health_threshold(changeset) do
    changeset
    |> validate_number(:health_threshold_days,
        greater_than: 0,
        less_than_or_equal_to: 365,
        message: "must be between 1 and 365 days")
  end

  def validate_started_at(changeset) do
    validate_change(changeset, :started_at, fn :started_at, date ->
      cond do
        Date.compare(date, Date.utc_today()) == :gt ->
          [started_at: "cannot be in the future"]
        Date.compare(date, ~D[1900-01-01]) == :lt ->
          [started_at: "must be after 1900-01-01"]
        true ->
          []
      end
    end)
  end

  def validate_notes(changeset) do
    validate_length(changeset, :notes, max: 5000)
  end

  def validate_unique_relationship(changeset) do
    changeset
    |> unique_constraint([:user_id, :entity_id],
        message: "relationship already exists for this entity")
  end

  def relationship_types, do: @relationship_types
  def statuses, do: @statuses
end
