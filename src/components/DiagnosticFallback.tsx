import { useEffect, useState } from 'react';
import { useAuth } from '@/hooks/use-auth';
import { DiagnosticExportButton } from './DiagnosticExportButton';

export function DiagnosticFallback() {
  const { authReady } = useAuth();
  const [show, setShow] = useState(false);

  useEffect(() => {
    if (authReady) {
      setShow(false);
      return;
    }
    const t = setTimeout(() => setShow(true), 8000);
    return () => clearTimeout(t);
  }, [authReady]);

  if (!show || authReady) return null;
  return <DiagnosticExportButton variant="fallback" />;
}
