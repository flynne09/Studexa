-- Studexa Supabase-only backend. This migration intentionally starts the beta
-- schema empty; the separate cutover procedure archives and removes legacy data.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  display_name text not null default '',
  role text check (role is null or role in ('teacher', 'student')),
  photo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 160),
  join_code text not null unique check (join_code = upper(join_code)),
  teacher_name text not null default '',
  section text not null default '',
  subject text not null default '',
  status text not null default 'active' check (status in ('active', 'archived')),
  roster_count integer not null default 0 check (roster_count >= 0),
  recent_quiz text not null default 'No quizzes yet',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.class_members (
  class_id uuid not null references public.classes(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('teacher', 'student')),
  display_name_snapshot text not null default '',
  email_snapshot text not null default '',
  joined_at timestamptz not null default now(),
  primary key (class_id, user_id)
);

create table if not exists public.materials (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  file_name text not null,
  file_type text not null check (file_type in ('pdf', 'docx', 'pptx')),
  file_ref text not null unique,
  storage_provider text not null default 'supabase' check (storage_provider = 'supabase'),
  storage_bucket text not null default 'study-materials',
  storage_upload_status text check (storage_upload_status in ('uploading', 'completed', 'failed')),
  download_url text,
  converted_pdf_ref text,
  converted_pdf_url text,
  conversion_status text check (conversion_status in ('pending', 'completed', 'failed', 'unsupported')),
  converted_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'processing', 'ready', 'failed')),
  error_reason text,
  extracted_text text not null default '',
  file_size_bytes bigint check (file_size_bytes is null or file_size_bytes between 1 and 52428800),
  created_at timestamptz not null default now(),
  extracted_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (id, class_id, teacher_id)
);

create table if not exists public.quizzes (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  material_id uuid,
  quiz_type text not null check (quiz_type in ('actual', 'practice')),
  title text not null default 'Untitled Quiz',
  status text not null default 'draft' check (
    (quiz_type = 'actual' and status in ('draft', 'finalized')) or
    (quiz_type = 'practice' and status in ('draft', 'published', 'closed'))
  ),
  generation_method text not null default 'gemini' check (generation_method in ('gemini', 'fallback', 'manual')),
  source_quiz_id uuid references public.quizzes(id) on delete set null,
  questions jsonb not null default '[]'::jsonb check (jsonb_typeof(questions) = 'array'),
  total_points numeric not null default 0 check (total_points >= 0),
  requested_question_count integer check (requested_question_count between 1 and 50),
  selected_question_types text[] not null default '{}' check (
    selected_question_types <@ array['multiple_choice','true_false','fill_blank','identification','enumeration']::text[] and
    cardinality(selected_question_types) <= 5
  ),
  extra_generation_attempted boolean not null default false,
  generation_session_id text,
  extra_generation_session_id text,
  completed_batch_ids text[] not null default '{}',
  automatic_batches_attempted integer not null default 0 check (automatic_batches_attempted >= 0),
  extra_batches_attempted integer not null default 0 check (extra_batches_attempted >= 0),
  generation_credential_source text not null default 'personal' check (generation_credential_source in ('personal', 'backup')),
  backup_used boolean not null default false,
  backup_usage_reason text,
  backup_grace_remaining integer,
  backup_fallback_remaining_today integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz,
  unique (id, class_id),
  unique (id, class_id, teacher_id),
  check (requested_question_count is null or cardinality(selected_question_types) <= requested_question_count),
  foreign key (material_id, class_id, teacher_id)
    references public.materials(id, class_id, teacher_id)
);

create unique index if not exists quizzes_generation_session_uidx
  on public.quizzes (teacher_id, generation_session_id)
  where generation_session_id is not null;

