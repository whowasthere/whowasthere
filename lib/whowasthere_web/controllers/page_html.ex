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
        Copy
      </button>
    </div>
    """
  end

  def plan_status(plan, expires) do
    date = String.slice(to_string(expires), 0, 10)

    case plan do
      "paid" -> "Paid through #{date}"
      "comp" -> "Complimentary access through #{date}"
      "trial" -> "Free trial ends #{date}"
      _ -> to_string(plan)
    end
  end

  def format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
