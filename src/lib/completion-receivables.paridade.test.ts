// Paridade dos recebíveis da conclusão: o TS de hoje × o banco (Agenda de Produção, Fase 3, P2 — 24/10/2026).
//
// A porta única de status passa a concluir a OS no banco e lança as cobranças por _os_recebiveis_da_conclusao
// (migration 20261026100100), um espelho de recebiveisDaConclusao. O dono decidiu que a porta MANTÉM A PARIDADE com a
// tela: a mesma regra de dinheiro, sem correção no caminho (corrigir o NOVO-agenda-22 é decisão dele).
//
// scripts/bancada-agenda/recebiveis-casos.json tem os casos fixos (≥ 20) e os 21 do replay das conclusões reais, cada um
// com o esperado que o TS de hoje dá. Este teste confere o TS contra o esperado; supabase/tests/agenda_fase3_recebiveis.sql
// confere o banco contra o MESMO esperado, linha a linha. Se um dos lados mudar, um dos dois reprova.
//
// Para regerar o esperado (só quando a regra mudar de propósito, com o OK do dono, ou quando o replay for regerado):
//   REGERAR_RECEBIVEIS_CASOS=1 npx vitest run src/lib/completion-receivables.paridade.test.ts
import { describe, expect, it, vi } from 'vitest';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

vi.mock('@/integrations/supabase/client', () => ({ supabase: {} }));

import {
  parcelasDaCondicao,
  recebiveisDaConclusao,
  type OsDaConclusao,
  type RecebiveisDaConclusao,
} from './completion-receivables';

interface Caso {
  nome: string;
  replay?: boolean;
  os: OsDaConclusao;
  preset_installments?: unknown;
  custom_payment_installments: unknown;
  data: string;
  existentes: { status: string | null; is_deposit?: boolean; amount?: number }[];
  esperado: RecebiveisDaConclusao | null;
}

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const ARQUIVO = join(RAIZ, 'scripts', 'bancada-agenda', 'recebiveis-casos.json');
const REGERAR = process.env.REGERAR_RECEBIVEIS_CASOS === '1';

const doc = JSON.parse(readFileSync(ARQUIVO, 'utf8')) as { nota: string; casos: Caso[] };

/** O que o TS de hoje dá para o caso: as parcelas resolvidas como ensureCompletionReceivables resolve. */
const calcular = (c: Caso) =>
  recebiveisDaConclusao(c.os, parcelasDaCondicao(c.preset_installments, c.custom_payment_installments), c.data, c.existentes);

if (REGERAR) {
  for (const c of doc.casos) c.esperado = calcular(c);
  writeFileSync(ARQUIVO, JSON.stringify(doc, null, 2) + '\n');
}

const manuais = doc.casos.filter((c) => !c.replay);
const replay = doc.casos.filter((c) => c.replay);
const porNome = (trecho: string) => {
  const c = doc.casos.find((x) => x.nome.includes(trecho));
  if (!c) throw new Error(`não achei o caso "${trecho}" em recebiveis-casos.json`);
  return c;
};

describe('recebiveis-casos.json (a régua que o banco também usa)', () => {
  it('tem pelo menos 20 casos fixos e os 21 do replay, com nomes únicos e números de OS únicos', () => {
    expect(manuais.length).toBeGreaterThanOrEqual(20);
    expect(replay.length).toBe(21);
    expect(new Set(doc.casos.map((c) => c.nome)).size).toBe(doc.casos.length);
    expect(new Set(doc.casos.map((c) => c.os.service_order_number)).size).toBe(doc.casos.length);
  });

  it('todo caso tem o esperado gravado (rode com REGERAR_RECEBIVEIS_CASOS=1 depois de gerar casos novos)', () => {
    expect(doc.casos.filter((c) => !c.esperado).map((c) => c.nome)).toEqual([]);
  });

  it('os casos fixos passam pelos quatro motivos', () => {
    expect(new Set(manuais.map((c) => c.esperado?.motivo))).toEqual(new Set(['ja_tem', 'parcelas', 'titulo_unico', 'total_zero']));
  });
});

describe('o TS de hoje dá o esperado de cada caso', () => {
  it.each(doc.casos.map((c) => [c.nome, c] as const))('%s', (_nome, c) => {
    expect(calcular(c)).toEqual(c.esperado);
  });
});

describe('os casos que documentam a regra (paridade intencional)', () => {
  it('1,005 arredonda como o JavaScript (Math.round sobre double): 1,00, não 1,01', () => {
    const c = porNome('1,005');
    expect(c.esperado?.linhas.map((l) => l.amount)).toEqual([1, 1]);
  });

  it('NOVO-agenda-22: só o sinal pago e a condição com saldo na entrega → nenhuma cobrança do saldo (ja_tem)', () => {
    // Paridade INTENCIONAL com a tela (decisão de 24/10): a OS que só tem o sinal não ganha o saldo na conclusão.
    // Corrigir é decisão do dono (está na lista dele); quando vier, este caso muda junto com o SQL, de propósito.
    const c = porNome('NOVO-agenda-22');
    expect(c.existentes).toEqual([{ status: 'paid', is_deposit: true, amount: 4500 }]);
    expect(c.esperado).toEqual({ motivo: 'ja_tem', linhas: [] });
  });

  it('o título único é o número como está (sem "OS " na frente) e vence em 30 dias', () => {
    const c = porNome('ainda com ORÇ-');
    expect(c.esperado?.linhas).toEqual([
      { description: 'ORÇ-90027', issue_date: '2026-10-27', due_date: '2026-11-26', amount: 1234.56, due_on_completion: false },
    ]);
  });

  it('a parcela "na entrega" vence no dia da conclusão e marca due_on_completion; as outras não', () => {
    const c = porNome('50% do serviço na aprovação');
    expect(c.esperado?.linhas.map((l) => [l.description, l.due_date, l.due_on_completion])).toEqual([
      [`Entrada — ${c.os.service_order_number}`, '2026-10-27', false],
      [`Saldo na entrega — ${c.os.service_order_number}`, '2026-10-27', true],
    ]);
  });
});

describe('parcelasDaCondicao (a mesma resolução de ensureCompletionReceivables)', () => {
  it('preset em lista vence; preset que não é lista cai nas personalizadas; nada é null', () => {
    const p = [{ label: 'P' }];
    const q = [{ label: 'Q' }];
    expect(parcelasDaCondicao(p, q)).toBe(p);
    expect(parcelasDaCondicao([], q)).toEqual([]);
    expect(parcelasDaCondicao({ x: 1 }, q)).toBe(q);
    expect(parcelasDaCondicao(undefined, q)).toBe(q);
    expect(parcelasDaCondicao(null, null)).toBeNull();
  });
});
