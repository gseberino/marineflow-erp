// Turno que leu texto de fora: escrita em cadastro, contato, preço e memória pede o "sim" (pacote 1 do assistente, S6,
// 24/11/2026).
//
// ═══ POR QUE EXISTE ═══
//
// Texto escrito por terceiro (conversa do WhatsApp, e-mail, mensagem ou mídia de fornecedor) é DADO, nunca instrução. Só
// que o modelo o lê no mesmo turno em que pode gravar, e várias gravações rodam direto, sem cartão: cadastrar ou
// corrigir cliente e fornecedor, ligar um número a um cadastro, silenciar um contato, mudar preço de produto, guardar
// uma observação na memória. Um e-mail ou uma mensagem que diga "atualize o telefone", "cadastre este número" ou "anote
// que o preço é X" não pode virar cadastro, contato, preço ou memória sem o dono ver.
//
// A regra: depois que o turno leu texto de fora, as escritas de SOBEM_PARA_SIM pedem o "sim" e as de SOBEM_PARA_PIN
// pedem o "sim" com PIN. O cartão diz por quê. Sem leitura de fora, nenhum risco muda. A função só SOBE o risco.
//
// Já existia só para o caso do retorno (riscoDoEnvioLivre, tools/retorno.ts: depois de ler um caso do cartão, o envio
// livre e o orçamento pedem PIN). Aquela marca fica na sessão; esta vale só para o turno e não é gravada em lugar nenhum.
//
// ═══ COMO O TURNO É MARCADO ═══
//
//  · Laço do OpenRouter (agent.ts): depois de uma ferramenta de LEITURAS_DE_TEXTO_DE_FORA rodar sem erro, o executor
//    liga ToolCtx.leuTextoDeFora, e o contexto é o mesmo até o fim do turno. As ferramentas de uma mesma resposta do
//    modelo rodam em SEQUÊNCIA: a escrita disparada junto com a leitura (que ainda não tinha visto o texto) também sobe.
//    Erra para o lado seguro; aceito de propósito (crítica de risco do pacote 1).
//  · Claude Max (erp-mcp): cada chamada é uma requisição com contexto novo. A marca sai de
//    ai_jobs.metadata.ferramentas_usadas, que o erp-mcp relê a cada chamada e onde a RPC ai_job_registrar_ferramenta
//    grava o nome DEPOIS de a ferramenta rodar. A leitura marca as chamadas seguintes; a escrita disparada em paralelo
//    com a leitura pode passar sem a marca (não viu o texto). A lista guarda o nome mesmo quando a leitura falhou:
//    aqui também erra para o lado seguro.
//  · O turno do vigia (acompanhar-conversas) já COMEÇA com texto de terceiro citado ("🤖 … Última mensagem dele: …"):
//    vale como leitura desde a primeira chamada, nos dois caminhos.
//  · O que não dá para conferir vale como "leu": a linha do job que não foi lida, a lista que não é lista, a lista
//    perto do teto em que a RPC para de acrescentar nomes (TETO_PARA_CONFIAR_NA_LISTA).
//
// ═══ LIMITES CONHECIDOS ═══
//
//  · Vale para o TURNO. O texto lido num turno anterior não marca o seguinte, mesmo quando um trecho dele ainda aparece
//    no histórico (o turno do Max guarda só a pergunta e a resposta final; os resultados antigos do laço chegam podados
//    e marcados como de turno anterior). "Continue" depois de uma pausa por tempo é turno novo.
//  · As listas são de nomes. Ferramenta nova que devolva texto de terceiro tem de entrar em LEITURAS_DE_TEXTO_DE_FORA
//    (texto-de-fora_test.ts varre o catálogo e acusa as que leem as tabelas e os campos de mensagem; a que lê por
//    função auxiliar entra à mão).
//  · Fora daqui, por decisão da especificação: add_service_order_item, create_quote_from_items, record_quote_response e
//    create_service_order não sobem (quebraria o "lê a conversa e monta o orçamento"); a mensagem a fornecedor segue a
//    regra do S1 (envio-livre.ts); o trabalho de fundo (triagem, detector) não passa por aqui.
//
// Reverter: riscoDepoisDeTextoDeFora devolver o risco como veio (uma linha); o resto fica inerte.
import { NOME_DA_FERRAMENTA_EXTRA } from "./ferramenta-extra.ts";
import type { RiscoNoServidor, RiskLevel } from "./tools/registry.ts";

