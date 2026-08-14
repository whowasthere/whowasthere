// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/whowasthere"
import topbar from "../vendor/topbar"

const Chart = {
  mounted() {
    this.alive = true
    import("./charts").then(({bootChart}) => {
      if (!this.alive) return
      bootChart(this)
    })
  },
  destroyed() {
    this.alive = false
    this.ro?.disconnect()
    this.mo?.disconnect()
    this.chart?.dispose()
    this.chart = null
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Chart},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#6ec3f5"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

const copyFrom = async (button, text) => {
  const label = button.dataset.label || "copy"
  try {
    await navigator.clipboard.writeText(text)
    button.textContent = "copied"
  } catch {
    button.textContent = "failed"
  }
  setTimeout(() => (button.textContent = label), 1500)
}

const addCopyButtons = () => {
  document.querySelectorAll(".readme pre").forEach(pre => {
    if (pre.dataset.copyable) return
    pre.dataset.copyable = "1"

    const button = document.createElement("button")
    button.type = "button"
    button.className = "copy-btn"
    button.textContent = "copy"
    button.addEventListener("click", () => {
      const code = pre.querySelector("code") || pre
      copyFrom(button, code.innerText.trim())
    })

    pre.appendChild(button)
  })

  document.querySelectorAll("[data-copy-target]").forEach(button => {
    if (button.dataset.copyBound) return
    button.dataset.copyBound = "1"
    button.dataset.label = button.textContent.trim() || "copy"
    button.addEventListener("click", () => {
      const target = document.getElementById(button.dataset.copyTarget)
      if (!target) return
      const code = target.querySelector("code") || target
      copyFrom(button, code.innerText.trim())
    })
  })
}

const LAST_SITE = "wwt:last-site"

const fillCode = (id, text) => {
  const el = document.getElementById(id)
  if (!el || !text) return
  const code = el.querySelector("code") || el
  code.textContent = text
}

const showIssued = (data) => {
  fillCode("start-snippet", data.snippet)
  fillCode("start-pixel", data.pixel)
  fillCode("start-event", data.event)
  fillCode("start-dash", data.dash)
  fillCode("start-pay", data.pay_url)
  fillCode("start-deposit", data.deposit)

  const link = document.getElementById("start-dash-open")
  if (link && data.dash) {
    link.href = data.dash
    link.hidden = false
  }

  const payment = document.getElementById("start-payment")
  const payLink = document.getElementById("start-pay-open")
  if (payment && data.pay_url && data.deposit) {
    payment.hidden = false
    if (payLink) payLink.href = data.pay_url
  }

  const meta = document.getElementById("start-meta")
  if (meta) {
    const site = meta.querySelector("[data-site]")
    const plan = meta.querySelector("[data-plan]")
    if (site) site.textContent = data.site || ""
    if (plan) {
      const until = data.expires ? String(data.expires).slice(0, 10) : ""
      plan.textContent = until ? `${data.plan} until ${until}` : (data.plan || "")
    }
    meta.hidden = false
  }
}

const bootStart = () => {
  const root = document.getElementById("start")
  if (!root) return

  try {
    const saved = sessionStorage.getItem(LAST_SITE)
    if (saved) showIssued(JSON.parse(saved))
  } catch {
    /* ignore */
  }

  const createBtn = document.getElementById("start-create")
  createBtn?.addEventListener("click", async () => {
    const url = root.dataset.newUrl
    if (!url) return
    createBtn.disabled = true
    createBtn.textContent = "creating…"
    try {
      const res = await fetch(url, {headers: {Accept: "application/json"}})
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || "failed")
      showIssued(data)
      try { sessionStorage.setItem(LAST_SITE, JSON.stringify(data)) } catch { /* ignore */ }
      createBtn.textContent = "create another"
    } catch {
      createBtn.textContent = "failed"
      setTimeout(() => (createBtn.textContent = "Create a site"), 1800)
    } finally {
      createBtn.disabled = false
    }
  })
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => {
    addCopyButtons()
    bootStart()
  })
} else {
  addCopyButtons()
  bootStart()
}

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
