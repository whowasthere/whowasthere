import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :whowasthere, WhoWasThere.Repo,
  database: Path.expand("../whowasthere_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :whowasthere, WhoWasThereWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "lYOpcR2dbLT4KbHxtZH+JTHYhQ6YoTo1ahOHF8G+5435ORrFfdI23aZQZT1cVn9Y",
  server: false

config :whowasthere, persist_interval: :infinity
config :whowasthere, mailer: :mailbox
config :whowasthere, pay_wallet: "Demo111111111111111111111111111111111111111"
config :whowasthere, pay_master_key: "11111111111111111111111111111111"
config :whowasthere, solana_profile_settle: fn _, _, _ -> {:ok, 0} end

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
