-- RETOUR ARRIÈRE DU CODE UNIQUEMENT. Ne pas exécuter lors de l'installation.
-- Ne restaure ni les interventions supprimées ni les accès désactivés.
begin;
do $$ declare item record; begin
 if (select count(*) from private.care_qg_originals where signature in (
 'private.v3_action_pre_mcp(text,jsonb,uuid)','private.v3_snapshot_pre_mcp()',
 'private.mcp_before(uuid)','private.mcp_prepare(jsonb)','private.mcp_apply(jsonb,boolean)'))<>5 then
  raise exception 'Sauvegarde des fonctions incomplète : arrêt du retour arrière';
 end if;
 for item in select definition from private.care_qg_originals where signature in (
 'private.v3_action_pre_mcp(text,jsonb,uuid)','private.v3_snapshot_pre_mcp()',
 'private.mcp_before(uuid)','private.mcp_prepare(jsonb)','private.mcp_apply(jsonb,boolean)') loop
  execute item.definition;
 end loop;
end $$;
drop trigger if exists qg_task_revision on public.intervention_tasks;
drop trigger if exists qg_assignment_revision on public.intervention_agents;
drop trigger if exists qg_photos_revision on public.photos;
drop trigger if exists qg_logbook_entries_revision on public.logbook_entries;
drop trigger if exists qg_issues_revision on public.issues;
drop trigger if exists qg_documents_revision on public.documents;
drop trigger if exists qg_quality_controls_revision on public.quality_controls;
drop trigger if exists qg_care_reports_revision on public.care_reports;
drop trigger if exists qg_client_requests_revision on public.client_requests;
revoke all on function private.v3_action_pre_mcp(text,jsonb,uuid),private.v3_snapshot_pre_mcp(),
 private.mcp_prepare(jsonb),private.mcp_apply(jsonb,boolean),private.mcp_before(uuid),
 private.qg_before(text,uuid),private.qg_touch_intervention() from public,anon,authenticated;
commit;
