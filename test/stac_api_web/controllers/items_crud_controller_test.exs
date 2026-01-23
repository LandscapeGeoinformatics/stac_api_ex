defmodule StacApiWeb.ItemsCrudControllerTest do
  use StacApiWeb.ConnCase, async: true
  alias StacApi.Data.{Item, Collection, Catalog}
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

  describe "POST /items - create item" do
    test "creates an item successfully", %{conn: conn} do
      params = %{
        "id" => "test-item",
        "collection_id" => "test-collection",
        "stac_version" => "1.0.0",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{"description" => "Test item", "source" => "test"}
      }

      conn = post(conn, ~p"/stac/api/v1/items", params)

      assert response = json_response(conn, 201)
      assert response["success"] == true
      assert response["data"]["id"] == "test-item"
      assert response["data"]["type"] == "Feature"
      assert response["data"]["collection"] == "test-collection"
      assert response["data"]["geometry"]["type"] == "Point"
    end

    test "creates an item with assets", %{conn: conn} do
      params = %{
        "id" => "item-with-assets",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [10, 10]},
        "bbox" => [9, 9, 11, 11],
        "datetime" => "2024-01-02T12:00:00Z",
        "properties" => %{"description" => "Item with assets"},
        "assets" => %{
          "thumbnail" => %{
            "href" => "https://example.com/thumb.jpg",
            "type" => "image/jpeg",
            "title" => "Thumbnail"
          },
          "data" => %{
            "href" => "https://example.com/data.tif",
            "type" => "image/tiff",
            "roles" => ["data"]
          }
        }
      }

      conn = post(conn, ~p"/stac/api/v1/items", params)

      assert response = json_response(conn, 201)
      assert response["success"] == true
      assert is_map(response["data"]["assets"])
      assert response["data"]["assets"]["thumbnail"]["href"] == "https://example.com/thumb.jpg"
    end

    test "returns 409 when item ID already exists", %{conn: conn} do
      params = %{
        "id" => "duplicate-item",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{}
      }

      post(conn, ~p"/stac/api/v1/items", params)

      conn = post(conn, ~p"/stac/api/v1/items", params)
      assert response = json_response(conn, 409)
      assert response["error"] =~ "already exists"
    end

    test "returns 400 when missing required field (id)", %{conn: conn} do
      params = %{
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{}
      }

      conn = post(conn, ~p"/stac/api/v1/items", params)
      assert response = json_response(conn, 400)
      assert response["error"] =~ "id"
    end

    test "returns 400 when missing required field (geometry)", %{conn: conn} do
      params = %{
        "id" => "no-geometry-item",
        "collection_id" => "test-collection",
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{}
      }

      conn = post(conn, ~p"/stac/api/v1/items", params)
      assert response = json_response(conn, 400)
      assert response["error"] =~ "geometry"
    end

    test "returns 400 when collection does not exist", %{conn: conn} do
      params = %{
        "id" => "orphan-item",
        "collection_id" => "non-existent-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{}
      }

      conn = post(conn, ~p"/stac/api/v1/items", params)
      assert response = json_response(conn, 400)
      assert response["error"] =~ "collection"
    end
  end

  describe "GET /items - list all items" do
    setup %{conn: conn} do
      item1_params = %{
        "id" => "item-1",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{"description" => "First"}
      }

      item2_params = %{
        "id" => "item-2",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [10, 10]},
        "bbox" => [9, 9, 11, 11],
        "datetime" => "2024-01-02T12:00:00Z",
        "properties" => %{"description" => "Second"}
      }

      post(conn, ~p"/stac/api/v1/items", item1_params)
      post(conn, ~p"/stac/api/v1/items", item2_params)

      :ok
    end

    test "returns all items", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/items")
      assert response = json_response(conn, 200)

      assert response["type"] == "FeatureCollection"
      assert is_list(response["features"])
      assert length(response["features"]) >= 2
    end

    test "returns items with proper GeoJSON structure", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/items")
      response = json_response(conn, 200)

      features = response["features"]
      item = Enum.find(features, &(&1["id"] == "item-1"))

      assert item["type"] == "Feature"
      assert item["id"] == "item-1"
      assert item["geometry"]
      assert item["bbox"]
      assert item["properties"]
      assert item["collection"]
    end

    test "supports pagination with limit parameter", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/items?limit=1")
      assert response = json_response(conn, 200)

      assert length(response["features"]) <= 1
      assert response["context"]["limit"] == 1
    end
  end

  describe "GET /items/:id - show specific item" do
    setup %{conn: conn} do
      item_params = %{
        "id" => "show-item",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [5, 5]},
        "bbox" => [4, 4, 6, 6],
        "datetime" => "2024-01-15T12:00:00Z",
        "properties" => %{"description" => "Show test"}
      }

      post(conn, ~p"/stac/api/v1/items", item_params)

      :ok
    end

    test "returns a specific item", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/items/show-item")
      assert response = json_response(conn, 200)

      assert response["id"] == "show-item"
      assert response["type"] == "Feature"
      assert response["geometry"]["type"] == "Point"
      assert response["properties"]["description"] == "Show test"
    end

    test "returns item with STAC properties", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/items/show-item")
      response = json_response(conn, 200)

      assert response["stac_version"]
      assert response["type"] == "Feature"
      assert response["id"]
      assert response["geometry"]
      assert response["bbox"]
      assert response["properties"]
      assert response["collection"]
      assert is_list(response["links"])
    end

    test "returns 404 for non-existent item", %{conn: conn} do
      conn = get(conn, ~p"/stac/api/v1/items/non-existent")
      assert response = json_response(conn, 404)
      assert response["error"] =~ "not found"
    end
  end

  describe "PUT /items/:id - update item (full replacement)" do
    setup %{conn: conn} do
      item_params = %{
        "id" => "update-item",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{"description" => "Original"}
      }

      post(conn, ~p"/stac/api/v1/items", item_params)

      :ok
    end

    test "fully replaces an item", %{conn: conn} do
      update_params = %{
        "id" => "update-item",
        "type" => "Feature",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [10, 10]},
        "bbox" => [9, 9, 11, 11],
        "datetime" => "2024-01-02T12:00:00Z",
        "properties" => %{"description" => "Updated"},
        "stac_version" => "1.0.0"
      }

      conn = put(conn, ~p"/stac/api/v1/items/update-item", update_params)

      assert response = json_response(conn, 200)
      assert response["success"] == true
      assert response["data"]["properties"]["description"] == "Updated"
      assert response["data"]["geometry"]["coordinates"] == [10.0, 10.0]
    end

    test "returns 404 when updating non-existent item", %{conn: conn} do
      params = %{
        "id" => "non-existent",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{},
        "stac_version" => "1.0.0"
      }

      conn = put(conn, ~p"/stac/api/v1/items/non-existent", params)
      assert response = json_response(conn, 404)
    end
  end

  describe "PATCH /items/:id - partial update item" do
    setup %{conn: conn} do
      item_params = %{
        "id" => "patch-item",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{"description" => "Original", "source" => "test"}
      }

      post(conn, ~p"/stac/api/v1/items", item_params)

      :ok
    end

    test "partially updates an item", %{conn: conn} do
      patch_params = %{
        "id" => "patch-item",
        "properties" => %{"description" => "Patched", "source" => "test"}
      }

      conn = patch(conn, ~p"/stac/api/v1/items/patch-item", patch_params)

      assert response = json_response(conn, 200)
      assert response["success"] == true
      assert response["data"]["properties"]["description"] == "Patched"
      assert response["data"]["properties"]["source"] == "test"
    end

    test "returns 404 when patching non-existent item", %{conn: conn} do
      params = %{"id" => "non-existent", "properties" => %{"description" => "Test"}}

      conn = patch(conn, ~p"/stac/api/v1/items/non-existent", params)
      assert response = json_response(conn, 404)
    end
  end

  describe "DELETE /items/:id - delete item" do
    setup %{conn: conn} do
      item_params = %{
        "id" => "delete-item",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{}
      }

      post(conn, ~p"/stac/api/v1/items", item_params)

      :ok
    end

    test "deletes an item successfully", %{conn: conn} do
      conn = delete(conn, ~p"/stac/api/v1/items/delete-item")

      assert response = json_response(conn, 200)
      assert response["success"] == true
      assert response["message"] =~ "deleted successfully"

      # Verify it's gone
      get_conn = get(build_conn(), ~p"/stac/api/v1/items/delete-item")
      assert json_response(get_conn, 404)
    end

    test "returns 404 when deleting non-existent item", %{conn: conn} do
      conn = delete(conn, ~p"/stac/api/v1/items/non-existent")
      assert response = json_response(conn, 404)
    end
  end

  describe "POST /items/import - bulk import items" do
    test "imports multiple items at once", %{conn: conn} do
      params = %{
        "features" => [
          %{
            "id" => "bulk-item-1",
            "collection_id" => "test-collection",
            "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
            "bbox" => [-1, -1, 1, 1],
            "datetime" => "2024-01-01T12:00:00Z",
            "properties" => %{"description" => "Bulk 1"}
          },
          %{
            "id" => "bulk-item-2",
            "collection_id" => "test-collection",
            "geometry" => %{"type" => "Point", "coordinates" => [10, 10]},
            "bbox" => [9, 9, 11, 11],
            "datetime" => "2024-01-02T12:00:00Z",
            "properties" => %{"description" => "Bulk 2"}
          }
        ]
      }

      conn = post(conn, ~p"/stac/api/v1/items/import", params)

      assert response = json_response(conn, 200)
      assert response["success"] == true
      assert response["imported"] == 2
      assert response["total"] == 2

      # Verify items were created
      get_conn = get(build_conn(), ~p"/stac/api/v1/items/bulk-item-1")
      assert json_response(get_conn, 200)
    end

    test "reports failures when importing items with invalid data", %{conn: conn} do
      params = %{
        "features" => [
          %{
            "id" => "valid-bulk-item",
            "collection_id" => "test-collection",
            "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
            "bbox" => [-1, -1, 1, 1],
            "datetime" => "2024-01-01T12:00:00Z",
            "properties" => %{}
          },
          %{
            # Missing collection_id
            "id" => "invalid-bulk-item",
            "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
            "bbox" => [-1, -1, 1, 1],
            "datetime" => "2024-01-01T12:00:00Z",
            "properties" => %{}
          }
        ]
      }

      conn = post(conn, ~p"/stac/api/v1/items/import", params)

      assert response = json_response(conn, 200)
      assert response["total"] == 2
      assert response["imported"] == 1
      assert response["failed"] == 1
    end

    test "returns 400 when features array is empty", %{conn: conn} do
      params = %{"features" => []}

      conn = post(conn, ~p"/stac/api/v1/items/import", params)
      assert response = json_response(conn, 400)
      assert response["error"] =~ "at least one"
    end
  end

  describe "Item with assets" do
    test "creates and retrieves item with assets", %{conn: conn} do
      item_params = %{
        "id" => "asset-item",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{},
        "assets" => %{
          "thumbnail" => %{
            "href" => "https://example.com/thumb.jpg",
            "type" => "image/jpeg",
            "title" => "Thumbnail",
            "roles" => ["thumbnail"]
          }
        }
      }

      post_conn = post(conn, ~p"/stac/api/v1/items", item_params)
      assert json_response(post_conn, 201)

      # Retrieve and verify assets
      get_conn = get(conn, ~p"/stac/api/v1/items/asset-item")
      response = json_response(get_conn, 200)

      assert is_map(response["assets"])
      assert response["assets"]["thumbnail"]["href"] == "https://example.com/thumb.jpg"
    end
  end

  describe "Item geometry handling" do
    test "handles Point geometry", %{conn: conn} do
      params = %{
        "id" => "point-item",
        "collection_id" => "test-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{}
      }

      conn = post(conn, ~p"/stac/api/v1/items", params)
      assert response = json_response(conn, 201)
      assert response["data"]["geometry"]["type"] == "Point"
    end

    test "handles Polygon geometry", %{conn: conn} do
      params = %{
        "id" => "polygon-item",
        "collection_id" => "test-collection",
        "geometry" => %{
          "type" => "Polygon",
          "coordinates" => [[
            [0, 0],
            [1, 0],
            [1, 1],
            [0, 1],
            [0, 0]
          ]]
        },
        "bbox" => [0, 0, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{}
      }

      conn = post(conn, ~p"/stac/api/v1/items", params)
      assert response = json_response(conn, 201)
      assert response["data"]["geometry"]["type"] == "Polygon"
    end
  end

  describe "Private catalog item access" do
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
        "description" => "Private",
        "license" => "CC-BY-4.0",
        "catalog_id" => "private-catalog"
      }
      post(conn, ~p"/stac/api/v1/collections", private_collection_params)

      # Create an item in the private collection
      item_params = %{
        "id" => "private-item",
        "collection_id" => "private-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [0, 0]},
        "bbox" => [-1, -1, 1, 1],
        "datetime" => "2024-01-01T12:00:00Z",
        "properties" => %{}
      }
      post(conn, ~p"/stac/api/v1/items", item_params)

      :ok
    end

    test "hides items from private catalogs in GET /items for unauthenticated users", %{} do
      unauth_conn = build_conn()
      conn = get(unauth_conn, ~p"/stac/api/v1/items")
      response = json_response(conn, 200)

      ids = Enum.map(response["features"], & &1["id"])
      refute "private-item" in ids
    end

    test "returns 404 for item in private catalog without authentication", %{} do
      unauth_conn = build_conn()
      conn = get(unauth_conn, ~p"/stac/api/v1/items/private-item")
      assert json_response(conn, 404)
    end
  end
end
