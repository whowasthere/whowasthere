defmodule WhoWasThere.Readme do
  @moduledoc false

  @path Path.expand("../../README.md", __DIR__)
  @external_resource @path
  @source File.read!(@path)

  def html(base_url) when is_binary(base_url) do
    @source
    |> String.replace("http://localhost:4000", String.trim_trailing(base_url, "/"))
    |> String.replace("https://YOUR_HOST", String.trim_trailing(base_url, "/"))
    |> MDEx.to_html!(extension: [table: true, strikethrough: true, autolink: true])
    |> anchor_headings()
  end

  defp anchor_headings(html) do
    Regex.replace(~r/<h2>([^<]+)<\/h2>/, html, fn _, title ->
      id =
        title
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/, "-")
        |> String.trim("-")

      ~s(<h2 id="#{id}">#{title}</h2>)
    end)
  end
end
