// O lembrete ANTES do vencimento ("vence em 3 dias") de UMA conta a receber — dono, 26/11/2026: "2. A", o lembrete passa a
// pedir o "sim" dele.
//
// Até aqui a rotina receivable-reminders mandava sozinha ao cliente (whatsapp-send, origem "sistema"), 3 dias antes, uma vez
// por conta — mensagem a cliente sem o "sim" do dono, contra a regra dele. Agora a rotina só PREPARA e pergunta ao dono no
// WhatsApp (como os lembretes de revisão); o "sim" executa a tool enviar_lembrete_de_vencimento
// (_shared/ai/tools/lembrete-de-vencimento.ts), que confere tudo de novo com dado fresco, recusa se algo mudou desde a
// pergunta (o retrato) e manda com a MESMA chave de antes (lembrete-recebivel:<conta>:<vencimento>): o que já saiu não sai
// de novo.
//
// Esta parte lê e confere — a rotina, o cartão e a tool perguntam a MESMA coisa: a conta (aberta, com saldo, não é sinal,
// ainda não venceu, sem lembrete já enviado), o cliente do cadastro (não genérico, sem opt-out, com telefone válido), o piso
// (Configurações) e a entrada do cliente esperando no Extrato. O texto ao cliente é o MESMO que a rotina mandava, palavra
// por palavra. Recusa de negócio = { error } com a frase pronta; leitura que falha LANÇA (erro engolido viraria "sem piso",
// "sem opt-out" ou "nenhuma entrada esperando").
import { telefoneLegivel, telefoneParaEnvio } from "../ai/tools/agendamento.ts";
import { AVISO_DE_FIXO, pareceTelefoneFixo } from "../ai/phone.ts";
import { chaveDeEnvio, diaLocal } from "../whatsapp/idempotencia.ts";
import { saldoDaConta } from "./cobrar-juntas.ts";
import { lerDinheiroEsperando } from "./dinheiro-esperando.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** O nome da tool que o "sim" executa (e da pendência que a rotina cria). */
export const ACAO_DO_LEMBRETE_DE_VENCIMENTO = "enviar_lembrete_de_vencimento";

/** O relógio do lembrete (os testes trocam). */
export const relogioDoLembreteDeVencimento = { agora: () => new Date() };

/** Quem manda o lembrete: administrador e financeiro, como o lembrete de cobrança. */
export const SEM_CARGO_DO_LEMBRETE_DE_VENCIMENTO = "Só administrador ou financeiro manda lembrete de vencimento ao cliente.";

/** O "sim" sem o retrato do que o dono viu não envia (a pendência sempre grava o retrato). */
export const SEM_RETRATO_DO_LEMBRETE_DE_VENCIMENTO =
  "Nada foi enviado: este pedido não guardou o que você aprovou (o valor, o vencimento, o número e a mensagem). Peça de novo que eu confiro e mostro.";

export interface ContaDoLembrete {
  id: string;
  client_id: string | null;
  status: string | null;
  amount: number | null;
  paid_amount: number | null;
  balance_amount: number | null;
  due_date: string | null;
  description: string | null;
  service_order_id: string | null;
  is_deposit: boolean | null;
  reminder_sent_at: string | null;
}
const COLUNAS_DA_CONTA =
  "id, client_id, status, amount, paid_amount, balance_amount, due_date, description, service_order_id, is_deposit, reminder_sent_at";

interface ClienteDoLembrete {
  id: string;
  name: string | null;
  display_name: string | null;
  whatsapp: string | null;
  phone: string | null;
  opt_out_whatsapp: boolean | null;
  generico: boolean | null;
}
const COLUNAS_DO_CLIENTE = "id, name, display_name, whatsapp, phone, opt_out_whatsapp, generico";

/** O lembrete resolvido: o que o cartão mostra, o retrato guarda e o envio manda. */
export interface LembreteDeVencimento {
  conta: ContaDoLembrete;
  /** Como o dono conhece o cliente (o apelido, se houver). */
  nomeDoCliente: string;
  /** O "referente a …": a descrição da conta; sem ela, o número da OS. */
  descricao: string;
  /** O saldo da conta hoje. */
  valor: number;
  /** aaaa-mm-dd */
  vencimento: string;
  /** Dias corridos até o vencimento (0 = vence hoje). */
  dias: number;
  /** Só dígitos (55…), já validado: o número que recebe. */
  telefone: string;
  /** O texto EXATO que vai ao cliente. */
  texto: string;
  /** A frase veio do dono (custom_message), não é o texto padrão. */
  frasePropria: boolean;
}

