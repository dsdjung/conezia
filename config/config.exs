# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :conezia,
  ecto_repos: [Conezia.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

# Configure Ecto for UUIDs and microsecond timestamps
config :conezia, Conezia.Repo,
  migration_primary_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec]

# Configure Guardian for JWT authentication
config :conezia, Conezia.Guardian,
  issuer: "conezia",
  secret_key: "development_secret_key_change_in_production"

# Configure Tzdata for timezone support
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Configure Oban for background jobs
config :conezia, Oban,
  repo: Conezia.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [default: 10, reminders: 5, imports: 3, webhooks: 5, health: 2]

# Configure field-level encryption vault
# WARNING: Change this key in production and keep it secure!
config :conezia, Conezia.Vault,
  secret_key: "dev_vault_key_32_bytes_change_me!"

# Configure storage adapter (local for development)
config :conezia, Conezia.Storage,
  adapter: Conezia.Storage.Local,
  base_path: "priv/uploads"

# Configure the endpoint
config :conezia, ConeziaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ConeziaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Conezia.PubSub,
  live_view: [signing_salt: "xmNbJq5o"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
