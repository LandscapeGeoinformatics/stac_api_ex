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

  defp follow(%{"method" => "POST", "body" => body}),
    do: build_conn() |> post(~p"/stac/api/v1/search", body) |> json_response(200)

  defp follow(%{"href" => href}), do: build_conn() |> get(href) |> json_response(200)

  # Ids of this page and of every page reached by following next.
  defp collect_ids(response) do
    page_ids = Enum.map(response["features"], & &1["id"])

    case link(response, "next") do
      nil -> page_ids
      next_link -> page_ids ++ collect_ids(follow(next_link))
    end
  end

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
    # sortby is a known parameter (Sort extension), so it goes back in its GET form.
    assert query["sortby"] == "id"

    assert build_conn() |> get(next_link["href"]) |> json_response(200)
  end

  test "limit above 100 returns 100 per page and following next gives every item once" do
    auth_conn = authenticated_conn(build_conn())

    post(auth_conn, ~p"/stac/manage/v1/collections", %{
      "id" => "links-many",
      "description" => "More items than the maximum page size",
      "license" => "CC-BY-4.0"
    })

    # Distinct datetimes, so the datetime order is unambiguous across pages.
    expected =
      for n <- 1..120 do
        id = "many-#{n}"

        post(auth_conn, ~p"/stac/manage/v1/items", %{
          "id" => id,
          "collection_id" => "links-many",
          "geometry" => %{"type" => "Point", "coordinates" => [26.0, 58.0]},
          "bbox" => [26.0, 58.0, 26.0, 58.0],
          "properties" => %{
            "datetime" => DateTime.add(~U[2023-01-01 00:00:00Z], n * 60) |> DateTime.to_iso8601()
          }
        })

        id
      end

    get_first =
      build_conn()
      |> get(~p"/stac/api/v1/search", %{"collections" => "links-many", "limit" => "150"})
      |> json_response(200)

    post_first =
      build_conn()
      |> post(~p"/stac/api/v1/search", %{"collections" => ["links-many"], "limit" => 150})
      |> json_response(200)

    for first_page <- [get_first, post_first] do
      assert length(first_page["features"]) == 100
      assert first_page["context"]["limit"] == 100

      collected = collect_ids(first_page)
      assert length(collected) == 120
      assert Enum.sort(collected) == Enum.sort(expected)
    end
  end

  test "limit below 1 or not an integer returns 400", %{conn: conn} do
    for limit <- ["0", "-1", "2.0", "abc"] do
      response =
        get(conn, ~p"/stac/api/v1/search", %{
          "collections" => "links-collection",
          "limit" => limit
        })

      assert json_response(response, 400)["error"] =~ "limit"
    end

    for limit <- [0, 2.0] do
      response =
        post(build_conn(), ~p"/stac/api/v1/search", %{
          "collections" => ["links-collection"],
          "limit" => limit
        })

      assert json_response(response, 400)["error"] =~ "limit"
    end
  end

  test "GET links keep a + offset in datetime and an & in an id", %{conn: conn} do
    post(authenticated_conn(build_conn()), ~p"/stac/manage/v1/items", %{
      "id" => "links-a&b",
      "collection_id" => "links-collection",
      "geometry" => %{"type" => "Point", "coordinates" => [26.5, 58.3]},
      "bbox" => [26.5, 58.3, 26.5, 58.3],
      "properties" => %{"datetime" => "2024-01-04T00:00:00Z"}
    })

    params = %{
      "ids" => "links-a&b,links-tartu,links-elva",
      "datetime" => "2024-01-01T12:00:00+02:00/2024-01-05T02:00:00+02:00"
    }

    all_at_once = conn |> get(~p"/stac/api/v1/search", params) |> json_response(200)
    assert ids(all_at_once) == ["links-a&b", "links-elva", "links-tartu"]

    first_page =
      build_conn()
      |> get(~p"/stac/api/v1/search", Map.put(params, "limit", "1"))
      |> json_response(200)

    query =
      link(first_page, "next")["href"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert query["datetime"] == params["datetime"]
    assert query["ids"] == params["ids"]

    assert follow(link(first_page, "self"))["features"] == first_page["features"]
    assert Enum.sort(collect_ids(first_page)) == ids(all_at_once)
  end
end
