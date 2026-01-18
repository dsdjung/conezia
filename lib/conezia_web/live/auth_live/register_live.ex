defmodule ConeziaWeb.AuthLive.RegisterLive do
  @moduledoc """
  LiveView for user registration.
  """
  use ConeziaWeb, :live_view

  alias Conezia.Accounts
  alias Conezia.Accounts.User

  def render(assigns) do
    ~H"""
    <div class="flex min-h-full flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div class="sm:mx-auto sm:w-full sm:max-w-md">
        <h2 class="mt-6 text-center text-2xl font-bold leading-9 tracking-tight text-gray-900">
          Create your account
        </h2>
        <p class="mt-2 text-center text-sm text-gray-600">
          Start managing your personal relationships
        </p>
      </div>

      <div class="mt-10 sm:mx-auto sm:w-full sm:max-w-[480px]">
        <div class="bg-white px-6 py-12 shadow sm:rounded-lg sm:px-12">
          <.simple_form
            for={@form}
            id="registration_form"
            phx-submit="save"
            phx-change="validate"
            phx-trigger-action={@trigger_submit}
            action={~p"/login"}
            method="post"
          >
            <.input field={@form[:email]} type="email" label="Email address" required />
            <.input field={@form[:password]} type="password" label="Password" required />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirm password"
              required
            />

            <:actions>
              <.button phx-disable-with="Creating account..." class="w-full">
                Create account <span aria-hidden="true">→</span>
              </.button>
            </:actions>
          </.simple_form>
        </div>

        <p class="mt-10 text-center text-sm text-gray-500">
          Already have an account?
          <.link navigate={~p"/login"} class="font-semibold leading-6 text-indigo-600 hover:text-indigo-500">
            Sign in
          </.link>
        </p>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user(%User{})
    socket = assign(socket, trigger_submit: false, check_errors: false)
    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      %User{}
      |> User.registration_changeset(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        changeset =
          Accounts.change_user(user)
          |> Ecto.Changeset.put_change(:email, user.email)
          |> Ecto.Changeset.put_change(:password, user_params["password"])

        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if socket.assigns[:check_errors] do
      assign(socket, form: form)
    else
      assign(socket, form: Map.put(form, :errors, []))
    end
  end
end
