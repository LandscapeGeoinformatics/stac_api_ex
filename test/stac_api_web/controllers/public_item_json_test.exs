defmodule StacApiWeb.PublicItemJSONTest do
  use StacApiWeb.ConnCase, async: true

  @collection "public-item-collection"

  setup %{conn: conn} do
    auth_conn = authenticated_conn(conn)

    post(auth_conn, ~p"/stac/manage/v1/collections", %{
      "id" => @collection,
      "title" => "Public Item Collection",
      "description" => "Exercises the public Item JSON",
      "license" => "CC-BY-4.0"
    })

    post(auth_conn, ~p"/stac/manage/v1/items", %{
      "id" => "instant-item",
      "collection_id" => @collection,
      "stac_extensions" => ["https://stac-extensions.github.io/eo/v1.1.0/schema.json"],
      "geometry" => %{
        "type" => "Polygon",
        "coordinates" => [
          [[26.7225, 58.3776], [26.7325, 58.3776], [26.7325, 58.3876], [26.7225, 58.3776]]
        ]
      },
      "bbox" => [26.7225, 58.3776, 26.7325, 58.3876],
      # Written with an offset on purpose, stored normalised to UTC.
      "properties" => %{"datetime" => "2024-01-02T03:00:00+03:00", "eo:cloud_cover" => 1.5},
      "assets" => %{
        "data" => %{"href" => "https://example.com/data.tif", "type" => "image/tiff"}
      },
      "links" => [%{"rel" => "license", "href" => "https://example.com/license"}]
    })

    post(auth_conn, ~p"/stac/manage/v1/items", %{
      "id" => "range-item",
      "collection_id" => @collection,
      "geometry" => %{"type" => "Point", "coordinates" => [26.4, 58.2]},
      "bbox" => [26.4, 58.2, 26.4, 58.2],
      "properties" => %{
        "datetime" => nil,
        "start_datetime" => "2024-01-01T00:00:00.123Z",
        "end_datetime" => "2024-01-03T00:00:00Z"
      }
    })

    {:ok, conn: build_conn()}
  end

  defp feature(response, id), do: Enum.find(response["features"], &(&1["id"] == id))

  defp get_json(path), do: build_conn() |> get(path) |> json_response(200)

  test "/search, /collections/:id/items and the single item return identical Item JSON", %{
    conn: conn
  } do
    search = conn |> get(~p"/stac/api/v1/search?collections=#{@collection}") |> json_response(200)
    items = get_json(~p"/stac/api/v1/collections/#{@collection}/items")

    for id <- ["instant-item", "range-item"] do
      single = get_json(~p"/stac/api/v1/collections/#{@collection}/items/#{id}")

      assert feature(search, id) == single
      assert feature(items, id) == single
    end
  end

  test "properties.datetime is the written value after normalisation on every endpoint" do
    search = get_json(~p"/stac/api/v1/search?collections=#{@collection}")
    items = get_json(~p"/stac/api/v1/collections/#{@collection}/items")

    for response <- [search, items] do
      assert feature(response, "instant-item")["properties"]["datetime"] ==
               "2024-01-02T00:00:00Z"

      assert Map.take(feature(response, "range-item")["properties"], [
               "datetime",
               "start_datetime",
               "end_datetime"
             ]) == %{
               "datetime" => nil,
               "start_datetime" => "2024-01-01T00:00:00.123Z",
               "end_datetime" => "2024-01-03T00:00:00Z"
             }
    end

    single = get_json(~p"/stac/api/v1/collections/#{@collection}/items/instant-item")
    assert single["properties"]["datetime"] == "2024-01-02T00:00:00Z"
  end

  test "LineString and MultiPoint items are the same GeoJSON on every endpoint, without crs" do
    collection = "public-item-geometries"
    auth_conn = authenticated_conn(build_conn())

    post(auth_conn, ~p"/stac/manage/v1/collections", %{
      "id" => collection,
      "description" => "Geometry types beyond Point and Polygon",
      "license" => "CC-BY-4.0"
    })

    geometries = %{
      "line-item" => %{"type" => "LineString", "coordinates" => [[26.7, 58.4], [26.8, 58.5]]},
      "multipoint-item" => %{
        "type" => "MultiPoint",
        "coordinates" => [[26.7, 58.4], [26.8, 58.5]]
      }
    }

    for {id, geometry} <- geometries do
      response =
        post(auth_conn, ~p"/stac/manage/v1/items", %{
          "id" => id,
          "collection_id" => collection,
          "geometry" => geometry,
          "bbox" => [26.7, 58.4, 26.8, 58.5],
          "properties" => %{"datetime" => "2024-01-02T00:00:00Z"}
        })

      assert response.status == 201
    end

    search = get_json(~p"/stac/api/v1/search?collections=#{collection}")
    items = get_json(~p"/stac/api/v1/collections/#{collection}/items")

    for {id, geometry} <- geometries do
      single = get_json(~p"/stac/api/v1/collections/#{collection}/items/#{id}")

      assert feature(search, id) == single
      assert feature(items, id) == single
      assert single["geometry"] == geometry
      refute Map.has_key?(single["geometry"], "crs")
    end
  end

  test "no public endpoint returns a top-level datetime", %{conn: conn} do
    post_search =
      conn
      |> post(~p"/stac/api/v1/search", %{"collections" => [@collection]})
      |> json_response(200)

    features =
      post_search["features"] ++
        get_json(~p"/stac/api/v1/search?collections=#{@collection}")["features"] ++
        get_json(~p"/stac/api/v1/collections/#{@collection}/items")["features"] ++
        [
          get_json(~p"/stac/api/v1/collections/#{@collection}/items/instant-item"),
          get_json(~p"/stac/api/v1/collections/#{@collection}/items/range-item")
        ]

    assert length(features) == 8

    for feature <- features do
      refute Map.has_key?(feature, "datetime")
    end
  end
end
