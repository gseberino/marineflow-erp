// A ficha de um dia de um freelancer, aberta pela célula da grade: três ações diretas e o que já
// está lançado naquele dia.
//
// "Não trabalhou" GRAVA a falta (valor zero) — não apaga o dia (decisão do dono, 28/09/2026).
// Apagar um lançamento feito por engano é o "Excluir" da lista, com Desfazer.
import { toast } from 'sonner';
import { Pencil, Trash2 } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { AcoesDaLinha } from '@/components/AcoesDaLinha';
import { useI18n } from '@/i18n';
import { JORNADAS, diaCurto, rotuloDaJornada, type Jornada } from '@/lib/diarias';
import {
  diaParaEditar, useExcluirDiaComDesfazer, useRegistrarDiaria,
  type DiaParaEditar, type FreelancerNoResumo, type LinhaDaContaCorrente,
} from '@/hooks/use-diarias';

interface Props {
  pessoa: FreelancerNoResumo;
  data: string;
  /** As linhas deste freelancer nesta data (o dia, se houver, e os pagamentos). */
  linhas: LinhaDaContaCorrente[];
  onFechar: () => void;
  onEditar: (d: DiaParaEditar) => void;
  onDetalhes: () => void;
}

export function FichaDoDia({ pessoa, data, linhas, onFechar, onEditar, onDetalhes }: Props) {
  const { formatCurrency } = useI18n();
  const registrar = useRegistrarDiaria();
  const { excluir, excluindo } = useExcluirDiaComDesfazer();
  const dia = linhas.find((l) => l.tipo === 'dia') ?? null;
  const pagamentos = linhas.filter((l) => l.tipo === 'pagamento');

  async function marcar(jornada: Jornada) {
    if (dia?.jornada === jornada) return;
    try {
      // Só a jornada: OS, extras e observação que o dia já tinha continuam como estavam.
      const r = await registrar.mutateAsync({ favorecidoId: pessoa.id, data, jornada });
      toast.success(r.message);
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para registrar o dia.');
    }
  }

  return (
    <Dialog open onOpenChange={(aberto) => !aberto && onFechar()}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{pessoa.nome} · {diaCurto(data)}</DialogTitle>
          <DialogDescription>
            {pessoa.diaria != null ? `Diária do cadastro: ${formatCurrency(pessoa.diaria)}.` : 'Sem diária no cadastro.'}
            {' '}Para OS, extras ou observação, use “Lançar com detalhes”.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-wrap gap-2" role="group" aria-label="Neste dia">
          {JORNADAS.map((j) => (
            <Button key={j.valor} type="button" size="sm" variant={dia?.jornada === j.valor ? 'default' : 'outline'}
                    aria-pressed={dia?.jornada === j.valor} disabled={registrar.isPending}
                    onClick={() => { void marcar(j.valor); }}>
              {j.rotulo}
            </Button>
          ))}
        </div>

        <div className="space-y-2">
          <p className="text-sm font-medium">Lançado neste dia</p>
          {!dia && pagamentos.length === 0 ? (
            <p className="text-sm text-muted-foreground">Nada lançado neste dia.</p>
          ) : (
            <div className="divide-y rounded-md border">
              {dia && (
                <div className="flex min-w-0 items-start gap-2 p-2">
                  <div className="min-w-0 flex-1 text-sm">
                    <div className="flex flex-wrap items-center gap-x-2">
                      <Badge variant="outline">{rotuloDaJornada(dia.jornada)}</Badge>
                      <span className="font-medium tabular-nums">{formatCurrency(dia.trabalhado)}</span>
                    </div>
                    <p className="mt-0.5 truncate text-xs text-muted-foreground">
                      {dia.os.length ? `OS ${dia.os.map((o) => o.numero).join(', ')}` : 'Sem OS'}
                      {dia.extras ? ` · extras ${formatCurrency(dia.extras)}` : ''}
                      {dia.observacao ? ` · ${dia.observacao}` : ''}
                    </p>
                  </div>
                  <AcoesDaLinha
                    rotulo={`dia ${diaCurto(data)} de ${pessoa.nome}`}
                    ocupada={excluindo}
                    menu={[
                      { texto: 'Corrigir o dia', icone: Pencil, onClick: () => onEditar(diaParaEditar(pessoa.id, dia)) },
                      { texto: 'Excluir o dia', icone: Trash2, perigo: true, onClick: () => { void excluir(dia.id); } },
                    ]}
                  />
                </div>
              )}
              {pagamentos.map((p) => (
                <div key={p.id} className="flex min-w-0 items-start gap-2 p-2 text-sm">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-x-2">
                      <Badge variant="outline" className="text-sky-700 dark:text-sky-400">Pagamento</Badge>
                      <span className="font-medium tabular-nums">{formatCurrency(p.pago)}</span>
                    </div>
                    <p className="mt-0.5 truncate text-xs text-muted-foreground">{p.conta}{p.descricao ? ` · ${p.descricao}` : ''}</p>
                  </div>
                </div>
              ))}
            </div>
          )}
          {pagamentos.length > 0 && (
            <p className="text-xs text-muted-foreground">Pagamento vem do extrato: para corrigir, use Financeiro › Despesas.</p>
          )}
        </div>

        <DialogFooter className="flex-col gap-2 sm:flex-row sm:justify-between">
          <Button type="button" variant="outline" size="sm" onClick={onDetalhes}>Lançar com detalhes</Button>
          <Button type="button" size="sm" onClick={onFechar}>Fechar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
