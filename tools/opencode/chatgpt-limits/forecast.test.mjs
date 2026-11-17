import test from "node:test"
import assert from "node:assert/strict"
import { fiveHourForecast, createForecastObserver } from "./forecast.mjs"
import { formatUsage, limitSegments, formatDeviation, formatDays } from "./presentation.mjs"

process.env.TZ = "UTC"
const now = 1790553600
const reset = now + 3000
const state = (samples, marker = reset) => ({
  reset: marker,
  samples: samples.map(([offset, pct]) => ({ ts: now - offset, pct })),
})
const window = (forecast) => ({ seconds: 18000, ...forecast })
const snapshot = (windows) => ({ status: "ready", windows, checkedAt: now * 1000 })

test("ports Go accelerating golden: stale percentage, negative ETA and red trend", () => {
  const history = state([[1200, 1000], [900, 1500], [600, 2500], [300, 4000]])
  const result = fiveHourForecast(history, 45, reset, now)
  assert.deepEqual(result.state, history)
  assert.equal(result.used, 40)
  assert.equal(result.dev, -1200)
  assert.equal(result.trend, "down")
  assert.deepEqual(limitSegments(snapshot([window(result)]), now * 1000), [
    { text: "5h 40% -20м (0:50 -> 0:30)", color: "red" },
  ])
})

test("ports Go decelerating golden: green trend with surplus hidden", () => {
  const history = state([[1800, 500], [1500, 1200], [1200, 1800], [900, 2200], [600, 2500], [300, 2700]])
  const result = fiveHourForecast(history, 28, reset, now)
  assert.deepEqual(result.state, history)
  assert.equal(result.used, 27)
  assert.equal(result.trend, "up")
  assert.deepEqual(limitSegments(snapshot([window(result)]), now * 1000), [
    { text: "5h 27% (0:50)", color: "green" },
  ])
})

test("new reset clears history; percentage decreases alone never do", () => {
  const history = state([[600, 5000], [30, 5500]])
  assert.deepEqual(fiveHourForecast(history, 100, reset + 1, now).state, state([[0, 100]], reset + 1))
  const stale = fiveHourForecast(history, 100, reset - 1, now)
  assert.equal(stale.used, 55)
  assert.equal(stale.resetsAt, reset)
  assert.deepEqual(stale.state, history)
  const lower = fiveHourForecast(history, 5400, reset, now)
  assert.equal(lower.used, 55)
  assert.deepEqual(lower.state, history)
})

test("future reset and poisoned marker follow the Go recovery rules", () => {
  const empty = { reset: 0, samples: [] }
  const ignored = fiveHourForecast(empty, 42, 1893456000, now)
  assert.equal(ignored.resetsAt, null)
  assert.deepEqual(ignored.state, empty)
  assert.equal(formatUsage(snapshot([window(ignored)]), now * 1000), "5h 0%")
  const recovered = fiveHourForecast(state([[30, 0]], 1893456000), 3500, reset, now)
  assert.deepEqual(recovered.state, state([[0, 3500]]))
})

test("sampling interval, minimum span/delta and idle detection match Go", () => {
  const history = state([[30, 3500]])
  assert.deepEqual(fiveHourForecast(history, 3500, reset, now).state, history)
  assert.equal(fiveHourForecast(state([[60, 3500]]), 3500, reset, now).state.samples.length, 2)
  assert.equal(fiveHourForecast(state([[179, 1000]]), 1100, reset, now).dev, null)
  assert.equal(fiveHourForecast(state([[180, 1000]]), 1099, reset, now).dev, null)
  assert.notEqual(fiveHourForecast(state([[180, 1000]]), 1100, reset, now).dev, null)
  assert.equal(fiveHourForecast(state([[900, 1000], [301, 1100]]), 1100, reset, now).dev, null)
})

test("flat trend and sign fallback use their exact five-minute bands", () => {
  const history = state([[2100, 1000], [1800, 1500], [1500, 2000], [1200, 2500], [900, 3000], [600, 3500], [300, 4000]])
  assert.equal(fiveHourForecast(history, 4500, reset, now).trend, "flat")
  for (const [dev, color] of [[301, "green"], [300, "cyan"], [-300, "cyan"], [-301, "red"]]) {
    const result = limitSegments(snapshot([window({ used: 50, resetsAt: reset, dev, trend: "" })]), now * 1000)[0]
    assert.equal(result.color, color)
  }
  const trend = limitSegments(snapshot([window({ used: 50, resetsAt: reset, dev: -600, trend: "up" })]), now * 1000)[0]
  assert.equal(trend.color, "green")
  assert.match(trend.text, /-10м/)
})

