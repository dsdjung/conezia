defmodule Conezia.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :name, :string, size: 255
      add :avatar_url, :string, size: 2048
      add :timezone, :string, size: 64, default: "UTC"
      add :hashed_password, :string, size: 255
      add :confirmed_at, :utc_datetime_usec
      add :tier, :string, size: 16, default: "free"
      add :settings, :map, default: %{}
      add :onboarding_completed_at, :utc_datetime_usec
      add :notification_preferences, :map, default: %{}
      add :onboarding_state, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
    create index(:users, [:inserted_at])
    create index(:users, [:tier])
  end
end
