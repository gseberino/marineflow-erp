// O turno da tarde do resumo (secretário, Passo 3, 15/10/2026): o fechamento das 17:30 (seg–sex), a revisão
// da semana, a revisão do mês e a pergunta da sexta. Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-fechamento.md
//
// Chamado por index.ts SÓ quando a URL tem ?turno= (o cron das 17:30 chama ?turno=tarde; ?dry=1&turno=…
// pré-visualiza). Sem o parâmetro — o cron das 07:30 — nada daqui roda.
//
// app_settings.fechamento_formato: 'desligado' (padrão) = nada; 'sombra' = monta e GUARDA (resumo_tarde), sem
// enviar; 'ligado' = envia ao dono, e só nos dias em que a manhã foi a nova (as letras são as que ele recebeu;
// com a manhã-sombra, rebaixa para sombra). A tarde depende da manhã do dia: sem manhã gravada, nada.
//
// Gravar e enfileirar são UMA transação (RPC resumo_tarde_registrar): existir a linha de hoje = "já decidi
// hoje" (os disparos das 17:40 e 17:50 param). Custo de IA zero: a montagem é por regra.

import { diaBR, horaBR } from "../_shared/pdf/datas.ts";
import { donoDoWhatsApp } from "../_shared/whatsapp/dono.ts";
import { resolveOrCreateWhatsAppSession } from "../_shared/ai/whatsapp-channel.ts";
import {
  ehDiaDaPerguntaDaSemana,
  lerFormatoDoFechamento,
  lerTurnoPedido,
  proximoDiaComManha,
  type TurnoDaTarde,
  turnoDaTarde,
} from "../_shared/secretario/turno.ts";
import { type Candidato, candidatosDoDia, type ColetaDoSecretario } from "./secretario-candidatos.ts";
import { coletar } from "./secretario-coleta.ts";
import type { PassagemDoHistorico } from "./secretario-selecao.ts";
import { cobrancasAntigas, ficaramDeHoje, type ItemDaManha, type LinhaComLetra, paradosDaSemana } from "./secretario-tarde-regras.ts";
import {
  type ContaDoMes,
  type DiaDeAmanha,
  minutosDoEscritorio,
  type Panorama,
  textoDaTarde,
} from "./secretario-tarde-texto.ts";
import {
  contarEscritorio,
  conversaAtiva,
  fornecedoresEsperando,
  lerAmanha,
  lerEsperando,
  lerManhaDeHoje,
  lerMesQueFechou,
  lerPanorama,
} from "./secretario-tarde-coleta.ts";
import { type DadosDoEscritorio, textoDoEscritorio } from "./secretario-texto.ts";
import { tentativasAte } from "./linhas.ts";
import { linhasDoHistorico } from "./historico.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export interface RespostaDaTarde {
  status: number;
  corpo: Record<string, unknown>;
}

/** 1 = antes de 17:40, 2 = antes de 17:50, 3 = 17:50 ou depois (a última: vai mesmo com conversa). */
export function tentativaDoRelogio(agora: Date): 1 | 2 | 3 {
  const [h, m] = horaBR(agora).split(":").map(Number);
  const desde = h * 60 + m - (17 * 60 + 30);
  return desde < 10 ? 1 : desde < 20 ? 2 : 3;
}

/** A corrida de verdade só monta entre 17:25 e 19:00 de Brasília (um disparo às 10h não vira "fechamento"). */
export function dentroDoHorario(agora: Date): boolean {
  const [h, m] = horaBR(agora).split(":").map(Number);
  const min = h * 60 + m;
  return min >= 17 * 60 + 25 && min < 19 * 60;
}

const NOME_DO_TURNO: Record<TurnoDaTarde, string> = {
  fechamento: "o fechamento das 17:30",
  revisao_semana: "a revisão da semana",
  revisao_mes: "a revisão do mês",
};

/** O que a tarde leu (a coleta da manhã, rodada de novo, e as leituras só da tarde). */
export interface LidoDaTarde {
  coleta: ColetaDoSecretario;
  historico: PassagemDoHistorico[];
  // deno-lint-ignore no-explicit-any
  esperando: any[];
  amanha: DiaDeAmanha | null;
  escritorio: DadosDoEscritorio | null;
  panorama: Panorama | null;
  mesQueFechou: { conta: ContaDoMes; faturamento: string | null } | null;
}

export interface TardeMontada {
  texto: string | null;
  letras: LinhaComLetra[];
  detalhe: Record<string, unknown>;
  escritorio: string | null;
}

