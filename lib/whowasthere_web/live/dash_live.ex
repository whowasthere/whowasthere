defmodule WhoWasThereWeb.DashLive do
  use WhoWasThereWeb, :live_view

  alias WhoWasThere.{Analytics, Billing, Collector, Format}

  @ranges [{:today, "today"}, {:d7, "7d"}, {:d30, "30d"}, {:d90, "90d"}]

  @dim_titles [
    {"entry", "Landings"},
    {"exit", "Exits"},
    {"page", "Pages"},
    {"ref", "Referrers"},
    {"src", "UTM / source"},
    {"medium", "UTM / medium"},
    {"campaign", "UTM / campaign"},
    {"country", "Countries"},
    {"device", "Devices"},
    {"width", "Viewport"},
    {"browser", "Browsers"},
    {"os", "OS"},
    {"lang", "Languages"},
    {"click", "Clicks"},
    {"event", "Events"}
  ]

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Collector.site_by_token(token) do
      %{id: id} = site ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(WhoWasThere.PubSub, "site:#{id}")
        end

        {:ok,
         socket
         |> assign(
           id: id,
           token: token,
           missing: false,
           range: :today,
           host: site.host,
           payment_id: site[:payment_id]
         )
         |> load()}

      _ ->
        {:ok, assign(socket, missing: true, token: token, page_title: "not found")}
    end
  end

  @impl true
  def handle_event("range", %{"r" => r}, socket) when r in ~w(today d7 d30 d90) do
    range = String.to_existing_atom(r)
    {:noreply, socket |> assign(range: range) |> load()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp load(%{assigns: %{missing: true}} = socket), do: socket

  defp load(socket) do
    report = Analytics.report(socket.assigns.id, socket.assigns.range)
    max_bar = report.hours |> Enum.map(& &1.pageviews) |> Enum.max(fn -> 0 end)

    # The host is only known once it is locked: from `?host=` on /new, or from the first hit.
    host = report.host || socket.assigns.host
    billing = Billing.status(socket.assigns[:payment_id])

    assign(socket,
      report: report,
      host: host,
      page_title: host || socket.assigns.id,
      max_bar: max_bar,
      billing: billing,
      dim_titles: @dim_titles,
      ranges: @ranges
    )
  end

  @impl true
  def render(%{missing: true} = assigns) do
    ~H"""
    <Layouts.shell flash={@flash}>
      <section class="mx-auto max-w-lg py-20 text-center sm:py-28">
        <p class="eyebrow">/d/…</p>
        <h1 class="mt-5 text-2xl font-semibold tracking-tight">This link does not work</h1>
        <p class="mt-3 leading-relaxed text-base-content/60">
          The dashboard is only the secret URL printed by <code class="font-mono text-primary">curl /new</code>. The key in your snippet opens
          nothing.
        </p>
        <div class="panel mt-8 px-4 py-3 text-left">
          <p class="num text-sm">curl -s {url(~p"/new")}</p>
        </div>
      </section>
    </Layouts.shell>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.shell flash={@flash} wide>
      <div class="flex flex-col gap-8">
        <header class="flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
          <div class="min-w-0">
            <div class="flex items-center gap-2">
              <span class="pulse" />
              <span class="eyebrow">{@report.live} live now</span>
            </div>
            <h1 class={[
              "mt-3 truncate font-mono text-3xl font-medium tracking-tighter sm:text-4xl",
              is_nil(@host) && "text-base-content/45"
            ]}>
              {@host || "no host yet"}
            </h1>
            <p class="num mt-2 text-xs text-base-content/40">
              {@id} · {@report.from} → {@report.to}
            </p>
            <p :if={is_nil(@host)} class="mt-1 text-xs text-base-content/35">
              The first hit names this site.
            </p>
          </div>

          <div class="seg self-start" role="group" aria-label="date range">
            <button
              :for={{key, label} <- @ranges}
              type="button"
              class="seg-btn"
              aria-pressed={to_string(@range == key)}
              phx-click="range"
              phx-value-r={key}
            >
              {label}
            </button>
          </div>
        </header>

        <section :if={@billing} class="panel px-5 py-4">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <p class="eyebrow">plan</p>
              <p class="num mt-1 text-sm">
                <span class={[
                  @billing.kind == "paid" && "text-primary",
                  @billing.expired? && "text-error"
                ]}>
                  {@billing.kind}
                </span>
                ·
                <%= if @billing.expired? do %>
                  expired
                <% else %>
                  {@billing.days_left}d left
                <% end %>
              </p>
              <p class="mt-1 text-xs text-base-content/40">
                {@billing.hits_month} / {@billing.month_cap} pageviews this month
              </p>
            </div>
            <div class="h-1.5 w-full overflow-hidden rounded-full bg-base-content/10 sm:max-w-xs">
              <div
                class={[
                  "h-full rounded-full transition-all",
                  @billing.over_quota? && "bg-error",
                  not @billing.over_quota? && "bg-primary"
                ]}
                style={"width: #{quota_pct(@billing)}%"}
              />
            </div>
          </div>
          <p :if={@billing.expired?} class="mt-3 text-xs text-error/80">
            Hits are dropped. Pay {Billing.price_usdc()} USDC on Solana, then
            <code class="font-mono">curl /renew?from={@billing.id}&to=TXID</code>
          </p>
        </section>

        <section class="grid grid-cols-2 gap-3 lg:grid-cols-5">
          <.stat label="pageviews" value={Format.compact(@report.pageviews)} accent />
          <.stat
            label="uniques"
            value={Format.compact(@report.uniques)}
            hint={unique_hint(@range)}
          />
          <.stat label="sessions" value={Format.compact(@report.sessions)} />
          <.stat label="bounce rate" value={Format.pct(@report.bounce_rate)} hint="one-page visits" />
          <.stat label="avg. time" value={Format.duration(@report.avg_ms)} hint="per session" />
        </section>

        <section class="panel p-5">
          <div class="mb-5 flex items-baseline justify-between gap-4">
            <h2 class="eyebrow">
              {if @range == :today, do: "by hour · utc", else: "by day"}
            </h2>
            <span class="num text-[11px] text-base-content/40">peak {@max_bar}</span>
          </div>

          <div class="chart flex h-36 items-end gap-[3px]">
            <div :for={bar <- @report.hours} class="col">
              <span class="col-tip">{tip(bar)}</span>
              <div
                :if={bar.pageviews > 0}
                class="col-fill"
                style={"height: #{bar_pct(bar.pageviews, @max_bar)}%"}
              />
              <div :if={bar.pageviews == 0} class="col-empty" />
            </div>
          </div>

          <div class="mt-3 flex justify-between">
            <span class="num text-[10px] text-base-content/30">{axis_start(@report)}</span>
            <span class="num text-[10px] text-base-content/30">{axis_end(@report)}</span>
          </div>
        </section>

        <section class="grid gap-4 lg:grid-cols-2">
          <.dim
            class="lg:col-span-2"
            title="Journeys"
            rows={@report.dims["chain"] || []}
            total={@report.pageviews}
            hint="whole session sequences, clicks included, up to 8 steps"
            wrap
          />
          <.dim
            class="lg:col-span-2"
            title="Steps"
            rows={@report.dims["flow"] || []}
            total={@report.pageviews}
            hint="page A → page B"
          />
        </section>

        <section class="wall">
          <.dim
            :for={{kind, title} <- @dim_titles}
            title={title}
            rows={@report.dims[kind] || []}
            total={@report.pageviews}
          />
        </section>
      </div>
    </Layouts.shell>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :hint, :string, default: nil
  attr :accent, :boolean, default: false

  defp stat(assigns) do
    ~H"""
    <div class="panel panel-lift px-4 py-3.5">
      <p class="eyebrow">{@label}</p>
      <p class={[
        "num mt-2 text-[1.75rem] leading-none",
        @accent && "text-primary"
      ]}>
        {@value}
      </p>
      <p class="mt-2 h-3 text-[10px] leading-3 text-base-content/35">{@hint}</p>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :total, :integer, required: true
  attr :hint, :string, default: nil
  attr :wrap, :boolean, default: false
  attr :class, :any, default: nil

  defp dim(assigns) do
    ~H"""
    <div class={["panel p-5", @class]}>
      <div class="mb-4 flex items-baseline justify-between gap-3">
        <h2 class="eyebrow">{@title}</h2>
        <span :if={@hint} class="text-[10px] text-base-content/30">{@hint}</span>
      </div>

      <p :if={@rows == []} class="num py-2 text-xs text-base-content/25">no data yet</p>

      <ul class="-mx-2 flex flex-col">
        <li :for={{row, i} <- Enum.with_index(@rows, 1)} class="row group">
          <span
            class="row-bar"
            style={"width: #{bar_pct(row.pageviews, @total)}%"}
            aria-hidden="true"
          />
          <span class="row-rank">{i}</span>
          <span class={["row-key min-w-0", if(@wrap, do: "break-words", else: "truncate")]}>
            {row.key}
          </span>
          <span class="num text-xs text-base-content/55">
            {Format.compact(row.pageviews)}
          </span>
        </li>
      </ul>
    </div>
    """
  end

  defp bar_pct(_n, 0), do: 0
  defp bar_pct(0, _), do: 0
  defp bar_pct(n, max), do: max(2, round(n / max * 100))

  defp tip(%{hour: hour, pageviews: views}) when is_integer(hour) do
    "#{pad(hour)}:00 · #{views}"
  end

  defp tip(%{hour: label, pageviews: views}), do: "#{label} · #{views}"

  defp axis_start(%{hours: [%{hour: hour} | _]}) when is_integer(hour), do: "00:00"
  defp axis_start(%{hours: [%{hour: label} | _]}), do: label
  defp axis_start(_), do: ""

  defp axis_end(%{hours: []}), do: ""

  defp axis_end(%{hours: hours}) do
    case List.last(hours) do
      %{hour: hour} when is_integer(hour) -> "23:59"
      %{hour: label} -> label
      _ -> ""
    end
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp quota_pct(%{hits_month: hits, month_cap: cap}) when cap > 0 do
    min(100, round(hits / cap * 100))
  end

  defp quota_pct(_), do: 0

  defp unique_hint(:today), do: "today, HyperLogLog"
  defp unique_hint(_), do: "sum of daily uniques"
end
