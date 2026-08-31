defmodule WhoWasThere.Repo.Migrations.AddStripeCheckouts do
  use Ecto.Migration

  def change do
    create table(:stripe_checkouts, primary_key: false) do
      add :session_id, :string, primary_key: true
      add :payment_id, :string, null: false
      add :amount_usdc, :integer, null: false
      add :created_at, :utc_datetime, null: false
    end

    create index(:stripe_checkouts, [:payment_id])
  end
end
