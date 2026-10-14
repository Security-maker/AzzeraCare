-- Azzera Care MCP 1.2: add client records, preserve sites/agents and existing plans.
-- Requires directory migration 20261014160126. No OAuth or membership changes.
begin;
do $$ begin
 if to_regprocedure('public.care_mcp_directory_claim(uuid)') is null then
  raise exception 'Installer le patch MCP sites/agents 1.1 avant le patch clients 1.2';
 end if;
end $$;
alter table private.care_mcp_directory_plans drop constraint care_mcp_directory_plans_kind_check;
alter table private.care_mcp_directory_plans add constraint care_mcp_directory_plans_kind_check
 check(kind in ('create_site','create_agent','create_client'));

create or replace function private.mcp_directory_validate(k text,p jsonb,org uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare key text; val jsonb; n int; allowed text[];
begin
 if k is null or k not in ('create_site','create_agent','create_client') or p is null or jsonb_typeof(p)<>'object' or length(p::text)>16000 then raise exception 'MCP_INVALID_DIRECTORY_INPUT';end if;
 allowed:=case when k='create_site' then array['client_id','name','address','general_instructions','contacts'] when k='create_client' then array['name','email','phone','contacts'] else array['full_name','email','role'] end;
 for key,val in select * from jsonb_each(p) loop
  if not(key=any(allowed)) or jsonb_typeof(val)<>'string' then raise exception 'MCP_UNKNOWN_OR_INVALID_FIELD';end if;
  n:=case key when 'address' then 1000 when 'general_instructions' then 5000 when 'contacts' then 4000 when 'email' then case when k='create_client' then 250 else 254 end when 'phone' then 50 else 200 end;
  if length(val#>>'{}')>n then raise exception 'MCP_FIELD_TOO_LONG';end if;
 end loop;
 if k='create_client' then
  if length(btrim(coalesce(p->>'name','')))<2 then raise exception 'MCP_CLIENT_NAME_REQUIRED';end if;
  p:=p||jsonb_build_object('name',btrim(p->>'name'));
  if p ? 'email' then
   p:=p||jsonb_build_object('email',lower(btrim(p->>'email')));
   if p->>'email'<>'' and p->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'MCP_VALID_EMAIL_REQUIRED';end if;
  end if;
  -- Check inactive clients too: never recreate or reactivate silently.
  if exists(select 1 from public.clients where organization_id=org and lower(btrim(name))=lower(p->>'name')) then raise exception 'MCP_CLIENT_ALREADY_EXISTS';end if;
 elsif k='create_site' then
  if length(btrim(coalesce(p->>'name','')))<2 then raise exception 'MCP_SITE_NAME_REQUIRED';end if;
  if not exists(select 1 from public.clients where id=(p->>'client_id')::uuid and organization_id=org and active) then raise exception 'MCP_ACTIVE_CLIENT_REQUIRED';end if;
  p:=p||jsonb_build_object('name',btrim(p->>'name'));
  if exists(select 1 from public.sites where organization_id=org and client_id=(p->>'client_id')::uuid and lower(btrim(name))=lower(p->>'name')) then raise exception 'MCP_SITE_ALREADY_EXISTS';end if;
 else
  if length(btrim(coalesce(p->>'full_name','')))<2 then raise exception 'MCP_AGENT_NAME_REQUIRED';end if;
  if coalesce(p->>'role','agent') not in ('agent','team_lead') then raise exception 'MCP_AGENT_ROLE_ONLY';end if;
  p:=p||jsonb_build_object('full_name',btrim(p->>'full_name'),'email',lower(btrim(p->>'email')),'role',coalesce(p->>'role','agent'));
  if coalesce(p->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'MCP_VALID_EMAIL_REQUIRED';end if;
  -- Never attach, overwrite, invite again or change an existing identity.
  if exists(select 1 from auth.users where lower(email)=p->>'email') then raise exception 'MCP_ACCOUNT_ALREADY_EXISTS_USE_QG';end if;
  if exists(select 1 from private.care_mcp_directory_plans where kind='create_agent' and payload->>'email'=p->>'email' and state in ('processing','review_required')) then raise exception 'MCP_ACCOUNT_CREATION_REQUIRES_REVIEW';end if;
 end if;
 return p;
end $$;

create or replace function public.care_mcp_directory_claim(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid; r private.care_mcp_directory_plans; p jsonb; out jsonb; nonce uuid;
begin
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'MCP_READ_COMMITTED_REQUIRED';end if;
 perform pg_advisory_xact_lock(731942,1);u:=private.mcp_gate(true,false);
 select * into r from private.care_mcp_directory_plans where id=p_id and actor=u and client_id=private.mcp_claims()->>'client_id' and organization_id=private.current_org_id() for update;
 if r.id is null then raise exception 'MCP_RESOURCE_NOT_FOUND';end if;
 if r.state='applied' then return jsonb_build_object('execute',false,'result',r.result);end if;
 if r.state in ('processing','review_required') then return jsonb_build_object('execute',false,'result',jsonb_build_object('ok',false,'applied',false,'plan_id',r.id,'error','MCP_ACCOUNT_CREATION_REQUIRES_REVIEW','outcome_unknown',true));end if;
 if r.state<>'approved' or r.expires_at<=now() then raise exception 'MCP_APPROVAL_REQUIRED_OR_EXPIRED';end if;
 p:=private.mcp_directory_validate(r.kind,r.payload,r.organization_id);
 if r.kind in ('create_site','create_client') then
  out:=private.v3_action_pre_mcp(case when r.kind='create_client' then 'client' else 'site' end,p,r.id);
  out:=jsonb_build_object('ok',true,'applied',true,'plan_id',r.id,'kind',r.kind,case when r.kind='create_client' then 'client_id' else 'site_id' end,out->'id');
  update private.care_mcp_directory_plans set state='applied',result=out where id=r.id;
  insert into private.care_mcp_audit(actor,plan_id,operation,result,resources) values(u,r.id,r.kind,'applied',jsonb_build_array(case when r.kind='create_client' then out->'client_id' else out->'site_id' end));
  return jsonb_build_object('execute',false,'result',out);
 end if;
 nonce:=gen_random_uuid();
 update private.care_mcp_directory_plans set state='processing',attempt=nonce,started_at=clock_timestamp(),session_id=(private.mcp_claims()->>'session_id')::uuid,token_expires_at=to_timestamp((private.mcp_claims()->>'exp')::double precision) where id=r.id;
 insert into private.care_mcp_audit(actor,plan_id,operation,result) values(u,r.id,r.kind,'processing');
 return jsonb_build_object('execute',true,'plan_id',r.id,'attempt',nonce,'payload',p);
end $$;

-- CREATE OR REPLACE preserves the existing function permissions.
notify pgrst,'reload schema';
commit;
