// Quem é a outra ponta de uma linha do extrato — fornecedor, favorecido ou cliente.
//
// Medido em 25/09/2026 na fila do Extrato: das 47 saídas, 3 chegavam com fornecedor e
// NENHUMA com favorecido; das 24 entradas, 1 com cliente — embora quase todas trouxessem
// CPF/CNPJ inteiro. Havia três motivos:
//   * favorecido e cliente só eram procurados pelo documento, e cliente por nome só se o
//     nome fosse idêntico em maiúsculas;
//   * o que o dono JÁ decidiu não era usado: a EQUIT pagou em nome do cliente Acrisio, a
//     TECHVODA em nome do Bruno — e a próxima entrada deles chegava sem cliente de novo;
//   * a identificação só rodava quando a proposta nascia. A MP Motorhomes foi cadastrada
//     depois, com o mesmo CNPJ, e seis entradas dela continuaram sem cliente.
//
// Aqui fica UM identificador para os dois lados, com a evidência escrita. A ordem é a da
// força da prova, e a trava do caso Coremma continua valendo: nome "parecido" nunca decide
// em silêncio — vira sugestão marcada para conferir.
//
// Leva 8 (22/10/2026, "siga pelo recomendado"): a ENTRADA nunca mais propõe "cadastrar cliente"
// com os dados de quem pagou — das 21 entradas que carregaram essa proposta, 9 foram aprovadas e
// quase todas eram de um cliente com OUTRO documento (cônjuge, empresa dele, marina). No lugar, a
// pergunta "de quem é este pagamento?" (deQuemE). Quem costuma pagar por um cliente fica guardado
// em pagadores_do_cliente com o SIM do dono e volta como SUGESTÃO com motivo (pagador_conhecido) —
// nunca como identificação que a aprovação usa sozinha (clienteExigeSim).
import { normalizeText } from "./matching.ts";

export type TipoDeEvidencia =
  | "documento"        // CPF/CNPJ igual ao do cadastro
  | "conta_bancaria"   // banco, agência e conta iguais aos do favorecido
  | "historico"        // o mesmo documento já foi lançado para este cadastro
  | "nome_identico"    // nome igual, sem acento, caixa e sufixo societário
  | "nome_cortado"     // o nome do extrato é o do cadastro cortado pelo banco (~30 letras)
  | "nome_parecido"    // NÃO É MAIS PRODUZIDO (decisão do dono, 26/09/2026); fica para ler linhas antigas
  | "regra"            // uma regra sua aponta o cadastro
  | "vinculo"          // é o dono da conta/OS que a linha paga
  | "pagador_conhecido"; // quem pagou já foi guardado pelo dono como pagador DESTE cliente (só dele)

export const ROTULO_DA_EVIDENCIA: Record<TipoDeEvidencia, string> = {
  documento: "CPF/CNPJ",
  conta_bancaria: "conta bancária",
  historico: "lançamentos anteriores",
  nome_identico: "nome idêntico",
  nome_cortado: "nome cortado pelo banco — confira",
  nome_parecido: "nome parecido — confira",
  regra: "regra sua",
  vinculo: "o que ela paga",
  pagador_conhecido: "pagador conhecido — confira",
};

/**
 * O cliente sugerido por esta prova só vale com o SIM de alguém ("Sim, é do X" na tela, ou o cliente escolhido):
 * a aprovação nunca o usa sozinha. Fonte única para o servidor (finance-review aprovar), a tela e o assistente.
 *   - vinculo: o motor antigo tirava o cliente do que a linha paga (decisão do dono, 26/09/2026);
 *   - pagador_conhecido: quem pagou é um terceiro guardado para este cliente — sugere, não decide;
 *   - historico: todo histórico de ENTRADA que chega aqui é de terceiro (o documento do próprio cliente é pego antes,
 *     no passo 1; o cliente sem documento que paga com o próprio CPF e o mesmo nome sai como nome_identico) — um
 *     pagamento de terceiro uma vez não decide o próximo.
 */
export function clienteExigeSim(por: string | null | undefined): boolean {
  return por === "vinculo" || por === "pagador_conhecido" || por === "historico";
}

/**
 * O que a ANOTAÇÃO do dono disse sobre a linha ("o Pix de 1.500 é da TSD", "é da OS-60") — a anotação aplicada
 * (anotacoes_do_extrato, pelo id em evidencia.anotacao.id). Chega de dois jeitos:
 *   - LIDA da anotação aplicada (servidor ao aprovar, assistente ao listar): {cliente_id, os_id}, com cliente_id sempre
 *     presente (string ou null). null no lugar do objeto = lida e não vale (cancelada, trocada) ou leitura que falhou;
 *   - só a MARCA da evidência (a tela, que não lê a anotação): evidencia.anotacao = {id, os_id} — o _aplicar_anotacao
 *     não grava o cliente; cliente_id fica AUSENTE (undefined). Quando a anotação é desfeita (comprovante desligado,
 *     migrations 20261011302000/20261011303000), a marca sai da evidência e o sugerido fica.
 */
export interface AnotacaoDoDono {
  /** O id da anotação aplicada — só na marca da evidência. */
  id?: string | null;
  /** O cliente que a anotação disse. undefined = não lida (só a marca); null = lida, sem cliente. */
  cliente_id?: string | null;
  os_id?: string | null;
}

/** O cliente que a prova do motor (evidencia.cliente) aponta, como fica gravado na proposta. */
export interface ClienteDaEvidencia {
  id?: string | null;
  nome?: string | null;
  por?: string | null;
}

/**
 * A anotação do dono DISSE o cliente sugerido? É instrução dele — vale como o SIM (revisão de 23/10/2026).
 *   - com cliente_id: só se for o próprio sugerido (o _aplicar_anotacao põe o cliente anotado no sugerido);
 *   - sem cliente_id e com OS: numa entrada, o cliente é o da OS anotada (service_orders.client_id é obrigatório; o
 *     _aplicar_anotacao o põe no sugerido e a aprovação usa o cliente da OS);
 *   - só a MARCA da evidência (não lida: cliente_id ausente) e o sugerido NÃO é o da prova do motor: só o
 *     _aplicar_anotacao põe na fila um cliente que não é o da prova, e a marca sai quando a anotação é desfeita — é a
 *     anotação em vigor que disse o sugerido (a tela não lê a anotação; o servidor sempre lê);
 *   - só categoria/descrição (lida, sem cliente nem OS), ou a marca sobre o MESMO cliente da prova: não disse quem é.
 */
