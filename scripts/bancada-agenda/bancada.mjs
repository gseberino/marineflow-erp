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
//      CHECK (sem as FKs do snapshot), mais as colunas que migrations posteriores ao snapshot acrescentaram e (Fase 4)
//      as tabelas de depois do snapshot em DDL mínima (TABELAS_DEPOIS_DO_SNAPSHOT: comprovantes);
//   3. a view product_availability e as funções reais do snapshot (05-funcoes.sql) COM a ACL de produção, as
//      sequências e os índices únicos de que essas funções dependem (01-sequencias.sql, 04-indices.sql) e a RLS de
//      produção das tabelas que as policies da agenda atravessam (08-politicas-rls.sql: payees é fechada para o
//      técnico — sem isso, uma policy que lesse payees direto passaria aqui e nunca casaria em produção);
//   3b. (Fase 3) os gatilhos de produção que a conclusão atravessa (07-triggers.sql: recebíveis e OS concluída) e as
//      migrations POSTERIORES ao snapshot que a Fase 3 lê, aplicadas inteiras e uma vez só, como estão em produção
//      (MIGRATIONS_DEPOIS_DO_SNAPSHOT: o acerto de diárias de 06/10, que trava o dia pago);
//   4. as migrations do worktree a partir de 20261024150000, em ordem, DUAS vezes (prova de idempotência),
//      menos o que é dado de produção e não estrutura (a faxina 20261024153000 e os modos em sombra 20261025101000 e
//      20261026101000: na bancada quem liga os modos é cada teste), cada versão registrada em
//      supabase_migrations.schema_migrations como em produção. A semente 20261024161000 entra: na bancada vazia ela não
//      acha diária e não semeia (a fixture semeia o dia 23/10). `ate` corta a lista (cada pacote testa até a sua). Na 2ª
//      rodada, a view que uma migration mais nova recriou com colunas a mais sai antes da antiga (VIEWS_RECRIADAS_DEPOIS);
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
  // Fase 3 (P7): modo_equipe e modo_diaria em sombra e a semente de agenda_equipe_contato (a fixture-fase3 faz o papel).
  '20261026101000_agenda_fase3_sombra.sql',
]);

/**
 * Views que uma migration MAIS NOVA recriou com colunas a mais no fim: na 2ª rodada, a migration antiga que as define
 * (create or replace view com menos colunas) esbarraria em "cannot drop columns from view" (42P16) — o Postgres só deixa
 * o create or replace ACRESCENTAR colunas. Em produção cada migration roda uma vez, na ordem, e isso não acontece; aqui,
 * só na 2ª rodada e só antes daquele arquivo, a view sai e a migration antiga a recria (com os grants dela), e a mais
 * nova, logo depois na mesma rodada, volta a acrescentar as colunas. [arquivo antigo]: [views].
 *   · Fase 4 (P1): 20261027100000 acrescenta service_order_part_id e service_order_service_id a v_oc_itens_a_caminho
 *     (Fase 0, 20261024150100).
 */
export const VIEWS_RECRIADAS_DEPOIS = {
  '20261024150100_compras_reserva_propria_e_ja_pedido.sql': ['v_oc_itens_a_caminho'],
};

/**
 * Migrations de ANTES da agenda e DEPOIS do snapshot (06/10 19:51 UTC) que a Fase 3 lê: aplicadas inteiras, uma vez,
 * antes das da agenda (em produção já estão aplicadas). Precisam só do que o snapshot e a lista abaixo trazem: o corpo
 * PL/pgSQL não é validado ao criar, e o que ele chama (conta_corrente_freelancer, _autor_do_financeiro) a bancada não
 * usa — a fixture-fase3 grava o acerto direto na tabela.
 *   · 20261006220000: acertos_diarias, a trava trg_dia_em_acerto_fechado em work_shifts ("dia de acerto fechado não
 *     entra, não muda e não sai") e registrar_conferencia_do_freelancer (o "ok" do recibo: NOVO-agenda-17).
 */
