defmodule WhoWasThere.UA do
  @moduledoc false

  @bots [
    "bot",
    "crawler",
    "spider",
    "crawling",
    "facebookexternal",
    "preview",
    "slurp",
    "curl/",
    "wget/",
    "python-requests",
    "httpie",
    "ahrefs",
    "semrush",
    "pingdom",
    "headless",
    "phantom",
    "puppeteer",
    "playwright",
    "lighthouse",
    "bytespider",
    "yandex",
    "baidu",
    "scrapy",
    "axios/",
    "node-fetch",
    "go-http-client",
    "monitor",
    "uptime",
    "healthcheck"
  ]

  def bot?(ua) when ua in [nil, ""], do: true

  def bot?(ua) do
    down = String.downcase(ua)
    Enum.any?(@bots, &String.contains?(down, &1))
  end

  def parse(ua) when ua in [nil, ""] do
    %{device: "unknown", os: "unknown", browser: "unknown"}
  end

  def parse(ua) do
    %{device: device(ua), os: os(ua), browser: browser(ua)}
  end

  defp device(ua) do
    cond do
      ua =~ ~r/iPad|Tablet|PlayBook/i -> "tablet"
      ua =~ ~r/Mobile|Android|iPhone|webOS|IEMobile/i -> "mobile"
      true -> "desktop"
    end
  end

  defp os(ua) do
    cond do
      ua =~ ~r/Android/i -> "Android"
      ua =~ ~r/iPhone|iPad|iPod/i -> "iOS"
      ua =~ ~r/Windows/i -> "Windows"
      ua =~ ~r/Mac OS X|Macintosh/i -> "macOS"
      ua =~ ~r/CrOS/i -> "ChromeOS"
      ua =~ ~r/Linux/i -> "Linux"
      true -> "other"
    end
  end

  defp browser(ua) do
    cond do
      ua =~ ~r/Edg\//i -> "Edge"
      ua =~ ~r/OPR\/|Opera/i -> "Opera"
      ua =~ ~r/SamsungBrowser/i -> "Samsung"
      ua =~ ~r/Firefox|FxiOS/i -> "Firefox"
      ua =~ ~r/Chrome|CriOS/i -> "Chrome"
      ua =~ ~r/Safari/i -> "Safari"
      true -> "other"
    end
  end
end
