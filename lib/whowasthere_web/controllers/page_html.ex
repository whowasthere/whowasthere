defmodule WhoWasThereWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use WhoWasThereWeb, :html

  embed_templates "page_html/*"

  attr :id, :string, required: true
  attr :code, :string, required: true

  def copy_block(assigns) do
    ~H"""
    <div class="start-snip">
      <pre id={@id}><code>{@code}</code></pre>
      <button type="button" class="copy-btn copy-btn-always" data-copy-target={@id} id={"#{@id}-copy"}>
        copy
      </button>
    </div>
    """
  end
end
