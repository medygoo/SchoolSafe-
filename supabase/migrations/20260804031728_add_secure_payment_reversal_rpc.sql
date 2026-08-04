create or replace function public.reverse_payment_transaction(
  p_transaction_id text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := private.current_app_role();
  v_uid text := private.current_app_user_id();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_tx public.payment_transactions%rowtype;
begin
  if v_role not in ('direction', 'direction3') or v_uid is null then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;

  if nullif(btrim(coalesce(p_transaction_id, '')), '') is null then
    raise exception 'Transaction requise' using errcode = '22023';
  end if;

  if length(v_reason) < 5 or length(v_reason) > 500 then
    raise exception 'Motif de contrepassation invalide' using errcode = '22023';
  end if;

  select *
  into v_tx
  from public.payment_transactions
  where id = p_transaction_id
  for update;

  if not found then
    raise exception 'Transaction introuvable' using errcode = 'P0002';
  end if;

  if v_tx.status <> 'confirmed' then
    raise exception 'Transaction déjà annulée ou indisponible' using errcode = '23514';
  end if;

  update public.payment_transactions
  set status = 'reversed',
      reversed_at = now(),
      reversed_by = v_uid,
      reversal_reason = v_reason,
      updated_at = now()
  where id = v_tx.id;

  return jsonb_build_object(
    'ok', true,
    'code', 'PAYMENT_REVERSED',
    'transaction_id', v_tx.id,
    'student_id', v_tx.sid,
    'receipt_no', v_tx.receipt_no,
    'amount', v_tx.amount,
    'currency', v_tx.currency,
    'status', 'reversed',
    'reversed_by', v_uid,
    'reversed_at', now(),
    'reason', v_reason
  );
end;
$$;

revoke all on function public.reverse_payment_transaction(text, text) from public;
revoke all on function public.reverse_payment_transaction(text, text) from anon;
grant execute on function public.reverse_payment_transaction(text, text) to authenticated;
grant execute on function public.reverse_payment_transaction(text, text) to service_role;

comment on function public.reverse_payment_transaction(text, text) is
  'Atomically reverses a confirmed payment without deleting the transaction or its allocations. Direction 1 and Caisse only.';