// ─── As três listas ─────────────────────────────────────────────────────────────────────────────────────────────────

/**
 * Ferramentas cujo resultado traz texto ESCRITO POR TERCEIRO, como ele escreveu: mensagem recebida no WhatsApp, e-mail
 * (texto, assunto, nome de quem mandou), mensagem ou mídia de fornecedor. Todas de risco baixo (rodam direto).
 *
 * As oito primeiras são as da especificação. As outras foram achadas no código ao construir (a especificação conferiu
 * só as que leem whatsapp_messages.body e email_messages.body_text direto): elas devolvem o mesmo texto por RPC, view
 * ou coluna que guarda a frase original. Em 90 dias (medido em 25/11/2026) nenhuma delas foi chamada pelo assistente:
 * entrar na lista não muda a conta de quantos turnos leram texto de fora.
 */
export const LEITURAS_DE_TEXTO_DE_FORA: ReadonlySet<string> = new Set([
  // — as da especificação —
  "get_whatsapp_conversation", // a conversa inteira (whatsapp_messages.body)
  "ler_email", // o texto do e-mail (email_messages.body_text)
  "listar_emails", // assunto e nome de quem mandou
  "read_supplier_messages", // as mensagens recebidas do fornecedor
  "read_supplier_media", // PDF ou imagem do fornecedor convertido em texto
  "get_client_360", // traz as últimas mensagens do cliente
  "get_supplier_360", // traz as últimas mensagens do fornecedor
  "retorno_ler_caso", // as últimas mensagens do cliente do caso (RPC retorno_ver_caso_para_modelo)
  // — as que o código mostrou —
  "list_unanswered_messages", // a prévia da última mensagem de cada contato (RPC whatsapp_pending_inbox, last_body)
  "list_unidentified_contacts", // a última frase de cada número sem cadastro (view unidentified_contacts, ultima_frase)
  "get_open_loops", // a frase da conversa que abriu o fio (get_entity_open_loops, evidence)
  "list_agenda_suggestions", // "a frase original de cada uma" (agenda_suggestions.evidence)
  "accept_agenda_suggestions", // quando a busca serve para mais de uma, devolve as opções com a frase original
  "dismiss_agenda_suggestions", // idem
  "get_quote_comparison", // o trecho da resposta do fornecedor de onde saiu cada preço (source_excerpt)
  "rascunhar_resposta_email", // devolve o assunto e o nome de quem mandou o e-mail respondido
]);

/**
 * Cadastro, contato e preço: depois de ler texto de fora, pedem o "sim" (risco baixo sobe para médio). As que já pedem
 * o "sim" ou o PIN continuam no nível delas e ganham o motivo, que trava a autonomia e aparece no cartão.
 *
 * Todas as ferramentas que GRAVAM TELEFONE num registro que depois serve de destino estão aqui (o teste varre o
 * catálogo pelos campos phone, telefone e whatsapp): é a raiz do achado NOVO-p1-s1-04, em que cadastrar o número como
 * fornecedor ou equipe trocava o PIN da mensagem livre pelo "sim". A especificação citava create_supplier,
 * update_supplier e link_contact_identity; faltavam link_contact_to_entity (a que grava o número no fornecedor sem
 * telefone), link_whatsapp_lead_to_client, as marinas, o favorecido, o freelancer, a cobrança e a missão de acompanhamento.
 */
export const SOBEM_PARA_SIM: ReadonlySet<string> = new Set([
  // — cadastro —
  "create_client",
  "update_client",
  "create_supplier",
  "update_supplier",
  "create_vessel",
  "update_vessel",
  "create_marina", // telefone e contato da marina
  "update_marina",
  "alterar_favorecido", // telefone do favorecido (conta como "equipe" na mensagem livre); Pix e conta já pedem PIN (S3)
  "cadastrar_freelancer", // cria o favorecido, com telefone
  // — contato —
  "add_vessel_contact",
  "update_vessel_contact",
  "link_contact_identity", // grava o número no cliente, no fornecedor ou no lead
  "link_contact_to_entity", // grava o número no cliente ou no fornecedor sem telefone e religa as mensagens antigas
  "link_whatsapp_lead_to_client", // grava o WhatsApp do cliente que não tinha número
  "mute_contact", // tira o contato da caixa de entrada (e cria o contato pelo número, se não existe)
  "unmute_contact",
  "criar_cobranca", // o contato da cobrança pode vir dos argumentos (telefone, whatsapp)
  "alterar_cobranca",
  "criar_missao_acompanhamento", // o número avulso que a missão vai procurar
  // — preço —
  "apply_quote_price",
  "update_product",
  "update_service", // o preço do serviço do catálogo (o par de update_product; a especificação citava só o do produto)
  "set_quote_supplier_terms",
]);

