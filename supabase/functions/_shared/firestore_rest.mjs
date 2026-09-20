const BASE = "https://firestore.googleapis.com/v1/projects/studexa-b5e55/databases/default/documents";

export class FirestoreError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function decodeValue(value) {
  if ("nullValue" in value) return null;
  if ("stringValue" in value) return value.stringValue;
  if ("timestampValue" in value) return value.timestampValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("booleanValue" in value) return value.booleanValue;
  if ("arrayValue" in value) return (value.arrayValue.values || []).map(decodeValue);
  if ("mapValue" in value) return decodeFields(value.mapValue.fields || {});
  throw new FirestoreError(502, "Firestore returned an unsupported value.");
}

function decodeFields(fields) {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, decodeValue(value)]));
}

function encodeValue(value, key = "") {
  if (value == null) return { nullValue: "NULL_VALUE" };
  if (typeof value === "string") {
    if (["createdAt", "updatedAt"].includes(key) && !Number.isNaN(Date.parse(value))) {
      return { timestampValue: value };
    }
    return { stringValue: value };
  }
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number" && Number.isFinite(value)) {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (Array.isArray(value)) return { arrayValue: { values: value.map((item) => encodeValue(item)) } };
  if (typeof value === "object") return { mapValue: { fields: encodeFields(value) } };
  throw new FirestoreError(400, "Unsupported quiz field.");
}

function encodeFields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [key, encodeValue(value, key)]));
}

function document(data) {
  return { fields: encodeFields(data) };
}

export function firestoreClient(token, fetchImpl = fetch) {
  async function request(url, options = {}) {
    const response = await fetchImpl(url, {
      ...options,
      signal: AbortSignal.timeout(10000),
      headers: {
        Authorization: `Bearer ${token}`,
        ...(options.body ? { "Content-Type": "application/json" } : {}),
      },
    });
    if (!response.ok) {
      throw new FirestoreError(response.status, `Firestore request failed (${response.status}).`);
    }
    const result = await response.json();
    return { data: decodeFields(result.fields || {}), updateTime: result.updateTime };
  }

  return {
    async findQuizBySession(classId, sessionId) {
      // A direct read of an absent quiz is denied by the existing rules because
      // quiz read authorization depends on resource.data.classId. A class-scoped
      // query can prove ownership even when it returns no documents.
      const response = await fetchImpl(`${BASE}:runQuery`, {
        method: "POST",
        signal: AbortSignal.timeout(10000),
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ structuredQuery: {
          from: [{ collectionId: "quizzes" }],
          where: { compositeFilter: { op: "AND", filters: [
            { fieldFilter: { field: { fieldPath: "classId" }, op: "EQUAL", value: { stringValue: classId } } },
            { fieldFilter: { field: { fieldPath: "generationSessionId" }, op: "EQUAL", value: { stringValue: sessionId } } },
          ] } },
          limit: 2,
        } }),
      });
      if (!response.ok) throw new FirestoreError(response.status, `Firestore query failed (${response.status}).`);
      const results = await response.json();
      const matches = results.filter((item) => item.document).map(({ document: value }) => ({
        id: value.name.split("/").at(-1),
        data: decodeFields(value.fields || {}),
        updateTime: value.updateTime,
      }));
      if (matches.length > 1) throw new FirestoreError(409, "Multiple drafts share a generation session.");
      return matches[0] || null;
    },
    async get(collection, id) {
      try {
        return await request(`${BASE}/${collection}/${encodeURIComponent(id)}`);
      } catch (error) {
        if (error instanceof FirestoreError && error.status === 404) return null;
        throw error;
      }
    },
    create(collection, id, data) {
      return request(`${BASE}/${collection}?documentId=${encodeURIComponent(id)}`, {
        method: "POST", body: JSON.stringify(document(data)),
      });
    },
    update(collection, id, data, updateTime) {
      const params = new URLSearchParams();
      for (const key of Object.keys(data)) params.append("updateMask.fieldPaths", key);
      params.set("currentDocument.updateTime", updateTime);
      return request(`${BASE}/${collection}/${encodeURIComponent(id)}?${params}`, {
        method: "PATCH", body: JSON.stringify(document(data)),
      });
    },
  };
}
