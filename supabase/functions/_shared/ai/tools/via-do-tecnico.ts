// A via do técnico em PDF pelo assistente (13/11/2026).
//
// Pedido do dono: "o assistente deve poder enviar por WhatsApp a ficha do técnico para cada responsável
// pelos serviços, parciais ou totais, de cada OS, e também para mim quando eu pedir". Decisões dele:
//   · cada pessoa recebe SÓ os serviços dela (as linhas marcadas para ela e as sem responsável);
//   · mandar a alguém da equipe pede o SIM dele; para si mesmo, não;
//   · a agenda manda sozinha junto da ficha das 19:30 (task-automations/via-da-agenda.ts), não daqui.
//
// O caminho é o do PDF do orçamento, peça por peça:
//   dados e folha   → _shared/pdf/via-do-tecnico-dados.ts + via-do-tecnico.ts (a mesma folha do menu Ações)
//   HTML → PDF      → /api/pdf no Vercel, com o token do link da OS (gerar-e-guardar.ts)
//   envio           → edge whatsapp-send (enviarDocumentoWhatsapp), arquivo 3 min no bucket privado
//   registro        → via_tecnico_envios (para a agenda não repetir e para "para quem foi a via?")
//
// A via não leva preço (decisão de 12/08/2026), mas leva telefone e endereço do cliente e as fotos do
// levantamento: vai só para telefone do CADASTRO (payees.phone ou app_users.phone_normalized), nunca
// para número digitado na conversa.

import {
  blockTechnician,
  cargosQueContam,
  lerRetrato,
  lerSolicitante,
  type Role,
  type ToolCtx,
  type ToolDef,
} from "./registry.ts";
import { enviarDocumentoWhatsapp } from "./whatsapp.ts";
import { chaveDeEnvio, liberarEnvio } from "../../whatsapp/idempotencia.ts";
import { desviadoPorTeste } from "../../whatsapp/marcar-enviado.ts";
import { guardarEEntregar } from "../../pdf/gerar-e-guardar.ts";
import {
  carregarDadosDaVia,
  legendaDaVia,
  linksDasFotosDaVia,
  type OrdemDaVia,
  type PessoaDaOs,
  pessoasDaOs,
  prepararVia,
} from "../../pdf/via-do-tecnico-dados.ts";
import type { DadosDaVia } from "../../pdf/via-do-tecnico.ts";
import { localizarOrdem } from "./documentos-pdf.ts";

/** Quem manda a via a alguém da equipe e marca responsável: só o administrador. */
export const CARGOS_DA_VIA_A_EQUIPE: Role[] = ["admin"];

/** O `context` do whatsapp-send: nunca 'quote' (marcaria o orçamento como enviado ao cliente). */
export const CONTEXTO_DA_VIA_PARA_SI = "agente_via_propria";
export const CONTEXTO_DA_VIA_A_EQUIPE = "agente_via_equipe";

/** Quem pode ser responsável por um serviço: a equipe de campo (comissionado é venda, não campo). */
export const TIPOS_DA_EQUIPE = ["socio", "funcionario", "diarista", "prestador"] as const;

/** Janela de 2 minutos: pedir duas vezes seguidas não manda dois arquivos iguais. */
const janelaDeDoisMinutos = () => Math.floor(Date.now() / 120_000);

// deno-lint-ignore no-explicit-any
type Admin = any;

const semAcento = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
const primeiroNome = (s: string) => s.trim().split(/\s+/)[0] ?? s;

// ═══ Achar a pessoa pelo nome ══════════════════════════════════════════════════════════════════

export type PessoaAchada = { id: string; nome: string; telefone: string };

/**
 * "Alex", "alex goncalves", "o Roberto" → a pessoa. Procura primeiro em quem está na OS (agenda e
 * responsáveis), depois na equipe ativa. Nome igual vence; senão o primeiro nome; senão "contém".
 * Dois candidatos = pergunta (nunca escolhe sozinho).
 */