export const MIGRATIONS_DEPOIS_DO_SNAPSHOT = ['20261006220000_diarias_acerto_e_recibo.sql'];

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
  // Fase 3 (P1): a conclusão e os recebíveis (paridade com ensureCompletionReceivables: condição de pagamento,
  // pagamentos, o vencimento "na entrega" que também acerta as cobranças em collections, o período fechado), a comissão
  // (despesas da OS, nota emitida e a alíquota; commissions e payables só para provar que nada é inserido) e as
  // mensagens do WhatsApp (a resposta da equipe).
  'payments', 'payment_condition_presets', 'service_order_expenses', 'issued_fiscal_documents', 'company_fiscal_settings',
  'commissions', 'collections', 'periodos_fechados', 'whatsapp_messages',
  // Fase 3 (P3): a trava do levantamento (D11) da conversa e das palavras que concluem (_os_levantamentos_pendentes).
  'service_surveys',
  // Fase 4 (P1): o que o material lê sem escrever — a NF-e do e-mail (a remessa aponta para a mensagem, o anexo e a nota
  // importada), o Pix (o extrato e a fila financeira), a cotação (o vínculo de linha que a OC copia) e o movimento de
  // estoque (o recebimento de texto livre não pode gerar um).
  'email_accounts', 'email_messages', 'email_attachments', 'fiscal_notes', 'fiscal_note_items', 'bank_transactions',
  'finance_review_queue', 'quote_requests', 'quote_request_items', 'inventory_movements',
];

/**
 * Tabelas de DEPOIS do snapshot (06/10) que a agenda lê, em DDL mínima: só as colunas que ela usa, sem FK. Não é a tabela
 * de produção — é o espelho do que a Fase 4 lê dela.
 *   · comprovantes (20261011100000 + 20261011200000): espelho mínimo de 20261011100000; a Fase 4 só lê (o CMP de
 *     fornecedor com destino a OS é candidato forte da pergunta do Pix).
 */
const TABELAS_DEPOIS_DO_SNAPSHOT = `
create table if not exists public.comprovantes (
  id              uuid primary key default gen_random_uuid(),
  numero          integer unique,
  codigo          text generated always as (case when numero is null then null
                                                 when numero < 100000 then 'CMP-' || lpad(numero::text, 5, '0')
                                                 else 'CMP-' || numero::text end) stored,
  supplier_id     uuid,
  fornecedor_nome text,
  valor           numeric(12,2),
  data_compra     date,
  destino         text,
  destino_os_id   uuid,
  situacao        text not null default 'recebido',
  recebido_em     timestamptz not null default now()
);
`;

/** Sequências do snapshot que as funções da lista abaixo usam (next_document_number). */
const SEQUENCIAS = ['document_number_seq'];

/**
 * Índices do snapshot de que as funções dependem (o ON CONFLICT do log_app_error; o dedupe da fila). Fase 3: um dia
 * por perfil em work_shifts (a diária automática só insere quando a pessoa não tem turno no dia) e o id único da
 * mensagem do WhatsApp (a resposta da equipe não é lida duas vezes).
 */
const INDICES = ['uq_app_error_logs_open', 'whatsapp_send_queue_dedupe_key_uq', 'work_shifts_um_dia_por_perfil',
  'whatsapp_messages_wa_message_id_unique'];

/**
 * Gatilhos de produção (07-triggers.sql, um por linha) que a conclusão e o sinal atravessam (Fase 3, P1). O so_status_stock
 * (a baixa de estoque na conclusão e o estorno na reabertura) fica fora: ele grava em inventory_movements, que a bancada
 * não tem. A spec dizia "stock_model_v2_on() falso na bancada", mas a fixture-2310 LIGA o v2 (para a reserva das peças):
 * com o gatilho, toda conclusão da bancada cairia na tabela que falta. Quem precisar provar a baixa ou o estorno traz
 * inventory_movements e o gatilho juntos. on_quote_deposit_paid entra além da lista da spec: é ele que converte o
 * orçamento pelo sinal pago (handle_quote_deposit_payment, NOVO-agenda-15), e sem ele a conversão nunca rodaria aqui.
 */
