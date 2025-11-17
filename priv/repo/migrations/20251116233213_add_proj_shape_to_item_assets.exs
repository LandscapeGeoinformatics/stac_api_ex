defmodule StacApi.Repo.Migrations.AddProjShapeToItemAssets do
  use Ecto.Migration

  def change do
    alter table(:item_assets) do
      add :proj_shape, {:array, :integer}
    end
  end
end