export function escolherPessoa(
  nome: string,
  candidatos: Array<{ id: string; nome: string; telefone: string }>,
): { pessoa: PessoaAchada } | { opcoes: string[] } | null {
  const alvo = semAcento(nome).replace(/^(o|a|pro|pra|para o|para a)\s+/, "");
  if (!alvo) return null;
  const n = (c: { nome: string }) => semAcento(c.nome);
  const iguais = candidatos.filter((c) => n(c) === alvo);
  const doPrimeiro = candidatos.filter((c) => semAcento(primeiroNome(c.nome)) === alvo);
  const contem = candidatos.filter((c) => n(c).includes(alvo));
  for (const grupo of [iguais, doPrimeiro, contem]) {
    const unicos = [...new Map(grupo.map((c) => [c.id, c])).values()];
    if (unicos.length === 1) return { pessoa: unicos[0] };
    if (unicos.length > 1) return { opcoes: unicos.map((c) => c.nome) };
  }
  return null;
}

/** A equipe ativa (para achar quem ainda não está na OS). */
export async function equipeAtiva(admin: Admin): Promise<Array<{ id: string; nome: string; telefone: string }>> {
  const { data, error } = await admin.from("payees").select("id, name, phone, kind")
    .eq("active", true).in("kind", [...TIPOS_DA_EQUIPE]);
  if (error) throw new Error(`não consegui ler a equipe: ${error.message}`);
  return ((data ?? []) as Array<{ id: string; name: string; phone: string | null }>)
    .map((p) => ({ id: p.id, nome: p.name, telefone: String(p.phone ?? "").replace(/\D/g, "") }));
}

/** A pessoa pelo nome: primeiro entre as da OS, depois a equipe toda. */
export async function acharPessoa(
  admin: Admin,
  nome: string,
  daOs: PessoaDaOs[],
): Promise<{ pessoa: PessoaAchada } | { erro: string }> {
  const naOs = escolherPessoa(nome, daOs);
  if (naOs && "pessoa" in naOs) return naOs;
  if (naOs && "opcoes" in naOs) return { erro: `Mais de uma pessoa com esse nome nesta OS: ${naOs.opcoes.join(" e ")}. Pergunte qual.` };
  const naEquipe = escolherPessoa(nome, await equipeAtiva(admin));
  if (naEquipe && "pessoa" in naEquipe) return naEquipe;
  if (naEquipe && "opcoes" in naEquipe) return { erro: `Mais de uma pessoa com esse nome na equipe: ${naEquipe.opcoes.join(" e ")}. Pergunte qual.` };
  return { erro: `Não achei "${nome}" na equipe (sócio, funcionário, diarista ou prestador ativos).` };
}

// ═══ Registro ══════════════════════════════════════════════════════════════════════════════════

export interface LinhaDoRegistro {
  service_order_id: string;
  payee_id?: string | null;
  app_user_id?: string | null;
  origem: "agenda" | "assistente" | "para_si";
  estado: "enviado" | "falhou" | "pulado";
  motivo?: string | null;
  destino?: string | null;
  impressao?: string | null;
  servicos?: number | null;
  ficha_id?: string | null;
  dia?: string | null;
  pedido_por?: string | null;
}

/** Grava o envio. Falha ao gravar não desfaz o envio (o PDF já está no WhatsApp): só avisa no log. */
export async function registrarEnvioDaVia(admin: Admin, linha: LinhaDoRegistro): Promise<boolean> {
  const destino = linha.destino && /^[0-9]{8,15}$/.test(linha.destino) ? linha.destino : null;
  const motivo = linha.estado === "enviado" ? (linha.motivo ?? null) : (linha.motivo || "sem motivo informado").slice(0, 300);
  const { error } = await admin.from("via_tecnico_envios").insert({ ...linha, destino, motivo });
  if (error) {
    console.warn(`[via-do-tecnico] envio sem registro (${error.code ?? ""}): ${error.message}`);
    return false;
  }
  return true;
}

// ═══ Mandar ════════════════════════════════════════════════════════════════════════════════════

export type ResultadoDoEnvio =
  | { ok: true; deduplicado?: boolean; servicos: number; impressao: string }
  | { ok: false; motivo: string; pulado?: boolean };

/**
 * Monta a via da pessoa (ou da OS inteira), renderiza e manda para o telefone. Quem chama decide o
 * contexto, a chave e o registro. Nunca lança.
 */
