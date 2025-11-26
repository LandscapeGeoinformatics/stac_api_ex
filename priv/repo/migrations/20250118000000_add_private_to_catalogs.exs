defmodule StacApi.Repo.Migrations.AddPrivateToCatalogs do
  use Ecto.Migration

  def change do
    alter table(:catalogs) do
      add :private, :boolean, default: false, null: false
    end

    create index(:catalogs, [:private])
  end
end
