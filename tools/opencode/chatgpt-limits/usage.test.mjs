import test from "node:test"
import assert from "node:assert/strict"
import { createUsageReader, normalizeUsage, usageURL } from "./usage.mjs"
import { formatUsage } from "./presentation.mjs"
import { createForecastObserver } from "./forecast.mjs"

process.env.TZ = "UTC"

const now = 1_793_640_000_000
const payload = {
  rate_limit: {
    primary_window: { used_percent: 44, limit_window_seconds: 18000, reset_at: now / 1000 + 6600 },
    secondary_window: { used_percent: 8, limit_window_seconds: 604800, reset_at: now / 1000 + 530000 },
  },
}
const credential = { type: "oauth", methodID: "chatgpt-headless", access: "test-token", metadata: { accountID: "test-account" } }
const connection = { key: "test", resolve: async () => credential }

test("normalizes and renders actual five-hour and seven-day windows", () => {
  const windows = normalizeUsage(payload, now)
  const reset = new Date((now / 1000 + 6600) * 1000)
  const clock = `${reset.getHours()}:${String(reset.getMinutes()).padStart(2, "0")}`
  assert.equal(formatUsage({ status: "ready", windows, checkedAt: now }, now), `5h 44% (${clock}) · 7d 8%`)
})

test("does not invent absent windows; accepts zero usage and relative reset", () => {
  const result = normalizeUsage({ rate_limit: { primary_window: {
    used_percent: 0, limit_window_seconds: 3600, reset_after_seconds: 60,
  } } }, now)
  assert.deepEqual(result, [{ seconds: 3600, used: 0, resetsAt: now / 1000 + 60 }])
})

test("rejects missing or malformed quota data", () => {
  for (const data of [null, {}, { rate_limit: {} }, { rate_limit: { primary_window: {} } }]) {
    assert.throws(() => normalizeUsage(data, now))
  }
  for (const used_percent of [-1, 101, "44", NaN]) {
    assert.throws(() => normalizeUsage({ rate_limit: { primary_window: {
      ...payload.rate_limit.primary_window, used_percent,
    } } }, now))
  }
})

test("uses active OAuth account, fixed URL, timeout and no redirects; caches for one minute", async () => {
  let time = now
  let calls = 0
  const read = createUsageReader(async () => connection, {
    clock: () => time,
    fetcher: async (url, options) => {
      calls++
      assert.equal(url, usageURL)
      assert.equal(options.redirect, "error")
      assert.ok(options.signal instanceof AbortSignal)
      assert.equal(options.headers.Authorization, "Bearer test-token")
      assert.equal(options.headers["ChatGPT-Account-Id"], "test-account")
      return { ok: true, json: async () => payload }
    },
  })
  assert.equal((await read()).status, "ready")
  await read()
  assert.equal(calls, 1)
  time += 60_000
  await read()
  assert.equal(calls, 2)
})

test("coalesces simultaneous requests and invalidates cache on account changes", async () => {
  let key = "first"
  let calls = 0
  const read = createUsageReader(async () => ({ ...connection, key }), {
    clock: () => now,
    fetcher: async () => { calls++; return { ok: true, json: async () => payload } },
  })
  await Promise.all([read(), read(), read()])
  assert.equal(calls, 1)
  key = "second"
  await read()
  assert.equal(calls, 2)
})

test("missing, API-key and token-sharing auth never send requests", async () => {
  for (const [value, status] of [
    [undefined, "sign-in"],
    [{ type: "api" }, "sign-in"],
    [{ ...credential, methodID: "chatgpt-token-sharing" }, "unsupported"],
    [{ ...credential, methodID: "other-oauth" }, "sign-in"],
  ]) {
    const read = createUsageReader(async () => value ? { key: "test", resolve: async () => value } : undefined, {
      clock: () => now,
      fetcher: () => assert.fail("must not send a request"),
    })
    assert.equal((await read()).status, status)
  }
})

test("HTTP, transport, credentials and JSON failures expose no secrets or stale values", async () => {
  for (const fetcher of [
    async () => ({ ok: false, status: 401 }),
    async () => { throw new Error("test-token") },
    async () => ({ ok: true, json: async () => { throw new Error("test-token") } }),
    async () => ({ ok: true, json: async () => ({}) }),
  ]) {
    const read = createUsageReader(async () => connection, { fetcher, clock: () => now })
    assert.deepEqual(await read(), { status: "unavailable", windows: [], checkedAt: now })
  }
  const read = createUsageReader(async () => { throw new Error("test-token") }, { clock: () => now })
  assert.equal((await read()).status, "unavailable")
})

test("expired or stale snapshots do not pretend the quota has reset", () => {
  const value = { status: "ready", windows: normalizeUsage(payload, now), checkedAt: now }
  assert.equal(formatUsage(value, now + 121_000), "ChatGPT limits: unavailable")
  const expired = { ...value, windows: [{ seconds: 18000, used: 44, resetsAt: now / 1000 }] }
  assert.equal(formatUsage(expired, now), "5h: refreshing")
})

test("cache hits recheck shared account history without re-fetching usage", async () => {
  let time = now
  const data = new Map()
  const storage = { get: async (key) => data.get(key), set: async (key, value) => { data.set(key, value) } }
  let calls = 0
  const reader = (used) => createUsageReader(async () => connection, {
    clock: () => time,
    observe: createForecastObserver(storage),
    fetcher: async () => {
      calls++
      return { ok: true, json: async () => ({ rate_limit: { primary_window: {
        ...payload.rate_limit.primary_window, used_percent: used,
      } } }) }
    },
  })
  const idle = reader(10)
  const active = reader(100)
  assert.equal((await idle()).windows[0].used, 10)
  time += 1000
  assert.equal((await active()).windows[0].used, 100)
  time += 1000
  const value = await idle()
  assert.equal(value.windows[0].used, 100)
  assert.equal(value.checkedAt, now)
  assert.equal(calls, 2)
})

test("cache hits recompute idle cutoff at the UI refresh time", async () => {
  let time = now
  const reset = now / 1000 + 3000
  const history = { reset, samples: [
    { ts: now / 1000 - 900, pct: 1000 }, { ts: now / 1000 - 300, pct: 4000 },
  ] }
  const storage = { get: async () => history, set: async () => {} }
  let calls = 0
  const read = createUsageReader(async () => connection, {
    clock: () => time,
    observe: createForecastObserver(storage),
    fetcher: async () => {
      calls++
      return { ok: true, json: async () => ({ rate_limit: { primary_window: {
        used_percent: 0.45, limit_window_seconds: 18000, reset_at: reset,
      } } }) }
    },
  })
  assert.equal((await read()).windows[0].dev, -1800)
  time += 15_000
  assert.equal((await read()).windows[0].dev, null)
  assert.equal(calls, 1)
})
