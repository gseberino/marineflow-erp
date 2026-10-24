// Bancada da Agenda de Produção: um Postgres em memória (PGlite) com o pedaço do snapshot de produção que a
// agenda lê e as migrations do worktree por cima. Nada vai para produção; não lê .env nem credencial.
//
//   import { criarBancada } from './bancada.mjs';
//   const { db, migrations } = await criarBancada({ ate: '20261024160200', fixture: true });
//
// Monta, nesta ordem:
//   1. o "Supabase de mentira": papéis anon/authenticated/service_role, os privilégios PADRÃO do Supabase em
//      public (tabela e função novas nascem com anon — é isso que prova os REVOKEs das migrations), schema auth
//      com auth.uid() lendo o claim (request.jwt.claim.sub), extensões unaccent e btree_gist;
//   2. as tabelas reais do snapshot (supabase/schemas/producao/02-tabelas.sql), só com colunas, PK, UNIQUE e
//      CHECK (sem as FKs do snapshot), mais as colunas que migrations posteriores ao snapshot acrescentaram;
//   3. a view product_availability e as funções reais do snapshot (05-funcoes.sql) COM a ACL de produção, as
//      sequências e os índices únicos de que essas funções dependem (01-sequencias.sql, 04-indices.sql) e a RLS de
//      produção das tabelas que as policies da agenda atravessam (08-politicas-rls.sql: payees é fechada para o
//      técnico — sem isso, uma policy que lesse payees direto passaria aqui e nunca casaria em produção);
//   4. as migrations do worktree a partir de 20261024150000, em ordem, DUAS vezes (prova de idempotência),
//      menos o que é dado de produção e não estrutura (a faxina 20261024153000 e os modos em sombra 20261025101000:
//      na bancada quem liga os modos é cada teste), cada versão registrada em supabase_migrations.schema_migrations
//      como em produção. A semente 20261024161000 entra: na bancada vazia ela não acha diária e não semeia (a fixture
//      semeia o dia 23/10). `ate` corta a lista (cada pacote testa até a sua);
//   5. com `fixture`, scripts/bancada-agenda/fixture-2310.sql (a carteira sintética de 23/10).
//
// O PGlite vem da bancada dos comprovantes (0.5.8), fora do repo: PGLITE_DIR troca a pasta.
// Se o PGlite recusar algum DEFAULT ou sintaxe do snapshot, a troca vai na lista TROCAS_DO_SNAPSHOT abaixo,
// nunca no snapshot.

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SNAP = join(RAIZ, 'supabase', 'schemas', 'producao');
const MIG = join(RAIZ, 'supabase', 'migrations');
export const TESTES = join(RAIZ, 'supabase', 'tests');
const PGLITE_DIR = process.env.PGLITE_DIR ?? 'D:/IA-HBR/comprovantes-bancada/pglite-ensaio';

/** A 1ª migration da Agenda de Produção (Fase 0). As anteriores já estão no snapshot (ou não importam aqui). */
export const PRIMEIRA = '20261024150000';
/** Dado de produção: não entra na bancada (a fixture faz o papel do dado). */
export const FORA_DA_BANCADA = new Set([
  '20261024153000_faxina_agenda_fase0.sql',
  // Fase 2 (P6): os modos de desligado para sombra. Na bancada cada teste liga o modo que precisa.
  '20261025101000_agenda_fase2_sombra.sql',
]);

export const ler = (p) => readFileSync(p, 'utf8').replace(/\r\n/g, '\n');

/** As tabelas do snapshot que a agenda (e a família de compras) lê. */
export const TABELAS = [
  'app_settings', 'app_users', 'clients', 'marinas', 'vessels', 'services', 'products', 'suppliers',
  'service_orders', 'service_order_parts', 'service_order_services', 'service_order_technicians',
  'purchase_orders', 'purchase_order_items', 'payees', 'work_profiles', 'work_shifts', 'work_shift_os',
  'receivables', 'payables', 'agenda_tasks',
  // P7: o SQL pós-deploy confere que a agenda não deixou erro aberto (supabase/tests/agenda_fase1_pos_deploy.sql)
  'app_error_logs',
  // Fase 2: o registro do gatilho de status de produção (a porta não escreve nele; o teste confere) e a fila de
  // envio do WhatsApp (os evals provam que nada sai para cliente nem equipe).
  'ai_lifecycle_events', 'whatsapp_send_queue',
];

/** Sequências do snapshot que as funções da lista abaixo usam (next_document_number). */
const SEQUENCIAS = ['document_number_seq'];

/** Índices do snapshot de que as funções dependem (o ON CONFLICT do log_app_error; o dedupe da fila). */
const INDICES = ['uq_app_error_logs_open', 'whatsapp_send_queue_dedupe_key_uq'];

