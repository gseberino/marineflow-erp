// O prazo que o fornecedor diz na conversa (Agenda de Produção, Fase 4, P4 — 25/10/2026; spec-fase4 §5.4).
//
// Um passo da rodada de 15 min do acompanhar-conversas (depois das promessas do dono). Lê, pelo banco, as mensagens dos
// fornecedores com COMPRA VIVA (agenda_mensagens_de_fornecedor: o dono, a equipe e o cliente com OS nunca entram — o
// telefone deles também está no cadastro de fornecedor, NOVO-agenda-34; o contador, sem compra, também não, NOVO-agenda-35),
// acha o prazo dito sem IA (detectarPrazoDeFornecedor) e registra o sinal (material_sinal_registrar). Com uma compra viva
// só, ela é a escolhida (unico); com mais, o modelo leve escolhe QUAL (escolherCompra: modelo, ou nenhum) — nunca a data:
// a data sai do banco pela expressão dita.
//
// C1 da revisão da Fase 4 (25/10/2026):
//   · "uma compra viva só" = uma linha E nenhuma outra compra viva dele (outras_vivas: a OC de estoque aberta, a nota sem
//     resposta, o Pix aberto). Com outra, a linha vai como dica e o casamento é nenhum (o banco rebaixa do mesmo jeito);
//   · o modelo pago é chamado no máximo agenda_config.detector_modelo_max vezes por rodada (padrão 5; 0 = nunca): passou
//     disso, a mensagem é registrada sem o modelo (nenhum) e a pergunta ao dono lista as compras. A leitura do teto que
//     falha = 0 (nenhum modelo) e vai para o log;
//   · o passo roda DEPOIS dos avisos ao dono e do "me acorde se" (index.ts): o dono vem primeiro.
//
// Aqui só se REGISTRA. O que o gestor faz com o sinal (a previsão da compra já ligada, com *desfaz*; a pergunta ao dono; o
// "chegou?") é do passo do material no banco (_agenda_material_sinais), atrás de agenda_config.modo_detector: desligado =
// a lista vem vazia e nada é chamado; sombra = só o que faria.
//
// Nunca lança: o erro vira linha em app_error_logs (context acompanhar-conversas, action agenda:fornecedor) e { erro } no
// resumo da rodada. A RPC que ainda não existe (migration 20261027100400 não aplicada) é silêncio: { pulado }.
import { diaBR } from "../_shared/agenda-dia.ts";
import { type CompraCandidata, type EscolhaDaCompra, escolherCompra } from "../_shared/agenda/casar-fornecedor.ts";
import { detectarPrazoDeFornecedor } from "../_shared/ai/promessa.ts";
import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export interface CompraViva extends CompraCandidata {
  os: string;
  os_material_id: string;
  situacao?: string;
  comprado_em?: string | null;
  previsao_ate?: string | null;
}

export interface MensagemDeFornecedor {
  msg_id: string;
  fornecedor_id: string;
  fornecedor?: string | null;
  direcao: "recebida" | "enviada";
  texto: string | null;
  em: string;
  /** As outras compras vivas dele que não são linha de OS (OC sem linha, nota sem linha, Pix aberto). */
  outras_vivas?: number;
  compras?: CompraViva[];
}

export interface ResultadoDosFornecedores {
  lidas: number;
  sinais: number;
  /** Quantas vezes o modelo leve foi chamado (mais de uma compra viva). */
  modelo: number;
  /** Mensagens que precisavam do modelo e foram sem ele (o teto da rodada, detector_modelo_max). */
  sem_modelo_pelo_teto?: number;
  /** A RPC ainda não existe (migration não aplicada). */
  pulado?: string;
  /** Mensagens que falharam sozinhas (o detalhe vai para app_error_logs). */
  erros?: number;
  /** O passo inteiro falhou. */
  erro?: string;
}

export interface DepsDosFornecedores {
  escolher?: (trecho: string, candidatos: CompraCandidata[]) => Promise<EscolhaDaCompra>;
  log?: typeof logEdgeError;
}

/** A função ausente (migration não aplicada): o PostgREST diz PGRST202; o Postgres, 42883. */
const FUNCAO_AUSENTE = new Set(["PGRST202", "42883"]);

/**
 * Quantas vezes o modelo pago pode ser chamado nesta rodada (agenda_config.detector_modelo_max). Erro na leitura = 0
 * (nenhum modelo: a mensagem vai sem ele e a pergunta ao dono lista as compras) e o motivo para o log.
 */
async function lerTetoDoModelo(admin: Db): Promise<{ teto: number; erro?: string }> {
  const { data, error } = await admin.from("agenda_config").select("detector_modelo_max").maybeSingle();
  if (error) return { teto: 0, erro: `agenda_config.detector_modelo_max: ${String(error.message ?? error)}` };
  const n = Number(data?.detector_modelo_max);
  return Number.isInteger(n) && n >= 0 ? { teto: n } : { teto: 0, erro: "agenda_config.detector_modelo_max ilegível" };
}

