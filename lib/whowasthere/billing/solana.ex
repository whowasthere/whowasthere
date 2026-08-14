defmodule WhoWasThere.Billing.Solana do
  @moduledoc false

  alias WhoWasThere.Base58

  @usdc_decimals 6
  @token_program "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

  def deposit_address(cap) when is_binary(cap) do
    with {:ok, public, _private} <- deposit_keypair(cap) do
      {:ok, Base58.encode(public)}
    end
  end

  def master_address do
    case master_keypair() do
      {:ok, public, _private} -> {:ok, Base58.encode(public)}
      error -> error
    end
  end

  def settle_profile(cap, expected_address, minimum_usdc) when is_binary(cap) do
    case Application.get_env(:whowasthere, :solana_profile_settle) do
      fun when is_function(fun, 3) -> fun.(cap, expected_address, minimum_usdc)
      _ -> settle_profile_rpc(cap, expected_address, minimum_usdc)
    end
  end

  defp settle_profile_rpc(cap, expected_address, minimum_usdc) do
    with {:ok, owner, owner_private} <- deposit_keypair(cap),
         :ok <- address_matches(owner, expected_address),
         {:ok, sources} <- token_accounts(expected_address) do
      funded = Enum.filter(sources, &(&1.amount > 0))

      total_funded = Enum.reduce(funded, 0, &(&1.amount + &2))

      if total_funded < minimum_usdc * 10 ** @usdc_decimals do
        {:ok, 0}
      else
        with {:ok, destination} <- treasury_token_account(),
             {:ok, master_public, master_private} <- master_keypair() do
          funded
          |> Enum.reduce_while({:ok, 0}, fn source, {:ok, total} ->
            case sweep(source, destination, owner, owner_private, master_public, master_private) do
              {:ok, _signature} -> {:cont, {:ok, total + source.amount}}
              {:error, _} = error -> {:halt, error}
            end
          end)
          |> case do
            {:ok, amount} -> {:ok, div(amount, 10 ** @usdc_decimals)}
            error -> error
          end
        end
      end
    end
  end

  defp address_matches(owner, expected_address) do
    if Base58.encode(owner) == expected_address, do: :ok, else: {:error, :bad_payment_cap}
  end

  defp token_accounts(owner) do
    mint = Application.fetch_env!(:whowasthere, :usdc_mint)

    with {:ok, %{"value" => values}} <-
           rpc("getTokenAccountsByOwner", [
             owner,
             %{"mint" => mint},
             %{"encoding" => "jsonParsed", "commitment" => "confirmed"}
           ]) do
      accounts =
        for %{"pubkey" => pubkey, "account" => account} <- values,
            amount = get_in(account, ["data", "parsed", "info", "tokenAmount", "amount"]),
            {integer, ""} <- [Integer.parse(to_string(amount))] do
          %{address: pubkey, amount: integer}
        end

      {:ok, accounts}
    end
  end

  defp treasury_token_account do
    wallet = Application.fetch_env!(:whowasthere, :pay_wallet)

    case token_accounts(wallet) do
      {:ok, [%{address: address} | _]} -> {:ok, address}
      {:ok, []} -> {:error, :treasury_token_account_missing}
      error -> error
    end
  end

  defp sweep(source, destination, owner, owner_private, master, master_private) do
    mint = Application.fetch_env!(:whowasthere, :usdc_mint)

    with {:ok, source_key} <- decode_key(source.address),
         {:ok, mint_key} <- decode_key(mint),
         {:ok, destination_key} <- decode_key(destination),
         {:ok, program_key} <- decode_key(@token_program),
         {:ok, blockhash} <- rpc("getLatestBlockhash", [%{"commitment" => "confirmed"}]),
         {:ok, blockhash_key} <- decode_key(get_in(blockhash, ["value", "blockhash"])) do
      keys = [master, owner, source_key, destination_key, mint_key, program_key]
      data = <<12, source.amount::little-unsigned-64, @usdc_decimals>>
      instruction = <<5>> <> shortvec(4) <> <<2, 4, 3, 1>> <> shortvec(byte_size(data)) <> data

      message =
        <<2, 1, 2>> <>
          shortvec(length(keys)) <>
          IO.iodata_to_binary(keys) <>
          blockhash_key <>
          shortvec(1) <>
          instruction

      master_signature = :crypto.sign(:eddsa, :none, message, [master_private, :ed25519])
      owner_signature = :crypto.sign(:eddsa, :none, message, [owner_private, :ed25519])
      transaction = shortvec(2) <> master_signature <> owner_signature <> message

      case rpc("sendTransaction", [
             Base.encode64(transaction),
             %{"encoding" => "base64", "preflightCommitment" => "confirmed"}
           ]) do
        {:ok, signature} when is_binary(signature) ->
          with :ok <- confirm_signature(signature, 40), do: {:ok, signature}

        error ->
          error
      end
    end
  end

  defp confirm_signature(_signature, 0), do: {:error, :sweep_confirmation_timeout}

  defp confirm_signature(signature, attempts_left) do
    case rpc("getSignatureStatuses", [
           [signature],
           %{"searchTransactionHistory" => true}
         ]) do
      {:ok, %{"value" => [%{"err" => nil, "confirmationStatus" => status}]}}
      when status in ["confirmed", "finalized"] ->
        :ok

      {:ok, %{"value" => [%{"err" => error} | _]}} when not is_nil(error) ->
        {:error, :tx_failed}

      {:ok, %{"value" => [_pending]}} ->
        Process.sleep(250)
        confirm_signature(signature, attempts_left - 1)

      error ->
        error
    end
  end

  defp deposit_keypair(cap) do
    with {:ok, _master_public, master_private} <- master_keypair() do
      seed =
        :crypto.mac(:hmac, :sha512, master_private, "whowasthere/pay/deposit/v1:" <> cap)
        |> binary_part(0, 32)

      {public, private} = :crypto.generate_key(:eddsa, :ed25519, seed)
      {:ok, public, private}
    end
  end

  defp master_keypair do
    with key when is_binary(key) <- Application.get_env(:whowasthere, :pay_master_key),
         {:ok, seed} <- decode_master_key(key),
         true <- byte_size(seed) == 32 || {:error, :bad_pay_master_key} do
      {public, private} = :crypto.generate_key(:eddsa, :ed25519, seed)
      {:ok, public, private}
    else
      nil -> {:error, :pay_master_key_missing}
      false -> {:error, :bad_pay_master_key}
      other -> other
    end
  end

  defp decode_master_key(key) do
    case Base.decode64(key) do
      {:ok, seed} when byte_size(seed) == 32 -> {:ok, seed}
      _ -> Base58.decode(key)
    end
  end

  defp decode_key(value) when is_binary(value) do
    with {:ok, key} <- Base58.decode(value),
         true <- byte_size(key) == 32 do
      {:ok, key}
    else
      _ -> {:error, :bad_solana_key}
    end
  end

  defp shortvec(value) when value in 0..127, do: <<value>>

  defp rpc(method, params) do
    case Application.get_env(:whowasthere, :solana_rpc_request) do
      fun when is_function(fun, 2) ->
        fun.(method, params)

      _ ->
        rpc =
          Application.get_env(:whowasthere, :solana_rpc) || "https://api.mainnet-beta.solana.com"

        body = %{jsonrpc: "2.0", id: 1, method: method, params: params}

        case Req.post(rpc, json: body, receive_timeout: 15_000) do
          {:ok, %{status: 200, body: %{"result" => result}}} -> {:ok, result}
          {:ok, %{status: 200, body: %{"error" => error}}} -> {:error, {:rpc, error}}
          {:ok, %{status: status}} -> {:error, {:rpc_http, status}}
          {:error, reason} -> {:error, {:rpc, reason}}
        end
    end
  end
end
