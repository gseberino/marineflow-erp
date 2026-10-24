// Evals da Agenda de Produção, Fase 1 (P7), na bancada local: as respostas-modelo contra os graders, pelo MESMO caminho
// das ferramentas de verdade. Spec §8.5. Nada vai para produção; não lê .env nem credencial; não chama modelo nenhum.
//
//   node scripts/bancada-agenda/evals/rodar-evals.mjs                 # todos os casos, boa e ruim
//   node scripts/bancada-agenda/evals/rodar-evals.mjs --caso R01      # um caso só
//   node scripts/bancada-agenda/evals/rodar-evals.mjs --ponte 8787    # serve a bancada para o ao-vivo.ts (Deno)
//
// O que roda, para cada caso de casos.json e cada resposta de respostas-modelo.json (a boa e a ruim):
//   1. a bancada (bancada.mjs: snapshot + todas as migrations + fixture-2310.sql) com o material da carteira já
//      sincronizado (os_material_sincronizar_carteira de 23/10: o motor de 15 min já passou, como em produção);
//   2. numa transação desfeita no fim: o estado do caso (inicial, ou fixture-2310-pos-rodada.sql por cima);
//   3. a fotografia das 4 tabelas de fato; as chamadas da resposta pelo execute DE VERDADE de
//      _shared/ai/tools/agenda-producao.ts (que usa _shared/agenda/rpc-das-ferramentas.ts) com o banco no lugar do
//      supabase-js — pelo WhatsApp (service_role), com o relógio no dia do caso; ferramenta que não é da agenda não
//      roda (fica só a chamada, para o juiz das ferramentas);
//   4. a fotografia de novo (nada pode ter mudado antes do *grava*) e o rascunho aberto; se o caso manda "grava", o
//      *grava* pela RPC (o comando sem IA do P6) e a fotografia final;
//   5. os três juízes de graders.mjs. A boa tem de passar nos três; a ruim tem de reprovar no juiz que ela diz
//      (reprova_em). Sai com 1 se uma boa reprovar ou uma ruim passar.
// Sem modelo, isto prova os juízes e o caminho das RPCs, não o modelo: o ao-vivo.ts faz a parte do modelo.

import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { criarBancada, ler, RAIZ } from '../bancada.mjs';
import { avaliar, datasDe, gradeBanco, gradeFerramentas, gradeTexto, montarTexto, numerosDeOsDe } from './graders.mjs';

const AQUI = dirname(fileURLToPath(import.meta.url));
const { agendaProducaoTools } = await import(
  pathToFileURL(join(RAIZ, 'supabase', 'functions', '_shared', 'ai', 'tools', 'agenda-producao.ts')).href
);
const FERRAMENTAS = new Map(agendaProducaoTools.map((t) => [t.name, t]));

export const CASOS = JSON.parse(readFileSync(join(AQUI, 'casos.json'), 'utf8'));
export const RESPOSTAS = JSON.parse(readFileSync(join(AQUI, 'respostas-modelo.json'), 'utf8'));
const POS_RODADA = ler(join(RAIZ, 'scripts', 'bancada-agenda', 'fixture-2310-pos-rodada.sql'));

function argumento(nome) {
  const i = process.argv.indexOf(nome);
  return i > 0 ? process.argv[i + 1] : undefined;
}

// ── O banco no lugar do supabase-js ─────────────────────────────────────────────────────────────────────

const tiposDe = new Map();
async function tipos(db, fn) {
  if (!tiposDe.has(fn)) {
    const r = await db.query(
      `select a.n, a.t from pg_proc p,
              lateral unnest(p.proargnames, p.proargtypes::regtype[]::text[]) as a(n, t)
        where p.proname = $1 and p.pronamespace = 'public'::regnamespace`, [fn]);
    if (!r.rows.length) throw new Error(`a função ${fn} não existe na bancada`);
    tiposDe.set(fn, Object.fromEntries(r.rows.map((x) => [x.n, x.t])));
  }
  return tiposDe.get(fn);
}

/**
 * db.rpc como o PostgREST: parâmetros por nome, JSON para jsonb e listas. Roda como service_role (o WhatsApp) e com
 * o relógio do caso (p_hoje), que o supabase-js nunca manda: em produção o banco usa o dia de Brasília.
 */
