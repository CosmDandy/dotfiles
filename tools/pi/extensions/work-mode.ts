import { randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { Type } from "typebox";
import { StringEnum } from "@earendil-works/pi-ai";
import { getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";

const childTools = ["read", "grep", "find", "ls", "contact_supervisor"];
const workerName = "foreman-worker";
const workerTools = ["read", "grep", "find", "ls", "bash", "edit", "write"];
const foremanTools = new Set(["foreman_worker", "foreman_diff"]);
const foremanEntry = "work-mode-foreman";

type Mode = "execute" | "explore" | "foreman";
type WorkerState = { id?: string; pending?: string };
type RpcData = {
  text?: string;
  details?: { asyncId?: string; runId?: string; lifecycleStatus?: { processTerminal?: { state: string } } };
};
type RpcReply = { success: true; data: RpcData } | { success: false; error: { message: string } };
class RpcTimeout extends Error {}

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
  let mode: Mode = "execute";
  let executeTools: string[] | undefined;
  let profile = profiles[0];
  let agents = false;
  let ceiling: CeilingRegistration | undefined;
  let workerRegistration: { dispose(): void } | undefined;
  let worker: WorkerState = {};
  let dispatching = false;
  const agentTools = new Set<string>();
  const mayDelegate = () => mode === "execute" && agents;
  const launchDenied = () => mode !== "execute"
    ? "Switch to Execute before launching a subagent."
    : "Enable Agents with Option+G in Execute before launching a subagent.";
  const capability = (): Ceiling => mode === "foreman"
    ? { allowedTools: workerTools, allowedAgents: [workerName] }
    : { allowedTools: childTools, ...(mayDelegate() ? {} : { allowedAgents: [] }) };

  function registerWorker() {
    const request: {
      version: 1;
      name: string;
      definition: object;
      result?: { ok: true; registration: { dispose(): void } } | { ok: false; error: Error };
    } = {
      version: 1,
      name: workerName,
      definition: {
        description: "Single local implementation worker for Foreman mode",
        systemPrompt: "Implement only the approved brief in the current working copy. Preserve unrelated changes. Do not delegate, push, deploy or change system settings. Run relevant checks. If blocked or a decision would change the brief, stop and report it. Return changed paths, observed check results and open issues.",
        systemPromptMode: "append",
        tools: workerTools,
        acceptanceRole: "writer",
        inheritProjectContext: true,
      },
    };
    pi.events.emit("pi-subagents:runtime-agent-register:v1", request);
    if (!request.result) throw new Error("The managed pi-subagents package is not available.");
    if (!request.result.ok) throw request.result.error;
    return request.result.registration;
  }

  function rpc(method: string, params: object, requestId = randomUUID()): Promise<RpcData> {
    return new Promise((resolve, reject) => {
      const unsubscribe = pi.events.on(`subagents:rpc:v1:reply:${requestId}`, payload => {
        clearTimeout(timer);
        unsubscribe();
        const reply = payload as RpcReply;
        if (reply.success) resolve(reply.data);
        else reject(new Error(reply.error.message));
      });
      const timer = setTimeout(() => {
        unsubscribe();
        reject(new RpcTimeout(`No pi-subagents reply for ${method} (${requestId}).`));
      }, 30_000);
      pi.events.emit("subagents:rpc:v1:request", { version: 1, requestId, method, params });
    });
  }

  function saveForeman() {
    pi.appendEntry(foremanEntry, mode === "foreman" ? worker : null);
  }

  async function workerStatus() {
    const current = worker;
    const id = current.pending ?? current.id;
    if (!id) return { text: "No Foreman worker has started." };
    const result = await rpc("status", { id });
    if (worker === current && current.pending && result.details?.runId) {
      worker = { id: result.details.runId };
      saveForeman();
    }
    return result;
  }

  async function workerActive() {
    if (dispatching) return true;
    if (!worker.id && !worker.pending) return false;
    try {
      const { details } = await workerStatus();
      return dispatching || !!worker.pending || details?.runId !== worker.id || details?.lifecycleStatus?.processTerminal?.state !== "observed";
    } catch {
      return true;
    }
  }

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

  const textResult = (text: string) => ({ content: [{ type: "text" as const, text }], details: {} });

  pi.registerTool({
    name: "foreman_worker",
    label: "Foreman worker",
    description: "Start one worker after user authorization, steer it while active, or resume its saved context for the next step. Status and stop target only this worker. Completion wakes this session; return control instead of polling.",
    parameters: Type.Object({
      action: StringEnum(["start", "steer", "resume", "status", "stop"] as const),
      message: Type.Optional(Type.String()),
    }),
    defaultActive: false,
    async execute(_id, { action, message }) {
      if (mode !== "foreman" || !workerRegistration) throw new Error("Foreman worker is unavailable.");
      if (dispatching) throw new Error("A Foreman worker operation is already in progress.");
      dispatching = true;
      try {
        if (action === "status") return textResult((await workerStatus()).text ?? "No status returned.");
        if (worker.pending) throw new Error("Check worker status before issuing further commands; the launch receipt was lost.");
        const id = worker.id;
        if (action === "stop") {
          if (!id) throw new Error("No Foreman worker has started.");
          await rpc("stop", { id });
          return textResult("Stop requested. Wait for confirmation before leaving Foreman.");
        }
        if (!message?.trim()) throw new Error("Provide the approved brief or a follow-up message.");
        if (action === "steer") {
          if (!id) throw new Error("No Foreman worker has started.");
          return textResult((await rpc("steer", { id, message })).text ?? "Guidance sent.");
        }
        if (action === "start" && id) throw new Error("A Foreman worker already exists. Steer or resume it instead.");
        if (action === "resume" && !id) throw new Error("No Foreman worker to resume.");
        const requestId = randomUUID();
        const method = action === "start" ? "spawn" : "resume";
        worker = { id, pending: `rpc-${method}-${requestId}` };
        saveForeman();
        try {
          const result = await rpc(method, id ? { id, message } : { agent: workerName, task: message, context: "fresh" }, requestId);
          if (!result.details?.asyncId) throw new RpcTimeout("Worker launch did not return a run ID.");
          worker = { id: result.details.asyncId };
          return textResult(result.text ?? "Worker started in the background.");
        } catch (error) {
          if (!(error instanceof RpcTimeout)) worker = { id };
          throw error;
        } finally {
          saveForeman();
        }
      } finally {
        dispatching = false;
      }
    },
  });

  pi.registerTool({
    name: "foreman_diff",
    label: "Foreman diff",
    description: "Inspect tracked changes against HEAD in the current working copy without executing a shell. Read reported new files separately.",
    parameters: Type.Object({}),
    defaultActive: false,
    async execute(_id, _params, signal, _onUpdate, ctx) {
      const result = await pi.exec("git", ["--no-pager", "diff", "--no-ext-diff", "--no-textconv", "HEAD", "--"], {
        cwd: ctx.cwd, signal, timeout: 5000, maxBuffer: 256 * 1024,
      });
      if (result.code !== 0) throw new Error(result.truncated ? "Diff exceeds 256 KiB. Read changed files individually." : result.stderr.trim() || "Git diff did not complete.");
      return textResult(result.stdout || "No tracked changes against HEAD.");
    },
  });

  function showMode(ctx: ExtensionContext) {
    if (ctx.mode !== "tui") return;
    if (mode === "explore") ctx.ui.setStatus("work-mode", "EXPLORE");
    else if (mode === "foreman") ctx.ui.setStatus("work-mode", `FOREMAN${profile.name === "Autonomous" ? " · AUTONOMOUS" : ""}`);
    else ctx.ui.setStatus("work-mode", [profile.name === "Autonomous" ? "AUTONOMOUS" : "", agents ? "AGENTS" : ""].filter(Boolean).join(" · ") || undefined);
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
    if (mode !== "execute") ctx.ui.notify(`Agents ${agents ? "enabled" : "disabled"} for Execute.`, "info");
    else syncTools();
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

  function setTools(wanted: string[]) {
    const active = pi.getActiveTools();
    if (active.length !== wanted.length || wanted.some(name => !active.includes(name))) pi.setActiveTools(wanted);
  }

  function setExecuteTools(tools: string[], enabled = agents) {
    const wanted = tools.filter(name => !agentTools.has(name) && !foremanTools.has(name));
    if (enabled) wanted.push(...pi.getAllTools().map(tool => tool.name).filter(name => agentTools.has(name)));
    setTools(wanted);
  }

  function syncTools() {
    if (mode === "execute") setExecuteTools(pi.getActiveTools());
    else setTools(pi.getAllTools().map(tool => tool.name).filter(name =>
      readOnlyTools.has(name) || (mode === "foreman" && workerRegistration && foremanTools.has(name))));
  }

  async function canLeaveForeman(ctx: ExtensionContext) {
    if (mode !== "foreman" || !(await workerActive())) return true;
    ctx.ui.notify("Wait for the Foreman worker to stop before leaving the session or mode.", "warning");
    return false;
  }

  async function switchMode(next: Mode, ctx: ExtensionContext) {
    if (!ctx.isIdle()) {
      ctx.ui.notify("Wait for the current run to finish before switching modes.", "info");
      return;
    }
    const current = mode;
    if (!(await canLeaveForeman(ctx)) || mode !== current || !ctx.isIdle()) return;
    if (next === "foreman") {
      try { workerRegistration = registerWorker(); }
      catch (error) { ctx.ui.notify(String(error), "warning"); return; }
    }
    if (mode === "execute") executeTools = pi.getActiveTools();
    const wasForeman = mode === "foreman";
    mode = next;
    if (wasForeman) {
      workerRegistration?.dispose();
      workerRegistration = undefined;
      worker = {};
    }
    if (wasForeman || mode === "foreman") saveForeman();
    ceiling?.update(capability());
    if (mode === "execute") {
      setExecuteTools(executeTools ?? pi.getActiveTools());
      executeTools = undefined;
    } else syncTools();
    showMode(ctx);
  }

  pi.registerShortcut("shift+tab", {
    description: "Switch between Explore and Execute",
    handler: async ctx => {
      if (mode === "foreman") ctx.ui.notify("Use /foreman to return to Execute.", "info");
      else await switchMode(mode === "execute" ? "explore" : "execute", ctx);
    },
  });
  pi.registerCommand("foreman", {
    description: "Toggle Foreman mode with one background implementation worker",
    handler: async (_args, ctx) => switchMode(mode === "foreman" ? "execute" : "foreman", ctx),
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

  pi.on("session_start", (_event, ctx) => {
    const saved = ctx.sessionManager.getEntries().findLast(entry => entry.type === "custom" && entry.customType === foremanEntry);
    if (saved?.type === "custom" && saved.data) {
      executeTools = pi.getActiveTools();
      mode = "foreman";
      worker = saved.data as WorkerState;
      try { workerRegistration = registerWorker(); }
      catch (error) { ctx.ui.notify(String(error), "warning"); }
    }
    ceiling?.dispose();
    ceiling = registerCeiling?.({ sessionId: ctx.sessionManager.getSessionId(), source: "work-mode", ceiling: capability() });
    syncTools();
    showMode(ctx);
  });
  pi.on("session_tree", syncTools);
  pi.on("session_before_switch", async (_event, ctx) => {
    if (!(await canLeaveForeman(ctx))) return { cancel: true };
  });
  pi.on("session_before_fork", async (_event, ctx) => {
    if (!(await canLeaveForeman(ctx))) return { cancel: true };
  });
  pi.on("session_shutdown", event => {
    ceiling?.dispose();
    ceiling = undefined;
    workerRegistration?.dispose();
    workerRegistration = undefined;
    if (event.reason === "reload" && (mode !== "execute" || agents)) {
      setExecuteTools(executeTools ?? pi.getActiveTools(), false);
      executeTools = undefined;
    }
  });
  pi.on("before_agent_start", event => {
    syncTools();
    if (mode === "execute") {
      const delegation = agents ? agentInstructions : "";
      event.systemPromptOptions.sections["work_mode"] = `Execute profile: ${profile.name}. ${profile.instructions}${delegation}`;
    } else if (mode === "foreman") {
      event.systemPromptOptions.sections["work_mode"] = `Foreman mode (${profile.name}): ${profile.instructions}
You own the discussion, decisions, brief and acceptance. Selecting this mode enables delegation, not permission to implement an unapproved task. After authorization, delegate all implementation and test commands to the single foreman_worker. Include the goal, scope, constraints and acceptance checks. Do not implement directly or fall back to another executor. Steer the live worker only when guidance changes. After its result, inspect the actual diff and check evidence; resume the same worker for follow-ups. When a worker is active, return control instead of waiting or polling. Do not accept a report without checking it.`;
    } else {
      event.systemPromptOptions.sections["work_mode"] =
        "Explore mode: investigate without changing files or external state. Clarify the goal and scope, surface relevant trade-offs, and propose a next step or concise plan when useful. Wait for the user to switch to Execute before implementing.";
    }
  });
  pi.on("tool_call", event => {
    if (!mayDelegate() && agentTools.has(event.toolName)) return { block: true, reason: launchDenied() };
    if (mode === "foreman" && workerRegistration && foremanTools.has(event.toolName)) return;
    if (mode !== "execute" && !readOnlyTools.has(event.toolName)) {
      return { block: true, reason: mode === "foreman"
        ? "Foreman reads and verifies; delegate approved changes to the Foreman worker."
        : "Explore mode allows read-only tools. Switch to Execute to make changes." };
    }
    if (foremanTools.has(event.toolName)) return { block: true, reason: "Switch to Foreman to use this tool." };
  });
}
