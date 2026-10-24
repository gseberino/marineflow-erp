// Evals AO VIVO da Agenda de Produção (Fase 1, P7; spec §8.5): o modelo de verdade, com o prompt de verdade
// (buildSystemBlocks) e as ferramentas de verdade (agenda-producao.ts), contra a bancada local. OPCIONAL e fora dos
// portões: custa chamadas de modelo, e só roda quando o dono quiser.
//
// Como rodar (dois terminais, na raiz do worktree):
//   1. a bancada, servindo pela ponte HTTP (só 127.0.0.1):
//        node scripts/bancada-agenda/evals/rodar-evals.mjs --ponte 8787
//   2. este script. Sem --vai, só mostra o plano (casos, vezes, chamadas) e não chama modelo nenhum:
//        deno run --no-lock --allow-net=127.0.0.1:8787,openrouter.ai --allow-env=OPENROUTER_API_KEY --allow-read \
//          scripts/bancada-agenda/evals/ao-vivo.ts --vezes 3 --vai
//      A chave é a do OpenRouter que o dono EXPORTA no próprio shell (export OPENROUTER_API_KEY=…). Nunca de .env:
//      não use --env-file, e o script não lê arquivo de credencial nenhum.
//   Ensaio sem modelo (prova a ponte, o laço e os juízes; não gasta nada): --ensaio. Ele toca as respostas BOAS de
//   respostas-modelo.json pelo mesmo laço, com as três de rascunho pela ferramenta_extra, como em produção.
//
// O que o modelo vê: o prompt do WhatsApp do dono (perfil enxuto do admin) e, à vista, agenda_ver + as vizinhas que a
// seção AGENDA DE PRODUÇÃO cita (create_task, get_purchase_needs, check_technician_availability, list_team_agenda),
// mais a ferramenta_extra com os_planejar, material_informar, equipe_disponibilidade, my_agenda e
// schedule_service_order (a rede, como no perfil enxuto). --ferramentas enxuto manda o PERFIL_ADMIN inteiro (mais
// caro, mais perto de produção). Só as 4 da agenda rodam (na bancada); as outras devolvem "nada foi executado no
// ensaio" e ficam registradas para o juiz das ferramentas.
//
// Meta (spec §8.5): pass^3 ≥ 90% na leitura e 100% na rodada e na OS que não existe (L08). pass^k = o caso passa
// nas k vezes.
import { buildSystemBlocks } from "../../../supabase/functions/_shared/ai/prompt.ts";
import { callClaude, type ClaudeContentBlock, type ClaudeMessage, type ClaudeToolSchema } from "../../../supabase/functions/_shared/ai/anthropic.ts";
import { MODEL_AGENT } from "../../../supabase/functions/_shared/ai/models.ts";
import { agendaProducaoTools } from "../../../supabase/functions/_shared/ai/tools/agenda-producao.ts";
import { allTools } from "../../../supabase/functions/_shared/ai/tools/index.ts";
import { PERFIL_ADMIN } from "../../../supabase/functions/_shared/ai/perfil-operacao.ts";
import { construirFerramentaExtra, NOME_DA_FERRAMENTA_EXTRA } from "../../../supabase/functions/_shared/ai/ferramenta-extra.ts";
import type { ToolCtx, ToolDef } from "../../../supabase/functions/_shared/ai/tools/registry.ts";
import { avaliar, montarTexto } from "./graders.mjs";

type Chamada = { ferramenta: string; argumentos: Record<string, unknown> };
type Caso = { id: string; grupo: string; entrada: string; espera?: Record<string, unknown> };
type Resposta = { chamadas: Chamada[]; texto: string };

function argumento(nome: string): string | undefined {
  const i = Deno.args.indexOf(nome);
  return i >= 0 ? Deno.args[i + 1] : undefined;
}
const tem = (nome: string) => Deno.args.includes(nome);

const PONTE = argumento("--ponte") ?? "http://127.0.0.1:8787";
const VEZES = Number(argumento("--vezes") ?? "3");
const SO = argumento("--caso");
const ENSAIO = tem("--ensaio");
const VAI = tem("--vai");
const PERFIL = argumento("--ferramentas") ?? "agenda";
const MAX_VOLTAS = 10; // o teto do WhatsApp (MAX_ITERATIONS_WHATSAPP)

