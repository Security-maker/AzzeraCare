-- QG administration 1.3. Additive migration after MCP 1.2. No business record is changed on install.
begin;
-- Save prior definitions once, for an explicit code rollback; never rollback business data.
create table if not exists private.care_qg_originals(signature text primary key,definition text not null);
alter table private.care_qg_originals enable row level security;
revoke all on private.care_qg_originals from public,anon,authenticated;
insert into private.care_qg_originals(signature,definition)
select sig,pg_get_functiondef(sig::regprocedure) from unnest(array[
 'private.v3_action_pre_mcp(text,jsonb,uuid)','private.v3_snapshot_pre_mcp()',
 'private.mcp_before(uuid)','private.mcp_prepare(jsonb)','private.mcp_apply(jsonb,boolean)']) sig
on conflict do nothing;
alter table public.clients add column if not exists deleted_at timestamptz, add column if not exists updated_at timestamptz not null default now();
alter table public.sites add column if not exists deleted_at timestamptz, add column if not exists updated_at timestamptz not null default now();
alter table public.profiles add column if not exists deleted_at timestamptz;
create or replace function private.qg_before(kind text,x uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare image_value jsonb;
begin
 if kind in ('client','update_client','delete_client') then
  select to_jsonb(c) into image_value from public.clients c where id=x and organization_id=private.current_org_id();
 elsif kind in ('site','update_site','delete_site') then
  select to_jsonb(s) into image_value from public.sites s where id=x and organization_id=private.current_org_id();
 elsif kind in ('profile','update_agent','delete_agent') then
  select to_jsonb(p) into image_value from public.profiles p where id=x and organization_id=private.current_org_id();
 else
  if kind='task' then select intervention_id into x from public.intervention_tasks where id=x; end if;
  select to_jsonb(i)||jsonb_build_object(
   'agent_ids',coalesce((select jsonb_agg(agent_id order by agent_id) from public.intervention_agents where intervention_id=x),'[]'),
   'participations',coalesce((select jsonb_agg(a order by agent_id) from public.intervention_agents a where intervention_id=x),'[]'),
   'tasks',coalesce((select jsonb_agg(t order by sort_order,id) from public.intervention_tasks t where intervention_id=x),'[]'),
   'photos',coalesce((select jsonb_agg(p order by id) from public.photos p where intervention_id=x),'[]'),
   'logs',coalesce((select jsonb_agg(l order by id) from public.logbook_entries l where intervention_id=x),'[]'),
   'reports',coalesce((select jsonb_agg(r) from public.care_reports r where intervention_id=x),'[]'),
   'requests',coalesce((select jsonb_agg(r order by id) from public.client_requests r where intervention_id=x),'[]'),
   'documents',coalesce((select jsonb_agg(d order by id) from public.documents d where intervention_id=x),'[]'),
   'issues',coalesce((select jsonb_agg(v order by id) from public.issues v where intervention_id=x),'[]'),
   'quality',coalesce((select jsonb_agg(v order by id) from public.quality_controls v where intervention_id=x),'[]')
  ) into image_value from public.interventions i where i.id=x and i.organization_id=private.current_org_id();
 end if;
 return image_value;
end $$;
revoke all on function private.qg_before(text,uuid) from public,anon,authenticated;
create or replace function private.mcp_before(x uuid) returns jsonb language sql security definer set search_path='' as $$ select private.qg_before('intervention',x) $$;
-- Checklist / pointage changes invalidate a browser form's old version too.
create or replace function private.qg_touch_intervention() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.interventions set updated_at=clock_timestamp() where id=coalesce(new.intervention_id,old.intervention_id);
 return null;
end $$;
revoke all on function private.qg_touch_intervention() from public,anon,authenticated;
drop trigger if exists qg_task_revision on public.intervention_tasks;
create trigger qg_task_revision after insert or update or delete on public.intervention_tasks for each row execute function private.qg_touch_intervention();
drop trigger if exists qg_assignment_revision on public.intervention_agents;
create trigger qg_assignment_revision after insert or update or delete on public.intervention_agents for each row execute function private.qg_touch_intervention();
drop trigger if exists qg_photos_revision on public.photos;
create trigger qg_photos_revision after insert or update or delete on public.photos for each row execute function private.qg_touch_intervention();
drop trigger if exists qg_logbook_entries_revision on public.logbook_entries;
create trigger qg_logbook_entries_revision after insert or update or delete on public.logbook_entries for each row execute function private.qg_touch_intervention();
drop trigger if exists qg_issues_revision on public.issues;
create trigger qg_issues_revision after insert or update or delete on public.issues for each row execute function private.qg_touch_intervention();
drop trigger if exists qg_documents_revision on public.documents;
create trigger qg_documents_revision after insert or update or delete on public.documents for each row execute function private.qg_touch_intervention();
drop trigger if exists qg_quality_controls_revision on public.quality_controls;
create trigger qg_quality_controls_revision after insert or update or delete on public.quality_controls for each row execute function private.qg_touch_intervention();
drop trigger if exists qg_care_reports_revision on public.care_reports;
create trigger qg_care_reports_revision after insert or update or delete on public.care_reports for each row execute function private.qg_touch_intervention();
drop trigger if exists qg_client_requests_revision on public.client_requests;
create trigger qg_client_requests_revision after insert or update or delete on public.client_requests for each row execute function private.qg_touch_intervention();
create or replace function private.v3_action_pre_mcp(p_kind text,p jsonb,p_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare me public.profiles; q boolean; x uuid; sid uuid; cid uuid; i public.interventions; a public.intervention_agents; t public.intervention_tasks; oldcmd private.care_commands; obj jsonb; item jsonb; aid uuid; result jsonb:='{}'; oldids uuid[]; newids uuid[]; published boolean; target public.profiles; before_value jsonb; oldtask public.intervention_tasks; kept uuid[]; pos integer;
begin
 if auth.uid() is null or p_key is null or p is null or length(p::text)>100000 then raise exception 'Requête invalide'; end if;
 -- Serialize duplicate commands from the same actor, including concurrent retries.
 select * into me from public.profiles where id=auth.uid() and active for update;
 if me.id is null then raise exception 'Compte non autorisé ou désactivé'; end if;
 select * into oldcmd from private.care_commands where actor=me.id and key=p_key;
 if found then if oldcmd.kind<>p_kind or oldcmd.input<>p then raise exception 'Clé de requête déjà utilisée'; end if; return oldcmd.result; end if;
 q:=private.is_qg(); x:=nullif(p->>'id','')::uuid;
 if x is not null and q then
  before_value:=private.qg_before(p_kind,x);
  if p?'expected_updated_at' and p->>'expected_updated_at' is not null and
    (before_value->>'updated_at')::timestamptz is distinct from (p->>'expected_updated_at')::timestamptz then
   raise exception 'Fiche modifiée depuis son ouverture. Actualise avant de recommencer.';
  end if;
 end if;
 if p_kind in ('start','finish','note','task','issue','retry_publication','correct_report','photo_permission') then
  if p_kind='task' then select * into t from public.intervention_tasks where id=x; x:=t.intervention_id; end if;
  if p_kind='photo_permission' then select intervention_id into x from public.photos where id=x; end if;
  if not coalesce(private.v3_can_intervention(x),false) then raise exception 'Intervention non autorisée'; end if;
  select * into i from public.interventions where id=x for update;
  select * into a from public.intervention_agents where intervention_id=x and agent_id=me.id;
  if p_kind in ('start','finish') and not private.is_assigned(x) then raise exception 'Participation non autorisée'; end if;
  if p_kind in ('note','task','issue') and not q and (a.started_at is null or a.ended_at is not null) then raise exception 'Démarre ta participation avant cette action'; end if;
  if not q and p_kind in ('start','note','task','issue') and i.status in ('completed','validated','cancelled','impossible') then raise exception 'Intervention verrouillée'; end if;
  if p_kind='start' then
   if a.ended_at is not null then raise exception 'Participation déjà terminée'; end if;
   if a.started_at is null then update public.intervention_agents set started_at=now() where intervention_id=x and agent_id=me.id; update public.interventions set status='in_progress',updated_at=now() where id=x; perform private.v3_log(x,'start','Participation démarrée'); end if;
  elsif p_kind='finish' then
   if a.started_at is null then raise exception 'La participation doit être démarrée'; end if;
   if a.ended_at is null then
    if exists(select 1 from public.intervention_tasks where intervention_id=x and required and not completed) and length(btrim(coalesce(p->>'reason','')))<5 then raise exception 'Tâches obligatoires manquantes : indique un motif précis'; end if;
    update public.intervention_agents set ended_at=now(),final_observation=left(p->>'reason',5000) where intervention_id=x and agent_id=me.id;
    update public.interventions set status=case when exists(select 1 from public.intervention_agents where intervention_id=x and ended_at is null) then 'in_progress'::public.intervention_status else 'completed'::public.intervention_status end, completed_at=case when not exists(select 1 from public.intervention_agents where intervention_id=x and ended_at is null) then now() else null end,updated_at=now() where id=x;
    perform private.v3_log(x,'finish','Participation terminée',left(p->>'reason',5000));
    published:=private.v3_publish(x);
   else select publication_state='published' into published from public.interventions where id=x; end if;
   result:=jsonb_build_object('finished',true,'published',published,'publication_state',(select publication_state from public.interventions where id=x));
  elsif p_kind='task' then
   select * into t from public.intervention_tasks where id=t.id for update;
   if t.completed is distinct from coalesce((p->>'expected')::boolean,false) then raise exception 'Tâche modifiée par un autre agent. Actualise.'; end if;
   if coalesce((p->>'completed')::boolean,false) then
    if t.proof_required='photo' and not exists(select 1 from public.photos where task_id=t.id and intervention_id=x) then raise exception 'Photo obligatoire manquante'; end if;
    if t.proof_required='comment' and length(btrim(coalesce(p->>'comment','')))<3 then raise exception 'Commentaire obligatoire'; end if;
   end if;
   update public.intervention_tasks set completed=(p->>'completed')::boolean,completed_by=case when (p->>'completed')::boolean then me.id end,completed_at=case when (p->>'completed')::boolean then now() end,comment=left(p->>'comment',3000) where id=t.id;
   perform private.v3_log(x,'task','Checklist modifiée',t.label);
  elsif p_kind='note' then
   if length(btrim(coalesce(p->>'details','')))<2 then raise exception 'Observation vide'; end if;
   if coalesce((p->>'publishable')::boolean,false) then update public.interventions set client_summary=concat_ws(E'\n',nullif(client_summary,''),left(p->>'details',3000)) where id=x; end if;
   perform private.v3_log(x,'note',case when coalesce((p->>'publishable')::boolean,false) then 'Observation publiable' else 'Observation interne' end,left(p->>'details',3000));
  elsif p_kind='issue' then
   if length(btrim(coalesce(p->>'title','')))<3 then raise exception 'Titre requis'; end if;
   insert into public.issues(organization_id,site_id,intervention_id,reported_by,category,priority,title,details) values(me.organization_id,i.site_id,x,me.id,left(coalesce(p->>'category','other'),40),coalesce(p->>'priority','normal'),left(p->>'title',200),left(p->>'details',5000));
   perform private.v3_log(x,'issue','Signalement enregistré',p->>'title');
  elsif p_kind in ('retry_publication','correct_report','photo_permission') then
   if p_kind='retry_publication' then
    if not q and a.ended_at is null then raise exception 'Reprise non autorisée'; end if;
    if i.publication_state='published' then result:=jsonb_build_object('published',true); else result:=jsonb_build_object('published',private.v3_publish(x)); end if;
   else
    if not q then raise exception 'Action QG uniquement'; end if;
    if length(btrim(coalesce(p->>'reason','')))<5 then raise exception 'Motif de correction requis'; end if;
    if p_kind='correct_report' then update public.interventions set client_summary=left(p->>'client_summary',10000) where id=x;
    else update public.photos set publishable=(p->>'publishable')::boolean where id=(p->>'id')::uuid; end if;
    perform private.v3_log(x,'correction','Correction QG',p->>'reason');
    if exists(select 1 from public.intervention_agents where intervention_id=x and ended_at is not null) then result:=jsonb_build_object('published',private.v3_publish(x)); end if;
   end if;
  end if;
 elsif p_kind='delete_intervention' then
  if not q then raise exception 'Action QG uniquement'; end if;
  if length(btrim(coalesce(p->>'reason','')))<5 then raise exception 'Motif de suppression requis'; end if;
  select * into i from public.interventions where id=x and organization_id=me.organization_id for update;
  if not found then raise exception 'Intervention introuvable'; end if;
  -- Audit retains the data before deletion. Storage bytes remain private, not publicly linked.
  update public.client_requests set intervention_id=null,request_state='cancelled',updated_at=now() where intervention_id=x;
  delete from public.care_reports where intervention_id=x;
  delete from private.care_publication_attempts where intervention_id=x;
  delete from public.notifications where entity_id=x and entity_type='intervention';
  delete from public.interventions where id=x;
  result:=jsonb_build_object('deleted',true,'storage_retained',true);
 elsif p_kind in ('delete_client','delete_site','delete_agent') then
  if not q or before_value is null then raise exception 'Fiche non autorisée'; end if;
  if length(btrim(coalesce(p->>'reason','')))<5 then raise exception 'Motif de suppression requis'; end if;
  if p_kind='delete_client' then update public.clients set active=false,deleted_at=clock_timestamp(),updated_at=clock_timestamp() where id=x and organization_id=me.organization_id;
  elsif p_kind='delete_site' then update public.sites set active=false,deleted_at=clock_timestamp(),updated_at=clock_timestamp() where id=x and organization_id=me.organization_id;
  else
   if not exists(select 1 from public.profiles where id=x and organization_id=me.organization_id and role in ('agent','team_lead')) or x=me.id then raise exception 'Compte protégé'; end if;
   update public.profiles set active=false,deleted_at=clock_timestamp(),updated_at=clock_timestamp() where id=x;
  end if;
  result:=jsonb_build_object('deleted',true,'archived',true,'history_retained',true);
 elsif p_kind='client' then
  if not q then raise exception 'Action QG uniquement'; end if;
  if length(btrim(coalesce(p->>'name','')))<2 then raise exception 'Nom requis'; end if;
  if x is null then insert into public.clients(organization_id,name,email,phone,contacts) values(me.organization_id,left(p->>'name',200),left(p->>'email',250),left(p->>'phone',50),left(p->>'contacts',4000)) returning id into x;
  else update public.clients set name=left(p->>'name',200),email=left(p->>'email',250),phone=left(p->>'phone',50),contacts=left(p->>'contacts',4000),active=coalesce((p->>'active')::boolean,true),deleted_at=case when coalesce((p->>'active')::boolean,true) then null else deleted_at end,updated_at=clock_timestamp() where id=x and organization_id=me.organization_id; if not found then raise exception 'Client introuvable'; end if; end if;
 elsif p_kind='site' then
  if not q then raise exception 'Action QG uniquement'; end if;
  cid:=(p->>'client_id')::uuid;
  if not exists(select 1 from public.clients where id=cid and organization_id=me.organization_id) then raise exception 'Client non autorisé'; end if;
  if length(btrim(coalesce(p->>'name','')))<2 then raise exception 'Nom requis'; end if;
  if x is null then insert into public.sites(organization_id,client_id,name,address,access_notes,general_instructions,contacts) values(me.organization_id,cid,left(p->>'name',200),left(p->>'address',1000),left(p->>'access_notes',5000),left(p->>'general_instructions',5000),left(p->>'contacts',4000)) returning id into x;
  else
   if exists(select 1 from public.sites where id=x and organization_id=me.organization_id and client_id<>cid) and length(btrim(coalesce(p->>'reason','')))<5 then raise exception 'Motif requis pour changer de client : les historiques du site seront accessibles au nouveau client'; end if;
   update public.sites set client_id=cid,name=left(p->>'name',200),address=left(p->>'address',1000),access_notes=left(p->>'access_notes',5000),general_instructions=left(p->>'general_instructions',5000),contacts=left(p->>'contacts',4000),active=coalesce((p->>'active')::boolean,true),deleted_at=case when coalesce((p->>'active')::boolean,true) then null else deleted_at end,updated_at=clock_timestamp() where id=x and organization_id=me.organization_id; if not found then raise exception 'Site introuvable'; end if;
  end if;
 elsif p_kind='profile' then
  if not q or x=me.id then raise exception 'Modification non autorisée'; end if;
  select * into target from public.profiles where id=x and organization_id=me.organization_id;
  if target.id is null or target.role='qg_admin' or (me.role='qg_manager' and target.role='qg_manager') then raise exception 'Compte protégé'; end if;
  if length(btrim(coalesce(p->>'full_name','')))<2 then raise exception 'Nom requis'; end if;
  if p?'role' and (target.role not in ('agent','team_lead') or p->>'role' not in ('agent','team_lead')) then raise exception 'Rôle protégé'; end if;
  update public.profiles set role=case when p?'role' then (p->>'role')::public.care_role else role end,deleted_at=case when (p->>'active')::boolean then null else deleted_at end,full_name=left(p->>'full_name',200),phone=left(p->>'phone',50),active=(p->>'active')::boolean,updated_at=now() where id=x;
 elsif p_kind='intervention' then
  if not q then raise exception 'Action QG uniquement'; end if;
  sid:=(p->>'site_id')::uuid;
  if not exists(select 1 from public.sites s join public.clients c on c.id=s.client_id where s.id=sid and s.organization_id=me.organization_id and ((s.active and c.active) or exists(select 1 from public.interventions v where v.id=x and v.site_id=sid and v.organization_id=me.organization_id))) then raise exception 'Site non autorisé'; end if;
  if length(btrim(coalesce(p->>'title','')))<3 or (p->>'ends_at')::timestamptz <= (p->>'starts_at')::timestamptz then raise exception 'Intitulé ou horaires invalides'; end if;
  if jsonb_array_length(coalesce(p->'agent_ids','[]'))=0 then raise exception 'Affecter au moins un agent'; end if;
  select array_agg(distinct value::uuid) into newids from jsonb_array_elements_text(p->'agent_ids');
  foreach aid in array newids loop if not exists(select 1 from public.profiles where id=aid and (active or exists(select 1 from public.intervention_agents where intervention_id=x and agent_id=aid)) and organization_id=me.organization_id and role in ('agent','team_lead')) then raise exception 'Agent non autorisé'; end if; end loop;
  if x is not null then
   select * into i from public.interventions where id=x and organization_id=me.organization_id for update;
   if i.id is null then raise exception 'Intervention introuvable'; end if;
   if i.site_id<>sid then
    if exists(select 1 from public.client_requests where intervention_id=x and site_id<>sid) then raise exception 'Corriger d’abord le rattachement de la demande client liée'; end if;
    if length(btrim(coalesce(p->>'reason','')))<5 then raise exception 'Motif requis pour changer le site et la visibilité des preuves'; end if;
    update public.photos set site_id=sid where intervention_id=x;
    update public.logbook_entries set site_id=sid where intervention_id=x;
    update public.issues set site_id=sid where intervention_id=x;
    update public.quality_controls set site_id=sid where intervention_id=x;
    update public.documents set site_id=sid,client_id=(select client_id from public.sites where id=sid) where intervention_id=x;
   end if;
   update public.interventions set site_id=sid,status=coalesce((p->>'status')::public.intervention_status,status),client_summary=case when p?'client_summary' then left(p->>'client_summary',10000) else client_summary end,title=left(p->>'title',200),starts_at=(p->>'starts_at')::timestamptz,ends_at=(p->>'ends_at')::timestamptz,service_type=left(p->>'service_type',60),description=left(p->>'description',5000),instructions=left(p->>'instructions',5000),internal_notes=left(p->>'internal_notes',5000),plan_visible=coalesce((p->>'plan_visible')::boolean,false),updated_at=now() where id=x;
   delete from public.intervention_agents where intervention_id=x and not(agent_id=any(newids));
  else
   insert into public.interventions(organization_id,site_id,title,starts_at,ends_at,created_by,service_type,description,instructions,internal_notes,plan_visible) values(me.organization_id,sid,left(p->>'title',200),(p->>'starts_at')::timestamptz,(p->>'ends_at')::timestamptz,me.id,left(p->>'service_type',60),left(p->>'description',5000),left(p->>'instructions',5000),left(p->>'internal_notes',5000),coalesce((p->>'plan_visible')::boolean,false)) returning id into x;
   if nullif(p->>'template_id','') is not null then
    if not exists(select 1 from public.service_templates where id=(p->>'template_id')::uuid and organization_id=me.organization_id) then raise exception 'Modèle non autorisé'; end if;
    insert into public.intervention_tasks(intervention_id,zone_label,label,proof_required,required,sort_order) select x,zone_label,label,proof_required,required,sort_order from public.service_template_tasks where template_id=(p->>'template_id')::uuid;
   end if;
   for item in select * from jsonb_array_elements(coalesce(p->'tasks','[]')) loop
    if length(btrim(coalesce(item->>'label','')))<2 then raise exception 'Libellé tâche requis'; end if;
    insert into public.intervention_tasks(intervention_id,label,proof_required,required,sort_order) values(x,left(item->>'label',500),coalesce(item->>'proof_required','none'),coalesce((item->>'required')::boolean,true),coalesce((item->>'sort_order')::int,0));
   end loop;
  end if;
  foreach aid in array newids loop insert into public.intervention_agents(intervention_id,agent_id) values(x,aid) on conflict do nothing; end loop;
  if i.id is not null and p?'tasks' then
   if jsonb_typeof(p->'tasks')<>'array' or jsonb_array_length(p->'tasks')>100 then raise exception 'Checklist invalide'; end if;
   kept:='{}';pos:=0;
   for item in select value from jsonb_array_elements(p->'tasks') loop
    if jsonb_typeof(item)<>'object' or length(btrim(coalesce(item->>'label','')))<2 then raise exception 'Libellé tâche requis'; end if;
    if exists(select 1 from jsonb_object_keys(item) f where f not in ('id','label','zone_label','proof_required','required','sort_order','completed','comment')) then raise exception 'Champ checklist inconnu'; end if;
    aid:=nullif(item->>'id','')::uuid;
    if aid is not null then
     if aid=any(kept) then raise exception 'Tâche dupliquée'; end if;
     select * into oldtask from public.intervention_tasks where id=aid and intervention_id=x for update;
     if not found then raise exception 'Tâche étrangère ou supprimée'; end if;
     update public.intervention_tasks set label=left(item->>'label',500),zone_label=left(item->>'zone_label',200),proof_required=coalesce(item->>'proof_required',oldtask.proof_required),required=coalesce((item->>'required')::boolean,oldtask.required),sort_order=pos,
      comment=case when item?'comment' then left(item->>'comment',3000) else comment end,
      completed=coalesce((item->>'completed')::boolean,completed),
      completed_by=case when item?'completed' and (item->>'completed')::boolean is distinct from completed then case when (item->>'completed')::boolean then me.id end else completed_by end,
      completed_at=case when item?'completed' and (item->>'completed')::boolean is distinct from completed then case when (item->>'completed')::boolean then now() end else completed_at end
     where id=aid;
    else
     insert into public.intervention_tasks(intervention_id,label,zone_label,proof_required,required,sort_order,completed,completed_by,completed_at,comment)
     values(x,left(item->>'label',500),left(item->>'zone_label',200),coalesce(item->>'proof_required','none'),coalesce((item->>'required')::boolean,true),pos,coalesce((item->>'completed')::boolean,false),case when (item->>'completed')::boolean then me.id end,case when (item->>'completed')::boolean then now() end,left(item->>'comment',3000)) returning id into aid;
    end if;
    kept:=array_append(kept,aid);pos:=pos+1;
   end loop;
   -- A removed task detaches its photos; it never destroys them.
   delete from public.intervention_tasks where intervention_id=x and not(id=any(kept));
  end if;
  if p?'participations' then
   if jsonb_typeof(p->'participations')<>'array' or jsonb_array_length(p->'participations')>100 then raise exception 'Pointages invalides'; end if;
   kept:='{}';
   for item in select value from jsonb_array_elements(p->'participations') loop
    if item->>'agent_id' is null or not(item->>'agent_id'=any(newids::text[])) then raise exception 'Participation non affectée'; end if;
    if (item->>'agent_id')::uuid=any(kept) then raise exception 'Pointage dupliqué'; end if;kept:=array_append(kept,(item->>'agent_id')::uuid);
    if item->>'ended_at' is not null and (item->>'started_at' is null or (item->>'ended_at')::timestamptz<(item->>'started_at')::timestamptz) then raise exception 'Pointages incohérents'; end if;
    update public.intervention_agents set started_at=(item->>'started_at')::timestamptz,ended_at=(item->>'ended_at')::timestamptz,final_observation=left(item->>'final_observation',5000) where intervention_id=x and agent_id=(item->>'agent_id')::uuid;
   end loop;
  end if;
  if p?'status' then update public.interventions set completed_at=case when status in ('completed','validated') then coalesce(completed_at,now()) else null end where id=x; end if;

  perform private.v3_log(x,'planning','Planning enregistré');
 elsif p_kind='cancel' then
  if not q then raise exception 'Action QG uniquement'; end if;
  select * into i from public.interventions where id=x and organization_id=me.organization_id for update;
  if i.id is null then raise exception 'Intervention introuvable'; end if;
  update public.interventions set status='cancelled',plan_visible=false where id=x; perform private.v3_log(x,'cancel','Intervention annulée',p->>'reason');
 elsif p_kind='request' then
  sid:=(p->>'site_id')::uuid;
  if not private.client_has_site(sid) then raise exception 'Site non autorisé'; end if;
  if length(btrim(coalesce(p->>'title','')))<3 then raise exception 'Objet requis'; end if;
  select client_id into cid from public.sites where id=sid;
  insert into public.client_requests(organization_id,client_id,site_id,created_by,title,details,category,desired_date) values(me.organization_id,cid,sid,me.id,left(p->>'title',200),left(p->>'details',5000),left(p->>'category',60),nullif(p->>'desired_date','')::date) returning id into x;
 elsif p_kind='request_state' then
  if not q then raise exception 'Action QG uniquement'; end if;
  update public.client_requests set request_state=p->>'request_state',updated_at=now() where id=x and organization_id=me.organization_id; if not found then raise exception 'Demande introuvable'; end if;
 elsif p_kind='issue_state' then
  if not q then raise exception 'Action QG uniquement'; end if;
  update public.issues set status=(p->>'status')::public.issue_status,resolved_at=case when p->>'status' in ('resolved','closed') then now() end where id=x and organization_id=me.organization_id; if not found then raise exception 'Signalement introuvable'; end if;
 elsif p_kind='photo' then
  x:=nullif(p->>'intervention_id','')::uuid; aid:=nullif(p->>'request_id','')::uuid;
  if (x is null)=(aid is null) then raise exception 'Association photo invalide'; end if;
  if x is not null then
   if not private.v3_can_intervention(x) then raise exception 'Photo non autorisée'; end if;
   select * into i from public.interventions where id=x for update; sid:=i.site_id;
   if not q and (i.status in ('completed','validated','cancelled','impossible') or not exists(select 1 from public.intervention_agents where intervention_id=x and agent_id=me.id and started_at is not null and ended_at is null)) then raise exception 'Participation active requise'; end if;
  else
   select site_id into sid from public.client_requests where id=aid and organization_id=me.organization_id;
   if sid is null or not(q or private.client_has_site(sid)) then raise exception 'Demande non autorisée'; end if;
  end if;
  if nullif(p->>'task_id','') is not null and not exists(select 1 from public.intervention_tasks where id=(p->>'task_id')::uuid and intervention_id=x) then raise exception 'Tâche non autorisée'; end if;
  if split_part(p->>'storage_path','/',1)<>me.organization_id::text or split_part(p->>'storage_path','/',2)<>coalesce(x::text,'request-'||aid::text) then raise exception 'Chemin photo invalide'; end if;
  if not exists(select 1 from storage.objects where bucket_id='care-media' and name=p->>'storage_path' and owner_id=me.id::text and metadata->>'mimetype' in ('image/jpeg','image/png','image/webp')) then raise exception 'Fichier photo absent ou format invalide'; end if;
  insert into public.photos(organization_id,intervention_id,site_id,task_id,client_request_id,uploaded_by,storage_path,category,caption,publishable) values(me.organization_id,x,sid,nullif(p->>'task_id','')::uuid,aid,me.id,p->>'storage_path',left(p->>'category',40),left(p->>'caption',1000),coalesce((p->>'publishable')::boolean,false) and p->>'category' in ('before','after'));
  if x is not null then perform private.v3_log(x,'photo','Photo enregistrée',p->>'category'); end if;
 elsif p_kind='document' then
  if not q then raise exception 'Action QG uniquement'; end if;
  sid:=nullif(p->>'site_id','')::uuid;
  if sid is null or not exists(select 1 from public.sites where id=sid and organization_id=me.organization_id) then raise exception 'Site requis'; end if;
  if split_part(p->>'storage_path','/',1)<>me.organization_id::text or split_part(p->>'storage_path','/',2)<>'documents' or not exists(select 1 from storage.objects where bucket_id='care-media' and name=p->>'storage_path' and owner_id=me.id::text) then raise exception 'Fichier invalide'; end if;
  select client_id into cid from public.sites where id=sid;
  insert into public.documents(organization_id,client_id,site_id,title,storage_path,visibility) values(me.organization_id,cid,sid,left(p->>'title',250),p->>'storage_path',(p->>'visibility')::public.visibility_scope) returning id into x;
 elsif p_kind='quality' then
  if not q then raise exception 'Action QG uniquement'; end if;
  sid:=(p->>'site_id')::uuid;
  if not exists(select 1 from public.sites where id=sid and organization_id=me.organization_id) then raise exception 'Site non autorisé'; end if;
  insert into public.quality_controls(organization_id,site_id,inspector_id,result,observations,client_visible) values(me.organization_id,sid,me.id,p->>'result',left(p->>'observations',5000),coalesce((p->>'client_visible')::boolean,false)) returning id into x;
 elsif p_kind='read_notification' then update public.notifications set read_at=now() where id=x and recipient_id=me.id;
 else raise exception 'Action inconnue'; end if;

 if q and x is not null and p_kind in ('intervention','task','note','cancel') then
  if exists(select 1 from public.intervention_agents where intervention_id=x and ended_at is not null) then
   if not private.v3_publish(x) then raise exception 'Publication de la correction impossible. Aucune modification enregistrée.'; end if;
  elsif exists(select 1 from public.care_reports where intervention_id=x) then
   delete from public.care_reports where intervention_id=x;
   update public.interventions set publication_state='pending',published_at=null,publication_error=null where id=x;
  end if;
 end if;
 result:=result||jsonb_build_object('id',x,'ok',true);
 insert into private.care_audit(actor,kind,entity_id,details) values(me.id,p_kind,x,(p-'storage_path')||case when q and before_value is not null then jsonb_build_object('before',before_value,'after',private.qg_before(case when p_kind='task' then 'intervention' else p_kind end,x)) else '{}'::jsonb end);
 insert into private.care_commands(actor,key,kind,input,result) values(me.id,p_key,p_kind,p,result);
 return result;
end $$;
create or replace function private.v3_snapshot_pre_mcp() returns jsonb language plpgsql security definer set search_path='' as $$
declare me public.profiles; q boolean; result jsonb; ids uuid[]; siteids uuid[]; clientids uuid[];
begin
 select * into me from public.profiles where id=auth.uid() and active;
 if me.id is null then raise exception 'Compte non autorisé ou désactivé'; end if;
 q:=private.is_qg();
 select coalesce(array_agg(i.id),'{}') into ids from public.interventions i where i.organization_id=me.organization_id and (q or private.is_assigned(i.id) or (private.client_has_site(i.site_id) and (i.plan_visible or exists(select 1 from public.care_reports r where r.intervention_id=i.id))));
 select coalesce(array_agg(s.id),'{}') into siteids from public.sites s where s.organization_id=me.organization_id and (q or private.client_has_site(s.id) or exists(select 1 from public.interventions i where i.id=any(ids) and i.site_id=s.id));
 select coalesce(array_agg(c.id),'{}') into clientids from public.clients c where c.organization_id=me.organization_id and (q or exists(select 1 from public.sites s where s.id=any(siteids) and s.client_id=c.id));
 result:=jsonb_build_object('profile',to_jsonb(me)-'created_at'-'updated_at',
 'clients',coalesce((select jsonb_agg(case when q then to_jsonb(c) else jsonb_build_object('id',c.id,'name',c.name) end) from public.clients c where c.id=any(clientids)),'[]'::jsonb),
 'sites',coalesce((select jsonb_agg(case when me.role='client' then jsonb_build_object('id',s.id,'client_id',s.client_id,'name',s.name,'address',s.address,'contacts',s.contacts) else to_jsonb(s) end) from public.sites s where s.id=any(siteids)),'[]'::jsonb),
 'interventions',coalesce((select jsonb_agg(case when me.role='client' then coalesce(r.payload-'tasks'-'photos',jsonb_build_object('id',i.id,'site_id',i.site_id,'title',i.title,'starts_at',i.starts_at,'ends_at',i.ends_at,'status','planned')) else case when q then to_jsonb(i) else to_jsonb(i)-'internal_notes'-'publication_error' end end order by i.starts_at) from public.interventions i left join public.care_reports r on r.intervention_id=i.id where i.id=any(ids)),'[]'::jsonb),
 'assignments',case when me.role='client' then '[]'::jsonb else coalesce((select jsonb_agg(case when q then to_jsonb(a) else to_jsonb(a)-'final_observation' end) from public.intervention_agents a where a.intervention_id=any(ids)),'[]'::jsonb) end,
 'people',coalesce((select jsonb_agg(case when q then to_jsonb(p) else jsonb_build_object('id',p.id,'full_name',p.full_name,'role',p.role) end) from public.profiles p where p.organization_id=me.organization_id and (q or p.id=me.id or (me.role<>'client' and exists(select 1 from public.intervention_agents a where a.agent_id=p.id and a.intervention_id=any(ids))))),'[]'::jsonb),
 'tasks',case when me.role='client' then coalesce((select jsonb_agg(t) from public.care_reports r cross join lateral jsonb_array_elements(r.payload->'tasks') t where r.intervention_id=any(ids)),'[]'::jsonb) else coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order) from public.intervention_tasks t where t.intervention_id=any(ids)),'[]'::jsonb) end,
 'logs',case when me.role='client' then '[]'::jsonb else coalesce((select jsonb_agg(l order by l.created_at desc) from public.logbook_entries l where l.intervention_id=any(ids) and (q or l.visibility='agent')),'[]'::jsonb) end,
 'photos',case when me.role='client' then coalesce((select jsonb_agg(ph) from public.care_reports r cross join lateral jsonb_array_elements(r.payload->'photos') ph where r.intervention_id=any(ids)),'[]'::jsonb) else coalesce((select jsonb_agg(ph) from public.photos ph where ph.organization_id=me.organization_id and (q or ph.intervention_id=any(ids))),'[]'::jsonb) end,
 'issues',case when me.role='client' then '[]'::jsonb else coalesce((select jsonb_agg(v) from public.issues v where v.organization_id=me.organization_id and (q or v.intervention_id=any(ids))),'[]'::jsonb) end,
 'requests',coalesce((select jsonb_agg(r order by r.created_at desc) from public.client_requests r where r.organization_id=me.organization_id and (q or (me.role='client' and private.client_has_site(r.site_id)))),'[]'::jsonb),
 'requestPhotos',coalesce((select jsonb_agg(jsonb_build_object('id',ph.id,'client_request_id',ph.client_request_id,'storage_path',ph.storage_path)) from public.photos ph join public.client_requests r on r.id=ph.client_request_id where r.organization_id=me.organization_id and (q or private.client_has_site(r.site_id))),'[]'::jsonb),
 'reports',coalesce((select jsonb_agg(r) from public.care_reports r where r.intervention_id=any(ids)),'[]'::jsonb),
 'templates',case when me.role='client' then '[]'::jsonb else coalesce((select jsonb_agg(t) from public.service_templates t where t.organization_id=me.organization_id),'[]'::jsonb) end,
 'documents',coalesce((select jsonb_agg(d) from public.documents d where d.organization_id=me.organization_id and (q or (me.role='client' and d.visibility='client' and d.site_id=any(siteids)) or (me.role in ('agent','team_lead') and d.visibility='agent' and d.site_id=any(siteids)))),'[]'::jsonb),
 'quality',coalesce((select jsonb_agg(case when q then to_jsonb(c) else to_jsonb(c)-'inspector_id' end) from public.quality_controls c where c.organization_id=me.organization_id and (q or (me.role='client' and c.client_visible and c.site_id=any(siteids)))),'[]'::jsonb),
 'notifications',coalesce((select jsonb_agg(n order by n.created_at desc) from public.notifications n where n.recipient_id=me.id),'[]'::jsonb),
 'audit',case when q then coalesce((select jsonb_agg(a) from (select a.* from private.care_audit a join public.profiles p on p.id=a.actor where p.organization_id=me.organization_id order by a.id desc limit 500) a),'[]'::jsonb) else '[]'::jsonb end);
 return result;
