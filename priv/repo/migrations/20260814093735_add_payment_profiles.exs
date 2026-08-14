defmodule WhoWasThere.Repo.Migrations.AddPaymentProfiles do
  use Ecto.Migration

  def change do
    create table(:payment_profiles, primary_key: false) do
      add :id, :string, primary_key: true

      add :payment_id, references(:payments, type: :string, column: :id, on_delete: :delete_all),
        null: false

      add :cap_hash, :binary, null: false
      add :deposit_address, :string, null: false
      add :settled_usdc, :integer, null: false, default: 0
      add :created_at, :utc_datetime, null: false
    end

    create unique_index(:payment_profiles, [:payment_id])
    create unique_index(:payment_profiles, [:cap_hash])
    create unique_index(:payment_profiles, [:deposit_address])
  end
end
