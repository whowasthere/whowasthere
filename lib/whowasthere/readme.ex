defmodule WhoWasThere.Readme do
  @moduledoc false

  @path Path.expand("../../README.md", __DIR__)
  @external_resource @path
  @source File.read!(@path)
  @hosted "https://whowasthere.fyi"

  def html(base_url, opts \\ []) when is_binary(base_url) do
    base = String.trim_trailing(base_url, "/")
    {hosted, self_host} = split_self_host(@source)

    hosted =
      hosted
      |> maybe_omit_intro(Keyword.get(opts, :omit_intro, false))
      |> rewrite_hosted(base)

    (hosted <> self_host)
    |> MDEx.to_html!(extension: [table: true, strikethrough: true, autolink: true])
    |> anchor_headings()
  end

  defp split_self_host(source) do
    case String.split(source, "\n## Self-host\n", parts: 2) do
      [hosted, rest] -> {hosted, "\n## Self-host\n" <> rest}
      [whole] -> {whole, ""}
    end
  end

  defp maybe_omit_intro(markdown, false), do: markdown

  defp maybe_omit_intro(markdown, true) do
    case String.split(markdown, "\n## ", parts: 2) do
      [_, rest] -> "## " <> rest
      [whole] -> whole
    end
  end

  defp rewrite_hosted(markdown, base) do
    markdown
    |> String.replace("https://YOUR_HOST", base)
    |> String.replace("http://YOUR_HOST", base)
    |> String.replace(@hosted, base)
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
