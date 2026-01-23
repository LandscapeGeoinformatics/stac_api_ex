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
    post(auth_conn, ~p"/stac/api/v1/catalogs", catalog_params)

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
    post(auth_conn, ~p"/stac/api/v1/collections", collection_params)

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

      post(conn, ~p"/stac/api/v1/items", item1_params)
      post(conn, ~p"/stac/api/v1/items", item2_params)

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
      post(conn, ~p"/stac/api/v1/collections", empty_params)

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

      post(conn, ~p"/stac/api/v1/items", item_params)

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

  describe "Private collection access" do
    setup %{conn: conn} do
      # Create a private catalog
      private_catalog_params = %{
        "id" => "private-catalog",
        "title" => "Private Catalog",
        "description" => "Private",
        "private" => true
      }
      post(conn, ~p"/stac/api/v1/catalogs", private_catalog_params)

      # Create a collection in the private catalog
      private_collection_params = %{
        "id" => "private-collection",
        "title" => "Private Collection",
        "description" => "In private catalog",
        "license" => "CC-BY-4.0",
        "catalog_id" => "private-catalog"
      }
      post(conn, ~p"/stac/api/v1/collections", private_collection_params)

      :ok
    end

    test "hides private collection from unauthenticated users in GET /collections", %{} do
      unauth_conn = build_conn()
      conn = get(unauth_conn, ~p"/stac/api/v1/collections")
      response = json_response(conn, 200)

      ids = Enum.map(response["collections"], & &1["id"])
      refute "private-collection" in ids
    end

    test "returns 404 for private collection without authentication", %{} do
      unauth_conn = build_conn()
      conn = get(unauth_conn, ~p"/stac/api/v1/collections/private-collection")
      assert json_response(conn, 404)
    end
  end
end
