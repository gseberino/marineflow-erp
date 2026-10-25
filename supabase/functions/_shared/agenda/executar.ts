// Agenda de Produção, Fase 1 (P6): as palavras curtas da agenda, com o banco. Spec: spec-fase1.md §7.2.
//
// Quem chama (ai-agent: o turno do WhatsApp e o do painel) passa o texto do dono por camadaDaAgenda, depois da
// confirmação (sim/ok/1), da lista de opções e do secretário, e antes do atalho do PDF e do modelo. A camada:
//   1. lê a palavra (lerComandoDaAgenda, puro) — o que não é comando volta null sem tocar no banco;
//   2. confere que é o dono (WhatsApp: o mesmo dono do resumo; painel: o administrador);
//   3. lê agenda_config.modo_leitura (erro, tabela ausente ou 'desligado' = a camada não existe: o texto segue ao
//      modelo como sempre). A chave só é lida quando o texto É comando. Exceção: com a agenda desligada, o *grava* e o
//      *descarta* ainda respondem quando há rascunho aberto do dono (o que ficou de antes de desligar tem saída;
//      sem rascunho, o "grava" segue como antes, inclusive para o "sim" do CMP);
//   4. chama UMA RPC: agenda_ver (o texto pronto do banco), agenda_rascunho_gravar (o *grava*) ou
//      agenda_rascunho_descartar. O texto que o dono lê sai do banco; aqui nada é calculado.
// Nunca lança: erro vira uma frase ao dono e uma linha em app_error_logs (context 'agenda', action 'comando:<x>').
//
// O *grava* só existe aqui (e no painel, pela mesma camada): o modelo não tem ferramenta para gravar. Por isso as
// ferramentas de rascunho (os_planejar, material_informar, equipe_disponibilidade) podem rodar direto pela rede.
//
// Fase 2 (P5, 24/10/2026; spec-fase2.md §11): *dia feito*, *dia não* + motivo, *dia parcial* + motivo, *choveu* e
// *desfaz* executam direto (agenda_conferir_dia, agenda_choveu, agenda_desfazer_dito): são a ordem exata do dono, e o
// banco confere o administrador, o modo da agenda (fora de 'ligado': "a agenda automática está em teste", nada muda) e
// o motivo (sem ele, a frase que pede). *o que mudou*, *agenda pendências* e *agenda plano* são agenda_ver. E os modos da
// Fase 2 para quem lê o plano (o secretário, a my_agenda, o panorama): modoDaPropostaNoBanco e modosDaAgendaNoBanco
// (erro = 'desligado', o caminho de hoje).
//
// Fase 3 (P3, 24/10/2026; spec-fase3.md §11): *concluiu [<alvo>]* e *entreguei <alvo>* executam direto
// (agenda_concluir_dito, agenda_entregar_dito): a conclusão e a entrega pela porta, com a saída e as cobranças da
// condição na mesma transação, e o texto do banco ("Concluí o Lenine (OS-00074) hoje … *desfaz OS-00074* volta como
// estava."). O alvo que o banco não acha (nao_achei: "concluiu a instalação") segue ao modelo, como o *desfaz <nome>*.
//
// Fase 3 (P4, 24/10/2026): *diária <nome> inteira|meia|não [quando]* executa direto (agenda_diaria_dita): responde a
// pergunta da diária aberta ou corrige/apaga a que a agenda lançou. Só com agenda_config.modo_diaria fora de 'desligado'
// (modoDaDiariaNoBanco, lido num SELECT à parte: a coluna é da Fase 3 e a falta dela não pode calar as palavras da Fase 2).
// Sem nada da agenda (nao_achei) o turno segue ao modelo e ao registrar_diaria de sempre.

import { logEdgeError } from "../log-error.ts";
import { lerModoDaProposta, type ModoDaProposta, modoDaPropostaNoBanco } from "../agenda-modo.ts";
import { type ComandoDaAgenda, ehPalavraDaDiaria, ehPalavraDaFase2, lerComandoDaAgenda } from "./comandos.ts";
import { paraAgendaVer, RPC_AGENDA_VER } from "./rpc-das-ferramentas.ts";

// deno-lint-ignore no-explicit-any
type Cliente = any;

