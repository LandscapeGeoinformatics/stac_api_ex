# STAC API Documentation

  

## Overview

  

This Phoenix application provides a STAC (SpatioTemporal Asset Catalog) API implementation with both REST API endpoints and HTML browser interface for exploring geospatial data catalogs.



## Document contribution workflow:

- make a fork from https://github.com/LandscapeGeoinformatics/stac_api_ex yo your own GitHub
- make a new "working branch" for yourself, keep the master branch just clean and in sync with our (https://github.com/LandscapeGeoinformatics/stac_api_ex) master branch (this way you always have a clean base in sync with upstream)
- from your working branch (can also be smaller feature branches) make a pull request to our master branch
- try to keep pull requests somewhat "isolated" (specific updates, not touching all the files all over the place)



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

│ │ └── StacBrowserController.ex

│ └── Router.ex

└── Repo.ex # Database interface

```

  

### Integration Points

  

For merging into an existing Phoenix application (e.g., geokuup.ee):

  

#### 1. Database Integration

```elixir
config  :your_app, YourApp.Repo,

extensions: [{Geo.PostGIS.Extension, library:  Geo}]
```

  

#### 2. Router Integration

```elixir

scope  "/stac/api/v1", YourAppWeb  do
pipe_through  :api
get  "/", StacController, :root
get  "/search", StacController, :search
end
scope  "/stac/web", YourAppWeb  do
pipe_through  :browser
get  "/browse", StacBrowserController, :index
get  "/browse/*path", StacBrowserController, :show
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

  

### REST API

-  `GET /stac/api/v1/` - STAC root catalog

-  `GET /stac/api/v1/search` - Search STAC items with filters

  

### Browser Interface

-  `GET /stac/web/browse` - HTML directory browser

-  `GET /stac/web/browse/*path` - Browse specific paths

-  `GET /stac/web/search` - HTML search interface

  

## Development Workflow

1.  **Setup**: Configure database with PostGIS

2.  **Import Data**: Use `mix stac.import` to load JSON files

3.  **Development**: Use browser interface for testing

4.  **API Testing**: Query REST endpoints for integration

5.  **Deployment**: Configure production data paths and database
