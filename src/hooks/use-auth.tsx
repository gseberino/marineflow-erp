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
  role: 'admin' | 'technician' | 'financial' | 'seller' | 'external_seller' | 'other';
  department?: string | null;
  metadata?: any;
};

type AuthContextType = {
  user: AuthUser | null;
  session: Session | null;
  loading: boolean;
  authReady: boolean;
  profileReady: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  refreshProfile: () => Promise<void>;
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
    role: 'other',
  };
}

async function loadProfile(
  authUser: { id: string; email?: string }
): Promise<AuthUser> {
  try {
    let { data } = await supabase
      .from('app_users')
      .select('full_name, role, department, metadata')
      .ilike('email', authUser.email || '')
      .maybeSingle();

    if (!data) {
      const res = await supabase
        .from('app_users')
        .select('full_name, role, department, metadata')
        .eq('id', authUser.id)
        .maybeSingle();
      data = res.data;
    }

    if (data) {
      console.log('[Auth] Profile loaded successfully:', { role: data.role, hasMetadata: !!data.metadata, metadata: data.metadata });
    }

    return {
      id: authUser.id,
      email: authUser.email || '',
      full_name: data.full_name || authUser.email || '',
      role: (data.role as AuthUser['role']) || 'other',
      department: data.department,
      metadata: data.metadata,
    };
  } catch (err) {
    console.error('[Auth] Profile load error:', err);
    return buildMinimalUser(authUser);
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [profileReady, setProfileReady] = useState(false);
  const mountedRef = useRef(true);
  const profileRequestRef = useRef(0);
  const lastUserIdRef = useRef<string | null>(null);

  function loadProfileBackground(authUser: { id: string; email?: string }) {
    const requestId = profileRequestRef.current + 1;
    profileRequestRef.current = requestId;

    // Only set minimal user if we don't already have a user for this id
    setUser((prev) => (prev?.id === authUser.id ? prev : buildMinimalUser(authUser)));
    // Reset profileReady while a new profile is being fetched
    setProfileReady(false);

    loadProfile(authUser)
      .then((profile) => {
        if (!mountedRef.current || profileRequestRef.current !== requestId) return;
        setUser(profile);
        setProfileReady(true);
        console.log('[Auth] Profile ready:', profile.role);
      })
      .catch((error) => {
        if (!mountedRef.current || profileRequestRef.current !== requestId) return;
        console.warn('[Auth] Profile load failed:', error);
        // Mark ready even on failure so ProtectedRoute can evaluate (role='other' → unauthorized)
        setProfileReady(true);
      });
  }

  function applySession(newSession: Session | null, opts?: { reloadProfile?: boolean }) {
    setSession(newSession);

    if (!newSession?.user) {
      profileRequestRef.current += 1;
      lastUserIdRef.current = null;
      setUser(null);
      setProfileReady(false);
      return;
    }

    const sameUser = lastUserIdRef.current === newSession.user.id;
    lastUserIdRef.current = newSession.user.id;

    if (!sameUser || opts?.reloadProfile) {
      loadProfileBackground(newSession.user);
    }
  }

  useEffect(() => {
    mountedRef.current = true;

    let unsub: (() => void) | null = null;

    // Safety timer: ensure UI does not hang forever
    const safetyTimer = setTimeout(() => {
      if (!mountedRef.current) return;
      if (!authReady) {
        console.warn('[Auth] Safety timeout — forcing authReady');
        setAuthReady(true);
      }
    }, 5000);

    // 1) Restore session FIRST so we know the truth before listening
    supabase.auth
      .getSession()
      .then(({ data: { session: s } }) => {
        if (!mountedRef.current) return;
        applySession(s);
        setAuthReady(true);
        clearTimeout(safetyTimer);

        // 2) THEN register listener
        const { data } = supabase.auth.onAuthStateChange((event, newSession) => {
          if (!mountedRef.current) return;

          if (event === 'SIGNED_OUT') {
            queryClient.clear();
            applySession(null);
            return;
          }

          if (event === 'TOKEN_REFRESHED') {
            applySession(newSession, { reloadProfile: false });
            // Re-run any queries that may have failed with stale JWT
            void queryClient.invalidateQueries();
            return;
          }

          if (event === 'SIGNED_IN' || event === 'USER_UPDATED' || event === 'INITIAL_SESSION') {
            applySession(newSession);
            return;
          }

          applySession(newSession);
        });
        unsub = () => data.subscription.unsubscribe();
      })
      .catch((error) => {
        if (!mountedRef.current) return;
        console.warn('[Auth] Session restore failed:', error);
        applySession(null);
        setAuthReady(true);
        clearTimeout(safetyTimer);
      });

    return () => {
      mountedRef.current = false;
      clearTimeout(safetyTimer);
      if (unsub) unsub();
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
    lastUserIdRef.current = null;
    queryClient.clear();
  };

  const refreshProfile = async () => {
    if (session?.user) {
      const profile = await loadProfile(session.user);
      setUser(profile);
    }
  };

  return (
    <AuthContext.Provider
      value={{ user, session, loading: !authReady, authReady, profileReady, signIn, signOut, refreshProfile }}
    >
      {children}
    </AuthContext.Provider>
  );
}
