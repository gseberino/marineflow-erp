import { QueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

function isAuthError(err: any): boolean {
  const status = err?.status ?? err?.statusCode ?? err?.code;
  const msg = String(err?.message || '').toLowerCase();
  return (
    status === 401 ||
    status === '401' ||
    status === 'PGRST301' ||
    msg.includes('jwt') ||
    msg.includes('unauthorized') ||
    msg.includes('not authenticated')
  );
}

// Single-flight session refresh: if many queries fail with 401 at once,
// only ONE real refresh call runs; everyone awaits the same promise.
let inflightRefresh: Promise<void> | null = null;
function refreshOnce(): Promise<void> {
  if (inflightRefresh) return inflightRefresh;
  inflightRefresh = supabase.auth
    .refreshSession()
    .then(() => {})
    .catch(() => {})
    .finally(() => {
      // Allow another refresh attempt after a small cool-down
      setTimeout(() => { inflightRefresh = null; }, 1500);
    });
  return inflightRefresh;
}

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      gcTime: 5 * 60_000,
      refetchOnWindowFocus: false,
      retry: (failureCount, error) => {
        if (isAuthError(error)) {
          // Coordinated refresh; up to 3 retries for auth errors
          refreshOnce();
          return failureCount < 3;
        }
        return failureCount < 2;
      },
      retryDelay: (attempt) => Math.min(500 * 2 ** attempt, 4000),
    },
  },
});
