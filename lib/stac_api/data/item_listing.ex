defmodule StacApi.Data.ItemListing do
  @moduledoc """
  Shared order and paging of STAC item lists for the Search and OGC Features
  endpoints: the Sort extension (`sortby`), `limit` and `offset`.

  Like `StacApi.Data.ItemFilters`, parameters are parsed first, so a controller
  can answer a malformed value with 400, and then applied to the item query.

  Sort keys are mapped to columns here; the ORDER BY is never built from the
  request. Without `sortby` the order is the same as
  `sortby=-properties.datetime`, and `id` ascending is always the last
  tie-breaker, so pages do not overlap when many items share a datetime.

  `limit` defaults to 10 and above 100 returns 100 (the spec asks for the
  maximum instead of an error); below 1 or not an integer is an error.
  `offset` defaults to 0; negative or not an integer is an error.
  """

  import Ecto.Query

  @sort_keys %{
    "properties.datetime" => :datetime,
    "id" => :id,
    "collection" => :collection
  }

  @key_names for {name, key} <- @sort_keys, into: %{}, do: {key, name}

  @allowed_keys "properties.datetime, id and collection"

  @type sort :: [{:datetime | :id | :collection, :asc | :desc}]

  @typedoc "`sort` is nil when the request has no `sortby`."
  @type listing :: %{sort: sort() | nil, limit: pos_integer(), offset: non_neg_integer()}

  @default_sort [{:datetime, :desc}]
  @default_limit 10
  @max_limit 100

  @doc """
  Parses `sortby`, `limit` and `offset`. `sortby` comes in its GET form
  (`-properties.datetime,id`, no sign meaning ascending) or its POST form
  (`[%{"field" => ..., "direction" => "asc" | "desc"}]`).
  """
  @spec parse(map()) :: {:ok, listing()} | {:error, :sortby | :limit | :offset, String.t()}
  def parse(params) when is_map(params) do
    with {:ok, sort} <- parse_sortby(param(params, "sortby", :sortby)),
         {:ok, limit} <- parse_limit(param(params, "limit", :limit)),
         {:ok, offset} <- parse_offset(param(params, "offset", :offset)) do
      {:ok, %{sort: sort, limit: limit, offset: offset}}
    end
  end

  @doc "The listing of a request without `sortby`, `limit` and `offset`."
  @spec default() :: listing()
  def default, do: %{sort: nil, limit: @default_limit, offset: 0}

  @doc """
  Orders an item query by the parsed sort keys, then by `id` ascending unless
  the request already sorts by `id`, and takes the requested page.
  """
  @spec apply(Ecto.Queryable.t(), listing()) :: Ecto.Query.t()
  def apply(query, %{sort: sort, limit: limit, offset: offset}) do
    (sort || @default_sort)
    |> with_tie_breaker()
    |> Enum.reduce(query, &order(&2, &1))
    |> limit(^limit)
    |> offset(^offset)
  end

  @doc """
  Puts `sortby` into GET pagination link parameters, in its canonical form.
  Ascending keys get no sign, so no `+` has to survive the URL.
  """
  @spec pagination_params(map(), listing()) :: map()
  def pagination_params(params, %{sort: nil}) do
    params |> Map.delete("sortby") |> Map.delete(:sortby)
  end

  def pagination_params(params, %{sort: sort}) do
    value = Enum.map_join(sort, ",", fn {key, direction} -> sign(direction) <> name(key) end)
    params |> Map.delete(:sortby) |> Map.put("sortby", value)
  end

  defp param(params, key, atom_key), do: Map.get(params, key, Map.get(params, atom_key))

  defp parse_limit(nil), do: {:ok, @default_limit}
  defp parse_limit(""), do: {:ok, @default_limit}

  defp parse_limit(value) do
    case integer(value) do
      {:ok, limit} when limit >= 1 -> {:ok, min(limit, @max_limit)}
      _ -> {:error, :limit, "must be an integer of at least 1"}
    end
  end

  defp parse_offset(nil), do: {:ok, 0}
  defp parse_offset(""), do: {:ok, 0}

  defp parse_offset(value) do
    case integer(value) do
      {:ok, offset} when offset >= 0 -> {:ok, offset}
      _ -> {:error, :offset, "must be an integer of at least 0"}
    end
  end

  defp integer(value) when is_integer(value), do: {:ok, value}

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp integer(_value), do: :error

  defp parse_sortby(nil), do: {:ok, nil}
  defp parse_sortby(""), do: {:ok, nil}
  defp parse_sortby([]), do: {:ok, nil}

  defp parse_sortby(value) when is_binary(value) do
    value |> String.split(",") |> Enum.map(&parse_get_key/1) |> collect()
  end

  defp parse_sortby(keys) when is_list(keys), do: keys |> Enum.map(&parse_post_key/1) |> collect()

  defp parse_sortby(_value) do
    {:error, :sortby,
     "must be a comma-separated list of fields or an array of field and direction objects"}
  end

  # A + that the client did not send as %2B arrives as a space, so " id" is "+id".
  defp parse_get_key(key) do
    case String.trim(key) do
      "-" <> field -> sort_key(field, :desc)
      "+" <> field -> sort_key(field, :asc)
      field -> sort_key(field, :asc)
    end
  end

  defp parse_post_key(%{"field" => field} = key) do
    case Map.get(key, "direction", "asc") do
      "asc" -> sort_key(field, :asc)
      "desc" -> sort_key(field, :desc)
      _ -> {:error, :sortby, "must have \"asc\" or \"desc\" as direction"}
    end
  end

  defp parse_post_key(_key) do
    {:error, :sortby, "must be an array of objects with a field and a direction"}
  end

  defp sort_key("", _direction), do: {:error, :sortby, "must not contain an empty field"}

  defp sort_key(field, direction) do
    case Map.fetch(@sort_keys, field) do
      {:ok, key} -> {:ok, {key, direction}}
      :error -> {:error, :sortby, "cannot sort by #{inspect(field)}, only by #{@allowed_keys}"}
    end
  end

  defp collect(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, key}, {:ok, keys} -> {:cont, {:ok, keys ++ [key]}}
      error, _acc -> {:halt, error}
    end)
  end

  defp with_tie_breaker(sort) do
    if Enum.any?(sort, &match?({:id, _}, &1)), do: sort, else: sort ++ [{:id, :asc}]
  end

  # One key for both directions, so ascending is exactly the reverse of
  # descending: a range item (datetime null) sorts by its start_datetime, like
  # the datetime filter treats it. An item with neither goes last either way.
  defp order(query, {:datetime, :asc}) do
    order_by(query, [i], asc_nulls_last: fragment("COALESCE(?, ?)", i.datetime, i.start_datetime))
  end

  defp order(query, {:datetime, :desc}) do
    order_by(query, [i],
      desc_nulls_last: fragment("COALESCE(?, ?)", i.datetime, i.start_datetime)
    )
  end

  defp order(query, {:id, direction}), do: order_by(query, [i], [{^direction, i.id}])

  defp order(query, {:collection, direction}),
    do: order_by(query, [i], [{^direction, i.collection_id}])

  defp sign(:asc), do: ""
  defp sign(:desc), do: "-"

  defp name(key), do: Map.fetch!(@key_names, key)
end
