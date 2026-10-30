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
//     (Fase 3, P3: os_registrar_andamento também conclui e entrega — a releitura diz a saída e as cobranças da condição)
//     calculado agora pelo banco (agenda_rascunho_aplicar/_desfazer/_andamento, migration 20261025100400); só o *grava*
//     do dono executa (publica, decide, desfaz, anota o dia). Rodam direto pela rede como as da Fase 1.
//   As quatro: só o admin, risco low, nenhuma recebe id nem data calculada, e ficam fora da vista (d14: só agenda_ver
//   à vista; o resto pela ferramenta_extra). Marcar uma OS num dia continua sendo schedule_service_order (com a agenda
//   automática ligada, ela também só deixa o rascunho).
//
// Fase 3 (P6, 24/10/2026; spec-fase3.md §9.4): agenda_ver ganha os focos ppc (a semana medida), diarias (as que a agenda
// lançou e as perguntas), marcos (com a OS), comissao (o mês dito em periodo; só a conta, nada é pago) e equipe (o que o
// Roberto respondeu). Nenhuma ferramenta nova: o teto de 113 do perfil do admin continua (só agenda_ver à vista).
//
// Fase 4 (P1, 25/10/2026; spec-fase4.md §7.1): fornecedor_prazo — como o dono compra de um fornecedor e em quantos dias
// chega vira RASCUNHO (agenda_rascunho_fornecedor, migration 20261027100100), com a releitura pronta; só o *grava* do dono
// grava em suppliers. Fora da vista como as outras escritas da agenda (pela ferramenta_extra, d14): o teto de 113 não muda.
//
// Fase 4 (P3, 25/10/2026; spec-fase4.md §5.3, §7.1): material_informar ganha o aviso (a nota, o Pix ou a mensagem do
// fornecedor que a agenda perguntou, como o dono disse) e a situação nao_e_de_servico (só com o aviso, sem OS nem itens).
// A ligação nota/Pix ↔ OS continua sendo do dono: a ferramenta só deixa o rascunho, e só o *grava* liga.
//
// Fase 5 (P5, 27/10/2026; spec-fase5.md §7.1): cliente_avisar — a mensagem-modelo ao cliente que o dono pede ("avisa o Nelson
// que a peça chegou"): só o tipo e a OS vão daqui; o texto e as datas são do banco (agenda_cliente_preparar, migration
// 20261028100500), que a registra ESPERANDO o *manda cliente <nome>* do dono. Nunca envia, nunca recebe texto livre, nunca
// cobrança. os_planejar ganha prometido (a data que o cliente ouviu, como o dono disse) e servico_cliente; agenda_ver ganha o
// foco clientes. Fora da vista como as outras (pela ferramenta_extra, d14): o teto de 113 não muda.
//
// Fase 6 (P8, 28/10/2026; spec-fase6.md §7): agenda_ver ganha o foco aprendizado (o que a agenda aprendeu com o que aconteceu:
// _agenda_ver_aprendizado, migration 20261029100800). Nenhuma ferramenta nova; nenhuma escreve parâmetro (mudar é decisão do
// dono pelas perguntas da agenda e pelo roteiro dos OKs).
//
// Fase 7a (P7, 30/10/2026; spec-fase7a.md §7): agenda_ver ganha o foco gestor (o que o gestor da agenda marcou ou marcaria
// sozinho e por quê: _agenda_ver_gestor, migration 20261031100600). Nenhuma ferramenta nova: *gestor, só propor*, *gestor, pode
// marcar* e *<nome> com dupla* são palavras do dono, lidas antes do modelo; o teto de 113 não muda.
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
  MODALIDADES_DO_FORNECEDOR,
  MOTIVOS_DO_ANDAMENTO,
  paraAgendaVer,
  paraAndamento,
  paraAplicar,
  paraCliente,
  paraDesfazer,
  paraDisponibilidade,
  paraFornecedor,
  paraMaterial,
  paraPlanejar,
  paraPropor,
  PRESENCAS_DO_DONO,
  resultadoDaLeitura,
  resultadoDaMensagemAoCliente,
  resultadoDaProposta,
  resultadoDoRascunho,
  SITUACOES_DA_EQUIPE,
  SITUACOES_DO_MATERIAL,
  TIPOS_DA_MENSAGEM_AO_CLIENTE,
  TURNOS,
  UNIDADES_DO_PRAZO,
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
      "como foi a semana, quanto do plano foi cumprido (foco ppc), as diárias que a agenda lançou e as perguntas de diária " +
      "(foco diarias), o que a equipe respondeu hoje e no próximo dia útil (foco equipe), os marcos de uma OS (os + foco " +
      "marcos: entrada, início, conclusão e entrega), a comissão dos técnicos de um mês (foco comissao com o mês em periodo, " +
      "como o dono disse: só a conta, nada é pago), " +
      "o que comprar e até quando, as notas que chegaram sem serviço dito, quanto tempo ele leva para comprar depois que o " +
      "cliente aprova e a pergunta da agenda ao fornecedor (foco compras; com os, a espera de peça daquela OS: da aprovação " +
      "até a compra, do fornecedor e o parado com o material na mão), como a agenda conta o prazo de cada fornecedor " +
      "(foco fornecedores), " +
      "as mensagens ao cliente: o que espera o dono, o que a agenda vai mandar, o que mandou e quem respondeu (foco " +
      "clientes; com os, só daquela OS, e o que foi dito ao cliente), " +
      "o que a agenda aprendeu com o que aconteceu (foco aprendizado: quanto as OS de cada tipo levam além do combinado, o " +
      "atraso de cada fornecedor, a capacidade do dono, a presença dele e o valor por diária, com quantas medidas; só lê, " +
      "e mudar é decisão do dono pelas perguntas da agenda), " +
      "o que o gestor da agenda marcou ou marcaria sozinho e por quê (foco gestor: pela estimativa do orçamento, o que ele " +
      "perguntou antes de marcar e o que fica de fora; só lê), " +
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
          description:
            "hoje, amanha, semana, proxima_semana ou o que o dono disse (\"segunda\", \"26/10 a 30/10\"). Sem = a semana. " +
            "No foco comissao, o mês como ele disse (\"outubro\", \"mês passado\").",
        },
        pessoa: { type: "string", description: "\"eu\" ou o nome (Roberto). Sem = o dono." },
        foco: { type: "string", enum: [...FOCOS] },
        os: OS_DITA,
        simular: {
          type: "object",
          description:
            "Serviço que ainda não existe (\"um serviço de 2 dias, eu e o Roberto\", \"se entrar um de 3 dias, quando dá?\"): " +
            "o 1º dia que cabe pelo plano de agora. Só simula: não marca nem reserva nada.",
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
      "de novo para o mesmo serviço. Não agenda OS nem cria tarefa. " +
      "\"Falei pro Flávio que é dia 3\" é prometido = \"dia 3\" (a data que o cliente OUVIU, não a do plano); \"pro " +
      "cliente, o serviço é a instalação do compressor\" é servico_cliente. Nada vai ao cliente por aqui.",
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
        prometido: {
          type: "string",
          description: "A data que o dono DISSE ao cliente, como ele disse (\"dia 3\", \"entre 4 e 8/11\", \"semana que vem\"). Nunca calcule.",
        },
        servico_cliente: {
          type: "string",
          description: "Como o cliente chama o serviço, nas palavras do dono (\"a instalação do compressor\"; até 40 letras, sem valor).",
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
      "(\"compressor\", \"painel\") ou [\"tudo\"]. Resposta a uma nota, Pix ou mensagem de fornecedor que a agenda " +
      "perguntou (\"a nota da Kamell é do Nelson, o Cerbo\", \"o Pix da Premel é do Vanderlei, já tá aqui\"): passe aviso " +
      "como ele disse, com a OS, os itens e a situação; \"não é de serviço\" é situacao nao_e_de_servico com o aviso (sem OS " +
      "nem itens). NÃO grava de fato nem cria ordem de compra ou cotação, e não liga a nota ou o Pix sozinho: devolve a " +
      "releitura, e só o *grava* do dono grava. A lista do que comprar continua sendo get_purchase_needs. Peça nova (novo) " +
      "entra na lista do que comprar, sem preço, mas não no orçamento: para cobrar, add_service_order_item.",
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
        aviso: {
          type: "string",
          description: "Só na resposta a uma pergunta da agenda: a nota, o Pix ou a mensagem como o dono disse (\"a nota da " +
            "Kamell\", \"o Pix da Premel\", \"a mensagem do Mateus\", \"a nota 812\"). Nunca o número que você inventou.",
        },
        trecho: TRECHO,
      },
      // os e itens: obrigatórios fora de nao_e_de_servico (o mapeamento recusa sem eles).
      required: ["situacao", "trecho"],
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
      "dia que já aconteceu sem trabalho (\"não veio hoje\", \"faltou ontem\") não se lança (fica sem diária; na OS do plano, é " +
      "os_registrar_andamento) e o dia trabalhado é registrar_diaria. NÃO grava de fato nem avisa ninguém: " +
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
      "montar de verdade (\"monta a semana que vem\"), deixa o plano montado, que não vale para ninguém. NÃO publica, " +
      "NÃO marca, não escolhe dia nem pessoa (quem escolhe é o sistema) e não decide qual OS atrasa: se não couber, a " +
      "pergunta volta no texto. Publicar é agenda_aplicar e o *grava* do dono; marcar uma OS num dia é " +
      "schedule_service_order. Datas e nomes como o dono disse; com fixar ou so_depois_de, trecho = as palavras dele.",
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
        trecho: { ...TRECHO, description: TRECHO.description + " Obrigatório com fixar ou so_depois_de (o banco confere nele cada dia)." },
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
      "com motivo), nao_foi (quem não foi, ou a OS não andou, com motivo), comecou (a OS começou), parou (parou por " +
      "material ou cliente), concluiu (o dono disse que o serviço terminou: concluir gera a saída e as cobranças da " +
      "condição, e a releitura diz quais) ou entregou (o barco ou o bem foi entregue ao cliente; se a OS ainda não estava " +
      "concluída, conclui junto). Concluir e entregar ficam com a data de hoje. Uma chamada por fato, com o trecho do " +
      "dono; nada sai sem o *grava* do dono. Não lança nem aprova diária (quanto pagar ao diarista é registrar_diaria), não " +
      "é a chegada dita pelo técnico (check_in_service_order) nem o check-out dele (que não conclui); update_service_order_status " +
      "não conclui.",
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
  // ── Fase 4 (P1): o prazo do fornecedor ──
  {
    name: "fornecedor_prazo",
    description:
      "Anota num RASCUNHO como o dono compra de um fornecedor e em quantos dias chega (\"a Premel eu pego no balcão\", " +
      "\"a Kamell chega em 4 dias úteis depois que sai\", \"a Toli chega em 5 dias\", \"a Kamell de SC é a mesma do ES\": " +
      "mesmo_que). Só a modalidade e os números que ele disse: nunca invente prazo nem modalidade. NÃO grava, não muda o " +
      "cadastro e não manda mensagem ao fornecedor: devolve a releitura, e só o *grava* do dono grava. O prazo de uma peça " +
      "de uma OS (\"o compressor chega dia 14\") é material_informar.",
    input_schema: {
      type: "object",
      properties: {
        fornecedor: { type: "string", description: "O fornecedor como o dono falou (\"Premel\", \"Kamell de Vila Velha\"). Nunca o id." },
        modalidade: {
          type: "string",
          enum: [...MODALIDADES_DO_FORNECEDOR],
          description: "balcao = ele pega na loja; entrega_local = entregam aqui; distribuidor_sc_pr = transportadora de SC/PR; " +
            "outro_estado; marketplace = loja pela internet; importacao = importado. Só se ele disse.",
        },
        prazo: { type: "number", description: "Os dias que o dono disse, inteiro. Sem número (\"no balcão\", \"na hora\") = não passe." },
        unidade: {
          type: "string",
          enum: [...UNIDADES_DO_PRAZO],
          description: "uteis (o padrão: \"4 dias úteis\") ou corridos (\"chega em 5 dias\", \"em 20 dias\"). Só com prazo.",
        },
        mesmo_que: {
          type: "string",
          description: "\"É a mesma de …\": o outro cadastro do mesmo fornecedor, como o dono falou. Sem modalidade nem prazo.",
        },
        trecho: TRECHO,
      },
      required: ["fornecedor", "trecho"],
    },
    risk: "low",
    roles: SO_ADMIN,
    async execute(args, ctx) {
      if (ctx.userRole !== "admin") return SO_O_ADMINISTRADOR;
      const chamada = paraFornecedor(args, contexto(ctx));
      if (!chamada.ok) return { error: chamada.error };
      return resultadoDoRascunho(await chamar(ctx, chamada), chamada.rpc);
    },
  },
  // ── Fase 5 (P5): a mensagem-modelo ao cliente (prepara, nunca envia) ──
  {
    name: "cliente_avisar",
    description:
      "Prepara a MENSAGEM-MODELO da agenda a um cliente (\"avisa o Nelson que a peça chegou\", \"manda a confirmação pro " +
      "Flávio\", \"avisa o Giancarlo que vai atrasar\"). O texto e as datas são do banco; você só escolhe a OS e o tipo. NÃO " +
      "envia: devolve o texto, e só sai quando o dono manda *manda cliente <nome>*. Texto livre ao cliente não é aqui (é a " +
      "mensagem do assistente, com a confirmação de sempre). Nunca cobrança, valor ou desconto.",
    input_schema: {
      type: "object",
      properties: {
        os: OS_DITA,
        tipo: {
          type: "string",
          enum: [...TIPOS_DA_MENSAGEM_AO_CLIENTE],
          description:
            "confirmar = a data do serviço; vespera = o aviso da véspera; acesso = a véspera perguntando onde está o bem e a " +
            "chave; material_chegou = a peça chegou; nova_data = a data firme depois do atraso; pode_atrasar = o aviso de " +
            "atraso; andamento; pronto = ficou pronto; pronto_lembrete = combinar a entrega; pos_servico = como ficou.",
        },
        firme: {
          type: "boolean",
          description: "Só em pode_atrasar e só se o dono disse: a data firme do plano no lugar da faixa (\"pode dizer que é terça\").",
        },
        trecho: TRECHO,
      },
      required: ["os", "tipo", "trecho"],
    },
    risk: "low",
    roles: SO_ADMIN,
    async execute(args, ctx) {
      if (ctx.userRole !== "admin") return SO_O_ADMINISTRADOR;
      const chamada = paraCliente(args, contexto(ctx));
      if (!chamada.ok) return { error: chamada.error };
      return resultadoDaMensagemAoCliente(await chamar(ctx, chamada));
    },
  },
];