async function rpc(db, fn, params, hoje) {
  const t = await tipos(db, fn);
  const p = { ...params };
  if ('p_hoje' in t && p.p_hoje === undefined) p.p_hoje = hoje;
  const valores = [];
  const args = Object.entries(p).filter(([, v]) => v !== undefined).map(([k, v]) => {
    const tipo = t[k];
    if (!tipo) throw new Error(`${fn} não tem o parâmetro ${k}`);
    if (v === null) return `${k} => null::${tipo}`;
    if (tipo.endsWith('[]')) {
      valores.push(JSON.stringify(v));
      return `${k} => array(select jsonb_array_elements_text($${valores.length}::jsonb))::${tipo}`;
    }
    valores.push(tipo === 'jsonb' ? JSON.stringify(v) : String(v));
    return `${k} => $${valores.length}::${tipo}`;
  });
  // Cada RPC do PostgREST é uma transação: a que falha não leva as outras. Aqui, um savepoint por chamada.
  await db.exec('savepoint rpc; set local role service_role');
  try {
    const r = await db.query(`select public.${fn}(${args.join(', ')}) as r`, valores);
    await db.exec('reset role; release savepoint rpc');
    return { data: r.rows[0].r, error: null };
  } catch (e) {
    await db.exec('rollback to savepoint rpc; release savepoint rpc; reset role');
    return { data: null, error: { message: String(e.message), code: e.code ?? null } };
  }
}

/** O ctx das ferramentas: o dono pelo WhatsApp, com o banco da bancada no lugar do cliente service role. */
function ctxDaBancada(db, hoje, autor) {
  const sb = { rpc: (fn, params) => rpc(db, fn, params, hoje) };
  return { sb, admin: sb, userId: autor, userRole: 'admin', canal: 'whatsapp', jwt: '', appOrigin: '', settings: {} };
}

// ── A fotografia das 4 tabelas de fato ──────────────────────────────────────────────────────────────────

const num = (v) => (v === null || v === undefined ? null : String(Number(v)));
const txt = (v) => (v === null || v === undefined ? null : String(v));

function porChave(linhas, chave, valor, tabela) {
  const m = {};
  for (const l of linhas) {
    const k = chave(l);
    if (k in m) throw new Error(`fotografia: duas linhas de ${tabela} com a chave "${k}"`);
    m[k] = valor(l);
  }
  return m;
}

export async function foto(db) {
  const plan = await db.query(`
    select so.service_order_number os, p.dias::text dias, p.estimativa_fonte fonte, p.dono_presenca presenca,
           p.precisa_ate::text precisa_ate, nullif(p.bem_indisponivel::text, '{}') bem, p.nao_antes_de::text nao_antes,
           p.nao_antes_motivo motivo, p.escopo_em_aberto aberto, p.escopo_decidido decidido, p.congelada_ate::text congelada,
           p.revisar_em::text rever, p.prioridade_manual::text prioridade, (p.material_conferido_em is not null)::text conferido
      from public.os_planejamento p join public.service_orders so on so.id = p.service_order_id`);
  const equipe = await db.query(`
    select so.service_order_number os, pe.name pessoa, e.turnos
      from public.os_planejamento_equipe e
      join public.service_orders so on so.id = e.service_order_id
      join public.payees pe on pe.id = e.payee_id`);
  const mat = await db.query(`
    select so.service_order_number os, m.descricao, m.origem, m.quantidade_necessaria::text precisa,
           m.quantidade_na_mao::text na_mao, m.critico::text critico, m.situacao, m.fonte,
           coalesce(s.name, m.fornecedor_nome) fornecedor, m.compra_prevista_em::text compra, m.comprado_em::text comprado,
           m.previsao_de::text prev_de, m.previsao_ate::text prev_ate, m.previsao_original::text prev_orig,
           m.previsao_fonte prev_fonte, m.chegou_em::text chegou
      from public.os_material m
      join public.service_orders so on so.id = m.service_order_id
      left join public.suppliers s on s.id = m.fornecedor_id`);
  const disp = await db.query(`
    select coalesce(p.name, 'todos') pessoa, d.origem, coalesce(d.dias_semana::text, d.periodo::text) quando,
           coalesce(d.turno, 'dia todo') turno, d.situacao, d.frequencia::text frequencia,
           (d.substituida_em is null) vigente
      from public.agenda_disponibilidade d left join public.payees p on p.id = d.payee_id`);
  return {
    planejamento: porChave(plan.rows, (l) => l.os, (l) => ({
      dias: num(l.dias), fonte: l.fonte, presenca: l.presenca, precisa_ate: l.precisa_ate, bem: l.bem,
      nao_antes: l.nao_antes, motivo: l.motivo, aberto: l.aberto, decidido: l.decidido, congelada: l.congelada,
      rever: l.rever, prioridade: l.prioridade, conferido: l.conferido,
    }), 'planejamento'),
    equipe: porChave(equipe.rows, (l) => `${l.os} ${l.pessoa}`, (l) => ({ turnos: l.turnos }), 'equipe'),
    material: porChave(mat.rows, (l) => `${l.os} ${l.descricao}`, (l) => ({
      origem: l.origem, precisa: num(l.precisa), na_mao: num(l.na_mao), critico: l.critico, situacao: l.situacao,
      fonte: l.fonte, fornecedor: l.fornecedor, compra: l.compra, comprado: l.comprado, prev_de: l.prev_de,
      prev_ate: l.prev_ate, prev_orig: l.prev_orig, prev_fonte: l.prev_fonte, chegou: l.chegou,
    }), 'material'),
    disponibilidade: porChave(disp.rows,
      (l) => `${l.pessoa} ${l.origem} ${l.quando} ${l.turno} ${l.situacao}${l.vigente ? '' : ' (substituída)'}`,
      (l) => ({ frequencia: num(l.frequencia) }), 'disponibilidade'),
  };
}

