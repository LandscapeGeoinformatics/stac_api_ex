# lib/stac_api_web/components/core_components.ex
defmodule StacApiWeb.CoreComponents do
  use Phoenix.Component

  # Add basic components if needed
  def container(assigns) do
    ~H"""
    <div class="container mx-auto px-4">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end
end
