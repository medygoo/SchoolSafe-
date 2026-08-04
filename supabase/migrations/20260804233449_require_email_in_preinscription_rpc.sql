-- Make the public pre-registration RPC report the mandatory e-mail field explicitly.
do $migration$
declare
  v_definition text;
  v_old text := 'if v_email is not null and (';
  v_new text := 'if v_email is null or (';
begin
  select pg_get_functiondef('public.submit_preinscription(jsonb)'::regprocedure)
  into v_definition;

  if position(v_old in v_definition) = 0 then
    raise exception 'submit_preinscription e-mail validation pattern not found';
  end if;

  if length(v_definition) - length(replace(v_definition, v_old, '')) <> length(v_old) then
    raise exception 'submit_preinscription e-mail validation pattern is not unique';
  end if;

  execute replace(v_definition, v_old, v_new);
end;
$migration$;