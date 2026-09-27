#!/usr/bin/env node

const fs = require("node:fs/promises");
const path = require("node:path");
const { createRequire } = require("node:module");
const functionsRequire = createRequire(path.resolve(__dirname, "../functions/package.json"));
const { applicationDefault, initializeApp } = functionsRequire("firebase-admin/app");
const { getFirestore } = functionsRequire("firebase-admin/firestore");
const { getStorage } = functionsRequire("firebase-admin/storage");

const outputRoot = process.argv[2] ? path.resolve(process.argv[2]) : "";
const projectId = process.env.GOOGLE_CLOUD_PROJECT || "studexa-b5e55";
const databaseId = process.env.FIRESTORE_DATABASE_ID || "default";
const storageBucket = process.env.FIREBASE_STORAGE_BUCKET || "studexa-b5e55.firebasestorage.app";

if (!outputRoot) {
  console.error("Usage: node tool/export_legacy_firebase.js <private-output-directory>");
  process.exit(2);
}

function encode(value) {
  if (value == null || ["string", "number", "boolean"].includes(typeof value)) return value;
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    return { __type: "bytes", base64: Buffer.from(value).toString("base64") };
  }
  if (Array.isArray(value)) return value.map(encode);
  if (typeof value.toDate === "function") {
    return { __type: "timestamp", value: value.toDate().toISOString() };
  }
  if (typeof value.path === "string" && value.firestore) {
    return { __type: "document_reference", path: value.path };
  }
  if (typeof value.latitude === "number" && typeof value.longitude === "number") {
    return { __type: "geopoint", latitude: value.latitude, longitude: value.longitude };
  }
  if (value instanceof Date) return { __type: "date", value: value.toISOString() };
  if (typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encode(item)]));
  }
  return String(value);
}

async function exportCollection(collection, records) {
  const refs = await collection.listDocuments();
  refs.sort((left, right) => left.path.localeCompare(right.path));
  for (const ref of refs) {
    const snapshot = await ref.get();
    if (snapshot.exists) records.push({ path: ref.path, data: encode(snapshot.data()) });
    const children = await ref.listCollections();
    children.sort((left, right) => left.path.localeCompare(right.path));
    for (const child of children) await exportCollection(child, records);
  }
}

function safeObjectDestination(root, objectName) {
  const relative = objectName
    .split("/")
    .filter(Boolean)
    .map((segment) => segment.replace(/[<>:"|?*]/g, "_").replace(/\.+$/g, "_"))
    .join(path.sep);
  const destination = path.resolve(root, relative || "unnamed-object");
  const requiredPrefix = `${path.resolve(root)}${path.sep}`.toLowerCase();
  if (!destination.toLowerCase().startsWith(requiredPrefix)) {
    throw new Error(`Unsafe Storage object path: ${objectName}`);
  }
  return { destination, relative: path.relative(root, destination) };
}

async function main() {
  await fs.mkdir(outputRoot, { recursive: true });
  const app = initializeApp({
    credential: applicationDefault(),
    projectId,
    storageBucket,
  }, `studexa-recovery-${Date.now()}`);

  const firestore = getFirestore(app, databaseId);
  const records = [];
  const roots = await firestore.listCollections();
  roots.sort((left, right) => left.path.localeCompare(right.path));
  for (const collection of roots) await exportCollection(collection, records);
  await fs.writeFile(
    path.join(outputRoot, "firestore-documents.json"),
    JSON.stringify({ projectId, databaseId, documentCount: records.length, documents: records }, null, 2),
    { encoding: "utf8", mode: 0o600 },
  );

  const storageRoot = path.join(outputRoot, "firebase-storage");
  await fs.mkdir(storageRoot, { recursive: true });
  const bucket = getStorage(app).bucket(storageBucket);
  const manifest = [];
  let storageApiError = null;
  try {
    const [files] = await bucket.getFiles({ autoPaginate: true });
    files.sort((left, right) => left.name.localeCompare(right.name));
    for (const file of files) {
      const target = safeObjectDestination(storageRoot, file.name);
      await fs.mkdir(path.dirname(target.destination), { recursive: true });
      await file.download({ destination: target.destination });
      const stat = await fs.stat(target.destination);
      manifest.push({ object: file.name, localPath: target.relative, bytes: stat.size, method: "admin" });
    }
  } catch (error) {
    storageApiError = String(error.message || error).replace(/[\r\n]+/g, " ").slice(0, 300);
  }

  // Spark/no-billing projects may reject the bucket listing API. Preserve any
  // legacy material that still has its private Firebase download URL without
  // writing that URL or its token into the manifest.
  const legacyMaterials = records.filter((record) =>
    /^materials\/[^/]+$/.test(record.path) && record.data?.storageProvider !== "supabase");
  const downloadedObjects = new Set(manifest.map((item) => item.object));
  const unresolved = [];
  for (const record of legacyMaterials) {
    const objectName = String(record.data.fileRef || "");
    if (objectName && downloadedObjects.has(objectName)) continue;
    const downloadUrl = String(record.data.downloadUrl || "");
    if (!downloadUrl.startsWith("https://")) {
      unresolved.push({ document: record.path, object: objectName || null, reason: "no_download_url" });
      continue;
    }
    const response = await fetch(downloadUrl, { signal: AbortSignal.timeout(30000) });
    if (!response.ok) {
      unresolved.push({ document: record.path, object: objectName || null, reason: `http_${response.status}` });
      continue;
    }
    const fallbackName = record.path.replaceAll("/", "_");
    const target = safeObjectDestination(storageRoot, objectName || fallbackName);
    await fs.mkdir(path.dirname(target.destination), { recursive: true });
    await fs.writeFile(target.destination, Buffer.from(await response.arrayBuffer()), { mode: 0o600 });
    const stat = await fs.stat(target.destination);
    manifest.push({ object: objectName || null, document: record.path, localPath: target.relative, bytes: stat.size, method: "download_url" });
  }
  await fs.writeFile(
    path.join(outputRoot, "firebase-storage-manifest.json"),
    JSON.stringify({
      bucket: storageBucket,
      objectCount: manifest.length,
      objects: manifest,
      unresolved,
      storageApiError,
    }, null, 2),
    { encoding: "utf8", mode: 0o600 },
  );

  console.log(JSON.stringify({
    firestoreDocuments: records.length,
    storageObjects: manifest.length,
    unresolvedStorageObjects: unresolved.length,
    storageListingAvailable: storageApiError == null,
  }));
}

main().catch((error) => {
  console.error(`Legacy Firebase export failed: ${error.message}`);
  process.exitCode = 1;
});
