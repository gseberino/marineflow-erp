import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Bot, MessageSquare, Coins, Activity, Smartphone } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAppUsers } from '@/hooks/use-app-users';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ScrollArea } from '@/components/ui/scroll-area';
import CommsPanel from '@/components/ai/CommsPanel';

// Preços estimados por 1M tokens (US$) — OpenRouter cobra em créditos USD.
// Ajuste conforme a fatura real; cache_read costuma custar ~10% do input.
const PRICING: Record<string, { in: number; out: number; cache: number }> = {
  'anthropic/claude-sonnet-5': { in: 3, out: 15, cache: 0.3 },
  'anthropic/claude-haiku-4.5': { in: 1, out: 5, cache: 0.1 },
};
const DEFAULT_PRICE = { in: 3, out: 15, cache: 0.3 };

function costUSD(model: string | null, tin: number, tout: number, cache: number): number {
  const p = PRICING[model || ''] || DEFAULT_PRICE;
  return (tin / 1e6) * p.in + (tout / 1e6) * p.out + (cache / 1e6) * p.cache;
}

const nfInt = new Intl.NumberFormat('pt-BR');
const nfUSD = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 2 });
const dayKey = (iso: string) => new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });

function timeAgo(iso: string): string {
  const min = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (min < 1) return 'agora';
  if (min < 60) return `há ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `há ${h} h`;
  return `há ${Math.floor(h / 24)} d`;
}

interface MsgRow { created_at: string; tokens_in: number | null; tokens_out: number | null; cache_read_tokens: number | null; model: string | null; }
interface SessionRow { id: string; channel: string; owner_user_id: string | null; status: string | null; last_activity_at: string | null; external_thread_key: string | null; }
interface AuditRow { id: string; event_type: string | null; event_category: string | null; actor_kind: string | null; actor_user_id: string | null; created_at: string; session_id: string | null; payload: any; }

export default function AIActivityPage() {
  const since14d = useMemo(() => new Date(Date.now() - 14 * 864e5).toISOString(), []);
  const since7d = useMemo(() => Date.now() - 7 * 864e5, []);

  const { data: users } = useAppUsers();
  const nameById = useMemo(() => {
    const m = new Map<string, string>();
    (users || []).forEach((u) => m.set(u.id, u.full_name));
    return m;
  }, [users]);

  const { data: messages = [], isLoading: loadingMsgs } = useQuery({
    queryKey: ['ai-activity-messages', since14d],
    queryFn: async (): Promise<MsgRow[]> => {
      const { data, error } = await supabase
        .from('ai_operator_messages')
        .select('created_at, tokens_in, tokens_out, cache_read_tokens, model')
        .gte('created_at', since14d)
        .not('tokens_in', 'is', null)
        .order('created_at', { ascending: false })
        .limit(8000);
      if (error) throw error;
      return (data as MsgRow[]) || [];
    },
    staleTime: 60_000,
  });

  const { data: sessions = [] } = useQuery({
    queryKey: ['ai-activity-sessions'],
    queryFn: async (): Promise<SessionRow[]> => {
      const { data, error } = await supabase
        .from('ai_operator_sessions')
        .select('id, channel, owner_user_id, status, last_activity_at, external_thread_key')
        .eq('channel', 'whatsapp')
        .order('last_activity_at', { ascending: false })
        .limit(30);
      if (error) throw error;
      return (data as SessionRow[]) || [];
    },
    staleTime: 30_000,
  });

  const { data: audit = [] } = useQuery({
    queryKey: ['ai-activity-audit'],
    queryFn: async (): Promise<AuditRow[]> => {
      const { data, error } = await supabase
        .from('ai_operator_audit')
        .select('id, event_type, event_category, actor_kind, actor_user_id, created_at, session_id, payload')
        .order('created_at', { ascending: false })
        .limit(50);
      if (error) throw error;
      return (data as AuditRow[]) || [];
    },
    staleTime: 30_000,
  });

  // Agregações
  const stats = useMemo(() => {
    let tin7 = 0, tout7 = 0, cache7 = 0, cost7 = 0, msgs7 = 0;
    const byDay = new Map<string, { tin: number; tout: number; cache: number; cost: number }>();
    for (const m of messages) {
      const tin = m.tokens_in || 0, tout = m.tokens_out || 0, cache = m.cache_read_tokens || 0;
      const c = costUSD(m.model, tin, tout, cache);
      const k = dayKey(m.created_at);
      const b = byDay.get(k) || { tin: 0, tout: 0, cache: 0, cost: 0 };
      b.tin += tin; b.tout += tout; b.cache += cache; b.cost += c;
      byDay.set(k, b);
      if (new Date(m.created_at).getTime() >= since7d) { tin7 += tin; tout7 += tout; cache7 += cache; cost7 += c; msgs7 += 1; }
    }
    // ordena por data crescente (mantém a ordem de inserção reversa → reordena)
    const days = Array.from(byDay.entries()).reverse();
    const maxCost = Math.max(0.0001, ...days.map(([, v]) => v.cost));
    return { tin7, tout7, cache7, cost7, msgs7, days, maxCost };
  }, [messages, since7d]);

  const activeWhatsapp = sessions.filter((s) => s.status === 'active').length;

  return (
    <div className="p-4 sm:p-6 space-y-6 max-w-6xl mx-auto">
      <div className="flex items-center gap-3">
        <div className="h-10 w-10 rounded-lg bg-primary/10 text-primary flex items-center justify-center">
          <Bot className="h-5 w-5" />
        </div>
        <div>
          <h1 className="text-xl font-semibold">Atividade da IA</h1>
          <p className="text-sm text-muted-foreground">Uso, custo estimado e auditoria do funcionário IA (últimos 14 dias).</p>
        </div>
      </div>

      {/* KPIs 7 dias */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <KpiCard icon={MessageSquare} label="Interações (7 dias)" value={nfInt.format(stats.msgs7)} sub="respostas geradas" />
        <KpiCard icon={Coins} label="Custo estimado (7 dias)" value={nfUSD.format(stats.cost7)} sub="crédito OpenRouter" />
        <KpiCard icon={Activity} label="Tokens (7 dias)" value={nfInt.format(stats.tin7 + stats.tout7)} sub={`${nfInt.format(stats.cache7)} de cache`} />
        <KpiCard icon={Smartphone} label="Sessões WhatsApp ativas" value={String(activeWhatsapp)} sub={`${sessions.length} no total`} />
      </div>

      <div className="grid lg:grid-cols-2 gap-4">
        {/* Custo por dia */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Custo estimado por dia</CardTitle>
          </CardHeader>
          <CardContent>
            {loadingMsgs ? (
              <p className="text-sm text-muted-foreground py-6 text-center">Carregando…</p>
            ) : stats.days.length === 0 ? (
              <p className="text-sm text-muted-foreground py-6 text-center">Sem uso registrado no período.</p>
            ) : (
              <div className="space-y-1.5">
                {stats.days.map(([day, v]) => (
                  <div key={day} className="flex items-center gap-2 text-xs">
                    <span className="w-12 shrink-0 text-muted-foreground tabular-nums">{day}</span>
                    <div className="flex-1 h-4 bg-muted rounded overflow-hidden">
                      <div className="h-full bg-primary/70" style={{ width: `${Math.round((v.cost / stats.maxCost) * 100)}%` }} />
                    </div>
                    <span className="w-16 shrink-0 text-right tabular-nums font-medium">{nfUSD.format(v.cost)}</span>
                  </div>
                ))}
              </div>
            )}
            <p className="text-[10px] text-muted-foreground mt-3">
              Estimativa: Sonnet ~US$3/US$15 e Haiku ~US$1/US$5 por 1M tokens (entrada/saída); cache a ~10% da entrada. Confira a fatura do OpenRouter para o valor exato.
            </p>
          </CardContent>
        </Card>

        {/* Sessões WhatsApp */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Sessões WhatsApp</CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <ScrollArea className="max-h-[320px]">
              {sessions.length === 0 ? (
                <p className="text-sm text-muted-foreground py-8 text-center">Nenhuma sessão de WhatsApp ainda.</p>
              ) : (
                <ul className="divide-y">
                  {sessions.map((s) => (
                    <li key={s.id} className="px-4 py-2.5 flex items-center justify-between gap-2">
                      <div className="min-w-0">
                        <p className="text-sm font-medium truncate">
                          {(s.owner_user_id && nameById.get(s.owner_user_id)) || s.external_thread_key || 'Sessão'}
                        </p>
                        <p className="text-[11px] text-muted-foreground">
                          {s.last_activity_at ? timeAgo(s.last_activity_at) : '—'}
                        </p>
                      </div>
                      <Badge variant={s.status === 'active' ? 'default' : 'secondary'} className="text-[10px] shrink-0">
                        {s.status || '—'}
                      </Badge>
                    </li>
                  ))}
                </ul>
              )}
            </ScrollArea>
          </CardContent>
        </Card>
      </div>

      {/* Comunicação (Camada de Inteligência de Comunicação) */}
      <CommsPanel />

      {/* Auditoria */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Auditoria recente</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <ScrollArea className="max-h-[420px]">
            {audit.length === 0 ? (
              <p className="text-sm text-muted-foreground py-8 text-center">Sem eventos de auditoria.</p>
            ) : (
              <ul className="divide-y">
                {audit.map((a) => (
                  <li key={a.id} className="px-4 py-2.5 flex items-start gap-3">
                    <Badge variant="outline" className="text-[10px] shrink-0 mt-0.5">{a.event_category || a.actor_kind || 'evento'}</Badge>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm">
                        <span className="font-medium">{a.event_type || '—'}</span>
                        {a.actor_user_id && nameById.get(a.actor_user_id) && (
                          <span className="text-muted-foreground"> · {nameById.get(a.actor_user_id)}</span>
                        )}
                      </p>
                      {a.payload?.tool_name && (
                        <p className="text-[11px] text-muted-foreground truncate">{String(a.payload.tool_name)}</p>
                      )}
                    </div>
                    <span className="text-[10px] text-muted-foreground shrink-0 mt-0.5">{timeAgo(a.created_at)}</span>
                  </li>
                ))}
              </ul>
            )}
          </ScrollArea>
        </CardContent>
      </Card>
    </div>
  );
}

function KpiCard({ icon: Icon, label, value, sub }: { icon: typeof Bot; label: string; value: string; sub: string }) {
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