export async function mandarVia(p: {
  admin: Admin;
  settings: Record<string, string>;
  jwt: string;
  dados: DadosDaVia;
  ordem: OrdemDaVia;
  pessoa: { id: string; nome: string } | null;
  telefone: string;
  contexto: string;
  chave: (impressao: string) => string;
  complementoDaLegenda?: string | null;
}): Promise<ResultadoDoEnvio> {
  try {
    if (!p.ordem.shareToken) return { ok: false, motivo: "a OS não tem token de link (o PDF não tem como ser gerado)" };
    const links = await linksDasFotosDaVia(p.admin, p.dados);
    const via = prepararVia(p.dados, p.ordem.numero, p.pessoa, links);
    if (via.semServicoDaPessoa) {
      return { ok: false, pulado: true, motivo: `todos os serviços da ${p.ordem.numero} estão com outra pessoa` };
    }
    const chave = p.chave(via.impressao);
    const entrega = await guardarEEntregar({
      admin: p.admin,
      doc: { html: via.html, nomeDoArquivo: via.nomeDoArquivo },
      shareToken: p.ordem.shareToken,
      baseUrl: p.settings.app_public_url || "",
      rotuloDoLog: "via-do-tecnico",
      entregar: (url) =>
        enviarDocumentoWhatsapp({
          phone: p.telefone,
          url,
          filename: via.nomeDoArquivo,
          caption: legendaDaVia(p.ordem, p.complementoDaLegenda),
          context: p.contexto,
          jwt: p.jwt,
          dedupeKey: chave,
        }),
    });
    if (!entrega.ok) return { ok: false, motivo: entrega.motivo };
    const envio = entrega.valor;
    if (!envio.ok) {
      // Sem resposta (tempo, rede): a reserva da chave ficaria de pé e o próximo pedido ouviria "já mandei".
      if (envio.semResposta) await liberarEnvio(p.admin, chave).catch(() => {});
      return { ok: false, motivo: envio.error };
    }
    return { ok: true, deduplicado: envio.deduplicated === true, servicos: via.servicos, impressao: via.impressao };
  } catch (e) {
    return { ok: false, motivo: e instanceof Error ? e.message : String(e) };
  }
}

/** Lê a OS para a via; erro já em frase para o modelo. */
async function abrirOs(admin: Admin, documento: string, settings: Record<string, string>) {
  const achado = await localizarOrdem(admin, documento, "os");
  if ("erro" in achado) return { erro: achado.erro } as const;
  if ("opcoes" in achado) return { erro: `Há mais de um documento com esse número: ${achado.opcoes.join(" e ")}. Pergunte qual.` } as const;
  const lida = await carregarDadosDaVia(admin, achado.ordem.id, settings);
  if (!lida.ok) return { erro: `Não consegui montar a via: ${lida.motivo}.` } as const;
  return { dados: lida.dados, ordem: lida.ordem } as const;
}

// ═══ Para si (chamado por send_document_pdf_to_self com via='tecnico') ═════════════════════════

