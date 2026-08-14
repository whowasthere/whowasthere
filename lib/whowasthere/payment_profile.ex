defmodule WhoWasThere.PaymentProfile do
  @moduledoc false

  import Ecto.Query

  alias WhoWasThere.{ID, Repo}
  alias WhoWasThere.Billing.Solana
  alias WhoWasThere.Store.PaymentProfile

  def create(payment_id) when is_binary(payment_id) do
    cap = "p_" <> ID.generate_token()
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

  defp cap_hash(cap), do: :crypto.hash(:sha256, cap)
end
