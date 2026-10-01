import { useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';
import { useLancarVia } from '@/hooks/use-lancar-via';
import { isoParaInputLocal } from '@/lib/datetime-local';
import { temAlgoParaLancar, type LancamentoDaVia, type SituacaoDaVolta } from '@/lib/lancar-via';

const OPCOES: Array<{ valor: SituacaoDaVolta; rotulo: string }> = [
  { valor: 'feito', rotulo: 'Feito' },
  { valor: 'parcial', rotulo: 'Parcial' },
  { valor: 'nao_feito', rotulo: 'Não feito' },
];

const DA_VOLTA = new Set(['feito', 'parcial', 'nao_feito']);

export interface ViaEntryService {
  id: string;
  name_snapshot?: string | null;
  field_status?: string | null;
  field_status_note?: string | null;
}

/**
 * Lançar a via — a tela que espelha o papel da via do técnico.
 *
 * Quem lança é o escritório, com a folha na mão (escolha do dono, 01/10/2026). A ordem dos
 * campos é a ordem da folha: chegada e saída, a volta de cada serviço, o relato e o material
 * além do previsto. Campo em branco não muda nada.
 */
export function ViaEntryDialog({
  open, onOpenChange, orderId, orderNumber, services, notasAtuais, checkInAt, checkOutAt, onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  orderId: string;
  orderNumber?: string | null;
  services: ViaEntryService[];
  notasAtuais?: string | null;
  checkInAt?: string | null;
  checkOutAt?: string | null;
  /** Para a tela da OS acompanhar as notas novas (o salvamento automático não pode desfazer). */
  onSaved?: (r: { technicianNotes?: string }) => void;
}) {
  const lancar = useLancarVia();

  const inicial = useMemo((): LancamentoDaVia => ({
    chegada: isoParaInputLocal(checkInAt),
    saida: isoParaInputLocal(checkOutAt),
    servicos: Object.fromEntries(services.map((s) => [s.id, {
      situacao: DA_VOLTA.has(s.field_status || '') ? (s.field_status as SituacaoDaVolta) : '',
      motivo: s.field_status_note || '',
    }])),
    relato: '',
    materialExtra: '',
  }), [services, checkInAt, checkOutAt]);

  const [l, setL] = useState<LancamentoDaVia>(inicial);
  useEffect(() => { if (open) setL(inicial); }, [open, inicial]);

  const setServico = (id: string, patch: { situacao?: SituacaoDaVolta | ''; motivo?: string }) =>
    setL((p) => ({ ...p, servicos: { ...p.servicos, [id]: { ...p.servicos[id], ...patch } } }));

  async function salvar() {
    try {
      const r = await lancar.mutateAsync({ orderId, notasAtuais, lancamento: l });
      onSaved?.({ technicianNotes: r.technicianNotes });
      toast.success(r.servicos
        ? `Via lançada: ${r.servicos} serviço(s) atualizado(s).`
        : 'Via lançada.');
      onOpenChange(false);
    } catch (e: any) {
      toast.error(e?.message || 'Não deu para lançar a via');
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90dvh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Lançar a via{orderNumber ? ` · ${orderNumber}` : ''}</DialogTitle>
          <DialogDescription>
            Passe para o sistema o que o técnico escreveu no papel. Campo em branco não muda nada.
          </DialogDescription>
        </DialogHeader>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <Label htmlFor="via-chegada">Chegada</Label>
            <Input id="via-chegada" type="datetime-local" value={l.chegada}
              onChange={(e) => setL((p) => ({ ...p, chegada: e.target.value }))} />
          </div>
          <div>
            <Label htmlFor="via-saida">Saída</Label>
            <Input id="via-saida" type="datetime-local" value={l.saida}
              onChange={(e) => setL((p) => ({ ...p, saida: e.target.value }))} />
          </div>
        </div>

        {services.length > 0 && (
          <div className="space-y-2">
            <Label>Serviços</Label>
            {services.map((s, i) => {
              const atual = l.servicos[s.id]?.situacao || '';
              return (
                <div key={s.id} className="space-y-2 rounded-md border p-2.5">
                  <div className="text-sm font-medium">{i + 1} · {s.name_snapshot || 'Serviço'}</div>
                  <div className="flex flex-wrap gap-1.5" role="group" aria-label={`Situação de ${s.name_snapshot || 'serviço'}`}>
                    {OPCOES.map((o) => (
                      <Button
                        key={o.valor}
                        type="button"
                        size="sm"
                        variant={atual === o.valor ? 'default' : 'outline'}
                        aria-pressed={atual === o.valor}
                        onClick={() => setServico(s.id, { situacao: atual === o.valor ? '' : o.valor })}
                      >
                        {o.rotulo}
                      </Button>
                    ))}
                  </div>
                  {(atual === 'parcial' || atual === 'nao_feito') && (
                    <Input
                      aria-label={`Motivo — ${s.name_snapshot || 'serviço'}`}
                      placeholder="Motivo (como está no papel)"
                      value={l.servicos[s.id]?.motivo || ''}
                      onChange={(e) => setServico(s.id, { motivo: e.target.value })}
                    />
                  )}
                </div>
              );
            })}
          </div>
        )}

        <div>
          <Label htmlFor="via-relato">O que encontrei · o que ficou pendente · o que vigiar da próxima vez</Label>
          <Textarea id="via-relato" rows={3} value={l.relato}
            onChange={(e) => setL((p) => ({ ...p, relato: e.target.value }))} />
        </div>
        <div>
          <Label htmlFor="via-material">Material usado além do previsto</Label>
          <Textarea id="via-material" rows={2} value={l.materialExtra}
            onChange={(e) => setL((p) => ({ ...p, materialExtra: e.target.value }))} />
          <p className="mt-1 text-xs text-muted-foreground">
            Vai para as notas da OS. Para cobrar, lance a peça na OS como de costume.
          </p>
        </div>

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button onClick={salvar} disabled={!temAlgoParaLancar(l) || lancar.isPending}>
            {lancar.isPending ? 'Lançando…' : 'Lançar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
