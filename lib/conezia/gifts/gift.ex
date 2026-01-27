defmodule Conezia.Gifts.Gift do
  @moduledoc """
  Gift schema for tracking gift ideas, purchases, and giving for connections.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(idea purchased wrapped given)
  @occasions ~w(birthday christmas holiday anniversary graduation wedding baby_shower housewarming other)

  schema "gifts" do
    field :name, :string
    field :name_encrypted, Conezia.Encrypted.Binary
    field :description, :string
    field :description_encrypted, Conezia.Encrypted.Binary
    field :status, :string, default: "idea"
    field :occasion, :string
    field :occasion_date, :date
    field :budget_cents, :integer
    field :actual_cost_cents, :integer
    field :url, :string
    field :notes, :string
    field :notes_encrypted, Conezia.Encrypted.Binary
    field :given_at, :utc_datetime_usec

    belongs_to :user, Conezia.Accounts.User
    belongs_to :entity, Conezia.Entities.Entity
    belongs_to :reminder, Conezia.Reminders.Reminder

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:name, :status, :occasion, :user_id, :entity_id]
  @optional_fields [
    :description, :occasion_date, :budget_cents, :actual_cost_cents,
    :url, :notes, :given_at, :reminder_id
  ]

  def changeset(gift, attrs) do
    gift
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:occasion, @occasions)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 2000)
    |> validate_length(:notes, max: 5000)
    |> validate_number(:budget_cents, greater_than_or_equal_to: 0)
    |> validate_number(:actual_cost_cents, greater_than_or_equal_to: 0)
    |> validate_url(:url)
    |> encrypt_fields()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:entity_id)
    |> foreign_key_constraint(:reminder_id)
  end

  defp encrypt_fields(changeset) do
    changeset
    |> maybe_encrypt(:name, :name_encrypted)
    |> maybe_encrypt(:description, :description_encrypted)
    |> maybe_encrypt(:notes, :notes_encrypted)
  end

  defp maybe_encrypt(changeset, field, encrypted_field) do
    case get_change(changeset, field) do
      nil -> changeset
      value -> put_change(changeset, encrypted_field, value)
    end
  end

  def status_changeset(gift, new_status) do
    gift
    |> change(status: new_status)
    |> maybe_set_given_at(new_status)
    |> validate_inclusion(:status, @statuses)
  end

  defp maybe_set_given_at(changeset, "given"), do: put_change(changeset, :given_at, DateTime.utc_now())
  defp maybe_set_given_at(changeset, _), do: changeset

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) -> []
        _ -> [{field, "must be a valid URL"}]
      end
    end)
  end

  def valid_statuses, do: @statuses
  def valid_occasions, do: @occasions
end
