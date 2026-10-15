// A manhã nova (secretário, Passo 2, 15/10/2026): o que o banco tem vira CANDIDATO, com a regra de cada
// família — lógica pura, sem banco e sem IA. Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-manha.md §3.
//
// Para subir de manhã, um item cumpre as 4 condições do desenho aprovado:
//   1. exige o dono (cliente, cobrança, obra parada por ele — fornecedor e papelada nunca);
//   2. esperar custa (cliente esperando, dinheiro vencido, orçamento grande parado, obra parada);
//   3. vem preparado (a recomendação e o `pedido`, que o assistente transforma no cartão pronto);
//   4. ainda é verdade na hora de montar: a coleta lê o banco às 07:30 (só pendente, só quem ainda
//      espera, o status de agora). O que é dedução (a OS que "parece" esperar compra; o contato que
//      "parece" pedir preço) diz "parece".
// Números, datas e nomes são do banco. O `{L}` nos textos vira a letra do item quando a seleção a define.

import { brl, ddmm, diasEntre, nomeDoDia, paraBusca, somarDias, umaLinha } from "../_shared/secretario/base.ts";
import type { Familia, Secao, TipoDoItem } from "../_shared/secretario/tipos.ts";
import { dataBR, diaBR, horaBR } from "../_shared/pdf/datas.ts";

/** Os cortes do desenho aprovado, num lugar só. */
export const REGRAS = {
  maxManha: 3,
  cobrancaGrande: 5000,
  cobrancaMarco: 1000,
  /** dias de atraso em que a cobrança de R$ 1 mil+ sobe: do 1º ao 3º e do 7º ao 9º */
  marcos: [[1, 3], [7, 9]] as const,
  /** a partir daqui a cobrança é da revisão do mês (só lista) */
  cobrancaAntigaDias: 30,
  orcamentoGrande: 5000,
  orcamentoParadoDias: 7,
  orcamentoVenceEmDias: 3,
  /** rascunho só conta se foi criado há até 30 dias (os de agosto estão abandonados) */
  rascunhoMaxDias: 30,
  /** rascunho mexido hoje está em montagem: só no dia seguinte */
  rascunhoParadoDias: 1,
  clienteSemRespostaHoras: 12,
  /** "conversa todo dia": mensagens do dono para o contato em 4+ dos últimos 7 dias */
  conversaTodoDiaDias: 4,
  osParadaDias: 10,
};

/**
 * Os orçamentos montados e não enviados (R$ 5 mil+) são UM assunto só (decisão do dono, 15/10/2026: "um
 * assunto aparece uma vez"): todos vão juntos num item da manhã ("3 orçamentos montados e ainda não
 * enviados, R$ 211 mil: …"), e a letra sozinha abre a lista deles. Os de menos de R$ 5 mil e os já
 * enviados seguem com o cliente.
 */
export const ASSUNTO_NAO_ENVIADOS = "pacote:orcamentos_nao_enviados";

/**
 * Cadastro genérico ("Cliente Final", "Consumidor Final") não é um assunto: no ensaio de 13/10 ele juntou num
 * item só o ORÇ-00103 (a lancha do Miguel), o caminhão da OS-00110 e três motorhomes — e um "B feito" valeria
 * para os cinco. Com ele, cada orçamento, OS ou cobrança vale por si (e não empresta valor a uma conversa).
 */
export function ehClienteGenerico(nome: string | null | undefined): boolean {
  return /^(?:cliente|consumidor) final$/.test(paraBusca(nome));
}

/** O assunto de um item de cliente: o cliente; sem cliente (ou genérico), o próprio item. */
function assuntoDe(clientId: string | null, cliente: string | null, proprio: string): string {
  return clientId && !ehClienteGenerico(cliente) ? `cliente:${clientId}` : proprio;
}

export interface Candidato {
  familia: Familia;
  tipo: TipoDoItem;
  secao: Secao;
  /** o que é: recv:<uuid>, os:<uuid>, fone:<telefone> */
  referencia: string;
  /** de quem é (um assunto aparece uma vez): cliente:<uuid>; sem cliente, a própria referência */
  assunto: string;
  nome: string;
  /** a impressão digital do fato: mudou = fato novo */
  fato: string;
  valor: number;
  /** para "o mais antigo primeiro" (dia ou instante ISO) */
  desde: string;
  /** "o que se perde hoje" */
  perdeHoje: boolean;
  /** passa na regra da família para a manhã */
  elegivel: boolean;
  /** cobrança grande: fica toda manhã (fora da regra de repetição) */
  todoDia: boolean;
  /** por que ficou na lista (quando não é elegível) */
  porqueNaoSobe: string | null;
  /** a linha da manhã, sem a letra, a recomendação e a resposta */
  titulo: string;
  /** a linha curta: lista e "também" */
  curto: string;
  /** o nome com o essencial, para o "logo abaixo ficaram…" (até ~50 caracteres) */
  rotulo: string;
  recomendacao: string | null;
  /** "*A* = <faco>" */
  faco: string | null;
  /** "*A espera* = <alternativa>" (ou "*A feito* = já comprei") */
  alternativa: string | null;
  comandoAlternativo: "espera" | "feito";
  /** por que subiu (o "por que o A?") */
  motivo: string;
  /** o texto do turno do assistente quando o dono manda só a letra */
  pedido: string | null;
  fatos: Array<[string, string]>;
}

