// Gera o replay da carteira REAL de 29/10/2026 (Agenda de Produção, Fase 7a, P1; spec-fase7a §8.2) a partir do SELECT de
// produção. Nada vai para produção; não lê .env nem credencial: só lê o arquivo que o SELECT gravou.
//
//   1. Rode o SELECT (só leitura) scratchpad/agenda-pesquisa/sql/wf7a_p1_02_replay.sql pelo q0.sh, que grava uma linha
//      {t: tabela, r: registro} por registro (as 20 OS — as 11 da carteira e os 9 orçamentos acima de R$ 5.000 —, as linhas,
//      as peças, o material, a OC, os sinais, a equipe, a disponibilidade, o plano, as perguntas ligadas, os eventos e a linha
//      de agenda_config).
//   2. node scripts/bancada-agenda/gerar-replay-2910.mjs <saída do SELECT> [corte ISO, padrão 2026-10-29T16:52:00-03:00]
//      Escreve scripts/bancada-agenda/fixture-replay-2910.sql.
//   3. node scripts/bancada-agenda/rodar.mjs: agenda_fase7a_base.sql (B7) confere o que o replay monta.
//
// O que o gerador faz com o que veio de produção:
//   · o CORTE (o estado de qui 29/10 16:52, a 1ª revisão do gestor): some o que nasceu depois (a linha do Alex e o contato dele,
//     de 29/10 21:30; as diárias e os perfis de depois); volta a valer o que acabou depois (a disponibilidade do Roberto e do João,
//     substituída em 30/10 00:11; o contato do Roberto, parado na mesma hora; as 12 reservas do Lenine, soltas pela vigia em 30/10
//     00:15; a pergunta material_conferir do Lenine, resolvida junto). O que mudou depois e não tem como voltar (a OS, o
//     material) é dito na saída e no cabeçalho da fixture;
//   · os NOMES: só o primeiro nome de cliente, de pessoa e de fornecedor, também dentro dos textos; nenhum telefone, documento,
//     e-mail, endereço, nota livre ou valor de pagamento a pessoa (a diária vira R$ 200, como na fixture-2310). Quem tem telefone
//     em produção ganha um telefone fictício (5547900000001…), para a ficha da equipe não ser recusada por "sem telefone";
//   · os IDS: todo uuid (também dentro de jsonb e de chave de texto) vira md5('replay2910:' || uuid), no formato de uuid; a
//     referência a um registro que não veio (a ação que publicou a reserva, a alocação que ela substituiu) fica nula.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const [, , entrada, corteIso = '2026-10-29T16:52:00-03:00'] = process.argv;
if (!entrada) {
  console.error('uso: node scripts/bancada-agenda/gerar-replay-2910.mjs <saída do wf7a_p1_02_replay> [corte ISO]');
  process.exit(2);
}
const CORTE = Date.parse(corteIso);
if (Number.isNaN(CORTE)) throw new Error(`corte inválido: ${corteIso}`);
const depois = (v) => v !== null && v !== undefined && Date.parse(v) > CORTE;
const diaDoCorte = new Date(CORTE - 3 * 3600 * 1000).toISOString().slice(0, 10);

const texto = readFileSync(entrada, 'utf8').trim();
let linhas;
try {
  const d = JSON.parse(texto);
  linhas = Array.isArray(d) ? d : d.rows;
} catch {
  linhas = texto.split('\n').filter(Boolean).map((l) => JSON.parse(l));
}
if (!Array.isArray(linhas) || linhas.length === 0) throw new Error('o SELECT não trouxe nada');

