defmodule WhoWasThere.Stamp do
  @moduledoc false

  alias WhoWasThere.ID

  @ingest "wwt-ingest"
  @dash "wwt-dash"
  @mac_bytes 9

  def issue(id, host \\ nil, payment_id) when is_binary(payment_id) do
    host = normalize_host(host)
    nonce = ID.nonce()

    %{
      id: id,
      host: host,
      nonce: nonce,
      payment_id: payment_id,
      key: ingest_key(id, nonce, host, payment_id),
      token: dash_token(id, nonce, host, payment_id)
    }
  end

  def ingest_key(id, nonce, host, payment_id) do
    Enum.join([id, nonce, payment_id, mac(@ingest, [id, nonce, host || "", payment_id])], ".")
  end

  def verify_ingest(tag, event_host) when is_binary(tag) do
    event_host = normalize_host(event_host)

    with [id, nonce, payment_id, given] <- String.split(tag, ".", parts: 4),
         true <- ID.valid?(id),
         true <- nonce?(nonce),
         true <- payment_id?(payment_id),
         {:ok, locked} <- match_host(id, nonce, payment_id, given, event_host) do
      {:ok, %{id: id, nonce: nonce, payment_id: payment_id, host: locked}}
    else
      _ -> :error
    end
  end

  def verify_ingest(_, _), do: :error

  def dash_token(id, nonce, host, payment_id) do
    Plug.Crypto.sign(secret(), @dash, %{
      i: id,
      n: nonce,
      h: normalize_host(host),
      p: payment_id
    })
  end

  def verify_dash(token) when is_binary(token) do
    case Plug.Crypto.verify(secret(), @dash, token, max_age: :infinity) do
      {:ok, %{i: id, n: nonce, h: host, p: payment_id}} ->
        if ID.valid?(id) and nonce?(nonce) and payment_id?(payment_id) do
          {:ok, %{id: id, nonce: nonce, host: host, payment_id: payment_id}}
        else
          :error
        end

      # Older tokens without payment_id.
      {:ok, %{i: id, n: nonce, h: host}} ->
        if ID.valid?(id) and nonce?(nonce) do
          {:ok, %{id: id, nonce: nonce, host: host, payment_id: nil}}
        else
          :error
        end

      _ ->
        :error
    end
  end

  def verify_dash(_), do: :error

  def normalize_host(nil), do: nil
  def normalize_host(""), do: nil

  def normalize_host(host) do
    host
    |> to_string()
    |> String.downcase()
    |> String.trim()
    |> String.replace_prefix("www.", "")
    |> case do
      "" -> nil
      h -> String.slice(h, 0, 80)
    end
  end

  defp match_host(id, nonce, payment_id, given, event_host) do
    cond do
      valid_mac?(id, nonce, payment_id, event_host, given) and event_host != nil ->
        {:ok, event_host}

      valid_mac?(id, nonce, payment_id, "", given) ->
        {:ok, nil}

      true ->
        :error
    end
  end

  defp valid_mac?(id, nonce, payment_id, host, given) do
    expected = mac(@ingest, [id, nonce, host || "", payment_id])
    byte_size(expected) == byte_size(given) and Plug.Crypto.secure_compare(expected, given)
  rescue
    _ -> false
  end

  defp mac(salt, parts) do
    secret()
    |> Plug.Crypto.KeyGenerator.generate(salt, length: 32)
    |> then(&:crypto.mac(:hmac, :sha256, &1, Enum.join(parts, "\n")))
    |> binary_part(0, @mac_bytes)
    |> Base.url_encode64(padding: false)
  end

  defp nonce?(value) when is_binary(value) do
    byte_size(value) == 8 and value =~ ~r/^[2-9a-kmnp-z]+$/
  end

  defp nonce?(_), do: false

  defp payment_id?(value) when is_binary(value) do
    String.length(value) in 8..128 and value =~ ~r/^[a-zA-Z0-9_-]+$/
  end

  defp payment_id?(_), do: false

  defp secret do
    Application.fetch_env!(:whowasthere, WhoWasThereWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end
end
