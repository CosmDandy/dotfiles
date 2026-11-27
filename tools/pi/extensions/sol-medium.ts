import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const provider = "openai-codex";
const sol = "gpt-6.2-sol";

export default function (pi: ExtensionAPI) {
  // Pi deduplicates scoped models by provider and ID, not by reasoning level.
  pi.registerVirtualModel({
    provider,
    id: "sol-medium",
    name: "GPT-6.2 Sol (Medium)",
    thinkingLevels: ["medium"],
    route(_request, ctx) {
      const model = ctx.modelRegistry.find(provider, sol);
      if (!model) throw new Error(`Model ${provider}/${sol} is not in the catalog.`);
      return { model, thinkingLevel: "medium" };
    },
  });
}
