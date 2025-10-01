defmodule StacApi.Repo.Migrations.CreateStacTables do
  use Ecto.Migration

  def up do
    # Enable PostGIS extension
    execute "CREATE EXTENSION IF NOT EXISTS postgis"

    # Collections table
    create table(:collections, primary_key: false) do
      add :id, :string, primary_key: true
      add :title, :string
      add :description, :text
      add :license, :string
      add :extent, :map
      add :summaries, :map
      add :properties, :map
      add :stac_version, :string
      add :stac_extensions, {:array, :string}
      add :links, {:array, :map}

      timestamps()
    end

    # Items table with proper STAC structure
    create table(:items, primary_key: false) do
      add :id, :string, primary_key: true
      add :collection_id, references(:collections, column: :id, type: :string)
      add :stac_version, :string
      add :stac_extensions, {:array, :string}

      # Geometry stored as PostGIS geometry (WGS84/EPSG:4326)
      add :geometry, :geometry, srid: 4326
      add :bbox, {:array, :float}

      # Properties
      add :datetime, :utc_datetime
      add :properties, :map

      # Assets and Links as JSONB
      add :assets, :map
      add :links, {:array, :map}

      timestamps()
    end

    # Spatial index on geometry (crucial for performance)
    execute "CREATE INDEX items_geometry_gist_idx ON items USING GIST (geometry)"

    # Additional indexes for common queries
    create index(:items, [:collection_id])
    create index(:items, [:datetime])
    create index(:items, [:bbox], using: :gin)

    # GIN index on properties for JSON queries
    execute "CREATE INDEX items_properties_gin_idx ON items USING GIN (properties)"
    execute "CREATE INDEX items_assets_gin_idx ON items USING GIN (assets)"
  end

  def down do
    drop table(:items)
    drop table(:collections)
    execute "DROP EXTENSION IF EXISTS postgis"
  end
end
