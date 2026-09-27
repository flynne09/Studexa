begin;

create extension if not exists pgtap with schema extensions;
select plan(38);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@example.test', '', now(), '{}', '{"display_name":"Owner"}', now(), now()),
  ('10000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'student@example.test', '', now(), '{}', '{"display_name":"Student"}', now(), now()),
  ('10000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outsider@example.test', '', now(), '{}', '{"display_name":"Outsider","studexa_role":"teacher"}', now(), now());

select is((
  select count(*)::integer
  from public.profiles
  where id in (
    '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000003'
  )
), 3, 'Auth trigger creates three fixture profiles');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select lives_ok($$select public.claim_studexa_role('teacher')$$, 'Owner claims Teacher once');
select is((select role from public.profiles where id = auth.uid()), 'teacher', 'Claim persists Teacher role');
select throws_ok($$select public.claim_studexa_role('student')$$, 'P0001', null, 'Teacher role cannot change to Student');
select lives_ok($$select public.create_studexa_class('Operating Systems', 'BSCS-3A')$$, 'Teacher creates a class atomically');
select is((select section from public.classes where teacher_id = auth.uid()), 'BSCS-3A', 'Class creation stores the entered section');
select is((select subject from public.classes where teacher_id = auth.uid()), 'Operating Systems', 'Class creation uses the class name as its subject');
select throws_ok($$select public.create_studexa_class('Networks', '   ')$$, 'P0001', null, 'Class creation requires a section');
select is((select count(*)::integer from public.class_members where user_id = auth.uid() and role = 'teacher'), 1, 'Class creation adds Teacher membership');
select is((select roster_count from public.classes where teacher_id = auth.uid()), 0, 'Teacher membership does not increase Student roster');

select set_config('test.class_id', (select id::text from public.classes where teacher_id = auth.uid()), true);
select set_config('test.join_code', (select join_code from public.classes where teacher_id = auth.uid()), true);

insert into public.materials (
  id, teacher_id, class_id, file_name, file_type, file_ref,
  storage_upload_status, status, extracted_text, is_posted, posted_at
) values (
  '20000000-0000-4000-8000-000000000001', auth.uid(), current_setting('test.class_id')::uuid,
  'lesson.pdf', 'pdf', 'uploads/10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001/lesson.pdf',
  'completed', 'ready', 'A processor executes instructions.', true, now()
);

insert into public.quizzes (
  id, class_id, teacher_id, material_id, quiz_type, title, status,
  questions, total_points, requested_question_count, selected_question_types
) values
  ('30000000-0000-4000-8000-000000000001', current_setting('test.class_id')::uuid, auth.uid(), '20000000-0000-4000-8000-000000000001', 'actual', 'Actual', 'finalized', '[{"id":"q_1","type":"identification","question":"CPU?","correctAnswer":"processor","points":1}]', 1, 1, array['identification']),
  ('30000000-0000-4000-8000-000000000002', current_setting('test.class_id')::uuid, auth.uid(), '20000000-0000-4000-8000-000000000001', 'practice', 'Practice', 'published', '[{"id":"q_1","type":"identification","question":"CPU?","correctAnswer":"processor","points":1}]', 1, 1, array['identification']),
  ('30000000-0000-4000-8000-000000000003', current_setting('test.class_id')::uuid, auth.uid(), '20000000-0000-4000-8000-000000000001', 'practice', 'Draft', 'draft', '[{"id":"q_1","type":"identification","question":"CPU?","correctAnswer":"processor","points":1}]', 1, 1, array['identification']);

insert into public.quiz_assignments (
  id, quiz_id, class_id, teacher_id, quiz_title
) values (
  '40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002',
  current_setting('test.class_id')::uuid, auth.uid(), 'Practice'
);

select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner_id) values (
    'study-materials',
    'uploads/10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001/lesson.pdf',
    '10000000-0000-4000-8000-000000000001'
  )$$,
  'Teacher can upload only inside the owned Storage prefix'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select lives_ok($$select public.claim_studexa_role('student')$$, 'Student claims Student role');
select lives_ok($$select public.join_studexa_class(current_setting('test.join_code'))$$, 'Student joins by code');
select is((select roster_count from public.classes where id = current_setting('test.class_id')::uuid), 1, 'Joining increments roster once');
select throws_ok($$select public.join_studexa_class(current_setting('test.join_code'))$$, 'P0001', null, 'Duplicate enrollment is rejected');
select is((select count(*)::integer from public.classes where id = current_setting('test.class_id')::uuid), 1, 'Member sees the joined class');
select is((select count(*)::integer from public.materials where id = '20000000-0000-4000-8000-000000000001'), 1, 'Member sees posted class material');
select is((select count(*)::integer from public.quizzes where id in (
  '30000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000003'
)), 1, 'Student sees only the published Practice fixture quiz');
select is((select count(*)::integer from public.quiz_assignments where id = '40000000-0000-4000-8000-000000000001'), 1, 'Student sees the fixture class assignment');
select lives_ok($$insert into public.quiz_drafts (student_id, quiz_id, attempt_number, answers)
  values (auth.uid(), '30000000-0000-4000-8000-000000000002', 1, '{"q_1":"processor"}')$$,
  'Student saves own published-Practice draft');
