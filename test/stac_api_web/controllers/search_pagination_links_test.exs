defmodule StacApiWeb.SearchPaginationLinksTest do
  use StacApiWeb.ConnCase, async: true

  @point %{"type" => "Point", "coordinates" => [26.7, 58.4]}
  @polygon %{
    "type" => "Polygon",
    "coordinates" => [[[26.0, 58.0], [27.5, 58.0], [27.5, 59.0], [26.0, 59.0], [26.0, 58.0]]]
  }

  setup %{conn: conn} do
    auth_conn = authenticated_conn(conn)

    post(auth_conn, ~p"/stac/manage/v1/collections", %{
      "id" => "links-collection",
      "title" => "Links Collection",
      "description" => "Exercises POST search pagination links",
      "license" => "CC-BY-4.0"
    })

    [
      {"links-tartu", [26.7, 58.4], "2024-01-03T00:00:00Z"},
      {"links-elva", [26.4, 58.2], "2024-01-02T00:00:00Z"},
      {"links-tallinn", [24.7, 59.4], "2024-01-01T00:00:00Z"}
    ]
    |> Enum.each(fn {id, [lon, lat] = coordinates, datetime} ->
      post(auth_conn, ~p"/stac/manage/v1/items", %{
        "id" => id,
        "collection_id" => "links-collection",
        "geometry" => %{"type" => "Point", "coordinates" => coordinates},
        "bbox" => [lon, lat, lon, lat],
        "properties" => %{"datetime" => datetime}
      })
    end)

    {:ok, conn: build_conn()}
  end

  defp ids(response), do: response["features"] |> Enum.map(& &1["id"]) |> Enum.sort()

  defp link(response, rel), do: Enum.find(response["links"], &(&1["rel"] == rel))

  test "POST search with a Point or Polygon intersects returns the matching items", %{conn: conn} do
    point_response =
      conn
      |> post(~p"/stac/api/v1/search", %{
        "collections" => ["links-collection"],
        "intersects" => @point
      })
      |> json_response(200)

    assert ids(point_response) == ["links-tartu"]

    polygon_response =
      build_conn()
      |> post(~p"/stac/api/v1/search", %{
        "collections" => ["links-collection"],
        "intersects" => @polygon
      })
      |> json_response(200)

    assert ids(polygon_response) == ["links-elva", "links-tartu"]
  end

  test "POST search links are POST links that carry the full body with the new offset", %{
    conn: conn
  } do
    body = %{"collections" => ["links-collection"], "intersects" => @polygon, "limit" => 1}

    response = conn |> post(~p"/stac/api/v1/search", body) |> json_response(200)

    self_link = link(response, "self")
    next_link = link(response, "next")

    for search_link <- [self_link, next_link] do
      assert search_link["method"] == "POST"
      assert URI.parse(search_link["href"]).path == "/stac/api/v1/search"
      assert URI.parse(search_link["href"]).query == nil
      refute Map.has_key?(search_link, "merge")
    end

    assert self_link["body"] == body
    assert next_link["body"] == Map.put(body, "offset", 1)
    assert is_integer(next_link["body"]["offset"]) and is_integer(next_link["body"]["limit"])

    second_page = build_conn() |> post(~p"/stac/api/v1/search", next_link["body"])
    prev_link = link(json_response(second_page, 200), "prev")

    assert prev_link["method"] == "POST"
    assert prev_link["body"] == Map.put(body, "offset", 0)
  end

  test "following POST next links with limit=1 returns every item exactly once", %{conn: conn} do
    first_body = %{"collections" => ["links-collection"], "limit" => 1}

    collected =
      Stream.unfold({conn, first_body}, fn
        nil ->
          nil

        {request_conn, body} ->
          response = request_conn |> post(~p"/stac/api/v1/search", body) |> json_response(200)

          next_state =
            case link(response, "next") do
              nil -> nil
              next_link -> {build_conn(), next_link["body"]}
            end

          {Enum.map(response["features"], & &1["id"]), next_state}
      end)
      |> Enum.to_list()
      |> List.flatten()

    assert Enum.sort(collected) == ["links-elva", "links-tallinn", "links-tartu"]
  end

  test "a body with a nested object and a list of objects cannot crash link building", %{
    conn: conn
  } do
    body = %{
      "collections" => ["links-collection"],
      "intersects" => @polygon,
      "sortby" => [%{"field" => "id", "direction" => "asc"}],
      "limit" => 1
    }

    response = conn |> post(~p"/stac/api/v1/search", body) |> json_response(200)

    assert link(response, "self")["body"] == body
    assert link(response, "next")["body"]["sortby"] == body["sortby"]
    assert link(response, "next")["body"]["intersects"] == @polygon
  end

  test "GET search links stay GET links", %{conn: conn} do
    response =
      conn
      |> get(~p"/stac/api/v1/search", %{"collections" => "links-collection", "limit" => "1"})
      |> json_response(200)

    for rel <- ["self", "next"] do
      search_link = link(response, rel)
      refute Map.has_key?(search_link, "method")
      refute Map.has_key?(search_link, "body")
    end

    query =
      link(response, "next")["href"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert query == %{"collections" => "links-collection", "limit" => "1", "offset" => "1"}
  end

  test "a GET query with a nested object and a list of objects cannot crash link building", %{
    conn: conn
  } do
    response =
      conn
      |> get(
        "/stac/api/v1/search?collections=links-collection&limit=1" <>
          "&query[description][eq]=x&sortby[][field]=id&sortby[][direction]=asc"
      )
      |> json_response(200)

    next_link = link(response, "next")
    refute Map.has_key?(next_link, "method")

    query = next_link["href"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert Jason.decode!(query["query"]) == %{"description" => %{"eq" => "x"}}
    assert Jason.decode!(query["sortby"]) == [%{"field" => "id", "direction" => "asc"}]

    assert build_conn() |> get(next_link["href"]) |> json_response(200)
  end
end
