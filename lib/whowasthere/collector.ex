defmodule WhoWasThere.Collector do
  @moduledoc """
  Онлайн-агрегатор. Сырые события не пишутся никуда: только счётчики,
  HyperLogLog и короткоживущие сессии в ETS.
  """
  use GenServer

  alias WhoWasThere.{Billing, HLL, ID, Stamp, Store, UA}

  @session_ms 30 * 60 * 1000
  @live_ms 5 * 60 * 1000
  @dim_cap 150
  @chain_max 8
  @kinds ~w(page ref country device browser os event src medium campaign lang width entry exit flow chain click)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def ingest(event) when is_map(event), do: GenServer.cast(__MODULE__, {:event, event})

  def ping, do: GenServer.call(__MODULE__, :ping)

  def create_site(id, host \\ nil, payment_id \\ nil)

  def create_site(id, host, payment_id) do
    GenServer.call(__MODULE__, {:create_site, id, host, payment_id})
  end

  def site?(id), do: :ets.lookup(:wwt_sites, id) != []

  def site(id) do
    case :ets.lookup(:wwt_sites, id) do
      [{^id, meta}] -> Map.put(meta, :id, id)
      [] -> nil
    end
  end

  def site_by_token(token) when is_binary(token) do
    case Stamp.verify_dash(token) do
      {:ok, claims} -> resolve_dash(claims, token)
      :error -> legacy_token(token)
    end
  end

  def site_by_token(_), do: nil

  def snapshot(id) do
    day = Date.utc_today()

    case :ets.lookup(:wwt_day, {id, day}) do
      [{{^id, ^day}, snap}] -> snap
      [] -> empty_snap()
    end
  end

  def live_count(id) do
    now = now_ms()

    :ets.foldl(
      fn
        {{^id, _}, %{last: last}}, acc -> if now - last <= @live_ms, do: acc + 1, else: acc
        _, acc -> acc
      end,
      0,
      :wwt_sess
    )
  end

  def empty_snap do
    %{
      pageviews: 0,
      sessions: 0,
      bounces: 0,
      duration_ms: 0,
      hll: HLL.new(),
      hours: List.to_tuple(List.duplicate(0, 24)),
      dims: Map.new(@kinds, &{&1, %{}})
    }
  end

  def flush, do: GenServer.call(__MODULE__, :flush)

  def reset! do
    if Process.whereis(__MODULE__), do: GenServer.call(__MODULE__, :reset)
    :ok
  end

  @impl true
  def init(opts) do
    Enum.each(
      [
        {:wwt_sites, [:named_table, :public, :set, read_concurrency: true]},
        {:wwt_tokens, [:named_table, :public, :set, read_concurrency: true]},
        {:wwt_day, [:named_table, :public, :set, read_concurrency: true]},
        {:wwt_sess, [:named_table, :public, :set]},
        {:wwt_dirty, [:named_table, :public, :set]}
      ],
      fn {name, tabs} ->
        if :ets.whereis(name) == :undefined, do: :ets.new(name, tabs)
      end
    )

    WhoWasThere.Billing.ensure_table()

    interval = Keyword.get(opts, :persist_interval, persist_interval())
    skip_load? = Keyword.get(opts, :skip_load, false)
    today = Date.utc_today()

    unless skip_load? do
      WhoWasThere.Billing.warm_cache()
      load_from_store(today)
    end

    if is_integer(interval), do: Process.send_after(self(), :flush, interval)
    Process.send_after(self(), :sweep, 10_000)
    Process.send_after(self(), :broadcast, 1_000)

    {:ok,
     %{
       salt: :crypto.strong_rand_bytes(16),
       day: today,
       persist_interval: interval
     }}
  end

  @impl true
  def handle_cast({:event, event}, state) do
    {:noreply, process(event, maybe_roll(state))}
  end

  @impl true
  def handle_call(:ping, _from, state), do: {:reply, :ok, state}

  def handle_call({:create_site, id, host, payment_id}, _from, state) do
    cond do
      not ID.valid?(id) ->
        {:reply, {:error, :invalid_id}, state}

      meta = site(id) ->
        {:reply, {:ok, meta}, state}

      stored = Store.get_site(id) ->
        {:reply, {:ok, remember(stored)}, state}

      true ->
        payment_id =
          payment_id ||
            case Billing.open_trial(nil) do
              {:ok, pay} -> pay.id
              _ -> nil
            end

        nonce = ID.nonce()
        meta = put_site(id, host, nonce, payment_id)
        token = Stamp.dash_token(id, nonce, host, payment_id)
        {:reply, {:ok, Map.put(meta, :token, token)}, state}
    end
  end

  def handle_call(:flush, _from, state) do
    state = maybe_roll(state)
    persist_dirty(state.day)
    Billing.flush_dirty()
    {:reply, :ok, state}
  end

  def handle_call(:reset, _from, state) do
    Enum.each(
      [:wwt_sites, :wwt_tokens, :wwt_day, :wwt_sess, :wwt_dirty],
      &:ets.delete_all_objects/1
    )

    WhoWasThere.Billing.reset_cache()

    {:reply, :ok, %{state | salt: :crypto.strong_rand_bytes(16), day: Date.utc_today()}}
  end

  @impl true
  def handle_info(:flush, state) do
    state = maybe_roll(state)
    persist_dirty(state.day)
    Billing.flush_dirty()

    if is_integer(state.persist_interval) do
      Process.send_after(self(), :flush, state.persist_interval)
    end

    {:noreply, state}
  end

  def handle_info(:sweep, state) do
    state = maybe_roll(state)
    now = now_ms()
    sweep_sessions(now)
    Billing.tick_notices()
    Process.send_after(self(), :sweep, 10_000)
    {:noreply, state}
  end

  def handle_info(:broadcast, state) do
    for [id] <- :ets.match(:wwt_dirty, {:"$1", :_}) do
      Phoenix.PubSub.broadcast(WhoWasThere.PubSub, "site:#{id}", :refresh)
    end

    Process.send_after(self(), :broadcast, 1_000)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    persist_dirty(state.day)
    Billing.flush_dirty()
    :ok
  end

  defp process(%{site_id: id} = event, state) do
    cond do
      not ID.valid?(id) ->
        state

      UA.bot?(event[:ua]) ->
        state

      true ->
        case admit(event) do
          :drop ->
            state

          :ok ->
            apply_event(event, state)
            state
        end
    end
  end

  defp process(_, state), do: state

  defp apply_event(event, state) do
    id = event.site_id
    name = event[:name] || "v"
    now = event[:at] || now_ms()
    hour = event[:hour] || hour_now()
    visitor = visitor_hash(event, state)
    event = attribute_utm(id, visitor, now, event)
    payment_id = event[:payment_id] || payment_of(id)

    cond do
      not Billing.allow_traffic?(payment_id) ->
        :dropped

      name == "v" and not Billing.allow_pageview?(payment_id) ->
        :dropped

      true ->
        if name == "v", do: Billing.record_pageview(payment_id)

        snap = get_snap(id, state.day)

        snap =
          case name do
            "v" ->
              snap
              |> inc_pageview(hour)
              |> add_unique(visitor)
              |> bump_dims(event, "v")

            "c" ->
              bump_dims(snap, event, "c")

            "k" ->
              %{snap | dims: bump(snap.dims, "click", event[:event] || "click")}

            _ ->
              snap
          end

        snap = touch_session(snap, id, visitor, now, event)
        put_snap(id, state.day, snap)
        :ets.insert(:wwt_dirty, {id, state.day})
        :ok
    end
  end

  defp inc_pageview(snap, hour) do
    hours = put_elem(snap.hours, hour, elem(snap.hours, hour) + 1)
    %{snap | pageviews: snap.pageviews + 1, hours: hours}
  end

  defp add_unique(snap, visitor), do: %{snap | hll: HLL.add(snap.hll, visitor)}

  defp bump_dims(snap, event, "c") do
    dims = bump(snap.dims, "event", event[:event] || "event")
    %{snap | dims: maybe_page_dim(dims, event)}
  end

  defp bump_dims(snap, event, _) do
    ua = UA.parse(event[:ua])

    dims =
      snap.dims
      |> bump("page", event[:path] || "/")
      |> bump("ref", event[:ref] || "direct")
      |> bump("country", event[:country] || "??")
      |> bump("device", ua.device)
      |> bump("browser", ua.browser)
      |> bump("os", ua.os)
      |> bump("src", event[:src] || "direct")
      |> maybe_bump("medium", event[:medium])
      |> maybe_bump("campaign", event[:campaign])
      |> bump("lang", event[:lang] || "??")
      |> maybe_bump("width", event[:width])

    %{snap | dims: dims}
  end

  defp maybe_page_dim(dims, event) do
    if event[:path], do: bump(dims, "page", event.path), else: dims
  end

  defp maybe_bump(dims, kind, key) do
    if present?(key), do: bump(dims, kind, key), else: dims
  end

  defp bump(dims, kind, key) do
    key = key |> to_string() |> String.slice(0, 160)
    map = Map.get(dims, kind, %{})

    map =
      cond do
        Map.has_key?(map, key) -> Map.update!(map, key, &(&1 + 1))
        map_size(map) >= @dim_cap -> map
        true -> Map.put(map, key, 1)
      end

    Map.put(dims, kind, map)
  end

  defp attribute_utm(id, visitor, now, event) do
    case :ets.lookup(:wwt_sess, {id, visitor}) do
      [{_, sess}] when now - sess.last <= @session_ms ->
        event
        |> Map.put(:src, coalesce(sess[:src], event[:src]))
        |> Map.put(:medium, coalesce(sess[:medium], event[:medium]))
        |> Map.put(:campaign, coalesce(sess[:campaign], event[:campaign]))

      _ ->
        event
    end
  end

  defp sess_fields(sess, now, hits, path, chain, event) do
    %{
      start: sess.start,
      last: now,
      hits: hits,
      path: path,
      chain: chain,
      src: event[:src],
      medium: event[:medium],
      campaign: event[:campaign]
    }
  end

  defp coalesce(a, b), do: if(present?(a), do: a, else: b)

  defp present?(v) when v in [nil, "", "direct"], do: false
  defp present?(_), do: true

  defp touch_session(snap, id, visitor, now, event) do
    name = event[:name] || "v"
    path = event[:path] || "/"
    key = {id, visitor}

    case :ets.lookup(:wwt_sess, key) do
      [{^key, sess}] ->
        %{start: start, last: last, hits: hits} = sess
        prev = Map.get(sess, :path)
        chain = Map.get(sess, :chain) || []

        if now - last > @session_ms do
          snap = close_session(snap, start, last, hits, prev, chain)
          open_session(snap, key, now, event)
        else
          {hits, snap, stored_path, chain} =
            continue_session(snap, sess, event, hits, prev, chain, path, name)

          :ets.insert(
            :wwt_sess,
            {key, sess_fields(sess, now, hits, stored_path, chain, event)}
          )

          snap
        end

      [] ->
        open_session(snap, key, now, event)
    end
  end

  defp continue_session(snap, _sess, _event, hits, prev, chain, path, "v") do
    {chain, snap} = push_chain(snap, chain, {:page, path})
    snap = follow_path(snap, prev, path, hits)
    {hits + 1, snap, path, chain}
  end

  defp continue_session(snap, _sess, event, hits, prev, chain, _path, "k") do
    {chain, snap} = push_chain(snap, chain, {:click, event[:event] || "click"})
    {hits, snap, prev, chain}
  end

  defp continue_session(snap, _sess, _event, hits, prev, chain, _path, _name) do
    {hits, snap, prev, chain}
  end

  defp open_session(snap, key, now, event) do
    name = event[:name] || "v"
    path = event[:path] || "/"
    pageview? = name == "v"
    click? = name == "k"

    {chain, snap} =
      cond do
        pageview? ->
          snap =
            snap
            |> Map.update!(:sessions, &(&1 + 1))
            |> Map.update!(:dims, &bump(&1, "entry", path))

          push_chain(snap, [], {:page, path})

        click? ->
          snap = Map.update!(snap, :sessions, &(&1 + 1))
          push_chain(snap, [], {:click, event[:event] || "click"})

        true ->
          {[], snap}
      end

    stored_path = if pageview?, do: path, else: nil
    hits = if pageview?, do: 1, else: 0

    :ets.insert(
      :wwt_sess,
      {key, sess_fields(%{start: now}, now, hits, stored_path, chain, event)}
    )

    snap
  end

  defp push_chain(snap, chain, step) do
    chain = List.wrap(chain)

    cond do
      List.last(chain) == step ->
        {chain, snap}

      length(chain) >= @chain_max ->
        {chain, snap}

      true ->
        chain = chain ++ [step]

        snap =
          if length(chain) >= 2,
            do: %{snap | dims: bump(snap.dims, "chain", format_chain(chain))},
            else: snap

        {chain, snap}
    end
  end

  defp format_chain(chain) do
    chain
    |> Enum.map_join(" → ", fn
      {:page, path} -> trim_path(path)
      {:click, label} -> "click:" <> String.slice(to_string(label), 0, 24)
      other -> to_string(other)
    end)
    |> String.slice(0, 160)
  end

  defp close_session(snap, start, last, hits, path, chain) do
    bounces = if hits <= 1, do: snap.bounces + 1, else: snap.bounces
    snap = %{snap | bounces: bounces, duration_ms: snap.duration_ms + max(last - start, 0)}

    exit_path =
      cond do
        is_binary(path) and path != "" ->
          path

        match?([_ | _], chain) ->
          chain
          |> Enum.reverse()
          |> Enum.find_value(fn
            {:page, p} -> p
            _ -> nil
          end)

        true ->
          nil
      end

    if exit_path, do: %{snap | dims: bump(snap.dims, "exit", exit_path)}, else: snap
  end

  defp follow_path(snap, nil, to, 0) do
    %{snap | sessions: snap.sessions + 1, dims: bump(snap.dims, "entry", to)}
  end

  defp follow_path(snap, nil, _to, _hits), do: snap
  defp follow_path(snap, from, from, _hits), do: snap

  defp follow_path(snap, from, to, _hits) do
    %{snap | dims: bump(snap.dims, "flow", "#{trim_path(from)} → #{trim_path(to)}")}
  end

  defp trim_path(path), do: path |> to_string() |> String.slice(0, 70)

  defp sweep_sessions(now) do
    :ets.foldl(
      fn {{id, _vis} = key, sess}, acc ->
        %{start: start, last: last, hits: hits} = sess

        if now - last > @session_ms do
          day = Date.utc_today()
          snap = get_snap(id, day)

          put_snap(
            id,
            day,
            close_session(
              snap,
              start,
              last,
              hits,
              Map.get(sess, :path),
              Map.get(sess, :chain) || []
            )
          )

          :ets.delete(:wwt_sess, key)
          :ets.insert(:wwt_dirty, {id, day})
        end

        acc
      end,
      :ok,
      :wwt_sess
    )
  end

  defp admit(event) do
    id = event.site_id
    host = event[:host]
    nonce = event[:nonce]
    payment_id = event[:payment_id]

    case lookup_site(id) do
      nil ->
        if is_binary(nonce) and is_binary(payment_id) do
          put_site(id, host, nonce, payment_id)
          :ok
        else
          :drop
        end

      meta ->
        with :ok <- nonce_ok(meta, nonce),
             :ok <- payment_ok(meta, payment_id),
             :ok <- host_ok(id, meta, host) do
          :ok
        end
    end
  end

  defp lookup_site(id) do
    case :ets.lookup(:wwt_sites, id) do
      [{^id, meta}] ->
        meta

      [] ->
        case Store.get_site(id) do
          nil -> nil
          stored -> remember(stored)
        end
    end
  end

  defp nonce_ok(%{nonce: nil}, _), do: :ok
  defp nonce_ok(%{nonce: n}, n), do: :ok
  defp nonce_ok(%{nonce: _}, nil), do: :ok
  defp nonce_ok(_, _), do: :drop

  defp host_ok(id, %{host: nil} = meta, host) do
    if host, do: :ets.insert(:wwt_sites, {id, %{meta | host: host}})
    :ok
  end

  defp host_ok(_id, %{host: locked}, host) do
    if is_nil(host) or host == locked, do: :ok, else: :drop
  end

  defp payment_of(id) do
    case lookup_site(id) do
      %{payment_id: pay} -> pay
      _ -> nil
    end
  end

  defp payment_ok(%{payment_id: nil}, _), do: :ok
  defp payment_ok(%{payment_id: p}, p), do: :ok
  defp payment_ok(%{payment_id: _}, nil), do: :ok
  defp payment_ok(_, _), do: :drop

  defp resolve_dash(%{id: id, nonce: nonce, host: host} = claims, token) do
    payment_id = Map.get(claims, :payment_id)

    case lookup_site(id) do
      nil ->
        %{id: id, host: host, nonce: nonce, payment_id: payment_id, token: token}

      %{nonce: claimed} when is_binary(claimed) and claimed != nonce ->
        nil

      meta ->
        meta
        |> Map.put(:id, id)
        |> Map.put(:token, token)
        |> Map.put(:host, meta.host || host)
        |> Map.put(:payment_id, meta.payment_id || payment_id)
    end
  end

  defp legacy_token(token) do
    case :ets.lookup(:wwt_tokens, token) do
      [{^token, id}] -> site(id)
      [] -> hydrate_token(token)
    end
  end

  defp put_site(id, host, nonce, payment_id) do
    meta = %{
      host: host,
      nonce: nonce,
      payment_id: payment_id,
      created_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    :ets.insert(:wwt_sites, {id, meta})
    :ets.insert(:wwt_dirty, {id, Date.utc_today()})
    Map.put(meta, :id, id)
  end

  defp remember(%Store.Site{} = site) do
    meta = %{
      host: site.host,
      nonce: site.token,
      payment_id: site.payment_id,
      created_at: site.created_at
    }

    :ets.insert(:wwt_sites, {site.id, meta})

    if is_binary(site.token) and not String.contains?(site.token, ".") do
      :ets.insert(:wwt_tokens, {site.token, site.id})
    end

    Map.put(meta, :id, site.id)
  end

  defp hydrate_token(token) do
    case Store.get_by_token(token) do
      nil -> nil
      site -> remember(site)
    end
  rescue
    _ -> nil
  end

  defp get_snap(id, day) do
    case :ets.lookup(:wwt_day, {id, day}) do
      [{{^id, ^day}, snap}] -> snap
      [] -> empty_snap()
    end
  end

  defp put_snap(id, day, snap), do: :ets.insert(:wwt_day, {{id, day}, snap})

  defp visitor_hash(event, state) do
    material = [
      event[:ip] || "",
      event[:ua] || "",
      event.site_id,
      Date.to_iso8601(state.day),
      state.salt
    ]

    <<hash::unsigned-64, _::binary>> = :crypto.hash(:sha256, material)
    hash
  end

  defp maybe_roll(%{day: day} = state) do
    today = Date.utc_today()

    if Date.compare(today, day) == :gt do
      persist_dirty(day)
      drop_days_before(today)

      %{state | day: today, salt: :crypto.strong_rand_bytes(16)}
    else
      state
    end
  end

  defp drop_days_before(today) do
    :ets.foldl(
      fn {{id, day} = key, snap}, acc ->
        if Date.compare(day, today) == :lt do
          persist_site(id, day, snap)
          :ets.delete(:wwt_day, key)
        end

        acc
      end,
      :ok,
      :wwt_day
    )
  end

  defp persist_dirty(day) do
    for [id] <- :ets.match(:wwt_dirty, {:"$1", :_}) do
      persist_site(id, day)
    end

    :ets.delete_all_objects(:wwt_dirty)
  end

  defp persist_site(id, day) do
    case :ets.lookup(:wwt_sites, id) do
      [{^id, meta}] -> Store.upsert_site(id, meta.nonce, meta.host, meta[:payment_id])
      [] -> :ok
    end

    case :ets.lookup(:wwt_day, {id, day}) do
      [{{^id, ^day}, snap}] -> persist_site(id, day, snap)
      [] -> :ok
    end
  end

  defp persist_site(id, day, snap) do
    Store.save_day(id, day, snap)
  rescue
    _ -> :ok
  end

  defp load_from_store(today) do
    Enum.each(Store.list_sites(), fn site ->
      :ets.insert(
        :wwt_sites,
        {site.id,
         %{
           host: site.host,
           nonce: site.token,
           payment_id: site.payment_id,
           created_at: site.created_at
         }}
      )

      if is_binary(site.token), do: :ets.insert(:wwt_tokens, {site.token, site.id})
    end)

    Enum.each(Store.load_today(today), fn {id, snap} ->
      :ets.insert(:wwt_day, {{id, today}, snap})
    end)
  rescue
    _ -> :ok
  end

  defp persist_interval, do: Application.get_env(:whowasthere, :persist_interval, 15_000)
  defp now_ms, do: System.system_time(:millisecond)
  defp hour_now, do: DateTime.utc_now().hour
end
