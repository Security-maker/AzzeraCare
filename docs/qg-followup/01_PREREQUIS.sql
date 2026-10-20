-- Lecture seule. Les trois premières colonnes doivent être true.
select
 to_regprocedure('private.qg_before(text,uuid)') is not null as gestion_qg_1_3_installee,
 to_regprocedure('private.care_push_allowed(public.notifications,public.profiles)') is not null as moteur_notifications_installe,
 exists(select 1 from pg_trigger where tgrelid='public.notifications'::regclass
  and tgname='care_enqueue_push' and tgenabled='O') as file_push_active,
 exists(select 1 from pg_trigger where tgname='care_wake_push'
  and tgenabled='O' and not tgisinternal) as envoi_immediat_installe;
-- L'envoi immédiat est facultatif si le Cron d'envoi existant fonctionne.
-- Ce contrôle ne prouve pas l'envoi de notifications sur un appareil.
