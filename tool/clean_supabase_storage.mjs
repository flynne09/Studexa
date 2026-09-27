#!/usr/bin/env node

import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';

const [projectUrl, bucket, keyFile, mode] = process.argv.slice(2);
const execute = mode === '--execute';
if (!projectUrl || !bucket || !keyFile || (mode && !execute)) {
  console.error(
    'Usage: node tool/clean_supabase_storage.mjs <project-url> <bucket> <private-key-json> [--execute]',
  );
  process.exit(2);
}
if (bucket !== 'study-materials') {
  throw new Error('Refusing to operate on any bucket except study-materials.');
}

const records = JSON.parse(
  readFileSync(resolve(keyFile), 'utf8').replace(/^\uFEFF/, ''),
);
const serverKey =
  records.find((item) => item.name === 'service_role')?.api_key ??
  records.find((item) => item.type === 'secret')?.api_key;
if (!serverKey) throw new Error('No Supabase server key was available.');
const headers = {apikey: serverKey, Authorization: `Bearer ${serverKey}`};

async function checked(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: {
      ...headers,
      ...(init.body ? {'Content-Type': 'application/json'} : {}),
      ...(init.headers ?? {}),
    },
    signal: AbortSignal.timeout(60000),
  });
  if (!response.ok) {
    throw new Error(`Supabase Storage request failed (${response.status}).`);
  }
  return response;
}

async function listFolder(prefix, output = []) {
  for (let offset = 0; ; offset += 1000) {
    const response = await checked(
      `${projectUrl}/storage/v1/object/list/${encodeURIComponent(bucket)}`,
      {
        method: 'POST',
        body: JSON.stringify({
          prefix,
          limit: 1000,
          offset,
          sortBy: {column: 'name', order: 'asc'},
        }),
      },
    );
    const rows = await response.json();
    for (const row of rows) {
      const name = prefix ? `${prefix}/${row.name}` : row.name;
      if (row.id == null && row.metadata == null) await listFolder(name, output);
      else output.push(name);
    }
    if (rows.length < 1000) break;
  }
  return output;
}

const before = await listFolder('');
if (!execute) {
  console.log(
    JSON.stringify({mode: 'read-only', bucket, before: before.length}),
  );
  process.exit(0);
}

for (const name of before) {
  const encoded = name.split('/').map(encodeURIComponent).join('/');
  await checked(
    `${projectUrl}/storage/v1/object/${encodeURIComponent(bucket)}/${encoded}`,
    {method: 'DELETE'},
  );
}

const after = await listFolder('');
const success = after.length === 0;
console.log(
  JSON.stringify({
    mode: 'execute',
    bucket,
    before: before.length,
    deleted: before.length - after.length,
    after: after.length,
    success,
  }),
);
if (!success) process.exitCode = 1;
