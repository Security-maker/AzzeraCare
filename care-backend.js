// V3 retains the V2 Supabase Auth and private Storage integration, with server RPC writes.
import {validateFile} from './modules/domain.js';
const cfg=window.CARE_CONFIG||{};
const configured=Boolean(/^https:\/\//.test(cfg.supabaseUrl||'')&&!/YOUR_PROJECT/.test(cfg.supabaseUrl)&&cfg.publishableKey&&!/xxxxx/.test(cfg.publishableKey)&&window.supabase);
const client=configured?window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
function assert(){if(!client)throw new Error('La connexion Azzera Care n’est pas configurée.');}
async function unwrap(p){const {data,error}=await p;if(error)throw error;return data;}
export const api={configured,client,
 async session(){return client?(await unwrap(client.auth.getSession())).session:null;},
 async signIn(email,password){assert();return unwrap(client.auth.signInWithPassword({email,password}));},
 async signOut(){assert();await unwrap(client.auth.signOut());},
 async resetPassword(email){assert();await unwrap(client.auth.resetPasswordForEmail(email,{redirectTo:new URL('index.html?recovery=1&portal='+(new URLSearchParams(location.search).get('portal')==='client'?'client':'pro'),location.href).href}));},
 async password(password){assert();await unwrap(client.auth.updateUser({password}));},
 async push(op,p={}){assert();const {data,error}=await client.rpc('care_push_device',{p_op:op,p});if(error){if(['PGRST202','42883'].includes(error.code))throw new Error('Les notifications ne sont pas encore installées dans Supabase.');throw error;}return data;},
 async snapshot(){assert();return unwrap(client.rpc('care_v3_snapshot'));},
 async action(kind,payload={},key=crypto.randomUUID()){assert();return unwrap(client.rpc('care_v3_action',{p_kind:kind,p:payload,p_key:key}));},
 async acceptRequest(requestId,payload,key){
  assert();const {data,error}=await client.rpc('care_v3_accept_request',{p_request_id:requestId,p:payload,p_key:key});
  if(error){if(['PGRST202','42883'].includes(error.code))throw new Error('La mise à jour SQL Demandes → interventions doit être installée dans Supabase avant cette action.');throw error;}return data;
 },
 async invite(payload){
  assert();const {data,error}=await client.functions.invoke('invite-user',{body:payload});
  if(error){
   let detail='';
   try{const body=await error.context.clone().json();detail=[body?.error,body?.message].find(v=>typeof v==='string'&&v.trim())||'';}catch{}
   throw new Error(detail||error.message||'Invitation impossible. Consulte les journaux de la fonction invite-user.');
  }
  if(data?.error)throw new Error(data.error);return data;
 },
 async upload(file,{intervention_id=null,request_id=null,task_id=null,category='general',caption='',publishable=false,document=false,title='',visibility='internal',site_id=null,client_id=null},profile){
  assert();validateFile(file,document);
  const ext=({'image/jpeg':'jpg','image/png':'png','image/webp':'webp','application/pdf':'pdf'})[file.type];
  const scope=document?'documents':request_id?`request-${request_id}`:intervention_id;
  if(!scope)throw new Error('Affectation du fichier manquante.');
  const path=`${profile.organization_id}/${scope}/${crypto.randomUUID()}.${ext}`;
  await unwrap(client.storage.from('care-media').upload(path,file,{upsert:false,cacheControl:'0',contentType:file.type}));
  try{return await api.action(document?'document':'photo',{storage_path:path,intervention_id,request_id,task_id,category,caption,publishable,title,visibility,site_id,client_id});}
  catch(error){const {error:cleanup}=await client.storage.from('care-media').remove([path]);if(cleanup)error.message+=' Le fichier non lié reste privé ; nettoyage QG nécessaire.';throw error;}
 },
 async file(path){assert();return (await unwrap(client.storage.from('care-media').createSignedUrl(path,60))).signedUrl;}
};
