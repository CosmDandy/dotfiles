import { Rpc } from "@opencode/plugin/rpc"

export const Limits = Rpc.define({
  id: "dotfiles-chatgpt-limits",
  methods: {
    read: {
      input: { type: "object", additionalProperties: false },
      output: {
        type: "object",
        properties: {
          status: { type: "string", enum: ["ready", "sign-in", "unsupported", "unavailable"] },
          checkedAt: { type: "number" },
          windows: {
            type: "array",
            items: {
              type: "object",
              properties: {
                seconds: { type: "number" },
                used: { type: "number" },
                resetsAt: { anyOf: [{ type: "number" }, { type: "null" }] },
                dev: { anyOf: [{ type: "number" }, { type: "null" }] },
                trend: { type: "string", enum: ["", "up", "down", "flat"] },
              },
              required: ["seconds", "used", "resetsAt"],
              additionalProperties: false,
            },
          },
        },
        required: ["status", "checkedAt", "windows"],
        additionalProperties: false,
      },
    },
  },
  events: {},
})
