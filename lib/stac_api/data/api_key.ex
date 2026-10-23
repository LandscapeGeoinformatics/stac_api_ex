defmodule StacApi.Data.ApiKey do
  @moduledoc """
  A personalized, read-only API key issued through the management API.

  Independent of the single static RW/RO keys configured via
  STAC_API_KEY / STAC_API_KEY_RO — those remain the only way to get
  read-write access or to manage keys at all. Rows here only ever grant
  read-only access to the public STAC API (see ReadAuthPlug).

  Only `key_hash` is persisted. The raw secret exists only in memory at
  creation/rotation time and in the response body returned to the caller
  at that moment — it cannot be recovered afterwards, only rotated.
  """
  use StacApi.Schema
  import Ecto.Changeset

  schema "api_keys" do
    field :name, :string
    field :key_hash, :string
    field :key_prefix, :string

    timestamps()
  end

  @doc """
  Builds a changeset for creating or updating an API key.

  Casts `:name`, `:key_hash` and `:key_prefix`, requires all three, and
  enforces uniqueness of `:key_hash`. Callers building a key from user input
  should only pass `:name` from the request and take the hash/prefix from
  `generate_secret/0`.
  """
  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:name, :key_hash, :key_prefix])
    |> validate_required([:name, :key_hash, :key_prefix])
    |> unique_constraint(:key_hash)
  end

  @doc """
  Generates a fresh random secret plus the attrs to persist for it.
  Returns `{raw_secret, attrs}` — `raw_secret` is shown to the caller once
  and is not itself stored.
  """
  def generate_secret do
    raw = "stac_ro_" <> (:crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false))
    {raw, %{key_hash: hash(raw), key_prefix: String.slice(raw, 0, 12)}}
  end

  @doc "SHA-256 hex digest used to look up a key by its raw secret."
  def hash(raw_secret) when is_binary(raw_secret) do
    :crypto.hash(:sha256, raw_secret) |> Base.encode16(case: :lower)
  end
end
