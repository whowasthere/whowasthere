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
    assert status.month_cap == Billing.month_cap()
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
    assert renewed.id == pay.id
    assert renewed.txid == new_txid
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

      assert {:ok, again} = Billing.open_paid(bypass, "ops@example.com")
      assert again.id == pay.id

      assert {:ok, trial} = Billing.open_trial("ops@example.com")
      assert {:ok, renewed} = Billing.renew(trial.id, bypass, "ops@example.com")
      assert renewed.id == trial.id
      assert renewed.kind == "paid"
      assert Billing.status(trial.id).kind == "paid"
      assert Billing.status(pay.id).month_cap == Billing.month_cap()

      assert {:ok, bumped} = Billing.open_paid(bypass <> ":90", "ops@example.com")
      assert bumped.id == pay.id
      assert Billing.status(bumped).month_cap == Billing.month_cap() * 3

      assert {:ok, same} = Billing.open_paid(bypass, "ops@example.com")
      assert Billing.status(same).month_cap == Billing.month_cap() * 3

      assert {:error, :bad_txid} = Billing.open_paid(bypass <> ":12", nil)
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

  test "USDC above 30 raises the monthly pageview cap in 500k steps" do
    previous = Application.get_env(:whowasthere, :solana_verify)

    try do
      Application.put_env(:whowasthere, :solana_verify, fn _, _, _ -> {:ok, 90} end)
      assert {:ok, pay90} = Billing.open_paid(@txid, "a@b.co")
      assert Billing.status(pay90).month_cap == Billing.month_cap() * 3

      Application.put_env(:whowasthere, :solana_verify, fn _, _, _ -> {:ok, 45} end)
      tx45 = String.replace_suffix(@txid, "vY4", "vY5")
      assert {:ok, pay45} = Billing.open_paid(tx45, "a@b.co")
      assert Billing.status(pay45).month_cap == Billing.month_cap()

      Application.put_env(:whowasthere, :solana_verify, fn _, _, _ -> {:ok, 60} end)
      tx60 = String.replace_suffix(@txid, "vY4", "vY6")
      assert {:ok, pay60} = Billing.open_paid(tx60, "a@b.co")
      assert Billing.status(pay60).month_cap == Billing.month_cap() * 2

      cap = Billing.status(pay60).month_cap

      :ets.insert(
        :wwt_pay,
        {pay60.id,
         %{
           id: pay60.id,
           kind: pay60.kind,
           txid: pay60.txid,
           email: pay60.email,
           expires_at: pay60.expires_at,
           month: pay60.month,
           hits_month: cap - 1,
           month_cap: cap,
           notices: "",
           dirty: true
         }}
      )

      assert Billing.allow_pageview?(pay60.id)
      Billing.record_pageview(pay60.id)
      refute Billing.allow_pageview?(pay60.id)
    after
      Application.put_env(:whowasthere, :solana_verify, previous)
    end
  end

  test "renew with a larger payment raises the cap" do
    previous = Application.get_env(:whowasthere, :solana_verify)

    try do
      Application.put_env(:whowasthere, :solana_verify, fn _, _, _ -> {:ok, 30} end)
      assert {:ok, pay} = Billing.open_paid(@txid, "a@b.co")
      assert Billing.status(pay).month_cap == Billing.month_cap()

      Application.put_env(:whowasthere, :solana_verify, fn _, _, _ -> {:ok, 60} end)
      new_txid = String.replace_suffix(@txid, "vY4", "vZ8")
      assert {:ok, renewed} = Billing.renew(pay.id, new_txid, "a@b.co")
      assert Billing.status(renewed).month_cap == Billing.month_cap() * 2
    after
      Application.put_env(:whowasthere, :solana_verify, previous)
    end
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
