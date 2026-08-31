defmodule WhoWasThere.Billing.Stripe do
  @moduledoc false

  @api "https://api.stripe.com/v1"
  @api_version "2026-07-29.dahlia"

  def configured? do
    present?(secret_key()) and present?(webhook_secret())
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  def create_checkout_session(attrs) when is_map(attrs) do
    case Application.get_env(:whowasthere, :stripe_create_checkout) do
      fun when is_function(fun, 1) -> fun.(attrs)
      _ -> create_checkout_session_api(attrs)
    end
  end

  def handle_webhook(payload, signature) when is_binary(payload) do
    with :ok <- verify_signature(payload, signature),
         {:ok, event} <- Jason.decode(payload) do
      dispatch(event)
    end
  end

  def handle_webhook(_, _), do: {:error, :bad_webhook}

  defp create_checkout_session_api(attrs) do
    amount_usdc = attrs.amount_usdc
    unit_amount = amount_usdc * 100
    integration = "wwt-pay-" <> random_suffix()

    form = [
      {"mode", "payment"},
      {"success_url", attrs.success_url},
      {"cancel_url", attrs.cancel_url},
      {"client_reference_id", attrs.payment_id},
      {"metadata[payment_id]", attrs.payment_id},
      {"metadata[amount_usdc]", Integer.to_string(amount_usdc)},
      {"line_items[0][quantity]", "1"},
      {"line_items[0][price_data][currency]", "usd"},
      {"line_items[0][price_data][unit_amount]", Integer.to_string(unit_amount)},
      {"line_items[0][price_data][product_data][name]",
       "Who Was There · #{amount_usdc} USDC year"},
      {"integration_identifier", integration}
    ]

    case http_form("/checkout/sessions", form) do
      {:ok, %{"id" => id, "url" => url}} when is_binary(id) and is_binary(url) ->
        {:ok, %{id: id, url: url}}

      {:ok, other} ->
        {:error, {:stripe, other}}

      error ->
        error
    end
  end

  defp dispatch(%{"type" => type, "data" => %{"object" => session}})
       when type in ["checkout.session.completed", "checkout.session.async_payment_succeeded"] do
    WhoWasThere.Billing.complete_stripe_checkout(session)
  end

  defp dispatch(_), do: :ok

  defp verify_signature(payload, signature) when is_binary(signature) do
    secret = webhook_secret()

    if secret in [nil, ""] do
      {:error, :stripe_webhook_secret_missing}
    else
      parts =
        signature
        |> String.split(",")
        |> Map.new(fn part ->
          case String.split(part, "=", parts: 2) do
            [k, v] -> {k, v}
            _ -> {part, ""}
          end
        end)

      case {Map.fetch(parts, "t"), Map.fetch(parts, "v1")} do
        {{:ok, timestamp}, {:ok, v1}} ->
          if fresh_timestamp?(timestamp) do
            expected =
              :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")
              |> Base.encode16(case: :lower)

            if Plug.Crypto.secure_compare(expected, String.downcase(v1)) do
              :ok
            else
              {:error, :stripe_signature_invalid}
            end
          else
            {:error, :stripe_signature_stale}
          end

        _ ->
          {:error, :stripe_signature_invalid}
      end
    end
  end

  defp verify_signature(_, _), do: {:error, :stripe_signature_invalid}

  defp fresh_timestamp?(timestamp) do
    case Integer.parse(timestamp) do
      {ts, ""} -> abs(System.system_time(:second) - ts) <= 300
      _ -> false
    end
  end

  defp http_form(path, form) do
    key = secret_key()

    if key in [nil, ""] do
      {:error, :stripe_not_configured}
    else
      body = URI.encode_query(form)

      case Req.post(@api <> path,
             body: body,
             headers: [
               {"authorization", "Bearer #{key}"},
               {"content-type", "application/x-www-form-urlencoded"},
               {"stripe-version", @api_version}
             ],
             receive_timeout: 15_000
           ) do
        {:ok, %{status: status, body: resp}} when status in 200..299 ->
          decode_body(resp)

        {:ok, %{status: status, body: resp}} ->
          {:error, {:stripe_http, status, resp}}

        {:error, reason} ->
          {:error, {:stripe, reason}}
      end
    end
  end

  defp decode_body(body) when is_map(body), do: {:ok, body}

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> {:ok, map}
      error -> error
    end
  end

  defp random_suffix do
    for <<idx <- :crypto.strong_rand_bytes(8)>>, into: "" do
      <<Enum.at(~c"abcdefghijklmnopqrstuvwxyz", rem(idx, 26))>>
    end
  end

  defp secret_key, do: Application.get_env(:whowasthere, :stripe_secret_key)
  defp webhook_secret, do: Application.get_env(:whowasthere, :stripe_webhook_secret)
end
