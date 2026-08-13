defmodule WhoWasThere.Repo.Migrations.AddSiteDashToken do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :token, :string
    end

    create unique_index(:sites, [:token])
  end
end
