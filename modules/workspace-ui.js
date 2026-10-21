import {dayKey} from './domain.js';
const normalize=value=>String(value??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('fr-FR');
export function filterInterventions(w,{site='',month='',status='',agent='',search=''}={}){
 const needle=normalize(search).trim();
 return w.interventions.filter(i=>{
  if(site&&i.site_id!==site||month&&dayKey(i.starts_at).slice(0,7)!==month||status&&i.status!==status)return false;
  const team=w.assignments.filter(a=>a.intervention_id===i.id);
  if(agent&&!team.some(a=>a.agent_id===agent))return false;
  const text=[i.title,w.sites.find(s=>s.id===i.site_id)?.name,...team.map(a=>w.people.find(p=>p.id===a.agent_id)?.full_name)].join(' ');
  return !needle||normalize(text).includes(needle);
 });
}
export function qgPriorities(w,now=new Date()){
 return {
  starts:w.interventions.filter(i=>['planned','upcoming','in_progress','partial'].includes(i.status)&&new Date(i.starts_at)<now&&w.assignments.some(a=>a.intervention_id===i.id&&!a.started_at&&!a.ended_at)).sort((a,b)=>new Date(a.starts_at)-new Date(b.starts_at)),
  issues:w.issues.filter(i=>!['resolved','closed'].includes(i.status)),
  requests:w.requests.filter(r=>['new','in_progress'].includes(r.request_state)&&!r.intervention_id),
  publications:w.interventions.filter(i=>i.publication_state==='failed')
 };
}
