defmodule StacApi.Data.Catalog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "catalogs" do
    field :title, :string
    field :description, :string
    field :type, :string, default: "Catalog"
    field :stac_version, :string, default: "1.0.0"
    field :extent, :map
    field :links, {:array, :map}
    field :depth, :integer, default: 0
    field :private, :boolean, default: false

    belongs_to :parent_catalog, StacApi.Data.Catalog, foreign_key: :parent_catalog_id
    has_many :child_catalogs, StacApi.Data.Catalog, foreign_key: :parent_catalog_id
    has_many :collections, StacApi.Data.Collection, foreign_key: :catalog_id

    timestamps(type: :utc_datetime)
  end

  def changeset(catalog, attrs) do
    catalog
    |> cast(attrs, [
      :id,
      :title,
      :description,
      :type,
      :stac_version,
      :extent,
      :links,
      :parent_catalog_id,
      :depth,
      :private
    ])
    |> validate_required([:id])
    |> unique_constraint(:id)
    |> foreign_key_constraint(:parent_catalog_id)
    |> validate_depth()
  end

  # Validate depth - root catalog should have depth 0
  defp validate_depth(changeset) do
    depth = get_field(changeset, :depth)
    parent_id = get_field(changeset, :parent_catalog_id)

    case {depth, parent_id} do
      {0, _} -> changeset
      {d, nil} when d > 0 -> add_error(changeset, :depth, "non-root catalog must have parent")
      {d, _} when d > 2 -> add_error(changeset, :depth, "maximum depth is 2 levels")
      _ -> changeset
    end
  end
end
