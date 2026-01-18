defmodule Conezia.Repo do
  use Ecto.Repo,
    otp_app: :conezia,
    adapter: Ecto.Adapters.Postgres
end
