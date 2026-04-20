import {
  useState, useEffect, createContext,
  useContext, ReactNode, useRef,
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

async function fetchProfile(
  authUser: { id: string; email?: string }
): Promise<AuthUser> {
  try {
    // Try by email (case-insensitive)
    let { data } = await supabase
      .from('app_users')
      .select('full_name, role')
      .ilike('email', authUser.email || '')
      .maybeSingle();

    // Fallback: try by id
    if (!data) {
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
    };
  } catch {
    return {
      id: authUser.id,
      email: authUser.email || '',
      full_name: authUser.email || '',
      role: 'admin',
    };
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [authReady, setAuthReady] = useState(false);

  // Use refs to avoid stale closures
  const authReadyRef = useRef(false);
  const finalizedRef = useRef(false);

  useEffect(() => {
    let mounted = true;

    // Called ONCE to mark auth as done — never resets to true
    function finalize() {
      if (!mounted || finalizedRef.current) return;
      finalizedRef.current = true;
      authReadyRef.current = true;
      setLoading(false);
      setAuthReady(true);
    }

    // Safety net: force-finalize after 6 seconds no matter what
    const safetyTimer = setTimeout(() => {
      if (mounted && !authReadyRef.current) {
        console.warn('[Auth] Safety timeout triggered');
        finalize();
      }
    }, 6000);

    // Single source of truth: onAuthStateChange handles everything.
    // We skip INITIAL_SESSION (handled by getSession below) and
    // TOKEN_REFRESHED (handled automatically by Supabase client).
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, newSession) => {
        if (!mounted) return;

        // These events don't require any action from us
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

        // SIGNED_IN or USER_UPDATED: load the profile
        fetchProfile(newSession.user).then((profile) => {
          if (!mounted) return;
          setUser(profile);
          console.log('[Auth] SIGNED_IN profile:', profile.role);
          finalize();
        });
      }
    );

    // Bootstrap: restore session from localStorage.
    // This is the ONLY place we call getSession().
    supabase.auth.getSession().then(({ data: { session: s } }) => {
      if (!mounted) return;
      setSession(s);

      if (!s?.user) {
        // No session in storage — done immediately
        finalize();
        return;
      }

      // Session found: load profile then finalize
      fetchProfile(s.user).then((profile) => {
        if (!mounted) return;
        setUser(profile);
        console.log('[Auth] Boot profile:', profile.role);
        finalize();
      });
    }).catch(() => {
      if (mounted) finalize();
    });

    return () => {
      mounted = false;
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
