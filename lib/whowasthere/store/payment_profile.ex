defmodule WhoWasThere.Store.PaymentProfile do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "payment_profiles" do
    field :payment_id, :string
    field :cap_hash, :binary
    field :deposit_address, :string
    field :settled_usdc, :integer, default: 0
    field :created_at, :utc_datetime
  end
end