function anotacaoDizOCliente(sugeridoId: string, anotacao: AnotacaoDoDono | null | undefined, provaDeOutro: boolean): boolean {
  if (!anotacao) return false;
  if (anotacao.cliente_id) return String(anotacao.cliente_id) === sugeridoId;
  if (anotacao.os_id) return true;
  return anotacao.cliente_id === undefined && !!anotacao.id && provaDeOutro;
}

/**
 * Como fica o cliente SUGERIDO de uma ENTRADA da fila na aprovação (revisão de 23/10/2026, 4ª rodada). Fonte única para
 * o servidor (aprovar), o assistente e a tela:
 *   - "sem_sugestao": não há cliente sugerido;
 *   - "vale": a aprovação usa o sugerido sem perguntar — a prova do motor é DESTE cliente e não pede o SIM (documento,
 *     nome idêntico, regra), ou a anotação do dono disse este cliente (ela É o SIM);
 *   - "pede_sim": a prova do motor é DESTE cliente e pede o SIM (clienteExigeSim: vínculo, pagador conhecido, histórico
 *     de terceiro) e a anotação não o disse — "Sim, é do X" sobre o cliente da prova;
 *   - "escolher": o sugerido NÃO é o da prova (prova de outro cliente, ou nenhuma) e nenhuma anotação em vigor o disse.
 *     Fora do motor, só a anotação põe na fila um cliente que não é o da prova; se ela foi desfeita (comprovante
 *     desligado: a marca sai, o sugerido fica) ou não deu para lê-la, ninguém resolveu de quem é: a aprovação não usa
 *     NENHUM cliente sem a escolha do dono — nem o sugerido, nem o da prova antiga ("Escolha o cliente…", nunca
 *     "Sim, é do <prova>").
 * `anotacao`: a LIDA (servidor, assistente) ou a marca da evidência (tela) — ver AnotacaoDoDono.
 */
export type SituacaoDoClienteSugerido = "sem_sugestao" | "vale" | "pede_sim" | "escolher";

export function situacaoDoClienteSugerido(
  sugeridoId: string | null | undefined,
  evidenciaCliente: ClienteDaEvidencia | null | undefined,
  anotacao?: AnotacaoDoDono | null,
): SituacaoDoClienteSugerido {
  if (!sugeridoId) return "sem_sugestao";
  const sugerido = String(sugeridoId);
  const daProva = !!evidenciaCliente?.id && String(evidenciaCliente.id) === sugerido;
  if (anotacaoDizOCliente(sugerido, anotacao, !daProva)) return "vale";
  if (!daProva) return "escolher";
  return clienteExigeSim(evidenciaCliente?.por) ? "pede_sim" : "vale";
}

/**
 * O cliente SUGERIDO pede o SIM ao cliente da PROVA ("Sim, é do X")? true só na situação "pede_sim"
 * (situacaoDoClienteSugerido): a prova do motor é deste cliente, pede o SIM, e a anotação do dono não o disse.
 * ATENÇÃO: false NÃO quer dizer que a aprovação usa o sugerido — na situação "escolher" (sugerido que não é o da prova,
 * sem anotação em vigor que o diga) ela não usa nenhum; quem decide se o sugerido vale é situacaoDoClienteSugerido.
 * Sem a anotação lida (só a marca da evidência), a OS anotada já conta; o cliente anotado igual ao da prova continua
 * pedindo o SIM — errar para o lado da pergunta custa um "sim".
 */
export function clienteDaPropostaExigeSim(
  sugeridoId: string | null | undefined,
  evidenciaCliente: ClienteDaEvidencia | null | undefined,
  anotacao?: AnotacaoDoDono | null,
): boolean {
  return situacaoDoClienteSugerido(sugeridoId, evidenciaCliente, anotacao) === "pede_sim";
}

/** Quem é o pagador para o cliente (pagadores_do_cliente.relacao). */
export type RelacaoDoPagador = "empresa_do_cliente" | "conjuge" | "parente" | "marina" | "seguradora" | "outro";

export const RELACOES_DO_PAGADOR: RelacaoDoPagador[] = ["empresa_do_cliente", "conjuge", "parente", "marina", "seguradora", "outro"];

/** Rótulo curto para seletor e lista ("Cônjuge"). */
export const ROTULO_DA_RELACAO: Record<RelacaoDoPagador, string> = {
  empresa_do_cliente: "Empresa do cliente",
  conjuge: "Cônjuge",
  parente: "Parente",
  marina: "Marina",
  seguradora: "Seguradora",
  outro: "Outro",
};

/** "Pago pela empresa de Acrisio", "Pago pelo cônjuge de Maria" — o começo do motivo da sugestão. */
export function frasePagoPor(relacao: string | null | undefined, cliente: string): string {
  switch (relacao) {
    case "empresa_do_cliente": return `Pago pela empresa de ${cliente}`;
    case "conjuge": return `Pago pelo cônjuge de ${cliente}`;
    case "parente": return `Pago por um parente de ${cliente}`;
    case "marina": return `Pago pela marina de ${cliente}`;
    case "seguradora": return `Pago pela seguradora de ${cliente}`;
    default: return `Pago por quem costuma pagar por ${cliente}`;
  }
}

/**
 * O documento como aparece fora do financeiro (recibo, assistente, lista): CNPJ inteiro e formatado; CPF MASCARADO
 * (***.456.789-**) — CPF de terceiro é dado pessoal (decisão do dono, 22/10/2026; o mesmo formato do cartão do caixa).
 */
export function documentoMascarado(doc: string | null | undefined): string | null {
  const d = documentoNormalizado(doc);
  if (d.length === 14) return d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
  if (d.length === 11) return d.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "***.$2.$3-**");
  return null;
}

