import { ReactNode } from 'react';
import { Loader2 } from 'lucide-react';
import { useAuth } from '@/hooks/use-auth';

/**
 * Prevents children (and therefore any useQuery hooks they contain)
 * from mounting until the auth session has been restored.
 * This eliminates the race condition where queries fire before
 * the Supabase JWT is attached, causing 401 → infinite loading.
 */
export function QueryGate({ children }: { children: ReactNode }) {
  const { authReady } = useAuth();

  if (!authReady) {
    return (
      <div className="flex h-screen w-full items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  return <>{children}</>;
}
