# Supabase Storage Setup

Studexa stores original PDF, DOCX, and PPTX material in the private Supabase
bucket `study-materials`. Authentication and authorization use native Supabase
Auth sessions; the earlier Firebase third-party JWT integration is obsolete.

## Project setup

1. Link the repository to Supabase project `zuidphgogdwyrtndbgkx`.
2. Apply every versioned migration:

   ```powershell
   npx supabase db push --linked
   ```

3. Confirm bucket `study-materials` exists and is private.
4. Confirm these Storage policies from the full-backend and later
   `202609250002_material_post_confirmation.sql` migrations are present:
   - `Studexa teachers upload originals`
   - `Studexa class members read originals`
   - `Studexa teachers delete originals`
5. Do not add the Supabase secret/service-role key to Flutter configuration.

## Object layout

Every original uses:

```text
study-materials/uploads/{supabaseAuthUid}/{materialId}/{safeFileName}
```

The first path segment is fixed to `uploads`; the second must equal
`auth.uid()`. The matching `materials.file_ref` stores the object path. A class
member can download the object only while the related material row authorizes
that class access. The owner can read the draft; enrolled Students can read the
object only after the material is explicitly posted, ready, and fully uploaded.

## Flutter configuration

Copy `supabase.config.example.json` to ignored `supabase.config.json` and fill
the public values:

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT_REF.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "YOUR_SUPABASE_PUBLISHABLE_KEY",
  "GOOGLE_WEB_CLIENT_ID": "YOUR_GOOGLE_WEB_OAUTH_CLIENT_ID.apps.googleusercontent.com"
}
```

Run or build with:

```powershell
flutter run --dart-define-from-file=supabase.config.json
flutter build apk --release --dart-define-from-file=supabase.config.json
```

## Current upload behavior

`MaterialService.uploadStudyMaterial()` extracts readable text on-device and
uploads the original file to Supabase. New material rows begin with
`is_posted = false`. After upload/extraction is ready, the Teacher explicitly
posts the material; `postMaterial()` sets `is_posted = true` and `posted_at`.
Unposting hides the row and original from Students without deleting either.
Material state records upload, extraction, posting, and conversion status in
Postgres. Supabase does not invoke the historical Firebase Storage
`extractText` trigger.

PDFs can be rendered inside Studexa. DOCX and PPTX originals are downloaded to
an authenticated local cache and opened through a compatible installed app.
The original Office document is preserved; extracted text is used for Gemini
quiz grounding.

## Verification

Use temporary Teacher, Student, and unrelated-Teacher accounts:

1. Teacher uploads under their own UID path: allowed.
2. Teacher uploads under another UID path: denied.
3. Enrolled Student cannot read/download the unposted draft.
4. Teacher posts the ready/completed material; enrolled Student can then read
   and download it.
5. Unrelated account downloads it: denied.
6. Teacher unposts it; enrolled Student loses read/download access.
7. Owning Teacher deletes it: allowed.
8. Student or unrelated Teacher deletes it: denied.

The production cutover verifier `tool/verify_live_supabase_cutover.mjs`
exercises the allowed upload, enrolled read, unrelated denial, and cleanup
paths. It accepts a temporary private key file only at execution time; that key
file must remain ignored and be deleted immediately afterward.