/**
 * CPF dentro de um NOME ou texto (leva 8, LGPD: CPF de terceiro só mascarado no recibo e no assistente) — o nome que o
 * banco escreve com o CPF ("12345678901-MARIA…"), o MEI ("JOAO SILVA 12345678901"), o motivo da conciliação ("Quem
 * enviou (CPF/CNPJ 123.456.789-01)"): sai como documentoMascarado, ***.456.789-**. Só 11 dígitos SOLTOS (ou no formato
 * do CPF): o CNPJ (14 dígitos, com ou sem pontuação) fica inteiro, como em documentoMascarado.
 * Sem lookbehind de propósito: este arquivo também roda na tela, e Safari antigo (iOS < 16.4) recusa o módulo inteiro
 * com ele. O caractere antes do CPF é capturado e devolvido (extrato-lgpd_test confere).
 * O assistente usa pelo nome antigo, mascararCpfNoTexto (financeiro-comum.ts reexporta esta).
 */
export function nomeSemCpf<T extends string | null | undefined>(nome: T): T {
  if (typeof nome !== "string") return nome;
  return nome.replace(/(^|\D)(\d{3})\.?(\d{3})\.?(\d{3})-?(\d{2})(?!\d)/g, "$1***.$3.$4-**") as T;
}

export type TipoDeCadastro = "fornecedor" | "favorecido" | "cliente";

export interface Reconhecimento {
  id: string;
  nome: string;
  por: TipoDeEvidencia;
  /** Frase para a linha: "CNPJ confere com MP MOTOR HOMES". */
  detalhe: string;
  /** Só em `pagador_conhecido`: quem o pagador é para o cliente. */
  relacao?: RelacaoDoPagador | string;
}

/** Um cliente para quem este pagador já foi guardado — candidato da pergunta "de quem é?". */
export interface CandidatoDoPagamento {
  id: string;
  nome: string;
  relacao: RelacaoDoPagador | string;
}

/** O "não" do dono para este documento × cliente (pagadores_do_cliente recusado ou pausado). */
export type SituacaoDoVeto = "recusado" | "pausado";

/** Um cliente que o motor sugeriria, mas para quem o dono recusou ou pausou este documento como pagador. */
export interface ClienteVetado {
  id: string;
  nome: string;
  situacao: SituacaoDoVeto;
}

export interface Identificacao {
  fornecedor: Reconhecimento | null;
  favorecido: Reconhecimento | null;
  cliente: Reconhecimento | null;
  /** O documento pertence a um cadastro de OUTRO tipo (ex.: CPF de cliente numa saída). */
  outroCadastro: { tipo: TipoDeCadastro; id: string; nome: string } | null;
  /**
   * Nada reconheceu e há o que cadastrar — já com o que o extrato traz. Só nas SAÍDAS: a entrada nunca propõe
   * cadastrar cliente com os dados de quem pagou (leva 8, 22/10/2026); ela pergunta (deQuemE). Linhas antigas da
   * fila ainda podem trazer `cadastrar` de cliente até a varredura refazê-las (MOTOR_DA_FILA 3).
   */
  cadastrar: { tipo: TipoDeCadastro; documento: string | null; nome: string | null } | null;
  /**
   * ENTRADA sem cliente reconhecido: "de quem é este pagamento?". `candidatos` são os clientes para quem este
   * documento já foi guardado como pagador (marina, seguradora: dois ou mais); vazio = ninguém ainda. O documento e
   * o nome são os do extrato. `vetados` (só quando há): os clientes que o histórico ou o nome sugeririam, mas para quem
   * o dono recusou ou pausou este documento como pagador — ficam de fora da sugestão e dos candidatos.
   */
  deQuemE: {
    documento: string | null;
    nome: string | null;
    candidatos: CandidatoDoPagamento[];
    vetados?: ClienteVetado[];
  } | null;
  /** Nome para mostrar quando o banco não mandou nome (sai do cadastro do documento). */
  nomeConhecido: string | null;
}

/** A pergunta "de quem é este pagamento?" como o motor a grava (evidencia.deQuemE). */
export type PerguntaDeQuemE = NonNullable<Identificacao["deQuemE"]>;

/**
 * Relação do candidato que só o NOME IDÊNTICO aponta quando a leitura dos pagadores falhou (pagadoresIndisponiveis):
 * sem saber o que o dono vetou, o nome idêntico não identifica sozinho — vira candidato da pergunta.
 */
export const RELACAO_DO_NOME_IDENTICO = "nome idêntico";

/** O que perguntaDeQuemEValida lê de uma proposta da fila. */
export interface PropostaComPergunta {
  suggested_client_id?: string | null;
  evidencia?: {
    deQuemE?: Partial<PerguntaDeQuemE> | null;
    cadastrar?: { tipo?: string | null; documento?: string | null; nome?: string | null } | null;
    cliente?: ClienteDaEvidencia | null;
  } | null;
}

/**
 * A pergunta "de quem é este pagamento?" que AINDA vale nesta proposta da fila — ou null (revisão de 23/10/2026).
 * As funções do banco que resolvem o cliente fora do motor — a anotação do dono (_aplicar_anotacao), o "É cliente novo"
 * (cadastro pela linha) — só tiram o `cadastrar` da evidência: o deQuemE sobra. O motor nunca grava cliente E pergunta
 * juntos (com pergunta, suggested_client_id é nulo e evidencia.cliente não existe); então, se a proposta já tem cliente
 * sugerido ou cliente na prova, a pergunta é sobra e não vale.
 * A linha antiga (motor 2) com `cadastrar` de CLIENTE vira a mesma pergunta, sem candidatos — nunca a proposta de
 * cadastrar cliente com os dados de quem pagou. Fonte única para a tela, o assistente e o servidor.
 */
export function perguntaDeQuemEValida(p: PropostaComPergunta | null | undefined): PerguntaDeQuemE | null {
  const ev = p?.evidencia;
  const q = ev?.deQuemE ?? (ev?.cadastrar?.tipo === "cliente" ? ev.cadastrar : null);
  if (!q) return null;
  if (p?.suggested_client_id || ev?.cliente?.id) return null;
  const vetados = (q as Partial<PerguntaDeQuemE>).vetados;
  return {
    documento: q.documento ?? null,
    nome: q.nome ?? null,
    candidatos: Array.isArray((q as Partial<PerguntaDeQuemE>).candidatos) ? (q as PerguntaDeQuemE).candidatos : [],
    ...(Array.isArray(vetados) && vetados.length > 0 ? { vetados } : {}),
  };
}

export interface TxParaIdentificar {
  transaction_type: "credit" | "debit";
  description?: string | null;
  counterparty_name?: string | null;
  counterparty_document?: string | null;
  counterparty_branch?: string | null;
  counterparty_account?: string | null;
}

