defmodule WhoWasThere.Store.StripeCheckout do
  use Ecto.Schema

  @primary_key {:session_id, :string, autogenerate: false}
  schema "stripe_checkouts" do
    field :payment_id, :string
    field :amount_usdc, :integer
    field :created_at, :utc_datetime
  end
end
