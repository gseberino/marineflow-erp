import { useAuth } from '@/hooks/use-auth';
import { Navigate } from 'react-router-dom';
import { Loader2, ShieldX } from 'lucide-react';
import { Button } from '@/components/ui/button';

interface Props {
  children: React.ReactNode;
  roles?: string[];
  groupId?: string;
}

export function ProtectedRoute({ children, roles, groupId }: Props) {
  const { user, session, authReady } = useAuth();

  if (!authReady) {
    return (
      <div className="flex h-screen w-screen items-center justify-center">
        <Loader2 className="h-16 w-16 animate-spin text-primary" />
      </div>
    );
  }

  if (!session) {
    return <Navigate to="/login" replace />;
  }

  if (roles && user) {
    const hasRole = roles.includes(user.role);
    const isAdmin = user.role === 'admin';
    
    // Check for dynamic permissions in metadata field
    const visibleAreas = (user.metadata as any)?.visible_areas as string[] | undefined;
    const legacyAreas = user.department ? user.department.split(',').map(s => s.trim()) : [];
    const allowedGroups = visibleAreas || legacyAreas;
    
    const hasGroup = groupId && allowedGroups.includes(groupId);

    if (!hasRole && !hasGroup && !isAdmin) {
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
  }

  return <>{children}</>;
}
