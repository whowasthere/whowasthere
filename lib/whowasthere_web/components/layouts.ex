defmodule WhoWasThereWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use WhoWasThereWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  slot :inner_block, required: true

  attr :wide, :boolean, default: false, doc: "use the full dashboard width"

  def shell(assigns) do
    ~H"""
    <header class="site-header sticky top-0 z-40">
      <div class={[
        "mx-auto flex items-center justify-between gap-4 px-5 py-3.5 sm:px-8",
        if(@wide, do: "max-w-7xl", else: "max-w-3xl")
      ]}>
        <a href={~p"/"} class="group flex items-center gap-2.5">
          <.mark />
          <span class="text-[14px] font-semibold tracking-tight">
            who<span class="text-primary">was</span>there
          </span>
        </a>

        <nav class="site-nav" aria-label="Primary navigation">
          <a href={~p"/#readme"} class="site-nav-link">docs</a>
          <a href={~p"/#pricing"} class="site-nav-link">pricing</a>
          <a href={~p"/#self-host"} class="site-nav-link">self-host</a>
          <a
            href="https://github.com/whowasthere/whowasthere"
            class="site-nav-link"
            target="_blank"
            rel="noopener noreferrer"
          >
            github
          </a>
        </nav>
      </div>
    </header>

    <main class={[
      "mx-auto px-5 py-10 sm:px-8 sm:py-14",
      if(@wide, do: "max-w-7xl", else: "max-w-3xl")
    ]}>
      {render_slot(@inner_block)}
    </main>

    <footer class={[
      "mx-auto px-5 pt-4 pb-12 sm:px-8",
      if(@wide, do: "max-w-7xl", else: "max-w-3xl")
    ]}>
      <div class="rule mb-4" />
      <p class="eyebrow">no cookies · no raw hits · aggregates only</p>
    </footer>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The logo: a 3x3 sensor grid with one cell lit.
  """
  def mark(assigns) do
    ~H"""
    <span class="grid size-[18px] grid-cols-3 grid-rows-3 gap-[2px]">
      <span
        :for={i <- 0..8}
        class={[
          "rounded-[1px] transition-colors duration-500",
          if(i == 4,
            do: "bg-primary group-hover:bg-accent",
            else: "bg-base-content/25 group-hover:bg-base-content/40"
          )
        ]}
      />
    </span>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
