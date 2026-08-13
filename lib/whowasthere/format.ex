defmodule WhoWasThere.Format do
  @moduledoc false

  def compact(n) when is_integer(n) and n >= 1_000_000 do
    :erlang.float_to_binary(n / 1_000_000, decimals: 1) <> "M"
  end

  def compact(n) when is_integer(n) and n >= 1_000 do
    :erlang.float_to_binary(n / 1_000, decimals: 1) <> "k"
  end

  def compact(n) when is_integer(n), do: Integer.to_string(n)
  def compact(_), do: "0"

  def pct(rate) when is_number(rate) do
    :erlang.float_to_binary(rate * 100, decimals: 1) <> "%"
  end

  def pct(_), do: "0%"

  def duration(ms) when is_integer(ms) and ms > 0 do
    s = div(ms, 1000)

    cond do
      s < 60 -> "#{s}s"
      s < 3600 -> "#{div(s, 60)}m #{rem(s, 60)}s"
      true -> "#{div(s, 3600)}h #{div(rem(s, 3600), 60)}m"
    end
  end

  def duration(_), do: "0s"
end