export async function mandarViaParaSi(
  args: { documento?: unknown; pessoa?: unknown },
  ctx: ToolCtx,
): Promise<Record<string, unknown>> {
  const { admin } = ctx;
  const aberta = await abrirOs(admin, String(args.documento ?? ""), ctx.settings);
  if ("erro" in aberta) return { error: aberta.erro };
  const { dados, ordem } = aberta;

  let pessoa: PessoaAchada | null = null;
  const nome = String(args.pessoa ?? "").trim();
  if (nome) {
    const achada = await acharPessoa(admin, nome, await pessoasDaOs(admin, dados));
    if ("erro" in achada) return { error: achada.erro };
    pessoa = achada.pessoa;
  }

  // Destino: o telefone de quem pediu, do cadastro — nunca de um texto.
  const { data: u, error: uErr } = await admin.from("app_users").select("phone_normalized").eq("id", ctx.userId).maybeSingle();
  if (uErr) return { error: `Falha ao ler o seu cadastro: ${uErr.message}` };
  const telefone = String(u?.phone_normalized ?? "").replace(/\D/g, "");
  if (!telefone) return { error: "Você não tem um WhatsApp cadastrado para receber o PDF. Cadastre em Configurações → Usuários (aba IA/Zap)." };

  const r = await mandarVia({
    admin, settings: ctx.settings, jwt: ctx.jwt, dados, ordem,
    pessoa: pessoa ? { id: pessoa.id, nome: pessoa.nome } : null,
    telefone,
    contexto: CONTEXTO_DA_VIA_PARA_SI,
    chave: (impressao) => chaveDeEnvio("agente-via", ordem.id, pessoa?.id ?? "os", telefone, impressao, janelaDeDoisMinutos()),
  });
  await registrarEnvioDaVia(admin, {
    service_order_id: ordem.id,
    app_user_id: ctx.userId || null,
    payee_id: pessoa?.id ?? null,
    origem: "para_si",
    estado: r.ok ? "enviado" : (("pulado" in r && r.pulado) ? "pulado" : "falhou"),
    motivo: r.ok ? (pessoa ? `a via de ${pessoa.nome}` : null) : r.motivo,
    destino: telefone,
    impressao: r.ok ? r.impressao : null,
    servicos: r.ok ? r.servicos : null,
    pedido_por: ctx.userId || null,
  });
  if (!r.ok) {
    return { error: `Não consegui mandar a via: ${r.motivo}.`, orientacao: "Diga que não foi (sem fingir que mandou) e o motivo." };
  }
  if (r.deduplicado) return { ok: true, deduplicated: true, aviso: `Essa mesma via (${ordem.numero}) já foi mandada para você há instantes; não reenviei.` };
  const modoTeste = desviadoPorTeste(ctx.settings);
  return {
    ok: true,
    enviado_para: modoTeste ? "o número de TESTE do WhatsApp (modo de teste ligado)" : "o WhatsApp de quem pediu",
    documento: `Via do técnico ${ordem.numero}`,
    de: pessoa ? `${pessoa.nome} (só os serviços dele/dela e os sem responsável)` : "a OS inteira, com o responsável de cada serviço",
    servicos: r.servicos,
    observacao: modoTeste
      ? "O modo de teste do WhatsApp está ligado: o arquivo foi para o número de teste. Diga isso."
      : "O arquivo já chegou no WhatsApp de quem pediu.",
  };
}

// ═══ Para a equipe (com o SIM do dono) ═════════════════════════════════════════════════════════

/** Para quem a via vai: os nomes pedidos ou, sem nomes, todo mundo da OS. */
export async function destinatariosDaVia(
  admin: Admin,
  dados: DadosDaVia,
  para: string[],
): Promise<{ pessoas: Array<PessoaAchada & { dias: string[]; linhas: number }> } | { erro: string }> {
  const daOs = await pessoasDaOs(admin, dados);
  if (!para.length) {
    if (!daOs.length) {
      return { erro: "Ninguém está nesta OS: nenhum dia na agenda de hoje em diante e nenhum serviço com responsável. Diga para quem mandar (o nome)." };
    }
    return { pessoas: daOs.filter((p) => p.ativo).map((p) => ({ id: p.id, nome: p.nome, telefone: p.telefone, dias: p.dias, linhas: p.linhas })) };
  }
  const pessoas: Array<PessoaAchada & { dias: string[]; linhas: number }> = [];
  for (const nome of para) {
    const achada = await acharPessoa(admin, nome, daOs);
    if ("erro" in achada) return { erro: achada.erro };
    const naOs = daOs.find((p) => p.id === achada.pessoa.id);
    if (!pessoas.some((p) => p.id === achada.pessoa.id)) {
      pessoas.push({ ...achada.pessoa, dias: naOs?.dias ?? [], linhas: naOs?.linhas ?? 0 });
    }
  }
  return { pessoas };
}

function lerPara(args: Record<string, unknown>): string[] {
  const bruto = args.para;
  const lista = Array.isArray(bruto) ? bruto : typeof bruto === "string" && bruto.trim() ? [bruto] : [];
  return lista.map((s) => String(s ?? "").trim()).filter(Boolean).slice(0, 10);
}

const fimDoTelefone = (t: string) => (t ? `…${t.slice(-4)}` : "");
const diasCurtos = (dias: string[]) => {
  if (!dias.length) return "";
  const br = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
  return dias.length === 1 ? `na agenda ${br(dias[0])}` : `na agenda ${br(dias[0])}–${br(dias[dias.length - 1])} (${dias.length} dias)`;
};

