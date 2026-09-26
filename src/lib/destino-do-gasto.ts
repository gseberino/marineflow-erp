// Para onde vai um gasto lançado à mão (Caixa, "+ Lançar"). A leitura do texto é a do
// Extrato e a do assistente do WhatsApp: as três portas sugerem a mesma categoria.
import { categoriaPeloTexto, type RegraFinanceira } from '../../supabase/functions/_shared/banking/proposals';

/**
 * Para onde o gasto vai, antes de gravar: a categoria escolhida; senão a padrão de quem
 * recebeu; senão o que o texto indica ("almoço" → Alimentação de campo) — a mesma leitura
 * que o assistente do WhatsApp faz (categoriaPeloTexto). Sem nada, "Outras despesas".
 */
export function destinoDoGasto(
  escolhida: string, padraoDeQuem: { nome: string; categoria: string | null } | null,
  descricao: string, valor: number, regras: RegraFinanceira[],
): { categoria: string; porque: string | null } {
  if (escolhida) return { categoria: escolhida, porque: null };
  if (padraoDeQuem?.categoria) return { categoria: padraoDeQuem.categoria, porque: `padrão de ${padraoDeQuem.nome}` };
  const pelo = categoriaPeloTexto(descricao, regras, valor);
  if (pelo) return { categoria: pelo.categoria, porque: `pelo texto: ${pelo.motivo}` };
  return { categoria: 'Outras despesas', porque: 'não reconheci pelo texto — escolha a categoria se quiser outra' };
}
