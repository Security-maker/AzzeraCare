// Starts an ephemeral loopback-only PostgreSQL cluster. Never accepts a remote DATABASE_URL.
import EmbeddedPostgres from 'embedded-postgres';import fs from 'node:fs/promises';import os from 'node:os';import path from 'node:path';import assert from 'node:assert/strict';
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'azzera-mcp-pg-')),port=55000+Math.floor(Math.random()*900);
const pg=new EmbeddedPostgres({databaseDir:path.join(dir,'db'),port,user:'postgres',password:crypto.randomUUID(),persistent:false,initdbFlags:['--locale=C','--encoding=UTF8'],postgresFlags:['-h','127.0.0.1','-k',dir],onLog:()=>{},onError:()=>{}});
let admin,c1,c2;let count=0;
try{
 await pg.initialise();await pg.start();admin=pg.getPgClient('postgres','127.0.0.1');await admin.connect();
 globalThis.CARE_TEST_DB={exec:s=>admin.query(s),query:(s,p)=>admin.query(s,p),close:()=>admin.end()};
 const f=await import('./fixture.mjs');
 c1=pg.getPgClient('postgres','127.0.0.1');c2=pg.getPgClient('postgres','127.0.0.1');await Promise.all([c1.connect(),c2.connect()]);
 const setup=async(c,oauth=true)=>{await c.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[f.qg,JSON.stringify({sub:f.qg,exp:Date.now()/1000+3600,session_id:f.uid(200),...(oauth?{client_id:'test-client',resource:'https://mcp.example/functions/v1/care-mcp'}:{})})]);await c.query('set role authenticated');};
 await setup(c1);await setup(c2);
 const check=(name)=>{console.log('PASS CONCURRENCY '+(++count)+': '+name);};
 const proposal=async(kind,payload)=>f.rpc('care_mcp_directory_preview',[kind,JSON.stringify(payload),crypto.randomUUID()]);
 const approve=async id=>f.rpc('care_mcp_directory_review',[id,'approve'],f.qg,false);
 const p=await proposal('create_agent',{full_name:'Concurrent Agent',email:'one@example.test',role:'agent'});await approve(p.plan_id);
 const same=await Promise.all([c1.query('select care_mcp_directory_claim($1) r',[p.plan_id]),c2.query('select care_mcp_directory_claim($1) r',[p.plan_id])]);
 assert.equal(same.filter(x=>x.rows[0].r.execute).length,1);check('simultaneous confirmations reserve exactly one Auth account creation');
 const a=await proposal('create_agent',{full_name:'Second Agent',email:'two@example.test',role:'agent'}),b=await proposal('create_agent',{full_name:'Second Agent',email:'two@example.test',role:'agent'});await approve(a.plan_id);await approve(b.plan_id);
 const separate=await Promise.allSettled([c1.query('select care_mcp_directory_claim($1) r',[a.plan_id]),c2.query('select care_mcp_directory_claim($1) r',[b.plan_id])]);
 assert.equal(separate.filter(x=>x.status==='fulfilled'&&x.value.rows[0].r.execute).length,1);assert.match(separate.find(x=>x.status==='rejected').reason.message,/REQUIRES_REVIEW/);check('two approved proposals for the same email cannot both call Auth');
 const sa=await proposal('create_site',{client_id:f.client,name:'Concurrent Site'}),sb=await proposal('create_site',{client_id:f.client,name:'Concurrent Site'});await approve(sa.plan_id);await approve(sb.plan_id);
 const sites=await Promise.allSettled([c1.query('select care_mcp_directory_claim($1) r',[sa.plan_id]),c2.query('select care_mcp_directory_claim($1) r',[sb.plan_id])]);
 assert.equal(sites.filter(x=>x.status==='fulfilled'&&x.value.rows[0].r.result.applied).length,1);assert.match(sites.find(x=>x.status==='rejected').reason.message,/ALREADY_EXISTS/);check('simultaneous site creation checks committed duplicates');
 console.log(JSON.stringify({postgres:(await admin.query('select version() v')).rows[0].v,checks:count,remote_connections:0}));
}catch(e){console.error(e.message);process.exitCode=1;}finally{await c1?.end();await c2?.end();await admin?.end();await pg.stop();}