// ─── O que a coleta entrega (as linhas do banco já com nomes) ─────────────────────────────────

export interface CobrancaCrua {
  id: string;
  client_id: string | null;
  cliente: string | null;
  descricao: string | null;
  vencimento: string;
  saldo: number;
  os_numero: string | null;
  barco: string | null;
}

export interface ConversaCrua {
  phone: string;
  contato: string;
  categoria: "cliente" | "fornecedor" | "contato";
  last_inbound_at: string;
  last_body: string | null;
  client_id: string | null;
  /** o que ele mandou nos últimos 7 dias, mais nova primeiro */
  recebidas: Array<{ body: string | null; em: string }>;
  /** em quantos dos últimos 7 o dono mandou mensagem para ele */
  diasComMensagemSua: number;
}

export interface OrcamentoCru {
  id: string;
  numero: string;
  quote_status: string;
  valor: number;
  client_id: string | null;
  cliente: string | null;
  barco: string | null;
  criado_em: string;
  mexido_em: string;
  /** o último dia da validade (ultimoDiaDaValidade); null = não vence (aguardando sinal) ou sem data */
  fim_validade: string | null;
  /**
   * o rascunho já saiu para o cliente (PDF encaminhado do celular ou link pelo sistema): a coleta o trata
   * como enviado (quote_status 'sent', mexido = o envio) e guarda a data aqui
   */
  enviado_em?: string | null;
  /** o cliente escreveu que fechou com outra empresa ou desistiu DEPOIS do orçamento (a data da mensagem) */
  cliente_encerrou_em?: string | null;
}

export interface OsCrua {
  id: string;
  numero: string;
  status: string;
  valor: number;
  client_id: string | null;
  cliente: string | null;
  barco: string | null;
  mexido_em: string;
  agendada_em: string | null;
  /** soma dos sinais pagos */
  sinal_pago: number;
  /** a tarefa de compra da R16 aberta (task-automations/rules.ts:632) */
  tarefa_compra: { titulo: string; criada_em: string } | null;
  /** recebíveis não cancelados */
  cobrancas_vivas: number;
}

export interface ColetaDoSecretario {
  cobrancas: CobrancaCrua[];
  conversas: ConversaCrua[];
  orcamentos: OrcamentoCru[];
  oss: OsCrua[];
}

// ─── Pedaços de texto ──────────────────────────────────────────────────────────────────────────

const ATIVAS = new Set(["approved", "scheduled", "in_progress", "awaiting_parts", "open"]);

function onde(...partes: Array<string | null | undefined>): string {
  const p = partes.map((x) => umaLinha(x, 24)).filter(Boolean);
  return p.length ? ` (${p.join(", ")})` : "";
}

function diasTexto(n: number): string {
  return `${n} ${n === 1 ? "dia" : "dias"}`;
}

/** "venceu ontem", "venceu terça (13/10)", "venceu em 22/07 (há 85 dias)". */
function venceuEm(venc: string, hoje: string): string {
  const d = diasEntre(venc, hoje);
  if (d === 1) return "venceu ontem";
  if (d < 7) return `venceu ${nomeDoDia(venc).toLowerCase()} (${ddmm(venc)})`;
  return `venceu em ${ddmm(venc)} (há ${d} dias)`;
}

/** "hoje às 06:50", "ontem às 17:10", "em 13/10". */
function quandoChegou(iso: string, agora: Date): string {
  const dia = diaBR(new Date(iso));
  const d = diasEntre(dia, diaBR(agora));
  if (d === 0) return `hoje às ${horaBR(new Date(iso))}`;
  if (d === 1) return `ontem às ${horaBR(new Date(iso))}`;
  return `em ${ddmm(dia)}`;
}

function haQuanto(horas: number): string {
  return horas < 48 ? `${Math.max(1, Math.round(horas))} h` : diasTexto(Math.round(horas / 24));
}

