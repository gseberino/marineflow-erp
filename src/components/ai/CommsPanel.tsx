import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { MessageCircle, Reply, ShieldAlert, BellOff } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ScrollArea } from '@/components/ui/scroll-area';

// Painel "o que o agente mandou e o que voltou" — Camada de Inteligência de Comunicação.
// Lê ai_comms_log (tabela nova, fora dos types gerados → cast pontual).

interface CommsRow {
  created_at: string;
  tipo: string | null;
  audiencia: string | null;
  status: string | null;
  block_code: string | null;
  responded_at: string | null;
  reply_intent: string | null;
  message_preview: string | null;
}

const TIPO_LABEL: Record<string, string> = {
  cotacao: 'Cotação', cobranca: 'Cobrança', os_link: 'Orçamento/OS', follow_up: 'Follow-up',
};
const INTENT_LABEL: Record<string, string> = {
  disputa: 'Disputa', opt_out: 'Opt-out', acordo: 'Acordo', cotacao_parcial: 'Cotação parcial', pergunta: 'Pergunta', outro: 'Resposta',
};
const INTENT_VARIANT: Record<string, 'default' | 'secondary' | 'destructive' | 'outline'> = {
  disputa: 'destructive', opt_out: 'destructive', acordo: 'default', cotacao_parcial: 'secondary', pergunta: 'secondary', outro: 'outline',
};

function timeAgo(iso: string): string {
  const min = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (min < 1) return 'agora';
  if (min < 60) return `há ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `há ${h} h`;
  return `há ${Math.floor(h / 24)} d`;
}

export default function CommsPanel() {
  const since14d = useMemo(() => new Date(Date.now() - 14 * 864e5).toISOString(), []);

  const { data: rows = [], isLoading } = useQuery({
    queryKey: ['comms-log', since14d],
    queryFn: async (): Promise<CommsRow[]> => {
      // ai_comms_log ainda não está nos types gerados do Supabase.
      const { data, error } = await (supabase as unknown as {
        from: (t: string) => {
          select: (c: string) => {
            gte: (c: string, v: string) => { order: (c: string, o: { ascending: boolean }) => { limit: (n: number) => Promise<{ data: CommsRow[] | null; error: unknown }> } };
          };
        };
      })
        .from('ai_comms_log')
        .select('created_at, tipo, audiencia, status, block_code, responded_at, reply_intent, message_preview')
        .gte('created_at', since14d)
        .order('created_at', { ascending: false })
        .limit(500);
      if (error) throw error;
      return (data as CommsRow[]) || [];
    },
    staleTime: 30_000,
  });

  const stats = useMemo(() => {
    const enviados = rows.filter((r) => r.status === 'sent');
    const responderam = enviados.filter((r) => r.responded_at);
    const bloqueios = rows.filter((r) => r.status === 'blocked').length;
    let disputas = 0, optOuts = 0;
    for (const r of rows) {
      if (r.reply_intent === 'disputa') disputas++;
      if (r.reply_intent === 'opt_out') optOuts++;
    }
    const porTipo = new Map<string, { enviados: number; responderam: number }>();
    for (const r of enviados) {
      const t = r.tipo || '?';
      const b = porTipo.get(t) || { enviados: 0, responderam: 0 };
      b.enviados++; if (r.responded_at) b.responderam++;
      porTipo.set(t, b);
    }
    return {
      enviados: enviados.length,
      responderam: responderam.length,
      taxa: enviados.length ? Math.round((responderam.length / enviados.length) * 100) : 0,
      bloqueios, disputas, optOuts,
      porTipo: Array.from(porTipo.entries()),
    };
  }, [rows]);

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-base font-semibold">Comunicação</h2>
        <p className="text-sm text-muted-foreground">O que o agente mandou a clientes/fornecedores e o que voltou (últimos 14 dias).</p>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <Kpi icon={MessageCircle} label="Enviadas" value={String(stats.enviados)} sub="mensagens externas" />
        <Kpi icon={Reply} label="Taxa de resposta" value={`${stats.taxa}%`} sub={`${stats.responderam} responderam`} />
        <Kpi icon={ShieldAlert} label="Bloqueios" value={String(stats.bloqueios)} sub="portão de conformidade" />
        <Kpi icon={BellOff} label="Atrito" value={String(stats.disputas + stats.optOuts)} sub={`${stats.disputas} disputas · ${stats.optOuts} opt-outs`} />
      </div>

      <div className="grid lg:grid-cols-2 gap-4">
        {/* Desempenho por tipo */}
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Taxa de resposta por tipo</CardTitle></CardHeader>
          <CardContent>
            {stats.porTipo.length === 0 ? (
              <p className="text-sm text-muted-foreground py-6 text-center">Sem envios no período.</p>
            ) : (
              <div className="space-y-2">
                {stats.porTipo.map(([tipo, v]) => {
                  const pct = v.enviados ? Math.round((v.responderam / v.enviados) * 100) : 0;
                  return (
                    <div key={tipo} className="flex items-center gap-2 text-xs">
                      <span className="w-24 shrink-0 text-muted-foreground">{TIPO_LABEL[tipo] || tipo}</span>
                      <div className="flex-1 h-4 bg-muted rounded overflow-hidden">
                        <div className="h-full bg-primary/70" style={{ width: `${pct}%` }} />
                      </div>
                      <span className="w-20 shrink-0 text-right tabular-nums font-medium">{pct}% · {v.enviados}</span>
                    </div>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Últimas mensagens */}
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Últimas mensagens</CardTitle></CardHeader>
          <CardContent className="p-0">
            <ScrollArea className="max-h-[340px]">
              {isLoading ? (
                <p className="text-sm text-muted-foreground py-8 text-center">Carregando…</p>
              ) : rows.length === 0 ? (
                <p className="text-sm text-muted-foreground py-8 text-center">Nenhuma mensagem externa registrada ainda.</p>
              ) : (
                <ul className="divide-y">
                  {rows.slice(0, 40).map((r, i) => (
                    <li key={i} className="px-4 py-2.5 flex items-start gap-3">
                      <Badge variant="outline" className="text-[10px] shrink-0 mt-0.5">{TIPO_LABEL[r.tipo || ''] || r.tipo || '—'}</Badge>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm truncate">{r.message_preview || '—'}</p>
                        <div className="flex items-center gap-1.5 mt-0.5">
                          {r.status === 'blocked' && <Badge variant="destructive" className="text-[10px]">bloqueado{r.block_code ? `: ${r.block_code}` : ''}</Badge>}
                          {r.status === 'sent' && !r.responded_at && <span className="text-[11px] text-muted-foreground">enviada</span>}
                          {r.reply_intent && <Badge variant={INTENT_VARIANT[r.reply_intent] || 'outline'} className="text-[10px]">{INTENT_LABEL[r.reply_intent] || r.reply_intent}</Badge>}
                        </div>
                      </div>
                      <span className="text-[10px] text-muted-foreground shrink-0 mt-0.5">{timeAgo(r.created_at)}</span>
                    </li>
                  ))}
                </ul>
              )}
            </ScrollArea>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

function Kpi({ icon: Icon, label, value, sub }: { icon: typeof MessageCircle; label: string; value: string; sub: string }) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center gap-2 text-muted-foreground mb-1">
          <Icon className="h-4 w-4" />
          <span className="text-xs">{label}</span>
        </div>
        <p className="text-2xl font-semibold tabular-nums">{value}</p>
        <p className="text-[11px] text-muted-foreground mt-0.5">{sub}</p>
      </CardContent>
    </Card>
  );
}
