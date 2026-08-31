defmodule WhoWasThereWeb.PageController do
  use WhoWasThereWeb, :controller

  def home(conn, params) do
    base = base_url(conn)
    info = WhoWasThere.Billing.info()

    render(conn, :home,
      page_title: "who was there",
      base_url: base,
      payment_cap: params["pay"],
      stripe_enabled: info.stripe,
      open_graph: %{
        title: "Who Was There — privacy-first web analytics",
        description:
          "Website analytics with no cookies or raw visit logs — only useful aggregates.",
        url: base,
        image: "#{base}/images/icon-512.png"
      },
      readme:
        WhoWasThere.Readme.html(base,
          omit_intro: true,
          omit_sections: ["Create a site", "Add the tracker"]
        )
    )
  end

  def license(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, WhoWasThere.License.text())
  end

  defp base_url(conn) do
    port =
      cond do
        conn.scheme == :http and conn.port == 80 -> ""
        conn.scheme == :https and conn.port == 443 -> ""
        true -> ":#{conn.port}"
      end

    "#{conn.scheme}://#{conn.host}#{port}"
  end
end
