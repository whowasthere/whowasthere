defmodule WhoWasThereWeb.PageControllerTest do
  use WhoWasThereWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    host = "#{conn.scheme}://#{conn.host}"

    assert html =~ "whowasthere"
    assert html =~ "curl -s"
    assert html =~ ~s(id="start")
    assert html =~ ~s(id="start-create")
    assert html =~ ~s(id="start-curl")
    assert html =~ ~s(id="start-snippet")
    assert html =~ "SITE_KEY"
    assert html =~ "hosted cloud"
    assert html =~ ~s(id="self-host")
    assert html =~ "mix phx.server"
    assert html =~ "http://localhost:4000"
    assert html =~ "curl -s #{host}/new"
    refute html =~ "Then open #{host}"
    assert html =~ ~s(href="LICENSE")
  end

  test "GET /LICENSE", %{conn: conn} do
    conn = get(conn, ~p"/LICENSE")
    body = text_response(conn, 200)
    assert body =~ "GNU AFFERO GENERAL PUBLIC LICENSE"
  end
end
