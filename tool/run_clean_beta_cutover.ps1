param(
  [switch]$Execute
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$archivePath = 'C:\Users\FLYNNE EJ\Studexa_Recovery\20260927-073500.studexa-recovery.enc'
$archiveKeyPath = 'C:\Users\FLYNNE EJ\Studexa_Recovery\20260927-073500.key.dpapi'
$expectedArchiveHash = '626459F65C6F5953E3F6127E9DC570EF19BEF88A71773B2933260D22E3A15D7E'
$expectedFirebaseUsers = 10
$expectedFirestoreDocuments = 67
$expectedFirebaseStorageObjects = 3
$resetMigration = '202609270001_clean_beta_reset_reapply.sql'

function Invoke-CheckedNative {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][scriptblock]$Command
  )
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = (& $Command 2>&1 | Out-String).Trim()
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    throw "$Label failed.`n$output"
  }
  return $output
}

function Get-SupabaseSnapshot {
  $temporaryExport = Join-Path $env:TEMP (
    'studexa-cutover-snapshot-' + [guid]::NewGuid().ToString('N') + '.json'
  )
  try {
    $null = Invoke-CheckedNative 'Supabase read-only recovery snapshot' {
      node tool/export_linked_supabase_database.mjs $temporaryExport
    }
    $database = Get-Content -LiteralPath $temporaryExport -Raw | ConvertFrom-Json
    $tables = $database.tables
    $studyMaterialObjects = @(
      $tables.'storage.objects'.rows |
        Where-Object { $_.bucket_id -eq 'study-materials' }
    ).Count
    return [ordered]@{
      authUsers = [int]$tables.'auth.users'.rowCount
      profiles = [int]$tables.'public.profiles'.rowCount
      classes = [int]$tables.'public.classes'.rowCount
      classMembers = [int]$tables.'public.class_members'.rowCount
      materials = [int]$tables.'public.materials'.rowCount
      quizzes = [int]$tables.'public.quizzes'.rowCount
      assignments = [int]$tables.'public.quiz_assignments'.rowCount
      attempts = [int]$tables.'public.quiz_attempts'.rowCount
      drafts = [int]$tables.'public.quiz_drafts'.rowCount
      credentialMappings = [int]$tables.'private.teacher_gemini_credentials'.rowCount
      backupSessions = [int]$tables.'private.teacher_gemini_backup_sessions'.rowCount
      storageObjects = [int]$studyMaterialObjects
    }
  } finally {
    if (Test-Path -LiteralPath $temporaryExport) {
      [System.IO.File]::Delete($temporaryExport)
    }
  }
}

function Invoke-SupabaseStorageCleanup {
  param([switch]$ExecuteCleanup)

  $temporaryKeys = Join-Path $env:TEMP (
    'studexa-storage-keys-' + [guid]::NewGuid().ToString('N') + '.json'
  )
  $temporaryErrors = Join-Path $env:TEMP (
    'studexa-storage-keys-' + [guid]::NewGuid().ToString('N') + '.stderr'
  )
  try {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      & npx --yes supabase@2.102.0 projects api-keys `
        --project-ref zuidphgogdwyrtndbgkx --output json `
        2> $temporaryErrors | Set-Content -LiteralPath $temporaryKeys -Encoding UTF8
      $exitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
      $errorText = if (Test-Path -LiteralPath $temporaryErrors) {
        Get-Content -LiteralPath $temporaryErrors -Raw
      } else { '' }
      throw "Supabase temporary Storage credential request failed.`n$errorText"
    }

    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $keyAcl = Get-Acl -LiteralPath $temporaryKeys
    $keyAcl.SetAccessRuleProtection($true, $false)
    $keyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
      $currentIdentity,
      'FullControl',
      'Allow'
    )
    $keyAcl.SetAccessRule($keyRule)
    Set-Acl -LiteralPath $temporaryKeys -AclObject $keyAcl

    $resultText = if ($ExecuteCleanup) {
      Invoke-CheckedNative 'Supabase Storage API cleanup' {
        node tool/clean_supabase_storage.mjs `
          'https://zuidphgogdwyrtndbgkx.supabase.co' `
          'study-materials' $temporaryKeys --execute
      }
    } else {
      Invoke-CheckedNative 'Supabase Storage API inventory' {
        node tool/clean_supabase_storage.mjs `
          'https://zuidphgogdwyrtndbgkx.supabase.co' `
          'study-materials' $temporaryKeys
      }
    }
    return $resultText | ConvertFrom-Json
  } finally {
    foreach ($temporaryFile in @($temporaryKeys, $temporaryErrors)) {
      if (Test-Path -LiteralPath $temporaryFile) {
        [System.IO.File]::Delete($temporaryFile)
      }
    }
  }
}

