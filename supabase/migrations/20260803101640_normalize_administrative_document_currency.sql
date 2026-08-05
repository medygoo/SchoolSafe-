create or replace function private.set_administrative_document_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_financial boolean;
begin
  select t.is_financial into v_financial
  from public.administrative_document_types t
  where t.id = new.document_type_id and t.active = true;

  if v_financial is null then
    raise exception 'Administrative document type is missing or inactive';
  end if;

  new.is_financial := v_financial;
  new.currency := coalesce(nullif(upper(btrim(new.currency)), ''), 'USD');

  if v_financial then
    new.confidentiality := case
      when new.confidentiality = 'restricted' then 'restricted'
      else 'financial'
    end;
  elsif new.confidentiality = 'financial' then
    new.confidentiality := 'administrative';
  end if;

  new.updated_at := now();
  return new;
end;
$$;
