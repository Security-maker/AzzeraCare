-- Lecture seule. APRÈS installation. Ne prouve ni le déploiement Edge ni la découverte ChatGPT.
select
 to_regprocedure('private.qg_before(text,uuid)') is not null as audit_avant,
 to_regprocedure('private.qg_touch_intervention()') is not null as revision_mission,
 (select count(*)=5 from private.care_qg_originals) as sauvegarde_anciennes_fonctions,
 (select count(*)=3 from information_schema.columns where table_schema='public'
  and table_name in ('clients','sites','profiles') and column_name='deleted_at') as archivage_installe,
 (select count(*)=9 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and not t.tgisinternal and t.tgenabled='O'
  and t.tgname in ('qg_task_revision','qg_assignment_revision','qg_photos_revision',
  'qg_logbook_entries_revision','qg_issues_revision','qg_documents_revision',
  'qg_quality_controls_revision','qg_care_reports_revision','qg_client_requests_revision')) as revisions_associees;

select
 position('delete_intervention' in pg_get_functiondef('private.v3_action_pre_mcp(text,jsonb,uuid)'::regprocedure))>0 as suppression_mission,
 position('delete_agent' in pg_get_functiondef('private.mcp_prepare(jsonb)'::regprocedure))>0 as archivage_mcp,
 position('participations' in pg_get_functiondef('private.mcp_prepare(jsonb)'::regprocedure))>0 as correction_pointages_mcp,
 position('tasks' in pg_get_functiondef('private.mcp_prepare(jsonb)'::regprocedure))>0 as checklist_mcp,
 position('MCP_STALE_PREVIEW' in pg_get_functiondef('private.mcp_apply(jsonb,boolean)'::regprocedure))>0 as proposition_perimee_refusee;

select r.rolname as role,not has_function_privilege(r.oid,p.oid,'EXECUTE') as execution_directe_interdite,
 p.oid::regprocedure::text as fonction
from pg_roles r cross join pg_proc p join pg_namespace n on n.oid=p.pronamespace
where r.rolname in ('anon','authenticated') and n.nspname='private'
and p.proname in ('qg_before','qg_touch_intervention','v3_action_pre_mcp','mcp_prepare','mcp_apply')
order by role,fonction;

select p.full_name,p.role,p.active,m.enabled as acces_mcp,m.can_write as ecriture_membre
from public.profiles p left join private.care_mcp_members m on m.profile_id=p.id
where p.id in ('c0b92dfe-2e7a-4d26-a280-92337f36c628','03d66417-7339-4c18-b518-2c9031460156');

select enabled as connecteur_actif,
 'fd41e3c7-7c7e-4184-9790-fe161b538f14'=any(oauth_client_ids) as oauth_yannice_autorise,
 not('fd41e3c7-7c7e-4184-9790-fe161b538f14'=any(read_only_client_ids)) as oauth_yannice_ecriture,
 '0e7f6f4e-c9ad-42a7-af61-c53f085668a5'=any(read_only_client_ids) as oauth_nacer_lecture_seule
from private.care_mcp_config where singleton;