async function ponte<T>(rota: string, corpo?: unknown): Promise<T> {
  const r = await fetch(`${PONTE}${rota}`, {
    method: corpo === undefined ? "GET" : "POST",
    headers: { "content-type": "application/json" },
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`ponte ${rota}: ${j?.erro ?? r.status}`);
  return j as T;
}

// ── As ferramentas do turno ─────────────────────────────────────────────────────────────────────────────

const DA_AGENDA = new Map(agendaProducaoTools.map((t) => [t.name, t]));
const TODAS = new Map((allTools as ToolDef[]).map((t) => [t.name, t]));
const A_VISTA_AGENDA = ["agenda_ver", "create_task", "get_purchase_needs", "check_technician_availability", "list_team_agenda"];
const PELA_REDE = ["os_planejar", "material_informar", "equipe_disponibilidade", "my_agenda", "schedule_service_order"];

function ferramentasDoTurno(): { visiveis: ToolDef[]; extra: ToolDef } {
  const nomes = PERFIL === "enxuto" ? [...PERFIL_ADMIN] : A_VISTA_AGENDA;
  const visiveis = nomes.map((n) => TODAS.get(n)).filter((t): t is ToolDef => !!t && (t.roles?.includes("admin") ?? true));
  const rede = PERFIL === "enxuto"
    ? [...TODAS.keys()].filter((n) => !PERFIL_ADMIN.has(n))
    : PELA_REDE;
  return { visiveis, extra: construirFerramentaExtra(rede) };
}

const esquema = (t: ToolDef): ClaudeToolSchema => ({ name: t.name, description: t.description, input_schema: t.input_schema as Record<string, unknown> });

/** O ctx das ferramentas da agenda: o dono pelo WhatsApp, com a ponte da bancada no lugar do supabase-js. */
function ctxDaPonte(autor: string): ToolCtx {
  const sb = { rpc: (fn: string, params: Record<string, unknown>) => ponte<{ data: unknown; error: unknown }>("/rpc", { fn, params }) };
  return { sb, admin: sb, userId: autor, userRole: "admin", jwt: "", appOrigin: "", settings: {}, canal: "whatsapp" };
}

/** Uma chamada do modelo: ferramenta_extra é desembrulhada; só as 4 da agenda rodam. */
async function executar(nome: string, input: Record<string, unknown>, autor: string): Promise<{ chamada: Chamada; saida: unknown }> {
  let alvo = nome;
  let args = input ?? {};
  if (nome === NOME_DA_FERRAMENTA_EXTRA) {
    alvo = String(input?.nome ?? "");
    if (input?.descrever === true) {
      const t = TODAS.get(alvo);
      return {
        chamada: { ferramenta: `${NOME_DA_FERRAMENTA_EXTRA}:descrever`, argumentos: input },
        saida: t ? { nome: t.name, description: t.description, input_schema: t.input_schema } : { error: `'${alvo}' não existe` },
      };
    }
    args = (input?.argumentos && typeof input.argumentos === "object" ? input.argumentos : {}) as Record<string, unknown>;
  }
  const chamada = { ferramenta: alvo, argumentos: args };
  const t = DA_AGENDA.get(alvo);
  if (!t) return { chamada, saida: { error: "Nada foi executado no ensaio: esta ferramenta não é da agenda." } };
  try {
    return { chamada, saida: await t.execute(args, ctxDaPonte(autor)) };
  } catch (e) {
    return { chamada, saida: { error: String((e as Error)?.message ?? e) } };
  }
}

// ── O laço de um caso ───────────────────────────────────────────────────────────────────────────────────

type Modelo = (system: ReturnType<typeof buildSystemBlocks>, mensagens: ClaudeMessage[], tools: ClaudeToolSchema[], volta: number) => Promise<ClaudeContentBlock[]>;

// O mesmo esforço do WhatsApp em produção (ai-agent/index.ts: "low", conversa rápida).
const modeloDeVerdade: Modelo = async (system, messages, tools) =>
  (await callClaude({ model: MODEL_AGENT, system, messages, tools, effort: "low" })).content;

/** O ensaio: toca a resposta boa (as chamadas numa volta, o texto na seguinte), rascunho pela ferramenta_extra. */
function modeloDeEnsaio(boa: Resposta, saidas: unknown[]): Modelo {
  return (_s, _m, _t, volta) => {
    if (volta === 0 && boa.chamadas.length) {
      return Promise.resolve(boa.chamadas.map((c, i) => {
        const pelaRede = PELA_REDE.includes(c.ferramenta);
        return {
          type: "tool_use" as const,
          id: `ensaio-${i}`,
          name: pelaRede ? NOME_DA_FERRAMENTA_EXTRA : c.ferramenta,
          input: pelaRede ? { nome: c.ferramenta, argumentos: c.argumentos } : c.argumentos,
        };
      }));
    }
    return Promise.resolve([{ type: "text" as const, text: montarTexto(boa.texto, saidas) }]);
  };
}

async function rodarCaso(caso: Caso, autor: string, modelo: (saidas: unknown[]) => Modelo) {
  await ponte("/inicio", { id: caso.id });
  const chamadas: Chamada[] = [];
  const saidas: unknown[] = [];
  let texto = "";
  let execucao: Record<string, unknown> = {};
  try {
    const system = buildSystemBlocks({ ai_tool_profile: "admin_enxuto" }, { userName: "Gustavo", userRole: "admin", channel: "whatsapp" });
    const { visiveis, extra } = ferramentasDoTurno();
    const tools = [...visiveis, extra].map(esquema);
    const mensagens: ClaudeMessage[] = [{ role: "user", content: [{ type: "text", text: caso.entrada }] }];
    const m = modelo(saidas);
    for (let volta = 0; volta < MAX_VOLTAS; volta++) {
      const blocos = await m(system, mensagens, tools, volta);
      mensagens.push({ role: "assistant", content: blocos });
      const usos = blocos.filter((b): b is Extract<ClaudeContentBlock, { type: "tool_use" }> => b.type === "tool_use");
      if (!usos.length) {
        texto = blocos.filter((b) => b.type === "text").map((b) => (b as { text: string }).text).join("\n").trim();
        break;
      }
      const resultados: ClaudeContentBlock[] = [];
      for (const u of usos) {
        const { chamada, saida } = await executar(u.name, u.input, autor);
        chamadas.push(chamada);
        if (DA_AGENDA.has(chamada.ferramenta)) saidas.push(saida);
        resultados.push({ type: "tool_result", tool_use_id: u.id, content: JSON.stringify(saida) });
      }
      mensagens.push({ role: "user", content: resultados });
    }
  } finally {
    // o *grava* (quando o caso pede) e as fotos ficam com a ponte, que desfaz tudo no fim
    execucao = await ponte<Record<string, unknown>>("/fim", {});
  }
  return { chamadas, texto, saidas, execucao, nota: avaliar(caso, { chamadas, texto, saidas, execucao }) };
}

// ── Principal ───────────────────────────────────────────────────────────────────────────────────────────

const casosDaPonte = await ponte<{ autor: string; casos: Caso[] }>("/casos");
const casos = casosDaPonte.casos.filter((c) => !SO || c.id === SO);
const respostas = JSON.parse(await Deno.readTextFile(new URL("./respostas-modelo.json", import.meta.url))) as Record<string, { boa: Resposta }>;

if (!ENSAIO && !VAI) {
  console.log(`Plano: ${casos.length} casos × ${VEZES} vezes = ${casos.length * VEZES} conversas com ${MODEL_AGENT} ` +
    `(até ${MAX_VOLTAS} chamadas cada; ferramentas: ${PERFIL}). Nada foi chamado.\n` +
    "Para rodar de verdade: --vai (com OPENROUTER_API_KEY exportada no shell). Para ensaiar sem modelo: --ensaio.");
  Deno.exit(0);
}

const resultado = new Map<string, boolean[]>();
for (const caso of casos) {
  for (let v = 0; v < (ENSAIO ? 1 : VEZES); v++) {
    const r = await rodarCaso(caso, casosDaPonte.autor, ENSAIO ? (s) => modeloDeEnsaio(respostas[caso.id].boa, s) : () => modeloDeVerdade);
    resultado.set(caso.id, [...(resultado.get(caso.id) ?? []), r.nota.ok]);
    console.log(`${r.nota.ok ? "ok    " : "FALHOU"} ${caso.id} #${v + 1}`);
    if (!r.nota.ok) {
      for (const j of ["ferramentas", "texto", "banco"] as const) for (const f of r.nota[j].falhas) console.log(`         ${j}: ${f}`);
      console.log(`         texto: ${r.texto.slice(0, 300).replace(/\n/g, " ⏎ ")}`);
    }
  }
}

const passK = (grupo: (c: Caso) => boolean) => {
  const doGrupo = casos.filter(grupo);
  const passaram = doGrupo.filter((c) => (resultado.get(c.id) ?? []).every(Boolean)).length;
  return { passaram, de: doGrupo.length, pct: doGrupo.length ? Math.round((100 * passaram) / doGrupo.length) : 100 };
};
const leitura = passK((c) => c.grupo === "leitura" && c.id !== "L08");
const rodada = passK((c) => c.grupo === "rodada");
const l08 = passK((c) => c.id === "L08");
const k = ENSAIO ? 1 : VEZES;
console.log(`\npass^${k}: leitura ${leitura.passaram}/${leitura.de} (${leitura.pct}%, meta 90%) · rodada ${rodada.passaram}/${rodada.de} ` +
  `(${rodada.pct}%, meta 100%) · OS inexistente ${l08.passaram}/${l08.de} (meta 100%)`);
const bateu = leitura.pct >= 90 && rodada.pct === 100 && l08.pct === 100;
console.log(bateu ? "meta batida" : "meta NÃO batida");
Deno.exit(bateu ? 0 : 1);
