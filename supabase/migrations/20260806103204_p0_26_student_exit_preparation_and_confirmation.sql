-- P0-26: two-step student exit workflow with complete immutable provenance.

create table if not exists public.student_exit_events (
  id text primary key default ('exit_'||replace(gen_random_uuid()::text,'-','')),
  sid text not null references public.students(id) on delete restrict,
  student_name_snapshot text not null,
  student_class_id_snapshot text,
  school_date date not null,
  status text not null default 'prepared',
  quick_flow boolean not null default false,

  prepared_at timestamptz not null,
  expires_at timestamptz not null,
  prepared_by_user_id text not null references public.users(id) on delete restrict,
  prepared_by_name text not null,
  prepared_by_role text not null,
  preparation_gate text,

  parent_id_snapshot text not null references public.users(id) on delete restrict,
  parent_name_snapshot text not null,
  parent_phone_snapshot text,
  parent_email_snapshot text,

  gate_scanned_at timestamptz,
  gate_scanned_by_user_id text references public.users(id) on delete restrict,
  gate_scanned_by_name text,
  gate_scanned_by_role text,
  gate_label text,
  teacher_gate_reason text,
  manual boolean not null default false,

  escort_kind text,
  escort_id_snapshot text,
  escort_name_snapshot text,
  escort_relation_snapshot text,
  escort_phone_snapshot text,
  escort_photo_portrait_snapshot text,
  escort_photo_full_body_snapshot text,
  escort_id_doc_type_snapshot text,
  escort_id_doc_last4_snapshot text,

  validated_at timestamptz,
  validated_by_user_id text references public.users(id) on delete restrict,
  validated_by_name text,
  validated_by_role text,
  decision_note text,
  finalized_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint student_exit_status_check check (
    status in ('prepared','gate_scanned','confirmed','refused','cancelled','expired')
  ),
  constraint student_exit_prepared_role_check check (
    prepared_by_role in ('direction','direction2','enseignant','gardien')
  ),
  constraint student_exit_scanner_role_check check (
    gate_scanned_by_role is null or gate_scanned_by_role in ('direction','direction2','enseignant','gardien')
  ),
  constraint student_exit_validator_role_check check (
    validated_by_role is null or validated_by_role in ('direction','direction2','enseignant','gardien')
  ),
  constraint student_exit_escort_kind_check check (
    escort_kind is null or escort_kind in ('primary','accredited','self')
  ),
  constraint student_exit_expiry_check check (expires_at>prepared_at)
);

create unique index if not exists uq_student_exit_active_day
  on public.student_exit_events(sid,school_date)
  where status in ('prepared','gate_scanned');
create unique index if not exists uq_student_exit_confirmed_day
  on public.student_exit_events(sid,school_date)
  where status='confirmed';
create index if not exists idx_student_exit_history
  on public.student_exit_events(sid,school_date desc,created_at desc);
create index if not exists idx_student_exit_active_expiry
  on public.student_exit_events(expires_at)
  where status in ('prepared','gate_scanned');

create table if not exists private.student_exit_notification_outbox (
  id text primary key default ('out_'||replace(gen_random_uuid()::text,'-','')),
  exit_event_id text not null references public.student_exit_events(id) on delete restrict,
  recipient_user_id text not null references public.users(id) on delete restrict,
  notification_type text not null,
  channel text not null,
  recipient_address_snapshot text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued',
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  constraint exit_outbox_type_check check (
    notification_type in ('exit_prepared','exit_confirmed','exit_refused','exit_cancelled','exit_expired')
  ),
  constraint exit_outbox_channel_check check (channel in ('app','email','whatsapp')),
  constraint exit_outbox_status_check check (status in ('queued','sent','failed','skipped')),
  constraint exit_outbox_unique unique(exit_event_id,notification_type,channel)
);

