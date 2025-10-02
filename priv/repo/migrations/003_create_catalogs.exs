defmodule StacApi.Repo.Migrations.CreateCatalogs do
  use Ecto.Migration

  def change do
    create table(:catalogs, primary_key: false) do
      add :id, :string, primary_key: true
      add :title, :string
      add :description, :text
      add :type, :string, default: "Catalog"
      add :stac_version, :string, default: "1.0.0"
      add :extent, :map
      add :links, {:array, :map}, default: []


      add :parent_catalog_id, :string
      add :depth, :integer, default: 0  # 0 = root, 1 = first level, 2 = second level

      timestamps(type: :utc_datetime)
    end

    create index(:catalogs, [:parent_catalog_id])
    create index(:catalogs, [:depth])
    create unique_index(:catalogs, [:id])

    # Self-referencing foreign key constraint
    execute "ALTER TABLE catalogs ADD CONSTRAINT catalogs_parent_catalog_id_fkey FOREIGN KEY (parent_catalog_id) REFERENCES catalogs(id)"
  end
end
