defmodule WhoWasThere.Billing.Solana do
  @moduledoc false

  @usdc_decimals 6

  def verify_usdc_payment(txid, wallet, min_usdc) do
    case Application.get_env(:whowasthere, :solana_verify, :rpc) do
      :accept_all -> :ok
      fun when is_function(fun, 3) -> fun.(txid, wallet, min_usdc)
      :rpc -> verify_rpc(txid, wallet, min_usdc)
    end
  end

  defp verify_rpc(txid, wallet, min_usdc) do
    rpc = Application.get_env(:whowasthere, :solana_rpc) || "https://api.mainnet-beta.solana.com"
    mint = Application.get_env(:whowasthere, :usdc_mint)
    need = min_usdc * 10 ** @usdc_decimals

    body = %{
      jsonrpc: "2.0",
      id: 1,
      method: "getTransaction",
      params: [
        txid,
        %{encoding: "jsonParsed", maxSupportedTransactionVersion: 0, commitment: "confirmed"}
      ]
    }

    case Req.post(rpc, json: body, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"result" => nil}}} ->
        {:error, :tx_not_found}

      {:ok, %{status: 200, body: %{"result" => result}}} when is_map(result) ->
        check_transfer(result, wallet, mint, need)

      {:ok, %{status: status}} ->
        {:error, {:rpc_http, status}}

      {:error, reason} ->
        {:error, {:rpc, reason}}
    end
  end

  defp check_transfer(result, wallet, mint, need) do
    err = get_in(result, ["meta", "err"])

    if err not in [nil, %{}] do
      {:error, :tx_failed}
    else
      amount =
        result
        |> get_in(["meta", "postTokenBalances"])
        |> List.wrap()
        |> Enum.reduce(0, fn bal, acc ->
          if bal["mint"] == mint and bal["owner"] == wallet do
            ui = get_in(bal, ["uiTokenAmount", "amount"])

            case Integer.parse(to_string(ui || "0")) do
              {n, _} -> max(acc, n)
              :error -> acc
            end
          else
            acc
          end
        end)

      # Prefer delta when pre balances exist.
      pre =
        result
        |> get_in(["meta", "preTokenBalances"])
        |> List.wrap()
        |> Enum.find_value(0, fn bal ->
          if bal["mint"] == mint and bal["owner"] == wallet do
            case Integer.parse(to_string(get_in(bal, ["uiTokenAmount", "amount"]) || "0")) do
              {n, _} -> n
              :error -> 0
            end
          end
        end)

      post =
        result
        |> get_in(["meta", "postTokenBalances"])
        |> List.wrap()
        |> Enum.find_value(0, fn bal ->
          if bal["mint"] == mint and bal["owner"] == wallet do
            case Integer.parse(to_string(get_in(bal, ["uiTokenAmount", "amount"]) || "0")) do
              {n, _} -> n
              :error -> 0
            end
          end
        end)

      delta = post - pre

      cond do
        delta >= need -> :ok
        amount >= need and pre == 0 -> :ok
        true -> {:error, :amount_too_low}
      end
    end
  end
end
