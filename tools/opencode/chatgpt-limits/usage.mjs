export const usageURL = "https://chatgpt.com/backend-api/wham/usage"

export function normalizeUsage(payload, now) {
  const windows = [payload?.rate_limit?.primary_window, payload?.rate_limit?.secondary_window]
    .filter((window) => window != null)
    .map((window) => {
      const seconds = window.limit_window_seconds
      const used = window.used_percent
      const resetsAt = window.reset_at ?? (now / 1000 + window.reset_after_seconds)
      if (
        !Number.isFinite(seconds) || seconds <= 0 ||
        !Number.isFinite(used) || used < 0 || used > 100 ||
        !Number.isFinite(resetsAt) || resetsAt <= 0
      ) throw new Error("Invalid usage window")
      return { seconds, used, resetsAt }
    })
  if (!windows.length) throw new Error("Missing usage windows")
  return windows
}

export function createUsageReader(getConnection, { fetcher = fetch, clock = Date.now, observe } = {}) {
  let cache
  let pending
  const current = async (entry, now) => {
    const value = entry.value
    if (value.status !== "ready" || !observe) return value
    return { ...value, windows: await observe(value.windows, entry.account, now) }
  }

  return async function read() {
    const checkedAt = clock()
    let connection
    try {
      connection = await getConnection()
    } catch {
      return { status: "unavailable", windows: [], checkedAt }
    }
    if (!connection) return { status: "sign-in", windows: [], checkedAt }
    const key = connection.key
    if (cache?.key === key && checkedAt - cache.value.checkedAt < 60_000) return current(cache, checkedAt)
    if (pending?.key === key) return current(await pending.promise, clock())

    let account = key
    const promise = (async () => {
      try {
        const credential = await connection.resolve()
        if (credential?.type !== "oauth") return { status: "sign-in", windows: [], checkedAt }
        if (credential.methodID === "chatgpt-token-sharing") {
          return { status: "unsupported", windows: [], checkedAt }
        }
        if (!["chatgpt-browser", "chatgpt-headless"].includes(credential.methodID)) {
          return { status: "sign-in", windows: [], checkedAt }
        }
        if (typeof credential.metadata?.accountID === "string") account = credential.metadata.accountID
        const headers = { Authorization: `Bearer ${credential.access}`, Accept: "application/json" }
        if (typeof credential.metadata?.accountID === "string") {
          headers["ChatGPT-Account-Id"] = credential.metadata.accountID
        }
        const response = await fetcher(usageURL, {
          headers,
          redirect: "error",
          signal: AbortSignal.timeout(10_000),
        })
        if (!response.ok) return { status: "unavailable", windows: [], checkedAt }
        const windows = normalizeUsage(await response.json(), checkedAt)
        return { status: "ready", windows, checkedAt }
      } catch {
        return { status: "unavailable", windows: [], checkedAt }
      }
    })().then((value) => ({ key, value, account }))
    const flight = { key, promise }
    pending = flight
    try {
      const entry = await promise
      cache = entry
      return await current(entry, clock())
    } finally {
      if (pending === flight) pending = undefined
    }
  }
}
