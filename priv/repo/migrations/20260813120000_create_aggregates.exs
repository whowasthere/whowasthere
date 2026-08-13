defmodule WhoWasThere.Repo.Migrations.CreateAggregates do
  use Ecto.Migration

  def change do
    create table(:sites, primary_key: false) do
      add :id, :string, primary_key: true
      add :host, :string
      add :created_at, :utc_datetime, null: false
    end

    create table(:days, primary_key: false) do
      add :site_id, :string, primary_key: true
      add :day, :date, primary_key: true
      add :pageviews, :integer, null: false, default: 0
      add :uniques, :integer, null: false, default: 0
      add :sessions, :integer, null: false, default: 0
      add :bounces, :integer, null: false, default: 0
      add :duration_ms, :integer, null: false, default: 0
      add :hll, :binary
    end

    create table(:dims, primary_key: false) do
      add :site_id, :string, primary_key: true
      add :day, :date, primary_key: true
      add :kind, :string, primary_key: true
      add :key, :string, primary_key: true
      add :pageviews, :integer, null: false, default: 0
    end

    create table(:hours, primary_key: false) do
      add :site_id, :string, primary_key: true
      add :day, :date, primary_key: true
      add :hour, :integer, primary_key: true
      add :pageviews, :integer, null: false, default: 0
    end
  end
end
