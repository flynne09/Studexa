-- One-time clean beta boundary. The encrypted recovery archive was finalized
-- before this migration. Keep schema, policies, bucket configuration, and the
-- server-side GEMINI_API_KEY while removing every user-created record/object.

delete from private.teacher_gemini_backup_sessions;
delete from private.teacher_gemini_credentials;

delete from storage.objects
where bucket_id = 'study-materials';

-- profiles and all application data cascade from Supabase Auth identities.
delete from auth.users;

-- Defensive cleanup for a partially initialized project. Foreign keys make
-- these empty after auth.users deletion in a normal Studexa installation.
delete from public.quiz_drafts;
delete from public.quiz_attempts;
delete from public.quiz_assignments;
delete from public.quizzes;
delete from public.materials;
delete from public.class_members;
delete from public.classes;
delete from public.profiles;

do $$
begin
  if exists (select 1 from auth.users) then
    raise exception 'Clean beta reset left Supabase Auth users behind';
  end if;
  if exists (
    select 1 from public.profiles
    union all select 1 from public.classes
    union all select 1 from public.class_members
    union all select 1 from public.materials
    union all select 1 from public.quizzes
    union all select 1 from public.quiz_assignments
    union all select 1 from public.quiz_attempts
    union all select 1 from public.quiz_drafts
  ) then
    raise exception 'Clean beta reset left application rows behind';
  end if;
  if exists (
    select 1 from private.teacher_gemini_credentials
    union all select 1 from private.teacher_gemini_backup_sessions
  ) then
    raise exception 'Clean beta reset left Gemini credential metadata behind';
  end if;
  if exists (select 1 from storage.objects where bucket_id = 'study-materials') then
    raise exception 'Clean beta reset left study-materials objects behind';
  end if;
end;
$$;
