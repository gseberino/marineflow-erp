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

let inflightRefresh: Promise<boolean> | null = null;

function refreshOnce(): Promise<boolean> {
  if (inflightRefresh) return inflightRefresh;
  inflightRefresh = supabase.auth
    .refreshSession()
    .then(({ data, error }) => {
      if (error || !data.session) return false;
      return true;
    })
    .catch(() => false)
    .finally(() => {
      setTimeout(() => {
        inflightRefresh = null;
      }, 2000);
    }) as Promise<boolean>;
  return inflightRefresh;
}

export async function triggerRefreshAndInvalidate(): Promise<boolean> {
  const ok = await refreshOnce();
  if (ok) {
    await queryClient.invalidateQueries();
  }
  return ok;
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
          // fire-and-forget refresh; retry will pick up new token
          void triggerRefreshAndInvalidate();
          return failureCount < 2;
        }
        return failureCount < 1;
      },
      retryDelay: (attempt) => Math.min(1000 * 2 ** attempt, 4000),
    },
  },
});
