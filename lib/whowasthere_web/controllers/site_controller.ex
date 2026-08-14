defmodule WhoWasThereWeb.SiteController do
  use WhoWasThereWeb, :controller

  alias WhoWasThere.{Billing, Collector, ID, Stamp, Store}

  def create(conn, params) do
    wanted = params |> Map.get("id", "") |> String.trim()
    email = params["email"]
    pay_cap = params["pay"]

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
        case Billing.start_for_profile(pay_cap, email) do
          {:ok, pay, profile, cap} ->
            id = if wanted != "", do: wanted, else: unique_id()
            issued = Stamp.issue(id, host, pay.id)
            base = base_url(conn)
            bill = Billing.status(pay)

            respond(conn, params, %{
              site: id,
              key: issued.key,
              pay: cap || pay_cap,
              pay_url: "#{base}/pay?pay=#{cap || pay_cap}",
              deposit: profile.deposit_address,
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
    base = base_url(conn)

    case Billing.payment_profile(params["pay"]) do
      {:ok, payment, profile} ->
        info = Billing.info()

        respond(conn, params, %{
          pay: params["pay"],
          deposit: profile.deposit_address,
          amount_usdc: info.amount_usdc,
          network: info.network,
          month_cap: payment.month_cap,
          plan: payment.kind,
          expires: DateTime.to_iso8601(payment.expires_at),
          email: payment.email,
          new: "#{base}/new?pay=#{params["pay"]}",
          notify: "#{base}/notify?pay=#{params["pay"]}&email=you@example.com"
        })

      {:error, reason} ->
        conn |> put_status(status_for(reason)) |> respond(params, %{error: error_text(reason)})
    end
  end

  def renew(conn, params) do
    pay(conn, params)
  end

  def notify(conn, params) do
    pay = params["pay"]
    email = params["email"]

    case Billing.set_profile_email(pay, email) do
      {:ok, payment} ->
        respond(conn, params, %{pay: pay, email: payment.email})

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

  defp status_for(:unknown_payment), do: 404
  defp status_for(:tx_failed), do: 402
  defp status_for(:pay_master_key_missing), do: 503
  defp status_for(:bad_pay_master_key), do: 503
  defp status_for(:treasury_token_account_missing), do: 503
  defp status_for(:sweep_confirmation_timeout), do: 504
  defp status_for({:rpc, _}), do: 502
  defp status_for({:rpc_http, _}), do: 502
  defp status_for(:bad_email), do: 400
  defp status_for(:email_required), do: 400
  defp status_for(_), do: 400

  defp error_text(:unknown_payment), do: "unknown payment"
  defp error_text(:tx_failed), do: "solana transaction failed"
  defp error_text(:pay_master_key_missing), do: "payment master key is not configured"
  defp error_text(:bad_pay_master_key), do: "payment master key is invalid"
  defp error_text(:treasury_token_account_missing), do: "treasury USDC token account is missing"
  defp error_text(:sweep_confirmation_timeout), do: "solana sweep was not confirmed in time"
  defp error_text(:bad_email), do: "email looks invalid"
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

  defp plaintext(%{site: _} = p) do
    """
    whowasthere

    site     #{p.site}
    pay      #{p.pay}   (#{p.plan}, until #{p.expires})
    pay URL  #{p.pay_url}   ← secret; keep it with the dashboard URL
    deposit  #{p.deposit}   (USDC on Solana)
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
    #{if Map.has_key?(p, :deposit), do: "send     #{p.amount_usdc} USDC to #{p.deposit}\n", else: ""}#{if Map.has_key?(p, :plan), do: "plan     #{p.plan}\n", else: ""}#{if Map.has_key?(p, :expires), do: "expires  #{p.expires}\n", else: ""}email    #{Map.get(p, :email) || "-"}
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
