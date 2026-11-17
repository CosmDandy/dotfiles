import { createHash } from "node:crypto"

const rateWindow = 900
const idleWindow = 300
const trendLag = 900
const maxAhead = 5 * 3600 + 600
const historyKeep = trendLag + 2 * rateWindow
const updates = new Map()

// Port of Claude Code's fiveHourDev: reset IDs, not percentage drops, delimit windows.
export function fiveHourForecast(state, pct100, reset, now) {
  if (reset > now + maxAhead) reset = null
  const result = () => ({ used: pct100 / 100, resetsAt: reset, dev: null, trend: "" })
  if (reset == null) return { state, ...result() }
  const previousReset = state.reset > now + maxAhead ? 0 : state.reset
  if (reset > previousReset) {
    return { state: { reset, samples: [{ ts: now, pct: pct100 }] }, ...result() }
  }

  const samples = [...state.samples]
  const last = samples.at(-1) ?? { ts: 0, pct: 0 }
  if (reset < previousReset) {
    reset = previousReset
    pct100 = last.pct
  } else if (pct100 < last.pct) {
    pct100 = last.pct
  } else if (pct100 !== last.pct || now - last.ts >= 60) {
    samples.push({ ts: now, pct: pct100 })
  }

  let baseline, first, idle, latest, previousBaseline, previousFirst, previousLatest
  for (const sample of samples) {
    if (sample.ts < now - rateWindow) {
      if (sample.ts >= now - 2 * rateWindow) baseline = sample
    } else {
      first ??= sample
      if (sample.ts < now - idleWindow) idle = sample
      latest = sample
    }
    if (sample.ts < now - trendLag - rateWindow) {
      if (sample.ts >= now - trendLag - 2 * rateWindow) previousBaseline = sample
    } else if (sample.ts <= now - trendLag) {
      previousFirst ??= sample
      previousLatest = sample
    }
  }
  baseline ??= first
  idle ??= baseline
  previousBaseline ??= previousFirst
  const nextState = {
    reset: state.reset,
    samples: samples.length > 200 ? samples.filter((sample) => sample.ts >= now - historyKeep) : samples,
  }
  const forecast = { state: nextState, ...result() }
  if (!baseline || !latest) return forecast
  const span = latest.ts - baseline.ts
  const delta = latest.pct - baseline.pct
  if (latest.pct - idle.pct <= 0 || span < 180 || delta < 100) return forecast

  forecast.dev = Math.trunc((10000 - pct100) * span / delta) - (reset - now)
  if (previousBaseline?.ts > 0 && previousLatest) {
    const previousSpan = previousLatest.ts - previousBaseline.ts
    const previousDelta = previousLatest.pct - previousBaseline.pct
    if (previousSpan >= 180 && previousDelta >= 100) {
      const previousDev = Math.trunc((10000 - previousLatest.pct) * previousSpan / previousDelta) -
        (reset - now + trendLag)
      forecast.trend = forecast.dev - previousDev > 300 ? "up" :
        previousDev - forecast.dev > 300 ? "down" : "flat"
    }
  }
  return forecast
}

// SDK storage is global to the plugin; serialize updates from different project locations.
export function createForecastObserver(storage) {
  return async (windows, account, checkedAt) => {
    const key = `five-hour:${createHash("sha256").update(account).digest("hex")}`
    const update = async () => {
      const window = windows.find((window) => window.seconds === 18000)
      if (!window) return windows
      try {
        const state = await storage.get(key) ?? { reset: 0, samples: [] }
        const { state: next, ...forecast } = fiveHourForecast(
          state, Math.floor(window.used * 100), Math.trunc(window.resetsAt), Math.floor(checkedAt / 1000),
        )
        await storage.set(key, next)
        return windows.map((item) => item === window ? { ...item, ...forecast } : item)
      } catch {
        const { state: _, ...forecast } = fiveHourForecast(
          { reset: 0, samples: [] }, Math.floor(window.used * 100), Math.trunc(window.resetsAt),
          Math.floor(checkedAt / 1000),
        )
        return windows.map((item) => item === window ? { ...item, ...forecast } : item)
      }
    }
    const pending = (updates.get(key) ?? Promise.resolve()).then(update, update)
    updates.set(key, pending)
    try {
      return await pending
    } finally {
      if (updates.get(key) === pending) updates.delete(key)
    }
  }
}
