defmodule WhoWasThere.Mailer do
  @moduledoc false

  require Logger

  def send(nil, _subject, _body), do: :ok
  def send("", _subject, _body), do: :ok

  def send(to, subject, body) when is_binary(to) do
    case Application.get_env(:whowasthere, :mailer, :log) do
      :log ->
        Logger.info("mail to=#{to} subject=#{subject}\n#{body}")
        :ok

      :mailbox ->
        box = Application.get_env(:whowasthere, :mailbox, [])

        Application.put_env(:whowasthere, :mailbox, [
          %{to: to, subject: subject, body: body} | box
        ])

        :ok

      :resend ->
        resend(to, subject, body)

      :postal ->
        postal(to, subject, body)

      fun when is_function(fun, 3) ->
        fun.(to, subject, body)
    end
  end

  defp resend(to, subject, body) do
    key = System.get_env("RESEND_API_KEY")

    from =
      Application.get_env(:whowasthere, :mail_from, "Who Was There <noreply@whowasthere.dev>")

    if is_nil(key) or key == "" do
      Logger.warning("RESEND_API_KEY missing; mail not sent")
      :ok
    else
      payload = %{from: from, to: [to], subject: subject, text: body}

      case Req.post("https://api.resend.com/emails",
             json: payload,
             headers: [{"authorization", "Bearer #{key}"}]
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        other ->
          Logger.warning("resend failed: #{inspect(other)}")
          :ok
      end
    end
  end

  defp postal(to, subject, body) do
    url = Application.get_env(:whowasthere, :postal_url)
    key = Application.get_env(:whowasthere, :postal_api_key)

    from =
      Application.get_env(:whowasthere, :mail_from, "Who Was There <noreply@whowasthere.dev>")
      |> from_address()

    if url in [nil, ""] or key in [nil, ""] do
      Logger.warning("Postal configuration missing; mail not sent")
      :ok
    else
      payload = %{from: from, to: [to], subject: subject, plain_body: body}

      options = [
        json: payload,
        headers: [{"x-server-api-key", key}]
      ]

      result =
        case Application.get_env(:whowasthere, :postal_request) do
          fun when is_function(fun, 2) -> fun.(url <> "/api/v1/send/message", options)
          _ -> Req.post(url <> "/api/v1/send/message", options)
        end

      case result do
        {:ok, %{status: status, body: %{"status" => "success"}}} when status in 200..299 ->
          :ok

        other ->
          Logger.warning("postal failed: #{inspect(other)}")
          :ok
      end
    end
  end

  defp from_address(from) do
    case Regex.run(~r/<([^<>]+)>\s*$/, from) do
      [_, address] -> String.trim(address)
      _ -> String.trim(from)
    end
  end
end
