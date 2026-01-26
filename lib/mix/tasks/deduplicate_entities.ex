defmodule Mix.Tasks.Conezia.DeduplicateEntities do
  @moduledoc """
  Mix task to find and merge duplicate entities for a user.

  ## Usage

      # List duplicates without merging (dry run)
      mix conezia.deduplicate_entities USER_EMAIL

      # Auto-merge all duplicates
      mix conezia.deduplicate_entities USER_EMAIL --merge

      # Auto-merge for all users
      mix conezia.deduplicate_entities --all --merge

  ## Examples

      mix conezia.deduplicate_entities user@example.com
      mix conezia.deduplicate_entities user@example.com --merge
      mix conezia.deduplicate_entities --all --merge
  """
  use Mix.Task

  @shortdoc "Find and merge duplicate entities"

  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    {opts, rest, _} = OptionParser.parse(args, switches: [merge: :boolean, all: :boolean])

    merge? = Keyword.get(opts, :merge, false)
    all? = Keyword.get(opts, :all, false)

    cond do
      all? ->
        process_all_users(merge?)

      length(rest) > 0 ->
        email = hd(rest)
        process_user_by_email(email, merge?)

      true ->
        Mix.shell().error("Usage: mix conezia.deduplicate_entities USER_EMAIL [--merge]")
        Mix.shell().error("       mix conezia.deduplicate_entities --all [--merge]")
    end
  end

  defp process_all_users(merge?) do
    alias Conezia.Repo
    alias Conezia.Accounts.User

    users = Repo.all(User)
    Mix.shell().info("Processing #{length(users)} users...")

    Enum.each(users, fn user ->
      Mix.shell().info("\n=== User: #{user.email} ===")
      process_user(user, merge?)
    end)
  end

  defp process_user_by_email(email, merge?) do
    alias Conezia.Accounts

    case Accounts.get_user_by_email(email) do
      nil ->
        Mix.shell().error("User not found: #{email}")

      user ->
        process_user(user, merge?)
    end
  end

  defp process_user(user, merge?) do
    alias Conezia.Entities

    groups = Entities.find_all_duplicates(user.id)

    if Enum.empty?(groups) do
      Mix.shell().info("No duplicates found.")
    else
      total_duplicates = Enum.sum(Enum.map(groups, &length(&1.duplicates)))
      Mix.shell().info("Found #{length(groups)} duplicate groups (#{total_duplicates} duplicates total)")
      Mix.shell().info("")

      Enum.each(groups, fn group ->
        print_group(group)
      end)

      if merge? do
        Mix.shell().info("\n--- Merging duplicates ---\n")

        {:ok, stats} = Entities.auto_merge_duplicates(user.id)

        Mix.shell().info("Merged #{stats.merged_groups} groups successfully.")
        Mix.shell().info("Removed #{stats.total_duplicates_removed} duplicate entities.")

        if stats.failed_groups > 0 do
          Mix.shell().error("#{stats.failed_groups} groups failed to merge.")
        end
      else
        Mix.shell().info("\nRun with --merge to automatically merge these duplicates.")
      end
    end
  end

  defp print_group(group) do
    Mix.shell().info("Duplicate Group:")
    Mix.shell().info("  Primary (keep): #{group.primary.name} (#{group.primary.id})")

    Enum.each(group.duplicates, fn dup ->
      Mix.shell().info("  Duplicate:      #{dup.name} (#{dup.id})")
    end)

    if length(group.match_reasons) > 0 do
      Mix.shell().info("  Match reasons:  #{Enum.join(group.match_reasons, ", ")}")
    end

    Mix.shell().info("")
  end
end
