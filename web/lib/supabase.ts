import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const supabaseURL = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
const supabasePublishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();

let browserClient: SupabaseClient | undefined;

export function isCloudBackupConfigured(): boolean {
  return Boolean(supabaseURL && supabasePublishableKey);
}

export function getSupabaseBrowserClient(): SupabaseClient | undefined {
  if (!supabaseURL || !supabasePublishableKey) return undefined;
  browserClient ??= createClient(supabaseURL, supabasePublishableKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  });
  return browserClient;
}
