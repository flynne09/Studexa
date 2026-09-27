#!/usr/bin/env node

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const execute = process.argv.includes("--execute");
const projectId = process.env.FIREBASE_PROJECT_ID || "studexa-b5e55";
const databaseId = process.env.FIRESTORE_DATABASE_ID || "default";
const storageBucket = process.env.FIREBASE_STORAGE_BUCKET || "studexa-b5e55.firebasestorage.app";
const cliRoot = path.join(process.env.APPDATA || "", "npm", "node_modules", "firebase-tools", "lib");
const cliConfigPath = path.join(os.homedir(), ".config", "configstore", "firebase-tools.json");
const firestoreDatabase = `projects/${projectId}/databases/${databaseId}`;
const firestoreDocuments = `${firestoreDatabase}/documents`;
const firestoreApi = "https://firestore.googleapis.com/v1";
const authApi = `https://identitytoolkit.googleapis.com/v1/projects/${encodeURIComponent(projectId)}`;
const storageApi = `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(storageBucket)}`;

let accessToken;

async function firebaseCliAccessToken() {
  if (accessToken) return accessToken;
  const config = JSON.parse(fs.readFileSync(cliConfigPath, "utf8"));
  const cliRefreshToken = config.tokens?.refresh_token;
  if (!cliRefreshToken) {
    throw new Error("Firebase CLI is not signed in. Run firebase login before cleanup.");
  }
  const auth = require(path.join(cliRoot, "auth.js"));
  const token = await auth.getAccessToken(cliRefreshToken, []);
  if (!token?.access_token) throw new Error("Firebase CLI did not return an OAuth access token.");
  accessToken = token.access_token;
  return accessToken;
}

async function googleRequest(url, { method = "GET", body } = {}) {
  const token = await firebaseCliAccessToken();
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(30000),
  });
  const text = await response.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch (_) {
    data = text;
  }
  if (!response.ok) {
    const message = data?.error?.message || data?.message || text || response.statusText;
    const error = new Error(`HTTP ${response.status}: ${String(message).replace(/[\r\n]+/g, " ").slice(0, 300)}`);
    error.status = response.status;
    throw error;
  }
  return data;
}

async function listUsers() {
  const users = [];
  let pageToken = "";
  do {
    const query = new URLSearchParams({ maxResults: "1000" });
    if (pageToken) query.set("nextPageToken", pageToken);
    const data = await googleRequest(`${authApi}/accounts:batchGet?${query}`);
    users.push(...(data?.users || []));
    pageToken = data?.nextPageToken || "";
  } while (pageToken);
  return users;
}

async function listCollectionIds(parent) {
  const ids = [];
  let pageToken = "";
  do {
    const data = await googleRequest(`${firestoreApi}/${parent}:listCollectionIds`, {
      method: "POST",
      body: { pageSize: 1000, ...(pageToken ? { pageToken } : {}) },
    });
    ids.push(...(data?.collectionIds || []));
    pageToken = data?.nextPageToken || "";
  } while (pageToken);
  return ids;
}

async function listCollectionDocuments(parent, collectionId) {
  const documents = [];
  let pageToken = "";
  do {
    const query = new URLSearchParams({ pageSize: "1000", showMissing: "true" });
    if (pageToken) query.set("pageToken", pageToken);
    const data = await googleRequest(
      `${firestoreApi}/${parent}/${encodeURIComponent(collectionId)}?${query}`,
    );
    documents.push(...(data?.documents || []));
    pageToken = data?.nextPageToken || "";
  } while (pageToken);
  return documents;
}

async function collectDocumentTree(parent, postOrderNames) {
  for (const collectionId of await listCollectionIds(parent)) {
    for (const document of await listCollectionDocuments(parent, collectionId)) {
      await collectDocumentTree(document.name, postOrderNames);
      postOrderNames.push(document.name);
    }
  }
}

async function listDocumentTree() {
  const documents = [];
  await collectDocumentTree(firestoreDocuments, documents);
  return documents;
}

async function storageInventory() {
  try {
    const objects = [];
    let pageToken = "";
    do {
      const query = new URLSearchParams({ maxResults: "1000" });
      if (pageToken) query.set("pageToken", pageToken);
      const data = await googleRequest(`${storageApi}/o?${query}`);
      objects.push(...(data?.items || []));
      pageToken = data?.nextPageToken || "";
    } while (pageToken);
    return { available: true, objects, error: null };
  } catch (error) {
    return { available: false, objects: [], error: String(error.message || error) };
  }
}

async function deleteUsers(users) {
  const failures = [];
  for (let offset = 0; offset < users.length; offset += 1000) {
    const localIds = users.slice(offset, offset + 1000).map((user) => user.localId);
    try {
      const result = await googleRequest(`${authApi}/accounts:batchDelete`, {
        method: "POST",
        body: { localIds, force: true },
      });
      failures.push(...(result?.errors || []).map((entry) => ({
        index: offset + Number(entry.index || 0),
        code: entry.message || "unknown",
      })));
    } catch (error) {
      failures.push({ index: offset, code: String(error.message || error) });
    }
  }
  return failures;
}

async function deleteDocuments(documentNames) {
  for (let offset = 0; offset < documentNames.length; offset += 500) {
    const writes = documentNames.slice(offset, offset + 500).map((name) => ({ delete: name }));
    await googleRequest(`${firestoreApi}/${firestoreDocuments}:batchWrite`, {
      method: "POST",
      body: { writes },
    });
  }
}

async function deleteStorageObjects(objects) {
  for (const object of objects) {
    await googleRequest(`${storageApi}/o/${encodeURIComponent(object.name)}`, { method: "DELETE" });
  }
}

async function inventory() {
  const [users, documents, storage] = await Promise.all([
    listUsers(),
    listDocumentTree(),
    storageInventory(),
  ]);
  return {
    users,
    documents,
    storage,
    summary: {
      authUsers: users.length,
      firestoreDocuments: documents.length,
      storageObjects: storage.available ? storage.objects.length : null,
      storageInventoryError: storage.error,
    },
  };
}

async function main() {
  const beforeInventory = await inventory();
  if (!execute) {
    console.log(JSON.stringify({
      mode: "dry-run",
      projectId,
      databaseId,
      storageBucket,
      before: beforeInventory.summary,
    }, null, 2));
    return;
  }

  await deleteDocuments(beforeInventory.documents);
  const authFailures = await deleteUsers(beforeInventory.users);
  let storageDeleteError = null;
  if (beforeInventory.storage.available) {
    try {
      await deleteStorageObjects(beforeInventory.storage.objects);
    } catch (error) {
      storageDeleteError = String(error.message || error);
    }
  } else {
    storageDeleteError = beforeInventory.storage.error;
  }

  const afterInventory = await inventory();
  const after = afterInventory.summary;
  const success = after.authUsers === 0 && after.firestoreDocuments === 0 &&
    authFailures.length === 0 && after.storageObjects === 0;
  console.log(JSON.stringify({
    mode: "execute",
    projectId,
    databaseId,
    storageBucket,
    before: beforeInventory.summary,
    after,
    authFailures,
    storageDeleteError,
    success,
  }, null, 2));
  if (!success) process.exitCode = 1;
}

main().catch((error) => {
  console.error(`Legacy Firebase cleanup failed: ${error.message}`);
  process.exitCode = 1;
});
