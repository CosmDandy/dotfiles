import assert from 'node:assert/strict';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {readFileSync} from 'node:fs';
import {setTimeout as sleep} from 'node:timers/promises';
import {stripVTControlCharacters as plain} from 'node:util';
const modules=process.env.PI_TEST_MODULES; assert.ok(modules);
const repo=process.env.REPO || process.cwd();
const load=path=>import(pathToFileURL(join(modules,'@earendil-works',path)));
const c=path=>load('pi-coding-agent/dist/'+path+'.js'); const interactive=p=>c('modes/interactive/'+p);
const {Container,TuiAltScreen,Spacer,setKeybindings,setCapabilityOverrides}=await load('pi-tui/dist/index.js');
const {initTheme,getEditorTheme}=await interactive('theme/theme'); setCapabilityOverrides({trueColor:true,images:null}); initTheme('dark',false);
const {VimTranscript}=await interactive('vim-transcript'); const {paintVimFrame}=await interactive('vim-dock');
const {createChatViewport}=await interactive('chat-viewport'); const {CustomEditor}=await interactive('components/custom-editor');
const {KeybindingsManager}=await c('core/keybindings'); const {ToolExecutionComponent}=await interactive('components/tool-execution');
const {BashExecutionComponent}=await interactive('components/bash-execution'); const {UserMessageComponent}=await interactive('components/user-message');
const {AssistantMessageComponent}=await interactive('components/assistant-message'); const {createEventBus}=await c('core/event-bus');
const {loadExtensions}=await c('core/extensions/loader');
const loaded=await loadExtensions([join(repo,'tools/pi/extensions/compact-tools.ts')], process.cwd(),createEventBus());assert.deepEqual(loaded.errors,[]);
const bash=loaded.extensions[0].toolRenderers[0]('bash',()=>undefined);
const keys=new KeybindingsManager(JSON.parse(readFileSync(join(repo,'tools/pi/keybindings.json'))));setKeybindings(keys);
console.error(`node ${process.version}, ${modules}, ${process.platform}-${process.arch}, fake terminal 100x32, n=5 per phase, no timing`);
for(const N of (process.argv.slice(2).length?process.argv.slice(2).map(Number):[100,1000,5000])){
 let onInput,resolveFrame,frameCount=0;
 const term={columns:100, rows:32,start(cb){onInput=cb},stop(){},write(){},showCursor(){},hideCursor(){}};
 const ui=new TuiAltScreen(term,false,undefined,{}),document=new Container(),editor=new CustomEditor(ui,getEditorTheme(),keys);
 const edBox=new Container();edBox.addChild(editor);const chat=new VimTranscript(()=>viewport,()=>document.getRenderedChildRow(chat),()=>ui.requestRender(),()=>ui.setFocus(editor),assert.fail);
 document.addChild(new Spacer(2)); document.addChild(chat); const empty=()=>new Container();
 const {transcript:viewport,root}=createChatViewport({document,editor:edBox,pendingMessages:empty(),status:empty(),footer:empty(),scrollbar:'hidden'});
 editor.onTranscriptEscape=()=>{if(!chat.enter())return false;ui.setFocus(chat);return true};
 const counters=[];
 for(let i=0;i<N;i++){
   let block;
   if(i%4===0) block=new UserMessageComponent('prompt '+i);
   if(i%4===1) block=new AssistantMessageComponent({role:'assistant',content:[{type:'text',text:'answer '+i}]});
   if(i%4===2){block=new ToolExecutionComponent('bash','call-'+i,{command:'printf cmd-'+i},{showImages:false},bash,ui,process.cwd());block.updateResult({isError:false,content:[{type:'text',text:'tool-output-'+i}]});}
   if(i%4===3){block=new BashExecutionComponent('echo direct-'+i,ui);block.appendOutput('direct-output-'+i);block.setComplete(0,false);}
   const stats={tool:i%4>=2,render:0,setter:0,rebuild:0};counters.push(stats);
   for(const [key,method] of Object.entries({render:'render',setter:'setResultHidden',rebuild:'updateDisplay'})){
      if(typeof block[method]!=='function')continue;const orig=block[method];block[method]=function(...args){stats[key]++;return orig.apply(this,args)};
   }
   chat.addChild(block);
 }
 ui.decorateFrame=(screen,layout)=>{
   if(chat.mode){const region=paintVimFrame(screen,layout,edBox,chat.mode,chat.openRows());chat.paintVisible(screen,layout.width,region)}
   frameCount++; const done=resolveFrame;resolveFrame=undefined;done?.();
 };
 async function step(act){assert(!resolveFrame);let fail;const timeout=new Promise((_,rej)=>fail=setTimeout(()=>rej(Error('no frame')),3000));
    const p=new Promise(r=>resolveFrame=r);act();try{await Promise.race([p,timeout]);}finally{clearTimeout(fail)}}
 function reset(){for(const c of counters)c.render=c.setter=c.rebuild=0}
 function count(){let row=document.getRenderedChildRow(chat);const sums={height:viewport.viewportHeight,rows:chat.childLines.lines.length,visibleTools:0,allChildRender:0,allToolRender:0,offToolRender:0,allToolSetter:0,offToolSetter:0,allToolRebuild:0};
    for(const [i,s] of counters.entries()){const h=chat.childLines.parts[i].length;const visible=h>0&&row<viewport.scrollTop+viewport.viewportHeight&&row+h>viewport.scrollTop;row+=h;sums.allChildRender+=s.render;
       if(s.tool){sums.visibleTools+=+visible;sums.allToolRender+=s.render;sums.allToolSetter+=s.setter;sums.allToolRebuild+=s.rebuild;if(!visible){sums.offToolRender+=s.render;sums.offToolSetter+=s.setter}}}
    return sums;
 }
 async function measure(phase,act){let results=[],frames=[];
    for(let i=0;i<5;i++){reset();let before=frameCount;await step(()=>act(i));results.push(count());frames.push(frameCount-before)}
    assert.deepEqual(frames,[1,1,1,1,1]);const median=a=>a.sort((a,b)=>a-b)[2];const med=Object.fromEntries(Object.keys(results[0]).map(k=>[k,median(results.map(r=>r[k]))]));
    if (process.env.PI_EXPECT_VIEW_CACHE && ['INSERT key','NORMAL key','VISUAL key','INSERT view-only','VISUAL view-only'].includes(phase)) {
      assert.ok(results.every(r=>r.offToolRender===0 && r.offToolSetter===0), phase);
    }
    console.log(JSON.stringify({N,phase,med,samples:results}));
 }
 ui.setLayoutRoot(root);ui.setFocus(editor);
 try{
    await step(()=>ui.start());await sleep(35);
    await measure('INSERT key',()=>onInput('x'));assert.equal(editor.getText(),'xxxxx');
    await measure('INSERT view-only',i=>ui.scrollBy(i%2===0?-1:1));
    const live = chat.children.find(c=>c instanceof AssistantMessageComponent);
    await step(()=>{live.updateContent({role:'assistant',content:[{type:'text',text:'fresh-while-typing'}]});ui.requestRender();onInput('z')});
    assert.ok(chat.childLines.lines.some(x=>plain(x).includes('fresh-while-typing')));
    assert.equal(editor.getText(),'xxxxxz'); await step(()=>onInput('\x7f'));
    await step(()=>onInput('\x1b'));await sleep(45);assert.equal(chat.mode,'NORMAL');assert.ok(ui.getScreenLines().some(x=>plain(x).includes('▸')));
    await measure('NORMAL content',()=>ui.requestRender());
    await measure('NORMAL key',i=>onInput(i%2===0?'k':'j'));
    await step(()=>onInput('v'));assert.equal(chat.mode,'VISUAL');
    await measure('VISUAL key',i=>onInput(i%2===0?'j':'k'));
    await measure('VISUAL view-only',i=>ui.scrollBy(i%2===0?-1:1));
    for (const width of [76,100]) {
      term.columns = width;
      await step(()=>ui.requestRender(true)); assert.equal(chat.mode,'VISUAL');
      assert.ok(ui.getScreenLines().length > 0 && ui.getScreenLines().length <= term.rows);
      assert.ok(viewport.viewportHeight > 0 && viewport.viewportHeight < term.rows);
    }
    await step(()=>onInput('i'));assert.equal(chat.mode,undefined);assert.equal(editor.getText(),'xxxxx');
    if(N===100){
      const fresh=title=>{const b=new BashExecutionComponent(title,ui);b.appendOutput('BODY '+title);b.setComplete(0,false);return b};
      const saved=chat.children.at(-1); saved.setExpanded(true);
      const getRows=block=>{const i=chat.childLines.children.indexOf(block);assert(i>=0);return chat.childLines.parts[i].map(plain).join('\n')};
      await step(()=>ui.requestRender());assert.match(getRows(saved),/direct-output-/);
      await step(()=>onInput('\x1b'));await sleep(45);assert.doesNotMatch(getRows(saved),/direct-output-/);
      await step(()=>onInput('\r'));await sleep(45);assert.match(getRows(saved),/direct-output-/);
      await step(()=>onInput('\x1b[D'));await sleep(45);assert.equal(saved.isExpanded,true);assert.doesNotMatch(getRows(saved),/direct-output-/);
      const a=fresh('fresh-A');await step(()=>{chat.addChild(a);ui.requestRender()});assert.doesNotMatch(getRows(a),/BODY/);
      const b=fresh('replace-B');await step(()=>{chat.removeChild(a);chat.addChild(b);ui.requestRender()});assert.doesNotMatch(getRows(b),/BODY/);
      const before=chat.children.length;const other=fresh('spliced-C');await step(()=>{chat.children.splice(1,1,other);ui.requestRender()});assert.equal(chat.children.length,before);assert.doesNotMatch(getRows(other),/BODY/);
      const streaming=chat.children.find(c=>c instanceof AssistantMessageComponent);
      await step(()=>{b.appendOutput('LATEST');streaming.updateContent({role:'assistant',content:[{type:'text',text:'streamed-while-moving'}]});ui.requestRender();onInput('j')});
      assert.match(getRows(streaming),/streamed-while-moving/);assert.doesNotMatch(getRows(b),/LATEST/);
      await step(()=>ui.setFocus(editor) || ui.requestRender());assert.match(getRows(b),/LATEST/);assert.match(getRows(other),/BODY/);
      await step(()=>ui.setFocus(chat) || ui.requestRender());assert.doesNotMatch(getRows(b),/LATEST/);
      await step(()=>onInput('i'));assert.match(getRows(saved),/direct-output-/);assert.match(getRows(b),/BODY replace-BLATEST/);
      console.error('EDGE PASS: expanded restore; active append, same-length replacement + splice; dirty result coalesced with key; focus loss/regain/exit; editor draft preserved');
    }
 }finally{ui.stop({preserveScreen:true})}
}