/**
 * O cartão do SIM (agent.ts, buildPendingSummary): a OS, e para cada pessoa o telefone (final), quantos
 * serviços vão no papel dela e os dias na agenda. Ninguém pode receber = "⚠️" numa linha (recusa).
 */
export async function resumirEnvioDaVia(admin: Admin, args: Record<string, unknown>, settings: Record<string, string>): Promise<string> {
  const aberta = await abrirOs(admin, String(args.documento ?? ""), settings);
  if ("erro" in aberta) return `⚠️ ${aberta.erro}`;
  const { dados, ordem } = aberta;
  const dest = await destinatariosDaVia(admin, dados, lerPara(args));
  if ("erro" in dest) return `⚠️ ${dest.erro}`;
  const linhas: string[] = [];
  let algum = false;
  for (const p of dest.pessoas) {
    const via = prepararVia(dados, ordem.numero, { id: p.id, nome: p.nome }, {});
    if (!p.telefone) { linhas.push(`• ${p.nome} — sem telefone no cadastro: NÃO vai`); continue; }
    if (via.semServicoDaPessoa) { linhas.push(`• ${p.nome} — todos os serviços estão com outra pessoa: NÃO vai`); continue; }
    algum = true;
    const extra = [`${via.servicos} serviço${via.servicos === 1 ? "" : "s"}`, diasCurtos(p.dias)].filter(Boolean).join(" · ");
    linhas.push(`• ${p.nome} (WhatsApp ${fimDoTelefone(p.telefone)}) — ${extra}`);
  }
  if (!algum) return `⚠️ Ninguém pode receber a via da ${ordem.numero}: ${linhas.map((l) => l.replace(/^• /, "")).join("; ")}.`;
  const unidade = ordem.unidade ? ` · ${ordem.unidade}` : "";
  return [
    `Mandar a via do técnico da ${ordem.numero} (${ordem.cliente}${unidade}) pelo WhatsApp, sem preço:`,
    ...linhas,
    "Cada um recebe só os serviços dele e os sem responsável.",
  ].join("\n");
}

/** Retrato do SIM: quem e para qual telefone. Mudou até a execução = recusa (o "sim" foi sobre isto). */
async function retratoDoEnvio(args: Record<string, unknown>, ctx: ToolCtx): Promise<Record<string, unknown> | null> {
  try {
    const aberta = await abrirOs(ctx.admin, String(args.documento ?? ""), ctx.settings);
    if ("erro" in aberta) return null;
    const dest = await destinatariosDaVia(ctx.admin, aberta.dados, lerPara(args));
    if ("erro" in dest) return null;
    return { os: aberta.ordem.id, destinos: dest.pessoas.map((p) => `${p.id}:${p.telefone}`).sort() };
  } catch {
    return null;
  }
}

// ═══ Responsável de cada serviço ═══════════════════════════════════════════════════════════════

const TIRAR = new Set(["", "ninguem", "nenhum", "sem responsavel", "tirar", "remover", "-"]);

/** "1", "2", "linha 3", ou parte do nome do serviço → a linha. Número = a ordem da via (e da tela). */
export function escolherLinha(
  servico: string,
  linhas: Array<{ id: string; nome: string }>,
): { linha: { id: string; nome: string; n: number } } | { erro: string } {
  const alvo = semAcento(servico).replace(/^(linha|servico|item)\s*/, "");
  const numero = /^\d+$/.test(alvo) ? Number(alvo) : null;
  const comN = linhas.map((l, i) => ({ ...l, n: i + 1 }));
  if (numero !== null) {
    const l = comN[numero - 1];
    return l ? { linha: l } : { erro: `A OS tem ${linhas.length} serviço${linhas.length === 1 ? "" : "s"}; não existe o ${numero}.` };
  }
  const achadas = comN.filter((l) => semAcento(l.nome).includes(alvo));
  if (achadas.length === 1) return { linha: achadas[0] };
  if (achadas.length > 1) return { erro: `"${servico}" casa com mais de um serviço: ${achadas.map((l) => `${l.n} · ${l.nome}`).join("; ")}. Use o número.` };
  return { erro: `Não achei o serviço "${servico}" nesta OS. Serviços: ${comN.map((l) => `${l.n} · ${l.nome}`).join("; ")}.` };
}