/** As tabelas na ordem de inserção (quem é referido vem antes). */
const ORDEM = [
  'app_users', 'payees', 'work_profiles', 'work_shifts', 'clients', 'marinas', 'vessels', 'services', 'suppliers', 'products',
  'service_orders', 'service_order_services', 'service_order_parts', 'service_order_technicians', 'purchase_orders',
  'purchase_order_items', 'receivables', 'work_shift_os', 'os_planejamento', 'os_planejamento_equipe', 'os_material',
  'agenda_disponibilidade', 'agenda_equipe_contato', 'agenda_propostas', 'agenda_alocacoes', 'agenda_perguntas',
  'ai_lifecycle_events',
];
/** A chave de cada tabela (o que identifica o registro: as referências a um registro que não veio ficam nulas). */
const CHAVE = { os_planejamento: 'service_order_id', agenda_equipe_contato: 'payee_id', work_shift_os: null,
  os_planejamento_equipe: null, app_settings: 'key', agenda_config: null };

const porTabela = new Map();
for (const { t, r } of linhas) {
  if (!porTabela.has(t)) porTabela.set(t, []);
  porTabela.get(t).push(r);
}
for (const t of porTabela.keys()) {
  if (!ORDEM.includes(t) && t !== 'agenda_config' && t !== 'app_settings') throw new Error(`tabela que o gerador não conhece: ${t}`);
}
const de = (t) => porTabela.get(t) ?? [];
const avisosN = new Map();
const avisos = { push: (m) => avisosN.set(m, (avisosN.get(m) ?? 0) + 1) };
const listaDeAvisos = () => [...avisosN].map(([m, n]) => (n > 1 ? `${m} (${n}×)` : m));

// ── 1. O corte ─────────────────────────────────────────────────────────────────────────────────────────────────
const nasceuDepois = { agenda_disponibilidade: 'criado_em', agenda_equipe_contato: 'incluido_em', work_profiles: 'created_at',
  work_shifts: 'created_at', ai_lifecycle_events: 'created_at', agenda_perguntas: 'criada_em', agenda_propostas: 'criada_em',
  agenda_alocacoes: 'criado_em', service_orders: 'created_at', os_material: null };
for (const [t, col] of Object.entries(nasceuDepois)) {
  if (!col || !porTabela.has(t)) continue;
  const antes = de(t).length;
  porTabela.set(t, de(t).filter((r) => !depois(r[col])));
  if (de(t).length < antes) avisos.push(`${t}: ${antes - de(t).length} registro(s) nascido(s) depois do corte ficaram de fora`);
}
porTabela.set('work_shifts', de('work_shifts').filter((r) => r.data <= diaDoCorte));
for (const r of de('agenda_disponibilidade')) {
  if (depois(r.substituida_em)) { r.substituida_em = null; avisos.push('agenda_disponibilidade: linha substituída depois do corte volta a valer'); }
}
for (const r of de('agenda_equipe_contato')) {
  if (depois(r.parou_em)) {
    r.parou_em = null; r.parou_motivo = null; r.recebe_rotina = true;
    avisos.push('agenda_equipe_contato: contato parado depois do corte volta a receber a rotina');
  }
}
for (const r of de('agenda_alocacoes')) {
  if (r.estado === 'cancelada' && depois(r.cancelada_em)) {
    r.estado = r.fixado_por ? 'fixada' : 'publicada';
    r.cancelada_em = null; r.cancelada_motivo = null;
    r.historico = (r.historico ?? []).filter((h) => !depois(h?.em));
  }
}
const nCanceladasVoltaram = de('agenda_alocacoes').length;
for (const r of de('agenda_perguntas')) {
  if (r.estado !== 'aberta') {
    r.estado = 'aberta';
    for (const k of ['respondida_em', 'respondida_por', 'respondida_via', 'opcao_escolhida', 'resposta', 'resolvida_motivo']) r[k] = null;
    avisos.push(`agenda_perguntas: ${r.tipo} fechada depois do corte volta a aberta`);
  }
  if (depois(r.mostrada_em)) { r.mostrada_vezes = 0; r.mostrada_em = null; r.mostrada_via = null; }
  if (depois(r.carona_em)) r.carona_em = null;
}
for (const r of de('agenda_propostas')) {
  if (depois(r.decidida_em)) avisos.push('agenda_propostas: decidida depois do corte (fica como está)');
}
for (const t of ['service_orders', 'os_material', 'os_planejamento']) {
  const col = t === 'service_orders' ? 'updated_at' : 'atualizado_em';
  const n = de(t).filter((r) => depois(r[col])).length;
  if (n) avisos.push(`${t}: ${n} registro(s) mudaram depois do corte e ficam como estão hoje (sem como voltar)`);
}

