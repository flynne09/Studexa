// The request handler is kept in an ES module so its auth, persistence and
// batching behavior can be tested without a running Supabase project.
import { handleQuizRequest } from "../_shared/quiz_edge.mjs";

Deno.serve(handleQuizRequest);
