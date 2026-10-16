// Os comandos do dono sobre a manhã nova, com o banco (secretário, Passo 2, 15/10/2026).
//
// Quem chama (ai-agent, handleWhatsAppTurn) já conferiu: resumo_formato = 'novo' e a mensagem é do dono.
// Só lê resumo_itens/resumo_manha do dia de Brasília e grava pelas RPCs resumo_item_acao/resumo_item_voltar
// (service_role). Nunca lança: erro de leitura vira uma frase ao dono, sem nada gravado pela metade.
//
// A letra sozinha NÃO executa nada: devolve o `pedido` do item, que o ai-agent põe no lugar do texto do
// turno (como o número de uma lista de opções vira o rótulo). O assistente monta o cartão pelo caminho de
// sempre, e nada sai para cliente sem o "sim".

import { diaBR } from "../pdf/datas.ts";
import { diasEntre, proximaSegunda, somarDias } from "./base.ts";
import { type AcaoDoLote, type ComandoDoSecretario, diaDoAdiamento } from "./comandos.ts";
import {
  ehPacote,
  type ItemGravado,
  type PassagemAnterior,
  pedidoDaCobrancaAntiga,
  TEXTO_SEM_RESUMO,
  textoDaAcao,
  textoDaLista,
  textoDaRespostaDaSemana,
  textoDaVolta,
  textoDoDetalhe,
  textoDoLote,
  textoDoPacote,
  textoDoPorque,
  textoNaoAchei,
  vencimentoDoFato,
} from "./respostas.ts";
import { esperaDoTipo } from "./tipos.ts";
import { executarPapelada, type PendenciaDoSecretario } from "./papelada.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export type ResultadoDoComando =
  /** responder ao dono sem o modelo */
  | { tipo: "resposta"; texto: string }
  /** o texto vira o turno do assistente (o cartão pronto do item) */
  | { tipo: "pedido"; texto: string; letra: string }
  /** não era comando meu (ex.: "pouco" sem a pergunta da sexta aberta): segue como conversa, sem mudar nada */
  | { tipo: "seguir" }
  /**
   * (Passo 5) responder E abrir a confirmação do assistente ("sim <PIN>"): o ai-agent grava a pendência, o
   * pending_confirm_action_id da sessão e a pergunta ativa — o mesmo mecanismo dos lembretes de revisão
   */
  | { tipo: "confirmar"; texto: string; pendencia: PendenciaDoSecretario };

const MODO = "novo";
const COLUNAS_DO_ITEM =
  "letra, principal, posicao, ordem, familia, tipo, secao, referencia, nome, titulo, recomendacao, motivo, pedido, detalhe, acao, adiado_ate, fato";

/** A cobrança vencida há 30 dias ou mais (a régua da revisão do mês, a mesma de REGRAS.cobrancaAntigaDias). */
const COBRANCA_ANTIGA_DIAS = 30;

/** Uma resposta do lote no formato da RPC resumo_itens_acoes (o "até" já calculado). */
export function acaoParaRpc(i: AcaoDoLote, hoje: string): { letra: string; acao: string; ate?: string; resposta?: string } {
  if (i.acao !== "adiar") return { letra: i.letra, acao: i.acao };
  const ate = i.quando === "amanha" ? somarDias(hoje, 1)
    : i.quando === "15dias" ? somarDias(hoje, 15)
    : proximaSegunda(hoje); // "segunda" e "semana": a próxima segunda (a da revisão seguinte)
  return {
    letra: i.letra, acao: "adiado", ate,
    ...(i.quando === "semana" ? { resposta: "semana" } : i.quando === "15dias" ? { resposta: "15dias" } : {}),
  };
}

/** A contagem de *escritório* da tarde de hoje, se houver (erro ou sem a tabela = null: vale a da manhã). */
async function escritorioDaTarde(admin: Admin, phone: string, hoje: string): Promise<string | null> {
  try {
    const { data, error } = await admin.from("resumo_tarde").select("escritorio")
      .eq("phone_normalized", phone).eq("dia", hoje).eq("modo", MODO).maybeSingle();
    if (error) return null;
    return typeof data?.escritorio === "string" && data.escritorio ? data.escritorio : null;
  } catch {
    return null;
  }
}

const ERRO_DE_LEITURA = "Não consegui ler o resumo de hoje agora. Tente de novo em instantes.";

