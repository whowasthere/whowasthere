defmodule WhoWasThere.CollectorTest do
  use WhoWasThere.DataCase

  alias WhoWasThere.{Analytics, Collector}

  @ua "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0.0.0 Safari/537.36"

  setup do
    Collector.reset!()
    :ok
  end

  test "aggregates pageviews and uniques without storing raw events" do
    {:ok, _} = Collector.create_site("testsite1", "example.com")

    Enum.each(1..3, fn i ->
      ingest(%{site_id: "testsite1", ip: "1.1.1.#{i}", path: "/home"})
    end)

    ingest(%{site_id: "testsite1", ip: "1.1.1.1", path: "/about"})

    Collector.ping()
    report = Analytics.report("testsite1", :today)

    assert report.pageviews == 4
    assert report.uniques == 3
    assert Enum.any?(report.dims["page"], &(&1.key == "/home" and &1.pageviews == 3))
  end

  test "drops bots" do
    {:ok, _} = Collector.create_site("testsite2", nil)
    ingest(%{site_id: "testsite2", ua: "curl/8.0", path: "/"})
    Collector.ping()
    assert Analytics.report("testsite2", :today).pageviews == 0
  end

  test "drops events for unknown sites" do
    ingest(%{site_id: "ghostsite", path: "/"})
    Collector.ping()
    assert Analytics.report("ghostsite", :today).pageviews == 0
  end

  test "locks host after first visit" do
    {:ok, _} = Collector.create_site("testsite3", "mine.com")
    ingest(%{site_id: "testsite3", host: "mine.com", path: "/"})
    ingest(%{site_id: "testsite3", host: "evil.com", path: "/hack"})
    Collector.ping()
    report = Analytics.report("testsite3", :today)
    assert report.pageviews == 1
    refute Enum.any?(report.dims["page"], &(&1.key == "/hack"))
  end

  test "records page transitions within a session" do
    {:ok, _} = Collector.create_site("journeys1", "example.com")
    t = System.system_time(:millisecond)

    ingest(%{site_id: "journeys1", ip: "1.2.3.4", path: "/home", at: t})
    ingest(%{site_id: "journeys1", ip: "1.2.3.4", path: "/pricing", at: t + 1_000})
    ingest(%{site_id: "journeys1", ip: "1.2.3.4", path: "/checkout", at: t + 2_000})
    ingest(%{site_id: "journeys1", ip: "1.2.3.4", path: "/home", at: t + 40 * 60 * 1000})

    Collector.ping()
    report = Analytics.report("journeys1", :today)

    assert Enum.any?(report.dims["entry"], &(&1.key == "/home"))
    assert Enum.any?(report.dims["flow"], &(&1.key == "/home → /pricing"))
    assert Enum.any?(report.dims["flow"], &(&1.key == "/pricing → /checkout"))
    assert Enum.any?(report.dims["chain"], &(&1.key == "/home → /pricing → /checkout"))
    refute Enum.any?(report.dims["chain"], &(&1.key == "/home → /pricing"))
    assert Enum.any?(report.dims["exit"], &(&1.key == "/checkout"))
    refute Enum.any?(report.dims["flow"], &(&1.key == "/checkout → /home"))
    refute Enum.any?(report.dims["chain"], &String.contains?(&1.key, "/checkout → /home"))
  end

  test "includes clicks in the session journey" do
    {:ok, _} = Collector.create_site("journeys2", "example.com")
    t = System.system_time(:millisecond)

    ingest(%{site_id: "journeys2", ip: "5.5.5.5", path: "/home", at: t})

    ingest(%{
      site_id: "journeys2",
      ip: "5.5.5.5",
      path: "/home",
      name: "k",
      event: "Pricing",
      at: t + 500
    })

    ingest(%{site_id: "journeys2", ip: "5.5.5.5", path: "/pricing", at: t + 1_000})
    Collector.ping()
    report = Analytics.report("journeys2", :today)

    assert Enum.any?(report.dims["click"], &(&1.key == "Pricing"))

    assert Enum.any?(
             report.dims["chain"],
             &(&1.key == "/home → click:Pricing → /pricing")
           )

    refute Enum.any?(report.dims["chain"], &(&1.key == "/home → click:Pricing"))
  end

  test "counts the same finished journey twice for two sessions" do
    {:ok, _} = Collector.create_site("journeys3", "example.com")
    t = System.system_time(:millisecond)

    ingest(%{site_id: "journeys3", ip: "8.8.8.8", path: "/home", at: t})
    ingest(%{site_id: "journeys3", ip: "8.8.8.8", path: "/pricing", at: t + 1_000})
    ingest(%{site_id: "journeys3", ip: "8.8.8.8", path: "/home", at: t + 40 * 60 * 1000})

    ingest(%{
      site_id: "journeys3",
      ip: "8.8.8.8",
      path: "/pricing",
      at: t + 40 * 60 * 1000 + 1_000
    })

    ingest(%{site_id: "journeys3", ip: "8.8.8.8", path: "/x", at: t + 80 * 60 * 1000})

    Collector.ping()
    report = Analytics.report("journeys3", :today)
    row = Enum.find(report.dims["chain"], &(&1.key == "/home → /pricing"))
    assert row && row.pageviews == 2
  end

  test "keeps first UTM for the rest of the session" do
    {:ok, _} = Collector.create_site("utmsite1", "example.com")
    t = System.system_time(:millisecond)

    ingest(%{
      site_id: "utmsite1",
      ip: "1.1.1.1",
      path: "/",
      src: "twitter",
      medium: "social",
      campaign: "launch",
      at: t
    })

    ingest(%{site_id: "utmsite1", ip: "1.1.1.1", path: "/about", src: "direct", at: t + 1_000})
    Collector.ping()
    report = Analytics.report("utmsite1", :today)

    assert Enum.any?(report.dims["src"], &(&1.key == "twitter" and &1.pageviews == 2))
    assert Enum.any?(report.dims["medium"], &(&1.key == "social" and &1.pageviews == 2))
    assert Enum.any?(report.dims["campaign"], &(&1.key == "launch" and &1.pageviews == 2))
    refute Enum.any?(report.dims["src"], &(&1.key == "direct"))
  end

  defp ingest(over) do
    Collector.ingest(
      Map.merge(
        %{
          name: "v",
          path: "/",
          ref: "direct",
          src: "direct",
          event: "",
          lang: "en",
          host: "example.com",
          country: "US",
          ua: @ua,
          ip: "9.9.9.9"
        },
        over
      )
    )
  end
end
