// O DRE é onde um erro de sinal ou de agrupamento vira decisão errada de negócio.
import { describe, it, expect } from 'vitest';
import { montarDRE, doMes, type LancamentoDRE } from '@/lib/dre';

const l = (o: Partial<LancamentoDRE>): LancamentoDRE => ({
  data: '2026-07-15', valor: 1000, categoria: 'X', grupo: 'despesa_operacional', tipo: 'despesa', ...o,
});

describe('montagem do resultado', () => {
  it('receita menos custo direto dá o lucro bruto', () => {
    const r = montarDRE([
      l({ grupo: 'receita', tipo: 'receita', valor: 10000, categoria: 'Serviços prestados' }),
      l({ grupo: 'custo_direto', valor: 3000, categoria: 'Peças e materiais' }),
    ]);
    expect(r.linhas.find((x) => x.chave === 'lucro_bruto')!.valor).toBe(7000);
  });

  it('desce até o resultado do período passando por cada etapa', () => {
    const r = montarDRE([
      l({ grupo: 'receita', tipo: 'receita', valor: 10000 }),
      l({ grupo: 'custo_direto', valor: 3000 }),
      l({ grupo: 'despesa_operacional', valor: 2000 }),
      l({ grupo: 'financeiro', valor: 500 }),
    ]);
    expect(r.linhas.find((x) => x.chave === 'resultado_operacional')!.valor).toBe(5000);
    expect(r.resultado).toBe(4500);
  });

  it('NÃO OPERACIONAL fica fora do resultado', () => {
    // O erro que mais engana num resultado caseiro: pagamento de fatura de cartão soma
    // R$ 30 mil no extrato desta empresa e não é despesa — a despesa está nos itens da
    // fatura. Jogá-lo aqui transformaria mês bom em prejuízo.
    const semFatura = montarDRE([
      l({ grupo: 'receita', tipo: 'receita', valor: 10000 }),
      l({ grupo: 'despesa_operacional', valor: 2000 }),
    ]);
    const comFatura = montarDRE([
      l({ grupo: 'receita', tipo: 'receita', valor: 10000 }),
      l({ grupo: 'despesa_operacional', valor: 2000 }),
      l({ grupo: 'nao_operacional', valor: 30000, categoria: 'Pagamento de fatura de cartão' }),
    ]);
    expect(comFatura.resultado).toBe(semFatura.resultado);
    expect(comFatura.naoOperacional).toBe(30000);
  });

  it('denuncia lançamento sem grupo em vez de engolir', () => {
    // Sem grupo o valor não entra em linha nenhuma. Se o total não avisasse, ele mentiria
    // por omissão — e foi assim que R$ 64 mil sumiram antes da auditoria.
    const r = montarDRE([
      l({ grupo: 'receita', tipo: 'receita', valor: 10000 }),
      l({ grupo: null, valor: 4500, categoria: 'Categoria órfã' }),
    ]);
    expect(r.semGrupo).toBe(4500);
    expect(r.resultado).toBe(10000);
  });

  it('abre cada grupo em categorias, da maior para a menor', () => {
    const r = montarDRE([
      l({ grupo: 'despesa_operacional', valor: 100, categoria: 'Telefonia' }),
      l({ grupo: 'despesa_operacional', valor: 900, categoria: 'Aluguel' }),
      l({ grupo: 'despesa_operacional', valor: 300, categoria: 'Software' }),
    ]);
    const det = r.linhas.find((x) => x.chave === 'despesa_operacional')!.detalhe!;
    expect(det.map((d) => d.categoria)).toEqual(['Aluguel', 'Software', 'Telefonia']);
  });

  it('percentual é sobre a receita, e some quando não há receita', () => {
    const comReceita = montarDRE([
      l({ grupo: 'receita', tipo: 'receita', valor: 10000 }),
      l({ grupo: 'custo_direto', valor: 2500 }),
    ]);
    expect(comReceita.linhas.find((x) => x.chave === 'custo_direto')!.percentual).toBe(-25);

    const semReceita = montarDRE([l({ grupo: 'custo_direto', valor: 2500 })]);
    expect(semReceita.linhas.find((x) => x.chave === 'custo_direto')!.percentual).toBeNull();
  });

  it('resultado negativo é prejuízo, não zero', () => {
    const r = montarDRE([
      l({ grupo: 'receita', tipo: 'receita', valor: 1000 }),
      l({ grupo: 'despesa_operacional', valor: 4000 }),
    ]);
    expect(r.resultado).toBe(-3000);
  });
});

describe('recorte por mês', () => {
  it('não perde o dia 1º por causa de fuso horário', () => {
    // new Date('2026-07-01') em UTC-3 volta para 30/06 e o lançamento cairia no mês
    // anterior — erro que só aparece na virada do mês, quando já foi conferido.
    const dados = [l({ data: '2026-07-01' }), l({ data: '2026-06-30' }), l({ data: '2026-07-31' })];
    expect(doMes(dados, 2026, 7)).toHaveLength(2);
    expect(doMes(dados, 2026, 6)).toHaveLength(1);
  });
});
