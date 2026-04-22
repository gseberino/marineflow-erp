import { useEffect, useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { toast } from '@/hooks/use-toast';
import { Activity, CheckCircle2, AlertTriangle, XCircle, Copy, RefreshCw } from 'lucide-react';

type HealthStatus = 'ok' | 'stale' | 'never';

type HealthData = {
  webhook_url: string;
  health_status: HealthStatus;
  total_inbound: number;
  last_24h: number;
  last_message_at: string | null;
  minutes_since_last: number | null;
  last_message_preview: { phone: string; body: string; is_broadcast: boolean } | null;
  recent_messages: Array<{ at: string; phone: string; type: string; body: string; is_broadcast: boolean }>;
  checked_at: string;
};

const WEBHOOK_URL = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/whatsapp-webhook`;

export function WhatsAppWebhookValidator() {
  const [loading, setLoading] = useState(false);
  const [data, setData] = useState<HealthData | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(false);

  const check = async () => {
    setLoading(true);
    try {
      const res = await fetch(`${WEBHOOK_URL}?healthcheck=1`, { method: 'GET' });
      const json = await res.json();
      if (!res.ok) throw new Error(json?.error || 'Falha no healthcheck');
      setData(json);
    } catch (e: any) {
      toast({ title: 'Erro ao validar webhook', description: e.message, variant: 'destructive' });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    check();
  }, []);

  useEffect(() => {
    if (!autoRefresh) return;
    const id = setInterval(check, 5000);
    return () => clearInterval(id);
  }, [autoRefresh]);

  const copyUrl = async () => {
    await navigator.clipboard.writeText(WEBHOOK_URL);
    toast({ title: 'URL copiada', description: 'Cole no painel da Z-API em "On Message Received".' });
  };

  const statusBadge = (s: HealthStatus | undefined) => {
    if (s === 'ok') return <Badge className="bg-primary text-primary-foreground"><CheckCircle2 className="h-3 w-3 mr-1" /> Ativo</Badge>;
    if (s === 'stale') return <Badge variant="secondary"><AlertTriangle className="h-3 w-3 mr-1" /> Sem tráfego recente</Badge>;
    return <Badge variant="destructive"><XCircle className="h-3 w-3 mr-1" /> Nunca recebeu</Badge>;
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Activity className="h-4 w-4" /> Validação do Webhook Z-API
        </CardTitle>
        <CardDescription>
          Verifique se mensagens estão chegando ao sistema. Use o monitoramento ao vivo enquanto envia
          uma mensagem de teste para o número conectado à Z-API.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2">
          <div className="text-xs font-medium text-muted-foreground">URL do Webhook (cole na Z-API)</div>
          <div className="flex gap-2">
            <code className="flex-1 text-xs bg-muted px-3 py-2 rounded border break-all">{WEBHOOK_URL}</code>
            <Button size="sm" variant="outline" onClick={copyUrl}>
              <Copy className="h-3 w-3 mr-1" /> Copiar
            </Button>
          </div>
        </div>

        <div className="flex flex-wrap gap-2">
          <Button onClick={check} disabled={loading}>
            <RefreshCw className={`h-4 w-4 mr-2 ${loading ? 'animate-spin' : ''}`} />
            {loading ? 'Validando…' : 'Validar webhook agora'}
          </Button>
          <Button
            variant={autoRefresh ? 'default' : 'outline'}
            onClick={() => setAutoRefresh((v) => !v)}
          >
            {autoRefresh ? '⏸ Parar monitoramento' : '▶ Monitorar ao vivo (5s)'}
          </Button>
        </div>

        {data && (
          <>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              <div className="border rounded p-3">
                <div className="text-xs text-muted-foreground">Status</div>
                <div className="mt-1">{statusBadge(data.health_status)}</div>
              </div>
              <div className="border rounded p-3">
                <div className="text-xs text-muted-foreground">Total recebidas</div>
                <div className="text-lg font-semibold">{data.total_inbound}</div>
              </div>
              <div className="border rounded p-3">
                <div className="text-xs text-muted-foreground">Últimas 24h</div>
                <div className="text-lg font-semibold">{data.last_24h}</div>
              </div>
              <div className="border rounded p-3">
                <div className="text-xs text-muted-foreground">Última mensagem</div>
                <div className="text-sm font-medium">
                  {data.minutes_since_last == null
                    ? '—'
                    : data.minutes_since_last < 1
                    ? 'Agora mesmo'
                    : data.minutes_since_last < 60
                    ? `há ${data.minutes_since_last} min`
                    : `há ${Math.floor(data.minutes_since_last / 60)}h`}
                </div>
              </div>
            </div>

            {data.health_status === 'never' && (
              <Alert variant="destructive">
                <XCircle className="h-4 w-4" />
                <AlertTitle>Nenhuma mensagem recebida</AlertTitle>
                <AlertDescription>
                  O webhook não recebeu tráfego ainda. No painel da Z-API, vá em{' '}
                  <strong>Webhooks → Ao receber</strong> e cole a URL acima. Em seguida, envie uma
                  mensagem de teste do seu celular pessoal para o número conectado à Z-API e clique
                  em "Validar webhook agora".
                </AlertDescription>
              </Alert>
            )}

            {data.health_status === 'stale' && (
              <Alert>
                <AlertTriangle className="h-4 w-4" />
                <AlertTitle>Sem tráfego recente</AlertTitle>
                <AlertDescription>
                  Última mensagem há mais de 1h. Pode ser normal se ninguém enviou nada — mas se você
                  acabou de enviar e não chegou, verifique se a URL no painel Z-API está correta.
                </AlertDescription>
              </Alert>
            )}

            {data.recent_messages.length > 0 && (
              <div className="space-y-2">
                <div className="text-xs font-medium text-muted-foreground">
                  Últimas 5 mensagens recebidas
                </div>
                <div className="border rounded divide-y">
                  {data.recent_messages.map((m, i) => (
                    <div key={i} className="p-2 text-xs flex gap-2 items-start">
                      <div className="text-muted-foreground whitespace-nowrap">
                        {new Date(m.at).toLocaleTimeString('pt-BR')}
                      </div>
                      <div className="font-mono">+{m.phone}</div>
                      {m.is_broadcast && <Badge variant="outline" className="h-4 text-[10px]">broadcast</Badge>}
                      <div className="flex-1 truncate text-muted-foreground">{m.body}</div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            <p className="text-[10px] text-muted-foreground">
              Verificado em {new Date(data.checked_at).toLocaleString('pt-BR')}
            </p>
          </>
        )}
      </CardContent>
    </Card>
  );
}
