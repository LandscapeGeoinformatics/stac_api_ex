defmodule StacApi.Repo.Migrations.AddKeywordsProvidersToCollections do
  use Ecto.Migration

  def change do
    alter table(:collections) do
      add :keywords, {:array, :string}
      add :providers, {:array, :map}
    end
  end
end
