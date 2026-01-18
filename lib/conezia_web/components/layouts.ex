defmodule ConeziaWeb.Layouts do
  @moduledoc """
  Layout components for the Conezia application.

  This module provides the embed_templates function to load
  the layout templates from the layouts directory.
  """
  use ConeziaWeb, :html

  alias Phoenix.LiveView.JS

  embed_templates "layouts/*"

  @doc """
  Shows the mobile navigation menu.
  """
  def show_mobile_menu(js \\ %JS{}) do
    JS.dispatch(js, "phx:show-mobile-menu")
  end

  @doc """
  Hides the mobile navigation menu.
  """
  def hide_mobile_menu(js \\ %JS{}) do
    JS.dispatch(js, "phx:hide-mobile-menu")
  end

  @doc """
  Toggles the user dropdown menu.
  """
  def toggle_user_menu(js \\ %JS{}) do
    JS.dispatch(js, "phx:toggle-user-menu")
  end

  @doc """
  Returns the user's display name or a default.
  """
  def user_name(nil), do: "Guest"
  def user_name(%{email: email}), do: email

  @doc """
  Returns the user's initials for the avatar.
  """
  def user_initials(nil), do: "?"
  def user_initials(%{email: email}) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.slice(0, 2)
    |> String.upcase()
  end
  def user_initials(_), do: "?"
end
