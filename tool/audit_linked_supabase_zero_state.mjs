#!/usr/bin/env node

import {spawnSync} from 'node:child_process';
import {rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

function expectedCount(argument, fallback = 0) {
  const prefix = `--expected-${argument}=`;
  const raw = process.argv.find((value) => value.startsWith(prefix))?.slice(
    prefix.length,
  );
  if (raw === undefined) return fallback;
  const parsed = Number(raw);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error(`Invalid expected count for ${argument}.`);
  }
  return parsed;
}

const expected = {
  authUsers: expectedCount('auth-users'),
  profiles: expectedCount('profiles'),
  classes: 0,
  classMembers: 0,
  materials: 0,
  quizzes: 0,
  assignments: 0,
  attempts: 0,
  drafts: 0,
  credentialMappings: 0,
  backupSessions: 0,
  studyMaterialObjects: 0,
};

const sqlPath = join(
  tmpdir(),
  `studexa-zero-state-${process.pid}-${Date.now()}.sql`,
);

const sql = String.raw`
select jsonb_build_object(
  'authUsers', (select count(*) from auth.users),
  'profiles', (select count(*) from public.profiles),
  'classes', (select count(*) from public.classes),
  'classMembers', (select count(*) from public.class_members),
  'materials', (select count(*) from public.materials),
  'quizzes', (select count(*) from public.quizzes),
  'assignments', (select count(*) from public.quiz_assignments),
  'attempts', (select count(*) from public.quiz_attempts),
  'drafts', (select count(*) from public.quiz_drafts),
  'credentialMappings', (
    select count(*) from private.teacher_gemini_credentials
  ),
  'backupSessions', (
    select count(*) from private.teacher_gemini_backup_sessions
  ),
  'studyMaterialObjects', (
    select count(*) from storage.objects where bucket_id = 'study-materials'
  )
) as zero_state;
`;

function extractJson(text) {
  const start = text.indexOf('{');
  if (start < 0) throw new Error('Supabase CLI did not return a JSON envelope.');
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = start; index < text.length; index++) {
    const character = text[index];
    if (inString) {
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === '"') inString = false;
      continue;
    }
    if (character === '"') inString = true;
    else if (character === '{') depth++;
    else if (character === '}' && --depth === 0) {
      return JSON.parse(text.slice(start, index + 1));
    }
  }
  throw new Error('Supabase CLI returned an incomplete JSON envelope.');
}

writeFileSync(sqlPath, sql, {encoding: 'utf8', mode: 0o600});
try {
  const windows = process.platform === 'win32';
  const command = windows ? 'powershell.exe' : 'npx';
  const prefix = windows
    ? [
        '-NoProfile',
        '-NonInteractive',
        '-File',
        'C:\\Program Files\\nodejs\\npx.ps1',
      ]
    : [];
  const result = spawnSync(
    command,
    [
      ...prefix,
      '--yes',
      'supabase@2.102.0',
      'db',
      'query',
      '--linked',
      '--file',
      sqlPath,
      '--output',
      'json',
    ],
    {
      cwd: process.cwd(),
      env: {...process.env, NODE_OPTIONS: '--use-system-ca'},
      encoding: 'utf8',
      maxBuffer: 1024 * 1024,
    },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `Supabase zero-state audit failed: ${(
        result.stderr || result.stdout || ''
      ).trim()}`,
    );
  }

  const envelope = extractJson(result.stdout);
  const zeroState = envelope.rows?.[0]?.zero_state;
  if (!zeroState || typeof zeroState !== 'object') {
    throw new Error('Supabase audit did not contain zero_state.');
  }

  const mismatches = Object.entries(expected).filter(
    ([key, value]) => Number(zeroState[key]) !== value,
  );
  console.log(JSON.stringify({
    zeroState,
    expected,
    success: mismatches.length === 0,
  }, null, 2));
  if (mismatches.length > 0) process.exitCode = 1;
} finally {
  rmSync(sqlPath, {force: true});
}
