defmodule WhoWasThereWeb.Charts do
  @moduledoc false
  use WhoWasThereWeb, :html

  alias WhoWasThere.Format

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :payload, :map, required: true
  attr :peak, :string, default: nil
  attr :height, :string, default: "h-56 sm:h-64"

  def panel(assigns) do
    ~H"""
    <section class="panel p-5">
      <div class="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div class="min-w-0">
          <h2 class="eyebrow">{@title}</h2>
          <p :if={@hint} class="mt-1 text-[11px] leading-snug text-base-content/40">{@hint}</p>
        </div>
        <span :if={@peak} class="num text-[11px] text-base-content/40">{@peak}</span>
      </div>

      <div
        id={@id}
        phx-hook="Chart"
        phx-update="ignore"
        data-chart={Jason.encode!(@payload)}
      >
        <div data-canvas class={["w-full", @height]}></div>
      </div>
    </section>
    """
  end

  def line_payload(points) do
    uniques? = Enum.any?(points, &is_integer(&1.secondary))

    series = [
      %{"name" => "Pageviews", "data" => Enum.map(points, & &1.value)}
    ]

    series =
      if uniques? do
        series ++
          [
            %{
              "name" => "Uniques",
              "dashed" => true,
              "data" => Enum.map(points, &(&1.secondary || 0))
            }
          ]
      else
        series
      end

    %{
      "type" => "line",
      "labels" => Enum.map(points, & &1.label),
      "series" => series
    }
  end

  def pie_payload(kind, rows) do
    %{"type" => "pie", "items" => named_items(kind, rows, 5)}
  end

  def bar_payload(kind, rows) do
    %{"type" => "bar", "items" => named_items(kind, rows, 10)}
  end

  defp named_items(kind, rows, keep) do
    {top, rest} = Enum.split(rows, keep)
    other = Enum.reduce(rest, 0, &(&1.pageviews + &2))

    items =
      Enum.map(top, fn row ->
        %{"name" => Format.dim_label(kind, row.key), "value" => row.pageviews}
      end)

    if other > 0 do
      items ++ [%{"name" => "Other", "value" => other}]
    else
      items
    end
  end
end
