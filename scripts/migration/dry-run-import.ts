type EnvLike = Record<string, string | undefined>;

export type DryRunSupabaseConfig = {
  url: string;
  key: string;
  source: string;
};

export function resolveDryRunSupabaseConfig(env: EnvLike = process.env): DryRunSupabaseConfig | null {
  const url = env.VITE_SUPABASE_URL?.trim() || env.SUPABASE_URL?.trim() || null;
  const key =
    env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ||
    env.SUPABASE_ANON_KEY?.trim() ||
    env.SUPABASE_PUBLISHABLE_KEY?.trim() ||
    null;

  if (!url || !key) {
    return null;
  }

  const source = [
    env.VITE_SUPABASE_URL?.trim() ? 'VITE_SUPABASE_URL' : 'SUPABASE_URL',
    env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()
      ? 'VITE_SUPABASE_PUBLISHABLE_KEY'
      : env.SUPABASE_ANON_KEY?.trim()
        ? 'SUPABASE_ANON_KEY'
        : 'SUPABASE_PUBLISHABLE_KEY',
  ].join(' / ');

  return { url, key, source };
}

export function listMissingDryRunEnvVars(env: EnvLike = process.env): string[] {
  const missing: string[] = [];

  if (!env.VITE_SUPABASE_URL?.trim() && !env.SUPABASE_URL?.trim()) {
    missing.push('VITE_SUPABASE_URL', 'SUPABASE_URL');
  }

  if (
    !env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() &&
    !env.SUPABASE_ANON_KEY?.trim() &&
    !env.SUPABASE_PUBLISHABLE_KEY?.trim()
  ) {
    missing.push('VITE_SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY', 'SUPABASE_PUBLISHABLE_KEY');
  }

  return missing;
}
