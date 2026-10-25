// Agenda de Produção, Fase 1 (P5): os argumentos das 4 ferramentas da agenda → os parâmetros da RPC, e a resposta da
// RPC → o que volta ao modelo. Módulo PURO: sem Deno, sem rede, sem import — o runner dos evals (P7,
// scripts/bancada-agenda/evals, Node 24 lê .ts) usa o MESMO mapeamento que as ferramentas
// (_shared/ai/tools/agenda-producao.ts).
//
// O que este módulo garante, antes de o banco ver:
//   · nenhuma ferramenta recebe id: OS é número ou nome do cliente, pessoa é "eu" ou o nome (uuid = recusa);
//   · nenhuma data calculada: data é o que o dono disse ("dia 3", "terça", "03/11"); "2026-11-03" = recusa — o banco
//     converte (agenda_data_dita) e confere que o dito está no trecho;
//   · as três de escrita exigem o trecho (as palavras do dono): é contra ele que o banco confere número e data;
//   · enum fora da lista e tipo errado voltam como erro para o modelo corrigir (nada é chamado).
// O banco é quem decide o resto (qual OS, qual peça, se é ambíguo) e devolve o texto pronto.
//
// Fase 2 (P6, 24/10/2026; spec-fase2.md §12.1): paraPropor (agenda_propor_dito: a simulação, padrão simular = true),
// paraAplicar (publicar a proposta aberta OU responder a decisão da agenda), paraDesfazer e paraAndamento. As três
// últimas também exigem o trecho e só deixam rascunho; nenhuma escolhe dia, pessoa ou opção pelo dono (a opção da
// decisão só vai se o modelo a mandou, e o banco devolve a pergunta quando falta).
//
// Fase 4 (P1, 25/10/2026; spec-fase4.md §5.1, §7.1): paraFornecedor (agenda_rascunho_fornecedor: como o dono compra de um
// fornecedor e em quantos dias chega). Também exige o trecho (o banco confere nele o prazo) e só deixa rascunho; o
// fornecedor é o nome como o dono disse (nunca o id), e com mesmo_que (o outro cadastro do mesmo fornecedor) não vai
// modalidade nem prazo: o banco copia do outro.
//
// Fase 4 (P3, 25/10/2026; spec-fase4.md §5.3, §7.1): paraMaterial ganha o aviso (p_aviso: a nota, o Pix ou a mensagem do
// fornecedor que a agenda perguntou, como o dono disse) e a situação nao_e_de_servico (só com o aviso; a OS e os itens
// ficam de fora). Sem o aviso, os parâmetros são os da Fase 1 (p_aviso nem vai).

export type CanalDaRpc = "whatsapp" | "painel";

export interface ContextoDaRpc {
  /** app_users.id de quem fala (o dono). Pelo painel o banco usa o login e confere; pelo WhatsApp, este. */
  autor: string;
  canal: CanalDaRpc;
  /** Só evals e testes: o dia fixo ("2026-10-23"). Em produção fica de fora e o banco usa o dia de Brasília. */
  hoje?: string;
}

export type ChamadaDaRpc =
  | { ok: true; rpc: string; params: Record<string, unknown> }
  | { ok: false; error: string };

export const RPC_AGENDA_VER = "agenda_ver";
export const RPC_PLANEJAR = "agenda_rascunho_planejar";
export const RPC_MATERIAL = "agenda_rascunho_material";
export const RPC_DISPONIBILIDADE = "agenda_rascunho_disponibilidade";
// Fase 2 (P6): a simulação da agenda e os três pedidos do dono que viram rascunho (migration 20261025100400).
export const RPC_PROPOR = "agenda_propor_dito";
export const RPC_APLICAR = "agenda_rascunho_aplicar";
export const RPC_DESFAZER = "agenda_rascunho_desfazer";
export const RPC_ANDAMENTO = "agenda_rascunho_andamento";
// Fase 4 (P1): o prazo do fornecedor que o dono diz vira rascunho (migration 20261027100100).
export const RPC_FORNECEDOR = "agenda_rascunho_fornecedor";
/**
 * (Fase 4) Como o dono compra do fornecedor: as chaves de agenda_config.prazo_classe_du + importacao (o CHECK
 * suppliers_modalidade_check). balcao = pega na loja; entrega_local = entregam aqui; distribuidor_sc_pr = transportadora de
 * SC/PR; outro_estado; marketplace = loja pela internet; importacao = importado (conta em dias corridos).
 */
export const MODALIDADES_DO_FORNECEDOR = [
  "balcao", "entrega_local", "distribuidor_sc_pr", "outro_estado", "marketplace", "importacao",
] as const;
/** (Fase 4) O prazo dito: dias úteis (o padrão) ou corridos (o banco converte; o importado é sempre corridos). */
export const UNIDADES_DO_PRAZO = ["uteis", "corridos"] as const;

