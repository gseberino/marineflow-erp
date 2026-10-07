import type { ToolDef } from "./registry.ts";
import { comFusoDeBrasilia } from "../fuso.ts";
import { acharOS } from "./os-referencia.ts";
import { ehErro } from "./caixa.ts";

// Operação de campo + agenda inteligente (Fase 2) — SEM schema novo.
// O schema já tinha o necessário: service_orders.check_in_at / check_out_at / technician_notes,
// agenda_tasks e service_order_technicians.
//
// Estas tools são PARA O TÉCNICO usar pelo WhatsApp — por isso NÃO têm restrição de cargo
// (ao contrário das financeiras). Nenhuma delas expõe preço, custo ou margem.

/** Carimbo curto pt-BR para a linha de progresso. */
function carimbo(): string {
  const d = new Date();
  const data = d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", timeZone: "America/Sao_Paulo" });
  const hora = d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" });
  return `[${data} ${hora}]`;
}

/** Anexa uma linha ao technician_notes preservando o que já estava lá. */
async function anexarNota(sb: any, soId: string, linha: string): Promise<string> {
  const { data: so } = await sb.from("service_orders").select("technician_notes").eq("id", soId).maybeSingle();
  const atual = (so?.technician_notes || "").trim();
  const novo = atual ? `${atual}\n${linha}` : linha;
  await sb.from("service_orders").update({ technician_notes: novo.slice(0, 8000) }).eq("id", soId);
  return novo;
}

// ─── Frente operacional (07/10/2026): via do técnico e horário dito ─────────────────────────

const semAcento = (s: unknown) =>
  String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/_/g, " ").replace(/\s+/g, " ").trim();

/** Dia de hoje em Brasília (YYYY-MM-DD) — Brasília não tem horário de verão desde 2019. */
function diaEmBrasilia(agora: Date, deslocamentoDias = 0): string {
  return new Date(agora.getTime() - 3 * 3600_000 + deslocamentoDias * 86_400_000).toISOString().slice(0, 10);
}

/**
 * Horário DITO → instante ISO. "8h", "08:30", "8h30", "ontem 17h", "2026-10-06T17:00" (sem fuso
 * = Brasília). A tela de "Lançar a via" aceita chegada e saída no passado; check-in/out pelo
 * assistente gravavam só a hora de AGORA — quem conta depois ("cheguei às 8h") ficava com a hora
 * errada. Horário no futuro é recusado: chegada e saída são do que já aconteceu.
 * null = não veio nada.
 */
export function horarioDito(valor: unknown, agora = new Date()): { iso: string } | { error: string } | null {
  if (valor == null || String(valor).trim() === "") return null;
  const bruto = String(valor).trim();
  let iso: string | null = null;
  const s = semAcento(bruto);
  const m0 = s.match(/^(hoje|ontem|anteontem)?\s*(?:as|a)?\s*(\d{1,2})\s*(?:h|:)\s*(\d{2})?\s*(?:min|m)?$/);
  if (m0) {
    const h = Number(m0[2]);
    const min = Number(m0[3] ?? 0);
    if (h > 23 || min > 59) return { error: `Não entendi o horário "${bruto}".` };
    const dia = diaEmBrasilia(agora, m0[1] === "ontem" ? -1 : m0[1] === "anteontem" ? -2 : 0);
    iso = `${dia}T${String(h).padStart(2, "0")}:${String(min).padStart(2, "0")}:00-03:00`;
  } else {
    const comFuso = comFusoDeBrasilia(bruto);
    if (typeof comFuso === "string" && /^\d{4}-\d{2}-\d{2}T/.test(comFuso)) iso = comFuso;
  }
  const d = iso ? new Date(iso) : null;
  if (!d || Number.isNaN(d.getTime())) return { error: `Não entendi o horário "${bruto}". Diga a hora (ex.: 8h30) ou data e hora.` };
  if (d.getTime() > agora.getTime() + 10 * 60_000) {
    return { error: `O horário ${bruto} ainda não chegou — chegada e saída são do que já aconteceu.` };
  }
  return { iso: d.toISOString() };
}

/** As situações da via, com o rótulo da tela (line-via-tecnico.tsx, SITUACOES_NA_VIA). */
export const SITUACOES_DA_VIA: Record<string, string> = {
  a_fazer: "A fazer",
  so_levantar: "Só levantar (não executar)",
  aguarda_peca: "Aguarda peça",
  feito: "Feito",
  parcial: "Parcial",
  nao_feito: "Não feito",
};

