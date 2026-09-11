// NOVO-006 / NOVO-008 / NOVO-020 — as views do técnico e quem lê de onde.
//
// A parte incomum deste arquivo: ele LÊ a migration em disco e cobra dela o que a lista em
// código promete. Sem isso, `COLUNAS_DE_VALOR_DA_OS` seria só documentação — alguém
// acrescentaria `grand_total` à view meses depois e o teste continuaria verde, porque estaria
// testando a lista contra ela mesma. O mesmo padrão do teste de status da OS, que lê o CHECK
// da migration.
//
// O que este teste NÃO cobre, e nenhum teste local cobre: se o PostgREST enxerga os
// relacionamentos (clients/vessels/marinas e as views irmãs) a partir das views. Isso só o
// ambiente real responde — provado em 10/09/2026 com a chave anon (42501, não PGRST200).
import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import {
  COLUNAS_DE_VALOR_DA_OS,
  COLUNAS_DE_VALOR_DAS_PECAS,
  COLUNAS_DE_VALOR_DOS_SERVICOS,
  OS_TABELA,
  OS_VIEW_TECNICO,
  OS_PARTS_VIEW_TECNICO,
  OS_SERVICES_VIEW_TECNICO,
  VIEW_TECNICO_DISPONIVEL,
  fonteDeLeituraDaOS,
  leDaViewDoTecnico,
  payloadParaCargo,
} from './service-orders-source';

const PASTA_MIGRATIONS = join(process.cwd(), 'supabase', 'migrations');

function migrationDasViews(): string {
  const arquivo = readdirSync(PASTA_MIGRATIONS).find(f => f.includes('views_tecnico_sem_valores'));
  if (!arquivo) throw new Error('migration das views do técnico não encontrada em supabase/migrations');
  return readFileSync(join(PASTA_MIGRATIONS, arquivo), 'utf8');
}

/** Só o corpo do SELECT de UMA view — o cabeçalho de comentários cita colunas proibidas ao
 *  explicar o critério, e citá-las é justamente o que se espera de uma boa migration. */
function corpoDoSelect(sql: string, view: string, tabelaBase: string): string {
  const cabecalho = sql.indexOf(`CREATE OR REPLACE VIEW public.${view}`);
  expect(cabecalho, `não achei a view ${view} na migration`).toBeGreaterThan(-1);
  const inicio = sql.indexOf('SELECT', cabecalho);
  const fim = sql.indexOf(`FROM public.${tabelaBase};`, inicio);
  expect(fim, `não achei o FROM da view ${view}`).toBeGreaterThan(inicio);
  return sql.slice(inicio, fim);
}

const temColuna = (select: string, coluna: string) =>
  new RegExp(`(^|[\\s,(])${coluna}\\s*(,|$)`, 'm').test(select);

describe('fonteDeLeituraDaOS — quem lê de onde', () => {
  it('técnico lê da view quando ela existe', () => {
    expect(fonteDeLeituraDaOS('technician', true)).toBe(OS_VIEW_TECNICO);
    expect(leDaViewDoTecnico('technician', true)).toBe(true);
  });

  it('todos os outros cargos leem da tabela', () => {
    for (const cargo of ['admin', 'financial', 'seller', 'external_seller', 'other']) {
      expect(fonteDeLeituraDaOS(cargo, true), `cargo ${cargo}`).toBe(OS_TABELA);
      expect(leDaViewDoTecnico(cargo, true), `cargo ${cargo}`).toBe(false);
    }
  });

  it('cargo ausente ou desconhecido lê da tabela — a view é restrição de um cargo, não modo seguro', () => {
    expect(fonteDeLeituraDaOS(undefined, true)).toBe(OS_TABELA);
    expect(fonteDeLeituraDaOS(null, true)).toBe(OS_TABELA);
    expect(fonteDeLeituraDaOS('', true)).toBe(OS_TABELA);
    expect(fonteDeLeituraDaOS('cargo_que_nao_existe', true)).toBe(OS_TABELA);
  });

  it('com a view ainda não aplicada, ninguém é mandado para ela', () => {
    expect(fonteDeLeituraDaOS('technician', false)).toBe(OS_TABELA);
  });

  it('a chave de disponibilidade é o padrão da função', () => {
    expect(fonteDeLeituraDaOS('technician')).toBe(
      VIEW_TECNICO_DISPONIVEL ? OS_VIEW_TECNICO : OS_TABELA,
    );
  });
});

