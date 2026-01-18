defmodule Conezia.Imports.ImportJob do
  @moduledoc """
  Import job schema for tracking contact import operations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sources ~w(google csv vcard linkedin icloud outlook)
  @statuses ~w(pending processing completed failed cancelled)

  schema "import_jobs" do
    field :source, :string
    field :status, :string, default: "pending"
    field :total_records, :integer, default: 0
    field :processed_records, :integer, default: 0
    field :created_records, :integer, default: 0
    field :merged_records, :integer, default: 0
    field :skipped_records, :integer, default: 0
    field :error_log, {:array, :map}, default: []
    field :file_path, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :user, Conezia.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:source, :user_id]
  @optional_fields [:status, :total_records, :processed_records, :created_records,
                    :merged_records, :skipped_records, :error_log, :file_path,
                    :started_at, :completed_at]

  def changeset(import_job, attrs) do
    import_job
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:total_records, greater_than_or_equal_to: 0)
    |> validate_number(:processed_records, greater_than_or_equal_to: 0)
    |> validate_number(:created_records, greater_than_or_equal_to: 0)
    |> validate_number(:merged_records, greater_than_or_equal_to: 0)
    |> validate_number(:skipped_records, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
  end

  def start_changeset(import_job) do
    change(import_job, status: "processing", started_at: DateTime.utc_now())
  end

  def complete_changeset(import_job, stats) do
    import_job
    |> change(stats)
    |> put_change(:status, "completed")
    |> put_change(:completed_at, DateTime.utc_now())
  end

  def fail_changeset(import_job, errors) do
    change(import_job,
      status: "failed",
      error_log: errors,
      completed_at: DateTime.utc_now()
    )
  end

  def valid_sources, do: @sources
  def valid_statuses, do: @statuses
end
