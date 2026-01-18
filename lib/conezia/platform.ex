defmodule Conezia.Platform do
  @moduledoc """
  The Platform context for managing third-party applications and webhooks.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Platform.{Application, ApplicationUser, Webhook, WebhookDelivery}

  # Application functions

  def get_application(id), do: Repo.get(Application, id)

  def get_application!(id), do: Repo.get!(Application, id)

  def get_application_for_developer(id, developer_id) do
    Application
    |> where([a], a.id == ^id and a.developer_id == ^developer_id)
    |> Repo.one()
  end

  def list_applications(developer_id) do
    Application
    |> where([a], a.developer_id == ^developer_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  def create_application(attrs) do
    %Application{}
    |> Application.changeset(attrs)
    |> Repo.insert()
  end

  def update_application(%Application{} = application, attrs) do
    application
    |> Application.changeset(attrs)
    |> Repo.update()
  end

  def delete_application(%Application{} = application) do
    Repo.delete(application)
  end

  # ApplicationUser functions

  def get_application_user(id), do: Repo.get(ApplicationUser, id)

  def get_application_user_by_app_and_user(application_id, user_id) do
    ApplicationUser
    |> where([au], au.application_id == ^application_id and au.user_id == ^user_id and is_nil(au.revoked_at))
    |> Repo.one()
  end

  def list_authorized_apps_for_user(user_id) do
    ApplicationUser
    |> where([au], au.user_id == ^user_id and is_nil(au.revoked_at))
    |> preload(:application)
    |> order_by([au], desc: au.authorized_at)
    |> Repo.all()
  end

  def authorize_application(application_id, user_id, scopes) do
    attrs = %{
      application_id: application_id,
      user_id: user_id,
      granted_scopes: scopes
    }

    %ApplicationUser{}
    |> ApplicationUser.changeset(attrs)
    |> Repo.insert()
  end

  def update_application_user_scopes(%ApplicationUser{} = app_user, scopes) do
    app_user
    |> Ecto.Changeset.change(granted_scopes: scopes)
    |> Repo.update()
  end

  def revoke_application_access(%ApplicationUser{} = app_user) do
    app_user
    |> ApplicationUser.revoke_changeset()
    |> Repo.update()
  end

  def update_application_user_access(%ApplicationUser{} = app_user) do
    app_user
    |> ApplicationUser.update_access_changeset()
    |> Repo.update()
  end

  # Webhook functions

  def get_webhook(id), do: Repo.get(Webhook, id)

  def get_webhook!(id), do: Repo.get!(Webhook, id)

  def get_webhook_for_application(id, application_id) do
    Webhook
    |> where([w], w.id == ^id and w.application_id == ^application_id)
    |> Repo.one()
  end

  def list_webhooks(application_id) do
    Webhook
    |> where([w], w.application_id == ^application_id)
    |> order_by([w], desc: w.inserted_at)
    |> Repo.all()
  end

  def create_webhook(attrs) do
    %Webhook{}
    |> Webhook.changeset(attrs)
    |> Repo.insert()
  end

  def update_webhook(%Webhook{} = webhook, attrs) do
    webhook
    |> Webhook.changeset(attrs)
    |> Repo.update()
  end

  def delete_webhook(%Webhook{} = webhook) do
    Repo.delete(webhook)
  end

  # WebhookDelivery functions

  def list_webhook_deliveries(webhook_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    WebhookDelivery
    |> where([wd], wd.webhook_id == ^webhook_id)
    |> limit(^limit)
    |> order_by([wd], desc: wd.inserted_at)
    |> Repo.all()
  end

  def create_webhook_delivery(attrs) do
    %WebhookDelivery{}
    |> WebhookDelivery.changeset(attrs)
    |> Repo.insert()
  end
end