test("history pruning retains age rather than only the last N samples", () => {
  const history = { reset, samples: Array.from({ length: 201 }, (_, i) => ({ ts: now - 4000 + i * 20, pct: 1000 })) }
  const result = fiveHourForecast(history, 1000, reset, now)
  assert.ok(result.state.samples.every((sample) => sample.ts >= now - 2700))
  assert.ok(result.state.samples.some((sample) => sample.ts === now - 2700))
})

test("weekly deficit is linear, only negative, and gated at twelve hours", () => {
  const weekly = (elapsed, used) => ({ seconds: 604800, used, resetsAt: now + 604800 - elapsed })
  assert.deepEqual(limitSegments(snapshot([weekly(43199, 90)]), now * 1000), [{ text: "7d 90%", color: "dim" }])
  assert.deepEqual(limitSegments(snapshot([weekly(43200, 50)]), now * 1000), [{ text: "7d 50% -3.0д", color: "red" }])
  assert.deepEqual(limitSegments(snapshot([weekly(43200, 10)]), now * 1000), [{ text: "7d 10% -0.2д", color: "dim" }])
  assert.deepEqual(limitSegments(snapshot([weekly(43200, 0)]), now * 1000), [{ text: "7d 0%", color: "dim" }])
})

test("formatting, saturation, exact one-hour cutoff and width gates preserve the old UI", () => {
  assert.deepEqual([-59, 59, -60, 60, 3601, -3660].map(formatDeviation), ["0м", "0м", "-1м", "+1м", "+1ч00м", "-1ч01м"])
  assert.deepEqual([-8639, 8639, -8640, 8640].map(formatDays), ["0.0д", "0.0д", "-0.1д", "+0.1д"])
  const five = window({ used: 50, resetsAt: reset, dev: -1200, trend: "down" })
  const weekly = { seconds: 604800, used: 5, resetsAt: now + 3000 }
  const value = snapshot([five, weekly])
  assert.equal(formatUsage(value, now * 1000, 59), "")
  assert.equal(formatUsage(value, now * 1000, 60), "5h 50% (0:50)")
  assert.equal(formatUsage(value, now * 1000, 79), "5h 50% (0:50)")
  assert.equal(formatUsage(value, now * 1000, 80), "5h 50% (0:50) · 7d 5%")
  assert.equal(formatUsage(value, now * 1000, 99), "5h 50% (0:50) · 7d 5%")
  assert.equal(formatUsage(value, now * 1000, 100), "5h 50% -20м (0:50 -> 0:30) · 7d 5%")
  const spent = limitSegments(snapshot([window({ used: 100, resetsAt: reset })]), now * 1000)
  assert.deepEqual(spent, [{ text: "5h you lose (0:50)", color: "red" }])
  assert.equal(formatUsage(snapshot([window({ used: 50, resetsAt: reset, dev: 3600 })]), now * 1000), "5h 50% (0:50)")
  assert.match(formatUsage(snapshot([window({ used: 50, resetsAt: reset, dev: 3599 })]), now * 1000), /\+59м/)
})

test("history persists across observers, is account-scoped and serializes parallel sessions", async () => {
  const data = new Map()
  const storage = { get: async (key) => data.get(key), set: async (key, value) => { data.set(key, value) } }
  const observe = createForecastObserver(storage)
  const first = [{ seconds: 18000, used: 10, resetsAt: reset }]
  await observe(first, "account-a", (now - 900) * 1000)
  const secondObserver = createForecastObserver(storage)
  const results = await Promise.all([20, 21, 22].map((used) => secondObserver(
    [{ ...first[0], used }], "account-a", now * 1000,
  )))
  assert.equal(results.at(-1)[0].used, 22)
  assert.equal([...data.values()][0].samples.length, 4)
  assert.notEqual(results.at(-1)[0].dev, null)
  const other = await observe(first, "account-b", now * 1000)
  assert.equal(other[0].dev, null)
  assert.equal(data.size, 2)
  assert.ok([...data.keys()].every((key) => !key.includes("account-")))
})

test("storage failure preserves the live percentage and reset without a fabricated forecast", async () => {
  const observe = createForecastObserver({ get: async () => { throw new Error("unavailable") } })
  const windows = [{ seconds: 18000, used: 30, resetsAt: reset }]
  assert.deepEqual(await observe(windows, "account", now * 1000), [
    { ...windows[0], dev: null, trend: "" },
  ])
})
