# Studexa Security Hardening Plan

## Current decision: classroom phone-to-phone demonstration

The current `Studexa.apk` is suitable for a classroom presentation or controlled beta demonstration without applying the hardening work in this document first.

That means a presenter can share the APK directly to another Android phone, install it, sign in with demonstration accounts, and demonstrate the current Teacher and Student flows. The APK targets Android API 36 and requires Android API 24 or newer. An internet connection is required because authentication, Postgres, Storage, Realtime, and Edge Functions are hosted in Supabase.

This is a controlled demonstration decision, not a production-security approval. For the demo:

- Use test accounts and non-sensitive study materials.
- Do not paste a Teacher's personal Gemini key into a phone that will be handed to another person.
- Share the APK through a trusted channel and verify its SHA-256 hash when practical.
- Treat the phone as a demonstration device until the session-storage, backup, signing, privacy, and backend verification work below is complete.

The APK audited on 2026-10-07/08 was:

- Path: `Studexa.apk`
- SHA-256: `8AC325B378EDBE2826CBAA137B309C383669919735AB7632D6A2DFEFB398A23A`
- Package: `com.example.studexa`
- Version: `0.1.0` (`versionCode 1`)
- Minimum SDK: 24
- Target SDK: 36
- Signature: Android debug certificate, APK Signature Scheme v2

## Why hardening is deferred for the demo

The static audit found no Critical or High vulnerability and found no Gemini key, Supabase service-role key, JWT signing secret, password, bearer token, Firebase service credential, or private application key in the APK. Supabase endpoints use HTTPS, only the Internet permission is requested, and the app's non-main exported providers and plugin components are permission-gated or not exported.

The audit did find release and defense-in-depth weaknesses. They matter before public production deployment, but they do not prevent a controlled phone-to-phone classroom demonstration.

## Findings and implementation status

| ID | Finding | Severity | Current state | Required future result |
|---|---|---:|---|---|
| SEC-001 | Release APK uses the Android debug signing certificate | Medium | Open | A dedicated release/upload key signs production artifacts and Play App Signing is configured |
| SEC-002 | Supabase session storage appears to use ordinary `SharedPreferences` | Medium | Open | Access/refresh sessions use Android Keystore-backed storage |
| SEC-003 | Backup policy is implicit and session preferences are not excluded | Medium | Open | Backup rules explicitly exclude session credentials or backups are disabled where appropriate |
| SEC-004 | Privacy policy and account-deletion path are not evidenced in the APK | Medium compliance risk | Open | In-app policy link, public deletion route, and tested account/data deletion exist |
| SEC-005 | Dart source paths and private names remain readable in the AOT binary | Low | Open | Release build uses Dart obfuscation and private split debug information |
| SEC-006 | Custom authentication callback scheme has `autoVerify=false` | Low | Open | Verified HTTPS App Links or equivalent callback protection is used, with PKCE/state checks retained |
| SEC-007 | No root detection or Play Integrity enforcement | Informational | Deferred | Add device/app-integrity enforcement only if the threat model requires it |
| SEC-008 | No application anti-tampering or signature validation | Informational | Deferred | Sensitive operations can reject untrusted app/device states where required |
| SEC-009 | No certificate/public-key pinning | Informational | Deferred | Add pinning only after deciding that the operational cost is justified |
| SEC-010 | Release error messages and stack traces may be logged | Informational | Open | Production logs redact IDs, paths, server details, and exception data |
| SEC-011 | No biometric protection | Informational | Optional | Add biometric protection only for a defined sensitive action |
| SEC-012 | Supabase RLS, Edge Function authorization, Vault isolation, and rate limits cannot be proven from an APK | Verification gap | Open | Complete linked backend policy and live authorization tests |

## Phase 1 — release identity and artifact protection

### 1. Create a production signing identity

The audited certificate is:

```text
C=US, O=Android, CN=Android Debug
SHA-256: DD:64:97:FC:D8:59:D1:E1:5D:67:35:39:78:FC:1D:C5:D5:12:99:BC:0C:18:3C:AA:27:7F:F2:D6:17:1D:1E:5A
```

