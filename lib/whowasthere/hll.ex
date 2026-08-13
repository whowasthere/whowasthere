defmodule WhoWasThere.HLL do
  @moduledoc false
  # HyperLogLog p=12 → 4KB на сайт/день, ошибка ~1.6%. Сырые id посетителей не храним.

  @p 12
  @m 4096
  @alpha 0.7213 / (1 + 1.079 / 4096)

  def new, do: :array.new(@m, default: 0, fixed: true)

  def add(hll, hash) when is_integer(hash) do
    add(hll, <<hash::unsigned-64>>)
  end

  def add(hll, <<idx::size(@p), rest::size(64 - @p)>>) do
    rho = rho(rest)
    old = :array.get(idx, hll)
    if rho > old, do: :array.set(idx, rho, hll), else: hll
  end

  def cardinality(hll) do
    sum =
      Enum.reduce(0..(@m - 1), 0.0, fn i, acc ->
        acc + :math.pow(2, -:array.get(i, hll))
      end)

    zeros = Enum.count(0..(@m - 1), fn i -> :array.get(i, hll) == 0 end)
    estimate = @alpha * @m * @m / sum

    cond do
      estimate <= 2.5 * @m and zeros > 0 ->
        round(@m * :math.log(@m / zeros))

      true ->
        round(estimate)
    end
  end

  def to_bin(hll) do
    for i <- 0..(@m - 1), into: <<>>, do: <<:array.get(i, hll)::8>>
  end

  def from_bin(<<bin::binary-size(@m)>>) do
    for(<<reg::8 <- bin>>, do: reg)
    |> Enum.with_index()
    |> Enum.reduce(new(), fn {val, i}, acc -> :array.set(i, val, acc) end)
  end

  def from_bin(_), do: new()

  defp rho(0), do: 53
  defp rho(rest), do: 52 - floor(:math.log2(rest))
end