// ── 2. Os nomes ────────────────────────────────────────────────────────────────────────────────────────────────
const primeiro = (s) => (s === null || s === undefined ? s : String(s).trim().split(/\s+/)[0]);
const nomesCompletos = new Map();
const guardar = (s) => { if (s && /\s/.test(String(s).trim())) nomesCompletos.set(String(s).trim(), primeiro(s)); };
for (const r of de('clients')) { guardar(r.name); guardar(r.display_name); r.name = primeiro(r.name); r.display_name = primeiro(r.display_name) ?? null; }
for (const r of de('payees')) { guardar(r.name); r.name = primeiro(r.name); }
for (const r of de('app_users')) { guardar(r.full_name); r.full_name = primeiro(r.full_name); r.email = `${primeiro(r.full_name).toLowerCase()}@replay2910.invalid`; }
for (const r of de('suppliers')) {
  guardar(r.name); guardar(r.trade_name); guardar(r.display_name);
  r.name = primeiro(r.name); r.trade_name = primeiro(r.trade_name) ?? null; r.display_name = primeiro(r.display_name) ?? null;
}
const nomesEmOrdem = [...nomesCompletos.entries()].sort((a, b) => b[0].length - a[0].length);
function semSobrenome(s) {
  let x = s;
  for (const [cheio, curto] of nomesEmOrdem) x = x.split(cheio).join(curto);
  return x;
}

// O telefone fictício e o que é pagamento a pessoa.
let fone = 0;
for (const r of de('payees')) {
  r.phone = r.tem_telefone ? `55479${String(++fone).padStart(8, '0')}` : null;
  delete r.tem_telefone;
}
for (const r of de('work_profiles')) r.valor_diaria = 200;
// A diária: R$ 200 (o valor real é pagamento a pessoa); quem registrou e aprovou não vem do SELECT — vira o dono (o admin),
// como na fixture-2310 (o CHECK work_shifts_aprovacao_tem_autor pede o autor na aprovada).
const dono = de('app_users').find((u) => u.role === 'admin');
if (!dono) throw new Error('o SELECT não trouxe o login do dono (admin)');
for (const r of de('work_shifts')) {
  r.valor_diaria = 200;
  r.registrado_por = dono.id;
  if (r.status !== 'rascunho') {
    r.aprovado_por = dono.id;
    r.aprovado_em = r.aprovado_em ?? r.updated_at ?? r.created_at;
  }
}
for (const r of de('os_material')) delete r.tem_trecho;
const numeroDaOs = new Map(de('service_orders').map((r) => [r.id, r.service_order_number]));
for (const r of de('receivables')) r.description = `Sinal ${numeroDaOs.get(r.service_order_id) ?? ''}`.trim();

// ── 3. Os ids ──────────────────────────────────────────────────────────────────────────────────────────────────
const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;
const novoId = (u) => {
  const h = createHash('md5').update(`replay2910:${u.toLowerCase()}`).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
};
function trocar(v) {
  if (typeof v === 'string') return semSobrenome(v).replace(UUID, novoId);
  if (Array.isArray(v)) return v.map(trocar);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, trocar(x)]));
  return v;
}
for (const [t, rs] of porTabela) porTabela.set(t, rs.map(trocar));