Set-Location -LiteralPath $repoRoot
$env:NODE_OPTIONS = '--use-system-ca'

if (-not (Test-Path -LiteralPath $archivePath)) {
  throw "Encrypted recovery archive is missing: $archivePath"
}
if (-not (Test-Path -LiteralPath $archiveKeyPath)) {
  throw "DPAPI-protected archive key is missing: $archiveKeyPath"
}
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
if ($archiveHash -ne $expectedArchiveHash) {
  throw "Recovery archive hash mismatch. Expected $expectedArchiveHash but found $archiveHash."
}

$supabaseBefore = Get-SupabaseSnapshot
$expectedSupabase = [ordered]@{
  authUsers = 4
  profiles = 4
  classes = 2
  classMembers = 3
  materials = 1
  quizzes = 1
  assignments = 1
  attempts = 2
  drafts = 0
  credentialMappings = 0
  backupSessions = 1
  storageObjects = 12
}
foreach ($name in $expectedSupabase.Keys) {
  if ([int]$supabaseBefore[$name] -ne [int]$expectedSupabase[$name]) {
    throw "Supabase state changed after the recovery archive at $name. " +
      "Expected $($expectedSupabase[$name]) but found $($supabaseBefore[$name]). " +
      'Refresh the encrypted archive and cutover expectations before continuing.'
  }
}
$storageBefore = Invoke-SupabaseStorageCleanup
if ([int]$storageBefore.before -ne [int]$expectedSupabase.storageObjects) {
  throw "Supabase Storage API inventory does not match the encrypted snapshot. " +
    "Expected $($expectedSupabase.storageObjects) objects but found $($storageBefore.before)."
}

$firebaseInventoryText = Invoke-CheckedNative 'Firebase read-only inventory' {
  node tool/clean_legacy_firebase.js
}
$firebaseInventory = $firebaseInventoryText | ConvertFrom-Json
$before = $firebaseInventory.before
 $firebaseMatchesArchive = (
  $before.authUsers -ne $expectedFirebaseUsers -or
  $before.firestoreDocuments -ne $expectedFirestoreDocuments -or
  $before.storageObjects -ne $expectedFirebaseStorageObjects
) -eq $false
$firebaseAlreadyClean = (
  $before.authUsers -eq 0 -and
  $before.firestoreDocuments -eq 0 -and
  $before.storageObjects -eq 0
)
if (-not $firebaseMatchesArchive -and -not $firebaseAlreadyClean) {
  throw "Firebase state changed after the recovery archive. Refresh the archive before cutover. " +
    "Expected $expectedFirebaseUsers users, $expectedFirestoreDocuments documents, and " +
    "$expectedFirebaseStorageObjects objects; found $($before.authUsers), " +
    "$($before.firestoreDocuments), and $($before.storageObjects)."
}

$null = Invoke-CheckedNative 'Firebase deny-all rules dry run' {
  firebase deploy --only 'firestore:rules,storage' --project studexa-b5e55 --dry-run
}
$supabaseDryRun = Invoke-CheckedNative 'Supabase reset dry run' {
  npx --yes supabase@2.102.0 db push --linked --dry-run
}
$pendingMigrations = @(
  [regex]::Matches($supabaseDryRun, '\d{12,14}_[A-Za-z0-9_]+\.sql') |
    ForEach-Object { $_.Value } |
    Sort-Object -Unique
)
if ($pendingMigrations.Count -ne 1 -or $pendingMigrations[0] -ne $resetMigration) {
  throw "Unexpected pending Supabase migrations: $($pendingMigrations -join ', ')"
}

