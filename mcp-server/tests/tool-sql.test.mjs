import fs from 'node:fs';
import test from 'node:test';import assert from 'node:assert/strict';import {McpServer} from '@modelcontextprotocol/sdk/server/mcp.js';import {WebStandardStreamableHTTPServerTransport as Transport} from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';import {z} from 'zod';
import {db,qg,a,b,site,plan,rpc,approve,snap} from './fixture.mjs';import {makeHandler} from '../../supabase/functions/care-mcp/core/handler.mjs';
const resource='https://mcp.example/functions/v1/care-mcp',base='https://db.example';
const token='e30.'+Buffer.from(JSON.stringify({sub:qg,iss:base+'/auth/v1',aud:'authenticated',resource,client_id:'test-client',exp:Date.now()/1000+3600})).toString('base64url')+'.test';
const params={care_mcp_authorize:[],care_mcp_read:[],care_mcp_preview:['p_operations','p_key'],care_mcp_confirm:['p_id'],care_mcp_directory_preview:['p_kind','p_payload','p_key'],care_mcp_directory_claim:['p_id']};
const handler=makeHandler({McpServer,Transport,z,env:k=>({SUPABASE_URL:base,SUPABASE_ANON_KEY:'public-test',CARE_MCP_URL:resource,SUPABASE_SERVICE_ROLE_KEY:'test-service',CARE_MCP_INITIAL_AGENT_PASSWORD:'test-password-only',CARE_MCP_REVIEW_URL:'https://care.example/mcp-auth/index.html'})[k],createClient:()=>({auth:{getUser:async()=>({data:{user:{id:qg}}})},rpc:async(name,args={})=>{try{return{data:await rpc(name,params[name].map(k=>args[k]))};}catch(e){return{error:{message:e.message}};}}})});
async function call(name,args={}){const response=await handler(new Request(resource,{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json',accept:'application/json, text/event-stream'},body:JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',params:{name,arguments:args}})}));assert.equal(response.status,200);return (await response.json()).result;}
test('MCP SDK → actual SQL business functions: real local read/write journey',async()=>{
 const initial=await call('get_planning',{date:'2027-02-10',period:'day'});assert.equal(initial.structuredContent.data.total,0);
 const created=await call('create_intervention',{patch:plan(),request_key:crypto.randomUUID()});assert.equal(created.isError,undefined,JSON.stringify(created));const pid=created.structuredContent.data.plan_id;assert.ok(created.structuredContent.data.approval_url.endsWith(pid));assert.equal((await snap(qg)).interventions.length,0);
 assert.equal((await call('confirm_planning_changes',{plan_id:pid})).isError,true);await approve(pid);
 const success=await call('confirm_planning_changes',{plan_id:pid});assert.equal(success.structuredContent.data.applied,true);const id=success.structuredContent.data.operations[0].result.id;
 for(const [tool,params] of [['assign_agents',{id,agent_ids:[b],mode:'add'}],['remove_agent_assignment',{id,agent_id:a}],['reschedule_intervention',{id,starts_at:'2027-02-11T09:00:00+01:00',ends_at:'2027-02-11T11:00:00+01:00'}]]){
  const p=await call(tool,{...params,request_key:crypto.randomUUID()});assert.equal(p.isError,undefined,JSON.stringify(p));await approve(p.structuredContent.data.plan_id);assert.equal((await call('confirm_planning_changes',{plan_id:p.structuredContent.data.plan_id})).structuredContent.data.applied,true);
 }
 const detail=await call('get_intervention',{id});assert.equal(detail.structuredContent.data.agents[0].agent_id,b);assert.equal(detail.structuredContent.data.instructions,'Consigne conservée');
 const summary=await call('get_activity_summary',{from:'2027-02-01T00:00:00Z',to:'2027-03-01T00:00:00Z'});assert.equal(summary.structuredContent.data.total,1);
 const cancel=await call('cancel_intervention',{id,reason:'Test annulation MCP',request_key:crypto.randomUUID()});await approve(cancel.structuredContent.data.plan_id);assert.equal((await call('confirm_planning_changes',{plan_id:cancel.structuredContent.data.plan_id})).structuredContent.data.applied,true);assert.equal((await snap(qg)).interventions[0].status,'cancelled');const clients=await call('list_clients');assert.ok(clients.structuredContent.data.items.length);
 const clientPlan=await call('create_client',{name:'IUT Université de Toulon — test local',request_key:crypto.randomUUID()});
 assert.equal(clientPlan.isError,undefined,JSON.stringify(clientPlan));
 const cp=clientPlan.structuredContent.data.plan_id;
 assert.equal((await call('list_clients',{search:'IUT Université'})).structuredContent.data.total,0);
 assert.equal((await call('confirm_directory_creation',{plan_id:cp})).isError,true);
 await rpc('care_mcp_directory_review',[cp,'approve'],qg,false);
 const clientResult=await call('confirm_directory_creation',{plan_id:cp});assert.equal(clientResult.structuredContent.data.applied,true,JSON.stringify(clientResult));
 const clientId=clientResult.structuredContent.data.client_id;assert.ok(clientId);
 assert.deepEqual((await call('confirm_directory_creation',{plan_id:cp})).structuredContent.data,clientResult.structuredContent.data);
 assert.equal((await call('list_clients',{search:'IUT Université'})).structuredContent.data.items[0].id,clientId);
 assert.equal((await call('create_client',{name:'IUT Université de Toulon — test local',request_key:crypto.randomUUID()})).isError,true);
 for(const bad of [{organization_id:clientId},{password:'refused'},{email:'invalid'}])assert.equal((await call('create_client',{name:'Client refusé',request_key:crypto.randomUUID(),...bad})).isError,true);
 const sitePlan=await call('create_site',{client_id:clientId,name:'Site créé via MCP',request_key:crypto.randomUUID()});
 assert.equal(sitePlan.isError,undefined,JSON.stringify(sitePlan));const directoryId=sitePlan.structuredContent.data.plan_id;
 assert.match(sitePlan.structuredContent.data.approval_url,/directory=1/);
 assert.equal((await call('confirm_directory_creation',{plan_id:directoryId})).isError,true);
 await rpc('care_mcp_directory_review',[directoryId,'approve'],qg,false);
 const siteResult=await call('confirm_directory_creation',{plan_id:directoryId});assert.equal(siteResult.structuredContent.data.applied,true,JSON.stringify(siteResult));
 assert.equal((await snap(qg)).sites.find(x=>x.id===siteResult.structuredContent.data.site_id)?.client_id,clientId);
 const agentPlan=await call('create_agent',{full_name:'Agent MCP',email:'agent@example.test',request_key:crypto.randomUUID()});assert.equal(agentPlan.isError,undefined,JSON.stringify(agentPlan));
 assert.equal(agentPlan.structuredContent.data.changes.role,'agent');
 for(const bad of [{password:'not-permitted'},{role:'qg_admin'}])assert.equal((await call('create_agent',{full_name:'Agent MCP',email:'agent@example.test',request_key:crypto.randomUUID(),...bad})).isError,true);
 await db.close();
});
