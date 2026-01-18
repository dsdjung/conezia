defmodule Conezia.Validators.UserValidator do
  @moduledoc """
  Validation rules for user-related data.
  """
  import Ecto.Changeset

  @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  @password_rules [
    min_length: 8,
    max_length: 72,
    require_lowercase: true,
    require_uppercase: true,
    require_number: true,
    require_special: false
  ]

  def validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, @email_regex, message: "must be a valid email address")
    |> validate_length(:email, max: 254)
    |> update_change(:email, &String.downcase(&1))
    |> unsafe_validate_unique(:email, Conezia.Repo)
    |> unique_constraint(:email, message: "has already been taken")
  end

  def validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password,
        min: @password_rules[:min_length],
        max: @password_rules[:max_length]
       )
    |> validate_password_complexity()
  end

  defp validate_password_complexity(changeset) do
    changeset
    |> validate_format(:password, ~r/[a-z]/,
        message: "must contain at least one lowercase letter")
    |> validate_format(:password, ~r/[A-Z]/,
        message: "must contain at least one uppercase letter")
    |> validate_format(:password, ~r/[0-9]/,
        message: "must contain at least one number")
  end

  def validate_name(changeset) do
    changeset
    |> validate_length(:name, min: 1, max: 255)
    |> validate_format(:name, ~r/^[\p{L}\p{M}\s\-'\.]+$/u,
        message: "can only contain letters, spaces, hyphens, apostrophes, and periods")
  end

  def validate_timezone(changeset) do
    validate_change(changeset, :timezone, fn :timezone, tz ->
      if tz in Tzdata.zone_list() do
        []
      else
        [timezone: "must be a valid IANA timezone (e.g., 'America/New_York')"]
      end
    end)
  end

  def validate_avatar_url(changeset) do
    changeset
    |> validate_length(:avatar_url, max: 2048)
    |> validate_url(:avatar_url)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host}
            when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []
        _ ->
          [{field, "must be a valid HTTP(S) URL"}]
      end
    end)
  end

  def password_rules, do: @password_rules
end
