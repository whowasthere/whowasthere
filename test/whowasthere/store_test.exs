defmodule WhoWasThere.StoreTest do
  use WhoWasThere.DataCase

  alias WhoWasThere.{HLL, Store}

  test "save_day writes day dims and hours atomically" do
    today = Date.utc_today()

    Store.upsert_site("store01", "tok01", "example.com")

    snap = %{
      pageviews: 3,
      sessions: 2,
      bounces: 1,
      duration_ms: 1000,
      hll: HLL.new() |> HLL.add(1) |> HLL.add(2),
      hours: List.to_tuple(for h <- 0..23, do: if(h == 10, do: 3, else: 0)),
      dims: Map.merge(Store.empty_dims(), %{"page" => %{"/" => 3}, "ref" => %{"direct" => 3}})
    }

    assert :ok = Store.save_day("store01", today, snap)

    assert [{_, loaded}] = Store.load_today(today)
    assert loaded.pageviews == 3
    assert loaded.dims["page"]["/"] == 3
    assert elem(loaded.hours, 10) == 3

    updated = %{
      snap
      | pageviews: 5,
        dims: Map.merge(Store.empty_dims(), %{"page" => %{"/a" => 5}})
    }

    assert :ok = Store.save_day("store01", today, updated)

    assert [{_, loaded}] = Store.load_today(today)
    assert loaded.pageviews == 5
    assert loaded.dims["page"]["/a"] == 5
    refute Map.has_key?(loaded.dims["page"], "/")
  end
end
