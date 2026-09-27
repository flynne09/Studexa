-- Migration: 202609250002_material_post_confirmation.sql
-- Add post confirmation workflow for study materials.
-- Materials are created as unposted drafts (is_posted = false).
-- Only when completely uploaded to storage and explicitly posted by the teacher
-- can students in the class view or download them.

alter table public.materials
  add column if not exists is_posted boolean not null default false,
  add column if not exists posted_at timestamptz;

-- Backfill existing materials that are already ready and completed.
update public.materials
set is_posted = true,
    posted_at = coalesce(extracted_at, created_at)
where status = 'ready'
  and (storage_upload_status = 'completed' or storage_upload_status is null);

-- Update RLS policy for materials table:
-- Teachers see all materials in their classes (draft and posted).
-- Students only see materials that are explicitly posted, ready, and completed upload.
drop policy if exists "materials visible inside class" on public.materials;
create policy "materials visible inside class" on public.materials for select to authenticated
using (
  teacher_id = auth.uid() or (
    is_posted = true and
    status = 'ready' and
    (storage_upload_status = 'completed' or storage_upload_status is null) and
    public.is_class_member(class_id)
  )
);

-- Update storage objects read policy:
-- Teachers can download their own files.
-- Students can only download if the material is posted, ready, and completed upload.
drop policy if exists "Studexa class members read originals" on storage.objects;
create policy "Studexa class members read originals" on storage.objects for select to authenticated
using (
  bucket_id = 'study-materials' and exists (
    select 1 from public.materials m
    where m.file_ref = name and (
      m.teacher_id = auth.uid() or (
        m.is_posted = true and
        m.status = 'ready' and
        (m.storage_upload_status = 'completed' or m.storage_upload_status is null) and
        public.is_class_member(m.class_id)
      )
    )
  )
);
