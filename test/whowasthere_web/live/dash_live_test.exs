defmodule WhoWasThereWeb.DashLiveTest do
  use WhoWasThereWeb.ConnCase

  import Phoenix.LiveViewTest

  @ua "Mozilla/5.0 (Macintosh; Intel Mac OS X) Chrome/120.0.0.0 Safari/537.36"

  test "dashboard opens by secret token, not public site id", %{conn: conn} do
    {:ok, site} = WhoWasThere.Collector.create_site("dashsite1", "dash.test")

    WhoWasThere.Collector.ingest(%{
      site_id: "dashsite1",
      name: "v",
      path: "/pricing",
      ref: "direct",
      src: "direct",
      event: "",
      lang: "ru",
      host: "dash.test",
      country: "RU",
      ua: @ua,
      ip: "8.8.8.8"
    })

    WhoWasThere.Collector.ping()

    conn = get(conn, "/dashsite1")
    assert conn.status == 404

    {:ok, view, html} = live(conn, "/d/#{site.token}")
    assert html =~ "pricing"
    assert render(view) =~ "pageviews"
  end

  test "shows the locked host, not the site id", %{conn: conn} do
    conn = get(conn, ~p"/new?id=dashsite3&host=named.test&format=json")
    body = json_response(conn, 200)

    {:ok, _view, html} = live(recycle(conn), "/d/#{token(body)}")
    assert html =~ "named.test"
    refute html =~ "no host yet"
  end

  test "dashboard works before any hits", %{conn: conn} do
    conn = get(conn, ~p"/new?id=dashsite2&format=json")
    body = json_response(conn, 200)

    {:ok, _view, html} = live(recycle(conn), "/d/#{token(body)}")
    assert html =~ "pageviews"
    assert html =~ "dashsite2"
    assert html =~ "no host yet"
  end

  defp token(body), do: body["dash"] |> String.split("/d/") |> List.last()

  test "unknown token is denied", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/d/notarealtoken0000001")
    assert html =~ "This link does not work"
  end
end
