defmodule Mix.Tasks.Conezia.ClearConnections do
  @moduledoc """
  Mix task to delete all connections/entities for a user.

  ## Usage

      # Delete all connections for a specific user
      mix conezia.clear_connections USER_EMAIL

      # Delete all connections for all users
      mix conezia.clear_connections --all

  ## Examples

      mix conezia.clear_connections user@example.com
      mix conezia.clear_connections --all
  """
  use Mix.Task

  @shortdoc "Delete all connections for a user"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest, _} = OptionParser.parse(args, switches: [all: :boolean, yes: :boolean])

    all? = Keyword.get(opts, :all, false)
    skip_confirm? = Keyword.get(opts, :yes, false)

    cond do
      all? ->
        if skip_confirm? || confirm?("Delete ALL connections for ALL users?") do
          clear_all_users()
        else
          Mix.shell().info("Aborted.")
        end

      length(rest) > 0 ->
        email = hd(rest)
        if skip_confirm? || confirm?("Delete all connections for #{email}?") do
          clear_user_by_email(email)
        else
          Mix.shell().info("Aborted.")
        end

      true ->
        Mix.shell().error("Usage: mix conezia.clear_connections USER_EMAIL")
        Mix.shell().error("       mix conezia.clear_connections --all")
    end
  end

  defp confirm?(message) do
    Mix.shell().yes?(message)
  end

  defp clear_all_users do
    alias Conezia.Repo
    alias Conezia.Accounts.User

    users = Repo.all(User)
    Mix.shell().info("Clearing connections for #{length(users)} users...")

    Enum.each(users, fn user ->
      count = clear_user(user)
      Mix.shell().info("  #{user.email}: deleted #{count} connections")
    end)

    Mix.shell().info("Done.")
  end

  defp clear_user_by_email(email) do
    alias Conezia.Accounts

    case Accounts.get_user_by_email(email) do
      nil ->
        Mix.shell().error("User not found: #{email}")

      user ->
        count = clear_user(user)
        Mix.shell().info("Deleted #{count} connections for #{email}")
    end
  end

  defp clear_user(user) do
    alias Conezia.Repo
    alias Conezia.Entities.Entity
    import Ecto.Query

    {count, _} =
      from(e in Entity, where: e.owner_id == ^user.id)
      |> Repo.delete_all()

    count
  end
end
