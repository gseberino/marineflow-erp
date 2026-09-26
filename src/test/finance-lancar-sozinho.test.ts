// O que o sistema lança sem clique. Cada "não" aqui é um jeito de errar calado que ficou
// de fora de propósito.
import { describe, it, expect } from 'vitest';
import { motivoParaNaoLancarSozinho, selecionarParaLancarSozinho } from '../../supabase/functions/finance-review/lancar-sozinho';

const base = {
  kind: 'create_payable', bank_transaction_id: 't1', confidence: 90, suggested_amount: 120,
  suggested_category: 'Combustível e deslocamento', vinculo_sugerido: null,
};
const criterio = { confiancaMinima: 85, limiteLote: 500, comAlerta: new Set<string>(), jaPorRegra: new Set<string>() };

describe('lançar sozinho', () => {
  it('saída de confiança alta, pequena e categorizada vai sozinha', () => {
    expect(motivoParaNaoLancarSozinho(base, criterio)).toBeNull();
  });

  it('cada limite tem o seu motivo', () => {
    expect(motivoParaNaoLancarSozinho({ ...base, kind: 'create_receivable' }, criterio)).toMatch(/só saída/);
    expect(motivoParaNaoLancarSozinho({ ...base, confidence: 84 }, criterio)).toMatch(/confiança/);
    expect(motivoParaNaoLancarSozinho({ ...base, suggested_amount: 500 }, criterio)).toMatch(/limite/);
    expect(motivoParaNaoLancarSozinho({ ...base, suggested_category: 'Outras despesas' }, criterio)).toMatch(/categoria/);
    expect(motivoParaNaoLancarSozinho(base, { ...criterio, comAlerta: new Set(['t1']) })).toMatch(/vigilante/);
    expect(motivoParaNaoLancarSozinho(base, { ...criterio, jaPorRegra: new Set(['t1']) })).toMatch(/regra/);
  });

  it('configurar abaixo de 85 não afrouxa o piso', () => {
    expect(motivoParaNaoLancarSozinho({ ...base, confidence: 70 }, { ...criterio, confiancaMinima: 60 })).toMatch(/confiança/);
  });

  it('o que pode já estar lançado nunca vai sozinho', () => {
    const linha = { ...base, vinculo_sugerido: { principal: {
      tipo: 'existing_payment', id: 'pg', rotulo: 'Pagamento já lançado: x', valor: 120, confianca: 60, nivel: 'weak',
      motivos: [], diferenca: 0, lancamentoId: 'p', lado: 'payable', ordemDeServicoId: null, clienteId: null,
      clienteNome: null, converteOrcamento: false, jaLancado: true,
    }, alternativas: [] } } as never;
    expect(motivoParaNaoLancarSozinho(linha, criterio)).toMatch(/já estar lançada/);
    expect(selecionarParaLancarSozinho([base, linha], criterio)).toEqual([base]);
  });
});

describe("travas de 26/09/2026 (achadas antes da primeira rodada)", () => {
  it("regra marcada 'só sugerir' não lança sozinha, mesmo com confiança 95", () => {
    expect(motivoParaNaoLancarSozinho({ ...base, confidence: 95, regra_so_sugere: true }, criterio)).toMatch(/só sugerir/);
  });

  it("o que fica fora do resultado não vai sozinho por confiança", () => {
    const fatura = { ...base, suggested_category: "Pagamento de fatura de cartão", dre_group: "nao_operacional", confidence: 95 };
    expect(motivoParaNaoLancarSozinho(fatura, criterio)).toMatch(/fora do resultado/);
  });

  it("compra no débito sem loja nunca vai sozinha", () => {
    expect(motivoParaNaoLancarSozinho({ ...base, sem_identidade: true }, criterio)).toMatch(/não informou/);
  });

  it("sem as marcas novas, a linha boa continua indo", () => {
    expect(motivoParaNaoLancarSozinho({ ...base, dre_group: "custo_direto", regra_so_sugere: false, sem_identidade: false }, criterio)).toBeNull();
  });
});
