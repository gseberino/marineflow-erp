import {
  useState,
  useEffect,
  createContext,
  useContext,
  ReactNode,
  useRef,
} from 'react';
import { supabase } from '@/integrations/supabase/client';
import { queryClient } from '@/lib/query-client';
import type { Session } from '@supabase/supabase-js';

type AuthUser = {
  id: string;
  email: string;
  full_name: string;
  role: 'admin' | 'technician' | 'financial' | 'seller' | 'other';
};

type AuthContextType = {
  user: AuthUser | null;
  session: Session | null;
  loading: boolean;
  authReady: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthContextType | null>(null);

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

function buildMinimalUser(authUser: { id: string; email?: string }): AuthUser {
  return {
    id: authUser.id,
    email: authUser.email || '',
    full_name: authUser.email || '',
    role: 'admin',
  };
}

async function loadProfile(
  authUser: { id: string; email?: string }
): Promise<AuthUser> {
  try {
    let { data } = await supabase
      .from('app_users')
      .select('full_name, role')
      .ilike('email', authUser.email || '')
      .maybeSingle();

    if (!data) {
      const res = await supabase
        .from('app_users')
        .select('full_name, role')
        .eq('id', authUser.id)
        .maybeSingle();
      data = res.data;
    }

    if (!data) return buildMinimalUser(authUser);

    return {
      id: authUser.id,
      email: authUser.email || '',
      full_name: data.full_name || authUser.email || '',
      role: (data.role as AuthUser['role']) || 'admin',
    };
  } catch {
    return buildMinimalUser(authUser);
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [authReady, setAuthReady] = useState(false);
  const mountedRef = useRef(true);
  const finalizedRef = useRef(false);

  function finalize() {
    if (finalizedRef.current) return;
    finalizedRef.current = true;
    setLoading(false);
    setAuthReady(true);
  }

  function loadProfileBackground(
    authUser: { id: string; email?: string }
  ) {
    setUser(buildMinimalUser(authUser));

    loadProfile(authUser).then((profile) => {
      if (!mountedRef.current) return;
      setUser(profile);
      console.log('[Auth] Profile ready:', profile.role);
    });
  }

  useEffect(() => {
    mountedRef.current = true;

    const safetyTimer = setTimeout(() => {
      console.warn('[Auth] Safety timeout');
      finalize();
    }, 8000);

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, newSession) => {
        if (!mountedRef.current) return;
        if (event === 'INITIAL_SESSION' || event === 'TOKEN_REFRESHED') {
          return;
        }

        setSession(newSession);

        if (event === 'SIGNED_OUT' || !newSession?.user) {
          setUser(null);
          queryClient.clear();
          finalize();
          return;
        }

        loadProfileBackground(newSession.user);
        finalize();
      }
    );

    supabase.auth
      .getSession()
      .then(({ data: { session: s } }) => {
        if (!mountedRef.current) return;
        clearTimeout(safetyTimer);
        setSession(s);

        if (!s?.user) {
          finalize();
          return;
        }

        loadProfileBackground(s.user);
        finalize();
      })
      .catch(() => {
        clearTimeout(safetyTimer);
        finalize();
      });

    return () => {
      mountedRef.current = false;
      clearTimeout(safetyTimer);
      subscription.unsubscribe();
    };
  }, []);

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (error) throw error;
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setSession(null);
    queryClient.clear();
  };

  return (
    <AuthContext.Provider
      value={{ user, session, loading, authReady, signIn, signOut }}
    >
      {children}
    </AuthContext.Provider>
  );
}
