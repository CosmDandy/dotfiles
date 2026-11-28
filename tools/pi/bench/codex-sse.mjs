// Run with Node 24, PI_TEST_MODULES and the baseline extension path as argv[2].
import assert from 'node:assert/strict';
import { mkdtempSync, copyFileSync, symlinkSync, rmSync, openSync, closeSync, readSync, writeFileSync, readFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const dir=process.env.PI_SSE_TRIAL || mkdtempSync(join(tmpdir(),'pi-sse-'));
if (!process.env.PI_SSE_TRIAL) {
  process.env.PI_SSE_TRIAL = dir;
  process.on('exit',()=>rmSync(dir,{force:true,recursive:true}));
  assert.ok(process.argv[2], 'pass the baseline codex-web-search.ts');
  copyFileSync(process.argv[2],join(dir,'legacy.ts'));
  copyFileSync(fileURLToPath(new URL('../extensions/codex-web-search.ts',import.meta.url)),join(dir,'hook.ts'));
  symlinkSync(process.env.PI_TEST_MODULES,join(dir,'node_modules'),'dir');
}
const arg=process.argv.slice(2), sizes=[65536,1048576,8388608];
const A='https://alpha.invalid/doc',B='http://beta.invalid/path',title='Résumé 🧭';
const expected=[{url:A,title},{url:B,title:B}];
const word='synthetic text ', url=(url,title)=>({type:'url_citation',url,title,start_index:0,end_index:4});
const frame=(e,nl='\r\n')=>`event: ${e.type}${nl}data: ${JSON.stringify(e)}${nl}${nl}`;
const ann=a=>({type:'response.output_text.annotation.added',output_index:1,item_id:'msg',content_index:0,annotation_index:0,annotation:a});
const msg=(text,annotations=[])=>({type:'message',id:'msg',role:'assistant',status:'completed',content:[{type:'output_text',text,annotations}]});
const finish=item=>({type:'response.output_item.done',output_index:item.type==='message'?1:0,item});
const delta=frame({type:'response.output_text.delta',item_id:'msg',output_index:1,content_index:0,delta:word});
const pathFor=(size,opt)=>join(dir,`fixture-${size}-${opt}.sse`);
function make(size,flavor){ // Parent ONLY. Child reads generated fixture in network-sized byte chunks, never a monolithic array.
  const search=flavor!=='missing-search', cites=!['late','missing'].includes(flavor);
  const action={type:'search',query:'generated',sources:[{type:'url',url:A}]}; // consulted != cited
  const c={type:'web_search_call',id:'ws',status:search?'completed':'in_progress',action};
  const pre=': keepalive\r\n\r\n'+frame({type:'response.created',response:{id:'gen',status:'in_progress'}},'\n')+
    frame({type:'response.output_item.added',output_index:0,item:{...c,status:'in_progress'}})+
    frame({type:'response.web_search_call.searching',output_index:0,item_id:'ws'})+
    (flavor==='dedicated'?frame({type:'response.web_search_call.completed',output_index:0,item_id:'ws'}):frame(finish(c)))+
    frame({type:'response.output_item.added',output_index:1,item:{...msg(''),status:'in_progress',content:[]}});
  const standalone=frame(ann(url(A,'old title')))+frame(ann(url(B)))+frame(ann(url(A)));
  function rest(n){
    // Final text and nested annotations are repeated in the done item and the terminal snapshot as in Responses.
    const m=msg(flavor==='empty'?'   ':word.repeat(n)+'See https://not-evidence.invalid/doc',cites?[url(A,title),url(B),url('ftp://ignored.invalid/'),{type:'file_citation',url:A}]:[]);
    const done=frame(finish(m),'\n'); const rsp={id:'gen',status:'completed',output:[c,m],usage:{input_tokens:3,output_tokens:5,total_tokens:8}};
    const terminal=flavor==='truncated'?'':flavor==='provider-error'?frame({type:'response.failed',response:{status:'failed',error:{code:'synthetic',message:'generated provider failure'}}}):
      flavor==='incomplete'?frame({type:'response.incomplete',response:{...rsp,status:'incomplete',incomplete_details:{reason:'max_output_tokens'}}}):frame({type:'response.completed',response:rsp});
    return (cites?standalone:'')+done+(flavor==='bad-json'?'data: {oops\r\n\r\n':'')+terminal+(flavor==='late'?standalone:'')+'data: [DONE]\n\n';
  }
  function body(n,pad){let b=pre+delta.repeat(n)+(pad?':'+'.'.repeat(pad-3)+'\n\n':'')+rest(n);
    if(flavor==='multi')b=b.replace('data: {"type":"response.created",','data: {"type":"response.created",\ndata: ');
    if(flavor==='cr')b=b.replace(/\r?\n/g,'\r');return b;}
  const n=Math.floor((size-Buffer.byteLength(body(0,0))-8)/(Buffer.byteLength(delta)+(flavor==='empty'?0:2*word.length)));
  let b=body(n,0),gap=size-Buffer.byteLength(b); if(gap>=3)b=body(n,gap); assert.equal(Buffer.byteLength(b),size);
  writeFileSync(pathFor(size,flavor),b);return {n,bytes:size,textUnits:b.length,events:b.split(/\r\n|\r|\n/).filter(l=>l.startsWith('data: {')).length};
}
const child=arg[0]==='worker';
// No credential lookup, no network: guard even stray global fetch calls outside our fake per-execute binding.
globalThis.fetch=async()=>{throw new Error('unexpected fetch in synthetic audit')};
if(child){
  const mode=arg[1], size=Number(arg[2]), flavor=arg[3];
  const sdk=join(dir,'node_modules/@earendil-works/pi-ai/dist');
  const {streamSimple}=await import(join(sdk,'api/openai-codex-responses.js'));
  const {OPENAI_CODEX_MODELS}=await import(join(sdk,'providers/openai-codex.models.js'));
  const model={...Object.values(OPENAI_CODEX_MODELS)[0],baseUrl:'https://offline.invalid'};
  const apiKey=`unused.${Buffer.from(JSON.stringify({'https://api.openai.com/auth':{chatgpt_account_id:'synthetic'}})).toString('base64')}.unused`;
  let tool; (await import(join(dir,mode+'.ts'))).default({registerTool:t=>tool=t,on(){}});
  async function run(size,flavor,diagnostic=false){
    let cloned=0,copyUnits=0,bytesRead=0,cancels=0,pulls=0,fetches=0,eventsParsed=0,observerCalls=0,queued=null,sourcePayload=0,err=null,answerBytes=0;
    const a=new AbortController(); let genDeadline,oldTimeout; if(flavor==='deadline') {genDeadline=new AbortController();oldTimeout=AbortSignal.timeout;AbortSignal.timeout=()=>genDeadline.signal;}
    const filename=pathFor(size,['hold','abort','deadline','http'].includes(flavor)?'ok':flavor);
    let tailTimer; const t=performance.now(), cpu0=process.cpuUsage();
    const fetchLocal=async(input,init)=>{
      assert.equal(new URL(input).hostname,'offline.invalid');assert.equal(++fetches,1);
      if(flavor==='http')return new Response('{"error":{"message":"generated HTTP failure"}}',{status:429});
      let fd=openSync(filename,'r'), closed=false; const close=()=>{if(!closed){closed=true;closeSync(fd);clearTimeout(tailTimer);}};
      const body=new ReadableStream({type:'bytes',pull(ctrl){
        ++pulls;
        if((flavor==='abort'||flavor==='deadline')&& pulls===3){
          // The legacy tee has two consumers. Its fake HTTP transport, like fetch, honors the forwarded signal.
          if(mode==='legacy')init?.signal?.addEventListener('abort',()=>{ctrl.error(init.signal.reason);close();},{once:true});
          setTimeout(()=>(genDeadline??a).abort(new DOMException('synthetic','AbortError')),2);
          tailTimer=setTimeout(()=>{throw Error('SDK did not cancel the stalled response');},2000);
          return new Promise(()=>{});
        }
        const len=flavor==='cr'||flavor==='multi'?107:[8191,16381,4093,1021][(pulls-1)%4];
        const chunk=new Uint8Array(len);const n=readSync(fd,chunk,0,len,null);bytesRead+=n;
        if(n){ctrl.enqueue(chunk.subarray(0,n));return;} if(flavor==='hold'){ // Do not send EOF for 250ms after terminal; single branch can cancel instead of waiting.
          return new Promise(resolve=>{tailTimer=setTimeout(()=>{if(!closed){close();ctrl.close();}resolve();},250);});}
        close();ctrl.close();},cancel(){++cancels;close();}});
      const r=new Response(body,{headers:{'Content-Type':'text/event-stream; charset=utf-8'}});const rc=r.clone.bind(r); r.clone=()=>{++cloned;const c=rc();const tx=c.text.bind(c);c.text=async()=>{const s=await tx();copyUnits=s.length;return s;};return c;};return r;};
    const prevJSON=JSON.parse;if(diagnostic)JSON.parse=(str,...args)=>{if(typeof str==='string'&&/^ ?\{"type":/.test(str))++eventsParsed;return prevJSON(str,...args);};
    globalThis.fetch=fetchLocal;
    let stream;
    const reg={streamSimple(model,ctx,options){ assert.equal(options.transport,'sse');assert.equal(options.maxRetries,0);
      // SDK processes all SSE/normalization/abort/error paths; mock registry only supplies the synthetic credential.
      const cb=options.onProviderStreamEvent;
      if(diagnostic&&cb)options={...options,onProviderStreamEvent:(e,m)=>{++observerCalls;return cb(e,m);}};
      return stream=streamSimple(model,ctx,{...options,apiKey});}};
    let result; try{result=await tool.execute('gen',{query:'generated public query'},a.signal,undefined,{model,modelRegistry:reg});}catch(e){err=e.message;}
    finally{JSON.parse=prevJSON;if(oldTimeout)AbortSignal.timeout=oldTimeout;globalThis.fetch=async()=>{throw new Error('out of scope fetch')};}
    const elapsed=performance.now()-t, cpu=process.cpuUsage(cpu0);
    if(result){const {answer,sources}=result.structuredContent;assert.ok(answer.trim());answerBytes=Buffer.byteLength(answer); if(flavor!=='late')assert.deepEqual(sources,expected); sourcePayload=sources.reduce((n,{url,title})=>n+Buffer.byteLength(url)+Buffer.byteLength(title),0);assert.equal(result.usage.totalTokens,8);}
    if(diagnostic) queued=stream?.queue?.length??null;
    return {mode,size,flavor,err,cloned,copyUnits,bytesRead,cancels,pulls,fetches,sourcePayload,answerBytes,eventsParsed,observerCalls,queued,ms:elapsed,cpuMs:(cpu.user+cpu.system)/1000,rssHwmMiB:process.resourceUsage().maxRSS/1024};
  }
  const warm=await run(65536,'ok');assert.equal(warm.err,null,warm.err);global.gc?.();
  const result=await run(size,flavor,arg[4]==='counts');process.stdout.write(JSON.stringify(result));
}else{
 const samples=Number(process.env.SAMPLES||7);assert.ok(Number.isInteger(samples)&&samples%2===1&&samples>0);const out={env:{node:process.version,platform:process.platform,arch:process.arch,samples},fixtures:{},runs:[],checks:[]};
 const work=(mode,size,flavor,counts=false)=>{const r=spawnSync(process.execPath,['--expose-gc','--no-warnings',fileURLToPath(import.meta.url),'worker',mode,size+'',flavor,counts?'counts':''],{encoding:'utf8',timeout:15000});assert.equal(r.status,0,r.stderr||r.error?.message);return JSON.parse(r.stdout);};
 for(const size of sizes){out.fixtures[size]=make(size,'ok');make(size,'missing');}
 for(const size of sizes){for(let i=0;i<samples;++i)for(const mode of i%2?['hook','legacy']:['legacy','hook']){const r=work(mode,size,'ok');assert.equal(r.err,null);out.runs.push(r);}
   for(const mode of ['legacy','hook'])for(const f of ['ok','missing']){const r=work(mode,size,f,true);assert.ok(f==='missing'?r.err?.includes('did not return a completed'):!r.err);out.checks.push(r);}}
 for(const f of ['dedicated','missing-search','empty','cr','multi','bad-json','truncated','provider-error','incomplete','late','hold','abort','deadline','http']){
   if(!['hold','abort','deadline','http'].includes(f))make(65536,f);
   for(const mode of ['legacy','hook']){const r=work(mode,65536,f,true);out.checks.push(r);
     const error=(['missing-search','empty'].includes(f)||(['cr','multi'].includes(f)&&mode==='legacy')||(f==='late'&&mode==='hook'))?/did not return a completed/:f==='bad-json'?/Invalid Codex SSE JSON/:f==='truncated'?/before a terminal/:f==='provider-error'?/generated provider failure/:f==='incomplete'?/did not finish/:f==='abort'?/abort/i:f==='deadline'?/timed out after 180/:f==='http'?/usage limit/:null;
     if(mode==='hook'&&['abort','deadline'].includes(f))assert.equal(r.cancels,1,'SDK must cancel the stalled body');
     if(error)assert.match(r.err||'',error,JSON.stringify(r));else assert.equal(r.err,null,JSON.stringify(r));
   }}
 if (process.env.PI_SSE_RESULTS) writeFileSync(process.env.PI_SSE_RESULTS,JSON.stringify(out,null,2));const med=xs=>xs.sort((a,b)=>a-b)[Math.floor(xs.length/2)];
 console.log('size mode cloneTextUnits extraParses urlTitleUTF8 answerUTF8 medianWallMs medianCpuMs totalProcPeakMiB');
 for(const size of sizes)for(const mode of ['legacy','hook']){const runs=out.runs.filter(x=>x.size===size&&x.mode===mode);const a=out.checks.find(x=>x.flavor==='ok'&&x.size===size&&x.mode===mode),b=out.checks.find(x=>x.flavor==='ok'&&x.size===size&&x.mode==='hook');console.log(size,mode,a.copyUnits,a.eventsParsed-b.eventsParsed,a.sourcePayload,a.answerBytes,...['ms','cpuMs','rssHwmMiB'].map(k=>med(runs.map(x=>x[k])).toFixed(2)));}
 console.log('semantic/diagnostic rows:',out.checks.length);}
