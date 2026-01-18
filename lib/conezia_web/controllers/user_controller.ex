defmodule ConeziaWeb.UserController do
  @moduledoc """
  Controller for user management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Accounts
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/users/me
  Get the current authenticated user.
  """
  def show(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    conn
    |> put_status(:ok)
    |> json(%{data: user_json(user)})
  end

  @doc """
  PUT /api/v1/users/me
  Update the current user.
  """
  def update(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    case Accounts.update_user(user, params) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{data: user_json(updated_user)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
    end
  end

  @doc """
  DELETE /api/v1/users/me
  Delete the current user's account.
  """
  def delete(conn, %{"password" => password, "confirmation" => "DELETE MY ACCOUNT"}) do
    user = Guardian.Plug.current_resource(conn)

    case Accounts.authenticate_by_email_password(user.email, password) do
      {:ok, _user} ->
        case Accounts.delete_user(user) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{
              meta: %{
                message: "Account deleted successfully"
              }
            })

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(ErrorHelpers.unauthorized("Invalid password.", conn.request_path))
    end
  end

  def delete(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request(
      "Password and confirmation phrase 'DELETE MY ACCOUNT' are required.",
      conn.request_path
    ))
  end

  @doc """
  GET /api/v1/users/me/preferences
  Get the current user's preferences.
  """
  def get_preferences(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    conn
    |> put_status(:ok)
    |> json(%{data: preferences_json(user)})
  end

  @doc """
  PUT /api/v1/users/me/preferences
  Update the current user's preferences.
  """
  def update_preferences(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    case Accounts.update_user_preferences(user, params) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{data: preferences_json(updated_user)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
    end
  end

  @doc """
  GET /api/v1/users/me/notifications
  Get the current user's notification settings.
  """
  def get_notifications(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    conn
    |> put_status(:ok)
    |> json(%{data: user.notification_preferences || default_notifications()})
  end

  @doc """
  PUT /api/v1/users/me/notifications
  Update the current user's notification settings.
  """
  def update_notifications(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    case Accounts.update_user(user, %{notification_preferences: params}) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{data: updated_user.notification_preferences})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
    end
  end

  @doc """
  GET /api/v1/users/me/onboarding
  Get the current user's onboarding status.
  """
  def get_onboarding(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    conn
    |> put_status(:ok)
    |> json(%{data: onboarding_json(user)})
  end

  @doc """
  PUT /api/v1/users/me/onboarding
  Update the current user's onboarding progress.
  """
  def update_onboarding(conn, %{"step" => step, "action" => action}) do
    user = Guardian.Plug.current_resource(conn)

    case Accounts.update_onboarding_step(user, step, action) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{data: onboarding_json(updated_user)})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(ErrorHelpers.bad_request(reason, conn.request_path))
    end
  end

  def update_onboarding(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("Step and action are required.", conn.request_path))
  end

  @doc """
  POST /api/v1/users/me/onboarding/complete
  Mark onboarding as complete.
  """
  def complete_onboarding(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    case Accounts.complete_onboarding(user) do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          data: onboarding_json(updated_user),
          meta: %{message: "Onboarding completed"}
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(ErrorHelpers.bad_request(reason, conn.request_path))
    end
  end

  @doc """
  GET /api/v1/users/me/authorized-apps
  List all third-party apps authorized by the user.
  """
  def list_authorized_apps(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    app_users = Conezia.Platform.list_authorized_apps_for_user(user.id)

    conn
    |> put_status(:ok)
    |> json(%{data: Enum.map(app_users, &authorized_app_json/1)})
  end

  @doc """
  GET /api/v1/users/me/authorized-apps/:app_id
  Get details of an authorized app.
  """
  def get_authorized_app(conn, %{"app_id" => app_id}) do
    user = Guardian.Plug.current_resource(conn)

    case Conezia.Platform.get_application_user_by_app_and_user(app_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("authorized app", app_id, conn.request_path))

      app_user ->
        conn
        |> put_status(:ok)
        |> json(%{data: authorized_app_detail_json(app_user)})
    end
  end

  @doc """
  PUT /api/v1/users/me/authorized-apps/:app_id
  Update scopes for an authorized app.
  """
  def update_authorized_app(conn, %{"app_id" => app_id, "granted_scopes" => scopes}) do
    user = Guardian.Plug.current_resource(conn)

    case Conezia.Platform.get_application_user_by_app_and_user(app_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("authorized app", app_id, conn.request_path))

      app_user ->
        case Conezia.Platform.update_application_user_scopes(app_user, scopes) do
          {:ok, updated} ->
            conn
            |> put_status(:ok)
            |> json(%{data: %{
              id: updated.id,
              granted_scopes: updated.granted_scopes,
              updated_at: updated.updated_at
            }})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  def update_authorized_app(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("granted_scopes is required.", conn.request_path))
  end

  @doc """
  DELETE /api/v1/users/me/authorized-apps/:app_id
  Revoke an app's authorization.
  """
  def revoke_authorized_app(conn, %{"app_id" => app_id}) do
    user = Guardian.Plug.current_resource(conn)

    case Conezia.Platform.get_application_user_by_app_and_user(app_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("authorized app", app_id, conn.request_path))

      app_user ->
        case Conezia.Platform.revoke_application_access(app_user) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Application access revoked successfully"}})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  # Private helpers

  defp user_json(user) do
    %{
      id: user.id,
      email: user.email,
      name: user.name,
      avatar_url: user.avatar_url,
      timezone: user.timezone,
      email_verified: user.email_verified_at != nil,
      settings: user.settings || %{},
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end

  defp preferences_json(user) do
    settings = user.settings || %{}

    %{
      theme: settings["theme"] || "light",
      language: settings["language"] || "en",
      date_format: settings["date_format"] || "YYYY-MM-DD",
      time_format: settings["time_format"] || "24h",
      default_reminder_time: settings["default_reminder_time"] || "09:00",
      digest_frequency: settings["digest_frequency"] || "weekly",
      digest_day: settings["digest_day"] || "monday"
    }
  end

  defp default_notifications do
    %{
      email: %{
        reminders: true,
        digest: true,
        health_alerts: true,
        security: true
      },
      push: %{
        reminders: true,
        messages: true,
        health_alerts: false
      },
      in_app: %{
        all: true
      },
      quiet_hours: %{
        enabled: false,
        start: "22:00",
        end: "08:00",
        timezone: "UTC"
      }
    }
  end

  defp onboarding_json(user) do
    onboarding = user.onboarding_state || %{}

    steps = [
      %{step: 1, name: "welcome", completed: onboarding["welcome"] == true},
      %{step: 2, name: "profile_setup", completed: onboarding["profile_setup"] == true},
      %{step: 3, name: "import_contacts", completed: onboarding["import_contacts"] == true, skipped: onboarding["import_contacts_skipped"] == true},
      %{step: 4, name: "create_first_entity", completed: onboarding["create_first_entity"] == true},
      %{step: 5, name: "set_first_reminder", completed: onboarding["set_first_reminder"] == true},
      %{step: 6, name: "tour_dashboard", completed: onboarding["tour_dashboard"] == true}
    ]

    current_step =
      steps
      |> Enum.find_index(fn s -> !s.completed and !Map.get(s, :skipped, false) end)
      |> Kernel.||(6)
      |> Kernel.+(1)

    %{
      completed: onboarding["completed"] == true,
      current_step: current_step,
      steps: steps,
      started_at: onboarding["started_at"]
    }
  end

  defp authorized_app_json(app_user) do
    app = app_user.application

    %{
      id: app_user.id,
      application: %{
        id: app.id,
        name: app.name,
        logo_url: app.logo_url,
        website_url: app.website_url
      },
      granted_scopes: app_user.granted_scopes,
      authorized_at: app_user.authorized_at,
      last_accessed_at: app_user.last_accessed_at
    }
  end

  defp authorized_app_detail_json(app_user) do
    app = app_user.application

    %{
      id: app_user.id,
      application: %{
        id: app.id,
        name: app.name,
        description: app.description,
        logo_url: app.logo_url,
        website_url: app.website_url
      },
      granted_scopes: app_user.granted_scopes,
      authorized_at: app_user.authorized_at,
      last_accessed_at: app_user.last_accessed_at,
      access_log: []
    }
  end
end
