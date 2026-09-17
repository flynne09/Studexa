-- Run this in Supabase SQL Editor after enabling the Firebase third-party
-- authentication integration for Firebase project `studexa-b5e55`.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'study-materials',
  'study-materials',
  false,
  52428800,
  array[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Studexa users upload to own folder" on storage.objects;
create policy "Studexa users upload to own folder"
on storage.objects
for insert
to anon, authenticated
with check (
  bucket_id = 'study-materials'
  and (storage.foldername(name))[1] = 'uploads'
  and (storage.foldername(name))[2] = (auth.jwt()->>'sub')
  and auth.jwt()->>'iss' =
    'https://securetoken.google.com/studexa-b5e55'
  and auth.jwt()->>'aud' = 'studexa-b5e55'
);

-- This matches the existing Firebase Storage behavior: any signed-in Studexa
-- user can read a material when they know its unguessable object path.
drop policy if exists "Studexa users read materials" on storage.objects;
create policy "Studexa users read materials"
on storage.objects
for select
to anon, authenticated
using (
  bucket_id = 'study-materials'
  and auth.jwt()->>'sub' is not null
  and auth.jwt()->>'iss' =
    'https://securetoken.google.com/studexa-b5e55'
  and auth.jwt()->>'aud' = 'studexa-b5e55'
);

drop policy if exists "Studexa users delete own materials" on storage.objects;
create policy "Studexa users delete own materials"
on storage.objects
for delete
to anon, authenticated
using (
  bucket_id = 'study-materials'
  and (storage.foldername(name))[1] = 'uploads'
  and (storage.foldername(name))[2] = (auth.jwt()->>'sub')
  and auth.jwt()->>'iss' =
    'https://securetoken.google.com/studexa-b5e55'
  and auth.jwt()->>'aud' = 'studexa-b5e55'
);
