import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {db,uid,qg,a,manager,org,otherorg,client,rpc,snap} from './fixture.mjs';
import {confirmDirectory} from '../../supabase/functions/care-mcp/core/directory.mjs';
const preview=(kind,payload,key=crypto.randomUUID(),user=qg,extra={})=>rpc('care_mcp_directory_preview',[kind,JSON.stringify(payload),key],user,true,extra);
const approve=id=>rpc('care_mcp_directory_review',[id,'approve'],qg,false);
const claim=id=>rpc('care_mcp_directory_claim',[id]);
const agent=(email='new-agent@example.test')=>({full_name:'Nouvel Agent',email,role:'agent'});
async function finish(id,attempt,user){await db.exec('set role service_role');try{return(await db.query('select public.care_mcp_directory_finish($1,$2,$3) r',[id,attempt,user])).rows[0].r;}finally{await db.exec('reset role');}}
test('Directory SQL: permissions, preview, external approval and durable creation',async t=>{
 await t.test('site preview no mutation, human-only approval, exactly-once confirmed site',async()=>{
  const before=(await snap(qg)).sites.length;
  const p=await preview('create_site',{client_id:client,name:'Nouveau site',address:'Adresse',general_instructions:'Consignes'});
  assert.equal((await snap(qg)).sites.length,before);await assert.rejects(()=>claim(p.plan_id),/APPROVAL/);
  await assert.rejects(()=>rpc('care_mcp_directory_review',[p.plan_id,'approve']),/HUMAN/);
  const view=await rpc('care_mcp_directory_review',[p.plan_id,'view'],qg,false);assert.equal(view.client_name,'Client 1');
  await approve(p.plan_id);const r=await claim(p.plan_id);assert.equal(r.result.applied,true);assert.equal(r.execute,false);
  assert.deepEqual(await claim(p.plan_id),r);assert.equal((await snap(qg)).sites.length,before+1);
  await assert.rejects(()=>preview('create_site',{client_id:client,name:' nouveau SITE '}),/ALREADY_EXISTS/);
 });
 await t.test('foreign clients, role elevation, unknown fields, no email, duplicates refused',async()=>{
  const foreign=uid(880);await db.query('insert into public.clients(id,organization_id,name) values($1,$2,$3)',[foreign,otherorg,'Foreign']);
  await assert.rejects(()=>preview('create_site',{client_id:foreign,name:'Bad'}),/ACTIVE_CLIENT/);
  for(const patch of [{role:'qg_admin'},{role:'client'},{password:'not-allowed'},{email:''},{full_name:null},{email:42}])await assert.rejects(()=>preview('create_agent',{...agent(),...patch}));
  await db.query('update auth.users set email=$1 where id=$2',['existing@example.test',a]);
  await assert.rejects(()=>preview('create_agent',agent('EXISTING@example.test')),/ALREADY_EXISTS/);
 });
 await t.test('idempotency checks exact input; native tokens cannot prepare; read-only and agent denied',async()=>{
  const key=crypto.randomUUID(),p=await preview('create_agent',agent(),key);assert.deepEqual(await preview('create_agent',agent(),key),p);
  await assert.rejects(()=>preview('create_agent',agent('different@example.test'),key),/IDEMPOTENCY/);
  await assert.rejects(()=>rpc('care_mcp_directory_preview',['create_agent',JSON.stringify(agent()),crypto.randomUUID()],qg,false),/TOKEN/);
  await assert.rejects(()=>preview('create_agent',agent(),crypto.randomUUID(),a),/ACCESS/);
  await db.query("update private.care_mcp_config set read_only_client_ids=array['test-client']");
  await assert.rejects(()=>preview('create_agent',agent()),/READ_ONLY/);
  await db.query("update private.care_mcp_config set read_only_client_ids='{}'");
 });
 await t.test('account creation reserved once, cannot be finalized by OAuth, profile created atomically',async()=>{
  const p=await preview('create_agent',agent('success@example.test'));await approve(p.plan_id);
  const c=await claim(p.plan_id);assert.equal(c.execute,true);assert.equal((await claim(p.plan_id)).execute,false);
  await assert.rejects(()=>preview('create_agent',agent('success@example.test')),/REQUIRES_REVIEW/);
  const newId=uid(881);await db.query('insert into auth.users(id,email) values($1,$2)',[newId,'success@example.test']);
  await assert.rejects(()=>rpc('care_mcp_directory_finish',[p.plan_id,c.attempt,newId]),/permission denied/);
  await assert.rejects(()=>finish(p.plan_id,crypto.randomUUID(),newId),/RECEIPT/);
  const r=await finish(p.plan_id,c.attempt,newId);assert.equal(r.applied,true);assert.equal(r.email_sent,false);
  const profile=(await db.query('select * from public.profiles where id=$1',[newId])).rows[0];assert.equal(profile.role,'agent');assert.equal(profile.organization_id,org);
  assert.deepEqual(await finish(p.plan_id,c.attempt,newId),r);assert.deepEqual((await claim(p.plan_id)).result,r);
 });
 await t.test('revoked permissions, expired plans, disabled client and deny prevent execution',async()=>{
  let p=await preview('create_site',{client_id:client,name:'Expired'});await approve(p.plan_id);
  await db.query("update private.care_mcp_directory_plans set expires_at=now()-interval '1 minute' where id=$1",[p.plan_id]);await assert.rejects(()=>claim(p.plan_id),/EXPIRED/);
  p=await preview('create_site',{client_id:client,name:'Denied'});await rpc('care_mcp_directory_review',[p.plan_id,'deny'],qg,false);await assert.rejects(()=>claim(p.plan_id),/APPROVAL/);
  p=await preview('create_site',{client_id:client,name:'Inactive client'});await approve(p.plan_id);await db.query('update public.clients set active=false where id=$1',[client]);await assert.rejects(()=>claim(p.plan_id),/ACTIVE_CLIENT/);await db.query('update public.clients set active=true where id=$1',[client]);
  await db.query('update private.care_mcp_members set can_write=false where profile_id=$1',[qg]);await assert.rejects(()=>claim(p.plan_id),/ACCESS/);await db.query('update private.care_mcp_members set can_write=true where profile_id=$1',[qg]);
 });
 await t.test('unknown Auth outcome is durable and cannot be retried',async()=>{
  const p=await preview('create_agent',agent('uncertain@example.test'));await approve(p.plan_id);const c=await claim(p.plan_id);
  const r=await finish(p.plan_id,c.attempt,null);assert.equal(r.applied,false);assert.equal(r.outcome_unknown,true);
  assert.equal((await claim(p.plan_id)).execute,false);await assert.rejects(()=>preview('create_agent',agent('uncertain@example.test')),/REQUIRES_REVIEW/);
 });
 await t.test('revocation during Auth call prevents profile creation',async()=>{
  const p=await preview('create_agent',agent('revoked@example.test'));await approve(p.plan_id);const c=await claim(p.plan_id),newId=uid(882);
  await db.query('insert into auth.users(id,email) values($1,$2)',[newId,'revoked@example.test']);
  await db.query('update private.care_mcp_members set can_write=false where profile_id=$1',[qg]);
  assert.equal((await finish(p.plan_id,c.attempt,newId)).applied,false);assert.equal((await db.query('select id from public.profiles where id=$1',[newId])).rows.length,0);
  await db.query('update private.care_mcp_members set can_write=true where profile_id=$1',[qg]);
 });
 await db.close();
});
test('Auth orchestration: fixed server password, no mail API, safe retries and no leaks',async()=>{
 let reserve=0,creates=0,finishes=0,received;const sensitive='server-only-test-password';
 const claim={execute:true,attempt:uid(901),payload:agent()};
 const admin={auth:{admin:{createUser:async args=>{creates++;received=args;return{data:{user:{id:uid(900)}}};}}},rpc:async()=>{finishes++;return{data:{ok:true,applied:true,email_sent:false}};}};
 const options={rpc:async()=>{reserve++;return reserve===1?claim:{execute:false,result:{ok:true,applied:true}};},createAdmin:()=>admin,initialPassword:sensitive};
 const r=await confirmDirectory(options,uid(902));assert.equal(r.applied,true);assert.equal(received.password,sensitive);assert.equal(received.email_confirm,true);assert.ok(!JSON.stringify(r).includes(sensitive));
 await confirmDirectory(options,uid(902));assert.equal(creates,1);assert.equal(finishes,1);
 await assert.rejects(()=>confirmDirectory({...options,initialPassword:''},uid(902)),/NOT_CONFIGURED/);assert.equal(reserve,2);
 admin.auth.admin.createUser=async()=>{throw Error('contains secret '+sensitive)};
 admin.rpc=async(_,args)=>{assert.equal(args.p_user_id,null);return{error:{message:sensitive}};};
 const fail=await confirmDirectory({...options,rpc:async()=>claim},uid(902));assert.equal(fail.applied,false);assert.equal(fail.outcome_unknown,true);assert.ok(!JSON.stringify(fail).includes(sensitive));
});
