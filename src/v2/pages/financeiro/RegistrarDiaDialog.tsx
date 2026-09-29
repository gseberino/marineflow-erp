// Registrar (ou corrigir) o dia de um freelancer. Grava por `registrar_diaria`: um dia por pessoa,
// então registrar de novo a mesma data corrige o dia em vez de duplicar.
import { useMemo, useState } from 'react';
import { X } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { MoneyInput } from '@/components/MoneyInput';
import { useI18n } from '@/i18n';
import { hojeLocal } from '@/lib/dia';
import { JORNADAS, valorDoDia, type Jornada } from '@/lib/diarias';
import { useServiceOrdersVinculaveis } from '@/hooks/use-payees';
import { useRegistrarDiaria, type FreelancerNoResumo, type OSDoDia } from '@/hooks/use-diarias';

export interface DiaParaEditar {
  favorecidoId: string;
  data: string;
  jornada: Jornada;
  valorDiaria: number;
  extras: number;
  descontos: number;
  observacao: string | null;
  os: OSDoDia[];
}

interface Props {
  pessoas: FreelancerNoResumo[];
  /** Pessoa já escolhida (botão "Registrar dia" do cartão dela). */
  favorecidoInicial?: string | null;
  /** Corrigir um dia já lançado: pessoa e data ficam fixas — são a identidade do dia. */
  editar?: DiaParaEditar | null;
  onFechar: () => void;
}

