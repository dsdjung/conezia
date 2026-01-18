defmodule Conezia.Accounts.UserToken do
  @moduledoc """
  User session and verification tokens.
  """
  use Ecto.Schema
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @rand_size 32

  # Token validity periods
  @session_validity_days 60
  @reset_password_validity_hours 1
  @confirm_email_validity_hours 24

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :user, Conezia.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", user_id: user.id}}
  end

  def build_email_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {Base.url_encode64(token, padding: false),
     %__MODULE__{token: token, context: context, sent_to: user.email, user_id: user.id}}
  end

  def verify_session_token_query(token) do
    query =
      from t in __MODULE__,
        where: t.token == ^token and t.context == "session",
        where: t.inserted_at > ago(@session_validity_days, "day"),
        join: u in assoc(t, :user),
        select: u

    {:ok, query}
  end

  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        validity_hours = case context do
          "reset_password" -> @reset_password_validity_hours
          "confirm" -> @confirm_email_validity_hours
          _ -> @confirm_email_validity_hours
        end

        query =
          from t in __MODULE__,
            where: t.token == ^decoded_token and t.context == ^context,
            where: t.inserted_at > ago(^validity_hours, "hour"),
            join: u in assoc(t, :user),
            select: u

        {:ok, query}

      :error ->
        :error
    end
  end
end
