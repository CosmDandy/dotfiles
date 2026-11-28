import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { registerHooks } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const tmp = mkdtempSync(join(tmpdir(), "pi-threshold-"));
const agent = join(tmp, "agent"), cwd = join(tmp, "cwd"), provider = join(tmp, "fixture.ts");
const pkg = join(process.env.PI_TEST_MODULES, "@earendil-works/pi-coding-agent");
const { PI_TEST_BIN: bin, PI_TEST_SUBAGENTS: subagents } = process.env;
const alias = fileURLToPath(new URL("../extensions/sol-medium.ts", import.meta.url));
const settings = JSON.parse(readFileSync(new URL("../settings.json", import.meta.url)));
settings.compaction = { keepRecentTokens: 1 };
const env = { PATH: process.env.PATH, HOME: tmp, PI_CODING_AGENT_DIR: agent, PI_OFFLINE: "1", PI_TELEMETRY: "0" };
const models = [["gpt-6.2-sol", 500000], ["gpt-6.2-astra", 272000], ["sol-medium", 500000]];
const summarize = ({ preparation: p }) => ({ compaction: { summary: "Fixture summary", tokensBefore: p.tokensBefore, firstKeptEntryId: p.firstKeptEntryId } });
try {
  mkdirSync(agent); mkdirSync(cwd); writeFileSync(join(agent, "settings.json"), JSON.stringify(settings));
  writeFileSync(provider, `import {createAssistantMessageEventStream} from "@earendil-works/pi-ai";
    import {appendFileSync} from "node:fs";
    export default pi => {
      const cost = {input:0,output:0,cacheRead:0,cacheWrite:0};
      pi.registerProvider("openai-codex", {api:"fixture",apiKey:"fake",baseUrl:"http://127.0.0.1:1",
        models:${JSON.stringify(models.slice(0,2))}.map(([id,contextWindow])=>({id,name:id,input:["text"],reasoning:true,contextWindow,maxTokens:128000,cost})),
        streamSimple(m){const s=createAssistantMessageEventStream(), input=Number(process.env.USAGE);
          s.push({type:"done",reason:"stop",message:{role:"assistant",api:m.api,provider:m.provider,model:m.id,timestamp:Date.now(),stopReason:"stop",
            content:[{type:"text",text:"done"}],usage:{input,output:0,cacheRead:0,cacheWrite:0,totalTokens:input,cost:{...cost,total:0}}}});s.end();return s;}
      }); pi.on("session_before_compact",e=>{appendFileSync(process.env.TRACE,e.reason+"\\n");return (${summarize})(e)});
    }\n`);
  const should = (await import(join(pkg, "dist/core/compaction/compaction.js"))).shouldCompact;
  for (const window of [0,101,272000,500000]) {
    const t = Math.ceil(window * .75);
    for (const n of [t-1,t,t+1]) for (const enabled of [false,true]) {
      assert.equal(should(n,window,{enabled,reserveTokens:7,keepRecentTokens:1}), enabled && window > 0 && n >= t);
    }
  }
  Object.assign(process.env, env, { PI_SUBAGENTS_PI_CODING_AGENT_PACKAGE_ROOT: pkg });
  globalThis.fetch = () => { throw Error("unexpected network"); };
  registerHooks({ resolve(s,c,next) { return next(s,/^(@earendil-works\/|typebox\b)/.test(s) ? {...c,parentURL:pathToFileURL(join(pkg,"dist/index.js")).href} : c); } });
  const pi = await import(join(pkg,"dist/index.js"));
  const {createDefaultChildSessionFactory} = await import(join(subagents,"pi-subagents/src/runs/shared/child-session.js"));
  let session;
  const factory = createDefaultChildSessionFactory({loadPiCodingAgent: async()=>({...pi,createAgentSession: async options=>{
    assert.equal(options.agentDir,agent);const r=await pi.createAgentSession(options);session=r.session;return r;
  }})});
  try {
    for (const [id,window] of models) for (const delta of [-1,0,1]) {
      const n = window*.75+delta, expected = delta >= 0 ? ["threshold"] : [];
      const trace=join(tmp,"log"), path=join(tmp,id+"-"+n+".jsonl");writeFileSync(trace,"");
      const cli=spawnSync(bin,["--offline","--session",path,"--no-extensions","--no-mcp","--no-skills","--no-tools","--no-context-files",
        "-e",provider,"-e",alias,"--model","openai-codex/"+id,"-p","synthetic history"],{env:{...env,USAGE:String(n),TRACE:trace},cwd,encoding:"utf8",timeout:12000});
      assert.equal(cli.status,0,cli.stderr);
      assert.deepEqual(readFileSync(trace,"utf8").split("\n").filter(Boolean),expected);
      assert.equal(readFileSync(path,"utf8").trim().split("\n").map(line=>JSON.parse(line)).filter(e=>e.type==="compaction").length,expected.length);
      const events=[];
      const child=await factory.create({cwd,projectTrusted:true,runtime:{},tools:[],model:"openai-codex/"+id,storage:{kind:"memory"},
        ambientExtensions:false,noSkills:true,noContextFiles:true,extensionPaths:[alias],hooks:[{name:"fixture",factory(api){
          api.on("session_before_compact",e=>{events.push(e.reason);return summarize(e)});
        }}]});
      try {
        assert.equal(child.modelId,"openai-codex/"+id);
        const m=session.modelRuntime.getPhysicalModel("openai-codex",id==="sol-medium"?"gpt-6.2-sol":id);
        assert.equal(m.contextWindow,window);
        const sm=session.sessionManager;
        const push=input=>{
          sm.appendMessage({role:"user",timestamp:1,content:"fixture"});
          const reply={role:"assistant",provider:m.provider,model:m.id,api:m.api,timestamp:2,content:[{type:"text",text:"done"}],stopReason:"stop",
            usage:{input,output:0,totalTokens:input,cacheRead:0,cacheWrite:0}};
          sm.appendMessage(reply);session.agent.state.messages=sm.buildSessionContext().messages;return reply;
        };
        push(10); await session._checkCompaction(push(n));
        assert.deepEqual(events,expected); assert.equal(sm.getBranch().filter(e=>e.type==="compaction").length,expected.length);
      } finally { await child.dispose(); }
    }
  } finally { await factory.dispose(); }
  console.log("PASS: inclusive physical-window thresholds in CLI and SDK child, including the windowless alias");
} finally { rmSync(tmp,{recursive:true,force:true}); }