/**
 * Tabelas com a RLS de produção ligada na bancada (as policies vêm de 08-politicas-rls.sql). Só as que uma policy
 * da agenda atravessa: a leitura de agenda_alocacoes deixa o técnico ver o próprio payee, e payees é fechada para
 * ele (só admin/financeiro) — por isso a policy lê por _agenda_payees_do_login() (security definer).
 */
const RLS_DE_PRODUCAO = ['payees'];

/** Colunas que migrations DEPOIS do snapshot (06/10) acrescentaram e que a agenda lê. */
const COLUNAS_DEPOIS_DO_SNAPSHOT = `
alter table public.service_orders add column if not exists merged_into_id uuid;   -- 20261015180000
alter table public.marinas add column if not exists neighborhood text;            -- 20261007161000
`;

/**
 * Trocas pontuais no texto do snapshot, quando o PGlite não aceita o original: [tabela, de, para].
 * Vazia em 23/10/2026 — as 21 tabelas sobem como estão (gen_random_uuid, now(), CURRENT_DATE e literais).
 */
const TROCAS_DO_SNAPSHOT = [];

/** Funções do snapshot que a agenda usa, na ordem de dependência. */
export const FUNCOES = [
  'is_admin', 'is_admin_or_financial', 'pode_ver_folha', '_hoje_brt', '_dia_curto', '_brl', '_nome_comparavel',
  'stock_model_v2_on', 'recompute_product_reservations', 'trg_parts_reservation', 'classify_service_text',
  'free_text_is_material', 'classify_free_text_materials', 'compute_purchase_needs', 'get_os_purchase_needs',
  'count_purchase_shortages',
  // Fase 2: o erro consultável em SQL (a vigia), o conflito de agenda que a Fase 2 recria e o número de documento
  // que o update_service_order_status do eval usa.
  'log_app_error', 'get_agenda_conflicts', 'next_document_number',
];

let snapshot;
function arquivosDoSnapshot() {
  snapshot ??= {
    sequencias: ler(join(SNAP, '01-sequencias.sql')),
    tabelas: ler(join(SNAP, '02-tabelas.sql')),
    indices: ler(join(SNAP, '04-indices.sql')),
    funcoes: ler(join(SNAP, '05-funcoes.sql')),
    views: ler(join(SNAP, '06-views.sql')),
    politicas: ler(join(SNAP, '08-politicas-rls.sql')),
  };
  return snapshot;
}

/** A linha do snapshot que cria a sequência ou o índice `nome` (uma por linha nos dois arquivos). */
function linhaDoSnapshot(arquivo, nome, marca) {
  const linha = arquivosDoSnapshot()[arquivo].split('\n').find((l) => l.includes(marca));
  if (!linha) throw new Error(`${nome} não está em ${arquivo} do snapshot`);
  return linha;
}
export const sequencia = (nome) => linhaDoSnapshot('sequencias', nome, ` public.${nome} `);
export const indice = (nome) => linhaDoSnapshot('indices', nome, ` INDEX ${nome} ON `);

/** A RLS de produção da tabela: liga a RLS e cria as policies do snapshot (o bloco "-- ── public.<nome> ──"). */
export function rls(nome) {
  const { politicas } = arquivosDoSnapshot();
  const cabeca = `-- ── public.${nome} ──\n`;
  const i = politicas.indexOf(cabeca);
  if (i < 0) throw new Error(`as policies de ${nome} não estão no snapshot`);
  const fim = politicas.indexOf('\n\n', i);
  const bloco = politicas.slice(i + cabeca.length, fim < 0 ? undefined : fim);
  return `alter table public.${nome} enable row level security;\n${bloco}\n`;
}

export function tabela(nome) {
  const { tabelas } = arquivosDoSnapshot();
  const i = tabelas.indexOf(`CREATE TABLE public.${nome} (`);
  if (i < 0) throw new Error(`tabela ${nome} não está no snapshot`);
  let ddl = tabelas.slice(i, tabelas.indexOf('\n);', i) + 3);
  for (const [t, de, para] of TROCAS_DO_SNAPSHOT) if (t === nome) ddl = ddl.replace(de, para);
  return ddl;
}

/** A função do snapshot e a ACL dela em produção (revoke de tudo + os GRANTs do snapshot). */
export function funcao(nome) {
  const { funcoes } = arquivosDoSnapshot();
  const cabeca = funcoes.indexOf(`\n-- ── public.${nome}(`);
  if (cabeca < 0) throw new Error(`função ${nome} não está no snapshot`);
  const i = funcoes.indexOf(`CREATE OR REPLACE FUNCTION public.${nome}(`, cabeca);
  const j = funcoes.indexOf('$function$\n;', i);
  const def = funcoes.slice(i, j) + '$function$;\n';
  const fim = funcoes.indexOf('\n-- ── ', j);
  const resto = funcoes.slice(j + '$function$\n;'.length, fim < 0 ? undefined : fim);
  const grants = resto.split('\n').filter((l) => /^GRANT /.test(l));
  const assinatura = funcoes.slice(cabeca + '\n-- ── '.length, funcoes.indexOf(' ──', cabeca + 7));
  return `${def}revoke all on function ${assinatura} from public, anon, authenticated, service_role;\n${grants.join('\n')}\n`;
}

