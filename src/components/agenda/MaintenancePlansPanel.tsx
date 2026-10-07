import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import {
  Wrench, Plus, Loader2, CheckCircle2, CalendarClock, Pencil, History, Power, Trash2, Sparkles, MessageCircle,
} from 'lucide-react';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';
import { AcoesDaLinha } from '@/components/AcoesDaLinha';
import { useConfirmacao } from '@/components/Confirmacao';
import { SYSTEM_LABEL, VERB_LABEL } from '@/hooks/use-step-blocks';
import { SISTEMAS, VERBOS } from '@/hooks/use-service-classification';
import {
  useApagarPlano, useEventosDoPlano, useHistoricoDaEmbarcacao, useLigarPlano, usePlanosDaEmbarcacao, useSalvarPlano,
  type PlanoInput,
} from '@/hooks/use-planos-manutencao';
import {
  CLASSE_DA_SITUACAO, ROTULO_DA_SITUACAO, ROTULO_DO_EVENTO, dataBR, lerPalavras, prazoPorExtenso, sugerirPlanos,
  type PlanoDeManutencao, type SugestaoDePlano,
} from '@/lib/planos-manutencao';
import {
  AdiarPlanoDialog, PedirLembreteDialog, RegistrarServicoDialog, type AlvoDoLembrete, type AlvoDoPlano,
} from '@/components/agenda/PlanoDialogs';

