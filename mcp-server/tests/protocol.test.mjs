import test from 'node:test';import assert from 'node:assert/strict';
import {McpServer} from '@modelcontextprotocol/sdk/server/mcp.js';
import {WebStandardStreamableHTTPServerTransport as Transport} from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';
import {z} from 'zod';import {makeHandler} from '../../supabase/functions/care-mcp/core/handler.mjs';import {resolveParis,periodRange} from '../../supabase/functions/care-mcp/core/time.mjs';
const resource='https://mcp.example/functions/v1/care-mcp',base='https://db.example',user='00000000-0000-4000-8000-000000000001';
const jwt=(claims={})=>'e30.'+Buffer.from(JSON.stringify({sub:user,iss:base+'/auth/v1',aud:'authenticated',resource,client_id:'client',exp:Date.now()/1000+3600,...claims})).toString('base64url')+'.signature';
const snapshot={interventions:[],assignments:[],people:[],clients:[],sites:[],requests:[],tasks:[],photos:[],reports:[],documents:[],logs:[],quality:[],issues:[]};
function setup({invalid=false,denied=false,rate=false,canWrite=true,data=snapshot}={}){let calls=[];const handler=makeHandler({McpServer,Transport,z,env:k=>({SUPABASE_URL:base,SUPABASE_ANON_KEY:'public-test-key',CARE_MCP_URL:resource,CARE_MCP_REVIEW_URL:'https://care.example/mcp-auth/index.html'})[k],createClient:()=>({auth:{getUser:async()=>invalid?{error:{message:'invalid'}}:{data:{user:{id:user}}}},rpc:async(name,args)=>{calls.push({name,args});if(denied||rate)return{error:{message:rate?'MCP_RATE_LIMIT':'MCP_ACCESS_DENIED'}};return{data:name==='care_mcp_read'?data:{authorized:true,can_write:canWrite}};}})});return{handler,calls,post:async(body,token=jwt(),headers={})=>handler(new Request(resource,{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json',accept:'application/json, text/event-stream',...headers},body:JSON.stringify(body)}))};}
const request=(method,params={})=>({jsonrpc:'2.0',id:1,method,params});
test('Supabase internal route supports discovery without relaxing OAuth resource or permissions',async()=>{
 const h=setup({canWrite:false});
 const internal='https://internal.example/care-mcp';
 const post=(url,token=jwt())=>h.handler(new Request(url,{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json',accept:'application/json, text/event-stream'},body:JSON.stringify(request('tools/list'))}));
 assert.equal((await h.handler(new Request(internal))).status,401);
 const response=await post(internal);assert.equal(response.status,200);
 const tools=(await response.json()).result.tools;assert.equal(tools.length,12);assert.ok(tools.every(t=>t.annotations.readOnlyHint));
 assert.equal((await post(internal,jwt({resource:internal}))).status,401);
 for(const path of ['/','/other','/care-mcp/extra','/prefix/care-mcp','/functions/v1/other'])assert.equal((await post('https://internal.example'+path)).status,404);
});
test('Native SDK: OAuth discovery challenge, initialize, list tools, typed call',async()=>{
 const h=setup();let r=await h.handler(new Request(resource));assert.equal(r.status,401);assert.match(r.headers.get('www-authenticate'),/resource_metadata/);
 r=await h.handler(new Request(resource+'/.well-known/oauth-protected-resource'));assert.equal((await r.json()).resource,resource);
 r=await h.post(request('initialize',{protocolVersion:'2025-06-18',capabilities:{},clientInfo:{name:'test',version:'1'}}));assert.equal(r.status,200);assert.equal((await r.json()).result.serverInfo.name,'azzera-care');
 r=await h.post(request('tools/list'));const tools=(await r.json()).result.tools;assert.equal(tools.length,25);assert.ok(tools.some(t=>t.name==='create_client')); assert.equal(tools.find(t=>t.name==='confirm_planning_changes').annotations.destructiveHint,true);assert.equal(tools.find(t=>t.name==='get_planning').annotations.readOnlyHint,true);
 r=await h.post(request('tools/call',{name:'get_planning',arguments:{date:'2026-10-25',period:'day'}}));let result=(await r.json()).result;assert.equal(result.structuredContent.data.total,0);assert.equal(Date.parse(result.structuredContent.data.to)-Date.parse(result.structuredContent.data.from),25*3600000);
 r=await h.post(request('tools/call',{name:'list_clients',arguments:{sql:'delete from profiles'}}));result=(await r.json()).result;assert.equal(result.isError,true);
});
test('Signature-verifier failure, wrong audience/resource/issuer, expired and future token fail closed',async()=>{
 assert.equal((await setup({invalid:true}).post(request('tools/list'))).status,401);
 for(const claims of [{aud:'other'},{resource:'https://other.example'},{iss:'https://evil.example'},{exp:1},{nbf:Date.now()/1000+500},{client_id:null},{sub:'other'}])assert.equal((await setup().post(request('tools/list'),jwt(claims))).status,401);
 assert.equal((await setup({denied:true}).post(request('tools/list'))).status,403);assert.equal((await setup({rate:true}).post(request('tools/list'))).status,429);
});
test('Origin, batch and body size restrictions',async()=>{
 const h=setup();assert.equal((await h.post(request('tools/list'),jwt(),{origin:'https://evil.example'})).status,403);assert.equal((await h.post([request('tools/list')])).status,400);assert.equal((await h.post({blob:'a'.repeat(81000)})).status,413);
});
test('Paris spring/fall transition, impossible dates and ambiguity',()=>{
 assert.equal(resolveParis('2026-03-29T01:30'),'2026-03-29T00:30:00.000Z');assert.throws(()=>resolveParis('2026-03-29T02:30'),/NOT_EXIST/);assert.throws(()=>resolveParis('2026-10-25T02:30'),/AMBIGUOUS/);assert.equal(resolveParis('2026-10-25T02:30','+02:00'),'2026-10-25T00:30:00.000Z');assert.equal(resolveParis('2026-10-25T02:30','+01:00'),'2026-10-25T01:30:00.000Z');assert.throws(()=>resolveParis('2026-07-01T12:00','+01:00'),/INVALID/);assert.throws(()=>periodRange('2026-02-30','day'),/INVALID/);
 const r=periodRange('2026-03-29','day');assert.equal(Date.parse(r.to)-Date.parse(r.from),23*3600000);
});
test('Read models: minimal personal data, filtering, statistics, availability',async()=>{
 const i={id:'00000000-0000-4000-8000-000000000010',site_id:'00000000-0000-4000-8000-000000000011',title:'Test',status:'planned',starts_at:'2026-10-25T09:00Z',ends_at:'2026-10-25T10:00Z'},agent='00000000-0000-4000-8000-000000000012',client='00000000-0000-4000-8000-000000000013';
 const data={...snapshot,interventions:[i],people:[{id:agent,full_name:'Agent test',email:'private@invalid',phone:'PRIVATE',role:'agent',active:true}],assignments:[{agent_id:agent,intervention_id:i.id}],sites:[{id:i.site_id,client_id:client,name:'Site',access_notes:'SECRET CODE'}],clients:[{id:client,name:'Client',email:'private@invalid'}]};const h=setup({data});
 const call=async(name,args)=>(await (await h.post(request('tools/call',{name,arguments:args}))).json()).result;
 const p=await call('get_planning',{date:'2026-10-25',period:'day',agent_id:agent});assert.equal(p.structuredContent.data.total,1);assert.ok(!JSON.stringify(p).includes('PRIVATE'));assert.ok(!JSON.stringify(await call('list_agents',{})).includes('private@'));assert.ok(!JSON.stringify(await call('list_sites',{})).includes('SECRET CODE'));
 const range={from:'2026-10-25T08:00:00Z',to:'2026-10-25T12:00:00Z'};assert.equal((await call('get_activity_summary',range)).structuredContent.data.total,1);const free=(await call('get_agent_availability',range)).structuredContent.data.agents[0];assert.equal(free.available,false);assert.equal(free.free.length,2);
});

test('Pro connection exposes only read tools on the SAME endpoint',async()=>{const h=setup({canWrite:false});const r=await h.post(request('tools/list'));const tools=(await r.json()).result.tools;assert.equal(tools.length,12);assert.ok(tools.every(t=>t.annotations.readOnlyHint));const denied=await h.post(request('tools/call',{name:'confirm_planning_changes',arguments:{plan_id:user}}));const body=await denied.json();assert.ok(body.error||body.result?.isError);});