function verboDaMensagem(body: string | null): { verbo: string; audio: boolean } {
  const b = String(body ?? "").trim();
  if (b === "[audio]" || b.startsWith("🎤")) return { verbo: "mandou áudio", audio: true };
  if (b === "[image]") return { verbo: "mandou foto", audio: false };
  if (b === "[document]") return { verbo: "mandou arquivo", audio: false };
  if (b === "[video]") return { verbo: "mandou vídeo", audio: false };
  return { verbo: "escreveu", audio: false };
}

function trecho(body: string | null): string {
  const b = String(body ?? "").trim();
  if (b === "[audio]") return "(áudio sem transcrição)";
  if (/^\[(image|video|document|conteúdo vazio)\]$/.test(b)) return "(sem texto)";
  return `"${umaLinha(b.replace(/^🎤\s*/u, ""), 60)}"`;
}

// PEDIR preço, não falar de preço (ensaio de 15/10: "preço de tabela… proposta diferenciada" era um vendedor
// oferecendo, e "diferença de preços entre a 288 e 628" era conversa de fornecedor). Vale: "quanto fica/custa…",
// "qual o valor", "me passa o orçamento", "preciso de um orçamento", "orçar", "quero fechar".
const PEDE_PRECO = new RegExp(String.raw`\b(?:` + [
  String.raw`quanto (?:custa|custaria|fica|ficaria|sai|sairia|cobra|cobram|cobraria|seria|e|vai ficar|vale)`,
  String.raw`(?:qual|quais) (?:e |seria |sera |o |a |os |as )*(?:valor|valores|preco|precos)`,
  String.raw`(?:passa|passar|passe|manda|mandar|mande|envia|enviar|envie|faz|fazer|faca|ve|ver) (?:me |pra mim |para mim )?(?:o |um |uma |a |os )?(?:orcamento|orcamentos|preco|valor|proposta|cotacao)`,
  String.raw`(?:preciso|precisava|precisamos|gostaria|queria|quero) (?:de )?(?:um |uma |o |a )?(?:orcamento|preco|valor|cotacao|proposta)`,
  String.raw`orcar|orcamento pra|orcamento para`,
  String.raw`(?:quero|vamos|podemos|queremos|quer) fechar`,
].join("|") + String.raw`)\b`);
const COM_PRESSA = /\b(hoje|urgente|urgencia|ainda hoje|o quanto antes|o mais rapido)\b/;

// ─── Famílias ──────────────────────────────────────────────────────────────────────────────────

export function candidatoDeCobranca(c: CobrancaCrua, hoje: string): Candidato {
  const dias = Math.max(1, diasEntre(c.vencimento, hoje));
  const grande = c.saldo >= REGRAS.cobrancaGrande;
  const noMarco = c.saldo >= REGRAS.cobrancaMarco && REGRAS.marcos.some(([a, b]) => dias >= a && dias <= b);
  const tipo: TipoDoItem = grande ? "cobranca_grande" : noMarco ? "cobranca_marco"
    : dias >= REGRAS.cobrancaAntigaDias ? "cobranca_antiga" : "cobranca_fora_do_marco";
  const fase = grande ? "grande" : noMarco ? (dias <= 3 ? "m1" : "m7") : "lista";
  const quem = umaLinha(c.cliente || "Sem cliente", 30);
  const porqueNaoSobe = tipo === "cobranca_antiga"
    ? `Ficou na lista: vencida há ${dias} dias (30 ou mais vão para a revisão do mês).`
    : tipo === "cobranca_fora_do_marco"
    ? (c.saldo < REGRAS.cobrancaMarco
      ? "Ficou na lista: abaixo de R$ 1 mil."
      : `Ficou na lista: ${dias}º dia de atraso (a manhã mostra cobrança do 1º ao 3º e do 7º ao 9º dia).`)
    : null;
  const motivo = grande
    ? `Subiu porque é cobrança de R$ 5 mil ou mais vencida há ${diasTexto(dias)}: fica toda manhã até entrar ou você adiar com data (*{L} espera* ou *{L} até dd/mm*).`
    : `Subiu porque passa de R$ 1 mil e está no ${dias}º dia de atraso (a manhã mostra cobrança do 1º ao 3º e do 7º ao 9º dia).`;
  return {
    familia: "cobranca",
    tipo,
    secao: "dinheiro",
    referencia: `recv:${c.id}`,
    assunto: assuntoDe(c.client_id, c.cliente, `recv:${c.id}`),
    nome: quem,
    fato: `${c.saldo.toFixed(2)}|${c.vencimento}|${fase}`,
    valor: c.saldo,
    desde: c.vencimento,
    perdeHoje: false,
    elegivel: grande || noMarco,
    todoDia: grande,
    porqueNaoSobe,
    titulo: `*${quem}*${onde(c.barco, c.os_numero)}: ${brl(c.saldo)} ${venceuEm(c.vencimento, hoje)} e não entrou.`,
    curto: `${quem}${onde(c.os_numero)}: ${brl(c.saldo)}, venceu ${ddmm(c.vencimento)} (${diasTexto(dias)})`,
    rotulo: `${umaLinha(quem, 24)} (${brl(c.saldo)}, venceu ${ddmm(c.vencimento)})`,
    recomendacao: dias <= 3 ? "Recomendo um lembrete educado hoje." : "Recomendo ligar hoje.",
    faco: "te mostro o lembrete pronto",
    alternativa: "até segunda",
    comandoAlternativo: "espera",
    motivo,
    pedido: `Prepare um lembrete de pagamento para o cliente ${umaLinha(c.cliente || "do recebível", 60)} sobre "${umaLinha(c.descricao || "o serviço", 80)}"` +
      ` (saldo de ${brl(c.saldo)}, venceu em ${dataBR(c.vencimento)}). Mostre o texto pronto e peça o meu sim antes de enviar.`,
    fatos: ([
      ["Cliente", c.cliente ? umaLinha(c.cliente, 60) : null],
      ["Barco", c.barco ? umaLinha(c.barco, 60) : null],
      ["OS", c.os_numero],
      ["Cobrança", c.descricao ? umaLinha(c.descricao, 80) : null],
      ["Saldo", brl(c.saldo)],
      ["Venceu em", `${dataBR(c.vencimento)} (${diasTexto(dias)})`],
    ] as Array<[string, string | null]>).filter((f): f is [string, string] => !!f[1]),
  };
}