create table if not exists public.quiz_assignments (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null,
  class_id uuid not null references public.classes(id) on delete cascade,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  quiz_title text not null default 'Untitled Quiz',
  deadline timestamptz,
  is_closed boolean not null default false,
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (class_id, quiz_id),
  unique (id, quiz_id, class_id),
  foreign key (quiz_id, class_id, teacher_id)
    references public.quizzes(id, class_id, teacher_id) on delete cascade
);

create table if not exists public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  client_attempt_id uuid not null,
  quiz_id uuid not null,
  assignment_id uuid references public.quiz_assignments(id) on delete set null,
  class_id uuid not null references public.classes(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  student_name text not null default 'Student',
  attempt_number integer not null check (attempt_number in (1, 2)),
  answers jsonb not null default '{}'::jsonb check (jsonb_typeof(answers) = 'object'),
  score numeric not null check (score >= 0),
  total_points numeric not null check (total_points >= 0 and score <= total_points),
  percentage numeric not null check (percentage between 0 and 100),
  breakdown jsonb not null default '[]'::jsonb check (jsonb_typeof(breakdown) = 'array'),
  submitted_at timestamptz not null default now(),
  unique (student_id, quiz_id, attempt_number),
  unique (student_id, client_attempt_id),
  foreign key (quiz_id, class_id)
    references public.quizzes(id, class_id) on delete cascade
);

create table if not exists public.quiz_drafts (
  student_id uuid not null references public.profiles(id) on delete cascade,
  quiz_id uuid not null references public.quizzes(id) on delete cascade,
  attempt_number integer not null check (attempt_number in (1, 2)),
  answers jsonb not null default '{}'::jsonb check (jsonb_typeof(answers) = 'object'),
  updated_at timestamptz not null default now(),
  primary key (student_id, quiz_id, attempt_number)
);

create index if not exists classes_teacher_idx on public.classes(teacher_id, created_at desc);
create index if not exists class_members_user_idx on public.class_members(user_id, joined_at desc);
create index if not exists materials_class_idx on public.materials(class_id, created_at desc);
create index if not exists materials_teacher_idx on public.materials(teacher_id, created_at desc);
create index if not exists quizzes_class_idx on public.quizzes(class_id, created_at desc);
create index if not exists quizzes_teacher_idx on public.quizzes(teacher_id, created_at desc);
create index if not exists assignments_class_idx on public.quiz_assignments(class_id, created_at desc);
create index if not exists attempts_quiz_idx on public.quiz_attempts(class_id, quiz_id, submitted_at desc);
create index if not exists attempts_student_idx on public.quiz_attempts(student_id, class_id, submitted_at desc);

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
drop trigger if exists classes_updated_at on public.classes;
create trigger classes_updated_at before update on public.classes
for each row execute function public.set_updated_at();
drop trigger if exists materials_updated_at on public.materials;
create trigger materials_updated_at before update on public.materials
for each row execute function public.set_updated_at();
drop trigger if exists quizzes_updated_at on public.quizzes;
create trigger quizzes_updated_at before update on public.quizzes
for each row execute function public.set_updated_at();
drop trigger if exists assignments_updated_at on public.quiz_assignments;
create trigger assignments_updated_at before update on public.quiz_assignments
for each row execute function public.set_updated_at();

create or replace function public.update_class_roster_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.role = 'student' then
    update public.classes set roster_count = roster_count + 1 where id = new.class_id;
  elsif tg_op = 'DELETE' and old.role = 'student' then
    update public.classes set roster_count = greatest(0, roster_count - 1) where id = old.class_id;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists class_members_roster_count on public.class_members;
create trigger class_members_roster_count
after insert or delete on public.class_members
for each row execute function public.update_class_roster_count();

create or replace function public.prepare_material_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.quizzes where material_id = old.id and status = 'draft';
  update public.quizzes set material_id = null where material_id = old.id;
  return old;
end;
$$;

drop trigger if exists materials_prepare_delete on public.materials;
create trigger materials_prepare_delete
before delete on public.materials
for each row execute function public.prepare_material_delete();

