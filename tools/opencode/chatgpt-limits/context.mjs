export function contextSummary(messages, models, boundary) {
  const boundaryIndex = boundary ? messages.findIndex((message) => message.id === boundary) : -1
  if (boundary && boundaryIndex === -1) return
  const end = boundaryIndex === -1 ? messages.length : boundaryIndex
  const compaction = messages.findLastIndex((message, index) =>
    message.type === "compaction" && message.status === "completed" && index < end,
  )
  // Streaming placeholders must not hide the last measured context window.
  for (let index = end - 1; index > compaction; index--) {
    const message = messages[index]
    if (message.type !== "assistant" || !message.tokens) continue
    const tokens = message.tokens.input + message.tokens.output + message.tokens.reasoning +
      message.tokens.cache.read + message.tokens.cache.write
    if (tokens <= 0) continue
    const model = models?.find((model) => model.providerID === message.model.providerID && model.id === message.model.id)
    const count = tokens >= 999950 ? `${(tokens / 1000000).toFixed(1)}M` :
      tokens >= 1000 ? `${(tokens / 1000).toFixed(1)}K` : `${tokens}`
    return model?.limit.context ? `${count} (${Math.round(tokens / model.limit.context * 100)}%)` : count
  }
}
