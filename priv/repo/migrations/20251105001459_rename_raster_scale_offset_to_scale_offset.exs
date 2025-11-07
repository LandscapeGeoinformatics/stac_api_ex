defmodule StacApi.Repo.Migrations.RenameRasterScaleOffsetToScaleOffset do
  use Ecto.Migration

  def up do
    rename table(:item_assets), :raster_scale, to: :scale
    rename table(:item_assets), :raster_offset, to: :offset
  end

  def down do
    rename table(:item_assets), :scale, to: :raster_scale
    rename table(:item_assets), :offset, to: :raster_offset
  end
end
