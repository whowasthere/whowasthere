defmodule WhoWasThere.Billing do
  @moduledoc """
  Trials, paid USDC years, shared monthly pageview quota, and renewals.

  Hot path (allow / record pageviews) uses ETS. SQLite is only touched on
  create, renew, email changes, and periodic flush.
  """
  import Ecto.Query

  alias WhoWasThere.{ID, Mailer, Repo}
  alias WhoWasThere.Billing.Solana
  alias WhoWasThere.Store.Payment

  @table :wwt_pay
  @trial_days 7
  @paid_days 365
  @month_cap 500_000
  @price_usdc 30
  @email_re ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/i

  def month_cap, do: @month_cap
  def price_usdc, do: @price_usdc
  def trial_days, do: @trial_days
  def wallet, do: Application.get_env(:whowasthere, :pay_wallet)
  def usdc_mint, do: Application.get_env(:whowasthere, :usdc_mint)

  def ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  def reset_cache do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  def warm_cache do
    ensure_table()

    for pay <- Repo.all(Payment) do
      cache_put(pay)
    end

    :ok
  rescue
    _ -> :ok
  end

  def flush_dirty do
    ensure_table()

    for {id, meta} <- :ets.tab2list(@table), meta[:dirty] do
      case Repo.get(Payment, id) do
        nil ->
          :ok

        pay ->
          pay
          |> Ecto.Changeset.change(%{
            hits_month: meta.hits_month,
            month: meta.month,
            notices: meta.notices || pay.notices
          })
          |> Repo.update!()

          cache_put(%{meta | dirty: false, id: id})
      end
    end

    :ok
  rescue
    _ -> :ok
  end

  def info do
    %{
      wallet: wallet(),
      mint: usdc_mint(),
      amount_usdc: @price_usdc,
      month_cap: @month_cap,
      trial_days: @trial_days,
      paid_days: @paid_days,
      network: Application.get_env(:whowasthere, :solana_network, "mainnet-beta")
    }
  end

  def get(id) when is_binary(id), do: Repo.get(Payment, id)
  def get(_), do: nil

  def get_by_txid(txid) when is_binary(txid), do: Repo.get_by(Payment, txid: txid)
  def get_by_txid(_), do: nil

  def status(nil), do: nil

  def status(%Payment{} = pay) do
    meta = cached(pay.id) || cache_put(pay)
    status_from_meta(meta)
  end

  def status(id) when is_binary(id) do
    case cached(id) || load_cache(id) do
      nil -> nil
      meta -> status_from_meta(follow_successor(meta))
    end
  end

  def current_id(id) when is_binary(id) do
    case cached(id) || load_cache(id) do
      nil -> id
      meta -> follow_successor(meta).id
    end
  end

  def current_id(_), do: nil

  def open_trial(email \\ nil) do
    with {:ok, email} <- normalize_email(email) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      pay = %Payment{
        id: "t_" <> ID.generate_token(),
        kind: "trial",
        txid: nil,
        email: email,
        expires_at: DateTime.add(now, @trial_days * 86_400, :second),
        month: month_key(now),
        hits_month: 0,
        notices: "",
        created_at: now
      }

      inserted = Repo.insert!(pay)
      cache_put(inserted)
      {:ok, inserted}
    end
  end

  def open_paid(txid, email \\ nil) do
    with {:ok, email} <- normalize_email(email),
         {:ok, txid} <- normalize_txid(txid),
         :ok <- Solana.verify_usdc_payment(txid, wallet(), @price_usdc) do
      cond do
        existing = bypass_txid?(txid) && (get(txid) || get_by_txid(txid)) ->
          {:ok, refresh_paid(existing, email)}

        true ->
          with :ok <- ensure_fresh_txid(txid) do
            insert_paid(txid, email)
          end
      end
    end
  end

  def start_for_new(txid, email) do
    cond do
      blank?(txid) ->
        open_trial(email)

      true ->
        case get_by_txid(String.trim(txid)) || get(String.trim(txid)) do
          %Payment{} = pay ->
            with {:ok, email} <- normalize_email(email) do
              pay =
                if bypass_txid?(pay.id) or (is_binary(pay.txid) and bypass_txid?(pay.txid)) do
                  refresh_paid(pay, email)
                else
                  maybe_set_email(pay, email)
                end

              {:ok, pay}
            end

          nil ->
            open_paid(txid, email)
        end
    end
  end

  def renew(from_id, to_txid, email \\ nil) do
    with {:ok, email} <- normalize_email(email),
         {:ok, to_txid} <- normalize_txid(to_txid),
         %Payment{} = from <- get(from_id) || get_by_txid(from_id),
         :ok <- Solana.verify_usdc_payment(to_txid, wallet(), @price_usdc) do
      {:ok, promote(from, to_txid, email)}
    else
      nil -> {:error, :unknown_payment}
      other -> other
    end
  end

  # Keep the id already baked into dashboard tokens and ingest keys.
  # A new txid is stored on that same payment when it is free; otherwise
  # the existing paid row is only used as a source of expiry.
  defp promote(from, to_txid, email) do
    existing = get(to_txid) || get_by_txid(to_txid)

    cond do
      from.id == to_txid or from.txid == to_txid ->
        refresh_paid(from, email)

      match?(%Payment{id: id} when id != from.id, existing) ->
        other = existing
        refreshed = refresh_paid(other, email || from.email)
        upgraded = upgrade_in_place(from, to_txid, email || from.email || other.email, refreshed)
        reattach_sites(other.id, upgraded.id)
        upgraded

      true ->
        case ensure_fresh_txid(to_txid) do
          :ok -> upgrade_in_place(from, to_txid, email || from.email, nil)
          {:error, :txid_used} -> refresh_paid(from, email)
        end
    end
  end

  defp insert_paid(txid, email) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    pay = %Payment{
      id: txid,
      kind: "paid",
      txid: txid,
      email: email,
      expires_at: DateTime.add(now, @paid_days * 86_400, :second),
      month: month_key(now),
      hits_month: 0,
      notices: "",
      created_at: now
    }

    inserted = Repo.insert!(pay)
    cache_put(inserted)
    {:ok, inserted}
  end

  defp upgrade_in_place(from, to_txid, email, source) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    source_exp = source && source.expires_at
    from_exp = from.expires_at

    base =
      [source_exp, from_exp, now]
      |> Enum.reject(&is_nil/1)
      |> Enum.max(DateTime)

    base = if from.kind == "trial", do: now, else: base
    txid = if txid_free?(to_txid, from.id), do: to_txid, else: from.txid

    changes = %{
      kind: "paid",
      txid: txid,
      expires_at: DateTime.add(base, @paid_days * 86_400, :second),
      notices: drop_expiry_notices(from.notices)
    }

    changes =
      if is_binary(email) and email != "", do: Map.put(changes, :email, email), else: changes

    updated = from |> Ecto.Changeset.change(changes) |> Repo.update!()
    cache_put(updated)
    WhoWasThere.Collector.reattach_payment(from.id, updated.id)
    updated
  end

  defp txid_free?(txid, keep_id) do
    case get_by_txid(txid) do
      nil -> true
      %{id: ^keep_id} -> true
      _ -> false
    end
  end

  defp follow_successor(meta) do
    case successor_id(meta.notices) do
      nil ->
        meta

      next ->
        case cached(next) || load_cache(next) do
          nil -> meta
          other -> follow_successor(other)
        end
    end
  end

  defp successor_id(notices) do
    notices
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.find_value(fn tag ->
      case String.split(tag, ":", parts: 2) do
        ["successor", id] -> id
        _ -> nil
      end
    end)
  end

  defp refresh_paid(%Payment{} = pay, email) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    base = if DateTime.compare(pay.expires_at, now) == :gt, do: pay.expires_at, else: now

    changes = %{
      kind: "paid",
      expires_at: DateTime.add(base, @paid_days * 86_400, :second),
      notices: drop_expiry_notices(pay.notices)
    }

    changes =
      cond do
        bypass_txid?(pay.id) and is_binary(email) and email != "" ->
          Map.put(changes, :email, email)

        pay.email in [nil, ""] and is_binary(email) and email != "" ->
          Map.put(changes, :email, email)

        true ->
          changes
      end

    updated = pay |> Ecto.Changeset.change(changes) |> Repo.update!()
    cache_put(updated)
    updated
  end

  defp reattach_sites(from_id, to_id) when from_id == to_id, do: {0, nil}

  defp reattach_sites(from_id, to_id) do
    result =
      from(s in WhoWasThere.Store.Site, where: s.payment_id == ^from_id)
      |> Repo.update_all(set: [payment_id: to_id])

    WhoWasThere.Collector.reattach_payment(from_id, to_id)
    result
  end

  defp drop_expiry_notices(notices) do
    notices
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.reject(&(&1 in ["expired", "trial_soon", "year_soon"]))
    |> Enum.join(",")
  end

  def set_email(payment_id, email) do
    with {:ok, email} <- normalize_email(email),
         %Payment{} = pay <- get(payment_id) || get_by_txid(payment_id) do
      if is_nil(email) do
        {:error, :email_required}
      else
        updated = pay |> Ecto.Changeset.change(%{email: email}) |> Repo.update!()
        cache_put(updated)
        {:ok, updated}
      end
    else
      nil -> {:error, :unknown_payment}
      other -> other
    end
  end

  def allow_pageview?(payment_id) when is_binary(payment_id) do
    case ensure_meta(current_id(payment_id) || payment_id) do
      nil -> false
      meta -> active?(meta) and meta.hits_month < @month_cap
    end
  end

  def allow_pageview?(_), do: false

  def allow_traffic?(payment_id) when is_binary(payment_id) do
    case ensure_meta(current_id(payment_id) || payment_id) do
      nil -> false
      meta -> active?(meta)
    end
  end

  def allow_traffic?(_), do: false

  def record_pageview(payment_id) when is_binary(payment_id) do
    case ensure_meta(current_id(payment_id) || payment_id) do
      nil ->
        :ok

      meta ->
        if active?(meta) and meta.hits_month < @month_cap do
          updated = %{meta | hits_month: meta.hits_month + 1, dirty: true}
          cache_put(updated)
          maybe_quota_mail(updated)
        end

        :ok
    end
  end

  def record_pageview(_), do: :ok

  def tick_notices do
    ensure_table()
    now = DateTime.utc_now()

    for {id, _} <- :ets.tab2list(@table) do
      case ensure_meta(id) do
        nil -> :ok
        meta -> maybe_expiry_mail(meta, now)
      end
    end

    :ok
  rescue
    _ -> :ok
  end

  defp status_from_meta(meta) do
    now = DateTime.utc_now()
    expired? = not active?(meta)
    left = max(@month_cap - meta.hits_month, 0)

    %{
      id: meta.id,
      kind: meta.kind,
      txid: meta.txid,
      email: meta.email,
      expires_at: meta.expires_at,
      expired?: expired?,
      days_left: days_left(meta.expires_at, now),
      month: meta.month,
      hits_month: meta.hits_month,
      month_cap: @month_cap,
      hits_left: left,
      over_quota?: meta.hits_month >= @month_cap
    }
  end

  defp ensure_meta(id) do
    case cached(id) do
      nil -> load_cache(id)
      meta -> roll_month_meta(meta)
    end
  end

  defp load_cache(id) do
    case get(id) do
      nil -> nil
      pay -> cache_put(pay)
    end
  rescue
    _ -> nil
  end

  defp cached(id) do
    ensure_table()

    case :ets.lookup(@table, id) do
      [{^id, meta}] -> roll_month_meta(meta)
      [] -> nil
    end
  end

  defp cache_put(%Payment{} = pay) do
    meta = %{
      id: pay.id,
      kind: pay.kind,
      txid: pay.txid,
      email: pay.email,
      expires_at: pay.expires_at,
      month: pay.month,
      hits_month: pay.hits_month,
      notices: pay.notices || "",
      dirty: false
    }

    cache_put(meta)
  end

  defp cache_put(%{id: id} = meta) do
    ensure_table()
    :ets.insert(@table, {id, meta})
    meta
  end

  defp roll_month_meta(meta) do
    current = month_key(DateTime.utc_now())

    if meta.month == current do
      meta
    else
      updated = %{
        meta
        | month: current,
          hits_month: 0,
          notices: drop_quota_notices(meta.notices),
          dirty: true
      }

      cache_put(updated)
    end
  end

  defp maybe_expiry_mail(%{email: nil}, _), do: :ok
  defp maybe_expiry_mail(%{email: ""}, _), do: :ok

  defp maybe_expiry_mail(meta, now) do
    days = days_left(meta.expires_at, now)

    cond do
      days < 0 and not noticed?(meta, "expired") ->
        Mailer.send(meta.email, "Who Was There expired", expiry_body(meta, :expired))
        notice(meta, "expired")

      meta.kind == "trial" and days in 0..2 and not noticed?(meta, "trial_soon") ->
        Mailer.send(meta.email, "Who Was There trial ends soon", expiry_body(meta, :trial_soon))
        notice(meta, "trial_soon")

      meta.kind == "paid" and days in 0..14 and not noticed?(meta, "year_soon") ->
        Mailer.send(meta.email, "Who Was There renews soon", expiry_body(meta, :year_soon))
        notice(meta, "year_soon")

      true ->
        :ok
    end
  end

  defp maybe_quota_mail(%{email: email} = meta) when email in [nil, ""], do: meta

  defp maybe_quota_mail(meta) do
    cond do
      meta.hits_month >= @month_cap and not noticed?(meta, "quota_full") ->
        Mailer.send(meta.email, "Who Was There monthly cap reached", quota_body(meta, :full))
        notice(meta, "quota_full")

      meta.hits_month >= div(@month_cap * 4, 5) and not noticed?(meta, "quota_80") ->
        Mailer.send(meta.email, "Who Was There at 80% of monthly cap", quota_body(meta, :warn))
        notice(meta, "quota_80")

      true ->
        meta
    end
  end

  defp expiry_body(meta, kind) do
    pay_info = info()

    """
    who was there

    payment  #{meta.id}
    plan     #{meta.kind}
    expires  #{DateTime.to_iso8601(meta.expires_at)}

    #{case kind do
      :trial_soon -> "Your 7-day trial ends soon. Send #{@price_usdc} USDC on Solana, then renew."
      :year_soon -> "Your paid year ends soon. Send #{@price_usdc} USDC on Solana, then renew."
      :expired -> "This plan has expired. Hits are dropped until you renew."
    end}

    wallet   #{pay_info.wallet}
    renew    curl -s 'https://YOUR_HOST/renew?from=#{meta.id}&to=TXID&email=#{meta.email || ""}'
    """
  end

  defp quota_body(meta, kind) do
    """
    who was there

    payment  #{meta.id}
    month    #{meta.month}
    hits     #{meta.hits_month} / #{@month_cap}

    #{if kind == :full, do: "The monthly pageview cap is reached. Further pageviews are dropped until next month.", else: "You are at about 80% of the monthly pageview cap."}
    """
  end

  defp noticed?(meta, tag) do
    meta.notices |> to_string() |> String.split(",", trim: true) |> Enum.member?(tag)
  end

  defp notice(meta, tag) do
    tags =
      (meta.notices || "")
      |> String.split(",", trim: true)
      |> Kernel.++([tag])
      |> Enum.uniq()
      |> Enum.join(",")

    cache_put(%{meta | notices: tags, dirty: true})
  end

  defp drop_quota_notices(notices) do
    notices
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.reject(&(&1 in ["quota_80", "quota_full"]))
    |> Enum.join(",")
  end

  defp active?(meta) do
    DateTime.compare(meta.expires_at, DateTime.utc_now()) == :gt
  end

  defp days_left(expires_at, now) do
    secs = DateTime.diff(expires_at, now, :second)
    if secs < 0, do: -1, else: div(secs, 86_400)
  end

  defp month_key(%DateTime{} = dt) do
    "#{dt.year}-#{dt.month |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp maybe_set_email(pay, nil), do: pay

  defp maybe_set_email(pay, email) do
    if pay.email in [nil, ""] do
      updated = pay |> Ecto.Changeset.change(%{email: email}) |> Repo.update!()
      cache_put(updated)
      updated
    else
      cache_put(pay)
      pay
    end
  end

  defp ensure_fresh_txid(txid) do
    if get_by_txid(txid), do: {:error, :txid_used}, else: :ok
  end

  defp normalize_txid(nil), do: {:error, :txid_required}
  defp normalize_txid(""), do: {:error, :txid_required}

  defp normalize_txid(txid) do
    txid = String.trim(txid)

    cond do
      bypass_txid?(txid) ->
        {:ok, txid}

      String.length(txid) in 64..128 and txid =~ ~r/^[1-9A-HJ-NP-Za-km-z]+$/ ->
        {:ok, txid}

      true ->
        {:error, :bad_txid}
    end
  end

  defp bypass_txid?(txid) when is_binary(txid) do
    case Application.get_env(:whowasthere, :pay_bypass_txid) do
      bypass when is_binary(bypass) and bypass != "" ->
        byte_size(bypass) == byte_size(txid) and Plug.Crypto.secure_compare(bypass, txid)

      _ ->
        false
    end
  end

  defp bypass_txid?(_), do: false

  defp normalize_email(nil), do: {:ok, nil}
  defp normalize_email(""), do: {:ok, nil}

  defp normalize_email(email) do
    email = email |> to_string() |> String.trim() |> String.downcase() |> String.slice(0, 160)

    if email =~ @email_re do
      {:ok, email}
    else
      {:error, :bad_email}
    end
  end

  defp blank?(v), do: v in [nil, ""]
end