export function RegistrarDiaDialog({ pessoas, favorecidoInicial, editar, onFechar }: Props) {
  const { formatCurrency } = useI18n();
  const registrar = useRegistrarDiaria();
  const { data: ordens = [] } = useServiceOrdersVinculaveis({ incluirFaturadas: true });

  const [favorecidoId, setFavorecidoId] = useState<string>(
    editar?.favorecidoId ?? favorecidoInicial ?? (pessoas.length === 1 ? pessoas[0].id : ''),
  );
  const [data, setData] = useState<string>(editar?.data ?? hojeLocal());
  const [jornada, setJornada] = useState<Jornada>(editar?.jornada ?? 'inteiro');
  const [osIds, setOsIds] = useState<string[]>(editar?.os.map((o) => o.id) ?? []);
  const [extras, setExtras] = useState<number>(editar?.extras ?? 0);
  const [descontos, setDescontos] = useState<number>(editar?.descontos ?? 0);
  const [observacao, setObservacao] = useState<string>(editar?.observacao ?? '');
  // A diária vem do cadastro (ou da que já está gravada no dia). Só vai para o banco se mudar
  // aqui: sem mudança, o banco usa a do perfil vigente NA DATA, que pode não ser a de hoje.
  const pessoa = pessoas.find((p) => p.id === favorecidoId);
  const diariaPadrao = editar?.valorDiaria ?? pessoa?.diaria ?? 0;
  const [diariaDigitada, setDiariaDigitada] = useState<number | null>(null);
  const diaria = diariaDigitada ?? diariaPadrao;

  const total = valorDoDia(jornada, diaria, extras, descontos);
  const hoje = hojeLocal();
  const nomesDasOS = useMemo(() => {
    const m = new Map<string, string>();
    for (const o of editar?.os ?? []) m.set(o.id, o.numero);
    for (const o of ordens) m.set(o.id, `${o.service_order_number}${o.clients?.name ? ` · ${o.clients.name}` : ''}`);
    return m;
  }, [ordens, editar]);
  const osParaAdicionar = ordens.filter((o) => !osIds.includes(o.id));

  const erro = !favorecidoId ? 'Escolha o freelancer.'
    : !data ? 'Informe a data.'
    : data > hoje ? 'A data não pode estar no futuro.'
    : jornada !== 'faltou' && diaria <= 0 ? 'Informe o valor da diária.'
    : null;

  async function salvar() {
    if (erro) return;
    try {
      const r = await registrar.mutateAsync({
        favorecidoId, data, jornada, osIds, extras, descontos,
        observacao: observacao.trim(),
        valorDiaria: diariaDigitada != null && diariaDigitada !== diariaPadrao ? diariaDigitada : undefined,
      });
      toast.success(r.message);
      onFechar();
    } catch (e) {
      toast.error((e as Error).message || 'Não foi possível registrar o dia.');
    }
  }

  return (
    <Dialog open onOpenChange={(aberto) => !aberto && onFechar()}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{editar ? 'Corrigir dia trabalhado' : 'Registrar dia trabalhado'}</DialogTitle>
          <DialogDescription>
            Um dia por pessoa: registrar de novo a mesma data corrige o dia, não duplica.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="dia-freelancer">Freelancer</Label>
            <Select value={favorecidoId} onValueChange={(v) => { setFavorecidoId(v); setDiariaDigitada(null); }} disabled={!!editar}>
              <SelectTrigger id="dia-freelancer"><SelectValue placeholder="Escolha…" /></SelectTrigger>
              <SelectContent>
                {pessoas.map((p) => <SelectItem key={p.id} value={p.id}>{p.nome}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="dia-data">Data</Label>
            <Input id="dia-data" type="date" value={data} max={hoje} onChange={(e) => setData(e.target.value)} disabled={!!editar} />
          </div>

          <div className="space-y-1.5 sm:col-span-2">
            <span className="text-sm font-medium" id="dia-jornada">Jornada</span>
            <div className="flex flex-wrap gap-2" role="group" aria-labelledby="dia-jornada">
              {JORNADAS.map((j) => (
                <Button key={j.valor} type="button" size="sm" variant={jornada === j.valor ? 'default' : 'outline'}
                        aria-pressed={jornada === j.valor} onClick={() => setJornada(j.valor)}>
                  {j.rotulo}
                </Button>
              ))}
            </div>
          </div>

          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="dia-os">Em qual OS (opcional)</Label>
            {osIds.length > 0 && (
              <div className="flex flex-wrap gap-1.5">
                {osIds.map((id) => (
                  <span key={id} className="inline-flex max-w-full items-center gap-1 rounded-md border bg-muted/50 px-2 py-0.5 text-xs">
                    <span className="truncate">{nomesDasOS.get(id) ?? 'OS'}</span>
                    <button type="button" className="shrink-0 rounded p-0.5 hover:bg-muted" aria-label={`Tirar ${nomesDasOS.get(id) ?? 'OS'}`}
                            onClick={() => setOsIds(osIds.filter((x) => x !== id))}>
                      <X className="h-3 w-3" />
                    </button>
                  </span>
                ))}
              </div>
            )}
            <Select value="" onValueChange={(v) => v && setOsIds([...osIds, v])}>
              <SelectTrigger id="dia-os"><SelectValue placeholder={osIds.length ? 'Adicionar outra OS…' : 'Escolher OS…'} /></SelectTrigger>
              <SelectContent>
                {osParaAdicionar.map((o) => (
                  <SelectItem key={o.id} value={o.id}>
                    {o.service_order_number}{o.clients?.name ? ` · ${o.clients.name}` : ''}{o.status === 'invoiced' ? ' (faturada)' : ''}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {osIds.length > 1 && <p className="text-xs text-muted-foreground">O valor do dia se divide em partes iguais entre as OS.</p>}
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="dia-diaria">Diária (R$)</Label>
            <MoneyInput id="dia-diaria" value={diaria} onValueChange={setDiariaDigitada} />
            <p className="text-xs text-muted-foreground">{editar ? 'A gravada neste dia.' : 'Vem do cadastro; mude só se este dia foi diferente.'}</p>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="dia-extras">Extras (R$)</Label>
            <MoneyInput id="dia-extras" value={extras} onValueChange={setExtras} />
            <p className="text-xs text-muted-foreground">Só o que ele pagou do bolso (almoço, transporte, material).</p>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="dia-descontos">Descontos (R$)</Label>
            <MoneyInput id="dia-descontos" value={descontos} onValueChange={setDescontos} />
          </div>
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="dia-obs">Observação</Label>
            <Textarea id="dia-obs" rows={2} value={observacao} onChange={(e) => setObservacao(e.target.value)}
                      placeholder="Serviço feito, obra, barco…" />
          </div>
        </div>

        <DialogFooter className="flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm">
            Total do dia <b className="tabular-nums">{formatCurrency(total)}</b>
            {erro && <span className="ml-2 text-destructive">{erro}</span>}
          </p>
          <div className="flex gap-2">
            <Button type="button" variant="outline" onClick={onFechar}>Cancelar</Button>
            <Button type="button" onClick={salvar} disabled={!!erro || registrar.isPending}>
              {registrar.isPending ? 'Salvando…' : editar ? 'Salvar' : 'Registrar'}
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
