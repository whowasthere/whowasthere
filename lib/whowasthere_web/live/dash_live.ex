defmodule WhoWasThereWeb.DashLive do
  use WhoWasThereWeb, :live_view

  import WhoWasThereWeb.Charts, only: [panel: 1]

  alias WhoWasThere.{Analytics, Billing, Collector, Format}
  alias WhoWasThereWeb.Charts

  @ranges [{:today, "today"}, {:d7, "7d"}, {:d30, "30d"}, {:d90, "90d"}]

  @dim_cards [
    {"page", "Pages", "Views by path"},
    {"entry", "Landings", "First page of the visit"},
    {"exit", "Exits", "Last page before they left"},
    {"ref", "Referrers", "Sites that sent this traffic"},
    {"src", "Source", "UTM source"},
    {"medium", "Medium", "UTM medium"},
    {"campaign", "Campaign", "UTM campaign"},
    {"lang", "Languages", "Browser language"},
    {"click", "Clicks", "Buttons, links, [data-wwt]"},
    {"event", "Events", "Custom window.wwt() calls"}
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
    traffic = traffic_points(report)
    peak = traffic |> Enum.map(& &1.value) |> Enum.max(fn -> 0 end)
    host = report.host || socket.assigns.host

    payment_id =
      case Collector.site(socket.assigns.id) do
        %{payment_id: pay} when is_binary(pay) -> pay
        _ -> socket.assigns[:payment_id]
      end

    payment_id = Billing.current_id(payment_id) || payment_id
    billing = Billing.status(payment_id)

    charts = %{
      "traffic-chart" => Charts.line_payload(traffic),
      "chart-devices" => Charts.pie_payload("device", report.dims["device"] || []),
      "chart-browsers" => Charts.pie_payload("browser", report.dims["browser"] || []),
      "chart-os" => Charts.pie_payload("os", report.dims["os"] || []),
      "chart-sessions" => Charts.pie_payload("session", session_slices(report)),
      "chart-countries" => Charts.bar_payload("country", report.dims["country"] || []),
      "chart-viewport" => Charts.bar_payload("width", report.dims["width"] || [])
    }

    socket
    |> assign(
      report: report,
      host: host,
      page_title: host || socket.assigns.id,
      traffic: traffic,
      peak: peak,
      charts: charts,
      payment_id: payment_id,
      billing: billing,
      dim_cards: @dim_cards,
      ranges: @ranges
    )
    |> push_charts(charts)
  end

  defp push_charts(socket, charts) do
    if connected?(socket), do: push_event(socket, "charts", charts), else: socket
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
              {@id} · {Date.to_iso8601(@report.from)} → {Date.to_iso8601(@report.to)}
            </p>
            <p :if={is_nil(@host)} class="mt-1 text-xs text-base-content/35">
              The first visit will name this site.
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
              <p class="mt-1 text-sm">
                <span class={[
                  "font-medium capitalize",
                  @billing.kind == "paid" && "text-primary",
                  @billing.expired? && "text-error"
                ]}>
                  {@billing.kind}
                </span>
                <span class="text-base-content/45">
                  · {plan_aside(@billing)}
                </span>
              </p>
              <p class="mt-1 text-xs text-base-content/45">
                {Format.commas(@billing.hits_month)} of {Format.commas(@billing.month_cap)} pageviews this month
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
            Hits are dropped. Send {Billing.price_usdc()} USDC to the address in your saved payment URL, then open that URL to settle it.
          </p>
        </section>

        <section class="grid grid-cols-2 gap-3 lg:grid-cols-5">
          <.stat
            label="Pageviews"
            value={Format.compact(@report.pageviews)}
            hint="views in this range"
            accent
          />
          <.stat
            label="Unique visitors"
            value={Format.compact(@report.uniques)}
            hint={unique_hint(@range)}
          />
          <.stat
            label="Sessions"
            value={Format.compact(@report.sessions)}
            hint="visits in this range"
          />
          <.stat
            label="Bounce rate"
            value={Format.pct(@report.bounce_rate)}
            hint="left after one page"
          />
          <.stat label="Avg. time" value={Format.duration(@report.avg_ms)} hint="per session" />
        </section>

        <.panel
          id="traffic-chart"
          title="Traffic"
          hint={
            if @range == :today,
              do: "Pageviews by hour, UTC",
              else: "Pageviews and unique visitors by day"
          }
          payload={@charts["traffic-chart"]}
          peak={"peak #{Format.compact(@peak)}"}
        />

        <section class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <.panel
            id="chart-devices"
            title="Devices"
            hint="Desktop, phone, tablet"
            payload={@charts["chart-devices"]}
            height="h-52"
          />
          <.panel
            id="chart-browsers"
            title="Browsers"
            payload={@charts["chart-browsers"]}
            height="h-52"
          />
          <.panel id="chart-os" title="Operating systems" payload={@charts["chart-os"]} height="h-52" />
          <.panel
            id="chart-sessions"
            title="Engagement"
            hint="Bounced vs stayed"
            payload={@charts["chart-sessions"]}
            height="h-52"
          />
        </section>

        <section class="grid gap-4 lg:grid-cols-2">
          <.panel
            id="chart-countries"
            title="Countries"
            hint="Top 10 by pageviews"
            payload={@charts["chart-countries"]}
            height="h-56"
          />
          <.panel
            id="chart-viewport"
            title="Screens"
            hint="Viewport width buckets"
            payload={@charts["chart-viewport"]}
            height="h-56"
          />
        </section>

        <section class="grid gap-4 lg:grid-cols-2">
          <.dim
            class="lg:col-span-2"
            kind="chain"
            title="Session paths"
            rows={@report.dims["chain"] || []}
            hint="One path per visit, clicks included, up to 8 steps"
            path
          />
          <.dim
            class="lg:col-span-2"
            kind="flow"
            title="Page to page"
            rows={@report.dims["flow"] || []}
            hint="Consecutive pages in a session"
            path
          />
        </section>

        <section class="wall">
          <.dim
            :for={{kind, title, hint} <- @dim_cards}
            kind={kind}
            title={title}
            hint={hint}
            rows={@report.dims[kind] || []}
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
      <p class="mt-2 h-4 text-[11px] leading-4 text-base-content/40">{@hint}</p>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :kind, :string, required: true
  attr :rows, :list, required: true
  attr :hint, :string, default: nil
  attr :path, :boolean, default: false
  attr :class, :any, default: nil

  defp dim(assigns) do
    total = Enum.reduce(assigns.rows, 0, &(&1.pageviews + &2))
    max = assigns.rows |> Enum.map(& &1.pageviews) |> Enum.max(fn -> 0 end)
    assigns = assign(assigns, total: total, max: max)

    ~H"""
    <div class={["panel p-5", @class]}>
      <div class="mb-4 flex items-baseline justify-between gap-3">
        <h2 class="eyebrow">{@title}</h2>
        <span
          :if={@hint}
          class="max-w-[18rem] text-right text-[11px] leading-snug text-base-content/35"
        >
          {@hint}
        </span>
      </div>

      <p :if={@rows == []} class="py-6 text-center text-sm text-base-content/35">Nothing here yet</p>

      <ul class="flex flex-col gap-1">
        <li :for={{row, i} <- Enum.with_index(@rows, 1)} class="row">
          <span class="row-rank">{i}</span>
          <div class="min-w-0 flex-1">
            <%= if @path do %>
              <div class="flex flex-wrap items-center gap-1">
                <%= for {step, si} <- Enum.with_index(Format.path_steps(row.key)) do %>
                  <span :if={si > 0} class="text-[10px] text-base-content/30">→</span>
                  <span class={[
                    "inline-flex max-w-full truncate rounded-md px-1.5 py-0.5 font-mono text-[11px]",
                    String.starts_with?(step, "click:") && "bg-accent/15 text-accent",
                    not String.starts_with?(step, "click:") &&
                      "bg-base-content/8 text-base-content/85"
                  ]}>
                    {String.replace_prefix(step, "click:", "")}
                  </span>
                <% end %>
              </div>
            <% else %>
              <p class="row-key truncate" title={row.key}>{Format.dim_label(@kind, row.key)}</p>
            <% end %>
            <div class="row-track">
              <span class="row-fill" style={"width: #{bar_pct(row.pageviews, @max)}%"}></span>
            </div>
          </div>
          <div class="shrink-0 text-right">
            <p class="num text-xs text-base-content/80">{Format.compact(row.pageviews)}</p>
            <p class="num text-[10px] text-base-content/35">{Format.share(row.pageviews, @total)}</p>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  defp bar_pct(_n, 0), do: 0
  defp bar_pct(0, _), do: 0
  defp bar_pct(n, max), do: max(4, round(n / max * 100))

  defp traffic_points(%{range: :today, hours: hours}) do
    Enum.map(hours, fn %{hour: hour, pageviews: views} ->
      %{label: pad(hour) <> ":00", value: views, secondary: nil}
    end)
  end

  defp traffic_points(%{series: series}) do
    Enum.map(series, fn row ->
      %{label: Date.to_iso8601(row.day), value: row.pageviews, secondary: row.uniques}
    end)
  end

  defp session_slices(%{sessions: sessions, bounces: bounces}) when sessions > 0 do
    engaged = max(sessions - bounces, 0)

    [
      %{key: "Stayed", pageviews: engaged},
      %{key: "Bounced", pageviews: bounces}
    ]
  end

  defp session_slices(_), do: []

  defp plan_aside(%{expired?: true}), do: "expired · hits dropped"
  defp plan_aside(%{days_left: 0}), do: "ends today"
  defp plan_aside(%{days_left: 1}), do: "1 day left"
  defp plan_aside(%{days_left: n}), do: "#{n} days left"

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp quota_pct(%{hits_month: hits, month_cap: cap}) when cap > 0 do
    min(100, round(hits / cap * 100))
  end

  defp quota_pct(_), do: 0

  defp unique_hint(:today), do: "estimated for today"
  defp unique_hint(_), do: "sum of daily uniques"
end
