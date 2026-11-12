// Registrar o serviço de um prestador que recebe por serviço, não por diária (o Alex, 12/11/2026).
//
// O combinado muda de serviço a serviço: um valor em reais na OS, ou um percentual da mão de obra, do
// total ou do lucro da OS. O valor só entra no saldo dele quando o cliente paga a OS — antes fica
// "aguardando o cliente pagar". Duas etapas, como o "sim" do WhatsApp: o formulário e a CONFERÊNCIA (a
// função do banco simula sem gravar: o valor de hoje, se já entra na conta, o que substitui). A mesma
// função do assistente (registrar_servico_prestador); a tela não calcula nada.
import { useState } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { MoneyInput } from '@/components/MoneyInput';
import { hojeLocal } from '@/lib/dia';
import { useServiceOrdersVinculaveis } from '@/hooks/use-payees';
import {
  simularServico, useRegistrarServico, type FreelancerNoResumo, type PedidoDeServico, type ResultadoDoServico,
} from '@/hooks/use-diarias';

const BASES = [
  { valor: 'mao_de_obra', rotulo: 'da mão de obra (serviços da OS)' },
  { valor: 'total', rotulo: 'do total da OS' },
  { valor: 'lucro', rotulo: 'do lucro da OS' },
] as const;

export interface ServicoParaEditar {
  favorecidoId: string;
  osId: string;
  modo: 'valor' | 'percentual';
  valor: number;
  percentual: number | null;
  base: PedidoDeServico['base'] | null;
  descricao: string | null;
}

