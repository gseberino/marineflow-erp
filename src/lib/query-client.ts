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

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      gcTime: 5 * 60_000,
      refetchOnWindowFocus: false,
      retry: (failureCount, error) => {
        if (isAuthError(error)) {
          // Try to refresh the session in background; allow more retries
          supabase.auth.refreshSession().catch(() => {});
          return failureCount < 5;
        }
        return failureCount < 3;
      },
      retryDelay: (attempt) => Math.min(1000 * 2 ** attempt, 8000),
    },
  },
});
