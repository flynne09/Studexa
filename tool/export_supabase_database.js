#!/usr/bin/env node

const fs = require("node:fs/promises");
const path = require("node:path");
const { createRequire } = require("node:module");

const [debugLogArg, outputArg, pgPackageRootArg] = process.argv.slice(2);
if (!debugLogArg || !outputArg || !pgPackageRootArg) {
  console.error("Usage: node tool/export_supabase_database.js <private-cli-debug-log> <output-json> <temporary-pg-package-root>");
  process.exit(2);
}

const pgRequire = createRequire(path.resolve(pgPackageRootArg, "package.json"));
const { Client } = pgRequire("pg");

function parseExport(log, name) {
  const match = log.match(new RegExp(`export ${name}="([^"]+)"`));
  if (!match) throw new Error(`Supabase CLI did not provide ${name}.`);
  return match[1];
}

function encode(value) {
  if (typeof value === "bigint") return { __type: "bigint", value: value.toString() };
  if (Buffer.isBuffer(value)) return { __type: "bytes", base64: value.toString("base64") };
  if (value instanceof Date) return { __type: "timestamp", value: value.toISOString() };
  if (Array.isArray(value)) return value.map(encode);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encode(item)]));
  }
  return value;
}

async function main() {
  const debugLogBytes = await fs.readFile(path.resolve(debugLogArg));
  const utf16LittleEndian = (debugLogBytes[0] === 0xff && debugLogBytes[1] === 0xfe)
    || debugLogBytes[1] === 0x00;
  const debugLog = utf16LittleEndian
    ? debugLogBytes.subarray(debugLogBytes[0] === 0xff ? 2 : 0).toString("utf16le")
    : debugLogBytes.toString("utf8");
  const host = parseExport(debugLog, "PGHOST");
  const allowLocalTlsProxy = process.env.STUDEXA_ALLOW_LOCAL_TLS_PROXY === "1";
  if (!host.endsWith(".pooler.supabase.com")) {
    throw new Error("Refusing to connect to an unexpected database host.");
  }
  const client = new Client({
    host,
    port: Number(parseExport(debugLog, "PGPORT")),
    database: parseExport(debugLog, "PGDATABASE"),
    user: parseExport(debugLog, "PGUSER"),
    password: parseExport(debugLog, "PGPASSWORD"),
    ssl: { rejectUnauthorized: !allowLocalTlsProxy },
    connectionTimeoutMillis: 15000,
    query_timeout: 30000,
  });

  await client.connect();
  try {
    await client.query('set role postgres');
    const schemas = ["public", "private", "auth", "storage", "vault"];
    const result = await client.query(
      `select table_schema, table_name
       from information_schema.tables
       where table_type = 'BASE TABLE' and table_schema = any($1::text[])
       order by table_schema, table_name`,
      [schemas],
    );
    const tables = {};
    let totalRows = 0;
    for (const { table_schema: schema, table_name: table } of result.rows) {
      const identifier = `"${schema.replaceAll('"', '""')}"."${table.replaceAll('"', '""')}"`;
      const rows = (await client.query(`select * from ${identifier}`)).rows.map(encode);
      tables[`${schema}.${table}`] = { rowCount: rows.length, rows };
      totalRows += rows.length;
    }
    await fs.writeFile(
      path.resolve(outputArg),
      JSON.stringify({
        exportedAt: new Date().toISOString(),
        schemas,
        tableCount: Object.keys(tables).length,
        totalRows,
        note: "Vault base-table values remain encrypted; decrypted_secrets was not queried.",
        tables,
      }, null, 2),
      { encoding: "utf8", mode: 0o600 },
    );
    console.log(JSON.stringify({ tableCount: Object.keys(tables).length, totalRows }));
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error(`Supabase database export failed: ${error.message}`);
  process.exitCode = 1;
});
