defmodule Conezia.Validators.TagValidator do
  @moduledoc """
  Validation rules for tag data.
  """
  import Ecto.Changeset
  import Ecto.Query

  @colors ~w(red orange yellow green blue purple pink gray)
  @max_tags_per_user 100

  def validate_name(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 50)
    |> validate_format(:name, ~r/^[\p{L}\p{N}\s\-_]+$/u,
        message: "can only contain letters, numbers, spaces, hyphens, and underscores")
    |> validate_not_blank(:name)
    |> unique_constraint([:user_id, :name],
        message: "tag with this name already exists")
  end

  def validate_color(changeset) do
    validate_change(changeset, :color, fn :color, color ->
      # Allow hex colors or predefined color names
      cond do
        color in @colors ->
          []
        Regex.match?(~r/^#[0-9A-Fa-f]{6}$/, color) ->
          []
        true ->
          [color: "must be a valid hex color or one of: #{Enum.join(@colors, ", ")}"]
      end
    end)
  end

  def validate_description(changeset) do
    validate_length(changeset, :description, max: 255)
  end

  def validate_tag_limit(user_id) do
    count = Conezia.Repo.aggregate(
      from(t in Conezia.Entities.Tag, where: t.user_id == ^user_id),
      :count
    )

    if count >= @max_tags_per_user do
      {:error, "maximum of #{@max_tags_per_user} tags allowed"}
    else
      :ok
    end
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

  def colors, do: @colors
  def max_tags_per_user, do: @max_tags_per_user
end
