# Supabase quiz generation deployment

Studexa keeps Firebase Authentication and the Firestore `default` database. Only
Gemini-backed quiz generation moves to the Supabase `generate-quiz` Edge Function.
The existing Firebase quiz functions stay deployed for older APKs.

1. In Supabase project `zuidphgogdwyrtndbgkx`, add the existing Gemini key under
   **Edge Functions > Secrets** as `GEMINI_API_KEY`. Do not put it in Flutter,
   Git, a dart-define, or a Supabase publishable key.
2. On the development computer, sign in with an account that can deploy to that
   project: `npx --yes supabase login`. The CLI is a development tool; it is not
   an app dependency. Do not paste a personal access token into chat. If npm
   reports a certificate-chain error on this Windows computer, set
   `$env:NODE_OPTIONS='--use-system-ca'` in that PowerShell session and retry.
3. Deploy from the repository root:
   `$env:NODE_OPTIONS='--use-system-ca'; npx --yes supabase@2.102.0 functions deploy generate-quiz --project-ref zuidphgogdwyrtndbgkx --use-api --no-verify-jwt`.
   CLI 2.102.0 was used for the verified deployment on this computer because
   CLI 2.117.0 returned a transport error under its HTTPS inspection setup.
   The checked-in `supabase/config.toml` disables Supabase's platform JWT check
   for this function because the caller sends a Firebase token. The handler
   verifies that token through Firebase Authentication **before** reading
   Firestore or calling Gemini, then reads/writes Firestore with that same user
   token so Firestore Security Rules apply.
4. Run a signed-in teacher test for Actual and Practice quizzes. Check that
   student requests are refused, 30/50-question quizzes complete in batches,
   a shortfall stays a draft, and the one-time **Generate more** action preserves
   manually added questions. Only then distribute a newly built APK.

The Flutter default endpoint is
`https://zuidphgogdwyrtndbgkx.supabase.co/functions/v1/generate-quiz`.
`QUIZ_GENERATION_URL` can override it for another environment. No Firebase
Blaze upgrade, Supabase Auth user migration, or Firebase service account is
required by this implementation.