// (Fase 2, P5) decisoes (o que a agenda precisa do dono), mudancas (o que ela mudou sozinha) e plano (o publicado): a
// agenda_ver do banco (20261025100500) aceita, e as palavras *agenda pendências*, *o que mudou* e *agenda plano* vêm por
// aqui. O prompt que ensina os focos novos ao modelo é do P6.
/**
 * Os focos de agenda_ver. (Fase 3, P6) Mais ppc (a semana medida), diarias (as que a agenda lançou e as perguntas),
 * marcos (com a OS: entrada, início, conclusão e entrega), comissao (o resumo do mês dito em periodo; só a conta, nada é
 * pago) e equipe (o que a equipe respondeu hoje e no próximo dia útil). (Fase 4, P6) Mais compras (o que comprar e até
 * quando, as notas sem serviço dito, o tempo até comprar e a pergunta ao fornecedor; com a OS, a espera de peça dela) e
 * fornecedores (como a agenda conta o prazo de cada fornecedor). A agenda_ver do banco (20261027100600) aceita os 17.
 */
export const FOCOS = [
  "tudo", "livre", "o_que_fazer", "riscos", "material", "atrasos", "aprontar", "decisoes", "mudancas", "plano",
  "ppc", "diarias", "marcos", "comissao", "equipe", "compras", "fornecedores",
] as const;
/**
 * As situações de material_informar. (Fase 4, P3) Mais nao_e_de_servico: a nota, o Pix ou a mensagem que a agenda perguntou
 * não é material de serviço (estoque, escritório, outra coisa) — só com o aviso, sem OS nem itens.
 */
export const SITUACOES_DO_MATERIAL = [
  "comprei", "a_caminho", "na_mao", "vou_comprar", "falta", "sem_previsao", "pode_comecar_sem", "dispensar",
  "nao_e_de_servico",
] as const;
export const SITUACOES_DA_EQUIPE = ["vem", "nao_vem", "so_manha", "so_tarde"] as const;
export const TURNOS = ["dia", "manha", "tarde"] as const;
export const PRESENCAS_DO_DONO = ["abre_e_fecha", "sempre", "nunca"] as const;
/** O que o dono desfaz no serviço: espera, "não antes de", prazo do cliente, escopo em aberto e (Fase 2) o pátio. */
export const LIMPAVEIS = ["espera", "nao_antes", "prazo", "escopo", "patio"] as const;
/** (Fase 2) O que o motor monta: a semana (= a que ele publica, a seguinte), uma OS ou o replano de algumas. */
export const ESCOPOS_DA_PROPOSTA = ["semana", "proxima_semana", "os", "replano"] as const;
/**
 * (Fase 2) O que aconteceu na OS num dia do plano. (Fase 3, P3) Mais concluiu e entregou: a releitura diz a saída e as
 * cobranças da condição, e o *grava* do dono conclui e entrega pela porta (agenda_rascunho_andamento, 20261026100200).
 */
export const EVENTOS_DO_ANDAMENTO = ["trabalhou", "parcial", "nao_foi", "comecou", "parou", "concluiu", "entregou"] as const;
/** (Fase 2) O motivo, na palavra do dono (o banco traduz para o código: _agenda_motivo_dito). */
export const MOTIVOS_DO_ANDAMENTO = [
  "material", "cliente", "equipe", "anterior", "informacao", "clima", "estimativa", "imprevisto", "urgencia", "esqueci",
] as const;
/**
 * (Fase 3, P3) Os sinônimos que o modelo manda em evento: "terminou", "acabou", "finalizou", "pronto" são concluiu;
 * "entregue" é entregou (o banco aceita os mesmos). Antes eram recusados ("concluir é pela tela").
 */
export const SINONIMOS_DO_ANDAMENTO: Readonly<Record<string, (typeof EVENTOS_DO_ANDAMENTO)[number]>> = Object.freeze({
  concluida: "concluiu", concluido: "concluiu", terminou: "concluiu", acabou: "concluiu", finalizou: "concluiu",
  pronto: "concluiu", pronta: "concluiu", entregue: "entregou",
});

/** O que vai junto do resultado ao modelo. */
export const INSTRUCAO_LEITURA = "Repita o texto; pode encurtar o fim, nunca mude número, data ou nome.";
export const INSTRUCAO_LEITURA_SEM_RESPOSTA =
  "Diga isto ao dono como está (é a pergunta ou o aviso do sistema); não descreva serviço, data nem número que não estejam aqui.";
export const INSTRUCAO_RASCUNHO = "Nada foi gravado: mostre a releitura ao dono. Só o *grava* dele grava.";
export const INSTRUCAO_RASCUNHO_RECUSA =
  "Nada entrou no rascunho. Faça esta pergunta ao dono como está e, com a resposta, chame a ferramenta de novo.";
/** (Fase 2) A simulação do motor: nada mudou, e o modelo não pode dizer que marcou. */
export const INSTRUCAO_SIMULACAO =
  "É simulação: nada mudou. Repita o texto (pode encurtar o fim, nunca mude número, data ou nome) e não diga que marcou, " +
  "moveu ou publicou. Para valer, o dono pede e a releitura sai pelo agenda_aplicar.";
