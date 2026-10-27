// Entry point for the `submit-quiz-attempt` Supabase Edge Function, which scores
// and persists a student's quiz attempt via `handleSubmitQuizAttempt`.
import { handleSubmitQuizAttempt } from "../_shared/submit_quiz_attempt_edge.mjs";

// Start the Deno HTTP server to listen for student quiz submission requests.
Deno.serve(handleSubmitQuizAttempt);
