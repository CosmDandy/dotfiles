import { Plugin } from "@opencode/plugin"
import { Limits } from "./rpc"
import { createUsageReader } from "./usage.mjs"
import { createForecastObserver } from "./forecast.mjs"

export default Plugin.define({
  id: "dotfiles-chatgpt-limits",
  async setup(context) {
    const read = createUsageReader(async () => {
      const connection = await context.integration.connection.active("openai")
      if (!connection) return
      return {
        key: JSON.stringify(connection),
        resolve: () => context.integration.connection.resolve(connection),
      }
    }, { observe: createForecastObserver(context.storage) })
    await context.rpc.register(Limits, { read })
  },
})
