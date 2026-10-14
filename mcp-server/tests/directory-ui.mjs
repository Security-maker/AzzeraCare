import {chromium} from 'playwright';import http from 'node:http';import fs from 'node:fs/promises';import path from 'node:path';import assert from 'node:assert/strict';
const root=process.cwd(),server=http.createServer(async(req,res)=>{try{const f=path.resolve(root,'.'+new URL(req.url,'http://localhost').pathname);if(!f.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',f.endsWith('.js')?'text/javascript':f.endsWith('.css')?'text/css':f.endsWith('.svg')?'image/svg+xml':'text/html');res.end(await fs.readFile(f));}catch{res.writeHead(404).end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({headless:true,channel:'chrome'});let checks=0;
try{
 const p=await browser.newPage({viewport:{width:390,height:844}});const errors=[];p.on('pageerror',e=>{errors.push(e.message);console.error('PAGEERROR',e.message)});p.on('console',m=>{if(m.type()==='error')console.error('BROWSER',m.text())});
 await p.route('**/config.js',route=>route.fulfill({contentType:'text/javascript',body:"window.CARE_CONFIG={supabaseUrl:'https://test.supabase.co',publishableKey:'public'}"}));

 const mock=()=>{
  window.rpcCalls=[];
  window.supabase={createClient:()=>({auth:{getUser:async()=>({data:{user:{id:'qg'}}})},rpc:async(name,args)=>{
   window.rpcCalls.push({name,args});const site=new URLSearchParams(location.search).get('plan')==='site';
   return {data:{kind:site?'create_site':'create_agent',state:args.p_decision==='view'?'pending':args.p_decision==='approve'?'approved':'denied',expires_at:new Date(Date.now()+600000).toISOString(),client_name:'Client réel',payload:site?{name:'Site test',client_id:'client',general_instructions:'<img src=x onerror=alert(1)>'}:{full_name:'Agent Test',email:'agent@example.test',role:'agent'}}};
  }})};
 };
 await p.route('**/vendor/supabase.js',route=>route.fulfill({contentType:'text/javascript',body:'('+mock.toString()+')()'}));
 for(const kind of ['site','agent']){
  await p.goto(base+'/mcp-auth/index.html?directory=1&plan='+kind);
  await p.getByRole('heading',{name:'Vérifier la création'}).waitFor();
  assert.equal(await p.getByRole('button',{name:'Autoriser',exact:true}).isDisabled(),true);checks++;
  assert.equal(await p.locator('#content img').count(),0);assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);checks++;
  if(kind==='agent')assert.match(await p.locator('#content').innerText(),/Aucun e-mail ne sera envoyé/);
  else assert.match(await p.locator('#content').innerText(),/Client réel/);
  await p.screenshot({path:'output/mcp-directory-patch/approval-'+kind+'.png',fullPage:true});
  await p.getByRole('checkbox').check();await p.getByRole('button',{name:'Autoriser',exact:true}).click();await p.getByText(/Accord enregistré/).waitFor();
  const calls=await p.evaluate(()=>window.rpcCalls);assert.equal(calls.filter(c=>c.args.p_decision==='approve').length,1);assert.ok(calls.every(c=>c.name==='care_mcp_directory_review'));checks++;
 }
 await p.goto(base+'/mcp-auth/index.html?directory=1&plan=agent');await p.getByRole('heading',{name:'Vérifier la création'}).waitFor();await p.getByRole('button',{name:'Refuser',exact:true}).click();await p.getByText(/Proposition refusée/).waitFor();checks++;
 assert.deepEqual(errors,[]);console.log('PASS directory UI '+checks+' checks (mocked Auth/RPC, real browser)');
}finally{await browser.close();await new Promise(r=>server.close(r));}