/** (Fase 2) A proposta em aberto (simular = false): existe, mas não vale para ninguém até o *grava* do dono. */
export const INSTRUCAO_PROPOSTA_ABERTA =
  "O plano ficou montado e ainda não vale para ninguém: repita o texto. Para publicar, o dono pede, agenda_aplicar deixa a " +
  "releitura e só o *grava* dele publica. Ao dono, diga \"o plano que eu montei\", nunca \"proposta\" (no negócio, " +
  "proposta é o orçamento).";
/** agenda_config.modo_leitura desligado: a agenda de produção sai do caminho e volta a agenda de antes. */
export const INSTRUCAO_AGENDA_DESLIGADA =
  "A agenda de produção está desligada. Para a agenda do dono (tarefas e compromissos), chame my_agenda pela ferramenta_extra e responda com ela; não fale da agenda de produção.";

/** O ctx.canal das ferramentas ("panel" | "whatsapp" | ausente) → o canal da RPC. Ausente = WhatsApp. */
export function canalDaRpc(canal?: string | null): CanalDaRpc {
  return canal === "panel" ? "painel" : "whatsapp";
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATA_CALCULADA = /^\s*\d{4}-\d{2}-\d{2}/;
const TRECHO_MAX = 1500;

/** AAAA-MM-DD (com ou sem hora) é data que o modelo calculou, não a que o dono disse. */
export function ehDataCalculada(v: unknown): boolean {
  return typeof v === "string" && DATA_CALCULADA.test(v);
}

class Recusa extends Error {}

function recusar(msg: string): never {
  throw new Recusa(msg);
}

function objeto(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : {};
}

/** Texto aparado numa linha; vazio = null. Número vira texto (o "112" da OS). */
function texto(v: unknown, campo: string, max: number): string | null {
  if (v === undefined || v === null) return null;
  if (typeof v === "number" && Number.isFinite(v)) v = String(v);
  if (typeof v !== "string") recusar(`'${campo}' tem de ser texto`);
  const t = (v as string).replace(/\s+/g, " ").trim();
  if (!t) return null;
  if (t.length > max) recusar(`'${campo}' passa de ${max} caracteres`);
  return t;
}

/** A OS como o dono falou: número ou nome. Id não. */
function referenciaDaOs(v: unknown, obrigatoria: boolean, campo = "os"): string | null {
  const t = texto(v, campo, 80);
  if (!t) {
    if (obrigatoria) recusar(`falta '${campo}': o número (OS-00112) ou o nome do cliente, como o dono falou`);
    return null;
  }
  if (UUID.test(t)) recusar(`'${campo}' é o número (OS-00112) ou o nome do cliente, não o id`);
  return t;
}

function referenciaDaPessoa(v: unknown, campo: string, obrigatoria: boolean): string | null {
  const t = texto(v, campo, 60);
  if (!t) {
    if (obrigatoria) recusar(`falta '${campo}': "eu" ou o nome (Roberto)`);
    return null;
  }
  if (UUID.test(t)) recusar(`'${campo}' é "eu" ou o nome da pessoa, não o id`);
  return t;
}

/** Data como o dono disse ("dia 3", "terça", "03/11"). AAAA-MM-DD é data calculada: volta. */
function dataDita(v: unknown, campo: string): string | null {
  const t = texto(v, campo, 60);
  if (t && DATA_CALCULADA.test(t)) {
    recusar(`'${campo}': passe a data como o dono falou ("dia 3", "terça", "03/11"), sem calcular`);
  }
  return t;
}

/** 2, "2" e o meio com vírgula ou ponto ("2,5", "2.5"). */
function numero(v: unknown, campo: string): number | null {
  if (v === undefined || v === null || v === "") return null;
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v.trim().replace(",", ".")) : NaN;
  if (!Number.isFinite(n)) recusar(`'${campo}' tem de ser número`);
  return n;
}

function booleano(v: unknown, campo: string): boolean | null {
  if (v === undefined || v === null) return null;
  if (typeof v !== "boolean") recusar(`'${campo}' tem de ser true ou false`);
  return v as boolean;
}

function umDe<T extends string>(v: unknown, campo: string, lista: readonly T[], obrigatorio: boolean): T | null {
  const t = texto(v, campo, 40);
  if (!t) {
    if (obrigatorio) recusar(`falta '${campo}' (${lista.join(", ")})`);
    return null;
  }
  if (!(lista as readonly string[]).includes(t)) recusar(`'${campo}' aceita só: ${lista.join(", ")}`);
  return t as T;
}

function trecho(v: unknown): string {
  const t = texto(v, "trecho", TRECHO_MAX);
  if (!t) recusar("falta 'trecho': copie as palavras do dono sobre este item (é contra elas que o banco confere número e data)");
  return t as string;
}

function comHoje(params: Record<string, unknown>, ctx: ContextoDaRpc): Record<string, unknown> {
  return ctx.hoje ? { ...params, p_hoje: ctx.hoje } : params;
}

function mapear(rpc: string, montar: () => Record<string, unknown>): ChamadaDaRpc {
  try {
    return { ok: true, rpc, params: montar() };
  } catch (e) {
    if (e instanceof Recusa) return { ok: false, error: `${e.message}. Nada foi chamado.` };
    throw e;
  }
}

