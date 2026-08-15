defmodule WhoWasThere.MailerTest do
  use ExUnit.Case, async: false

  alias WhoWasThere.Mailer

  @config_keys [
    :mailer,
    :mail_from,
    :postal_url,
    :postal_api_key,
    :postal_request
  ]

  setup do
    previous =
      Map.new(@config_keys, fn key ->
        {key, Application.fetch_env(:whowasthere, key)}
      end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:whowasthere, key, value)
        {key, :error} -> Application.delete_env(:whowasthere, key)
      end)
    end)

    :ok
  end

  test "sends plain text mail through a Postal server API" do
    requests = start_supervised!({Agent, fn -> [] end})

    Application.put_env(:whowasthere, :mailer, :postal)
    Application.put_env(:whowasthere, :mail_from, "Who Was There <noreply@example.com>")
    Application.put_env(:whowasthere, :postal_url, "https://postal.example.com")
    Application.put_env(:whowasthere, :postal_api_key, "server-api-key")

    Application.put_env(:whowasthere, :postal_request, fn url, options ->
      Agent.update(requests, &[{url, options} | &1])
      {:ok, %Req.Response{status: 200, body: %{"status" => "success"}}}
    end)

    assert :ok = Mailer.send("owner@example.net", "Trial ending", "Renew now")

    assert [{url, options}] = Agent.get(requests, & &1)
    assert url == "https://postal.example.com/api/v1/send/message"

    assert options[:json] == %{
             from: "noreply@example.com",
             to: ["owner@example.net"],
             subject: "Trial ending",
             plain_body: "Renew now"
           }

    assert {"x-server-api-key", "server-api-key"} in options[:headers]
  end
end
