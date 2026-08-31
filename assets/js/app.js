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
  const label = button.dataset.label || "Copy"
  try {
    await navigator.clipboard.writeText(text)
    button.textContent = "Copied"
  } catch {
    button.textContent = "Copy failed"
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
    button.textContent = "Copy"
    button.addEventListener("click", () => {
      const code = pre.querySelector("code") || pre
      copyFrom(button, code.innerText.trim())
    })

    pre.appendChild(button)
  })

  document.querySelectorAll("[data-copy-target]").forEach(button => {
    if (button.dataset.copyBound) return
    button.dataset.copyBound = "1"
    button.dataset.label = button.textContent.trim() || "Copy"
    button.addEventListener("click", () => {
      const target = document.getElementById(button.dataset.copyTarget)
      if (!target) return
      const code = target.querySelector("code") || target
      copyFrom(button, code.innerText.trim())
    })
  })
}

const LAST_SITE = "wwt:last-site"
const PAYMENT_STEP_USDC = 30
let lastIssued = null
let paymentQrRender = 0

const fillCode = (id, text) => {
  const el = document.getElementById(id)
  if (!el || !text) return
  const code = el.querySelector("code") || el
  code.textContent = text
}

const planStatus = (plan, until) => {
  switch (plan) {
    case "paid":
      return until ? `Paid through ${until}` : "Paid"
    case "comp":
      return until ? `Complimentary access through ${until}` : "Complimentary access"
    case "trial":
      return until ? `Free trial ends ${until}` : "Free trial"
    default:
      return plan || ""
  }
}

const paymentStatus = (data, checked = false) => {
  const status = document.getElementById("start-pay-status")
  if (!status) return

  const until = data.expires ? String(data.expires).slice(0, 10) : ""
  if (data.plan === "paid" || data.plan === "comp") {
    status.dataset.state = "paid"
    status.textContent = planStatus(data.plan, until)
  } else {
    status.dataset.state = "waiting"
    status.textContent = checked
      ? "No confirmed USDC payment yet. Try again once the transfer has been confirmed."
      : planStatus(data.plan, until)
  }
}

const drawPaymentQr = async (canvas, uri) => {
  const render = ++paymentQrRender
  try {
    const {drawQr} = await import("./qr")
    if (render !== paymentQrRender) return
    drawQr(canvas, uri)
    canvas.hidden = false
  } catch {
    if (render === paymentQrRender) canvas.hidden = true
  }
}

const selectedPaymentAmount = data => {
  const amount = Number(data.selected_amount_usdc || data.amount_usdc)
  return Number.isSafeInteger(amount) && amount >= PAYMENT_STEP_USDC && amount % PAYMENT_STEP_USDC === 0
    ? amount
    : PAYMENT_STEP_USDC
}

const solanaPayForAmount = (uri, amount) => {
  try {
    const payment = new URL(uri)
    payment.searchParams.set("amount", String(amount))
    return payment.toString()
  } catch {
    return uri
  }
}

// Safari rejects `a.href = "solana:…"` (TypeError: pattern). setAttribute works.
const setAnchorHref = (el, href) => {
  if (!el || !href) return
  try {
    el.href = href
  } catch {
    el.setAttribute("href", href)
  }
}

const showIssued = (data, checked = false) => {
  lastIssued = data
  fillCode("start-snippet", data.snippet)
  fillCode("start-dash", data.dash)
  fillCode("start-pay", data.pay_url)
  fillCode("start-deposit", data.deposit)

  const link = document.getElementById("start-dash-open")
  if (link && data.dash) {
    setAnchorHref(link, data.dash)
    link.hidden = false
  }

  const payment = document.getElementById("start-payment")
  const paymentEmpty = document.getElementById("start-payment-empty")
  const payLink = document.getElementById("start-pay-open")
  const walletLink = document.getElementById("start-wallet-open")
  const amount = document.getElementById("start-pay-amount")
  const less = document.getElementById("start-pay-less")
  const network = document.getElementById("start-pay-network")
  const qr = document.getElementById("start-pay-qr")
  if (payLink && data.pay_url) {
    setAnchorHref(payLink, data.pay_url)
    payLink.hidden = false
  }
  if (payment && data.pay_url && data.deposit) {
    const selectedAmount = selectedPaymentAmount(data)
    const paymentUri = solanaPayForAmount(data.solana_pay, selectedAmount)
    lastIssued.selected_amount_usdc = selectedAmount
    payment.hidden = false
    if (paymentEmpty) paymentEmpty.hidden = true
    if (walletLink && paymentUri) {
      setAnchorHref(walletLink, paymentUri)
      walletLink.hidden = false
    }
    if (amount) amount.textContent = `${selectedAmount} USDC`
    if (less) less.disabled = selectedAmount === PAYMENT_STEP_USDC
    if (network) network.textContent = `Solana · ${data.network || "mainnet-beta"}`
    if (qr && paymentUri) drawPaymentQr(qr, paymentUri)
    const cardBtn = document.getElementById("start-pay-card")
    if (cardBtn) {
      const stripeOn =
        data.stripe === true ||
        data.stripe === "true" ||
        document.getElementById("start")?.dataset.stripe === "true"
      cardBtn.hidden = !stripeOn
    }
    paymentStatus(data, checked)
  }

  const meta = document.getElementById("start-meta")
  if (meta) {
    const site = meta.querySelector("[data-site]")
    const plan = meta.querySelector("[data-plan]")
    if (site) site.textContent = data.site || ""
    if (plan) {
      const until = data.expires ? String(data.expires).slice(0, 10) : ""
      plan.textContent = planStatus(data.plan, until)
    }
    meta.hidden = !data.site
  }
}

