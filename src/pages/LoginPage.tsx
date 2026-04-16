import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/use-auth';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import { Anchor, Loader2, Eye, EyeOff, CheckCircle } from 'lucide-react';
import { toast } from 'sonner';

export default function LoginPage() {
  const { signIn } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);

  const [showForgot, setShowForgot] = useState(false);
  const [forgotEmail, setForgotEmail] = useState('');
  const [forgotSent, setForgotSent] = useState(false);
  const [forgotLoading, setForgotLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !password) {
      toast.error('Preencha email e senha');
      return;
    }
    setLoading(true);
    try {
      await signIn(email, password);
      navigate('/');
    } catch (err: any) {
      const msg = err?.message || '';
      if (msg.includes('Invalid login credentials')) {
        toast.error('Email ou senha incorretos');
      } else if (msg.includes('Email not confirmed')) {
        toast.error('Confirme seu email antes de entrar');
      } else if (msg.includes('Too many requests')) {
        toast.error('Muitas tentativas. Aguarde alguns minutos.');
      } else {
        toast.error(msg || 'Erro ao fazer login');
      }
    } finally {
      setLoading(false);
    }
  };

  const handleForgot = async () => {
    if (!forgotEmail) return;
    setForgotLoading(true);
    try {
      await supabase.auth.resetPasswordForEmail(forgotEmail, {
        redirectTo: window.location.origin + '/reset-password',
      });
      setForgotSent(true);
    } catch {
      setForgotSent(true);
    } finally {
      setForgotLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-background p-4">
      <div className="w-full max-w-sm space-y-8">
        {/* Logo */}
        <div className="flex flex-col items-center gap-2">
          <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-primary">
            <Anchor className="h-7 w-7 text-primary-foreground" />
          </div>
          <div className="text-center">
            <h1 className="text-2xl font-bold tracking-tight">MarineFlow</h1>
            <p className="text-sm text-muted-foreground">
              Sistema de Gestão Náutica
            </p>
          </div>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              placeholder="usuario@email.com"
              value={email}
              onChange={e => setEmail(e.target.value)}
              disabled={loading}
              autoComplete="email"
              autoFocus
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Senha</Label>
            <div className="relative">
              <Input
                id="password"
                type={showPassword ? 'text' : 'password'}
                placeholder="••••••••"
                value={password}
                onChange={e => setPassword(e.target.value)}
                disabled={loading}
                autoComplete="current-password"
                className="pr-10"
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                tabIndex={-1}
              >
                {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
          </div>
          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Entrando...
              </>
            ) : (
              'Entrar'
            )}
          </Button>
          <button
            type="button"
            onClick={() => setShowForgot(true)}
            className="text-xs text-muted-foreground hover:text-primary transition-colors w-full text-center"
          >
            Esqueci minha senha
          </button>
        </form>

        <p className="text-center text-xs text-muted-foreground">
          MarineFlow ERP · Acesso restrito
        </p>

        {import.meta.env.DEV && (
          <div className="rounded-lg border border-dashed p-3 text-xs text-muted-foreground">
            <p className="font-medium">Modo desenvolvimento</p>
            <p>
              Crie um usuário em Supabase Auth e cadastre-o em Configurações →
              Usuários com o mesmo email.
            </p>
          </div>
        )}
      </div>

      <Dialog open={showForgot} onOpenChange={setShowForgot}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Redefinir senha</DialogTitle>
            <DialogDescription>
              Insira seu email. Se houver uma conta associada, você receberá
              um link para redefinir sua senha.
            </DialogDescription>
          </DialogHeader>
          {forgotSent ? (
            <div className="flex flex-col items-center gap-3 py-4 text-center">
              <CheckCircle className="h-10 w-10 text-primary" />
              <p className="text-sm text-muted-foreground">
                Se este email estiver cadastrado, você receberá as instruções
                em breve. Verifique sua caixa de entrada.
              </p>
              <Button
                onClick={() => {
                  setShowForgot(false);
                  setForgotSent(false);
                  setForgotEmail('');
                }}
              >
                Fechar
              </Button>
            </div>
          ) : (
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="forgot-email">Email</Label>
                <Input
                  id="forgot-email"
                  type="email"
                  placeholder="usuario@email.com"
                  value={forgotEmail}
                  onChange={e => setForgotEmail(e.target.value)}
                  disabled={forgotLoading}
                  autoFocus
                />
              </div>
              <div className="flex justify-end gap-2">
                <Button variant="ghost" onClick={() => setShowForgot(false)}>
                  Cancelar
                </Button>
                <Button onClick={handleForgot} disabled={forgotLoading || !forgotEmail}>
                  {forgotLoading ? (
                    <>
                      <Loader2 className="h-4 w-4 animate-spin" />
                      Enviando...
                    </>
                  ) : (
                    'Enviar link'
                  )}
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
