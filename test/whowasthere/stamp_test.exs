defmodule WhoWasThere.StampTest do
  use ExUnit.Case, async: true

  alias WhoWasThere.Stamp

  @pay "t_testpay01abcdefghijkl"

  test "ingest key verifies for the locked host only" do
    issued = Stamp.issue("my-blog-01", "Example.COM", @pay)

    assert {:ok, %{id: "my-blog-01", host: "example.com", payment_id: @pay}} =
             Stamp.verify_ingest(issued.key, "www.example.com")

    assert Stamp.verify_ingest(issued.key, "evil.com") == :error
  end

  test "open ingest key accepts any host and stays unlocked" do
    issued = Stamp.issue("my-blog-02", nil, @pay)
    assert {:ok, %{id: "my-blog-02", host: nil}} = Stamp.verify_ingest(issued.key, "a.test")
    assert {:ok, %{host: nil}} = Stamp.verify_ingest(issued.key, "b.test")
  end

  test "dashboard token is not derivable from the public key" do
    a = Stamp.issue("my-blog-03", "dash.test", @pay)
    b = Stamp.issue("my-blog-03", "dash.test", @pay)
    assert a.key != b.key
    assert a.token != b.token
    assert {:ok, claims} = Stamp.verify_dash(a.token)
    assert claims.id == "my-blog-03"
    assert claims.nonce == a.nonce
    assert claims.payment_id == @pay
    assert Stamp.verify_dash(a.key) == :error
    assert Stamp.verify_dash("notarealtoken0000001") == :error
  end

  test "unsigned site ids are rejected" do
    assert Stamp.verify_ingest("my-blog-01", "example.com") == :error
    assert Stamp.verify_ingest("not a tag", "example.com") == :error
  end
end
