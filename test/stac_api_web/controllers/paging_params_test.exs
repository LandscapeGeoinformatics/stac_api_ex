defmodule StacApiWeb.PagingParamsTest do
  use StacApiWeb.ConnCase, async: true

  @collection "paging-collection"

  setup do
    auth_conn = authenticated_conn(build_conn())

    post(auth_conn, ~p"/stac/manage/v1/collections", %{
      "id" => @collection,
      "description" => "Exercises limit and offset",
      "license" => "CC-BY-4.0"
    })

    {:ok, auth_conn: auth_conn}
  end

  defp add_items(auth_conn, count) do
    # Distinct datetimes, so the order is unambiguous across pages.
    for n <- 1..count do
      id = "paging-#{n}"

      response =
        post(auth_conn, ~p"/stac/manage/v1/items", %{
          "id" => id,
          "collection_id" => @collection,
          "geometry" => %{"type" => "Point", "coordinates" => [26.0, 58.0]},
          "bbox" => [26.0, 58.0, 26.0, 58.0],
          "properties" => %{
            "datetime" => DateTime.add(~U[2023-01-01 00:00:00Z], n * 60) |> DateTime.to_iso8601()
          }
        })

      assert response.status == 201
      id
    end
  end

  defp get_search(params),
    do: build_conn() |> get(~p"/stac/api/v1/search", Map.put(params, "collections", @collection))

  defp post_search(body),
    do: build_conn() |> post(~p"/stac/api/v1/search", Map.put(body, "collections", [@collection]))

  defp get_items(params),
    do: build_conn() |> get(~p"/stac/api/v1/collections/#{@collection}/items", params)

  defp ids(response), do: Enum.map(response["features"], & &1["id"])

  defp collect_ids(response) do
    case Enum.find(response["links"], &(&1["rel"] == "next")) do
      nil ->
        ids(response)

      next ->
        ids(response) ++ collect_ids(build_conn() |> get(next["href"]) |> json_response(200))
    end
  end

  test "a negative or non-integer offset returns 400 on every endpoint", %{auth_conn: auth_conn} do
    add_items(auth_conn, 2)

    for offset <- ["-1", "abc", "2.0", "1x"], request <- [&get_search/1, &get_items/1] do
      error = %{"offset" => offset} |> request.() |> json_response(400) |> Map.fetch!("error")
      assert error == "Invalid offset parameter: it must be an integer of at least 0", offset
    end

    for offset <- [-1, "abc", 2.0] do
      error = %{"offset" => offset} |> post_search() |> json_response(400) |> Map.fetch!("error")
      assert error == "Invalid offset parameter: it must be an integer of at least 0"
    end
  end

  test "an offset past the end returns an empty page on every endpoint", %{auth_conn: auth_conn} do
    add_items(auth_conn, 2)

    for response <- [
          get_search(%{"offset" => "5"}),
          post_search(%{"offset" => 5}),
          get_items(%{"offset" => "5"})
        ] do
      assert json_response(response, 200)["features"] == []
    end
  end

  test "limit below 1 or not an integer returns 400 on the items endpoint too", %{
    auth_conn: auth_conn
  } do
    add_items(auth_conn, 2)

    for limit <- ["0", "-1", "2.0", "abc"] do
      error = %{"limit" => limit} |> get_items() |> json_response(400) |> Map.fetch!("error")
      assert error == "Invalid limit parameter: it must be an integer of at least 1", limit
    end
  end

  test "limit above 100 returns 100 on the items endpoint too, and next reaches every item", %{
    auth_conn: auth_conn
  } do
    expected = add_items(auth_conn, 120)

    first_page = %{"limit" => "150"} |> get_items() |> json_response(200)

    assert length(first_page["features"]) == 100
    assert first_page["context"]["limit"] == 100

    collected = collect_ids(first_page)
    assert length(collected) == 120
    assert Enum.sort(collected) == Enum.sort(expected)
  end
end
