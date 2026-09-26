// Para onde vai um gasto lançado à mão (Caixa, "+ Lançar"). A leitura do texto é a mesma do
// assistente do WhatsApp (categoriaPeloTexto): as portas sugerem a mesma categoria.
import { categoriaPeloTexto, type RegraFinanceira } from '../../supabase/functions/_shared/banking/proposals';

/**
 * Para onde o gasto vai, antes de gravar: a categoria escolhida; senão a padrão de quem
 * recebeu; senão o que o texto indica ("almoço" → Alimentação de campo). Sem nada, "Outras
 * despesas" — marcada como `reserva`, para quem chama saber que ninguém decidiu: numa
 * anotação do banco, mandar a reserva apagaria a categoria que o motor acharia sozinho.
 */
export function destinoDoGasto(
  escolhida: string, padraoDeQuem: { nome: string; categoria: string | null } | null,
  descricao: string, valor: number, regras: RegraFinanceira[],
): { categoria: string; porque: string | null; reserva: boolean } {
  if (escolhida) return { categoria: escolhida, porque: null, reserva: false };
  if (padraoDeQuem?.categoria) return { categoria: padraoDeQuem.categoria, porque: `padrão de ${padraoDeQuem.nome}`, reserva: false };
  const pelo = categoriaPeloTexto(descricao, regras, valor);
  if (pelo) return { categoria: pelo.categoria, porque: `pelo texto: ${pelo.motivo}`, reserva: false };
  return { categoria: 'Outras despesas', porque: 'não reconheci pelo texto — escolha a categoria se quiser outra', reserva: true };
}
