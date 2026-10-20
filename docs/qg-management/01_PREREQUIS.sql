-- Lecture seule. Exécuter AVANT le patch. Aucun secret ni mot de passe.
select
 to_regprocedure('private.v3_action_pre_mcp(text,jsonb,uuid)') is not null as moteur_metier,
 to_regprocedure('private.v3_snapshot_pre_mcp()') is not null as lecture_metier,
 to_regprocedure('private.mcp_before(uuid)') is not null as etat_avant,
 to_regprocedure('private.mcp_prepare(jsonb)') is not null as preparation_mcp,
 to_regprocedure('private.mcp_apply(jsonb,boolean)') is not null as execution_mcp,
 to_regprocedure('public.care_mcp_directory_preview(text,jsonb,uuid)') is not null as creation_annuaire,
 coalesce((select position('create_client' in pg_get_functiondef(p.oid))>0
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='mcp_directory_validate' limit 1),false) as version_1_2_clients;

-- Si une table est absente, ne pas installer avant d'avoir établi la version existante.
select p.full_name,p.role,p.active,m.enabled as acces_mcp,m.can_write as ecriture_membre
from public.profiles p left join private.care_mcp_members m on m.profile_id=p.id
where p.id in ('c0b92dfe-2e7a-4d26-a280-92337f36c628','03d66417-7339-4c18-b518-2c9031460156');

select enabled as connecteur_actif,
 'fd41e3c7-7c7e-4184-9790-fe161b538f14'=any(oauth_client_ids) as oauth_yannice_autorise,
 not('fd41e3c7-7c7e-4184-9790-fe161b538f14'=any(read_only_client_ids)) as oauth_yannice_ecriture,
 '0e7f6f4e-c9ad-42a7-af61-c53f085668a5'=any(read_only_client_ids) as oauth_nacer_lecture_seule
from private.care_mcp_config where singleton;
