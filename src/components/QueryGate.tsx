import { ReactNode } from 'react';
import { Loader2 } from 'lucide-react';
import { useAuth } from '@/hooks/use-auth';

export function QueryGate({ children }: { children: ReactNode }) {
  const { authReady, session } = useAuth();

  // Block children until auth is fully resolved AND we have a session.
  // This prevents queries from firing without a valid JWT.
  if (!authReady || !session) {
    return (
      <div className="flex h-screen w-screen items-center justify-center">
        <Loader2 className="h-16 w-16 animate-spin text-primary" />
      </div>
    );
  }

  return <>{children}</>;
}
