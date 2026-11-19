import { useEffect, useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';
import { useAppUsers } from '@/hooks/use-app-users';
import { Bell, BellOff, Send, Info, ShieldAlert } from 'lucide-react';
import { ErroAoCarregar } from '@/components/ErroAoCarregar';

const KEYS = {
  enabled: 'whatsapp_reminder_enabled',
  minutes: 'whatsapp_reminder_minutes',
  cooldown: 'whatsapp_reminder_cooldown_minutes',
  recipients: 'whatsapp_reminder_recipients',
};

export function WhatsAppReminderSettings() {
  // Padrão DESLIGADO, igual ao webhook (whatsapp-webhook só envia com 'true'): a tela mostrava
  // ligado quando a chave não existia, e o servidor tratava como desligado (19/11/2026).
  const [enabled, setEnabled] = useState(false);
  const [minutes, setMinutes] = useState('30');
  const [cooldown, setCooldown] = useState('60');
  const [recipients, setRecipients] = useState('');
  const [loading, setLoading] = useState(true);
  const [erroLeitura, setErroLeitura] = useState(false);
  const [tentativa, setTentativa] = useState(0);
  const [saving, setSaving] = useState(false);
  const [togglingKill, setTogglingKill] = useState(false);
  const [testing, setTesting] = useState(false);
  const { data: users = [] } = useAppUsers();

  useEffect(() => {
    (async () => {
      setLoading(true);
      const { data, error } = await supabase
        .from('app_settings')
        .select('key, value')
        .in('key', [KEYS.enabled, KEYS.minutes, KEYS.cooldown, KEYS.recipients]);
      setErroLeitura(!!error);
      if (error) { setLoading(false); return; }
      const map = Object.fromEntries((data || []).map((r: any) => [r.key, r.value]));
      setEnabled((map[KEYS.enabled] ?? 'false') === 'true');
      setMinutes(map[KEYS.minutes] || '30');
      setCooldown(map[KEYS.cooldown] || '60');
      setRecipients(map[KEYS.recipients] || '');
      setLoading(false);
    })();
  }, [tentativa]);

  const persistEnabled = async (next: boolean) => {
    setTogglingKill(true);
    try {
      const { error } = await supabase.from('app_settings').upsert(
        {
          key: KEYS.enabled,
          value: next ? 'true' : 'false',
          description: 'Liga/desliga globalmente o envio de lembretes WhatsApp.',
        },
        { onConflict: 'key' },
      );
      if (error) throw error;
      setEnabled(next);
      toast({
        title: next ? 'Lembretes ATIVADOS' : 'Lembretes DESATIVADOS',
        description: next
          ? 'O botão "Executar agora" e o aviso de número novo voltam a enviar.'
          : 'Nenhum lembrete será enviado até você reativar.',
        variant: next ? 'default' : 'destructive',
      });
    } catch (e: any) {
      toast({ title: 'Erro ao alterar status', description: e.message, variant: 'destructive' });
    } finally {
      setTogglingKill(false);
    }
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      const rows = [
        { key: KEYS.minutes, value: minutes, description: 'Minutos sem resposta para considerar conversa pendente.' },
        { key: KEYS.cooldown, value: cooldown, description: 'Intervalo mínimo entre lembretes para a mesma conversa.' },
        { key: KEYS.recipients, value: recipients, description: 'CSV de telefones (DDI+DDD+numero). Vazio = usa app_users admin/financial/manager com phone preenchido.' },
      ];
      for (const row of rows) {
        const { error } = await supabase.from('app_settings').upsert(row, { onConflict: 'key' });
        if (error) throw error;
      }
      toast({ title: 'Configurações salvas' });
    } catch (e: any) {
      toast({ title: 'Erro ao salvar', description: e.message, variant: 'destructive' });
    } finally {
      setSaving(false);
    }
  };

  const handleTest = async () => {
    setTesting(true);
    try {
      const { data, error } = await supabase.functions.invoke('whatsapp-unread-reminder', {
        body: { manual: true },
      });
      if (error) throw error;
      if (data?.disabled) {
        toast({
          title: 'Lembretes estão desativados',
          description: 'Reative o switch acima para que o teste envie mensagens.',
          variant: 'destructive',
        });
      } else {
        toast({
          title: 'Verificação executada',
          description: `${data?.pending ?? 0} conversa(s) pendente(s). Destinatários: ${data?.recipients ?? 0}.`,
        });
      }
    } catch (e: any) {
      toast({ title: 'Erro ao executar', description: e.message, variant: 'destructive' });
    } finally {
      setTesting(false);
    }
  };

  const usersWithPhone = users.filter((u: any) =>
    u.phone && ['admin', 'financial', 'manager'].includes(u.role)
  );

  if (loading) return <div className="text-sm text-muted-foreground">Carregando…</div>;
  if (erroLeitura) {
    return <ErroAoCarregar oQue="os lembretes de mensagens" onTentarDeNovo={() => setTentativa((n) => n + 1)} />;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Bell className="h-4 w-4" /> Lembretes de mensagens não respondidas
        </CardTitle>
        <CardDescription>
          {/* Não existe agendamento para whatsapp-unread-reminder: dizer "a cada 15 minutos" era
              prometer o que não roda (19/11/2026). */}
          O lembrete automático de conversas sem resposta <strong>não está agendado</strong>: hoje ele só
          roda quando você clica em <strong>Executar agora</strong>, que confere as conversas e envia o
          resumo na hora para os responsáveis.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Kill switch — destaque grande */}
        <div
          className={`rounded-lg border p-4 flex items-start gap-3 ${
            enabled
              ? 'border-primary/30 bg-primary/5'
              : 'border-destructive/40 bg-destructive/5'
          }`}
        >
          {enabled ? (
            <Bell className="h-5 w-5 text-primary mt-0.5" />
          ) : (
            <BellOff className="h-5 w-5 text-destructive mt-0.5" />
          )}
          <div className="flex-1">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-sm font-semibold">
                  {enabled ? 'Lembretes ativados' : 'Lembretes DESATIVADOS'}
                </p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  {enabled
                    ? 'Ligado: "Executar agora" envia o resumo, e um número novo que escrever gera um aviso na hora para os telefones da lista abaixo.'
                    : 'Nenhuma mensagem automática será enviada até você reativar este interruptor.'}
                </p>
              </div>
              <Switch
                checked={enabled}
                onCheckedChange={persistEnabled}
                disabled={togglingKill}
                aria-label="Ativar/desativar lembretes WhatsApp"
              />
            </div>
            {!enabled && (
              <Alert variant="destructive" className="mt-3">
                <ShieldAlert className="h-4 w-4" />
                <AlertTitle>Modo de proteção</AlertTitle>
                <AlertDescription className="text-xs">
                  Use esta opção se houve disparos em excesso ou se você suspeita de risco de
                  bloqueio pela Meta. Reative quando for seguro.
                </AlertDescription>
              </Alert>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label htmlFor="r-min">Tempo sem resposta (minutos)</Label>
            <Input
              id="r-min"
              type="number"
              min={5}
              value={minutes}
              onChange={(e) => setMinutes(e.target.value)}
              disabled={!enabled}
            />
            <p className="text-xs text-muted-foreground">
              Padrão: 30. Mensagens recebidas há mais que isso sem resposta entram no lembrete.
            </p>
          </div>
          <div className="space-y-2">
            <Label htmlFor="r-cd">Cooldown por conversa (minutos)</Label>
            <Input
              id="r-cd"
              type="number"
              min={5}
              value={cooldown}
              onChange={(e) => setCooldown(e.target.value)}
              disabled={!enabled}
            />
            <p className="text-xs text-muted-foreground">
              Padrão: 60. Evita reenvio do mesmo lembrete para a mesma conversa.
            </p>
          </div>
        </div>

        <div className="space-y-2">
          <Label htmlFor="r-rec">Destinatários (telefones, separados por vírgula)</Label>
          <Textarea
            id="r-rec"
            rows={2}
            placeholder="Ex.: 5511999999999, 5511888888888"
            value={recipients}
            onChange={(e) => setRecipients(e.target.value)}
            disabled={!enabled}
          />
          <p className="text-xs text-muted-foreground">
            Formato: DDI+DDD+número, sem espaços ou símbolos. Se vazio, o sistema usará
            automaticamente os usuários ativos com perfil <strong>admin</strong>,{' '}
            <strong>financeiro</strong> ou <strong>gerente</strong> que possuam telefone cadastrado.
          </p>
        </div>

        {!recipients && (
          <Alert>
            <Info className="h-4 w-4" />
            <AlertTitle>Destinatários automáticos detectados</AlertTitle>
            <AlertDescription>
              {usersWithPhone.length === 0 ? (
                <span className="text-destructive">
                  Nenhum usuário admin/financeiro/gerente com telefone cadastrado. Cadastre
                  telefones em <strong>Usuários</strong> ou preencha a lista acima.
                </span>
              ) : (
                <ul className="mt-1 text-xs space-y-0.5">
                  {usersWithPhone.map((u: any) => (
                    <li key={u.id}>
                      • {u.full_name} ({u.role}) — {u.phone}
                    </li>
                  ))}
                </ul>
              )}
            </AlertDescription>
          </Alert>
        )}

        <div className="flex flex-wrap gap-2 pt-2">
          <Button onClick={handleSave} disabled={saving || !enabled}>
            {saving ? 'Salvando…' : 'Salvar configurações'}
          </Button>
          <Button onClick={handleTest} disabled={testing} variant="outline">
            <Send className="h-4 w-4 mr-2" />
            {testing ? 'Executando…' : 'Executar agora'}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
