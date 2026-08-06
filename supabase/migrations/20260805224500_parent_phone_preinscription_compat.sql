alter table public.preinscriptions drop constraint if exists preinscriptions_email_required_check;
alter table public.preinscriptions drop constraint if exists preinscriptions_contact_required_check;
alter table public.preinscriptions add constraint preinscriptions_contact_required_check
check (
  private.normalize_phone_e164(telephone) is not null
  and (
    email is null
    or (
      email = lower(btrim(email))
      and length(email) <= 320
      and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    )
  )
);

do $$
begin
  if to_regprocedure('public.submit_preinscription_email(jsonb)') is null
     and to_regprocedure('public.submit_preinscription(jsonb)') is not null then
    alter function public.submit_preinscription(jsonb) rename to submit_preinscription_email;
  end if;
  if to_regprocedure('public.validate_preinscription_email(text)') is null
     and to_regprocedure('public.validate_preinscription(text)') is not null then
    alter function public.validate_preinscription(text) rename to validate_preinscription_email;
  end if;
end;
$$;

create or replace function public.submit_preinscription(p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_email text:=nullif(lower(btrim(coalesce(p_request->>'email',''))),'');
  v_phone text:=private.normalize_phone_e164(p_request->>'telephone');
  v_temp_email text;
  v_result jsonb;
  v_request_id text;
begin
  if p_request is null or jsonb_typeof(p_request)<>'object' then return jsonb_build_object('ok',false,'code','INVALID_PAYLOAD'); end if;
  if v_phone is null then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','telephone'); end if;
  if v_email is not null then return public.submit_preinscription_email(p_request || jsonb_build_object('telephone',v_phone,'email',v_email)); end if;
  v_temp_email:=replace(gen_random_uuid()::text,'-','') || '@phone.invalid';
  v_result:=public.submit_preinscription_email(p_request || jsonb_build_object('telephone',v_phone,'email',v_temp_email));
  if coalesce((v_result->>'ok')::boolean,false) then
    v_request_id:=v_result->>'request_id';
    if v_request_id is not null then update public.preinscriptions set email=null,telephone=v_phone where id=v_request_id; end if;
    v_result:=v_result || jsonb_build_object('access_channel','phone_whatsapp');
  end if;
  return v_result;
end;
$$;

create or replace function public.validate_preinscription(p_id text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_request public.preinscriptions%rowtype;
  v_phone text;
  v_temp_email text;
  v_result jsonb;
  v_parent_id text;
  v_parent_reused boolean;
begin
  select * into v_request from public.preinscriptions where id=p_id;
  if not found then return jsonb_build_object('ok',false,'code','PREINSCRIPTION_NOT_FOUND'); end if;
  if v_request.email is not null then return public.validate_preinscription_email(p_id); end if;
  v_phone:=private.normalize_phone_e164(v_request.telephone);
  if v_phone is null then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','telephone'); end if;
  v_temp_email:=replace(gen_random_uuid()::text,'-','') || '@phone.invalid';
  update public.preinscriptions set email=v_temp_email,telephone=v_phone where id=p_id;
  v_result:=public.validate_preinscription_email(p_id);
  update public.preinscriptions set email=null,telephone=v_phone where id=p_id;
  if coalesce((v_result->>'ok')::boolean,false) then
    v_parent_id:=v_result->>'parent_id';
    v_parent_reused:=coalesce((v_result->>'parent_reused')::boolean,false);
    if v_parent_id is not null and not v_parent_reused then
      update public.users set email=null,phone=v_phone,access_channel='phone_whatsapp',updated_at=now() where id=v_parent_id and role='parent';
      v_result:=v_result || jsonb_build_object('requires_phone_provisioning',true,'access_channel','phone_whatsapp');
    else
      v_result:=v_result || jsonb_build_object('requires_phone_provisioning',false);
    end if;
  end if;
  return v_result;
end;
$$;

revoke all on function public.submit_preinscription_email(jsonb) from public,anon;
grant execute on function public.submit_preinscription_email(jsonb) to authenticated,service_role;
revoke all on function public.validate_preinscription_email(text) from public,anon;
grant execute on function public.validate_preinscription_email(text) to authenticated,service_role;
revoke all on function public.submit_preinscription(jsonb) from public;
grant execute on function public.submit_preinscription(jsonb) to anon,authenticated;
revoke all on function public.validate_preinscription(text) from public,anon;
grant execute on function public.validate_preinscription(text) to authenticated;
