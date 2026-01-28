defmodule Conezia.Repo.Migrations.AddLocationCoordsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :place_id, :string
      add :latitude, :float
      add :longitude, :float
    end
  end
end