const GATILHOS = ['on_quote_deposit_paid', 'receivables_coerencia', 'trg_receivables_periodo_fechado', 'trg_sync_payment_status',
  'trg_sync_balance_due_on_completion', 'trg_sync_commission_on_complete'];

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
-- Fase 4 (P3): o que o leitor do e-mail extraiu (as NF-e com a saída, o frete, o lugar e os itens); a remessa lê daqui.
alter table public.email_messages add column if not exists dados_extraidos jsonb;  -- 20261008110000
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
  // Fase 3 (P1): a concordância ("ok") e o telefone normalizado (a resposta da equipe); a diária de hoje
  // (registrar_diaria: a diária automática nunca a chama, e o teste do P4 prova contra ela); os gatilhos dos recebíveis
  // e da OS concluída (o período fechado, a coerência do recebível, o estado do pagamento da OS, o vencimento "na
  // entrega", a comissão de vendedor) e a conversão pelo sinal pago. Todas com o corpo do snapshot: nenhuma foi
  // redefinida por migration depois de 06/10 (conferido em 24/10; a mais nova de handle_quote_deposit_payment é
  // 20261003210000, igual ao snapshot).
  '_e_concordancia', 'wa_normalize_phone', 'registrar_diaria', 'periodo_esta_fechado', 'bloqueia_lancamento_em_periodo_fechado',
  'valida_recebivel_coerente', 'sync_service_order_payment_status', 'sync_balance_due_on_completion',
  'sync_commission_on_so_complete', 'handle_quote_deposit_payment',
  // Fase 3 (P4): o que o registrar_diaria chama por dentro (a decisão do dono numa diária que já existe e a palavra
  // *diária <nome> meia* depois do automático passam por ele): o cargo do financeiro e o rótulo da jornada.
  '_autor_do_financeiro', '_rotulo_jornada',
];

let snapshot;
function arquivosDoSnapshot() {
  snapshot ??= {
    sequencias: ler(join(SNAP, '01-sequencias.sql')),
    tabelas: ler(join(SNAP, '02-tabelas.sql')),
    indices: ler(join(SNAP, '04-indices.sql')),
    funcoes: ler(join(SNAP, '05-funcoes.sql')),
    views: ler(join(SNAP, '06-views.sql')),
    gatilhos: ler(join(SNAP, '07-triggers.sql')),
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
export const gatilho = (nome) => linhaDoSnapshot('gatilhos', nome, `CREATE TRIGGER ${nome} `);

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
  await db.exec(TABELAS_DEPOIS_DO_SNAPSHOT);
  await db.exec(COLUNAS_DEPOIS_DO_SNAPSHOT);
  await db.exec(INDICES.map(indice).join('\n'));
  await db.exec(view('product_availability'));
  await db.exec(FUNCOES.map(funcao).join('\n'));
  await db.exec(RLS_DE_PRODUCAO.map(rls).join('\n'));
  await db.exec(ESTOQUE_DE_MENTIRA);
  await db.exec(GATILHOS.map(gatilho).join('\n'));
  for (const m of MIGRATIONS_DEPOIS_DO_SNAPSHOT) {
    try {
      await db.exec(ler(join(MIG, m)));
      log(true, `migration ${m} (depois do snapshot, uma vez)`);
    } catch (e) {
      log(false, `migration ${m} (depois do snapshot): ${String(e.message).split('\n')[0]}`);
      throw e;
    }
  }

  const migrations = migracoesAte(ate);
  for (const rodada of [1, 2]) {
    for (const m of migrations) {
      try {
        if (rodada === 2) {
          for (const v of VIEWS_RECRIADAS_DEPOIS[m] ?? []) await db.exec(`drop view if exists public.${v}`);
        }
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
