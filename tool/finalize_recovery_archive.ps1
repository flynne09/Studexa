param(
  [Parameter(Mandatory = $true)]
  [string]$RecoveryDirectory
)

$ErrorActionPreference = 'Stop'
$recovery = (Resolve-Path -LiteralPath $RecoveryDirectory).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$required = @(
  'firebase-auth-users.json',
  'firestore-documents.json',
  'firebase-storage-manifest.json',
  'supabase-auth-users.json',
  'supabase-database-data.json',
  'supabase-storage-manifest.json'
)
foreach ($name in $required) {
  if (-not (Test-Path -LiteralPath (Join-Path $recovery $name))) {
    throw "Recovery export is incomplete: missing $name"
  }
}

$temporaryNames = @(
  'temporary-firebase-adc.json',
  'temporary-supabase-api-keys.json',
  'temporary-db-dump-debug.log',
  'temporary-database-url.txt',
  'supabase-database-data.sql'
)
foreach ($name in $temporaryNames) {
  $candidate = Join-Path $recovery $name
  if (Test-Path -LiteralPath $candidate) {
    [System.IO.File]::Delete((Resolve-Path -LiteralPath $candidate).Path)
  }
}

$firebaseAuth = Get-Content -LiteralPath (Join-Path $recovery 'firebase-auth-users.json') -Raw | ConvertFrom-Json
$firestore = Get-Content -LiteralPath (Join-Path $recovery 'firestore-documents.json') -Raw | ConvertFrom-Json
$firebaseStorage = Get-Content -LiteralPath (Join-Path $recovery 'firebase-storage-manifest.json') -Raw | ConvertFrom-Json
$supabaseAuth = Get-Content -LiteralPath (Join-Path $recovery 'supabase-auth-users.json') -Raw | ConvertFrom-Json
$supabaseDatabase = Get-Content -LiteralPath (Join-Path $recovery 'supabase-database-data.json') -Raw | ConvertFrom-Json
$supabaseStorage = Get-Content -LiteralPath (Join-Path $recovery 'supabase-storage-manifest.json') -Raw | ConvertFrom-Json

$archiveNotes = @(
  'Vault data was exported only from encrypted base tables; vault.decrypted_secrets was never queried.',
  'Temporary CLI credentials and API-key files are excluded from this archive.'
)
if ([int]$firebaseStorage.unresolved.Count -gt 0) {
  $archiveNotes += 'Some Firebase Storage objects were unavailable; see firebase-storage-manifest.json for non-secret failure details.'
}

$summary = [ordered]@{
  createdAt = (Get-Date).ToUniversalTime().ToString('o')
  recoveryOnly = $true
  firebaseAuthUsers = [int]($firebaseAuth.users.Count)
  firestoreDocuments = [int]$firestore.documentCount
  firebaseStorageObjects = [int]$firebaseStorage.objectCount
  unresolvedFirebaseStorageObjects = [int]$firebaseStorage.unresolved.Count
  supabaseAuthUsers = [int]$supabaseAuth.userCount
  supabaseDatabaseTables = [int]$supabaseDatabase.tableCount
  supabaseDatabaseRows = [int]$supabaseDatabase.totalRows
  supabaseStorageObjects = [int]$supabaseStorage.objectCount
  notes = $archiveNotes
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$summaryPath = Join-Path $recovery 'recovery-summary.json'
[System.IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 8), $utf8)

$readme = @"
Studexa recovery archive

This is a private recovery-only snapshot created before the clean Supabase beta cutover.
It is not an active data migration and must never be committed to Git.

The encrypted archive uses AES-256-GCM. Its random key is stored separately in the
.key.dpapi file and can be unprotected only by the same Windows user account on this
computer. Keep both files together. The file-checksums.sha256.json inside the archive
can be used to verify every exported file after recovery.

Firebase Storage recovery: $($summary.firebaseStorageObjects) object(s) archived and
$($summary.unresolvedFirebaseStorageObjects) unresolved. Any unresolved object paths
and non-secret failure reasons are recorded in firebase-storage-manifest.json.
"@
[System.IO.File]::WriteAllText((Join-Path $recovery 'RECOVERY_README.txt'), $readme, $utf8)

