-- SchoolSafe VPS baseline - 04m pre-registration RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.submit_preinscription(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.submit_preinscription_email(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_nom text; v_sexe text; v_dob date; v_lieu_naissance text; v_classe text;
  v_ecole_provenance text; v_nom_papa text; v_nom_maman text; v_telephone text;
  v_telephone_norm text; v_telephone2 text; v_adresse text; v_email text;
  v_blood_group text; v_urgence text; v_medical_notes text; v_tutelle text;
  v_autorisees jsonb := '[]'::jsonb; v_item jsonb; v_name text; v_relation text;
  v_phone text; v_phone_norm text; v_i integer; v_count integer; v_existing_id text;
  v_saved public.preinscriptions%rowtype;
begin
  if p_request is null or jsonb_typeof(p_request) <> 'object' then return jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD'); end if;
  if length(btrim(coalesce(p_request->>'website', ''))) > 0 or length(btrim(coalesce(p_request->>'company', ''))) > 0 or length(btrim(coalesce(p_request->>'url', ''))) > 0 then return jsonb_build_object('ok', false, 'code', 'INVALID_SUBMISSION'); end if;
  v_nom := nullif(btrim(coalesce(p_request->>'nom', '')), '');
  v_sexe := nullif(btrim(coalesce(p_request->>'sexe', '')), '');
  v_lieu_naissance := nullif(btrim(coalesce(p_request->>'lieu_naissance', '')), '');
  v_classe := nullif(btrim(coalesce(p_request->>'classe', '')), '');
  v_ecole_provenance := nullif(btrim(coalesce(p_request->>'ecole_provenance', '')), '');
  v_nom_papa := nullif(btrim(coalesce(p_request->>'nom_papa', '')), '');
  v_nom_maman := nullif(btrim(coalesce(p_request->>'nom_maman', '')), '');
  v_telephone := nullif(btrim(coalesce(p_request->>'telephone', '')), '');
  v_telephone2 := nullif(btrim(coalesce(p_request->>'telephone2', '')), '');
  v_adresse := nullif(btrim(coalesce(p_request->>'adresse', '')), '');
  v_email := nullif(lower(btrim(coalesce(p_request->>'email', ''))), '');
  v_blood_group := nullif(btrim(coalesce(p_request->>'blood_group', '')), '');
  v_urgence := nullif(btrim(coalesce(p_request->>'urgence', '')), '');
  v_medical_notes := nullif(btrim(coalesce(p_request->>'medical_notes', '')), '');
  v_tutelle := nullif(btrim(coalesce(p_request->>'tutelle', '')), '');
  if v_nom is null or length(v_nom) > 200 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'nom'); end if;
  if v_sexe is null or length(v_sexe) > 30 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'sexe'); end if;
  if v_classe is null or length(v_classe) > 160 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'classe'); end if;
  if v_telephone is null then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'telephone'); end if;
  v_telephone_norm := private.normalize_phone_e164(v_telephone);
  if v_telephone_norm is null then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'telephone'); end if;
  v_telephone := v_telephone_norm;
  if v_tutelle is null or length(v_tutelle) > 300 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'tutelle'); end if;
  begin v_dob := (p_request->>'dob')::date; exception when invalid_datetime_format or datetime_field_overflow then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'dob'); end;
  if v_dob is null or v_dob > (timezone('Africa/Kinshasa', now()))::date then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'dob'); end if;
  if length(coalesce(v_lieu_naissance, '')) > 200 or length(coalesce(v_ecole_provenance, '')) > 200 or length(coalesce(v_nom_papa, '')) > 200 or length(coalesce(v_nom_maman, '')) > 200 or length(coalesce(v_telephone2, '')) > 50 or length(coalesce(v_adresse, '')) > 500 or length(coalesce(v_blood_group, '')) > 20 or length(coalesce(v_urgence, '')) > 300 or length(coalesce(v_medical_notes, '')) > 2000 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR'); end if;
  if v_email is not null and (length(v_email) > 320 or v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'email'); end if;

  if p_request ? 'autorisees' then
    if jsonb_typeof(p_request->'autorisees') <> 'array' or jsonb_array_length(p_request->'autorisees') > 3 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'autorisees'); end if;
    for v_item in select value from jsonb_array_elements(p_request->'autorisees') loop
      if jsonb_typeof(v_item) <> 'object' then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'autorisees'); end if;
      v_name := nullif(btrim(coalesce(v_item->>'nom', '')), ''); v_relation := nullif(btrim(coalesce(v_item->>'relation', '')), ''); v_phone := nullif(btrim(coalesce(v_item->>'telephone', '')), '');
      if v_name is null and v_relation is null and v_phone is null then continue; end if;
      v_phone_norm := private.normalize_phone_e164(v_phone);
      if v_name is null or length(v_name) > 200 or v_relation is null or length(v_relation) > 100 or v_phone_norm is null then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'autorisees'); end if;
      v_autorisees := v_autorisees || jsonb_build_array(jsonb_build_object('nom', v_name, 'relation', v_relation, 'telephone', v_phone_norm));
    end loop;
  else
    for v_i in 1..3 loop
      v_name := nullif(btrim(coalesce(p_request->>('a' || v_i || '_nom'), '')), ''); v_relation := nullif(btrim(coalesce(p_request->>('a' || v_i || '_relation'), '')), ''); v_phone := nullif(btrim(coalesce(p_request->>('a' || v_i || '_telephone'), '')), '');
      if v_name is null and v_relation is null and v_phone is null then continue; end if;
      v_phone_norm := private.normalize_phone_e164(v_phone);
      if v_name is null or length(v_name) > 200 or v_relation is null or length(v_relation) > 100 or v_phone_norm is null then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'a' || v_i); end if;
      v_autorisees := v_autorisees || jsonb_build_array(jsonb_build_object('nom', v_name, 'relation', v_relation, 'telephone', v_phone_norm));
    end loop;
  end if;

  select p.id into v_existing_id from public.preinscriptions p
  where p.created_at >= now() - interval '24 hours' and lower(btrim(p.nom)) = lower(v_nom) and p.dob = v_dob and private.normalize_phone_e164(p.telephone) = v_telephone_norm
  order by p.created_at desc limit 1;
  if found then return jsonb_build_object('ok', true, 'code', 'ALREADY_SUBMITTED', 'request_id', v_existing_id); end if;
  select count(*) into v_count from public.preinscriptions p where p.created_at >= now() - interval '24 hours' and private.normalize_phone_e164(p.telephone) = v_telephone_norm;
  if v_count >= 3 then return jsonb_build_object('ok', false, 'code', 'RATE_LIMITED'); end if;

  insert into public.preinscriptions(nom,sexe,dob,lieu_naissance,classe,ecole_provenance,nom_papa,nom_maman,telephone,telephone2,adresse,email,blood_group,urgence,medical_notes,tutelle,autorisees)
  values(v_nom,v_sexe,v_dob,v_lieu_naissance,v_classe,v_ecole_provenance,v_nom_papa,v_nom_maman,v_telephone,v_telephone2,v_adresse,v_email,v_blood_group,v_urgence,v_medical_notes,v_tutelle,v_autorisees)
  returning * into v_saved;
  return jsonb_build_object('ok', true, 'code', 'PREINSCRIPTION_CREATED', 'request_id', v_saved.id, 'created_at', v_saved.created_at, 'expire_le', v_saved.expire_le, 'access_channel', case when v_email is null then 'phone_whatsapp' else 'email' end);
