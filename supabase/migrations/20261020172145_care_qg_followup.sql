-- Azzera Care 1.3.1. Apply after QG management 1.3 and the existing Web Push migration.
-- No historical notifications; no authentication, membership or publication changes.
begin;
do $$ begin
 if to_regprocedure('private.qg_before(text,uuid)') is null
 or to_regprocedure('private.care_push_allowed(public.notifications,public.profiles)') is null
 or not exists(select 1 from pg_trigger where tgrelid='public.notifications'::regclass and tgname='care_enqueue_push' and tgenabled='O') then
  raise exception 'Prérequis manquant : installer la gestion QG 1.3 et le système Web Push existant avant ce correctif.';
 end if;
end $$;
-- Save the previous predicate once, for a code-only rollback without changing user data.
create table if not exists private.care_followup_originals(signature text primary key,definition text not null);
alter table private.care_followup_originals enable row level security;
revoke all on private.care_followup_originals from public,anon,authenticated;
insert into private.care_followup_originals(signature,definition)
select 'private.care_push_allowed(public.notifications,public.profiles)',pg_get_functiondef('private.care_push_allowed(public.notifications,public.profiles)'::regprocedure)
on conflict do nothing;
create or replace function private.care_push_allowed(n public.notifications,p public.profiles) returns boolean language sql stable security definer set search_path='' as $$
 select p.active and p.id=n.recipient_id and p.organization_id=n.organization_id and case
 when n.kind='push_test' then true
 when n.kind in ('issue','client_request','publication_failed') then p.role in ('qg_admin','qg_manager')
 when n.kind in ('agent_started','agent_finished') then p.role in ('qg_admin','qg_manager') and n.entity_type='intervention' and exists(select 1 from public.interventions i where i.id=n.entity_id and i.organization_id=p.organization_id)
 when n.kind in ('assignment','planning') then p.role in ('agent','team_lead') and exists(select 1 from public.intervention_agents a join public.interventions i on i.id=a.intervention_id where a.agent_id=p.id and i.id=n.entity_id and i.organization_id=p.organization_id)
 when n.kind='report_ready' then p.role='client' and exists(select 1 from public.care_reports r join public.interventions i on i.id=r.intervention_id join public.sites s on s.id=i.site_id join public.clients c on c.id=s.client_id join public.client_users u on u.client_id=c.id where i.id=n.entity_id and u.profile_id=p.id and c.active and s.active and i.organization_id=p.organization_id and s.organization_id=p.organization_id and c.organization_id=p.organization_id)
 when n.kind='request_accepted' then p.role='client' and exists(select 1 from public.client_requests r join public.sites s on s.id=r.site_id join public.clients c on c.id=s.client_id join public.client_users u on u.client_id=c.id where r.id=n.entity_id and u.profile_id=p.id and s.active and c.active and r.organization_id=p.organization_id and s.organization_id=p.organization_id and c.organization_id=p.organization_id)
 else false end
$$;

-- Real starts/finishes emit these log entries after updating the agent participation.
-- QG corrections and MCP previews do not emit start/finish events.
create or replace function private.care_notify_qg_participation() returns trigger
language plpgsql security definer set search_path='' as $$
declare mission public.interventions; participant public.intervention_agents;
 agent public.profiles; site_name text; happened_at timestamptz; event_kind text;
begin
 if new.entry_type not in ('start','finish') or new.intervention_id is null or new.author_id is null then return new; end if;
 select * into mission from public.interventions where id=new.intervention_id and organization_id=new.organization_id;
 if mission.id is null or new.site_id is distinct from mission.site_id then return new; end if;
 select * into agent from public.profiles where id=new.author_id and organization_id=mission.organization_id and active and role in ('agent','team_lead');
 if agent.id is null then return new; end if;
 select * into participant from public.intervention_agents where intervention_id=mission.id and agent_id=agent.id;
 happened_at:=case when new.entry_type='start' then participant.started_at else participant.ended_at end;
 if happened_at is null then return new; end if;
 select name into site_name from public.sites where id=mission.site_id and organization_id=mission.organization_id;
 event_kind:=case when new.entry_type='start' then 'agent_started' else 'agent_finished' end;
 insert into public.notifications(organization_id,recipient_id,kind,title,body,entity_type,entity_id,event_key)
 select mission.organization_id,p.id,event_kind,
  case when new.entry_type='start' then 'Prise de poste' else 'Fin de poste' end,
  agent.full_name||' · '||mission.title||' · '||coalesce(site_name,'Site')||' · '||to_char(happened_at at time zone 'Europe/Paris','DD/MM/YYYY à HH24:MI')||' (heure de Paris)',
  'intervention',mission.id,event_kind||':'||new.id::text
 from public.profiles p where p.organization_id=mission.organization_id and p.active and p.role in ('qg_admin','qg_manager')
 on conflict do nothing;
 return new;
end $$;
revoke all on function private.care_notify_qg_participation(),private.care_push_allowed(public.notifications,public.profiles) from public,anon,authenticated;
drop trigger if exists care_notify_qg_participation on public.logbook_entries;
create trigger care_notify_qg_participation after insert on public.logbook_entries
for each row when (new.entry_type in ('start','finish')) execute function private.care_notify_qg_participation();
commit;