/** agenda_ver: periodo, pessoa, foco, os, simular {dias, com_quem, dono}, simular_aprovacao. */
export function paraAgendaVer(args: unknown, ctx: ContextoDaRpc): ChamadaDaRpc {
  return mapear(RPC_AGENDA_VER, () => {
    const a = objeto(args);
    let simular: Record<string, unknown> | null = null;
    if (a.simular !== undefined && a.simular !== null) {
      if (typeof a.simular !== "object" || Array.isArray(a.simular)) recusar("'simular' tem de ser {dias, com_quem, dono}");
      const s = objeto(a.simular);
      const dias = numero(s.dias, "simular.dias");
      if (dias === null || dias <= 0 || dias > 60) recusar("'simular.dias' tem de ser os dias que o dono disse (de meio dia a 60)");
      const lista = s.com_quem === undefined || s.com_quem === null ? [] : s.com_quem;
      if (!Array.isArray(lista) || lista.length > 6) recusar("'simular.com_quem' tem de ser uma lista de nomes (ou \"eu\")");
      const comQuem = (lista as unknown[]).map((p, i) => {
        const nome = typeof p === "object" && p !== null ? (p as Record<string, unknown>).pessoa : p;
        return referenciaDaPessoa(nome, `simular.com_quem[${i}]`, true);
      });
      simular = { dias, com_quem: comQuem };
      const dono = umDe(s.dono, "simular.dono", PRESENCAS_DO_DONO, false);
      if (dono) simular.dono = dono;
    }
    const aprovacao = booleano(a.simular_aprovacao, "simular_aprovacao") ?? false;
    const periodo = dataDita(a.periodo, "periodo");
    return comHoje({
      p_autor: ctx.autor,
      p_periodo: periodo,
      p_pessoa: referenciaDaPessoa(a.pessoa, "pessoa", false),
      p_foco: umDe(a.foco, "foco", FOCOS, false),
      p_os: referenciaDaOs(a.os, aprovacao),
      p_simular: simular,
      p_simular_aprovacao: aprovacao,
    }, ctx);
  });
}

/** os_planejar → agenda_rascunho_planejar(p_dados): só os campos ditos. */
export function paraPlanejar(args: unknown, ctx: ContextoDaRpc): ChamadaDaRpc {
  return mapear(RPC_PLANEJAR, () => {
    const a = objeto(args);
    const os = referenciaDaOs(a.os, true);
    const t = trecho(a.trecho);
    const dados: Record<string, unknown> = {};
    const dias = numero(a.dias, "dias");
    if (dias !== null) dados.dias = dias;
    // Fase 2 (P4 no banco, P6 aqui): "dá para adiantar um dia no pátio" (sem o barco/motorhome). O banco confere o número
    // no trecho, como os dias.
    const patio = numero(a.adiantavel_patio, "adiantavel_patio");
    if (patio !== null) {
      if (patio <= 0 || patio > 30) recusar("'adiantavel_patio' tem de ser os dias que o dono disse (de meio dia a 30)");
      dados.adiantavel_patio = patio;
    }
    if (a.com_quem !== undefined && a.com_quem !== null) {
      if (!Array.isArray(a.com_quem) || a.com_quem.length > 8) recusar("'com_quem' tem de ser uma lista [{pessoa, turnos}]");
      dados.com_quem = (a.com_quem as unknown[]).map((p, i) => {
        const item = typeof p === "string" ? { pessoa: p } : objeto(p);
        const pessoa = referenciaDaPessoa(item.pessoa, `com_quem[${i}].pessoa`, true);
        const turnos = umDe(item.turnos, `com_quem[${i}].turnos`, TURNOS, false) ?? "dia";
        return { pessoa, turnos };
      });
    }
    const dono = umDe(a.dono, "dono", PRESENCAS_DO_DONO, false);
    if (dono) dados.dono = dono;
    for (const campo of ["precisa_ate", "bem_fora", "bem_livre_em", "nao_antes_de", "congelar_ate", "revisar_em"]) {
      const d = dataDita(a[campo], campo);
      if (d) dados[campo] = d;
    }
    for (const [campo, max] of [["nao_antes_motivo", 120], ["escopo_em_aberto", 160], ["escopo_decidido", 160]] as const) {
      const v = texto(a[campo], campo, max);
      if (v) dados[campo] = v;
    }
    const prioridade = numero(a.prioridade, "prioridade");
    if (prioridade !== null) {
      if (![1, 2, 3].includes(prioridade)) recusar("'prioridade' aceita só 1, 2 ou 3");
      dados.prioridade = prioridade;
    }
    const semMaterial = booleano(a.sem_material, "sem_material");
    if (semMaterial !== null) dados.sem_material = semMaterial;
    const aceitar = booleano(a.aceitar_sugestao, "aceitar_sugestao");
    if (aceitar) dados.aceitar_sugestao = true;
    if (a.limpar !== undefined && a.limpar !== null) {
      const bruto = typeof a.limpar === "string" ? [a.limpar] : a.limpar;
      if (!Array.isArray(bruto) || bruto.length > LIMPAVEIS.length) {
        recusar(`'limpar' tem de ser a lista do que o dono desfez (${LIMPAVEIS.join(", ")})`);
      }
      const limpar = [...new Set((bruto as unknown[]).map((x, i) => umDe(x, `limpar[${i}]`, LIMPAVEIS, true) as string))];
      if (limpar.length) dados.limpar = limpar;
    }
    if (Object.keys(dados).length === 0) {
      recusar("diga o que mudou no serviço (dias, com_quem, dono, precisa_ate, bem_fora, bem_livre_em, nao_antes_de, " +
        "escopo_em_aberto, escopo_decidido, congelar_ate, prioridade, sem_material, aceitar_sugestao, adiantavel_patio ou limpar)");
    }
    return comHoje({ p_autor: ctx.autor, p_canal: ctx.canal, p_os: os, p_dados: dados, p_trecho: t }, ctx);
  });
}