create or replace function public.handle_new_studexa_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  selected_role text;
begin
  selected_role := lower(new.raw_user_meta_data->>'studexa_role');
  if selected_role not in ('teacher', 'student') then selected_role := null; end if;
  insert into public.profiles (id, email, display_name, role, photo_url)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(coalesce(new.email, ''), '@', 1)),
    selected_role,
    coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture')
  )
  on conflict (id) do update set
    email = excluded.email,
    display_name = case when public.profiles.display_name = '' then excluded.display_name else public.profiles.display_name end,
    photo_url = coalesce(public.profiles.photo_url, excluded.photo_url);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update of email, raw_user_meta_data on auth.users
for each row execute function public.handle_new_studexa_user();

create or replace function public.current_studexa_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$ select role from public.profiles where id = auth.uid(); $$;

create or replace function public.is_class_owner(p_class_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select exists(select 1 from public.classes where id = p_class_id and teacher_id = auth.uid()); $$;

create or replace function public.is_class_member(p_class_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select exists(select 1 from public.class_members where class_id = p_class_id and user_id = auth.uid()); $$;

create or replace function public.claim_studexa_role(p_role text)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile public.profiles%rowtype;
  desired text := lower(btrim(p_role));
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if desired not in ('teacher', 'student') then raise exception 'Invalid role'; end if;
  select * into profile from public.profiles where id = auth.uid() for update;
  if profile.id is null then raise exception 'Profile unavailable'; end if;
  if profile.role is null then
    update public.profiles set role = desired where id = auth.uid() returning * into profile;
  elsif profile.role <> desired then
    raise exception 'This account is registered as a %, not a %', profile.role, desired using errcode = 'P0001';
  end if;
  return profile;
end;
$$;

create or replace function public.create_studexa_class(p_name text)
returns public.classes
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile public.profiles%rowtype;
  created public.classes%rowtype;
  prefix text;
  candidate text;
  chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  attempt integer;
begin
  select * into profile from public.profiles where id = auth.uid();
  if profile.role <> 'teacher' then raise exception 'Teacher account required'; end if;
  if length(btrim(p_name)) = 0 then raise exception 'Class name cannot be empty'; end if;
  prefix := upper(regexp_replace(split_part(btrim(p_name), ' ', 1), '[^A-Za-z]', '', 'g'));
  prefix := substr(prefix || 'CLS', 1, 3);
  for attempt in 1..30 loop
    candidate := prefix || '-' ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1) ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1) ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1) ||
      substr(chars, 1 + floor(random() * length(chars))::int, 1);
    exit when not exists(select 1 from public.classes where join_code = candidate);
  end loop;
  if exists(select 1 from public.classes where join_code = candidate) then raise exception 'Could not allocate a join code'; end if;
  insert into public.classes (teacher_id, name, join_code, teacher_name)
  values (profile.id, btrim(p_name), candidate, profile.display_name)
  returning * into created;
  insert into public.class_members (class_id, user_id, role, display_name_snapshot, email_snapshot)
  values (created.id, profile.id, 'teacher', profile.display_name, profile.email);
  return created;
end;
$$;

create or replace function public.join_studexa_class(p_join_code text)
returns public.classes
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile public.profiles%rowtype;
  target public.classes%rowtype;
begin
  select * into profile from public.profiles where id = auth.uid();
  if profile.role <> 'student' then raise exception 'Student account required'; end if;
  select * into target from public.classes where join_code = upper(btrim(p_join_code)) for update;
  if target.id is null then raise exception 'Class not found'; end if;
  if target.status <> 'active' then raise exception 'Class is inactive'; end if;
  if exists(select 1 from public.class_members where class_id = target.id and user_id = profile.id) then
    raise exception 'Already enrolled';
  end if;
  insert into public.class_members (class_id, user_id, role, display_name_snapshot, email_snapshot)
  values (target.id, profile.id, 'student', profile.display_name, profile.email);
  select * into target from public.classes c where c.id = target.id;
  return target;
