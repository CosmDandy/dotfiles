import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const readOnlyTools = new Set([
  "read", "grep", "find", "ls",
  "mcp__knowledge__search", "mcp__knowledge__read", "mcp__knowledge__related", "mcp__knowledge__status",
  "mcp__exa__web_search_exa", "mcp__exa__web_fetch_exa",
]);

export default function (pi: ExtensionAPI) {
  let executeTools: string[] | undefined;

  function showMode(ctx: ExtensionContext) {
    if (ctx.mode !== "tui") return;
    ctx.ui.setStatus("work-mode", executeTools ? "EXPLORE" : "EXECUTE");
  }

  function selectExploreTools() {
    pi.setActiveTools(pi.getAllTools().map(tool => tool.name).filter(name => readOnlyTools.has(name)));
  }

  function restoreExecuteTools() {
    if (!executeTools) return;
    pi.setActiveTools(executeTools);
    executeTools = undefined;
  }

  pi.registerShortcut("shift+tab", {
    description: "Switch between Explore and Execute",
    handler: async ctx => {
      if (!ctx.isIdle()) {
        ctx.ui.notify("Wait for the current run to finish before switching modes.", "info");
        return;
      }
      if (executeTools) {
        restoreExecuteTools();
      } else {
        executeTools = pi.getActiveTools();
        selectExploreTools();
      }
      showMode(ctx);
    },
  });

  pi.on("session_start", (_event, ctx) => showMode(ctx));
  pi.on("session_shutdown", event => {
    if (event.reason === "reload") restoreExecuteTools();
  });
  pi.on("before_agent_start", event => {
    if (!executeTools) return;
    selectExploreTools();
    event.systemPromptOptions.sections["work_mode"] =
      "Explore mode: investigate without changing files or external state. Clarify the goal and scope, surface relevant trade-offs, and propose a next step or concise plan when useful. Wait for the user to switch to Execute before implementing.";
  });
  pi.on("tool_call", event => {
    if (executeTools && !readOnlyTools.has(event.toolName)) {
      return { block: true, reason: "Explore mode allows read-only tools. Switch to Execute to make changes." };
    }
  });
}
