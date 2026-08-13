defmodule WhoWasThere.Ingest do
  @moduledoc false

  alias WhoWasThere.{Collector, Stamp}

  def accept(conn, data) do
    tag = str(data["s"] || data["site"])
    host = host(conn, data)

    case Stamp.verify_ingest(tag, host) do
      {:ok, %{id: id, nonce: nonce, payment_id: payment_id, host: locked}} ->
        {src, medium, campaign} = campaign_fields(data["q"] || data["query"] || "")

        Collector.ingest(%{
          site_id: id,
          nonce: nonce,
          payment_id: payment_id,
          name: normalize_name(data["n"] || data["name"]),
          path: normalize_path(data["p"] || data["path"]),
          ref: normalize_ref(data["r"] || data["ref"], host),
          src: src,
          medium: medium,
          campaign: campaign,
          event: str(data["e"] || data["event"]) |> String.slice(0, 40),
          lang: lang(data["l"] || data["lang"]),
          width: viewport(data["w"] || data["width"]),
          host: locked || host,
          country: country(conn, data),
          ua: ua(conn),
          ip: ip(conn)
        })

        :ok

      :error ->
        :ok
    end
  end

  defp normalize_name(n) when n in ["v", "h", "x", "c", "k"], do: n
  defp normalize_name(_), do: "v"

  defp normalize_path(nil), do: "/"

  defp normalize_path(path) do
    path = path |> to_string() |> String.split("?", parts: 2) |> hd()

    p =
      case String.split(path, "#", parts: 2) do
        [base] ->
          empty_path(base)

        [base, hash] ->
          if String.starts_with?(hash, "/") or String.starts_with?(hash, "!/") do
            empty_path(base) <> "#" <> hash
          else
            empty_path(base)
          end
      end

    String.slice(p, 0, 180)
  end

  defp empty_path(""), do: "/"
  defp empty_path(p), do: p

  defp host(conn, data) do
    origin_host(conn) || header_host(conn, "referer") || norm_host(data["h"] || data["host"])
  end

  defp origin_host(conn) do
    case Plug.Conn.get_req_header(conn, "origin") do
      ["null"] -> nil
      [origin] -> origin |> URI.parse() |> Map.get(:host) |> norm_host()
      _ -> nil
    end
  end

  defp header_host(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value] -> value |> URI.parse() |> Map.get(:host) |> norm_host()
      _ -> nil
    end
  end

  defp norm_host(nil), do: nil
  defp norm_host(""), do: nil

  defp norm_host(host) do
    host
    |> to_string()
    |> String.downcase()
    |> String.trim()
    |> String.replace_prefix("www.", "")
    |> case do
      "" -> nil
      h -> String.slice(h, 0, 80)
    end
  end

  defp normalize_ref(ref, site_host) do
    host = ref |> to_string() |> URI.parse() |> Map.get(:host) |> norm_host()

    cond do
      is_nil(host) -> "direct"
      host == site_host -> "direct"
      true -> host
    end
  end

  defp campaign_fields(q) do
    q = q |> to_string() |> String.trim_leading("?")

    query =
      case URI.decode_query(q) do
        map when is_map(map) -> map
        _ -> %{}
      end

    {
      pick(query, ["utm_source", "source", "ref"]) || "direct",
      pick(query, ["utm_medium", "medium"]),
      pick(query, ["utm_campaign", "campaign"])
    }
  rescue
    _ -> {"direct", nil, nil}
  end

  defp pick(query, keys) do
    Enum.find_value(keys, fn key ->
      case query[key] do
        v when is_binary(v) and v != "" -> String.slice(v, 0, 40)
        _ -> nil
      end
    end)
  end

  defp lang(nil), do: "??"

  defp lang(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.slice(0, 2)
    |> case do
      <<a, b>> when a in ?a..?z and b in ?a..?z -> <<a, b>>
      _ -> "??"
    end
  end

  defp viewport(nil), do: nil
  defp viewport(w) when is_integer(w), do: width_bucket(w)

  defp viewport(w) when is_binary(w) do
    case Integer.parse(String.trim(w)) do
      {n, _} -> width_bucket(n)
      :error -> nil
    end
  end

  defp viewport(_), do: nil

  defp width_bucket(w) when w < 1, do: nil
  defp width_bucket(w) when w < 640, do: "0-639"
  defp width_bucket(w) when w < 1024, do: "640-1023"
  defp width_bucket(w) when w < 1440, do: "1024-1439"
  defp width_bucket(_), do: "1440+"

  defp country(conn, data) do
    header =
      Enum.find_value(
        ~w(cf-ipcountry cloudfront-viewer-country x-vercel-ip-country x-country-code),
        fn name ->
          case Plug.Conn.get_req_header(conn, name) do
            [v] ->
              v = v |> String.upcase() |> String.slice(0, 2)
              if v in ["", "XX", "T1"], do: nil, else: v

            _ ->
              nil
          end
        end
      )

    header || region_from_lang(data["l"] || data["lang"]) || "??"
  end

  defp region_from_lang(nil), do: nil

  defp region_from_lang(value) do
    case String.split(to_string(value), ["-", "_"], parts: 2) do
      [_, region] ->
        region = String.upcase(region) |> String.slice(0, 2)
        if region =~ ~r/^[A-Z]{2}$/, do: region, else: nil

      _ ->
        nil
    end
  end

  defp ua(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [v] -> String.slice(v, 0, 300)
      _ -> ""
    end
  end

  defp ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [v | _] -> v |> String.split(",", parts: 2) |> hd() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp str(nil), do: ""
  defp str(v), do: v |> to_string() |> String.trim()
end