Future work:

1. Create a dedicated upload/release keystore outside the repository.
2. Store its passwords in a local secret mechanism or CI secret store.
3. Add a release signing configuration to `android/app/build.gradle.kts`.
4. Keep `key.properties` and keystore files ignored by Git.
5. Choose a permanent application ID before publishing. `com.example.studexa` is still a template-style ID and is tied to the current Google OAuth callback configuration.
6. Register the release and Play App Signing certificate fingerprints with the Google OAuth/Supabase provider configuration.
7. Build an Android App Bundle for Google Play and a signed APK only when direct distribution requires one.

Verification:

```powershell
flutter build appbundle --release --dart-define-from-file=supabase.config.json
flutter build apk --release --dart-define-from-file=supabase.config.json
C:\Android\Sdk\build-tools\37.0.0\apksigner.bat verify --verbose --print-certs build\app\outputs\flutter-apk\app-release.apk
```

Acceptance criteria:

- The certificate no longer says `Android Debug`.
- The production signing private key is not in Git or the APK.
- The package ID, OAuth callback, and Supabase redirect configuration agree.
- Every update increments `versionCode`.

### 2. Enable Dart release obfuscation

The APK contains readable strings such as `package:studexa/services/auth_service.dart`, `TeacherGeminiKeyService`, and `_AnswerQuizScreenState`. The binary is still a Flutter AOT release, but Dart obfuscation was not evidenced.

Future build:

```powershell
flutter build appbundle --release `
  --dart-define-from-file=supabase.config.json `
  --obfuscate `
  --split-debug-info=build\symbols
