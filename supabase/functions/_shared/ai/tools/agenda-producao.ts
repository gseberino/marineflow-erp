// Agenda de Produção, Fase 1 (P5): as 4 ferramentas do assistente para a agenda de produção do dono.
//
//   · agenda_ver — a leitura (à vista no perfil do admin, no lugar de my_agenda; decisão d14 do dono): o que ele tem
//     que fazer, a semana, quando fica livre, o que está atrasado, o material, a rodada de perguntas, o dia de alguém
//     da equipe, uma OS, "se o cliente aprovar hoje" e o serviço hipotético. O texto sai PRONTO do banco
//     (agenda_ver, migration 20261024160500): o modelo repete, sem calcular nada.
//   · os_planejar, material_informar, equipe_disponibilidade — o que o dono conta vira RASCUNHO (migration
//     20261024160600), com a releitura pronta do banco. Nada vira fato: só o *grava* do dono (comando sem IA, P6)
//     grava. Por isso rodam direto pela rede (ESCRITAS_VERIFICADAS_DA_REDE, perfil-operacao.ts): a escrita é só do
//     rascunho, como a do completar_comprovante.
//
// Cada execute chama UMA RPC com ctx.sb (painel: o JWT do dono; WhatsApp: service role), p_autor = ctx.userId e
// p_canal pelo ctx.canal. O mapeamento argumento → parâmetro é o de _shared/agenda/rpc-das-ferramentas.ts (puro), o
// mesmo dos evals. `if (error) throw`: leitura que falha nunca vira "nada marcado".
import type { Role, ToolCtx, ToolDef } from "./registry.ts";
import {
  canalDaRpc,
  type ChamadaDaRpc,
  FOCOS,
  paraAgendaVer,
  paraDisponibilidade,
  paraMaterial,
  paraPlanejar,
  PRESENCAS_DO_DONO,
  resultadoDaLeitura,
  resultadoDoRascunho,
  SITUACOES_DA_EQUIPE,
  SITUACOES_DO_MATERIAL,
  TURNOS,
} from "../../agenda/rpc-das-ferramentas.ts";

const SO_ADMIN: Role[] = ["admin"];
const SO_O_ADMINISTRADOR = { error: "Só o administrador mexe na agenda de produção." };

/** Quem fala e por onde. */
function contexto(ctx: ToolCtx) {
  return { autor: String(ctx.userId), canal: canalDaRpc(ctx.canal) };
}

/** Uma RPC; erro do banco sobe. */
async function chamar(ctx: ToolCtx, chamada: Extract<ChamadaDaRpc, { ok: true }>): Promise<unknown> {
  const { data, error } = await ctx.sb.rpc(chamada.rpc, chamada.params);
  if (error) throw error;
  return data;
}

const TRECHO = {
  type: "string",
  description: "As palavras do dono sobre ESTE item (texto ou áudio transcrito), sem resumir. O banco confere nelas cada número e data.",
};
const OS_DITA = {
  type: "string",
  description: "Número (OS-00112, ORÇ-00119) ou o nome do cliente, como o dono falou. Nunca o id.",
};