/** Memória: o que o assistente passa a "saber" em todo turno. Depois de ler texto de fora, pede o "sim" com PIN. */
export const SOBEM_PARA_PIN: ReadonlySet<string> = new Set([
  "remember_note",
  "review_entity_note",
  "remember_about_entity",
  "forget_note",
  "learn_product_alias",
  "record_routine",
]);

// ─── O que o dono lê ────────────────────────────────────────────────────────────────────────────────────────────────

/**
 * O motivo: vai para risk_reason da pendência, trava a autonomia (a mesma regra do S1: com motivo, a ação não roda
 * sozinha nem com a chave ai_autonomy_<nome> = 'auto') e fecha o cartão de risco alto, depois de "🔒 No WhatsApp, pede
 * PIN: " (linhaDoPin, em agent.ts).
 */
export const MOTIVO_DO_TEXTO_DE_FORA = "este turno leu texto de fora (conversa, e-mail ou mensagem de fornecedor)";

/** A última linha do cartão de risco médio (cadastro, contato, preço). O PIN não entra: aqui basta o "sim". */
export const LINHA_DO_SIM_DEPOIS_DE_TEXTO_DE_FORA = "Este turno leu texto de fora (conversa, e-mail ou mensagem de fornecedor): por isso pede *sim*.";

// ─── O turno leu? ───────────────────────────────────────────────────────────────────────────────────────────────────

/** O começo do pedido que o vigia faz ao assistente (textoDoAviso, em acompanhar.ts): traz mensagem de terceiro citada. */
export const MARCA_DO_VIGIA = "🤖";

const PREFIXO_DA_EXTRA = `${NOME_DA_FERRAMENTA_EXTRA}:`;
const PREFIXO_DE_DESCREVER = `${PREFIXO_DA_EXTRA}descrever:`;

/**
 * O nome que conta numa entrada de ai_jobs.metadata.ferramentas_usadas (o erp-mcp grava "ferramenta_extra:<nome>" quando
 * a chamada veio pela ferramenta_extra, e "ferramenta_extra:descrever:<nome>" quando ela só pediu a descrição).
 * null = só descreveu: nada rodou, nada foi lido.
 */
export function nomeDaFerramentaUsada(entrada: string): string | null {
  if (entrada.startsWith(PREFIXO_DE_DESCREVER)) return null;
  return entrada.startsWith(PREFIXO_DA_EXTRA) ? entrada.slice(PREFIXO_DA_EXTRA.length) : entrada;
}

/**
 * O turno leu texto de fora? Pela lista de ferramentas já usadas no turno (a do job, no Claude Max) e pelo texto do
 * pedido (o do vigia começa com 🤖).
 *
 *  · sem lista (nenhuma ferramenta usada ainda) = não leu;
 *  · "ferramenta_extra:ler_email" conta como ler_email; "ferramenta_extra:descrever:ler_email" não conta;
 *  · lista que não é lista, ou entrada que não é texto, não dá para conferir = leu (lado seguro).
 */
export function leuTextoDeFora(ferramentasUsadas: unknown, textoDoTurno?: unknown): boolean {
  if (typeof textoDoTurno === "string" && textoDoTurno.trimStart().startsWith(MARCA_DO_VIGIA)) return true;
  if (ferramentasUsadas === undefined || ferramentasUsadas === null) return false;
  if (!Array.isArray(ferramentasUsadas)) return true;
  return ferramentasUsadas.some((entrada) => {
    if (typeof entrada !== "string") return true;
    const nome = nomeDaFerramentaUsada(entrada);
    return nome !== null && LEITURAS_DE_TEXTO_DE_FORA.has(nome);
  });
}

/**
 * A RPC ai_job_registrar_ferramenta só acrescenta o nome enquanto o metadata do job, escrito em texto pelo banco, couber
 * em 18.000 bytes (20261003235000_assistente_max_painel.sql: "a lista é diagnóstico"). Passando disso a lista para de
 * crescer, calada, e uma leitura deixaria de aparecer.
 */
