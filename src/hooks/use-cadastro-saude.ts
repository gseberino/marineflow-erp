// Saúde do cadastro: mede a evidência, não opina sobre o nome.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import {
  analisarFornecedor, acharDuplicados, ordenarProblemas, normalizar,
  type FornecedorParaAnalise, type ProblemaDeCadastro,
} from '@/lib/cadastro-saude';

/**
 * Carrega fornecedores, uso e a evidência que sustenta cada acusação.
 *
 * `fantasia_em_terceiros` é o número que substitui o palpite: quantas transações do
 * extrato contêm o texto da fantasia SEM serem deste fornecedor. Foi assim que "Itajai"
 * se denunciou — aparecia em dezenas de estabelecimentos que nada tinham a ver com a
 * Coremma. Julgar a palavra exigiria uma lista de municípios que ninguém mantém; contar
 * onde ela aparece exige só o extrato que já temos.
 */
export function useSaudeDoCadastro() {
  return useQuery({
    queryKey: ['saude-cadastro-fornecedores'],
    queryFn: async () => {
      const [{ data: fornecedores, error: e1 }, { data: usos, error: e2 }, { data: txs, error: e3 }] =
        await Promise.all([
          supabase.from('suppliers').select('id, name, trade_name, cnpj_cpf, active').limit(2000),
          supabase.from('payables').select('supplier_id').not('supplier_id', 'is', null).limit(5000),
          supabase.from('bank_transactions')
            .select('counterparty_name, description, id')
            .limit(3000),
        ]);
      if (e1) throw e1;
      if (e2) throw e2;
      if (e3) throw e3;

      const contagem = new Map<string, number>();
      for (const u of (usos ?? []) as { supplier_id: string }[]) {
        contagem.set(u.supplier_id, (contagem.get(u.supplier_id) ?? 0) + 1);
      }

      // Texto de cada transação, normalizado uma vez só. Comparar 530 fantasias contra
      // 3.000 transações normalizando dos dois lados a cada volta seria o mesmo erro de
      // custo que já derrubou o motor de propostas.
      const textos = ((txs ?? []) as { counterparty_name: string | null; description: string }[])
        .map((t) => normalizar(`${t.counterparty_name ?? ''} ${t.description ?? ''}`));

      const lista: FornecedorParaAnalise[] = ((fornecedores ?? []) as any[]).map((f) => {
        const fantasia = normalizar(f.trade_name);
        const nome = normalizar(f.name);
        let emTerceiros = 0;
        // Palavra única e com 3+ letras: é a forma que sequestra casamento. Fantasia
        // composta raramente colide, e contar todas custaria caro sem mudar decisão.
        if (fantasia && !fantasia.includes(' ') && fantasia.length >= 3) {
          const alvo = ` ${fantasia} `;
          for (const t of textos) {
            if (!(` ${t} `).includes(alvo)) continue;
            // Se o texto também traz o nome do fornecedor, a transação é dele — não conta
            // como evidência contra o apelido.
            if (nome && t.includes(nome.split(' ')[0])) continue;
            emTerceiros += 1;
          }
        }
        return {
          id: f.id, name: f.name, trade_name: f.trade_name, cnpj_cpf: f.cnpj_cpf,
          active: f.active !== false,
          lancamentos: contagem.get(f.id) ?? 0,
          fantasia_em_terceiros: emTerceiros,
        };
      });

      const problemas: ProblemaDeCadastro[] = [];
      for (const f of lista) problemas.push(...analisarFornecedor(f));

      return {
        total: lista.length,
        problemas: ordenarProblemas(problemas),
        duplicados: acharDuplicados(lista),
      };
    },
    staleTime: 60_000,
  });
}

/** Aplica a correção sugerida. Uma linha ou várias — o gesto é o mesmo. */
export function useCorrigirCadastro() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (
      v: { correcoes: Array<{ id: string; campo: 'trade_name' | 'active'; valor: string | boolean | null }> },
    ) => {
      // Agrupa por campo+valor: dezenas de "limpar fantasia" viram UMA escrita, em vez de
      // uma ida ao banco por fornecedor.
      const porAlvo = new Map<string, { campo: string; valor: unknown; ids: string[] }>();
      for (const c of v.correcoes) {
        const chave = `${c.campo}=${String(c.valor)}`;
        const atual = porAlvo.get(chave) ?? { campo: c.campo, valor: c.valor, ids: [] };
        atual.ids.push(c.id);
        porAlvo.set(chave, atual);
      }
      let feitas = 0;
      for (const { campo, valor, ids } of porAlvo.values()) {
        const { error } = await supabase.from('suppliers')
          .update({ [campo]: valor } as never).in('id', ids);
        if (error) throw error;
        feitas += ids.length;
      }
      return feitas;
    },
    onSuccess: (feitas) => {
      toast.success(`${feitas} cadastro(s) corrigido(s)`);
      qc.invalidateQueries({ queryKey: ['saude-cadastro-fornecedores'] });
      qc.invalidateQueries({ queryKey: ['suppliers'] });
    },
    onError: (e: Error) => toast.error(e.message || 'Não foi possível corrigir'),
  });
}
