defmodule WhoWasThereWeb.PageController do
  use WhoWasThereWeb, :controller

  def home(conn, _params) do
    base = base_url(conn)

    render(conn, :home,
      page_title: "who was there",
      base_url: base,
      readme: WhoWasThere.Readme.html(base, omit_intro: true)
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
