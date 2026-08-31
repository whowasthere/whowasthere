defmodule WhoWasThere.PaymentProfile do
  @moduledoc false

  import Ecto.Query

  alias WhoWasThere.{ID, Repo}
  alias WhoWasThere.Billing.Solana
  alias WhoWasThere.Store.PaymentProfile

  @alphabet ~c"23456789abcdefghijkmnpqrstuvwxyz"
  @token_rand 16
  @token_mac 6
  @token_len @token_rand + @token_mac

  def create(payment_id) when is_binary(payment_id) do
    create(payment_id, "p_" <> ID.generate_token())
  end

  def create(payment_id, "p_" <> _ = cap) when is_binary(payment_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, deposit_address} <- Solana.deposit_address(cap) do
      profile = %PaymentProfile{
        id: "profile_" <> ID.generate_token(),
        payment_id: payment_id,
        cap_hash: cap_hash(cap),
        deposit_address: deposit_address,
        created_at: now
      }

      {:ok, Repo.insert!(profile), cap}
    end
  end

  @doc """
  Issues a pay capability that is not stored until first use.

  The token embeds a short MAC so random `p_…` guesses cannot materialize a trial.
  Payment id shares the same token body (`t_` <> token) so an ingest key can
  materialize the same profile without a prior database row.
  """
  def issue_lazy do
    token = issue_token()
    cap = "p_" <> token
    payment_id = "t_" <> token

    with {:ok, deposit_address} <- Solana.deposit_address(cap) do
      {:ok,
       %{
         cap: cap,
         payment_id: payment_id,
         deposit_address: deposit_address
       }}
    end
  end

  def get_by_cap(cap) when is_binary(cap) do
    case cap do
      "p_" <> token ->
        if ID.valid_token?(token) do
          Repo.one(from p in PaymentProfile, where: p.cap_hash == ^cap_hash(cap))
        end

      _ ->
        nil
    end
  end

  def get_by_cap(_), do: nil

  def get_by_payment(payment_id) when is_binary(payment_id) do
    Repo.one(from p in PaymentProfile, where: p.payment_id == ^payment_id)
  end

  def get_by_payment(_), do: nil

  def add_settled(profile, amount) when is_integer(amount) and amount > 0 do
    profile
    |> Ecto.Changeset.change(settled_usdc: profile.settled_usdc + amount)
    |> Repo.update!()
  end

  def issued_cap?("p_" <> token), do: issued_token?(token)
  def issued_cap?(_), do: false

  def payment_id_for_cap("p_" <> token = cap) do
    if issued_cap?(cap), do: "t_" <> token
  end

  def payment_id_for_cap(_), do: nil

  def cap_for_payment_id("t_" <> token) do
    if issued_token?(token), do: "p_" <> token
  end

  def cap_for_payment_id(_), do: nil

  defp issue_token do
    rand = random_alphabet(@token_rand)
    rand <> token_mac(rand)
  end

  defp issued_token?(token) when is_binary(token) do
    ID.valid_token?(token) and String.length(token) == @token_len and
      String.slice(token, @token_rand, @token_mac) ==
        token_mac(String.slice(token, 0, @token_rand))
  end

  defp token_mac(rand) do
    :crypto.mac(:hmac, :sha256, secret(), "whowasthere/pay/cap/v1:" <> rand)
    |> alphabet_prefix(@token_mac)
  end

  defp alphabet_prefix(binary, n) do
    for <<idx <- binary>>, into: "" do
      <<Enum.at(@alphabet, rem(idx, 32))>>
    end
    |> String.slice(0, n)
  end

  defp random_alphabet(n) do
    for <<idx <- :crypto.strong_rand_bytes(n)>>, into: "" do
      <<Enum.at(@alphabet, rem(idx, 32))>>
    end
  end

  defp secret do
    Application.fetch_env!(:whowasthere, WhoWasThereWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end

  defp cap_hash(cap), do: :crypto.hash(:sha256, cap)
end
