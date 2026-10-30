# STAC API Documentation

  

## Overview

  

This Phoenix application provides a STAC (SpatioTemporal Asset Catalog) API implementation with both REST API endpoints and HTML browser interface for exploring geospatial data catalogs.



## Contributing

### External Contributors
- Fork the repository from [GitHub](https://github.com/LandscapeGeoinformatics/stac_api_ex).
- Create a feature branch for your changes.
- Submit a Pull Request to the `master` branch.
- Keep pull requests focused on specific updates.


### Updated initialisation

```bash
# git clone
# cd folder

mix deps.get
# mix ecto.setup for local docker dev could work (but have postgres db credentials
)
mix assets.setup
mix assets.build

mix compile

mix assets.deploy

mix ecto.migrate
mix test

```



### Maintainer Workflow (Dual Remote Mirroring)
We maintain an internal GitLab (`origin`) and a public GitHub mirror (`outbound`). To keep histories identical across both while using rebases, follow the "Mirroring Workflow":

#### 1. One-Time Setup
Create a combined `all` remote that pushes to both GitLab and GitHub:
```bash
git remote add all git@gitlab.ut.ee:geog/stac_api_ex.git
git remote set-url --add --push all git@gitlab.ut.ee:geog/stac_api_ex.git
git remote set-url --add --push all git@github.com:LandscapeGeoinformatics/stac_api_ex.git
```

#### 2. Daily Development
Always pull from the internal GitLab and push to the combined remote:
```bash
# Pull and rebase from internal source
git pull origin master --rebase

# Push to both remotes simultaneously
git push all master --force-with-lease
```

#### 3. Merging GitHub Pull Requests
When merging external contributions from GitHub:
```bash
# Fetch the PR branch (replace ID with PR number)
git fetch outbound pull/ID/head:pr-branch

# Rebase and merge locally
git checkout master
git rebase pr-branch

# Update both remotes
git push all master --force-with-lease
git branch -D pr-branch
```




## Source JSON to Database Flow

  

### Import Process

  

The application uses a dedicated importer module to load STAC JSON data into PostgreSQL with PostGIS extension.

  

#### Import Task

  

```bash

# Import from default directory (priv/stac_data)

mix  stac.import

  
# Import from custom directory

mix  stac.import  /path/to/stac/data

```

  

#### How it Works

  

The importer (`StacApi.Data.Importer`) performs the following:

  

1.  **Collections Import**: Scans for `collection.json` files using pattern `**/collection.json`

2.  **Items Import**: Processes all `*.json` files except `collection.json` and `catalog.json`

3.  **Data Validation**: Only imports valid STAC Items (Features with geometry)

4.  **Conflict Resolution**: Uses `on_conflict: :replace_all` for upserts

  

#### File Structure Expected

  

```

priv/stac_data/

├── collection1/

│ ├── collection.json

│ ├── item1.json

│ ├── item2.json

│ └── assets/

│ ├── item1.tif

│ └── item2.tif

└── collection2/

├── collection.json

└── items/

├── item3.json

└── item4.json

```

  

#### On-Demand Import

  

The import can be triggered:

-  **CLI Task**: `mix stac.import` (shown above)

-  **Programmatically**: Call `StacApi.Data.Importer.import_from_directory/1`

-  **Potential Web Interface**: Could be extended to provide admin upload interface

  

### Database Schema

  

-  **Collections**: Stores STAC Collection metadata

-  **Items**: Stores STAC Items with PostGIS geometry fields

-  **Relationships**: Items reference collections via `collection_id`

-  **Timestamps**: All timestamp columns are `timestamptz(6)`, and every schema `use`s
   `StacApi.Schema` rather than `Ecto.Schema`, which fixes the Ecto type
   (`:utc_datetime_usec`) in one place. This is what makes stored timestamps render as
   RFC 3339 with an offset; a `NaiveDateTime` would silently render without one and fail
   STAC conformance. Note Ecto's `:utc_datetime*` types map to Postgres `timestamp`, not
   `timestamptz` — a migration has to say `timestamptz` explicitly. See
   [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md#timestamps).

  

## HTML Browser Interface

  

### Current Implementation

  

The browser interface (`StacBrowserController`) provides:

  

-  **Directory Navigation**: Browse STAC data structure

-  **Search Interface**: Query items with various filters

-  **File Viewing**: Display JSON content inline

   

## Geographic Types and Libraries

  

### PostGIS Integration

  

The application uses PostgreSQL with PostGIS extension for spatial data:

  

```elixir

# Database configuration includes PostGIS extension

config  :stac_api, StacApi.Repo,

extensions: [{Geo.PostGIS.Extension, library:  Geo}]

```

  

### Geo Library Usage

  

**Geo.ex** provides Elixir structs for geometric data:

  

```elixir

# Converting GeoJSON to PostGIS format

{:ok, geo_struct} = Geo.JSON.decode(geojson_geometry)

# Geo structs used in schema

field  :geometry, Geo.PostGIS.Geometry

```

  

### Spatial Queries

  

The Search module can be extended for spatial queries:

  

```elixir

# Example spatial query (to be implemented)

from  i  in  Item,

where:  st_intersects(i.geometry, ^query_polygon)

```

  

## Application Architecture for Integration

  

### Core Components
```
StacApi/

├── Data/ # Data layer

│ ├── Collection.ex # Collection schema

│ ├── Item.ex # Item schema

│ ├── Search.ex # Search logic

│ └── Importer.ex # Data import

├── Web/ # Web layer

│ ├── Controllers/

│ │ ├── RootController.ex

│ │ ├── SearchController.ex

│ │ ├── StacBrowserController.ex

│ │ └── CatalogJSON.ex / CollectionJSON.ex / ItemJSON.ex # Management API serializers

│ └── Router.ex

├── Schema.ex # Shared Ecto schema base (timestamp type)

└── Repo.ex # Database interface

```

Management API responses are built by one serializer module per type, so each STAC
representation is defined once instead of being rebuilt inline in every controller action.
The public STAC API keeps its own representations (`CollectionsController.sanitize_collection/1`,
`Search.serialize_item_for_api/1`) and does not share these.

  

### Integration Points

  

For merging into an existing Phoenix application (e.g., geokuup.ee):

  

#### 1. Database Integration

```elixir
config  :your_app, YourApp.Repo,

extensions: [{Geo.PostGIS.Extension, library:  Geo}]
```

  

#### 2. Router Integration

```elixir
# STAC API — public read (optional auth for private catalogs)
scope "/stac/api/v1", YourAppWeb do
  pipe_through [:api, :read_auth]
  get "/", RootController, :index
  get "/conformance", RootController, :conformance
  get "/search", SearchController, :index
  post "/search", SearchController, :index
  get "/collections", CollectionsController, :index
  get "/collections/:id", CollectionsController, :show
  get "/collections/:id/items", CollectionsController, :items
  get "/collections/:collection_id/items/:item_id", CollectionsController, :show_item
end

# Management API — requires RW key
scope "/stac/manage/v1", YourAppWeb do
  pipe_through [:api, :auth]
  # catalogs, collections, items CRUD routes
end

scope "/stac/web", YourAppWeb do
  pipe_through :browser
  get "/browse", StacBrowserController, :index
  get "/browse/*path", StacBrowserController, :show
end
```

  

#### 3. Module Integration

- Copy `StacApi.Data.*` modules to your app's data layer

- Adapt controllers to your app's naming convention

- Update references to use your app's Repo module

  

#### 4. Dependencies

Add to `mix.exs`:

```elixir

{:geo, "~> 3.4"},

{:geo_postgis, "~> 3.4"},

{:jason, "~> 1.2"}

```

  

### Migration Strategy

  

1.  **Database**: Run STAC table migrations in target app

2.  **Modules**: Namespace modules under target app

3.  **Routes**: Integrate routes into existing router

4.  **Configuration**: Merge database and geo configurations

5.  **Assets**: Ensure asset serving routes don't conflict

  

## Configuration Management

  

### Making STAC Data Path Configurable

  

#### Option 1: Runtime Configuration

  

```elixir

# config/runtime.exs

import  Config

config  :stac_api, :stac_data_path,

System.get_env("STAC_DATA_PATH") || "priv/stac_data"

```

  

#### Option 2: Environment-Specific Configuration

  

```elixir

# config/dev.exs

config  :stac_api, :stac_data_path, "priv/stac_data"

  

# config/prod.exs

config  :stac_api, :stac_data_path, "/opt/app/stac_data"

```

  

#### Usage in Code

  

```elixir

# Replace hardcoded paths with configuration

defmodule  StacApiWeb.StacBrowserController  do

@stac_data_path  Application.compile_env(:stac_api, :stac_data_path, "priv/stac_data")

# Or for runtime configuration:

defp  get_stac_data_path  do

Application.get_env(:stac_api, :stac_data_path, "priv/stac_data")

end

end

```

  

#### Environment Variables

  

```bash

# .env or deployment configuration

export  STAC_DATA_PATH="/mnt/stac-storage"

export  DATABASE_URL="postgresql://user:pass@localhost/stac_prod"

```

  

### Recommended Configuration Structure

  

```elixir

# config/config.exs - Base configuration

config  :stac_api,

stac_data_path:  "priv/stac_data",

max_search_results:  10000,

default_page_size:  10

  

# config/runtime.exs - Runtime overrides

config  :stac_api,

stac_data_path:  System.get_env("STAC_DATA_PATH") || "priv/stac_data"

```

  

## API Endpoints

### STAC API — public read (`/stac/api/v1`)

- `GET /stac/api/v1/` - STAC root catalog
- `GET /stac/api/v1/conformance` - OGC/STAC conformance classes
- `GET /stac/api/v1/search` - Search STAC items (GET + POST)
- `GET /stac/api/v1/collections` - List all collections
- `GET /stac/api/v1/collections/:id` - Get specific collection
- `GET /stac/api/v1/collections/:id/items` - Get items in collection
- `GET /stac/api/v1/collections/:collection_id/items/:item_id` - Get specific item

### Management API — requires `X-API-Key` (`/stac/manage/v1`)

- Full CRUD for catalogs, collections, and items
- Bulk item import (`POST /stac/manage/v1/items/import`)
- Personal read-only API keys (`/stac/manage/v1/api-keys`, see [below](#personal-read-only-api-keys))

Responses here carry two fields beyond the STAC ones:

- `created` / `updated` — RFC 3339 UTC, top level on catalogs and collections, inside
  `properties` on items (STAC Common Metadata placement). Useful for detecting that a
  resource changed server-side before overwriting it.
- `catalog_id` on collections — the owning catalog, or `null` for root-level collections.
  The `parent` link deliberately points at the STAC root for every collection, so this is
  the only way to see which catalog a collection belongs to.

See [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md#management-api-response-fields)
for the caveats (server timestamps override client-supplied ones; `GET` omits nil fields).

#### Datetimes must be RFC 3339 with a UTC offset

Item temporal values are read from `properties` only — there is no top-level `datetime`
field. Either `properties.datetime` is a valid RFC 3339 UTC string, or it is `null` and
both `properties.start_datetime` and `properties.end_datetime` are given. Anything else
is a `400`; nothing is silently coerced or dropped. Non-UTC offsets are accepted and
normalized to `Z`.

Temporal search matches by intersection with an item's footprint, so range items are
findable and an instant matches a range containing it. Full rules, including the
`datetime=<start>/<end>` and `..` query syntax, are in
[PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md#stac-datetime-handling).

Items created before this was enforced need a one-off backfill, or they stay invisible to
temporal search — `mix stac.backfill_temporal` in development, and in a release:

```bash
bin/stac_api eval 'StacApi.Release.backfill_temporal(["--dry-run"])'
bin/stac_api eval 'StacApi.Release.backfill_temporal()'
```

See [Deployment order](PROJECT_DOCUMENTATION.md#deployment-order).

#### Personal read-only API keys

Besides the two keys set through `STAC_API_KEY` and `STAC_API_KEY_RO`, you can hand out
your own read-only keys, for example one per colleague or per script. That way you can see
who uses what, and cut off one person without changing the key everyone else uses.

A personal key works like the read-only key: it is sent in the `X-API-Key` header, it
unlocks private catalogs (also in the web browser), and it can never write or manage keys.
Only the read-write key can create, change or delete them.

Create a key by giving it a name:

```bash
curl -X POST http://localhost:4000/stac/manage/v1/api-keys \
  -H "X-API-Key: $STAC_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "Anna - field data"}'
```

```json
{
  "success": true,
  "message": "API key created successfully. Store the key now; it cannot be shown again.",
  "data": {
    "id": 1,
    "name": "Anna - field data",
    "key": "stac_ro_Qm3xT7...",
    "key_prefix": "stac_ro_Qm3x",
    "last_used_at": null,
    "inserted_at": "2026-10-23T11:02:41.318204Z",
    "updated_at": "2026-10-23T11:02:41.318204Z"
  }
}
```

**Copy the `key` right away.** Only a hash is stored, so the key is shown this one time and
cannot be looked up later. If it gets lost, rotate it to get a new one.

| Request | What it does |
|---|---|
| `GET /stac/manage/v1/api-keys` | List all keys (name, `key_prefix`, `last_used_at`; never the secret) |
| `GET /stac/manage/v1/api-keys/:id` | Show one key |
| `POST /stac/manage/v1/api-keys` | Create a key from a `name` |
| `PATCH /stac/manage/v1/api-keys/:id` | Rename a key; the secret stays the same |
| `POST /stac/manage/v1/api-keys/:id/rotate` | Issue a new secret; the old one stops working immediately |
| `DELETE /stac/manage/v1/api-keys/:id` | Delete a key; it stops working immediately |

A few things that are good to know:

- Names are trimmed, up to 100 characters, and must be unique. Otherwise you get a `422`
  that says what is wrong.
- `key_prefix` is the first characters of the key. Use it to tell which key is which in the
  list.
- `last_used_at` shows when a key was last used, which helps to find keys nobody uses
  anymore. It is `null` for a key that was never used, and it is only updated about once
  an hour, so treat it as approximate.
- After you run `mix ecto.migrate`, the keys live in the `api_keys` table.

### Browser Interface

- `GET /stac/web/browse` - HTML directory browser
- `GET /stac/web/browse/*path` - Browse specific paths
- `GET /stac/web/search` - HTML search interface

  

## Development Workflow

1.  **Setup**: Configure database with PostGIS

2.  **Import Data**: Use `mix stac.import` to load JSON files

3.  **Development**: Use browser interface for testing

4.  **API Testing**: Query REST endpoints for integration

5.  **Deployment**: Configure production data paths and database