end;
$$;

create or replace function public.append_manual_quiz_question(p_quiz_id uuid, p_question jsonb)
returns public.quizzes
language plpgsql
security definer
set search_path = ''
as $$
declare
  quiz public.quizzes%rowtype;
  next_question jsonb;
  next_number integer;
begin
  select * into quiz from public.quizzes where id = p_quiz_id for update;
  if quiz.id is null then raise exception 'This quiz no longer exists'; end if;
  if quiz.teacher_id <> auth.uid() then raise exception 'Only the class teacher can edit this quiz'; end if;
  if quiz.status <> 'draft' then raise exception 'Questions can only be added to a draft quiz'; end if;
  if length(btrim(p_question->>'question')) = 0 or length(btrim(p_question->>'correctAnswer')) = 0 then
    raise exception 'Question and correct answer are required';
  end if;
  if exists(select 1 from jsonb_array_elements(quiz.questions) q where lower(btrim(q->>'question')) = lower(btrim(p_question->>'question'))) then
    raise exception 'That question is already in this quiz';
  end if;
  next_number := jsonb_array_length(quiz.questions) + 1;
  next_question := p_question || jsonb_build_object('id', 'q_' || next_number, 'origin', 'manual');
  update public.quizzes set
    questions = questions || jsonb_build_array(next_question),
    total_points = total_points + greatest(1, coalesce((next_question->>'points')::numeric, 1))
  where id = p_quiz_id returning * into quiz;
  return quiz;
end;
$$;

-- Edge-only atomic persistence after the submit function computes the score.
create or replace function public.studexa_save_scored_attempt(
  p_student_id uuid,
  p_quiz_id uuid,
  p_class_id uuid,
  p_client_attempt_id uuid,
  p_answers jsonb,
  p_score numeric,
  p_total_points numeric,
  p_percentage numeric,
  p_breakdown jsonb,
  p_quiz_updated_at timestamptz
)
returns public.quiz_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  quiz public.quizzes%rowtype;
  assignment public.quiz_assignments%rowtype;
  profile public.profiles%rowtype;
  attempt public.quiz_attempts%rowtype;
  next_attempt integer;
begin
  select * into attempt from public.quiz_attempts
    where student_id = p_student_id and client_attempt_id = p_client_attempt_id;
  if attempt.id is not null then return attempt; end if;
  select * into profile from public.profiles where id = p_student_id;
  if profile.role <> 'student' then raise exception 'Student account required'; end if;
  select * into quiz from public.quizzes where id = p_quiz_id and class_id = p_class_id for update;
  if quiz.id is null or quiz.quiz_type <> 'practice' or quiz.status <> 'published' then
    raise exception 'This practice quiz is unavailable';
  end if;
  if quiz.updated_at is distinct from p_quiz_updated_at then
    raise exception 'The quiz changed while this attempt was being scored. Submit again.';
  end if;
  select * into attempt from public.quiz_attempts
    where student_id = p_student_id and client_attempt_id = p_client_attempt_id;
  if attempt.id is not null then return attempt; end if;
  if not exists(select 1 from public.class_members where class_id = p_class_id and user_id = p_student_id and role = 'student') then
    raise exception 'Class membership required';
  end if;
  select * into assignment from public.quiz_assignments
    where class_id = p_class_id and quiz_id = p_quiz_id;
  if assignment.id is not null and (assignment.is_closed or (assignment.deadline is not null and now() > assignment.deadline)) then
    raise exception 'This quiz is closed or its deadline has passed';
  end if;
  select count(*)::integer + 1 into next_attempt from public.quiz_attempts
    where student_id = p_student_id and quiz_id = p_quiz_id;
  if next_attempt > 2 then raise exception 'You have reached the maximum 2 attempts for this practice quiz'; end if;
  if p_score < 0 or p_total_points < 0 or p_score > p_total_points or
      p_total_points <> quiz.total_points or p_percentage < 0 or p_percentage > 100 then
    raise exception 'Invalid score';
  end if;
  insert into public.quiz_attempts (
    client_attempt_id, quiz_id, assignment_id, class_id, student_id, student_name,
    attempt_number, answers, score, total_points, percentage, breakdown
  ) values (
    p_client_attempt_id, p_quiz_id, assignment.id, p_class_id, p_student_id, profile.display_name,
    next_attempt, p_answers, p_score, p_total_points, p_percentage, p_breakdown
  ) returning * into attempt;
  delete from public.quiz_drafts where student_id = p_student_id and quiz_id = p_quiz_id and attempt_number = next_attempt;
  return attempt;
