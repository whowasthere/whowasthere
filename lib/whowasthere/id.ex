defmodule WhoWasThere.ID do
  @moduledoc false

  @alphabet ~c"23456789abcdefghijkmnpqrstuvwxyz"
  @reserved MapSet.new(~w(
    new e health live assets fonts images phoenix
    robots.txt favicon.ico t.js e.gif w.js api dash d pay renew notify
  ))

  def generate, do: random(10)

  def nonce, do: random(8)

  def generate_token, do: random(22)

  def valid_token?(token) when is_binary(token) do
    String.length(token) in 16..32 and token =~ ~r/^[a-z0-9]+$/
  end

  def valid_token?(_), do: false

  defp random(n) do
    for <<idx <- :crypto.strong_rand_bytes(n)>>, into: "" do
      <<Enum.at(@alphabet, rem(idx, 32))>>
    end
  end

  def valid?(id) when is_binary(id) do
    String.length(id) in 8..32 and
      id =~ ~r/^[a-z0-9][a-z0-9_-]*$/i and
      not MapSet.member?(@reserved, String.downcase(id))
  end

  def valid?(_), do: false
end
