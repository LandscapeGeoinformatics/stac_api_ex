defmodule StacApi.StaticKeysTest do
  use ExUnit.Case, async: false

  alias StacApi.StaticKeys

  setup do
    previous = Application.get_env(:stac_api, :api_keys)
    on_exit(fn -> Application.put_env(:stac_api, :api_keys, previous) end)

    Application.put_env(:stac_api, :api_keys, %{
      read_write: ["rw-one", "rw-two"],
      read_only: ["ro-one"]
    })

    :ok
  end

  test "returns the level of a static key" do
    assert StaticKeys.level("rw-one") == :read_write
    assert StaticKeys.level("rw-two") == :read_write
    assert StaticKeys.level("ro-one") == :read_only
  end

  test "returns nil for anything that is not a static key" do
    assert StaticKeys.level("stac_ro_issued-key") == nil
    assert StaticKeys.level("rw-on") == nil
    assert StaticKeys.level("rw-one-and-more") == nil
    assert StaticKeys.level(nil) == nil
    assert StaticKeys.level(123) == nil
  end

  test "a blank key never matches, even if a blank key is configured" do
    Application.put_env(:stac_api, :api_keys, %{read_write: [""], read_only: [nil, ""]})

    assert StaticKeys.level("") == nil
  end

  test "missing lists count as no keys" do
    Application.put_env(:stac_api, :api_keys, %{read_write: nil, read_only: ["ro-one"]})

    assert StaticKeys.level("ro-one") == :read_only
    assert StaticKeys.level("rw-one") == nil
  end

  test "raises when the keys are not configured at all" do
    Application.delete_env(:stac_api, :api_keys)

    assert_raise RuntimeError, ~r/API keys configuration is missing/, fn ->
      StaticKeys.level("anything")
    end
  end
end
