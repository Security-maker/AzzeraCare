import test from 'node:test';
import assert from 'node:assert/strict';
import {db,qg,a,uid,org,otherorg,rpc,snap} from './fixture.mjs';
const preview=(p,key=crypto.randomUUID(),user=qg,extra={})=>rpc('care_mcp_directory_preview',['create_client',JSON.stringify(p),key],user,true,extra);
const approve=id=>rpc('care_mcp_directory_review',[id,'approve'],qg,false);
const claim=id=>rpc('care_mcp_directory_claim',[id]);
test('Client creation: business records only, approvals, isolation and retries',async t=>{
 await t.test('normalized fields, no early mutation, exactly once, no Auth account',async()=>{
  const users=(await db.query('select count(*) n from auth.users')).rows[0].n;
  const before=(await snap(qg)).clients.length,key=crypto.randomUUID();
  const payload={name:'  Client MCP  ',email:' CONTACT@EXAMPLE.TEST ',phone:'0123456789',contacts:'Accueil'};
  const p=await preview(payload,key);assert.equal(p.changes.name,'Client MCP');assert.equal(p.changes.email,'contact@example.test');
  assert.deepEqual(await preview(payload,key),p);assert.equal((await snap(qg)).clients.length,before);
  await assert.rejects(()=>preview({...payload,name:'Different'},key),/IDEMPOTENCY/);
  await assert.rejects(()=>claim(p.plan_id),/APPROVAL/);
  await assert.rejects(()=>rpc('care_mcp_directory_review',[p.plan_id,'approve']),/HUMAN/);
  await approve(p.plan_id);const r=await claim(p.plan_id);assert.equal(r.execute,false);assert.equal(r.result.applied,true);
  assert.deepEqual(await claim(p.plan_id),r);
  const row=(await db.query('select * from public.clients where id=$1',[r.result.client_id])).rows[0];
  assert.equal(row.organization_id,org);assert.equal(row.name,'Client MCP');assert.equal(row.email,'contact@example.test');assert.equal(row.phone,payload.phone);assert.equal(row.contacts,payload.contacts);
  assert.equal((await snap(qg)).clients.length,before+1);assert.equal((await db.query('select count(*) n from auth.users')).rows[0].n,users);
  await db.query('update public.clients set active=false where id=$1',[row.id]);
  await assert.rejects(()=>preview({name:' client mcp '}),/CLIENT_ALREADY_EXISTS/);
 });
 await t.test('reject injected ownership, updates, credentials and malformed or overlong fields',async()=>{
  for(const p of [{name:' '},{name:'X'},{name:'x'.repeat(201)},{name:'Valid',id:uid(99)},{name:'Valid',organization_id:otherorg},{name:'Valid',active:false},{name:'Valid',password:'refused'},{name:'Valid',email:'bad'},{name:'Valid',email:null},{name:'Valid',email:'x'.repeat(251)},{name:'Valid',phone:'x'.repeat(51)},{name:'Valid',contacts:'x'.repeat(4001)}])await assert.rejects(()=>preview(p));
  assert.equal((await preview({name:'Name only'})).kind,'create_client');
  assert.equal((await preview({name:'Empty contact',email:''})).changes.email,'');
 });
 await t.test('same name in another organization is allowed, result remains in own organization',async()=>{
  await db.query('insert into public.clients(organization_id,name) values($1,$2)',[otherorg,'Foreign name']);
  const p=await preview({name:'Foreign name'});await approve(p.plan_id);const r=await claim(p.plan_id);
  assert.equal((await db.query('select organization_id from public.clients where id=$1',[r.result.client_id])).rows[0].organization_id,org);
 });
 await t.test('read-only, anonymous, ordinary agent, revoked access, denial and expiry cannot create',async()=>{
  await assert.rejects(()=>preview({name:'No agent'},crypto.randomUUID(),a),/ACCESS/);
  await db.exec('set role anon');try{await assert.rejects(()=>db.query("select public.care_mcp_directory_preview('create_client','{}',gen_random_uuid())"),/permission denied/);}finally{await db.exec('reset role');}
  await db.query("update private.care_mcp_config set read_only_client_ids=array['test-client']");
  await assert.rejects(()=>preview({name:'No read only'}),/READ_ONLY/);
  await db.query("update private.care_mcp_config set read_only_client_ids='{}'");
  const revoked=await preview({name:'Revoked client'});await approve(revoked.plan_id);
  await db.query('update private.care_mcp_members set can_write=false where profile_id=$1',[qg]);
  await assert.rejects(()=>claim(revoked.plan_id),/ACCESS/);
  await db.query('update private.care_mcp_members set can_write=true where profile_id=$1',[qg]);
  const denied=await preview({name:'Denied client'});await rpc('care_mcp_directory_review',[denied.plan_id,'deny'],qg,false);await assert.rejects(()=>claim(denied.plan_id),/APPROVAL/);
  const expired=await preview({name:'Expired client'});await approve(expired.plan_id);
  await db.query("update private.care_mcp_directory_plans set expires_at=now()-interval '1 minute' where id=$1",[expired.plan_id]);await assert.rejects(()=>claim(expired.plan_id),/EXPIRED/);
 });
 await t.test('duplicate created after approval is rechecked before insertion',async()=>{
  const p=await preview({name:'Created meanwhile'});await approve(p.plan_id);
  await db.query('insert into public.clients(organization_id,name) values($1,$2)',[org,' CREATED MEANWHILE ']);
  await assert.rejects(()=>claim(p.plan_id),/CLIENT_ALREADY_EXISTS/);
 });
 await db.close();
});
