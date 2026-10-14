-- READ ONLY. Aucun secret, mot de passe ou jeton.
select
 to_regprocedure('private.mcp_gate(boolean,boolean)') is not null as prerequis_mcp,
 to_regprocedure('public.care_mcp_directory_preview(text,jsonb,uuid)') is not null as preparation_installee,
 to_regprocedure('public.care_mcp_directory_review(uuid,text)') is not null as validation_installee,
 to_regprocedure('public.care_mcp_directory_claim(uuid)') is not null as execution_installee,
 to_regprocedure('public.care_mcp_directory_finish(uuid,uuid,uuid)') is not null as finalisation_installee;
-- Presence of create_client in the validator; no execution, no data mutation.
select coalesce(position('create_client' in (select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='mcp_directory_validate')),0)>0 as creation_clients_installee;
select p.full_name,m.enabled as acces_mcp_actif,m.can_write as ecriture_configuree
from private.care_mcp_members m join public.profiles p on p.id=m.profile_id
order by p.full_name;
-- À exécuter séparément APRÈS la migration :
-- select id,kind,state,created_at,expires_at,result
-- from private.care_mcp_directory_plans order by created_at desc limit 20;
