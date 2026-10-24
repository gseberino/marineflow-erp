// Gera o replay das conclusões reais (Agenda de Produção, Fase 3, P2) a partir do SELECT de produção.
// Nada vai para produção; não lê .env nem credencial: só lê o arquivo que o SELECT gravou.
//
//   1. Rode o SELECT (só leitura) scratchpad/agenda-pesquisa/sql/i06_replay_export.sql pelo q0.sh, que grava uma linha
//      JSON por OS concluída ou faturada.
//   2. node scripts/bancada-agenda/gerar-replay-conclusoes.mjs <saída do SELECT> [AAAA-MM-DD do corte]
//      Escreve scripts/bancada-agenda/fixture-replay-conclusoes.sql e troca, em recebiveis-casos.json, os casos do replay
//      (os manuais ficam), com o esperado vazio.
//   3. REGERAR_RECEBIVEIS_CASOS=1 npx vitest run src/lib/completion-receivables.paridade.test.ts
//      O TS de hoje (recebiveisDaConclusao) preenche o esperado de cada caso; sem a variável, o mesmo teste só confere.
//   4. node scripts/bancada-agenda/rodar.mjs: agenda_fase3_replay_conclusoes.sql confere a classe de cada OS e o banco =
//      TS; agenda_fase3_recebiveis.sql confere todos os casos.
//
// A fixture leva só número e estrutura: o número da OS, os totais, a condição (as parcelas do preset e as personalizadas),
// a saída, a criação e cada recebível com valor, datas, flags e created_at. Sem nome, documento, telefone, descrição de
// recebível nem id de produção (os ids e o cliente são sintéticos na bancada).
//
// O estado ANTES da saída (o que a tela via ao concluir) é a mesma regra aqui e no teste SQL: os recebíveis criados mais de
// 5 minutos antes da saída, mais os sinais criados até a saída (o sinal registrado no mesmo minuto da conclusão existia
// quando a tela conferiu). O teste SQL confere que os dois lados acham o mesmo conjunto.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const [, , entrada, corte = '2026-10-24'] = process.argv;
if (!entrada) {
  console.error('uso: node scripts/bancada-agenda/gerar-replay-conclusoes.mjs <saída do i06_replay_export> [AAAA-MM-DD do corte]');
  process.exit(2);
}

const texto = readFileSync(entrada, 'utf8').trim();
let linhas;
try {
  const d = JSON.parse(texto);
  linhas = Array.isArray(d) ? d : d.rows;
} catch {
  linhas = texto.split('\n').filter(Boolean).map((l) => JSON.parse(l));
}
if (!Array.isArray(linhas) || linhas.length === 0) throw new Error('o SELECT não trouxe nenhuma OS');

const CINCO_MIN = 5 * 60 * 1000;
const num = (v) => (v === null || v === undefined ? null : Number(v));
const sqlTexto = (v) => (v === null || v === undefined ? 'null' : `'${String(v).replace(/'/g, "''")}'`);
const sqlNum = (v) => (v === null || v === undefined ? 'null' : String(Number(v)));
const sqlBool = (v) => (v === null || v === undefined ? 'null' : v ? 'true' : 'false');
const sqlJson = (v) => (v === null || v === undefined ? 'null' : `${sqlTexto(JSON.stringify(v))}::jsonb`);
const diaBrasilia = (iso) => new Date(Date.parse(iso) - 3 * 3600 * 1000).toISOString().slice(0, 10);

/** O recebível existia quando a tela concluiu? (a regra do estado antes da saída) */
function antesDaSaida(r, saida) {
  const criado = Date.parse(r.created_at);
  return criado < saida - CINCO_MIN || (r.is_deposit === true && criado <= saida);
}

