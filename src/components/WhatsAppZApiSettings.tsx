import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Shield, MessageSquare, AlertCircle, Send } from 'lucide-react';
import { useZApiSend } from '@/hooks/use-zapi-send';

export function WhatsAppZApiSettings() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [settings, setSettings] = useState({
    zapi_instance_id: '',
    zapi_token: '',
    zapi_client_token: '',
    zapi_test_mode: 'false',
    zapi_test_number: '',
  });

  const { send, sending: zapiSending } = useZApiSend();

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
    if (!settings.zapi_test_number) {
      toast.error('Informe o número de teste primeiro');
      return;
    }
    const ok = await send({
      phone: settings.zapi_test_number,
      message: '🚀 MarineFlow: Teste de integração Z-API realizado com sucesso!',
      mode: 'link',
      context: 'test',
      publicUrl: 'https://hbrmarine.online',
      link_title: 'MarineFlow ERP',
      link_description: 'Sistema de Gestão Náutica'
    }, { autoRetry: false, maxAttempts: 1 });
    
    if (ok) toast.success('Mensagem de teste enviada!');
  };

  if (loading) return null;

  return (
    <Card className="max-w-2xl border-primary/20 shadow-sm">
      <CardHeader>
        <CardTitle className="text-lg flex items-center gap-2">
          <Shield className="h-5 w-5 text-primary" /> Credenciais Z-API
        </CardTitle>
        <CardDescription>
          Configure aqui os tokens da sua conta Z-API para habilitar o envio automático.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
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
            <Input
              id="zapi_token"
              value={settings.zapi_token}
              onChange={e => setSettings(p => ({ ...p, zapi_token: e.target.value }))}
              placeholder="Ex: 50..."
              type="password"
            />
          </div>
          <div className="space-y-2 col-span-2">
            <Label htmlFor="zapi_client_token">Client Token (Segurança Adicional)</Label>
            <Input
              id="zapi_client_token"
              value={settings.zapi_client_token}
              onChange={e => setSettings(p => ({ ...p, zapi_client_token: e.target.value }))}
              placeholder="Ex: F..."
              type="password"
            />
          </div>
        </div>

        <div className="pt-4 border-t space-y-4">
          <div className="flex items-center justify-between">
            <div className="space-y-0.5">
              <Label className="text-base flex items-center gap-2">
                <AlertCircle className="h-4 w-4 text-amber-500" /> Modo de Teste / Redirecionamento
              </Label>
              <p className="text-sm text-muted-foreground">
                Quando ativo, TODAS as mensagens enviadas pelo sistema serão redirecionadas para o número abaixo.
              </p>
            </div>
            <Switch
              checked={settings.zapi_test_mode === 'true'}
              onCheckedChange={v => setSettings(p => ({ ...p, zapi_test_mode: String(v) }))}
            />
          </div>
          
          <div className="space-y-2">
            <Label htmlFor="zapi_test_number">Número de Teste (WhatsApp pessoal)</Label>
            <Input
              id="zapi_test_number"
              value={settings.zapi_test_number}
              onChange={e => setSettings(p => ({ ...p, zapi_test_number: e.target.value }))}
              placeholder="5547999159654"
              className={settings.zapi_test_mode === 'true' ? 'border-amber-300 bg-amber-50/50' : ''}
            />
            <p className="text-[10px] text-muted-foreground">
              Formato: DDI + DDD + Número (ex: 554799999999). Atualmente configurado para: <strong>{settings.zapi_test_number || 'Não definido'}</strong>
            </p>
          </div>
        </div>

        <div className="flex justify-between items-center pt-2">
          <Button 
            variant="outline" 
            onClick={handleSendTest} 
            disabled={zapiSending || saving} 
            className="gap-2 border-amber-200 text-amber-700 hover:bg-amber-50"
          >
            <Send className="h-4 w-4" /> Enviar Mensagem de Teste
          </Button>

          <Button onClick={handleSave} disabled={saving} className="gap-2">
            {saving ? 'Salvando...' : 'Salvar Configurações Z-API'}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
