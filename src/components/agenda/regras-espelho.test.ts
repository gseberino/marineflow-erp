import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Toda regra do motor aparece na tela de Configurações › Automações.
 *
 * A lista da tela (RULE_DEFS em TaskAutomationSettings.tsx) é uma cópia à mão de RULES
 * (supabase/functions/task-automations/rules.ts). Regra que só existe no motor roda — com
 * defaultEnabled — mas não tem chave para desligar: o dono não tem como saber que ela
 * existe nem como pará-la. A R19 (orçamento vencido, 26/09/2026) quase entrou assim.
 *
 * Leitura por texto: rules.ts é código Deno e não é importável pelo build do front.
 */
const ler = (...partes: string[]) => readFileSync(join(process.cwd(), ...partes), 'utf8');

const idsDoMotor = [...ler('supabase', 'functions', 'task-automations', 'rules.ts').matchAll(/^\s+id: '(r\d+)',$/gm)]
  .map((m) => m[1]);
const idsDaTela = [...ler('src', 'components', 'agenda', 'TaskAutomationSettings.tsx').matchAll(/\{ id: '(r\d+)'/g)]
  .map((m) => m[1]);

describe('regras do motor × tela de configurações', () => {
  it('a varredura achou as regras (não passa lendo zero)', () => {
    expect(idsDoMotor.length).toBeGreaterThanOrEqual(15);
    expect(idsDoMotor).toContain('r19');
  });

  it('toda regra do motor tem chave na tela', () => {
    const faltando = idsDoMotor.filter((id) => !idsDaTela.includes(id));
    expect(faltando).toEqual([]);
  });
});
