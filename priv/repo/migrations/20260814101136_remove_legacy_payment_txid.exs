defmodule WhoWasThere.Repo.Migrations.RemoveLegacyPaymentTxid do
  use Ecto.Migration

  def up do
    drop_if_exists index(:payments, [:txid])

    alter table(:payments) do
      remove :txid
    end
  end

  def down do
    alter table(:payments) do
      add :txid, :string
    end

    create unique_index(:payments, [:txid])
  end
end