export function candidatoDeConversa(w: ConversaCrua, agora: Date, valorDoCliente: number): Candidato {
  const horas = (agora.getTime() - new Date(w.last_inbound_at).getTime()) / 3_600_000;
  const recentes = w.recebidas.map((r) => paraBusca(r.body)).join(" ");
  const das24h = w.recebidas
    .filter((r) => agora.getTime() - new Date(r.em).getTime() <= 24 * 3_600_000)
    .map((r) => paraBusca(r.body)).join(" ");
  const pedePreco = PEDE_PRECO.test(recentes);
  // "amanhã" escrito ONTEM é hoje (ensaio de 15/10: o Jorge, às 14:53 de 14/10, "quer que eu leve o motorhome amanhã?")
  const ontem = somarDias(diaBR(agora), -1);
  const amanhaDeOntem = w.recebidas.some((r) => diaBR(new Date(r.em)) === ontem && /\bamanha\b/.test(paraBusca(r.body)));
  const comPressa = COM_PRESSA.test(das24h) || amanhaDeOntem;
  const sobrePressa = COM_PRESSA.test(das24h) ? 'fala em "hoje" ou "urgente"' : 'escreveu ontem "amanhã", que é hoje';
  const todoDia = w.diasComMensagemSua >= REGRAS.conversaTodoDiaDias;
  const passou = horas > REGRAS.clienteSemRespostaHoras;
  const cliente = w.categoria === "cliente";
  const tipo: TipoDoItem = w.categoria === "fornecedor" ? "fornecedor"
    : cliente ? (passou && !todoDia ? "cliente_sem_resposta" : "cliente_recente")
    : (pedePreco && passou && !todoDia ? "contato_pedindo_preco" : "contato_sem_cadastro");
  const elegivel = tipo === "cliente_sem_resposta" || tipo === "contato_pedindo_preco";
  const nome = umaLinha(w.contato || w.phone, 30);
  const { verbo, audio } = verboDaMensagem(w.last_body);
  const tempo = haQuanto(horas);
  const porqueNaoSobe = tipo === "fornecedor" ? "Ficou na lista: fornecedor (nunca de manhã)."
    : todoDia ? "Ficou na lista: vocês conversam quase todo dia."
    : !passou ? `Ficou na lista: escreveu há ${tempo} (a manhã espera 12 h).`
    : tipo === "contato_sem_cadastro" ? "Ficou na lista: contato sem cadastro que não fala de preço, orçamento ou fechar."
    : null;
  const pressa = comPressa ? ` Parece ter pressa (${sobrePressa}).` : "";
  const titulo = cliente
    ? `*${nome}* ${verbo} ${quandoChegou(w.last_inbound_at, agora)} e está há ${tempo} sem resposta.${pressa}`
    : `*${nome}* (sem cadastro) ${verbo} ${quandoChegou(w.last_inbound_at, agora)} e está há ${tempo} sem resposta; a mensagem parece pedir preço ou orçamento.${pressa}`;
  const motivo = (cliente
    ? `Subiu porque é cliente e está há ${tempo} sem resposta (a manhã mostra cliente sem resposta há mais de 12 h).`
    : `Subiu porque, mesmo sem cadastro, a mensagem parece pedir preço, orçamento ou fechar, e está há ${tempo} sem resposta.`) +
    (comPressa ? ` Pode se perder hoje: ${sobrePressa}.` : "");
  return {
    familia: cliente ? "cliente" : "contato",
    tipo,
    secao: cliente ? "clientes" : "contatos",
    referencia: `fone:${w.phone}`,
    assunto: assuntoDe(w.client_id, w.contato, `fone:${w.phone}`),
    nome,
    fato: new Date(w.last_inbound_at).toISOString(),
    valor: valorDoCliente,
    desde: new Date(w.last_inbound_at).toISOString(),
    perdeHoje: elegivel && comPressa,
    elegivel,
    todoDia: false,
    porqueNaoSobe,
    titulo,
    curto: `${nome}${cliente ? "" : w.categoria === "fornecedor" ? " (fornecedor)" : " (sem cadastro)"}: ${verbo} há ${tempo}, sem resposta`,
    rotulo: `${umaLinha(nome, 24)} (sem resposta há ${tempo})`,
    recomendacao: "Recomendo responder ainda de manhã.",
    faco: audio ? "resumo o áudio e preparo a resposta" : "preparo a resposta",
    alternativa: "lembro amanhã",
    comandoAlternativo: "espera",
    motivo,
    pedido: `Leia a conversa do WhatsApp com ${umaLinha(w.contato || w.phone, 60)} (${w.phone}), me diga em até duas linhas o que foi pedido` +
      " e prepare a resposta. Peça o meu sim antes de enviar.",
    fatos: [
      ["Contato", `${umaLinha(w.contato || w.phone, 60)} (${cliente ? "cliente" : w.categoria === "fornecedor" ? "fornecedor" : "sem cadastro"})`],
      ["Telefone", w.phone],
      ["Última mensagem dele", quandoChegou(w.last_inbound_at, agora)],
      ["Trecho", trecho(w.last_body)],
    ],
  };
}

