-- Require a section for every class created through the application and keep
-- the class subject aligned with its displayed class name.

drop function if exists public.create_studexa_class(text);

create or replace function public.create_studexa_class(
  p_name text,
  p_section text
)
returns public.classes
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile public.profiles%rowtype;
  created public.classes%rowtype;
  clean_name text := btrim(coalesce(p_name, ''));
  clean_section text := btrim(coalesce(p_section, ''));
  prefix text;
  candidate text;
  chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  attempt integer;
begin
  select * into profile from public.profiles where id = auth.uid();
  if profile.role <> 'teacher' then
    raise exception 'Teacher account required';
  end if;
  if clean_name = '' then
    raise exception 'Class name cannot be empty';
  end if;
  if clean_section = '' then
    raise exception 'Class section cannot be empty';
  end if;

  prefix := upper(regexp_replace(split_part(clean_name, ' ', 1), '[^A-Za-z]', '', 'g'));
  prefix := substr(prefix || 'CLS', 1, 3);
  for attempt in 1..30 loop
    candidate := prefix || '-' ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1) ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1) ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1) ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1);
    exit when not exists(select 1 from public.classes where join_code = candidate);
  end loop;
  if exists(select 1 from public.classes where join_code = candidate) then
    raise exception 'Could not allocate a join code';
  end if;

  insert into public.classes (
    teacher_id,
    name,
    join_code,
    teacher_name,
    section,
    subject
  ) values (
    profile.id,
    clean_name,
    candidate,
    profile.display_name,
    clean_section,
    clean_name
  )
  returning * into created;

  insert into public.class_members (
    class_id,
    user_id,
    role,
    display_name_snapshot,
    email_snapshot
  ) values (
    created.id,
    profile.id,
    'teacher',
    profile.display_name,
    profile.email
  );

  return created;
end;
$$;

revoke all on function public.create_studexa_class(text, text) from public, anon;
grant execute on function public.create_studexa_class(text, text) to authenticated;
