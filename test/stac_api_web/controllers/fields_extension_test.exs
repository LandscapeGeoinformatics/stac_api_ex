defmodule StacApiWeb.FieldsExtensionTest do
  use StacApiWeb.ConnCase, async: true

  setup %{conn: conn} do
    auth_conn = authenticated_conn(conn)

    post(auth_conn, ~p"/stac/manage/v1/collections", %{
      "id" => "fields-collection",
      "title" => "Fields Collection",
      "description" => "Exercises STAC Fields responses",
      "license" => "CC-BY-4.0"
    })

    Enum.each(1..2, fn number ->
      post(auth_conn, ~p"/stac/manage/v1/items", %{
        "id" => "fields-item-#{number}",
        "collection_id" => "fields-collection",
        "geometry" => %{"type" => "Point", "coordinates" => [number, number]},
        "bbox" => [number, number, number, number],
        "properties" => %{
          "datetime" => "2024-01-0#{number}T00:00:00Z",
          "description" => "full payload #{number}",
          "table:columns" => Enum.map(1..50, &"column-#{&1}")
        }
      })
    end)

    {:ok, conn: build_conn()}
  end

  test "GET search keeps full items without fields and supports nested exclusions", %{conn: conn} do
    full =
      conn
      |> get(~p"/stac/api/v1/search", %{"collections" => "fields-collection"})
      |> json_response(200)

    filtered =
      build_conn()
      |> get(~p"/stac/api/v1/search", %{
        "collections" => "fields-collection",
        "fields" => "-properties.table:columns"
      })
      |> json_response(200)

    assert full_item = hd(full["features"])
    assert full_item["properties"]["table:columns"]

    assert filtered_item = hd(filtered["features"])
    assert filtered_item["properties"]["description"]
    refute Map.has_key?(filtered_item["properties"], "table:columns")
    assert byte_size(Jason.encode!(filtered)) < byte_size(Jason.encode!(full))
  end

  test "GET collection items and POST search apply the same include selection", %{conn: conn} do
    fields = "id,collection,properties.datetime"

    collection_response =
      conn
      |> get(~p"/stac/api/v1/collections/fields-collection/items", %{"fields" => fields})
      |> json_response(200)

    search_response =
      build_conn()
      |> post(~p"/stac/api/v1/search", %{
        "collections" => ["fields-collection"],
        "fields" => %{
          "include" => ["id", "collection", "properties.datetime"],
          "exclude" => ["id"]
        }
      })
      |> json_response(200)

    assert Enum.all?(collection_response["features"], fn feature ->
             Map.keys(feature) |> Enum.sort() == ["collection", "id", "properties"] and
               Map.keys(feature["properties"]) == ["datetime"]
           end)

    assert Enum.all?(search_response["features"], fn feature ->
             Map.keys(feature) |> Enum.sort() == ["collection", "id", "properties"] and
               Map.keys(feature["properties"]) == ["datetime"]
           end)
  end

  test "invalid fields return 400 and pagination retains fields", %{conn: conn} do
    invalid =
      conn
      |> get(~p"/stac/api/v1/collections/fields-collection/items", %{"fields" => ","})
      |> json_response(400)

    assert invalid["error"] =~ "fields"

    response =
      build_conn()
      |> get(~p"/stac/api/v1/collections/fields-collection/items", %{
        "fields" => "id",
        "limit" => "1"
      })
      |> json_response(200)

    next_link = Enum.find(response["links"], &(&1["rel"] == "next"))
    query = next_link["href"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["fields"] == "id"
  end

  test "all Fields endpoints share full, empty, and exclude-only behavior", %{conn: conn} do
    full_responses = [
      get(conn, ~p"/stac/api/v1/search", %{"collections" => "fields-collection"}),
      post(build_conn(), ~p"/stac/api/v1/search", %{"collections" => ["fields-collection"]}),
      get(build_conn(), ~p"/stac/api/v1/collections/fields-collection/items")
    ]

    Enum.each(full_responses, fn response ->
      assert hd(json_response(response, 200)["features"])["properties"]["table:columns"]
    end)

    empty_responses = [
      get(conn, ~p"/stac/api/v1/search", %{"collections" => "fields-collection", "fields" => ""}),
      post(build_conn(), ~p"/stac/api/v1/search", %{
        "collections" => ["fields-collection"],
        "fields" => %{}
      }),
      get(build_conn(), ~p"/stac/api/v1/collections/fields-collection/items", %{"fields" => ""})
    ]

    Enum.each(empty_responses, fn response ->
      feature = hd(json_response(response, 200)["features"])

      assert Map.keys(feature) |> Enum.sort() == [
               "assets",
               "bbox",
               "geometry",
               "id",
               "links",
               "properties",
               "stac_version",
               "type"
             ]

      assert Map.keys(feature["properties"]) == ["datetime"]
    end)

    include_responses = [
      get(conn, ~p"/stac/api/v1/search", %{
        "collections" => "fields-collection",
        "fields" => "id,collection,properties.datetime"
      }),
      post(build_conn(), ~p"/stac/api/v1/search", %{
        "collections" => ["fields-collection"],
        "fields" => %{"include" => ["id", "collection", "properties.datetime"]}
      }),
      get(build_conn(), ~p"/stac/api/v1/collections/fields-collection/items", %{
        "fields" => "id,collection,properties.datetime"
      })
    ]

    Enum.each(include_responses, fn response ->
      feature = hd(json_response(response, 200)["features"])
      assert Map.keys(feature) |> Enum.sort() == ["collection", "id", "properties"]
      assert Map.keys(feature["properties"]) == ["datetime"]
    end)

    exclude_responses = [
      get(conn, ~p"/stac/api/v1/search", %{
        "collections" => "fields-collection",
        "fields" => "-properties.table:columns"
      }),
      post(build_conn(), ~p"/stac/api/v1/search", %{
        "collections" => ["fields-collection"],
        "fields" => %{"exclude" => ["properties.table:columns"]}
      }),
      get(build_conn(), ~p"/stac/api/v1/collections/fields-collection/items", %{
        "fields" => "-properties.table:columns"
      })
    ]

    Enum.each(exclude_responses, fn response ->
      properties = hd(json_response(response, 200)["features"])["properties"]
      assert properties["description"]
      refute Map.has_key?(properties, "table:columns")
    end)
  end

  test "all Fields endpoints reject malformed input and retain fields in pagination links", %{
    conn: conn
  } do
    invalid_responses = [
      get(conn, ~p"/stac/api/v1/search", %{"fields" => ","}),
      post(build_conn(), ~p"/stac/api/v1/search", %{"fields" => "id"}),
      get(build_conn(), ~p"/stac/api/v1/collections/fields-collection/items", %{"fields" => ","})
    ]

    Enum.each(invalid_responses, fn response ->
      assert json_response(response, 400)["error"] =~ "fields"
    end)

    paginated_responses = [
      get(conn, ~p"/stac/api/v1/search", %{
        "collections" => "fields-collection",
        "fields" => "id",
        "limit" => "1"
      }),
      post(build_conn(), ~p"/stac/api/v1/search", %{
        "collections" => ["fields-collection"],
        "fields" => %{"include" => ["id"]},
        "limit" => 1
      }),
      get(build_conn(), ~p"/stac/api/v1/collections/fields-collection/items", %{
        "fields" => "id",
        "limit" => "1"
      })
    ]

    Enum.each(paginated_responses, fn response ->
      next_link = json_response(response, 200)["links"] |> Enum.find(&(&1["rel"] == "next"))
      query = next_link["href"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert query["fields"] == "id"
    end)
  end
end
