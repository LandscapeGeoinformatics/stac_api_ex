defmodule StacApi.Data.ItemFields do
  @moduledoc """
  Parses and applies the STAC API Fields extension to serialized Items.

  Fields are projected after an Item has been queried and serialized, so they
  reduce response payloads without affecting search, access control, or counts.
  """

  @default_paths [
    "type",
    "stac_version",
    "id",
    "geometry",
    "bbox",
    "links",
    "assets",
    "properties.datetime"
  ]

  @type selection :: %{
          mode: :all | :default | :include | :exclude,
          include: [String.t()],
          exclude: [String.t()]
        }

  @doc """
  Parses a Fields value from either a GET query map or a POST search body.

  A missing or null parameter preserves the complete item. An empty parameter
  selects the minimal default STAC Item fields; an empty POST include list is
  treated as missing. Exclude-only requests retain the full
  item except for the requested paths, matching this API's documented behavior.
  """
  @spec parse(map(), :get | :post) :: {:ok, selection()} | {:error, :fields, String.t()}
  def parse(params, :get) when is_map(params) do
    case fetch_param(params, "fields") do
      :missing -> {:ok, %{mode: :all, include: [], exclude: []}}
      {:ok, ""} -> {:ok, %{mode: :default, include: [], exclude: []}}
      {:ok, value} when is_binary(value) -> parse_get_value(value)
      {:ok, _value} -> {:error, :fields, "must be a comma-separated string"}
    end
  end

  def parse(params, :post) when is_map(params) do
    case fetch_param(params, "fields") do
      :missing ->
        {:ok, %{mode: :all, include: [], exclude: []}}

      {:ok, nil} ->
        {:ok, %{mode: :all, include: [], exclude: []}}

      {:ok, fields} when is_map(fields) ->
        parse_post_value(fields)

      {:ok, _value} ->
        {:error, :fields, "must be an object with string include and exclude arrays"}
    end
  end

  @doc """
  Projects a serialized Item according to a parsed Fields selection.
  """
  @spec project(map(), selection()) :: map()
  def project(item, %{mode: :all}), do: item

  def project(item, %{mode: :exclude, exclude: exclude}) do
    Enum.reduce(exclude, item, &drop_path(&2, path_segments(&1)))
  end

  def project(item, %{mode: mode, include: include, exclude: exclude})
      when mode in [:default, :include] do
    include = if mode == :default, do: default_paths(item), else: include

    projected =
      Enum.reduce(include, %{}, fn path, acc ->
        case fetch_path(item, path_segments(path)) do
          {:ok, value} -> put_path(acc, path_segments(path), value)
          :missing -> acc
        end
      end)

    Enum.reduce(exclude, projected, fn path, acc ->
      if Enum.any?(include, &same_or_descendant?(&1, path)) do
        acc
      else
        drop_path(acc, path_segments(path))
      end
    end)
  end

  @doc """
  Converts a parsed selection into the GET representation used in pagination links.
  """
  @spec pagination_params(map(), selection()) :: map()
  def pagination_params(params, %{mode: :all}) do
    params |> Map.delete("fields") |> Map.delete(:fields)
  end

  def pagination_params(params, %{mode: :default}) do
    params |> Map.delete(:fields) |> Map.put("fields", "")
  end

  def pagination_params(params, %{include: include, exclude: exclude}) do
    value = Enum.join(include ++ Enum.map(exclude, &"-#{&1}"), ",")
    params |> Map.delete(:fields) |> Map.put("fields", value)
  end

  defp parse_get_value(value) do
    value
    |> String.split(",", trim: false)
    |> Enum.map(&String.trim/1)
    |> parse_paths()
  end

  defp parse_post_value(fields) do
    with {:ok, include_state} <- parse_post_paths(fields, "include"),
         {:ok, exclude_state} <- parse_post_paths(fields, "exclude") do
      selection_from_states(include_state, exclude_state)
    end
  end

  defp parse_post_paths(fields, key) do
    case Map.fetch(fields, key) do
      :error ->
        {:ok, :missing}

      {:ok, nil} ->
        {:ok, :empty}

      {:ok, []} ->
        {:ok, :missing}

      {:ok, values} when is_list(values) ->
        if Enum.all?(values, &valid_path?/1),
          do: {:ok, {:paths, values}},
          else: {:error, :fields, "#{key} must be an array of non-empty strings"}

      {:ok, _value} ->
        {:error, :fields, "#{key} must be an array of strings"}
    end
  end

  defp parse_paths(paths) do
    if Enum.all?(paths, &valid_path?/1) do
      {exclude, include} = Enum.split_with(paths, &String.starts_with?(&1, "-"))

      selection_from_states(
        if(include == [],
          do: :missing,
          else: {:paths, Enum.map(include, &String.trim_leading(&1, "+"))}
        ),
        if(exclude == [],
          do: :missing,
          else: {:paths, Enum.map(exclude, &String.trim_leading(&1, "-"))}
        )
      )
    else
      {:error, :fields, "must contain comma-separated non-empty field paths"}
    end
  end

  defp selection_from_states(:missing, :missing),
    do: {:ok, %{mode: :default, include: [], exclude: []}}

  defp selection_from_states(:missing, {:paths, exclude}),
    do: {:ok, %{mode: :exclude, include: [], exclude: exclude}}

  defp selection_from_states(:empty, :missing),
    do: {:ok, %{mode: :default, include: [], exclude: []}}

  defp selection_from_states(:empty, :empty),
    do: {:ok, %{mode: :default, include: [], exclude: []}}

  defp selection_from_states(:empty, {:paths, exclude}),
    do: {:ok, %{mode: :default, include: [], exclude: exclude}}

  defp selection_from_states({:paths, include}, :missing),
    do: {:ok, %{mode: :include, include: include, exclude: []}}

  defp selection_from_states({:paths, include}, :empty),
    do: {:ok, %{mode: :include, include: include, exclude: []}}

  defp selection_from_states({:paths, include}, {:paths, exclude}),
    do: {:ok, %{mode: :include, include: include, exclude: exclude}}

  defp valid_path?(path) when is_binary(path) do
    path != "" and String.trim_leading(path, "-+") != ""
  end

  defp valid_path?(_path), do: false

  defp default_paths(item) do
    case fetch_path(item, ["properties", "datetime"]) do
      {:ok, value} when not is_nil(value) -> @default_paths
      _ -> @default_paths ++ ["properties.start_datetime", "properties.end_datetime"]
    end
  end

  defp fetch_param(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        case Map.fetch(params, String.to_atom(key)) do
          {:ok, value} -> {:ok, value}
          :error -> :missing
        end
    end
  end

  defp path_segments(path), do: String.split(path, ".")

  defp same_or_descendant?(included, path),
    do: included == path or String.starts_with?(included, path <> ".")

  defp fetch_path(map, [segment]) when is_map(map) do
    case matching_key(map, segment) do
      nil -> :missing
      key -> {:ok, Map.fetch!(map, key)}
    end
  end

  defp fetch_path(map, [segment | rest]) when is_map(map) do
    case matching_key(map, segment) do
      nil -> :missing
      key -> fetch_path(Map.fetch!(map, key), rest)
    end
  end

  defp fetch_path(_value, _segments), do: :missing

  defp put_path(map, [segment], value), do: Map.put(map, segment, value)

  defp put_path(map, [segment | rest], value),
    do: Map.put(map, segment, put_path(Map.get(map, segment, %{}), rest, value))

  defp drop_path(map, [segment]) when is_map(map) do
    case matching_key(map, segment) do
      nil -> map
      key -> Map.delete(map, key)
    end
  end

  defp drop_path(map, [segment | rest]) when is_map(map) do
    case matching_key(map, segment) do
      nil ->
        map

      key ->
        nested = drop_path(Map.fetch!(map, key), rest)
        if nested == %{}, do: Map.delete(map, key), else: Map.put(map, key, nested)
    end
  end

  defp drop_path(value, _segments), do: value

  defp matching_key(map, segment) do
    cond do
      Map.has_key?(map, segment) -> segment
      true -> Enum.find(Map.keys(map), &(is_atom(&1) and Atom.to_string(&1) == segment))
    end
  end
end
