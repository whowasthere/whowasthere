defmodule WhoWasThereWeb.PageControllerTest do
  use WhoWasThereWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    host = "#{conn.scheme}://#{conn.host}"

    assert html =~ "whowasthere"
    assert html =~ ~s(<html phx-r lang="en" data-theme="light">)
    assert html =~ ~s(<meta name="theme-color" content="#f7f7f4">)
    refute html =~ "prefers-color-scheme: dark"

    assert html =~
             ~s(<meta name="description" content="Website analytics with no cookies or raw visit logs — only useful aggregates.">)

    assert html =~ ~s(<meta property="og:site_name" content="Who Was There">)

    assert html =~
             ~s(<meta property="og:title" content="Who Was There — privacy-first web analytics">)

    assert html =~ ~s(<meta property="og:url" content="#{host}">)
    assert html =~ ~s(<meta property="og:image" content="#{host}/images/icon-512.png">)
    assert html =~ ~s(<meta name="twitter:card" content="summary">)
    assert html =~ "curl -s"
    assert html =~ ~s(id="start")
    assert html =~ ~s(id="start-create")
    assert html =~ ~s(id="hads-create")
    assert html =~ ~s(data-hads-slot="create")
    assert html =~ "https://api.hads.dev/v1/hads.js?site=site_F7v4CJh18Dm4XZnSG64BlX4haf2xAanw"
    assert html =~ ~s(id="start-snippet")
    assert html =~ ~s(id="start-pay")
    assert html =~ ~s(id="start-deposit")
    assert html =~ ~s(id="start-pay-open")
    assert html =~ ~s(id="start-pay-step")
    assert html =~ ~s(id="start-pay-qr")
    assert html =~ ~s(id="start-pay-amount-control")
    assert html =~ ~s(id="start-pay-less")
    assert html =~ ~s(id="start-pay-more")
    assert html =~ ~s(id="start-wallet-open")
    assert html =~ ~s(id="start-pay-check")
    assert html =~ ~s(id="start-pay-status")
    assert html =~ "Pay when you’re ready"
    assert html =~ "SITE_KEY"

    document = LazyHTML.from_fragment(html)

    lead =
      document
      |> LazyHTML.query("#start .start-lead")
      |> LazyHTML.text()
      |> String.replace(~r/\s+/, " ")

    hosted =
      document
      |> LazyHTML.query("#start .start-hosted")
      |> LazyHTML.text()
      |> String.replace(~r/\s+/, " ")

    nav = LazyHTML.query(document, ".site-nav")

    assert LazyHTML.query(document, ".start-title") |> LazyHTML.text() =~ "Website analytics"
    assert lead =~ "Who Was There gives you a private dashboard"
    assert lead =~ "traffic, pages, referrers, devices, and journeys"
    assert lead =~ "no cookies"
    assert lead =~ "no raw visit logs"
    assert hosted =~ "Hosted here: 7 days free"
    assert hosted =~ "$30 USDC / year"
    assert hosted =~ "Self-host for full control"
    assert LazyHTML.query(document, "#start-event") |> Enum.empty?()
    assert LazyHTML.query(document, "#start-pixel") |> Enum.empty?()
    assert LazyHTML.query(document, "#start-curl") |> Enum.empty?()
    assert LazyHTML.query(nav, ".site-nav-link") |> Enum.count() == 4
    assert LazyHTML.query(nav, ".chip") |> Enum.empty?()
    refute LazyHTML.text(nav) =~ "start"
    refute LazyHTML.text(nav) =~ "curl /new"
    assert html =~ "This instance uses:"
    assert html =~ "One plan for every site in a payment profile"
    assert html =~ "500,000 pageviews / month"
    assert html =~ "private <code>pay URL</code>"
    assert html =~ "Blockchain transaction ids are never credentials"
    assert html =~ ~s(id="self-host")
    assert html =~ "Free profiles for your own sites"
    assert html =~ "WhoWasThere.Billing.grant"
    assert html =~ "analytics.example.com/new?pay=p_SECRET"
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