async function rascunhoAberto(db, autor) {
  const r = await db.query(`select count(*)::int n from public.agenda_rascunho where autor = $1 and estado = 'aberto'`, [autor]);
  return r.rows[0].n;
}

// ── Um caso ─────────────────────────────────────────────────────────────────────────────────────────────

/** A bancada pronta para os evals: a fixture e o material da carteira sincronizado no dia dos casos. */
export async function bancadaDosEvals(log = () => {}) {
  const { db } = await criarBancada({ fixture: true, log });
  await db.query(`select public.os_material_sincronizar_carteira($1::date)`, [CASOS.hoje]);
  return db;
}

async function aplicarEstado(db, estado) {
  if (estado === 'pos_rodada') await db.exec(POS_RODADA);
  else if (estado !== 'inicial') throw new Error(`estado "${estado}" não existe (inicial | pos_rodada)`);
}

/** A foto de um estado nomeado (o igual_ao_estado do caso), tirada numa transação desfeita. */
async function fotoDoEstado(db, estado) {
  await db.exec('begin');
  try {
    await aplicarEstado(db, estado);
    return await foto(db);
  } finally {
    await db.exec('rollback');
  }
}

/** Abre a transação do caso e tira a foto de antes. */
export async function iniciarCaso(db, caso) {
  await db.exec('begin');
  await aplicarEstado(db, caso.estado ?? 'inicial');
  return { antes: await foto(db) };
}

/** Uma chamada do modelo: a ferramenta da agenda roda de verdade; as outras não rodam (só contam para o juiz). */
export async function executarChamada(db, chamada) {
  const ferramenta = FERRAMENTAS.get(chamada.ferramenta);
  if (!ferramenta) return null;
  try {
    return await ferramenta.execute(chamada.argumentos ?? {}, ctxDaBancada(db, CASOS.hoje, CASOS.autor));
  } catch (e) {
    // A ferramenta lança quando o banco falha: é o que o agente recebe como erro da ferramenta.
    return { error: String(e?.message ?? e) };
  }
}

