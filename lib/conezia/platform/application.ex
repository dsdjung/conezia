defmodule Conezia.Platform.Application do
  @moduledoc """
  Platform application schema for third-party app registrations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending approved suspended)
  @scopes ~w(read:entities write:entities delete:entities read:communications
             write:communications read:reminders write:reminders read:profile write:profile)

  schema "applications" do
    field :name, :string
    field :description, :string
    field :logo_url, :string
    field :website_url, :string
    field :callback_urls, {:array, :string}, default: []
    field :api_key, :string, virtual: true
    field :api_key_hash, :string
    field :api_secret, :string, virtual: true
    field :api_secret_hash, :string
    field :scopes, {:array, :string}, default: []
    field :status, :string, default: "pending"

    belongs_to :developer, Conezia.Accounts.User
    has_many :application_users, Conezia.Platform.ApplicationUser
    has_many :webhooks, Conezia.Platform.Webhook

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:name, :developer_id]
  @optional_fields [:description, :logo_url, :website_url, :callback_urls, :scopes, :status]

  def changeset(application, attrs) do
    application
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 2, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_url(:logo_url)
    |> validate_url(:website_url)
    |> validate_callback_urls()
    |> validate_scopes()
    |> validate_inclusion(:status, @statuses)
    |> generate_api_credentials()
    |> foreign_key_constraint(:developer_id)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case value do
        nil -> []
        "" -> []
        url ->
          case URI.parse(url) do
            %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
              []
            _ ->
              [{field, "must be a valid URL"}]
          end
      end
    end)
  end

  defp validate_callback_urls(changeset) do
    validate_change(changeset, :callback_urls, fn :callback_urls, urls ->
      Enum.flat_map(urls, fn url ->
        case URI.parse(url) do
          %URI{scheme: "https", host: host} when not is_nil(host) -> []
          _ -> [callback_urls: "must all be valid HTTPS URLs"]
        end
      end)
    end)
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn :scopes, scopes ->
      invalid = scopes -- @scopes
      if invalid == [] do
        []
      else
        [scopes: "contains invalid scopes: #{inspect(invalid)}"]
      end
    end)
  end

  defp generate_api_credentials(changeset) do
    if get_change(changeset, :developer_id) && !get_field(changeset, :api_key_hash) do
      api_key = generate_key("ck_")
      api_secret = generate_key("cs_")

      changeset
      |> put_change(:api_key, api_key)
      |> put_change(:api_secret, api_secret)
      |> put_change(:api_key_hash, hash_key(api_key))
      |> put_change(:api_secret_hash, hash_key(api_secret))
    else
      changeset
    end
  end

  defp generate_key(prefix) do
    prefix <> (:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))
  end

  defp hash_key(key) do
    :crypto.hash(:sha256, key) |> Base.encode16(case: :lower)
  end

  def valid_scopes, do: @scopes
  def valid_statuses, do: @statuses
end
