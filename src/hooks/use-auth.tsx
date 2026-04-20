import { useState, useEffect, createContext, useContext, ReactNode, useRef } from 'react';
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

const PROFILE_TIMEOUT_MS = 4000;

function withTimeout<T>(p: Promise<T>, ms: number, fallback: T): Promise<T> {
  return new Promise((resolve) => {
    let done = false;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      resolve(fallback);
    }, ms);
    p.then((v) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve(v);
    }).catch(() => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve(fallback);
    });
  });
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [authReady, setAuthReady] = useState(false);
  const profileLoadIdRef = useRef(0);

  // If Settings menu is missing, verify app_users record:
  // SELECT id, email, role FROM app_users
  //   WHERE email ILIKE 'your@email.com';
  // UPDATE app_users SET role = 'admin'
  //   WHERE email ILIKE 'your@email.com';
  const loadUserProfile = async (authUser: { id: string; email?: string }) => {
    const myId = ++profileLoadIdRef.current;

    // Build a minimal user immediately so the app never blocks on profile fetch
    const minimal: AuthUser = {
      id: authUser.id,
      email: authUser.email || '',
      full_name: authUser.email || '',
      role: 'admin',
    };

    const fetchProfile = (async () => {
      let { data } = await supabase
        .from('app_users')
        .select('full_name, role')
        .ilike('email', authUser.email || '')
        .maybeSingle();

      if (!data && authUser.id) {
        const res = await supabase
          .from('app_users')
          .select('full_name, role')
          .eq('id', authUser.id)
          .maybeSingle();
        data = res.data;
      }

      return {
        id: authUser.id,
        email: authUser.email || '',
        full_name: data?.full_name || authUser.email || '',
        role: (data?.role as AuthUser['role']) || 'admin',
      } as AuthUser;
    })();

    const resolved = await withTimeout(fetchProfile, PROFILE_TIMEOUT_MS, minimal);

    // Stale-response guard: only the most recent load may write user state
    if (myId !== profileLoadIdRef.current) return;
    setUser(resolved);
    console.log('[Auth] Profile loaded:', { email: resolved.email, role: resolved.role });
  };

  useEffect(() => {
    let mounted = true;

    const finalize = () => {
      if (!mounted) return;
      setLoading(false);
      setAuthReady(true);
    };

    // Register listener BEFORE getSession. The callback never blocks the
    // auth pipeline with awaits — profile loading runs in the background.
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, newSession) => {
        if (!mounted) return;
        setSession(newSession);

        if (event === 'SIGNED_OUT' || !newSession?.user) {
          profileLoadIdRef.current++; // invalidate any in-flight profile load
          setUser(null);
          if (event === 'SIGNED_OUT') queryClient.clear();
          finalize();
          return;
        }

        // Fire-and-forget profile load — does not block auth pipeline
        loadUserProfile(newSession.user).finally(() => {
          if (mounted) finalize();
        });

        if (event === 'TOKEN_REFRESHED') {
          queryClient.invalidateQueries();
        }
      }
    );

    // Initial session restoration
    supabase.auth.getSession().then(({ data: { session: s } }) => {
      if (!mounted) return;
      setSession(s);
      if (s?.user) {
        loadUserProfile(s.user).finally(() => {
          if (mounted) finalize();
        });
      } else {
        finalize();
      }
    }).catch(() => {
      finalize();
    });

    // Hard safety net: never let bootstrap take more than 8 seconds
    const bootTimeout = setTimeout(() => {
      if (mounted && !authReady) finalize();
    }, 8000);

    // When the tab becomes visible again, re-check the session
    const onVisibility = () => {
      if (document.visibilityState === 'visible') {
        supabase.auth.getSession().catch(() => {});
      }
    };
    document.addEventListener('visibilitychange', onVisibility);

    return () => {
      mounted = false;
      clearTimeout(bootTimeout);
      subscription.unsubscribe();
      document.removeEventListener('visibilitychange', onVisibility);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setSession(null);
    queryClient.clear();
  };

  return (
    <AuthContext.Provider value={{ user, session, loading, authReady, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}
