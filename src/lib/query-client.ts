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

let inflightRefresh: Promise<void> | null = null;
function refreshOnce(): Promise<void> {
  if (inflightRefresh) return inflightRefresh;
  inflightRefresh = supabase.auth
    .refreshSession()
    .then(() => {})
    .catch(() => {})
    .finally(() => {
      setTimeout(() => { inflightRefresh = null; }, 2000);
    });
  return inflightRefresh;
}

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60_000,
      gcTime: 5 * 60_000,
      refetchOnWindowFocus: false,
      refetchOnReconnect: false,
      retry: (failureCount, error) => {
        if (isAuthError(error)) {
          refreshOnce();
          return failureCount < 1;
        }
        return failureCount < 1;
      },
      retryDelay: 1000,
    },
  },
});