/** material_informar → agenda_rascunho_material. */
export function paraMaterial(args: unknown, ctx: ContextoDaRpc): ChamadaDaRpc {
  return mapear(RPC_MATERIAL, () => {
    const a = objeto(args);
    const situacao = umDe(a.situacao, "situacao", SITUACOES_DO_MATERIAL, true);
    // Fase 4 (P3): o aviso — a nota, o Pix ou a mensagem do fornecedor que a agenda perguntou, como o dono disse ("a nota
    // da Kamell", "o Pix da Premel"). O banco acha a pergunta; o modelo nunca passa id. "Não é de serviço"
    // (nao_e_de_servico) só existe com o aviso e dispensa a OS e os itens.
    const aviso = texto(a.aviso, "aviso", 120);
    if (situacao === "nao_e_de_servico") {
      if (!aviso) recusar("'nao_e_de_servico' precisa do 'aviso': a nota, o Pix ou a mensagem, como o dono disse (\"a nota da Correa\")");
      return comHoje({
        p_autor: ctx.autor,
        p_canal: ctx.canal,
        p_os: referenciaDaOs(a.os, false),
        p_itens: null,
        p_situacao: situacao,
        p_trecho: trecho(a.trecho),
        p_aviso: aviso,
      }, ctx);
    }
    const os = referenciaDaOs(a.os, true);
    const t = trecho(a.trecho);
    const bruto = typeof a.itens === "string" ? [a.itens] : a.itens;
    if (!Array.isArray(bruto) || bruto.length === 0 || bruto.length > 20) {
      recusar("'itens' tem de ser a lista do que o dono citou (\"compressor\", \"painel\") ou [\"tudo\"]");
    }
    const itens = (bruto as unknown[]).map((x, i) => texto(x, `itens[${i}]`, 120)).filter((x): x is string => !!x);
    if (itens.length === 0) recusar("'itens' veio vazio: diga qual material (ou \"tudo\")");
    const quantidade = numero(a.quantidade, "quantidade");
    if (quantidade !== null && quantidade <= 0) recusar("'quantidade' tem de ser maior que zero");
    return comHoje({
      p_autor: ctx.autor,
      p_canal: ctx.canal,
      p_os: os,
      p_itens: itens,
      p_situacao: situacao,
      p_quando: dataDita(a.quando, "quando"),
      p_fornecedor: texto(a.fornecedor, "fornecedor", 80),
      p_quantidade: quantidade,
      p_novo: booleano(a.novo, "novo") ?? false,
      p_trecho: t,
      // Fase 4: só quando dito — sem o aviso, a chamada é a da Fase 1 (a RPC antiga, antes da migration, continua servindo).
      ...(aviso ? { p_aviso: aviso } : {}),
    }, ctx);
  });
}

/** equipe_disponibilidade → agenda_rascunho_disponibilidade. */
export function paraDisponibilidade(args: unknown, ctx: ContextoDaRpc): ChamadaDaRpc {
  return mapear(RPC_DISPONIBILIDADE, () => {
    const a = objeto(args);
    const pessoa = referenciaDaPessoa(a.pessoa, "pessoa", true);
    const situacao = umDe(a.situacao, "situacao", SITUACOES_DA_EQUIPE, true);
    const dias = dataDita(a.dias, "dias");
    if (!dias) recusar("falta 'dias': como o dono disse (\"terça\", \"dia 3\" ou, com padrao, \"segunda a sexta\")");
    const t = trecho(a.trecho);
    return comHoje({
      p_autor: ctx.autor,
      p_canal: ctx.canal,
      p_pessoa: pessoa,
      p_situacao: situacao,
      p_dias: dias,
      p_padrao: booleano(a.padrao, "padrao") ?? false,
      p_trecho: t,
    }, ctx);
  });
}

// ── Fase 2 (P6): a simulação e os pedidos do dono ───────────────────────────────────────────────────────

