defmodule StacApi.Data.Collection do
  use Ecto.Schema
  import Ecto.Changeset
  alias StacApi.Data.Item

  @primary_key {:id, :string, autogenerate: false}

  schema "collections" do
    field :title, :string
    field :description, :string
    field :license, :string
    field :extent, :map
    field :summaries, :map
    field :keywords, {:array, :string}
    field :providers, {:array, :map}
    field :stac_version, :string
    field :stac_extensions, {:array, :string}
    field :links, {:array, :map}

    # Add catalog relationship
    belongs_to :catalog, StacApi.Data.Catalog, foreign_key: :catalog_id, type: :string
    has_many :items, Item, foreign_key: :collection_id

    timestamps()
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:id, :title, :description, :license, :extent, :summaries,
                    :keywords, :providers, :stac_version, :stac_extensions, :links, :catalog_id])
    |> validate_required([:id])
    |> unique_constraint(:id)
    |> foreign_key_constraint(:catalog_id)
  end
end