/** O que a rotina lê uma vez para todas as contas (em vez de reler por conta). */
export interface PreLeituraDoVencimento {
  piso: number;
  empresa: string;
  /** As entradas esperando no Extrato, por cliente. */
  esperando: Map<string, Array<{ valor: number; data: string | null }>>;
}

const ehUuid = (s: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
const centavos = (v: unknown) => Math.round(Number(v ?? 0) * 100);

/** "R$ 1.234,56", como a rotina sempre formatou (Intl). */
export function emReaisDoLembrete(v: number): string {
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(v);
}

/** "29/11/2026" a partir de aaaa-mm-dd. */
export function dataDoVencimento(dia: string | null | undefined): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(dia ?? ""));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : "";
}

/** Soma dias a uma data aaaa-mm-dd (meio-dia UTC: sem surpresa de fuso nem de horário de verão). */
export function somarDias(dia: string, dias: number): string {
  const d = new Date(`${dia}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

/** Dias corridos de `de` até `ate` (aaaa-mm-dd). */
export function diasEntre(de: string, ate: string): number {
  return Math.round((Date.parse(`${ate}T12:00:00Z`) - Date.parse(`${de}T12:00:00Z`)) / 86_400_000);
}

/** "vence *hoje*", "vence *amanhã*" ou "vence em *N dias*". */
export function textoDoPrazo(dias: number): string {
  if (dias <= 0) return "vence *hoje*";
  if (dias === 1) return "vence *amanhã*";
  return `vence em *${dias} dias*`;
}

/** O "referente a …". A descrição da conta vence; sem ela, o número da OS como vem ("OS-00060"); sem os dois, "cobrança pendente". */
export function descricaoDaCobranca(descricao: string | null | undefined, numeroDaOs: string | null | undefined): string {
  return String(descricao ?? "").trim() || String(numeroDaOs ?? "").trim() || "cobrança pendente";
}

/**
 * O texto ao cliente — o MESMO que a rotina mandava desde 29/06/2026, palavra por palavra. Frase nova a cliente pede a
 * aprovação do dono: não mude nada aqui sem ela. Pura.
 */
export function mensagemDoLembreteDeVencimento(p: { nome: string; valor: number; descricao: string; dias: number; vencimento: string; empresa: string }): string {
  return `Olá ${p.nome}! 👋 Lembramos que o pagamento de *${emReaisDoLembrete(p.valor)}* ` +
    `referente a *${p.descricao}* ${textoDoPrazo(p.dias)} ` +
    `(*${dataDoVencimento(p.vencimento)}*). Em caso de dúvidas, entre em contato. — *${p.empresa}*`;
}

/** Leitura que falha LANÇA. */
async function ler<T>(consulta: PromiseLike<{ data: unknown; error: unknown }>, oQue: string): Promise<T> {
  const { data, error } = await consulta;
  if (error) throw new Error(`Não consegui ler ${oQue}: ${(error as { message?: string })?.message ?? error}`);
  return data as T;
}

/** O piso, o nome da empresa e as entradas esperando no Extrato, numa leitura só. LANÇA. */
export async function lerPreLeituraDoVencimento(admin: Db): Promise<PreLeituraDoVencimento> {
  const linhas = await ler<Array<{ key: string; value: unknown }>>(
    admin.from("app_settings").select("key, value").in("key", ["collection_min_amount", "company_name"]),
    "as configurações (piso e nome da empresa)",
  );
  const cfg = Object.fromEntries((linhas ?? []).map((l) => [l.key, String(l.value ?? "")]));
  const esperando = new Map<string, Array<{ valor: number; data: string | null }>>();
  for (const e of await lerDinheiroEsperando(admin)) {
    if (!e.clienteId) continue;
    const lista = esperando.get(e.clienteId) ?? [];
    lista.push({ valor: e.valor, data: e.data });
    esperando.set(e.clienteId, lista);
  }
  return { piso: Number(cfg.collection_min_amount) || 0, empresa: cfg.company_name || "MarineFlow", esperando };
}

/**
 * Lê a conta e o cliente, passa as travas (na ordem: a conta, o cliente, o dinheiro, o contato) e monta a mensagem.
 * `db`: o cliente das leituras (admin no cartão e na rotina, sb na execução); `admin`: as configurações e as entradas
 * esperando (service role). `pre`: a leitura que a rotina já fez para todas as contas.
 */
export async function montarLembreteDeVencimento(
  db: Db,
  admin: Db,
  args: Record<string, unknown> | undefined,
  pre?: PreLeituraDoVencimento,
): Promise<LembreteDeVencimento | { error: string }> {
  const id = String(args?.receivable_id ?? "").trim();
  if (!ehUuid(id)) return { error: "Diga qual conta a receber (o id da conta) recebe o lembrete." };
  const conta = await ler<ContaDoLembrete | null>(db.from("receivables").select(COLUNAS_DA_CONTA).eq("id", id).maybeSingle(), "a conta a receber");
  if (!conta) return { error: "Conta a receber não encontrada." };
  if (conta.status === "paid" || conta.status === "cancelled") {
    return { error: `Esta conta já está ${conta.status === "paid" ? "paga" : "cancelada"}: não há o que lembrar.` };
  }
  const valor = saldoDaConta(conta);
  if (!(valor > 0)) return { error: "Esta conta não tem saldo em aberto: não há o que lembrar." };
  if (conta.is_deposit) return { error: "Esta conta é um sinal: o lembrete antes do vencimento não vale para sinal." };
  const vencimento = String(conta.due_date ?? "").slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(vencimento)) return { error: "Esta conta não tem vencimento: não há o que lembrar." };
  const hoje = diaLocal(relogioDoLembreteDeVencimento.agora());
  const dias = diasEntre(hoje, vencimento);
  if (dias < 0) {
    return { error: `Esta conta já venceu (${dataDoVencimento(vencimento)}): aí é cobrança, não lembrete. Cobre o cliente (cobrar_juntas com o cliente).` };
  }
  if (conta.reminder_sent_at) return { error: "O lembrete desta conta já saiu (ou foi dispensado quando ela nasceu): não mando de novo." };
  if (!conta.client_id) return { error: "Esta conta não está ligada a um cliente do cadastro: não há para quem mandar." };

  const cliente = await ler<ClienteDoLembrete | null>(
    db.from("clients").select(COLUNAS_DO_CLIENTE).eq("id", conta.client_id).maybeSingle(), "o cadastro do cliente",
  );
  if (!cliente) return { error: "O cadastro do cliente desta conta não foi encontrado." };
  const nomeDoCliente = String(cliente.display_name ?? "").trim() || String(cliente.name ?? "").trim() || "cliente";
  if (cliente.generico) return { error: `O cadastro ${nomeDoCliente} é genérico, sem CPF/CNPJ: não recebe lembrete.` };

  const p = pre ?? await lerPreLeituraDoVencimento(admin);
  if (p.piso > 0 && valor < p.piso) {
    return { error: `${emReaisDoLembrete(valor)} fica abaixo do piso de ${emReaisDoLembrete(p.piso)} (Configurações): sem lembrete por WhatsApp.` };
  }
  const esperando = p.esperando.get(conta.client_id) ?? [];
  if (esperando.length) {
    const lista = esperando.map((e) => `${emReaisDoLembrete(e.valor)}${e.data ? ` de ${dataDoVencimento(e.data)}` : ""}`).join(", ");
    return { error: `Este cliente tem entrada esperando no Extrato (${lista}): pode ser este pagamento. Confira no Extrato antes de lembrar.` };
  }
  if (cliente.opt_out_whatsapp) return { error: "Este cliente pediu para não receber mensagens no WhatsApp (opt-out)." };
  const telefone = telefoneParaEnvio(cliente.whatsapp || cliente.phone || "");
  if (!telefone) return { error: "Sem telefone válido no cadastro do cliente para mandar o lembrete." };

  let numeroDaOs: string | null = null;
  if (conta.service_order_id && !String(conta.description ?? "").trim()) {
    const os = await ler<{ service_order_number: string | null } | null>(
      db.from("service_orders").select("service_order_number").eq("id", conta.service_order_id).maybeSingle(), "a OS da conta",
    );
    numeroDaOs = os?.service_order_number ?? null;
  }
  const descricao = descricaoDaCobranca(conta.description, numeroDaOs);
  const frase = String(args?.custom_message ?? "").trim();
  const primeiroNome = String(cliente.name ?? "").trim().split(/\s+/)[0] || "Cliente";
  const texto = frase || mensagemDoLembreteDeVencimento({ nome: primeiroNome, valor, descricao, dias, vencimento, empresa: p.empresa });
  return { conta, nomeDoCliente, descricao, valor, vencimento, dias, telefone, texto, frasePropria: !!frase };
}

export function lembreteRecusado(l: LembreteDeVencimento | { error: string }): l is { error: string } {
  return typeof (l as { error?: unknown }).error === "string";
}

/** "em 3 dias", "amanhã", "hoje". */
export function prazoDoVencimento(dias: number): string {
  return dias <= 0 ? "hoje" : dias === 1 ? "amanhã" : `em ${dias} dias`;
}

/** O cartão do "sim": quem recebe, o número inteiro, a conta (valor e vencimento conferidos) e a mensagem EXATA. */
export function cartaoDoLembreteDeVencimento(l: LembreteDeVencimento, p: { teste?: boolean } = {}): string {
  const linhas = [
    `Lembrete ANTES do vencimento para *${l.nomeDoCliente}* — WhatsApp ${telefoneLegivel(l.telefone)}`,
    `Conta: ${l.descricao} · *${emReaisDoLembrete(l.valor)}* · vence ${dataDoVencimento(l.vencimento)} (${prazoDoVencimento(l.dias)})`,
    `Mensagem que vai ao cliente:\n${l.texto}`,
  ];
  if (l.frasePropria) {
    linhas.push(`- Atenção: a frase é sua — confira se o valor (${emReaisDoLembrete(l.valor)}) e a data (${dataDoVencimento(l.vencimento)}) estão certos.`);
  }
  if (pareceTelefoneFixo(l.telefone)) linhas.push(`- ${AVISO_DE_FIXO}`);
  if (p.teste) linhas.push("- ⚠️ Modo de teste ligado: vai para o número de teste, não para o cliente.");
  return linhas.join("\n");
}

/** O retrato que o "sim" aprova: a conta, o telefone de destino, o valor, o vencimento e o texto. */
export function retratoDoLembreteDeVencimento(l: LembreteDeVencimento): Record<string, unknown> {
  return { conta: l.conta.id, telefone: l.telefone, valor: l.valor, vencimento: l.vencimento, texto: l.texto };
}

/** O que mudou entre o retrato aprovado e agora, em português; null = nada. */
export function oQueMudouNoLembreteDeVencimento(retrato: Record<string, unknown>, agora: LembreteDeVencimento): string | null {
  const novo = retratoDoLembreteDeVencimento(agora);
  if (retrato.conta !== novo.conta) return "a conta do pedido não é a mesma";
  if (retrato.telefone !== novo.telefone) return "o telefone de destino mudou";
  if (centavos(retrato.valor) !== centavos(novo.valor)) {
    return `o valor mudou (era ${emReaisDoLembrete(Number(retrato.valor))}, agora ${emReaisDoLembrete(agora.valor)})`;
  }
  if (retrato.vencimento !== novo.vencimento) {
    return `o vencimento mudou (era ${dataDoVencimento(String(retrato.vencimento ?? "")) || "—"}, agora ${dataDoVencimento(agora.vencimento)})`;
  }
  // "vence em 3 dias" vira "vence em 2 dias" de um dia para o outro: o texto padrão muda sozinho com a data. O dono aprovou
  // o lembrete desta conta, deste valor e deste vencimento — a contagem de dias atualizada não é mudança de conteúdo.
  if (retrato.texto !== novo.texto && !(typeof retrato.texto === "string" && mesmoTextoAMenosDoPrazo(retrato.texto, novo.texto as string))) {
    return "o texto da mensagem mudou";
  }
  return null;
}

/** Os dois textos só diferem no "vence hoje / amanhã / em N dias". */
function mesmoTextoAMenosDoPrazo(a: string, b: string): boolean {
  const semPrazo = (t: string) => t.replace(/vence (\*hoje\*|\*amanhã\*|em \*\d+ dias\*)/, "vence <prazo>");
  return semPrazo(a) === semPrazo(b);
}

/** A chave do envio: a MESMA que a rotina usava (o vencimento é o dia-alvo), com ":teste" quando desviado. */
export function chaveDoLembreteDeVencimento(contaId: string, vencimento: string, desviadoPorTeste: boolean): string {
  return chaveDeEnvio("lembrete-recebivel", contaId, vencimento, desviadoPorTeste ? "teste" : null);
}

/** O cartão do "sim" pedido pelo assistente (buildPendingSummary): "⚠️ …" numa linha = recusa, sem pendência. */
export async function resumirLembreteDeVencimento(admin: Db, args: Record<string, unknown>, p: { teste?: boolean } = {}): Promise<string> {
  const l = await montarLembreteDeVencimento(admin, admin, args);
  if (lembreteRecusado(l)) return `⚠️ ${l.error.replace(/\s*\n+\s*/g, " ")}`;
  return cartaoDoLembreteDeVencimento(l, p);
}

/** O retrato para a pendência do assistente; null = não deu para conferir (o cartão recusa). */
export async function retratoDaPendenciaDoVencimento(admin: Db, args: Record<string, unknown>): Promise<Record<string, unknown> | null> {
  try {
    const l = await montarLembreteDeVencimento(admin, admin, args);
    return lembreteRecusado(l) ? null : retratoDoLembreteDeVencimento(l);
  } catch {
    return null;
  }
}
