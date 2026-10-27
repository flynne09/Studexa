// The request handler is kept in an ES module so its auth, persistence and
// batching behavior can be tested without a running Supabase project.
// Entry point for the `generate-quiz` Supabase Edge Function, which delegates
// incoming HTTP requests to `handleQuizRequest`.
import { handleQuizRequest } from "../_shared/quiz_edge.mjs";

// Start the Deno HTTP server to handle AI quiz generation and continuation batches.
Deno.serve(handleQuizRequest);
