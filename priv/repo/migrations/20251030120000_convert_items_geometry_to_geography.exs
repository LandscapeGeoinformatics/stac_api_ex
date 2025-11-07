defmodule StacApi.Repo.Migrations.ConvertItemsGeometryToGeography do
  use Ecto.Migration

  def up do
    execute "DROP INDEX IF EXISTS items_geometry_gist_idx"

    execute """
    ALTER TABLE items
    ALTER COLUMN geometry TYPE geography(Geometry,4326)
    USING ST_SetSRID(geometry, 4326)::geography
    """

    execute "CREATE INDEX items_geometry_gist_idx ON items USING GIST (geometry)"
  end

  def down do
    execute "DROP INDEX IF EXISTS items_geometry_gist_idx"

    execute """
    ALTER TABLE items
    ALTER COLUMN geometry TYPE geometry(Geometry,4326)
    USING ST_SetSRID(geometry::geometry, 4326)
    """

    execute "CREATE INDEX items_geometry_gist_idx ON items USING GIST (geometry)"
  end
end


