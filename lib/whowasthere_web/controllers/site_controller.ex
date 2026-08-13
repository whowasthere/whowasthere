defmodule WhoWasThereWeb.SiteController do
  use WhoWasThereWeb, :controller

  alias WhoWasThere.{Billing, Collector, ID, Stamp, Store}

  def create(conn, params) do
    wanted = params |> Map.get("id", "") |> String.trim()
    email = params["email"]
    txid = params["txid"]

    host =
      params
      |> Map.get("host", "")
      |> String.trim()
      |> Stamp.normalize_host()

    cond do
      wanted != "" and not ID.valid?(wanted) ->
        conn
        |> put_status(400)
        |> respond(params, %{error: "id must be 8–32 characters: letters, digits, _ or -"})

      wanted != "" and (Collector.site?(wanted) || Store.get_site(wanted)) ->
        conn
        |> put_status(409)
        |> respond(params, %{error: "id is taken, pick another"})

      true ->
        case Billing.start_for_new(txid, email) do
          {:ok, pay} ->
            id = if wanted != "", do: wanted, else: unique_id()
            issued = Stamp.issue(id, host, pay.id)
            base = base_url(conn)
            bill = Billing.status(pay)

            respond(conn, params, %{
              site: id,
              key: issued.key,
              pay: pay.id,
              plan: bill.kind,
              expires: DateTime.to_iso8601(bill.expires_at),
              email: bill.email,
              dash: "#{base}/d/#{issued.token}",
              snippet: ~s(<script src="#{base}/w.js" data-w="#{issued.key}" defer></script>),
              pixel: ~s(<img src="#{base}/w.js?s=#{issued.key}" alt="" width="1" height="1">),
              event: "window.wwt('signup')"
            })

          {:error, reason} ->
            conn
            |> put_status(status_for(reason))
            |> respond(params, %{error: error_text(reason)})
        end
    end
  end

  def pay(conn, params) do
    info = Billing.info()
    base = base_url(conn)

    respond(conn, params, %{
      wallet: info.wallet,
      mint: info.mint,
      amount_usdc: info.amount_usdc,
      network: info.network,
      month_cap: info.month_cap,
      trial_days: info.trial_days,
      paid_days: info.paid_days,
      new: "#{base}/new?txid=TXID&email=you@example.com",
      renew: "#{base}/renew?from=PAY_OR_TXID&to=NEW_TXID&email=you@example.com",
      notify: "#{base}/notify?pay=PAY_OR_TXID&email=you@example.com"
    })
  end

  def renew(conn, params) do
    from = params["from"] || params["pay"]
    to = params["to"] || params["txid"]
    email = params["email"]

    case Billing.renew(from, to, email) do
      {:ok, pay} ->
        bill = Billing.status(pay)

        respond(conn, params, %{
          pay: pay.id,
          plan: bill.kind,
          expires: DateTime.to_iso8601(bill.expires_at),
          email: bill.email,
          hits_month: bill.hits_month,
          month_cap: bill.month_cap
        })

      {:error, reason} ->
        conn
        |> put_status(status_for(reason))
        |> respond(params, %{error: error_text(reason)})
    end
  end

  def notify(conn, params) do
    pay = params["pay"] || params["from"] || params["txid"]
    email = params["email"]

    case Billing.set_email(pay, email) do
      {:ok, payment} ->
        respond(conn, params, %{pay: payment.id, email: payment.email})

      {:error, reason} ->
        conn
        |> put_status(status_for(reason))
        |> respond(params, %{error: error_text(reason)})
    end
  end

  def health(conn, _params) do
    json(conn, %{ok: true})
  end

  defp unique_id do
    id = ID.generate()
    if Collector.site?(id) || Store.get_site(id), do: unique_id(), else: id
  end

  defp status_for(:txid_used), do: 409
  defp status_for(:unknown_payment), do: 404
  defp status_for(:tx_not_found), do: 402
  defp status_for(:amount_too_low), do: 402
  defp status_for(:tx_failed), do: 402
  defp status_for(:bad_txid), do: 400
  defp status_for(:bad_email), do: 400
  defp status_for(:txid_required), do: 400
  defp status_for(:email_required), do: 400
  defp status_for(_), do: 400

  defp error_text(:txid_used), do: "txid already used"
  defp error_text(:unknown_payment), do: "unknown payment"
  defp error_text(:tx_not_found), do: "solana transaction not found"
  defp error_text(:amount_too_low), do: "USDC amount too low"
  defp error_text(:tx_failed), do: "solana transaction failed"
  defp error_text(:bad_txid), do: "txid looks invalid"
  defp error_text(:bad_email), do: "email looks invalid"
  defp error_text(:txid_required), do: "txid required"
  defp error_text(:email_required), do: "email required"
  defp error_text(other), do: "payment error: #{inspect(other)}"

  defp respond(conn, params, payload) do
    if json?(conn, params) do
      json(conn, payload)
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(conn.status || 200, plaintext(payload))
    end
  end

  defp json?(conn, params) do
    params["format"] == "json" or
      conn
      |> get_req_header("accept")
      |> List.first()
      |> Kernel.||("")
      |> String.contains?("application/json")
  end

  defp plaintext(%{error: error}), do: "error: #{error}\n"

  defp plaintext(%{wallet: _} = p) do
    """
    whowasthere pay

    wallet   #{p.wallet}
    mint     #{p.mint}
    amount   #{p.amount_usdc} USDC / year
    network  #{p.network}
    cap      #{p.month_cap} pageviews / month across all sites
    trial    #{p.trial_days} days free

    new      curl -s '#{p.new}'
    renew    curl -s '#{p.renew}'
    notify   curl -s '#{p.notify}'
    """
  end

  defp plaintext(%{site: _} = p) do
    """
    whowasthere

    site     #{p.site}
    pay      #{p.pay}   (#{p.plan}, until #{p.expires})
    email    #{p.email || "-"}
    dash     #{p.dash}
    snippet  #{p.snippet}
    pixel    #{p.pixel}
    event    #{p.event}
    """
  end

  defp plaintext(%{pay: pay} = p) do
    """
    whowasthere

    pay      #{pay}
    #{if Map.has_key?(p, :plan), do: "plan     #{p.plan}\n", else: ""}#{if Map.has_key?(p, :expires), do: "expires  #{p.expires}\n", else: ""}email    #{p.email || "-"}
    """
  end

  defp base_url(conn) do
    port =
      cond do
        conn.scheme == :http and conn.port == 80 -> ""
        conn.scheme == :https and conn.port == 443 -> ""
        true -> ":#{conn.port}"
      end

    "#{conn.scheme}://#{conn.host}#{port}"
  end
end
