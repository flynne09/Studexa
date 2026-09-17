# Supabase Storage Setup for Studexa

Studexa keeps Firebase Authentication and Cloud Firestore. Only original study
material files are stored in the private Supabase `study-materials` bucket.

## Dashboard setup

1. In Supabase, confirm **Authentication > Third-party Auth > Firebase** lists
   Firebase project ID `studexa-b5e55` and is enabled.
2. Open **SQL Editor**, paste the complete contents of
   `supabase/migrations/202609170001_study_material_storage.sql`, and select
   **Run**. This creates the private bucket, the 50 MB/MIME restrictions, and
   Firebase-JWT-based upload, read, and delete policies.
3. Open **Project Settings > API** (or the project's **Connect** dialog) and
   copy the **Project URL** and **Publishable key**. Never use the secret or
   service-role key in Flutter.

## Run Studexa with the Supabase configuration

The project includes its public Supabase Project URL and publishable client key
as safe defaults in `lib/config/supabase_config.dart`. The git-ignored
`supabase.local.json` and dart-defines can still override these defaults for a
different Supabase project. Never replace the publishable key with a secret or
service-role key.

Stop the currently running app completely and rebuild/start `main.dart` again.
Hot reload does not replace compile-time configuration in an already running
application.

PowerShell:

```powershell
flutter run --dart-define="SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co" --dart-define="SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY"
```

For an APK:

```powershell
flutter build apk --debug --dart-define="SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co" --dart-define="SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY"
```

The publishable key is intended for client apps. Authorization is enforced by
the private bucket's Row Level Security policies. Do not commit or pass a
Supabase secret/service-role key through `--dart-define`.

## Expected behavior

- The original file uploads in the background to
  `study-materials/uploads/{firebaseUid}/{materialId}/{safeFileName}`.
- On-device extraction still saves ready text to Firestore immediately.
- PDFs load from private Supabase bytes in the in-app viewer.
- DOCX/PPTX originals download from Supabase and open in a compatible device
  app; extracted-text viewing remains available.
- New DOCX/PPTX records use `conversionStatus: unsupported` because the old
  Firebase Storage-triggered Office-to-PDF converter does not receive Supabase
  upload events.

## Verification

1. Sign in as a teacher and upload a small PDF.
2. Confirm a file appears in Supabase Storage under `study-materials/uploads`.
3. Confirm the Firestore material contains `storageProvider: supabase`,
   `storageBucket: study-materials`, and eventually
   `storageUploadStatus: completed`.
4. Open the PDF from both the teacher and an enrolled student account.
5. Upload a DOCX or PPTX and verify **Open Original** and extracted text.
6. Attempt an upload without signing in; Supabase must reject it.

Supabase recommends resumable TUS uploads for files above 6 MB. The current
integration supports the project's existing 50 MB limit through the standard
upload API, but large-file resumable progress is a separate enhancement.
