import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
globalThis.CARE_TEST_SKIP_CLIENT_MIGRATION=true;
const {db,qg,client,rpc}=await import('./fixture.mjs');
test('1.1 to 1.2 upgrade preserves approved site and pending agent plans',async()=>{
 const preview=(kind,p)=>rpc('care_mcp_directory_preview',[kind,JSON.stringify(p),crypto.randomUUID()]);
 const site=await preview('create_site',{client_id:client,name:'Site prepared before upgrade'});
 await rpc('care_mcp_directory_review',[site.plan_id,'approve'],qg,false);
 const agent=await preview('create_agent',{full_name:'Agent before upgrade',email:'before@example.test'});
 const before=(await db.query('select * from private.care_mcp_directory_plans order by id')).rows;
 await assert.rejects(()=>preview('create_client',{name:'Not yet supported'}),/INVALID_DIRECTORY_INPUT/);
 await db.exec(fs.readFileSync('supabase/migrations/20261014191808_care_mcp_client_creation.sql','utf8'));
 assert.deepEqual((await db.query('select * from private.care_mcp_directory_plans order by id')).rows,before);
 assert.equal((await rpc('care_mcp_directory_claim',[site.plan_id])).result.applied,true);
 assert.equal((await rpc('care_mcp_directory_review',[agent.plan_id,'view'],qg,false)).state,'pending');
 assert.equal((await preview('create_client',{name:'Newly supported'})).kind,'create_client');
 await db.close();
});
