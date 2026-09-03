// Ambient declaration for the Supabase Edge Runtime's built-in inference API.
// Ported from DreTheGeek/laseanpickens supabase/functions/_shared/supabase-ai.d.ts.
//
// Supabase.ai exists at runtime but is not declared by
// jsr:@supabase/functions-js/edge-runtime.d.ts, so any function using it fails
// deno check with TS2304 "Cannot find name 'Supabase'".
//
// run() returns the embedding vector for gte-small: 384 floats, matching the
// extensions.vector(384) column on knowledge.document_chunks.

declare namespace Supabase {
  namespace ai {
    class Session {
      constructor(model: string);
      run(input: string, options?: { mean_pool?: boolean; normalize?: boolean }): Promise<number[]>;
    }
  }
}