async function itensDoDia(admin: Admin, phone: string, hoje: string, letra?: string): Promise<ItemGravado[]> {
  let q = admin.from("resumo_itens").select(COLUNAS_DO_ITEM)
    .eq("phone_normalized", phone).eq("dia", hoje).eq("modo", MODO);
  if (letra) q = q.eq("letra", letra);
  const { data, error } = await q.order("ordem", { ascending: true }).limit(200);
  if (error) throw new Error(String(error.code ?? "erro"));
  return ((data as ItemGravado[] | null) ?? []);
}

async function resumoDoDia(admin: Admin, phone: string, hoje: string): Promise<
  { texto_antigo: string | null; escritorio: string | null; sem_letra: number } | null
> {
  const { data, error } = await admin.from("resumo_manha").select("texto_antigo, escritorio, sem_letra")
    .eq("phone_normalized", phone).eq("dia", hoje).eq("modo", MODO).maybeSingle();
  if (error) throw new Error(String(error.code ?? "erro"));
  return data ?? null;
}

async function anterioresDaReferencia(admin: Admin, phone: string, referencia: string, hoje: string): Promise<PassagemAnterior[]> {
  const { data, error } = await admin.from("resumo_itens").select("dia, posicao, acao, acao_em, adiado_ate")
    .eq("phone_normalized", phone).eq("modo", MODO).eq("referencia", referencia)
    .gte("dia", somarDias(hoje, -30)).lt("dia", hoje).limit(60);
  if (error) throw new Error(String(error.code ?? "erro"));
  return ((data as PassagemAnterior[] | null) ?? []);
}

function principal(itens: ItemGravado[]): ItemGravado | null {
  return itens.find((i) => i.principal) ?? itens[0] ?? null;
}

async function rpc(admin: Admin, nome: string, p: Record<string, unknown>): Promise<Record<string, unknown> | null> {
  try {
    const { data, error } = await admin.rpc(nome, { p });
    if (error) {
      console.warn(JSON.stringify({ fn: "secretario", evento: `${nome}_falhou`, codigo: String(error.code ?? "erro") }));
      return null;
    }
    return (data ?? null) as Record<string, unknown> | null;
  } catch (e) {
    console.warn(JSON.stringify({ fn: "secretario", evento: `${nome}_falhou`, codigo: (e as Error)?.name ?? "erro" }));
    return null;
  }
}

