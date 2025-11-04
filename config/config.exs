# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configures the endpoint
config :stac_api, StacApiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: StacApiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: StacApi.PubSub,
  live_view: [signing_salt: "5+y7odye"]

# Configures the mailer
config :stac_api, StacApi.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason



# Configure Ecto repositories
config :stac_api, ecto_repos: [StacApi.Repo]


# Geo configuration for PostGIS
config :geo,
  json_library: Jason,  # Required for proper GeoJSON handling
  unit_cache: :memory   # Optional: Improves performance

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