/** A parte pura: dos dados lidos ao texto, às letras e ao detalhe gravado. */
export function montarTardeDosDados(p: {
  hoje: string;
  agora: Date;
  turno: TurnoDaTarde;
  itens: ItemDaManha[];
  lido: LidoDaTarde;
  pergunta: boolean;
}): TardeMontada {
  const { hoje, agora, turno, lido } = p;
  const candidatos = new Map<string, Candidato>(candidatosDoDia(lido.coleta, agora, hoje).map((c) => [c.referencia, c]));
  const ficaram = turno === "fechamento" ? ficaramDeHoje(p.itens, candidatos) : [];
  const parados = turno === "revisao_semana" ? paradosDaSemana(p.itens, candidatos, lido.historico, hoje) : [];
  const antigas = turno === "revisao_mes" ? cobrancasAntigas(p.itens, lido.coleta.cobrancas, candidatos, lido.historico, hoje) : null;
  const fornecedores = turno === "fechamento" ? fornecedoresEsperando(lido.esperando, agora) : [];
  const t = textoDaTarde({
    hoje, turno, ficaram, amanha: lido.amanha, fornecedores, escritorio: lido.escritorio,
    parados, panorama: lido.panorama, antigas,
    mesQueFechou: lido.mesQueFechou?.conta ?? null, faturamento: lido.mesQueFechou?.faturamento ?? null,
    pergunta: p.pergunta,
  });
  const e = lido.escritorio;
  return {
    texto: t.texto,
    letras: t.letras,
    detalhe: {
      ficaram: ficaram.length,
      // todos os parados (o texto mostra até 5)
      parados: parados.length,
      ...(antigas ? { antigas: { n: antigas.n, total: antigas.total, sem_letra: antigas.fora.n } } : {}),
      ...(lido.amanha ? { amanha: lido.amanha.itens.length } : {}),
      fornecedores: fornecedores.length,
      ...(e ? { escritorio: { propostas: e.propostas, alertas: e.alertas, regras: e.regras, debitos_sem_loja: e.debitosSemLoja, entradas: e.entradas, minutos: minutosDoEscritorio(e) } } : {}),
      ...(lido.panorama ? { panorama: { mes: lido.panorama.mes, semana: lido.panorama.semana, vigia: !!lido.panorama.vigia } } : {}),
      ...(lido.mesQueFechou ? { mes_que_fechou: lido.mesQueFechou.conta } : {}),
      caracteres: t.texto?.length ?? 0,
    },
    escritorio: e ? textoDoEscritorio(e, horaBR(agora)).slice(0, 2000) : null,
  };
}

/** Lê o banco para a tarde. Lança se uma leitura essencial falhar (quem chama não monta). */
export async function lerTudoDaTarde(admin: Admin, p: {
  agora: Date;
  hoje: string;
  turno: TurnoDaTarde;
  dono: { id: string; phone: string };
  modo: "sombra" | "novo";
  cfg: Record<string, string>;
}): Promise<LidoDaTarde> {
  const { esperando, recebidas } = await lerEsperando(admin, p.agora);
  const lido = await coletar(admin, { agora: p.agora, hoje: p.hoje, dono: p.dono, modo: p.modo, doResumo: { esperando, recebidas, cfg: p.cfg } });
  return {
    coleta: lido.coleta,
    historico: lido.historico,
    esperando,
    amanha: p.turno === "fechamento" ? await lerAmanha(admin, p.dono, p.hoje, proximoDiaComManha(p.hoje), lido.coleta.oss) : null,
    escritorio: p.turno === "fechamento" ? await contarEscritorio(admin, p.hoje) : null,
    panorama: p.turno === "revisao_semana" ? await lerPanorama(admin, p.hoje) : null,
    mesQueFechou: p.turno === "revisao_mes" ? await lerMesQueFechou(admin, p.hoje) : null,
  };
}

function ok(corpo: Record<string, unknown>): RespostaDaTarde {
  return { status: 200, corpo: { ok: true, ...corpo } };
}

/**
 * O turno da tarde inteiro. `pedido` = o ?turno= da URL ("tarde" = o do dia; um turno forçado só com dry).
 * Nunca envia na sombra; nunca grava no dry-run.
 */
