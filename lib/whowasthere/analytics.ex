defmodule WhoWasThere.Analytics do
  @moduledoc false

  alias WhoWasThere.{Collector, HLL, Store}

  def report(id, range) when range in [:today, :d7, :d30, :d90] do
    today = Date.utc_today()
    {from, to} = dates(range, today)
    include_today? = Date.compare(to, today) != :lt
    today_snap = if include_today?, do: Collector.snapshot(id)
    hist_to = if include_today?, do: Date.add(today, -1), else: to

    hist =
      if Date.compare(from, hist_to) != :gt,
        do: Store.range_totals(id, from, hist_to),
        else: Store.empty_totals()

    hist_dims =
      if Date.compare(from, hist_to) != :gt, do: Store.range_dims(id, from, hist_to), else: %{}

    hist_series =
      if Date.compare(from, hist_to) != :gt, do: Store.range_series(id, from, hist_to), else: []

    totals = if today_snap, do: merge_totals(hist, today_snap), else: hist
    dims = if today_snap, do: merge_dims(hist_dims, today_snap.dims), else: hist_dims

    series =
      if today_snap do
        hist_series ++
          [
            %{
              day: today,
              pageviews: today_snap.pageviews,
              uniques: HLL.cardinality(today_snap.hll)
            }
          ]
      else
        hist_series
      end

    hours =
      cond do
        from == to and include_today? ->
          for h <- 0..23, do: %{hour: h, pageviews: elem(today_snap.hours, h)}

        from == to ->
          Store.range_hours(id, from)

        true ->
          Enum.map(series, fn row ->
            %{hour: Date.to_iso8601(row.day), pageviews: row.pageviews}
          end)
      end

    sessions = max(totals.sessions, 0)
    site = Collector.site(id)

    %{
      site_id: id,
      host: site && site.host,
      range: range,
      from: from,
      to: to,
      live: Collector.live_count(id),
      pageviews: totals.pageviews,
      uniques: totals.uniques,
      sessions: sessions,
      bounces: totals.bounces,
      bounce_rate: ratio(totals.bounces, sessions),
      duration_ms: totals.duration_ms,
      avg_ms: if(sessions > 0, do: div(totals.duration_ms, sessions), else: 0),
      hours: hours,
      series: series,
      dims: sort_dims(dims)
    }
  end

  defp merge_totals(hist, snap) do
    %{
      pageviews: hist.pageviews + snap.pageviews,
      uniques: hist.uniques + HLL.cardinality(snap.hll),
      sessions: hist.sessions + snap.sessions,
      bounces: hist.bounces + snap.bounces,
      duration_ms: hist.duration_ms + snap.duration_ms
    }
  end

  defp merge_dims(hist, today) do
    Map.merge(today, hist, fn _kind, a, b ->
      Map.merge(a, b, fn _k, x, y -> x + y end)
    end)
  end

  defp sort_dims(dims) do
    Map.new(dims, fn {kind, map} ->
      rows =
        map
        |> Enum.sort_by(fn {_k, v} -> -v end)
        |> Enum.take(20)
        |> Enum.map(fn {k, v} -> %{key: k, pageviews: v} end)

      {kind, rows}
    end)
  end

  defp dates(:today, today), do: {today, today}
  defp dates(:d7, today), do: {Date.add(today, -6), today}
  defp dates(:d30, today), do: {Date.add(today, -29), today}
  defp dates(:d90, today), do: {Date.add(today, -89), today}

  defp ratio(_n, 0), do: 0.0
  defp ratio(n, d), do: n / d
end
