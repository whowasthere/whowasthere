defmodule WhoWasThere.Store do
  @moduledoc false
  import Ecto.Query
  alias WhoWasThere.{HLL, Repo}

  def get_site(id), do: Repo.get(WhoWasThere.Store.Site, id)

  def get_by_token(token) when is_binary(token) do
    Repo.get_by(WhoWasThere.Store.Site, token: token)
  end

  def list_sites, do: Repo.all(WhoWasThere.Store.Site)

  def upsert_site(id, token, host, payment_id \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case get_site(id) do
      nil ->
        Repo.insert!(%WhoWasThere.Store.Site{
          id: id,
          token: token,
          host: host,
          payment_id: payment_id,
          created_at: now
        })

      site ->
        changes =
          %{}
          |> maybe_put(:host, host, site.host)
          |> maybe_put(:token, token, site.token)
          |> maybe_put(:payment_id, payment_id, site.payment_id)

        if changes == %{} do
          site
        else
          site
          |> Ecto.Changeset.change(changes)
          |> Repo.update!()
        end
    end
  end

  defp maybe_put(changes, _key, nil, _old), do: changes
  defp maybe_put(changes, :token, _val, old) when is_binary(old), do: changes
  defp maybe_put(changes, :payment_id, _val, old) when is_binary(old), do: changes
  defp maybe_put(changes, _key, val, val), do: changes
  defp maybe_put(changes, key, val, _old), do: Map.put(changes, key, val)

  def save_day(site_id, %Date{} = day, snap) do
    hll_bin = if day == Date.utc_today(), do: HLL.to_bin(snap.hll), else: nil

    Repo.insert(
      %WhoWasThere.Store.Day{
        site_id: site_id,
        day: day,
        pageviews: snap.pageviews,
        uniques: HLL.cardinality(snap.hll),
        sessions: snap.sessions,
        bounces: snap.bounces,
        duration_ms: snap.duration_ms,
        hll: hll_bin
      },
      on_conflict: {:replace_all_except, [:site_id, :day]},
      conflict_target: [:site_id, :day]
    )

    Repo.delete_all(
      from d in WhoWasThere.Store.Dim, where: d.site_id == ^site_id and d.day == ^day
    )

    Repo.delete_all(
      from h in WhoWasThere.Store.Hour, where: h.site_id == ^site_id and h.day == ^day
    )

    dim_rows =
      for {kind, map} <- snap.dims, {key, views} <- map do
        %{site_id: site_id, day: day, kind: kind, key: key, pageviews: views}
      end

    hour_rows =
      for hour <- 0..23, views = elem(snap.hours, hour), views > 0 do
        %{site_id: site_id, day: day, hour: hour, pageviews: views}
      end

    if dim_rows != [], do: Repo.insert_all(WhoWasThere.Store.Dim, dim_rows)
    if hour_rows != [], do: Repo.insert_all(WhoWasThere.Store.Hour, hour_rows)
    :ok
  end

  def load_today(%Date{} = today) do
    days = Repo.all(from d in WhoWasThere.Store.Day, where: d.day == ^today)
    dims = Repo.all(from d in WhoWasThere.Store.Dim, where: d.day == ^today)
    hours = Repo.all(from h in WhoWasThere.Store.Hour, where: h.day == ^today)

    dims_by_site = Enum.group_by(dims, & &1.site_id)
    hours_by_site = Enum.group_by(hours, & &1.site_id)

    Enum.map(days, fn row ->
      {row.site_id,
       snapshot_from_row(row, dims_by_site[row.site_id] || [], hours_by_site[row.site_id] || [])}
    end)
  end

  def range_totals(site_id, %Date{} = from, %Date{} = to) do
    Repo.one(
      from d in WhoWasThere.Store.Day,
        where: d.site_id == ^site_id and d.day >= ^from and d.day <= ^to,
        select: %{
          pageviews: coalesce(sum(d.pageviews), 0),
          uniques: coalesce(sum(d.uniques), 0),
          sessions: coalesce(sum(d.sessions), 0),
          bounces: coalesce(sum(d.bounces), 0),
          duration_ms: coalesce(sum(d.duration_ms), 0)
        }
    ) || empty_totals()
  end

  def range_dims(site_id, %Date{} = from, %Date{} = to) do
    Repo.all(
      from d in WhoWasThere.Store.Dim,
        where: d.site_id == ^site_id and d.day >= ^from and d.day <= ^to,
        group_by: [d.kind, d.key],
        select: {d.kind, d.key, sum(d.pageviews)}
    )
    |> Enum.reduce(%{}, fn {kind, key, views}, acc ->
      Map.update(acc, kind, %{key => views}, &Map.put(&1, key, views))
    end)
  end

  def range_series(site_id, %Date{} = from, %Date{} = to) do
    rows =
      Repo.all(
        from d in WhoWasThere.Store.Day,
          where: d.site_id == ^site_id and d.day >= ^from and d.day <= ^to,
          select: {d.day, d.pageviews, d.uniques}
      )
      |> Map.new(fn {day, views, uniques} -> {day, {views, uniques}} end)

    Date.range(from, to)
    |> Enum.map(fn day ->
      {views, uniques} = Map.get(rows, day, {0, 0})
      %{day: day, pageviews: views, uniques: uniques}
    end)
  end

  def range_hours(site_id, %Date{} = day) do
    rows =
      Repo.all(
        from h in WhoWasThere.Store.Hour,
          where: h.site_id == ^site_id and h.day == ^day,
          select: {h.hour, h.pageviews}
      )
      |> Map.new()

    for hour <- 0..23, do: %{hour: hour, pageviews: Map.get(rows, hour, 0)}
  end

  def empty_totals do
    %{pageviews: 0, uniques: 0, sessions: 0, bounces: 0, duration_ms: 0}
  end

  defp snapshot_from_row(row, dims, hours) do
    hour_tuple =
      hours
      |> Map.new(&{&1.hour, &1.pageviews})
      |> then(fn map -> for(i <- 0..23, do: Map.get(map, i, 0)) end)
      |> List.to_tuple()

    dim_map =
      Enum.reduce(dims, empty_dims(), fn dim, acc ->
        Map.update(
          acc,
          dim.kind,
          %{dim.key => dim.pageviews},
          &Map.put(&1, dim.key, dim.pageviews)
        )
      end)

    hll = if row.hll, do: HLL.from_bin(row.hll), else: HLL.new()

    %{
      pageviews: row.pageviews,
      sessions: row.sessions,
      bounces: row.bounces,
      duration_ms: row.duration_ms,
      hll: hll,
      hours: hour_tuple,
      dims: dim_map
    }
  end

  def empty_dims do
    %{
      "page" => %{},
      "ref" => %{},
      "country" => %{},
      "device" => %{},
      "browser" => %{},
      "os" => %{},
      "event" => %{},
      "src" => %{},
      "medium" => %{},
      "campaign" => %{},
      "lang" => %{},
      "width" => %{},
      "entry" => %{},
      "exit" => %{},
      "flow" => %{},
      "chain" => %{},
      "click" => %{}
    }
  end
end
