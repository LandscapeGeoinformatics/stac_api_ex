defmodule StacApi.Data.ItemFieldsTest do
  use ExUnit.Case, async: true

  alias StacApi.Data.ItemFields

  @item %{
    "type" => "Feature",
    "stac_version" => "1.0.0",
    "id" => "fields-item",
    "collection" => "fields-collection",
    "geometry" => nil,
    "bbox" => [0, 0, 1, 1],
    "links" => [],
    "assets" => %{},
    "properties" => %{
      "datetime" => "2024-01-01T00:00:00Z",
      "description" => "full response",
      "table:columns" => ["wide", "payload"]
    }
  }

  test "missing, empty, and exclude-only GET selections have distinct behavior" do
    assert {:ok, all} = ItemFields.parse(%{}, :get)
    assert ItemFields.project(@item, all) == @item

    assert {:ok, default} = ItemFields.parse(%{"fields" => ""}, :get)
    default_item = ItemFields.project(@item, default)

    assert Map.keys(default_item) |> Enum.sort() == [
             "assets",
             "bbox",
             "geometry",
             "id",
             "links",
             "properties",
             "stac_version",
             "type"
           ]

    assert default_item["properties"] == %{"datetime" => "2024-01-01T00:00:00Z"}

    assert {:ok, excluded} = ItemFields.parse(%{"fields" => "-properties.table:columns"}, :get)
    excluded_item = ItemFields.project(@item, excluded)
    assert excluded_item["properties"]["description"] == "full response"
    refute Map.has_key?(excluded_item["properties"], "table:columns")
  end

  test "nested include wins over an exclusion of its parent" do
    assert {:ok, selection} =
             ItemFields.parse(
               %{"fields" => "id,properties.datetime,-properties"},
               :get
             )

    assert ItemFields.project(@item, selection) == %{
             "id" => "fields-item",
             "properties" => %{"datetime" => "2024-01-01T00:00:00Z"}
           }
  end

  test "POST fields validates its include and exclude arrays" do
    assert {:error, :fields, _reason} = ItemFields.parse(%{"fields" => "id"}, :post)

    assert {:error, :fields, _reason} =
             ItemFields.parse(%{"fields" => %{"include" => [1]}}, :post)
  end
end
