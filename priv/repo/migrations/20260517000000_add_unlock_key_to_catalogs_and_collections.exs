defmodule StacApi.Repo.Migrations.AddUnlockKeyToCatalogsAndCollections do
  use Ecto.Migration

  def change do
    alter table(:catalogs) do
      add :unlock_key, :string
    end

    alter table(:collections) do
      add :unlock_key, :string
    end
  end
end