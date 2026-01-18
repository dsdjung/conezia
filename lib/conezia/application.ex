defmodule Conezia.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ConeziaWeb.Telemetry,
      Conezia.Repo,
      {DNSCluster, query: Application.get_env(:conezia, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Conezia.PubSub},
      # Oban for background job processing
      {Oban, Application.fetch_env!(:conezia, Oban)},
      # Start to serve requests, typically the last entry
      ConeziaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Conezia.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ConeziaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