export function view(nome) {
  const { views } = arquivosDoSnapshot();
  const i = views.indexOf(`CREATE VIEW public.${nome} `);
  if (i < 0) throw new Error(`view ${nome} não está no snapshot`);
  return views.slice(i, views.indexOf(';\n', i) + 2);
}

const SHIM = `
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema if not exists auth;
create schema if not exists extensions;
create extension if not exists unaccent schema extensions;
create extension if not exists btree_gist schema extensions;
grant usage on schema public, auth, extensions to anon, authenticated, service_role;

-- Os privilégios padrão do Supabase em public: tabela e função novas nascem abertas para anon.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

-- auth.uid() igual ao do Supabase: o claim sub (ou o JSON das claims).
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$$;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- O registro das versões aplicadas, como o do Supabase (o db query --linked + o insert da spec §10, passo 1): o SQL
-- pós-deploy (P7) confere que as versões da Fase 1 estão registradas.
create schema if not exists supabase_migrations;
create table supabase_migrations.schema_migrations (version text primary key, name text);
`;

const ESTOQUE_DE_MENTIRA = `
-- entrada_de_estoque de mentira (os testes de compras da Fase 0 usam): o saldo entra direto. A de verdade
-- grava o movimento e recalcula a soma (estoque_so_por_movimento.sql).
create function public.entrada_de_estoque(p_produto uuid, p_quantidade numeric, p_custo numeric default null,
  p_notas text default null, p_autor uuid default null) returns jsonb language sql as $$
  update public.products set stock_quantity = stock_quantity + p_quantidade where id = p_produto
  returning jsonb_build_object('nova', stock_quantity) $$;
create trigger parts_reservation after insert or delete or update on public.service_order_parts
  for each row execute function public.trg_parts_reservation();
`;

/** As migrations do worktree que a bancada aplica, até `ate` (versão, inclusive). */
export function migracoesAte(ate) {
  return readdirSync(MIG)
    .filter((f) => /^\d{14}_.+\.sql$/.test(f))
    .sort()
    .filter((f) => f.slice(0, 14) >= PRIMEIRA)
    .filter((f) => !FORA_DA_BANCADA.has(f))
    .filter((f) => !ate || f.slice(0, 14) <= ate);
}

async function carregarPglite() {
  const base = join(PGLITE_DIR, 'node_modules', '@electric-sql', 'pglite', 'dist');
  const [{ PGlite }, { unaccent }, { btree_gist }] = await Promise.all([
    import(pathToFileURL(join(base, 'index.js')).href),
    import(pathToFileURL(join(base, 'contrib', 'unaccent.js')).href),
    import(pathToFileURL(join(base, 'contrib', 'btree_gist.js')).href),
  ]);
  return { PGlite, extensions: { unaccent, btree_gist } };
}

/**
 * Sobe a bancada. `log(ok, texto)` recebe uma linha por passo (migration e rodada); erro de migration lança
 * depois de logar, porque nada adiante faz sentido sem ela.
 */
export async function criarBancada({ ate, fixture = true, log = () => {} } = {}) {
  const { PGlite, extensions } = await carregarPglite();
  const db = await PGlite.create({ extensions });
  await db.exec(SHIM);
  await db.exec(SEQUENCIAS.map(sequencia).join('\n'));
  await db.exec(TABELAS.map(tabela).join('\n'));
  await db.exec(COLUNAS_DEPOIS_DO_SNAPSHOT);
  await db.exec(INDICES.map(indice).join('\n'));
  await db.exec(view('product_availability'));
  await db.exec(FUNCOES.map(funcao).join('\n'));
  await db.exec(RLS_DE_PRODUCAO.map(rls).join('\n'));
  await db.exec(ESTOQUE_DE_MENTIRA);

  const migrations = migracoesAte(ate);
  for (const rodada of [1, 2]) {
    for (const m of migrations) {
      try {
        await db.exec(ler(join(MIG, m)));
        await db.query(
          `insert into supabase_migrations.schema_migrations (version, name) values ($1, $2) on conflict (version) do nothing`,
          [m.slice(0, 14), m.slice(15, -4)],
        );
        log(true, `migration ${m} (rodada ${rodada})`);
      } catch (e) {
        log(false, `migration ${m} (rodada ${rodada}): ${String(e.message).split('\n')[0]}`);
        throw e;
      }
    }
  }
  if (fixture) {
    await db.exec(ler(join(RAIZ, 'scripts', 'bancada-agenda', 'fixture-2310.sql')));
    log(true, 'fixture-2310.sql');
  }
  return { db, migrations };
}