export async function rodarTurnoDaTarde(admin: Admin, p: { agora: Date; pedido: string | null; dry: boolean }): Promise<RespostaDaTarde> {
  const pedido = lerTurnoPedido(p.pedido);
  if (!pedido) return { status: 400, corpo: { ok: false, erro: "turno_invalido" } };
  if (!p.dry && pedido !== "tarde") return { status: 400, corpo: { ok: false, erro: "turno_forcado_so_no_dry" } };
  const hoje = diaBR(p.agora);

  const { data: cfgRows, error: cfgErr } = await admin.from("app_settings").select("key, value")
    .in("key", ["fechamento_formato", "quote_validity_days"]);
  const cfg: Record<string, string> = {};
  for (const r of (cfgRows as Array<{ key: string; value: unknown }>) || []) if (r?.key) cfg[String(r.key)] = String(r.value ?? "");
  // sem conseguir ler a chave = desligado (nada sai por engano)
  const formato = cfgErr ? "desligado" : lerFormatoDoFechamento(cfg["fechamento_formato"]);
  if (!p.dry && formato === "desligado") return ok({ motivo: "desligado" });

  const turno = pedido === "tarde" ? turnoDaTarde(hoje) : pedido;
  if (!turno) return ok({ motivo: "sem_tarde_hoje", dia: hoje });
  if (!p.dry && !dentroDoHorario(p.agora)) return ok({ motivo: "fora_do_horario", hora: horaBR(p.agora) });

  const dono = await donoDoWhatsApp(admin);
  if (!dono) return ok({ motivo: "sem_dono" });
  if (!p.dry) {
    const ja = await admin.from("resumo_tarde").select("id, turno, enviado, calado")
      .eq("dia", hoje).eq("phone_normalized", dono.phone).maybeSingle();
    if (ja.error) throw Object.assign(new Error("tarde: leitura de resumo_tarde falhou"), { code: ja.error.code });
    if (ja.data) return ok({ motivo: "ja_feito", turno: ja.data.turno, enviado: ja.data.enviado, calado: ja.data.calado });
  }

  const manha = await lerManhaDeHoje(admin, dono.phone, hoje);
  if (!manha) return ok({ motivo: "sem_manha", turno });
  const enviar = formato === "ligado" && manha.modo === "novo";
  const rebaixado = formato === "ligado" && manha.modo !== "novo";
  const tentativa = tentativaDoRelogio(p.agora);
  const conversa = await conversaAtiva(admin, dono.phone, p.agora);
  // "Se o dono estiver no meio de uma conversa, espera até 20 min": só faz sentido quando vai enviar
  if (!p.dry && enviar && conversa && tentativa < 3) return ok({ motivo: "esperando_conversa", turno, tentativa });

  const lido = await lerTudoDaTarde(admin, { agora: p.agora, hoje, turno, dono, modo: manha.modo, cfg });
  const pergunta = ehDiaDaPerguntaDaSemana(hoje);
  const m = montarTardeDosDados({ hoje, agora: p.agora, turno, itens: manha.itens, lido, pergunta });
  const letras = m.letras.map((l) => ({ letra: l.letra, referencia: l.referencia, tipo: l.tipo, parte: l.parte }));

  if (p.dry) {
    return ok({
      dry: true, turno, formato, modo_da_manha: manha.modo, enviaria: enviar && !!m.texto, rebaixado,
      conversa_ativa: conversa, pergunta_semana: pergunta, texto: m.texto, caracteres: m.texto?.length ?? 0, letras,
      detalhe: m.detalhe,
    });
  }

  const vaiEnviar = enviar && !!m.texto;
  const { data, error } = await admin.rpc("resumo_tarde_registrar", {
    p: {
      dia: hoje,
      phone: dono.phone,
      app_user_id: dono.id,
      turno,
      modo: manha.modo,
      formato: formato === "ligado" ? "ligado" : "sombra",
      texto: m.texto,
      calado: !m.texto,
      enviado: vaiEnviar,
      letras,
      detalhe: m.detalhe,
      escritorio: m.escritorio,
      itens: Math.min(21, m.letras.length),
      pergunta_semana: pergunta && !!m.texto,
      conversa_ativa: conversa,
      tentativa,
      // a fila para de tentar às 19:30 (nada depois das 20h)
      max_attempts: tentativasAte("19:30", p.agora),
    },
  });
  if (error) throw Object.assign(new Error("tarde: resumo_tarde_registrar falhou"), { code: error.code });
  const r = (data ?? {}) as { ok?: boolean; novo?: boolean; enviado?: boolean; calado?: boolean; erro?: string };
  if (!r.ok) return { status: 500, corpo: { ok: false, erro: r.erro ?? "registrar" } };

  // o que foi enviado entra no histórico da conversa do assistente ("e o B?" tem a que se referir); falha só loga
  let historico = false;
  if (r.novo && r.enviado && m.texto) {
    try {
      const sessao = await resolveOrCreateWhatsAppSession(admin, dono.phone, dono.id);
      const agoraHist = new Date();
      const { error: hErr } = await admin.from("ai_operator_messages").insert(linhasDoHistorico(sessao, m.texto, agoraHist, NOME_DO_TURNO[turno]));
      if (hErr) throw hErr;
      await admin.from("ai_operator_sessions").update({ last_activity_at: agoraHist.toISOString() }).eq("id", sessao);
      historico = true;
    } catch (e) {
      console.warn(JSON.stringify({ fn: "ai-daily-briefing", tarde: "historico_falhou", codigo: String((e as { code?: unknown })?.code ?? "erro") }));
    }
  }
  return ok({
    turno, formato, modo_da_manha: manha.modo, gravado: r.novo === true, enviado: r.enviado === true, calado: r.calado === true,
    rebaixado, conversa_ativa: conversa, tentativa, letras: letras.length, historico,
  });
}
