// Painel "IA acompanhando" — as missões do "Deixar a IA acompanhar" (Fase 1, copiloto).
//
// O que o dono precisa ver aqui: quem a IA está cobrando, sobre o quê, quantos toques já
// saíram e o que aconteceu (trilha). A aprovação de cada mensagem continua no sino de
// pendências, que é o portão único de tudo que a IA faz em nome da empresa.
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Bot, ChevronDown, ChevronUp, Loader2, Power } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { Skeleton } from '@/components/ui/skeleton';
import { PageShell } from '@/v2/components/PageShell';
import { StatusChip, type StatusTone } from '@/v2/components/StatusChip';
import { EntityCard } from '@/v2/components/EntityCard';
import { V2Shell } from '@/v2/components/V2Shell';
import {
  EVENTO_LABEL, STATUS_LABEL,
  useCancelFollowupMission, useFollowupEvents, useFollowupMissions, useFollowupSwitch,
  type FollowupMission, type FollowupMissionStatus,
} from '@/hooks/use-followup-missions';
import '@/v2/tokens.css';

const TONE: Record<FollowupMissionStatus, StatusTone> = {
  active: 'info',
  waiting_reply: 'warning',
  escalated: 'critical',
  resolved: 'success',
  cancelled: 'neutral',
  expired: 'neutral',
};

const fmtData = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) : '—';
const fmtDataHora = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—';

function Trilha({ missionId }: { missionId: string }) {
  const { data: eventos = [], isLoading } = useFollowupEvents(missionId);
  if (isLoading) return <Skeleton className="h-16 w-full" />;
  if (!eventos.length) return <p className="text-sm text-muted-foreground">Sem eventos ainda.</p>;
  return (
    <ol className="space-y-2 border-l pl-3">
      {eventos.map((e) => (
        <li key={e.id} className="text-sm">
          <div className="flex flex-wrap items-baseline gap-x-2">
            <span className="font-medium">{EVENTO_LABEL[e.tipo] ?? e.tipo}</span>
            <span className="text-xs text-muted-foreground">{fmtDataHora(e.created_at)}</span>
          </div>
          {e.conteudo && (
            <p className="mt-0.5 whitespace-pre-wrap rounded bg-muted/50 px-2 py-1 text-[13px]">{e.conteudo}</p>
          )}
          {e.evidencia && <p className="text-xs text-muted-foreground">Evidência: {e.evidencia}</p>}
        </li>
      ))}
    </ol>
  );
}

function CartaoMissao({ m }: { m: FollowupMission }) {
  const [aberta, setAberta] = useState(m.status === 'waiting_reply' || m.status === 'escalated');
  const cancelar = useCancelFollowupMission();
  const emAndamento = m.status === 'active' || m.status === 'waiting_reply' || m.status === 'escalated';

  async function encerrar() {
    if (!window.confirm(`Encerrar o acompanhamento de ${m.contraparte_label}? A IA para de cobrar.`)) return;
    try {
      await cancelar.mutateAsync({ id: m.id, motivo: 'encerrada pelo dono no painel' });
      toast.success('Acompanhamento encerrado.');
    } catch (e: any) {
      toast.error(e?.message || 'Não deu para encerrar.');
    }
  }

  const linhas = [
    `${m.contraparte_tipo === 'supplier' ? 'Fornecedor' : m.contraparte_tipo === 'client' ? 'Cliente' : 'Contato'} · ${m.contraparte_phone}`,
    m.status === 'active'
      ? `Toques ${m.toques_feitos}/${m.max_toques} · próximo ${m.proximo_toque_em ? fmtDataHora(m.proximo_toque_em) : 'aguardando sua aprovação'}${m.prazo_final ? ` · prazo ${fmtData(m.prazo_final)}` : ''}`
      : m.resolucao
        ? `${m.resolucao}${m.resolucao_evidencia ? ` — ${m.resolucao_evidencia}` : ''}`
        : `Toques ${m.toques_feitos}/${m.max_toques}`,
  ];

  return (
    <div className="space-y-2">
      <EntityCard
        id={m.contraparte_label}
        badge={<StatusChip tone={TONE[m.status]} dot>{STATUS_LABEL[m.status]}</StatusChip>}
        title={m.objetivo}
        lines={linhas}
        severity={TONE[m.status]}
        actions={
          <>
            <Button size="sm" variant="ghost" onClick={() => setAberta((v) => !v)} aria-expanded={aberta}>
              {aberta ? <ChevronUp className="mr-1 h-4 w-4" /> : <ChevronDown className="mr-1 h-4 w-4" />} Trilha
            </Button>
            {m.service_order_id && (
              <Button asChild size="sm" variant="ghost">
                <Link to={`/v2/service-orders/${m.service_order_id}`}>Abrir OS</Link>
              </Button>
            )}
            {emAndamento && (
              <Button size="sm" variant="outline" onClick={encerrar} disabled={cancelar.isPending}>
                {cancelar.isPending && <Loader2 className="mr-1 h-4 w-4 animate-spin" />} Encerrar
              </Button>
            )}
          </>
        }
      />
      {/* A trilha fica fora do cartão: o EntityCard é o resumo de decisão, não um acordeão. */}
      {aberta && (
        <div className="rounded-lg border bg-card p-3 shadow-sm">
          <Trilha missionId={m.id} />
        </div>
      )}
    </div>
  );
}