/** Uma lista de referências de OS como o dono falou (texto solto vira lista de um); vazia = null. */
function listaDeOs(v: unknown, campo: string, max = 12): string[] | null {
  if (v === undefined || v === null) return null;
  const bruto = typeof v === "string" || typeof v === "number" ? [v] : v;
  if (!Array.isArray(bruto) || bruto.length > max) recusar(`'${campo}' tem de ser a lista das OS que o dono citou (número ou nome)`);
  const lista = (bruto as unknown[]).map((x, i) => referenciaDaOs(x, true, `${campo}[${i}]`)).filter((x): x is string => !!x);
  return lista.length ? [...new Set(lista)] : null;
}

/**
 * agenda_propor → agenda_propor_dito: escopo, os, fixar [{os, quando, ate, pessoa}], tirar, so_depois_de, simular e o
 * trecho. Revisão da Fase 2: com fixar ou so_depois_de o trecho é obrigatório — o banco confere nele cada dia (a proposta
 * aberta segue para o *grava*, e o dia dela não pode ser um que o modelo calculou).
 */
export function paraPropor(args: unknown, ctx: ContextoDaRpc): ChamadaDaRpc {
  return mapear(RPC_PROPOR, () => {
    const a = objeto(args);
    const escopo = umDe(a.escopo, "escopo", ESCOPOS_DA_PROPOSTA, true);
    const os = listaDeOs(a.os, "os");
    let fixar: Array<Record<string, unknown>> | null = null;
    if (a.fixar !== undefined && a.fixar !== null) {
      if (!Array.isArray(a.fixar) || a.fixar.length > 8) recusar("'fixar' tem de ser a lista [{os, quando, ate, pessoa}] do que o dono pediu");
      fixar = (a.fixar as unknown[]).map((x, i) => {
        const f = objeto(x);
        const item: Record<string, unknown> = { os: referenciaDaOs(f.os, true, `fixar[${i}].os`) };
        const quando = dataDita(f.quando, `fixar[${i}].quando`);
        if (!quando) recusar(`falta 'fixar[${i}].quando': o dia como o dono disse ("quinta", "dia 5")`);
        item.quando = quando;
        const ate = dataDita(f.ate, `fixar[${i}].ate`);
        if (ate) item.ate = ate;
        const pessoa = referenciaDaPessoa(f.pessoa, `fixar[${i}].pessoa`, false);
        if (pessoa) item.pessoa = pessoa;
        return item;
      });
      if (!fixar.length) fixar = null;
    }
    let depois: Array<Record<string, unknown>> | null = null;
    if (a.so_depois_de !== undefined && a.so_depois_de !== null) {
      if (!Array.isArray(a.so_depois_de) || a.so_depois_de.length > 8) recusar("'so_depois_de' tem de ser a lista [{os, quando}]");
      depois = (a.so_depois_de as unknown[]).map((x, i) => {
        const f = objeto(x);
        const quando = dataDita(f.quando, `so_depois_de[${i}].quando`);
        if (!quando) recusar(`falta 'so_depois_de[${i}].quando': a partir de quando, como o dono disse`);
        return { os: referenciaDaOs(f.os, true, `so_depois_de[${i}].os`), quando };
      });
      if (!depois.length) depois = null;
    }
    const tirar = listaDeOs(a.tirar, "tirar");
    if ((escopo === "os" || escopo === "replano") && !os && !fixar && !depois) {
      recusar("com escopo os ou replano, diga de qual serviço (os, fixar ou so_depois_de)");
    }
    // o dia de fixar e de "só depois de" é conferido nas palavras do dono
    const t = fixar || depois ? trecho(a.trecho) : texto(a.trecho, "trecho", TRECHO_MAX);
    return comHoje({
      p_autor: ctx.autor,
      p_canal: ctx.canal,
      p_escopo: escopo,
      p_os: os,
      p_fixar: fixar,
      p_tirar: tirar,
      p_so_depois_de: depois,
      p_acima_da_carga: booleano(a.acima_da_carga, "acima_da_carga") ?? false,
      // Padrão: simular. Só um false explícito grava a proposta (em aberto: não vale para ninguém).
      p_simular: booleano(a.simular, "simular") ?? true,
      p_trecho: t,
    }, ctx);
  });
}

/** agenda_aplicar → agenda_rascunho_aplicar: publicar (proposta, os) OU responder a decisão (decisao, opcao). */
export function paraAplicar(args: unknown, ctx: ContextoDaRpc): ChamadaDaRpc {
  return mapear(RPC_APLICAR, () => {
    const a = objeto(args);
    const proposta = texto(a.proposta, "proposta", 40);
    const decisao = texto(a.decisao, "decisao", 80);
    const opcao = texto(a.opcao, "opcao", 80);
    for (const [campo, v] of [["decisao", decisao], ["opcao", opcao], ["proposta", proposta]] as const) {
      if (v && UUID.test(v)) recusar(`'${campo}' é o número que a agenda mostrou ou o nome, não o id`);
    }
    const os = listaDeOs(a.os, "os");
    if (proposta && (decisao || opcao)) recusar("diga a proposta OU a decisão, não as duas");
    if (os && (decisao || opcao)) recusar("'os' é só para publicar parte da proposta; numa decisão, diga decisao e opcao");
    const t = trecho(a.trecho);
    return comHoje({
      p_autor: ctx.autor,
      p_canal: ctx.canal,
      p_proposta: proposta,
      p_os: os,
      p_decisao: decisao,
      p_opcao: opcao,
      p_trecho: t,
    }, ctx);
  });
}

