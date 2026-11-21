// Fatura FAT-N do "Fechar juntas" (Fase 1, 20/11/2026): as regras que a tela mostra ANTES do clique.
// Quem decide é o banco (fatura_criar / fatura_receber, migration 20270220100000); aqui é a mesma regra
// repetida para o aviso aparecer antes do botão — se as duas divergirem, vale a do banco.

/** No texto do Cobrar juntas, o lugar do número da fatura que ainda vai nascer no envio. */
export const NUMERO_DA_FATURA_NOVA = 'FAT-(número ao enviar)';

/** Status da OS que conta como "já executada" para a fatura (o mesmo de _fatura_impedimento). */
export const STATUS_QUE_FATURAM: readonly string[] = ['completed', 'invoiced'];

/** A OS entra em fatura? Concluída ou faturada, com número de OS (orçamento fora) e não agrupada noutra. */
export function osEntraNaFatura(os: { status?: string | null; merged_into_id?: string | null } | null | undefined, numero?: string | null): boolean {
  return !!os && !os.merged_into_id && STATUS_QUE_FATURAM.includes(String(os.status))
    && String(numero ?? '').startsWith('OS-');
}

/** Põe o número de verdade no lugar do provisório (se a pessoa apagou a linha, a mensagem fica como está). */
export function colocarNumeroDaFatura(mensagem: string, numero: string): string {
  return mensagem.split(NUMERO_DA_FATURA_NOVA).join(numero);
}

export interface PreviaDoRecebimento {
  /** O banco vai aceitar (sobra até R$ 10 no Pix, ou falta). */
  pode: boolean;
  mensagem: string;
}

const RECEITA = 10;  // dono, 02/10/2026: até R$ 10 a mais é receita
const AVALIAR = 100; // acima de R$ 100, avaliar o porquê

/**
 * O que acontece com `valor` recebido numa fatura com `saldo` (a mesma regra de fatura_receber).
 * Pix: até R$ 10 a mais vira receita da última conta; entre R$ 10 e R$ 100 é decisão do dono; acima,
 * avaliar. Dinheiro a mais: recusa (o resto é troco). A menos: recebimento parcial.
 */
export function previaDoRecebimento(
  valor: number,
  saldo: number,
  forma: 'pix' | 'dinheiro',
  brl: (v: number) => string,
): PreviaDoRecebimento {
  const v = Math.round(valor * 100) / 100;
  const s = Math.round(saldo * 100) / 100;
  if (!(v > 0)) return { pode: false, mensagem: 'Diga quanto foi recebido.' };
  if (!(s > 0)) return { pode: false, mensagem: 'Esta fatura não tem saldo a receber.' };
  const sobra = Math.round((v - s) * 100) / 100;
  if (sobra > 0.005) {
    if (forma === 'dinheiro') {
      return { pode: false, mensagem: `Passa do saldo da fatura (${brl(s)}) em ${brl(sobra)}. Registre só o saldo: o resto é troco.` };
    }
    if (sobra > AVALIAR) {
      return { pode: false, mensagem: `Passa do saldo da fatura (${brl(s)}) em ${brl(sobra)}. Acima de R$ 100 é preciso avaliar o porquê antes: pode ser outra conta do cliente ou crédito dele.` };
    }
    if (sobra > RECEITA) {
      return { pode: false, mensagem: `Passa do saldo da fatura (${brl(s)}) em ${brl(sobra)}. Entre R$ 10 e R$ 100 a mais é decisão do dono: a sobra é sinal/adiantamento ou o Pix também paga outra conta?` };
    }
    return { pode: true, mensagem: `Quita a fatura; os ${brl(sobra)} a mais viram receita da última conta.` };
  }
  if (sobra < -0.005) {
    return { pode: true, mensagem: `Recebimento parcial: a conta que vence primeiro recebe primeiro e ficam faltando ${brl(-sobra)} na fatura.` };
  }
  return { pode: true, mensagem: 'Quita a fatura.' };
}
