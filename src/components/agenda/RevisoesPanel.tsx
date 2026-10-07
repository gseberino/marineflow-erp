/**
 * Aba "Revisões" da Agenda (07/10/2026): todos os planos de manutenção, do ponto de vista de quem
 * vende o serviço — o que vence nos próximos 30 dias, o que já venceu, o que o cliente pediu para
 * adiar e quem respondeu ao lembrete. A receita prevista no topo é a soma do valor estimado do que
 * vence em 30 dias com o que já venceu: o dinheiro que está na mesa.
 *
 * Fonte única: v_maintenance_plans_due (o banco calcula vencimento e situação). Sem tabela larga:
 * cada plano é um cartão que empilha no celular — nada de rolagem lateral.
 */
import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Anchor, CalendarClock, CheckCircle2, Loader2, MessageCircle, MessageSquareReply } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { AcoesDaLinha } from '@/components/AcoesDaLinha';
import { useRevisoes } from '@/hooks/use-planos-manutencao';
import {
  CLASSE_DA_SITUACAO, ROTULO_DA_SITUACAO, agruparRevisoes, dataBR, prazoPorExtenso, type PlanoNaView,
} from '@/lib/planos-manutencao';
import {
  AdiarPlanoDialog, PedirLembreteDialog, RegistrarServicoDialog, type AlvoDoLembrete, type AlvoDoPlano,
} from '@/components/agenda/PlanoDialogs';

type Recorte = 'vencendo' | 'vencidas' | 'adiadas' | 'responderam';

const RECORTES: { id: Recorte; texto: string; vazio: string }[] = [
  { id: 'vencendo', texto: 'Vencendo em 30 dias', vazio: 'Nenhuma revisão vence nos próximos 30 dias.' },
  { id: 'vencidas', texto: 'Vencidas', vazio: 'Nenhuma revisão vencida.' },
  { id: 'adiadas', texto: 'Adiadas', vazio: 'Nenhum plano adiado.' },
  { id: 'responderam', texto: 'Responderam', vazio: 'Nenhum cliente respondeu a lembrete neste ciclo.' },
];

const moeda = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

function CartaoDaRevisao({
  r, onServico, onAdiar, onLembrete,
}: {
  r: PlanoNaView;
  onServico: (a: AlvoDoPlano) => void;
  onAdiar: (a: AlvoDoPlano) => void;
  onLembrete: (a: AlvoDoLembrete) => void;
}) {
  const navigate = useNavigate();
  const embarcacao = r.vessel_name ?? 'Embarcação';
  const alvo: AlvoDoPlano = { planId: r.plan_id, rotulo: `${r.name} — ${embarcacao}` };
  const valor = r.estimated_value != null ? Number(r.estimated_value) : null;
  return (
    <div className="flex items-start gap-2 rounded-md border bg-card p-3">
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium leading-snug break-words">
          {embarcacao} <span className="font-normal text-muted-foreground">· {r.name}</span>
        </p>
        <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted-foreground">
          <span className={cn('rounded px-1.5 py-0.5 font-medium', CLASSE_DA_SITUACAO[r.situacao])}>
            {ROTULO_DA_SITUACAO[r.situacao]}
          </span>
          <span className={r.situacao === 'vencida' ? 'font-medium text-destructive' : ''}>
            {dataBR(r.next_due_on)} · {prazoPorExtenso(r.dias_para_vencer)}
          </span>
          {r.situacao === 'adiada' && r.snoozed_until && <span>· até {dataBR(r.snoozed_until)}</span>}
          {r.client_name && <span>· {r.client_name}</span>}
          {valor != null && <span className="font-medium text-foreground/80">· {moeda(valor)}</span>}
        </div>
        <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[11px]">
          {r.tem_os_agendada && <span className="rounded bg-emerald-500/15 px-1.5 py-0.5 text-emerald-700 dark:text-emerald-400">OS agendada</span>}
          {r.respondeu_no_ciclo && (
            <span className="inline-flex items-center gap-1 rounded bg-primary/10 px-1.5 py-0.5 text-primary">
              <MessageSquareReply className="h-3 w-3" /> cliente respondeu
            </span>
          )}
          {!!r.ultimo_toque && !r.respondeu_no_ciclo && (
            <span className="rounded bg-muted px-1.5 py-0.5 text-muted-foreground">{r.ultimo_toque}º lembrete enviado</span>
          )}
          {r.opt_out && <span className="rounded bg-destructive/10 px-1.5 py-0.5 text-destructive">pediu para não receber</span>}
        </div>
      </div>
      <AcoesDaLinha
        rotulo={`revisão ${r.name} de ${embarcacao}`}
        rapidas={[{ texto: 'Serviço feito', icone: CheckCircle2, onClick: () => onServico(alvo) }]}
        menu={[
          { texto: 'Adiar', icone: CalendarClock, onClick: () => onAdiar(alvo) },
          { texto: 'Abrir embarcação', icone: Anchor, onClick: () => navigate(`/v2/vessels/${r.vessel_id}?tab=maintenance`) },
          {
            texto: 'Pedir lembrete agora', icone: MessageCircle,
            onClick: () => onLembrete({
              ...alvo, plano: r.name, embarcacao, cliente: r.client_name, vesselId: r.vessel_id,
              optOut: r.opt_out, semTelefone: !r.client_phone,
            }),
          },
        ]}
      />
    </div>
  );
}

