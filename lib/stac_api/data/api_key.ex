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
  import Ecto.Query

  alias StacApi.Repo

  # last_used_at is refreshed at most this often, to avoid a write per request.
  @last_used_interval_seconds 3600

  schema "api_keys" do
    field :name, :string
    field :key_hash, :string
    field :key_prefix, :string
    field :last_used_at, :utc_datetime_usec

    timestamps()
  end

  @doc """
  Builds a changeset for creating or updating an API key.

  Casts `:name`, `:key_hash` and `:key_prefix` and requires all three. The
  name is trimmed and must be 1-100 characters and unique; `:key_hash` must
  be unique. Callers building a key from user input should only pass `:name`
  from the request and take the hash/prefix from `generate_secret/0`.
  """
  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:name, :key_hash, :key_prefix])
    |> update_change(:name, &trim_name/1)
    |> validate_required([:name, :key_hash, :key_prefix])
    |> validate_length(:name, max: 100)
    |> unique_constraint(:name)
    |> unique_constraint(:key_hash)
  end

  defp trim_name(name) when is_binary(name), do: String.trim(name)
  defp trim_name(name), do: name

  @doc """
  Returns the key whose secret is `raw_secret`, or `nil`.

  Looks the key up by the SHA-256 hash of the secret, which is all that is
  stored. Non-binary input returns `nil`.
  """
  def get_by_secret(raw_secret) when is_binary(raw_secret) do
    Repo.one(from k in __MODULE__, where: k.key_hash == ^hash(raw_secret))
  end

  def get_by_secret(_), do: nil

  @doc """
  Records that `api_key` was just used, at most once per hour.

  Done as a single conditional UPDATE, so concurrent requests cannot both
  write and no write happens when the stored value is recent enough.
  `last_used_at` is therefore accurate to about an hour. Returns `:ok`.
  """
  def touch_last_used(%__MODULE__{id: id}) do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -@last_used_interval_seconds, :second)

    Repo.update_all(
      from(k in __MODULE__,
        where: k.id == ^id and (is_nil(k.last_used_at) or k.last_used_at < ^cutoff)
      ),
      set: [last_used_at: now]
    )

    :ok
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
