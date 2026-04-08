defmodule StacApiWeb.CollectionsControllerTest do
  use StacApiWeb.ConnCase, async: true
  alias StacApi.Data.{Collection, Item, Catalog}
  alias StacApi.Repo

  setup %{conn: conn} do
    auth_conn = authenticated_conn(conn)
    
    catalog_params = %{
      "id" => "test-catalog",
      "title" => "Test Catalog",
      "description" => "Test"
    }
    post(auth_conn, ~p"/stac/manage/v1/catalogs", catalog_params)

    collection_params = %{
      "id" => "test-collection",
      "title" => "Test Collection",
      "description" => "Test",
      "license" => "CC-BY-4.0",
      "catalog_id" => "test-catalog",
      "extent" => %{
        "spatial" => %{"bbox" => [[-180, -90, 180, 90]]},
        "temporal" => %{"interval" => [["2020-01-01T00:00:00Z", "2024-12-31T23:59:59Z"]]}
      }
    }
    post(auth_conn, ~p"/stac/manage/v1/collections", collection_params)

    {:ok, conn: auth_conn}
  end

  describe "GET /collections - list all collections" do
    test "returns all collections", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections")
      assert response = json_response(conn, 200)
      assert is_list(response["collections"])
      assert length(response["collections"]) > 0
      assert is_list(response["links"])
    end

    test "returns collection with proper structure", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections")
      response = json_response(conn, 200)

      collection = Enum.find(response["collections"], &(&1["id"] == "test-collection"))
      assert collection != nil, "Collection 'test-collection' not found in response"
      assert collection["title"] == "Test Collection"
      assert collection["type"] == "Collection"
      assert collection["license"] == "CC-BY-4.0"
      assert is_list(collection["links"])
    end
  end

  describe "GET /collections/:id - show specific collection" do
    test "returns a specific collection with all STAC properties", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/test-collection")
      assert response = json_response(conn, 200)

      assert response["id"] == "test-collection"
      assert response["title"] == "Test Collection"
      assert response["type"] == "Collection"
      assert response["license"] == "CC-BY-4.0"
      assert is_list(response["links"])
      assert is_map(response["extent"])
    end

    test "returns 404 for non-existent collection", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/non-existent")
      assert response = json_response(conn, 404)
      assert response["error"] =~ "not found"
    end

    test "returns proper STAC collection format", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/test-collection")
      response = json_response(conn, 200)

      # Check required STAC properties
      assert response["stac_version"]
      assert response["stac_extensions"] || true  # Can be empty array or not present
      assert response["type"] == "Collection"
      assert response["id"]
      assert response["title"]
      assert response["description"]
      assert response["license"]
    end
  end

  describe "GET /collections/:id/items - list items in collection" do
    setup %{conn: conn} do
      # Create test items in the collection
      item1_params = %{
        "id" => "item-1",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{"description" => "First item"}
      }

      item2_params = %{
        "id" => "item-2",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [10, 10]},
        "bbox" => [9, 9, 11, 11],
        "datetime" => "2024-01-02T12:00:00Z",
        "properties" => %{"description" => "Second item"}
      }

      post(conn, ~p"/stac/manage/v1/items", item1_params)
      post(conn, ~p"/stac/manage/v1/items", item2_params)

      :ok
    end

    test "returns all items in a collection", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/test-collection/items")
      assert response = json_response(conn, 200)

      assert response["type"] == "FeatureCollection"
      assert is_list(response["features"])
      assert length(response["features"]) == 2
    end

    test "returns items with proper GeoJSON format", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/test-collection/items")
      response = json_response(conn, 200)

      features = response["features"]
      feature = Enum.find(features, &(&1["id"] == "item-1"))

      assert feature["type"] == "Feature"
      assert feature["id"] == "item-1"
      assert feature["geometry"]
      assert feature["bbox"]
      assert feature["properties"]
      assert is_list(feature["links"])
    end

    test "returns empty features list when collection has no items", %{conn: conn} do
      # Create empty collection
      empty_params = %{
        "id" => "empty-collection",
        "title" => "Empty",
        "description" => "No items",
        "license" => "CC-BY-4.0"
      }
      post(conn, ~p"/stac/manage/v1/collections", empty_params)

      conn = get(conn, ~p"/stac/api/v1/collections/empty-collection/items")
      assert response = json_response(conn, 200)

      assert response["type"] == "FeatureCollection"
      assert response["features"] == []
    end

    test "returns 404 for non-existent collection", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/non-existent/items")
      assert response = json_response(conn, 404)
      assert response["error"] =~ "not found"
    end
  end

  describe "GET /collections/:collection_id/items/:item_id - show specific item" do
    setup %{conn: conn} do
      item_params = %{
        "id" => "specific-item",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [5, 5]},
        "bbox" => [4, 4, 6, 6],
        "datetime" => "2024-01-15T12:00:00Z",
        "properties" => %{"description" => "Specific test item", "source" => "test"}
      }

      post(conn, ~p"/stac/manage/v1/items", item_params)

      :ok
    end

    test "returns a specific item from a collection", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/test-collection/items/specific-item")
      assert response = json_response(conn, 200)

      assert response["id"] == "specific-item"
      assert response["type"] == "Feature"
      assert response["geometry"]
      assert response["bbox"]
      assert response["properties"]["description"] == "Specific test item"
      assert response["collection"] == "test-collection"
    end

    test "returns item as STAC Feature object", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/test-collection/items/specific-item")
      response = json_response(conn, 200)

      assert response["stac_version"]
      assert response["stac_extensions"] || true
      assert response["type"] == "Feature"
      assert response["geometry"]
      assert response["bbox"]
      assert response["properties"]
      assert response["datetime"] || response["properties"]["datetime"]
      assert is_list(response["links"])
    end

    test "returns 404 for non-existent item", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/test-collection/items/non-existent")
      assert response = json_response(conn, 404)
      assert response["error"] =~ "not found"
    end

    test "returns 404 for non-existent collection", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/non-existent/items/any-item")
      assert response = json_response(conn, 404)
      assert response["error"] =~ "not found"
    end
  end

  describe "Private catalog access control" do
    setup %{conn: conn} do
      # Create a private catalog
      post(conn, ~p"/stac/manage/v1/catalogs", %{
        "id" => "private-catalog",
        "title" => "Private Catalog",
        "description" => "Only visible to authenticated users",
        "private" => true
      })

      # Create a collection inside the private catalog
      post(conn, ~p"/stac/manage/v1/collections", %{
        "id" => "private-collection",
        "title" => "Private Collection",
        "description" => "In private catalog",
        "license" => "CC-BY-4.0",
        "catalog_id" => "private-catalog"
      })

      # Create an item inside that collection
      post(conn, ~p"/stac/manage/v1/items", %{
        "id" => "private-item",
        "collection_id" => "private-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [25.0, 58.5]},
        "bbox" => [24.0, 57.5, 26.0, 59.5],
        "datetime" => "2024-06-01T12:00:00Z",
        "properties" => %{"description" => "Private item"}
      })

      :ok
    end

    # --- Unauthenticated: must NOT see private resources ---

    test "GET /collections — hides private collection from unauthenticated users" do
      conn = get(build_conn(), ~p"/stac/api/v1/collections")
      response = json_response(conn, 200)
      ids = Enum.map(response["collections"], & &1["id"])
      refute "private-collection" in ids
    end

    test "GET /collections/:id — returns 404 for private collection without auth" do
      conn = get(build_conn(), ~p"/stac/api/v1/collections/private-collection")
      assert json_response(conn, 404)
    end

    test "GET /collections/:id/items — returns 404 for private collection items without auth" do
      conn = get(build_conn(), ~p"/stac/api/v1/collections/private-collection/items")
      assert json_response(conn, 404)
    end

    test "GET /collections/:collection_id/items/:item_id — returns 404 for private item without auth" do
      conn = get(build_conn(), ~p"/stac/api/v1/collections/private-collection/items/private-item")
      assert json_response(conn, 404)
    end

    test "POST /search — excludes private items from unauthenticated search" do
      conn = post(build_conn(), ~p"/stac/api/v1/search", %{"collections" => ["private-collection"]})
      response = json_response(conn, 200)
      ids = Enum.map(response["features"], & &1["id"])
      refute "private-item" in ids
    end

    # --- RO key: must see private resources ---

    test "GET /collections — shows private collection with RO key" do
      conn = get(read_only_conn(build_conn()), ~p"/stac/api/v1/collections")
      response = json_response(conn, 200)
      ids = Enum.map(response["collections"], & &1["id"])
      assert "private-collection" in ids
    end

    test "GET /collections/:id — returns private collection with RO key" do
      conn = get(read_only_conn(build_conn()), ~p"/stac/api/v1/collections/private-collection")
      response = json_response(conn, 200)
      assert response["id"] == "private-collection"
      assert response["type"] == "Collection"
    end

    test "GET /collections/:id/items — returns items from private collection with RO key" do
      conn = get(read_only_conn(build_conn()), ~p"/stac/api/v1/collections/private-collection/items")
      response = json_response(conn, 200)
      assert response["type"] == "FeatureCollection"
      ids = Enum.map(response["features"], & &1["id"])
      assert "private-item" in ids
    end

    test "GET /collections/:collection_id/items/:item_id — returns private item with RO key" do
      conn = get(read_only_conn(build_conn()), ~p"/stac/api/v1/collections/private-collection/items/private-item")
      response = json_response(conn, 200)
      assert response["id"] == "private-item"
      assert response["type"] == "Feature"
    end

    test "POST /search — includes private items with RO key" do
      conn = post(read_only_conn(build_conn()), ~p"/stac/api/v1/search", %{"collections" => ["private-collection"]})
      response = json_response(conn, 200)
      ids = Enum.map(response["features"], & &1["id"])
      assert "private-item" in ids
    end

    # --- RW key: must also see private resources ---

    test "GET /collections — shows private collection with RW key" do
      conn = get(authenticated_conn(build_conn()), ~p"/stac/api/v1/collections")
      response = json_response(conn, 200)
      ids = Enum.map(response["collections"], & &1["id"])
      assert "private-collection" in ids
    end

    test "GET /collections/:id — returns private collection with RW key" do
      conn = get(authenticated_conn(build_conn()), ~p"/stac/api/v1/collections/private-collection")
      response = json_response(conn, 200)
      assert response["id"] == "private-collection"
    end

    test "GET /collections/:id/items — returns items from private collection with RW key" do
      conn = get(authenticated_conn(build_conn()), ~p"/stac/api/v1/collections/private-collection/items")
      response = json_response(conn, 200)
      ids = Enum.map(response["features"], & &1["id"])
      assert "private-item" in ids
    end

    test "GET /collections/:collection_id/items/:item_id — returns private item with RW key" do
      conn = get(authenticated_conn(build_conn()), ~p"/stac/api/v1/collections/private-collection/items/private-item")
      response = json_response(conn, 200)
      assert response["id"] == "private-item"
    end

    test "POST /search — includes private items with RW key" do
      conn = post(authenticated_conn(build_conn()), ~p"/stac/api/v1/search", %{"collections" => ["private-collection"]})
      response = json_response(conn, 200)
      ids = Enum.map(response["features"], & &1["id"])
      assert "private-item" in ids
    end
  end

  describe "STAC conformance — Issue 3: no properties field on Collection" do
    test "collection response must not contain a top-level properties field", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/test-collection")
      response = json_response(conn, 200)
      refute Map.has_key?(response, "properties"),
        "STAC Collections must not have a top-level 'properties' field"
    end

    test "collections list must not contain properties on any collection", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections")
      response = json_response(conn, 200)
      Enum.each(response["collections"], fn col ->
        refute Map.has_key?(col, "properties"),
          "Collection #{col["id"]} must not expose 'properties'"
      end)
    end
  end

  describe "STAC conformance — Issue 6: no Ecto timestamps in STAC responses" do
    test "collection GET must not leak inserted_at or updated_at", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/test-collection")
      response = json_response(conn, 200)
      refute Map.has_key?(response, "inserted_at"), "inserted_at must not appear in STAC response"
      refute Map.has_key?(response, "updated_at"), "updated_at must not appear in STAC response"
    end
  end

  describe "STAC conformance — Issue 5: parent link must be STAC-conformant" do
    test "collection parent link points to root, not a /catalog/ path", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/test-collection")
      response = json_response(conn, 200)
      parent_link = Enum.find(response["links"], &(&1["rel"] == "parent"))
      assert parent_link, "Collection must have a parent link"
      refute String.contains?(parent_link["href"], "/catalog/"),
        "parent link must not use non-standard /catalog/ path, got: #{parent_link["href"]}"
    end
  end

  describe "STAC conformance — Issue 4: keywords and providers round-trip" do
    setup %{conn: conn} do
      params = %{
        "id" => "kw-collection",
        "title" => "Keywords Test",
        "description" => "Testing keywords and providers",
        "license" => "CC0-1.0",
        "catalog_id" => "test-catalog",
        "keywords" => ["ndvi", "sentinel-2", "estonia"],
        "providers" => [%{
          "name" => "University of Tartu HPC",
          "roles" => ["producer"],
          "url" => "https://hpc.ut.ee"
        }],
        "extent" => %{
          "spatial" => %{"bbox" => [[21.7, 57.5, 28.2, 59.9]]},
          "temporal" => %{"interval" => [["2017-01-01T00:00:00Z", nil]]}
        }
      }
      post(conn, ~p"/stac/manage/v1/collections", params)
      :ok
    end

    test "keywords are stored and returned", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/kw-collection")
      response = json_response(conn, 200)
      assert response["keywords"] == ["ndvi", "sentinel-2", "estonia"]
    end

    test "providers are stored and returned", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/kw-collection")
      response = json_response(conn, 200)
      assert [provider | _] = response["providers"]
      assert provider["name"] == "University of Tartu HPC"
      assert provider["roles"] == ["producer"]
    end
  end

  describe "STAC conformance — Issue 1 & 2: computed spatial and temporal extent" do
    setup %{conn: conn} do
      # Create a collection and add two items with known bounding boxes and date ranges
      col_params = %{
        "id" => "extent-test-collection",
        "title" => "Extent Test",
        "description" => "Tests that extent is computed from items",
        "license" => "CC0-1.0",
        "catalog_id" => "test-catalog"
      }
      post(conn, ~p"/stac/manage/v1/collections", col_params)

      # Item 1: polygon in Estonia-ish area, spring 2017
      item1 = %{
        "id" => "extent-item-1",
        "collection_id" => "extent-test-collection",
        "geometry" => %{
          "type" => "Polygon",
          "coordinates" => [[[21.0, 57.0], [22.0, 57.0], [22.0, 58.0], [21.0, 58.0], [21.0, 57.0]]]
        },
        "bbox" => [21.0, 57.0, 22.0, 58.0],
        "datetime" => nil,
        "properties" => %{
          "datetime" => nil,
          "start_datetime" => "2017-04-01T00:00:00Z",
          "end_datetime" => "2017-05-31T23:59:59Z"
        }
      }

      # Item 2: polygon shifted east, autumn 2024
      item2 = %{
        "id" => "extent-item-2",
        "collection_id" => "extent-test-collection",
        "geometry" => %{
          "type" => "Polygon",
          "coordinates" => [[[26.0, 58.0], [28.0, 58.0], [28.0, 60.0], [26.0, 60.0], [26.0, 58.0]]]
        },
        "bbox" => [26.0, 58.0, 28.0, 60.0],
        "datetime" => nil,
        "properties" => %{
          "datetime" => nil,
          "start_datetime" => "2024-09-01T00:00:00Z",
          "end_datetime" => "2024-10-31T23:59:59Z"
        }
      }

      post(conn, ~p"/stac/manage/v1/items", item1)
      post(conn, ~p"/stac/manage/v1/items", item2)
      :ok
    end

    test "extent.spatial.bbox is present and covers all items", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/extent-test-collection")
      response = json_response(conn, 200)

      assert extent = response["extent"], "extent must be present"
      assert spatial = extent["spatial"], "extent.spatial must be present"
      assert [bbox | _] = spatial["bbox"], "extent.spatial.bbox must be a non-empty list"

      # bbox must be [minx, miny, maxx, maxy] covering both items
      [minx, miny, maxx, maxy] = bbox
      assert minx <= 21.0, "minx should cover western item (21.0)"
      assert miny <= 57.0, "miny should cover southern item (57.0)"
      assert maxx >= 28.0, "maxx should cover eastern item (28.0)"
      assert maxy >= 60.0, "maxy should cover northern item (60.0)"
    end

    test "extent.temporal.interval spans all items using start/end_datetime", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/extent-test-collection")
      response = json_response(conn, 200)

      assert extent = response["extent"]
      assert temporal = extent["temporal"]
      assert [[start_dt, end_dt] | _] = temporal["interval"]

      # start must be <= 2017-04-01 (earliest start_datetime)
      assert start_dt <= "2017-04-01T00:00:00Z",
        "temporal start should be at or before 2017-04-01, got #{start_dt}"

      # end must be >= 2024-10-31 (latest end_datetime)
      assert end_dt >= "2024-10-31T23:59:59Z",
        "temporal end should be at or after 2024-10-31, got #{end_dt}"
    end

    test "temporal extent timestamps have no microseconds (.000000Z)", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/collections/extent-test-collection")
      response = json_response(conn, 200)

      [[start_dt, end_dt]] = response["extent"]["temporal"]["interval"]
      refute String.contains?(start_dt || "", "."), "start_datetime must not contain microseconds"
      refute String.contains?(end_dt || "", "."), "end_datetime must not contain microseconds"
    end
  end
end