export const agendaProducaoTools: ToolDef[] = [
  {
    name: "agenda_ver",
    description:
      "Agenda de produção do dono, lida do banco com o texto pronto: o que ele tem que fazer (foco o_que_fazer), a " +
      "semana (periodo), quando fica livre (foco livre), o que está atrasado (foco atrasos), o material (foco material), " +
      "as perguntas para montar a semana (foco aprontar), o dia de alguém da equipe (pessoa + periodo), uma OS (os), " +
      "\"se o cliente aprovar hoje, quando dá\" (os + simular_aprovacao) ou um serviço que ainda não existe (simular). " +
      "Datas, dias livres, capacidade e duração vêm SÓ daqui: repita o texto, sem calcular nem mudar número, data ou nome. " +
      "Só lê: não marca nada, não cria tarefa (create_task) nem agenda OS (schedule_service_order). O que o dono contar " +
      "(quantos dias, quem vai, peça que chegou, quem vem) vai para os_planejar, material_informar ou " +
      "equipe_disponibilidade, que só anotam um rascunho para ele conferir.",
    input_schema: {
      type: "object",
      properties: {
        periodo: {
          type: "string",
          description: "hoje, amanha, semana, proxima_semana ou o que o dono disse (\"segunda\", \"26/10 a 30/10\"). Sem = a semana.",
        },
        pessoa: { type: "string", description: "\"eu\" ou o nome (Roberto). Sem = o dono." },
        foco: { type: "string", enum: [...FOCOS] },
        os: OS_DITA,
        simular: {
          type: "object",
          description: "Serviço que ainda não existe (\"um serviço de 2 dias, eu e o Roberto\"). É projeção: não reserva nada.",
          properties: {
            dias: { type: "number", description: "Os dias que o dono disse." },
            com_quem: { type: "array", items: { type: "string" }, description: "Nomes, ou \"eu\"." },
            dono: { type: "string", enum: [...PRESENCAS_DO_DONO] },
          },
        },
        simular_aprovacao: { type: "boolean", description: "Com os: e se o cliente aprovar hoje, quando dá?" },
      },
    },
    risk: "low",
    roles: SO_ADMIN,
    async execute(args, ctx) {
      if (ctx.userRole !== "admin") return SO_O_ADMINISTRADOR;
      const chamada = paraAgendaVer(args, contexto(ctx));
      if (!chamada.ok) return { error: chamada.error };
      return resultadoDaLeitura(await chamar(ctx, chamada));
    },
  },
  {
    name: "os_planejar",
    description:
      "Anota num RASCUNHO o que o dono disse de um serviço: quantos dias, quem vai e em que turno, se ele abre e fecha, " +
      "até quando o cliente precisa, quando o barco/motorhome está fora (bem_fora) ou volta (bem_livre_em), \"não antes " +
      "de\", escopo, espera, prioridade, \"não tem peça a comprar\" (sem_material) ou \"aceito a sua estimativa\" " +
      "(aceitar_sugestao). NÃO grava de fato: devolve a releitura para o dono conferir, e só o *grava* dele grava. Passe " +
      "só números e datas que ele disse, como disse (\"dia 3\", \"terça\"), e em trecho as palavras dele. Correção = chame " +
      "de novo para o mesmo serviço. Não agenda OS nem cria tarefa.",
    input_schema: {
      type: "object",
      properties: {
        os: OS_DITA,
        dias: { type: "number", description: "Dias de serviço que o dono disse (meio dia = 0.5). Nunca estime." },
        com_quem: {
          type: "array",
          description: "Quem vai: [{pessoa: \"eu\" ou o nome, turnos: dia, manha ou tarde}].",
          items: {
            type: "object",
            properties: { pessoa: { type: "string" }, turnos: { type: "string", enum: [...TURNOS] } },
          },
        },
        dono: { type: "string", enum: [...PRESENCAS_DO_DONO], description: "\"eu abro e fecho\" = abre_e_fecha." },
        precisa_ate: { type: "string", description: "Até quando o cliente precisa, como o dono disse." },
        bem_fora: { type: "string", description: "O barco/motorhome fora (\"de 26 a 30/10\", \"até dia 3\": inclusive)." },
        bem_livre_em: { type: "string", description: "\"Só fica livre dia 3\": o dia em que volta." },
        nao_antes_de: { type: "string" },
        nao_antes_motivo: { type: "string" },
        escopo_em_aberto: { type: "string", description: "A pergunta de escopo que ficou em aberto." },
        escopo_decidido: { type: "string", description: "O que o dono decidiu (\"só a primeira parte\")." },
        congelar_ate: { type: "string", description: "Em espera até (como o dono disse)." },
        revisar_em: { type: "string" },
        prioridade: { type: "integer", enum: [1, 2, 3], description: "1 = passa na frente." },
        sem_material: { type: "boolean", description: "true = \"não tem peça a comprar\"." },
        aceitar_sugestao: { type: "boolean", description: "true = o dono aceitou a duração estimada pelo sistema." },
        trecho: TRECHO,
      },
      required: ["os", "trecho"],
    },
    risk: "low",
    roles: SO_ADMIN,
    async execute(args, ctx) {
      if (ctx.userRole !== "admin") return SO_O_ADMINISTRADOR;
      const chamada = paraPlanejar(args, contexto(ctx));
      if (!chamada.ok) return { error: chamada.error };
      return resultadoDoRascunho(await chamar(ctx, chamada), chamada.rpc);
    },
  },
  {
    name: "material_informar",
    description:
      "Anota num RASCUNHO o que o dono disse do material de uma OS: comprei; a_caminho (\"chega dia 3\": quando = \"dia " +
      "3\"); na_mao (\"chegou\", \"tá aqui\"); vou_comprar (\"compro terça na Premel\"); falta; sem_previsao; " +
      "pode_comecar_sem; dispensar; ou peça fora do orçamento (novo). Uma chamada por situação; itens = o que ele citou " +
      "(\"compressor\", \"painel\") ou [\"tudo\"]. NÃO grava de fato nem cria ordem de compra ou cotação: devolve a " +
      "releitura, e só o *grava* do dono grava. A lista do que comprar continua sendo get_purchase_needs.",
    input_schema: {
      type: "object",
      properties: {
        os: OS_DITA,
        itens: { type: "array", items: { type: "string" }, description: "As peças como o dono falou, ou [\"tudo\"] / [\"a peça\"]." },
        situacao: { type: "string", enum: [...SITUACOES_DO_MATERIAL] },
        quando: { type: "string", description: "A data como o dono disse (\"dia 14\", \"terça\", \"ontem\")." },
        fornecedor: { type: "string", description: "Onde compra/comprou, como o dono disse." },
        quantidade: { type: "number", description: "Só se o dono disse quantas chegaram (parcial)." },
        novo: { type: "boolean", description: "true = peça que não está no orçamento." },
        trecho: TRECHO,
      },
      required: ["os", "itens", "situacao", "trecho"],
    },
    risk: "low",
    roles: SO_ADMIN,
    async execute(args, ctx) {
      if (ctx.userRole !== "admin") return SO_O_ADMINISTRADOR;
      const chamada = paraMaterial(args, contexto(ctx));
      if (!chamada.ok) return { error: chamada.error };
      return resultadoDoRascunho(await chamar(ctx, chamada), chamada.rpc);
    },
  },
  {
    name: "equipe_disponibilidade",
    description:
      "Anota num RASCUNHO quem vem quando: vem, nao_vem, so_manha ou so_tarde, numa data (\"terça\") ou toda semana " +
      "(padrao = true: \"segunda a sexta\"). pessoa \"eu\" = o dono (\"fico em campo de segunda a sexta\"). NÃO grava de " +
      "fato nem avisa ninguém: devolve a releitura, e só o *grava* do dono grava.",
    input_schema: {
      type: "object",
      properties: {
        pessoa: { type: "string", description: "\"eu\" ou o nome (Roberto)." },
        situacao: { type: "string", enum: [...SITUACOES_DA_EQUIPE] },
        dias: { type: "string", description: "Como o dono disse: \"terça\", \"dia 3\" ou, com padrao, \"segunda a sexta\"." },
        padrao: { type: "boolean", description: "true = toda semana." },
        trecho: TRECHO,
      },
      required: ["pessoa", "situacao", "dias", "trecho"],
    },
    risk: "low",
    roles: SO_ADMIN,
    async execute(args, ctx) {
      if (ctx.userRole !== "admin") return SO_O_ADMINISTRADOR;
      const chamada = paraDisponibilidade(args, contexto(ctx));
      if (!chamada.ok) return { error: chamada.error };
      return resultadoDoRascunho(await chamar(ctx, chamada), chamada.rpc);
    },
  },
];
