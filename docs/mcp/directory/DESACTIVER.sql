-- Désactive uniquement le patch annuaire ; conserve les créations et reçus.
begin;
revoke execute on function public.care_mcp_directory_preview(text,jsonb,uuid),public.care_mcp_directory_review(uuid,text),public.care_mcp_directory_claim(uuid) from authenticated;
-- Laisser finir une opération déjà réservée : ne pas couper le finaliseur service_role.
notify pgrst,'reload schema';
commit;