end;
$$;

alter table public.profiles enable row level security;
alter table public.classes enable row level security;
alter table public.class_members enable row level security;
alter table public.materials enable row level security;
alter table public.quizzes enable row level security;
alter table public.quiz_assignments enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.quiz_drafts enable row level security;

revoke all on all tables in schema public from anon;
grant select on public.profiles to authenticated;
grant select, insert, update, delete on public.classes, public.class_members, public.materials, public.quizzes, public.quiz_assignments, public.quiz_drafts to authenticated;
grant select on public.quiz_attempts to authenticated;

drop policy if exists "profiles read own" on public.profiles;
create policy "profiles read own" on public.profiles for select to authenticated using (id = auth.uid());
drop policy if exists "profiles update own non-role" on public.profiles;

drop policy if exists "classes visible to owner or member" on public.classes;
create policy "classes visible to owner or member" on public.classes for select to authenticated
using (teacher_id = auth.uid() or public.is_class_member(id));
drop policy if exists "teachers update owned classes" on public.classes;
create policy "teachers update owned classes" on public.classes for update to authenticated
using (teacher_id = auth.uid()) with check (teacher_id = auth.uid());
drop policy if exists "teachers delete owned classes" on public.classes;
create policy "teachers delete owned classes" on public.classes for delete to authenticated using (teacher_id = auth.uid());

drop policy if exists "members visible inside class" on public.class_members;
create policy "members visible inside class" on public.class_members for select to authenticated
using (public.is_class_owner(class_id) or public.is_class_member(class_id));

drop policy if exists "materials visible inside class" on public.materials;
create policy "materials visible inside class" on public.materials for select to authenticated
using (teacher_id = auth.uid() or public.is_class_member(class_id));
drop policy if exists "teachers insert owned materials" on public.materials;
create policy "teachers insert owned materials" on public.materials for insert to authenticated
with check (teacher_id = auth.uid() and public.is_class_owner(class_id));
drop policy if exists "teachers update owned materials" on public.materials;
create policy "teachers update owned materials" on public.materials for update to authenticated
using (teacher_id = auth.uid()) with check (teacher_id = auth.uid() and public.is_class_owner(class_id));
drop policy if exists "teachers delete owned materials" on public.materials;
create policy "teachers delete owned materials" on public.materials for delete to authenticated using (teacher_id = auth.uid());

drop policy if exists "quizzes visible by role" on public.quizzes;
create policy "quizzes visible by role" on public.quizzes for select to authenticated using (
  teacher_id = auth.uid() or (quiz_type = 'practice' and status = 'published' and public.is_class_member(class_id))
);
drop policy if exists "teachers insert owned quizzes" on public.quizzes;
create policy "teachers insert owned quizzes" on public.quizzes for insert to authenticated
with check (teacher_id = auth.uid() and public.is_class_owner(class_id));
drop policy if exists "teachers update owned quizzes" on public.quizzes;
create policy "teachers update owned quizzes" on public.quizzes for update to authenticated
using (teacher_id = auth.uid()) with check (teacher_id = auth.uid() and public.is_class_owner(class_id));
drop policy if exists "teachers delete owned quizzes" on public.quizzes;
create policy "teachers delete owned quizzes" on public.quizzes for delete to authenticated using (teacher_id = auth.uid());

