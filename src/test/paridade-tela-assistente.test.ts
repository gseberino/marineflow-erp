// Paridade: toda ação de lançamento que a TELA faz, o ASSISTENTE também faz.
//
// Pedido do dono (25/09/2026): qualquer inclusão, alteração ou ajuste de número, data ou
// fornecedor tem de estar pronto para o assistente — no painel e no WhatsApp. A forma de
// garantir isso sem depender de memória é esta: as ações de lançamento da tela passam por
// funções do banco, e cada função chamada pela tela precisa ser chamada por alguma tool.
// Se alguém criar um botão novo com uma função nova e esquecer o assistente, este teste cai.
import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const RAIZ = join(__dirname, '..', '..');
const HOOKS_DE_LANCAMENTO = ['src/hooks/use-lancamentos.ts', 'src/hooks/use-conciliacao.ts', 'src/hooks/use-financial.ts', 'src/hooks/use-contraparte.ts', 'src/hooks/use-fechamento.ts', 'src/hooks/use-extrato-conta.ts', 'src/hooks/use-caixa.ts'];
const PASTA_DAS_TOOLS = 'supabase/functions/_shared/ai/tools';

/** Funções do banco que MUDAM lançamento e que a tela chama. */
function funcoesDaTela(): Set<string> {
  const nomes = new Set<string>();
  for (const arq of HOOKS_DE_LANCAMENTO) {
    const texto = readFileSync(join(RAIZ, arq), 'utf8');
    // rpc('nome' …) e o helper chamar('nome', …) de use-lancamentos.ts
    for (const m of texto.matchAll(/(?:\.rpc|chamar|useAcaoDoCaixa(?:<[^>]*>)?)\(\s*'([a-z_]+)'/g)) nomes.add(m[1]);
  }
  return nomes;
}

function textoDasTools(): string {
  return readdirSync(join(RAIZ, PASTA_DAS_TOOLS))
    .filter((f) => f.endsWith('.ts') && !f.endsWith('_test.ts'))
    .map((f) => readFileSync(join(RAIZ, PASTA_DAS_TOOLS, f), 'utf8'))
    .join('\n');
}

describe('paridade tela ↔ assistente nos lançamentos', () => {
  it('a tela usa as quatro funções do caminho único', () => {
    const tela = funcoesDaTela();
    for (const f of ['corrigir_lancamento', 'desfazer_aprovacao', 'cancelar_lancamento', 'conciliar_lancamento',
      'cadastrar_contraparte', 'checklist_do_mes', 'fechar_mes', 'extrato_da_conta',
      'lancar_no_caixa', 'mover_caixa', 'ajustar_caixa', 'anotar_transacao']) {
      expect(tela.has(f), f).toBe(true);
    }
  });

  it('cada função que a tela chama também é chamada por uma tool do assistente', () => {
    const tools = textoDasTools();
    const faltando = [...funcoesDaTela()].filter((f) => !new RegExp(`["']${f}["']`).test(tools));
    expect(faltando).toEqual([]);
  });

  it('nenhuma tela grava lançamento direto na tabela (sem trilha, sem trava de mês)', () => {
    for (const arq of HOOKS_DE_LANCAMENTO) {
      const texto = readFileSync(join(RAIZ, arq), 'utf8');
      // Update direto em payables/receivables é o que deixava a trilha cega e o saldo velho.
      const diretos = [...texto.matchAll(/from\('(payables|receivables)'\)\s*\.update\(/g)];
      expect(diretos.map((m) => `${arq}: ${m[0]}`)).toEqual([]);
    }
  });
});

describe('paridade na categoria deduzida', () => {
  // Teste do dono (25/09/2026): "almoço" pelo WhatsApp caiu em Outras despesas. A tela do Caixa
  // e o assistente deduzem pela MESMA função — se um lado trocar de lógica, este teste cai.
  it('tela e assistente usam categoriaPeloTexto', () => {
    const tela = readFileSync(join(RAIZ, 'src/lib/destino-do-gasto.ts'), 'utf8');
    const assistente = readFileSync(join(RAIZ, PASTA_DAS_TOOLS, 'caixa.ts'), 'utf8');
    expect(tela).toContain('categoriaPeloTexto(');
    expect(assistente).toContain('categoriaPeloTexto(');
  });
});
