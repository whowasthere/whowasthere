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
    assert html =~ ~s(id="hads-create")
    assert html =~ ~s(data-hads-slot="create")
    assert html =~ "https://api.hads.dev/v1/hads.js?site=site_F7v4CJh18Dm4XZnSG64BlX4haf2xAanw"
    assert html =~ ~s(id="start-curl")
    assert html =~ ~s(id="start-snippet")
    assert html =~ "SITE_KEY"
    assert html =~ "Privacy-first web analytics"
    assert html =~ "no cookies or raw visit logs"
    assert html =~ "use this instance’s origin"
    assert html =~ "payment instructions"
    assert html =~ "This instance uses:"
    assert html =~ "within the instance that verifies it"
    assert html =~ "Get the payment wallet from <code>/pay</code> on that same instance"
    assert html =~ ~s(id="self-host")
    assert html =~ "mix phx.server"
    assert html =~ "http://localhost:4000"
    assert html =~ "curl -s #{host}/new"
    assert html =~ "#{host}/w.js"
    assert html =~ "#{host}/d/TOKEN"
    refute html =~ "Then open #{host}"
    assert html =~ ~s(href="LICENSE")
  end

  test "GET /LICENSE", %{conn: conn} do
    conn = get(conn, ~p"/LICENSE")
    body = text_response(conn, 200)
    assert body =~ "GNU AFFERO GENERAL PUBLIC LICENSE"
  end
end