describe('payloadParaCargo — o Salvar do técnico não apaga o que não leu (NOVO-020b)', () => {
  const payload = {
    problem_description: 'Inversor não liga',
    technician_notes: 'Fusível queimado',
    status: 'in_progress',
    discount_amount: 0,          // semeado do form como 0 — NÃO é o valor negociado
    commission_rate: 3.5,        // default do form
    payment_conditions: '',
    grand_total: 0,
    financial_notes: null,
  };

  it('técnico: colunas de valor saem do payload, as operacionais ficam', () => {
    const limpo = payloadParaCargo('technician', payload, true);
    expect(limpo).toEqual({
      problem_description: 'Inversor não liga',
      technician_notes: 'Fusível queimado',
      status: 'in_progress',
    });
  });

  it('os outros cargos mandam o payload intacto', () => {
    for (const cargo of ['admin', 'financial', 'seller', undefined, null]) {
      expect(payloadParaCargo(cargo, payload, true), `cargo ${cargo}`).toEqual(payload);
    }
  });

  it('com a view desligada, nem o técnico é filtrado — ele leu da tabela e pode devolver tudo', () => {
    expect(payloadParaCargo('technician', payload, false)).toEqual(payload);
  });

  it('a lista de proibidas cobre as 12 colunas que o NOVO-020 viu sendo zeradas', () => {
    for (const c of [
      'discount_amount', 'tax_amount', 'subcontract_cost_total', 'commission_rate',
      'commission_amount', 'commissioned_user_id', 'payment_conditions',
      'payment_condition_preset_id', 'financial_notes', 'discount_services_pct',
      'discount_parts_pct', 'travel_cost_per_km',
    ]) {
      expect((COLUNAS_DE_VALOR_DA_OS as readonly string[]).includes(c), `${c} fora da lista`).toBe(true);
    }
  });
});

describe('a migration das views cumpre o que as listas em código prometem', () => {
  const sql = migrationDasViews();
  const os = corpoDoSelect(sql, OS_VIEW_TECNICO, 'service_orders');
  const pecas = corpoDoSelect(sql, OS_PARTS_VIEW_TECNICO, 'service_order_parts');
  const servicos = corpoDoSelect(sql, OS_SERVICES_VIEW_TECNICO, 'service_order_services');

  it('nenhuma coluna de valor da OS aparece na view da OS', () => {
    for (const coluna of COLUNAS_DE_VALOR_DA_OS) {
      expect(temColuna(os, coluna), `${coluna} está na view — é coluna de valor`).toBe(false);
    }
  });

  it('decisão (b) do dono: invoicing_status e payment_status ficaram de fora', () => {
    expect(temColuna(os, 'invoicing_status')).toBe(false);
    expect(temColuna(os, 'payment_status')).toBe(false);
    // O bloqueio de edição do formulário usa `status`, que fica.
    expect(temColuna(os, 'status')).toBe(true);
  });

  it('as views irmãs não têm preço, custo, total nem desconto por linha (NOVO-008)', () => {
    for (const coluna of COLUNAS_DE_VALOR_DAS_PECAS) {
      expect(temColuna(pecas, coluna), `${coluna} está na view de peças`).toBe(false);
    }
    for (const coluna of COLUNAS_DE_VALOR_DOS_SERVICOS) {
      expect(temColuna(servicos, coluna), `${coluna} está na view de serviços`).toBe(false);
    }
  });

  it('as três views são security_invoker — senão ignoram a RLS da tabela base', () => {
    // Conta a cláusula de CRIAÇÃO, não menções no comentário (que também citam o termo).
    const ocorrencias = sql.match(/WITH\s*\(\s*security_invoker\s*=\s*on\s*\)/gi) ?? [];
    expect(ocorrencias.length).toBe(3);
  });

  it('anônimo é revogado e authenticated recebe SELECT, nas três, na mesma migration', () => {
    for (const view of [OS_VIEW_TECNICO, OS_PARTS_VIEW_TECNICO, OS_SERVICES_VIEW_TECNICO]) {
      expect(sql).toMatch(new RegExp(`REVOKE\\s+ALL\\s+ON\\s+public\\.${view}\\s+FROM\\s+anon`, 'i'));
      expect(sql).toMatch(new RegExp(`REVOKE\\s+ALL\\s+ON\\s+public\\.${view}\\s+FROM\\s+PUBLIC`, 'i'));
      expect(sql).toMatch(new RegExp(`GRANT\\s+SELECT\\s+ON\\s+public\\.${view}\\s+TO\\s+authenticated`, 'i'));
    }
  });

  it('nenhuma view usa SELECT * — coluna de valor nova entraria sozinha', () => {
    expect(os).not.toMatch(/SELECT\s+\*/i);
    expect(pecas).not.toMatch(/SELECT\s+\*/i);
    expect(servicos).not.toMatch(/SELECT\s+\*/i);
  });

  it('as colunas que a tela do técnico precisa continuam lá', () => {
    for (const coluna of [
      'id', 'service_order_number', 'client_id', 'vessel_id', 'marina_id',
      'status', 'priority', 'problem_description', 'technician_notes',
      'scheduled_start_at', 'check_in_at', 'check_out_at', 'photos', 'survey_id',
    ]) {
      expect(temColuna(os, coluna), `${coluna} sumiu da view`).toBe(true);
    }
    for (const coluna of ['id', 'service_order_id', 'product_id', 'quantity', 'service_order_service_id']) {
      expect(temColuna(pecas, coluna), `${coluna} sumiu da view de peças`).toBe(true);
    }
    for (const coluna of ['id', 'service_order_id', 'service_id', 'name_snapshot', 'quantity', 'technician_user_id']) {
      expect(temColuna(servicos, coluna), `${coluna} sumiu da view de serviços`).toBe(true);
    }
  });
});