export interface CadastroParaIdentificar {
  fornecedores: Array<{ id: string; name: string; trade_name?: string | null; cnpj_cpf?: string | null }>;
  favorecidos: Array<{ id: string; name: string; document?: string | null; bank_branch?: string | null; bank_account?: string | null }>;
  clientes: Array<{ id: string; name: string; cpf_cnpj?: string | null }>;
  /** Uma linha por lançamento já feito a partir do extrato (sem cadastro também conta). */
  historico: Array<{
    documento: string | null;
    lado: "saida" | "entrada";
    supplier_id?: string | null; payee_id?: string | null; client_id?: string | null;
  }>;
  /**
   * Pagadores CONFIRMADOS pelo dono (pagadores_do_cliente, situacao 'confirmado'), só de cliente ativo — quem
   * chama filtra. Pagador de cliente que não está em `clientes` é ignorado. Ausente = nenhum.
   */
  pagadores?: Array<{ documento: string; client_id: string; relacao: RelacaoDoPagador | string; confirmado_em?: string | null }>;
  /**
   * O "não" do dono (pagadores_do_cliente recusado ou pausado): este documento NUNCA sugere este cliente — nem como
   * pagador conhecido, nem pelo histórico, nem pelo nome idêntico. CPF inteiro; CNPJ pela raiz. Ausente = nenhum.
   */
  vetados?: Array<{ documento: string; client_id: string; situacao: SituacaoDoVeto | string }>;
  /**
   * A leitura de pagadores_do_cliente falhou: não se sabe o que o dono guardou nem o que vetou. O histórico continua
   * sugerindo, sempre pedindo o SIM (o atalho "é o próprio cliente sem documento" fica desligado), e o nome idêntico
   * vira a pergunta "de quem é?", com o cliente como candidato (RELACAO_DO_NOME_IDENTICO).
   */
  pagadoresIndisponiveis?: boolean;
}

interface Entrada { id: string; nome: string; limpo: string; tokens: string[]; documento?: string }

interface HistoricoDoDocumento {
  saida: { total: number; fornecedor: Map<string, number>; favorecido: Map<string, number> };
  entrada: { total: number; cliente: Map<string, number> };
}

/** Um pagador guardado para um cliente, já com o cadastro do cliente. */
export interface PagadorIndexado {
  cliente: { id: string; nome: string };
  relacao: RelacaoDoPagador | string;
  /** Quando o dono confirmou (ISO), para "guardado por você em dd/mm". */
  em: string | null;
}

export interface IndiceDeContrapartes {
  fornecedorPorDoc: Map<string, Entrada>;
  favorecidoPorDoc: Map<string, Entrada>;
  clientePorDoc: Map<string, Entrada>;
  favorecidoPorConta: Map<string, Entrada>;
  fornecedores: Entrada[];
  favorecidos: Entrada[];
  clientes: Entrada[];
  /** documento → quem ele já foi, por sentido, com contagem e total de lançamentos. */
  historico: Map<string, HistoricoDoDocumento>;
  /**
   * Pagadores confirmados: pelo documento exato (CPF) e pela raiz do CNPJ (`raiz:12345678` — matriz e filiais são a
   * mesma empresa), um por cliente.
   */
  pagadorPorDoc: Map<string, PagadorIndexado[]>;
  /** O "não" do dono: chave do documento (CPF; CNPJ pela raiz) → cliente → recusado ou pausado. */
  vetoPorDoc: Map<string, Map<string, SituacaoDoVeto>>;
  /** A leitura dos pagadores falhou (CadastroParaIdentificar.pagadoresIndisponiveis). */
  pagadoresIndisponiveis: boolean;
  porId: { fornecedor: Map<string, Entrada>; favorecido: Map<string, Entrada>; cliente: Map<string, Entrada> };
}

/** Chave do pagador no índice: CPF inteiro; CNPJ pela raiz. */
function chaveDoPagador(doc: string): string {
  return doc.length === 14 ? `raiz:${doc.slice(0, 8)}` : doc;
}

/**
 * O dono recusou ou pausou este documento como pagador deste cliente? Devolve a situação (o veto) ou null. CNPJ pela
 * raiz, como o pagador confirmado.
 */
export function vetoDoPagador(
  idx: IndiceDeContrapartes, documento: string | null | undefined, clienteId: string | null | undefined,
): SituacaoDoVeto | null {
  const d = documentoNormalizado(documento);
  if (!clienteId || (d.length !== 11 && d.length !== 14)) return null;
  return idx.vetoPorDoc.get(chaveDoPagador(d))?.get(clienteId) ?? null;
}

/**
 * Os clientes (um por cliente) para quem este documento foi guardado como pagador CONFIRMADO — menos os vetados (o
 * "não" do dono vence: recusado ou pausado não sugere, nem como candidato).
 */
export function pagadoresDoDocumento(idx: IndiceDeContrapartes, documento: string | null | undefined): PagadorIndexado[] {
  const d = documentoNormalizado(documento);
  if (d.length !== 11 && d.length !== 14) return [];
  const vetados = idx.vetoPorDoc.get(chaveDoPagador(d));
  const lista = idx.pagadorPorDoc.get(chaveDoPagador(d)) ?? [];
  return vetados ? lista.filter((p) => !vetados.has(p.cliente.id)) : lista;
}

/** dd/mm de um carimbo ISO, no fuso de Brasília. */
function ddmm(iso: string | null | undefined): string | null {
  const t = Date.parse(String(iso ?? ""));
  if (!Number.isFinite(t)) return null;
  const br = new Date(t - 3 * 3600_000).toISOString();
  return `${br.slice(8, 10)}/${br.slice(5, 7)}`;
}

const digitos = (s: string | null | undefined) => String(s ?? "").replace(/\D/g, "");

/**
 * CPF/CNPJ só com dígitos, com o zero à esquerda que a planilha comeu: CNPJ gravado com 13
 * dígitos ("2559947000324") e CPF com 10 são o mesmo documento com o zero perdido. Sem isto
 * o MESMO documento "contradizia" a si mesmo e o cadastro certo deixava de ser reconhecido.
 */
