defmodule ConeziaWeb.AuthLive.ForgotPasswordLive do
  @moduledoc """
  LiveView for password reset request.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Accounts

  def render(assigns) do
    ~H"""
    <div class="flex min-h-full flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div class="sm:mx-auto sm:w-full sm:max-w-md">
        <h2 class="mt-6 text-center text-2xl font-bold leading-9 tracking-tight text-gray-900">
          Forgot your password?
        </h2>
        <p class="mt-2 text-center text-sm text-gray-600">
          We'll send you a password reset link
        </p>
      </div>

      <div class="mt-10 sm:mx-auto sm:w-full sm:max-w-[480px]">
        <div class="bg-white px-6 py-12 shadow sm:rounded-lg sm:px-12">
          <.simple_form for={@form} id="reset_password_form" phx-submit="send_email">
            <.input field={@form[:email]} type="email" label="Email address" required />
            <:actions>
              <.button phx-disable-with="Sending..." class="w-full">
                Send password reset email
              </.button>
            </:actions>
          </.simple_form>
        </div>

        <p class="mt-10 text-center text-sm text-gray-500">
          Remember your password?
          <.link navigate={~p"/login"} class="font-semibold leading-6 text-indigo-600 hover:text-indigo-500">
            Sign in
          </.link>
        </p>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    Accounts.deliver_password_reset_instructions(email)

    info =
      "If an account with that email exists, you will receive an email with instructions shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/login")}
  end
end