export const RPC_GRAVAR = "agenda_rascunho_gravar";
export const RPC_DESCARTAR = "agenda_rascunho_descartar";
/** Fase 2: as palavras da conferência do dia e do desfazer. */
export const RPC_CONFERIR_DIA = "agenda_conferir_dia";
export const RPC_CHOVEU = "agenda_choveu";
export const RPC_DESFAZER_DITO = "agenda_desfazer_dito";
/** Fase 3: as palavras de concluir e de entregar. */
export const RPC_CONCLUIR_DITO = "agenda_concluir_dito";
export const RPC_ENTREGAR_DITO = "agenda_entregar_dito";
/** Fase 3 (P4): a palavra da diária. */
export const RPC_DIARIA_DITA = "agenda_diaria_dita";

export { modoDaPropostaNoBanco };
export type { ModoDaProposta };

/** Os dois modos da Fase 2: o que o motor faz (proposta) e o que o sistema diz sozinho (vigia). */
export interface ModosDaAgenda {
  proposta: ModoDaProposta;
  vigia: ModoDaProposta;
}

/**
 * agenda_config.modo_proposta e modo_vigia (um SELECT). Nunca lança: erro, tabela ou coluna ausente (as migrations da
 * Fase 2 ainda não aplicadas) ou linha ausente = os dois 'desligado' — quem lê continua lendo como antes.
 */
export async function modosDaAgendaNoBanco(admin: Cliente): Promise<ModosDaAgenda> {
  try {
    const { data, error } = await admin.from("agenda_config").select("modo_proposta, modo_vigia").maybeSingle();
    if (error) return { proposta: "desligado", vigia: "desligado" };
    return { proposta: lerModoDaProposta(data?.modo_proposta), vigia: lerModoDaProposta(data?.modo_vigia) };
  } catch {
    return { proposta: "desligado", vigia: "desligado" };
  }
}

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
 * (Fase 3, P4) agenda_config.modo_diaria (um SELECT só dela). Nunca lança: erro, coluna ausente (a migration
 * 20261026100000 não aplicada) ou linha ausente = "desligado" — a palavra *diária* segue ao modelo como antes.
 */
export async function modoDaDiariaNoBanco(admin: Cliente): Promise<ModoDaLeitura> {
  try {
    const { data, error } = await admin.from("agenda_config").select("modo_diaria").maybeSingle();
    if (error) return "desligado";
    return lerModoDaLeitura(data?.modo_diaria);
  } catch {
    return "desligado";
  }
}

/**
 * Há rascunho da agenda aberto e dentro da validade (do autor, se vier)? Só para o *grava* ou *descarta* com a agenda
 * desligada. Nunca lança: erro, tabela ausente ou exceção = false (o caminho de hoje).
 */
export async function rascunhoAbertoNoBanco(admin: Cliente, autor?: string): Promise<boolean> {
  try {
    let q = admin.from("agenda_rascunho").select("id").eq("estado", "aberto").gt("expira_em", new Date().toISOString());
    if (autor) q = q.eq("autor", autor);
    const { data, error } = await q.limit(1);
    if (error) return false;
    return Array.isArray(data) && data.length > 0;
  } catch {
    return false;
  }
}

/** Com a agenda desligada, só o *grava* e o *descarta* do rascunho que ficou aberto passam. */
function passaDesligada(cmd: ComandoDaAgenda): boolean {
  return cmd.comando === "gravar" || cmd.comando === "descartar";
}

/** (Fase 2) A agenda automática está fora de 'desligado' (o motor ou a vigia)? Só então as palavras da Fase 2 valem. */
export function fase2Ligada(m: ModosDaAgenda): boolean {
  return m.proposta !== "desligado" || m.vigia !== "desligado";
}

/**
 * Para o webhook (roteamento do texto do dono): o texto é uma palavra da agenda E a agenda está ligada (sombra ou
 * ligado)? As palavras da Fase 2 (dia feito, choveu, desfaz, o que mudou…) só com a agenda automática fora de
 * 'desligado' (modo_proposta ou modo_vigia): antes disso "desfaz …" é de outras ferramentas e segue o caminho de sempre.
 * Desligada, só o *grava* ou *descarta* com rascunho aberto. A chave só é lida quando o texto é comando. Nunca lança
 * (erro = false: o caminho de hoje).
 */