type PedidoDeResponsavel = { servico: string; pessoa: string };

function lerPedidos(args: Record<string, unknown>): PedidoDeResponsavel[] {
  const bruto = Array.isArray(args.linhas) ? args.linhas : [];
  return bruto
    .map((x) => ({ servico: String((x as Record<string, unknown>)?.servico ?? "").trim(), pessoa: String((x as Record<string, unknown>)?.pessoa ?? "").trim() }))
    .filter((x) => x.servico)
    .slice(0, 30);
}

/** O que vai mudar, linha a linha, sem gravar. Usado pelo cartão do SIM e pela execução. */
export async function planoDosResponsaveis(
  admin: Admin,
  args: Record<string, unknown>,
): Promise<{ os: { id: string; numero: string }; mudancas: Array<{ id: string; n: number; nome: string; de: string | null; para: { id: string; nome: string } | null }> } | { erro: string }> {
  const achado = await localizarOrdem(admin, String(args.documento ?? ""), "os");
  if ("erro" in achado) return { erro: achado.erro };
  if ("opcoes" in achado) return { erro: `Há mais de um documento com esse número: ${achado.opcoes.join(" e ")}. Pergunte qual.` };
  const pedidos = lerPedidos(args);
  if (!pedidos.length) return { erro: "Diga qual serviço (número ou nome) e de quem é." };
  const { data: ls, error } = await admin.from("service_order_services")
    .select("id, name_snapshot, responsavel_payee_id, services(name)")
    .eq("service_order_id", achado.ordem.id).order("created_at", { ascending: true });
  if (error) return { erro: `Não consegui ler os serviços da OS: ${error.message}` };
  const linhas = ((ls ?? []) as Array<{ id: string; name_snapshot: string | null; responsavel_payee_id: string | null; services?: { name?: string | null } | null }>)
    .map((l) => ({ id: l.id, nome: l.name_snapshot || l.services?.name || "Serviço", atual: l.responsavel_payee_id }));
  if (!linhas.length) return { erro: `A ${achado.ordem.service_order_number} não tem serviço lançado.` };
  const equipe = await equipeAtiva(admin);
  const nomeDe = (id: string | null) => (id ? equipe.find((p) => p.id === id)?.nome ?? "outra pessoa (inativa)" : null);
  const mudancas: Array<{ id: string; n: number; nome: string; de: string | null; para: { id: string; nome: string } | null }> = [];
  for (const p of pedidos) {
    const l = escolherLinha(p.servico, linhas);
    if ("erro" in l) return { erro: l.erro };
    let para: { id: string; nome: string } | null = null;
    if (!TIRAR.has(semAcento(p.pessoa))) {
      const achada = escolherPessoa(p.pessoa, equipe);
      if (!achada) return { erro: `Não achei "${p.pessoa}" na equipe (sócio, funcionário, diarista ou prestador ativos).` };
      if ("opcoes" in achada) return { erro: `Mais de uma pessoa com esse nome na equipe: ${achada.opcoes.join(" e ")}. Pergunte qual.` };
      para = { id: achada.pessoa.id, nome: achada.pessoa.nome };
    }
    const atual = linhas.find((x) => x.id === l.linha.id)!.atual;
    mudancas.push({ id: l.linha.id, n: l.linha.n, nome: l.linha.nome, de: nomeDe(atual), para });
  }
  return { os: { id: achado.ordem.id, numero: achado.ordem.service_order_number }, mudancas };
}

/** O cartão do SIM da marcação de responsável. */
export async function resumirResponsaveis(admin: Admin, args: Record<string, unknown>): Promise<string> {
  const plano = await planoDosResponsaveis(admin, args);
  if ("erro" in plano) return `⚠️ ${plano.erro}`;
  return [
    `Responsável pelos serviços da ${plano.os.numero} (decide quem recebe cada serviço na via do técnico):`,
    ...plano.mudancas.map((m) =>
      `• ${m.n} · ${m.nome}: ${m.para ? m.para.nome : "sem responsável (vai na via de todos)"}${m.de ? ` (era ${m.de})` : ""}`),
  ].join("\n");
}