/** Foto do meio, rascunho aberto, o *grava* (se o caso pede) e a foto final; desfaz tudo. */
export async function terminarCaso(db, caso, inicio) {
  try {
    const meio = await foto(db);
    const aberto = await rascunhoAberto(db, CASOS.autor);
    let grava = null;
    if (caso.depois === 'grava') {
      const r = await rpc(db, 'agenda_rascunho_gravar', { p_autor: CASOS.autor }, CASOS.hoje);
      if (r.error) throw new Error(`*grava*: ${r.error.message}`);
      grava = r.data;
    } else if (caso.depois) {
      throw new Error(`depois "${caso.depois}" não existe (só "grava")`);
    }
    const depois = caso.depois === 'grava' ? await foto(db) : meio;
    // As conferências que a foto não mostra (o nível do material na prontidão), no estado final.
    const consultas = [];
    for (const c of caso.espera?.banco?.consultas ?? []) {
      const r = await db.query(c.sql);
      consultas.push({ sql: c.sql, valor: r.rows[0] ? Object.values(r.rows[0])[0] ?? null : null });
    }
    return { antes: inicio.antes, meio, depois, rascunho_aberto: aberto, grava, consultas };
  } finally {
    await db.exec('rollback');
  }
}

async function rodarResposta(db, caso, resposta, estados) {
  const inicio = await iniciarCaso(db, caso);
  const saidas = [];
  let execucao;
  try {
    for (const c of resposta.chamadas ?? []) saidas.push(await executarChamada(db, c));
  } finally {
    execucao = await terminarCaso(db, caso, inicio);
  }
  if (caso.espera?.banco?.igual_ao_estado) execucao.estado_esperado = estados.get(caso.espera.banco.igual_ao_estado);
  const texto = montarTexto(resposta.texto, saidas);
  return { saidas, texto, execucao, nota: avaliar(caso, { chamadas: resposta.chamadas ?? [], texto, saidas, execucao }) };
}

// ── A ponte HTTP para o ao-vivo.ts ──────────────────────────────────────────────────────────────────────

async function servirPonte(db, porta) {
  let caso = null;
  let inicio = null;
  let fila = Promise.resolve();
  const corpo = (req) => new Promise((ok, erro) => {
    let s = '';
    req.on('data', (c) => { s += c; });
    req.on('end', () => { try { ok(s ? JSON.parse(s) : {}); } catch (e) { erro(e); } });
  });
  const rotas = {
    'GET /casos': async () => CASOS,
    'POST /inicio': async ({ id }) => {
      if (caso) await terminarCaso(db, caso, inicio).catch(() => {});
      caso = CASOS.casos.find((c) => c.id === id);
      if (!caso) throw new Error(`caso ${id} não existe`);
      inicio = await iniciarCaso(db, caso);
      return { ok: true, caso };
    },
    'POST /rpc': async ({ fn, params }) => {
      if (!caso) throw new Error('sem caso aberto (POST /inicio)');
      return rpc(db, fn, params ?? {}, CASOS.hoje);
    },
    'POST /fim': async () => {
      if (!caso) throw new Error('sem caso aberto');
      const c = caso;
      caso = null;
      const execucao = await terminarCaso(db, c, inicio);
      if (c.espera?.banco?.igual_ao_estado) execucao.estado_esperado = await fotoDoEstado(db, c.espera.banco.igual_ao_estado);
      return execucao;
    },
  };
  createServer((req, res) => {
    fila = fila.then(async () => {
      const rota = rotas[`${req.method} ${req.url}`];
      try {
        if (!rota) throw new Error(`rota ${req.method} ${req.url} não existe`);
        const r = await rota(await corpo(req));
        res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(r));
      } catch (e) {
        res.writeHead(500, { 'content-type': 'application/json' }).end(JSON.stringify({ erro: String(e?.message ?? e) }));
      }
    });
  }).listen(porta, '127.0.0.1', () => console.log(`ponte da bancada em http://127.0.0.1:${porta} (Ctrl+C para sair)`));
}

// ── Os juízes sabem reprovar? (as regras que nenhuma resposta ruim exercita) ─────────────────────────────

