#!/usr/bin/env node

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const projectId = process.env.FIREBASE_PROJECT_ID || 'studexa-b5e55';
const storageBucket =
  process.env.FIREBASE_STORAGE_BUCKET ||
  'studexa-b5e55.firebasestorage.app';
const cliRoot = path.join(
  process.env.APPDATA || '',
  'npm',
  'node_modules',
  'firebase-tools',
  'lib',
);
const cliConfigPath = path.join(
  os.homedir(),
  '.config',
  'configstore',
  'firebase-tools.json',
);
const rulesApi = `https://firebaserules.googleapis.com/v1/projects/${projectId}`;

async function accessToken() {
  const config = JSON.parse(fs.readFileSync(cliConfigPath, 'utf8'));
  const refreshToken = config.tokens?.refresh_token;
  if (!refreshToken) throw new Error('Firebase CLI is not signed in.');
  const auth = require(path.join(cliRoot, 'auth.js'));
  const token = await auth.getAccessToken(refreshToken, []);
  if (!token?.access_token) throw new Error('Firebase CLI token unavailable.');
  return token.access_token;
}

async function request(url, token) {
  const response = await fetch(url, {
    headers: {Authorization: `Bearer ${token}`},
    signal: AbortSignal.timeout(30000),
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : null;
  if (!response.ok) {
    throw new Error(
      `Firebase Rules request failed (${response.status}): ${String(
        data?.error?.message || response.statusText,
      ).slice(0, 240)}`,
    );
  }
  return data;
}

function canonicalRules(value) {
  return value
    .replace(/\/\/.*$/gm, '')
    .replace(/\s+/g, '')
    .trim();
}

async function allReleases(token) {
  const releases = [];
  let pageToken = '';
  do {
    const query = new URLSearchParams({pageSize: '100'});
    if (pageToken) query.set('pageToken', pageToken);
    const data = await request(`${rulesApi}/releases?${query}`, token);
    releases.push(...(data.releases || []));
    pageToken = data.nextPageToken || '';
  } while (pageToken);
  return releases;
}

async function releaseResult(release, expectedPath, token) {
  if (!release?.rulesetName) return null;
  const ruleset = await request(
    `https://firebaserules.googleapis.com/v1/${release.rulesetName}`,
    token,
  );
  const deployed = (ruleset.source?.files || [])
    .map((file) => file.content || '')
    .join('\n');
  const expected = fs.readFileSync(expectedPath, 'utf8');
  return {
    release: release.name,
    ruleset: release.rulesetName,
    matchesTrackedDenyAll:
      canonicalRules(deployed) === canonicalRules(expected),
  };
}

async function main() {
  const token = await accessToken();
  const releases = await allReleases(token);
  const firestoreReleases = releases.filter((release) =>
    release.name.includes('/releases/cloud.firestore'),
  );
  const firestoreRelease =
    firestoreReleases.find((release) => release.name.endsWith('/default')) ||
    firestoreReleases[0];
  const storageReleases = releases.filter((release) =>
    release.name.includes('/releases/firebase.storage'),
  );
  const storageRelease =
    storageReleases.find((release) => release.name.includes(storageBucket)) ||
    storageReleases[0];

  const firestore = await releaseResult(
    firestoreRelease,
    path.resolve('firestore.rules'),
    token,
  );
  const storage = await releaseResult(
    storageRelease,
    path.resolve('storage.rules'),
    token,
  );
  const success = Boolean(
    firestore?.matchesTrackedDenyAll && storage?.matchesTrackedDenyAll,
  );
  console.log(JSON.stringify({projectId, firestore, storage, success}, null, 2));
  if (!success) process.exitCode = 1;
}

main().catch((error) => {
  console.error(`Firebase shutdown verification failed: ${error.message}`);
  process.exitCode = 1;
});
