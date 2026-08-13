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
    <header class="sticky top-0 z-40 border-b border-base-content/8 bg-base-100/70 backdrop-blur-xl">
      <div class={[
        "mx-auto flex items-center justify-between gap-4 px-5 py-3.5 sm:px-8",
        if(@wide, do: "max-w-7xl", else: "max-w-3xl")
      ]}>
        <a href={~p"/"} class="group flex items-center gap-2.5">
          <.mark />
          <span class="font-mono text-[13px] tracking-tight">
            who<span class="text-primary">was</span>there
          </span>
        </a>

        <nav class="flex items-center gap-2">
          <a href={~p"/"} class="chip">docs</a>
          <a href={~p"/#pricing"} class="chip">pricing</a>
          <a
            href="https://github.com/whowasthere/whowasthere"
            class="chip"
            target="_blank"
            rel="noopener noreferrer"
          >
            github
          </a>
          <a href={~p"/new"} class="chip">
            <span class="text-primary">$</span> curl /new
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

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
