defmodule WhoWasThereWeb.IngestController do
  use WhoWasThereWeb, :controller

  alias WhoWasThere.Ingest

  @gif <<71, 73, 70, 56, 57, 97, 1, 0, 1, 0, 128, 0, 0, 0, 0, 0, 255, 255, 255, 33, 249, 4, 1, 0,
         0, 0, 0, 44, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 68, 1, 0, 59>>

  @external_resource "priv/static/t.js"
  @script File.read!("priv/static/t.js")

  def asset(conn, params) do
    if usable?(params), do: pixel(conn, params), else: script(conn, params)
  end

  def event(conn, params) do
    {conn, data} = payload(conn, params)
    Ingest.accept(conn, data)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(204, "")
  end

  def pixel(conn, params) do
    Ingest.accept(conn, params)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("image/gif")
    |> send_resp(200, @gif)
  end

  def script(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> put_resp_content_type("text/javascript")
    |> send_resp(200, @script)
  end

  defp payload(conn, params) do
    if usable?(params) do
      {conn, stringify(params)}
    else
      case Plug.Conn.read_body(conn, length: 8192) do
        {:ok, body, conn} -> {conn, decode(body)}
        {:more, _, conn} -> {conn, %{}}
        {:error, _} -> {conn, %{}}
      end
    end
  end

  defp usable?(params), do: is_binary(params["s"]) or is_binary(params["site"])

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) -> stringify(map)
      _ -> %{}
    end
  end

  defp stringify(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