drop policy if exists "assignments visible inside class" on public.quiz_assignments;
create policy "assignments visible inside class" on public.quiz_assignments for select to authenticated
using (teacher_id = auth.uid() or public.is_class_member(class_id));
drop policy if exists "teachers insert assignments" on public.quiz_assignments;
create policy "teachers insert assignments" on public.quiz_assignments for insert to authenticated
with check (teacher_id = auth.uid() and public.is_class_owner(class_id));
drop policy if exists "teachers update assignments" on public.quiz_assignments;
create policy "teachers update assignments" on public.quiz_assignments for update to authenticated
using (teacher_id = auth.uid()) with check (
  teacher_id = auth.uid() and public.is_class_owner(class_id) and exists (
    select 1 from public.quizzes q
    where q.id = quiz_id and q.class_id = class_id and q.teacher_id = auth.uid()
  )
);
drop policy if exists "teachers delete assignments" on public.quiz_assignments;
create policy "teachers delete assignments" on public.quiz_assignments for delete to authenticated using (teacher_id = auth.uid());

drop policy if exists "attempts visible to student or teacher" on public.quiz_attempts;
create policy "attempts visible to student or teacher" on public.quiz_attempts for select to authenticated
using (student_id = auth.uid() or public.is_class_owner(class_id));

drop policy if exists "students read own drafts" on public.quiz_drafts;
create policy "students read own drafts" on public.quiz_drafts for select to authenticated using (student_id = auth.uid());
drop policy if exists "students insert own drafts" on public.quiz_drafts;
create policy "students insert own drafts" on public.quiz_drafts for insert to authenticated
with check (
  student_id = auth.uid() and public.current_studexa_role() = 'student' and exists (
    select 1 from public.quizzes q
    where q.id = quiz_id and q.quiz_type = 'practice' and q.status = 'published'
      and public.is_class_member(q.class_id)
  )
);
drop policy if exists "students update own drafts" on public.quiz_drafts;
create policy "students update own drafts" on public.quiz_drafts for update to authenticated
using (student_id = auth.uid()) with check (
  student_id = auth.uid() and exists (
    select 1 from public.quizzes q
    where q.id = quiz_id and q.quiz_type = 'practice' and q.status = 'published'
      and public.is_class_member(q.class_id)
  )
);
drop policy if exists "students delete own drafts" on public.quiz_drafts;
create policy "students delete own drafts" on public.quiz_drafts for delete to authenticated using (student_id = auth.uid());

revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.handle_new_studexa_user() from public, anon, authenticated;
revoke all on function public.update_class_roster_count() from public, anon, authenticated;
revoke all on function public.prepare_material_delete() from public, anon, authenticated;
revoke all on function public.current_studexa_role() from public, anon;
revoke all on function public.is_class_owner(uuid) from public, anon;
revoke all on function public.is_class_member(uuid) from public, anon;
grant execute on function public.current_studexa_role() to authenticated;
grant execute on function public.is_class_owner(uuid) to authenticated;
grant execute on function public.is_class_member(uuid) to authenticated;