export async function ehComandoDaAgendaLigada(admin: Cliente, texto: string): Promise<boolean> {
  const cmd = lerComandoDaAgenda(texto);
  if (cmd === null) return false;
  if ((await modoDaLeituraNoBanco(admin)) !== "desligado") {
    // (Fase 3, P4) a palavra *diária* só com a diária automática fora de 'desligado'
    if (ehPalavraDaDiaria(cmd)) return (await modoDaDiariaNoBanco(admin)) !== "desligado";
    return !ehPalavraDaFase2(cmd) || fase2Ligada(await modosDaAgendaNoBanco(admin));
  }
  return passaDesligada(cmd) && (await rascunhoAbertoNoBanco(admin));
}

export type ChamadaDoComando = { rpc: string; params: Record<string, unknown> };

/**
 * O comando → a RPC e os parâmetros. O "ver" passa pelo MESMO mapeamento da ferramenta agenda_ver
 * (rpc-das-ferramentas.ts): o comando e a ferramenta pedem a mesma coisa do mesmo jeito. `hoje` só em teste.
 * (Fase 2) `canal`: por onde o dono respondeu (a pergunta da conferência fica respondida por ele).
 */
export function chamadaDoComando(
  cmd: ComandoDaAgenda,
  autor: string,
  hoje?: string,
  canal: "whatsapp" | "painel" = "whatsapp",
): ChamadaDoComando {
  const comHoje = (p: Record<string, unknown>) => (hoje ? { ...p, p_hoje: hoje } : p);
  if (cmd.comando === "gravar") return { rpc: RPC_GRAVAR, params: comHoje({ p_autor: autor }) };
  if (cmd.comando === "descartar") return { rpc: RPC_DESCARTAR, params: { p_autor: autor } };
  // Fase 2: a palavra vai como o dono disse (o dia e o alvo são resolvidos no banco; aqui nada é calculado)
  if (cmd.comando === "dia") {
    return {
      rpc: RPC_CONFERIR_DIA,
      params: comHoje({ p_autor: autor, p_resultado: cmd.resultado, p_motivo: cmd.motivo, p_quando: cmd.quando, p_canal: canal }),
    };
  }
  if (cmd.comando === "choveu") return { rpc: RPC_CHOVEU, params: comHoje({ p_autor: autor, p_quando: cmd.quando, p_canal: canal }) };
  if (cmd.comando === "desfazer") {
    return { rpc: RPC_DESFAZER_DITO, params: comHoje({ p_autor: autor, p_alvo: cmd.alvo, p_canal: canal }) };
  }
  // Fase 3: concluir e entregar, com o alvo como o dono disse (o banco resolve a OS)
  if (cmd.comando === "concluir") {
    return { rpc: RPC_CONCLUIR_DITO, params: comHoje({ p_autor: autor, p_alvo: cmd.alvo, p_canal: canal }) };
  }
  if (cmd.comando === "entregar") {
    return { rpc: RPC_ENTREGAR_DITO, params: comHoje({ p_autor: autor, p_alvo: cmd.alvo, p_canal: canal }) };
  }
  // Fase 3 (P4): a pessoa, a jornada e o dia como o dono disse (o banco resolve a pessoa e o dia)
  if (cmd.comando === "diaria") {
    return {
      rpc: RPC_DIARIA_DITA,
      params: comHoje({ p_autor: autor, p_nome: cmd.nome, p_jornada: cmd.jornada, p_quando: cmd.quando, p_canal: canal }),
    };
  }
  const args: Record<string, unknown> = { foco: cmd.foco };
  if (cmd.periodo) args.periodo = cmd.periodo;
  // (Fase 3, P6) o mês da comissão como o dono disse ("outubro"): o banco resolve (_agenda_mes_dito)
  if (cmd.mes) args.periodo = cmd.mes;
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
/** Fase 2: quando o banco falha no *dia feito* / *choveu* (o dono manda de novo; anotar duas vezes não muda nada). */
export const TEXTO_SEM_ANOTAR =
  "Não consegui anotar o dia agora. Mande de novo em alguns minutos: se já tiver anotado, eu digo que está anotado.";
export const TEXTO_SEM_DESFAZER = "Não consegui desfazer agora. Mande *desfaz* de novo em alguns minutos.";
/** Fase 3: quando o banco falha no *concluiu* / *entreguei* (concluir duas vezes não lança nada em dobro). */
export const TEXTO_SEM_CONCLUIR =
  "Não consegui concluir agora. Mande *concluiu* de novo em alguns minutos: se já tiver concluído, eu digo que está concluída.";
export const TEXTO_SEM_ENTREGAR =
  "Não consegui marcar a entrega agora. Mande *entreguei* de novo em alguns minutos: se já tiver marcado, eu digo que já foi entregue.";
/** Fase 3 (P4): quando o banco falha na palavra *diária* (mandar de novo não lança em dobro: a agenda diz que já está assim). */
export const TEXTO_SEM_DIARIA =
  "Não consegui mexer na diária agora. Mande de novo em alguns minutos: se já tiver feito, eu digo que já está assim.";

function textoDoErro(cmd: ComandoDaAgenda, e: unknown): string {
  if ((e as { code?: unknown })?.code === "42501") return TEXTO_SO_ADMIN;
  switch (cmd.comando) {
    case "gravar":
      return TEXTO_SEM_GRAVAR;
    case "descartar":
      return TEXTO_SEM_DESCARTAR;
    case "dia":
    case "choveu":
      return TEXTO_SEM_ANOTAR;
    case "desfazer":
      return TEXTO_SEM_DESFAZER;
    case "concluir":
      return TEXTO_SEM_CONCLUIR;
    case "entregar":
      return TEXTO_SEM_ENTREGAR;
    case "diaria":
      return TEXTO_SEM_DIARIA;
    default:
      return TEXTO_SEM_AGENDA;
  }
}

/** A RPC de cada comando (para o registro do erro, antes de montar os parâmetros). */
function rpcDoComando(cmd: ComandoDaAgenda): string {
  switch (cmd.comando) {
    case "gravar":
      return RPC_GRAVAR;
    case "descartar":
      return RPC_DESCARTAR;
    case "dia":
      return RPC_CONFERIR_DIA;
    case "choveu":
      return RPC_CHOVEU;
    case "desfazer":
      return RPC_DESFAZER_DITO;
    case "concluir":
      return RPC_CONCLUIR_DITO;
    case "entregar":
      return RPC_ENTREGAR_DITO;
    case "diaria":
      return RPC_DIARIA_DITA;
    default:
      return RPC_AGENDA_VER;
  }
}

/**
 * (Fase 2) O *desfaz <nome>* que o banco não ligou a nenhuma mudança da agenda (o nome não é de OS, a OS já saiu da
 * carteira ou não tem mudança dela): não mudou nada, e o pedido pode ser de outra ferramenta. O turno segue ao modelo.
 * "desfaz semana" e o *desfaz* sozinho são só da agenda: a frase do banco vale. Ambíguo também fica: a pergunta é dela.
 */
const NAO_E_DA_AGENDA = new Set(["nao_achei", "nenhuma", "fora_da_carteira"]);
function seguirAoModelo(cmd: ComandoDaAgenda, data: unknown): boolean {
  const r = data && typeof data === "object" && !Array.isArray(data) ? data as Record<string, unknown> : null;
  // (Fase 3) *concluiu <alvo>* / *entreguei <alvo>* que não acha OS nenhuma ("concluiu a instalação"): não é da agenda.
  // Ambíguo, já concluída, orçamento e a recusa da porta ficam: são a resposta do banco sobre uma OS que existe.
  if ((cmd.comando === "concluir" || cmd.comando === "entregar") && cmd.alvo !== null) {
    return !!r && r.ok !== true && String(r.status) === "nao_achei";
  }
  // (Fase 3, P4) *diária <nome> …* sem pergunta nem diária da agenda (ou a pessoa que não é da equipe): o registrar_diaria
  // de sempre, pelo modelo. Ambíguo, a opção que não existe e o acerto fechado ficam: são a resposta do banco.
  if (cmd.comando === "diaria") return !!r && r.ok !== true && String(r.status) === "nao_achei";
  if (cmd.comando !== "desfazer" || cmd.alvo === null || cmd.alvo === "semana") return false;
  return !!r && r.ok !== true && NAO_E_DA_AGENDA.has(String(r.status));
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
  /** (Fase 2) nada mudou e o pedido não é da agenda: o turno segue ao modelo (camadaDaAgenda devolve null) */
  seguirAoModelo?: boolean;
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
  let rpc = rpcDoComando(cmd);
  try {
    const chamada = chamadaDoComando(cmd, ctx.autor, undefined, ctx.canal ?? "whatsapp");
    rpc = chamada.rpc;
    const { data, error } = await cliente.rpc(chamada.rpc, chamada.params);
    if (error) throw error;
    const texto = textoDaResposta(data);
    // leitura que falha nunca vira "nada marcado": sem texto é erro
    if (texto === null) throw new Error(`${chamada.rpc} respondeu sem texto`);
    return seguirAoModelo(cmd, data) ? { ok: true, texto, seguirAoModelo: true } : { ok: true, texto };
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
  /**
   * (Fase 2) agenda_config.modo_proposta e modo_vigia (modosDaAgendaNoBanco). Só é chamado com uma palavra da Fase 2.
   * Ausente ou erro = os dois 'desligado' (as palavras da Fase 2 seguem ao modelo).
   */
  modosDaFase2?(): Promise<ModosDaAgenda>;
  /**
   * (Fase 3, P4) agenda_config.modo_diaria (modoDaDiariaNoBanco). Só é chamado com a palavra *diária*. Ausente ou erro =
   * 'desligado' (a palavra segue ao modelo).
   */
  modoDaDiaria?(): Promise<ModoDaLeitura>;
  /** executarComandoDaAgenda com o cliente do canal. */
  executar(cmd: ComandoDaAgenda): Promise<RespostaDoComando>;
  /**
   * Há rascunho aberto do dono (rascunhoAbertoNoBanco)? Só é chamado com a agenda desligada e o *grava* ou *descarta*.
   * Ausente = não há (desligada, nada passa).
   */
  rascunhoAberto?(): Promise<boolean>;
}

export interface RespostaDaCamada {
  comando: ComandoDaAgenda;
  /** o que vai ao dono, sem o modelo */
  texto: string;
  ok: boolean;
}

/**
 * A camada inteira. null = não é comando da agenda, não é o dono ou a agenda está desligada (salvo o *grava* ou *descarta*
 * com rascunho aberto): o turno segue (secretário já passou; vem o atalho do PDF e o modelo). As palavras da Fase 2 só
 * com a agenda automática fora de 'desligado'; o *desfaz <nome>* que o banco não liga a mudança nenhuma também segue ao
 * modelo. Nada é lido no banco quando o texto não é comando, e o modo só é lido quando é o dono. Nunca lança.
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
  if (modo === "desligado") {
    if (!passaDesligada(comando)) return null;
    let aberto = false;
    try {
      aberto = (await deps.rascunhoAberto?.()) === true;
    } catch {
      aberto = false;
    }
    if (!aberto) return null;
  }
  if (ehPalavraDaFase2(comando)) {
    let modos: ModosDaAgenda = { proposta: "desligado", vigia: "desligado" };
    try {
      modos = (await deps.modosDaFase2?.()) ?? modos;
    } catch {
      modos = { proposta: "desligado", vigia: "desligado" };
    }
    if (!fase2Ligada(modos)) return null;
  }
  if (ehPalavraDaDiaria(comando)) {
    let md: ModoDaLeitura = "desligado";
    try {
      md = (await deps.modoDaDiaria?.()) ?? "desligado";
    } catch {
      md = "desligado";
    }
    if (md === "desligado") return null;
  }
  let r: RespostaDoComando;
  try {
    r = await deps.executar(comando);
  } catch {
    // executarComandoDaAgenda não lança; um executar de outro jeito que lance ainda assim não derruba o turno
    r = { ok: false, texto: textoDoErro(comando, null) };
  }
  if (r.seguirAoModelo) return null;
  return { comando, texto: r.texto, ok: r.ok };
}