export function documentoNormalizado(s: string | null | undefined): string {
  const d = digitos(s);
  if (d.length === 13) return d.padStart(14, "0");
  if (d.length === 10) return d.padStart(11, "0");
  return d;
}

/**
 * O extrato e o cadastro têm documento, e eles NÃO são da mesma pessoa ou empresa: o nome
 * igual não vale. CPF contra CNPJ nunca é o mesmo; CNPJ contra CNPJ compara a raiz (matriz e
 * filiais são a mesma empresa); CPF contra CPF, o número inteiro. Sem documento de um dos
 * lados, não há o que contradizer.
 */
export function documentoContradiz(doExtrato: string | null | undefined, doCadastro: string | null | undefined): boolean {
  const a = documentoNormalizado(doExtrato);
  const b = documentoNormalizado(doCadastro);
  if (a.length < 11 || b.length < 11) return false;
  if (a.length !== b.length) return true;
  return a.length === 14 ? a.slice(0, 8) !== b.slice(0, 8) : a !== b;
}

/** Palavras que não identificam ninguém. */
const VAZIAS = new Set(["DE", "DA", "DO", "DAS", "DOS", "E", "LTDA", "ME", "EPP", "EIRELI", "SA", "S", "A", "CIA", "COMERCIO", "SERVICOS"]);

/** Nome sem acento, caixa, pontuação e sufixo societário. */
export function nomeLimpo(s: string | null | undefined): string {
  // "(Lisiane)" em "Thaline Soares Mendonça (Lisiane)" é anotação de quem cadastrou, não nome.
  return normalizeText(String(s ?? "").replace(/\([^)]*\)/g, " "))
    .replace(/\b(LTDA|ME|EPP|EIRELI|SA|S A|CIA)\b/g, " ")
    // "65.010.587 CRISLAINE…" — MEI traz a raiz do CNPJ no começo do nome. Só esse formato:
    // apagar qualquer número tornava "idênticos" nomes diferentes ("2 IRMAOS" e "IRMAOS").
    .replace(/^\d{2} ?\d{3} ?\d{3}(?: ?\d{4} ?\d{2})? +/, "")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * O nome que está DENTRO da descrição, quando o banco não manda o nome à parte.
 * "Pix enviado para JOSE CARLOS ABEL" → "JOSE CARLOS ABEL". Sem isto metade das linhas do
 * Nubank chegava sem nome e não podia ser reconhecida nem cadastrada.
 */
export function nomeDaDescricao(descricao: string | null | undefined): string | null {
  const m = String(descricao ?? "").trim().match(
    /^(?:pix|ted|doc|transf(?:er[eê]ncia)?|transfer[eê]ncia pix)\s+(?:enviad[oa]|recebid[oa]|realizad[oa])\s+(?:para|de|por)\s+(.{3,})$/i,
  );
  return m ? m[1].trim() : null;
}

/**
 * O nome dentro da descrição em qualquer dos dois formatos: "Pix enviado para NOME" (nomeDaDescricao) ou
 * "MEIO|NOME" — o Nubank, pela Pluggy, põe o nome de quem recebeu depois da barra: "Transferência enviada|NOME"
 * e "Compra no débito|LOJA" (esta sem o nome da contraparte à parte; 4 linhas em 18–19/08/2026, revisão de
 * 22/10/2026). Antes da barra, só o meio de pagamento: "Valor adicionado na conta por cartão de crédito | Valor
 * adicionado para PIX no Crédito" não tem nome nenhum depois dela.
 * Usado por quem compara o extrato com ele mesmo (vigilante, aprendiz de regras); a identificação continua
 * com nomeDaDescricao.
 */
const MEIO_ANTES_DA_BARRA =
  /^(?:(?:pix|ted|doc|transf(?:er[eê]ncia)?)\s+(?:enviad[oa]|recebid[oa]|realizad[oa])|compra\s+(?:no\s+)?(?:d[eé]bito|cr[eé]dito))\s*\|\s*(.{3,})$/i;

export function nomeDentroDaDescricao(descricao: string | null | undefined): string | null {
  const d = String(descricao ?? "").trim();
  return nomeDaDescricao(d) ?? (d.match(MEIO_ANTES_DA_BARRA)?.[1]?.trim() || null);
}

function palavras(limpo: string): string[] {
  return limpo.split(" ").filter((p) => p.length >= 3 && !VAZIAS.has(p));
}

function entrada(id: string, nome: string, documento?: string | null): Entrada {
  const limpo = nomeLimpo(nome);
  const d = documentoNormalizado(documento);
  return { id, nome, limpo, tokens: palavras(limpo), documento: d.length >= 11 ? d : undefined };
}

/** Chave da conta: agência + conta só com dígitos. Conta curta demais não identifica. */
function chaveDaConta(agencia: string | null | undefined, conta: string | null | undefined): string | null {
  const c = digitos(conta);
  if (c.length < 4) return null;
  // Zero à esquerda some: um banco manda "0001", outro manda "1" para a mesma agência.
  return `${digitos(agencia).replace(/^0+/, "")}|${c.replace(/^0+/, "")}`;
}