/** agenda_desfazer → agenda_rascunho_desfazer: o alvo como o dono disse (nome, número, "semana", "a última"). */
export function paraDesfazer(args: unknown, ctx: ContextoDaRpc): ChamadaDaRpc {
  return mapear(RPC_DESFAZER, () => {
    const a = objeto(args);
    const alvo = texto(a.alvo, "alvo", 40);
    if (alvo && UUID.test(alvo)) recusar("'alvo' é o nome do cliente, o número, \"semana\" ou \"a última\", não o id");
    const t = trecho(a.trecho);
    return comHoje({ p_autor: ctx.autor, p_canal: ctx.canal, p_alvo: alvo, p_trecho: t }, ctx);
  });
}

/**
 * os_registrar_andamento → agenda_rascunho_andamento: os, evento, dia, quem, motivo. (Fase 3) concluiu e entregou também
 * (os sinônimos viram o evento: "terminou" é concluiu, "entregue" é entregou).
 */
export function paraAndamento(args: unknown, ctx: ContextoDaRpc): ChamadaDaRpc {
  return mapear(RPC_ANDAMENTO, () => {
    const a = objeto(args);
    const bruto = texto(a.evento, "evento", 40);
    const evento = umDe(bruto ? (SINONIMOS_DO_ANDAMENTO[bruto.toLowerCase()] ?? bruto) : bruto, "evento", EVENTOS_DO_ANDAMENTO, true);
    const os = referenciaDaOs(a.os, true);
    let quem: string[] | null = null;
    if (a.quem !== undefined && a.quem !== null) {
      const lista = typeof a.quem === "string" ? [a.quem] : a.quem;
      if (!Array.isArray(lista) || lista.length > 6) recusar("'quem' tem de ser a lista dos nomes (ou \"eu\")");
      quem = (lista as unknown[]).map((p, i) => referenciaDaPessoa(p, `quem[${i}]`, true) as string);
      if (!quem.length) quem = null;
    }
    const motivo = umDe(a.motivo, "motivo", MOTIVOS_DO_ANDAMENTO, false);
    const t = trecho(a.trecho);
    return comHoje({
      p_autor: ctx.autor,
      p_canal: ctx.canal,
      p_os: os,
      p_evento: evento,
      p_dia: dataDita(a.dia, "dia"),
      p_quem: quem,
      p_motivo: motivo,
      p_trecho: t,
    }, ctx);
  });
}

// ── Fase 4 (P1): o prazo do fornecedor ──────────────────────────────────────────────────────────────────

/**
 * fornecedor_prazo → agenda_rascunho_fornecedor: fornecedor (o nome como o dono disse), modalidade, prazo (dias inteiros,
 * como ele disse), unidade (uteis | corridos), mesmo_que (o outro cadastro do mesmo fornecedor) e o trecho. Com mesmo_que,
 * nem modalidade nem prazo (o banco copia do outro); sem mesmo_que, ao menos a modalidade ou o prazo.
 */
export function paraFornecedor(args: unknown, ctx: ContextoDaRpc): ChamadaDaRpc {
  return mapear(RPC_FORNECEDOR, () => {
    const a = objeto(args);
    const fornecedor = texto(a.fornecedor, "fornecedor", 80);
    if (!fornecedor) recusar("falta 'fornecedor': o nome como o dono falou (\"Premel\", \"Kamell de Vila Velha\")");
    if (UUID.test(fornecedor as string)) recusar("'fornecedor' é o nome como o dono falou, não o id");
    const mesmoQue = texto(a.mesmo_que, "mesmo_que", 80);
    if (mesmoQue && UUID.test(mesmoQue)) recusar("'mesmo_que' é o nome do outro cadastro como o dono falou, não o id");
    const modalidade = umDe(a.modalidade, "modalidade", MODALIDADES_DO_FORNECEDOR, false);
    const prazo = numero(a.prazo, "prazo");
    if (prazo !== null && (!Number.isInteger(prazo) || prazo < 0 || prazo > 120)) {
      recusar("'prazo' tem de ser os dias que o dono disse, inteiro (de 0 a 120)");
    }
    const unidade = umDe(a.unidade, "unidade", UNIDADES_DO_PRAZO, false);
    if (unidade && prazo === null) recusar("'unidade' só vai junto do 'prazo'");
    if (mesmoQue && (modalidade || prazo !== null)) {
      recusar("com 'mesmo_que' não passe modalidade nem prazo: o banco copia como o outro cadastro entrega");
    }
    if (!mesmoQue && !modalidade && prazo === null) {
      recusar("diga como o dono compra (modalidade), em quantos dias chega (prazo) ou de qual cadastro é o mesmo (mesmo_que)");
    }
    const t = trecho(a.trecho);
    return comHoje({
      p_autor: ctx.autor,
      p_canal: ctx.canal,
      p_fornecedor: fornecedor,
      p_modalidade: modalidade,
      p_prazo: prazo,
      p_unidade: unidade,
      p_mesmo_que: mesmoQue,
      p_trecho: t,
    }, ctx);
  });
}

