defmodule ConeziaWeb.AuthLive.LoginLive do
  @moduledoc """
  LiveView for user login.
  """
  use ConeziaWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="flex min-h-full flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div class="sm:mx-auto sm:w-full sm:max-w-md">
        <h2 class="mt-6 text-center text-2xl font-bold leading-9 tracking-tight text-gray-900">
          Sign in to Conezia
        </h2>
        <p class="mt-2 text-center text-sm text-gray-600">
          Manage your personal relationships
        </p>
      </div>

      <div class="mt-10 sm:mx-auto sm:w-full sm:max-w-[480px]">
        <div class="bg-white px-6 py-12 shadow sm:rounded-lg sm:px-12">
          <.simple_form
            for={@form}
            id="login_form"
            action={~p"/login"}
            phx-update="ignore"
          >
            <.input
              field={@form[:email]}
              type="email"
              label="Email address"
              autocomplete="email"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
              required
            />

            <div class="flex items-center justify-between">
              <.input
                field={@form[:remember_me]}
                type="checkbox"
                label="Keep me logged in"
              />
              <.link navigate={~p"/forgot-password"} class="text-sm font-semibold text-indigo-600 hover:text-indigo-500">
                Forgot your password?
              </.link>
            </div>

            <:actions>
              <.button phx-disable-with="Signing in..." class="w-full">
                Sign in <span aria-hidden="true">→</span>
              </.button>
            </:actions>
          </.simple_form>
        </div>

        <p class="mt-10 text-center text-sm text-gray-500">
          Don't have an account?
          <.link navigate={~p"/register"} class="font-semibold leading-6 text-indigo-600 hover:text-indigo-500">
            Register now
          </.link>
        </p>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
