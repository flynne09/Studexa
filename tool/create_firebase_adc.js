#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const destination = process.argv[2] ? path.resolve(process.argv[2]) : "";
if (!destination) {
  console.error("Usage: node tool/create_firebase_adc.js <private-adc-path>");
  process.exit(2);
}

const configPath = path.join(process.env.USERPROFILE || "", ".config", "configstore", "firebase-tools.json");
const apiPath = path.join(
  process.env.APPDATA || "",
  "npm",
  "node_modules",
  "firebase-tools",
  "lib",
  "api.js",
);

const firebaseConfig = JSON.parse(fs.readFileSync(configPath, "utf8"));
const refreshToken = firebaseConfig.tokens?.refresh_token;
if (!refreshToken) throw new Error("Firebase CLI login has no refresh token.");
const api = require(apiPath);
const adc = {
  type: "authorized_user",
  client_id: api.clientId(),
  client_secret: api.clientSecret(),
  refresh_token: refreshToken,
};
fs.mkdirSync(path.dirname(destination), { recursive: true });
fs.writeFileSync(destination, JSON.stringify(adc), { encoding: "utf8", mode: 0o600 });
console.log(`Temporary Application Default Credentials created at ${destination}`);