revoke all on function public.claim_studexa_role(text) from public, anon;
revoke all on function public.create_studexa_class(text) from public, anon;
revoke all on function public.join_studexa_class(text) from public, anon;
revoke all on function public.append_manual_quiz_question(uuid, jsonb) from public, anon;
grant execute on function public.claim_studexa_role(text) to authenticated;
grant execute on function public.create_studexa_class(text) to authenticated;
grant execute on function public.join_studexa_class(text) to authenticated;
grant execute on function public.append_manual_quiz_question(uuid, jsonb) to authenticated;
revoke all on function public.studexa_save_scored_attempt(uuid, uuid, uuid, uuid, jsonb, numeric, numeric, numeric, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public.studexa_save_scored_attempt(uuid, uuid, uuid, uuid, jsonb, numeric, numeric, numeric, jsonb, timestamptz) to service_role;

-- Replace Firebase-token Storage policies with native Supabase Auth policies.
drop policy if exists "Studexa users upload to own folder" on storage.objects;
drop policy if exists "Studexa users read materials" on storage.objects;
drop policy if exists "Studexa users delete own materials" on storage.objects;
drop policy if exists "Studexa teachers upload originals" on storage.objects;
drop policy if exists "Studexa class members read originals" on storage.objects;
drop policy if exists "Studexa teachers delete originals" on storage.objects;

create policy "Studexa teachers upload originals" on storage.objects for insert to authenticated
with check (
  bucket_id = 'study-materials' and
  (storage.foldername(name))[1] = 'uploads' and
  (storage.foldername(name))[2] = auth.uid()::text and
  public.current_studexa_role() = 'teacher'
);
create policy "Studexa class members read originals" on storage.objects for select to authenticated
using (
  bucket_id = 'study-materials' and exists (
    select 1 from public.materials m
    where m.file_ref = name and (m.teacher_id = auth.uid() or public.is_class_member(m.class_id))
  )
);
create policy "Studexa teachers delete originals" on storage.objects for delete to authenticated
using (
  bucket_id = 'study-materials' and
  (storage.foldername(name))[1] = 'uploads' and
  (storage.foldername(name))[2] = auth.uid()::text and
  public.current_studexa_role() = 'teacher'
);

-- Rebuild private per-teacher credential state for Supabase UUID identities.
do $$
begin
  if to_regclass('private.teacher_gemini_credentials') is not null then
    delete from vault.secrets where id in (select secret_id from private.teacher_gemini_credentials);
  end if;
end $$;
drop function if exists public.studexa_teacher_gemini_status(text);
drop function if exists public.studexa_get_teacher_gemini_credential(text);
drop function if exists public.studexa_upsert_teacher_gemini_credential(text, text, text);
drop function if exists public.studexa_mark_teacher_gemini_invalid(text);
drop function if exists public.studexa_delete_teacher_gemini_credential(text);
drop function if exists public.studexa_get_backup_session(text, text);
drop function if exists public.studexa_reserve_backup_session(text, text, text);
drop function if exists public.studexa_finish_backup_session(text, text, boolean);
drop table if exists private.teacher_gemini_backup_sessions;
drop table if exists private.teacher_gemini_credentials;

create table private.teacher_gemini_credentials (
  teacher_uid uuid primary key references auth.users(id) on delete cascade,
  secret_id uuid not null unique references vault.secrets(id) on delete cascade,
  last_four text not null check (char_length(last_four) = 4),
  status text not null default 'valid' check (status in ('valid', 'invalid')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_validated_at timestamptz not null default now()
);
create table private.teacher_gemini_backup_sessions (
  teacher_uid uuid not null references auth.users(id) on delete cascade,
  client_session_id text not null,
  reason text not null check (reason in ('grace', 'personal_quota', 'provider_unavailable')),
  state text not null default 'reserved' check (state in ('reserved', 'used', 'failed')),
  reserved_at timestamptz not null default now(),
  used_at timestamptz,
  primary key (teacher_uid, client_session_id)
);
create index teacher_gemini_backup_sessions_daily_idx
  on private.teacher_gemini_backup_sessions (teacher_uid, used_at) where state = 'used';
revoke all on private.teacher_gemini_credentials, private.teacher_gemini_backup_sessions from public, anon, authenticated;

do $$
declare table_name text;
begin
  foreach table_name in array array['classes','class_members','materials','quizzes','quiz_assignments','quiz_attempts','quiz_drafts'] loop
    if not exists (
      select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = table_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end $$;
