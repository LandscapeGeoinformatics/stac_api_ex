# lib/stac_api/postgres_types.ex
Postgrex.Types.define(
  StacApi.PostgresTypes,
  [Geo.PostGIS.Extension] ++ Ecto.Adapters.Postgres.extensions(),
  json: Jason
)