const QUALQUER = '__qualquer__';
const moeda = (v: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(v);

interface Formulario {
  name: string;
  months: string;
  value: string;
  scope: string;
  lastAt: string;
  advance: string;
  sistema: string;
  verbo: string;
  palavras: string;
  lembrete: boolean;
  source: 'manual' | 'sugerido';
}

const VAZIO: Formulario = {
  name: '', months: '12', value: '', scope: '', lastAt: '', advance: '14',
  sistema: QUALQUER, verbo: QUALQUER, palavras: '', lembrete: true, source: 'manual',
};

function doPlano(p: PlanoDeManutencao): Formulario {
  return {
    name: p.name, months: String(p.interval_months), value: p.estimated_value != null ? String(p.estimated_value) : '',
    scope: p.scope ?? '', lastAt: p.last_service_at ?? '', advance: String(p.advance_days ?? 14),
    sistema: p.service_system ?? QUALQUER, verbo: p.service_verb ?? QUALQUER,
    palavras: (p.match_keywords ?? []).join(', '), lembrete: p.client_reminder_enabled !== false, source: p.source ?? 'manual',
  };
}

function daSugestao(s: SugestaoDePlano): Formulario {
  return {
    ...VAZIO,
    name: s.familia.nome, months: String(s.familia.intervaloMeses),
    value: s.valorEstimado != null ? String(s.valorEstimado) : '', scope: s.familia.escopo,
    lastAt: s.ultimoServico, sistema: s.familia.sistema ?? QUALQUER, palavras: s.familia.palavras.join(', '),
    source: 'sugerido',
  };
}

function paraInput(f: Formulario): PlanoInput {
  return {
    name: f.name.trim(),
    interval_months: Math.min(60, Math.max(1, Number(f.months) || 12)),
    estimated_value: f.value ? Number(f.value) : null,
    scope: f.scope.trim() || null,
    advance_days: Math.min(90, Math.max(0, Number(f.advance) || 0)),
    service_system: f.sistema === QUALQUER ? null : f.sistema,
    service_verb: f.verbo === QUALQUER ? null : f.verbo,
    match_keywords: lerPalavras(f.palavras),
    client_reminder_enabled: f.lembrete,
    last_service_at: f.lastAt || null,
    source: f.source,
  };
}

/** Como o sistema reconhece o "serviço feito" numa OS concluída — dito em português. */
function criterioPorExtenso(p: PlanoDeManutencao): string {
  const partes = [
    p.service_system ? SYSTEM_LABEL[p.service_system] ?? p.service_system : '',
    p.service_verb ? (VERB_LABEL[p.service_verb] ?? p.service_verb).toLowerCase() : '',
    (p.match_keywords ?? []).length ? `“${(p.match_keywords ?? []).join('”, “')}”` : '',
  ].filter(Boolean);
  return partes.length ? partes.join(' · ') : 'qualquer OS concluída';
}

/**
 * Planos de manutenção recorrente da embarcação (Fase 8 — padrão ServiceTitan memberships;
 * reescrito em 07/10/2026 para os lembretes). Vencimento e situação vêm do BANCO (view
 * v_maintenance_plans_due): o "Serviço feito" passa pela RPC (data de Brasília, deixa histórico),
 * e a OS concluída que casa com o critério do plano já reinicia o ciclo sozinha.
 */
export function MaintenancePlansPanel({ vesselId }: { vesselId: string | undefined }) {
  const { data, isLoading, error } = usePlanosDaEmbarcacao(vesselId);
  const salvar = useSalvarPlano(vesselId);
  const ligar = useLigarPlano();
  const apagar = useApagarPlano();
  const { pedir, dialogo } = useConfirmacao();

  const [form, setForm] = useState<Formulario | null>(null);
  const [editandoId, setEditandoId] = useState<string | null>(null);
  const [servico, setServico] = useState<AlvoDoPlano | null>(null);
  const [adiar, setAdiar] = useState<AlvoDoPlano | null>(null);
  const [lembrete, setLembrete] = useState<AlvoDoLembrete | null>(null);
  const [historico, setHistorico] = useState<PlanoDeManutencao | null>(null);
  const [sugerindo, setSugerindo] = useState(false);

  const planos = data?.planos ?? [];
  const vencimentos = data?.vencimentos ?? {};
  const set = <K extends keyof Formulario>(k: K, v: Formulario[K]) => setForm((f) => (f ? { ...f, [k]: v } : f));

  if (!vesselId) return null;

  const abrirNovo = (f: Formulario = VAZIO) => { setEditandoId(null); setForm(f); };
  const gravar = () => {
    if (!form) return;
    salvar.mutate({ id: editandoId ?? undefined, input: paraInput(form) }, {
      onSuccess: () => {
        toast.success(editandoId ? 'Plano atualizado' : 'Plano criado — o sistema avisa na hora de propor a revisão');
        setForm(null);
        setEditandoId(null);
      },
      onError: (e) => toast.error((e as Error)?.message || 'Erro ao salvar o plano'),
    });
  };

  return (
    <Card className="p-4 space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-sm font-semibold">
          <Wrench className="h-4 w-4 text-primary" /> Planos de manutenção
        </div>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="ghost" onClick={() => setSugerindo(true)}>
            <Sparkles className="h-4 w-4 mr-1" /> Sugerir planos
          </Button>
          <Button size="sm" variant="outline" onClick={() => abrirNovo()}>
            <Plus className="h-4 w-4 mr-1" /> Novo plano
          </Button>
        </div>
      </div>

      {error ? (
        <p className="text-xs text-destructive">Não deu para ler os planos: {(error as Error).message}</p>
      ) : isLoading ? (
        <div className="flex justify-center py-4 text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /></div>
      ) : planos.length === 0 ? (
        <p className="text-xs text-muted-foreground">
          Nenhum plano. Crie um (ex.: "Revisão de motor · a cada 12 meses") ou peça uma sugestão a partir das OS
          já feitas nesta embarcação — o sistema lembra de propor o serviço na hora certa.
        </p>
      ) : null}
      {data?.erroDaView && planos.length > 0 && (
        <p className="text-xs text-destructive">Não deu para calcular os vencimentos agora: {data.erroDaView}</p>
      )}

      <div className="space-y-2">
        {planos.map((p) => {
          const v = vencimentos[p.id];
          const alvo: AlvoDoPlano = { planId: p.id, rotulo: p.name };
          return (
            <div key={p.id} className={cn('flex items-start gap-3 rounded-md border px-3 py-2 text-sm', !p.active && 'opacity-60')}>
              <div className="min-w-0 flex-1">
                <p className="font-medium break-words">
                  {p.name}{' '}
                  <span className="text-xs font-normal text-muted-foreground">· a cada {p.interval_months} mês(es)</span>
                </p>
                <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px] text-muted-foreground">
                  {!p.active ? (
                    <span className="rounded bg-muted px-1.5 py-0.5 font-medium">desligado</span>
                  ) : v ? (
                    <>
                      <span className={cn('rounded px-1.5 py-0.5 font-medium', CLASSE_DA_SITUACAO[v.situacao])}>
                        {ROTULO_DA_SITUACAO[v.situacao]}
                      </span>
                      <span>Próxima: {dataBR(v.next_due_on)} ({prazoPorExtenso(v.dias_para_vencer)})</span>
                      {v.situacao === 'adiada' && v.snoozed_until && <span>· adiada até {dataBR(v.snoozed_until)}</span>}
                    </>
                  ) : null}
                  <span>· {p.last_service_at ? `último serviço ${dataBR(p.last_service_at)}` : 'sem serviço registrado'}</span>
                  {p.estimated_value != null && <span>· {moeda(Number(p.estimated_value))}</span>}
                </div>
                <p className="mt-0.5 text-[11px] text-muted-foreground break-words">
                  Conta como feito: {criterioPorExtenso(p)} · avisar {p.advance_days} dias antes
                  {' · '}{p.client_reminder_enabled === false ? 'sem lembrete ao cliente' : 'lembrete ao cliente com seu sim'}
                </p>
              </div>
              <AcoesDaLinha
                rotulo={`plano ${p.name}`}
                rapidas={p.active ? [{ texto: 'Serviço feito', icone: CheckCircle2, onClick: () => setServico(alvo) }] : []}
                menu={[
                  ...(p.active ? [
                    { texto: 'Adiar', icone: CalendarClock, onClick: () => setAdiar(alvo) },
                    {
                      texto: 'Pedir lembrete agora', icone: MessageCircle,
                      desabilitada: p.client_reminder_enabled === false,
                      titulo: p.client_reminder_enabled === false ? 'O lembrete ao cliente está desligado neste plano' : undefined,
                      onClick: () => setLembrete({
                        ...alvo, plano: p.name, embarcacao: v?.vessel_name ?? 'a embarcação', cliente: v?.client_name ?? null,
                        vesselId: p.vessel_id, optOut: v?.opt_out, semTelefone: !!v && !v.client_phone,
                      }),
                    },
                  ] : []),
                  { texto: 'Editar', icone: Pencil, onClick: () => { setEditandoId(p.id); setForm(doPlano(p)); } },
                  { texto: 'Histórico', icone: History, onClick: () => setHistorico(p) },
                  {
                    texto: p.active ? 'Desligar plano' : 'Ligar plano', icone: Power,
                    onClick: () => ligar.mutate({ id: p.id, active: !p.active }, {
                      onError: (e) => toast.error((e as Error)?.message || 'Erro ao atualizar'),
                    }),
                  },
                  {
                    texto: 'Apagar plano', icone: Trash2, perigo: true,
                    onClick: () => pedir({
                      titulo: `Apagar o plano “${p.name}”?`,
                      descricao: 'Some o plano e o histórico de lembretes dele. Para só parar os avisos, use "Desligar plano".',
                      confirmar: 'Apagar',
                      acao: () => apagar.mutate(p.id, {
                        onSuccess: () => toast.success('Plano apagado'),
                        onError: (e) => toast.error((e as Error)?.message || 'Erro ao apagar'),
                      }),
                    }),
                  },
                ]}
              />
            </div>
          );
        })}
      </div>

      <Dialog open={!!form} onOpenChange={(v) => { if (!v) { setForm(null); setEditandoId(null); } }}>
        <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editandoId ? 'Editar plano de manutenção' : 'Novo plano de manutenção'}</DialogTitle>
            <DialogDescription>O sistema propõe a revisão na janela certa; nada vai ao cliente sem o seu sim.</DialogDescription>
          </DialogHeader>
          {form && (
            <div className="space-y-3">
              <div className="space-y-1.5">
                <Label htmlFor="plano-nome">Nome *</Label>
                <Input id="plano-nome" value={form.name} onChange={(e) => set('name', e.target.value)} placeholder="Revisão de motor" />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <Label htmlFor="plano-meses">A cada (meses) *</Label>
                  <Input id="plano-meses" type="number" min={1} max={60} value={form.months} onChange={(e) => set('months', e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="plano-valor">Valor estimado (R$)</Label>
                  <Input id="plano-valor" type="number" value={form.value} onChange={(e) => set('value', e.target.value)} placeholder="opcional" />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                {!editandoId && (
                  <div className="space-y-1.5">
                    <Label htmlFor="plano-ultimo">Último serviço</Label>
                    <Input id="plano-ultimo" type="date" value={form.lastAt} onChange={(e) => set('lastAt', e.target.value)} />
                  </div>
                )}
                <div className="space-y-1.5">
                  <Label htmlFor="plano-aviso">Avisar quantos dias antes</Label>
                  <Input id="plano-aviso" type="number" min={0} max={90} value={form.advance} onChange={(e) => set('advance', e.target.value)} />
                </div>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="plano-escopo">Escopo</Label>
                <Input id="plano-escopo" value={form.scope} onChange={(e) => set('scope', e.target.value)} placeholder="óleo, filtros, correias…" />
              </div>
              <div className="rounded-md border p-2.5 space-y-2">
                <p className="text-xs font-medium">O que conta como "serviço feito" numa OS concluída</p>
                <div className="grid grid-cols-2 gap-2">
                  <Select value={form.sistema} onValueChange={(v) => set('sistema', v)}>
                    <SelectTrigger aria-label="Sistema"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value={QUALQUER}>Qualquer sistema</SelectItem>
                      {SISTEMAS.filter((s) => s !== 'nenhum').map((s) => (
                        <SelectItem key={s} value={s}>{SYSTEM_LABEL[s] ?? s}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Select value={form.verbo} onValueChange={(v) => set('verbo', v)}>
                    <SelectTrigger aria-label="Tipo de serviço"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value={QUALQUER}>Qualquer tipo</SelectItem>
                      {VERBOS.map((s) => (
                        <SelectItem key={s} value={s}>{VERB_LABEL[s] ?? s}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <Input aria-label="Palavras do serviço ou da peça" value={form.palavras} onChange={(e) => set('palavras', e.target.value)}
                  placeholder="palavras do serviço/peça: bateria, inversor" />
                <p className="text-[11px] text-muted-foreground">Sem nada aqui, qualquer OS concluída da embarcação reinicia o ciclo.</p>
              </div>
              <label className="flex items-start justify-between gap-3 text-sm">
                <span>
                  Lembrete ao cliente
                  <span className="block text-[11px] text-muted-foreground">Preparado pelo sistema; só sai com o seu sim.</span>
                </span>
                <Switch checked={form.lembrete} onCheckedChange={(v) => set('lembrete', v)} aria-label="Lembrete ao cliente" />
              </label>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => { setForm(null); setEditandoId(null); }}>Cancelar</Button>
            <Button onClick={gravar} disabled={!form?.name.trim() || salvar.isPending}>
              {salvar.isPending && <Loader2 className="h-4 w-4 animate-spin mr-1" />}
              {editandoId ? 'Salvar' : 'Criar plano'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <HistoricoDoPlanoDialog plano={historico} onOpenChange={(v) => { if (!v) setHistorico(null); }} />
      <SugerirPlanosDialog
        aberto={sugerindo}
        vesselId={vesselId}
        existentes={planos}
        onOpenChange={setSugerindo}
        onUsar={(s) => { setSugerindo(false); abrirNovo(daSugestao(s)); }}
      />
      <RegistrarServicoDialog alvo={servico} onOpenChange={(v) => { if (!v) setServico(null); }} />
      <AdiarPlanoDialog alvo={adiar} onOpenChange={(v) => { if (!v) setAdiar(null); }} />
      <PedirLembreteDialog alvo={lembrete} onOpenChange={(v) => { if (!v) setLembrete(null); }} />
      {dialogo}
    </Card>
  );
}

function HistoricoDoPlanoDialog({ plano, onOpenChange }: { plano: PlanoDeManutencao | null; onOpenChange: (v: boolean) => void }) {
  const { data: eventos = [], isLoading, error } = useEventosDoPlano(plano?.id);
  return (
    <Dialog open={!!plano} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Histórico do plano</DialogTitle>
          <DialogDescription>{plano?.name}</DialogDescription>
        </DialogHeader>
        {error ? (
          <p className="text-sm text-destructive">Não deu para ler o histórico: {(error as Error).message}</p>
        ) : isLoading ? (
          <div className="flex justify-center py-4"><Loader2 className="h-4 w-4 animate-spin" /></div>
        ) : eventos.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nada registrado ainda.</p>
        ) : (
          <ul className="space-y-2">
            {eventos.map((e) => {
              const detalhe = e.detalhe as { motivo?: string; texto?: string } | null;
              return (
                <li key={e.id} className="rounded-md border px-3 py-2 text-sm">
                  <p className="font-medium">
                    {ROTULO_DO_EVENTO[e.tipo] ?? e.tipo}{e.toque ? ` (toque ${e.toque})` : ''}
                  </p>
                  <p className="text-[11px] text-muted-foreground">
                    {new Date(e.created_at).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', dateStyle: 'short', timeStyle: 'short' })}
                    {e.due_on ? ` · ciclo de ${dataBR(e.due_on)}` : ''}
                    {e.service_order_id && (
                      <> · <Link className="text-primary hover:underline" to={`/v2/service-orders/${e.service_order_id}`}>ver OS</Link></>
                    )}
                  </p>
                  {(detalhe?.motivo || detalhe?.texto) && (
                    <p className="mt-1 text-xs italic text-muted-foreground break-words">“{detalhe.motivo || detalhe.texto}”</p>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </DialogContent>
    </Dialog>
  );
}

/**
 * "Sugerir planos": lê as OS concluídas da embarcação e propõe os planos que fazem sentido
 * (baterias, inversor/carregador, motor, gás, refrigeração). É proposta: "Usar" abre o
 * formulário preenchido para o dono conferir — nada é criado sem ele.
 */
function SugerirPlanosDialog({
  aberto, vesselId, existentes, onOpenChange, onUsar,
}: {
  aberto: boolean;
  vesselId: string;
  existentes: PlanoDeManutencao[];
  onOpenChange: (v: boolean) => void;
  onUsar: (s: SugestaoDePlano) => void;
}) {
  const { data: historico = [], isLoading, error } = useHistoricoDaEmbarcacao(vesselId, aberto);
  const sugestoes = sugerirPlanos(historico, existentes);
  return (
    <Dialog open={aberto} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Planos sugeridos</DialogTitle>
          <DialogDescription>A partir dos serviços e peças das OS concluídas desta embarcação.</DialogDescription>
        </DialogHeader>
        {error ? (
          <p className="text-sm text-destructive">Não deu para ler o histórico de OS: {(error as Error).message}</p>
        ) : isLoading ? (
          <div className="flex justify-center py-4"><Loader2 className="h-4 w-4 animate-spin" /></div>
        ) : sugestoes.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Nada a sugerir: {historico.length === 0 ? 'esta embarcação ainda não tem OS concluída.' : 'o histórico não tem serviço recorrente sem plano.'}
          </p>
        ) : (
          <ul className="space-y-2">
            {sugestoes.map((s) => (
              <li key={s.familia.chave} className="flex items-start gap-3 rounded-md border px-3 py-2 text-sm">
                <div className="min-w-0 flex-1">
                  <p className="font-medium">{s.familia.nome} · a cada {s.familia.intervaloMeses} meses</p>
                  <p className="text-[11px] text-muted-foreground">
                    Último: {dataBR(s.ultimoServico)}{s.ultimaOsNumero ? ` (${s.ultimaOsNumero})` : ''}
                    {s.valorEstimado != null ? ` · em torno de ${moeda(s.valorEstimado)}` : ''}
                  </p>
                  <p className="text-[11px] italic text-muted-foreground break-words">{s.evidencias.join(' · ')}</p>
                </div>
                <Button size="sm" variant="outline" onClick={() => onUsar(s)}>Usar</Button>
              </li>
            ))}
          </ul>
        )}
      </DialogContent>
    </Dialog>
  );
}