export async function vigiarPrazosDosFornecedores(
  admin: Db,
  agora: Date,
  deps: DepsDosFornecedores = {},
): Promise<ResultadoDosFornecedores> {
  const escolher = deps.escolher ?? ((t: string, c: CompraCandidata[]) => escolherCompra(t, c));
  const log = deps.log ?? logEdgeError;
  const resultado: ResultadoDosFornecedores = { lidas: 0, sinais: 0, modelo: 0 };
  const falhas: Array<{ msg: string; erro: string }> = [];
  const hoje = diaBR(agora.getTime());
  try {
    const { data, error } = await admin.rpc("agenda_mensagens_de_fornecedor", { p_hoje: hoje, p_agora: agora.toISOString() });
    if (error) {
      if (FUNCAO_AUSENTE.has(String(error.code ?? ""))) return { ...resultado, pulado: "agenda_mensagens_de_fornecedor ausente" };
      throw error;
    }
    const mensagens = (Array.isArray(data) ? data : []) as MensagemDeFornecedor[];
    resultado.lidas = mensagens.length;
    let teto: number | null = null;
    for (const m of mensagens) {
      try {
        const p = detectarPrazoDeFornecedor(m.texto, new Date(m.em), m.direcao);
        if (!p) continue;
        const compras = Array.isArray(m.compras) ? m.compras : [];
        const outras = Number(m.outras_vivas ?? 0);
        let escolhida: CompraViva | undefined;
        let casouPor: "unico" | "modelo" | "nenhum" = "nenhum";
        let confianca: number | null = null;
        if (compras.length === 1) {
          // Uma linha só — mas com outra compra viva dele (a OC de estoque, a nota sem resposta, o Pix aberto) a mensagem
          // pode ser dessa outra: a linha vai como dica e o casamento é nenhum (vira pergunta, nunca grava sozinho).
          escolhida = compras[0];
          casouPor = outras > 0 ? "nenhum" : "unico";
        } else if (compras.length > 1) {
          if (teto === null) {
            const t = await lerTetoDoModelo(admin);
            teto = t.teto;
            if (t.erro) {
              await log(admin, {
                context: "acompanhar-conversas",
                action: "agenda:fornecedor",
                message: `prazo do fornecedor: o teto do modelo não foi lido (${t.erro}); nesta rodada, nenhum modelo`,
                details: { teto: 0 },
              });
            }
          }
          if (resultado.modelo < teto) {
            resultado.modelo++;
            const r = await escolher(p.trecho, compras.map((c) => ({ n: c.n, rotulo: c.rotulo })));
            confianca = r.confianca;
            escolhida = r.n === null ? undefined : compras.find((c) => c.n === r.n);
            casouPor = escolhida ? "modelo" : "nenhum";
          } else {
            // o teto da rodada: sem o modelo, a pergunta ao dono lista as compras
            resultado.sem_modelo_pelo_teto = (resultado.sem_modelo_pelo_teto ?? 0) + 1;
          }
        }
        const { error: e2 } = await admin.rpc("material_sinal_registrar", {
          p_msg: m.msg_id,
          p_fornecedor: m.fornecedor_id,
          p_tipo: p.tipo,
          p_expressao: p.expressao,
          p_condicional: p.condicional,
          p_trecho: p.trecho,
          p_candidatos: compras.map((c) => ({ n: c.n, os: c.os, os_material_id: c.os_material_id, rotulo: c.rotulo })),
          p_os_material: escolhida?.os_material_id ?? null,
          p_casou_por: casouPor,
          p_confianca: confianca,
          p_hoje: hoje,
          p_agora: agora.toISOString(),
        });
        if (e2) throw e2;
        resultado.sinais++;
      } catch (e) {
        // deno-lint-ignore no-explicit-any
        falhas.push({ msg: m.msg_id, erro: String((e as any)?.message ?? e) });
      }
    }
    if (falhas.length) {
      resultado.erros = falhas.length;
      await log(admin, {
        context: "acompanhar-conversas",
        action: "agenda:fornecedor",
        message: `prazo do fornecedor: ${falhas.length} mensagem(ns) com erro (` +
          falhas.slice(0, 5).map((f) => `${f.msg}: ${f.erro}`).join("; ") + ")",
        details: { falhas },
      });
    }
    return resultado;
  } catch (e) {
    // deno-lint-ignore no-explicit-any
    const msg = String((e as any)?.message ?? e);
    console.error("[acompanhar-conversas] agenda:fornecedor falhou:", e);
    await log(admin, {
      context: "acompanhar-conversas",
      action: "agenda:fornecedor",
      message: `prazo do fornecedor: ${msg}`,
      // deno-lint-ignore no-explicit-any
      details: { code: (e as any)?.code ?? null },
      error: e,
    });
    return { ...resultado, erro: msg };
  }
}