end $$;
create or replace function private.mcp_prepare(ops jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o jsonb; p jsonb; old jsonb; res jsonb:='[]'; req public.client_requests; seen uuid[]:='{}'; x uuid; k text; allowed text[];
begin
 if jsonb_typeof(ops)<>'array' or jsonb_array_length(ops) not between 1 and 25 or length(ops::text)>60000 then raise exception 'MCP_INVALID_OPERATIONS'; end if;
 for o in select value from jsonb_array_elements(ops) loop
  if jsonb_typeof(o)<>'object' or exists(select 1 from jsonb_object_keys(o) t where t not in ('kind','id','request_id','patch','expected_agent_ids')) then raise exception 'MCP_INVALID_OPERATION'; end if;
  k:=o->>'kind';p:=coalesce(o->'patch','{}');x:=nullif(o->>'id','')::uuid;
  if k is null or k not in ('create','update','cancel','accept_request','delete','update_client','delete_client','update_site','delete_site','update_agent','delete_agent') or jsonb_typeof(p)<>'object' then raise exception 'MCP_INVALID_OPERATION';end if;
  allowed:=array['title','starts_at','ends_at','service_type','description','instructions','internal_notes','plan_visible','agent_ids'];
  if k in ('create','update','accept_request') then allowed:=allowed||array['site_id','tasks','template_id','reason'];end if;
  if k='update' then allowed:=allowed||array['status','client_summary','participations'];end if;
  if k='update_client' then allowed:=array['name','email','phone','contacts','active','reason'];end if;
  if k='update_site' then allowed:=array['client_id','name','address','general_instructions','access_notes','contacts','active','reason'];end if;
  if k='update_agent' then allowed:=array['full_name','phone','role','active','reason'];end if;
  if k in ('cancel','delete','delete_client','delete_site','delete_agent') then allowed:=array['reason'];end if;
  if exists(select 1 from jsonb_object_keys(p) t where not(t=any(allowed))) then raise exception 'MCP_UNKNOWN_FIELD';end if;
  if (k not in ('create','accept_request')) is distinct from (x is not null) then raise exception 'MCP_ID_REQUIRED_OR_FORBIDDEN';end if;
  if (k='accept_request') is distinct from (nullif(o->>'request_id','') is not null) then raise exception 'MCP_REQUEST_ID_REQUIRED_OR_FORBIDDEN';end if;
  if x=any(seen) then raise exception 'MCP_DUPLICATE_TARGET';end if;seen:=array_append(seen,x);
  old:=null;
  if x is not null then
   old:=private.qg_before(k,x);if old is null then raise exception 'MCP_RESOURCE_NOT_FOUND';end if;
   if o?'expected_agent_ids' and (select jsonb_agg(v order by v) from jsonb_array_elements_text(o->'expected_agent_ids') v) is distinct from old->'agent_ids' then raise exception 'MCP_ASSIGNMENTS_CHANGED';end if;
   if k='update_agent' and old->>'role' not in ('agent','team_lead') then raise exception 'Compte protégé'; end if;
   if k in ('update_client','update_site','update_agent') then
    if p='{}'::jsonb or exists(select 1 from jsonb_each(p) e where e.value='null'::jsonb) then raise exception 'MCP_EMPTY_OR_NULL_PATCH'; end if;
    p:=(select jsonb_object_agg(key,value) from jsonb_each(old) where key=any(allowed))||p;
   end if;
   if k='update' then
    if p='{}'::jsonb or exists(select 1 from jsonb_each(p) e where e.value='null'::jsonb) then raise exception 'MCP_EMPTY_OR_NULL_PATCH';end if;
    p:=jsonb_build_object('site_id',old->'site_id','title',old->'title','starts_at',old->'starts_at','ends_at',old->'ends_at','service_type',old->'service_type','description',old->'description','instructions',old->'instructions','internal_notes',old->'internal_notes','plan_visible',old->'plan_visible','agent_ids',old->'agent_ids')||p;
   end if;
   p:=p||jsonb_build_object('id',x);
  end if;
  if k='accept_request' then
   select * into req from public.client_requests where id=(o->>'request_id')::uuid and organization_id=private.current_org_id();
   if req.id is null or req.intervention_id is not null then raise exception 'MCP_REQUEST_UNAVAILABLE';end if;
   old:=to_jsonb(req);
   if p?'site_id' and p->>'site_id'<>req.site_id::text then raise exception 'MCP_REQUEST_SITE_MISMATCH';end if;
   p:=jsonb_build_object('site_id',req.site_id,'title',req.title,'description',req.details)||p;
  end if;
  if k in ('create','update','accept_request') then
   if coalesce(p->>'starts_at','') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' or coalesce(p->>'ends_at','') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' then raise exception 'MCP_TIME_OFFSET_REQUIRED';end if;
   if (p->>'ends_at')::timestamptz<=(p->>'starts_at')::timestamptz then raise exception 'MCP_TIME_RANGE_INVALID';end if;
   if jsonb_typeof(p->'agent_ids') is distinct from 'array' or jsonb_array_length(p->'agent_ids') not between 1 and 100 then raise exception 'MCP_AGENT_REQUIRED';end if;
  elsif k in ('cancel','delete','delete_client','delete_site','delete_agent') and length(btrim(coalesce(p->>'reason','')))<5 then raise exception 'MCP_CANCELLATION_REASON_REQUIRED';end if;
  res:=res||jsonb_build_array(jsonb_build_object('kind',k,'id',x,'request_id',o->'request_id','payload',p,'before',old,'key',gen_random_uuid()));
 end loop;
 return res;
end $$;
create or replace function private.mcp_apply(ops jsonb,check_before boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare o jsonb; r jsonb; res jsonb:='[]'; ids uuid[]:='{}'; current_value jsonb;
begin
 for o in select value from jsonb_array_elements(ops) loop
  if check_before then
   if o->>'id' is not null then current_value:=private.qg_before(o->>'kind',(o->>'id')::uuid);
   elsif o->>'kind'='accept_request' then select to_jsonb(q) into current_value from public.client_requests q where id=(o->>'request_id')::uuid and organization_id=private.current_org_id();
   else current_value:=null; end if;
   if current_value is distinct from nullif(o->'before','null') then raise exception 'MCP_STALE_PREVIEW';end if;
  end if;
  if o->>'kind'='accept_request' then r:=private.v3_accept_request_pre_mcp((o->>'request_id')::uuid,o->'payload',(o->>'key')::uuid);
  else r:=private.v3_action_pre_mcp(case o->>'kind' when 'cancel' then 'cancel' when 'delete' then 'delete_intervention' when 'update_client' then 'client' when 'update_site' then 'site' when 'update_agent' then 'profile' when 'delete_client' then 'delete_client' when 'delete_site' then 'delete_site' when 'delete_agent' then 'delete_agent' else 'intervention' end,o->'payload',(o->>'key')::uuid);end if;
  if o->>'kind' in ('create','update','accept_request') then ids:=array_append(ids,(r->>'id')::uuid); end if;
  res:=res||jsonb_build_array(jsonb_build_object('kind',o->>'kind','result',r,'after',(select jsonb_object_agg(key,value) from jsonb_each(private.qg_before(o->>'kind',(r->>'id')::uuid)) where key in ('id','title','site_id','status','starts_at','ends_at','agent_ids','tasks','participations','name','full_name','active','deleted_at'))));
 end loop;
 perform private.mcp_conflicts(ids);return res;
end $$;

revoke all on function private.v3_action_pre_mcp(text,jsonb,uuid),private.v3_snapshot_pre_mcp(),private.mcp_prepare(jsonb),private.mcp_apply(jsonb,boolean),private.mcp_before(uuid) from public,anon,authenticated;
commit;
