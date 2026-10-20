-- Lecture seule après installation. Aucun secret ni adresse d'appareil affiché.
select
 exists(select 1 from pg_trigger where tgrelid='public.logbook_entries'::regclass
  and tgname='care_notify_qg_participation' and tgenabled='O') as alertes_prise_fin_installees,
 coalesce((select position('agent_started' in pg_get_functiondef(p.oid))>0
  and position('agent_finished' in pg_get_functiondef(p.oid))>0 from pg_proc p
  where p.oid=to_regprocedure('private.care_push_allowed(public.notifications,public.profiles)')),false)
  as prise_fin_autorisees_pour_push,
 coalesce((select length(public_key)=87 from private.care_push_config where singleton),false)
  as cle_publique_push_configuree;

select p.full_name,p.role,p.active,
 count(s.id) filter(where s.active and s.registered_role=p.role::text
  and s.public_key=(select public_key from private.care_push_config where singleton)) as appareils_inscrits
from public.profiles p left join private.care_push_subscriptions s on s.user_id=p.id
where p.role in ('qg_admin','qg_manager')
group by p.id,p.full_name,p.role,p.active order by p.full_name;

-- Faire ensuite démarrer/terminer une mission de test par un agent.
-- Les anciennes prises/fins de poste ne sont volontairement pas rejouées.
select n.created_at,p.full_name as destinataire,n.kind,n.title,n.entity_id,
 count(d.id) as envois_appareils,
 count(d.id) filter(where d.state='pending') as en_attente,
 count(d.id) filter(where d.state='sending') as en_cours,
 count(d.id) filter(where d.state='accepted') as acceptes_par_service,
 count(d.id) filter(where d.state='failed') as echecs,
 count(d.id) filter(where d.state='cancelled') as annules
from public.notifications n join public.profiles p on p.id=n.recipient_id
left join private.care_push_deliveries d on d.notification_id=n.id
where n.kind in ('agent_started','agent_finished') and n.created_at>now()-interval '24 hours'
group by n.id,p.full_name order by n.created_at desc limit 40;

select count(*) as erreurs_mise_en_file_24h from private.care_push_queue_errors
where created_at>now()-interval '24 hours';
-- Zéro ligne d'événements avant le premier test n'est pas une erreur.
-- Une acceptation par le service ne confirme pas la réception physique.
