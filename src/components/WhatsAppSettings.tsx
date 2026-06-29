import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { AlertTriangle, CheckCircle2, FlaskConical, MessageSquare, Send, ServerCog } from 'lucide-react';
import { useWhatsAppSend } from '@/hooks/use-whatsapp-send';

const SETTING_KEYS = ['wa_test_mode', 'wa_test_number'] as const;

type WhatsAppOperationalSettings = {
  wa_test_mode: string;
  wa_test_number: string;
};

export function WhatsAppConnectionSettings() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [settings, setSettings] = useState<WhatsAppOperationalSettings>({
    wa_test_mode: 'false',
    wa_test_number: '',
  });

  const { send, sending: waSending } = useWhatsAppSend();
  const testModeActive = settings.wa_test_mode === 'true';

  useEffect(() => {
    async function loadSettings() {
      // Load new keys; also check legacy zapi_* keys as fallback (migration period)
      const { data, error } = await supabase
        .from('app_settings')
        .select('key, value')
        .in('key', [...SETTING_KEYS, 'zapi_test_mode', 'zapi_test_number']);

      if (error) {
        toast.error('Erro ao carregar controles do WhatsApp');
        setLoading(false);
        return;
      }

      const map: WhatsAppOperationalSettings = { wa_test_mode: 'false', wa_test_number: '' };
      const raw: Record<string, string> = {};
      data?.forEach((s) => { raw[s.key] = s.value || ''; });

      // Prefer new keys; fall back to legacy if new keys not yet migrated
      map.wa_test_mode = raw['wa_test_mode'] ?? raw['zapi_test_mode'] ?? 'false';
      map.wa_test_number = raw['wa_test_number'] ?? raw['zapi_test_number'] ?? '';

      setSettings(map);
      setLoading(false);
    }

    loadSettings();
  }, []);

  const handleSave = async () => {
    if (testModeActive && !settings.wa_test_number.trim()) {
      toast.error('Informe o número de redirecionamento antes de ativar o Modo de Teste.');
      return;
    }

    setSaving(true);
    try {
      const entries = SETTING_KEYS.map((key) => ({
        key,
        value: String(settings[key]),
      }));

      const { error } = await supabase.from('app_settings').upsert(entries, { onConflict: 'key' });
      if (error) throw error;
      toast.success('Controles operacionais do WhatsApp salvos');
    } catch (err: any) {
      toast.error(err.message || 'Erro ao salvar');
    } finally {
      setSaving(false);
    }
  };

  const handleSendTest = async () => {
    const targetPhone = settings.wa_test_number.trim();
    if (!targetPhone) {
      toast.error('Informe o número de teste primeiro');
      return;
    }

    toast.info(`Enviando mensagem de teste para +${targetPhone.replace(/\D/g, '')}...`);
    const ok = await send(
      {
        phone: targetPhone,
        message:
          '🚀 *MarineFlow ERP* — Teste de integração WhatsApp realizado com sucesso!\n\n_Este é um envio de verificação para o número autorizado no modo de teste._',
        mode: 'link',
        context: 'test',
        publicUrl: 'https://hbrmarine.online',
        link_title: 'MarineFlow ERP',
        link_description: 'Sistema de Gestão Náutica',
      },
      { autoRetry: false, maxAttempts: 1 },
    );

    if (ok) toast.success(`Mensagem enviada para +${targetPhone.replace(/\D/g, '')}!`);
  };

  if (loading) return null;

  return (
    <Card className="max-w-2xl border-primary/20 shadow-sm">
      <CardHeader>
        <CardTitle className="text-lg flex items-center gap-2">
          <ServerCog className="h-5 w-5 text-primary" /> Integração WhatsApp
        </CardTitle>
        <CardDescription>
          Credenciais e tokens ficam exclusivamente no backend. Aqui ficam apenas controles operacionais seguros.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        <Alert className="border-primary/30 bg-primary/5">
          <CheckCircle2 className="h-4 w-4 text-primary" />
          <AlertTitle>Credenciais protegidas no backend</AlertTitle>
          <AlertDescription className="text-sm">
            Instance ID, token e Client Token não são exibidos nem salvos pelo painel. O envio usa os secrets
            configurados nas Edge Functions, reduzindo exposição de credenciais no browser e no banco.
          </AlertDescription>
        </Alert>

        {testModeActive && (
          <Alert className="border-amber-400 bg-amber-50 dark:bg-amber-950/30">
            <FlaskConical className="h-4 w-4 text-amber-600" />
            <AlertTitle className="text-amber-700 font-bold">MODO DE TESTE ATIVO</AlertTitle>
            <AlertDescription className="text-amber-700">
              <strong>Nenhum cliente deve receber mensagens enquanto este modo estiver ativo.</strong> Os envios
              passam a ser redirecionados para o número de teste configurado.
              <code className="bg-amber-100 px-2 py-0.5 rounded font-mono font-bold text-sm">
                +{settings.wa_test_number || '(número não definido)'}
              </code>
              <br />
              <span className="text-xs mt-1 block">
                Inclui: OS, orçamentos, lembretes de agendamento e cobranças automáticas.
              </span>
            </AlertDescription>
          </Alert>
        )}

        {!testModeActive && (
          <Alert className="border-green-300 bg-green-50 dark:bg-green-950/20">
            <CheckCircle2 className="h-4 w-4 text-green-600" />
            <AlertTitle className="text-green-700 font-semibold">Modo produção</AlertTitle>
            <AlertDescription className="text-green-700 text-sm">
              Mensagens podem ser enviadas para clientes reais. Ative o Modo de Teste antes de realizar validações.
            </AlertDescription>
          </Alert>
        )}

        <div className={`pt-4 border-t space-y-4 ${testModeActive ? 'rounded-lg border border-amber-200 bg-amber-50/30 dark:bg-amber-950/10 p-4' : ''}`}>
          <div className="flex items-center justify-between gap-4">
            <div className="space-y-0.5">
              <Label className="text-base flex items-center gap-2 font-semibold">
                <AlertTriangle className={`h-4 w-4 ${testModeActive ? 'text-amber-500 animate-pulse' : 'text-muted-foreground'}`} />
                Modo de Teste / Redirecionamento
              </Label>
              <p className="text-sm text-muted-foreground">
                Quando ativo, as mensagens enviadas pelo sistema são redirecionadas para o número abaixo,
                protegendo clientes durante validações.
              </p>
            </div>
            <Switch
              checked={testModeActive}
              onCheckedChange={(value) => setSettings((prev) => ({ ...prev, wa_test_mode: String(value) }))}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="wa_test_number" className={testModeActive ? 'text-amber-700 font-semibold' : ''}>
              <MessageSquare className="h-3 w-3 inline mr-1" />
              Número de redirecionamento
              {testModeActive && <span className="ml-1 text-red-500">*</span>}
            </Label>
            <Input
              id="wa_test_number"
              value={settings.wa_test_number}
              onChange={(e) => setSettings((prev) => ({ ...prev, wa_test_number: e.target.value }))}
              placeholder="55DDDNXXXXXXXX"
              className={testModeActive ? 'border-amber-400 bg-amber-50 ring-2 ring-amber-200' : ''}
            />
            <p className="text-[10px] text-muted-foreground">
              Formato: DDI + DDD + número sem espaços.
              {settings.wa_test_number && (
                <span className="ml-1 font-medium text-amber-700">
                  Configurado: <strong>+{settings.wa_test_number.replace(/\D/g, '')}</strong>
                </span>
              )}
            </p>
          </div>
        </div>

        <div className="flex justify-between items-center pt-2 border-t gap-3">
          <Button
            variant="outline"
            onClick={handleSendTest}
            disabled={waSending || saving || !settings.wa_test_number}
            className="gap-2 border-amber-300 text-amber-700 hover:bg-amber-50"
            title={!settings.wa_test_number ? 'Defina o número de teste primeiro' : ''}
          >
            <Send className="h-4 w-4" />
            {waSending ? 'Enviando...' : 'Enviar mensagem de teste'}
          </Button>

          <Button onClick={handleSave} disabled={saving} className="gap-2">
            {saving ? 'Salvando...' : 'Salvar controles WhatsApp'}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
