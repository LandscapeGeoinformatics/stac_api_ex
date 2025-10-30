defmodule StacApi.Repo.Migrations.AddRasterScaleOffsetToItemAssets do
  use Ecto.Migration

  def change do
    alter table(:item_assets) do
      add :raster_scale, :decimal
      add :raster_offset, :decimal
    end
  end
end

