defmodule Conezia.Accounts do
  @moduledoc """
  The Accounts context for user management and authentication.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Accounts.{User, AuthProvider, UserToken}

  # User functions

  def get_user(id), do: Repo.get(User, id)

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def get_user_by_email_and_password(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  def list_users(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    User
    |> limit(^limit)
    |> offset(^offset)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def update_user_preferences(%User{} = user, attrs) do
    user
    |> User.preferences_changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  def confirm_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now())
    |> Repo.update()
  end

  # Auth Provider functions

  def get_auth_provider(id), do: Repo.get(AuthProvider, id)

  def get_auth_provider_by_provider_uid(provider, provider_uid) do
    Repo.get_by(AuthProvider, provider: provider, provider_uid: provider_uid)
  end

  def list_auth_providers_for_user(user_id) do
    AuthProvider
    |> where([ap], ap.user_id == ^user_id)
    |> Repo.all()
  end

  def create_auth_provider(attrs) do
    %AuthProvider{}
    |> AuthProvider.changeset(attrs)
    |> Repo.insert()
  end

  def update_auth_provider(%AuthProvider{} = auth_provider, attrs) do
    auth_provider
    |> AuthProvider.changeset(attrs)
    |> Repo.update()
  end

  def delete_auth_provider(%AuthProvider{} = auth_provider) do
    Repo.delete(auth_provider)
  end

  def get_or_create_user_from_oauth(provider, provider_uid, user_attrs) do
    case get_auth_provider_by_provider_uid(provider, provider_uid) do
      nil ->
        create_user_from_oauth(provider, provider_uid, user_attrs)

      auth_provider ->
        {:ok, Repo.get!(User, auth_provider.user_id)}
    end
  end

  defp create_user_from_oauth(provider, provider_uid, user_attrs) do
    Repo.transaction(fn ->
      with {:ok, user} <- create_user_without_password(user_attrs),
           {:ok, _auth_provider} <- create_auth_provider(%{
             provider: provider,
             provider_uid: provider_uid,
             user_id: user.id
           }) do
        user
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp create_user_without_password(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now())
    |> Repo.insert()
  end

  # Session token functions

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_session_token(token) do
    Repo.delete_all(from t in UserToken, where: t.token == ^token)
    :ok
  end

  def delete_all_sessions_for_user(user) do
    Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id and t.context == "session")
    :ok
  end

  # Email verification tokens

  def generate_user_email_token(user, context) do
    {token, user_token} = UserToken.build_email_token(user, context)
    Repo.insert!(user_token)
    token
  end

  def verify_email_token(token, context) do
    case UserToken.verify_email_token_query(token, context) do
      {:ok, query} ->
        case Repo.one(query) do
          nil -> :error
          user -> {:ok, user}
        end

      :error ->
        :error
    end
  end

  def delete_email_token(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        Repo.delete_all(from t in UserToken, where: t.token == ^decoded_token and t.context == ^context)
        :ok

      :error ->
        :error
    end
  end

  # Authentication

  def authenticate_by_email_password(email, password) do
    case get_user_by_email_and_password(email, password) do
      nil -> {:error, :invalid_credentials}
      user -> {:ok, user}
    end
  end

  # Password reset

  def deliver_password_reset_instructions(email) do
    case get_user_by_email(email) do
      nil -> :ok  # Don't reveal if email exists
      user ->
        _token = generate_user_email_token(user, "reset_password")
        # In production, send email here
        :ok
    end
  end

  def reset_password_with_token(token, new_password) do
    case verify_email_token(token, "reset_password") do
      {:ok, user} ->
        user
        |> User.password_changeset(%{password: new_password})
        |> Repo.update()
        |> case do
          {:ok, user} ->
            delete_email_token(token, "reset_password")
            {:ok, user}
          error -> error
        end

      :error ->
        {:error, :invalid_token}
    end
  end

  # Email verification

  def verify_email_with_token(token) do
    case verify_email_token(token, "confirm") do
      {:ok, user} ->
        user
        |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now())
        |> Repo.update()
        |> case do
          {:ok, user} ->
            delete_email_token(token, "confirm")
            {:ok, user}
          error -> error
        end

      :error ->
        {:error, :invalid_token}
    end
  end

  # Onboarding

  def update_onboarding_step(%User{} = user, step, action) do
    onboarding_state = user.onboarding_state || %{}

    new_state = case action do
      "complete" -> Map.put(onboarding_state, step, true)
      "skip" -> Map.merge(onboarding_state, %{step => false, "#{step}_skipped" => true})
      _ -> onboarding_state
    end

    user
    |> Ecto.Changeset.change(onboarding_state: new_state)
    |> Repo.update()
  end

  def complete_onboarding(%User{} = user) do
    onboarding_state = Map.put(user.onboarding_state || %{}, "completed", true)

    user
    |> Ecto.Changeset.change(
      onboarding_state: onboarding_state,
      onboarding_completed_at: DateTime.utc_now()
    )
    |> Repo.update()
  end
end
