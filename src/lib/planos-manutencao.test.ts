// Planos de manutenção — a parte pura das telas (07/10/2026). O que se protege: o agrupamento da
// aba Revisões (e a receita prevista), o "Sugerir planos" a partir do histórico real (nome do
// serviço/peça, já que a maioria dos serviços concluídos tem sistema nulo), e a lista "sem plano"
// da Prospecção, que antes usava a data do ORÇAMENTO, ignorava OS mais nova e opt-out.
import { describe, it, expect } from 'vitest';
import {
  agruparRevisoes, alvosSemPlano, dataBR, hojeEmBrasilia, interruptorLigado, lerPalavras, prazoPorExtenso,
  sugerirPlanos, type ItemDoHistorico, type OrdemDaEmbarcacao, type PlanoNaView,
} from './planos-manutencao';

const linha = (over: Partial<PlanoNaView>): PlanoNaView => ({
  plan_id: 'p', vessel_id: 'v', vessel_name: 'Mar Azul', client_id: 'c', client_name: 'Carlos', client_phone: '5511999999999',
  opt_out: false, name: 'Revisão de motor', scope: null, estimated_value: 1000, interval_months: 12,
  last_service_at: '2025-10-20', last_service_order_id: null, next_due_on: '2026-10-20', window_opens_on: '2026-09-29',
  snoozed_until: null, dias_para_vencer: 13, situacao: 'na_janela', tem_os_agendada: false, ultimo_toque: null,
  respondeu_no_ciclo: false, ...over,
});

describe('agruparRevisoes', () => {
  it('separa vencendo em 30 dias, vencidas, adiadas e quem respondeu; soma a receita prevista', () => {
    const g = agruparRevisoes([
      linha({ plan_id: 'a', dias_para_vencer: 13, next_due_on: '2026-10-20', estimated_value: 1000 }),
      linha({ plan_id: 'b', dias_para_vencer: 45, next_due_on: '2026-11-21', situacao: 'em_dia', estimated_value: 9999 }),
      linha({ plan_id: 'c', dias_para_vencer: -5, next_due_on: '2026-10-02', situacao: 'vencida', estimated_value: '500' }),
      linha({ plan_id: 'd', dias_para_vencer: 3, situacao: 'adiada', estimated_value: 700 }),
      linha({ plan_id: 'e', dias_para_vencer: 2, next_due_on: '2026-10-09', respondeu_no_ciclo: true, estimated_value: null }),
    ]);
    expect(g.vencendo.map((l) => l.plan_id)).toEqual(['e', 'a']); // por vencimento
    expect(g.vencidas.map((l) => l.plan_id)).toEqual(['c']);
    expect(g.adiadas.map((l) => l.plan_id)).toEqual(['d']);
    expect(g.responderam.map((l) => l.plan_id)).toEqual(['e']);
    // 1000 + 500 + 0; o de 45 dias e o adiado ficam fora.
    expect(g.receitaPrevista).toBe(1500);
  });
});

describe('datas e textos', () => {
  it('dia de calendário não muda de dia; hoje é o de Brasília', () => {
    expect(dataBR('2026-11-05')).toBe('05/11/2026');
    expect(dataBR(null)).toBe('—');
    // 02:00 UTC do dia 8 ainda é dia 7 em Brasília — o "Serviço feito" antigo gravava o dia 8.
    expect(hojeEmBrasilia(new Date('2026-10-08T02:00:00Z'))).toBe('2026-10-07');
  });
  it('prazo por extenso', () => {
    expect(prazoPorExtenso(0)).toBe('vence hoje');
    expect(prazoPorExtenso(12)).toBe('vence em 12 dias');
    expect(prazoPorExtenso(-3)).toBe('venceu há 3 dias');
  });
  it('palavras e interruptores', () => {
    expect(lerPalavras('Bateria, inversor; bateria ,')).toEqual(['bateria', 'inversor']);
    expect(interruptorLigado(undefined)).toBe(true); // padrão 'on'
    expect(interruptorLigado('on')).toBe(true);
    expect(interruptorLigado('off')).toBe(false);
    expect(interruptorLigado('false')).toBe(false);
  });
});