function rotuloDoStatus(s: string): string {
  return ({
    draft: "montado, não enviado", sent: "enviado", awaiting_approval: "esperando aprovação",
    awaiting_deposit: "aprovado, esperando o sinal",
  } as Record<string, string>)[s] ?? s;
}

/** null = o rascunho é velho demais (abandonado): nem lista. */
export function candidatoDeOrcamento(q: OrcamentoCru, hoje: string): Candidato | null {
  const mexido = diaBR(new Date(q.mexido_em));
  const criado = diaBR(new Date(q.criado_em));
  const parado = Math.max(0, diasEntre(mexido, hoje));
  const rascunho = q.quote_status === "draft";
  if (rascunho && diasEntre(criado, hoje) > REGRAS.rascunhoMaxDias) return null;
  const grande = q.valor >= REGRAS.orcamentoGrande;
  const fim = q.fim_validade;
  const vencido = !!fim && hoje > fim;
  const vencendo = !!fim && !vencido && diasEntre(hoje, fim) <= REGRAS.orcamentoVenceEmDias;
  // o cliente disse que fechou com outra ou desistiu: nada de "recomendo um follow-up" (fica na lista)
  const encerrou = q.cliente_encerrou_em ? diaBR(new Date(q.cliente_encerrou_em)) : null;
  const tipo: TipoDoItem = encerrou ? "orcamento_na_lista"
    : rascunho
    ? (grande && parado >= REGRAS.rascunhoParadoDias ? "orcamento_nao_enviado" : "orcamento_na_lista")
    : grande && vencendo ? "orcamento_vencendo"
    : grande && parado >= REGRAS.orcamentoParadoDias ? "orcamento_parado"
    : "orcamento_na_lista";
  const elegivel = tipo !== "orcamento_na_lista";
  const quem = umaLinha(q.cliente || "sem cliente", 30);
  const cab = `*${q.numero}*${onde(q.cliente, q.barco)}, ${brl(q.valor)}`;
  const avisoVencido = vencido ? ` A validade venceu em ${ddmm(fim)}.` : "";
  const titulo = tipo === "orcamento_nao_enviado"
    ? `${cab}: montado em ${ddmm(criado)} e não enviado.`
    // "sem aprovação", não "sem resposta": o banco sabe do orçamento, não da conversa (o Miguel conversava
    // todo dia com o orçamento parado)
    : tipo === "orcamento_vencendo"
    ? `${cab}: a validade termina ${fim === hoje ? "hoje" : `em ${ddmm(fim)}`} e o cliente ainda não aprovou.`
    : q.quote_status === "awaiting_deposit"
    ? `${cab}: aprovado, e o sinal não veio desde ${ddmm(mexido)} (${diasTexto(parado)}).`
    : `${cab}: enviado e sem aprovação há ${diasTexto(parado)}.${avisoVencido}`;
  const mandado = q.enviado_em ? `mandado em ${ddmm(diaBR(new Date(q.enviado_em)))}, ` : "";
  const estadoCurto = mandado + (rascunho ? `montado em ${ddmm(criado)}, não enviado`
    : vencido ? `validade vencida em ${ddmm(fim)}`
    : q.quote_status === "awaiting_deposit" ? `aprovado, sinal não veio desde ${ddmm(mexido)}`
    : `parado há ${diasTexto(parado)}`) + (encerrou ? ` (o cliente disse em ${ddmm(encerrou)} que fechou com outra ou desistiu)` : "");
  const porqueNaoSobe = elegivel ? null
    : encerrou ? `Ficou na lista: o cliente escreveu em ${ddmm(encerrou)} que fechou com outra empresa ou desistiu. Se foi isso, marque o orçamento como recusado.`
    : !grande ? "Ficou na lista: abaixo de R$ 5 mil."
    : rascunho ? "Ficou na lista: mexido hoje (ainda em montagem)."
    : vencido ? `Ficou na lista: validade vencida em ${ddmm(fim)} e parado há ${diasTexto(parado)} (a manhã mostra a partir de 7).`
    : `Ficou na lista: parado há ${diasTexto(parado)} (a manhã mostra a partir de 7).`;
  const motivo = tipo === "orcamento_nao_enviado"
    ? `Subiu porque é orçamento de R$ 5 mil ou mais montado em ${ddmm(criado)} e ainda não enviado ao cliente.`
    : tipo === "orcamento_vencendo"
    ? `Subiu porque é orçamento de R$ 5 mil ou mais e a validade termina em ${ddmm(fim)}.`
    : `Subiu porque é orçamento de R$ 5 mil ou mais parado há ${diasTexto(parado)} (a manhã mostra a partir de 7).`;
  const marca = tipo === "orcamento_nao_enviado" ? "nao_enviado" : tipo === "orcamento_vencendo" ? "vencendo"
    : tipo === "orcamento_parado" ? "parado" : encerrou ? "encerrou" : "lista";
  return {
    familia: "orcamento",
    tipo,
    secao: "clientes",
    referencia: `os:${q.id}`,
    assunto: tipo === "orcamento_nao_enviado" ? ASSUNTO_NAO_ENVIADOS : assuntoDe(q.client_id, q.cliente, `os:${q.id}`),
    nome: `${q.numero} ${quem}`,
    fato: `${q.quote_status}|${q.valor.toFixed(2)}|${mexido}|${marca}`,
    valor: q.valor,
    desde: new Date(q.mexido_em).toISOString(),
    perdeHoje: elegivel && fim === hoje,
    elegivel,
    todoDia: false,
    porqueNaoSobe,
    titulo,
    curto: `${q.numero} ${quem}${onde(q.barco)}, ${brl(q.valor)}: ${estadoCurto}`,
    rotulo: `${q.numero} (${umaLinha(quem, 18)}, ${brl(q.valor)})`,
    recomendacao: tipo === "orcamento_nao_enviado" ? "Recomendo revisar e enviar."
      : tipo === "orcamento_vencendo" ? "Recomendo um follow-up antes de vencer."
      : q.quote_status === "awaiting_deposit" ? "Recomendo lembrar o sinal hoje." : "Recomendo um follow-up hoje.",
    faco: tipo === "orcamento_nao_enviado" ? "te mando o PDF" : "preparo o follow-up",
    alternativa: "até segunda",
    comandoAlternativo: "espera",
    motivo,
    // O rascunho vai pelo atalho do PDF (_shared/ai/atalho-pdf.ts): o PDF para o dono, nunca ao cliente.
    pedido: tipo === "orcamento_nao_enviado"
      ? `me manda o pdf do ${q.numero}`
      : `Prepare um follow-up do orçamento ${q.numero} (${umaLinha(q.cliente || "sem cliente", 60)}, ${brl(q.valor)}, ${rotuloDoStatus(q.quote_status)})` +
        " para o cliente pelo WhatsApp. Mostre o texto pronto e peça o meu sim antes de enviar.",
    fatos: ([
      ["Orçamento", q.numero],
      ["Cliente", q.cliente ? umaLinha(q.cliente, 60) : null],
      ["Barco", q.barco ? umaLinha(q.barco, 60) : null],
      ["Valor", brl(q.valor)],
      ["Situação", rotuloDoStatus(q.quote_status)],
      ["Mandado pelo WhatsApp em", q.enviado_em ? `${dataBR(diaBR(new Date(q.enviado_em)))} (no sistema ainda está como rascunho)` : null],
      ["Cliente escreveu que fechou com outra em", encerrou ? dataBR(encerrou) : null],
      ["Montado em", dataBR(criado)],
      ["Última mudança", `${dataBR(mexido)} (${diasTexto(parado)})`],
      ["Validade", fim ? dataBR(fim) : null],
    ] as Array<[string, string | null]>).filter((f): f is [string, string] => !!f[1]),
  };
}

