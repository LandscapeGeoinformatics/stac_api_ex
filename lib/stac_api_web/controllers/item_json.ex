defmodule StacApiWeb.ItemJSON do
  @moduledoc """
  STAC JSON representation of a `StacApi.Data.Item`.

  Single source of truth for the item payload returned by
  `StacApiWeb.ItemsCrudController` (create / show / update / patch / index).
  Links and assets are passed in by the caller: links come from
  `StacApiWeb.DynamicLinkGenerator` and vary per request, assets are
  reconstructed from the normalized `item_assets` table.

  Note this is deliberately *not* the same rendering as
  `StacApi.Data.Search.serialize_item_for_api/1`, which serves the public read
  API. That one uses string keys, converts `Geo` structs to plain GeoJSON and
  returns `properties` exactly as stored. Unifying the two is worthwhile but
  changes payloads on one side or the other, so it is not part of this
  extraction.
  """

  alias StacApi.Data.Item
  alias StacApiWeb.STACDateTime

  @doc """
  Render an item as a STAC Item (GeoJSON Feature) object.
  """
  def to_stac(%Item{} = item, links, assets) do
    %{
      type: "Feature",
      stac_version: item.stac_version || "1.0.0",
      stac_extensions: item.stac_extensions || [],
      id: item.id,
      geometry: item.geometry,
      bbox: item.bbox,
      properties: stac_properties(item),
      assets: assets,
      collection: item.collection_id,
      links: links
    }
  end

  # STAC Common Metadata puts `created` / `updated` inside an item's properties,
  # unlike collections and catalogs where they are top level.
  #
  # These are the API's record of its own writes, so they win over anything the
  # client sent under the same keys — a client that trusted its own `updated`
  # back could not detect that the server had been written to meanwhile, which
  # is the whole point of exposing them.
  defp stac_properties(%Item{} = item) do
    (item.properties || %{})
    |> put_unless_nil("created", STACDateTime.to_rfc3339(item.inserted_at))
    |> put_unless_nil("updated", STACDateTime.to_rfc3339(item.updated_at))
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)
end
