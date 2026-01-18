defmodule Conezia.Accounts.User do
  @moduledoc """
  User schema for Conezia accounts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @tiers ~w(free personal professional enterprise)
  @default_notification_preferences %{
    "email" => true,
    "push" => true,
    "in_app" => true,
    "quiet_hours_start" => nil,
    "quiet_hours_end" => nil
  }

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar_url, :string
    field :timezone, :string, default: "UTC"
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime_usec
    field :tier, :string, default: "free"
    field :settings, :map, default: %{}
    field :onboarding_completed_at, :utc_datetime_usec
    field :notification_preferences, :map, default: @default_notification_preferences
    field :onboarding_state, :map, default: %{}

    has_many :auth_providers, Conezia.Accounts.AuthProvider
    has_many :entities, Conezia.Entities.Entity, foreign_key: :owner_id
    has_many :tags, Conezia.Entities.Tag
    has_many :groups, Conezia.Entities.Group
    has_many :reminders, Conezia.Reminders.Reminder
    has_many :external_accounts, Conezia.ExternalAccounts.ExternalAccount

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:email]
  @optional_fields [:name, :avatar_url, :timezone, :settings, :tier,
                    :onboarding_completed_at, :notification_preferences, :onboarding_state]

  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_email()
    |> validate_timezone()
    |> validate_inclusion(:tier, @tiers)
  end

  def preferences_changeset(user, attrs) do
    user
    |> cast(attrs, [:settings, :notification_preferences])
    |> validate_notification_preferences()
  end

  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:password])
    |> validate_password()
    |> hash_password()
  end

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_password()
    |> hash_password()
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 254)
    |> unsafe_validate_unique(:email, Conezia.Repo)
    |> unique_constraint(:email)
    |> update_change(:email, &String.downcase/1)
  end

  defp validate_timezone(changeset) do
    validate_change(changeset, :timezone, fn :timezone, tz ->
      case DateTime.now(tz) do
        {:ok, _} -> []
        {:error, _} -> [timezone: "must be a valid IANA timezone"]
      end
    end)
  end

  defp validate_notification_preferences(changeset) do
    validate_change(changeset, :notification_preferences, fn :notification_preferences, prefs ->
      cond do
        not is_map(prefs) -> [notification_preferences: "must be a map"]
        prefs["quiet_hours_start"] && !valid_time?(prefs["quiet_hours_start"]) ->
          [notification_preferences: "quiet_hours_start must be HH:MM format"]
        prefs["quiet_hours_end"] && !valid_time?(prefs["quiet_hours_end"]) ->
          [notification_preferences: "quiet_hours_end must be HH:MM format"]
        true -> []
      end
    end)
  end

  defp valid_time?(time) when is_binary(time) do
    Regex.match?(~r/^([01]?[0-9]|2[0-3]):[0-5][0-9]$/, time)
  end
  defp valid_time?(_), do: false

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> validate_format(:password, ~r/[a-z]/, message: "must contain a lowercase letter")
    |> validate_format(:password, ~r/[A-Z]/, message: "must contain an uppercase letter")
    |> validate_format(:password, ~r/[0-9]/, message: "must contain a number")
  end

  defp hash_password(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(changeset, :hashed_password, Argon2.hash_pwd_salt(password))
      _ ->
        changeset
    end
  end

  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Argon2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end

  def valid_tiers, do: @tiers
end
