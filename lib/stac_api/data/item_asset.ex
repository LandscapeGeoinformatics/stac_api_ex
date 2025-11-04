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
    field :scale, :decimal
    field :offset, :decimal
    
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
      :unit, :sampling, :scale, :offset, :epsg_code, :proj_bbox, :proj_transform, :additional_properties
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
      # Support both v1 (no prefix) and v2 (raster: prefix) field names
      %{
        nodata_value: Map.get(band, "raster:nodata") || Map.get(band, "nodata"),
        data_type: Map.get(band, "raster:data_type") || Map.get(band, "data_type"),
        spatial_resolution: Map.get(band, "raster:spatial_resolution") || Map.get(band, "spatial_resolution"),
        unit: Map.get(band, "raster:unit") || Map.get(band, "unit"),
        sampling: Map.get(band, "raster:sampling") || Map.get(band, "sampling"),
        scale: Map.get(band, "raster:scale") || Map.get(band, "scale"),
        offset: Map.get(band, "raster:offset") || Map.get(band, "offset")
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
  
  Version-aware serialization: raster v1 uses "scale"/"offset", v2 uses "raster:scale"/"raster:offset"
  """
  def to_stac_asset(%__MODULE__{} = asset, stac_extensions \\ []) do
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
      # Detect raster extension version to use correct field names
      # v1: no prefix (nodata, data_type, scale, offset, etc.)
      # v2: all fields prefixed with "raster:" (raster:nodata, raster:data_type, raster:scale, raster:offset, etc.)
      use_v2 = is_raster_v2?(stac_extensions)
      
      raster_band = if use_v2 do
        %{
          "raster:nodata" => asset.nodata_value,
          "raster:data_type" => asset.data_type,
          "raster:spatial_resolution" => asset.spatial_resolution,
          "raster:unit" => asset.unit,
          "raster:sampling" => asset.sampling,
          "raster:scale" => asset.scale,
          "raster:offset" => asset.offset
        }
      else
        %{
          "nodata" => asset.nodata_value,
          "data_type" => asset.data_type,
          "spatial_resolution" => asset.spatial_resolution,
          "unit" => asset.unit,
          "sampling" => asset.sampling,
          "scale" => asset.scale,
          "offset" => asset.offset
        }
      end
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

  # Helper to detect if raster extension v2 is used based on stac_extensions
  defp is_raster_v2?(stac_extensions) when is_list(stac_extensions) do
    Enum.any?(stac_extensions, fn ext ->
      # Check if the extension URL contains "/raster/v2"
      String.contains?(ext, "/raster/v2")
    end)
  end
  defp is_raster_v2?(_), do: false

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
