import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Shield, MessageSquare, AlertTriangle, Send, FlaskConical, CheckCircle2, Eye, EyeOff } from 'lucide-react';
import { useZApiSend } from '@/hooks/use-zapi-send';

export function WhatsAppZApiSettings() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showToken, setShowToken] = useState(false);
  const [showClientToken, setShowClientToken] = useState(false);
  const [settings, setSettings] = useState({
    zapi_instance_id: '',
    zapi_token: '',
    zapi_client_token: '',
    zapi_test_mode: 'false',
    zapi_test_number: '',
  });

  const { send, sending: zapiSending } = useZApiSend();
  const testModeActive = settings.zapi_test_mode === 'true';

  useEffect(() => {
    async function loadSettings() {
      const { data, error } = await supabase
        .from('app_settings')
        .select('key, value')
        .filter('key', 'like', 'zapi_%');
      
      if (error) {
        toast.error('Erro ao carregar configurações do Z-API');
        return;
      }

      if (data) {
        const map: any = { ...settings };
        data.forEach(s => {
          if (s.key in map) map[s.key] = s.value || '';
        });
        setSettings(map);
      }
      setLoading(false);
    }
    loadSettings();
  }, []);

  const handleSave = async () => {
    // Validação: modo de teste ativo sem número bloqueia salvamento
    if (testModeActive && !settings.zapi_test_number.trim()) {
      toast.error('Informe o número de redirecionamento antes de ativar o Modo de Teste.');
      return;
    }

    setSaving(true);
    try {
      const entries = Object.entries(settings).map(([key, value]) => ({
        key,
        value: String(value),
      }));

      const { error } = await supabase
        .from('app_settings')
        .upsert(entries, { onConflict: 'key' });

      if (error) throw error;
      toast.success('Configurações do Z-API salvas com sucesso');
    } catch (err: any) {
      toast.error(err.message || 'Erro ao salvar');
    } finally {
      setSaving(false);
    }
  };

  const handleSendTest = async () => {
    const targetPhone = settings.zapi_test_number.trim();
    if (!targetPhone) {
      toast.error('Informe o número de teste primeiro');
      return;
    }
    toast.info(`Enviando mensagem de teste para +${targetPhone.replace(/\D/g, '')}...`);
    const ok = await send({
      phone: targetPhone,
      message: '🚀 *MarineFlow ERP* — Teste de integração Z-API realizado com sucesso!\n\n_Este é um envio de verificação. Modo de Teste está ATIVO._',
      mode: 'link',
      context: 'test',
      publicUrl: 'https://hbrmarine.online',
      link_title: 'MarineFlow ERP',
      link_description: 'Sistema de Gestão Náutica'
    }, { autoRetry: false, maxAttempts: 1 });
    
    if (ok) toast.success(`Mensagem enviada para +${targetPhone.replace(/\D/g, '')}!`);
  };

  if (loading) return null;

  return (
    <Card className="max-w-2xl border-primary/20 shadow-sm">
      <CardHeader>
        <CardTitle className="text-lg flex items-center gap-2">
          <Shield className="h-5 w-5 text-primary" /> Credenciais Z-API
        </CardTitle>
        <CardDescription>
          Configure aqui os tokens da sua conta Z-API para habilitar o envio automático de mensagens WhatsApp.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">

        {/* Banner de Modo de Teste ATIVO */}
        {testModeActive && (
          <Alert className="border-amber-400 bg-amber-50 dark:bg-amber-950/30">
            <FlaskConical className="h-4 w-4 text-amber-600" />
            <AlertTitle className="text-amber-700 font-bold">🔀 MODO DE TESTE ATIVO</AlertTitle>
            <AlertDescription className="text-amber-700">
              <strong>NENHUM cliente receberá mensagens agora.</strong> Todos os envios estão sendo
              redirecionados para:{' '}
              <code className="bg-amber-100 px-2 py-0.5 rounded font-mono font-bold text-sm">
                +{settings.zapi_test_number || '(número não definido)'}
              </code>
              <br/>
              <span className="text-xs mt-1 block">Inclui: OS, orçamentos, lembretes de agendamento e cobranças automáticas.</span>
            </AlertDescription>
          </Alert>
        )}

        {/* Banner de Produção */}
        {!testModeActive && settings.zapi_instance_id && (
          <Alert className="border-green-300 bg-green-50 dark:bg-green-950/20">
            <CheckCircle2 className="h-4 w-4 text-green-600" />
            <AlertTitle className="text-green-700 font-semibold">Modo Produção</AlertTitle>
            <AlertDescription className="text-green-700 text-sm">
              Mensagens serão enviadas para os clientes reais. Ative o Modo de Teste ao realizar validações.
            </AlertDescription>
          </Alert>
        )}

        {/* Credenciais */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label htmlFor="zapi_instance_id">ID da Instância</Label>
            <Input
              id="zapi_instance_id"
              value={settings.zapi_instance_id}
              onChange={e => setSettings(p => ({ ...p, zapi_instance_id: e.target.value }))}
              placeholder="Ex: 3B..."
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="zapi_token">Token da Instância</Label>
            <div className="relative">
              <Input
                id="zapi_token"
                value={settings.zapi_token}
                onChange={e => setSettings(p => ({ ...p, zapi_token: e.target.value }))}
                placeholder="Ex: 50..."
                type={showToken ? 'text' : 'password'}
                className="pr-10"
              />
              <button
                type="button"
                onClick={() => setShowToken(v => !v)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
              >
                {showToken ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
          </div>
          <div className="space-y-2 col-span-2">
            <Label htmlFor="zapi_client_token">Client Token (Segurança Adicional)</Label>
            <div className="relative">
              <Input
                id="zapi_client_token"
                value={settings.zapi_client_token}
                onChange={e => setSettings(p => ({ ...p, zapi_client_token: e.target.value }))}
                placeholder="Ex: F..."
                type={showClientToken ? 'text' : 'password'}
                className="pr-10"
              />
              <button
                type="button"
                onClick={() => setShowClientToken(v => !v)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
              >
                {showClientToken ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
          </div>
        </div>

        {/* Modo de Teste */}
        <div className={`pt-4 border-t space-y-4 ${testModeActive ? 'rounded-lg border border-amber-200 bg-amber-50/30 dark:bg-amber-950/10 p-4' : ''}`}>
          <div className="flex items-center justify-between">
            <div className="space-y-0.5">
              <Label className="text-base flex items-center gap-2 font-semibold">
                <AlertTriangle className={`h-4 w-4 ${testModeActive ? 'text-amber-500 animate-pulse' : 'text-muted-foreground'}`} />
                Modo de Teste / Redirecionamento
              </Label>
              <p className="text-sm text-muted-foreground">
                Quando ativo, <strong>TODAS</strong> as mensagens enviadas pelo sistema (automáticas ou manuais)
                serão redirecionadas para o número abaixo, protegendo os clientes.
              </p>
            </div>
            <Switch
              checked={testModeActive}
              onCheckedChange={v => setSettings(p => ({ ...p, zapi_test_mode: String(v) }))}
            />
          </div>
          
          <div className="space-y-2">
            <Label htmlFor="zapi_test_number" className={testModeActive ? 'text-amber-700 font-semibold' : ''}>
              <MessageSquare className="h-3 w-3 inline mr-1" />
              Número de Redirecionamento (WhatsApp pessoal)
              {testModeActive && <span className="ml-1 text-red-500">*</span>}
            </Label>
            <Input
              id="zapi_test_number"
              value={settings.zapi_test_number}
              onChange={e => setSettings(p => ({ ...p, zapi_test_number: e.target.value }))}
              placeholder="5547999159654"
              className={testModeActive ? 'border-amber-400 bg-amber-50 ring-2 ring-amber-200' : ''}
            />
            <p className="text-[10px] text-muted-foreground">
              Formato: DDI + DDD + Número sem espaços (ex: <code>5547999159654</code>).
              {settings.zapi_test_number && (
                <span className="ml-1 font-medium text-amber-700">
                  Configurado: <strong>+{settings.zapi_test_number.replace(/\D/g, '')}</strong>
                </span>
              )}
            </p>
          </div>
        </div>

        <div className="flex justify-between items-center pt-2 border-t gap-3">
          <Button 
            variant="outline" 
            onClick={handleSendTest} 
            disabled={zapiSending || saving || !settings.zapi_test_number} 
            className="gap-2 border-amber-300 text-amber-700 hover:bg-amber-50"
            title={!settings.zapi_test_number ? 'Defina o número de teste primeiro' : ''}
          >
            <Send className="h-4 w-4" />
            {zapiSending ? 'Enviando...' : 'Enviar Mensagem de Teste'}
          </Button>

          <Button onClick={handleSave} disabled={saving} className="gap-2">
            {saving ? 'Salvando...' : 'Salvar Configurações Z-API'}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