export function indexarContrapartes(c: CadastroParaIdentificar): IndiceDeContrapartes {
  const idx: IndiceDeContrapartes = {
    fornecedorPorDoc: new Map(), favorecidoPorDoc: new Map(), clientePorDoc: new Map(),
    favorecidoPorConta: new Map(),
    fornecedores: [], favorecidos: [], clientes: [],
    historico: new Map(),
    pagadorPorDoc: new Map(),
    vetoPorDoc: new Map(),
    pagadoresIndisponiveis: c.pagadoresIndisponiveis === true,
    porId: { fornecedor: new Map(), favorecido: new Map(), cliente: new Map() },
  };
  for (const f of c.fornecedores) {
    const e = entrada(f.id, f.name, f.cnpj_cpf);
    idx.fornecedores.push(e);
    if (f.trade_name) idx.fornecedores.push({ ...entrada(f.id, f.trade_name, f.cnpj_cpf), nome: f.name });
    idx.porId.fornecedor.set(f.id, e);
    const d = documentoNormalizado(f.cnpj_cpf);
    // Primeiro cadastro vence: dois cadastros com o mesmo documento é erro de cadastro, e
    // trocar qual deles ganha mudaria a identificação sem aviso.
    if (d.length >= 11 && !idx.fornecedorPorDoc.has(d)) idx.fornecedorPorDoc.set(d, e);
  }
  for (const f of c.favorecidos) {
    const e = entrada(f.id, f.name, f.document);
    idx.favorecidos.push(e);
    idx.porId.favorecido.set(f.id, e);
    const d = documentoNormalizado(f.document);
    if (d.length >= 11 && !idx.favorecidoPorDoc.has(d)) idx.favorecidoPorDoc.set(d, e);
    const k = chaveDaConta(f.bank_branch, f.bank_account);
    if (k && !idx.favorecidoPorConta.has(k)) idx.favorecidoPorConta.set(k, e);
  }
  for (const cl of c.clientes) {
    const e = entrada(cl.id, cl.name, cl.cpf_cnpj);
    idx.clientes.push(e);
    idx.porId.cliente.set(cl.id, e);
    const d = documentoNormalizado(cl.cpf_cnpj);
    if (d.length >= 11 && !idx.clientePorDoc.has(d)) idx.clientePorDoc.set(d, e);
  }
  const soma = (m: Map<string, number>, id: string) => m.set(id, (m.get(id) ?? 0) + 1);
  for (const h of c.historico) {
    const d = documentoNormalizado(h.documento);
    if (d.length < 11) continue;
    const reg: HistoricoDoDocumento = idx.historico.get(d) ?? {
      saida: { total: 0, fornecedor: new Map(), favorecido: new Map() },
      entrada: { total: 0, cliente: new Map() },
    };
    if (h.lado === "saida") {
      reg.saida.total += 1;
      if (h.supplier_id) soma(reg.saida.fornecedor, h.supplier_id);
      if (h.payee_id) soma(reg.saida.favorecido, h.payee_id);
    } else {
      reg.entrada.total += 1;
      if (h.client_id) soma(reg.entrada.cliente, h.client_id);
    }
    idx.historico.set(d, reg);
  }
  for (const p of c.pagadores ?? []) {
    const d = documentoNormalizado(p.documento);
    const cliente = idx.porId.cliente.get(p.client_id);
    // Cliente fora do cadastro lido (inativo, apagado) não é sugerido; documento torto não entra.
    if (!cliente || (d.length !== 11 && d.length !== 14)) continue;
    const k = chaveDoPagador(d);
    const lista = idx.pagadorPorDoc.get(k) ?? [];
    // Matriz e filial guardadas para o mesmo cliente contam uma vez só.
    if (!lista.some((x) => x.cliente.id === cliente.id)) {
      lista.push({ cliente: { id: cliente.id, nome: cliente.nome }, relacao: p.relacao, em: p.confirmado_em ?? null });
    }
    idx.pagadorPorDoc.set(k, lista);
  }
  // O "não" do dono vale para qualquer cliente lido (o veto só tira sugestão). Recusado vence pausado na mesma chave.
  for (const v of c.vetados ?? []) {
    const d = documentoNormalizado(v.documento);
    if (!v.client_id || (d.length !== 11 && d.length !== 14)) continue;
    if (v.situacao !== "recusado" && v.situacao !== "pausado") continue;
    const k = chaveDoPagador(d);
    const m = idx.vetoPorDoc.get(k) ?? new Map<string, SituacaoDoVeto>();
    if (m.get(String(v.client_id)) !== "recusado") m.set(String(v.client_id), v.situacao as SituacaoDoVeto);
    idx.vetoPorDoc.set(k, m);
  }
  return idx;
}

/**
 * Histórico só decide quando é UNÂNIME: TODO lançamento deste documento, neste sentido, foi
 * para o mesmo cadastro — contando os que ficaram sem cadastro.
 *
 * Contar só os preenchidos propagaria erro antigo: o CPF do Felipe foi lançado duas vezes
 * com o fornecedor "VIA S.A." (casamento errado de nome, de antes da trava) e duas sem
 * ninguém. Metade não é prática da casa; é acidente.
 */
function unanime(m: Map<string, number>, total: number): { id: string; vezes: number } | null {
  if (m.size !== 1 || total === 0) return null;
  const [[id, vezes]] = [...m.entries()];
  return vezes === total ? { id, vezes } : null;
}

/**
 * Nome idêntico, e só um cadastro com esse nome — se dois têm, escolher seria sorteio. Nome
 * igual com documento diferente é homônimo, não a mesma pessoa.
 */
function porNomeIdentico(lista: Entrada[], limpo: string, doc: string): Entrada | null {
  if (!limpo) return null;
  // Por EMPRESA: matriz e filial (mesma raiz de CNPJ) são uma só; entre elas, sempre a de
  // menor documento. Duas empresas com o mesmo nome é empate.
  const empresa = (e: Entrada) => (e.documento?.length === 14 ? `raiz:${e.documento.slice(0, 8)}` : `id:${e.id}`);
  const porEmpresa = new Map<string, Entrada>();
  for (const e of lista) {
    if (e.limpo !== limpo || documentoContradiz(doc, e.documento)) continue;
    const k = empresa(e);
    const atual = porEmpresa.get(k);
    if (!atual || (e.documento ?? "").localeCompare(atual.documento ?? "") < 0) porEmpresa.set(k, e);
  }
  return porEmpresa.size === 1 ? [...porEmpresa.values()][0] : null;
}

function reconhecer(e: Entrada, por: TipoDeEvidencia, detalhe: string): Reconhecimento {
  return { id: e.id, nome: e.nome, por, detalhe };
}

