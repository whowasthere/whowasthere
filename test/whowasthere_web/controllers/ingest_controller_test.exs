defmodule WhoWasThereWeb.IngestControllerTest do
  use WhoWasThereWeb.ConnCase

  alias WhoWasThere.{Analytics, Collector, Store}

  @ua "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36"

  test "GET / shows curl signup", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "curl -s"
    assert html_response(conn, 200) =~ "whowasthere"
  end

  test "GET /new signs keys and does not write the database", %{conn: conn} do
    conn = get(conn, ~p"/new?format=json")
    body = json_response(conn, 200)
    assert body["site"]
    assert body["key"] =~ "#{body["site"]}."
    assert body["snippet"] =~ "w.js"
    assert body["snippet"] =~ "data-w=\"#{body["key"]}\""
    refute body["snippet"] =~ "t.js"
    assert body["dash"] =~ "/d/"
    refute body["dash"] =~ "/#{body["site"]}"
    refute body["snippet"] =~ "/d/"
    assert Store.get_site(body["site"]) == nil
  end

  test "GET /new accepts application/json", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/new")

    body = json_response(conn, 200)
    assert body["snippet"]
    assert body["dash"]
  end

  test "GET /new?id= custom", %{conn: conn} do
    conn = get(conn, ~p"/new?id=my-blog-01")
    assert text_response(conn, 200) =~ "my-blog-01"
  end

  test "POST /w.js records a pageview", %{conn: conn} do
    {conn, body} = signup(conn, "ingest01")

    conn =
      conn
      |> put_req_header("user-agent", @ua)
      |> put_req_header("origin", "https://blog.test")
      |> put_req_header("content-type", "text/plain")
      |> post(~p"/w.js", Jason.encode!(%{s: body["key"], n: "v", p: "/hello", w: 390}))

    assert conn.status == 204
    Collector.ping()
    report = Analytics.report("ingest01", :today)
    assert report.pageviews == 1
    assert Enum.any?(report.dims["width"], &(&1.key == "0-639"))
    Collector.flush()
    assert Store.get_site("ingest01")
  end

  test "unsigned site ids are ignored", %{conn: conn} do
    {conn, _body} = signup(conn, "ingest09")

    conn
    |> put_req_header("user-agent", @ua)
    |> put_req_header("origin", "https://blog.test")
    |> put_req_header("content-type", "text/plain")
    |> post(~p"/w.js", Jason.encode!(%{s: "ingest09", n: "v", p: "/hello"}))

    Collector.ping()
    assert Analytics.report("ingest09", :today).pageviews == 0
  end

  test "GET /w.js?s= records a pageview as a gif", %{conn: conn} do
    {conn, body} = signup(conn, "ingest02")

    conn =
      conn
      |> put_req_header("user-agent", @ua)
      |> get(~p"/w.js?s=#{URI.encode_www_form(body["key"])}&p=/pix")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/gif"
    Collector.ping()
    assert Analytics.report("ingest02", :today).pageviews == 1
  end

  test "POST /w.js keeps hash-router paths", %{conn: conn} do
    {conn, body} = signup(conn, "ingest03")

    conn =
      conn
      |> put_req_header("user-agent", @ua)
      |> put_req_header("origin", "https://spa.test")
      |> put_req_header("content-type", "text/plain")
      |> post(~p"/w.js", Jason.encode!(%{s: body["key"], n: "v", p: "/#/pricing"}))

    assert conn.status == 204
    Collector.ping()
    pages = Analytics.report("ingest03", :today).dims["page"]
    assert Enum.any?(pages, &(&1.key == "/#/pricing"))
  end

  test "POST /w.js reads UTM medium and campaign", %{conn: conn} do
    {conn, body} = signup(conn, "ingest04")

    conn
    |> put_req_header("user-agent", @ua)
    |> put_req_header("origin", "https://blog.test")
    |> put_req_header("content-type", "text/plain")
    |> post(
      ~p"/w.js",
      Jason.encode!(%{
        s: body["key"],
        n: "v",
        p: "/",
        q: "?utm_source=twitter&utm_medium=social&utm_campaign=launch",
        w: 1440
      })
    )

    Collector.ping()
    dims = Analytics.report("ingest04", :today).dims
    assert Enum.any?(dims["src"], &(&1.key == "twitter"))
    assert Enum.any?(dims["medium"], &(&1.key == "social"))
    assert Enum.any?(dims["campaign"], &(&1.key == "launch"))
    assert Enum.any?(dims["width"], &(&1.key == "1440+"))
  end

  test "custom id is taken after the first hit", %{conn: conn} do
    {conn, body} = signup(conn, "ingest08")

    conn
    |> put_req_header("user-agent", @ua)
    |> put_req_header("origin", "https://blog.test")
    |> put_req_header("content-type", "text/plain")
    |> post(~p"/w.js", Jason.encode!(%{s: body["key"], n: "v", p: "/"}))

    Collector.ping()
    conn = get(build_conn(), ~p"/new?id=ingest08")
    assert conn.status == 409
  end

  test "GET /w.js serves the tracker", %{conn: conn} do
    conn = get(conn, ~p"/w.js")
    assert get_resp_header(conn, "content-type") |> hd() =~ "javascript"
    assert response(conn, 200) =~ "sendBeacon"
    assert response(conn, 200) =~ "data-w"
    assert response(conn, 200) =~ "innerWidth"
    assert response(conn, 200) =~ "click"
    assert response(conn, 200) =~ "pushState"
    assert response(conn, 200) =~ "composedPath"
    assert response(conn, 200) =~ "keepalive"
    assert response(conn, 200) =~ "pageshow"
    refute response(conn, 200) =~ "/e"
  end

  test "legacy /e and /t.js still work", %{conn: conn} do
    {conn, body} = signup(conn, "ingest05")

    conn =
      conn
      |> put_req_header("user-agent", @ua)
      |> put_req_header("content-type", "text/plain")
      |> post(~p"/e", Jason.encode!(%{s: body["key"], n: "v", p: "/old"}))

    assert conn.status == 204

    script = conn |> recycle() |> get(~p"/t.js")
    assert script.status == 200

    pixel = script |> recycle() |> get(~p"/e.gif?s=#{URI.encode_www_form(body["key"])}")
    assert pixel.status == 200
  end

  defp signup(conn, id) do
    conn = get(conn, ~p"/new?id=#{id}&format=json")
    {recycle(conn), json_response(conn, 200)}
  end
end
