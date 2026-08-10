-- P0-8 — registre annuel des cartes élèves + durcissement sortie
-- Préparé par ChatGPT après audit du frontend Claude PR #73/#74.
-- IMPORTANT : ce fichier est versionné pour revue/fusion par Claude.
-- Il n'est PAS appliqué à la base de production par ce commit.

begin;

-- ---------------------------------------------------------------------------
-- 1. Clé HMAC dédiée aux cartes permanentes — jamais exposée au navigateur.
-- ---------------------------------------------------------------------------
insert into private.qr_keys(id, secret)
values ('student_card_v1', extensions.gen_random_bytes(32))
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Registre immuable des cartes physiques.
-- Une ligne = une carte émise. Pas de DELETE authentifié.
-- ---------------------------------------------------------------------------
create table if not exists public.student_cards (
  id text primary key default ('card_' || replace(gen_random_uuid()::text, '-', '')),
  sid text not null references public.students(id) on delete restrict,
  year text not null,
  card_no text not null unique,
  class_id text references public.classes(id) on delete restrict,
  class_name text not null,
  status text not null default 'active',
  emission text not null,
  motif text,
  note text,
  photo text not null,
  qr_payload text not null unique,
  issued_by text not null references public.users(id) on delete restrict,
  issued_by_name text not null,
  issued_at timestamptz not null default now(),
  print_count integer not null default 1,
  replaces text references public.student_cards(id) on delete restrict,
  replaced_by text references public.student_cards(id) on delete restrict,
  invalidated_at timestamptz,
  invalidated_by text references public.users(id) on delete restrict,
  invalidated_by_name text,
  invalidated_reason text,
  updated_at timestamptz not null default now(),
  constraint student_cards_year_check
    check (year ~ '^[0-9]{4}-[0-9]{4}$'),
  constraint student_cards_status_check
    check (status in ('active','remplacee','perdue','deterioree','revoquee')),
  constraint student_cards_emission_check
    check (emission in ('initiale','renouvellement','duplicata_perte','duplicata_deterioration','correction')),
  constraint student_cards_print_count_check
    check (print_count >= 1),
  constraint student_cards_required_motif_check
    check (
      emission not in ('duplicata_perte','duplicata_deterioration','correction')
      or length(btrim(coalesce(motif,''))) >= 3
    )
);

create unique index if not exists student_cards_one_active_per_student_year_idx
  on public.student_cards(sid, year)
  where status = 'active';

create index if not exists student_cards_sid_year_issued_idx
  on public.student_cards(sid, year, issued_at desc);

create index if not exists student_cards_status_year_idx
  on public.student_cards(status, year);

alter table public.student_cards enable row level security;

drop policy if exists student_cards_read on public.student_cards;
create policy student_cards_read
on public.student_cards
for select
to authenticated
using (
  private.current_app_role() in ('direction','direction2')
  or (
    private.current_app_role() = 'enseignant'
    and private.teaches_class(class_id)
  )
  or private.owns_student(sid)
);

-- Aucun rôle utilisateur n'écrit directement : toutes les mutations passent RPC.
revoke all on public.student_cards from anon, authenticated;
grant select on public.student_cards to authenticated;
grant all on public.student_cards to service_role;

-- ---------------------------------------------------------------------------
-- 3. Helpers privés cartes.
-- ---------------------------------------------------------------------------
create or replace function private.can_manage_student_cards()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_app_role() in ('direction','direction2'), false)
$$;

create or replace function private.can_verify_student_card()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.current_app_role() in ('direction','direction2','enseignant','gardien'), false)
$$;

