defmodule WhoWasThere.Base58 do
  @moduledoc false

  @alphabet "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  def encode(binary) when is_binary(binary) do
    zeros = binary |> :binary.bin_to_list() |> Enum.take_while(&(&1 == 0)) |> length()
    value = :binary.decode_unsigned(binary)
    encoded = if value == 0, do: "", else: encode_integer(value, [])
    String.duplicate("1", zeros) <> encoded
  end

  def decode(value) when is_binary(value) do
    with {:ok, number} <- decode_chars(String.to_charlist(value), 0) do
      zeros = value |> String.to_charlist() |> Enum.take_while(&(&1 == ?1)) |> length()
      body = if number == 0, do: <<>>, else: :binary.encode_unsigned(number)
      {:ok, :binary.copy(<<0>>, zeros) <> body}
    end
  end

  defp decode_chars([], number), do: {:ok, number}

  defp decode_chars([char | rest], number) do
    case :binary.match(@alphabet, <<char>>) do
      {index, 1} -> decode_chars(rest, number * 58 + index)
      :nomatch -> {:error, :invalid_base58}
    end
  end

  defp encode_integer(0, chars), do: IO.iodata_to_binary(chars)

  defp encode_integer(value, chars) do
    digit = rem(value, 58)
    encode_integer(div(value, 58), [binary_part(@alphabet, digit, 1) | chars])
  end
end
