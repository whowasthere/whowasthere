import * as echarts from "echarts/core"
import { BarChart, LineChart, PieChart } from "echarts/charts"
import {
  GridComponent,
  LegendComponent,
  TooltipComponent,
} from "echarts/components"
import { CanvasRenderer } from "echarts/renderers"

echarts.use([BarChart, LineChart, PieChart, GridComponent, LegendComponent, TooltipComponent, CanvasRenderer])

const MONO = 'ui-monospace, "SF Mono", SFMono-Regular, "JetBrains Mono", Menlo, monospace'

const darkPalette = ["#7dd3f0", "#5eead4", "#93c5fd", "#fbbf24", "#34d399", "#c4b5fd", "#fb7185", "#94a3b8"]
const lightPalette = ["#0284c7", "#0d9488", "#2563eb", "#d97706", "#059669", "#7c3aed", "#e11d48", "#475569"]

const theme = () => {
  const dark = document.documentElement.getAttribute("data-theme") !== "light"
  return {
    dark,
    palette: dark ? darkPalette : lightPalette,
    text: dark ? "rgba(236, 242, 255, 0.88)" : "rgba(24, 32, 44, 0.88)",
    muted: dark ? "rgba(236, 242, 255, 0.42)" : "rgba(24, 32, 44, 0.45)",
    grid: dark ? "rgba(236, 242, 255, 0.08)" : "rgba(24, 32, 44, 0.08)",
    tooltipBg: dark ? "rgba(14, 18, 26, 0.94)" : "rgba(255, 255, 255, 0.96)",
    tooltipBorder: dark ? "rgba(236, 242, 255, 0.12)" : "rgba(24, 32, 44, 0.1)",
    hole: dark ? "#141820" : "#ffffff",
  }
}

const tooltipBase = (t) => ({
  backgroundColor: t.tooltipBg,
  borderColor: t.tooltipBorder,
  borderWidth: 1,
  padding: [8, 12],
  textStyle: { color: t.text, fontFamily: MONO, fontSize: 12 },
  extraCssText: "backdrop-filter: blur(10px); box-shadow: 0 12px 40px rgba(0,0,0,.28);",
})

const hexAlpha = (hex, a) => {
  const n = hex.replace("#", "")
  const r = parseInt(n.slice(0, 2), 16)
  const g = parseInt(n.slice(2, 4), 16)
  const b = parseInt(n.slice(4, 6), 16)
  return `rgba(${r}, ${g}, ${b}, ${a})`
}

const lineOption = (payload, t) => {
  const labels = payload.labels || []
  const series = payload.series || []
  const few = labels.length <= 32

  return {
    color: t.palette,
    animationDuration: 450,
    animationDurationUpdate: 280,
    tooltip: { trigger: "axis", ...tooltipBase(t) },
    legend: {
      show: series.length > 1,
      top: 0,
      right: 0,
      icon: "roundRect",
      itemWidth: 10,
      itemHeight: 6,
      textStyle: { color: t.muted, fontFamily: MONO, fontSize: 11 },
    },
    grid: { left: 6, right: 10, top: series.length > 1 ? 32 : 16, bottom: 4, containLabel: true },
    xAxis: {
      type: "category",
      data: labels,
      boundaryGap: false,
      axisTick: { show: false },
      axisLine: { lineStyle: { color: t.grid } },
      axisLabel: { color: t.muted, fontFamily: MONO, fontSize: 10, hideOverlap: true },
    },
    yAxis: {
      type: "value",
      minInterval: 1,
      splitLine: { lineStyle: { color: t.grid, type: "dashed" } },
      axisLabel: { color: t.muted, fontFamily: MONO, fontSize: 10 },
    },
    series: series.map((s, i) => ({
      name: s.name,
      type: "line",
      smooth: 0.22,
      showSymbol: few,
      symbol: "circle",
      symbolSize: 7,
      z: series.length - i,
      lineStyle: {
        width: i === 0 ? 2.6 : 2,
        type: s.dashed ? "dashed" : "solid",
      },
      areaStyle:
        i === 0
          ? {
              color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
                { offset: 0, color: hexAlpha(t.palette[0], 0.38) },
                { offset: 1, color: hexAlpha(t.palette[0], 0.02) },
              ]),
            }
          : undefined,
      data: s.data || [],
    })),
  }
}

const barOption = (payload, t) => {
  const items = payload.items || []
  return {
    color: t.palette,
    animationDuration: 450,
    animationDurationUpdate: 280,
    tooltip: { trigger: "axis", axisPointer: { type: "shadow" }, ...tooltipBase(t) },
    grid: { left: 6, right: 8, top: 18, bottom: 4, containLabel: true },
    xAxis: {
      type: "category",
      data: items.map((i) => i.name),
      axisTick: { show: false },
      axisLine: { lineStyle: { color: t.grid } },
      axisLabel: {
        color: t.muted,
        fontFamily: MONO,
        fontSize: 10,
        hideOverlap: true,
        rotate: items.some((i) => String(i.name).length > 8) ? 28 : 0,
      },
    },
    yAxis: {
      type: "value",
      minInterval: 1,
      splitLine: { lineStyle: { color: t.grid, type: "dashed" } },
      axisLabel: { color: t.muted, fontFamily: MONO, fontSize: 10 },
    },
    series: [
      {
        type: "bar",
        barMaxWidth: 44,
        data: items.map((item, i) => ({
          value: item.value,
          itemStyle: {
            color: t.palette[i % t.palette.length],
            borderRadius: [6, 6, 2, 2],
          },
        })),
      },
    ],
  }
}

const pieOption = (payload, t) => {
  const items = payload.items || []
  const empty = items.length === 0 || items.every((i) => !i.value)

  return {
    color: t.palette,
    animationDuration: 450,
    animationDurationUpdate: 280,
    tooltip: { trigger: "item", formatter: "{b}<br/>{c} · {d}%", ...tooltipBase(t) },
    legend: {
      bottom: 0,
      type: "scroll",
      itemWidth: 8,
      itemHeight: 8,
      textStyle: { color: t.muted, fontFamily: MONO, fontSize: 11 },
    },
    series: [
      {
        type: "pie",
        radius: ["48%", "72%"],
        center: ["50%", "44%"],
        stillShowZeroSum: false,
        avoidLabelOverlap: true,
        itemStyle: {
          borderColor: t.dark ? "#161b24" : "#f7f8fa",
          borderWidth: 2,
          borderRadius: 5,
        },
        label: { show: false },
        emphasis: {
          scaleSize: 7,
          label: { show: true, color: t.text, fontFamily: MONO, fontSize: 12, fontWeight: 500 },
        },
        data: empty ? [] : items,
      },
    ],
  }
}

const optionFor = (payload) => {
  const t = theme()
  switch (payload?.type) {
    case "bar":
      return barOption(payload, t)
    case "pie":
      return pieOption(payload, t)
    default:
      return lineOption(payload, t)
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
  hook.chart.setOption(optionFor(payload), true)
  hook.chart.resize()
}

const parsePayload = (el) => {
  try {
    return JSON.parse(el.dataset.chart || "{}")
  } catch {
    return {}
  }
}