/** null = OS sem nada a dizer (ativa e andando, concluída com cobrança). */
export function candidatoDeOs(o: OsCrua, hoje: string): Candidato | null {
  const ativa = ATIVAS.has(o.status);
  const mexido = diaBR(new Date(o.mexido_em));
  const parada = Math.max(0, diasEntre(mexido, hoje));
  const agendadaDia = o.agendada_em ? diaBR(new Date(o.agendada_em)) : null;
  const quem = umaLinha(o.cliente || "sem cliente", 30);
  const base = {
    familia: "os" as const,
    secao: "obras" as const,
    referencia: `os:${o.id}`,
    assunto: assuntoDe(o.client_id, o.cliente, `os:${o.id}`),
    nome: `${o.numero} ${quem}`,
    valor: o.valor,
    todoDia: false,
    comandoAlternativo: "espera" as "espera" | "feito",
  };
  const fatosBase: Array<[string, string]> = ([
    ["OS", o.numero],
    ["Cliente", o.cliente ? umaLinha(o.cliente, 60) : null],
    ["Barco", o.barco ? umaLinha(o.barco, 60) : null],
    ["Valor", brl(o.valor)],
  ] as Array<[string, string | null]>).filter((f): f is [string, string] => !!f[1]);

  if (ativa && o.tarefa_compra && (o.sinal_pago > 0 || agendadaDia)) {
    const n = /Comprar (\d+) (item|itens)/.exec(o.tarefa_compra.titulo);
    const oQue = n ? `${n[1]} ${n[2]}` : "itens";
    const desde = diaBR(new Date(o.tarefa_compra.criada_em));
    const extra = [
      o.sinal_pago > 0 ? `sinal de ${brl(o.sinal_pago)} já pago` : "",
      agendadaDia ? `serviço marcado para ${agendadaDia === hoje ? "hoje" : ddmm(agendadaDia)}` : "",
    ].filter(Boolean).join(", ");
    return {
      ...base,
      tipo: "os_esperando_compra",
      fato: `${o.tarefa_compra.titulo}|${o.status}`,
      desde: new Date(o.tarefa_compra.criada_em).toISOString(),
      perdeHoje: agendadaDia === hoje,
      elegivel: true,
      porqueNaoSobe: null,
      titulo: `*${o.numero}*${onde(o.cliente, o.barco)}: parece esperar a compra de ${oQue}${extra ? ` (${extra})` : ""}. Sem a peça o serviço não anda.`,
      curto: `${o.numero} ${quem}${onde(o.barco)}: parece esperar compra de ${oQue}`,
      // dedução pela tarefa: "parece" também no "logo abaixo" (a OS-00112 tinha a compra feita, crítica)
      rotulo: `${o.numero} (${umaLinha(quem, 18)}, parece esperar compra)`,
      recomendacao: "Recomendo resolver a compra hoje.",
      faco: "te mando a lista do que falta",
      alternativa: "já comprei",
      comandoAlternativo: "feito",
      motivo: `Subiu porque a OS tem ${o.sinal_pago > 0 ? "sinal pago" : "serviço marcado"} e a tarefa "${umaLinha(o.tarefa_compra.titulo, 60)}" está aberta desde ${ddmm(desde)}.` +
        " É dedução pela tarefa: se já comprou, responda *{L} feito*.",
      pedido: `Me mostre o que falta comprar para a ${o.numero} (${umaLinha(o.cliente || "sem cliente", 60)}): os itens, as quantidades e de quem costumo comprar.` +
        " Se der, prepare o pedido de compra; nada é enviado nem gravado sem o meu sim.",
      fatos: [...fatosBase, ["Tarefa", umaLinha(o.tarefa_compra.titulo, 80)], ["Aberta desde", dataBR(desde)],
        ...(o.sinal_pago > 0 ? [["Sinal pago", brl(o.sinal_pago)] as [string, string]] : []),
        ...(agendadaDia ? [["Marcada para", dataBR(agendadaDia)] as [string, string]] : [])],
    };
  }
  if (o.status === "completed" && o.valor > 0 && o.cobrancas_vivas === 0) {
    return {
      ...base,
      tipo: "os_sem_cobranca",
      fato: `${o.valor.toFixed(2)}|${mexido}`,
      desde: new Date(o.mexido_em).toISOString(),
      perdeHoje: false,
      elegivel: true,
      porqueNaoSobe: null,
      titulo: `*${o.numero}*${onde(o.cliente, o.barco)}: concluída e sem cobrança lançada (${brl(o.valor)}).`,
      curto: `${o.numero} ${quem}: concluída sem cobrança (${brl(o.valor)})`,
      rotulo: `${o.numero} (${umaLinha(quem, 18)}, sem cobrança)`,
      recomendacao: "Recomendo lançar a cobrança hoje.",
      faco: "preparo a cobrança",
      alternativa: "até segunda",
      motivo: "Subiu porque a OS foi concluída e não tem nenhuma cobrança (conta a receber) lançada.",
      pedido: `A ${o.numero} (${umaLinha(o.cliente || "sem cliente", 60)}) foi concluída e não tem nenhuma cobrança lançada.` +
        ` Prepare a cobrança de ${brl(o.valor)} para o cliente; peça o meu sim antes de gravar.`,
      fatos: [...fatosBase, ["Situação", "concluída, sem cobrança"], ["Última mudança", dataBR(mexido)]],
    };
  }
  if (ativa && parada >= REGRAS.osParadaDias) {
    return {
      ...base,
      tipo: "os_parada",
      fato: `${o.status}|${mexido}`,
      desde: new Date(o.mexido_em).toISOString(),
      perdeHoje: false,
      elegivel: false,
      porqueNaoSobe: `Ficou na lista: parada há ${diasTexto(parada)} sem tarefa sua aberta.`,
      titulo: `*${o.numero}*${onde(o.cliente, o.barco)}: parada desde ${ddmm(mexido)}.`,
      curto: `${o.numero} ${quem}${onde(o.barco)}: parada desde ${ddmm(mexido)}`,
      rotulo: `${o.numero} (${umaLinha(quem, 18)}, parada desde ${ddmm(mexido)})`,
      recomendacao: null,
      faco: "te mostro como ela está",
      alternativa: "até segunda",
      motivo: `Parada há ${diasTexto(parada)}.`,
      pedido: `Me mostre como está a ${o.numero} (${umaLinha(o.cliente || "sem cliente", 60)}): o que falta e o próximo passo.`,
      fatos: [...fatosBase, ["Parada desde", dataBR(mexido)]],
    };
  }
  return null;
}

