import { spawnSync } from 'node:child_process';
import { readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const sourcePath = resolve(
  process.argv[2] ?? 'supabase/tests/database_policy_test.sql',
);
const source = readFileSync(sourcePath, 'utf8');

if (!/^begin;/im.test(source) || !/^rollback;/im.test(source)) {
  throw new Error('Refusing to run a pgTAP file without BEGIN and ROLLBACK.');
}

let diagnosticSql = source.replace(
  'create extension if not exists pgtap with schema extensions;',
  `create extension if not exists pgtap with schema extensions;
create temporary table tap_results (
  line text not null
) on commit drop;
grant insert, select on pg_temp.tap_results to authenticated, service_role;`,
);

diagnosticSql = diagnosticSql.replace(
  /^select (is|lives_ok|throws_ok)\(/gm,
  'insert into pg_temp.tap_results(line) select $1(',
);

diagnosticSql = diagnosticSql.replace(
  /select \* from finish\(\);\s*rollback;/i,
  `insert into pg_temp.tap_results(line) select * from finish();
do $diagnostic$
declare
  diagnostic_text text;
begin
  select string_agg(line, E'\\n' order by ctid)
    into diagnostic_text
    from pg_temp.tap_results;
  raise exception using message = E'STUDEXA_PGTAP_RESULTS\\n' || diagnostic_text;
end
$diagnostic$;`,
);

const wrappedAssertions = (
  diagnosticSql.match(/insert into pg_temp\.tap_results\(line\) select/g) ?? []
).length;
if (wrappedAssertions < 2 || diagnosticSql.includes('\nrollback;')) {
  throw new Error('Could not prepare the rollback-only pgTAP diagnostic query.');
}

const diagnosticPath = join(
  tmpdir(),
  `studexa-pgtap-${process.pid}-${Date.now()}.sql`,
);
writeFileSync(diagnosticPath, diagnosticSql, 'utf8');

try {
  const windows = process.platform === 'win32';
  const command = windows ? 'powershell.exe' : 'npx';
  const commandArgs = windows
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
      ...commandArgs,
      '--yes',
      'supabase@2.102.0',
      'db',
      'query',
      '--linked',
      '--file',
      diagnosticPath,
      '--output',
      'json',
    ],
    {
      cwd: process.cwd(),
      env: {...process.env, NODE_OPTIONS: '--use-system-ca'},
      encoding: 'utf8',
    },
  );

  // The diagnostic query deliberately raises an exception so the linked
  // transaction cannot persist test fixtures. The caller inspects its TAP
  // output rather than treating the expected non-zero status as test failure.
  const combined = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  if (!combined.includes('STUDEXA_PGTAP_RESULTS')) {
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    throw new Error(`Linked pgTAP query failed before reporting results.`);
  }

  const jsonMatch = result.stderr?.match(/unexpected status 400: (\{.*\})/);
  let message = combined;
  if (jsonMatch) {
    try {
      message = JSON.parse(jsonMatch[1]).message ?? message;
    } catch {
      // Fall back to the complete CLI output if its error envelope changes.
    }
  }
  const tapOutput = message
    .split('STUDEXA_PGTAP_RESULTS\n', 2)[1]
    ?.split('\nCONTEXT:', 1)[0]
    ?.trim();
  if (!tapOutput) {
    throw new Error('Linked pgTAP query returned an unreadable result envelope.');
  }

  process.stdout.write(`${tapOutput}\n`);
  const failed = /(?:^|\n)not ok \d+/i.test(tapOutput);
  if (!failed) {
    const planned = source.match(/select plan\((\d+)\)/i)?.[1] ?? 'all';
    process.stdout.write(`All ${planned} linked pgTAP tests passed.\n`);
  }
  process.exitCode = failed ? 1 : 0;
} finally {
  rmSync(diagnosticPath, {force: true});
}