export default function FollowupMissionsV2() {
  const [filtro, setFiltro] = useState<'andamento' | 'encerradas'>('andamento');
  const { data: missoes = [], isLoading, error } = useFollowupMissions(filtro);
  const sw = useFollowupSwitch();

  return (
    <V2Shell>
      <PageShell
        breadcrumb={[{ label: 'Agenda', to: '/v2/agenda' }, { label: 'IA acompanhando' }]}
        title="IA acompanhando"
        count={missoes.length}
        description="Compromissos que a IA está cobrando de fornecedores e clientes. Cada mensagem passa pela sua aprovação no sino."
        actions={
          <label className="flex items-center gap-2 text-sm">
            <Power className={sw.ligado ? 'h-4 w-4 text-success' : 'h-4 w-4 text-muted-foreground'} />
            <span>{sw.ligado ? 'Ligado' : 'Desligado'}</span>
            <Switch
              checked={sw.ligado}
              disabled={sw.isLoading || sw.isPending}
              onCheckedChange={async (v) => {
                try { await sw.alternar(v); toast.success(v ? 'Acompanhamento pela IA ligado.' : 'Acompanhamento pela IA desligado — nenhum toque novo sai.'); }
                catch (e: any) { toast.error(e?.message || 'Não deu para alterar.'); }
              }}
              aria-label="Acompanhamento pela IA"
            />
          </label>
        }
      >
        <div className="flex flex-wrap items-center gap-1">
          <Button size="sm" variant={filtro === 'andamento' ? 'default' : 'ghost'} onClick={() => setFiltro('andamento')}>Em andamento</Button>
          <Button size="sm" variant={filtro === 'encerradas' ? 'default' : 'ghost'} onClick={() => setFiltro('encerradas')}>Encerradas</Button>
        </div>

        {error && <p className="text-sm text-destructive">Não deu para carregar as missões: {(error as Error).message}</p>}
        {isLoading && <div className="space-y-2"><Skeleton className="h-24 w-full" /><Skeleton className="h-24 w-full" /></div>}
        {!isLoading && !error && missoes.length === 0 && (
          <div className="rounded-lg border border-dashed p-6 text-center text-sm text-muted-foreground">
            <Bot className="mx-auto mb-2 h-6 w-6" />
            {filtro === 'andamento'
              ? 'Nenhuma missão em andamento. Abra uma tarefa da agenda ou um orçamento e clique em "Deixar a IA acompanhar".'
              : 'Nenhuma missão encerrada ainda.'}
          </div>
        )}
        <div className="grid gap-3 md:grid-cols-2">
          {missoes.map((m) => <CartaoMissao key={m.id} m={m} />)}
        </div>
      </PageShell>
    </V2Shell>
  );
}
