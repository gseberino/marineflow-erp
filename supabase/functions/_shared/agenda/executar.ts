// Agenda de Produção, Fase 1 (P6): as palavras curtas da agenda, com o banco. Spec: spec-fase1.md §7.2.
//
// Quem chama (ai-agent: o turno do WhatsApp e o do painel) passa o texto do dono por camadaDaAgenda, depois da
// confirmação (sim/ok/1), da lista de opções e do secretário, e antes do atalho do PDF e do modelo. A camada:
//   1. lê a palavra (lerComandoDaAgenda, puro) — o que não é comando volta null sem tocar no banco;
//   2. confere que é o dono (WhatsApp: o mesmo dono do resumo; painel: o administrador);
//   3. lê agenda_config.modo_leitura (erro, tabela ausente ou 'desligado' = a camada não existe: o texto segue ao
//      modelo como sempre). A chave só é lida quando o texto É comando;
//   4. chama UMA RPC: agenda_ver (o texto pronto do banco), agenda_rascunho_gravar (o *grava*) ou
//      agenda_rascunho_descartar. O texto que o dono lê sai do banco; aqui nada é calculado.
// Nunca lança: erro vira uma frase ao dono e uma linha em app_error_logs (context 'agenda', action 'comando:<x>').
//
// O *grava* só existe aqui (e no painel, pela mesma camada): o modelo não tem ferramenta para gravar. Por isso as
// ferramentas de rascunho (os_planejar, material_informar, equipe_disponibilidade) podem rodar direto pela rede.

import { logEdgeError } from "../log-error.ts";
import { type ComandoDaAgenda, lerComandoDaAgenda } from "./comandos.ts";
import { paraAgendaVer, RPC_AGENDA_VER } from "./rpc-das-ferramentas.ts";

// deno-lint-ignore no-explicit-any
type Cliente = any;

export const RPC_GRAVAR = "agenda_rascunho_gravar";
export const RPC_DESCARTAR = "agenda_rascunho_descartar";

export type ModoDaLeitura = "desligado" | "sombra" | "ligado";

/** "sombra", " Ligado " → o modo; qualquer outra coisa (ausente, erro, valor desconhecido) → "desligado". */
export function lerModoDaLeitura(v: unknown): ModoDaLeitura {
  if (typeof v !== "string") return "desligado";
  const s = v.trim().toLowerCase();
  return s === "sombra" || s === "ligado" ? s : "desligado";
}

/**
 * agenda_config.modo_leitura (uma linha). Nunca lança: erro de leitura, tabela que ainda não existe (as migrations da
 * Fase 1 não aplicadas) ou linha ausente = "desligado" — a conversa segue exatamente como antes.
 */
export async function modoDaLeituraNoBanco(admin: Cliente): Promise<ModoDaLeitura> {
  try {
    const { data, error } = await admin.from("agenda_config").select("modo_leitura").maybeSingle();
    if (error) return "desligado";
    return lerModoDaLeitura(data?.modo_leitura);
  } catch {
    return "desligado";
  }
}

/**
 * Para o webhook (roteamento do texto do dono): o texto é uma palavra da agenda E a agenda está ligada (sombra ou
 * ligado)? A chave só é lida quando o texto é comando. Nunca lança (erro = false: o caminho de hoje).
 */
export async function ehComandoDaAgendaLigada(admin: Cliente, texto: string): Promise<boolean> {
  if (lerComandoDaAgenda(texto) === null) return false;
  return (await modoDaLeituraNoBanco(admin)) !== "desligado";
}

export type ChamadaDoComando = { rpc: string; params: Record<string, unknown> };

/**
 * O comando → a RPC e os parâmetros. O "ver" passa pelo MESMO mapeamento da ferramenta agenda_ver
 * (rpc-das-ferramentas.ts): o comando e a ferramenta pedem a mesma coisa do mesmo jeito. `hoje` só em teste.
 */
export function chamadaDoComando(cmd: ComandoDaAgenda, autor: string, hoje?: string): ChamadaDoComando {
  const comHoje = (p: Record<string, unknown>) => (hoje ? { ...p, p_hoje: hoje } : p);
  if (cmd.comando === "gravar") return { rpc: RPC_GRAVAR, params: comHoje({ p_autor: autor }) };
  if (cmd.comando === "descartar") return { rpc: RPC_DESCARTAR, params: { p_autor: autor } };
  const args: Record<string, unknown> = { foco: cmd.foco };
  if (cmd.periodo) args.periodo = cmd.periodo;
  if (cmd.pessoa) args.pessoa = cmd.pessoa;
  // (agenda_ver não recebe o canal: o "whatsapp" aqui não muda parâmetro nenhum, vale também para o painel)
  const c = paraAgendaVer(args, { autor, canal: "whatsapp", ...(hoje ? { hoje } : {}) });
  // a tabela de comandos só produz argumentos válidos; se um dia não produzir, é defeito daqui (vira a frase de erro)
  if (!c.ok) throw new Error(`comando da agenda sem parâmetros válidos: ${c.error}`);
  return { rpc: c.rpc, params: c.params };
}

