defmodule StacApiWeb.RootHTML do
  @moduledoc "HTML views for `StacApiWeb.RootController` (currently the API documentation page)."
  use StacApiWeb, :html

  import StacApiWeb.StacBrowserComponents, only: [copy_button: 1]
  import StacApiWeb.StacBrowserHTML, only: [auth_controls: 1]
  alias StacApiWeb.ApiDocs

  embed_templates "root_html/*"

  @doc "Badge classes per HTTP method, in the app palette (navy secondary, lime primary, green accent)."
  def method_class("GET"), do: "bg-secondary text-primary"
  def method_class("POST"), do: "bg-accent text-white"
  def method_class("PUT"), do: "bg-amber-500 text-white"
  def method_class("PATCH"), do: "bg-orange-500 text-white"
  def method_class("DELETE"), do: "bg-red-600 text-white"
  def method_class(_), do: "bg-gray-500 text-white"

  @doc "Label and classes for an endpoint's auth level."
  def auth_badge(:public),
    do: {"Public", "bg-gray-100 text-gray-600 border border-gray-200", "No key needed."}

  def auth_badge(:optional),
    do:
      {"Optional key", "bg-primary/40 text-secondary border border-primary",
       "Works without a key; add X-API-Key to also see private catalogs."}

  def auth_badge(:rw),
    do:
      {"RW key required", "bg-red-50 text-red-700 border border-red-200",
       "X-API-Key with a read-write key, else 401."}

  def auth_badge(_), do: auth_badge(:public)

  def status_class(status) when status < 300, do: "bg-green-100 text-green-800"
  def status_class(status) when status < 400, do: "bg-blue-100 text-blue-800"
  def status_class(status) when status < 500, do: "bg-amber-100 text-amber-800"
  def status_class(_), do: "bg-red-100 text-red-800"

  def pretty_json(data), do: Jason.encode!(data, pretty: true)
end
