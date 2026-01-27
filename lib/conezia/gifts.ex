defmodule Conezia.Gifts do
  @moduledoc """
  The Gifts context for managing gift planning and tracking.
  """
  import Ecto.Query
  alias Conezia.Repo
  alias Conezia.Gifts.Gift
  alias Conezia.Reminders

  def get_gift!(id), do: Repo.get!(Gift, id)

  def get_gift_for_user(id, user_id) do
    Gift
    |> where([g], g.id == ^id and g.user_id == ^user_id)
    |> preload([:entity, :reminder])
    |> Repo.one()
  end

  def list_gifts(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    status = Keyword.get(opts, :status)
    entity_id = Keyword.get(opts, :entity_id)
    occasion = Keyword.get(opts, :occasion)

    query =
      from g in Gift,
        where: g.user_id == ^user_id,
        limit: ^limit,
        offset: ^offset,
        order_by: [asc_nulls_last: g.occasion_date, desc: g.inserted_at],
        preload: [:entity]

    gifts =
      query
      |> filter_by_status(status)
      |> filter_by_entity_id(entity_id)
      |> filter_by_occasion(occasion)
      |> Repo.all()

    {gifts, %{has_more: length(gifts) >= limit, next_cursor: nil}}
  end

  def list_gifts_for_entity(entity_id, user_id) do
    from(g in Gift,
      where: g.entity_id == ^entity_id and g.user_id == ^user_id,
      order_by: [asc_nulls_last: g.occasion_date, desc: g.inserted_at],
      preload: [:entity]
    )
    |> Repo.all()
  end

  def upcoming_gifts(user_id, days_ahead \\ 30) do
    today = Date.utc_today()
    cutoff = Date.add(today, days_ahead)

    from(g in Gift,
      where: g.user_id == ^user_id,
      where: g.status != "given",
      where: not is_nil(g.occasion_date),
      where: g.occasion_date >= ^today and g.occasion_date <= ^cutoff,
      order_by: [asc: g.occasion_date],
      preload: [:entity]
    )
    |> Repo.all()
  end

  def create_gift(attrs) do
    %Gift{}
    |> Gift.changeset(attrs)
    |> Repo.insert()
    |> maybe_create_reminder()
  end

  def update_gift(%Gift{} = gift, attrs) do
    gift
    |> Gift.changeset(attrs)
    |> Repo.update()
  end

  def update_gift_status(%Gift{} = gift, new_status) do
    gift
    |> Gift.status_changeset(new_status)
    |> Repo.update()
  end

  def delete_gift(%Gift{} = gift) do
    # Delete linked reminder if exists
    if gift.reminder_id do
      case Reminders.get_reminder(gift.reminder_id) do
        nil -> :ok
        reminder -> Reminders.delete_reminder(reminder)
      end
    end

    Repo.delete(gift)
  end

  def change_gift(%Gift{} = gift, attrs \\ %{}) do
    Gift.changeset(gift, attrs)
  end

  def budget_summary(user_id, opts \\ []) do
    year = Keyword.get(opts, :year, Date.utc_today().year)
    start_date = Date.new!(year, 1, 1)
    end_date = Date.new!(year, 12, 31)

    query =
      from g in Gift,
        where: g.user_id == ^user_id,
        where: not is_nil(g.occasion_date),
        where: g.occasion_date >= ^start_date and g.occasion_date <= ^end_date

    total_budget =
      query
      |> select([g], sum(g.budget_cents))
      |> Repo.one() || 0

    total_spent =
      query
      |> where([g], g.status in ["purchased", "wrapped", "given"])
      |> select([g], sum(g.actual_cost_cents))
      |> Repo.one() || 0

    %{total_budget: total_budget, total_spent: total_spent}
  end

  # Reminder integration

  defp maybe_create_reminder({:ok, %Gift{occasion_date: nil} = gift}), do: {:ok, gift}

  defp maybe_create_reminder({:ok, %Gift{} = gift}) do
    reminder_date = Date.add(gift.occasion_date, -14)

    # Only create reminder if the reminder date is in the future
    if Date.compare(reminder_date, Date.utc_today()) == :gt do
      due_at = DateTime.new!(reminder_date, ~T[09:00:00], "Etc/UTC")

      entity = Repo.preload(gift, :entity).entity
      entity_name = if entity, do: entity.name, else: "someone"

      recurrence =
        if gift.occasion in ["birthday", "anniversary"],
          do: %{"freq" => "yearly"},
          else: nil

      case Reminders.create_reminder(%{
             type: "gift",
             title: "Gift for #{entity_name}: #{gift.name} (#{humanize_occasion(gift.occasion)})",
             description: "Reminder to prepare gift: #{gift.name}",
             due_at: due_at,
             user_id: gift.user_id,
             entity_id: gift.entity_id,
             recurrence_rule: recurrence
           }) do
        {:ok, reminder} ->
          gift
          |> Ecto.Changeset.change(reminder_id: reminder.id)
          |> Repo.update()

        {:error, _} ->
          {:ok, gift}
      end
    else
      {:ok, gift}
    end
  end

  defp maybe_create_reminder(error), do: error

  defp humanize_occasion(occasion) do
    occasion
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # Private filter helpers

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status), do: where(query, [g], g.status == ^status)

  defp filter_by_entity_id(query, nil), do: query
  defp filter_by_entity_id(query, entity_id), do: where(query, [g], g.entity_id == ^entity_id)

  defp filter_by_occasion(query, nil), do: query
  defp filter_by_occasion(query, occasion), do: where(query, [g], g.occasion == ^occasion)
end
