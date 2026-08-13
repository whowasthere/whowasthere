defmodule WhoWasThere.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WhoWasThereWeb.Telemetry,
      WhoWasThere.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:whowasthere, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:whowasthere, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WhoWasThere.PubSub},
      WhoWasThere.Collector,
      WhoWasThereWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WhoWasThere.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WhoWasThereWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