$preflight = [ordered]@{
  mode = if ($Execute) { 'execute' } else { 'dry-run' }
  archive = [ordered]@{
    path = $archivePath
    sha256 = $archiveHash
    keyPresent = $true
  }
  firebase = [ordered]@{
    authUsers = $before.authUsers
    firestoreDocuments = $before.firestoreDocuments
    storageObjects = $before.storageObjects
    alreadyClean = $firebaseAlreadyClean
    denyAllRulesCompiled = $true
  }
  supabase = [ordered]@{
    protectedSnapshot = $supabaseBefore
    storageApiInventory = $storageBefore
    pendingMigrations = $pendingMigrations
  }
}

if (-not $Execute) {
  $preflight | ConvertTo-Json -Depth 6
  exit 0
}

$null = Invoke-CheckedNative 'Firebase deny-all rules deployment' {
  firebase deploy --only 'firestore:rules,storage' --project studexa-b5e55
}

$firebaseCleanup = if ($firebaseAlreadyClean) {
  [ordered]@{ skipped = $true; reason = 'Firebase data already verified at zero.' }
} else {
  $firebaseCleanupText = Invoke-CheckedNative 'Firebase data cleanup' {
    node tool/clean_legacy_firebase.js --execute
  }
  $cleanup = $firebaseCleanupText | ConvertFrom-Json
  if (-not $cleanup.success) {
    throw "Firebase cleanup reported an incomplete result.`n$firebaseCleanupText"
  }
  $cleanup
}

$supabaseStorageCleanup = Invoke-SupabaseStorageCleanup -ExecuteCleanup
if (-not $supabaseStorageCleanup.success -or $supabaseStorageCleanup.after -ne 0) {
  throw 'Supabase Storage cleanup did not verify an empty study-materials bucket.'
}

$null = Invoke-CheckedNative 'Supabase clean beta reset' {
  npx --yes supabase@2.102.0 db push --linked --yes
}
$null = Invoke-CheckedNative 'Supabase production schema lint' {
  npx --yes supabase@2.102.0 db lint --linked --level error
}
$postResetDryRun = Invoke-CheckedNative 'Supabase post-reset migration audit' {
  npx --yes supabase@2.102.0 db push --linked --dry-run
}
if ([regex]::IsMatch($postResetDryRun, '\d{12,14}_[A-Za-z0-9_]+\.sql')) {
  throw "Supabase still reports a pending migration after reset.`n$postResetDryRun"
}
$supabaseAfter = Get-SupabaseSnapshot
foreach ($name in $supabaseAfter.Keys) {
  if ([int]$supabaseAfter[$name] -ne 0) {
    throw "Supabase zero-state audit failed at $name with $($supabaseAfter[$name]) remaining."
  }
}

$firebaseFinalText = Invoke-CheckedNative 'Firebase zero-state audit' {
  node tool/clean_legacy_firebase.js
}
$firebaseFinal = $firebaseFinalText | ConvertFrom-Json
if (
  $firebaseFinal.before.authUsers -ne 0 -or
  $firebaseFinal.before.firestoreDocuments -ne 0 -or
  $firebaseFinal.before.storageObjects -ne 0
) {
  throw "Firebase zero-state audit failed.`n$firebaseFinalText"
}

$retirement = @()
foreach ($entry in @(
  @{ Name = 'generateQuiz/generateQuizHttp'; Region = 'us-central1'; Functions = @('generateQuiz', 'generateQuizHttp') },
  @{ Name = 'extractText'; Region = 'us-east1'; Functions = @('extractText') }
)) {
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = (& firebase functions:delete @($entry.Functions) --region $entry.Region --project studexa-b5e55 --force 2>&1 | Out-String).Trim()
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  $retirement += [ordered]@{
    functions = $entry.Name
    region = $entry.Region
    deleted = ($exitCode -eq 0)
    result = $output
  }
}

[ordered]@{
  mode = 'execute'
  preflight = $preflight
  firebaseCleanup = $firebaseCleanup
  supabaseStorageCleanup = $supabaseStorageCleanup
  supabaseResetApplied = $true
  supabaseZeroState = $supabaseAfter
  firebaseFunctions = $retirement
} | ConvertTo-Json -Depth 8
