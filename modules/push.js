// No permission request during boot. Activation must originate from a user gesture.
export function pushSupport(){
 const ios=/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
 if(ios&&!matchMedia('(display-mode: standalone)').matches&&!navigator.standalone)return 'Sur iPhone/iPad : Partager → Sur l’écran d’accueil, puis ouvre Azzera Care depuis son icône (iOS 16.4 ou plus récent).';
 if(!window.isSecureContext||!('serviceWorker' in navigator)||!('PushManager' in window)||!('Notification' in window))return 'Les notifications ne sont pas disponibles dans ce navigateur. Ouvre la version HTTPS dans un navigateur compatible.';
 return '';
}
export function keyBytes(key){return Uint8Array.from(atob(key.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));}
export function createPush(api){
 let registration;
 const register=async()=>registration||=await navigator.serviceWorker.register('./service-worker.js');
 const active=async()=>{await register();return Promise.race([navigator.serviceWorker.ready,new Promise((_,reject)=>setTimeout(()=>reject(new Error('Le service de notifications ne démarre pas. Recharge la page.')),12000))]);};
 const subscription=async()=>{if(pushSupport())return null;return (await active()).pushManager.getSubscription();};
 const rpc=async(op,p={})=>api.push(op,p);
 return {
  async status(){const sub=await subscription();return {...await rpc('status',{endpoint:sub?.endpoint}),permission:'Notification' in window?Notification.permission:'unsupported'};},
  async reconcile(){if(pushSupport())return;const sub=await subscription();if(!sub)return;const s=await rpc('status',{endpoint:sub.endpoint});if(!s.enabled)await sub.unsubscribe();},
  async enable(publicKey){
   const unsupported=pushSupport();if(unsupported)throw new Error(unsupported);
   if(!publicKey||publicKey.length!==87)throw new Error('Les notifications doivent d’abord être configurées dans Supabase.');
   // This call is deliberately before any await to preserve the iOS user gesture.
   const permission=await Notification.requestPermission();
   if(permission!=='granted')throw new Error('Autorisation refusée. Autorise les notifications dans les réglages de ton navigateur ou de l’application.');
   const r=await active();let sub=await r.pushManager.getSubscription();
   if(sub){const state=await rpc('status',{endpoint:sub.endpoint});if(!state.enabled){await sub.unsubscribe();sub=null;}}
   sub||=await r.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:keyBytes(publicKey)});
   const data=sub.toJSON();
   try{await rpc('subscribe',{endpoint:data.endpoint,p256dh:data.keys.p256dh,auth:data.keys.auth,public_key:publicKey});}
   catch(err){await sub.unsubscribe().catch(()=>{});throw err;}
  },
  async disable(){const sub=await subscription();if(!sub)return;await rpc('unsubscribe',{endpoint:sub.endpoint});await sub.unsubscribe();},
  async disableAll(){await rpc('disable_all');const sub=await subscription();await sub?.unsubscribe();},
  async logout(){
   // Browser unsubscribe still runs if the backend is offline. Do not block sign-out.
   if(pushSupport())return;try{const sub=await subscription();if(!sub)return;try{await rpc('unsubscribe',{endpoint:sub.endpoint});}finally{await sub.unsubscribe();}}catch{}
   try{const r=await register();for(const n of await r.getNotifications())n.close();}catch{}
  },
  async test(){const sub=await subscription();if(!sub)throw new Error('Active les notifications sur cet appareil.');await rpc('test',{endpoint:sub.endpoint});},
  async retry(){await rpc('retry');}
 };
}
