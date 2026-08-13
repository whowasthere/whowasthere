defmodule WhoWasThereWeb.Plugs.CORS do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type")
    |> put_resp_header("access-control-max-age", "86400")
    |> maybe_halt()
  end

  defp maybe_halt(%{method: "OPTIONS"} = conn), do: conn |> send_resp(204, "") |> halt()
  defp maybe_halt(conn), do: conn
end
