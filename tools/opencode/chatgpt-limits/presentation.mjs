function clock(timestamp) {
  const date = new Date(timestamp * 1000)
  return `${date.getHours()}:${String(date.getMinutes()).padStart(2, "0")}`
}

export function formatDeviation(seconds) {
  const sign = seconds < 0 ? "-" : "+"
  seconds = Math.abs(seconds)
  if (seconds < 60) return "0м"
  if (seconds >= 3600) return `${sign}${Math.trunc(seconds / 3600)}ч${String(Math.trunc(seconds % 3600 / 60)).padStart(2, "0")}м`
  return `${sign}${Math.trunc(seconds / 60)}м`
}

export function formatDays(seconds) {
  const tenths = Math.trunc(Math.abs(seconds) * 10 / 86400)
  if (tenths === 0) return "0.0д"
  return `${seconds < 0 ? "-" : "+"}${Math.trunc(tenths / 10)}.${tenths % 10}д`
}

export function limitSegments(value, now = Date.now(), width = 100) {
  if (width < 60) return []
  if (!value) return [{ text: "ChatGPT limits: loading", color: "dim" }]
  if (value.status === "sign-in") return [{ text: "ChatGPT limits: sign in", color: "dim" }]
  if (value.status === "unsupported") return [{ text: "ChatGPT limits: legacy sign-in required", color: "dim" }]
  if (value.status !== "ready" || now - value.checkedAt > 120_000) {
    return [{ text: "ChatGPT limits: unavailable", color: "dim" }]
  }
  const seconds = Math.floor(now / 1000)
  const segments = []
  for (const window of value.windows) {
    const used = Math.floor(window.used)
    if (window.seconds === 18000) {
      const reset = window.resetsAt > seconds + 18600 ? null : window.resetsAt
      if (reset != null && reset <= seconds) {
        segments.push({ text: "5h: refreshing", color: "dim" })
        continue
      }
      if (used >= 100) {
        segments.push({ text: `5h you lose${reset == null ? "" : ` (${clock(reset)})`}`, color: "red" })
        continue
      }
      let color = "dim"
      if (window.trend) color = { up: "green", down: "red", flat: "cyan" }[window.trend]
      else if (window.dev != null) color = window.dev > 300 ? "green" : window.dev < -300 ? "red" : "cyan"
      let text = `5h ${used}%`
      const showDeviation = width >= 100 && window.dev != null && window.dev < 3600
      if (showDeviation) text += ` ${formatDeviation(window.dev)}`
      if (reset != null) {
        const eta = showDeviation && window.dev < 0 ? ` -> ${clock(reset + window.dev)}` : ""
        text += ` (${clock(reset)}${eta})`
      }
      segments.push({ text, color })
    } else if (window.seconds === 604800 && width >= 80) {
      let text = `7d ${used}%`
      let color = "dim"
      if (window.resetsAt != null) {
        const elapsed = 604800 - (window.resetsAt - seconds)
        if (elapsed >= 43200) {
          const dev = elapsed - Math.trunc(used * 604800 / 100)
          if (dev < 0) {
            text += ` ${formatDays(dev)}`
            if (dev < -43200) color = "red"
          }
        }
      }
      segments.push({ text, color })
    }
  }
  return segments
}

export function formatUsage(value, now = Date.now(), width = 100) {
  return limitSegments(value, now, width).map((segment) => segment.text).join(" · ")
}
