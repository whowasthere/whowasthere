defmodule WhoWasThere.Billing.StripeTest do
  use WhoWasThere.DataCase

  alias WhoWasThere.{Billing, PaymentProfile}
  alias WhoWasThere.Billing.Stripe, as: StripePay

  setup do
    previous_create = Application.get_env(:whowasthere, :stripe_create_checkout)
    previous_key = Application.get_env(:whowasthere, :stripe_secret_key)
    previous_wh = Application.get_env(:whowasthere, :stripe_webhook_secret)

    Application.put_env(:whowasthere, :stripe_secret_key, "sk_test_x")
    Application.put_env(:whowasthere, :stripe_webhook_secret, "whsec_test_secret")

    on_exit(fn ->
      put_or_delete(:stripe_create_checkout, previous_create)
      put_or_delete(:stripe_secret_key, previous_key)
      put_or_delete(:stripe_webhook_secret, previous_wh)
    end)

    :ok
  end

  test "start_checkout returns a hosted session url" do
    Application.put_env(:whowasthere, :stripe_create_checkout, fn attrs ->
      assert attrs.amount_usdc == 60
      assert attrs.payment_id
      {:ok, %{id: "cs_test_1", url: "https://checkout.stripe.com/c/pay/cs_test_1"}}
    end)

    assert {:ok, _pay, _profile, cap} = Billing.open_profile(nil)

    assert {:ok, %{url: url}} =
             Billing.start_checkout(cap, 60, %{
               success_url: "https://example.com/ok",
               cancel_url: "https://example.com/cancel"
             })

    assert url =~ "checkout.stripe.com"
  end

  test "webhook activates a profile once per session" do
    assert {:ok, pay, _profile, _cap} = Billing.open_profile(nil)
    secret = "whsec_test_secret"
    Application.put_env(:whowasthere, :stripe_webhook_secret, secret)

    payload =
      Jason.encode!(%{
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => %{
            "id" => "cs_test_paid_1",
            "payment_status" => "paid",
            "client_reference_id" => pay.id,
            "metadata" => %{"payment_id" => pay.id, "amount_usdc" => "90"}
          }
        }
      })

    signature = sign(payload, secret)
    assert :ok = StripePay.handle_webhook(payload, signature)

    paid = Billing.get(pay.id)
    assert paid.kind == "paid"
    assert paid.month_cap == Billing.month_cap() * 3
    assert PaymentProfile.get_by_payment(pay.id).settled_usdc == 90

    assert :ok = StripePay.handle_webhook(payload, signature)
    assert PaymentProfile.get_by_payment(pay.id).settled_usdc == 90
  end

  test "invalid webhook signatures are rejected" do
    timestamp = System.system_time(:second) |> Integer.to_string()

    assert {:error, :stripe_signature_invalid} =
             StripePay.handle_webhook("{}", "t=#{timestamp},v1=deadbeef")
  end

  defp sign(payload, secret) do
    timestamp = System.system_time(:second) |> Integer.to_string()

    v1 =
      :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{v1}"
  end

  defp put_or_delete(key, nil), do: Application.delete_env(:whowasthere, key)
  defp put_or_delete(key, value), do: Application.put_env(:whowasthere, key, value)
end
