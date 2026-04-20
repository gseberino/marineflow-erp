import { useState, useEffect, createContext, useContext, ReactNode } from 'react';
import { supabase } from '@/integrations/supabase/client';
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
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthContextType | null>(null);

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  const loadUserProfile = async (authUser: { id: string; email?: string }) => {
    try {
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

      setUser({
        id: authUser.id,
        email: authUser.email || '',
        full_name: data?.full_name || authUser.email || '',
        role: (data?.role as AuthUser['role']) || 'admin',
      });
    } catch {
      setUser({
        id: authUser.id,
        email: authUser.email || '',
        full_name: authUser.email || '',
        role: 'admin',
      });
    }
  };

  useEffect(() => {
    let mounted = true;

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      async (_event, newSession) => {
        if (!mounted) return;
        setSession(newSession);
        if (newSession?.user) {
          await loadUserProfile(newSession.user);
        } else {
          setUser(null);
        }
        if (mounted) setLoading(false);
      }
    );

    supabase.auth.getSession().then(({ data: { session: s } }) => {
      if (!mounted) return;
      setSession(s);
      if (s?.user) {
        loadUserProfile(s.user).finally(() => {
          if (mounted) setLoading(false);
        });
      } else {
        if (mounted) setLoading(false);
      }
    });

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, []);

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setSession(null);
  };

  return (
    <AuthContext.Provider value={{ user, session, loading, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}
