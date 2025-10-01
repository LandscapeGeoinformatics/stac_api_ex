defmodule StacApi.Repo.Migrations.FixGeometrySrid do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE items ALTER COLUMN geometry TYPE geometry(Geometry,4326)"
  end

  def down do
    execute "ALTER TABLE items ALTER COLUMN geometry TYPE geometry"
  end
end