export function identificarContraparte(tx: TxParaIdentificar, idx: IndiceDeContrapartes): Identificacao {
  const doc = documentoNormalizado(tx.counterparty_document);
  const temDoc = doc.length >= 11;
  const tipoDoc = doc.length === 14 ? "CNPJ" : "CPF";
  const nomeDoExtrato = (tx.counterparty_name ?? "").trim() || nomeDaDescricao(tx.description);
  const limpo = nomeLimpo(nomeDoExtrato);
  const historico = temDoc ? idx.historico.get(doc) : undefined;
  const saida = tx.transaction_type === "debit";

  const r: Identificacao = {
    fornecedor: null, favorecido: null, cliente: null,
    outroCadastro: null, cadastrar: null, deQuemE: null, nomeConhecido: null,
  };

  // O nome que o banco não mandou, pelo cadastro do documento (qualquer tipo).
  if (temDoc && !nomeDoExtrato) {
    r.nomeConhecido = (idx.favorecidoPorDoc.get(doc) ?? idx.fornecedorPorDoc.get(doc) ?? idx.clientePorDoc.get(doc))?.nome ?? null;
  }

  if (saida) {
    // 1. Documento.
    if (temDoc) {
      const fav = idx.favorecidoPorDoc.get(doc);
      if (fav) r.favorecido = reconhecer(fav, "documento", `${tipoDoc} confere com o favorecido ${fav.nome}`);
      const forn = idx.fornecedorPorDoc.get(doc);
      if (forn) r.fornecedor = reconhecer(forn, "documento", `${tipoDoc} confere com o fornecedor ${forn.nome}`);
    }
    // 2. Conta bancária do favorecido.
    if (!r.favorecido) {
      const k = chaveDaConta(tx.counterparty_branch, tx.counterparty_account);
      const fav = k ? idx.favorecidoPorConta.get(k) : undefined;
      // Mesma agência e conta, mas CPF de outra pessoa: é conta de outro banco com o mesmo número.
      if (fav && !documentoContradiz(doc, fav.documento)) r.favorecido = reconhecer(fav, "conta_bancaria", `Conta bancária igual à do favorecido ${fav.nome}`);
    }
    // 3. O que já se lançou para este documento — só se sempre foi o mesmo, e só se o
    //    cadastro não tem documento de OUTRO tipo. Um Pix ao CPF do Ricardo foi lançado uma
    //    vez com o fornecedor "VIA S.A." (Casas Bahia, CNPJ): repetir isso seria propagar
    //    erro antigo com cara de prática da casa.
    if (!r.favorecido && !r.fornecedor && historico) {
      const fav = unanime(historico.saida.favorecido, historico.saida.total);
      const forn = unanime(historico.saida.fornecedor, historico.saida.total);
      const compativel = (e: Entrada | undefined) => !!e && !documentoContradiz(doc, e.documento);
      const e0 = fav ? idx.porId.favorecido.get(fav.id) : undefined;
      const f0 = forn ? idx.porId.fornecedor.get(forn.id) : undefined;
      const e = compativel(e0) ? e0 : undefined;
      const f = compativel(f0) ? f0 : undefined;
      if (e && fav) r.favorecido = reconhecer(e, "historico", `Este ${tipoDoc} já foi lançado ${fav.vezes}× para ${e.nome}`);
      else if (f && forn) r.fornecedor = reconhecer(f, "historico", `Este ${tipoDoc} já foi lançado ${forn.vezes}× para ${f.nome}`);
    }
    // 4. Nome idêntico. Documento de pessoa (CPF) procura favorecido antes de fornecedor.
    if (!r.favorecido && !r.fornecedor && limpo) {
      const fav = porNomeIdentico(idx.favorecidos, limpo, doc);
      const forn = fav ? null : porNomeIdentico(idx.fornecedores, limpo, doc);
      if (fav) r.favorecido = reconhecer(fav, "nome_identico", `Nome idêntico ao do favorecido ${fav.nome}`);
      else if (forn) r.fornecedor = reconhecer(forn, "nome_identico", `Nome idêntico ao do fornecedor ${forn.nome}`);
    }
    // Nome PARECIDO não identifica ninguém (decisão do dono, 26/09/2026: "o sistema nunca pode
    // sugerir ou lançar alguma transação com nomes diferentes"). Sem documento, conta, histórico
    // do mesmo documento ou nome igual, quem decide é a pessoa.
    if (!r.favorecido && !r.fornecedor) {
      const cli = temDoc ? idx.clientePorDoc.get(doc) : undefined;
      if (cli) r.outroCadastro = { tipo: "cliente", id: cli.id, nome: cli.nome };
      // Cadastrar só quando há documento: estabelecimento de maquininha sem CNPJ não vira
      // fornecedor, e propor isso em cada cafezinho seria ruído.
      if (temDoc) {
        r.cadastrar = {
          tipo: doc.length === 14 ? "fornecedor" : "favorecido",
          documento: doc,
          nome: nomeDoExtrato ?? cli?.nome ?? null,
        };
      }
    }
    return r;
  }

  // ── Entrada: de qual cliente veio ──
  // O "não" do dono (pagador recusado ou pausado para um cliente, revisão de 23/10/2026): aquele cliente nunca é
  // sugerido para este documento — nem como pagador conhecido, nem pelo histórico, nem pelo nome idêntico. A linha
  // pergunta "de quem é?" com os candidatos que sobram. Só o documento do PRÓPRIO cliente (passo 1) passa por cima.
  const vetados: ClienteVetado[] = [];
  const vetado = (e: Entrada): boolean => {
    const s = temDoc ? vetoDoPagador(idx, doc, e.id) : null;
    if (s && !vetados.some((x) => x.id === e.id)) vetados.push({ id: e.id, nome: e.nome, situacao: s });
    return !!s;
  };
  // 1. Documento do próprio cliente (verde).
  if (temDoc) {
    const cli = idx.clientePorDoc.get(doc);
    if (cli) r.cliente = reconhecer(cli, "documento", `${tipoDoc} confere com o cliente ${cli.nome}`);
  }
  // 2. Pagador guardado pelo dono. De UM cliente: sugestão com o motivo, que pede o SIM (clienteExigeSim). De dois
  //    ou mais (marina, seguradora): não identifica ninguém — a pergunta, com eles como candidatos. O documento do
  //    próprio cliente (passo 1) vence sempre. Vetado não entra (pagadoresDoDocumento já tira).
  const pagadores = !r.cliente && temDoc ? pagadoresDoDocumento(idx, doc) : [];
  if (pagadores.length === 1) {
    const [p] = pagadores;
    const quando = ddmm(p.em);
    r.cliente = {
      id: p.cliente.id, nome: p.cliente.nome, por: "pagador_conhecido", relacao: p.relacao,
      detalhe: `${frasePagoPor(p.relacao, p.cliente.nome)}, guardado por você${quando ? ` em ${quando}` : ""} — confira`,
    };
  }
  const variosClientes = pagadores.length > 1;
  // 3. Histórico unânime — continua sugerindo, mas pede o SIM: o histórico de entrada que chega aqui é de terceiro
  //    (o documento do próprio cliente foi pego no passo 1)… menos quando o cliente NÃO TEM documento no cadastro e o
  //    nome de quem pagou é idêntico ao dele: aí é o próprio cliente pagando com o CPF que falta na ficha. Se o nome
  //    idêntico (passo 4) acharia o MESMO cliente do histórico, a prova é o nome idêntico, sem SIM — como era antes
  //    da leva 8 (simulação de 22/10/2026: 3 linhas de 2 clientes sem CPF passavam a pedir o SIM à toa).
  //    Sem a leitura dos pagadores (pagadoresIndisponiveis) não se sabe o que o dono vetou: o atalho fica desligado e o
  //    histórico sempre pede o SIM. Histórico de um cliente VETADO não sugere nada — nem o nome idêntico depois dele: o
  //    dono disse que este documento não é daquele cliente, e a linha pergunta.
  let historicoVetado = false;
  if (!r.cliente && !variosClientes && historico) {
    const u = unanime(historico.entrada.cliente, historico.entrada.total);
    const cli = u ? idx.porId.cliente.get(u.id) : undefined;
    if (cli && u && vetado(cli)) {
      historicoVetado = true;
    } else if (cli && u) {
      const peloNome = limpo && !idx.pagadoresIndisponiveis ? porNomeIdentico(idx.clientes, limpo, doc) : null;
      r.cliente = peloNome?.id === cli.id
        ? reconhecer(cli, "nome_identico", `Nome idêntico ao do cliente ${cli.nome} (este ${tipoDoc} já pagou ${u.vezes}× em nome dele)`)
        : reconhecer(cli, "historico", `Este ${tipoDoc} já pagou ${u.vezes}× em nome de ${cli.nome} — confira`);
    }
  }
  // 4. Nome idêntico — menos o cliente para quem o dono vetou este documento. Sem a leitura dos pagadores
  //    (pagadoresIndisponiveis) não se sabe se o dono vetou este documento para este cliente: o nome idêntico não
  //    identifica sozinho (a prova nome_identico a aprovação usa sem o SIM) — vira a pergunta, com o cliente como
  //    candidato (revisão de 23/10/2026). Nunca cliente sem SIM. Sem documento no extrato não há veto a conferir (o
  //    veto é por documento): o nome idêntico decide como sempre.
  let candidatoPeloNome: CandidatoDoPagamento | null = null;
  if (!r.cliente && !variosClientes && !historicoVetado && limpo) {
    const cli = porNomeIdentico(idx.clientes, limpo, doc);
    if (cli && !vetado(cli)) {
      if (idx.pagadoresIndisponiveis && temDoc) candidatoPeloNome = { id: cli.id, nome: cli.nome, relacao: RELACAO_DO_NOME_IDENTICO };
      else r.cliente = reconhecer(cli, "nome_identico", `Nome idêntico ao do cliente ${cli.nome}`);
    }
  }
  // 5. Nada: "de quem é este pagamento?". Nunca "cadastrar cliente" com os dados de quem pagou (leva 8).
  if (!r.cliente) {
    const outro = temDoc ? (idx.favorecidoPorDoc.get(doc) ?? idx.fornecedorPorDoc.get(doc)) : undefined;
    if (outro) {
      r.outroCadastro = {
        tipo: idx.favorecidoPorDoc.get(doc) ? "favorecido" : "fornecedor",
        id: outro.id, nome: outro.nome,
      };
    }
    // Sem documento e sem nome (maquininha, boleto) a linha fica como antes: sem evidência, e a varredura diária
    // continua tentando identificá-la.
    if (temDoc || nomeDoExtrato || variosClientes) {
      r.deQuemE = {
        documento: temDoc ? doc : null,
        nome: nomeDoExtrato ?? outro?.nome ?? null,
        candidatos: [
          ...pagadores.map((p) => ({ id: p.cliente.id, nome: p.cliente.nome, relacao: p.relacao })),
          ...(candidatoPeloNome ? [candidatoPeloNome] : []),
        ],
        ...(vetados.length > 0 ? { vetados } : {}),
      };
    }
  }
  return r;
}