// As referências (uuid solto numa coluna) a um registro que não veio ficam nulas.
const exportados = new Set();
for (const [t, rs] of porTabela) {
  const k = t in CHAVE ? CHAVE[t] : 'id';
  if (k) for (const r of rs) if (r[k]) exportados.add(r[k]);
}
const UM_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
let anuladas = 0;
for (const [t, rs] of porTabela) {
  if (t === 'agenda_config' || t === 'app_settings') continue;
  const k = t in CHAVE ? CHAVE[t] : 'id';
  for (const r of rs) {
    for (const [col, v] of Object.entries(r)) {
      if (col === k || typeof v !== 'string' || !UM_UUID.test(v)) continue;
      if (!exportados.has(v)) { r[col] = null; anuladas++; }
    }
  }
}
// work_shift_os só com a diária e a OS que vieram
porTabela.set('work_shift_os', de('work_shift_os').filter((r) => r.shift_id && r.service_order_id));

// ── 4. A fixture ───────────────────────────────────────────────────────────────────────────────────────────────
/** Quebra o texto em linhas de até 130 letras, cada uma com o prefixo. */
function quebrar(t, prefixo) {
  const saida = [];
  let atual = '';
  for (const p of t.split(' ')) {
    if ((prefixo + atual + ' ' + p).length > 130 && atual) {
      saida.push(prefixo + atual);
      atual = p;
    } else {
      atual = atual ? `${atual} ${p}` : p;
    }
  }
  if (atual) saida.push(prefixo + atual);
  return saida.join('\n');
}
const json = (v) => {
  const s = JSON.stringify(v);
  if (s.includes('$r$')) throw new Error('o JSON tem $r$');
  return `$r$${s}$r$::jsonb`;
};
const contagens = ORDEM.filter((t) => de(t).length).map((t) => `${t} ${de(t).length}`);
const cfg = de('agenda_config')[0];
if (!cfg) throw new Error('o SELECT não trouxe a linha de agenda_config');
delete cfg.id;
delete cfg.versao_plano;

const corpo = ORDEM.filter((t) => de(t).length)
  .map((t) => `select pg_temp._replay2910_inserir('${t}', ${json(de(t))});`)
  .join('\n');

