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
// Fase 2 (P6, 24/10/2026; spec-fase2.md §12.1; decisões do dono de 23/10, Autonomia): a agenda se monta e se ajusta
// sozinha; o dono pede pela conversa, e nada do que ele pede é executado pelo modelo:
//   · agenda_propor — a simulação do motor ("e se…"; simular = true por padrão: nada é gravado). Com simular = false
//     grava só a proposta EM ABERTO (agenda_propostas e alocações em estado proposta), que não vale para ninguém;
//   · agenda_aplicar, agenda_desfazer, os_registrar_andamento — o pedido vira RASCUNHO com a releitura do efeito
//     calculado agora pelo banco (agenda_rascunho_aplicar/_desfazer/_andamento, migration 20261025100400); só o *grava*
//     do dono executa (publica, decide, desfaz, anota o dia). Rodam direto pela rede como as da Fase 1.
//   As quatro: só o admin, risco low, nenhuma recebe id nem data calculada, e ficam fora da vista (d14: só agenda_ver
//   à vista; o resto pela ferramenta_extra). Marcar uma OS num dia continua sendo schedule_service_order (com a agenda
//   automática ligada, ela também só deixa o rascunho).
//
// Cada execute chama UMA RPC com ctx.sb (painel: o JWT do dono; WhatsApp: service role), p_autor = ctx.userId e
// p_canal pelo ctx.canal. O mapeamento argumento → parâmetro é o de _shared/agenda/rpc-das-ferramentas.ts (puro), o
// mesmo dos evals. `if (error) throw`: leitura que falha nunca vira "nada marcado".
import type { Role, ToolCtx, ToolDef } from "./registry.ts";
import {
  canalDaRpc,
  type ChamadaDaRpc,
  ESCOPOS_DA_PROPOSTA,
  EVENTOS_DO_ANDAMENTO,
  FOCOS,
  LIMPAVEIS,
  MOTIVOS_DO_ANDAMENTO,
  paraAgendaVer,
  paraAndamento,
  paraAplicar,
  paraDesfazer,
  paraDisponibilidade,
  paraMaterial,
  paraPlanejar,
  paraPropor,
  PRESENCAS_DO_DONO,
  resultadoDaLeitura,
  resultadoDaProposta,
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
const LISTA_DE_OS = { type: "array", items: OS_DITA, description: "As OS como o dono falou (número ou nome). Nunca o id." };
const DIA_DITO = { type: "string", description: "O dia como o dono disse (\"quinta\", \"dia 5\", \"semana que vem\"). Nunca calcule." };

export const agendaProducaoTools: ToolDef[] = [
  {
    name: "agenda_ver",
    description:
      "Agenda de produção do dono, lida do banco com o texto pronto: o que ele tem que fazer (foco o_que_fazer), a " +
      "semana (periodo), quando fica livre (foco livre), o que está atrasado (foco atrasos), o material (foco material), " +
      "as perguntas para montar a semana (foco aprontar), o que a agenda mudou sozinha (foco mudancas), o que ela precisa " +
      "do dono (foco decisoes: as decisões numeradas, com as opções e a recomendação), o publicado dia a dia (foco plano), " +
      "o dia de alguém da equipe (pessoa + periodo), uma OS (os), " +
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
      "(aceitar_sugestao); o que ele desfaz (\"pode voltar\", \"tira da espera\", \"o cliente não tem mais prazo\") vai em " +
      "limpar. NÃO grava de fato: devolve a releitura para o dono conferir, e só o *grava* dele grava. Passe " +
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
        adiantavel_patio: {
          type: "number",
          description: "Dias que dá para adiantar no pátio, sem o barco/motorhome (\"dá para adiantar um dia no pátio\"). Só o dito.",
        },
        limpar: {
          type: "array",
          items: { type: "string", enum: [...LIMPAVEIS] },
          description:
            "O que o dono desfez: espera (\"pode voltar\", \"tira da espera\"), nao_antes (\"não tem mais data mínima\"), " +
            "prazo (\"o cliente não tem mais prazo\"), escopo (\"o escopo está resolvido\"), patio (\"no pátio não dá para adiantar nada\").",
        },
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
      "releitura, e só o *grava* do dono grava. A lista do que comprar continua sendo get_purchase_needs. Peça nova (novo) " +
      "só avisa a agenda: não entra na OS, no orçamento nem na compra; para cobrar e comprar, add_service_order_item.",
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
      "(padrao = true: \"segunda a sexta\"). pessoa \"eu\" = o dono (\"fico em campo de segunda a sexta\"). É quem VAI vir; o " +
      "dia que já aconteceu (\"não veio hoje\", \"faltou ontem\") é registrar_diaria. NÃO grava de fato nem avisa ninguém: " +
      "devolve a releitura, e só o *grava* do dono grava.",
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
  // ── Fase 2 (P6): a simulação e os pedidos do dono à agenda ──
  {
    name: "agenda_propor",
    description:
      "Simula a agenda que o sistema montaria: a semana que ele publica (escopo semana ou proxima_semana), uma OS (os) ou " +
      "o replano de algumas (replano), com o que o dono quer testar: \"e se eu tirar o Rodrigo da semana?\" (tirar), \"e se " +
      "o Lenine for na quinta?\" (fixar com quando), \"o Nelson só depois do dia 10\" (so_depois_de), \"mesmo acima da " +
      "carga\" (acima_da_carga). simular = true (o padrão) não grava nada; simular = false, só quando o dono pede para " +
      "montar de verdade (\"monta a semana que vem\"), deixa a proposta em aberto, que não vale para ninguém. NÃO publica, " +
      "NÃO marca, não escolhe dia nem pessoa (quem escolhe é o sistema) e não decide qual OS atrasa: se não couber, a " +
      "pergunta volta no texto. Publicar é agenda_aplicar e o *grava* do dono; marcar uma OS num dia é " +
      "schedule_service_order. Datas e nomes como o dono disse.",
    input_schema: {
      type: "object",
      properties: {
        escopo: { type: "string", enum: [...ESCOPOS_DA_PROPOSTA], description: "semana = proxima_semana (a que o sistema publica)." },
        os: LISTA_DE_OS,
        fixar: {
          type: "array",
          description: "O que o dono quer num dia: [{os, quando, ate, pessoa}], com o dia como ele disse.",
          items: {
            type: "object",
            properties: { os: OS_DITA, quando: DIA_DITO, ate: DIA_DITO, pessoa: { type: "string", description: "\"eu\" ou o nome." } },
          },
        },
        tirar: { ...LISTA_DE_OS, description: "As OS que saem da conta (\"e se eu tirar o Rodrigo?\"), como o dono falou." },
        so_depois_de: {
          type: "array",
          description: "\"Só depois do dia 10\": [{os, quando}].",
          items: { type: "object", properties: { os: OS_DITA, quando: DIA_DITO } },
        },
        acima_da_carga: { type: "boolean", description: "true = o dono aceita passar da carga da equipe." },
        simular: { type: "boolean", description: "Padrão true (não grava nada). false só com \"monta\"/\"prepara\" dito pelo dono." },
      },
      required: ["escopo"],
    },
    risk: "low",
    roles: SO_ADMIN,
    async execute(args, ctx) {
      if (ctx.userRole !== "admin") return SO_O_ADMINISTRADOR;
      const chamada = paraPropor(args, contexto(ctx));
      if (!chamada.ok) return { error: chamada.error };
      return resultadoDaProposta(await chamar(ctx, chamada));
    },
  },
  {
    name: "agenda_aplicar",
    description:
      "Anota num RASCUNHO um pedido do dono à agenda: publicar a proposta em aberto (\"pode publicar\", \"publica só o " +
      "Lenine e o Flávio\": proposta = \"a última\" ou o nº, os = as OS ditas) OU responder uma decisão que a agenda pediu " +
      "(decisao = o nº que agenda_ver foco decisoes mostrou, ou o nome da OS; opcao = o nº ou o nome da OS que o dono " +
      "escolheu). NÃO grava: devolve a releitura do efeito, e só o *grava* do dono publica ou decide. Nunca escolha a " +
      "opção pelo dono: sem opcao dita, a pergunta volta como está. Marcar uma OS num dia (\"marca o Lenine pra quinta\") " +
      "é schedule_service_order com quando.",
    input_schema: {
      type: "object",
      properties: {
        proposta: { type: "string", description: "\"a última\" ou o nº da proposta. Só para publicar." },
        os: { ...LISTA_DE_OS, description: "Publicar só estas OS da proposta (como o dono disse)." },
        decisao: { type: "string", description: "O nº da decisão (agenda_ver foco decisoes) ou o nome da OS." },
        opcao: { type: "string", description: "O nº da opção ou o nome da OS que o dono escolheu. Só o que ele disse." },
        trecho: TRECHO,
      },
      required: ["trecho"],
    },
    risk: "low",
    roles: SO_ADMIN,
    async execute(args, ctx) {
      if (ctx.userRole !== "admin") return SO_O_ADMINISTRADOR;
      const chamada = paraAplicar(args, contexto(ctx));
      if (!chamada.ok) return { error: chamada.error };
      return resultadoDoRascunho(await chamar(ctx, chamada), chamada.rpc);
    },
  },
  {
    name: "agenda_desfazer",
    description:
      "Anota num RASCUNHO o \"desfaz\" de uma mudança que a agenda fez sozinha (alvo = o nome do cliente, o número, " +
      "\"semana\" ou \"a última\"). NÃO desfaz: devolve a releitura (o que volta como estava), e só o *grava* do dono " +
      "desfaz. A palavra *desfaz* + nome o dono manda direto, sem você.",
    input_schema: {
      type: "object",
      properties: {
        alvo: { type: "string", description: "O nome do cliente, o número, \"semana\" ou \"a última\", como o dono disse." },
        trecho: TRECHO,
      },
      required: ["trecho"],
    },
    risk: "low",
    roles: SO_ADMIN,
    async execute(args, ctx) {
      if (ctx.userRole !== "admin") return SO_O_ADMINISTRADOR;
      const chamada = paraDesfazer(args, contexto(ctx));
      if (!chamada.ok) return { error: chamada.error };
      return resultadoDoRascunho(await chamar(ctx, chamada), chamada.rpc);
    },
  },
  {
    name: "os_registrar_andamento",
    description:
      "Anota num RASCUNHO o que aconteceu numa OS num dia do plano: trabalhou (quem trabalhou), parcial (andou em parte, " +
      "com motivo), nao_foi (quem não foi, ou a OS não andou, com motivo), comecou (a OS começou) ou parou (parou por " +
      "material ou cliente). Uma chamada por fato, com o trecho do dono. NÃO conclui nem entrega (concluir é pela tela, " +
      "botão Concluir da OS), não lança nem aprova diária (quanto pagar ao diarista é registrar_diaria) e não é a chegada " +
      "dita pelo técnico (check_in_service_order). Só o *grava* do dono grava.",
    input_schema: {
      type: "object",
      properties: {
        os: OS_DITA,
        evento: { type: "string", enum: [...EVENTOS_DO_ANDAMENTO] },
        dia: { type: "string", description: "\"hoje\", \"ontem\", \"segunda\", como o dono disse. Sem = hoje." },
        quem: { type: "array", items: { type: "string" }, description: "Os nomes (ou \"eu\") de quem o fato fala." },
        motivo: { type: "string", enum: [...MOTIVOS_DO_ANDAMENTO], description: "Obrigatório em parcial, nao_foi e parou." },
        trecho: TRECHO,
      },
      required: ["os", "evento", "trecho"],
    },
    risk: "low",
    roles: SO_ADMIN,
    async execute(args, ctx) {
      if (ctx.userRole !== "admin") return SO_O_ADMINISTRADOR;
      const chamada = paraAndamento(args, contexto(ctx));
      if (!chamada.ok) return { error: chamada.error };
      return resultadoDoRascunho(await chamar(ctx, chamada), chamada.rpc);
    },
  },
];