describe('sugerirPlanos', () => {
  const item = (over: Partial<ItemDoHistorico>): ItemDoHistorico => ({
    dia: '2026-03-10', osId: 'os1', osNumero: 'OS-00010', sistema: null, texto: '', valor: 0, ...over,
  });

  it('reconhece a família pelo nome do serviço/peça (sistema nulo) e pega o último serviço', () => {
    const s = sugerirPlanos([
      item({ texto: 'REPARO DE CONVERSOR E CARREGADOR TECHNOMAA', valor: 300 }),
      item({ dia: '2026-06-01', osId: 'os2', osNumero: 'OS-00020', texto: 'Instalação 2x Carregador DC/DC 50A', valor: 444 }),
      item({ texto: 'Instalação de Ramal de Gás GLP Para Fogão', valor: 200 }),
      item({ texto: 'Bateria de lítio 100Ah', valor: 3500 }),
      item({ texto: 'Montagem de Pneu em Nova Roda', sistema: 'mecanico', valor: 100 }),
    ], []);
    const porChave = Object.fromEntries(s.map((x) => [x.familia.chave, x]));
    expect(Object.keys(porChave).sort()).toEqual(['baterias', 'carregador', 'gas']);
    expect(porChave.carregador.ultimoServico).toBe('2026-06-01');
    expect(porChave.carregador.ultimaOsNumero).toBe('OS-00020');
    expect(porChave.carregador.valorEstimado).toBe(440); // arredondado à dezena
    // "mecânico" sozinho (pneu) não vira revisão de motor
    expect(porChave.motor).toBeUndefined();
  });

  it('não sugere o que já tem plano, nem casa palavra dentro de outra (motorhome, gasolina)', () => {
    const s = sugerirPlanos([
      item({ texto: 'Bateria estacionária' }),
      item({ texto: 'Limpeza do motorhome' }),
      item({ texto: 'Galão de gasolina' }),
    ], [{ name: 'Revisão do banco de baterias', match_keywords: ['bateria'] }]);
    expect(s).toEqual([]);
  });
});

describe('alvosSemPlano (Prospecção › Revisões preventivas)', () => {
  const agora = new Date('2026-10-07T12:00:00Z');
  const os = (over: Partial<OrdemDaEmbarcacao>): OrdemDaEmbarcacao => ({
    vessel_id: 'v1', status: 'completed', created_at: '2025-01-10T12:00:00Z', check_out_at: '2026-02-15T15:00:00Z',
    scheduled_end_at: null, updated_at: '2026-02-20T12:00:00Z', vessel_name: 'Mar Azul', client_name: 'Carlos', opt_out: false,
    ...over,
  });

  it('usa a data do SERVIÇO (saída), não a do orçamento', () => {
    const [a] = alvosSemPlano([os({})], new Set(), agora);
    expect(a.ultimoServico).toBe('2026-02-15');
    expect(a.meses).toBe(7);
  });

  it('fora: serviço recente, quem já tem plano, quem pediu PARAR e quem tem OS mais nova', () => {
    expect(alvosSemPlano([os({ check_out_at: '2026-08-01T12:00:00Z' })], new Set(), agora)).toEqual([]);
    expect(alvosSemPlano([os({})], new Set(['v1']), agora)).toEqual([]);
    expect(alvosSemPlano([os({ opt_out: true })], new Set(), agora)).toEqual([]);
    expect(alvosSemPlano([
      os({}),
      os({ status: 'draft', created_at: '2026-09-01T12:00:00Z', check_out_at: null }),
    ], new Set(), agora)).toEqual([]);
  });

  it('OS cancelada depois do serviço não tira a embarcação da lista', () => {
    const r = alvosSemPlano([
      os({}),
      os({ status: 'cancelled', created_at: '2026-09-01T12:00:00Z', check_out_at: null }),
    ], new Set(), agora);
    expect(r).toHaveLength(1);
  });
});
