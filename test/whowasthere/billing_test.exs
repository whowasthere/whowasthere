defmodule WhoWasThere.BillingTest do
  use WhoWasThere.DataCase

  alias WhoWasThere.Billing

  @txid "5VEJv7RQxbjLHeGSNVTBnrDWRwDx5PhHQSX8dP1d3R1b9Y8uGvK2nM4pQ6sTAwX3zA7cF9hJ1kL5nP8rT2vY4"

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
    assert Billing.allow_pageview?(pay.id)
  end

  test "paid txid can be shared by many sites and renewed" do
    assert {:ok, pay} = Billing.open_paid(@txid, "a@b.co")
    assert pay.id == @txid

    assert {:ok, same} = Billing.start_for_new(@txid, nil)
    assert same.id == pay.id

    new_txid = String.replace_suffix(@txid, "vY4", "vZ9")
    assert {:ok, renewed} = Billing.renew(pay.id, new_txid, "a@b.co")
    assert renewed.kind == "paid"
    assert renewed.hits_month == 0 or renewed.hits_month == pay.hits_month
  end

  test "PAY_BYPASS_TXID skips chain verification" do
    bypass = "bypass-token-for-tests-only"
    previous = Application.get_env(:whowasthere, :pay_bypass_txid)
    previous_verify = Application.get_env(:whowasthere, :solana_verify)

    Application.put_env(:whowasthere, :pay_bypass_txid, bypass)
    Application.put_env(:whowasthere, :solana_verify, fn _, _, _ -> {:error, :should_not_call} end)

    try do
      assert {:ok, pay} = Billing.open_paid(bypass, "ops@example.com")
      assert pay.id == bypass
      assert pay.kind == "paid"
    after
      Application.put_env(:whowasthere, :pay_bypass_txid, previous)
      Application.put_env(:whowasthere, :solana_verify, previous_verify)
    end
  end

  test "quota blocks pageviews after the monthly cap" do
    assert {:ok, pay} = Billing.open_trial(nil)

    meta = %{
      id: pay.id,
      kind: pay.kind,
      txid: nil,
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

  test "expiry mail is sent once" do
    assert {:ok, pay} = Billing.open_trial("ops@example.com")

    past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

    :ets.insert(
      :wwt_pay,
      {pay.id,
       %{
         id: pay.id,
         kind: pay.kind,
         txid: nil,
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