$checksumRows = @()
$recoveryUri = New-Object System.Uri(($recovery.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar))
Get-ChildItem -LiteralPath $recovery -Recurse -File |
  Where-Object { $_.Name -ne 'file-checksums.sha256.json' } |
  Sort-Object FullName |
  ForEach-Object {
    $checksumRows += [ordered]@{
      path = [System.Uri]::UnescapeDataString($recoveryUri.MakeRelativeUri((New-Object System.Uri($_.FullName))).ToString())
      bytes = $_.Length
      sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
  }
[System.IO.File]::WriteAllText(
  (Join-Path $recovery 'file-checksums.sha256.json'),
  ($checksumRows | ConvertTo-Json -Depth 5),
  $utf8
)

$parent = Split-Path -Parent $recovery
$baseName = Split-Path -Leaf $recovery
$zipPath = Join-Path $parent "$baseName.zip"
$encryptedPath = Join-Path $parent "$baseName.studexa-recovery.enc"
$candidateEncryptedPath = Join-Path $parent "$baseName.candidate.studexa-recovery.enc"
$rawKeyPath = Join-Path $parent "$baseName.raw-key.tmp"
$protectedKeyPath = Join-Path $parent "$baseName.key.dpapi"
$candidateProtectedKeyPath = Join-Path $parent "$baseName.candidate.key.dpapi"
$verificationZip = Join-Path $parent "$baseName.verify.tmp.zip"
$verificationKey = Join-Path $parent "$baseName.verify-key.tmp"

foreach ($file in @($zipPath, $candidateEncryptedPath, $rawKeyPath, $candidateProtectedKeyPath, $verificationZip, $verificationKey)) {
  if (Test-Path -LiteralPath $file) { [System.IO.File]::Delete($file) }
}
Compress-Archive -Path (Join-Path $recovery '*') -DestinationPath $zipPath -CompressionLevel Optimal
node (Join-Path $repoRoot 'tool/recovery_archive_crypto.js') encrypt $zipPath $candidateEncryptedPath $rawKeyPath
if ($LASTEXITCODE -ne 0) { throw 'Recovery encryption failed.' }

Add-Type -AssemblyName System.Security
$protected = [System.Security.Cryptography.ProtectedData]::Protect(
  [System.IO.File]::ReadAllBytes($rawKeyPath),
  $null,
  [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)
[System.IO.File]::WriteAllBytes($candidateProtectedKeyPath, $protected)
[System.IO.File]::Delete($rawKeyPath)

$unprotected = [System.Security.Cryptography.ProtectedData]::Unprotect(
  [System.IO.File]::ReadAllBytes($candidateProtectedKeyPath),
  $null,
  [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)
[System.IO.File]::WriteAllBytes($verificationKey, $unprotected)
node (Join-Path $repoRoot 'tool/recovery_archive_crypto.js') decrypt $candidateEncryptedPath $verificationZip $verificationKey
if ($LASTEXITCODE -ne 0) { throw 'Recovery decryption verification failed.' }
$originalHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$verifiedHash = (Get-FileHash -LiteralPath $verificationZip -Algorithm SHA256).Hash
[System.IO.File]::Delete($verificationKey)
[System.IO.File]::Delete($verificationZip)
[System.IO.File]::Delete($zipPath)
if ($originalHash -ne $verifiedHash) { throw 'Recovery archive verification hash did not match.' }

$previousArchive = if (Test-Path -LiteralPath $encryptedPath) {
  [System.IO.File]::ReadAllBytes($encryptedPath)
} else { $null }
$previousProtectedKey = if (Test-Path -LiteralPath $protectedKeyPath) {
  [System.IO.File]::ReadAllBytes($protectedKeyPath)
} else { $null }
try {
  [System.IO.File]::WriteAllBytes(
    $encryptedPath,
    [System.IO.File]::ReadAllBytes($candidateEncryptedPath)
  )
  [System.IO.File]::WriteAllBytes(
    $protectedKeyPath,
    [System.IO.File]::ReadAllBytes($candidateProtectedKeyPath)
  )
  if (
    (Get-FileHash -LiteralPath $encryptedPath -Algorithm SHA256).Hash -ne
      (Get-FileHash -LiteralPath $candidateEncryptedPath -Algorithm SHA256).Hash
  ) {
    throw 'Committed recovery archive does not match the verified candidate.'
  }
  if (
    (Get-FileHash -LiteralPath $protectedKeyPath -Algorithm SHA256).Hash -ne
      (Get-FileHash -LiteralPath $candidateProtectedKeyPath -Algorithm SHA256).Hash
  ) {
    throw 'Committed recovery key does not match the verified candidate.'
  }
} catch {
  if ($null -ne $previousArchive) {
    [System.IO.File]::WriteAllBytes($encryptedPath, $previousArchive)
  } elseif (Test-Path -LiteralPath $encryptedPath) {
    [System.IO.File]::Delete($encryptedPath)
  }
  if ($null -ne $previousProtectedKey) {
    [System.IO.File]::WriteAllBytes($protectedKeyPath, $previousProtectedKey)
  } elseif (Test-Path -LiteralPath $protectedKeyPath) {
    [System.IO.File]::Delete($protectedKeyPath)
  }
  throw
} finally {
  if (Test-Path -LiteralPath $candidateEncryptedPath) {
    [System.IO.File]::Delete($candidateEncryptedPath)
  }
  if (Test-Path -LiteralPath $candidateProtectedKeyPath) {
    [System.IO.File]::Delete($candidateProtectedKeyPath)
  }
}

$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
foreach ($privateArtifact in @($encryptedPath, $protectedKeyPath)) {
  $artifactAcl = Get-Acl -LiteralPath $privateArtifact
  $artifactAcl.SetAccessRuleProtection($true, $false)
  $artifactRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $currentIdentity,
    'FullControl',
    'Allow'
  )
  $artifactAcl.SetAccessRule($artifactRule)
  Set-Acl -LiteralPath $privateArtifact -AclObject $artifactAcl
}

[pscustomobject]@{
  encryptedArchive = $encryptedPath
  protectedKey = $protectedKeyPath
  encryptedBytes = (Get-Item -LiteralPath $encryptedPath).Length
  encryptedSha256 = (Get-FileHash -LiteralPath $encryptedPath -Algorithm SHA256).Hash
  archivedFiles = $checksumRows.Count + 1
  roundTripVerified = $true
} | ConvertTo-Json
