import { useAuth } from '@/hooks/use-auth';
import { Navigate } from 'react-router-dom';
import { Loader2, ShieldX } from 'lucide-react';
import { Button } from '@/components/ui/button';

interface Props {
  children: React.ReactNode;
  roles?: string[];
}

export function ProtectedRoute({ children, roles }: Props) {
  const { user, session, authReady } = useAuth();

  if (!authReady) {
    return (
      <div className="flex h-screen w-screen items-center justify-center">
        <Loader2 className="h-16 w-16 animate-spin text-primary" />
      </div>
    );
  }

  // Only redirect when auth is fully resolved AND there is no session.
  // Using `session` (not `user`) avoids a flash redirect during background
  // profile loading, since `user` is populated asynchronously.
  if (!session) {
    return <Navigate to="/login" replace />;
  }

  if (roles && user && !roles.includes(user.role)) {
    return (
      <div className="flex h-screen w-screen flex-col items-center justify-center gap-4 px-6 text-center">
        <ShieldX className="h-16 w-16 text-destructive" />
        <h1 className="text-2xl font-bold">Acesso não autorizado</h1>
        <p className="text-muted-foreground">
          Você não tem permissão para acessar esta página.
        </p>
        <Button onClick={() => window.history.back()}>Voltar</Button>
      </div>
    );
  }

  return <>{children}</>;
}