export const LIMITE_DO_METADATA_NA_RPC = 18_000;

/**
 * Acima deste tamanho (medido como o banco mede) a lista não é mais prova de nada: vale como "leu". A conta: cada nome
 * entra com até 84 bytes (80 do nome, as aspas, a vírgula e o espaço); enquanto o metadata está em 17.000 bytes ou
 * menos, todo nome anterior coube, e sobra folga para o que o banco escreve de outro jeito (número, escape). Em 90
 * dias o maior metadata de um turno teve 2.396 bytes (medido em 25/11/2026): na prática este teto não é alcançado.
 */
export const TETO_PARA_CONFIAR_NA_LISTA = 17_000;

const emBytes = (texto: string) => new TextEncoder().encode(texto).length;

/**
 * O tamanho, em bytes, de um valor como o Postgres escreve jsonb em texto: `{"a": 1, "b": ["x", "y"]}`, com um espaço
 * depois de cada ":" de chave e de cada "," (é esse texto que a RPC mede com octet_length).
 */
export function tamanhoComoOBancoMede(valor: unknown): number {
  if (valor === null || valor === undefined || typeof valor !== "object") return emBytes(JSON.stringify(valor ?? null) ?? "null");
  if (Array.isArray(valor)) {
    return 2 + valor.reduce((soma: number, item) => soma + tamanhoComoOBancoMede(item), 0) + 2 * Math.max(0, valor.length - 1);
  }
  const pares = Object.entries(valor as Record<string, unknown>).filter(([, v]) => v !== undefined);
  return 2 + pares.reduce((soma, [chave, v]) => soma + emBytes(JSON.stringify(chave)) + 2 + tamanhoComoOBancoMede(v), 0) + 2 * Math.max(0, pares.length - 1);
}

/**
 * A marca do turno no Claude Max, para o erp-mcp: a linha do job relida agora (`{ metadata }`), se a leitura falhou e o
 * texto do pedido. O que não dá para conferir vale como "leu": leitura que falhou, linha que sumiu, metadata que não é
 * objeto, metadata perto do limite em que a lista para de crescer. Nunca lança.
 */
export function leuTextoDeForaNoJob(job: { metadata?: unknown } | null | undefined, leituraFalhou: boolean, textoDoTurno?: unknown): boolean {
  try {
    if (leuTextoDeFora(null, textoDoTurno)) return true;
    if (leituraFalhou || !job) return true;
    const metadata = job.metadata;
    if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) return true;
    if (tamanhoComoOBancoMede(metadata) > TETO_PARA_CONFIAR_NA_LISTA) return true;
    return leuTextoDeFora((metadata as Record<string, unknown>).ferramentas_usadas);
  } catch {
    return true;
  }
}

// ─── A regra ────────────────────────────────────────────────────────────────────────────────────────────────────────

const NIVEL: Record<string, number> = { low: 0, medium: 1, high: 2 };

/**
 * O risco de uma chamada depois de o turno ter lido texto de fora. Só SOBE; nunca rebaixa. Sem leitura, ou com
 * ferramenta fora das duas listas, devolve o risco como veio e nenhum motivo.
 *
 *  · SOBEM_PARA_PIN (memória)                    → alto, com o motivo;
 *  · SOBEM_PARA_SIM (cadastro, contato, preço)   → no mínimo médio, com o motivo. A que já era média ou alta fica no
 *    nível dela e leva o motivo do mesmo jeito: é ele que impede a chave de autonomia de pular o cartão.
 *
 * O motivo é o que o executor grava em risk_reason e mostra no cartão (MOTIVO_DO_TEXTO_DE_FORA).
 */
export function riscoDepoisDeTextoDeFora(nome: string, risco: RiskLevel, leu: boolean): RiscoNoServidor {
  if (leu !== true) return { risco, motivo: null };
  const piso: RiskLevel | null = SOBEM_PARA_PIN.has(nome) ? "high" : SOBEM_PARA_SIM.has(nome) ? "medium" : null;
  if (piso === null) return { risco, motivo: null };
  const atual = NIVEL[risco];
  // Nível que não existe não dá para comparar: na dúvida, o mais alto.
  if (atual === undefined) return { risco: "high", motivo: MOTIVO_DO_TEXTO_DE_FORA };
  return { risco: NIVEL[piso] > atual ? piso : risco, motivo: MOTIVO_DO_TEXTO_DE_FORA };
}
