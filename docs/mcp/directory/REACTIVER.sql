-- Réactive uniquement les RPC du patch déjà installé ; aucun changement de membres.
begin;
grant execute on function public.care_mcp_directory_preview(text,jsonb,uuid),public.care_mcp_directory_review(uuid,text),public.care_mcp_directory_claim(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