// ═══ As tools ══════════════════════════════════════════════════════════════════════════════════

export const viaDoTecnicoTools: ToolDef[] = [
  {
    name: "enviar_via_do_tecnico",
    description:
      "Manda pelo WhatsApp, em PDF, a VIA DO TÉCNICO de uma OS (a folha de serviço sem preço: serviços, material, instruções, levantamento, segurança) para as pessoas da EQUIPE que fazem o serviço. Sem 'para', vai a todos da OS (quem tem dias na agenda de hoje em diante e quem é responsável por algum serviço); com 'para', só aos nomes ditos. Cada pessoa recebe só os serviços dela e os sem responsável. Pede o SIM do dono. Para o próprio dono receber a via, use send_document_pdf_to_self com via='tecnico'.",
    input_schema: {
      type: "object",
      properties: {
        documento: { type: "string", description: "Número da OS (OS-00119 ou só 119) ou id." },
        para: { type: "array", items: { type: "string" }, description: "Nomes da equipe (ex.: ['Alex']). Vazio = todos da OS." },
      },
      required: ["documento"],
    },
    risk: "medium",
    roles: CARGOS_DA_VIA_A_EQUIPE,
    gravarSolicitante: true,
    preValidar: (args, ctx) => {
      if (!CARGOS_DA_VIA_A_EQUIPE.includes(ctx.userRole as Role)) return { error: "Só o administrador manda a via do técnico à equipe." };
      if (!String(args?.documento ?? "").trim()) return { error: "Diga de qual OS (o número)." };
      return null;
    },
    retratoDaPendencia: retratoDoEnvio,
    async execute(args, ctx) {
      const bloqueado = blockTechnician(ctx);
      if (bloqueado) return bloqueado;
      // Revalida com o cargo de quem PEDIU e de quem confirma (o "sim" pode vir de outro administrador no painel).
      const quem = lerSolicitante(args);
      if (!cargosQueContam(args, ctx).every((c) => CARGOS_DA_VIA_A_EQUIPE.includes(c as Role))) {
        return { error: "Só o administrador manda a via do técnico à equipe." };
      }

      const { admin } = ctx;
      const aberta = await abrirOs(admin, String(args.documento ?? ""), ctx.settings);
      if ("erro" in aberta) return { error: aberta.erro };
      const { dados, ordem } = aberta;
      const dest = await destinatariosDaVia(admin, dados, lerPara(args));
      if ("erro" in dest) return { error: dest.erro };

      const retrato = lerRetrato(args);
      if (retrato && Array.isArray(retrato.destinos)) {
        const agora = dest.pessoas.map((p) => `${p.id}:${p.telefone}`).sort();
        if (retrato.os !== ordem.id || JSON.stringify(agora) !== JSON.stringify(retrato.destinos)) {
          return { error: "Quem recebe a via (ou o telefone de alguém) mudou depois do seu SIM. Nada foi mandado; peça de novo para eu mostrar a lista atual." };
        }
      }

      const resultados: Array<Record<string, unknown>> = [];
      for (const p of dest.pessoas) {
        if (!p.telefone) {
          resultados.push({ pessoa: p.nome, enviado: false, motivo: "sem telefone no cadastro" });
          await registrarEnvioDaVia(admin, { service_order_id: ordem.id, payee_id: p.id, origem: "assistente", estado: "pulado", motivo: "sem telefone no cadastro", pedido_por: quem?.user_id || ctx.userId || null });
          continue;
        }
        const r = await mandarVia({
          admin, settings: ctx.settings, jwt: ctx.jwt, dados, ordem,
          pessoa: { id: p.id, nome: p.nome },
          telefone: p.telefone,
          contexto: CONTEXTO_DA_VIA_A_EQUIPE,
          chave: (impressao) => chaveDeEnvio("via-equipe", ordem.id, p.id, p.telefone, impressao, janelaDeDoisMinutos()),
        });
        await registrarEnvioDaVia(admin, {
          service_order_id: ordem.id,
          payee_id: p.id,
          origem: "assistente",
          estado: r.ok ? "enviado" : (("pulado" in r && r.pulado) ? "pulado" : "falhou"),
          motivo: r.ok ? null : r.motivo,
          destino: p.telefone,
          impressao: r.ok ? r.impressao : null,
          servicos: r.ok ? r.servicos : null,
          pedido_por: quem?.user_id || ctx.userId || null,
        });
        resultados.push(r.ok
          ? { pessoa: p.nome, enviado: true, servicos: r.servicos, ...(r.deduplicado ? { aviso: "já tinha ido há instantes; não repeti" } : {}) }
          : { pessoa: p.nome, enviado: false, motivo: r.motivo });
      }
      const modoTeste = desviadoPorTeste(ctx.settings);
      return {
        ok: resultados.some((r) => r.enviado === true),
        documento: `Via do técnico ${ordem.numero}`,
        resultados,
        ...(modoTeste ? { observacao: "O modo de teste do WhatsApp está ligado: os arquivos foram para o número de teste. Diga isso." } : {}),
        orientacao: "Diga para quem foi e para quem não foi (com o motivo). Nunca diga que foi para quem não foi.",
      };
    },
  },
  {
    name: "definir_responsavel_do_servico",
    description:
      "Marca QUEM FAZ cada serviço de uma OS (o responsável da linha), para a via do técnico de cada pessoa levar só os serviços dela. Ex.: 'na OS 119 o Alex faz a instalação do inversor e o Roberto as baterias' → linhas=[{servico:'inversor', pessoa:'Alex'}, {servico:'baterias', pessoa:'Roberto'}]. servico = número da linha (1, 2…) ou parte do nome; pessoa vazia ou 'ninguém' tira o responsável. Pede o SIM.",
    input_schema: {
      type: "object",
      properties: {
        documento: { type: "string", description: "Número da OS (OS-00119 ou só 119) ou id." },
        linhas: {
          type: "array",
          items: {
            type: "object",
            properties: {
              servico: { type: "string", description: "Número da linha na OS (1, 2…) ou parte do nome do serviço." },
              pessoa: { type: "string", description: "Nome de quem faz. Vazio ou 'ninguém' = sem responsável." },
            },
            required: ["servico"],
          },
        },
      },
      required: ["documento", "linhas"],
    },
    risk: "medium",
    roles: CARGOS_DA_VIA_A_EQUIPE,
    gravarSolicitante: true,
    preValidar: (args, ctx) => {
      if (!CARGOS_DA_VIA_A_EQUIPE.includes(ctx.userRole as Role)) return { error: "Só o administrador marca o responsável dos serviços." };
      if (!String(args?.documento ?? "").trim()) return { error: "Diga de qual OS (o número)." };
      if (!Array.isArray(args?.linhas) || !args.linhas.length) return { error: "Diga qual serviço e de quem é." };
      return null;
    },
    async execute(args, ctx) {
      const bloqueado = blockTechnician(ctx);
      if (bloqueado) return bloqueado;
      if (!cargosQueContam(args, ctx).every((c) => CARGOS_DA_VIA_A_EQUIPE.includes(c as Role))) {
        return { error: "Só o administrador marca o responsável dos serviços." };
      }
      const plano = await planoDosResponsaveis(ctx.admin, args);
      if ("erro" in plano) return { error: plano.erro };
      const feitas: string[] = [];
      for (const m of plano.mudancas) {
        const { error } = await ctx.admin.from("service_order_services")
          .update({ responsavel_payee_id: m.para?.id ?? null })
          .eq("id", m.id).eq("service_order_id", plano.os.id);
        if (error) {
          return { error: `Gravei ${feitas.length} de ${plano.mudancas.length}; o ${m.n} · ${m.nome} falhou: ${error.message}`, gravadas: feitas };
        }
        feitas.push(`${m.n} · ${m.nome}: ${m.para?.nome ?? "sem responsável"}`);
      }
      return {
        ok: true,
        os: plano.os.numero,
        gravadas: feitas,
        orientacao: "Diga o que ficou com quem. A via do técnico de cada pessoa passa a levar só os serviços dela (e os sem responsável).",
      };
    },
  },
];
