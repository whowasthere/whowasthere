defmodule WhoWasThere.Format do
  @moduledoc false

  @countries %{
    "US" => "United States",
    "GB" => "United Kingdom",
    "DE" => "Germany",
    "FR" => "France",
    "NL" => "Netherlands",
    "PL" => "Poland",
    "IT" => "Italy",
    "ES" => "Spain",
    "PT" => "Portugal",
    "SE" => "Sweden",
    "NO" => "Norway",
    "FI" => "Finland",
    "DK" => "Denmark",
    "IE" => "Ireland",
    "CH" => "Switzerland",
    "AT" => "Austria",
    "BE" => "Belgium",
    "CZ" => "Czechia",
    "UA" => "Ukraine",
    "RU" => "Russia",
    "TR" => "Turkey",
    "IL" => "Israel",
    "AE" => "UAE",
    "IN" => "India",
    "CN" => "China",
    "JP" => "Japan",
    "KR" => "South Korea",
    "SG" => "Singapore",
    "AU" => "Australia",
    "NZ" => "New Zealand",
    "CA" => "Canada",
    "BR" => "Brazil",
    "MX" => "Mexico",
    "AR" => "Argentina",
    "ZA" => "South Africa"
  }

  def compact(n) when is_integer(n) and n >= 1_000_000 do
    :erlang.float_to_binary(n / 1_000_000, decimals: 1) <> "M"
  end

  def compact(n) when is_integer(n) and n >= 1_000 do
    :erlang.float_to_binary(n / 1_000, decimals: 1) <> "k"
  end

  def compact(n) when is_integer(n), do: Integer.to_string(n)
  def compact(_), do: "0"

  def commas(n) when is_integer(n) and n >= 0 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def commas(n) when is_integer(n), do: "-" <> commas(-n)
  def commas(_), do: "0"

  def pct(rate) when is_number(rate) do
    :erlang.float_to_binary(rate * 100, decimals: 1) <> "%"
  end

  def pct(_), do: "0%"

  def share(_n, total) when total in [0, nil], do: "0%"
  def share(n, total) when is_integer(n) and is_integer(total) and total > 0, do: pct(n / total)
  def share(_, _), do: "0%"

  def duration(ms) when is_integer(ms) and ms > 0 do
    s = div(ms, 1000)

    cond do
      s < 60 -> "#{s}s"
      s < 3600 -> "#{div(s, 60)}m #{rem(s, 60)}s"
      true -> "#{div(s, 3600)}h #{div(rem(s, 3600), 60)}m"
    end
  end

  def duration(_), do: "0s"

  def dim_label("width", "0-639"), do: "Phone"
  def dim_label("width", "640-1023"), do: "Tablet"
  def dim_label("width", "1024-1439"), do: "Laptop"
  def dim_label("width", "1440+"), do: "Desktop"
  def dim_label("device", "mobile"), do: "Mobile"
  def dim_label("device", "desktop"), do: "Desktop"
  def dim_label("device", "tablet"), do: "Tablet"
  def dim_label("device", "unknown"), do: "Unknown"
  def dim_label("os", "other"), do: "Other"
  def dim_label("browser", "other"), do: "Other"

  def dim_label(kind, key) when kind in ["ref", "src"] and key in ["direct", "", nil],
    do: "Direct"

  def dim_label("country", code) when is_binary(code) do
    up = String.upcase(code)
    Map.get(@countries, up, up)
  end

  def dim_label("lang", key) when is_binary(key), do: String.upcase(key)
  def dim_label(_kind, key), do: to_string(key)

  def path_steps(key) when is_binary(key), do: String.split(key, " → ", trim: true)
  def path_steps(_), do: []
end