exception when check_violation then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR');
end;
$function$;

CREATE OR REPLACE FUNCTION public.validate_preinscription(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request public.preinscriptions%rowtype;
  v_phone text; v_temp_email text; v_result jsonb; v_parent_id text; v_parent_reused boolean;
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
$function$;

CREATE OR REPLACE FUNCTION public.refuse_preinscription(p_id text, p_motif text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id text := private.current_app_user_id(); v_actor_role text := private.current_app_role(); v_actor_name text;
  v_motif text := nullif(btrim(coalesce(p_motif, '')), ''); v_request public.preinscriptions%rowtype;
begin
  if auth.uid() is null or v_actor_role <> 'direction' then return jsonb_build_object('ok', false, 'code', 'FORBIDDEN'); end if;
  if v_motif is null or length(v_motif) < 3 or length(v_motif) > 300 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'motif'); end if;
  select u.name into v_actor_name from public.users u where u.id = v_actor_id and u.status = 'active' and u.role = 'direction' limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'ACTOR_NOT_FOUND'); end if;
  select * into v_request from public.preinscriptions p where p.id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'PREINSCRIPTION_NOT_FOUND'); end if;
  if v_request.statut = 'refusee' then return jsonb_build_object('ok', true, 'code', 'ALREADY_REFUSED'); end if;
  if v_request.statut <> 'nouvelle' then return jsonb_build_object('ok', false, 'code', 'PREINSCRIPTION_NOT_OPEN'); end if;
  update public.preinscriptions set statut = 'refusee', motif_refus = v_motif, traite_par = v_actor_id, traite_par_nom = v_actor_name, traite_le = now() where id = p_id;
  perform private.write_audit_event(v_actor_id, v_actor_name, 'preinscription_refusee', jsonb_build_object('preinscription_id', p_id, 'motif', v_motif), p_id);
  return jsonb_build_object('ok', true, 'code', 'PREINSCRIPTION_REFUSED', 'request_id', p_id);
end;
$function$;

COMMIT;