```

Keep `build\symbols` private and back it up securely for crash-symbolication. Do not ship it in the APK, repository, or public artifact folder.

Verification:

- Inspect `lib/*/libapp.so` for the disappearance or substantial reduction of application package paths and private Dart identifiers.
- Confirm the app still launches and all release tests pass.
- Confirm the symbol directory is not tracked or included in the APK.

## Phase 2 — session storage and Android backup

### 3. Replace ordinary session persistence

The APK contains `SharedPreferencesLocalStorage` and `SharedPreferencesGotrueAsyncStorage` strings and no evidence of `AndroidKeyStore`, `EncryptedSharedPreferences`, or `flutter_secure_storage`.

Future implementation:

1. Configure Supabase Auth with an Android Keystore-backed local-storage implementation.
2. Store access and refresh session data only through that implementation.
3. Keep PKCE verifier storage protected as well.
4. Ensure logout removes all persisted session material.
5. Do not place Teacher Gemini keys in local preferences; they remain backend/Vault data.

Verification:

- Sign in, restart the app, and confirm session restoration still works.
- Sign out, restart the app, and confirm no session returns.
- Inspect the app data on a test device and confirm the session is not readable plaintext in ordinary preference files.
- Confirm no complete credential appears in logs, crash reports, analytics, or error messages.

### 4. Define backup and restore behavior

The manifest contains no explicit `android:allowBackup`, `android:fullBackupContent`, or `android:dataExtractionRules`. Android Auto Backup therefore needs an explicit policy for an app that persists authentication sessions.

Future implementation:

1. Add Android 12+ `dataExtractionRules`.
2. Add legacy `fullBackupContent` rules for Android 11 and earlier.
3. Exclude all Supabase session files/preferences and any sensitive temporary credential data.
4. Decide whether device-to-device transfer should be disabled for session data.
5. Set `android:allowBackup` explicitly when the policy decision is made.

Verification:

- Test cloud backup and device-to-device transfer on supported Android versions.
- Restore onto a clean test phone and confirm that a restored app cannot silently reuse the previous signed-in session unless that behavior is deliberately approved.
- Confirm temporary material cache files are not treated as durable backup data.

## Phase 3 — privacy, account deletion, and data handling

### 5. Add an in-app privacy policy and account deletion flow

The APK contains no clear in-app privacy-policy URL, terms link, or account-deletion action. This is a production/store compliance gap; an external webpage cannot be verified from the APK alone.

Future implementation:

1. Add a visible Privacy Policy link in authentication or account settings.
2. Add a public HTTPS privacy-policy page naming Studexa and the responsible contact.
3. Add an accessible Delete Account action for both Teacher and Student accounts.
4. Explain what happens to classes, memberships, materials, quizzes, attempts, drafts, Gemini credential mappings, and Storage objects.
5. Implement deletion through an authenticated Edge Function or server transaction rather than client-only row deletes.
6. Keep a documented retention/legal-hold policy for records that cannot be immediately deleted.
7. Complete the Play Console Data Safety and account-deletion declarations before store release.

Verification:

- Create disposable Teacher and Student accounts.
- Delete each account through the app.
- Confirm Auth, profile, application rows, Storage objects, personal Gemini mappings, and related records are removed or handled according to the documented retention rule.
- Confirm the public deletion URL works without an installed app.

### 6. Keep data boundaries explicit

The APK correctly exposes only public configuration:

- Supabase project URL: `https://zuidphgogdwyrtndbgkx.supabase.co`
- Supabase publishable key: `sb_publishable_KHO1****tu0a`
- Google OAuth client ID: public client identifier, not a client secret

These values may remain client-visible. The following must never enter the APK:

- Supabase service-role or secret keys
- Gemini API keys
- Vault secrets
- OAuth client secrets
- Database passwords
- JWT signing secrets
- Recovery or administrative credentials

Verification:

```powershell
rg -n -i "sb_secret|service_role|GEMINI_API_KEY|private key|BEGIN RSA|BEGIN EC|bearer" lib android supabase
```

Also scan the final APK's `classes.dex`, `lib/*/libapp.so`, resources, and assets without printing complete candidate values.

## Phase 4 — authentication callback and platform hardening

### 7. Harden the authentication callback

The current callback is:

```text
com.example.studexa://login-callback
```

with `autoVerify=false`. The APK contains Supabase PKCE-related code, which is a useful protection, but custom schemes can collide with another installed application.

Future implementation:

1. Prefer a verified HTTPS Android App Link backed by `assetlinks.json`.
2. Keep PKCE and state validation enabled.
3. Reject callbacks with an unexpected host, path, state, or code verifier.
4. Do not treat arbitrary deep-link parameters as an authenticated user or role.
5. Update Google OAuth, Supabase redirect URLs, and the Android package ID together.

Verification:

- Test a valid callback.
- Test an incorrect state, host, path, and verifier.
- Test a competing callback handler and confirm no session is accepted without successful validation.

### 8. Decide on device and app integrity controls

No root detection, Magisk detection, debugger detection, APK signature validation, Play Integrity, or anti-hooking control was found.

These are defense-in-depth controls, not requirements for the classroom demo. If institutional data or teacher credentials require them:

1. Use Play Integrity for server-approved high-risk actions.
2. Perform enforcement on the backend, not only in Dart code.
3. Treat root detection as an additional signal, not the sole security boundary.
4. Decide whether a failed integrity check blocks quiz generation, key management, or account changes.

Verification:

- Test approved and failed integrity verdicts against a staging backend.
- Confirm a modified/repackaged client cannot bypass server-side role, ownership, or credential checks.

### 9. Review certificate validation and pinning

The APK uses HTTPS but contains no custom certificate pinning. There is also no evidence of a trust-all certificate callback.

Future decision:

- Keep platform TLS validation if the threat model does not require pinning.
- Add carefully rotated public-key pins only if the project accepts the operational risk of certificate rotation and emergency recovery.

Verification:

- Test invalid certificates and hostname mismatches in a staging environment.
- Confirm requests fail safely and no trust-all callback is present.

## Phase 5 — logging and dependency review

### 10. Redact release logs

The APK retains error strings for Google sign-in, Postgres, Storage, uploads, PDF extraction, quiz generation, and local-file cleanup. No literal token or password was found, but interpolated exceptions and stack traces can reveal operational data.

Future implementation:

1. Remove or gate verbose stack traces in release builds.
2. Redact user IDs, material IDs, Storage paths, URLs containing query data, and server error bodies.
3. Never log Authorization headers, access tokens, refresh tokens, API keys, or passwords.
4. Use a controlled crash-reporting path only after its privacy and retention settings are reviewed.

Verification:

```powershell
adb logcat -c
adb logcat | Select-String -Pattern "token|authorization|bearer|api.?key|password|secret"
```

Run authenticated sign-in, upload, generation, and logout flows while reviewing logs.

### 11. Review dependencies before production

The APK exposes Flutter, Supabase, Google Play Services Auth, AndroidX, Syncfusion PDF, printing, file picker, URL launcher, `open_filex`, DataStore, and SharedPreferences components. Exact versions for some Dart packages cannot be reliably reconstructed from the APK alone.

Future implementation:

1. Review `pubspec.lock` and Gradle dependency versions.
2. Check current security advisories for every shipped package.
3. Remove unused plugins and permissions.
4. Rebuild and repeat the APK inventory after dependency updates.
5. Record the final dependency versions in the release evidence.

No dependency should be labeled vulnerable solely because it is present; a current advisory or reproducible issue is required.

## Phase 6 — backend verification that an APK cannot prove

The APK exposes the Supabase public boundary, but it cannot prove that the backend is secure. Before production deployment, re-run linked tests for:

- Anonymous requests to every Edge Function.
- Student, Teacher-owner, unrelated Teacher, and service-role access.
- Supabase Auth role immutability and role mismatch handling.
- Class ownership and join-code authorization.
- Private Storage upload/download/delete policies.
- Material post/unpost visibility.
- Quiz generation ownership and Student denial.
- Teacher Gemini Vault isolation, key masking, allowance reservations, and fallback limits.
- Attempt scoring, deadlines, idempotency, and two-attempt limits.
- Account deletion and cleanup of all related data.

The backend must reject unauthorized calls even when a caller replaces the Flutter APK with a custom client. Client-side role checks are never sufficient.

## Production acceptance gate

Do not label a build production-ready until all of the following are true:

- [ ] Release/upload signing replaces the Android debug certificate.
- [ ] Permanent application ID and OAuth callback are finalized.
- [ ] A signed AAB is built and verified.
- [ ] Dart obfuscation and private split debug information are enabled.
- [ ] Supabase sessions use secure Keystore-backed storage.
- [ ] Backup and restore rules exclude session credentials.
- [ ] Privacy policy is accessible in-app and on a public HTTPS URL.
- [ ] Account deletion is accessible and verified end to end.
- [ ] No confidential key or token appears in the APK, logs, or crash reports.
- [ ] Deep-link PKCE/state and callback validation tests pass.
- [ ] Release logs are redacted.
- [ ] Dependency advisory review is current.
- [ ] Linked Supabase RLS and Edge Function tests pass.
- [ ] A signed-in physical Android smoke test passes with clean demo accounts.
- [ ] Data Safety and store declarations match actual behavior.

## Verification commands and evidence to retain

```powershell
flutter analyze
flutter test
flutter build appbundle --release --dart-define-from-file=supabase.config.json --obfuscate --split-debug-info=build\symbols
C:\Android\Sdk\build-tools\37.0.0\apksigner.bat verify --verbose --print-certs app-release.apk
C:\Android\Sdk\build-tools\37.0.0\aapt.exe dump badging app-release.apk
C:\Android\Sdk\build-tools\37.0.0\aapt.exe dump xmltree app-release.apk AndroidManifest.xml
```

Keep the following with each release review:

- APK/AAB SHA-256 hashes
- signing certificate fingerprints
- package/version metadata
- permissions and exported-component inventory
- dependency/advisory review
- Flutter and Edge Function test results
- linked RLS test results
- backup/restore results
- account-deletion evidence
- physical-device smoke-test result

This document is a future implementation plan. It does not change the current app flow, security configuration, signing configuration, backend, or APK.
