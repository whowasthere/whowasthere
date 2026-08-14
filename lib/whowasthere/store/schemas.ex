defmodule WhoWasThere.Store.Site do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "sites" do
    field :token, :string
    field :host, :string
    field :payment_id, :string
    field :created_at, :utc_datetime
  end
end

defmodule WhoWasThere.Store.Payment do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "payments" do
    field :kind, :string
    field :email, :string
    field :expires_at, :utc_datetime
    field :month, :string
    field :hits_month, :integer, default: 0
    field :month_cap, :integer, default: 500_000
    field :notices, :string, default: ""
    field :created_at, :utc_datetime
  end
end

defmodule WhoWasThere.Store.Day do
  use Ecto.Schema

  @primary_key false
  schema "days" do
    field :site_id, :string, primary_key: true
    field :day, :date, primary_key: true
    field :pageviews, :integer, default: 0
    field :uniques, :integer, default: 0
    field :sessions, :integer, default: 0
    field :bounces, :integer, default: 0
    field :duration_ms, :integer, default: 0
    field :hll, :binary
  end
end

defmodule WhoWasThere.Store.Dim do
  use Ecto.Schema

  @primary_key false
  schema "dims" do
    field :site_id, :string, primary_key: true
    field :day, :date, primary_key: true
    field :kind, :string, primary_key: true
    field :key, :string, primary_key: true
    field :pageviews, :integer, default: 0
  end
end

defmodule WhoWasThere.Store.Hour do
  use Ecto.Schema

  @primary_key false
  schema "hours" do
    field :site_id, :string, primary_key: true
    field :day, :date, primary_key: true
    field :hour, :integer, primary_key: true
    field :pageviews, :integer, default: 0
  end
end
