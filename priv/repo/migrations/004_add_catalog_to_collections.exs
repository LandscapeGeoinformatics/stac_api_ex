defmodule StacApi.Repo.Migrations.AddCatalogToCollections do
  use Ecto.Migration

  def change do
    alter table(:collections) do
      add :catalog_id, :string
    end

    create index(:collections, [:catalog_id])
    execute "ALTER TABLE collections ADD CONSTRAINT collections_catalog_id_fkey FOREIGN KEY (catalog_id) REFERENCES catalogs(id)"
  end
end
