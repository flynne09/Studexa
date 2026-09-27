#!/usr/bin/env node

const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

const recoveryRoot = process.argv[2] ? path.resolve(process.argv[2]) : "";
const bucket = process.env.FIREBASE_STORAGE_BUCKET || "studexa-b5e55.firebasestorage.app";
const cliRoot = path.join(process.env.APPDATA || "", "npm", "node_modules", "firebase-tools", "lib");
const cliConfigPath = path.join(os.homedir(), ".config", "configstore", "firebase-tools.json");

if (!recoveryRoot) {
  console.error("Usage: node tool/download_legacy_firebase_storage.js <private-recovery-directory>");
  process.exit(2);
}

async function firebaseCliAccessToken() {
  const config = JSON.parse(await fs.readFile(cliConfigPath, "utf8"));
  const cliRefreshToken = config.tokens?.refresh_token;
  if (!cliRefreshToken) throw new Error("Firebase CLI is not signed in.");
  const auth = require(path.join(cliRoot, "auth.js"));
  const token = await auth.getAccessToken(cliRefreshToken, []);
  if (!token?.access_token) throw new Error("Firebase CLI did not return an OAuth access token.");
  return token.access_token;
}

function safeDestination(root, objectName) {
  const relative = objectName
    .split("/")
    .filter(Boolean)
    .map((segment) => segment.replace(/[<>:"|?*]/g, "_").replace(/\.+$/g, "_"))
    .join(path.sep);
  const destination = path.resolve(root, relative || "unnamed-object");
  const requiredPrefix = `${path.resolve(root)}${path.sep}`.toLowerCase();
  if (!destination.toLowerCase().startsWith(requiredPrefix)) {
    throw new Error(`Unsafe Firebase Storage object path: ${objectName}`);
  }
  return { destination, relative: path.relative(root, destination) };
}

async function authorizedFetch(url, token) {
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(60000),
  });
  if (!response.ok) {
    const text = await response.text();
    let message = text;
    try {
      message = JSON.parse(text)?.error?.message || text;
    } catch (_) {}
    const error = new Error(`HTTP ${response.status}: ${String(message).replace(/[\r\n]+/g, " ").slice(0, 300)}`);
    error.status = response.status;
    throw error;
  }
  return response;
}

async function listObjects(token) {
  const objects = [];
  let pageToken = "";
  do {
    const query = new URLSearchParams({ maxResults: "1000" });
    if (pageToken) query.set("pageToken", pageToken);
    const response = await authorizedFetch(
      `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}/o?${query}`,
      token,
    );
    const data = await response.json();
    objects.push(...(data.items || []));
    pageToken = data.nextPageToken || "";
  } while (pageToken);
  return objects;
}

async function main() {
  const token = await firebaseCliAccessToken();
  const storageRoot = path.join(recoveryRoot, "firebase-storage");
  const manifestPath = path.join(recoveryRoot, "firebase-storage-manifest.json");
  await fs.mkdir(storageRoot, { recursive: true });
  const previousManifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
  const documentByObject = new Map(
    (previousManifest.unresolved || [])
      .filter((entry) => entry.object)
      .map((entry) => [entry.object, entry.document]),
  );
  const listed = await listObjects(token);
  const objects = [];
  const unresolved = [];

  for (const object of listed.sort((left, right) => left.name.localeCompare(right.name))) {
    const target = safeDestination(storageRoot, object.name);
    try {
      const response = await authorizedFetch(
        `https://storage.googleapis.com/download/storage/v1/b/${encodeURIComponent(bucket)}/o/${encodeURIComponent(object.name)}?alt=media`,
        token,
      );
      const bytes = Buffer.from(await response.arrayBuffer());
      await fs.mkdir(path.dirname(target.destination), { recursive: true });
      await fs.writeFile(target.destination, bytes, { mode: 0o600 });
      objects.push({
        object: object.name,
        localPath: target.relative,
        bytes: bytes.length,
        sha256: crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase(),
        method: "firebase_cli_oauth_rest",
      });
    } catch (error) {
      unresolved.push({
        document: documentByObject.get(object.name) || null,
        object: object.name,
        reason: error.status ? `http_${error.status}` : "download_failed",
        detail: String(error.message || error).replace(/[\r\n]+/g, " ").slice(0, 300),
      });
    }
  }

  const manifest = {
    bucket,
    objectCount: objects.length,
    objects,
    unresolved,
    storageApiError: null,
  };
  await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2), { encoding: "utf8", mode: 0o600 });
  console.log(JSON.stringify({
    bucket,
    listedObjects: listed.length,
    downloadedObjects: objects.length,
    unresolvedObjects: unresolved.length,
  }, null, 2));
  if (unresolved.length) process.exitCode = 1;
}

main().catch((error) => {
  console.error(`Firebase Storage recovery failed: ${error.message}`);
  process.exitCode = 1;
});