export function controlesDosJuizes() {
  const caso = { entrada: 'o painel do Nelson chega dia 3', espera: { nao_afirma_gravado: true, datas_so_do_banco: true, os_so_do_banco: true } };
  const foto = (situacao) => ({ material: { 'OS-00112 Painel': { situacao } } });
  const controles = [
    ['banco: o que mudou ANTES do *grava* reprova, mesmo com o diff final certo',
      !gradeBanco({ espera: { banco: { diff: [] } } }, { antes: foto('falta'), meio: foto('na_mao'), depois: foto('falta') }).ok],
    ['banco: diff igual passa', gradeBanco({ espera: { banco: { diff: [] } } }, { antes: foto('falta'), meio: foto('falta'), depois: foto('falta') }).ok],
    ['texto: "Nada foi gravado ainda" e "não gravei" passam', gradeTexto(caso, 'Nada foi gravado ainda; não gravei nada.', []).ok],
    ['texto: "Gravado." e "anotei" reprovam', !gradeTexto(caso, 'Gravado. Anotei o painel.', []).ok],
    ['texto: data e OS fora das saídas reprovam; as das saídas passam',
      !gradeTexto(caso, 'chega 04/11', [{ texto: 'chega ter 03/11' }]).ok && !gradeTexto(caso, 'OS-00113', [{ texto: 'OS-00112' }]).ok
      && gradeTexto(caso, 'chega 3/11 (OS 112)', [{ texto: 'chega ter 03/11 — Nelson (OS-00112)' }]).ok],
    ['texto: "3/11" = "03/11" e "orc 119" = "ORÇ-00119"', datasDe('3/11')[0] === '03/11' && numerosDeOsDe('orc 119')[0] === 'ORÇ-00119'],
    ['ferramentas: trecho que o dono não disse reprova',
      !gradeFerramentas(caso, [{ ferramenta: 'material_informar', argumentos: { trecho: 'o painel chegou' } }]).ok],
    ['ferramentas: data calculada reprova',
      !gradeFerramentas(caso, [{ ferramenta: 'agenda_ver', argumentos: { periodo: '2026-11-03' } }]).ok],
    ['ferramentas: escrita fora do rascunho reprova (create_task)',
      !gradeFerramentas(caso, [{ ferramenta: 'create_task', argumentos: {} }]).ok],
  ];
  return controles.map(([nome, ok]) => ({ nome, ok: !!ok }));
}

// ── Principal ───────────────────────────────────────────────────────────────────────────────────────────

const ehPrincipal = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (ehPrincipal) {
  const db = await bancadaDosEvals();
  const porta = argumento('--ponte');
  if (porta) {
    await servirPonte(db, Number(porta));
  } else {
    const so = argumento('--caso');
    const casos = CASOS.casos.filter((c) => !so || c.id === so);
    if (!casos.length) throw new Error(`nenhum caso ${so}`);
    const estados = new Map();
    for (const c of casos) {
      const e = c.espera?.banco?.igual_ao_estado;
      if (e && !estados.has(e)) estados.set(e, await fotoDoEstado(db, e));
    }
    let falhas = 0;
    const mostrar = (ok, texto) => {
      if (!ok) falhas++;
      console.log(`${ok ? 'ok    ' : 'FALHOU'} ${texto}`);
    };
    for (const c of controlesDosJuizes()) mostrar(c.ok, `juízes · ${c.nome}`);
    for (const caso of casos) {
      const r = RESPOSTAS[caso.id];
      if (!r?.boa || !r?.ruim) {
        mostrar(false, `${caso.id}: falta a resposta boa ou a ruim em respostas-modelo.json`);
        continue;
      }
      const boa = await rodarResposta(db, caso, r.boa, estados);
      mostrar(boa.nota.ok, `${caso.id} boa passa nos três juízes`);
      if (!boa.nota.ok) {
        for (const j of ['ferramentas', 'texto', 'banco']) for (const f of boa.nota[j].falhas) console.log(`         ${j}: ${f}`);
      }
      const ruim = await rodarResposta(db, caso, r.ruim, estados);
      const alvo = r.ruim.reprova_em;
      const reprovou = ruim.nota[alvo] && !ruim.nota[alvo].ok;
      mostrar(!!reprovou, `${caso.id} ruim reprova em ${alvo}${reprovou ? `: ${ruim.nota[alvo].falhas[0]}` : ' — PASSOU, o juiz não pegou'}`);
    }
    // Todo caso tem as duas respostas, e nenhuma resposta sobra sem caso.
    const sobra = Object.keys(RESPOSTAS).filter((k) => !k.startsWith('_') && !CASOS.casos.some((c) => c.id === k));
    if (sobra.length) mostrar(false, `respostas sem caso: ${sobra.join(', ')}`);
    await db.close();
    console.log(falhas ? `\n${falhas} falha(s)` : `\ntudo ok (${casos.length} casos × boa e ruim)`);
    process.exit(falhas ? 1 : 0);
  }
}
