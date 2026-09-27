#!/usr/bin/env node

import {spawnSync} from 'node:child_process';
import {readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve, join} from 'node:path';

const outputArg = process.argv[2];
if (!outputArg) {
  console.error(
    'Usage: node tool/export_linked_supabase_database.mjs <private-output-json>',
  );
  process.exit(2);
}

const outputPath = resolve(outputArg);
const sqlPath = join(
  tmpdir(),
  `studexa-linked-export-${process.pid}-${Date.now()}.sql`,
);

const sql = String.raw`
create or replace function pg_temp.studexa_recovery_export()
returns jsonb
language plpgsql
set search_path = ''
as $export$
declare
  table_record record;
  table_key text;
  table_rows jsonb;
  table_count bigint;
  tables jsonb := '{}'::jsonb;
  total_rows bigint := 0;
  table_total integer := 0;
begin
  for table_record in
    select table_schema, table_name
    from information_schema.tables
    where table_type = 'BASE TABLE'
      and table_schema = any(array['public', 'private', 'auth', 'storage', 'vault'])
    order by table_schema, table_name
  loop
    execute format(
      'select count(*)::bigint, coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from %I.%I t',
      table_record.table_schema,
      table_record.table_name
    ) into table_count, table_rows;
    table_key := table_record.table_schema || '.' || table_record.table_name;
    tables := tables || jsonb_build_object(
      table_key,
      jsonb_build_object('rowCount', table_count, 'rows', table_rows)
    );
    total_rows := total_rows + table_count;
    table_total := table_total + 1;
  end loop;

  return jsonb_build_object(
    'exportedAt', clock_timestamp(),
    'schemas', array['public', 'private', 'auth', 'storage', 'vault'],
    'tableCount', table_total,
    'totalRows', total_rows,
    'note', 'Vault base-table values remain encrypted; decrypted_secrets was not queried.',
    'tables', tables
  );
end
$export$;

select pg_temp.studexa_recovery_export() as database_export;
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
      maxBuffer: 256 * 1024 * 1024,
    },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `Supabase linked export failed: ${(result.stderr || result.stdout || '').trim()}`,
    );
  }

  const envelope = extractJson(result.stdout);
  const databaseExport = envelope.rows?.[0]?.database_export;
  if (!databaseExport || typeof databaseExport !== 'object') {
    throw new Error('Supabase linked export did not contain database_export.');
  }
  writeFileSync(outputPath, JSON.stringify(databaseExport, null, 2), {
    encoding: 'utf8',
    mode: 0o600,
  });
  console.log(
    JSON.stringify({
      output: outputPath,
      tableCount: databaseExport.tableCount,
      totalRows: databaseExport.totalRows,
      vaultDecrypted: false,
    }),
  );
} finally {
  rmSync(sqlPath, {force: true});
}
