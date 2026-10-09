import * as echarts from "echarts/core"
import { BarChart, LineChart } from "echarts/charts"
import { GridComponent, TooltipComponent } from "echarts/components"
import { CanvasRenderer } from "echarts/renderers"

echarts.use([BarChart, LineChart, GridComponent, TooltipComponent, CanvasRenderer])

const UI_FONT = '"Avenir Next", Avenir, -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", Arial, sans-serif'
const MONO = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace'

// Mirrors --color-primary and the ink tokens in app.css for each theme.
const theme = () => {
  const dark = document.documentElement.getAttribute("data-theme") === "dark"
  return dark
    ? {
        bar: "#5fb8ea",
        barHover: "#8fd0f5",
        line: "#e9edf5",
        text: "rgba(236, 242, 255, 0.9)",
        muted: "rgba(236, 242, 255, 0.5)",
        grid: "rgba(236, 242, 255, 0.09)",
        tooltipBg: "#1c222d",
        tooltipBorder: "rgba(236, 242, 255, 0.14)",
      }
    : {
        bar: "#1f63c6",
        barHover: "#174f9f",
        line: "#1b2433",
        text: "#1b2433",
        muted: "rgba(27, 36, 51, 0.55)",
        grid: "rgba(27, 36, 51, 0.08)",
        tooltipBg: "#ffffff",
        tooltipBorder: "rgba(27, 36, 51, 0.14)",
      }
}

const fmt = (n) => Number(n || 0).toLocaleString("en-US")

const trafficOption = (payload, t) => {
  const labels = payload.labels || []
  const series = payload.series || []

  return {
    animationDuration: 500,
    animationDurationUpdate: 300,
    tooltip: {
      trigger: "axis",
      axisPointer: { type: "shadow", shadowStyle: { color: t.grid } },
      backgroundColor: t.tooltipBg,
      borderColor: t.tooltipBorder,
      borderWidth: 1,
      padding: [10, 12],
      textStyle: { color: t.text, fontFamily: UI_FONT, fontSize: 12 },
      extraCssText: "border-radius: 8px; box-shadow: 0 8px 24px rgba(0,0,0,.14);",
      formatter: (items) => {
        const rows = items
          .map(
            (i) =>
              `<div style="display:flex;gap:16px;justify-content:space-between;align-items:center">
                 <span>${i.marker}${i.seriesName}</span>
                 <b style="font-family:${MONO};font-weight:600">${fmt(i.value)}</b>
               </div>`,
          )
          .join("")
        return `<div style="margin-bottom:6px;color:${t.muted}">${items[0]?.axisValue ?? ""}</div>${rows}`
      },
    },
    grid: { left: 4, right: 4, top: 12, bottom: 2, containLabel: true },
    xAxis: {
      type: "category",
      data: labels,
      axisTick: { show: false },
      axisLine: { lineStyle: { color: t.grid } },
      axisLabel: { color: t.muted, fontFamily: UI_FONT, fontSize: 11, hideOverlap: true, margin: 10 },
    },
    yAxis: {
      type: "value",
      minInterval: 1,
      splitNumber: 4,
      splitLine: { lineStyle: { color: t.grid } },
      axisLabel: {
        color: t.muted,
        fontFamily: MONO,
        fontSize: 10,
        formatter: (v) => (v >= 1000 ? `${v / 1000}k` : v),
      },
    },
    series: series.map((s) =>
      s.kind === "line"
        ? {
            name: s.name,
            type: "line",
            data: s.data || [],
            z: 3,
            smooth: 0.2,
            symbol: "circle",
            symbolSize: 5,
            showSymbol: labels.length <= 31,
            itemStyle: { color: t.line, borderColor: t.tooltipBg, borderWidth: 1.5 },
            lineStyle: { color: t.line, width: 2 },
          }
        : {
            name: s.name,
            type: "bar",
            data: s.data || [],
            z: 2,
            barCategoryGap: labels.length > 40 ? "18%" : "28%",
            itemStyle: { color: t.bar, borderRadius: [3, 3, 0, 0] },
            emphasis: { itemStyle: { color: t.barHover } },
          },
    ),
  }
}

export const bootChart = (hook) => {
  const canvas = hook.el.querySelector("[data-canvas]")
  hook.chart = echarts.init(canvas, null, { renderer: "canvas" })
  draw(hook, parsePayload(hook.el))

  hook.handleEvent("charts", (all) => {
    const payload = all[hook.el.id]
    if (!payload) return
    hook.el.dataset.chart = JSON.stringify(payload)
    draw(hook, payload)
  })

  hook.ro = new ResizeObserver(() => hook.chart?.resize())
  hook.ro.observe(hook.el)

  hook.mo = new MutationObserver(() => draw(hook, parsePayload(hook.el)))
  hook.mo.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] })
}

const draw = (hook, payload) => {
  if (!hook.chart) return
  hook.chart.setOption(trafficOption(payload, theme()), true)
  hook.chart.resize()
}

const parsePayload = (el) => {
  try {
    return JSON.parse(el.dataset.chart || "{}")
  } catch {
    return {}
  }
}