/** Situação como se fala → o valor do CHECK de service_order_services.field_status. */
export function situacaoDita(valor: unknown): string | null {
  const s = semAcento(valor);
  if (!s) return null;
  const direto = s.replace(/ /g, "_");
  if (direto in SITUACOES_DA_VIA) return direto;
  if (/^nao\b.*(feit|fez|realiz|execut)/.test(s) || s === "nao") return "nao_feito";
  if (/parcial|meio feit|metade/.test(s)) return "parcial";
  if (/^(ja )?(feit|pront|conclu|ok|realizad|executad)/.test(s)) return "feito";
  if (/aguard.* peca|espera.* peca|falta peca/.test(s)) return "aguarda_peca";
  if (/levant/.test(s)) return "so_levantar";
  if (/^(a fazer|pendente|fazer)$/.test(s)) return "a_fazer";
  return null;
}

const PALAVRAS_VAZIAS = new Set(["de", "do", "da", "dos", "das", "o", "a", "os", "as", "e", "em", "no", "na", "com", "para", "pra", "um", "uma"]);

/**
 * Acha a linha de serviço pelo que foi dito: id, nome igual, nome contido, ou todas as palavras
 * do que foi dito no nome ("parametrização" acha "Parametrização do inversor"). Mais de uma
 * candidata = pergunta; nunca escolhe sozinho.
 */
export function acharServico<T extends { id: string; name_snapshot?: string | null }>(
  linhas: T[], dito: unknown,
): { linha: T } | { opcoes: string[] } | null {
  const bruto = String(dito ?? "").trim();
  if (!bruto) return null;
  const porId = linhas.find((l) => l.id === bruto);
  if (porId) return { linha: porId };
  const alvo = semAcento(bruto);
  const nome = (l: T) => semAcento(l.name_snapshot);
  const iguais = linhas.filter((l) => nome(l) === alvo);
  if (iguais.length === 1) return { linha: iguais[0] };
  const contidos = linhas.filter((l) => nome(l).includes(alvo));
  if (contidos.length === 1) return { linha: contidos[0] };
  if (contidos.length > 1) return { opcoes: contidos.map((l) => String(l.name_snapshot ?? "Serviço")) };
  const palavras = alvo.split(" ").filter((p) => p.length >= 3 && !PALAVRAS_VAZIAS.has(p));
  if (palavras.length === 0) return null;
  const porPalavra = linhas.filter((l) => palavras.every((p) => nome(l).includes(p)));
  if (porPalavra.length === 1) return { linha: porPalavra[0] };
  if (porPalavra.length > 1) return { opcoes: porPalavra.map((l) => String(l.name_snapshot ?? "Serviço")) };
  return null;
}

/** "[Via lançada em dd/mm/aaaa]" — o mesmo cabeçalho de src/lib/lancar-via.ts (registroDaVia). */
function cabecalhoDaVia(agora: Date): string {
  return `[Via lançada em ${agora.toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" })}]`;
}

/** Junta embaixo do que já existia, sem perder nada (juntarNotas de src/lib/lancar-via.ts). */
function juntarNotas(atuais: unknown, registro: string): string {
  const antes = String(atuais ?? "").trim();
  if (!registro) return antes;
  return antes ? `${antes}\n\n${registro}` : registro;
}

const horaBR = (iso: string) =>
  new Date(iso).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });

export const fieldOpsTools: ToolDef[] = [
  {
    name: "check_in_service_order",
    description:
      "Registra a CHEGADA do técnico no serviço (check-in): marca a hora e move a OS para 'em andamento'. Use quando o técnico disser 'cheguei', 'comecei o serviço', 'estou no barco'. " +
      "Se ele disser a HORA ('cheguei às 8h', 'ontem cheguei 7h30'), passe em `horario` — sem horário vale agora. Com horário, corrige uma chegada já registrada. Não mexe em preço nem conclui a OS.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
        os: { type: "string", description: "Número da OS como foi dito (OS-00112). Use isto OU service_order_id." },
        horario: { type: "string", description: "Hora da chegada como foi dita: '8h', '08:30', 'ontem 17h' ou data e hora ISO. Omitir = agora." },
        note: { type: "string", description: "Observação inicial opcional (ex.: 'cliente pediu para ver o inversor também')." },
      },
    },
    risk: "low",
    async execute(args, ctx) {
      const { sb } = ctx;
      const achada = await acharOS(ctx, args);
      if (ehErro(achada)) return achada;
      const dito = horarioDito(args.horario);
      if (ehErro(dito)) return dito;
      const { data: so } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, check_in_at")
        .eq("id", achada.id)
        .maybeSingle();
      if (!so) return { error: "OS não encontrada." };
      if (so.status === "cancelled") return { error: "OS cancelada — não dá para fazer check-in." };
      // Sem horário dito, a chegada registrada fica (pedir de novo não muda a hora). Com horário
      // dito, vale o que ele disse — é a correção que a tela "Lançar a via" também permite.
      if (so.check_in_at && !dito) {
        return { ok: true, ja_feito: true, os: so.service_order_number, check_in_em: so.check_in_at, mensagem: "Check-in já estava registrado. Se a hora estiver errada, diga a hora certa." };
      }

      const quando = dito ? dito.iso : new Date().toISOString();
      const patch: Record<string, unknown> = { check_in_at: quando };
      // Só promove para "em andamento" a partir de estados de trabalho — não mexe em concluída/faturada.
      if (["open", "scheduled", "approved", "pending", "awaiting_parts"].includes(so.status)) {
        patch.status = "in_progress";
      }
      const { error } = await sb.from("service_orders").update(patch).eq("id", so.id);
      if (error) throw error;

      const hora = dito ? ` (chegada às ${horaBR(quando)})` : "";
      if (args.note) await anexarNota(sb, so.id, `${carimbo()} Check-in${hora}: ${args.note}`);
      else await anexarNota(sb, so.id, `${carimbo()} Check-in do técnico${hora}.`);

      return {
        ok: true, os: so.service_order_number, check_in_em: quando, status: patch.status || so.status,
        ...(so.check_in_at ? { corrigido_de: so.check_in_at } : {}),
      };
    },
  },
  {
    name: "check_out_service_order",
    description:
      "Registra a SAÍDA do técnico (check-out): marca a hora de término e grava o relato do que foi feito. Use quando o técnico disser 'terminei', 'saí do barco', 'finalizei o serviço'. " +
      "Se ele disser a HORA ('saí às 17h'), passe em `horario` — sem horário vale agora. NÃO conclui a OS nem fatura — concluir é update_service_order_status, decisão de quem administra.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
        os: { type: "string", description: "Número da OS como foi dito (OS-00112). Use isto OU service_order_id." },
        horario: { type: "string", description: "Hora da saída como foi dita: '17h', '17:30', 'ontem 18h' ou data e hora ISO. Omitir = agora." },
        note: { type: "string", description: "Relato do que foi feito (recomendado)." },
      },
    },
    risk: "low",
    async execute(args, ctx) {
      const { sb } = ctx;
      const achada = await acharOS(ctx, args);
      if (ehErro(achada)) return achada;
      const dito = horarioDito(args.horario);
      if (ehErro(dito)) return dito;
      const { data: so } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, check_in_at, check_out_at")
        .eq("id", achada.id)
        .maybeSingle();
      if (!so) return { error: "OS não encontrada." };
      if (so.status === "cancelled") return { error: "OS cancelada — não dá para fazer check-out." };

      const agora = dito ? dito.iso : new Date().toISOString();
      if (so.check_in_at && new Date(agora) < new Date(so.check_in_at)) {
        return { error: `A saída (${horaBR(agora)}) ficaria antes da chegada registrada (${horaBR(so.check_in_at)}). Confira a hora.` };
      }
      const { error } = await sb.from("service_orders").update({ check_out_at: agora }).eq("id", so.id);
      if (error) throw error;

      const hora = dito ? ` (saída às ${horaBR(agora)})` : "";
      const linha = args.note ? `${carimbo()} Check-out${hora}: ${args.note}` : `${carimbo()} Check-out do técnico${hora}.`;
      await anexarNota(sb, so.id, linha);

      // Duração só faz sentido se houve check-in.
      let duracao: string | null = null;
      if (so.check_in_at) {
        const min = Math.max(0, Math.round((new Date(agora).getTime() - new Date(so.check_in_at).getTime()) / 60000));
        duracao = min < 60 ? `${min} min` : `${Math.floor(min / 60)}h${String(min % 60).padStart(2, "0")}`;
      }
      return {
        ok: true,
        os: so.service_order_number,
        check_out_em: agora,
        duracao_no_local: duracao,
        lembrete: "A OS continua no status atual — concluir/faturar é decisão de quem administra.",
      };
    },
  },
  {
    name: "update_service_order_via",
    description:
      "Lança a VIA DO TÉCNICO de uma OS — o mesmo que a tela 'Lançar a via' e a situação de cada serviço no cartão da OS: " +
      "marca um, vários ou TODOS os serviços como feito, parcial, não feito, aguarda peça, só levantar ou a fazer (com o motivo quando parcial ou não feito), " +
      "e grava chegada e saída com o horário DITO (pode ser no passado), o relato (vai para as notas do técnico) e o material além do previsto (vai para as notas internas). " +
      "Use para 'na OS-00112 a instalação do DC-DC ficou feita e a parametrização parcial, falta o cabo', 'a troca da bomba não foi feita: cliente não liberou', " +
      "'marca todos os serviços da OS-00108 como feitos', 'cheguei às 8h e saí às 17h na OS-00112'. Aceita o NÚMERO da OS. " +
      "O serviço é achado pelo nome (ou parte dele); se o nome servir para mais de um, a tool devolve as opções e não grava nada. Não conclui nem fatura a OS.",
    input_schema: {
      type: "object",
      properties: {
        os: { type: "string", description: "Número da OS como foi dito (OS-00112). Use isto OU service_order_id." },
        service_order_id: { type: "string", description: "UUID da OS." },
        servicos: {
          type: "array",
          description: "Um item por serviço citado.",
          items: {
            type: "object",
            properties: {
              servico: { type: "string", description: "Nome do serviço como foi dito (ou parte dele), ou o item_id de get_service_order." },
              situacao: { type: "string", description: "feito | parcial | nao_feito | aguarda_peca | so_levantar | a_fazer (pode vir como se fala: 'não foi feito', 'ficou pela metade')." },
              motivo: { type: "string", description: "Obrigatório quando parcial ou não feito: o que faltou / por que não foi feito." },
            },
            required: ["servico", "situacao"],
          },
        },
        todos: { type: "string", description: "Situação para TODOS os serviços da OS ('feito' em 'marca todos como feitos')." },
        motivo_todos: { type: "string", description: "Motivo para todos, quando 'todos' for parcial ou não feito." },
        chegada: { type: "string", description: "Hora da chegada como foi dita: '8h', '08:30', 'ontem 7h30' ou data e hora ISO." },
        saida: { type: "string", description: "Hora da saída como foi dita: '17h', '17:30', 'ontem 18h' ou data e hora ISO." },
        relato: { type: "string", description: "O que o técnico encontrou / deixou pendente / pediu para vigiar (vai para as notas do técnico, que saem no documento da OS)." },
        material_extra: { type: "string", description: "Material usado além do previsto (vai para as notas internas, que o cliente não vê)." },
      },
    },
    risk: "low",
    async execute(args, ctx) {
      // Frente operacional (07/10/2026). Caminho da tela: use-lancar-via.ts grava, linha a linha,
      // field_status/field_status_note em service_order_services e, numa só atualização,
      // check_in_at/check_out_at e as notas em service_orders. Não há função do banco nem
      // gatilho para isto; a tool faz o mesmo, com as mesmas regras de src/lib/lancar-via.ts:
      // "feito" limpa o motivo; o relato e o material entram EMBAIXO do que já existia.
      // Diferença de propósito: tudo é conferido ANTES de gravar — um serviço não achado ou
      // ambíguo devolve a pergunta sem ter gravado metade do pedido.
      const { sb } = ctx;
      const achada = await acharOS(ctx, args);
      if (ehErro(achada)) return achada;
      if (achada.status === "cancelled") return { error: `${achada.numero} está cancelada — a via não se lança em OS cancelada.` };

      const { data: linhas, error: erroLinhas } = await sb
        .from("service_order_services")
        .select("id, name_snapshot, field_status, field_status_note")
        .eq("service_order_id", achada.id);
      if (erroLinhas) return { error: `Não consegui ler os serviços da ${achada.numero}: ${erroLinhas.message}` };
      const servicosDaOS = (linhas ?? []) as Array<{ id: string; name_snapshot: string | null; field_status: string | null; field_status_note: string | null }>;
      const nomes = servicosDaOS.map((l) => l.name_snapshot || "Serviço");

      // 1) Situação de cada serviço — tudo resolvido antes de gravar.
      const mudancas = new Map<string, { field_status: string; field_status_note?: string | null }>();
      const problemas: string[] = [];
      const marcar = (linha: { id: string; name_snapshot: string | null; field_status_note: string | null }, situacaoBruta: unknown, motivoBruto: unknown) => {
        const situacao = situacaoDita(situacaoBruta);
        const nome = linha.name_snapshot || "Serviço";
        if (!situacao) { problemas.push(`"${situacaoBruta}" não é uma situação da via (feito, parcial, não feito, aguarda peça, só levantar, a fazer) — serviço ${nome}.`); return; }
        const motivo = String(motivoBruto ?? "").trim();
        if ((situacao === "parcial" || situacao === "nao_feito") && !motivo) {
          problemas.push(`${nome} ficou ${SITUACOES_DA_VIA[situacao].toLowerCase()}: qual o motivo? (o que faltou / por que não foi feito)`);
          return;
        }
        // Como a tela: "feito" limpa o motivo; parcial/não feito gravam o motivo; nas situações
        // de antes do serviço (a fazer, só levantar, aguarda peça) o motivo só muda se foi dito.
        const mudanca: { field_status: string; field_status_note?: string | null } = { field_status: situacao };
        if (situacao === "feito") mudanca.field_status_note = null;
        else if (motivo) mudanca.field_status_note = motivo.slice(0, 500);
        mudancas.set(linha.id, mudanca);
      };

      if (args.todos != null && String(args.todos).trim() !== "") {
        if (servicosDaOS.length === 0) return { error: `${achada.numero} não tem serviços lançados — não há o que marcar na via.` };
        for (const linha of servicosDaOS) marcar(linha, args.todos, args.motivo_todos);
      }
      for (const item of Array.isArray(args.servicos) ? args.servicos : []) {
        const achado = acharServico(servicosDaOS, item?.servico);
        if (!achado) { problemas.push(`Não achei o serviço "${item?.servico}" na ${achada.numero}. Serviços da OS: ${nomes.join("; ") || "nenhum"}.`); continue; }
        if ("opcoes" in achado) { problemas.push(`"${item?.servico}" serve para mais de um serviço: ${achado.opcoes.join("; ")}. Qual?`); continue; }
        marcar(achado.linha, item?.situacao, item?.motivo);
      }

      // 2) Chegada e saída com o horário dito.
      const chegadaDita = horarioDito(args.chegada);
      if (ehErro(chegadaDita)) problemas.push(`Chegada: ${chegadaDita.error}`);
      const saidaDita = horarioDito(args.saida);
      if (ehErro(saidaDita)) problemas.push(`Saída: ${saidaDita.error}`);
      const chegada = ehErro(chegadaDita) ? null : chegadaDita;
      const saida = ehErro(saidaDita) ? null : saidaDita;
      if (problemas.length) return { error: problemas.join(" "), nada_gravado: true, servicos_da_os: nomes };

      const relato = String(args.relato ?? "").trim();
      const material = String(args.material_extra ?? "").trim();
      if (mudancas.size === 0 && !chegada && !saida && !relato && !material) {
        return { error: "Nada para lançar: diga a situação dos serviços, a chegada/saída, o relato ou o material além do previsto.", servicos_da_os: nomes };
      }

      const { data: so, error: erroOS } = await sb
        .from("service_orders")
        .select("id, check_in_at, check_out_at, technician_notes, internal_notes")
        .eq("id", achada.id)
        .maybeSingle();
      if (erroOS) return { error: `Não consegui ler a ${achada.numero}: ${erroOS.message}` };
      if (!so) return { error: "OS não encontrada." };
      const inicio = chegada ? chegada.iso : so.check_in_at;
      const fim = saida ? saida.iso : so.check_out_at;
      if ((chegada || saida) && inicio && fim && new Date(fim) < new Date(inicio)) {
        return { error: `A saída (${horaBR(fim)}) ficaria antes da chegada (${horaBR(inicio)}). Confira os horários.`, nada_gravado: true };
      }

      // 3) Grava — linha a linha, como a tela.
      let gravadas = 0;
      for (const [id, mudanca] of mudancas) {
        const { error } = await sb.from("service_order_services").update(mudanca).eq("id", id);
        if (error) {
          return { error: `Falhou ao gravar a situação de um serviço (${error.message}). ${gravadas} de ${mudancas.size} já tinham sido gravados; chegada, saída e notas não foram.` };
        }
        gravadas++;
      }
      const agora = new Date();
      const patch: Record<string, string> = {};
      if (chegada) patch.check_in_at = chegada.iso;
      if (saida) patch.check_out_at = saida.iso;
      if (relato) patch.technician_notes = juntarNotas(so.technician_notes, `${cabecalhoDaVia(agora)}\nO que encontrei / pendente / vigiar: ${relato}`).slice(0, 8000);
      if (material) patch.internal_notes = juntarNotas(so.internal_notes, `${cabecalhoDaVia(agora)}\nMaterial além do previsto: ${material}`).slice(0, 8000);
      if (Object.keys(patch).length) {
        const { error } = await sb.from("service_orders").update(patch).eq("id", achada.id);
        if (error) throw error;
      }

      // 4) Como ficou a via inteira — o que falta é o que o dono quer saber em seguida.
      const depois = servicosDaOS.map((l) => {
        const m = mudancas.get(l.id);
        const situacao = m?.field_status ?? l.field_status ?? "a_fazer";
        const motivo = m && "field_status_note" in m ? m.field_status_note : l.field_status_note;
        return { servico: l.name_snapshot || "Serviço", situacao: SITUACOES_DA_VIA[situacao] ?? situacao, ...(motivo ? { motivo } : {}), mudou: !!m };
      });
      return {
        ok: true,
        os: achada.numero,
        servicos_atualizados: depois.filter((d) => d.mudou).map(({ mudou: _m, ...d }) => d),
        ainda_nao_feitos: depois.filter((d) => d.situacao !== SITUACOES_DA_VIA.feito).map(({ mudou: _m, ...d }) => d),
        ...(chegada ? { chegada: horaBR(chegada.iso) } : {}),
        ...(saida ? { saida: horaBR(saida.iso) } : {}),
        ...(relato ? { relato_gravado_nas_notas_do_tecnico: true } : {}),
        ...(material ? { material_gravado_nas_notas_internas: true } : {}),
        lembrete: "A via não conclui nem fatura a OS — concluir é update_service_order_status.",
      };
    },
  },
  {
    name: "log_service_order_progress",
    description:
      "Registra uma nota de PROGRESSO do serviço na OS — texto no histórico, sem medir tempo. Use para relatos do dia a dia: 'troquei as duas baterias', 'faltou peça X', 'cliente pediu mais um serviço'. Se veio de áudio, registre o que foi falado. " +
      "NÃO use quando a frase disser QUANTO TEMPO durou ('trabalhei 2h', 'fiquei 1h30 lá', 'foram 45 minutos') — isso é APONTAMENTO DE HORA e vai em log_service_order_hours, que grava a duração de verdade e entra no controle de tempo da OS. Uma nota de progresso não registra hora nenhuma. " +
      "Na dúvida entre as duas: tem número de duração na frase? então é log_service_order_hours.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
        note: { type: "string", description: "O que aconteceu / foi feito." },
      },
      required: ["service_order_id", "note"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: so } = await sb.from("service_orders").select("id, service_order_number, status").eq("id", args.service_order_id).maybeSingle();
      if (!so) return { error: "OS não encontrada." };
      if (so.status === "cancelled") return { error: "OS cancelada — não aceita novas notas." };
      await anexarNota(sb, so.id, `${carimbo()} ${args.note}`);
      return { ok: true, os: so.service_order_number, registrado: args.note };
    },
  },
  {
    name: "attach_photo_to_service_order",
    description:
      "Vincula uma FOTO/arquivo recebido no WhatsApp a uma OS (fica anexado ao serviço, ex.: 'antes' e 'depois'). Use o message_id que veio de read_supplier_messages ou da conversa. Não copia o arquivo — apenas amarra a mensagem à OS.",
    input_schema: {
      type: "object",
      properties: {
        message_id: { type: "string", description: "UUID da mensagem do WhatsApp que contém a foto/arquivo." },
        service_order_id: { type: "string", description: "UUID da OS." },
        note: { type: "string", description: "Legenda opcional (ex.: 'antes da troca')." },
      },
      required: ["message_id", "service_order_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: msg } = await sb
        .from("whatsapp_messages")
        .select("id, message_type, body, service_order_id")
        .eq("id", args.message_id)
        .maybeSingle();
      if (!msg) return { error: "Mensagem não encontrada." };
      const { data: so } = await sb.from("service_orders").select("id, service_order_number").eq("id", args.service_order_id).maybeSingle();
      if (!so) return { error: "OS não encontrada." };

      const { error } = await sb.from("whatsapp_messages").update({ service_order_id: so.id }).eq("id", msg.id);
      if (error) throw error;
      if (args.note) await anexarNota(sb, so.id, `${carimbo()} Foto anexada: ${args.note}`);

      return { ok: true, os: so.service_order_number, tipo: msg.message_type, legenda: args.note || null };
    },
  },
  {
    name: "check_technician_availability",
    description:
      "Mostra a AGENDA de um técnico num dia: tarefas da agenda e OS agendadas, em ordem de horário — e avisa se um horário proposto conflita. Use antes de agendar ('dá pra encaixar o João amanhã 14h?').",
    input_schema: {
      type: "object",
      properties: {
        technician_user_id: { type: "string", description: "UUID do técnico (use list_technicians)." },
        date: { type: "string", description: "Dia a consultar (YYYY-MM-DD). Padrão: hoje." },
        proposed_start: { type: "string", description: "Horário proposto (ISO) para checar conflito, opcional." },
        proposed_end: { type: "string", description: "Fim do horário proposto (ISO), opcional." },
      },
      required: ["technician_user_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const dia = String(args.date || new Date().toISOString().slice(0, 10));
      const ini = `${dia}T00:00:00`;
      const fim = `${dia}T23:59:59`;

      const { data: tarefas } = await sb
        .from("agenda_tasks")
        .select("id, title, scheduled_start_at, scheduled_end_at, status, location")
        .eq("assignee_user_id", args.technician_user_id)
        .gte("scheduled_start_at", ini)
        .lte("scheduled_start_at", fim);

      // OS agendadas para este técnico (vínculo em service_order_technicians).
      const { data: vinc } = await sb
        .from("service_order_technicians")
        .select("service_order_id")
        .eq("user_id", args.technician_user_id);
      const soIds = ((vinc as any[]) || []).map((v) => v.service_order_id).filter(Boolean);
      let oss: any[] = [];
      if (soIds.length) {
        const { data } = await sb
          .from("service_orders")
          .select("id, service_order_number, scheduled_start_at, scheduled_end_at, status, clients(name)")
          .in("id", soIds)
          .gte("scheduled_start_at", ini)
          .lte("scheduled_start_at", fim)
          .neq("status", "cancelled");
        oss = (data as any[]) || [];
      }

      const compromissos = [
        ...((tarefas as any[]) || []).map((t) => ({
          tipo: "tarefa", titulo: t.title, inicio: t.scheduled_start_at, fim: t.scheduled_end_at, status: t.status, local: t.location || null,
        })),
        ...oss.map((o) => ({
          tipo: "OS", titulo: `${o.service_order_number}${o.clients?.name ? ` — ${o.clients.name}` : ""}`,
          inicio: o.scheduled_start_at, fim: o.scheduled_end_at, status: o.status, local: null,
        })),
      ].sort((a, b) => new Date(a.inicio || 0).getTime() - new Date(b.inicio || 0).getTime());

      // Conflito = sobreposição real de intervalos.
      let conflito: any = null;
      if (args.proposed_start) {
        const pIni = new Date(args.proposed_start).getTime();
        const pFim = args.proposed_end ? new Date(args.proposed_end).getTime() : pIni + 60 * 60000;
        for (const c of compromissos) {
          const cIni = c.inicio ? new Date(c.inicio).getTime() : null;
          if (cIni === null) continue;
          const cFim = c.fim ? new Date(c.fim).getTime() : cIni + 60 * 60000;
          if (pIni < cFim && cIni < pFim) { conflito = c; break; }
        }
      }

      return {
        dia,
        compromissos,
        total: compromissos.length,
        horario_proposto: args.proposed_start || null,
        conflito,
        livre: args.proposed_start ? !conflito : null,
      };
    },
  },
];
