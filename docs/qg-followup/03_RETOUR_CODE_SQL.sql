-- SECOURS UNIQUEMENT, pas une étape d'installation.
-- Retire le nouveau déclencheur et restaure le prédicat push antérieur.
-- Ne supprime aucun pointage, commentaire, intervention ni notification.
begin;
do $$
declare definition text;
begin
 select o.definition into definition from private.care_followup_originals o
 where o.signature='private.care_push_allowed(public.notifications,public.profiles)';
 if definition is null then raise exception 'Sauvegarde de code introuvable : aucun retour effectué'; end if;
 execute definition;
end $$;
drop trigger if exists care_notify_qg_participation on public.logbook_entries;
drop function if exists private.care_notify_qg_participation();
commit;