/** Executa o comando já lido (lerComandoDoSecretario). Nunca lança. */
export async function executarComandoDoSecretario(
  admin: Admin,
  cmd: ComandoDoSecretario,
  ctx: { phone: string; agora?: Date },
): Promise<ResultadoDoComando> {
  const hoje = diaBR(ctx.agora ?? new Date());
  const phone = ctx.phone;
  const resposta = (texto: string): ResultadoDoComando => ({ tipo: "resposta", texto });
  try {
    switch (cmd.comando) {
      case "lista": {
        const resumo = await resumoDoDia(admin, phone, hoje);
        if (!resumo) return resposta(TEXTO_SEM_RESUMO);
        return resposta(textoDaLista(await itensDoDia(admin, phone, hoje), cmd.filtro, hoje, { semLetra: resumo.sem_letra }));
      }
      case "escritorio": {
        const resumo = await resumoDoDia(admin, phone, hoje);
        if (!resumo) return resposta(TEXTO_SEM_RESUMO);
        // Passo 3: depois das 17:30 vale a contagem da tarde (a que o fechamento citou)
        return resposta((await escritorioDaTarde(admin, phone, hoje)) || resumo.escritorio || "Nada de papelada contado hoje cedo.");
      }
      case "tudo": {
        const resumo = await resumoDoDia(admin, phone, hoje);
        if (!resumo) return resposta(TEXTO_SEM_RESUMO);
        return resposta(resumo.texto_antigo || "O resumo completo de hoje não ficou guardado.");
      }
      case "detalhe": {
        const itens = await itensDoDia(admin, phone, hoje, cmd.letra);
        const p = principal(itens);
        if (!p) return resposta(textoNaoAchei(cmd.letra));
        return resposta(textoDoDetalhe(itens, await anterioresDaReferencia(admin, phone, p.referencia, hoje), hoje));
      }
      case "porque": {
        const p = principal(await itensDoDia(admin, phone, hoje, cmd.letra));
        return resposta(p ? textoDoPorque(p) : textoNaoAchei(cmd.letra));
      }
      case "abrir": {
        const itens = await itensDoDia(admin, phone, hoje, cmd.letra);
        const p = principal(itens);
        if (!p) return resposta(textoNaoAchei(cmd.letra));
        // o pacote dos orçamentos não enviados: a letra lista todos (sem modelo); o PDF é pedido um a um
        const pacote = ehPacote(itens);
        if (!pacote && !p.pedido) return resposta(`O item ${p.letra} não tem cartão pronto. *detalhe ${p.letra}* mostra os fatos.`);
        // "abriu" entra só no histórico do item (a métrica "virou ação"); falhar aqui não impede o cartão
        await rpc(admin, "resumo_item_acao", { phone, modo: MODO, letra: p.letra, acao: "abriu" });
        if (pacote) return resposta(textoDoPacote(itens));
        return { tipo: "pedido", texto: p.pedido!, letra: p.letra };
      }
      case "acao": {
        const r = await rpc(admin, "resumo_item_acao", { phone, modo: MODO, letra: cmd.letra, acao: cmd.acao });
        return resposta(textoDaAcao(r as Parameters<typeof textoDaAcao>[0], cmd.letra, hoje));
      }
      case "adiar": {
        const p = principal(await itensDoDia(admin, phone, hoje, cmd.letra));
        if (!p) return resposta(textoNaoAchei(cmd.letra));
        const ate = diaDoAdiamento(cmd.quando, hoje, esperaDoTipo(p.tipo), proximaSegunda, somarDias);
        if (!ate) return resposta(`Não entendi a data (vale até 90 dias à frente). Exemplo: *${cmd.letra} até 20/10*.`);
        const r = await rpc(admin, "resumo_item_acao", { phone, modo: MODO, letra: cmd.letra, acao: "adiado", ate });
        return resposta(textoDaAcao(r as Parameters<typeof textoDaAcao>[0], cmd.letra, hoje));
      }
      case "volta": {
        const r = await rpc(admin, "resumo_item_voltar", { phone, modo: MODO, letra: cmd.letra ?? "", nome: cmd.nome ?? "" });
        return resposta(textoDaVolta(r as Parameters<typeof textoDaVolta>[0], { letra: cmd.letra, nome: cmd.nome }, hoje));
      }
      // ── Passo 3: a tarde ──
      case "lote": {
        // tudo ou nada na RPC: letra que não existe hoje, repetida ou data inválida → nada é gravado
        const r = await rpc(admin, "resumo_itens_acoes", { phone, modo: MODO, acoes: cmd.itens.map((i) => acaoParaRpc(i, hoje)) });
        return resposta(textoDoLote(r as Parameters<typeof textoDoLote>[0], hoje));
      }
      case "antiga": {
        const itens = await itensDoDia(admin, phone, hoje, cmd.letra);
        if (!itens.length) return resposta(textoNaoAchei(cmd.letra));
        const antigas = itens.filter((i) => {
          const venc = i.familia === "cobranca" ? vencimentoDoFato(i.fato) : null;
          return !!venc && diasEntre(venc, hoje) >= COBRANCA_ANTIGA_DIAS;
        });
        if (!antigas.length) {
          return resposta(`O item ${cmd.letra} não tem cobrança vencida há 30 dias ou mais. *detalhe ${cmd.letra}* mostra os fatos.`);
        }
        await rpc(admin, "resumo_item_acao", { phone, modo: MODO, letra: cmd.letra, acao: "abriu" });
        return { tipo: "pedido", texto: pedidoDaCobrancaAntiga(cmd.acao, antigas), letra: cmd.letra };
      }
      case "semana": {
        const r = await rpc(admin, "resumo_semana_responder", { phone, resposta: cmd.resposta });
        // sem a pergunta da sexta aberta, "pouco"/"ajudou" é conversa: segue ao assistente como se nada fosse.
        // Erro na RPC também segue (melhor perder uma medição do que responder "não anotei" a uma conversa).
        if (!r || r.resultado === "sem_pergunta") return { tipo: "seguir" };
        return resposta(textoDaRespostaDaSemana(r as Parameters<typeof textoDaRespostaDaSemana>[0], cmd.resposta));
      }
      // ── Passo 5: o lote semanal da papelada (chave desligada = "seguir": o texto vai ao assistente como antes) ──
      case "papelada":
        return await executarPapelada(admin, cmd, { phone, agora: ctx.agora });
    }
  } catch (e) {
    console.warn(JSON.stringify({ fn: "secretario", evento: "leitura_falhou", codigo: (e as Error)?.message ?? "erro" }));
    return resposta(ERRO_DE_LEITURA);
  }
  return resposta(ERRO_DE_LEITURA);
}