const bootStart = () => {
  const root = document.getElementById("start")
  if (!root) return

  const paymentCap = new URLSearchParams(window.location.search).get("pay")

  if (!paymentCap) {
    try {
      const saved = sessionStorage.getItem(LAST_SITE)
      if (saved) showIssued(JSON.parse(saved))
    } catch {
      /* ignore */
    }
  } else {
    const paymentEmpty = document.getElementById("start-payment-empty")
    if (paymentEmpty) paymentEmpty.textContent = "Loading payment options…"

    const loadPaymentProfile = async () => {
      try {
        const url = new URL(root.dataset.paymentUrl || "/pay", window.location.origin)
        url.searchParams.set("pay", paymentCap)
        url.searchParams.set("format", "json")
        const res = await fetch(url, {headers: {Accept: "application/json"}})
        const data = await res.json()
        if (!res.ok) throw new Error(data.error || "Couldn’t load the payment profile.")

        showIssued(data)
        try { sessionStorage.setItem(LAST_SITE, JSON.stringify(data)) } catch { /* ignore */ }
      } catch (error) {
        if (paymentEmpty) {
          paymentEmpty.textContent = error.message || "Couldn’t load the payment profile."
        }
      }
    }

    loadPaymentProfile()
  }

  const createBtn = document.getElementById("start-create")
  createBtn?.addEventListener("click", async () => {
    const url = root.dataset.newUrl
    if (!url) return
    createBtn.disabled = true
    createBtn.textContent = "Creating…"
    try {
      const res = await fetch(url, {headers: {Accept: "application/json"}})
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || "failed")
      showIssued(data)
      try { sessionStorage.setItem(LAST_SITE, JSON.stringify(data)) } catch { /* ignore */ }
      createBtn.textContent = "Create another"
    } catch {
      createBtn.textContent = "Try again"
      setTimeout(() => (createBtn.textContent = "Create a site"), 1800)
    } finally {
      createBtn.disabled = false
    }
  })

  const changePaymentAmount = delta => {
    if (!lastIssued?.solana_pay) return
    const current = selectedPaymentAmount(lastIssued)
    const next = Math.max(PAYMENT_STEP_USDC, current + delta)
    if (next === current) return

    showIssued({...lastIssued, selected_amount_usdc: next})
    try { sessionStorage.setItem(LAST_SITE, JSON.stringify(lastIssued)) } catch { /* ignore */ }
  }

  document.getElementById("start-pay-less")?.addEventListener("click", () => {
    changePaymentAmount(-PAYMENT_STEP_USDC)
  })
  document.getElementById("start-pay-more")?.addEventListener("click", () => {
    changePaymentAmount(PAYMENT_STEP_USDC)
  })

  const cardBtn = document.getElementById("start-pay-card")
  const cardLabel = cardBtn?.textContent?.trim() || "Pay by card"
  cardBtn?.addEventListener("click", async () => {
    if (!lastIssued?.pay || !root.dataset.checkoutUrl) return

    cardBtn.disabled = true
    cardBtn.textContent = "Redirecting…"
    const status = document.getElementById("start-pay-status")
    const csrf = document.querySelector("meta[name='csrf-token']")?.content

    try {
      const body = new URLSearchParams({
        pay: lastIssued.pay,
        amount: String(selectedPaymentAmount(lastIssued))
      })
      const res = await fetch(root.dataset.checkoutUrl, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/x-www-form-urlencoded",
          ...(csrf ? {"x-csrf-token": csrf} : {})
        },
        body
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || "checkout failed")
      if (!data.url) throw new Error("checkout url missing")
      window.location.href = data.url
    } catch (error) {
      if (status) {
        status.dataset.state = "error"
        status.textContent = error.message || "Couldn’t start the card payment."
      }
      cardBtn.textContent = cardLabel
      cardBtn.disabled = false
    }
  })

  const checkBtn = document.getElementById("start-pay-check")
  const checkLabel = checkBtn?.textContent?.trim() || "Check USDC payment"
  checkBtn?.addEventListener("click", async () => {
    if (!lastIssued?.pay) return

    checkBtn.disabled = true
    checkBtn.textContent = "Checking…"
    const status = document.getElementById("start-pay-status")

    try {
      const url = new URL("/pay", window.location.origin)
      url.searchParams.set("pay", lastIssued.pay)
      url.searchParams.set("format", "json")
      const res = await fetch(url, {headers: {Accept: "application/json"}})
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || "failed")

      const payUrl =
        lastIssued.pay_url || `${window.location.origin}/pay?pay=${encodeURIComponent(data.pay || lastIssued.pay)}`
      const updated = {
        ...lastIssued,
        ...data,
        pay: data.pay || lastIssued.pay,
        pay_url: payUrl,
        site: lastIssued.site,
        dash: lastIssued.dash,
        snippet: lastIssued.snippet,
        key: lastIssued.key,
        selected_amount_usdc: lastIssued.selected_amount_usdc
      }
      showIssued(updated, true)
      try { sessionStorage.setItem(LAST_SITE, JSON.stringify(updated)) } catch { /* ignore */ }
      checkBtn.textContent =
        data.plan === "paid" || data.plan === "comp" ? "Payment confirmed" : checkLabel
    } catch (error) {
      if (status) {
        status.dataset.state = "error"
        status.textContent = error.message || "Payment check failed."
      }
      checkBtn.textContent = "Try again"
    } finally {
      checkBtn.disabled = false
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