create or replace function private.next_student_card_no(p_year text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n bigint;
  v_key text;
begin
  if p_year is null or p_year !~ '^[0-9]{4}-[0-9]{4}$' then
    raise exception 'Invalid school year';
  end if;

  v_key := 'student_card:' || p_year;

  insert into private.school_counters(counter_key, counter_value, updated_at)
  values (v_key, 1, now())
  on conflict (counter_key) do update
    set counter_value = private.school_counters.counter_value + 1,
        updated_at = now()
  returning counter_value into v_n;

  return 'LS-' || p_year || '-' || lpad(v_n::text, 4, '0');
end;
$$;

create or replace function private.student_card_qr_payload(p_card_no text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret bytea;
  v_sig text;
begin
  select secret into v_secret
  from private.qr_keys
  where id = 'student_card_v1';

  if v_secret is null then
    return null;
  end if;

  v_sig := encode(
    extensions.hmac(convert_to('card:' || p_card_no, 'UTF8'), v_secret, 'sha256'),
    'hex'
  );

  return 'schoolsafe://card/' || p_card_no || '/' || v_sig;
end;
$$;

revoke all on function private.can_manage_student_cards() from public, anon, authenticated;
revoke all on function private.can_verify_student_card() from public, anon, authenticated;
revoke all on function private.next_student_card_no(text) from public, anon, authenticated;
revoke all on function private.student_card_qr_payload(text) from public, anon, authenticated;
grant execute on function private.can_manage_student_cards() to service_role;
grant execute on function private.can_verify_student_card() to service_role;
grant execute on function private.next_student_card_no(text) to service_role;
grant execute on function private.student_card_qr_payload(text) to service_role;

-- ---------------------------------------------------------------------------
-- 4. Émission transactionnelle.
-- Le navigateur ne choisit ni le numéro, ni l'auteur, ni la classe figée,
-- ni la signature QR.
-- ---------------------------------------------------------------------------
create or replace function public.issue_student_card(
  p_sid text,
  p_year text,
  p_emission text,
  p_motif text default null,
  p_note text default null,
  p_photo text default null,
  p_class_id text default null,
  p_replaces text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_year text;
  v_emission text := lower(btrim(coalesce(p_emission,'')));
  v_motif text := nullif(btrim(coalesce(p_motif,'')), '');
  v_note text := nullif(btrim(coalesce(p_note,'')), '');
  v_photo text := nullif(btrim(coalesce(p_photo,'')), '');
  v_student public.students%rowtype;
  v_class public.classes%rowtype;
  v_active public.student_cards%rowtype;
  v_previous public.student_cards%rowtype;
  v_new_id text := 'card_' || replace(gen_random_uuid()::text, '-', '');
  v_card_no text;
  v_qr text;
  v_old_status text;
  v_total_prints numeric;
begin
  if not private.can_manage_student_cards() then
    return jsonb_build_object('ok',false,'code','CARD_ROLE_DENIED');
  end if;

  select name into v_actor_name
  from public.users
  where id = v_actor_id and status = 'active';
  if not found then
    return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND');
  end if;

  select year into v_year
  from public.settings
  order by id
  limit 1;

  if v_year is null or p_year is distinct from v_year then
    return jsonb_build_object('ok',false,'code','CARD_YEAR_MISMATCH','expected_year',v_year);
  end if;

  if v_emission not in ('initiale','renouvellement','duplicata_perte','duplicata_deterioration','correction') then
    return jsonb_build_object('ok',false,'code','CARD_EMISSION_INVALID');
  end if;

  if v_emission in ('duplicata_perte','duplicata_deterioration','correction')
     and (v_motif is null or length(v_motif) < 3) then
    return jsonb_build_object('ok',false,'code','CARD_MOTIF_REQUIRED');
  end if;

  select * into v_student
  from public.students
  where id = p_sid and not coalesce(archived,false);
  if not found then
    return jsonb_build_object('ok',false,'code','CARD_STUDENT_NOT_FOUND');
  end if;

  if p_class_id is not null and p_class_id is distinct from v_student.cid then
    return jsonb_build_object('ok',false,'code','CARD_CLASS_MISMATCH');
  end if;

  select * into v_class
  from public.classes
  where id = v_student.cid;

  if v_photo is null then
    v_photo := nullif(btrim(coalesce(v_student.photo,'')), '');
  end if;

  if nullif(btrim(coalesce(v_student.name,'')),'') is null
     or nullif(btrim(coalesce(v_student.mat,'')),'') is null
     or nullif(btrim(coalesce(v_student.dob,'')),'') is null
     or v_student.cid is null
     or v_class.id is null
     or nullif(btrim(coalesce(v_class.name,'')),'') is null
     or v_photo is null then
    return jsonb_build_object('ok',false,'code','CARD_INCOMPLETE_FILE');
  end if;

  perform pg_advisory_xact_lock(hashtext('student-card:' || v_student.id || ':' || v_year));

  select * into v_active
  from public.student_cards
  where sid = v_student.id and year = v_year and status = 'active'
  order by issued_at desc
  limit 1
  for update;

  if v_emission = 'initiale' then
    if v_active.id is not null
       or exists(select 1 from public.student_cards c where c.sid=v_student.id and c.year=v_year) then
      return jsonb_build_object('ok',false,'code','CARD_ALREADY_ACTIVE');
    end if;
    if nullif(btrim(coalesce(p_replaces,'')),'') is not null then
      return jsonb_build_object('ok',false,'code','CARD_PREVIOUS_INVALID');
    end if;
  else
    if nullif(btrim(coalesce(p_replaces,'')),'') is not null then
      select * into v_previous
      from public.student_cards
      where id = p_replaces and sid = v_student.id
      for update;
      if not found then
        return jsonb_build_object('ok',false,'code','CARD_PREVIOUS_INVALID');
      end if;
    elsif v_active.id is not null then
      v_previous := v_active;
    else
      select * into v_previous
      from public.student_cards
      where sid = v_student.id
      order by issued_at desc
      limit 1
      for update;
    end if;

    if v_previous.id is null then
      return jsonb_build_object('ok',false,'code','CARD_PREVIOUS_REQUIRED');
    end if;

    if v_previous.status = 'revoquee' then
      return jsonb_build_object('ok',false,'code','CARD_PREVIOUS_INVALID');
    end if;

    if v_active.id is not null and v_previous.id <> v_active.id then
      return jsonb_build_object('ok',false,'code','CARD_ALREADY_ACTIVE');
    end if;

    if v_previous.replaced_by is not null then
      return jsonb_build_object('ok',false,'code','CARD_ALREADY_REPLACED');
    end if;
  end if;

  v_card_no := private.next_student_card_no(v_year);
  v_qr := private.student_card_qr_payload(v_card_no);
  if v_qr is null then
    return jsonb_build_object('ok',false,'code','CARD_QR_SECRET_MISSING');
  end if;

  -- L'ancienne carte est invalidée AVANT l'activation de la nouvelle.
  if v_previous.id is not null and v_previous.status = 'active' then
    v_old_status := case v_emission
      when 'duplicata_perte' then 'perdue'
      when 'duplicata_deterioration' then 'deterioree'
      else 'remplacee'
    end;

    update public.student_cards
    set status = v_old_status,
        invalidated_at = now(),
        invalidated_by = v_actor_id,
        invalidated_by_name = v_actor_name,
        invalidated_reason = coalesce(v_motif,
          case v_emission
            when 'renouvellement' then 'Renouvellement annuel'
            when 'correction' then 'Correction de carte'
            else 'Remplacement de carte'
          end),
        replaced_by = v_new_id,
        updated_at = now()
    where id = v_previous.id;
  elsif v_previous.id is not null then
    update public.student_cards
    set replaced_by = v_new_id,
        updated_at = now()
    where id = v_previous.id;
  end if;

  insert into public.student_cards(
    id,sid,year,card_no,class_id,class_name,status,emission,motif,note,photo,qr_payload,
    issued_by,issued_by_name,issued_at,print_count,replaces
  ) values (
    v_new_id,v_student.id,v_year,v_card_no,v_student.cid,v_class.name,'active',v_emission,
    v_motif,left(v_note,500),v_photo,v_qr,v_actor_id,v_actor_name,now(),1,
    case when v_previous.id is null then null else v_previous.id end
  );

  select coalesce(sum(print_count),0) into v_total_prints
  from public.student_cards
  where sid = v_student.id;

  update public.students
  set card_printed = true,
      card_print_date = to_char(timezone('Africa/Kinshasa',now()),'YYYY-MM-DD'),
      card_print_count = v_total_prints
  where id = v_student.id;

  perform private.write_audit_event(
    v_actor_id,v_actor_name,'student_card_issued',
    jsonb_build_object(
      'card_id',v_new_id,'card_no',v_card_no,'student_id',v_student.id,'year',v_year,
      'emission',v_emission,'replaces',case when v_previous.id is null then null else v_previous.id end
    ),
    v_student.id
  );

  return jsonb_build_object(
    'ok',true,'code','CARD_ISSUED',
    'data',jsonb_build_object(
      'id',v_new_id,'sid',v_student.id,'year',v_year,'card_no',v_card_no,
      'class_id',v_student.cid,'class_name',v_class.name,'status','active',
      'emission',v_emission,'motif',v_motif,'note',v_note,'photo',v_photo,
      'qr_payload',v_qr,'issued_by',v_actor_id,'issued_by_name',v_actor_name,
      'issued_at',now(),'print_count',1,
      'replaces',case when v_previous.id is null then null else v_previous.id end
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Perte, révocation et réimpression.
-- ---------------------------------------------------------------------------
create or replace function public.declare_student_card_lost(p_card_id text, p_motif text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_motif text := nullif(btrim(coalesce(p_motif,'')), '');
  v_card public.student_cards%rowtype;
  v_year text;
begin
  if not private.can_manage_student_cards() then
    return jsonb_build_object('ok',false,'code','CARD_ROLE_DENIED');
  end if;
  if v_motif is null or length(v_motif)<3 then
    return jsonb_build_object('ok',false,'code','CARD_MOTIF_REQUIRED');
  end if;

  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;

  select * into v_card from public.student_cards where id=p_card_id for update;
  if not found then return jsonb_build_object('ok',false,'code','CARD_NOT_FOUND'); end if;
  if v_card.status <> 'active' then return jsonb_build_object('ok',false,'code','CARD_NOT_ACTIVE'); end if;

  update public.student_cards
  set status='perdue',invalidated_at=now(),invalidated_by=v_actor_id,
      invalidated_by_name=v_actor_name,invalidated_reason=left(v_motif,500),updated_at=now()
  where id=v_card.id;

  select year into v_year from public.settings order by id limit 1;
  update public.students s
  set card_printed = exists(
    select 1 from public.student_cards c where c.sid=s.id and c.year=v_year and c.status='active'
  )
  where s.id=v_card.sid;

  perform private.write_audit_event(v_actor_id,v_actor_name,'student_card_lost',
    jsonb_build_object('card_id',v_card.id,'card_no',v_card.card_no,'reason',v_motif),v_card.sid);

  return jsonb_build_object('ok',true,'code','CARD_DECLARED_LOST',
    'data',jsonb_build_object('id',v_card.id,'card_no',v_card.card_no,'status','perdue',
      'invalidated_by',v_actor_id,'invalidated_by_name',v_actor_name,'invalidated_reason',v_motif));
end;
$$;

create or replace function public.revoke_student_card(p_card_id text, p_motif text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_motif text := nullif(btrim(coalesce(p_motif,'')), '');
  v_card public.student_cards%rowtype;
  v_year text;
begin
  if not private.can_manage_student_cards() then
    return jsonb_build_object('ok',false,'code','CARD_ROLE_DENIED');
  end if;
  if v_motif is null or length(v_motif)<3 then
    return jsonb_build_object('ok',false,'code','CARD_MOTIF_REQUIRED');
  end if;

  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;

  select * into v_card from public.student_cards where id=p_card_id for update;
  if not found then return jsonb_build_object('ok',false,'code','CARD_NOT_FOUND'); end if;
  if v_card.status <> 'active' then return jsonb_build_object('ok',false,'code','CARD_NOT_ACTIVE'); end if;

  update public.student_cards
  set status='revoquee',invalidated_at=now(),invalidated_by=v_actor_id,
      invalidated_by_name=v_actor_name,invalidated_reason=left(v_motif,500),updated_at=now()
  where id=v_card.id;

  select year into v_year from public.settings order by id limit 1;
  update public.students s
  set card_printed = exists(
    select 1 from public.student_cards c where c.sid=s.id and c.year=v_year and c.status='active'
  )
  where s.id=v_card.sid;

  perform private.write_audit_event(v_actor_id,v_actor_name,'student_card_revoked',
    jsonb_build_object('card_id',v_card.id,'card_no',v_card.card_no,'reason',v_motif),v_card.sid);

  return jsonb_build_object('ok',true,'code','CARD_REVOKED',
    'data',jsonb_build_object('id',v_card.id,'card_no',v_card.card_no,'status','revoquee',
      'invalidated_by',v_actor_id,'invalidated_by_name',v_actor_name,'invalidated_reason',v_motif));
end;
$$;

create or replace function public.count_student_card_print(p_card_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_card public.student_cards%rowtype;
  v_total_prints numeric;
begin
  if not private.can_manage_student_cards() then
    return jsonb_build_object('ok',false,'code','CARD_ROLE_DENIED');
  end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;

  update public.student_cards
  set print_count=print_count+1,updated_at=now()
  where id=p_card_id and status='active'
  returning * into v_card;

  if not found then
    if exists(select 1 from public.student_cards where id=p_card_id) then
      return jsonb_build_object('ok',false,'code','CARD_NOT_ACTIVE');
    end if;
    return jsonb_build_object('ok',false,'code','CARD_NOT_FOUND');
  end if;

  select coalesce(sum(print_count),0) into v_total_prints
  from public.student_cards where sid=v_card.sid;
  update public.students set card_print_count=v_total_prints where id=v_card.sid;

  perform private.write_audit_event(v_actor_id,v_actor_name,'student_card_reprinted',
    jsonb_build_object('card_id',v_card.id,'card_no',v_card.card_no,'print_count',v_card.print_count),v_card.sid);

  return jsonb_build_object('ok',true,'code','CARD_PRINT_COUNTED',
    'data',jsonb_build_object('id',v_card.id,'card_no',v_card.card_no,'print_count',v_card.print_count));
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Vérification du QR permanent au portail.
-- Le gardien ne reçoit ni famille, ni finances, ni secret HMAC.
-- ---------------------------------------------------------------------------
create or replace function public.verify_student_card_qr(p_payload text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match text[];
  v_card_no text;
  v_sig text;
  v_secret bytea;
  v_expected text;
  v_card public.student_cards%rowtype;
  v_student public.students%rowtype;
  v_class_name text;
  v_year text;
  v_refusal text;
begin
  if not private.can_verify_student_card() then
    return jsonb_build_object('ok',false,'valid',false,'refusal_code','CARD_ROLE_DENIED');
  end if;

  v_match := regexp_match(coalesce(p_payload,''), '^schoolsafe://card/([^/]+)/([0-9A-Fa-f]{64})$');
  if v_match is null then
    return jsonb_build_object('ok',true,'valid',false,'refusal_code','CARD_QR_FORMAT_INVALID');
  end if;

  v_card_no := v_match[1];
  v_sig := lower(v_match[2]);

  select secret into v_secret from private.qr_keys where id='student_card_v1';
  if v_secret is null then
    return jsonb_build_object('ok',false,'valid',false,'refusal_code','CARD_QR_SECRET_MISSING');
  end if;

  v_expected := encode(
    extensions.hmac(convert_to('card:' || v_card_no,'UTF8'),v_secret,'sha256'),
    'hex'
  );
  if v_sig <> lower(v_expected) then
    return jsonb_build_object('ok',true,'valid',false,'refusal_code','CARD_QR_SIGNATURE_INVALID');
  end if;

  select * into v_card from public.student_cards where card_no=v_card_no;
  if not found then
    return jsonb_build_object('ok',true,'valid',false,'refusal_code','CARD_NOT_FOUND');
  end if;

  if v_card.status <> 'active' then
    v_refusal := case v_card.status
      when 'perdue' then 'CARD_LOST'
      when 'remplacee' then 'CARD_REPLACED'
      when 'deterioree' then 'CARD_DAMAGED'
      when 'revoquee' then 'CARD_REVOKED'
      else 'CARD_NOT_ACTIVE'
    end;
    return jsonb_build_object('ok',true,'valid',false,'refusal_code',v_refusal,
      'card',jsonb_build_object('card_no',v_card.card_no,'status',v_card.status));
  end if;

  select year into v_year from public.settings order by id limit 1;
  if v_card.year is distinct from v_year then
    return jsonb_build_object('ok',true,'valid',false,'refusal_code','CARD_WRONG_YEAR',
      'card',jsonb_build_object('card_no',v_card.card_no,'year',v_card.year,'status',v_card.status),
      'current_year',v_year);
  end if;

  select * into v_student from public.students where id=v_card.sid;
  if not found or coalesce(v_student.archived,false) then
    return jsonb_build_object('ok',true,'valid',false,'refusal_code','CARD_STUDENT_ARCHIVED');
  end if;

  select name into v_class_name from public.classes where id=v_student.cid;

  return jsonb_build_object(
    'ok',true,'valid',true,'refusal_code',null,
    'card',jsonb_build_object(
      'id',v_card.id,'card_no',v_card.card_no,'year',v_card.year,'status',v_card.status
    ),
    'student',jsonb_build_object(
      'id',v_student.id,'name',v_student.name,'mat',v_student.mat,'photo',v_student.photo,
      'class_name',v_class_name
    )
  );
end;
$$;

revoke all on function public.issue_student_card(text,text,text,text,text,text,text,text) from public, anon;
revoke all on function public.declare_student_card_lost(text,text) from public, anon;
revoke all on function public.revoke_student_card(text,text) from public, anon;
revoke all on function public.count_student_card_print(text) from public, anon;
revoke all on function public.verify_student_card_qr(text) from public, anon;
grant execute on function public.issue_student_card(text,text,text,text,text,text,text,text) to authenticated, service_role;
grant execute on function public.declare_student_card_lost(text,text) to authenticated, service_role;
grant execute on function public.revoke_student_card(text,text) to authenticated, service_role;
grant execute on function public.count_student_card_print(text) to authenticated, service_role;
grant execute on function public.verify_student_card_qr(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Durcissement du lot Sortie après audit de la PR #74.
-- ---------------------------------------------------------------------------
create or replace function private.can_read_student_pickup_context(p_sid text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.current_app_role() in ('direction','direction2','enseignant','gardien')
    or private.owns_student(p_sid),
    false
  )
$$;

revoke all on function private.can_read_student_pickup_context(text) from public, anon, authenticated;
grant execute on function private.can_read_student_pickup_context(text) to service_role;

-- La Caisse (direction3) ne peut plus demander photos/pièces des accompagnants.
create or replace function public.get_student_pickup_context(p_sid text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := private.current_app_role();
  v_student public.students%rowtype;
  v_parent public.users%rowtype;
  v_people jsonb;
  v_full_phone boolean;
begin
  if not private.can_read_student_pickup_context(p_sid) then
    raise exception 'Accès refusé' using errcode='42501';
  end if;

  select * into v_student from public.students
  where id=p_sid and not coalesce(archived,false);
  if not found then return jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); end if;

  if v_student.pid is not null then
    select * into v_parent from public.users where id=v_student.pid and role='parent';
  end if;
  v_full_phone := v_role in ('direction','direction2','gardien');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'kind','accredited','name',a.name,'relation',a.relation,
    'phone',case when v_full_phone then a.phone else regexp_replace(a.phone,'^(\\+[0-9]{3})[0-9]+([0-9]{2})$','\\1••••••\\2') end,
    'photo_portrait',a.photo,'photo_full_body',a.photo_full_body,
    'id_doc_type',a.id_doc_type,'id_doc_last4',a.id_doc_last4,
    'valid_from',a.valid_from,'valid_until',a.valid_until
  ) order by a.name),'[]'::jsonb) into v_people
  from public.aps a
  where a.sid=p_sid and a.active and a.approval_status='approved'
    and a.valid_from<=timezone('Africa/Kinshasa',now())::date
    and (a.valid_until is null or a.valid_until>=timezone('Africa/Kinshasa',now())::date);

  return jsonb_build_object(
    'ok',true,
    'student',jsonb_build_object('id',v_student.id,'name',v_student.name,'photo',v_student.photo,'class_id',v_student.cid),
    'primary_parent',case when v_parent.id is null then null else jsonb_build_object(
      'id',v_parent.id,'kind','primary','name',v_parent.name,'relation','Parent principal',
      'phone',case when v_full_phone then v_parent.phone else null end,
      'photo_portrait',v_parent.photo_url,
      'photo_full_body',v_parent.identity_full_body_photo_url,
      'id_doc_type',v_parent.identity_document_type,
      'id_doc_last4',v_parent.identity_document_last4,
      'ready_for_pickup',v_parent.status='active' and v_parent.photo_url is not null and v_parent.identity_full_body_photo_url is not null
    ) end,
    'authorized_people',v_people,
    'authorized_count',jsonb_array_length(v_people)
  );
end;
$$;

-- Un enseignant prépare uniquement un élève d'une classe qu'il enseigne.
create or replace function public.prepare_student_exit(p_sid text, p_gate_label text default null, p_manual boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  s public.students%rowtype;
  p public.users%rowtype;
  e public.student_exit_events%rowtype;
  v_date date:=timezone('Africa/Kinshasa',now())::date;
  v_notify jsonb;
begin
  if not private.can_prepare_student_exit() then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  perform private.expire_student_exit_events();
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  select * into s from public.students where id=p_sid and not coalesce(archived,false);
  if not found then return jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); end if;

  if v_role='enseignant' and not private.teaches_class(s.cid) then
    return jsonb_build_object('ok',false,'code','STUDENT_OUTSIDE_TEACHER_CLASSES');
  end if;

  if not exists(select 1 from public.attendance a where a.sid=s.id and a.date=v_date::text) then
    return jsonb_build_object('ok',false,'code','MISSING_ENTRY');
  end if;
  if exists(select 1 from public.student_exit_events x where x.sid=s.id and x.school_date=v_date and x.status='confirmed') then
    return jsonb_build_object('ok',false,'code','ALREADY_EXITED');
  end if;
  if s.pid is null then return jsonb_build_object('ok',false,'code','PRIMARY_PARENT_REQUIRED'); end if;
  select * into p from public.users where id=s.pid and role='parent' and status='active';
  if not found then return jsonb_build_object('ok',false,'code','PRIMARY_PARENT_INACTIVE'); end if;

  perform pg_advisory_xact_lock(hashtext('student-exit:'||s.id||':'||v_date::text));
  select * into e from public.student_exit_events
  where sid=s.id and school_date=v_date and status in ('prepared','gate_scanned')
  order by created_at desc limit 1 for update;
  if found then
    return jsonb_build_object('ok',true,'code','EXIT_ALREADY_PREPARED','exit_event_id',e.id,
      'status',e.status,'expires_at',e.expires_at);
  end if;

  insert into public.student_exit_events(
    sid,student_name_snapshot,student_class_id_snapshot,school_date,status,quick_flow,
    prepared_at,expires_at,prepared_by_user_id,prepared_by_name,prepared_by_role,preparation_gate,
    parent_id_snapshot,parent_name_snapshot,parent_phone_snapshot,parent_email_snapshot,manual
  ) values (
    s.id,s.name,s.cid,v_date,'prepared',false,
    now(),now()+interval '30 minutes',v_actor_id,v_actor_name,v_role,nullif(btrim(coalesce(p_gate_label,'')),''),
    p.id,p.name,p.phone,p.email,coalesce(p_manual,false)
  ) returning * into e;

  v_notify:=private.queue_student_exit_notification(e.id,'exit_prepared');
  perform private.write_audit_event(v_actor_id,v_actor_name,'student_exit_prepared',
    jsonb_build_object('exit_event_id',e.id,'student_id',s.id,'expires_at',e.expires_at,'channels',v_notify->'channels'),s.id);

  return jsonb_build_object('ok',true,'code','EXIT_PREPARED','exit_event_id',e.id,
    'status',e.status,'prepared_at',e.prepared_at,'expires_at',e.expires_at,
    'notification',v_notify);
exception when unique_violation then
  select * into e from public.student_exit_events
  where sid=p_sid and school_date=v_date and status in ('prepared','gate_scanned') order by created_at desc limit 1;
  return jsonb_build_object('ok',true,'code','EXIT_ALREADY_PREPARED','exit_event_id',e.id,'status',e.status,'expires_at',e.expires_at);
end;
$$;

-- Un enseignant de remplacement au portail peut confirmer une sortie déjà préparée.
-- Sans préparation, il ne peut pas créer un quick-flow pour une autre classe.
create or replace function public.scan_student_exit_at_gate(
  p_sid text,
  p_exit_event_id text default null,
  p_escort_kind text default null,
  p_escort_id text default null,
  p_gate_label text default null,
  p_teacher_gate_reason text default null,
  p_manual boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_gate text:=nullif(btrim(coalesce(p_gate_label,'')),'');
  v_reason text:=nullif(btrim(coalesce(p_teacher_gate_reason,'')),'');
  v_kind text:=lower(btrim(coalesce(p_escort_kind,'')));
  v_date date:=timezone('Africa/Kinshasa',now())::date;
  s public.students%rowtype;
  p public.users%rowtype;
  a public.aps%rowtype;
  e public.student_exit_events%rowtype;
  prep jsonb;
  v_escort_id text;
  v_escort_name text;
  v_escort_relation text;
  v_escort_phone text;
  v_portrait text;
  v_full_body text;
  v_doc_type text;
  v_doc_last4 text;
begin
  if not private.can_confirm_student_exit() then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  perform private.expire_student_exit_events();
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  if v_gate is null or length(v_gate)>120 then return jsonb_build_object('ok',false,'code','GATE_REQUIRED'); end if;
  if v_role='enseignant' and (v_reason is null or length(v_reason)<5) then
    return jsonb_build_object('ok',false,'code','TEACHER_GATE_REASON_REQUIRED');
  end if;
  select * into s from public.students where id=p_sid and not coalesce(archived,false);
  if not found then return jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); end if;

  perform pg_advisory_xact_lock(hashtext('student-exit:'||s.id||':'||v_date::text));
  if exists(select 1 from public.student_exit_events x where x.sid=s.id and x.school_date=v_date and x.status='confirmed') then
    return jsonb_build_object('ok',false,'code','ALREADY_EXITED');
  end if;

  if nullif(btrim(coalesce(p_exit_event_id,'')),'') is not null then
    select * into e from public.student_exit_events
    where id=p_exit_event_id and sid=s.id and school_date=v_date for update;
  else
    select * into e from public.student_exit_events
    where sid=s.id and school_date=v_date and status in ('prepared','gate_scanned')
    order by created_at desc limit 1 for update;
  end if;

  if not found then
    if v_role='enseignant' and not private.teaches_class(s.cid) then
      return jsonb_build_object('ok',false,'code','PREPARATION_REQUIRED_FOR_OTHER_CLASS');
    end if;
    prep:=public.prepare_student_exit(s.id,v_gate,p_manual);
    if prep->>'ok'<>'true' then return prep; end if;
    select * into e from public.student_exit_events where id=prep->>'exit_event_id' for update;
    update public.student_exit_events set quick_flow=true where id=e.id returning * into e;
  end if;
  if e.status='gate_scanned' then
    return jsonb_build_object('ok',true,'code','EXIT_ALREADY_SCANNED','exit_event_id',e.id,'status',e.status);
  end if;
  if e.status<>'prepared' or e.expires_at<=now() then
    return jsonb_build_object('ok',false,'code','PREPARATION_EXPIRED');
  end if;

  if v_kind='primary' then
    select * into p from public.users where id=s.pid and role='parent' and status='active';
    if not found or (p_escort_id is not null and p_escort_id<>p.id) then
      return jsonb_build_object('ok',false,'code','INVALID_ESCORT');
    end if;
    if p.photo_url is null or p.identity_full_body_photo_url is null then
      return jsonb_build_object('ok',false,'code','PRIMARY_PARENT_IDENTITY_INCOMPLETE');
    end if;
    v_escort_id:=p.id; v_escort_name:=p.name; v_escort_relation:='Parent principal';
    v_escort_phone:=p.phone; v_portrait:=p.photo_url; v_full_body:=p.identity_full_body_photo_url;
    v_doc_type:=p.identity_document_type; v_doc_last4:=p.identity_document_last4;
  elsif v_kind='accredited' then
    select * into a from public.aps where id=p_escort_id and sid=s.id and active and approval_status='approved'
      and valid_from<=v_date and (valid_until is null or valid_until>=v_date);
    if not found then return jsonb_build_object('ok',false,'code','INVALID_ESCORT'); end if;
    v_escort_id:=a.id; v_escort_name:=a.name; v_escort_relation:=a.relation;
    v_escort_phone:=a.phone; v_portrait:=a.photo; v_full_body:=a.photo_full_body;
    v_doc_type:=a.id_doc_type; v_doc_last4:=a.id_doc_last4;
  elsif v_kind='self' then
    if not s.may_leave_alone or (s.leave_alone_until is not null and s.leave_alone_until<v_date) then
      return jsonb_build_object('ok',false,'code','SELF_EXIT_NOT_ALLOWED');
    end if;
    v_escort_id:=s.id; v_escort_name:=s.name||' — sortie autonome'; v_escort_relation:='Élève';
    v_portrait:=s.photo;
  else
    return jsonb_build_object('ok',false,'code','ESCORT_REQUIRED');
  end if;

  update public.student_exit_events set
    status='gate_scanned',gate_scanned_at=now(),gate_scanned_by_user_id=v_actor_id,
    gate_scanned_by_name=v_actor_name,gate_scanned_by_role=v_role,gate_label=v_gate,
    teacher_gate_reason=case when v_role='enseignant' then left(v_reason,500) else null end,
    manual=coalesce(p_manual,false),expires_at=greatest(expires_at,now()+interval '10 minutes'),
    escort_kind=v_kind,escort_id_snapshot=v_escort_id,escort_name_snapshot=v_escort_name,
    escort_relation_snapshot=v_escort_relation,escort_phone_snapshot=v_escort_phone,
    escort_photo_portrait_snapshot=v_portrait,escort_photo_full_body_snapshot=v_full_body,
    escort_id_doc_type_snapshot=v_doc_type,escort_id_doc_last4_snapshot=v_doc_last4
  where id=e.id returning * into e;

  perform private.write_audit_event(v_actor_id,v_actor_name,'student_exit_gate_scanned',
    jsonb_build_object('exit_event_id',e.id,'student_id',s.id,'gate',v_gate,'escort_kind',v_kind,
      'teacher_gate_reason',e.teacher_gate_reason),s.id);

  return jsonb_build_object('ok',true,'code','EXIT_GATE_SCANNED','exit_event_id',e.id,
    'status',e.status,'gate_scanned_at',e.gate_scanned_at,'escort_name',e.escort_name_snapshot,
    'photo_portrait',e.escort_photo_portrait_snapshot,'photo_full_body',e.escort_photo_full_body_snapshot,
    'id_doc_type',e.escort_id_doc_type_snapshot,'id_doc_last4',e.escort_id_doc_last4_snapshot);
end;
$$;

-- La lecture d'état ne renvoie plus to_jsonb(e) : aucun téléphone/e-mail/photo
-- ou identifiant de pièce n'est exposé par cette RPC.
create or replace function public.get_student_exit_status(p_sid text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  e public.student_exit_events%rowtype;
  v_date date:=timezone('Africa/Kinshasa',now())::date;
  v_event jsonb;
begin
  if not private.can_read_student_pickup_context(p_sid) then
    raise exception 'Accès refusé' using errcode='42501';
  end if;

  perform private.expire_student_exit_events();
  select * into e from public.student_exit_events
  where sid=p_sid and school_date=v_date order by created_at desc limit 1;

  if e.id is null then
    v_event := null;
  else
    v_event := jsonb_build_object(
      'id',e.id,'sid',e.sid,'school_date',e.school_date,'status',e.status,'quick_flow',e.quick_flow,
      'prepared_at',e.prepared_at,'expires_at',e.expires_at,'prepared_by_name',e.prepared_by_name,
      'preparation_gate',e.preparation_gate,'gate_scanned_at',e.gate_scanned_at,
      'gate_scanned_by_name',e.gate_scanned_by_name,'gate_label',e.gate_label,
      'escort_name_snapshot',e.escort_name_snapshot,'validated_at',e.validated_at,
      'validated_by_name',e.validated_by_name
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'event',v_event,
    'pickup_context',public.get_student_pickup_context(p_sid)
  );
end;
$$;

-- Lecture RLS des événements : enseignant = ses classes seulement.
drop policy if exists student_exit_events_read on public.student_exit_events;
create policy student_exit_events_read
on public.student_exit_events
for select
to authenticated
using (
  private.current_app_role() in ('direction','direction2')
  or private.owns_student(sid)
  or (
    private.current_app_role()='gardien'
    and school_date=timezone('Africa/Kinshasa',now())::date
  )
  or (
    private.current_app_role()='enseignant'
    and school_date=timezone('Africa/Kinshasa',now())::date
    and private.teaches_class(student_class_id_snapshot)
  )
);

commit;
