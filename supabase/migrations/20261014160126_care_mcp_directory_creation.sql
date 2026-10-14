-- Azzera Care MCP 1.1: additive directory creation. Apply AFTER MCP 1.0.
-- No change to memberships, OAuth clients, token hooks or existing planning functions.
begin;
do $$ begin
 if to_regprocedure('private.mcp_gate(boolean,boolean)') is null then
  raise exception 'Installer le connecteur MCP 1.0 avant ce patch';
 end if;
end $$;
create table private.care_mcp_directory_plans (
 id uuid primary key default gen_random_uuid(), actor uuid not null references public.profiles(id),
 organization_id uuid not null references public.organizations(id), client_id text not null,
 request_key uuid not null, kind text not null check(kind in ('create_site','create_agent')),
 input jsonb not null, payload jsonb not null,
 state text not null default 'pending' check(state in ('pending','approved','denied','processing','applied','review_required')),
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '10 minutes',
 approved_at timestamptz, started_at timestamptz, attempt uuid, session_id uuid, token_expires_at timestamptz, result jsonb,
 unique(actor,client_id,request_key)
);
alter table private.care_mcp_directory_plans enable row level security;
revoke all on private.care_mcp_directory_plans from public,anon,authenticated;

create function private.mcp_directory_validate(k text,p jsonb,org uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare key text; val jsonb; n int; allowed text[];
begin
 if k is null or k not in ('create_site','create_agent') or p is null or jsonb_typeof(p)<>'object' or length(p::text)>16000 then raise exception 'MCP_INVALID_DIRECTORY_INPUT';end if;
 allowed:=case when k='create_site' then array['client_id','name','address','general_instructions','contacts'] else array['full_name','email','role'] end;
 for key,val in select * from jsonb_each(p) loop
  if not(key=any(allowed)) or jsonb_typeof(val)<>'string' then raise exception 'MCP_UNKNOWN_OR_INVALID_FIELD';end if;
  n:=case key when 'address' then 1000 when 'general_instructions' then 5000 when 'contacts' then 4000 when 'email' then 254 else 200 end;
  if length(val#>>'{}')>n then raise exception 'MCP_FIELD_TOO_LONG';end if;
 end loop;
 if k='create_site' then
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

create function public.care_mcp_directory_preview(p_kind text,p_payload jsonb,p_key uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid; org uuid; cid text; p jsonb; r private.care_mcp_directory_plans;
begin
 perform pg_advisory_xact_lock(731942,1);u:=private.mcp_gate(true,false);cid:=private.mcp_claims()->>'client_id';
 if p_key is null then raise exception 'MCP_KEY_REQUIRED';end if;
 select * into r from private.care_mcp_directory_plans where actor=u and client_id=cid and request_key=p_key;
 if found then
  if r.kind is distinct from p_kind or r.input is distinct from p_payload then raise exception 'MCP_IDEMPOTENCY_MISMATCH';end if;
 else
  select organization_id into org from public.profiles where id=u;
  p:=private.mcp_directory_validate(p_kind,p_payload,org);
  insert into private.care_mcp_directory_plans(actor,organization_id,client_id,request_key,kind,input,payload)
   values(u,org,cid,p_key,p_kind,p_payload,p) returning * into r;
  insert into private.care_mcp_audit(actor,plan_id,operation,result) values(u,r.id,p_kind||'_preview','pending');
 end if;
 return jsonb_build_object('plan_id',r.id,'kind',r.kind,'state',r.state,'expires_at',r.expires_at,'changes',r.payload,'applied',r.state='applied','result',r.result);
end $$;

create function public.care_mcp_directory_review(p_id uuid,p_decision text default 'view') returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid; r private.care_mcp_directory_plans; cname text;
begin
 perform pg_advisory_xact_lock(731942,1);u:=private.mcp_gate(true,true);
 select * into r from private.care_mcp_directory_plans where id=p_id and actor=u and organization_id=private.current_org_id() for update;
 if r.id is null then raise exception 'MCP_RESOURCE_NOT_FOUND';end if;
 if p_decision is null or p_decision not in ('view','approve','deny') then raise exception 'MCP_INVALID_DECISION';end if;
 if p_decision<>'view' then
  if r.expires_at<=now() or r.state<>'pending' then raise exception 'MCP_PLAN_EXPIRED_OR_CLOSED';end if;
  if not exists(select 1 from private.care_mcp_config where r.client_id=any(oauth_client_ids) and not(r.client_id=any(read_only_client_ids))) then raise exception 'MCP_CLIENT_NOT_ALLOWED';end if;
  if p_decision='approve' then perform private.mcp_directory_validate(r.kind,r.payload,r.organization_id);end if;
  update private.care_mcp_directory_plans set state=case when p_decision='approve' then 'approved' else 'denied' end,
   approved_at=case when p_decision='approve' then now() end where id=p_id returning * into r;
  insert into private.care_mcp_audit(actor,plan_id,operation,result) values(u,p_id,'directory_human_review',r.state);
 end if;
 if r.kind='create_site' then select name into cname from public.clients where id=(r.payload->>'client_id')::uuid and organization_id=r.organization_id;end if;
 return jsonb_build_object('plan_id',r.id,'kind',r.kind,'state',r.state,'expires_at',r.expires_at,'payload',r.payload,'client_name',cname,'result',r.result);
end $$;

-- For sites: one SQL transaction. For account creations: reserve once BEFORE external Auth call.
-- A processing/ambiguous account creation is never retried automatically.
create function public.care_mcp_directory_claim(p_id uuid) returns jsonb
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
 if r.kind='create_site' then
  out:=private.v3_action_pre_mcp('site',p,r.id);
  out:=jsonb_build_object('ok',true,'applied',true,'plan_id',r.id,'kind',r.kind,'site_id',out->'id');
  update private.care_mcp_directory_plans set state='applied',result=out where id=r.id;
  insert into private.care_mcp_audit(actor,plan_id,operation,result,resources) values(u,r.id,r.kind,'applied',jsonb_build_array(out->'site_id'));
  return jsonb_build_object('execute',false,'result',out);
 end if;
 nonce:=gen_random_uuid();
 update private.care_mcp_directory_plans set state='processing',attempt=nonce,started_at=clock_timestamp(),session_id=(private.mcp_claims()->>'session_id')::uuid,token_expires_at=to_timestamp((private.mcp_claims()->>'exp')::double precision) where id=r.id;
 insert into private.care_mcp_audit(actor,plan_id,operation,result) values(u,r.id,r.kind,'processing');
 return jsonb_build_object('execute',true,'plan_id',r.id,'attempt',nonce,'payload',p);
end $$;

-- Only the server service role can finalize an Auth account creation. Never callable with an OAuth/user token.
create function public.care_mcp_directory_finish(p_id uuid,p_attempt uuid,p_user_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.care_mcp_directory_plans; out jsonb; valid boolean;
begin
 perform pg_advisory_xact_lock(731942,1);
 select * into r from private.care_mcp_directory_plans where id=p_id for update;
 if r.id is null or r.attempt is distinct from p_attempt or r.kind<>'create_agent' then raise exception 'MCP_INVALID_ACCOUNT_CREATION_RECEIPT';end if;
 if r.state='applied' then return r.result;end if;
 if r.state<>'processing' then raise exception 'MCP_ACCOUNT_CREATION_REQUIRES_REVIEW';end if;
 -- Recheck actor, organization and client grants after the external call.
 select exists(select 1 from public.profiles p join private.care_mcp_members m on m.profile_id=p.id cross join private.care_mcp_config c
  where p.id=r.actor and p.active and p.role in ('qg_admin','qg_manager') and p.organization_id=r.organization_id and c.organization_id=r.organization_id
   and r.token_expires_at>now() and exists(select 1 from auth.sessions s where s.id=r.session_id and s.user_id=r.actor and (to_jsonb(s)->>'not_after' is null or (to_jsonb(s)->>'not_after')::timestamptz>now()))
   and m.enabled and m.can_write and c.enabled and r.client_id=any(c.oauth_client_ids) and not(r.client_id=any(c.read_only_client_ids))) into valid;
 if p_user_id is null or not valid or not exists(select 1 from auth.users where id=p_user_id and lower(email)=r.payload->>'email') or exists(select 1 from public.profiles where id=p_user_id) then
  out:=jsonb_build_object('ok',false,'applied',false,'plan_id',r.id,'error','MCP_ACCOUNT_CREATION_REQUIRES_REVIEW','outcome_unknown',true);
 else
  begin
   insert into public.profiles(id,organization_id,role,full_name,active) values(p_user_id,r.organization_id,(r.payload->>'role')::public.care_role,r.payload->>'full_name',true);
   out:=jsonb_build_object('ok',true,'applied',true,'plan_id',r.id,'kind',r.kind,'agent_id',p_user_id,'account_created',true,'email_sent',false);
  exception when others then
   out:=jsonb_build_object('ok',false,'applied',false,'plan_id',r.id,'error','MCP_ACCOUNT_CREATION_REQUIRES_REVIEW','outcome_unknown',true);
  end;
 end if;
 update private.care_mcp_directory_plans set state=case when (out->>'ok')::boolean then 'applied' else 'review_required' end,result=out where id=r.id;
 insert into private.care_mcp_audit(actor,plan_id,operation,result,resources) values(r.actor,r.id,r.kind,case when (out->>'ok')::boolean then 'applied' else 'review_required' end,case when p_user_id is null then '[]'::jsonb else jsonb_build_array(p_user_id) end);
 return out;
end $$;
revoke all on function private.mcp_directory_validate(text,jsonb,uuid) from public,anon,authenticated;
revoke all on function public.care_mcp_directory_preview(text,jsonb,uuid),public.care_mcp_directory_review(uuid,text),public.care_mcp_directory_claim(uuid) from public,anon;
grant execute on function public.care_mcp_directory_preview(text,jsonb,uuid),public.care_mcp_directory_review(uuid,text),public.care_mcp_directory_claim(uuid) to authenticated;
revoke all on function public.care_mcp_directory_finish(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.care_mcp_directory_finish(uuid,uuid,uuid) to service_role;
notify pgrst,'reload schema';
commit;
