defmodule WhoWasThere.BillingTest do
  use WhoWasThere.DataCase

  alias WhoWasThere.{Billing, PaymentProfile}

  setup do
    Application.put_env(:whowasthere, :mailbox, [])
    Billing.reset_cache()
    :ok
  end

  test "trial lasts seven days and accepts an email" do
    assert {:ok, pay} = Billing.open_trial("you@example.com")
    status = Billing.status(pay)
    assert status.kind == "trial"
    assert status.email == "you@example.com"
    assert status.days_left in 6..7
    assert status.month_cap == Billing.month_cap()
    assert Billing.allow_pageview?(pay.id)
  end

  test "a private capability resolves one stable payment profile" do
    assert {:ok, pay, profile, cap} = Billing.open_profile("ops@example.com")
    assert cap =~ "p_"
    assert PaymentProfile.get_by_cap(cap).id == profile.id
    assert profile.payment_id == pay.id
    assert profile.deposit_address =~ ~r/^[1-9A-HJ-NP-Za-km-z]{32,44}$/
  end

  test "quota blocks pageviews after the monthly cap" do
    assert {:ok, pay} = Billing.open_trial(nil)

    meta = %{
      id: pay.id,
      kind: pay.kind,
      email: nil,
      expires_at: pay.expires_at,
      month: pay.month,
      hits_month: Billing.month_cap(),
      notices: "",
      dirty: true
    }

    :ets.insert(:wwt_pay, {pay.id, meta})
    refute Billing.allow_pageview?(pay.id)
  end

  test "settling 90 USDC activates the profile with three quota units" do
    previous = Application.get_env(:whowasthere, :solana_profile_settle)
    Application.put_env(:whowasthere, :solana_profile_settle, fn _, _, _ -> {:ok, 90} end)

    try do
      assert {:ok, _pay, _profile, cap} = Billing.open_profile("a@b.co")
      assert {:ok, paid, settled_profile} = Billing.payment_profile(cap)
      assert paid.kind == "paid"
      assert paid.month_cap == Billing.month_cap() * 3
      assert PaymentProfile.get_by_cap(cap).settled_usdc == 90
      assert settled_profile.payment_id == paid.id
    after
      Application.put_env(:whowasthere, :solana_profile_settle, previous)
    end
  end

  test "an operator grant activates a private profile without a payment" do
    assert {:ok, pay, _profile, cap} = Billing.open_profile("owner@example.com")
    assert pay.kind == "trial"

    assert {:ok, granted} = Billing.grant(cap, years: 10, month_cap: 2_000_000)
    status = Billing.status(granted)

    assert status.kind == "comp"
    assert status.days_left in 3649..3650
    assert status.month_cap == 2_000_000
    assert Billing.allow_pageview?(granted.id)
    assert {:error, :unknown_payment} = Billing.grant("p_not_a_real_profile", years: 10)
  end

  test "expiry mail is sent once" do
    assert {:ok, pay} = Billing.open_trial("ops@example.com")

    past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

    :ets.insert(
      :wwt_pay,
      {pay.id,
       %{
         id: pay.id,
         kind: pay.kind,
         email: "ops@example.com",
         expires_at: past,
         month: pay.month,
         hits_month: 0,
         notices: "",
         dirty: true
       }}
    )

    Billing.tick_notices()
    Billing.tick_notices()

    mails = Application.get_env(:whowasthere, :mailbox)
    assert length(mails) == 1
    assert hd(mails).to == "ops@example.com"
    assert hd(mails).subject =~ "expired"
  end
end
