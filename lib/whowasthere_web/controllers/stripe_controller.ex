defmodule WhoWasThereWeb.StripeController do
  use WhoWasThereWeb, :controller

  require Logger

  alias WhoWasThere.Billing.Stripe, as: StripePay

  def webhook(conn, _params) do
    payload = raw_body(conn)
    signature = conn |> get_req_header("stripe-signature") |> List.first()

    case StripePay.handle_webhook(payload, signature) do
      :ok ->
        send_resp(conn, 200, "")

      {:error, :stripe_signature_invalid} ->
        send_resp(conn, 400, "invalid signature")

      {:error, :stripe_signature_stale} ->
        send_resp(conn, 400, "stale signature")

      {:error, :stripe_webhook_secret_missing} ->
        send_resp(conn, 503, "webhook not configured")

      {:error, reason} ->
        Logger.warning("stripe webhook rejected reason=#{inspect(reason)}")
        send_resp(conn, 200, "")
    end
  end

  defp raw_body(conn) do
    case conn.assigns[:raw_body] do
      [body | _] when is_binary(body) -> body
      bodies when is_list(bodies) -> IO.iodata_to_binary(bodies)
      body when is_binary(body) -> body
      _ -> ""
    end
  end
end