const osSql = [];
const recSql = [];
const casos = [];
for (const o of linhas) {
  if (!o.check_out_at) throw new Error(`${o.numero} está ${o.status} sem saída: o replay precisa da saída`);
  const saida = Date.parse(o.check_out_at);
  osSql.push(`  (${[
    sqlTexto(o.numero), sqlTexto(o.status), sqlTexto(o.check_out_at), sqlTexto(o.created_at), sqlTexto(o.converted_to_os_at),
    sqlNum(o.labor_cost_total), sqlNum(o.parts_cost_total), sqlNum(o.operational_cost_total), sqlNum(o.travel_cost_total),
    sqlNum(o.subcontract_cost_total), sqlBool(o.is_travel_billable), sqlNum(o.discount_amount), sqlNum(o.tax_amount),
    sqlNum(o.grand_total), sqlBool(o.tem_preset && o.preset_existe), sqlJson(o.preset_installments),
    sqlJson(o.custom_payment_installments),
  ].join(', ')})`);
  (o.recebiveis ?? []).forEach((r, i) => {
    recSql.push(`  (${[
      sqlTexto(o.numero), i + 1, sqlNum(r.amount), sqlTexto(r.status), sqlBool(r.is_deposit), sqlBool(r.due_on_completion),
      sqlTexto(r.issue_date), sqlTexto(r.due_date), sqlNum(r.paid_amount), sqlNum(r.balance_amount), sqlTexto(r.created_at),
    ].join(', ')})`);
  });
  casos.push({
    nome: `replay ${o.numero} (${diaBrasilia(o.check_out_at)})`,
    replay: true,
    os: {
      service_order_number: o.numero,
      grand_total: num(o.grand_total),
      labor_cost_total: num(o.labor_cost_total),
      parts_cost_total: num(o.parts_cost_total),
      operational_cost_total: num(o.operational_cost_total),
      travel_cost_total: num(o.travel_cost_total),
      subcontract_cost_total: num(o.subcontract_cost_total),
      is_travel_billable: o.is_travel_billable,
      discount_amount: num(o.discount_amount),
      tax_amount: num(o.tax_amount),
    },
    ...(o.tem_preset && o.preset_existe ? { preset_installments: o.preset_installments } : {}),
    custom_payment_installments: o.custom_payment_installments ?? null,
    data: diaBrasilia(o.check_out_at),
    existentes: (o.recebiveis ?? [])
      .filter((r) => antesDaSaida(r, saida))
      .map((r) => ({ status: r.status, is_deposit: r.is_deposit, amount: num(r.amount) })),
    esperado: null,
  });
}

const fixture = `-- Replay das conclusões reais (Agenda de Produção, Fase 3, P2): as ${linhas.length} OS concluídas ou faturadas de produção
-- até ${corte}, SÓ NÚMEROS. GERADO por scripts/bancada-agenda/gerar-replay-conclusoes.mjs a partir do SELECT
-- scratchpad/agenda-pesquisa/sql/i06_replay_export.sql — não edite à mão: regere.
-- Roda dentro do begin/rollback de supabase/tests/agenda_fase3_replay_conclusoes.sql (o rodar.mjs passa este arquivo em
-- agenda_teste.replay_conclusoes). Só cria duas tabelas temporárias; quem monta as OS na bancada é o teste. NUNCA rodar em
-- produção. Sem nome, documento, telefone, descrição de recebível nem id de produção.

create temp table _replay_os (
  numero text primary key, status text, check_out_at timestamptz, created_at timestamptz, converted_to_os_at timestamptz,
  labor_cost_total numeric, parts_cost_total numeric, operational_cost_total numeric, travel_cost_total numeric,
  subcontract_cost_total numeric, is_travel_billable boolean, discount_amount numeric, tax_amount numeric, grand_total numeric,
  tem_preset boolean, preset_installments jsonb, custom_payment_installments jsonb
) on commit drop;

create temp table _replay_rec (
  numero text not null, n int not null, amount numeric, status text, is_deposit boolean, due_on_completion boolean,
  issue_date date, due_date date, paid_amount numeric, balance_amount numeric, created_at timestamptz,
  primary key (numero, n)
) on commit drop;

insert into _replay_os values
${osSql.join(',\n')};

insert into _replay_rec values
${recSql.join(',\n')};
`;
writeFileSync(join(AQUI, 'fixture-replay-conclusoes.sql'), fixture);

const CASOS = join(AQUI, 'recebiveis-casos.json');
const doc = JSON.parse(readFileSync(CASOS, 'utf8'));
doc.casos = [...doc.casos.filter((c) => !c.replay), ...casos];
writeFileSync(CASOS, JSON.stringify(doc, null, 2) + '\n');
console.log(`fixture-replay-conclusoes.sql: ${linhas.length} OS, ${recSql.length} recebíveis; recebiveis-casos.json: ${casos.length} casos do replay (esperado vazio — rode o vitest com REGERAR_RECEBIVEIS_CASOS=1)`);
