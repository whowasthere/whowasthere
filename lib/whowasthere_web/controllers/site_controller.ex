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
        |> respond(params, %{
          error:
            "ID must be 8–32 characters and contain only lowercase letters, digits, underscores, or hyphens."
        })

      wanted != "" and (Collector.site?(wanted) || Store.get_site(wanted)) ->
        conn
        |> put_status(409)
        |> respond(params, %{error: "That ID is already taken. Choose another."})

      true ->
        case Billing.start_for_profile(pay_cap, email) do
          {:ok, pay, profile, cap} ->
            id = if wanted != "", do: wanted, else: unique_id()
            issued = Stamp.issue(id, host, pay.id)
            base = base_url(conn)
            bill = Billing.status(pay)
            info = Billing.info()
            solana_pay = solana_pay_uri(profile.deposit_address, info)

            respond(conn, params, %{
              site: id,
              key: issued.key,
              pay: cap || pay_cap,
              pay_url: "#{base}/pay?pay=#{cap || pay_cap}",
              deposit: profile.deposit_address,
              amount_usdc: info.amount_usdc,
              mint: info.mint,
              network: info.network,
              solana_pay: solana_pay,
              stripe: info.stripe,
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
    if browser_request?(conn, params) do
      destination = "/?pay=#{URI.encode_www_form(params["pay"] || "")}#start-pay-step"
      redirect(conn, to: destination)
    else
      payment_status(conn, params)
    end
  end

  defp payment_status(conn, params) do
    base = base_url(conn)

    case Billing.payment_profile(params["pay"]) do
      {:ok, payment, profile} ->
        info = Billing.info()

        respond(conn, params, %{
          pay: params["pay"],
          pay_url: "#{base}/pay?pay=#{params["pay"]}",
          deposit: profile.deposit_address,
          amount_usdc: info.amount_usdc,
          mint: info.mint,
          network: info.network,
          solana_pay: solana_pay_uri(profile.deposit_address, info),
          stripe: info.stripe,
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

  def checkout(conn, params) do
    pay = params["pay"]
    amount = parse_amount(params["amount"])
    base = base_url(conn)

    urls = %{
      success_url: "#{base}/pay?pay=#{URI.encode_www_form(pay || "")}&checkout=1",
      cancel_url: "#{base}/#start-pay-step"
    }

    case Billing.start_checkout(pay, amount, urls) do
      {:ok, %{url: url}} ->
        json(conn, %{url: url})

      {:error, reason} ->
        conn
        |> put_status(status_for(reason))
        |> json(%{error: error_text(reason)})
    end
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
  defp status_for(:stripe_not_configured), do: 503
  defp status_for(:bad_amount), do: 400
  defp status_for({:rpc, _}), do: 502
  defp status_for({:rpc_http, _}), do: 502
  defp status_for({:stripe_http, _, _}), do: 502
  defp status_for({:stripe, _}), do: 502
  defp status_for(:bad_email), do: 400
  defp status_for(:email_required), do: 400
  defp status_for(_), do: 400

  defp error_text(:unknown_payment), do: "Payment profile not found."
  defp error_text(:tx_failed), do: "The Solana transaction failed."
  defp error_text(:pay_master_key_missing), do: "The payment master key is not configured."
  defp error_text(:bad_pay_master_key), do: "The payment master key is invalid."

  defp error_text(:treasury_token_account_missing),
    do: "The treasury USDC token account is missing."

  defp error_text(:sweep_confirmation_timeout),
    do: "The Solana transfer was not confirmed in time."

  defp error_text(:stripe_not_configured), do: "Card payments are not configured."
  defp error_text(:bad_amount), do: "The amount must be a multiple of $30."
  defp error_text(:bad_email), do: "Enter a valid email address."
  defp error_text(:email_required), do: "An email address is required."
  defp error_text(other), do: "Payment error: #{inspect(other)}"

  defp parse_amount(nil), do: Billing.price_usdc()

  defp parse_amount(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n
      _ -> Billing.price_usdc()
    end
  end

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

  defp browser_request?(conn, params) do
    params["format"] != "json" and
      Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "text/html"))
  end

  defp plaintext(%{error: error}), do: "error: #{error}\n"

  defp plaintext(%{site: _} = p) do
    """
    whowasthere

    site     #{p.site}
    pay      #{p.pay}   (#{p.plan}, expires #{p.expires})
    pay URL  #{p.pay_url}   ← secret; keep it with the dashboard URL
    deposit  #{p.deposit}   (USDC on Solana)
    wallet   #{p.solana_pay}
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
    #{if Map.has_key?(p, :deposit), do: "send     #{p.amount_usdc} USDC to #{p.deposit}\n", else: ""}#{if Map.has_key?(p, :solana_pay), do: "wallet   #{p.solana_pay}\n", else: ""}#{if Map.has_key?(p, :plan), do: "plan     #{p.plan}\n", else: ""}#{if Map.has_key?(p, :expires), do: "expires  #{p.expires}\n", else: ""}email    #{Map.get(p, :email) || "-"}
    """
  end

  defp solana_pay_uri(deposit, info) do
    query = URI.encode_query(%{"amount" => info.amount_usdc, "spl-token" => info.mint})
    "solana:#{deposit}?#{query}"
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
