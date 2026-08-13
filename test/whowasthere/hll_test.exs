defmodule WhoWasThere.HLLTest do
  use ExUnit.Case, async: true

  alias WhoWasThere.HLL

  test "empty is zero" do
    assert HLL.cardinality(HLL.new()) == 0
  end

  test "one value is one" do
    hll = HLL.add(HLL.new(), 1)
    assert HLL.cardinality(hll) == 1
  end

  test "roundtrip binary" do
    hll = Enum.reduce(1..200, HLL.new(), &HLL.add(&2, &1))
    assert HLL.cardinality(HLL.from_bin(HLL.to_bin(hll))) == HLL.cardinality(hll)
  end

  test "estimates unique count within a few percent" do
    n = 5_000

    hll =
      Enum.reduce(1..n, HLL.new(), fn i, acc ->
        <<hash::unsigned-64, _::binary>> = :crypto.hash(:sha256, <<i::32>>)
        HLL.add(acc, hash)
      end)

    est = HLL.cardinality(hll)
    assert_in_delta est, n, n * 0.05
  end
end