/** As opções de uma pergunta, só em texto (o resolvedor do banco traz ids: não vão ao modelo). */
function opcoesEmTexto(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v.map((o) => {
    if (typeof o === "string") return o;
    const r = objeto(o);
    return String(r.texto ?? r.numero ?? r.nome ?? "");
  }).filter((s) => s !== "");
}

function respostaDoBanco(data: unknown, rpc: string): Record<string, unknown> {
  const r = objeto(data);
  if (typeof r.ok !== "boolean" || (typeof r.texto !== "string" && typeof r.releitura !== "string" && typeof r.pergunta !== "string")) {
    // Leitura que falha lança: nunca vira "nada marcado" nem "livre".
    throw new Error(`${rpc} respondeu sem texto`);
  }
  return r;
}

export interface ResultadoParaOModelo {
  ok: boolean;
  texto: string;
  pergunta?: string;
  opcoes?: string[];
  rota?: string;
  item?: string;
  /** agenda_config.modo_leitura desligado (só a leitura): a instrução manda o modelo à my_agenda */
  desligada?: boolean;
  instrucao: string;
}

/** A resposta de agenda_ver → o modelo: o texto pronto e a instrução; nada de `dados`. */
export function resultadoDaLeitura(data: unknown): ResultadoParaOModelo {
  const r = respostaDoBanco(data, RPC_AGENDA_VER);
  if (r.ok === false && r.desligada === true) {
    return { ok: false, texto: String(r.texto ?? ""), desligada: true, instrucao: INSTRUCAO_AGENDA_DESLIGADA };
  }
  if (r.ok === false) {
    const pergunta = typeof r.pergunta === "string" && r.pergunta ? r.pergunta : undefined;
    return {
      ok: false,
      texto: String(r.texto ?? r.pergunta ?? ""),
      ...(pergunta ? { pergunta } : {}),
      ...(opcoesEmTexto(r.opcoes).length ? { opcoes: opcoesEmTexto(r.opcoes) } : {}),
      instrucao: INSTRUCAO_LEITURA_SEM_RESPOSTA,
    };
  }
  return {
    ok: true,
    texto: String(r.texto ?? ""),
    ...(typeof r.rota === "string" ? { rota: r.rota } : {}),
    instrucao: INSTRUCAO_LEITURA,
  };
}

/** A resposta de uma RPC de rascunho → o modelo: a releitura (ok) ou a pergunta (nada entrou). */
export function resultadoDoRascunho(data: unknown, rpc = "rascunho"): ResultadoParaOModelo {
  const r = respostaDoBanco(data, rpc);
  if (r.ok === false) {
    const pergunta = String(r.pergunta ?? r.texto ?? "");
    return {
      ok: false,
      texto: pergunta,
      pergunta,
      ...(opcoesEmTexto(r.opcoes).length ? { opcoes: opcoesEmTexto(r.opcoes) } : {}),
      instrucao: INSTRUCAO_RASCUNHO_RECUSA,
    };
  }
  return {
    ok: true,
    texto: String(r.releitura ?? r.texto ?? ""),
    ...(typeof r.item === "string" ? { item: r.item } : {}),
    instrucao: INSTRUCAO_RASCUNHO,
  };
}

/**
 * (Fase 2) A resposta de agenda_propor_dito → o modelo: o texto do motor (o título, uma linha por OS, o "Fora:" e, na
 * simulação, "É simulação: não muda nada.") e as perguntas que ele faria, só em texto. Nada de itens, alocações nem
 * ids: o modelo repete, sem montar agenda nenhuma. Recusa (OS ambígua, data que não entendeu) = a pergunta.
 */
export function resultadoDaProposta(data: unknown): ResultadoParaOModelo & { simulacao?: boolean; perguntas?: string[] } {
  const r = respostaDoBanco(data, RPC_PROPOR);
  if (r.ok === false) {
    const pergunta = String(r.pergunta ?? r.texto ?? "");
    return {
      ok: false,
      texto: pergunta,
      pergunta,
      ...(opcoesEmTexto(r.opcoes).length ? { opcoes: opcoesEmTexto(r.opcoes) } : {}),
      instrucao: r.desligada === true || r.motivo === "desligada" ? INSTRUCAO_LEITURA_SEM_RESPOSTA : INSTRUCAO_RASCUNHO_RECUSA,
    };
  }
  const simulacao = r.simulacao !== false;
  const perguntas = (Array.isArray(r.perguntas) ? r.perguntas : [])
    .map((q) => (typeof q === "object" && q !== null ? String((q as Record<string, unknown>).texto ?? "") : ""))
    .filter((s) => s !== "");
  return {
    ok: true,
    texto: String(r.texto ?? ""),
    simulacao,
    ...(perguntas.length ? { perguntas } : {}),
    instrucao: simulacao ? INSTRUCAO_SIMULACAO : INSTRUCAO_PROPOSTA_ABERTA,
  };
}
