defmodule StacApi.Repo.Migrations.CreateItemAssetsTable do
  use Ecto.Migration

  def change do
    create table(:item_assets) do
      add :item_id, :string, null: false
      add :asset_key, :string, null: false
      
      # Core asset fields
      add :href, :text
      add :type, :string
      add :title, :string
      add :description, :text
      add :roles, {:array, :string}
      
      # File information
      add :file_size, :bigint
      add :created_at, :utc_datetime
      
      # Raster-specific fields (for gsdata assets)
      add :nodata_value, :decimal
      add :data_type, :string
      add :spatial_resolution, :decimal
      add :unit, :string
      add :sampling, :string
      
      # Projection information
      add :epsg_code, :integer
      add :proj_bbox, {:array, :decimal}
      add :proj_transform, {:array, :decimal}
      
      # Store any other properties as JSONB for flexibility
      add :additional_properties, :map
      
      timestamps()
    end

    create unique_index(:item_assets, [:item_id, :asset_key])
    create index(:item_assets, [:item_id])
    create index(:item_assets, [:epsg_code])
    create index(:item_assets, [:file_size])
    create index(:item_assets, [:data_type])
    
    # Add foreign key constraint
    alter table(:item_assets) do
      modify :item_id, references(:items, column: :id, type: :string, on_delete: :delete_all)
    end
  end
end
