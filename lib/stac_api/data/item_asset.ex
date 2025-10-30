defmodule StacApi.Data.ItemAsset do
  use Ecto.Schema
  import Ecto.Changeset

  schema "item_assets" do
    field :item_id, :string
    field :asset_key, :string
    
    # Core asset fields
    field :href, :string
    field :type, :string
    field :title, :string
    field :description, :string
    field :roles, {:array, :string}
    
    # File information
    field :file_size, :integer
    field :created_at, :utc_datetime
    
    # Raster-specific fields
    field :nodata_value, :decimal
    field :data_type, :string
    field :spatial_resolution, :decimal
    field :unit, :string
    field :sampling, :string
    field :raster_scale, :decimal
    field :raster_offset, :decimal
    
    # Projection information
    field :epsg_code, :integer
    field :proj_bbox, {:array, :decimal}
    field :proj_transform, {:array, :decimal}
    
    # Additional properties
    field :additional_properties, :map

    timestamps()
  end

  @doc false
  def changeset(item_asset, attrs) do
    item_asset
    |> cast(attrs, [
      :item_id, :asset_key, :href, :type, :title, :description, :roles,
      :file_size, :created_at, :nodata_value, :data_type, :spatial_resolution,
      :unit, :sampling, :raster_scale, :raster_offset, :epsg_code, :proj_bbox, :proj_transform, :additional_properties
    ])
    |> validate_required([:item_id, :asset_key])
    |> unique_constraint([:item_id, :asset_key])
  end

  @doc """
  Convert a STAC asset JSON to ItemAsset changeset
  """
  def from_stac_asset(item_id, asset_key, asset_data) do
    # Extract raster bands if present
    raster_bands = Map.get(asset_data, "raster:bands", [])
    raster_data = if length(raster_bands) > 0 do
      band = hd(raster_bands)
      %{
        nodata_value: Map.get(band, "nodata"),
        data_type: Map.get(band, "data_type"),
        spatial_resolution: Map.get(band, "spatial_resolution"),
        unit: Map.get(band, "unit"),
        sampling: Map.get(band, "sampling"),
        # Support both "raster:scale" and "scale" for backward compatibility
        raster_scale: Map.get(band, "raster:scale") || Map.get(band, "scale"),
        raster_offset: Map.get(band, "raster:offset") || Map.get(band, "offset")
      }
    else
      %{}
    end

    # Extract projection info if present
    proj_epsg = Map.get(asset_data, "proj:epsg", %{})
    proj_data = %{
      epsg_code: Map.get(proj_epsg, "epsg"),
      proj_bbox: Map.get(proj_epsg, "bbox"),
      proj_transform: Map.get(proj_epsg, "transform")
    }

    # Extract file size if present
    file_size = Map.get(asset_data, "file:size")

    # Extract created_at if present
    created_at = Map.get(asset_data, "created")

    # Everything else goes into additional_properties
    additional_properties = asset_data
    |> Map.drop([
      "href", "type", "title", "description", "roles", "file:size", "created",
      "raster:bands", "proj:epsg"
    ])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})

    changeset(%__MODULE__{}, %{
      item_id: item_id,
      asset_key: asset_key,
      href: Map.get(asset_data, "href"),
      type: Map.get(asset_data, "type"),
      title: Map.get(asset_data, "title"),
      description: Map.get(asset_data, "description"),
      roles: Map.get(asset_data, "roles", []),
      file_size: file_size,
      created_at: created_at,
      additional_properties: additional_properties
    } |> Map.merge(raster_data) |> Map.merge(proj_data))
  end

  @doc """
  Convert ItemAsset back to STAC asset JSON
  """
  def to_stac_asset(%__MODULE__{} = asset) do
    asset_data = %{
      "href" => asset.href,
      "type" => asset.type,
      "title" => asset.title,
      "description" => asset.description,
      "roles" => asset.roles || []
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {k, convert_decimal(v)} end)
    |> Enum.into(%{})

    # Add file size if present
    asset_data = if asset.file_size do
      Map.put(asset_data, "file:size", asset.file_size)
    else
      asset_data
    end

    # Add created_at if present
    asset_data = if asset.created_at do
      Map.put(asset_data, "created", asset.created_at)
    else
      asset_data
    end

    # Add raster bands if present
    asset_data = if asset.data_type do
      raster_band = %{
        "nodata" => asset.nodata_value,
        "data_type" => asset.data_type,
        "spatial_resolution" => asset.spatial_resolution,
        "unit" => asset.unit,
        "sampling" => asset.sampling,
        "raster:scale" => asset.raster_scale,
        "raster:offset" => asset.raster_offset
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> {k, convert_decimal(v)} end)
      |> Enum.into(%{})

      Map.put(asset_data, "raster:bands", [raster_band])
    else
      asset_data
    end

    # Add projection info if present
    asset_data = if asset.epsg_code do
      proj_epsg = %{
        "epsg" => asset.epsg_code,
        "bbox" => asset.proj_bbox,
        "transform" => asset.proj_transform
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> {k, convert_decimal(v)} end)
      |> Enum.into(%{})

      Map.put(asset_data, "proj:epsg", proj_epsg)
    else
      asset_data
    end

    # Add any additional properties
    additional_props = asset.additional_properties || %{}
    Map.merge(asset_data, additional_props)
  end

  # Helper to convert Decimal structs to floats/numbers for JSON serialization
  defp convert_decimal(%Decimal{} = decimal) do
    Decimal.to_float(decimal)
  end
  defp convert_decimal(list) when is_list(list) do
    Enum.map(list, &convert_decimal/1)
  end
  defp convert_decimal(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, convert_decimal(v)} end)
  end
  defp convert_decimal(value), do: value
end
