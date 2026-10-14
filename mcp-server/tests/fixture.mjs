import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';import assert from 'node:assert/strict';
export const db=globalThis.CARE_TEST_DB||new PGlite();let count=0;
await db.exec(`create role supabase_auth_admin;create role anon;create role authenticated;create role service_role bypassrls;
create schema auth;create table auth.users(id uuid primary key,email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;
create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner_id text default auth.uid()::text,metadata jsonb default '{"mimetype":"image/jpeg"}');alter table storage.objects enable row level security;
create function storage.foldername(text) returns text[] language sql as $$ select string_to_array($1,'/') $$;
grant usage on schema storage to authenticated;grant select,insert,update,delete on storage.objects to authenticated;grant execute on function storage.foldername(text) to authenticated;
create publication supabase_realtime;`);
// PGlite has gen_random_uuid built in; Supabase's extension install is the only omitted statement.
await db.exec(fs.readFileSync('supabase/migrations/001_care_core.sql','utf8').replace('create extension if not exists pgcrypto;',''));
await db.exec(fs.readFileSync('supabase/migrations/20261010103139_care_v3_secure_operations.sql','utf8'));
await db.exec(fs.readFileSync('supabase/migrations/20261010170239_care_v3_request_intervention.sql','utf8'));
await db.exec(fs.readFileSync('supabase/migrations/20261010172547_care_v3_web_push.sql','utf8'));
export const uid=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
export const org=uid(100),qg=uid(1),a=uid(2),b=uid(3),c=uid(4),other=uid(5),manager=uid(6),otherorg=uid(101);
await db.exec(`insert into public.organizations(id,name) values('${org}','Azzera Test'),('${otherorg}','Other test');
insert into auth.users(id) values('${qg}'),('${a}'),('${b}'),('${c}'),('${other}'),('${manager}');
insert into public.profiles(id,organization_id,role,full_name) values('${qg}','${org}','qg_admin','QG Test'),('${a}','${org}','agent','Agent A'),('${b}','${org}','agent','Agent B'),('${c}','${org}','client','Client A'),('${other}','${org}','client','Client B'),('${manager}','${org}','qg_manager','Manager');`);
export async function as(user,sql,args=[]){await db.exec(`reset role;set request.jwt.claim.sub='${user}';set role authenticated;`);try{return await db.query(sql,args)}finally{await db.exec('reset role')}}
export async function act(user,kind,p={},key=crypto.randomUUID()){return (await as(user,'select public.care_v3_action($1,$2,$3) as r',[kind,JSON.stringify(p),key])).rows[0].r}
export async function snap(user){return (await as(user,'select public.care_v3_snapshot() as r')).rows[0].r}
async function pass(label,fn){await fn();count++;console.log(`PASS ${count}: ${label}`)}
async function denied(fn){await assert.rejects(fn)}
export let client,site,client2,site2,mission,request;
await pass('QG creates clients/sites with real SQL',async()=>{client=(await act(qg,'client',{name:'Client 1',contacts:'Contact public'})).id;site=(await act(qg,'site',{client_id:client,name:'Site A',access_notes:'SECRET ACCESS',general_instructions:'Instructions'})).id;client2=(await act(qg,'client',{name:'Client 2'})).id;site2=(await act(qg,'site',{client_id:client2,name:'Site B'})).id;await db.query('insert into public.client_users values($1,$2),($3,$4)',[client,c,client2,other]);});

await db.exec(`create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);`);
await db.exec(fs.readFileSync('supabase/migrations/20261011140817_care_mcp_secure_connector.sql','utf8'));
await db.exec(fs.readFileSync('supabase/migrations/20261014160126_care_mcp_directory_creation.sql','utf8'));
if(!globalThis.CARE_TEST_SKIP_CLIENT_MIGRATION)await db.exec(fs.readFileSync('supabase/migrations/20261014191808_care_mcp_client_creation.sql','utf8'));
await db.query("update private.care_mcp_config set resource_url='https://mcp.example/functions/v1/care-mcp',enabled=true,organization_id=$1,oauth_client_ids=$2",[org,['test-client']]);
await db.query('insert into private.care_mcp_members values($1,true,true),($2,true,true),($3,true,true)',[qg,a,c]);
await db.query('insert into auth.sessions values($1,$2,null)',[uid(200),qg]);
export async function rpc(name,args=[],user=qg,oauth=true,extra={}) {
 const claims={sub:user,session_id:uid(200),exp:Math.floor(Date.now()/1000)+3600,...(oauth?{client_id:'test-client',resource:'https://mcp.example/functions/v1/care-mcp',session_id:uid(200)}:{}),...extra};
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify(claims)]);
 try {return (await as(user,`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) as r`,args)).rows[0].r} finally {await db.exec("set request.jwt.claims='{}'");}
}
export const plan=(over={})=>({site_id:site,title:'Intervention MCP test',starts_at:'2027-02-10T08:00:00+01:00',ends_at:'2027-02-10T10:00:00+01:00',service_type:'cleaning',agent_ids:[a],internal_notes:'Interne conservé',instructions:'Consigne conservée',...over});
export const preview=(ops,key=crypto.randomUUID())=>rpc('care_mcp_preview',[JSON.stringify(ops),key]);
export const approve=id=>rpc('care_mcp_review',[id,'approve'],qg,false);
export const confirm=id=>rpc('care_mcp_confirm',[id]);