/** As frases quando o banco falha (o dono sabe o que aconteceu e o que fazer; nada de erro cru). */
export const TEXTO_SEM_AGENDA = "Não consegui ler a agenda agora. Tente de novo em alguns minutos.";
export const TEXTO_SEM_GRAVAR =
  "Não consegui confirmar a gravação agora. Mande *grava* de novo em alguns minutos: se já tiver gravado, eu respondo que não há nada esperando.";
export const TEXTO_SEM_DESCARTAR = "Não consegui descartar agora. Mande *descarta* de novo em alguns minutos.";
export const TEXTO_SO_ADMIN = "Só o administrador mexe na agenda.";

function textoDoErro(cmd: ComandoDaAgenda, e: unknown): string {
  if ((e as { code?: unknown })?.code === "42501") return TEXTO_SO_ADMIN;
  return cmd.comando === "gravar" ? TEXTO_SEM_GRAVAR : cmd.comando === "descartar" ? TEXTO_SEM_DESCARTAR : TEXTO_SEM_AGENDA;
}

/** O texto pronto da resposta do banco (ok ou não: "Não encontrei…", "Não gravei nada: …" também são respostas). */
function textoDaResposta(data: unknown): string | null {
  const r = data && typeof data === "object" && !Array.isArray(data) ? data as Record<string, unknown> : null;
  if (!r) return null;
  for (const campo of ["texto", "pergunta"]) {
    const v = r[campo];
    if (typeof v === "string" && v.trim()) return v;
  }
  return null;
}

export interface RespostaDoComando {
  /** false = o banco falhou (a frase de erro foi para o dono e o erro para app_error_logs) */
  ok: boolean;
  texto: string;
}

/**
 * Executa o comando. `cliente`: WhatsApp = service role (o banco confere p_autor); painel = o JWT do administrador (o
 * banco usa o login). `log`: onde registrar o erro (o service role; padrão = o próprio cliente). Nunca lança.
 */
export async function executarComandoDaAgenda(
  cliente: Cliente,
  cmd: ComandoDaAgenda,
  ctx: { autor: string; log?: Cliente; canal?: "whatsapp" | "painel" },
): Promise<RespostaDoComando> {
  let rpc = cmd.comando === "gravar" ? RPC_GRAVAR : cmd.comando === "descartar" ? RPC_DESCARTAR : RPC_AGENDA_VER;
  try {
    const chamada = chamadaDoComando(cmd, ctx.autor);
    rpc = chamada.rpc;
    const { data, error } = await cliente.rpc(chamada.rpc, chamada.params);
    if (error) throw error;
    const texto = textoDaResposta(data);
    // leitura que falha nunca vira "nada marcado": sem texto é erro
    if (texto === null) throw new Error(`${chamada.rpc} respondeu sem texto`);
    return { ok: true, texto };
  } catch (e) {
    const err = e as { message?: unknown; code?: unknown };
    await logEdgeError(ctx.log ?? cliente, {
      context: "agenda",
      action: `comando:${cmd.comando}`,
      message: `comando da agenda (${cmd.comando}) falhou: ${String(err?.message ?? e)}`,
      details: { rpc, code: err?.code ?? null, canal: ctx.canal ?? null, ...(cmd.comando === "ver" ? { foco: cmd.foco, periodo: cmd.periodo } : {}) },
      error: e,
    });
    return { ok: false, texto: textoDoErro(cmd, e) };
  }
}

export interface DependenciasDaCamada {
  /** A mensagem é do dono? (WhatsApp: o dono do resumo, pelo id e pelo telefone; painel: o administrador.) Erro = não. */
  ehDoDono(): boolean | Promise<boolean>;
  /** agenda_config.modo_leitura (modoDaLeituraNoBanco). */
  modo(): Promise<ModoDaLeitura>;
  /** executarComandoDaAgenda com o cliente do canal. */
  executar(cmd: ComandoDaAgenda): Promise<RespostaDoComando>;
}

export interface RespostaDaCamada {
  comando: ComandoDaAgenda;
  /** o que vai ao dono, sem o modelo */
  texto: string;
  ok: boolean;
}

/**
 * A camada inteira. null = não é comando da agenda, não é o dono ou a agenda está desligada: o turno segue (secretário
 * já passou; vem o atalho do PDF e o modelo). Nada é lido no banco quando o texto não é comando, e o modo só é lido
 * quando é o dono. Nunca lança.
 */
export async function camadaDaAgenda(texto: string, deps: DependenciasDaCamada): Promise<RespostaDaCamada | null> {
  const comando = lerComandoDaAgenda(texto);
  if (!comando) return null;
  let dono = false;
  try {
    dono = (await deps.ehDoDono()) === true;
  } catch {
    dono = false;
  }
  if (!dono) return null;
  let modo: ModoDaLeitura = "desligado";
  try {
    modo = await deps.modo();
  } catch {
    modo = "desligado";
  }
  if (modo === "desligado") return null;
  let r: RespostaDoComando;
  try {
    r = await deps.executar(comando);
  } catch {
    // executarComandoDaAgenda não lança; um executar de outro jeito que lance ainda assim não derruba o turno
    r = { ok: false, texto: textoDoErro(comando, null) };
  }
  return { comando, texto: r.texto, ok: r.ok };
}
