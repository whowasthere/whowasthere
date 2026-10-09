defmodule WhoWasThereWeb.DashLive do
  use WhoWasThereWeb, :live_view

  import WhoWasThereWeb.Charts, only: [chart: 1]

  alias WhoWasThere.{Analytics, Billing, Collector, Format}
  alias WhoWasThereWeb.Charts

  @ranges [{:today, "Today"}, {:d7, "7 days"}, {:d30, "30 days"}, {:d90, "90 days"}]

  # Tabbed panels: {panel id, [{dim kind, tab label, column hint}]}
  @tabs %{
    "content" => [
      {"page", "Pages", "Pageviews by path"},
      {"entry", "Landings", "First page of a session"},
      {"exit", "Exits", "Last page of a session"}
    ],
    "campaign" => [
      {"src", "Source", "utm_source"},
      {"medium", "Medium", "utm_medium"},
      {"campaign", "Campaign", "utm_campaign"}
    ],
    "actions" => [
      {"click", "Clicks", "Buttons, links and [data-wwt]"},
      {"event", "Events", "Calls to window.wwt()"}
    ],
    "journeys" => [
      {"chain", "Session paths", "One path per session, clicks included, up to 8 steps"},
      {"flow", "Page transitions", "Consecutive pages within a session"}
    ],
    "places" => [
      {"country", "Countries", "Pageviews by visitor country"},
      {"lang", "Languages", "Browser language"}
    ]
  }

  @tech [
    {"device", "Device"},
    {"width", "Screen"},
    {"browser", "Browser"},
    {"os", "System"}
  ]

  @visible_rows 8

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Collector.site_by_token(token) do
      %{id: id} = site ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(WhoWasThere.PubSub, "site:#{id}")
        end

        tabs = Map.new(@tabs, fn {panel, [{kind, _, _} | _]} -> {panel, kind} end)

        {:ok,
         socket
         |> assign(
           id: id,
           token: token,
           missing: false,
           range: :today,
           tab: tabs,
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

  def handle_event("tab", %{"panel" => panel, "kind" => kind}, socket) do
    case Map.fetch(@tabs, panel) do
      {:ok, tabs} ->
        if Enum.any?(tabs, fn {k, _, _} -> k == kind end) do
          {:noreply, update(socket, :tab, &Map.put(&1, panel, kind))}
        else
          {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
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
    _ = Billing.materialize_payment(payment_id)
    billing = Billing.status(payment_id)

    charts = %{"traffic-chart" => Charts.traffic_payload(traffic)}

    socket
    |> assign(
      report: report,
      host: host,
      page_title: host || socket.assigns.id,
      peak: peak,
      charts: charts,
      payment_id: payment_id,
      billing: billing,
      tabs: @tabs,
      tech: @tech,
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
        <p class="eyebrow">Dashboard</p>
        <h1 class="mt-5 text-2xl font-semibold tracking-tight">This link doesn’t work</h1>
        <p class="mt-3 leading-relaxed text-base-content/60">
          Only the secret dashboard URL returned by
          <code class="font-mono text-primary">curl /new</code>
          works here. The tracking key in your snippet cannot open the dashboard.
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
      <div class="dash">
        <header class="dash-head">
          <div class="min-w-0">
            <p class="dash-live" id="live-now">
              <span class="pulse" />
              <span>
                <strong class="num">{@report.live}</strong>
                {if @report.live == 1, do: "visitor", else: "visitors"} on the site now
              </span>
            </p>
            <h1 class={["dash-host", is_nil(@host) && "dash-host--empty"]}>
              {@host || "no host yet"}
            </h1>
            <p class="dash-meta">
              <span>{period_label(@report)}</span>
              <span :if={@report.previous} class="dash-compare">
                Changes compare with the {@report.to |> Date.diff(@report.from) |> Kernel.+(1)} days before
              </span>
              <span :if={is_nil(@host)}>The first visit will set the hostname.</span>
              <span class="num dash-id">{@id}</span>
            </p>
          </div>

          <div class="seg self-start sm:self-end" role="group" aria-label="Date range">
            <button
              :for={{key, label} <- @ranges}
              id={"range-#{key}"}
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

        <section
          :if={@billing}
          id="plan"
          class={["plan", @billing.expired? && "plan--expired"]}
        >
          <p class="plan-name">
            <span class={["plan-kind", "plan-kind--#{@billing.kind}"]}>
              {plan_label(@billing.kind)} plan
            </span>
            <span class="plan-aside">{plan_aside(@billing)}</span>
          </p>
          <div class="plan-quota">
            <div
              class="plan-track"
              role="meter"
              aria-label="Pageviews used this month"
              aria-valuemin="0"
              aria-valuemax={@billing.month_cap}
              aria-valuenow={@billing.hits_month}
            >
              <span
                class={["plan-fill", @billing.over_quota? && "plan-fill--over"]}
                style={"width: #{quota_pct(@billing)}%"}
              />
            </div>
            <p class="plan-numbers">
              <span class="num">{Format.commas(@billing.hits_month)}</span>
              of <span class="num">{Format.commas(@billing.month_cap)}</span>
              pageviews this month
            </p>
          </div>
          <p :if={@billing.expired?} class="plan-warn">
            Pageviews are being dropped. Open your saved payment link to renew by card or with USDC.
          </p>
        </section>

        <section id="overview" class="panel overview">
          <dl class="kpis">
            <.kpi
              id="kpi-pageviews"
              label="Pageviews"
              value={Format.compact(@report.pageviews)}
              exact={Format.commas(@report.pageviews)}
              delta={delta(@report.pageviews, @report.previous, :pageviews)}
              lead
            />
            <.kpi
              id="kpi-uniques"
              label="Unique visitors"
              value={Format.compact(@report.uniques)}
              exact={Format.commas(@report.uniques)}
              delta={delta(@report.uniques, @report.previous, :uniques)}
              note={unique_hint(@range)}
            />
            <.kpi
              id="kpi-sessions"
              label="Sessions"
              value={Format.compact(@report.sessions)}
              exact={Format.commas(@report.sessions)}
              delta={delta(@report.sessions, @report.previous, :sessions)}
            />
            <.kpi
              id="kpi-bounce"
              label="Bounce rate"
              value={Format.pct(@report.bounce_rate)}
              delta={delta(@report.bounce_rate, @report.previous, :bounce_rate)}
              note="Sessions with one page"
              lower_is_better
            />
            <.kpi
              id="kpi-duration"
              label="Avg. session"
              value={Format.duration(@report.avg_ms)}
              delta={delta(@report.avg_ms, @report.previous, :avg_ms)}
            />
          </dl>

          <div class="overview-chart">
            <div class="overview-legend">
              <p>
                {if @range == :today,
                  do: "Pageviews by hour, UTC",
                  else: "Pageviews and unique visitors by day"}
              </p>
              <p class="num">Peak {Format.commas(@peak)}</p>
            </div>
            <.chart id="traffic-chart" payload={@charts["traffic-chart"]} />
          </div>
        </section>

        <div class="dash-grid dash-grid--2">
          <.tabbed panel="content" tabs={@tabs["content"]} tab={@tab} dims={@report.dims} />
          <.board
            id="panel-ref"
            title="Referrers"
            hint="Sites that sent this traffic"
            kind="ref"
            rows={@report.dims["ref"] || []}
          />
        </div>

        <.tabbed
          panel="journeys"
          tabs={@tabs["journeys"]}
          tab={@tab}
          dims={@report.dims}
          path
        />

        <div class="dash-grid dash-grid--3">
          <.tabbed panel="places" tabs={@tabs["places"]} tab={@tab} dims={@report.dims} />
          <section id="panel-tech" class="panel board lg:col-span-2">
            <header class="board-head">
              <h2 class="board-title">Technology</h2>
              <p class="board-hint">Share of pageviews</p>
            </header>
            <div class="tech">
              <.share
                :for={{kind, label} <- @tech}
                id={"share-#{kind}"}
                kind={kind}
                label={label}
                rows={@report.dims[kind] || []}
              />
            </div>
          </section>
        </div>

        <div class="dash-grid dash-grid--2">
          <.tabbed panel="campaign" tabs={@tabs["campaign"]} tab={@tab} dims={@report.dims} />
          <.tabbed panel="actions" tabs={@tabs["actions"]} tab={@tab} dims={@report.dims} />
        </div>
      </div>
    </Layouts.shell>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :exact, :string, default: nil
  attr :delta, :any, default: nil
  attr :note, :string, default: nil
  attr :lead, :boolean, default: false
  attr :lower_is_better, :boolean, default: false

  defp kpi(assigns) do
    ~H"""
    <div id={@id} class={["kpi", @lead && "kpi--lead"]}>
      <dt class="kpi-label">{@label}</dt>
      <dd class="kpi-value num" title={@exact}>{@value}</dd>
      <dd class="kpi-foot">
        <span
          :if={@delta}
          class={[
            "kpi-delta",
            delta_tone(@delta, @lower_is_better)
          ]}
          title="Change from the previous period of the same length"
        >
          <.icon
            name={if(@delta >= 0, do: "hero-arrow-up-mini", else: "hero-arrow-down-mini")}
            class="size-3.5"
          />
          <span class="num">{delta_label(@delta)}</span>
        </span>
        <span :if={@note} class="kpi-note">{@note}</span>
      </dd>
    </div>
    """
  end

  attr :panel, :string, required: true
  attr :tabs, :list, required: true
  attr :tab, :map, required: true
  attr :dims, :map, required: true
  attr :path, :boolean, default: false

  defp tabbed(assigns) do
    current = assigns.tab[assigns.panel]
    {kind, _label, hint} = Enum.find(assigns.tabs, &(elem(&1, 0) == current))
    assigns = assign(assigns, kind: kind, hint: hint)

    ~H"""
    <section id={"panel-#{@panel}"} class="panel board">
      <header class="board-head">
        <div class="dtabs" role="tablist">
          <button
            :for={{kind, label, _} <- @tabs}
            id={"tab-#{@panel}-#{kind}"}
            type="button"
            role="tab"
            class="dtab"
            aria-selected={to_string(kind == @kind)}
            phx-click="tab"
            phx-value-panel={@panel}
            phx-value-kind={kind}
          >
            {label}
          </button>
        </div>
        <p class="board-hint">{@hint}</p>
      </header>
      <.rows id={"rows-#{@panel}"} kind={@kind} rows={@dims[@kind] || []} path={@path} />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :kind, :string, required: true
  attr :rows, :list, required: true

  defp board(assigns) do
    ~H"""
    <section id={@id} class="panel board">
      <header class="board-head">
        <h2 class="board-title">{@title}</h2>
        <p :if={@hint} class="board-hint">{@hint}</p>
      </header>
      <.rows id={"rows-#{@kind}"} kind={@kind} rows={@rows} />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :kind, :string, required: true
  attr :rows, :list, required: true
  attr :path, :boolean, default: false

  defp rows(assigns) do
    total = Enum.reduce(assigns.rows, 0, &(&1.pageviews + &2))
    max = assigns.rows |> Enum.map(& &1.pageviews) |> Enum.max(fn -> 0 end)
    {top, more} = Enum.split(assigns.rows, @visible_rows)
    assigns = assign(assigns, total: total, max: max, top: top, more: more)

    ~H"""
    <div id={@id} class="ranks">
      <p :if={@rows == []} class="ranks-empty">
        No data for this period yet.
      </p>
      <ol :if={@rows != []} class="ranks-list">
        <.rank :for={row <- @top} row={row} kind={@kind} max={@max} total={@total} path={@path} />
      </ol>
      <details :if={@more != []} class="ranks-more">
        <summary>
          <span class="ranks-more-open">Show {length(@more)} more</span>
          <span class="ranks-more-close">Show fewer</span>
        </summary>
        <ol class="ranks-list">
          <.rank :for={row <- @more} row={row} kind={@kind} max={@max} total={@total} path={@path} />
        </ol>
      </details>
    </div>
    """
  end

  attr :row, :map, required: true
  attr :kind, :string, required: true
  attr :max, :integer, required: true
  attr :total, :integer, required: true
  attr :path, :boolean, default: false

  defp rank(assigns) do
    ~H"""
    <li class="rank">
      <span class="rank-bar" style={"width: #{bar_pct(@row.pageviews, @max)}%"} />
      <div class="rank-key">
        <%= if @path do %>
          <span class="hops">
            <%= for {step, si} <- Enum.with_index(Format.path_steps(@row.key)) do %>
              <.icon :if={si > 0} name="hero-chevron-right-mini" class="hop-sep" />
              <span class={["hop", String.starts_with?(step, "click:") && "hop--click"]}>
                {String.replace_prefix(step, "click:", "")}
              </span>
            <% end %>
          </span>
        <% else %>
          <span :if={@kind == "country"} class="flag" aria-hidden="true">{flag(@row.key)}</span>
          <span class="truncate" title={@row.key}>{Format.dim_label(@kind, @row.key)}</span>
        <% end %>
      </div>
      <span class="rank-value num">{Format.compact(@row.pageviews)}</span>
      <span class="rank-share num">{Format.share(@row.pageviews, @total)}</span>
    </li>
    """
  end

  attr :id, :string, required: true
  attr :kind, :string, required: true
  attr :label, :string, required: true
  attr :rows, :list, required: true

  defp share(assigns) do
    assigns = assign(assigns, :slices, slices(assigns.kind, assigns.rows))

    ~H"""
    <div id={@id} class="share">
      <p class="share-label">{@label}</p>
      <%= if @slices == [] do %>
        <div class="share-bar share-bar--empty" />
        <p class="share-empty">No data for this period yet.</p>
      <% else %>
        <div class="share-bar" role="img" aria-label={share_summary(@label, @slices)}>
          <span
            :for={s <- @slices}
            class={["share-seg", "tone-#{s.tone}"]}
            style={"flex-grow: #{s.value}"}
            title={"#{s.name}: #{s.pct}"}
          />
        </div>
        <ul class="share-legend">
          <li :for={s <- @slices}>
            <span class={["share-dot", "tone-#{s.tone}"]} />
            <span class="share-name">{s.name}</span>
            <span class="num share-pct">{s.pct}</span>
          </li>
        </ul>
      <% end %>
    </div>
    """
  end

  defp slices(kind, rows) do
    {top, rest} = Enum.split(rows, 4)
    other = Enum.reduce(rest, 0, &(&1.pageviews + &2))
    total = Enum.reduce(rows, 0, &(&1.pageviews + &2))

    named =
      top
      |> Enum.with_index()
      |> Enum.map(fn {row, i} ->
        %{name: Format.dim_label(kind, row.key), value: row.pageviews, tone: i}
      end)

    named = if other > 0, do: named ++ [%{name: "Other", value: other, tone: "rest"}], else: named

    named
    |> Enum.reject(&(&1.value <= 0))
    |> Enum.map(&Map.put(&1, :pct, Format.share(&1.value, total)))
  end

  defp share_summary(label, slices) do
    label <> ": " <> Enum.map_join(slices, ", ", &"#{&1.name} #{&1.pct}")
  end

  defp bar_pct(_n, 0), do: 0
  defp bar_pct(0, _), do: 0
  defp bar_pct(n, max), do: max(1, round(n / max * 100))

  # Regional indicator symbols render as a flag for ISO 3166 alpha-2 codes.
  defp flag(<<a, b>>) when a in ?A..?Z and b in ?A..?Z,
    do: <<a - ?A + 0x1F1E6::utf8, b - ?A + 0x1F1E6::utf8>>

  defp flag(<<a, b>>) when a in ?a..?z and b in ?a..?z, do: flag(<<a - 32, b - 32>>)
  defp flag(_), do: "🌐"

  defp delta(_current, nil, _key), do: nil

  defp delta(current, previous, key) do
    case Map.fetch!(previous, key) do
      prev when is_number(prev) and prev > 0 -> (current - prev) / prev
      _ -> nil
    end
  end

  defp delta_label(d) do
    pct = abs(d * 100)
    if pct >= 10, do: "#{round(pct)}%", else: :erlang.float_to_binary(pct, decimals: 1) <> "%"
  end

  defp delta_tone(d, _lower) when abs(d) < 0.005, do: "kpi-delta--flat"
  defp delta_tone(d, false) when d > 0, do: "kpi-delta--good"
  defp delta_tone(d, true) when d < 0, do: "kpi-delta--good"
  defp delta_tone(_d, _lower), do: "kpi-delta--bad"

  defp traffic_points(%{range: :today, hours: hours}) do
    Enum.map(hours, fn %{hour: hour, pageviews: views} ->
      %{label: pad(hour) <> ":00", value: views, secondary: nil}
    end)
  end

  defp traffic_points(%{series: series}) do
    Enum.map(series, fn row ->
      %{label: Calendar.strftime(row.day, "%b %-d"), value: row.pageviews, secondary: row.uniques}
    end)
  end

  defp period_label(%{range: :today, from: day}),
    do: "Today, " <> Calendar.strftime(day, "%B %-d") <> " (UTC)"

  defp period_label(%{from: from, to: to}),
    do: Calendar.strftime(from, "%b %-d") <> " – " <> Calendar.strftime(to, "%b %-d, %Y")

  defp plan_label("comp"), do: "Complimentary"
  defp plan_label("paid"), do: "Paid"
  defp plan_label("trial"), do: "Trial"
  defp plan_label(kind), do: kind

  defp plan_aside(%{expired?: true}), do: "expired, pageviews are dropped"
  defp plan_aside(%{days_left: 0}), do: "ends today"
  defp plan_aside(%{days_left: 1}), do: "1 day left"
  defp plan_aside(%{days_left: n}), do: "#{Format.commas(n)} days left"

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp quota_pct(%{hits_month: hits, month_cap: cap}) when cap > 0 do
    min(100, round(hits / cap * 100))
  end

  defp quota_pct(_), do: 0

  defp unique_hint(:today), do: "Estimated for today"
  defp unique_hint(_), do: "Sum of daily estimates"
end
