defmodule StacApiWeb.StacBrowserComponents do
  @moduledoc """
  Function components for the HTML STAC browser (collection and item pages).

  Every component is defensive: attributes that originate from STAC JSON are
  typed `:any`, guarded inside, and a missing or malformed element renders
  either nothing or an `n/a` placeholder instead of raising.

  Later idea (deliberately not implemented yet, see plan): derived GDAL/QGIS
  access strings per asset (`/vsicurl/<https href>`, `/vsis3/<bucket>/<key>`).
  """
  use Phoenix.Component

  import StacApiWeb.StacBrowserHelpers

  @card_class "bg-gray-50 shadow-sm shadow-black/20 border border-gray-100 rounded-lg p-6"
  @json_link_class "text-xs font-mono font-medium text-white hover:text-primary border border-black rounded px-2 py-0.5 bg-secondary transition-transform duration-200 hover:scale-110 shadow-lg shadow-black/20 shrink-0"

  # ---------------------------------------------------------------------------
  # Layout
  # ---------------------------------------------------------------------------

  attr :title, :string, required: true
  attr :count, :any, default: nil
  attr :class, :string, default: ""
  attr :json_href, :string, default: nil
  slot :inner_block, required: true
  slot :actions

  def section(assigns) do
    assigns = assign(assigns, card_class: @card_class, json_link_class: @json_link_class)

    ~H"""
    <section class={[@card_class, @class]}>
      <div class="flex items-center justify-between gap-2 mb-4">
        <h2 class="text-xl font-semibold text-gray-900">
          <%= @title %>
          <span :if={@count != nil} class="ml-1 text-sm font-normal text-gray-500">(<%= @count %>)</span>
        </h2>
        <div class="flex items-center gap-2">
          <%= render_slot(@actions) %>
          <a
            :if={@json_href}
            href={@json_href}
            target="_blank"
            rel="noopener noreferrer"
            title="View API JSON"
            class={@json_link_class}
          >
            &#123;&nbsp;&#125; JSON
          </a>
        </div>
      </div>
      <%= render_slot(@inner_block) %>
    </section>
    """
  end

  slot :inner_block, required: true
  attr :class, :string, default: ""

  def kv_grid(assigns) do
    ~H"""
    <dl class={["grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3", @class]}>
      <%= render_slot(@inner_block) %>
    </dl>
    """
  end

  attr :label, :string, required: true
  attr :raw_key, :string, default: nil
  attr :value, :any, default: nil
  attr :mono, :boolean, default: false
  attr :span, :boolean, default: false
  slot :inner_block

  def kv(assigns) do
    ~H"""
    <div class={["min-w-0", @span && "sm:col-span-2"]}>
      <dt class="text-xs font-medium uppercase tracking-wide text-gray-500" title={@raw_key}>
        <%= @label %>
      </dt>
      <dd class={["mt-0.5 text-sm text-gray-900 break-words", @mono && "font-mono"]}>
        <%= if @inner_block != [] do %>
          <%= render_slot(@inner_block) %>
        <% else %>
          <.value v={@value} />
        <% end %>
      </dd>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Generic value renderer
  # ---------------------------------------------------------------------------

  attr :v, :any, default: nil
  attr :depth, :integer, default: 0
  attr :id, :string, default: nil

  @doc """
  Renders any JSON value: scalars as text (URLs become links), lists of
  scalars as chips, lists of uniform maps as a table, small maps as nested
  key/value lists, and everything deeper as a collapsed JSON block.
  """
  def value(assigns) do
    assigns =
      assigns
      |> assign(:shape, value_shape(assigns.v, assigns.depth))
      |> assign(:id, assigns.id || "v-" <> Integer.to_string(:erlang.phash2(assigns.v)))

    ~H"""
    <%= case @shape do %>
      <% :nil -> %>
        <span class="text-gray-400 italic">n/a</span>
      <% :empty -> %>
        <span class="text-gray-400 italic">empty</span>
      <% :url -> %>
        <a href={@v} target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline break-all"><%= @v %></a>
      <% :text -> %>
        <span class="whitespace-pre-wrap"><%= @v %></span>
      <% :scalar -> %>
        <span class="font-mono"><%= to_string(@v) %></span>
      <% :range -> %>
        <span class="font-mono"><%= to_string(@v["minimum"]) %> – <%= to_string(@v["maximum"]) %></span>
      <% :chips -> %>
        <span class="inline-flex flex-wrap gap-1">
          <span :for={x <- @v} class="inline-block px-2 py-0.5 text-xs rounded bg-gray-100 text-gray-700 font-mono">
            <%= if is_nil(x), do: "null", else: to_string(x) %>
          </span>
        </span>
      <% :table -> %>
        <.map_list_table rows={@v} depth={@depth} />
      <% :map -> %>
        <dl class="grid grid-cols-1 gap-y-1 border-l-2 border-gray-200 pl-3">
          <div :for={{k, x} <- Enum.sort_by(@v, fn {k, _} -> to_string(k) end)} class="text-sm">
            <dt class="inline text-gray-500 mr-1" title={to_string(k)}><%= humanize_key(k) %>:</dt>
            <dd class="inline"><.value v={x} depth={@depth + 1} /></dd>
          </div>
        </dl>
      <% :json -> %>
        <.json_details id={@id} data={@v} summary="Show JSON" />
    <% end %>
    """
  end

  defp value_shape(nil, _), do: nil
  defp value_shape([], _), do: :empty
  defp value_shape(m, _) when m == %{}, do: :empty
  defp value_shape(v, _) when is_binary(v), do: if(url?(v), do: :url, else: :text)
  defp value_shape(v, _) when is_number(v) or is_boolean(v) or is_atom(v), do: :scalar

  defp value_shape(%{"minimum" => min, "maximum" => max} = m, _) when map_size(m) == 2 do
    if scalar?(min) and scalar?(max), do: :range, else: :json
  end

  defp value_shape(v, depth) when is_list(v) do
    cond do
      Enum.all?(v, &scalar?/1) -> :chips
      depth < 2 and length(v) <= 200 and Enum.all?(v, &is_map/1) -> :table
      true -> :json
    end
  end

  defp value_shape(v, depth) when is_map(v) and not is_struct(v) do
    simple? =
      Enum.all?(v, fn {_, x} -> scalar?(x) or (is_list(x) and Enum.all?(x, &scalar?/1)) end)

    if depth < 2 and map_size(v) <= 12 and simple?, do: :map, else: :json
  end

  defp value_shape(_, _), do: :json

  attr :rows, :list, required: true
  attr :depth, :integer, default: 0

  defp map_list_table(assigns) do
    columns =
      assigns.rows
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    assigns = assign(assigns, :columns, columns)

    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full text-xs text-left border border-gray-200 rounded">
        <thead class="bg-gray-100 text-gray-600">
          <tr>
            <th :for={c <- @columns} class="px-2 py-1 font-medium whitespace-nowrap" title={c}><%= humanize_key(c) %></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100 bg-white">
          <tr :for={row <- @rows}>
            <td :for={c <- @columns} class="px-2 py-1 align-top">
              <.value v={Map.get(row, c)} depth={@depth + 1} />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Small widgets
  # ---------------------------------------------------------------------------

  attr :text, :string, default: nil
  attr :target_id, :string, default: nil
  attr :label, :string, default: "Copy"
  attr :class, :string, default: ""

  @doc "Copies `text` (or the text content of `target_id`) to the clipboard."
  def copy_button(assigns) do
    ~H"""
    <button
      type="button"
      data-copy={@text}
      data-copy-target={@target_id}
      onclick="var t=this.dataset.copyTarget?document.getElementById(this.dataset.copyTarget).textContent:this.dataset.copy;var b=this;navigator.clipboard.writeText(t).then(function(){var o=b.textContent;b.textContent='Copied';setTimeout(function(){b.textContent=o},1200)})"
      class={["px-2 py-0.5 text-xs rounded bg-gray-700 text-white hover:bg-gray-800 shrink-0", @class]}
      title="Copy to clipboard"
    >
      <%= @label %>
    </button>
    """
  end

  attr :id, :string, required: true
  attr :data, :any, required: true
  attr :summary, :string, default: "Raw JSON"
  attr :open, :boolean, default: false

  @doc "Collapsed pretty-printed JSON with a copy button."
  def json_details(assigns) do
    assigns = assign(assigns, :json, safe_pretty_json(assigns.data))

    ~H"""
    <details class="group" open={@open}>
      <summary class="cursor-pointer text-sm font-medium text-secondary select-none">
        <%= @summary %>
      </summary>
      <div class="relative mt-2">
        <.copy_button target_id={@id} class="absolute top-2 right-2" />
        <pre id={@id} class="text-xs bg-gray-900 text-gray-100 p-4 rounded overflow-x-auto max-h-96"><%= @json %></pre>
      </div>
    </details>
    """
  end

  attr :range, :any, required: true
  attr :class, :string, default: ""

  @doc "Renders a `temporal_range/1` result: instant, start → end (with days), or a placeholder."
  def temporal_badge(assigns) do
    assigns = assign(assigns, :days, duration_days(assigns.range))

    ~H"""
    <span class={["inline-flex flex-wrap items-center gap-1 text-sm text-gray-700", @class]}>
      <%= case @range do %>
        <% {:instant, dt} -> %>
          <span title="datetime">📅</span>
          <span class="font-mono"><%= format_dt(dt, :datetime) %></span>
        <% {:range, s, e} -> %>
          <span title="start_datetime → end_datetime">📅</span>
          <span class="font-mono"><%= if s, do: format_dt(s), else: "…" %></span>
          <span class="text-gray-400">→</span>
          <span class="font-mono"><%= if e, do: format_dt(e), else: "…" %></span>
          <span :if={@days} class="text-xs text-gray-500">(<%= @days %> days)</span>
        <% _ -> %>
          <span class="text-gray-400 italic">no datetime</span>
      <% end %>
    </span>
    """
  end

  attr :bbox, :any, default: nil
  attr :unit, :string, default: "°"

  @doc "A 4-number bbox as a min/max table; anything else falls back to the generic value renderer."
  def bbox_table(assigns) do
    assigns =
      assigns
      |> assign(:b, bbox4(assigns.bbox))
      |> assign(:geographic?, assigns.unit == "°")

    ~H"""
    <%= if @b do %>
      <table class="text-xs font-mono text-gray-800">
        <thead>
          <tr class="text-gray-500">
            <th class="pr-3 text-left font-normal"></th>
            <th class="pr-3 text-left font-normal">min</th>
            <th class="text-left font-normal">max</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class="pr-3 text-gray-500"><%= if @geographic?, do: "Lon", else: "X" %></td>
            <td class="pr-3"><%= format_coord(Enum.at(@b, 0)) %></td>
            <td><%= format_coord(Enum.at(@b, 2)) %></td>
          </tr>
          <tr>
            <td class="pr-3 text-gray-500"><%= if @geographic?, do: "Lat", else: "Y" %></td>
            <td class="pr-3"><%= format_coord(Enum.at(@b, 1)) %></td>
            <td><%= format_coord(Enum.at(@b, 3)) %></td>
          </tr>
        </tbody>
      </table>
      <span :if={@unit != ""} class="text-xs text-gray-500">unit: <%= @unit %></span>
    <% else %>
      <.value v={@bbox} />
    <% end %>
    """
  end

  attr :url, :string, required: true

  @doc "Chip linking to a STAC extension schema, labelled `name vX.Y.Z`."
  def extension_chip(assigns) do
    ~H"""
    <a
      href={@url}
      target="_blank"
      rel="noopener noreferrer"
      title={@url}
      class="inline-block px-2 py-0.5 text-xs bg-gray-100 text-gray-700 rounded hover:bg-gray-200 font-mono"
    >
      <%= extension_label(@url) %>
    </a>
    """
  end

  attr :kind, :atom, required: true
  attr :assets, :any, default: nil

  @doc "Badge describing the item kind and asset count."
  def kind_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-full bg-secondary text-primary">
      <span><%= kind_icon(@kind) %></span>
      <span><%= item_kind_label(@kind, @assets) %></span>
    </span>
    """
  end

  attr :stats, :list, required: true

  @doc "Horizontal strip of `{label, value}` facts."
  def stat_strip(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-x-6 gap-y-2 text-sm">
      <div :for={{label, value} <- @stats} class="flex items-baseline gap-1.5">
        <span class="text-xs uppercase tracking-wide text-gray-500"><%= label %></span>
        <span class="font-medium text-gray-900"><%= value %></span>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Projection
  # ---------------------------------------------------------------------------

  attr :props, :any, default: nil
  attr :class, :string, default: ""
  attr :id, :string, default: "proj"

  @doc "Projection card from `proj:*` properties. Renders nothing when there is nothing to show."
  def projection_card(assigns) do
    summary = proj_summary(assigns.props)
    assigns = assign(assigns, summary: summary, present: proj_present?(summary))

    ~H"""
    <.section :if={@present} title="Projection" class={@class}>
      <.kv_grid>
        <.kv label="CRS" raw_key="proj:code">
          <%= cond do %>
            <% @summary.epsg -> %>
              <a href={"https://epsg.io/#{@summary.epsg}"} target="_blank" rel="noopener noreferrer" class="font-mono text-blue-600 hover:underline">
                <%= @summary.code %>
              </a>
            <% @summary.code -> %>
              <span class="font-mono"><%= @summary.code %></span>
            <% true -> %>
              <span class="text-gray-400 italic">n/a</span>
          <% end %>
        </.kv>
        <.kv :if={@summary.shape} label="Shape" raw_key="proj:shape">
          <span class="font-mono"><%= format_int(elem(@summary.shape, 0)) %> rows × <%= format_int(elem(@summary.shape, 1)) %> cols</span>
        </.kv>
        <.kv :if={@summary.pixel} label="Pixel size" raw_key="proj:transform">
          <span class="font-mono"><%= format_coord(elem(@summary.pixel, 0)) %> × <%= format_coord(elem(@summary.pixel, 1)) %></span>
          <span class="text-xs text-gray-500">CRS units</span>
        </.kv>
        <.kv :if={@summary.origin} label="Origin (upper left)" raw_key="proj:transform">
          <span class="font-mono"><%= format_coord(elem(@summary.origin, 0)) %>, <%= format_coord(elem(@summary.origin, 1)) %></span>
        </.kv>
        <.kv :if={@summary.bbox} label="Bbox (native CRS)" raw_key="proj:bbox">
          <.bbox_table bbox={@summary.bbox} unit="CRS units" />
        </.kv>
        <.kv :if={@summary.centroid} label="Centroid" raw_key="proj:centroid" value={@summary.centroid} />
        <.kv :if={@summary.transform} label="Affine transform" raw_key="proj:transform" span>
          <.value v={@summary.transform} />
        </.kv>
      </.kv_grid>
      <div :if={@summary.geometry || @summary.wkt2 || @summary.projjson} class="mt-3 space-y-2">
        <.json_details :if={@summary.geometry} id={@id <> "-geometry"} data={@summary.geometry} summary="Footprint in native CRS (proj:geometry)" />
        <.json_details :if={@summary.projjson} id={@id <> "-projjson"} data={@summary.projjson} summary="PROJJSON (proj:projjson)" />
        <details :if={@summary.wkt2}>
          <summary class="cursor-pointer text-sm font-medium text-secondary select-none">WKT2 (proj:wkt2)</summary>
          <pre class="mt-2 text-xs bg-gray-900 text-gray-100 p-4 rounded overflow-x-auto max-h-96"><%= @summary.wkt2 %></pre>
        </details>
      </div>
    </.section>
    """
  end

  # ---------------------------------------------------------------------------
  # Table / vector schema
  # ---------------------------------------------------------------------------

  attr :props, :any, default: nil
  attr :class, :string, default: ""

  @doc "Table schema card from `table:*` / `vector:*` properties. Renders nothing when absent."
  def table_schema_card(assigns) do
    props = if is_map(assigns.props), do: assigns.props, else: %{}
    columns = table_columns(props)

    extra_columns =
      columns
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.map(&to_string/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in ["name", "type"]))

    assigns =
      assign(assigns,
        props: props,
        present: table_present?(props),
        columns: columns,
        extra_columns: extra_columns,
        collapsed: length(columns) > 20
      )

    ~H"""
    <.section :if={@present} title="Table schema" class={@class}>
      <.kv_grid class="mb-3">
        <.kv :if={Map.has_key?(@props, "table:row_count")} label="Rows" raw_key="table:row_count">
          <span class="font-mono"><%= format_int(@props["table:row_count"]) %></span>
        </.kv>
        <.kv :if={Map.has_key?(@props, "table:primary_geometry")} label="Primary geometry" raw_key="table:primary_geometry" value={@props["table:primary_geometry"]} mono />
        <.kv :if={Map.has_key?(@props, "vector:geometry_types")} label="Geometry types" raw_key="vector:geometry_types" value={@props["vector:geometry_types"]} />
      </.kv_grid>
      <details :if={@columns != []} open={not @collapsed}>
        <summary class="cursor-pointer text-sm font-medium text-secondary select-none">
          Columns (<%= length(@columns) %>)
        </summary>
        <div class="mt-2 overflow-x-auto max-h-96 overflow-y-auto">
          <table class="min-w-full text-xs text-left border border-gray-200 rounded">
            <thead class="bg-gray-100 text-gray-600 sticky top-0">
              <tr>
                <th class="px-2 py-1 font-medium">#</th>
                <th class="px-2 py-1 font-medium">Name</th>
                <th class="px-2 py-1 font-medium">Type</th>
                <th :for={c <- @extra_columns} class="px-2 py-1 font-medium" title={c}><%= humanize_key(c) %></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100 bg-white">
              <tr :for={{col, i} <- Enum.with_index(@columns, 1)}>
                <td class="px-2 py-1 text-gray-400"><%= i %></td>
                <td class="px-2 py-1 font-mono"><.value v={Map.get(col, "name")} /></td>
                <td class="px-2 py-1 font-mono"><.value v={Map.get(col, "type")} /></td>
                <td :for={c <- @extra_columns} class="px-2 py-1"><.value v={Map.get(col, c)} depth={1} /></td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
    </.section>
    """
  end

  # ---------------------------------------------------------------------------
  # Assets
  # ---------------------------------------------------------------------------

  attr :title, :string, default: nil
  attr :assets, :list, required: true
  attr :columns, :integer, default: 3

  @doc "A titled grid of asset cards; `assets` is a list of `{key, asset}`."
  def asset_group(assigns) do
    ~H"""
    <div :if={@assets != []} class="mb-6 last:mb-0">
      <h3 :if={@title} class="text-sm font-semibold text-secondary uppercase tracking-wide mb-2">
        <%= @title %> <span class="text-gray-400 font-normal">(<%= length(@assets) %>)</span>
      </h3>
      <div class={["grid gap-4", asset_grid_class(@columns)]}>
        <.asset_card :for={{key, asset} <- @assets} key={key} asset={asset} />
      </div>
    </div>
    """
  end

  defp asset_grid_class(1), do: "grid-cols-1"
  defp asset_grid_class(2), do: "grid-cols-1 md:grid-cols-2"
  defp asset_grid_class(_), do: "grid-cols-1 md:grid-cols-2 xl:grid-cols-3"

  attr :key, :string, required: true
  attr :asset, :any, required: true

  @doc "One asset: type, roles, size, access hrefs with copy buttons, raster bands, and any extra fields."
  def asset_card(assigns) do
    asset = if is_map(assigns.asset), do: assigns.asset, else: %{}

    assigns =
      assign(assigns,
        asset: asset,
        kind: asset_kind(asset),
        roles: asset_roles(asset),
        bands: raster_bands(asset),
        alternates: asset_alternates(asset),
        extra: asset_extra(asset)
      )

    ~H"""
    <div class="border border-gray-200 bg-white rounded-lg p-4 flex flex-col gap-3 min-w-0">
      <div class="flex items-start justify-between gap-2">
        <div class="min-w-0">
          <h3 class="font-semibold text-gray-900 break-all">
            <span class="mr-1" title={to_string(@kind)}><%= kind_icon(@kind) %></span><%= @key %>
          </h3>
          <p :if={is_binary(@asset["title"])} class="text-sm text-gray-600"><%= @asset["title"] %></p>
        </div>
        <span class="text-xs bg-secondary text-primary px-2 py-0.5 rounded shrink-0 whitespace-nowrap" title={@asset["type"]}>
          <%= media_type_label(@asset["type"]) %>
        </span>
      </div>

      <p :if={is_binary(@asset["description"])} class="text-sm text-gray-600"><%= @asset["description"] %></p>

      <div class="flex flex-wrap items-center gap-1.5 text-xs">
        <span class="text-gray-500">Roles:</span>
        <span :if={@roles == []} class="text-gray-400 italic">n/a</span>
        <span :for={role <- @roles} class={["px-2 py-0.5 rounded", role_chip_class(role)]}><%= role %></span>
        <span class="ml-auto text-gray-500">
          Size: <span class="font-mono text-gray-800"><%= format_bytes(@asset["file:size"]) %></span>
        </span>
      </div>

      <div class="border-t border-gray-100 pt-2 space-y-1.5">
        <p class="text-xs font-medium text-gray-500">Access</p>
        <.href_row label="https" href={@asset["href"]} type={@asset["type"]} />
        <.href_row :for={{name, href, type} <- @alternates} label={name} href={href} type={type} show_type />
      </div>

      <div :if={@bands != []} class="border-t border-gray-100 pt-2">
        <p class="text-xs font-medium text-gray-500 mb-1">Raster bands</p>
        <.bands_table bands={@bands} />
      </div>

      <div :if={@extra != []} class="border-t border-gray-100 pt-2">
        <.kv_grid>
          <.kv :for={{k, v} <- @extra} label={humanize_key(k)} raw_key={k} value={v} />
        </.kv_grid>
      </div>
    </div>
    """
  end

  defp role_chip_class("data"), do: "bg-secondary text-primary"
  defp role_chip_class(_), do: "bg-gray-100 text-gray-700"

  attr :label, :string, required: true
  attr :href, :any, default: nil
  attr :type, :any, default: nil
  attr :show_type, :boolean, default: false

  defp href_row(assigns) do
    assigns = assign(assigns, :link?, url?(assigns.href))

    ~H"""
    <div class="flex items-start gap-2 text-xs min-w-0">
      <span class="inline-block bg-gray-100 text-gray-600 px-1.5 py-0.5 rounded font-mono shrink-0" title={@type}>
        <%= @label %><span :if={@show_type and is_binary(@type)} class="text-gray-400 font-sans"> · <%= media_type_label(@type) %></span>
      </span>
      <%= cond do %>
        <% @link? -> %>
          <a href={@href} target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline break-all font-mono flex-1 min-w-0"><%= @href %></a>
          <.copy_button text={@href} />
        <% is_binary(@href) -> %>
          <span class="text-gray-800 break-all font-mono flex-1 min-w-0"><%= @href %></span>
          <.copy_button text={@href} />
        <% true -> %>
          <span class="text-gray-400 italic">n/a</span>
      <% end %>
    </div>
    """
  end

  @band_fields [
    {"data_type", "Data type"},
    {"nodata", "Nodata"},
    {"scale", "Scale"},
    {"offset", "Offset"},
    {"spatial_resolution", "Resolution"},
    {"sampling", "Sampling"},
    {"unit", "Unit"}
  ]

  attr :bands, :list, required: true

  defp bands_table(assigns) do
    fields =
      Enum.filter(@band_fields, fn {name, _} ->
        Enum.any?(assigns.bands, &(band_field(&1, name) != nil))
      end)

    assigns = assign(assigns, fields: fields, multi: length(assigns.bands) > 1)

    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full text-xs text-left">
        <thead class="text-gray-500">
          <tr>
            <th :if={@multi} class="pr-3 py-0.5 font-medium">#</th>
            <th :for={{_, label} <- @fields} class="pr-3 py-0.5 font-medium whitespace-nowrap"><%= label %></th>
          </tr>
        </thead>
        <tbody class="font-mono text-gray-800">
          <tr :for={{band, i} <- Enum.with_index(@bands, 1)}>
            <td :if={@multi} class="pr-3 py-0.5 text-gray-400"><%= i %></td>
            <td :for={{name, _} <- @fields} class="pr-3 py-0.5 whitespace-nowrap">
              <.value v={band_field(band, name)} depth={2} />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