export function RegistrarServicoDialog({ pessoas, favorecidoInicial, editar, onFechar }: {
  /** Só os prestadores por serviço. */
  pessoas: FreelancerNoResumo[];
  favorecidoInicial?: string | null;
  editar?: ServicoParaEditar;
  onFechar: () => void;
}) {
  const registrar = useRegistrarServico();
  const { data: ordens = [] } = useServiceOrdersVinculaveis({ incluirFaturadas: true });
  const [favorecidoId, setFavorecidoId] = useState(editar?.favorecidoId ?? favorecidoInicial ?? (pessoas.length === 1 ? pessoas[0].id : ''));
  const [osId, setOsId] = useState(editar?.osId ?? '');
  const [modo, setModo] = useState<'valor' | 'percentual'>(editar?.modo ?? 'valor');
  const [valor, setValor] = useState(editar?.modo === 'valor' ? editar.valor : 0);
  const [percentual, setPercentual] = useState(editar?.percentual != null ? String(editar.percentual).replace('.', ',') : '');
  const [base, setBase] = useState<PedidoDeServico['base'] | ''>(editar?.base ?? '');
  const [descricao, setDescricao] = useState(editar?.descricao ?? '');
  const [data, setData] = useState('');
  const [conferindo, setConferindo] = useState(false);
  const [simulado, setSimulado] = useState<ResultadoDoServico | null>(null);
  const [recusa, setRecusa] = useState<string | null>(null);

  const pct = Number(percentual.replace(',', '.'));
  const erro = !favorecidoId ? 'Escolha o prestador.'
    : !osId ? 'Escolha a OS do serviço.'
    : modo === 'valor' && valor <= 0 ? 'Informe o valor combinado.'
    : modo === 'percentual' && !(pct > 0 && pct <= 100) ? 'Informe o percentual (de 0 a 100).'
    : modo === 'percentual' && !base ? 'Percentual de quê? Escolha a base.'
    : null;

  const pedido = (): PedidoDeServico => ({
    favorecidoId, osId, modo, valor, percentual: pct, base: (base || 'mao_de_obra') as PedidoDeServico['base'], descricao, data,
  });

  // Qualquer mudança invalida a conferência: o "Registrar" vale para o que foi conferido.
  const mudou = <T,>(set: (v: T) => void) => (v: T) => { set(v); setSimulado(null); setRecusa(null); };

  async function conferir() {
    if (erro) return;
    setConferindo(true);
    setRecusa(null);
    try {
      setSimulado(await simularServico(pedido()));
    } catch (e) {
      setRecusa((e as Error).message || 'O registro seria recusado.');
    } finally {
      setConferindo(false);
    }
  }

  async function gravar() {
    try {
      const r = await registrar.mutateAsync(pedido());
      toast.success(r.entra_na_conta ? 'Serviço registrado e já na conta.' : 'Serviço registrado: entra na conta quando o cliente pagar a OS.');
      onFechar();
    } catch (e) {
      setSimulado(null);
      setRecusa((e as Error).message || 'Não foi possível registrar.');
    }
  }

  return (
    <Dialog open onOpenChange={(aberto) => !aberto && onFechar()}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{simulado ? 'Conferir o serviço' : editar ? 'Corrigir o serviço' : 'Registrar serviço'}</DialogTitle>
          <DialogDescription>
            {simulado
              ? 'Nada foi gravado ainda. Confira e registre — ou volte para corrigir.'
              : 'Para quem recebe por serviço (não por diária). O valor entra no saldo dele quando o cliente pagar a OS.'}
          </DialogDescription>
        </DialogHeader>

        {simulado ? (
          <div className="space-y-1 whitespace-pre-line text-sm">{simulado.message}</div>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="serv-prestador">Prestador</Label>
              <Select value={favorecidoId} onValueChange={mudou(setFavorecidoId)} disabled={!!editar}>
                <SelectTrigger id="serv-prestador"><SelectValue placeholder="Escolher…" /></SelectTrigger>
                <SelectContent>
                  {pessoas.map((p) => <SelectItem key={p.id} value={p.id}>{p.nome}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="serv-os">OS do serviço</Label>
              <Select value={osId} onValueChange={mudou(setOsId)} disabled={!!editar}>
                <SelectTrigger id="serv-os"><SelectValue placeholder="Escolher OS…" /></SelectTrigger>
                <SelectContent>
                  {ordens.map((o) => (
                    <SelectItem key={o.id} value={o.id}>
                      {o.service_order_number}{o.clients?.name ? ` · ${o.clients.name}` : ''}{o.status === 'invoiced' ? ' (faturada)' : ''}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">Um serviço por OS: registrar de novo na mesma OS corrige o combinado.</p>
            </div>
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="serv-modo">Como foi combinado</Label>
              <Select value={modo} onValueChange={(v) => mudou(setModo)(v as 'valor' | 'percentual')}>
                <SelectTrigger id="serv-modo"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="valor">Valor combinado (R$)</SelectItem>
                  <SelectItem value="percentual">Percentual (comissão)</SelectItem>
                </SelectContent>
              </Select>
            </div>
            {modo === 'valor' ? (
              <div className="space-y-1.5 sm:col-span-2">
                <Label htmlFor="serv-valor">Valor combinado (R$)</Label>
                <MoneyInput id="serv-valor" value={valor} onValueChange={mudou(setValor)} />
              </div>
            ) : (
              <>
                <div className="space-y-1.5">
                  <Label htmlFor="serv-pct">Percentual (%)</Label>
                  <Input id="serv-pct" inputMode="decimal" value={percentual} placeholder="Ex.: 30"
                         onChange={(e) => mudou(setPercentual)(e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="serv-base">Sobre</Label>
                  <Select value={base} onValueChange={(v) => mudou(setBase)(v as PedidoDeServico['base'])}>
                    <SelectTrigger id="serv-base"><SelectValue placeholder="Escolher…" /></SelectTrigger>
                    <SelectContent>
                      {BASES.map((b) => <SelectItem key={b.valor} value={b.valor}>{b.rotulo}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <p className="text-xs text-muted-foreground sm:col-span-2">
                  O valor acompanha a OS até o cliente pagar; aí fica fixo.
                </p>
              </>
            )}
            <div className="space-y-1.5">
              <Label htmlFor="serv-data">Dia do serviço (opcional)</Label>
              <Input id="serv-data" type="date" value={data} max={hojeLocal()} onChange={(e) => mudou(setData)(e.target.value)} />
            </div>
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="serv-desc">O que ele fez (opcional)</Label>
              <Textarea id="serv-desc" rows={2} value={descricao} onChange={(e) => mudou(setDescricao)(e.target.value)}
                        placeholder="Ex.: troca do banco de baterias" />
            </div>
          </div>
        )}

        {recusa && <p role="alert" className="text-sm text-destructive">{recusa}</p>}

        <DialogFooter className="flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm text-destructive">{!simulado && erro && osId ? erro : ''}</p>
          <div className="flex gap-2">
            {simulado ? (
              <>
                <Button type="button" variant="outline" onClick={() => setSimulado(null)}>Voltar</Button>
                <Button type="button" onClick={gravar} disabled={registrar.isPending}>
                  {registrar.isPending ? 'Registrando…' : 'Registrar'}
                </Button>
              </>
            ) : (
              <>
                <Button type="button" variant="outline" onClick={onFechar}>Cancelar</Button>
                <Button type="button" onClick={conferir} disabled={!!erro || conferindo}>
                  {conferindo ? 'Conferindo…' : 'Conferir'}
                </Button>
              </>
            )}
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