alter table public.scan_log
  add column if not exists exit_event_id text,
  add column if not exists prepared_by_uid text,
  add column if not exists prepared_by_name text,
  add column if not exists prepared_by_role text,
  add column if not exists validated_by_uid text,
  add column if not exists validated_by_name text,
  add column if not exists validated_by_role text,
  add column if not exists gate_label text,
  add column if not exists preparation_time timestamptz,
  add column if not exists gate_scan_time timestamptz,
  add column if not exists validation_time timestamptz,
  add column if not exists escort_relation text,
  add column if not exists escort_photo_portrait text,
  add column if not exists escort_photo_full_body text,
  add column if not exists escort_id_doc_type text,
  add column if not exists escort_id_doc_last4 text;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.scan_log'::regclass and conname='scan_log_exit_event_id_fkey'
  ) then
    alter table public.scan_log add constraint scan_log_exit_event_id_fkey
      foreign key(exit_event_id) references public.student_exit_events(id) on delete restrict;
  end if;
end $$;
create unique index if not exists uq_scan_log_exit_event
  on public.scan_log(exit_event_id) where exit_event_id is not null;

create or replace function private.can_prepare_student_exit()
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(private.current_app_role() in ('direction','direction2','enseignant','gardien'),false)
$$;

create or replace function private.can_confirm_student_exit()
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(private.current_app_role() in ('direction','direction2','enseignant','gardien'),false)
$$;

create or replace function private.protect_student_exit_history()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if tg_op='DELETE' then
    raise exception 'L historique de sortie ne peut pas être supprimé.' using errcode='23514';
  end if;
  if old.status in ('confirmed','refused','cancelled','expired') then
    raise exception 'Un événement de sortie finalisé est immuable.' using errcode='23514';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

drop trigger if exists trg_student_exit_history_guard on public.student_exit_events;
create trigger trg_student_exit_history_guard
before update or delete on public.student_exit_events
for each row execute function private.protect_student_exit_history();

