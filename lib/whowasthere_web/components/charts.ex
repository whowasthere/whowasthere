defmodule WhoWasThereWeb.Charts do
  @moduledoc false
  use WhoWasThereWeb, :html

  alias WhoWasThere.Format

  @palette [
    "var(--color-primary)",
    "var(--color-accent)",
    "var(--color-info)",
    "var(--color-warning)",
    "var(--color-success)",
    "oklch(0.72 0.12 280)",
    "oklch(0.74 0.11 20)",
    "oklch(0.7 0.08 310)"
  ]

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :points, :list, required: true
  attr :peak, :integer, default: 0

  def area_chart(assigns) do
    dual? = Enum.any?(assigns.points, &is_integer(&1.secondary))
    assigns = assign(assigns, build_area(assigns.points) |> Map.put(:dual?, dual?))

    ~H"""
    <section id={@id} class="panel p-5">
      <div class="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 class="eyebrow">{@title}</h2>
          <p :if={@hint} class="mt-1 text-[10px] text-base-content/30">{@hint}</p>
        </div>
        <div class="flex items-center gap-4">
          <span class="flex items-center gap-1.5 text-[10px] text-base-content/45">
            <span class="viz-swatch viz-swatch-line" /> pageviews
          </span>
          <span :if={@dual?} class="flex items-center gap-1.5 text-[10px] text-base-content/45">
            <span class="viz-swatch viz-swatch-dash" /> uniques
          </span>
          <span class="num text-[11px] text-base-content/40">peak {Format.compact(@peak)}</span>
        </div>
      </div>

      <svg
        class="viz h-52 w-full sm:h-64"
        viewBox={"0 0 #{@w} #{@h}"}
        role="img"
        aria-label={@title}
      >
        <defs>
          <linearGradient id={"#{@id}-fill"} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="var(--color-primary)" stop-opacity="0.38" />
            <stop offset="100%" stop-color="var(--color-primary)" stop-opacity="0" />
          </linearGradient>
        </defs>

        <g class="viz-grid">
          <line
            :for={tick <- @grid}
            x1={@pad_l}
            x2={@w - @pad_r}
            y1={tick.y}
            y2={tick.y}
          />
          <text
            :for={tick <- @grid}
            x={@pad_l - 8}
            y={tick.y + 3}
            text-anchor="end"
          >
            {tick.label}
          </text>
        </g>

        <path :if={@area_d != ""} class="viz-area" d={@area_d} fill={"url(##{@id}-fill)"} />
        <path :if={@line_d != ""} class="viz-line" d={@line_d} />
        <path :if={@dual? and @line2_d != ""} class="viz-line viz-line-2" d={@line2_d} />

        <g class="viz-dots">
          <circle :for={p <- @dots} class="viz-dot" cx={p.x} cy={p.y} r="3.2">
            <title>{p.label} · {p.value}</title>
          </circle>
        </g>

        <g class="viz-axis">
          <text :for={tick <- @x_ticks} x={tick.x} y={@h - 10} text-anchor="middle">
            {tick.label}
          </text>
        </g>
      </svg>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :rows, :list, required: true

  def bar_chart(assigns) do
    assigns = assign(assigns, build_bars(assigns.rows))

    ~H"""
    <section id={@id} class="panel p-5">
      <div class="mb-4 flex items-baseline justify-between gap-3">
        <h2 class="eyebrow">{@title}</h2>
        <span :if={@hint} class="text-[10px] text-base-content/30">{@hint}</span>
      </div>

      <p :if={@bars == []} class="num py-8 text-center text-xs text-base-content/25">no data yet</p>

      <svg
        :if={@bars != []}
        class="viz h-52 w-full sm:h-56"
        viewBox={"0 0 #{@w} #{@h}"}
        role="img"
        aria-label={@title}
      >
        <g class="viz-grid">
          <line
            :for={tick <- @grid}
            x1={@pad_l}
            x2={@w - @pad_r}
            y1={tick.y}
            y2={tick.y}
          />
          <text
            :for={tick <- @grid}
            x={@pad_l - 8}
            y={tick.y + 3}
            text-anchor="end"
          >
            {tick.label}
          </text>
        </g>

        <g class="viz-bars">
          <g :for={bar <- @bars} class="viz-bar">
            <rect
              x={bar.x}
              y={bar.y}
              width={bar.w}
              height={bar.h}
              rx="4"
              fill={bar.color}
            />
            <title>{bar.key} · {bar.value}</title>
            <text
              :if={bar.h > 18}
              class="viz-bar-val"
              x={bar.x + bar.w / 2}
              y={bar.y - 6}
              text-anchor="middle"
            >
              {Format.compact(bar.value)}
            </text>
            <text class="viz-bar-key" x={bar.x + bar.w / 2} y={@h - 12} text-anchor="middle">
              {bar.key}
            </text>
          </g>
        </g>
      </svg>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :rows, :list, required: true
  attr :unit, :string, default: "hits"

  def donut_chart(assigns) do
    slices = pie_slices(assigns.rows)
    total = Enum.reduce(assigns.rows, 0, &(&1.pageviews + &2))
    assigns = assign(assigns, slices: slices, total: total)

    ~H"""
    <section id={@id} class="panel p-5">
      <div class="mb-4 flex items-baseline justify-between gap-3">
        <h2 class="eyebrow">{@title}</h2>
        <span :if={@hint} class="text-[10px] text-base-content/30">{@hint}</span>
      </div>

      <p :if={@slices == []} class="num py-8 text-center text-xs text-base-content/25">no data yet</p>

      <div :if={@slices != []} class="flex flex-col items-center gap-4">
        <div class="relative h-40 w-40">
          <svg class="viz h-full w-full" viewBox="0 0 200 200" role="img" aria-label={@title}>
            <path
              :for={slice <- @slices}
              class="viz-slice"
              d={donut_d(slice.start, slice.stop)}
              fill={slice.color}
              fill-rule="evenodd"
            >
              <title>
                {slice.key} · {Format.compact(slice.value)} ({Format.pct(slice.pct)})
              </title>
            </path>
          </svg>
          <div class="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
            <span class="num text-xl leading-none">{Format.compact(@total)}</span>
            <span class="mt-1 text-[10px] uppercase tracking-[0.14em] text-base-content/35">
              {@unit}
            </span>
          </div>
        </div>

        <ul class="flex w-full flex-col gap-1.5">
          <li :for={slice <- @slices} class="flex items-center gap-2 text-xs">
            <span class="viz-swatch shrink-0" style={"background: #{slice.color}"} />
            <span class="min-w-0 truncate font-mono text-[12px]">{slice.key}</span>
            <span class="num ml-auto text-base-content/50">{Format.compact(slice.value)}</span>
            <span class="num w-10 text-right text-[10px] text-base-content/35">
              {Format.pct(slice.pct)}
            </span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  defp build_area([]), do: empty_area()

  defp build_area(points) do
    w = 800
    h = 260
    pad_l = 44
    pad_r = 16
    pad_t = 20
    pad_b = 36
    inner_w = w - pad_l - pad_r
    inner_h = h - pad_t - pad_b
    bottom = h - pad_b
    n = length(points)

    raw_max =
      points
      |> Enum.map(&max(&1.value, &1.secondary || 0))
      |> Enum.max(fn -> 0 end)

    max_y = nice_max(raw_max)
    span = max(n - 1, 1)

    plotted =
      points
      |> Enum.with_index()
      |> Enum.map(fn {p, i} ->
        x = pad_l + i * inner_w / span
        y = bottom - p.value / max_y * inner_h
        y2 = if is_integer(p.secondary), do: bottom - p.secondary / max_y * inner_h
        Map.merge(p, %{x: x, y: y, y2: y2})
      end)

    grid =
      for t <- [0.0, 0.25, 0.5, 0.75, 1.0] do
        %{
          y: pad_t + inner_h * (1 - t),
          label: Format.compact(round(max_y * t))
        }
      end

    %{
      w: w,
      h: h,
      pad_l: pad_l,
      pad_r: pad_r,
      area_d: area_d(plotted, bottom),
      line_d: line_d(plotted, :y),
      line2_d: line_d(plotted, :y2),
      grid: grid,
      x_ticks: x_ticks(plotted),
      dots: Enum.filter(plotted, &(n <= 32 and &1.value > 0))
    }
  end

  defp empty_area do
    %{
      w: 800,
      h: 260,
      pad_l: 44,
      pad_r: 16,
      area_d: "",
      line_d: "",
      line2_d: "",
      grid: [],
      x_ticks: [],
      dots: [],
      dual?: false
    }
  end

  defp build_bars([]), do: %{w: 640, h: 240, pad_l: 40, pad_r: 8, bars: [], grid: []}

  defp build_bars(rows) do
    rows = Enum.take(rows, 10)
    w = 640
    h = 240
    pad_l = 40
    pad_r = 8
    pad_t = 28
    pad_b = 36
    n = length(rows)
    gap = 10
    inner_w = w - pad_l - pad_r
    inner_h = h - pad_t - pad_b
    bar_w = max((inner_w - gap * (n - 1)) / n, 6)
    max_y = nice_max(rows |> Enum.map(& &1.pageviews) |> Enum.max(fn -> 0 end))

    bars =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, i} ->
        bh = if max_y > 0, do: row.pageviews / max_y * inner_h, else: 0
        bh = if row.pageviews > 0, do: max(bh, 3), else: 0

        %{
          key: short(row.key, 8),
          value: row.pageviews,
          color: Enum.at(@palette, rem(i, length(@palette))),
          x: pad_l + i * (bar_w + gap),
          y: pad_t + inner_h - bh,
          w: bar_w,
          h: bh
        }
      end)

    grid =
      for t <- [0.0, 0.5, 1.0] do
        %{
          y: pad_t + inner_h * (1 - t),
          label: Format.compact(round(max_y * t))
        }
      end

    %{w: w, h: h, pad_l: pad_l, pad_r: pad_r, bars: bars, grid: grid}
  end

  defp pie_slices(rows) do
    total = Enum.reduce(rows, 0, &(&1.pageviews + &2))

    if total <= 0 do
      []
    else
      rows = collapse_other(rows, 5)
      count = length(rows)

      {slices, _} =
        rows
        |> Enum.with_index()
        |> Enum.map_reduce(0.0, fn {row, i}, start ->
          sweep =
            if i == count - 1 do
              max(360.0 - start, 0.0)
            else
              row.pageviews / total * 360.0
            end

          slice = %{
            key: row.key,
            value: row.pageviews,
            pct: row.pageviews / total,
            start: start,
            stop: start + sweep,
            color: Enum.at(@palette, rem(i, length(@palette)))
          }

          {slice, start + sweep}
        end)

      Enum.reject(slices, &(&1.stop - &1.start < 0.4))
    end
  end

  defp collapse_other(rows, keep) do
    {top, rest} = Enum.split(rows, keep)
    other = Enum.reduce(rest, 0, &(&1.pageviews + &2))

    if other > 0 do
      top ++ [%{key: "other", pageviews: other}]
    else
      top
    end
  end

  defp donut_d(start, stop) do
    cx = 100.0
    cy = 100.0
    ro = 82.0
    ri = 54.0
    sweep = stop - start

    if sweep >= 359.9 do
      "M #{cx} #{cy - ro} A #{ro} #{ro} 0 1 1 #{cx} #{cy + ro} A #{ro} #{ro} 0 1 1 #{cx} #{cy - ro} M #{cx} #{cy - ri} A #{ri} #{ri} 0 1 0 #{cx} #{cy + ri} A #{ri} #{ri} 0 1 0 #{cx} #{cy - ri}"
    else
      {ox1, oy1} = polar(cx, cy, ro, start)
      {ox2, oy2} = polar(cx, cy, ro, stop)
      {ix1, iy1} = polar(cx, cy, ri, start)
      {ix2, iy2} = polar(cx, cy, ri, stop)
      large = if sweep > 180, do: 1, else: 0

      "M #{f(ox1)} #{f(oy1)} A #{ro} #{ro} 0 #{large} 1 #{f(ox2)} #{f(oy2)} L #{f(ix2)} #{f(iy2)} A #{ri} #{ri} 0 #{large} 0 #{f(ix1)} #{f(iy1)} Z"
    end
  end

  defp polar(cx, cy, r, deg) do
    rad = :math.pi() * (deg - 90) / 180
    {cx + r * :math.cos(rad), cy + r * :math.sin(rad)}
  end

  defp line_d(points, key) do
    coords =
      points
      |> Enum.map(fn p -> {p.x, Map.get(p, key)} end)
      |> Enum.reject(fn {_x, y} -> is_nil(y) end)

    case coords do
      [] ->
        ""

      [{x, y} | rest] ->
        "M #{f(x)} #{f(y)} " <> Enum.map_join(rest, " ", fn {x, y} -> "L #{f(x)} #{f(y)}" end)
    end
  end

  defp area_d([], _), do: ""

  defp area_d(points, bottom) do
    case line_d(points, :y) do
      "" ->
        ""

      line ->
        last = List.last(points)
        first = hd(points)
        line <> " L #{f(last.x)} #{f(bottom)} L #{f(first.x)} #{f(bottom)} Z"
    end
  end

  defp x_ticks(points) do
    n = length(points)

    cond do
      n == 0 ->
        []

      n <= 8 ->
        Enum.map(points, &%{x: &1.x, label: &1.label})

      true ->
        step = max(div(n - 1, 5), 1)

        points
        |> Enum.with_index()
        |> Enum.filter(fn {_, i} -> rem(i, step) == 0 or i == n - 1 end)
        |> Enum.map(fn {p, _} -> %{x: p.x, label: short(p.label, 10)} end)
        |> Enum.uniq_by(& &1.x)
    end
  end

  defp nice_max(n) when not is_number(n) or n <= 0, do: 1

  defp nice_max(n) do
    mag = :math.pow(10, floor(:math.log10(n)))
    norm = n / mag

    nice =
      cond do
        norm <= 1 -> 1
        norm <= 2 -> 2
        norm <= 5 -> 5
        true -> 10
      end

    trunc(nice * mag)
  end

  defp short(text, n) when is_binary(text) do
    if String.length(text) > n, do: String.slice(text, 0, n - 1) <> "…", else: text
  end

  defp short(other, n), do: other |> to_string() |> short(n)

  defp f(n) when is_integer(n), do: Integer.to_string(n)
  defp f(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
end
