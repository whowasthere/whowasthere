defmodule WhoWasThere.Billing do
  @moduledoc """
  Trials, paid USDC years, shared monthly pageview quota, and renewals.

  Hot path (allow / record pageviews) uses ETS. SQLite is only touched on
  create, settle, email changes, and periodic flush.
  """
  alias WhoWasThere.{ID, Mailer, PaymentProfile, Repo}
  alias WhoWasThere.Billing.Solana
  alias WhoWasThere.Billing.Stripe, as: StripePay
  alias WhoWasThere.Store.Payment
  alias WhoWasThere.Store.StripeCheckout

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

    for {id, meta} <- :ets.tab2list(@table), is_binary(id), is_map(meta), meta[:dirty] do
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
      network: Application.get_env(:whowasthere, :solana_network, "mainnet-beta"),
      stripe: StripePay.configured?()
    }
  end

  def get(id) when is_binary(id), do: Repo.get(Payment, id)
  def get(_), do: nil

  def status(nil), do: nil

  def status(%Payment{} = pay) do
    meta =
      case cached(pay.id) || load_cache(pay.id) do
        nil -> meta_from_pay(pay)
        meta -> meta
      end

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
        email: email,
        expires_at: DateTime.add(now, @trial_days * 86_400, :second),
        month: month_key(now),
        hits_month: 0,
        month_cap: @month_cap,
        notices: "",
        created_at: now
      }

      inserted = Repo.insert!(pay)
      cache_put(inserted)
      {:ok, inserted}
    end
  end

  def open_profile(email \\ nil) do
    with {:ok, pay} <- open_trial(email) do
      case PaymentProfile.create(pay.id) do
        {:ok, profile, cap} ->
          {:ok, pay, profile, cap}

        {:error, _} = error ->
          Repo.delete!(pay)
          error
      end
    end
  end

  @doc """
  Starts a profile for `/new`.

  Without `pay` and without email, returns a lazy capability that is not written
  to SQLite until first hit, `/pay`, `/notify`, or `/new?pay=`. An email forces
  immediate persistence so reminders have a row to attach to.
  """
  def start_for_profile(nil, email) do
    with {:ok, email} <- normalize_email(email) do
      if email, do: open_profile(email), else: issue_lazy_profile()
    end
  end

  def start_for_profile(cap, email) do
    with {:ok, pay, profile, _cap} <- ensure_profile(cap),
         {:ok, pay} <- settle_profile(profile, pay, cap),
         {:ok, email} <- normalize_email(email) do
      {:ok, maybe_set_email(pay, email), profile, nil}
    end
  end

  def payment_profile(cap) do
    with {:ok, pay, profile, _cap} <- ensure_profile(cap),
         {:ok, pay} <- settle_profile(profile, pay, cap) do
      {:ok, pay, profile}
    end
  end

  def set_profile_email(cap, email) do
    with {:ok, pay, _profile, _cap} <- ensure_profile(cap) do
      set_email(pay.id, email)
    end
  end

  @doc """
  Grants a private payment profile without touching the public payment flow.

  Intended for operator use from a release console. The grant starts now for
  trials and extends the current expiry for an existing paid or comp profile.
  """
  def grant(cap, opts \\ []) when is_binary(cap) and is_list(opts) do
    years = Keyword.get(opts, :years, 1)
    month_cap = Keyword.get(opts, :month_cap, @month_cap)

    cond do
      not (is_integer(years) and years in 1..100) ->
        {:error, :bad_grant_years}

      not (is_integer(month_cap) and month_cap > 0) ->
        {:error, :bad_grant_month_cap}

      true ->
        case ensure_profile(cap) do
          {:ok, pay, _profile, _cap} ->
            now = DateTime.utc_now() |> DateTime.truncate(:second)

            base =
              if pay.kind in ["paid", "comp"],
                do: Enum.max([pay.expires_at, now], DateTime),
                else: now

            updated =
              pay
              |> Ecto.Changeset.change(%{
                kind: "comp",
                expires_at: DateTime.add(base, years * @paid_days * 86_400, :second),
                month_cap: month_cap,
                notices: drop_expiry_notices(pay.notices)
              })
              |> Repo.update!()

            cache_put(updated)
            {:ok, updated}

          error ->
            error
        end
    end
  end

  @doc """
  Deletes unused trial rows that never received traffic or settlement.

  Lazy `/new` calls never create rows; this cleans trials that were materialized
  (email, `/pay`, or a hit) and then abandoned.
  """
  def prune_unused_trials(older_than_days \\ 14)
      when is_integer(older_than_days) and older_than_days > 0 do
    import Ecto.Query

    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-older_than_days * 86_400, :second)
      |> DateTime.truncate(:second)

    candidates =
      Repo.all(
        from p in Payment,
          where: p.kind == "trial" and p.hits_month == 0 and p.created_at < ^cutoff,
          select: p.id
      )

    deleted =
      Enum.reduce(candidates, 0, fn id, count ->
        site? =
          Repo.exists?(
            from s in WhoWasThere.Store.Site,
              where: s.payment_id == ^id
          )

        profile = PaymentProfile.get_by_payment(id)

        if site? or match?(%{settled_usdc: n} when n > 0, profile) do
          count
        else
          case get(id) do
            %Payment{} = pay ->
              Repo.delete!(pay)
              :ets.delete(@table, id)
              count + 1

            _ ->
              count
          end
        end
      end)

    {:ok, deleted}
  rescue
    _ -> {:ok, 0}
  end

  defp issue_lazy_profile do
    with {:ok, lazy} <- PaymentProfile.issue_lazy() do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      pay = %Payment{
        id: lazy.payment_id,
        kind: "trial",
        email: nil,
        expires_at: DateTime.add(now, @trial_days * 86_400, :second),
        month: month_key(now),
        hits_month: 0,
        month_cap: @month_cap,
        notices: "",
        created_at: now
      }

      profile = %WhoWasThere.Store.PaymentProfile{
        id: "profile_lazy",
        payment_id: lazy.payment_id,
        deposit_address: lazy.deposit_address,
        settled_usdc: 0,
        created_at: now
      }

      {:ok, pay, profile, lazy.cap}
    end
  end

  defp ensure_profile(cap) when is_binary(cap) do
    case PaymentProfile.get_by_cap(cap) do
      %{payment_id: payment_id} = profile ->
        case get(payment_id) do
          %Payment{} = pay -> {:ok, pay, profile, cap}
          nil -> {:error, :unknown_payment}
        end

      nil ->
        materialize_cap(cap)
    end
  end

  defp ensure_profile(_), do: {:error, :unknown_payment}

  defp materialize_cap(cap) do
    with payment_id when is_binary(payment_id) <- PaymentProfile.payment_id_for_cap(cap) do
      case materialize_pair(payment_id, cap) do
        {:ok, pay, profile} -> {:ok, pay, profile, cap}
        {:error, _} = error -> error
      end
    else
      _ -> {:error, :unknown_payment}
    end
  end

  defp materialize_payment_id(payment_id) when is_binary(payment_id) do
    case PaymentProfile.cap_for_payment_id(payment_id) do
      cap when is_binary(cap) ->
        case materialize_pair(payment_id, cap) do
          {:ok, pay, _profile} -> pay
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp materialize_pair(payment_id, cap) do
    case PaymentProfile.get_by_cap(cap) do
      %{payment_id: ^payment_id} = profile ->
        case get(payment_id) do
          %Payment{} = pay -> {:ok, pay, profile}
          nil -> {:error, :unknown_payment}
        end

      %{payment_id: _} ->
        {:error, :unknown_payment}

      nil ->
        case get(payment_id) do
          %Payment{} = pay ->
            case PaymentProfile.create(payment_id, cap) do
              {:ok, profile, ^cap} -> {:ok, pay, profile}
              {:error, _} = error -> error
            end

          nil ->
            insert_lazy_pair(payment_id, cap)
        end
    end
  rescue
    e in [Ecto.ConstraintError] ->
      # Concurrent first use — reload the winner.
      case PaymentProfile.get_by_cap(cap) do
        %{payment_id: ^payment_id} = profile ->
          case get(payment_id) do
            %Payment{} = pay -> {:ok, pay, profile}
            nil -> reraise e, __STACKTRACE__
          end

        _ ->
          reraise e, __STACKTRACE__
      end
  end

  defp insert_lazy_pair(payment_id, cap) do
    with {:ok, pay} <- open_trial_with_id(payment_id, nil) do
      case PaymentProfile.create(payment_id, cap) do
        {:ok, profile, ^cap} ->
          {:ok, pay, profile}

        {:error, _} = error ->
          Repo.delete!(pay)
          :ets.delete(@table, payment_id)
          error
      end
    end
  end

  defp open_trial_with_id(payment_id, email) do
    with {:ok, email} <- normalize_email(email) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      pay = %Payment{
        id: payment_id,
        kind: "trial",
        email: email,
        expires_at: DateTime.add(now, @trial_days * 86_400, :second),
        month: month_key(now),
        hits_month: 0,
        month_cap: @month_cap,
        notices: "",
        created_at: now
      }

      inserted = Repo.insert!(pay)
      cache_put(inserted)
      {:ok, inserted}
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

  defp drop_expiry_notices(notices) do
    notices
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.reject(&(&1 in ["expired", "trial_soon", "year_soon"]))
    |> Enum.join(",")
  end

  def set_email(payment_id, email) do
    with {:ok, email} <- normalize_email(email),
         %Payment{} = pay <- get(payment_id) do
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

  def materialize_payment(payment_id) when is_binary(payment_id) do
    case get(payment_id) do
      %Payment{} = pay ->
        cache_put(pay)
        {:ok, pay}

      nil ->
        case materialize_payment_id(payment_id) do
          %Payment{} = pay ->
            cache_put(pay)
            {:ok, pay}

          _ ->
            {:error, :unknown_payment}
        end
    end
  end

  def materialize_payment(_), do: {:error, :unknown_payment}

  @doc """
  Starts a Stripe Checkout session for a private payment capability.

  Amount must be a multiple of #{@price_usdc} USDC (billed as USD 1:1).
  """
  def start_checkout(cap, amount_usdc, urls) when is_binary(cap) and is_map(urls) do
    with true <- StripePay.configured?() || {:error, :stripe_not_configured},
         true <- valid_checkout_amount?(amount_usdc) || {:error, :bad_amount},
         {:ok, pay, _profile, _cap} <- ensure_profile(cap),
         {:ok, session} <-
           StripePay.create_checkout_session(%{
             payment_id: pay.id,
             amount_usdc: amount_usdc,
             success_url: urls.success_url,
             cancel_url: urls.cancel_url
           }) do
      {:ok, session}
    end
  end

  def complete_stripe_checkout(session) when is_map(session) do
    session_id = session["id"]
    payment_id = session["metadata"]["payment_id"] || session["client_reference_id"]
    amount = parse_amount_usdc(session)

    cond do
      not is_binary(session_id) or session_id == "" ->
        {:error, :bad_stripe_session}

      not is_binary(payment_id) or payment_id == "" ->
        {:error, :bad_stripe_session}

      session["payment_status"] not in ["paid", "no_payment_required"] ->
        :ok

      true ->
        apply_stripe_session(session_id, payment_id, amount)
    end
  end

  def complete_stripe_checkout(_), do: {:error, :bad_stripe_session}

  defp apply_stripe_session(session_id, payment_id, amount) do
    import Ecto.Query

    if Repo.exists?(from s in StripeCheckout, where: s.session_id == ^session_id) do
      :ok
    else
      with true <- valid_checkout_amount?(amount) || {:error, :bad_amount},
           %Payment{} = pay <- get(payment_id),
           %{id: _} = profile <- PaymentProfile.get_by_payment(payment_id),
           {:ok, _pay} <- apply_payment(profile, pay, amount) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Repo.insert!(%StripeCheckout{
          session_id: session_id,
          payment_id: payment_id,
          amount_usdc: amount,
          created_at: now
        })

        :ok
      else
        nil -> {:error, :unknown_payment}
        {:error, _} = error -> error
      end
    end
  rescue
    e in [Ecto.ConstraintError] ->
      if String.contains?(to_string(e.constraint), "stripe"),
        do: :ok,
        else: reraise(e, __STACKTRACE__)
  end

  defp parse_amount_usdc(session) do
    case session do
      %{"metadata" => %{"amount_usdc" => value}} ->
        case Integer.parse(to_string(value)) do
          {n, ""} -> n
          _ -> 0
        end

      %{"amount_total" => total} when is_integer(total) ->
        div(total, 100)

      _ ->
        0
    end
  end

  defp valid_checkout_amount?(amount)
       when is_integer(amount) and amount >= @price_usdc and amount <= @price_usdc * 20 do
    rem(amount, @price_usdc) == 0
  end

  defp valid_checkout_amount?(_), do: false

  def allow_pageview?(payment_id) when is_binary(payment_id) do
    case ensure_meta(current_id(payment_id) || payment_id) do
      nil -> false
      meta -> active?(meta) and meta.hits_month < meta_cap(meta)
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
        if active?(meta) and meta.hits_month < meta_cap(meta) do
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

    for {id, meta} <- :ets.tab2list(@table), is_binary(id), is_map(meta) do
      case ensure_meta(id) do
        nil -> :ok
        meta -> maybe_expiry_mail(meta, now)
      end
    end

    maybe_prune_unused_trials(now)
    :ok
  rescue
    _ -> :ok
  end

  defp maybe_prune_unused_trials(now) do
    case :ets.lookup(@table, :__prune_at__) do
      [{:__prune_at__, at}] when is_struct(at, DateTime) ->
        if DateTime.compare(now, at) == :gt do
          prune_unused_trials()
          schedule_prune(now)
        end

      _ ->
        schedule_prune(now)
    end
  rescue
    _ -> :ok
  end

  defp schedule_prune(now) do
    ensure_table()
    :ets.insert(@table, {:__prune_at__, DateTime.add(now, 3600, :second)})
  end

  defp status_from_meta(meta) do
    now = DateTime.utc_now()
    expired? = not active?(meta)
    cap = meta_cap(meta)
    left = max(cap - meta.hits_month, 0)

    %{
      id: meta.id,
      kind: meta.kind,
      email: meta.email,
      expires_at: meta.expires_at,
      expired?: expired?,
      days_left: days_left(meta.expires_at, now),
      month: meta.month,
      hits_month: meta.hits_month,
      month_cap: cap,
      hits_left: left,
      over_quota?: meta.hits_month >= cap
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
      [{^id, meta}] when is_map(meta) -> roll_month_meta(meta)
      _ -> nil
    end
  end

  defp meta_from_pay(%Payment{} = pay) do
    %{
      id: pay.id,
      kind: pay.kind,
      email: pay.email,
      expires_at: pay.expires_at,
      month: pay.month,
      hits_month: pay.hits_month,
      month_cap: pay.month_cap || @month_cap,
      notices: pay.notices || "",
      dirty: false
    }
  end

  defp cache_put(%Payment{} = pay) do
    cache_put(meta_from_pay(pay))
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
      meta.hits_month >= meta_cap(meta) and not noticed?(meta, "quota_full") ->
        Mailer.send(meta.email, "Who Was There monthly cap reached", quota_body(meta, :full))
        notice(meta, "quota_full")

      meta.hits_month >= div(meta_cap(meta) * 4, 5) and not noticed?(meta, "quota_80") ->
        Mailer.send(meta.email, "Who Was There at 80% of monthly cap", quota_body(meta, :warn))
        notice(meta, "quota_80")

      true ->
        meta
    end
  end

  defp expiry_body(meta, kind) do
    profile = PaymentProfile.get_by_payment(meta.id)

    """
    who was there

    payment  #{meta.id}
    plan     #{meta.kind}
    expires  #{DateTime.to_iso8601(meta.expires_at)}

    #{case kind do
      :trial_soon -> "Your 7-day trial ends soon. Fund the payment profile to keep collecting."
      :year_soon -> "Your paid year ends soon. Fund the payment profile to extend it."
      :expired -> "This plan has expired. Hits are dropped until the payment profile is funded."
    end}

    deposit  #{if profile, do: profile.deposit_address, else: "unavailable"}
    settle   open the private payment URL saved with the dashboard
    """
  end

  defp quota_body(meta, kind) do
    """
    who was there

    payment  #{meta.id}
    month    #{meta.month}
    hits     #{meta.hits_month} / #{meta_cap(meta)}

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

  defp cap_for_usdc(paid_usdc) when is_integer(paid_usdc) and paid_usdc >= @price_usdc do
    div(paid_usdc, @price_usdc) * @month_cap
  end

  defp cap_for_usdc(_), do: @month_cap

  defp settle_profile(_profile, %Payment{kind: "comp"} = pay, _cap), do: {:ok, pay}

  defp settle_profile(profile, pay, cap) do
    case Solana.settle_profile(cap, profile.deposit_address, @price_usdc) do
      {:ok, amount} when is_integer(amount) and amount >= @price_usdc ->
        apply_payment(profile, pay, amount)

      {:ok, _amount} ->
        {:ok, pay}

      {:error, _} = error ->
        error
    end
  end

  defp apply_payment(profile, pay, amount)
       when is_integer(amount) and amount >= @price_usdc do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    # Reload settled_usdc in case a concurrent settle already credited.
    profile = PaymentProfile.get_by_payment(pay.id) || profile
    total_usdc = profile.settled_usdc + amount

    expiry =
      if pay.kind in ["paid", "comp"],
        do: Enum.max([pay.expires_at, now], DateTime),
        else: now

    updated =
      pay
      |> Ecto.Changeset.change(%{
        kind: "paid",
        expires_at: DateTime.add(expiry, @paid_days * 86_400, :second),
        month_cap: cap_for_usdc(total_usdc),
        notices: drop_expiry_notices(pay.notices)
      })
      |> Repo.update!()

    PaymentProfile.add_settled(profile, amount)
    cache_put(updated)
    {:ok, updated}
  end

  defp meta_cap(%{month_cap: cap}) when is_integer(cap) and cap > 0, do: cap
  defp meta_cap(_), do: @month_cap

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
end
