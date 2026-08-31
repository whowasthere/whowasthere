defmodule WhoWasThere.Billing.SolanaTest do
  use ExUnit.Case, async: false

  alias WhoWasThere.Base58
  alias WhoWasThere.Billing.Solana

  setup do
    previous_settle = Application.get_env(:whowasthere, :solana_profile_settle)
    previous_rpc = Application.get_env(:whowasthere, :solana_rpc_request)
    previous_master_key = Application.get_env(:whowasthere, :pay_master_key)
    previous_attempts = Application.get_env(:whowasthere, :solana_confirm_attempts)

    on_exit(fn ->
      Application.put_env(:whowasthere, :solana_profile_settle, previous_settle)
      Application.put_env(:whowasthere, :solana_rpc_request, previous_rpc)
      Application.put_env(:whowasthere, :pay_master_key, previous_master_key)

      if previous_attempts do
        Application.put_env(:whowasthere, :solana_confirm_attempts, previous_attempts)
      else
        Application.delete_env(:whowasthere, :solana_confirm_attempts)
      end
    end)

    :ok
  end

  test "base58 normalization preserves derived deposit addresses" do
    seed = :crypto.strong_rand_bytes(32)
    cap = "p_sameprivatecapability"

    Application.put_env(:whowasthere, :pay_master_key, Base.encode64(seed))
    assert {:ok, address_before} = Solana.deposit_address(cap)

    Application.put_env(:whowasthere, :pay_master_key, Base58.encode(seed))
    assert {:ok, ^address_before} = Solana.deposit_address(cap)
  end

  test "finds the derived owner's ATA and signs a sweep transaction" do
    cap = "p_23456789abcdefghijkmnp"
    {:ok, owner} = Solana.deposit_address(cap)
    calls = start_supervised!({Agent, fn -> [] end})
    blockhash = Base58.encode(:binary.copy(<<7>>, 32))
    source = Base58.encode(:binary.copy(<<8>>, 32))
    destination = Base58.encode(:binary.copy(<<9>>, 32))
    mint = Application.fetch_env!(:whowasthere, :usdc_mint)
    token_program = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

    Application.delete_env(:whowasthere, :solana_profile_settle)

    Application.put_env(:whowasthere, :solana_rpc_request, fn method, params ->
      Agent.update(calls, &[method | &1])

      case {method, params} do
        {"getTokenAccountsByOwner", [^owner, _, _]} ->
          {:ok, %{"value" => [token_account(source, 30_000_000)]}}

        {"getTokenAccountsByOwner", [_treasury, _, _]} ->
          {:ok, %{"value" => [token_account(destination, 0)]}}

        {"getLatestBlockhash", _} ->
          {:ok, %{"value" => %{"blockhash" => blockhash}}}

        {"sendTransaction", [encoded, _options]} ->
          assert {:ok, transaction} = Base.decode64(encoded)

          assert <<2, master_signature::binary-size(64), owner_signature::binary-size(64),
                   message::binary>> = transaction

          assert <<2, 1, 2, 6, master::binary-size(32), derived_owner::binary-size(32),
                   source_key::binary-size(32), destination_key::binary-size(32),
                   mint_key::binary-size(32), program_key::binary-size(32),
                   recent_blockhash::binary-size(32), 1, 5, 4, 2, 4, 3, 1, 10, 12,
                   30_000_000::little-unsigned-64, 6>> = message

          assert Base58.encode(source_key) == source
          assert Base58.encode(destination_key) == destination
          assert Base58.encode(mint_key) == mint
          assert Base58.encode(program_key) == token_program
          assert Base58.encode(recent_blockhash) == blockhash

          assert :crypto.verify(:eddsa, :none, message, master_signature, [master, :ed25519])

          assert :crypto.verify(:eddsa, :none, message, owner_signature, [derived_owner, :ed25519])

          {:ok, "sweep-signature"}

        {"getSignatureStatuses", [["sweep-signature"], _options]} ->
          {:ok, %{"value" => [%{"err" => nil, "confirmationStatus" => "confirmed"}]}}
      end
    end)

    assert {:ok, 30} = Solana.settle_profile(cap, owner, 30)
    assert "sendTransaction" in Agent.get(calls, & &1)
  end

  test "an unfunded profile does not look up or require a treasury token account" do
    cap = "p_3456789abcdefghijkmnpq"
    {:ok, owner} = Solana.deposit_address(cap)
    Application.delete_env(:whowasthere, :solana_profile_settle)

    Application.put_env(:whowasthere, :solana_rpc_request, fn
      "getTokenAccountsByOwner", [^owner, _, _] -> {:ok, %{"value" => []}}
      method, _params -> flunk("unexpected RPC call: #{method}")
    end)

    assert {:ok, 0} = Solana.settle_profile(cap, owner, 30)
  end

  test "credits the successful sweep when a later ATA sweep fails" do
    cap = "p_456789abcdefghijkmnpqr"
    {:ok, owner} = Solana.deposit_address(cap)
    blockhash = Base58.encode(:binary.copy(<<7>>, 32))
    source_ok = Base58.encode(:binary.copy(<<8>>, 32))
    source_fail = Base58.encode(:binary.copy(<<10>>, 32))
    destination = Base58.encode(:binary.copy(<<9>>, 32))
    sends = start_supervised!({Agent, fn -> 0 end})

    Application.delete_env(:whowasthere, :solana_profile_settle)

    Application.put_env(:whowasthere, :solana_rpc_request, fn
      "getTokenAccountsByOwner", [^owner, _, _] ->
        {:ok,
         %{
           "value" => [
             token_account(source_ok, 30_000_000),
             token_account(source_fail, 30_000_000)
           ]
         }}

      "getTokenAccountsByOwner", [_treasury, _, _] ->
        {:ok, %{"value" => [token_account(destination, 0)]}}

      "getLatestBlockhash", _ ->
        {:ok, %{"value" => %{"blockhash" => blockhash}}}

      "sendTransaction", _ ->
        n = Agent.get_and_update(sends, &{&1 + 1, &1 + 1})

        if n == 1 do
          {:ok, "sweep-ok"}
        else
          {:error, {:rpc, "second sweep failed"}}
        end

      "getSignatureStatuses", [["sweep-ok"], _] ->
        {:ok, %{"value" => [%{"err" => nil, "confirmationStatus" => "confirmed"}]}}
    end)

    assert {:ok, 30} = Solana.settle_profile(cap, owner, 30)
    assert Agent.get(sends, & &1) == 2
  end

  test "treats a confirmation timeout as swept when the source ATA is empty" do
    cap = "p_56789abcdefghijkmnpqrs"
    {:ok, owner} = Solana.deposit_address(cap)
    blockhash = Base58.encode(:binary.copy(<<7>>, 32))
    source = Base58.encode(:binary.copy(<<8>>, 32))
    destination = Base58.encode(:binary.copy(<<9>>, 32))

    Application.delete_env(:whowasthere, :solana_profile_settle)
    Application.put_env(:whowasthere, :solana_confirm_attempts, 1)

    Application.put_env(:whowasthere, :solana_rpc_request, fn
      "getTokenAccountsByOwner", [^owner, _, _] ->
        {:ok, %{"value" => [token_account(source, 60_000_000)]}}

      "getTokenAccountsByOwner", [_treasury, _, _] ->
        {:ok, %{"value" => [token_account(destination, 0)]}}

      "getLatestBlockhash", _ ->
        {:ok, %{"value" => %{"blockhash" => blockhash}}}

      "sendTransaction", _ ->
        {:ok, "sweep-pending"}

      "getSignatureStatuses", [["sweep-pending"], _] ->
        {:ok, %{"value" => [nil]}}

      "getTokenAccountBalance", [^source, _] ->
        {:ok, %{"value" => %{"amount" => "0"}}}
    end)

    assert {:ok, 60} = Solana.settle_profile(cap, owner, 30)
  end

  test "keeps the timeout error when confirmation fails and the source still holds funds" do
    cap = "p_6789abcdefghijkmnpqrst"
    {:ok, owner} = Solana.deposit_address(cap)
    blockhash = Base58.encode(:binary.copy(<<7>>, 32))
    source = Base58.encode(:binary.copy(<<8>>, 32))
    destination = Base58.encode(:binary.copy(<<9>>, 32))

    Application.delete_env(:whowasthere, :solana_profile_settle)
    Application.put_env(:whowasthere, :solana_confirm_attempts, 1)

    Application.put_env(:whowasthere, :solana_rpc_request, fn
      "getTokenAccountsByOwner", [^owner, _, _] ->
        {:ok, %{"value" => [token_account(source, 30_000_000)]}}

      "getTokenAccountsByOwner", [_treasury, _, _] ->
        {:ok, %{"value" => [token_account(destination, 0)]}}

      "getLatestBlockhash", _ ->
        {:ok, %{"value" => %{"blockhash" => blockhash}}}

      "sendTransaction", _ ->
        {:ok, "sweep-stuck"}

      "getSignatureStatuses", [["sweep-stuck"], _] ->
        {:ok, %{"value" => [nil]}}

      "getTokenAccountBalance", [^source, _] ->
        {:ok, %{"value" => %{"amount" => "30000000"}}}
    end)

    assert {:error, :sweep_confirmation_timeout} = Solana.settle_profile(cap, owner, 30)
  end

  defp token_account(address, amount) do
    %{
      "pubkey" => address,
      "account" => %{
        "data" => %{
          "parsed" => %{
            "info" => %{"tokenAmount" => %{"amount" => Integer.to_string(amount)}}
          }
        }
      }
    }
  end
end