create or replace function private.queue_student_exit_notification(
  p_exit_event_id text,
  p_notification_type text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  e public.student_exit_events%rowtype;
  p public.users%rowtype;
  v_message text;
  v_type text := lower(btrim(coalesce(p_notification_type,'')));
  v_outbox_id text;
  v_channels jsonb := '[]'::jsonb;
  v_date text;
  v_time text;
begin
  select * into e from public.student_exit_events where id=p_exit_event_id;
  if not found then return jsonb_build_object('ok',false,'code','EXIT_EVENT_NOT_FOUND'); end if;
  select * into p from public.users where id=e.parent_id_snapshot;
  if not found then return jsonb_build_object('ok',false,'code','PARENT_NOT_FOUND'); end if;

  v_date:=to_char(timezone('Africa/Kinshasa',now()),'YYYY-MM-DD');
  v_time:=to_char(timezone('Africa/Kinshasa',now()),'HH24:MI');
  v_message:=case v_type
    when 'exit_prepared' then e.student_name_snapshot||' est prêt(e) pour la sortie. Vous pouvez venir le/la récupérer au portail.'
    when 'exit_confirmed' then 'La sortie de '||e.student_name_snapshot||' a été confirmée à '||
      coalesce(to_char(timezone('Africa/Kinshasa',e.validated_at),'HH24:MI'),v_time)||'. Récupéré(e) par '||
      coalesce(e.escort_name_snapshot,'la personne autorisée')||'.'
    when 'exit_refused' then 'La sortie de '||e.student_name_snapshot||' a été refusée. Contactez la Direction.'
    when 'exit_cancelled' then 'La préparation de sortie de '||e.student_name_snapshot||' a été annulée.'
    when 'exit_expired' then 'La préparation de sortie de '||e.student_name_snapshot||' a expiré. L enfant reste sous la responsabilité de l école.'
    else null
  end;
  if v_message is null then return jsonb_build_object('ok',false,'code','UNSUPPORTED_NOTIFICATION'); end if;

  v_outbox_id:=null;
  insert into private.student_exit_notification_outbox(
    exit_event_id,recipient_user_id,notification_type,channel,recipient_address_snapshot,payload,status
  ) values (
    e.id,p.id,v_type,'app',p.id,
    jsonb_build_object('message',v_message,'student_id',e.sid,'exit_event_id',e.id),
    'queued'
  ) on conflict(exit_event_id,notification_type,channel) do nothing returning id into v_outbox_id;
  if v_outbox_id is not null then
    insert into public.notifs(id,uid,"from",msg,type,date,time,read,by,status)
    values('notif_'||replace(gen_random_uuid()::text,'-',''),p.id,'SchoolSafe — Sortie',v_message,
      case when v_type in ('exit_refused','exit_expired') then 'warning' else 'info' end,
      v_date,v_time,false,coalesce(e.validated_by_user_id,e.gate_scanned_by_user_id,e.prepared_by_user_id),v_type);
    update private.student_exit_notification_outbox set status='sent',sent_at=now(),attempts=1
    where id=v_outbox_id;
    v_channels:=v_channels||'"app"'::jsonb;
  end if;

  if p.email is not null and p.login_email_enabled then
    v_outbox_id:=null;
    insert into private.student_exit_notification_outbox(
      exit_event_id,recipient_user_id,notification_type,channel,recipient_address_snapshot,payload,status
    ) values (
      e.id,p.id,v_type,'email',p.email,
      jsonb_build_object('subject','SchoolSafe — Sortie de '||e.student_name_snapshot,'message',v_message,
        'student_id',e.sid,'exit_event_id',e.id),'queued'
    ) on conflict(exit_event_id,notification_type,channel) do nothing returning id into v_outbox_id;
    if v_outbox_id is not null then v_channels:=v_channels||'"email"'::jsonb; end if;
  end if;

  if p.phone is not null and p.login_phone_enabled then
    v_outbox_id:=null;
    insert into private.student_exit_notification_outbox(
      exit_event_id,recipient_user_id,notification_type,channel,recipient_address_snapshot,payload,status
    ) values (
      e.id,p.id,v_type,'whatsapp',p.phone,
      jsonb_build_object('message',v_message,'student_id',e.sid,'exit_event_id',e.id),'queued'
    ) on conflict(exit_event_id,notification_type,channel) do nothing returning id into v_outbox_id;
    if v_outbox_id is not null then v_channels:=v_channels||'"whatsapp"'::jsonb; end if;
  end if;

  return jsonb_build_object('ok',true,'channels',v_channels,'message',v_message);
end;
$$;

create or replace function private.expire_student_exit_events()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_count integer:=0;
begin
  for r in
    select id from public.student_exit_events
    where status in ('prepared','gate_scanned') and expires_at<=now()
    for update skip locked
  loop
    update public.student_exit_events set status='expired',finalized_at=now(),decision_note='Expiration automatique'
    where id=r.id;
    perform private.queue_student_exit_notification(r.id,'exit_expired');
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.prepare_student_exit(
  p_sid text,
  p_gate_label text default null,
  p_manual boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=''
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
set search_path=''
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

create or replace function public.validate_student_exit(
  p_exit_event_id text,
  p_decision text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_decision text:=lower(btrim(coalesce(p_decision,'')));
  v_note text:=nullif(btrim(coalesce(p_note,'')),'');
  e public.student_exit_events%rowtype;
  v_notify jsonb;
  v_scan_id text;
begin
  if not private.can_confirm_student_exit() then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  perform private.expire_student_exit_events();
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  if v_decision not in ('authorized','refused') then
    return jsonb_build_object('ok',false,'code','UNSUPPORTED_DECISION');
  end if;
  if v_decision='refused' and (v_note is null or length(v_note)<3) then
    return jsonb_build_object('ok',false,'code','REFUSAL_REASON_REQUIRED');
  end if;

  select * into e from public.student_exit_events where id=p_exit_event_id for update;
  if not found then return jsonb_build_object('ok',false,'code','EXIT_EVENT_NOT_FOUND'); end if;
  if e.status<>'gate_scanned' then return jsonb_build_object('ok',false,'code','EXIT_NOT_READY_FOR_VALIDATION'); end if;
  perform pg_advisory_xact_lock(hashtext('student-exit:'||e.sid||':'||e.school_date::text));
  if v_decision='authorized' and exists(
    select 1 from public.student_exit_events x where x.sid=e.sid and x.school_date=e.school_date
      and x.status='confirmed' and x.id<>e.id
  ) then return jsonb_build_object('ok',false,'code','ALREADY_EXITED'); end if;

  update public.student_exit_events set
    status=case when v_decision='authorized' then 'confirmed' else 'refused' end,
    validated_at=now(),validated_by_user_id=v_actor_id,validated_by_name=v_actor_name,
    validated_by_role=v_role,decision_note=left(v_note,500),finalized_at=now()
  where id=e.id returning * into e;

  v_scan_id:='scan_'||replace(gen_random_uuid()::text,'-','');
  insert into public.scan_log(
    id,sid,type,status,date,time,name,label,by_uid,by_name,by_role,manual,description,note,
    escort_kind,escort_id,escort_name,exit_event_id,
    prepared_by_uid,prepared_by_name,prepared_by_role,
    validated_by_uid,validated_by_name,validated_by_role,gate_label,
    preparation_time,gate_scan_time,validation_time,escort_relation,
    escort_photo_portrait,escort_photo_full_body,escort_id_doc_type,escort_id_doc_last4
  ) values (
    v_scan_id,e.sid,'exit',case when v_decision='authorized' then 'authorized' else 'unauthorized' end,
    e.school_date::text,to_char(timezone('Africa/Kinshasa',e.validated_at),'HH24:MI'),e.student_name_snapshot,
    case when v_decision='authorized' then 'Sortie autorisée' else 'Sortie refusée' end,
    e.gate_scanned_by_user_id,e.gate_scanned_by_name,e.gate_scanned_by_role,e.manual,
    'Contrôle de sortie en deux étapes',e.decision_note,e.escort_kind,e.escort_id_snapshot,e.escort_name_snapshot,e.id,
    e.prepared_by_user_id,e.prepared_by_name,e.prepared_by_role,
    e.validated_by_user_id,e.validated_by_name,e.validated_by_role,e.gate_label,
    e.prepared_at,e.gate_scanned_at,e.validated_at,e.escort_relation_snapshot,
    e.escort_photo_portrait_snapshot,e.escort_photo_full_body_snapshot,e.escort_id_doc_type_snapshot,e.escort_id_doc_last4_snapshot
  );

  v_notify:=private.queue_student_exit_notification(e.id,
    case when v_decision='authorized' then 'exit_confirmed' else 'exit_refused' end);
  perform private.write_audit_event(v_actor_id,v_actor_name,
    case when v_decision='authorized' then 'student_exit_confirmed' else 'student_exit_refused' end,
    jsonb_build_object('exit_event_id',e.id,'student_id',e.sid,'scanner_id',e.gate_scanned_by_user_id,
      'validator_id',v_actor_id,'escort_name',e.escort_name_snapshot,'gate',e.gate_label,'notification',v_notify->'channels'),e.sid);

  return jsonb_build_object('ok',true,'code',
    case when v_decision='authorized' then 'EXIT_CONFIRMED' else 'EXIT_REFUSED' end,
    'exit_event_id',e.id,'scan_log_id',v_scan_id,'status',e.status,
    'prepared_by',e.prepared_by_name,'scanned_by',e.gate_scanned_by_name,'validated_by',e.validated_by_name,
    'escort_name',e.escort_name_snapshot,'notification',v_notify);
end;
$$;

create or replace function public.cancel_student_exit_preparation(
  p_exit_event_id text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  e public.student_exit_events%rowtype;
  v_notify jsonb;
begin
  if not private.can_prepare_student_exit() then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  if v_reason is null or length(v_reason)<3 then return jsonb_build_object('ok',false,'code','REASON_REQUIRED'); end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  select * into e from public.student_exit_events where id=p_exit_event_id for update;
  if not found then return jsonb_build_object('ok',false,'code','EXIT_EVENT_NOT_FOUND'); end if;
  if e.status not in ('prepared','gate_scanned') then return jsonb_build_object('ok',false,'code','EXIT_ALREADY_FINALIZED'); end if;
  if v_role='enseignant' and e.prepared_by_user_id<>v_actor_id then
    return jsonb_build_object('ok',false,'code','FORBIDDEN');
  end if;
  update public.student_exit_events set status='cancelled',decision_note=left(v_reason,500),finalized_at=now()
  where id=e.id returning * into e;
  v_notify:=private.queue_student_exit_notification(e.id,'exit_cancelled');
  perform private.write_audit_event(v_actor_id,v_actor_name,'student_exit_cancelled',
    jsonb_build_object('exit_event_id',e.id,'student_id',e.sid,'reason',v_reason,'notification',v_notify->'channels'),e.sid);
  return jsonb_build_object('ok',true,'code','EXIT_PREPARATION_CANCELLED','exit_event_id',e.id,'notification',v_notify);
end;
$$;

create or replace function public.get_student_exit_status(p_sid text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  e public.student_exit_events%rowtype;
  v_date date:=timezone('Africa/Kinshasa',now())::date;
begin
  if not (private.can_prepare_student_exit() or private.owns_student(p_sid)) then
    raise exception 'Accès refusé' using errcode='42501';
  end if;
  perform private.expire_student_exit_events();
  select * into e from public.student_exit_events
  where sid=p_sid and school_date=v_date order by created_at desc limit 1;
  return jsonb_build_object('ok',true,'event',case when e.id is null then null else to_jsonb(e) end,
    'pickup_context',public.get_student_pickup_context(p_sid));
end;
$$;

create or replace function private.notify_scan_event()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_parent text;
  v_message text;
  rec record;
begin
  if new.exit_event_id is not null then return new; end if;
  select pid into v_parent from public.students where id=new.sid;
  if new.type='entry' and new.status in ('ontime','late') then
    v_message:=new.name||' : entrée enregistrée à '||coalesce(new.time,'');
  elsif new.type='exit' and new.status='authorized' then
    v_message:=new.name||' : sortie autorisée à '||coalesce(new.time,'');
  else
    v_message:=new.name||' : contrôle de sécurité refusé. Contactez la Direction générale.';
  end if;
  if v_parent is not null then
    insert into public.notifs(id,uid,"from",msg,type,date,time,read,by)
    values('notif_'||replace(gen_random_uuid()::text,'-',''),v_parent,'SchoolSafe',v_message,
      case when new.status in ('ontime','late','authorized') then 'info' else 'warning' end,
      new.date,new.time,false,new.by_uid);
  end if;
  if new.status in ('refused_access','unauthorized') then
    for rec in select id from public.users where status='active'
      and role in ('direction','direction2','direction_pedagogique')
    loop
      insert into public.notifs(id,uid,"from",msg,type,date,time,read,by)
      values('notif_'||replace(gen_random_uuid()::text,'-',''),rec.id,'Contrôle d’accès',v_message,
        'warning',new.date,new.time,false,new.by_uid);
    end loop;
  end if;
  return new;
end;
$$;

create or replace function public.record_exit_scan(
  p_sid text,
  p_escort_kind text,
  p_escort_id text,
  p_escort_name text,
  p_manual boolean
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_role text:=private.current_app_role();
  scanned jsonb;
  validated jsonb;
  v_reason text;
begin
  v_reason:=case when v_role='enseignant' then 'Enseignant au poste de sortie — parcours compatible' else null end;
  scanned:=public.scan_student_exit_at_gate(
    p_sid,null,p_escort_kind,p_escort_id,'Portail principal',v_reason,p_manual
  );
  if scanned->>'ok'<>'true' then
    return jsonb_build_object('contract_version',3,'recorded',false,'allowed',false,
      'reason',lower(coalesce(scanned->>'code','exit_failed')),'details',scanned);
  end if;
  validated:=public.validate_student_exit(scanned->>'exit_event_id','authorized',null);
  if validated->>'ok'<>'true' then
    return jsonb_build_object('contract_version',3,'recorded',false,'allowed',false,
      'reason',lower(coalesce(validated->>'code','validation_failed')),'details',validated);
  end if;
  return jsonb_build_object('contract_version',3,'recorded',true,'allowed',true,
    'status','authorized','date',to_char(timezone('Africa/Kinshasa',now()),'YYYY-MM-DD'),
    'time',to_char(timezone('Africa/Kinshasa',now()),'HH24:MI'),
    'escort_name',validated->>'escort_name','exit_event_id',validated->>'exit_event_id',
    'prepared_by',validated->>'prepared_by','scanned_by',validated->>'scanned_by',
    'validated_by',validated->>'validated_by');
end;
$$;

alter table public.student_exit_events enable row level security;
create policy student_exit_events_read on public.student_exit_events
for select to authenticated using (
  private.is_direction_any()
  or private.owns_student(sid)
  or (private.current_app_role() in ('gardien','enseignant') and school_date=timezone('Africa/Kinshasa',now())::date)
);

alter table private.student_exit_notification_outbox enable row level security;
create policy student_exit_outbox_read on private.student_exit_notification_outbox
for select to authenticated using (
  private.is_direction_any() or recipient_user_id=private.current_app_user_id()
);

revoke all on public.student_exit_events from anon,authenticated;
grant select on public.student_exit_events to authenticated;
revoke all on private.student_exit_notification_outbox from anon,authenticated;
grant select on private.student_exit_notification_outbox to authenticated;

revoke all on function public.prepare_student_exit(text,text,boolean) from public,anon;
grant execute on function public.prepare_student_exit(text,text,boolean) to authenticated,service_role;
revoke all on function public.scan_student_exit_at_gate(text,text,text,text,text,text,boolean) from public,anon;
grant execute on function public.scan_student_exit_at_gate(text,text,text,text,text,text,boolean) to authenticated,service_role;
revoke all on function public.validate_student_exit(text,text,text) from public,anon;
grant execute on function public.validate_student_exit(text,text,text) to authenticated,service_role;
revoke all on function public.cancel_student_exit_preparation(text,text) from public,anon;
grant execute on function public.cancel_student_exit_preparation(text,text) to authenticated,service_role;
revoke all on function public.get_student_exit_status(text) from public,anon;
grant execute on function public.get_student_exit_status(text) to authenticated,service_role;
revoke all on function public.record_exit_scan(text,text,text,text,boolean) from public,anon;
grant execute on function public.record_exit_scan(text,text,text,text,boolean) to authenticated,service_role;

revoke all on function private.can_prepare_student_exit() from public,anon,authenticated;
revoke all on function private.can_confirm_student_exit() from public,anon,authenticated;
revoke all on function private.protect_student_exit_history() from public,anon,authenticated;
revoke all on function private.queue_student_exit_notification(text,text) from public,anon,authenticated;
revoke all on function private.expire_student_exit_events() from public,anon,authenticated;
grant execute on function private.can_prepare_student_exit() to service_role;
grant execute on function private.can_confirm_student_exit() to service_role;
grant execute on function private.protect_student_exit_history() to service_role;
grant execute on function private.queue_student_exit_notification(text,text) to service_role;
grant execute on function private.expire_student_exit_events() to service_role;

comment on table public.student_exit_events is
  'Journal immuable: préparation, scan au portail, personne récupératrice et validation finale.';
comment on table private.student_exit_notification_outbox is
  'File de livraison des notifications externes. App est immédiate; email et WhatsApp restent queued jusqu au dispatcher.';
comment on function public.prepare_student_exit(text,text,boolean) is
  'Enseignant/gardien/direction: prépare la sortie pendant 30 minutes et avertit le parent principal.';
comment on function public.scan_student_exit_at_gate(text,text,text,text,text,text,boolean) is
  'Gardien ou enseignant au portail: sélectionne et photographie la personne récupératrice dans l historique.';
comment on function public.validate_student_exit(text,text,text) is
  'Validation finale séparée; conserve le scanneur et le validateur même lorsqu ils sont la même personne.';