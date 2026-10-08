defmodule StacApi.Data.ItemFilters do
  @moduledoc """
  Shared STAC item filtering for the Search and OGC Features endpoints.

  Parsing query parameters separately from applying their Ecto predicates keeps
  both endpoints consistent and lets controllers reject malformed filters with
  a useful HTTP 400 response.
  """

  import Ecto.Query

  alias StacApi.Temporal

  @type filters :: %{
          bbox: {number(), number(), number(), number()} | nil,
          datetime:
            {:instant, DateTime.t()} | {:interval, DateTime.t() | nil, DateTime.t() | nil} | nil
        }

  @doc """
  Parses the supported `bbox` and `datetime` parameters into reusable filters.
  """
  @spec parse(map()) :: {:ok, filters()} | {:error, :bbox | :datetime, String.t()}
  def parse(params) when is_map(params) do
    with {:ok, datetime} <-
           parse_datetime(Map.get(params, "datetime", Map.get(params, :datetime))),
         {:ok, bbox} <- parse_bbox(Map.get(params, "bbox", Map.get(params, :bbox))) do
      {:ok, %{datetime: datetime, bbox: bbox}}
    end
  end

  @doc """
  Applies parsed temporal and spatial predicates to an item query.
  """
  @spec apply(Ecto.Queryable.t(), filters()) :: Ecto.Query.t()
  def apply(query, filters) do
    query
    |> filter_by_datetime(filters.datetime)
    |> filter_by_bbox(filters.bbox)
  end

  defp parse_datetime(nil), do: {:ok, nil}
  defp parse_datetime(""), do: {:ok, nil}

  defp parse_datetime(value) do
    case Temporal.parse_datetime_param(value) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, reason} -> {:error, :datetime, reason}
    end
  end

  defp parse_bbox(nil), do: {:ok, nil}
  defp parse_bbox(""), do: {:ok, nil}

  defp parse_bbox(bbox) when is_binary(bbox) do
    bbox
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> parse_bbox_coordinates()
  end

  defp parse_bbox(bbox) when is_list(bbox), do: parse_bbox_coordinates(bbox)
  defp parse_bbox(_), do: {:error, :bbox, "must contain four WGS84 coordinates"}

  defp parse_bbox_coordinates([west, south, east, north]) do
    with {:ok, west} <- parse_coordinate(west),
         {:ok, south} <- parse_coordinate(south),
         {:ok, east} <- parse_coordinate(east),
         {:ok, north} <- parse_coordinate(north),
         :ok <- validate_bbox(west, south, east, north) do
      {:ok, {west, south, east, north}}
    end
  end

  defp parse_bbox_coordinates(_), do: {:error, :bbox, "must contain four WGS84 coordinates"}

  defp parse_coordinate(value) when is_number(value), do: {:ok, value}

  defp parse_coordinate(value) when is_binary(value) do
    case Float.parse(value) do
      {coordinate, ""} -> {:ok, coordinate}
      _ -> {:error, :bbox, "must contain numeric coordinates"}
    end
  end

  defp parse_coordinate(_), do: {:error, :bbox, "must contain numeric coordinates"}

  defp validate_bbox(west, south, east, north)
       when west >= -180 and west <= 180 and east >= -180 and east <= 180 and
              south >= -90 and south <= 90 and north >= -90 and north <= 90 and
              south <= north,
       do: :ok

  defp validate_bbox(_, _, _, _),
    do: {:error, :bbox, "must stay within WGS84 bounds, with south not greater than north"}

  defp filter_by_datetime(query, nil), do: query

  defp filter_by_datetime(query, {:instant, instant}) do
    from(i in query,
      where:
        fragment("COALESCE(?, ?)", i.start_datetime, i.datetime) <= ^instant and
          fragment("COALESCE(?, ?)", i.end_datetime, i.datetime) >= ^instant
    )
  end

  defp filter_by_datetime(query, {:interval, start_dt, end_dt}) do
    cond do
      start_dt && end_dt ->
        from(i in query,
          where:
            fragment("COALESCE(?, ?)", i.start_datetime, i.datetime) <= ^end_dt and
              fragment("COALESCE(?, ?)", i.end_datetime, i.datetime) >= ^start_dt
        )

      start_dt ->
        from(i in query,
          where: fragment("COALESCE(?, ?)", i.end_datetime, i.datetime) >= ^start_dt
        )

      end_dt ->
        from(i in query,
          where: fragment("COALESCE(?, ?)", i.start_datetime, i.datetime) <= ^end_dt
        )
    end
  end

  defp filter_by_bbox(query, nil), do: query

  # A bbox is a rectangle in lon/lat, so it is compared as planar geometry. Cast to
  # geography its edges become great-circle arcs that take the shorter way round:
  # wide boxes then miss items, and a whole-world box raises in PostGIS.
  defp filter_by_bbox(query, {west, south, east, north}) when west <= east do
    from(i in query,
      where:
        fragment(
          "ST_Intersects(?::geometry, ST_MakeEnvelope(?, ?, ?, ?, 4326))",
          i.geometry,
          ^west,
          ^south,
          ^east,
          ^north
        )
    )
  end

  # west > east means the box crosses the antimeridian, so it is split at 180 degrees.
  defp filter_by_bbox(query, {west, south, east, north}) do
    from(i in query,
      where:
        fragment(
          "ST_Intersects(?::geometry, ST_MakeEnvelope(?, ?, 180, ?, 4326))",
          i.geometry,
          ^west,
          ^south,
          ^north
        ) or
          fragment(
            "ST_Intersects(?::geometry, ST_MakeEnvelope(-180, ?, ?, ?, 4326))",
            i.geometry,
            ^south,
            ^east,
            ^north
          )
    )
  end
end
