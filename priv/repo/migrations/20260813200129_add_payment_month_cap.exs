defmodule WhoWasThere.Repo.Migrations.AddPaymentMonthCap do
  use Ecto.Migration

  def change do
    alter table(:payments) do
      add :month_cap, :integer, null: false, default: 500_000
    end
  end
end
