defmodule StacApi.Data.Item do
  use Ecto.Schema
  import Ecto.Changeset
  alias StacApi.Data.Collection

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "items" do
    field :stac_version, :string
    field :stac_extensions, {:array, :string}
    field :geometry, Geo.PostGIS.Geometry
    field :bbox, {:array, :float}
    field :datetime, :utc_datetime
    field :properties, :map
    field :assets, :map
    field :links, {:array, :map}

    belongs_to :collection, Collection, foreign_key: :collection_id, type: :string

    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:id, :stac_version, :stac_extensions, :geometry, :bbox,
                    :datetime, :properties, :assets, :links, :collection_id])
    |> validate_required([:id, :geometry, :collection_id])
    |> foreign_key_constraint(:collection_id)
  end
end
