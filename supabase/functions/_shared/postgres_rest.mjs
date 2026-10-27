/**
 * Custom error class representing HTTP errors returned by the Supabase PostgREST API.
 */
export class PostgresStoreError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// Lookup table mapping camelCase domain field names to snake_case PostgreSQL column names.
const camelToSnake = {
  classId: "class_id", teacherId: "teacher_id", materialId: "material_id",
  type: "quiz_type", generationMethod: "generation_method", sourceQuizId: "source_quiz_id",
  totalPoints: "total_points", requestedQuestionCount: "requested_question_count",
  selectedQuestionTypes: "selected_question_types", extraGenerationAttempted: "extra_generation_attempted",
  generationSessionId: "generation_session_id", extraGenerationSessionId: "extra_generation_session_id",
  completedBatchIds: "completed_batch_ids", automaticBatchesAttempted: "automatic_batches_attempted",
  extraBatchesAttempted: "extra_batches_attempted", generationCredentialSource: "generation_credential_source",
  backupUsed: "backup_used", backupUsageReason: "backup_usage_reason",
  backupGraceRemaining: "backup_grace_remaining", backupFallbackRemainingToday: "backup_fallback_remaining_today",
  fileName: "file_name", extractedText: "extracted_text", createdAt: "created_at",
  updatedAt: "updated_at", publishedAt: "published_at",
};

// Inverse lookup table mapping snake_case PostgreSQL column names back to camelCase domain keys.
const snakeToCamel = Object.fromEntries(Object.entries(camelToSnake).map(([camel, snake]) => [snake, camel]));

/**
 * Converts a camelCase domain object into a snake_case payload suitable for PostgREST inserts/updates.
 */
function toDatabase(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [camelToSnake[key] || key, value]));
}

/**
 * Converts a snake_case database row from PostgREST into a camelCase domain object.
 */
function toDomain(row) {
  return Object.fromEntries(Object.entries(row).map(([key, value]) => [snakeToCamel[key] || key, value]));
}

/**
 * Safely reads an environment variable from the Deno runtime, returning an empty string if unset.
 */
function env(name) { return globalThis.Deno?.env.get(name) || ""; }

/**
 * Creates a lightweight PostgREST client scoped to the caller's Bearer JWT (`token`) so RLS policies apply.
 * Exposes helper methods for finding quizzes by session, getting a row by ID, creating, and optimistic-concurrency updating.
 */
export function postgresClient(token, fetchImpl = fetch, options = {}) {
  const url = options.url || env("SUPABASE_URL");
  const apiKey = options.apiKey || env("SUPABASE_ANON_KEY");
  if (!url || !apiKey) throw new PostgresStoreError(500, "Database is not configured.");

  /**
   * Executes an authenticated HTTP request against `/rest/v1/{path}` and verifies the HTTP status code.
   */
  async function request(path, init = {}, expected = [200]) {
    const response = await fetchImpl(`${url}/rest/v1/${path}`, {
      ...init,
      signal: AbortSignal.timeout(10000),
      headers: {
        Authorization: `Bearer ${token}`,
        apikey: apiKey,
        ...(init.body ? { "Content-Type": "application/json" } : {}),
        ...(init.headers || {}),
      },
    });
    if (!expected.includes(response.status)) {
      throw new PostgresStoreError(response.status, `Database request failed (${response.status}).`);
    }
    if (response.status === 204) return null;
    return response.json();
  }

  return {
    /**
     * Looks up an existing quiz draft by `classId` and `generation_session_id` to guarantee idempotency.
     */
    async findQuizBySession(classId, sessionId) {
      const rows = await request(`quizzes?select=*&class_id=eq.${encodeURIComponent(classId)}&generation_session_id=eq.${encodeURIComponent(sessionId)}&limit=2`);
      if (rows.length > 1) throw new PostgresStoreError(409, "Multiple drafts share a generation session.");
      const row = rows[0];
      return row ? { id: row.id, data: toDomain(row), updateTime: row.updated_at } : null;
    },
    /**
     * Fetches a single record by primary key `id` from `collection`.
     */
    async get(collection, id) {
      const rows = await request(`${collection}?select=*&id=eq.${encodeURIComponent(id)}&limit=1`);
      const row = rows[0];
      return row ? { id: row.id, data: toDomain(row), updateTime: row.updated_at } : null;
    },
    /**
     * Inserts a new record with `id` and `data` into `collection` and returns the created domain entity.
     */
    async create(collection, id, data) {
      const rows = await request(`${collection}?select=*`, {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({ id, ...toDatabase(data) }),
      }, [201]);
      const row = rows[0];
      return { id: row.id, data: toDomain(row), updateTime: row.updated_at };
    },
    /**
     * Updates an existing record in `collection` by `id`, optionally enforcing optimistic locking via `updateTime`.
     */
    async update(collection, id, data, updateTime) {
      const timestampFilter = updateTime ? `&updated_at=eq.${encodeURIComponent(updateTime)}` : "";
      const rows = await request(`${collection}?select=*&id=eq.${encodeURIComponent(id)}${timestampFilter}`, {
        method: "PATCH",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify(toDatabase(data)),
      });
      if (!rows.length) throw new PostgresStoreError(412, "The record changed.");
      const row = rows[0];
      return { id: row.id, data: toDomain(row), updateTime: row.updated_at };
    },
  };
}
