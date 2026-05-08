import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/use-auth';
import { supabase } from '@/integrations/supabase/client';
import { useQuery } from '@tanstack/react-query';
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
import { Loader2, Eye, EyeOff, CheckCircle } from 'lucide-react';
import { toast } from 'sonner';

export default function LoginPage() {
  const { signIn } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);

  const { data: logoUrl } = useQuery({
    queryKey: ['company-logo'],
    queryFn: async () => {
      const { data } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'company_logo_url')
        .maybeSingle();
      return data?.value || null;
    },
    staleTime: 5 * 60 * 1000,
  });

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
    <div className="relative flex min-h-screen overflow-hidden bg-[#0D1B2A]">

      {/* ── Decorative background waves ── */}
      <div className="pointer-events-none absolute inset-0 overflow-hidden">
        {/* Gradient overlay top */}
        <div className="absolute inset-x-0 top-0 h-72 bg-gradient-to-b from-[#274A6D]/25 to-transparent" />
        {/* Wave SVG — bottom */}
        <svg
          className="absolute bottom-0 left-0 w-full"
          viewBox="0 0 1440 180"
          preserveAspectRatio="none"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            d="M0,90 C240,30 480,150 720,90 C960,30 1200,150 1440,90 L1440,180 L0,180 Z"
            fill="#274A6D"
            fillOpacity="0.18"
          />
          <path
            d="M0,110 C360,50 720,170 1080,110 C1260,80 1360,100 1440,90"
            stroke="#C8A063"
            strokeWidth="1.5"
            opacity="0.35"
          />
          <path
            d="M0,130 C360,80 720,175 1080,130 C1260,108 1360,122 1440,115"
            stroke="#7FA0B8"
            strokeWidth="1"
            opacity="0.25"
          />
        </svg>
        {/* Subtle radial glow */}
        <div className="absolute left-1/2 top-1/3 h-96 w-96 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[#274A6D]/20 blur-3xl" />
      </div>

      {/* ── Main content ── */}
      <div className="relative z-10 flex flex-1 flex-col items-center justify-center px-4 py-12">

        {/* Logo & brand */}
        <div className="mb-8 flex flex-col items-center gap-3">
          {logoUrl ? (
            <img src={logoUrl} alt="HBR Systems" className="h-20 w-auto max-w-[240px] object-contain drop-shadow-lg" />
          ) : (
            <>
              {/* HBR lettering */}
              <div className="flex flex-col items-center leading-none select-none">
                <span className="text-[52px] font-black tracking-[0.22em] text-white drop-shadow-md" style={{ fontFamily: "'Plus Jakarta Sans', system-ui, sans-serif" }}>
                  HBR
                </span>

                {/* Wave line */}
                <svg viewBox="0 0 220 22" className="w-52 -mt-1" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path
                    d="M10,11 C45,2 75,19 110,11 C145,3 175,18 210,11"
                    stroke="#C8A063"
                    strokeWidth="2.2"
                    strokeLinecap="round"
                  />
                  <path
                    d="M18,13 C55,5 85,20 118,13 C151,6 180,19 215,13"
                    stroke="#7FA0B8"
                    strokeWidth="1.4"
                    strokeLinecap="round"
                    opacity="0.7"
                  />
                </svg>

                {/* SYSTEMS wordmark */}
                <div className="flex items-center gap-2.5 mt-1">
                  <div className="h-px w-8 bg-[#C8A063]/70" />
                  <span className="text-[10px] font-bold tracking-[0.45em] text-[#D9DDE1]/80 uppercase">
                    Systems
                  </span>
                  <div className="h-px w-8 bg-[#7FA0B8]/60" />
                </div>
              </div>

              {/* Tagline */}
              <p className="mt-2 text-sm font-medium tracking-wider text-[#C8A063]">
                Energia. Controle. Confiança.
              </p>
            </>
          )}
        </div>

        {/* ── Form card ── */}
        <div className="w-full max-w-sm">
          <div className="rounded-2xl bg-white p-7 shadow-2xl shadow-black/50 ring-1 ring-white/10">
            <h2 className="mb-5 text-center text-lg font-bold text-[#0D1B2A]">
              Acesse sua conta
            </h2>

            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="space-y-1.5">
                <Label htmlFor="email" className="text-[#274A6D] font-medium">Email</Label>
                <Input
                  id="email"
                  type="email"
                  placeholder="usuario@hbrsystems.com.br"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  disabled={loading}
                  autoComplete="email"
                  autoFocus
                  className="border-[#D9DDE1] focus-visible:ring-[#C8A063]/60"
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="password" className="text-[#274A6D] font-medium">Senha</Label>
                <div className="relative">
                  <Input
                    id="password"
                    type={showPassword ? 'text' : 'password'}
                    placeholder="••••••••"
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    disabled={loading}
                    autoComplete="current-password"
                    className="pr-10 border-[#D9DDE1] focus-visible:ring-[#C8A063]/60"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-[#7FA0B8] hover:text-[#274A6D] transition-colors"
                    tabIndex={-1}
                  >
                    {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
              </div>

              <Button
                type="submit"
                className="w-full bg-[#C8A063] hover:bg-[#b8905a] text-[#0D1B2A] font-bold shadow-md shadow-[#C8A063]/30 transition-all"
                disabled={loading}
              >
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
                className="w-full text-center text-xs text-[#7FA0B8] hover:text-[#274A6D] transition-colors"
              >
                Esqueci minha senha
              </button>
            </form>
          </div>

          {/* Footer */}
          <p className="mt-5 text-center text-[11px] text-[#7FA0B8]/50">
            HBR Systems · High-Trust Boats &amp; RV Systems · Acesso restrito
          </p>

          {import.meta.env.DEV && (
            <div className="mt-3 rounded-lg border border-white/10 p-3 text-xs text-white/40">
              <p className="font-medium">Modo desenvolvimento</p>
              <p>Crie um usuário em Supabase Auth e cadastre-o em Configurações → Usuários.</p>
            </div>
          )}
        </div>
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
