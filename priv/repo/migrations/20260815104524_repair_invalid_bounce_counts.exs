defmodule WhoWasThere.Repo.Migrations.RepairInvalidBounceCounts do
  use Ecto.Migration

  def up do
    execute("UPDATE days SET bounces = sessions WHERE bounces > sessions")
  end

  def down, do: :ok
end
