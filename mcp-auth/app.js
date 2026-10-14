/* Separate first-party human surface. No automatic approval, no tokens in query strings. */
(async()=>{
 const $=id=>document.getElementById(id),msg=t=>$('message').textContent=t;
 if(window.top!==window.self){document.body.textContent='Ouvre cette autorisation dans une fenêtre indépendante';return;}
 const q=new URLSearchParams(location.search),plan=q.get('plan'),authorization=q.get('authorization_id'),directory=q.get('directory')==='1',cfg=window.CARE_CONFIG||{};
 if(Boolean(plan)===Boolean(authorization)){msg('Lien incomplet ou ambigu. Rouvre le lien fourni par ChatGPT');return;}
 if(!cfg.supabaseUrl||!cfg.publishableKey||!window.supabase){msg('La configuration publique Azzera Care manque');return;}
 const api=window.supabase.createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
 const unwrap=async p=>{const {data,error}=await p;if(error)throw error;return data;};
 const reviewRpc=directory?'care_mcp_directory_review':'care_mcp_review';
 let mode=null,review;
 const el=(tag,text)=>{const x=document.createElement(tag);if(text!==undefined)x.textContent=text;return x;};
 const labels={title:'Intitulé',site_id:'Site',starts_at:'Début',ends_at:'Fin',agent_ids:'Agents',service_type:'Prestation',description:'Description',instructions:'Consignes terrain',internal_notes:'Notes internes',plan_visible:'Visible au client avant réalisation',tasks:'Checklist',template_id:'Modèle de checklist',reason:'Motif'};
 function showDirectoryReview(r){
  review=r;mode='plan';$('heading').textContent='Vérifier la création';
  const root=$('content');root.replaceChildren();
  root.append(el('h2',r.kind==='create_site'?'Créer un site':'Créer un compte agent'));
  root.append(el('p','État : '+r.state+' — expiration : '+new Date(r.expires_at).toLocaleString('fr-FR',{timeZone:'Europe/Paris'})));
  const names={client_id:'Client',name:'Nom du site',address:'Adresse',general_instructions:'Consignes générales',contacts:'Contacts',full_name:'Nom complet',email:'Adresse e-mail de connexion',role:'Rôle'};
  const dl=el('dl');for(const [k,v] of Object.entries(r.payload)){
   dl.append(el('dt',names[k]||k),el('dd',k==='client_id'?(r.client_name||v):k==='role'?(v==='team_lead'?'Chef d’équipe':'Agent'):v));
  }root.append(dl);
  if(r.kind==='create_agent')root.append(el('p','Cette action crée un compte actif avec le mot de passe initial configuré par votre administrateur. Aucun e-mail ne sera envoyé. Aucun compte existant ne sera modifié. Le rôle ne définit pas le statut contractuel de la personne.'));
  if(r.result)root.append(el('p',r.result.applied?'Création confirmée.':'Création non confirmée. Faire contrôler le compte par le QG avant toute nouvelle tentative.'));
  root.hidden=false;$('actions').hidden=r.state!=='pending'||Date.parse(r.expires_at)<=Date.now();
  msg(r.state==='processing'||r.state==='review_required'?'Un contrôle QG est nécessaire. Ne relance pas une nouvelle création.':'Vérifie les informations. Après ton accord, retourne dans ChatGPT pour exécuter cette création.');
 }
 function showReview(r){
  review=r;$('heading').textContent='Vérifier la proposition';const root=$('content');root.replaceChildren();root.append(el('p','État : '+r.state+' — expiration : '+new Date(r.expires_at).toLocaleString('fr-FR',{timeZone:'Europe/Paris'})));
  const display=(k,v)=>{if(v==null)return 'Non renseigné';if(k==='starts_at'||k==='ends_at')return new Date(v).toLocaleString('fr-FR',{timeZone:'Europe/Paris',timeZoneName:'short'});if(k==='agent_ids')return v.map(id=>r.labels?.agents.find(x=>x.id===id)?.name||id).join(', ');if(k==='site_id')return r.labels?.sites.find(x=>x.id===v)?.name||v;if(k==='tasks')return v.map(t=>t.label+(t.required?' — obligatoire':'')+(t.proof_required?' — preuve : '+t.proof_required:'')).join('\n');if(typeof v==='boolean')return v?'Oui':'Non';return typeof v==='object'?JSON.stringify(v):String(v);};
  for(const [idx,o] of r.operations.entries()){
   const box=el('article'),kind={create:'Créer une intervention',update:'Modifier une intervention',cancel:'Annuler une intervention',accept_request:'Planifier une demande client'}[o.kind];
   box.append(el('h2',(idx+1)+'. '+kind),el('p',o.before?.title||o.payload.title||''));
   if(o.id)box.append(el('small','Intervention : '+o.id));if(o.request_id)box.append(el('small','Demande : '+o.request_id));
   const dl=el('dl');for(const [k,v] of Object.entries(o.payload)){if(k==='id'||JSON.stringify(v)===JSON.stringify(o.before?.[k]))continue;dl.append(el('dt',labels[k]||k));const dd=el('dd');if(o.kind==='update'){const before=el('span','Avant : '+display(k,o.before?.[k]));before.className='before';dd.append(before);}dd.append(el('span',display(k,v)));dl.append(dd);}box.append(dl);root.append(box);
  }
  root.hidden=false;mode='plan';$('actions').hidden=r.state!=='pending'||Date.parse(r.expires_at)<=Date.now();msg('Vérifie chaque changement. Ton accord porte uniquement sur cette proposition. ChatGPT devra ensuite l’exécuter');
 }
 const redirect=data=>{const target=new URL(data.redirect_url);if(target.protocol!=='https:')throw Error('Redirection non sécurisée refusée');location.assign(target.href);};
 async function load(){
  const {data,error}=await api.auth.getUser();if(error||!data.user){$('login').hidden=false;msg('Connecte-toi avec ton compte QG autorisé');return;}
  $('login').hidden=true;
  if(plan){(directory?showDirectoryReview:showReview)(await unwrap(api.rpc(reviewRpc,{p_id:plan,p_decision:'view'})));}
  else {
   const details=await unwrap(api.auth.oauth.getAuthorizationDetails(authorization));
   if(details.redirect_url){redirect(details);return;}
   const access=await unwrap(api.rpc('care_mcp_access',{p_client_id:details.client.id}));
   $('heading').textContent='Connecter Azzera Care à ChatGPT';$('content').replaceChildren(el('p','Application : '+details.client.name),el('p','Compte : '+details.user.email),el('p','Autorisations d’identité demandées : '+details.scope),el('p',access.can_write?'Consultation QG et préparation de modifications. Chaque modification exige ensuite une approbation distincte sur cette page.':'Consultation QG uniquement'),el('p','Les informations consultées seront transmises à ton espace ChatGPT'));
   $('content').hidden=false;$('actions').hidden=false;mode='oauth';msg('Autorise uniquement la connexion que tu viens de demander');
  }
 }
 $('login').onsubmit=async e=>{e.preventDefault();const b=e.target.querySelector('button');b.disabled=true;try{await unwrap(api.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value}));$('password').value='';await load();}catch(e){msg(e.message);}finally{b.disabled=false;}};
 $('checked').onchange=()=>{$('approve').disabled=!$('checked').checked;};
 async function decide(approve){$('approve').disabled=true;$('deny').disabled=true;try{
  if(mode==='plan'){const r=await unwrap(api.rpc(reviewRpc,{p_id:plan,p_decision:approve?'approve':'deny'}));$('actions').hidden=true;msg(r.state==='approved'?'Accord enregistré. Retourne dans ChatGPT et demande l’exécution de ce plan. Aucune modification appliquée à ce stade.':'Proposition refusée. Aucune modification effectuée');}
  else if(mode==='oauth'){const data=await unwrap(api.auth.oauth[approve?'approveAuthorization':'denyAuthorization'](authorization,{skipBrowserRedirect:true}));redirect(data);}
 }catch(e){msg(e.message);$('deny').disabled=false;$('approve').disabled=!$('checked').checked;}}
 $('approve').onclick=()=>{if($('checked').checked)decide(true);};$('deny').onclick=()=>decide(false);
 try{await load();}catch(e){msg(e.message);}
})();
