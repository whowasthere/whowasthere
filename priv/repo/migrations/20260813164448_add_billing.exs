defmodule WhoWasThere.Repo.Migrations.AddBilling do
  use Ecto.Migration

  def change do
    create table(:payments, primary_key: false) do
      add :id, :string, primary_key: true
      add :kind, :string, null: false
      add :txid, :string
      add :email, :string
      add :expires_at, :utc_datetime, null: false
      add :month, :string, null: false
      add :hits_month, :integer, null: false, default: 0
      add :notices, :string, null: false, default: ""
      add :created_at, :utc_datetime, null: false
    end

    create unique_index(:payments, [:txid])

    alter table(:sites) do
      add :payment_id, :string
    end

    create index(:sites, [:payment_id])
  end
end
