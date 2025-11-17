import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :stac_api, StacApiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "JO8wCECsD8yjbyVpZ+fCuLrotVEZ4k9PmqlKlvsnVT517QlBXLoFh8RtOUCcoDL9",
  server: false


config :stac_api, StacApi.Repo,
  username: System.get_env("DB_USERNAME") || "postgres",
  password: System.get_env("DB_PASSWORD") || "postgres",
  database: System.get_env("DB_NAME") || "stac_api_#{config_env()}",
  hostname: System.get_env("DB_HOST") || "localhost",
  port: System.get_env("DB_PORT") || 5432,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  extensions: [{Geo.PostGIS.Extension, library: Geo}],  # Required for PostGIS
  # This function will be called when Repo starts, overriding the config if DATABASE_URL exists
  url: System.get_env("DATABASE_URL")


# In test we don't send emails
config :stac_api, StacApi.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Default API key for testing (same as dev for convenience)
config :stac_api, :api_key,
  System.get_env("STAC_API_KEY") || "dev-api-key-2024"
