defmodule WhoWasThere.Repo do
  use Ecto.Repo,
    otp_app: :whowasthere,
    adapter: Ecto.Adapters.SQLite3
end
