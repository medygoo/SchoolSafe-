create or replace function public.evaluate_student_access(p_sid text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  st jsonb;
  role_code text := private.current_app_role();
  code text;
  public_reason text;
  financial_reason text;
begin
  if not private.can_scan() then
    raise exception 'Accès refusé';
  end if;

  st := private.compute_payment_state(p_sid);
  code := coalesce(st->>'access_status', 'unavailable');

  public_reason := case code
    when 'allowed' then 'Accès autorisé'
    when 'exception' then 'Accès temporairement autorisé'
    when 'orient' then 'Accès autorisé — suivi administratif requis'
    when 'blocked' then 'Accès non autorisé — orienter vers la Caisse'
    else 'Contrôle manuel requis'
  end;

  if role_code in ('direction', 'direction3') then
    financial_reason := case coalesce(st->>'status', 'unavailable')
      when 'overdue' then 'Frais en retard'
      when 'partial' then 'Paiement partiel'
      when 'pending' then 'Échéancier non couvert'
      when 'due_soon' then 'Échéance proche'
      when 'exception' then 'Dérogation temporaire active'
      when 'blocked' then 'Blocage administratif actif'
      else null
    end;
  end if;

  return jsonb_build_object(
    'allowed', coalesce((st->>'allowed')::boolean, false),
    'public_reason', public_reason,
    'financial_reason', financial_reason,
    'access_status', code
  );
end;
$$;

create or replace function public.check_gate_access_status(
  p_sid text,
  p_source text default 'qr'
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  r jsonb;
  code text;
  src text := case when p_source = 'manual' then 'manual' else 'qr' end;
begin
  if not private.can_scan() then
    raise exception 'Accès refusé';
  end if;

  r := public.get_gate_access_status(p_sid);
  code := coalesce(r->>'access_status', 'unavailable');

  if nullif(r->>'student_name', '') is not null then
    insert into public.payment_scan_log(
      sid,
      checked_by,
      checked_role,
      source,
      result_code,
      details
    ) values (
      r->>'student_id',
      private.current_app_user_id(),
      private.current_app_role(),
      src,
      case
        when code in ('allowed', 'orient', 'blocked', 'exception') then code
        else 'unavailable'
      end,
      jsonb_build_object('instruction', r->>'instruction')
    );
  end if;

  return r;
end;
$$;

create or replace function public.record_scan_incident(
  p_sid text,
  p_type text,
  p_code text,
  p_note text,
  p_manual boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.students%rowtype;
  u public.users%rowtype;
  role_code text := private.current_app_role();
  v_date text := to_char(timezone('Africa/Kinshasa', now()), 'YYYY-MM-DD');
  v_time text := to_char(timezone('Africa/Kinshasa', now()), 'HH24:MI');
  v_type text := case when p_type = 'exit' then 'exit' else 'entry' end;
  v_note text;
begin
  if not private.can_scan() then
    raise exception 'Accès refusé';
  end if;

  select * into s
  from public.students
  where id = p_sid
    and not coalesce(archived, false);

  if not found then
    return jsonb_build_object('recorded', false, 'reason', 'unknown_student');
  end if;

  select * into u
  from public.users
  where id = private.current_app_user_id()
    and status = 'active';

  if not found then
    raise exception 'Profil scanner introuvable';
  end if;

  if role_code in ('direction', 'direction3') then
    v_note := left(
      coalesce(
        nullif(btrim(coalesce(p_note, '')), ''),
        nullif(btrim(coalesce(p_code, '')), ''),
        'Décision de sécurité'
      ),
      250
    );
  else
    v_note := case coalesce(p_code, '')
      when 'invalid_escort' then 'Accompagnateur non autorisé'
      when 'missing_entry' then 'Entrée du jour introuvable'
      when 'invalid_qr' then 'QR invalide'
      when 'expired_qr' then 'QR expiré'
      when 'unknown_student' then 'Élève introuvable'
      else 'Décision administrative — contrôle manuel requis'
    end;
  end if;

  insert into public.scan_log(
    id,
    sid,
    type,
    status,
    date,
    time,
    name,
    label,
    by_uid,
    by_name,
    by_role,
    manual,
    description,
    note
  ) values (
    'scan_' || replace(gen_random_uuid()::text, '-', ''),
    s.id,
    v_type,
    case when v_type = 'exit' then 'unauthorized' else 'refused_access' end,
    v_date,
    v_time,
    s.name,
    case when v_type = 'exit' then 'Sortie refusée' else 'Accès refusé' end,
    u.id,
    u.name,
    role_code,
    coalesce(p_manual, false),
    'Décision de sécurité',
    v_note
  );

  return jsonb_build_object('recorded', true);
end;
$$;

revoke all on function public.evaluate_student_access(text) from public;
revoke all on function public.evaluate_student_access(text) from anon;
grant execute on function public.evaluate_student_access(text) to authenticated, service_role;

revoke all on function public.check_gate_access_status(text, text) from public;
revoke all on function public.check_gate_access_status(text, text) from anon;
grant execute on function public.check_gate_access_status(text, text) to authenticated, service_role;

revoke all on function public.record_scan_incident(text, text, text, text, boolean) from public;
revoke all on function public.record_scan_incident(text, text, text, text, boolean) from anon;
grant execute on function public.record_scan_incident(text, text, text, text, boolean) to authenticated, service_role;

comment on function public.check_gate_access_status(text, text) is
'Contrôle portail journalisé. Les identifiants inconnus retournent un contrôle manuel sans violer la clé étrangère du journal financier.';

comment on function public.record_scan_incident(text, text, text, text, boolean) is
'Incident de scan SchoolSafe. Notes arbitraires réservées aux rôles financiers autorisés ; autres rôles limités à des messages administratifs génériques.';
