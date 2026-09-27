#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";

const [projectUrl, bucket, keyFile, outputRootArg] = process.argv.slice(2);
if (!projectUrl || !bucket || !keyFile || !outputRootArg) {
  console.error("Usage: node tool/export_supabase_recovery.mjs <project-url> <bucket> <private-key-json> <output-directory>");
  process.exit(2);
}
const outputRoot = path.resolve(outputRootArg);
const keyRecords = JSON.parse((await fs.readFile(path.resolve(keyFile), "utf8")).replace(/^\uFEFF/, ""));
const serverKey = keyRecords.find((item) => item.name === "service_role")?.api_key ||
  keyRecords.find((item) => item.type === "secret")?.api_key;
if (!serverKey) throw new Error("No Supabase server key was available for the recovery export.");
const headers = { apikey: serverKey, Authorization: `Bearer ${serverKey}` };

async function checkedJson(url, init = {}) {
  const response = await fetch(url, {
    ...init,
    headers: { ...headers, ...(init.body ? { "Content-Type": "application/json" } : {}), ...(init.headers || {}) },
    signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) throw new Error(`Supabase recovery request failed (${response.status}).`);
  return response.json();
}

function safeDestination(root, objectName) {
  const relative = objectName
    .split("/")
    .filter(Boolean)
    .map((segment) => segment.replace(/[<>:"|?*]/g, "_").replace(/\.+$/g, "_"))
    .join(path.sep);
  const destination = path.resolve(root, relative || "unnamed-object");
  const requiredPrefix = `${path.resolve(root)}${path.sep}`.toLowerCase();
  if (!destination.toLowerCase().startsWith(requiredPrefix)) throw new Error("Unsafe Storage object path.");
  return { destination, relative: path.relative(root, destination) };
}

async function exportAuth() {
  const users = [];
  for (let page = 1; ; page++) {
    const body = await checkedJson(`${projectUrl}/auth/v1/admin/users?page=${page}&per_page=1000`);
    const batch = Array.isArray(body) ? body : body.users || [];
    users.push(...batch);
    if (batch.length < 1000) break;
  }
  await fs.writeFile(
    path.join(outputRoot, "supabase-auth-users.json"),
    JSON.stringify({ userCount: users.length, users }, null, 2),
    { encoding: "utf8", mode: 0o600 },
  );
  return users.length;
}

async function listFolder(prefix, output = []) {
  for (let offset = 0; ; offset += 1000) {
    const rows = await checkedJson(`${projectUrl}/storage/v1/object/list/${encodeURIComponent(bucket)}`, {
      method: "POST",
      body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: "name", order: "asc" } }),
    });
    for (const row of rows) {
      const name = prefix ? `${prefix}/${row.name}` : row.name;
      if (row.id == null && row.metadata == null) await listFolder(name, output);
      else output.push({ name, metadata: row.metadata || null, createdAt: row.created_at || null, updatedAt: row.updated_at || null });
    }
    if (rows.length < 1000) break;
  }
  return output;
}

async function exportStorage() {
  const objects = await listFolder("");
  const storageRoot = path.join(outputRoot, "supabase-storage", bucket);
  await fs.mkdir(storageRoot, { recursive: true });
  const manifest = [];
  for (const object of objects) {
    const response = await fetch(
      `${projectUrl}/storage/v1/object/authenticated/${encodeURIComponent(bucket)}/${object.name.split("/").map(encodeURIComponent).join("/")}`,
      { headers, signal: AbortSignal.timeout(60000) },
    );
    if (!response.ok) throw new Error(`Supabase object download failed (${response.status}).`);
    const target = safeDestination(storageRoot, object.name);
    await fs.mkdir(path.dirname(target.destination), { recursive: true });
    await fs.writeFile(target.destination, Buffer.from(await response.arrayBuffer()), { mode: 0o600 });
    const stat = await fs.stat(target.destination);
    manifest.push({ ...object, localPath: target.relative, bytes: stat.size });
  }
  await fs.writeFile(
    path.join(outputRoot, "supabase-storage-manifest.json"),
    JSON.stringify({ bucket, objectCount: manifest.length, objects: manifest }, null, 2),
    { encoding: "utf8", mode: 0o600 },
  );
  return manifest.length;
}

await fs.mkdir(outputRoot, { recursive: true });
const [authUsers, storageObjects] = await Promise.all([exportAuth(), exportStorage()]);
console.log(JSON.stringify({ authUsers, storageObjects }));
