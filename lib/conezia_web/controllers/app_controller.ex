defmodule ConeziaWeb.AppController do
  @moduledoc """
  Controller for third-party application management endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Platform
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  # Auth is handled in router pipeline

  @doc """
  GET /api/v1/apps
  List all applications for the current developer.
  """
  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    apps = Platform.list_applications(user.id)

    conn
    |> put_status(:ok)
    |> json(%{data: Enum.map(apps, &app_list_json/1)})
  end

  @doc """
  GET /api/v1/apps/:id
  Get a single application.
  """
  def show(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Platform.get_application_for_developer(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("application", id, conn.request_path))

      app ->
        conn
        |> put_status(:ok)
        |> json(%{data: app_detail_json(app)})
    end
  end

  @doc """
  POST /api/v1/apps
  Create a new application.
  """
  def create(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    attrs = Map.put(params, "developer_id", user.id)

    case Platform.create_application(attrs) do
      {:ok, app} ->
        # Return the API key and secret only on creation
        conn
        |> put_status(:created)
        |> json(%{
          data: %{
            id: app.id,
            name: app.name,
            api_key: app.api_key,
            api_secret: app.api_secret,
            status: app.status
          },
          meta: %{
            warning: "Save your API credentials now. They will not be shown again."
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
    end
  end

  @doc """
  PUT /api/v1/apps/:id
  Update an application.
  """
  def update(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Platform.get_application_for_developer(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("application", id, conn.request_path))

      app ->
        case Platform.update_application(app, params) do
          {:ok, updated_app} ->
            conn
            |> put_status(:ok)
            |> json(%{data: app_detail_json(updated_app)})

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  DELETE /api/v1/apps/:id
  Delete an application.
  """
  def delete(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Platform.get_application_for_developer(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("application", id, conn.request_path))

      app ->
        case Platform.delete_application(app) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{meta: %{message: "Application deleted"}})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  @doc """
  POST /api/v1/apps/:id/rotate-secret
  Rotate the API secret for an application.
  """
  def rotate_secret(conn, %{"id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Platform.get_application_for_developer(id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("application", id, conn.request_path))

      app ->
        new_secret = generate_api_secret()

        case Platform.update_application(app, %{api_secret: new_secret}) do
          {:ok, _updated_app} ->
            conn
            |> put_status(:ok)
            |> json(%{
              data: %{
                api_secret: new_secret
              },
              meta: %{
                warning: "Save your new API secret now. It will not be shown again."
              }
            })

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(ErrorHelpers.internal_error(conn.request_path))
        end
    end
  end

  # Webhook management

  @doc """
  GET /api/v1/apps/:app_id/webhooks
  List all webhooks for an application.
  """
  def list_webhooks(conn, %{"app_id" => app_id}) do
    user = Guardian.Plug.current_resource(conn)

    case Platform.get_application_for_developer(app_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("application", app_id, conn.request_path))

      _app ->
        webhooks = Platform.list_webhooks(app_id)

        conn
        |> put_status(:ok)
        |> json(%{data: Enum.map(webhooks, &webhook_json/1)})
    end
  end

  @doc """
  GET /api/v1/apps/:app_id/webhooks/:id
  Get a single webhook.
  """
  def show_webhook(conn, %{"app_id" => app_id, "id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Platform.get_application_for_developer(app_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("application", app_id, conn.request_path))

      _app ->
        case Platform.get_webhook_for_application(id, app_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(ErrorHelpers.not_found("webhook", id, conn.request_path))

          webhook ->
            conn
            |> put_status(:ok)
            |> json(%{data: webhook_json(webhook)})
        end
    end
  end

  @doc """
  POST /api/v1/apps/:app_id/webhooks
  Create a new webhook.
  """
  def create_webhook(conn, %{"app_id" => app_id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Platform.get_application_for_developer(app_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("application", app_id, conn.request_path))

      _app ->
        attrs = Map.put(params, "application_id", app_id)

        case Platform.create_webhook(attrs) do
          {:ok, webhook} ->
            conn
            |> put_status(:created)
            |> json(%{
              data: %{
                id: webhook.id,
                url: webhook.url,
                events: webhook.events,
                secret: webhook.secret,
                status: webhook.status
              }
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
        end
    end
  end

  @doc """
  PUT /api/v1/apps/:app_id/webhooks/:id
  Update a webhook.
  """
  def update_webhook(conn, %{"app_id" => app_id, "id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Platform.get_application_for_developer(app_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("application", app_id, conn.request_path))

      _app ->
        case Platform.get_webhook_for_application(id, app_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(ErrorHelpers.not_found("webhook", id, conn.request_path))

          webhook ->
            case Platform.update_webhook(webhook, params) do
              {:ok, updated_webhook} ->
                conn
                |> put_status(:ok)
                |> json(%{data: webhook_json(updated_webhook)})

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
            end
        end
    end
  end

  @doc """
  DELETE /api/v1/apps/:app_id/webhooks/:id
  Delete a webhook.
  """
  def delete_webhook(conn, %{"app_id" => app_id, "id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Platform.get_application_for_developer(app_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("application", app_id, conn.request_path))

      _app ->
        case Platform.get_webhook_for_application(id, app_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(ErrorHelpers.not_found("webhook", id, conn.request_path))

          webhook ->
            case Platform.delete_webhook(webhook) do
              {:ok, _} ->
                conn
                |> put_status(:ok)
                |> json(%{meta: %{message: "Webhook deleted"}})

              {:error, _} ->
                conn
                |> put_status(:internal_server_error)
                |> json(ErrorHelpers.internal_error(conn.request_path))
            end
        end
    end
  end

  @doc """
  POST /api/v1/apps/:app_id/webhooks/:id/test
  Test a webhook.
  """
  def test_webhook(conn, %{"app_id" => app_id, "id" => id}) do
    user = Guardian.Plug.current_resource(conn)

    case Platform.get_application_for_developer(app_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("application", app_id, conn.request_path))

      _app ->
        case Platform.get_webhook_for_application(id, app_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(ErrorHelpers.not_found("webhook", id, conn.request_path))

          webhook ->
            # Send a test payload to the webhook URL
            case send_test_webhook(webhook) do
              {:ok, response_status} ->
                conn
                |> put_status(:ok)
                |> json(%{
                  data: %{
                    success: response_status >= 200 and response_status < 300,
                    response_status: response_status
                  }
                })

              {:error, reason} ->
                conn
                |> put_status(:ok)
                |> json(%{
                  data: %{
                    success: false,
                    error: reason
                  }
                })
            end
        end
    end
  end

  @doc """
  GET /api/v1/apps/:app_id/webhooks/:id/deliveries
  List webhook deliveries.
  """
  def list_deliveries(conn, %{"app_id" => app_id, "id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)

    case Platform.get_application_for_developer(app_id, user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(ErrorHelpers.not_found("application", app_id, conn.request_path))

      _app ->
        case Platform.get_webhook_for_application(id, app_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(ErrorHelpers.not_found("webhook", id, conn.request_path))

          _webhook ->
            opts = [limit: parse_int(params["limit"], 50, 100)]
            deliveries = Platform.list_webhook_deliveries(id, opts)

            conn
            |> put_status(:ok)
            |> json(%{data: Enum.map(deliveries, &delivery_json/1)})
        end
    end
  end

  # Private helpers

  defp parse_int(nil, default, _max), do: default
  defp parse_int(val, default, max) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> min(num, max)
      :error -> default
    end
  end
  defp parse_int(val, _default, max) when is_integer(val), do: min(val, max)
  defp parse_int(_, default, _max), do: default

  defp app_list_json(app) do
    %{
      id: app.id,
      name: app.name,
      description: app.description,
      status: app.status,
      inserted_at: app.inserted_at
    }
  end

  defp app_detail_json(app) do
    %{
      id: app.id,
      name: app.name,
      description: app.description,
      website_url: app.website_url,
      callback_urls: app.callback_urls,
      scopes: app.scopes,
      status: app.status,
      inserted_at: app.inserted_at,
      updated_at: app.updated_at
    }
  end

  defp webhook_json(webhook) do
    %{
      id: webhook.id,
      url: webhook.url,
      events: webhook.events,
      status: webhook.status,
      inserted_at: webhook.inserted_at,
      updated_at: webhook.updated_at
    }
  end

  defp delivery_json(delivery) do
    %{
      id: delivery.id,
      event_type: delivery.event_type,
      response_status: delivery.response_status,
      delivered_at: delivery.delivered_at,
      inserted_at: delivery.inserted_at
    }
  end

  defp generate_api_secret do
    "cs_" <> (:crypto.strong_rand_bytes(32) |> Base.encode64(padding: false))
  end

  defp send_test_webhook(webhook) do
    test_payload = %{
      id: "evt_test_" <> UUID.uuid4(),
      type: "test.ping",
      created_at: DateTime.utc_now(),
      data: %{
        message: "This is a test webhook delivery"
      }
    }

    signature = compute_signature(test_payload, webhook.secret)

    case Req.post(webhook.url,
      json: test_payload,
      headers: [
        {"content-type", "application/json"},
        {"x-conezia-signature", "sha256=#{signature}"}
      ],
      receive_timeout: 10_000
    ) do
      {:ok, response} ->
        {:ok, response.status}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp compute_signature(payload, secret) do
    body = Jason.encode!(payload)
    :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
  end
end
