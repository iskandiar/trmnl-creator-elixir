defmodule TrmnlWeb.Layouts do
  use TrmnlWeb, :html
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div id="app-shell">
      {render_slot(@inner_block)}
      <div id="flash-group" class="flash-stack" aria-live="polite">
        <p :for={{kind, message} <- @flash} class="notice" data-kind={kind}>{message}</p>
      </div>
    </div>
    """
  end

  embed_templates "layouts/*"
end
