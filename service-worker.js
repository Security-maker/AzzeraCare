const CACHE='azzera-care-v3-shell-10';
const ASSETS=['./index.html','./client.html','./style.css','./app.js','./modules/push.js','./modules/reports.js','./modules/domain.js','./modules/icons.js','./care-backend.js','./vendor/supabase.js','./manifest.json','./assets/logo-azzera.png','./assets/favicon-a.svg','./assets/favicon-a-16.png','./assets/favicon-a-32.png','./assets/icons/apple-touch-care-large.png','./assets/icons/care-large-192.png','./assets/icons/care-large-512.png'];
const allowed=new Set(ASSETS.map(p=>new URL(p,self.location.href).href));
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('azzera-care-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{const url=new URL(e.request.url);if(e.request.method!=='GET'||url.origin!==self.location.origin||url.search||!allowed.has(url.href))return;e.respondWith(fetch(e.request).catch(()=>caches.match(e.request)));});

self.addEventListener('push',event=>{
 event.waitUntil((async()=>{
  let data={};try{data=event.data?.json()||{};}catch{}
  // Never display business data, photos or names on a locked device.
  let url=new URL('index.html#notifications',self.registration.scope);
  try{const target=new URL(data.url);if(target.origin===url.origin&&target.pathname.startsWith(new URL(self.registration.scope).pathname))url=target;}catch{}
  await self.registration.showNotification('Azzera Care',{body:'Une nouvelle information est disponible dans votre espace.',icon:new URL('assets/icons/care-large-192.png',self.registration.scope).href,badge:new URL('assets/icons/care-large-192.png',self.registration.scope).href,tag:typeof data.tag==='string'?data.tag.slice(0,100):'care-update',data:{url:url.href}});
 })());
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{
  const base=new URL(self.registration.scope);let url=new URL('index.html#notifications',base);
  try{const target=new URL(event.notification.data?.url);if(target.origin===base.origin&&target.pathname.startsWith(base.pathname))url=target;}catch{}
  // Opens the right portal; normal authentication and RLS still apply.
  await self.clients.openWindow(url.href);
 })());
});
