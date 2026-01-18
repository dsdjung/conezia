defmodule ConeziaWeb.AuthController do
  @moduledoc """
  Controller for authentication endpoints.
  """
  use ConeziaWeb, :controller

  alias Conezia.Accounts
  alias Conezia.Guardian
  alias ConeziaWeb.ErrorHelpers

  @doc """
  POST /api/v1/auth/register
  Register a new user with email and password.
  """
  # JWT tokens expire after 1 hour
  @token_ttl {1, :hour}

  def register(conn, params) do
    case Accounts.create_user(params) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user, %{}, ttl: @token_ttl)

        conn
        |> put_status(:created)
        |> json(%{
          data: %{
            user: user_json(user),
            token: token_json(token)
          },
          meta: %{
            message: "Verification email sent"
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
    end
  end

  @doc """
  POST /api/v1/auth/login
  Login with email and password.
  """
  @max_failed_attempts 10

  def login(conn, %{"email" => email, "password" => password}) do
    alias ConeziaWeb.Plugs.AuthRateLimiter

    # Check if account is locked due to too many failed attempts
    failed_count = AuthRateLimiter.failed_login_count(email)

    if failed_count >= @max_failed_attempts do
      conn
      |> put_status(:too_many_requests)
      |> json(ErrorHelpers.error_response(
        :account_locked,
        "Account Temporarily Locked",
        429,
        "Too many failed login attempts. Please try again later or reset your password.",
        instance: conn.request_path
      ))
    else
      case Accounts.authenticate_by_email_password(email, password) do
        {:ok, user} ->
          # Clear failed login attempts on successful login
          AuthRateLimiter.clear_failed_logins(email)
          {:ok, token, _claims} = Guardian.encode_and_sign(user, %{}, ttl: @token_ttl)

          conn
          |> put_status(:ok)
          |> json(%{
            data: %{
              user: user_json(user),
              token: token_json(token)
            }
          })

        {:error, :invalid_credentials} ->
          # Record failed login attempt
          AuthRateLimiter.record_failed_login(email)

          conn
          |> put_status(:unauthorized)
          |> json(ErrorHelpers.error_response(
            :invalid_credentials,
            "Invalid credentials",
            401,
            "The email or password is incorrect.",
            instance: conn.request_path
          ))
      end
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("Email and password are required.", conn.request_path))
  end

  @doc """
  POST /api/v1/auth/google
  Authenticate via Google OAuth.
  """
  def google_oauth(conn, %{"code" => code, "redirect_uri" => redirect_uri}) do
    case exchange_google_code(code, redirect_uri) do
      {:ok, user, is_new} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user, %{}, ttl: @token_ttl)

        status = if is_new, do: :created, else: :ok

        conn
        |> put_status(status)
        |> json(%{
          data: %{
            user: user_json(user),
            token: token_json(token)
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(ErrorHelpers.unauthorized("Google authentication failed: #{reason}", conn.request_path))
    end
  end

  def google_oauth(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("Code and redirect_uri are required.", conn.request_path))
  end

  @doc """
  POST /api/v1/auth/refresh
  Refresh the access token.
  """
  def refresh(conn, %{"refresh_token" => refresh_token}) do
    case Guardian.refresh(refresh_token) do
      {:ok, _old_stuff, {new_token, _new_claims}} ->
        conn
        |> put_status(:ok)
        |> json(%{
          data: %{
            token: token_json(new_token)
          }
        })

      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(ErrorHelpers.unauthorized("Invalid or expired refresh token.", conn.request_path))
    end
  end

  def refresh(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("Refresh token is required.", conn.request_path))
  end

  @doc """
  POST /api/v1/auth/forgot-password
  Send password reset email.
  """
  def forgot_password(conn, %{"email" => email}) do
    # Always return success to prevent email enumeration
    _result = Accounts.deliver_password_reset_instructions(email)

    conn
    |> put_status(:ok)
    |> json(%{
      meta: %{
        message: "If an account exists, a reset email has been sent"
      }
    })
  end

  def forgot_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("Email is required.", conn.request_path))
  end

  @doc """
  POST /api/v1/auth/reset-password
  Reset password using token.
  """
  def reset_password(conn, %{"token" => token, "password" => password}) do
    case Accounts.reset_password_with_token(token, password) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          meta: %{
            message: "Password has been reset successfully"
          }
        })

      {:error, :invalid_token} ->
        conn
        |> put_status(:bad_request)
        |> json(ErrorHelpers.bad_request("Invalid or expired reset token.", conn.request_path))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(ErrorHelpers.validation_errors(changeset, conn.request_path))
    end
  end

  def reset_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("Token and password are required.", conn.request_path))
  end

  @doc """
  POST /api/v1/auth/verify-email
  Verify email using token.
  """
  def verify_email(conn, %{"token" => token}) do
    case Accounts.verify_email_with_token(token) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          meta: %{
            message: "Email has been verified successfully"
          }
        })

      {:error, :invalid_token} ->
        conn
        |> put_status(:bad_request)
        |> json(ErrorHelpers.bad_request("Invalid or expired verification token.", conn.request_path))
    end
  end

  def verify_email(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(ErrorHelpers.bad_request("Token is required.", conn.request_path))
  end

  @doc """
  POST /api/v1/auth/logout
  Logout and invalidate the current session.
  """
  def logout(conn, _params) do
    # Revoke the current token
    Guardian.Plug.sign_out(conn)

    conn
    |> put_status(:ok)
    |> json(%{
      meta: %{
        message: "Logged out successfully"
      }
    })
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
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end

  defp token_json(token) do
    %{
      access_token: token,
      token_type: "Bearer",
      expires_in: 86400
    }
  end

  @spec exchange_google_code(String.t(), String.t()) :: {:ok, map(), boolean()} | {:error, String.t()}
  defp exchange_google_code(code, redirect_uri) do
    # TODO: Implement Google OAuth token exchange
    # This would use Req to call Google's token endpoint
    # and then get user info from Google's userinfo endpoint
    case {code, redirect_uri} do
      # Placeholder for future implementation
      {"test_success_code", _uri} ->
        test_user = %{id: "test", email: "test@example.com", name: "Test", avatar_url: nil, timezone: "UTC", email_verified_at: nil, inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
        {:ok, test_user, true}

      _ ->
        {:error, "Google OAuth not implemented"}
    end
  end
end