const fixture = `-- Replay da carteira REAL de qui 29/10/2026 16:52 (Agenda de Produção, Fase 7a, P1; spec-fase7a §8.2). GERADO por
-- scripts/bancada-agenda/gerar-replay-2910.mjs a partir do SELECT scratchpad/agenda-pesquisa/sql/wf7a_p1_02_replay.sql — não
-- edite à mão: regere. Corte: ${corteIso}.
-- Roda dentro do begin/rollback do teste (o rodar.mjs passa este arquivo em agenda_teste.replay2910), POR CIMA da fixture-2310:
-- primeiro tira o mundo sintético de 23/10 (os mesmos números de OS), depois põe o de produção. NUNCA rodar em produção.
-- Só o primeiro nome de cliente, pessoa e fornecedor; nenhum telefone (o de quem tem é fictício), documento, e-mail, endereço,
-- nota livre ou valor de pagamento a pessoa; ids trocados por md5('replay2910:' || id).
--
-- O que tem:
${quebrar(contagens.join(', '), '--   ')}
-- Como:
--   · a carteira das 11 (OS-00074 Lenine, OS-00069 Vanderlei, OS-00130 Giancarlo, OS-00112 Nelson, OS-00104 Flávio,
--     OS-00096 e OS-00076 Rodrigo, OS-00032 e OS-00033 Kalmar, ORÇ-00083 Robson, ORÇ-00095 MP) e os 9 orçamentos acima de
--     R$ 5.000 mexidos em 90 dias (ORÇ-00117, 116, 126, 125, 122, 118, 123, 119 e 127), com as linhas, as peças, os produtos e os
--     fornecedores delas, as 19 linhas de material, a OC-00004 do compressor, os sinais, os eventos de status de 60 dias;
--   · a equipe que o motor via: o dono (sem linha de disponibilidade), Roberto e João pela semente de 8 semanas, Mickael com
--     perfil de diarista e sem disponibilidade, Alex sem perfil (a linha dele, de 29/10 21:30, fica de fora pelo corte);
--   · o plano: as 12 reservas do Lenine (05, 06 e 10/11; ${nCanceladasVoltaram} alocações) e a proposta delas; as 3 perguntas
--     ligadas abertas (fornecedores_prazo, fornecedor_cadastro do Flávio, material_conferir do Lenine);
--   · a linha de agenda_config de produção (todos os modos das Fases 1–6 ligados; versao_plano e as colunas da Fase 7 ficam as
--     da bancada).
-- Do corte (${corteIso}):
${quebrar(listaDeAvisos().join('; ') || 'nada a voltar', '--   ')}
--   ${anuladas} referência(s) a registro que não veio ficaram nulas.

-- ── 1. O mundo sintético de 23/10 sai (a fixture-2310 tem as mesmas OS, com outros ids) ─────────────────────────────────
delete from public.agenda_disponibilidade;
delete from public.agenda_equipe_contato;
delete from public.agenda_tasks;
delete from public.receivables;
delete from public.payables;
delete from public.purchase_order_items;
delete from public.purchase_orders;
delete from public.service_order_parts;
delete from public.service_order_services;
delete from public.service_order_technicians;
delete from public.os_material;
delete from public.os_planejamento_equipe;
delete from public.os_planejamento;
delete from public.work_shift_os;
delete from public.service_orders;
delete from public.products;
delete from public.services;
delete from public.suppliers;
delete from public.vessels;
delete from public.marinas;
delete from public.clients;
delete from public.work_shifts;
delete from public.work_profiles;
delete from public.payees;
delete from public.app_users;

-- ── 2. O inseridor: só as colunas que a bancada tem (o snapshot é de 06/10; as colunas que produção tem a mais ficam de fora) ─
create or replace function pg_temp._replay2910_inserir(p_tabela text, p_linhas jsonb) returns integer
language plpgsql as $f$
declare
  v_cols text;
  v_n    integer;
begin
  select string_agg(format('%I', a.attname), ', ' order by a.attnum) into v_cols
    from pg_attribute a
   where a.attrelid = ('public.' || p_tabela)::regclass and a.attnum > 0 and not a.attisdropped
     and a.attgenerated = '' and a.attidentity = ''
     and exists (select 1 from jsonb_array_elements(p_linhas) e where e ? a.attname);
  execute format('insert into public.%I (%s) select %s from jsonb_populate_recordset(null::public.%I, $1)',
                 p_tabela, v_cols, v_cols, p_tabela) using p_linhas;
  get diagnostics v_n = row_count;
  return v_n;
end $f$;

-- A linha de agenda_config de produção: só as colunas que a bancada tem (fora id e versao_plano).
create or replace function pg_temp._replay2910_config(p_cfg jsonb) returns void
language plpgsql as $f$
declare
  v_cols text;
begin
  select string_agg(format('%I', a.attname), ', ' order by a.attnum) into v_cols
    from pg_attribute a
   where a.attrelid = 'public.agenda_config'::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
     and p_cfg ? a.attname and a.attname not in ('id', 'versao_plano');
  execute format('update public.agenda_config c set (%s) = (select %s from jsonb_populate_record(c, $1)) where c.id',
                 v_cols, v_cols) using p_cfg;
end $f$;

-- ── 3. O mundo de produção de 29/10 ────────────────────────────────────────────────────────────────────────────────
insert into public.app_settings (key, value) values ('stock_model_v2', 'on') on conflict (key) do update set value = 'on';
${corpo}

-- ── 4. A configuração de produção ──────────────────────────────────────────────────────────────────────────────────
select pg_temp._replay2910_config(${json(cfg)});
`;
writeFileSync(join(AQUI, 'fixture-replay-2910.sql'), fixture.replace(/\r\n/g, '\n'));
console.log(`fixture-replay-2910.sql: ${contagens.join(', ')}`);
console.log(`corte ${corteIso}: ${anuladas} referência(s) anulada(s)`);
for (const a of listaDeAvisos()) console.log(`  · ${a}`);
