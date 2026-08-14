defmodule WhoWasThere.Base58Test do
  use ExUnit.Case, async: true

  alias WhoWasThere.Base58
  alias WhoWasThere.Billing.Solana

  test "round trips binary keys and preserves leading zeros" do
    key = <<0, 0, 1, 2, 3, 250, 255>>
    encoded = Base58.encode(key)

    assert String.starts_with?(encoded, "11")
    assert {:ok, ^key} = Base58.decode(encoded)
    assert {:error, :invalid_base58} = Base58.decode("0OIl")
  end

  test "payment deposit owners are deterministic and separated by capability" do
    assert {:ok, first} = Solana.deposit_address("p_firstprivatecapability")
    assert {:ok, ^first} = Solana.deposit_address("p_firstprivatecapability")
    assert {:ok, second} = Solana.deposit_address("p_secondprivatecapability")
    assert first != second
    assert {:ok, _fee_payer} = Solana.master_address()
  end
end
