/**
 * "O que eu mudei sozinho" na Semana de produção (Fase 3, P7a): o que o gestor da agenda fez de ontem para hoje, uma
 * linha cada, com Desfazer no que ainda dá. A confirmação só aparece quando desfazer é perda real — cancela a cobrança
 * que a conclusão criou ou apaga a diária lançada (padrão do dono: proteger contra erro sem perguntar à toa). A frase de
 * volta é a do banco.
 */
import { Loader2, Undo2 } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { useConfirmacao } from '@/components/Confirmacao';
import { useDesfazerAcao, type MudancaDoGestor } from '@/hooks/use-agenda-producao';

const PERDA: Record<'cobranca' | 'diaria', { titulo: string; descricao: string }> = {
  cobranca: {
    titulo: 'Desfazer a conclusão?',
    descricao: 'A OS volta ao status de antes e as cobranças que a conclusão criou são canceladas.',
  },
  diaria: {
    titulo: 'Desfazer a diária?',
    descricao: 'A diária que a agenda lançou é apagada.',
  },
};

export function MudancasDoGestor({ mudancas }: { mudancas: MudancaDoGestor[] }) {
  const desfazer = useDesfazerAcao();
  const { pedir, dialogo } = useConfirmacao();

  const executar = async (acaoId: string) => {
    try {
      const texto = await desfazer.mutateAsync(acaoId);
      toast.success(texto || 'Desfeito.');
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Não deu para desfazer.');
    }
  };

  if (mudancas.length === 0) return null;
  return (
    <section className="space-y-2 rounded-lg border p-3" aria-labelledby="mudancas-do-gestor">
      <h3 id="mudancas-do-gestor" className="text-sm font-semibold">O que eu mudei sozinho</h3>
      <ul className="space-y-2">
        {mudancas.map((m, i) => (
          <li key={m.acao_id ?? i} className="flex min-w-0 flex-col gap-1 sm:flex-row sm:items-start sm:justify-between sm:gap-3">
            <p className="min-w-0 break-words text-sm">{m.texto}</p>
            {m.desfazivel && !m.desfeita && m.acao_id && (
              <Button
                size="sm"
                variant="outline"
                className="shrink-0 gap-1 self-start"
                disabled={desfazer.isPending}
                onClick={() => {
                  const id = m.acao_id!;
                  if (m.perda) {
                    pedir({ titulo: PERDA[m.perda].titulo, descricao: PERDA[m.perda].descricao, confirmar: 'Desfazer',
                            acao: () => { void executar(id); } });
                  } else {
                    void executar(id);
                  }
                }}
              >
                {desfazer.isPending && desfazer.variables === m.acao_id
                  ? <Loader2 className="h-3 w-3 animate-spin" aria-hidden />
                  : <Undo2 className="h-3 w-3" aria-hidden />}
                Desfazer
              </Button>
            )}
          </li>
        ))}
      </ul>
      {dialogo}
    </section>
  );
}
