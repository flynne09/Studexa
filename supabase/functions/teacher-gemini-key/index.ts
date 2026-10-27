// Entry point for the `teacher-gemini-key` Supabase Edge Function, which lets
// teachers inspect, verify/save, or remove their personal Gemini API key.
import { handleTeacherGeminiKeyRequest } from "../_shared/teacher_gemini_key_edge.mjs";

// Start the Deno HTTP server to handle teacher Gemini credential management requests.
Deno.serve(handleTeacherGeminiKeyRequest);
