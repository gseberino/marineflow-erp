// "Saiu da equipe" (decisão do dono, 20/11/2026): o último dia de trabalho de um freelancer de diária.
//
// Depois desse dia nenhum dia entra para ele e a agenda deixa de contar com ele. O saldo — a receber
// OU adiantado — fica na conta, na seção "Saíram da equipe", até zerar; o cadastro continua ativo e o
// Pix para ele continua abatendo. Quem decide tudo isso é registrar_saida_da_equipe (a mesma função
// do assistente): a tela pede a data e mostra a frase do banco, que SIMULA a saída a cada data
// escolhida (nada é gravado até "Registrar a saída"). Recusas (dia lançado depois, data no futuro)
// aparecem antes do clique.
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Campo } from '@/components/Campo';
import { hojeLocal } from '@/lib/dia';
import { simularSaida, useRegistrarSaida, type FreelancerNoResumo } from '@/hooks/use-diarias';

interface Props {
  pessoa: Pick<FreelancerNoResumo, 'id' | 'nome' | 'desde' | 'ultimo_dia_trabalhado' | 'saiu_em'>;
  onFechar: () => void;
}

export function SaidaDaEquipeDialog({ pessoa, onFechar }: Props) {
  const hoje = hojeLocal();
  const registrar = useRegistrarSaida();
  // O último dia proposto: o último dia trabalhado lançado (ou a saída já registrada, para corrigir).
  const [ultimoDia, setUltimoDia] = useState<string>(pessoa.saiu_em ?? pessoa.ultimo_dia_trabalhado ?? hoje);
  const dataValida = !!ultimoDia && ultimoDia <= hoje;
  const conferencia = useQuery({
    queryKey: ['diarias', 'saida', pessoa.id, ultimoDia],
    queryFn: () => simularSaida(pessoa.id, ultimoDia),
    enabled: dataValida,
    retry: false,
    staleTime: 0,
  });

  async function registrarSaida() {
    try {
      const r = await registrar.mutateAsync({ favorecidoId: pessoa.id, ultimoDia });
      toast.success(r.message);
      onFechar();
    } catch (e) {
      toast.error((e as Error).message || 'Não deu para registrar a saída.');
    }
  }

  const recusa = !ultimoDia ? 'Informe o último dia de trabalho.'
    : ultimoDia > hoje ? 'O último dia não pode estar no futuro.'
    : conferencia.error ? (conferencia.error as Error).message
    : null;

  return (
    <Dialog open onOpenChange={(aberto) => !aberto && onFechar()}>
      <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{pessoa.saiu_em ? `Corrigir a saída de ${pessoa.nome}` : `${pessoa.nome} saiu da equipe`}</DialogTitle>
          <DialogDescription>
            Depois do último dia nenhum dia entra para ele. O saldo continua na conta até zerar, e o cadastro fica ativo.
          </DialogDescription>
        </DialogHeader>

        <Campo rotulo="Último dia de trabalho" htmlFor="saida-ultimo-dia" idAjuda="saida-ultimo-dia-ajuda"
               ajuda={pessoa.ultimo_dia_trabalhado ? `O último dia lançado é ${pessoa.ultimo_dia_trabalhado.split('-').reverse().join('/')}.` : undefined}>
          <Input id="saida-ultimo-dia" type="date" value={ultimoDia} max={hoje} min={pessoa.desde ?? undefined}
                 aria-describedby="saida-ultimo-dia-ajuda" onChange={(e) => setUltimoDia(e.target.value)} />
        </Campo>

        <div className="rounded-md border bg-muted/40 p-3 text-sm" aria-live="polite">
          {recusa ? <p className="text-destructive">{recusa}</p>
            : conferencia.isLoading ? <p className="text-muted-foreground">Conferindo…</p>
            : <p>{conferencia.data?.message}</p>}
        </div>

        <DialogFooter className="gap-2">
          <Button type="button" variant="outline" onClick={onFechar}>Cancelar</Button>
          <Button type="button" onClick={() => { void registrarSaida(); }}
                  disabled={!!recusa || !conferencia.data || conferencia.data.acao === 'sem_mudanca' || registrar.isPending}>
            {registrar.isPending ? 'Registrando…' : 'Registrar a saída'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
