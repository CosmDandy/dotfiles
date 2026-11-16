import test from "node:test"
import assert from "node:assert/strict"
import { contextSummary } from "./context.mjs"

const assistant = (id, input) => ({
  id, type: "assistant", model: { providerID: "openai", id: "test" },
  tokens: { input, output: 0, reasoning: 0, cache: { read: 0, write: 0 } },
})
const models = [{ providerID: "openai", id: "test", limit: { context: 200000 } }]

test("matches the built-in context token sum and compact formatting", () => {
  const message = assistant("a", 50000)
  message.tokens = { input: 10000, output: 5000, reasoning: 5000, cache: { read: 20000, write: 10000 } }
  assert.equal(contextSummary([message], models), "50.0K (25%)")
  assert.equal(contextSummary([assistant("a", 999950)], models), "1.0M (500%)")
  assert.equal(contextSummary([assistant("a", 999)], undefined), "999")
})

test("context remains visible throughout a response with pending or zero-token messages", () => {
  const previous = assistant("a", 50000)
  for (const pending of [
    { id: "b", type: "user" },
    { id: "b", type: "assistant" },
    assistant("b", 0),
  ]) assert.equal(contextSummary([previous, pending], models), "50.0K (25%)")
  assert.equal(contextSummary([previous, assistant("b", 60000)], models), "60.0K (30%)")
})

test("compaction and revert boundaries do not revive discarded context", () => {
  const previous = assistant("a", 50000)
  const compaction = { id: "b", type: "compaction", status: "completed" }
  assert.equal(contextSummary([previous, compaction, assistant("c", 0)], models), undefined)
  assert.equal(contextSummary([previous, assistant("b", 60000)], models, "b"), "50.0K (25%)")
  assert.equal(contextSummary([previous], models, "missing"), undefined)
})
