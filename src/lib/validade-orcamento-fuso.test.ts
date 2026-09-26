import { describe, it, expect, afterEach } from 'vitest';
import { ultimoDiaDaValidade, validadeDoOrcamento } from '../../supabase/functions/_shared/pdf/documento';
import { diaBR } from '../../supabase/functions/_shared/pdf/datas';

/**
 * O vencimento do orçamento não depende do fuso de quem calcula.
 *
 * ═══ POR QUE ESTE TESTE EXISTE ═══
 *
 * Desde 26/09/2026 o vencimento vira uma TAREFA para o dono (R19 do task-automations), no
 * lugar da rejeição automática. A regra roda numa Edge Function, em UTC; o PDF que o cliente
 * lê é gerado no navegador, em Brasília. Se a conta dependesse do relógio da máquina, um
 * orçamento criado às 23h30 teria um "até" no PDF e outro dia de aviso no motor.
 *
 * Os testes Deno (task-automations/rules_test.ts) cobrem a regra, mas o Deno no Windows
 * ignora a variável TZ; a prova de que o fuso da máquina não interfere é esta, no vitest,
 * que respeita process.env.TZ. A R19 compara `diaBR(agora) > ultimoDiaDaValidade(...)`.
 */

const FUSOS = ['America/Sao_Paulo', 'UTC', 'Asia/Tokyo', 'America/Los_Angeles'];
const FUSO_ORIGINAL = process.env.TZ;

afterEach(() => {
  // `process.env.TZ = undefined` grava a STRING "undefined" (fuso desconhecido = UTC).
  if (FUSO_ORIGINAL === undefined) delete process.env.TZ;
  else process.env.TZ = FUSO_ORIGINAL;
});

describe('vencimento do orçamento em qualquer fuso', () => {
  for (const fuso of FUSOS) {
    it(`orçamento das 23h30 vence no dia certo em ${fuso}`, () => {
      process.env.TZ = fuso;
      // 23h30 de 19/09 em Brasília = 02h30 UTC de 20/09; 3 dias → "até 22/09" no PDF.
      const orcamento = { created_at: '2026-09-20T02:30:00Z', quote_validity_days: 3 };
      const fim = ultimoDiaDaValidade(orcamento, { quote_validity_days: '15' });
      expect(fim).toBe('2026-09-22');
      // 23h de 22/09 em Brasília: ainda vale.
      expect(diaBR(new Date('2026-09-23T02:00:00Z')) > fim!).toBe(false);
      // 00h30 de 23/09 em Brasília: venceu.
      expect(diaBR(new Date('2026-09-23T03:30:00Z')) > fim!).toBe(true);
    });
  }

  it('a validade segue orçamento → empresa → 15, igual ao formulário', () => {
    // A conta antiga do formulário: form.quote_validity_days || Number(settings ?? 15) || 15
    const antiga = (dias: unknown, ajuste: unknown) => Number(dias) || Number(ajuste ?? 15) || 15;
    for (const dias of [7, 0, null, undefined, '10', 'x']) {
      for (const ajuste of ['3', undefined, '', 'lixo']) {
        expect(validadeDoOrcamento(dias, { quote_validity_days: ajuste }).days).toBe(antiga(dias, ajuste));
      }
    }
  });
});
