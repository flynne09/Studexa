#!/usr/bin/env node

const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

const MAGIC = Buffer.from('STUDEXA_RECOVERY_V1\n', 'ascii');

async function encrypt(inputPath, outputPath, keyPath) {
  const plaintext = await fs.readFile(inputPath);
  const key = crypto.randomBytes(32);
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = cipher.getAuthTag();
  await fs.writeFile(outputPath, Buffer.concat([MAGIC, nonce, ciphertext, tag]), { mode: 0o600 });
  await fs.writeFile(keyPath, key, { mode: 0o600 });
}

async function decrypt(inputPath, outputPath, keyPath) {
  const encoded = await fs.readFile(inputPath);
  const key = await fs.readFile(keyPath);
  if (key.length !== 32) throw new Error('The recovery key must contain exactly 32 bytes.');
  if (!encoded.subarray(0, MAGIC.length).equals(MAGIC)) {
    throw new Error('The recovery archive header is invalid.');
  }
  const nonceStart = MAGIC.length;
  const nonceEnd = nonceStart + 12;
  if (encoded.length <= nonceEnd + 16) throw new Error('The recovery archive is truncated.');
  const nonce = encoded.subarray(nonceStart, nonceEnd);
  const tag = encoded.subarray(encoded.length - 16);
  const ciphertext = encoded.subarray(nonceEnd, encoded.length - 16);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
  decipher.setAuthTag(tag);
  const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  await fs.writeFile(outputPath, plaintext, { mode: 0o600 });
}

async function main() {
  const [operation, inputArg, outputArg, keyArg] = process.argv.slice(2);
  if (!['encrypt', 'decrypt'].includes(operation) || !inputArg || !outputArg || !keyArg) {
    throw new Error('Usage: node tool/recovery_archive_crypto.js <encrypt|decrypt> <input> <output> <raw-key-file>');
  }
  const inputPath = path.resolve(inputArg);
  const outputPath = path.resolve(outputArg);
  const keyPath = path.resolve(keyArg);
  if (operation === 'encrypt') await encrypt(inputPath, outputPath, keyPath);
  else await decrypt(inputPath, outputPath, keyPath);
}

main().catch((error) => {
  console.error(`Recovery archive operation failed: ${error.message}`);
  process.exitCode = 1;
});
