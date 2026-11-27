defmodule StacApiWeb.SortExtensionTest do
  use StacApiWeb.ConnCase, async: true

  alias StacApi.Data.Item
  alias StacApi.Repo

  @one "sort-one"
  @two "sort-two"
  @endpoints [:get_search, :post_search, :items]

  # sort-a and sort-c share a datetime; sort-range has datetime null and sorts
  # by its start_datetime, between sort-b and sort-a.
  setup do
    auth_conn = authenticated_conn(build_conn())

    for id <- [@one, @two] do
      post(auth_conn, ~p"/stac/manage/v1/collections", %{
        "id" => id,
        "description" => "Exercises the Sort extension",
        "license" => "CC-BY-4.0"
      })
    end

    [
      {"sort-a", @one, %{"datetime" => "2024-01-03T00:00:00Z"}},
      {"sort-b", @one, %{"datetime" => "2024-01-01T00:00:00Z"}},
      {"sort-c", @one, %{"datetime" => "2024-01-03T00:00:00Z"}},
      {"sort-range", @one,
       %{
         "datetime" => nil,
         "start_datetime" => "2024-01-02T00:00:00Z",
         "end_datetime" => "2024-01-10T00:00:00Z"
       }},
      {"sort-d", @two, %{"datetime" => "2024-01-02T12:00:00Z"}}
    ]
    |> Enum.each(fn {id, collection, properties} ->
      response =
        post(auth_conn, ~p"/stac/manage/v1/items", %{
          "id" => id,
          "collection_id" => collection,
          "geometry" => %{"type" => "Point", "coordinates" => [26.7, 58.4]},
          "bbox" => [26.7, 58.4, 26.7, 58.4],
          "properties" => properties
        })

      assert response.status == 201
    end)

    :ok
  end

  defp ids(response), do: Enum.map(response["features"], & &1["id"])

  defp link(response, rel), do: Enum.find(response["links"], &(&1["rel"] == rel))

  # GET sortby as the POST form, e.g. "-properties.datetime,id" ->
  # [%{"field" => "properties.datetime", "direction" => "desc"}, %{"field" => "id", ...}]
  defp post_form(sortby) do
    for key <- String.split(sortby, ",") do
      case key do
        "-" <> field -> %{"field" => field, "direction" => "desc"}
        field -> %{"field" => field, "direction" => "asc"}
      end
    end
  end

  defp request(endpoint, sortby, extra \\ %{})

  defp request(:get_search, sortby, extra) do
    params = Map.merge(%{"collections" => @one}, extra) |> maybe_put("sortby", sortby)
    build_conn() |> get(~p"/stac/api/v1/search", params)
  end

  defp request(:post_search, sortby, extra) do
    sortby = if is_binary(sortby), do: post_form(sortby), else: sortby
    body = Map.merge(%{"collections" => [@one]}, extra) |> maybe_put("sortby", sortby)
    build_conn() |> post(~p"/stac/api/v1/search", body)
  end

  defp request(:items, sortby, extra) do
    params = maybe_put(extra, "sortby", sortby)
    build_conn() |> get(~p"/stac/api/v1/collections/#{@one}/items", params)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp ids_via(endpoint, sortby), do: endpoint |> request(sortby) |> json_response(200) |> ids()

  defp follow(%{"method" => "POST", "body" => body}),
    do: build_conn() |> post(~p"/stac/api/v1/search", body) |> json_response(200)

  defp follow(%{"href" => href}), do: build_conn() |> get(href) |> json_response(200)

  # Ids of this page and of every page reached by following next.
  defp collect_ids(response) do
    case link(response, "next") do
      nil -> ids(response)
      next_link -> ids(response) ++ collect_ids(follow(next_link))
    end
  end

  test "sortby orders by properties.datetime and id, ascending and descending, on every endpoint" do
    cases = [
      {"properties.datetime", ["sort-b", "sort-range", "sort-a", "sort-c"]},
      {"-properties.datetime", ["sort-a", "sort-c", "sort-range", "sort-b"]},
      {"id", ["sort-a", "sort-b", "sort-c", "sort-range"]},
      {"-id", ["sort-range", "sort-c", "sort-b", "sort-a"]}
    ]

    for endpoint <- @endpoints, {sortby, expected} <- cases do
      assert ids_via(endpoint, sortby) == expected, "#{endpoint} sortby=#{sortby}"
    end
  end

  test "several keys are applied in the given order" do
    cases = [
      {"-properties.datetime,-id", ["sort-c", "sort-a", "sort-range", "sort-b"]},
      {"properties.datetime,-id", ["sort-b", "sort-range", "sort-c", "sort-a"]}
    ]

    for endpoint <- @endpoints, {sortby, expected} <- cases do
      assert ids_via(endpoint, sortby) == expected, "#{endpoint} sortby=#{sortby}"
    end
  end

  test "collection orders across collections on /search and is accepted on the items endpoint" do
    both = %{"collections" => "#{@one},#{@two}"}

    cases = [
      {"collection,properties.datetime", ["sort-b", "sort-range", "sort-a", "sort-c", "sort-d"]},
      {"-collection,properties.datetime", ["sort-d", "sort-b", "sort-range", "sort-a", "sort-c"]}
    ]

    for {sortby, expected} <- cases do
      get_ids = :get_search |> request(sortby, both) |> json_response(200) |> ids()

      post_ids =
        :post_search
        |> request(sortby, %{"collections" => [@one, @two]})
        |> json_response(200)
        |> ids()

      assert get_ids == expected, "GET sortby=#{sortby}"
      assert post_ids == expected, "POST sortby=#{sortby}"
    end

    # One collection, so the id tie-breaker decides.
    for sortby <- ["collection", "-collection"] do
      assert ids_via(:items, sortby) == ["sort-a", "sort-b", "sort-c", "sort-range"]
    end
  end

  test "without sortby the order is -properties.datetime, with the range item in its place" do
    for endpoint <- @endpoints do
      default = ids_via(endpoint, nil)

      assert default == ["sort-a", "sort-c", "sort-range", "sort-b"], "#{endpoint}"
      assert default == ids_via(endpoint, "-properties.datetime"), "#{endpoint}"
      # Not first, as with the old datetime DESC (NULLs first), but by its start_datetime.
      assert Enum.find_index(default, &(&1 == "sort-range")) == 2, "#{endpoint}"
    end
  end

  test "an item with neither datetime nor start_datetime comes last in both directions" do
    # The write API no longer accepts such an item, so it is inserted directly.
    Repo.insert!(%Item{
      id: "sort-undated",
      collection_id: @one,
      geometry: %Geo.Point{coordinates: {26.7, 58.4}, srid: 4326},
      properties: %{}
    })

    for endpoint <- @endpoints, sortby <- ["properties.datetime", "-properties.datetime", nil] do
      assert List.last(ids_via(endpoint, sortby)) == "sort-undated", "#{endpoint} #{sortby}"
    end
  end

  test "a + sent without %2B arrives as a space and still means ascending" do
    expected = ["sort-a", "sort-b", "sort-c", "sort-range"]

    for path <- [
          "/stac/api/v1/search?collections=#{@one}&sortby=+id",
          "/stac/api/v1/search?collections=#{@one}&sortby=%2Bid",
          "/stac/api/v1/collections/#{@one}/items?sortby=+id",
          "/stac/api/v1/collections/#{@one}/items?sortby=%2Bid"
        ] do
      assert build_conn() |> get(path) |> json_response(200) |> ids() == expected, path
    end

    response =
      build_conn()
      |> get("/stac/api/v1/search?collections=#{@one}&sortby=+properties.datetime,-id")
      |> json_response(200)

    assert ids(response) == ["sort-b", "sort-range", "sort-c", "sort-a"]
  end

  test "an unknown key or a malformed value returns 400" do
    get_values = ["datetime", "properties.title", "id,,collection", "-", "+id;drop"]

    for endpoint <- [:get_search, :items], sortby <- get_values do
      error = endpoint |> request(sortby) |> json_response(400) |> Map.fetch!("error")
      assert error =~ "Invalid sortby parameter", "#{endpoint} sortby=#{sortby}"
    end

    error = :items |> request("properties.title") |> json_response(400) |> Map.fetch!("error")
    assert error =~ ~s(cannot sort by "properties.title")
    assert error =~ "properties.datetime, id and collection"

    post_values = [
      [%{"field" => "properties.title", "direction" => "asc"}],
      [%{"field" => "id", "direction" => "up"}],
      [%{"direction" => "asc"}],
      ["id"],
      %{"field" => "id"}
    ]

    for sortby <- post_values do
      error = :post_search |> request(sortby) |> json_response(400) |> Map.fetch!("error")
      assert error =~ "Invalid sortby parameter", inspect(sortby)
    end
  end

  test "paging a sorted result with limit=1 returns every item exactly once, in order" do
    expected = ["sort-b", "sort-range", "sort-a", "sort-c"]

    for endpoint <- @endpoints do
      first_page =
        endpoint |> request("properties.datetime", %{"limit" => 1}) |> json_response(200)

      assert collect_ids(first_page) == expected, "#{endpoint}"
    end
  end

  test "pagination links keep sortby" do
    for endpoint <- [:get_search, :items] do
      response =
        endpoint |> request("-properties.datetime,id", %{"limit" => 1}) |> json_response(200)

      for rel <- ["self", "next"] do
        query =
          link(response, rel)["href"] |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

        assert query["sortby"] == "-properties.datetime,id", "#{endpoint} #{rel}"
      end
    end

    # A + that arrived as a space is written back without a sign.
    response =
      build_conn()
      |> get("/stac/api/v1/search?collections=#{@one}&sortby=+id&limit=1")
      |> json_response(200)

    next_query = link(response, "next")["href"] |> URI.parse() |> Map.fetch!(:query)
    assert URI.decode_query(next_query)["sortby"] == "id"

    sortby = post_form("-properties.datetime,id")
    response = :post_search |> request(sortby, %{"limit" => 1}) |> json_response(200)
    assert link(response, "next")["body"]["sortby"] == sortby

    # Without sortby the links do not add one.
    response = :get_search |> request(nil, %{"limit" => 1}) |> json_response(200)
    refute link(response, "next")["href"] =~ "sortby"
  end
end