export function RevisoesPanel() {
  const { data: linhas = [], isLoading, error, refetch } = useRevisoes();
  const [recorte, setRecorte] = useState<Recorte>('vencendo');
  const [servico, setServico] = useState<AlvoDoPlano | null>(null);
  const [adiar, setAdiar] = useState<AlvoDoPlano | null>(null);
  const [lembrete, setLembrete] = useState<AlvoDoLembrete | null>(null);
  const grupos = useMemo(() => agruparRevisoes(linhas), [linhas]);

  if (error) {
    return (
      <div className="py-8 text-center text-sm text-destructive space-y-2">
        <p>Não deu para ler as revisões: {(error as Error).message}</p>
        <Button size="sm" variant="outline" onClick={() => refetch()}>Tentar de novo</Button>
      </div>
    );
  }
  if (isLoading) {
    return <div className="flex justify-center py-12 text-muted-foreground"><Loader2 className="h-5 w-5 animate-spin" /></div>;
  }

  const lista = grupos[recorte];
  const atual = RECORTES.find((r) => r.id === recorte)!;

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <div className="rounded-md border p-2.5">
          <p className="text-[11px] text-muted-foreground">Receita prevista</p>
          <p className="text-base font-semibold" data-testid="receita-prevista">{moeda(grupos.receitaPrevista)}</p>
          <p className="text-[10px] text-muted-foreground">30 dias + vencidas</p>
        </div>
        <div className="rounded-md border p-2.5">
          <p className="text-[11px] text-muted-foreground">Vencendo em 30 dias</p>
          <p className="text-base font-semibold">{grupos.vencendo.length}</p>
        </div>
        <div className="rounded-md border p-2.5">
          <p className="text-[11px] text-muted-foreground">Vencidas</p>
          <p className={cn('text-base font-semibold', grupos.vencidas.length > 0 && 'text-destructive')}>{grupos.vencidas.length}</p>
        </div>
        <div className="rounded-md border p-2.5">
          <p className="text-[11px] text-muted-foreground">Responderam</p>
          <p className="text-base font-semibold">{grupos.responderam.length}</p>
        </div>
      </div>

      {/* flex-wrap: quatro recortes não podem estourar a largura do celular. */}
      <div className="flex flex-wrap gap-1">
        {RECORTES.map((r) => (
          <Button key={r.id} size="sm" variant={recorte === r.id ? 'default' : 'outline'} onClick={() => setRecorte(r.id)}>
            {r.texto} ({grupos[r.id].length})
          </Button>
        ))}
      </div>

      {linhas.length === 0 ? (
        <p className="py-6 text-center text-sm text-muted-foreground">
          Nenhum plano de manutenção ativo. Crie na aba Manutenção de cada embarcação (ou peça ao assistente
          "sugira planos de manutenção").
        </p>
      ) : lista.length === 0 ? (
        <p className="py-6 text-center text-sm text-muted-foreground">{atual.vazio}</p>
      ) : (
        <div className="space-y-2">
          {lista.map((r) => (
            <CartaoDaRevisao key={r.plan_id} r={r} onServico={setServico} onAdiar={setAdiar} onLembrete={setLembrete} />
          ))}
        </div>
      )}

      <RegistrarServicoDialog alvo={servico} onOpenChange={(v) => { if (!v) setServico(null); }} />
      <AdiarPlanoDialog alvo={adiar} onOpenChange={(v) => { if (!v) setAdiar(null); }} />
      <PedirLembreteDialog alvo={lembrete} onOpenChange={(v) => { if (!v) setLembrete(null); }} />
    </div>
  );
}
