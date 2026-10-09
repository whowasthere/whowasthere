defmodule WhoWasThereWeb.Charts do
  @moduledoc false
  use WhoWasThereWeb, :html

  attr :id, :string, required: true
  attr :payload, :map, required: true
  attr :height, :string, default: "h-60 sm:h-72"

  def chart(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="Chart"
      phx-update="ignore"
      data-chart={Jason.encode!(@payload)}
    >
      <div data-canvas class={["w-full", @height]}></div>
    </div>
    """
  end

  def traffic_payload(points) do
    uniques? = Enum.any?(points, &is_integer(&1.secondary))

    series = [%{"name" => "Pageviews", "kind" => "bar", "data" => Enum.map(points, & &1.value)}]

    series =
      if uniques? do
        series ++
          [
            %{
              "name" => "Unique visitors",
              "kind" => "line",
              "data" => Enum.map(points, &(&1.secondary || 0))
            }
          ]
      else
        series
      end

    %{"labels" => Enum.map(points, & &1.label), "series" => series}
  end
end