/** As frases de evidência, para o "por que o sistema propôs isto". */
export function frasesDaIdentificacao(i: Identificacao): string[] {
  const f: string[] = [];
  for (const rec of [i.fornecedor, i.favorecido, i.cliente]) if (rec) f.push(rec.detalhe);
  if (i.outroCadastro) {
    const tipo = { fornecedor: "fornecedor", favorecido: "favorecido", cliente: "cliente" }[i.outroCadastro.tipo];
    f.push(`O documento é do ${tipo} ${i.outroCadastro.nome}`);
  }
  if (i.deQuemE) {
    const c = i.deQuemE.candidatos ?? [];
    const peloNome = c.length === 1 && c[0].relacao === RELACAO_DO_NOME_IDENTICO ? c[0] : null;
    f.push(peloNome
      ? `De quem é este pagamento? O nome é idêntico ao do cliente ${peloNome.nome}, mas não deu para conferir os pagadores `
        + "que você guardou agora — confirme o cliente"
      : c.length > 1
      ? `De quem é este pagamento? Este ${tipoDoDocumento(i.deQuemE.documento)} paga por mais de um cliente: ${c.map((x) => x.nome).join(", ")}`
      : "De quem é este pagamento? Nenhum cliente reconhecido pelo CPF/CNPJ nem pelo nome");
    for (const v of i.deQuemE.vetados ?? []) f.push(fraseDoVeto(v.situacao, tipoDoDocumento(i.deQuemE.documento), v.nome));
  }
  if (i.nomeConhecido) f.push(`O banco não mandou o nome; pelo documento é ${i.nomeConhecido}`);
  return f;
}

function tipoDoDocumento(doc: string | null | undefined): string {
  return documentoNormalizado(doc).length === 14 ? "CNPJ" : "CPF";
}

/** "Você recusou este CPF como pagador de X: X não é sugerido" — o porquê de o cliente não aparecer. */
export function fraseDoVeto(situacao: SituacaoDoVeto | string, tipoDoc: string, cliente: string): string {
  return situacao === "pausado"
    ? `Você pausou este ${tipoDoc} como pagador de ${cliente}: ${cliente} não é sugerido até o administrador reativar`
    : `Você recusou este ${tipoDoc} como pagador de ${cliente}: ${cliente} não é sugerido`;
}