/** O maior valor aberto de cada cliente (orçamento ou OS): conta na ordem do "cliente sem resposta". */
export function valorAbertoPorCliente(c: ColetaDoSecretario): Map<string, number> {
  const m = new Map<string, number>();
  const somar = (id: string | null, nome: string | null, v: number) => {
    if (id && !ehClienteGenerico(nome)) m.set(id, Math.max(m.get(id) ?? 0, v));
  };
  for (const q of c.orcamentos) somar(q.client_id, q.cliente, q.valor);
  for (const o of c.oss) if (ATIVAS.has(o.status)) somar(o.client_id, o.cliente, o.valor);
  return m;
}

/** Todos os candidatos do dia. */
export function candidatosDoDia(c: ColetaDoSecretario, agora: Date, hoje: string): Candidato[] {
  const valores = valorAbertoPorCliente(c);
  const lista: Candidato[] = [];
  for (const r of c.cobrancas) lista.push(candidatoDeCobranca(r, hoje));
  for (const w of c.conversas) lista.push(candidatoDeConversa(w, agora, w.client_id ? valores.get(w.client_id) ?? 0 : 0));
  for (const q of c.orcamentos) {
    const x = candidatoDeOrcamento(q, hoje);
    if (x) lista.push(x);
  }
  for (const o of c.oss) {
    const x = candidatoDeOs(o, hoje);
    if (x) lista.push(x);
  }
  return lista;
}