select throws_ok($$select public.create_studexa_class('Not allowed', 'BSCS-3A')$$, 'P0001', null, 'Student cannot create a class');
select is((select count(*)::integer from storage.objects where bucket_id = 'study-materials' and name =
  'uploads/10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001/lesson.pdf'
), 1, 'Member can read the related private fixture object');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select lives_ok($$select public.claim_studexa_role('teacher')$$, 'Unrelated Teacher role remains valid');
select is((select count(*)::integer from public.classes where id = current_setting('test.class_id')::uuid), 0, 'Unrelated Teacher cannot read the fixture class');
select is((select count(*)::integer from public.materials where id = '20000000-0000-4000-8000-000000000001'), 0, 'Unrelated Teacher cannot read fixture material');
select is((select count(*)::integer from public.quizzes where id in (
  '30000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000003'
)), 0, 'Unrelated Teacher cannot read fixture quizzes');
select is((select count(*)::integer from public.quiz_attempts where client_attempt_id in (
  '50000000-0000-4000-8000-000000000001',
  '50000000-0000-4000-8000-000000000002'
)), 0, 'Unrelated Teacher cannot read fixture attempts');
select is((select count(*)::integer from storage.objects where bucket_id = 'study-materials' and name =
  'uploads/10000000-0000-4000-8000-000000000001/20000000-0000-4000-8000-000000000001/lesson.pdf'
), 0, 'Unrelated Teacher cannot read private fixture object');
select throws_ok($$insert into public.quiz_drafts (student_id, quiz_id, attempt_number, answers)
  values (auth.uid(), '30000000-0000-4000-8000-000000000002', 1, '{}')$$,
  '42501', null, 'Teacher cannot create a Student draft');

reset role;
set local role service_role;
select throws_ok($$select public.studexa_save_scored_attempt(
  '10000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000002',
  current_setting('test.class_id')::uuid,
  '50000000-0000-4000-8000-000000000002',
  '{"q_1":"processor"}', 1, 1, 100,
  '[{"questionId":"q_1","earned":1,"points":1}]',
  (select updated_at - interval '1 second' from public.quizzes where id = '30000000-0000-4000-8000-000000000002')
)$$, 'P0001', null, 'Scored attempt rejects a stale quiz version');
select lives_ok($$select public.studexa_save_scored_attempt(
  '10000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000002',
  current_setting('test.class_id')::uuid,
  '50000000-0000-4000-8000-000000000001',
  '{"q_1":"processor"}', 1, 1, 100,
  '[{"questionId":"q_1","earned":1,"points":1}]',
  (select updated_at from public.quizzes where id = '30000000-0000-4000-8000-000000000002')
)$$, 'Service role saves authoritative score');
select lives_ok($$select public.studexa_save_scored_attempt(
  '10000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000002',
  current_setting('test.class_id')::uuid,
  '50000000-0000-4000-8000-000000000001',
  '{"q_1":"processor"}', 1, 1, 100,
  '[{"questionId":"q_1","earned":1,"points":1}]',
  (select updated_at from public.quizzes where id = '30000000-0000-4000-8000-000000000002')
)$$, 'Stable retry returns the existing attempt');
select is((select count(*)::integer from public.quiz_attempts where client_attempt_id = '50000000-0000-4000-8000-000000000001'), 1, 'Retry does not duplicate fixture attempt');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
select is((select count(*)::integer from public.quiz_attempts where client_attempt_id = '50000000-0000-4000-8000-000000000001'), 1, 'Student reads own fixture result');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select is((select count(*)::integer from public.quiz_attempts where client_attempt_id = '50000000-0000-4000-8000-000000000001'), 1, 'Owning Teacher reads fixture class result');
select lives_ok($$delete from public.materials where id = '20000000-0000-4000-8000-000000000001'$$,
  'Teacher can delete owned material');
select is((select count(*)::integer from public.quizzes where id = '30000000-0000-4000-8000-000000000003'), 0, 'Material deletion removes draft quiz');
select is((select count(*)::integer from public.quizzes where material_id is null and id in (
  '30000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002'
)), 2, 'Material deletion preserves finalized/published quizzes without an orphan reference');

select * from finish();
rollback;
