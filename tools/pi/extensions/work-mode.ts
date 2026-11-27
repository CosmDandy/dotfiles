import { existsSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";

const childTools = ["read", "grep", "find", "ls", "contact_supervisor"];

const readOnlyTools = new Set([
  "read", "grep", "find", "ls",
  "mcp__knowledge__search", "mcp__knowledge__read", "mcp__knowledge__related", "mcp__knowledge__status",
  "mcp__context7__resolve_library_id", "mcp__context7__query_docs",
  "mcp__exa__web_search_exa", "mcp__exa__web_fetch_exa",
]);

const agentInstructions = ` Agents is enabled: use the subagent tool for authorized, independent investigation or review. Default to fresh context and a cheaper model when it fits. Fork only when the task needs the prior conversation.
Keep noise out of this context. Broad search, log trawls, unfamiliar code, another
repo — a subagent, returning findings and \`file:line\`
rather than the dumps that produced them.

- Brief it as precisely as an implementation task: what to look for, where, what shape
  the answer takes. A vague "investigate X" reliably returns a confident answer to the
  wrong question.
- Don't delegate one named file, one grep, one known path — a round trip costs more
  than doing it.
- Implementation stays here: delegates are read-only.
- A report is not evidence — spot-check any claim that drives a decision. A reviewer
  will always find something; weigh by effect on correctness.
- Background sessions forbid subagents unless you asked for them — say so rather than
  quietly doing the work here.
- Every scope, once: a subagent reviews the diff in a fresh context, reporting only
  gaps that affect correctness or a stated requirement. Same threshold as plan mode;
  per file it burns a whole context for nothing. (INTERACTIVE)`;

const profiles = [
  {
    name: "Pair",
    instructions: "Once authorized to implement, work in small, verifiable steps. Continue through routine changes, but at a consequential decision present the alternatives and wait for the user's choice before proceeding.",
  },
  {
    name: "Autonomous",
    instructions: "Once authorized to implement, make reversible decisions independently and carry the task through verification. Pause only when blocked or when user approval is required. Ask only when stuck: the same failure twice with no new hypothesis; show what you ruled out, one question.",
  },
];

type Ceiling = { allowedTools: string[]; allowedAgents?: string[] };
type CeilingRegistration = {
  update(ceiling: Ceiling): void;
  dispose(): void;
};

export default async function (pi: ExtensionAPI) {
  if (process.env.PI_SUBAGENT_CHILD === "1") return;
  let executeTools: string[] | undefined;
  let profile = profiles[0];
  let agents = false;
  let ceiling: CeilingRegistration | undefined;
  const agentTools = new Set<string>();
  const mayDelegate = () => !executeTools && agents;
  const launchDenied = () => executeTools
    ? "Switch to Execute before launching a subagent."
    : "Enable Agents with Option+G in Execute before launching a subagent.";
  const capability = (): Ceiling => ({ allowedTools: childTools, ...(mayDelegate() ? {} : { allowedAgents: [] }) });

  const packageDir = join(getAgentDir(), "subagent-package", "pi-subagents");
  const entry = join(packageDir, "bundle", "index.js");
  const load = (path: string) => import(pathToFileURL(path).href);
  const registerCeiling: ((options: { sessionId: string; source: string; ceiling: Ceiling }) => CeilingRegistration) | undefined =
    existsSync(entry) ? (await load(join(packageDir, "src", "api", "capability-ceiling.js"))).registerSubagentCapabilityCeiling : undefined;

  if (registerCeiling) {
    const { default: registerSubagents } = await load(entry);
    registerSubagents(new Proxy(pi, {
      get(target, key, receiver) {
        if (key === "registerTool") return ((definition) => {
          agentTools.add(definition.name);
          pi.registerTool({ ...definition, defaultActive: false });
        }) as ExtensionAPI["registerTool"];
        if (key === "registerCommand") return ((name, command) => {
          if (name === "subagents-fleet") pi.registerCommand("agents", command);
          if (name === "run") {
            const run = command.handler;
            command = { ...command, handler: async (args, ctx) => {
              if (mayDelegate()) await run(args, ctx);
              else ctx.ui.notify(launchDenied(), "warning");
            } };
          }
          if (name === "subagents") {
            const administer = command.handler;
            command = { ...command, handler: (args, ctx) => {
              const scoped = ctx.scopedModels.map(({ model }) => model);
              if (!scoped.length) return administer(args, ctx);
              const modelRegistry = new Proxy(ctx.modelRegistry, {
                get(registry, property) {
                  if (property === "getAvailable") return () => scoped;
                  const value = Reflect.get(registry, property, registry);
                  return typeof value === "function" ? value.bind(registry) : value;
                },
              });
              return administer(args, { ...ctx, modelRegistry });
            } };
          }
          pi.registerCommand(name, command);
        }) as ExtensionAPI["registerCommand"];
        return Reflect.get(target, key, receiver);
      },
    }));
  }

  function showMode(ctx: ExtensionContext) {
    if (ctx.mode !== "tui") return;
    ctx.ui.setStatus("work-mode", executeTools ? "EXPLORE" : `EXECUTE · ${profile.name.toUpperCase()}${agents ? " · AGENTS" : ""}`);
  }

  async function toggleAgents(ctx: ExtensionContext) {
    if (!ctx.isIdle()) {
      ctx.ui.notify("Wait for the current run to finish before toggling Agents.", "info");
      return;
    }
    if (!agentTools.has("subagent")) {
      ctx.ui.notify("The managed pi-subagents package is not installed.", "warning");
      return;
    }
    agents = !agents;
    ceiling?.update(capability());
    if (executeTools) ctx.ui.notify(`Agents ${agents ? "enabled" : "disabled"} for Execute.`, "info");
    else setExecuteTools(pi.getActiveTools());
    showMode(ctx);
  }

  function canSwitchProfile(ctx: ExtensionContext) {
    if (ctx.isIdle()) return true;
    ctx.ui.notify("Wait for the current run to finish before switching profiles.", "info");
    return false;
  }

  function applyProfile(selected: (typeof profiles)[number], ctx: ExtensionContext) {
    profile = selected;
    showMode(ctx);
  }

  async function selectProfile(ctx: ExtensionContext) {
    if (!canSwitchProfile(ctx)) return;
    const choices = new Map([profile, ...profiles.filter(item => item !== profile)]
      .map(item => [`${item.name}${item === profile ? " (active)" : ""}`, item] as const));
    const choice = await ctx.ui.select("Execute profile", [...choices.keys()]);
    const selected = choice === undefined ? undefined : choices.get(choice);
    if (selected && ctx.isIdle()) applyProfile(selected, ctx);
  }

  function selectExploreTools() {
    pi.setActiveTools(pi.getAllTools().map(tool => tool.name).filter(name => readOnlyTools.has(name)));
  }

  function setExecuteTools(tools: string[], enabled = agents) {
    const wanted = tools.filter(name => !agentTools.has(name));
    if (enabled) wanted.push(...pi.getAllTools().map(tool => tool.name).filter(name => agentTools.has(name)));
    const active = pi.getActiveTools();
    if (active.length !== wanted.length || wanted.some(name => !active.includes(name))) pi.setActiveTools(wanted);
  }

  pi.registerShortcut("shift+tab", {
    description: "Switch between Explore and Execute",
    handler: async ctx => {
      if (!ctx.isIdle()) {
        ctx.ui.notify("Wait for the current run to finish before switching modes.", "info");
        return;
      }
      if (executeTools) {
        setExecuteTools(executeTools);
        executeTools = undefined;
      } else {
        executeTools = pi.getActiveTools();
        selectExploreTools();
      }
      ceiling?.update(capability());
      showMode(ctx);
    },
  });

  pi.registerShortcut("alt+r", {
    description: "Cycle Execute profiles",
    handler: async ctx => {
      if (!canSwitchProfile(ctx)) return;
      applyProfile(profiles[(profiles.indexOf(profile) + 1) % profiles.length], ctx);
    },
  });
  pi.registerCommand("execute", {
    description: "Choose an Execute profile",
    handler: async (_args, ctx) => selectProfile(ctx),
  });

  pi.registerShortcut("alt+g", {
    description: "Toggle Agents",
    handler: toggleAgents,
  });

  function syncTools() {
    if (executeTools) selectExploreTools();
    else setExecuteTools(pi.getActiveTools());
  }

  pi.on("session_start", (_event, ctx) => {
    ceiling?.dispose();
    ceiling = registerCeiling?.({ sessionId: ctx.sessionManager.getSessionId(), source: "work-mode", ceiling: capability() });
    syncTools();
    showMode(ctx);
  });
  pi.on("session_tree", syncTools);
  pi.on("session_shutdown", event => {
    ceiling?.dispose();
    ceiling = undefined;
    if (event.reason === "reload" && (executeTools || agents)) {
      setExecuteTools(executeTools ?? pi.getActiveTools(), false);
      executeTools = undefined;
    }
  });
  pi.on("before_agent_start", event => {
    syncTools();
    if (!executeTools) {
      const delegation = agents ? agentInstructions : "";
      event.systemPromptOptions.sections["work_mode"] = `Execute profile: ${profile.name}. ${profile.instructions}${delegation}`;
      return;
    }
    event.systemPromptOptions.sections["work_mode"] =
      "Explore mode: investigate without changing files or external state. Clarify the goal and scope, surface relevant trade-offs, and propose a next step or concise plan when useful. Wait for the user to switch to Execute before implementing.";
  });
  pi.on("tool_call", event => {
    if (!mayDelegate() && agentTools.has(event.toolName)) return { block: true, reason: launchDenied() };
    if (executeTools && !readOnlyTools.has(event.toolName)) {
      return { block: true, reason: "Explore mode allows read-only tools. Switch to Execute to make changes." };
    }
  });
}
