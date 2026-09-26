// Ferramentas do agente para a caixa de entrada, as regras e os cadastros do financeiro.
//
// O PRINCÍPIO QUE ORGANIZA OS RISCOS AQUI: ensinar é barato, executar é caro.
//
// Criar uma regra ("toda transação com Mercado Livre é peça e material") não move um
// centavo: ela muda como o sistema PROPÕE dali em diante, e desfazer é pausar. Já aprovar
// uma proposta cria lançamento contábil, mexe em saldo e pode aprovar orçamento — isso é
// irreversível na prática e continua exigindo confirmação humana.
//
// Sem essa distinção, ou o agente vira inútil (pede permissão para tudo, e a fadiga faz o
// gestor aprovar no automático) ou vira perigoso (lança dinheiro sozinho). O critério é o
// mesmo que a literatura de agentes em finanças usa: reversibilidade e alcance da escrita.

import { blockTechnician, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { regraDeFornecedorAlcanca, type FornecedorConhecido, type TransacaoOrfa } from "../../banking/proposals.ts";

/**
 * Quem pode operar o financeiro pelo agente.
 *
 * NÃO usar NON_TECHNICIAN_ROLES aqui: ele inclui seller e external_seller, e a RLS destas
 * tabelas exige `is_admin_or_financial`. O vendedor veria a ferramenta na lista, o modelo
 * tentaria usá-la e receberia silêncio — SELECT sob RLS devolve vazio, não erro, então o
 * agente concluiria "não há regras cadastradas" em vez de "você não tem acesso".
 */
const CARGOS_FINANCEIRO: Role[] = ["admin", "financial"];

function bloqueiaSemAcesso(ctx: ToolCtx): { error: string } | null {
  const bloqueio = blockTechnician(ctx);
  if (bloqueio) return bloqueio;
  if (!CARGOS_FINANCEIRO.includes(ctx.userRole as Role)) {
    return { error: "Apenas administrador ou financeiro podem operar esta parte do sistema." };
  }
  return null;
}

/** Categorias ativas do plano de contas — o agente não pode inventar categoria. */
async function categoriasValidas(ctx: ToolCtx, tipo: "payable" | "receivable" = "payable") {
  const { data } = await ctx.sb
    .from("financial_categories")
    .select("name, dre_group")
    .eq("type", tipo).eq("active", true);
  return (data ?? []) as { name: string; dre_group: string | null }[];
}

/**
 * Chama a finance-review com a autenticação que o canal permite.
 *
 * Pelo painel existe JWT do usuário. Pelo WhatsApp NÃO existe — o agente monta o contexto
 * com `jwt: ""` (ai-agent/index.ts), e mandar "Bearer " vazio devolve 401. Nesse caso a
 * chamada usa o segredo interno e informa QUEM está decidindo, para a aprovação continuar
 * tendo dono na trilha de auditoria.
 */
async function chamarFinanceReview(ctx: ToolCtx, body: Record<string, unknown>) {
  const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/finance-review`;
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  let corpo = body;

  if (ctx.jwt) {
    headers.Authorization = `Bearer ${ctx.jwt}`;
  } else {
    const segredo = Deno.env.get("CRON_SECRET");
    if (!segredo) {
      return { error: "Sem credencial para executar esta ação por este canal." };
    }
    headers["x-cron-secret"] = segredo;
    corpo = { ...body, acting_user_id: ctx.userId };
  }

  const res = await fetch(url, { method: "POST", headers, body: JSON.stringify(corpo) });
  const dados = await res.json().catch(() => ({}));
  if (!res.ok) {
    return { error: dados?.detail || dados?.error || `finance-review respondeu ${res.status}` };
  }
  return dados;
}

/**
 * Quantas transações do extrato esta regra alcança.
 *
 * Regra que não pega nada nasce calada e assim permanece: o gestor acha que ensinou o
 * sistema, a fila continua igual, e não há erro em lugar nenhum para investigar. Foi o que
 * aconteceu com uma regra por NOME criada como "POSTO PAULINHO" enquanto o extrato escreve
 * "POSTO PAULINHO NAVEGANTES BRA" — a comparação por nome é do nome inteiro, então ela
 * nunca valeria para nada.
 *
 * `alcanca_por_trecho` existe para dar o diagnóstico junto do sintoma: quando o alvo não
 * casa como está mas apareceria como pedaço de texto, o problema é o TIPO da regra, não a
 * grafia — e a resposta pode dizer isso em vez de deixar o usuário adivinhando.
 */
/**
 * Todos os fornecedores, em páginas: o PostgREST corta em 1.000 linhas sem avisar, e um
 * .limit(5000) passaria a "não achar" fornecedor quando o cadastro crescer.
 */
async function lerFornecedores(ctx: ToolCtx): Promise<Array<{ id: string; name: string; trade_name: string | null; cnpj_cpf: string | null }>> {
  const todos: Array<{ id: string; name: string; trade_name: string | null; cnpj_cpf: string | null }> = [];
  for (let de = 0; de < 50000; de += 1000) {
    const { data, error } = await ctx.sb.from("suppliers").select("id, name, trade_name, cnpj_cpf").order("id").range(de, de + 999);
    if (error) break;
    const pagina = (data ?? []) as typeof todos;
    todos.push(...pagina);
    if (pagina.length < 1000) break;
  }
  return todos;
}

async function alcanceDaRegra(
  ctx: ToolCtx,
  tipo: string,
  valor: string,
): Promise<{ alcanca: number; alcanca_por_trecho?: number }> {
  const base = () => ctx.sb
    .from("bank_transactions")
    .select("id", { count: "exact", head: true })
    .eq("transaction_type", "debit");

  const escapado = valor.replace(/[%_]/g, "");
  const porTrecho = await base()
    .or(`description.ilike.%${escapado}%,counterparty_name.ilike.%${escapado}%`);
  const trecho = porTrecho.count ?? 0;

  if (tipo === "text") return { alcanca: trecho };

  if (tipo === "counterparty") {
    const exato = await base().ilike("counterparty_name", escapado);
    return { alcanca: exato.count ?? 0, alcanca_por_trecho: trecho };
  }

  if (tipo === "document") {
    const digitos = valor.replace(/\D/g, "");
    const r = await base().eq("counterparty_document", digitos);
    return { alcanca: r.count ?? 0 };
  }

  // Fornecedor: conta com as MESMAS provas do motor (documento, mesmo nome, nome cortado
  // provado, mesma empresa) — decisão do dono de 26/09/2026. As candidatas vêm do banco por
  // documento ou pela primeira palavra do nome; quem decide se a regra alcança é o motor.
  // Todas as saídas passam pelo motor (são ~2 mil): um pré-filtro por palavra deixava de fora
  // o que o motor reconhece (nome com a 1ª palavra curta, fantasia diferente da razão social).
  const fornecedores = (await lerFornecedores(ctx)) as FornecedorConhecido[];
  if (!fornecedores.some((x) => x.id === valor)) return { alcanca: 0 };
  let alcanca = 0;
  for (let de = 0; de < 20000; de += 1000) {
    const { data: pagina, error } = await ctx.sb.from("bank_transactions")
      .select("id, transaction_date, description, amount, transaction_type, counterparty_name, counterparty_document, source_type")
      .eq("transaction_type", "debit").order("id").range(de, de + 999);
    if (error) break;
    const linhas = (pagina ?? []) as TransacaoOrfa[];
    alcanca += linhas.filter((tx) => regraDeFornecedorAlcanca({ ...tx, amount: Number(tx.amount) }, valor, fornecedores)).length;
    if (linhas.length < 1000) break;
  }
  return { alcanca };
}

/**
 * O fornecedor que o usuário disse, pelo nome IGUAL ao do cadastro (razão social ou fantasia,
 * sem acento, caixa e sufixo societário) ou pelo id. Um só parecido NÃO é aceito calado:
 * vira pergunta com o nome por extenso ("é FERNANDO NUNES FACHINI EPP?") — decisão do dono de
 * 26/09/2026: nome diferente só por escolha dele.
 */
type FornecedorDaLista = { id: string; name: string; trade_name: string | null; cnpj_cpf: string | null };

/** A mesma forma comparável do motor: sem parênteses, acento, caixa, pontuação e sufixo. */
function limpaNome(s: string): string {
  return String(s ?? "").replace(/\([^)]*\)/g, " ").normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase()
    .replace(/[^A-Z0-9 ]/g, " ").replace(/\b(LTDA|ME|EPP|EIRELI|SA|S A|CIA)\b/g, " ").replace(/\s+/g, " ").trim();
}

/** A empresa do cadastro: raiz do CNPJ (matriz e filiais), ou o próprio cadastro sem CNPJ. */
function empresaDoCadastro(f: FornecedorDaLista): string {
  let d = String(f.cnpj_cpf ?? "").replace(/\D/g, "");
  if (d.length === 13) d = d.padStart(14, "0");
  return d.length === 14 ? `raiz:${d.slice(0, 8)}` : `id:${f.id}`;
}

/** Entre cadastros da mesma empresa, sempre o mesmo: o de menor CNPJ (a matriz), como no motor. */
function representanteDa(lista: FornecedorDaLista[]): FornecedorDaLista {
  return [...lista].sort((a, b) => String(a.cnpj_cpf ?? "").replace(/\D/g, "").padStart(14, "0")
    .localeCompare(String(b.cnpj_cpf ?? "").replace(/\D/g, "").padStart(14, "0")) || a.id.localeCompare(b.id))[0];
}

/**
 * O fornecedor que o usuário disse, pelo nome IGUAL ao do cadastro (razão social ou fantasia,
 * sem acento, caixa, sufixo societário e parênteses) ou pelo id. Um só parecido NÃO é aceito
 * calado: vira pergunta com o nome por extenso — decisão do dono de 26/09/2026: nome
 * diferente só por escolha dele.
 *
 * Compara em memória (são ~530 cadastros): o ilike do banco diferencia acento, e a
 * transcrição do áudio sempre acentua — "Kamell Comércio Global" não achava nada. Cadastros
 * da mesma empresa (matriz e filial) contam como um só, o mesmo que o motor escolhe.
 */
export async function resolverFornecedorDito(
  ctx: ToolCtx,
  dito: string,
): Promise<{ id: string; nome: string } | { error: string; opcoes?: Array<{ id: string; nome: string; cnpj_cpf: string | null }>; dica?: string }> {
  const d = String(dito ?? "").trim();
  if (/^[0-9a-f-]{36}$/i.test(d)) {
    const { data } = await ctx.sb.from("suppliers").select("id, name").eq("id", d).maybeSingle();
    return data ? { id: (data as any).id, nome: (data as any).name } : { error: "Fornecedor não encontrado." };
  }
  const alvo = limpaNome(d);
  if (!alvo) return { error: "Qual fornecedor?" };
  const todos = (await lerFornecedores(ctx)) as FornecedorDaLista[];
  const opcao = (f: FornecedorDaLista) => ({ id: f.id, nome: f.name, cnpj_cpf: f.cnpj_cpf ?? null });

  const iguais = todos.filter((f) => limpaNome(f.name) === alvo || (!!f.trade_name && limpaNome(f.trade_name) === alvo));
  const empresas = new Map<string, FornecedorDaLista[]>();
  for (const f of iguais) empresas.set(empresaDoCadastro(f), [...(empresas.get(empresaDoCadastro(f)) ?? []), f]);
  if (empresas.size === 1) {
    const r = representanteDa([...empresas.values()][0]);
    return { id: r.id, nome: r.name };
  }
  if (empresas.size > 1) {
    return {
      error: `"${d}" é o nome de mais de uma empresa cadastrada. Pergunte ao usuário qual é e repita com o id da opção escolhida.`,
      opcoes: [...empresas.values()].map((l) => opcao(representanteDa(l))),
    };
  }
  // Nenhum igual: os que CONTÊM o nome dito viram pergunta, nunca escolha.
  const parecidos = todos.filter((f) => limpaNome(f.name).includes(alvo) || (!!f.trade_name && limpaNome(f.trade_name).includes(alvo)));
  if (parecidos.length > 0) {
    return {
      error: parecidos.length === 1
        ? `O cadastro parecido é "${parecidos[0].name}". Pergunte ao usuário se é este; se for, repita com o id dele.`
        : `"${d}" não é o nome exato de um fornecedor. Pergunte ao usuário qual é e repita com o id da opção escolhida.`,
      opcoes: parecidos.slice(0, 8).map(opcao),
    };
  }
  return {
    error: `Nenhum fornecedor cadastrado com "${d}".`,
    dica: "Confira o nome, ou crie a regra por 'texto' usando um trecho do histórico do extrato.",
  };
}

export const financeRulesTools: ToolDef[] = [
  // ── ENSINAR: muda o que o sistema propõe, não o que ele já lançou ──────────────
  {
    name: "criar_regra_financeira",
    description:
      "Ensina o sistema a classificar despesas automaticamente. Use quando o usuário disser algo como " +
      "'toda transação com Mercado Livre é peças e materiais', 'pagamentos para Fulano são sempre pró-labore' " +
      "ou 'despesas do fornecedor X vão para categoria Y'. Ao criar, a regra também " +
      "reclassifica as propostas que já estão na fila aguardando decisão. Não altera " +
      "lançamentos já feitos.",
    input_schema: {
      type: "object",
      properties: {
        reconhecer_por: {
          type: "string",
          enum: ["texto", "fornecedor", "documento", "nome_de_quem_recebe"],
          description:
            "texto = trecho que aparece no histórico do extrato (ex: MERCADOLIVRE) — é o mais comum. " +
            "fornecedor = NOME de fornecedor cadastrado, igual ao do cadastro (vale só para o que o banco escreve com o " +
            "MESMO nome ou o mesmo CNPJ). Para a grafia do cartão ('PREMEL - ITAJAI'), use texto + fornecedor_da_regra. " +
            "documento = CNPJ/CPF. nome_de_quem_recebe = nome exato da contraparte no extrato.",
        },
        valor_de_busca: {
          type: "string",
          description:
            "O trecho, nome do fornecedor, documento ou nome procurado. " +
            "Com reconhecer_por='texto', VÁRIOS trechos podem vir separados por vírgula e " +
            "cada um vira uma regra — use isso quando o usuário listar sinônimos e " +
            "abreviações para a mesma categoria (ex: 'PANIFIC, PADAR, CONFEIT'). " +
            "O trecho casa em qualquer parte do histórico, inclusive colado a outras " +
            "letras: 'CONFEIT' pega 'LMGCONFEITARIA'. Prefira o radical curto e sem " +
            "acento, que cobre as variações de uma vez.",
        },
        categoria: { type: "string", description: "Categoria do plano de contas a aplicar." },
        substituir_regra_existente: {
          type: "boolean",
          description: "Só com reconhecer_por='fornecedor', quando a ferramenta disser que já há regra para a empresa e o usuário confirmar a troca: pausa a antiga e cria a nova.",
        },
        fornecedor_da_regra: {
          type: "string",
          description: "Só com reconhecer_por='texto': o fornecedor cadastrado (nome igual ao do cadastro) a quem a despesa pertence.",
        },
        valor_minimo: { type: "number", description: "Opcional: só vale acima deste valor." },
        valor_maximo: { type: "number", description: "Opcional: só vale até este valor." },
        lancar_sozinha: {
          type: "boolean",
          description:
            "false (padrão) = a despesa fica na fila já classificada, aguardando o OK do gestor. " +
            "true = a despesa é lançada automaticamente. Só use true se o usuário pedir explicitamente.",
        },
      },
      required: ["reconhecer_por", "valor_de_busca", "categoria"],
    },
    // Média, não alta: a regra não move dinheiro e desfazer é pausá-la. Mas escreve
    // configuração que afeta lançamentos futuros, então passa pela confirmação.
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;

      const cats = await categoriasValidas(ctx);
      const cat = cats.find((c) => c.name.toLowerCase() === String(args.categoria).toLowerCase());
      if (!cat) {
        return {
          error: `A categoria "${args.categoria}" não existe no plano de contas.`,
          categorias_disponiveis: cats.map((c) => c.name),
          dica: "Use criar_categoria_de_despesa antes, ou escolha uma da lista.",
        };
      }

      const tipoMap: Record<string, string> = {
        texto: "text",
        fornecedor: "supplier",
        documento: "document",
        nome_de_quem_recebe: "counterparty",
      };
      const tipo = tipoMap[String(args.reconhecer_por)];
      let alvo = String(args.valor_de_busca).trim();

      // Regra por fornecedor guarda o ID, mas quem fala diz o NOME — e o agente não tem
      // como adivinhar um uuid. Resolver aqui evita a regra nascer apontando para um
      // fornecedor que não existe, que só apareceria como "regra que nunca aplica".
      let fornecedorNome: string | null = null;
      /** Regras da mesma empresa que a nova substitui — pausadas só DEPOIS de a nova existir. */
      let aSubstituir: string[] = [];
      if (tipo === "supplier") {
        const r = await resolverFornecedorDito(ctx, alvo);
        if ("error" in r) return r;
        alvo = r.id;
        fornecedorNome = r.nome;
        // Já existe regra ativa para esta EMPRESA (o mesmo cadastro, a matriz ou uma filial)?
        // Duas regras na mesma empresa brigariam; a nova só entra trocando a antiga, e só se
        // o usuário disser (revisão de 26/09/2026).
        const cadastros = (await lerFornecedores(ctx)) as FornecedorDaLista[];
        const eu = cadastros.find((f) => f.id === alvo);
        const daEmpresa = eu ? cadastros.filter((f) => empresaDoCadastro(f) === empresaDoCadastro(eu)).map((f) => f.id) : [alvo];
        // Ativas e propostas: uma proposta na filial bateria no índice único na hora de criar.
        const { data: existentes } = await ctx.sb.from("finance_rules")
          .select("id, match_value, set_category, autonomy, direction, status")
          .eq("match_type", "supplier").in("status", ["active", "proposed"]).in("match_value", daEmpresa);
        const conflito = ((existentes ?? []) as any[]).filter((x) => x.direction === "debit" || x.direction === "any");
        if (conflito.length > 0 && !args.substituir_regra_existente) {
          return {
            error: `Já existe regra ${conflito[0].status === "proposed" ? "sugerida" : "ativa"} para esta empresa (${eu?.name ?? fornecedorNome}): `
              + `categoria "${conflito[0].set_category}"${conflito[0].autonomy === "apply" ? ", lançando sozinha" : ""}. `
              + "Pergunte ao usuário se é para TROCAR; se for, repita com substituir_regra_existente=true (a antiga é pausada, não apagada).",
          };
        }
        // Trocar a regra do MESMO cadastro é editar a que existe (o índice não deixa duas no
        // mesmo alvo); trocar a de outro cadastro da empresa é criar a nova e só então pausar.
        const mesma = conflito.find((x) => x.match_value === alvo);
        if (mesma) {
          const { error: eEdita } = await ctx.sb.from("finance_rules").update({
            set_category: cat.name, set_dre_group: cat.dre_group, set_supplier_id: alvo,
            autonomy: args.lancar_sozinha ? "apply" : "suggest",
            min_amount: args.valor_minimo ?? null, max_amount: args.valor_maximo ?? null, status: "active",
          }).eq("id", mesma.id);
          if (eEdita) return { error: `Não consegui trocar a regra: ${eEdita.message}` };
          const outras = conflito.filter((x) => x.id !== mesma.id).map((x) => x.id);
          if (outras.length > 0) await ctx.sb.from("finance_rules").update({ status: "paused" }).in("id", outras);
          const efeito = await chamarFinanceReview(ctx, { action: "reclassify" });
          return {
            ok: true, categoria: cat.name, fornecedor: fornecedorNome ?? undefined, regra_trocada: mesma.id,
            lanca_sozinha: !!args.lancar_sozinha,
            propostas_reclassificadas: Number((efeito as any)?.atualizadas ?? 0),
          };
        }
        aSubstituir = conflito.map((x) => x.id);
      }
      // Regra de TEXTO que também diz de quem é a despesa: o caminho para a grafia do cartão
      // ("PREMEL - ITAJAI" é a PREMEL MAT. ELETRICOS), que a regra de fornecedor não alcança
      // mais por nome parecido (decisão do dono, 26/09/2026).
      let fornecedorDaRegra: { id: string; nome: string } | null = null;
      if (tipo === "text" && args.fornecedor_da_regra) {
        const r = await resolverFornecedorDito(ctx, String(args.fornecedor_da_regra));
        if ("error" in r) return r;
        fornecedorDaRegra = r;
      }

      /**
       * Vários trechos numa tacada, quando a regra é por texto.
       *
       * O usuário pediu seis termos para "Alimentação de campo" — PANIFICADORA, PANIFIC,
       * PADARIA, PADAR, CONFEITARIA, CONFEIT — e o assistente criou UM. Os outros cinco
       * simplesmente não existiam, e a tela seguia sem classificar padaria nenhuma sem
       * nada indicando que faltava regra. Quem lista sinônimos está descrevendo UMA
       * intenção; obrigá-lo a repetir o pedido seis vezes é transformar a ferramenta em
       * formulário.
       */
      const alvos = tipo === "text"
        ? [...new Set(alvo.split(/[,;]/).map((t) => t.trim()).filter(Boolean))]
        : [alvo];

      const criadas: Array<Record<string, unknown>> = [];
      const recusadas: string[] = [];

      for (const valor of alvos) {
        const { data, error } = await ctx.sb
          .from("finance_rules")
          .insert({
            match_type: tipo,
            match_value: valor,
            direction: "debit",
            set_category: cat.name,
            set_dre_group: cat.dre_group,
            set_supplier_id: fornecedorDaRegra?.id ?? null,
            min_amount: args.valor_minimo ?? null,
            max_amount: args.valor_maximo ?? null,
            autonomy: args.lancar_sozinha ? "apply" : "suggest",
            origin: "user",
            status: "active",
            reasoning: "Criada pelo assistente a pedido do usuário.",
          })
          .select("id")
          .single();

        if (error) {
          recusadas.push(/uma_por_alvo|duplicate key/i.test(error.message)
            ? `${valor}: já existe uma regra ativa para este alvo`
            : `${valor}: ${error.message}`);
          continue;
        }
        criadas.push({ id: (data as any).id, alvo: valor, ...await alcanceDaRegra(ctx, tipo, valor) });
      }

      if (criadas.length === 0) {
        return { error: "Nenhuma regra criada.", detalhes: recusadas };
      }
      // Só agora, com a nova de pé, a antiga da mesma empresa sai (pausada, não apagada).
      if (aSubstituir.length > 0) {
        const { error: ePausa } = await ctx.sb.from("finance_rules").update({ status: "paused" }).in("id", aSubstituir);
        if (ePausa) recusadas.push(`A regra antiga não foi pausada (${ePausa.message}) — pause-a pela tela para as duas não brigarem`);
      }

      // A regra nova alcança de imediato o que JÁ está esperando decisão. Sem isto, quem
      // ensina "compra na Corema é ferramenta" continua corrigindo à mão as 40 compras da
      // Corema que já estavam na fila — as linhas que a regra existe para resolver.
      // Reclassificar troca a sugestão e não aprova nada, então é seguro rodar sozinho.
      const efeito = await chamarFinanceReview(ctx, { action: "reclassify" });

      // Regra que não alcança nada é regra morta, e hoje ela nascia calada. Dizer o número
      // na hora é o que separa "ensinei o sistema" de "achei que tinha ensinado".
      const mortas = criadas.filter((c) => Number(c.alcanca ?? 0) === 0);

      return {
        ok: true,
        categoria: cat.name,
        // O cadastro que a regra usa, por extenso: o "sim" foi sobre ele.
        fornecedor: fornecedorNome ?? fornecedorDaRegra?.nome ?? undefined,
        regras_criadas: criadas,
        nao_criadas: recusadas.length > 0 ? recusadas : undefined,
        lanca_sozinha: !!args.lancar_sozinha,
        propostas_reclassificadas: Number((efeito as any)?.atualizadas ?? 0),
        aviso: mortas.length > 0
          ? `Estas não alcançam nenhuma transação do extrato hoje: ${mortas.map((m) => m.alvo).join(", ")}. `
            + "Confira a grafia — e, se o alvo era um nome de estabelecimento, prefira "
            + "reconhecer_por='texto' com um trecho curto, porque a regra por nome exige o nome inteiro."
          : undefined,
      };
    },
  },

  {
    name: "listar_regras_financeiras",
    description:
      "Mostra as regras de classificação já ensinadas, quantas vezes cada uma foi aplicada e quais " +
      "estão apenas sugeridas pelo sistema aguardando aceite.",
    input_schema: {
      type: "object",
      properties: {
        situacao: { type: "string", enum: ["ativas", "sugeridas", "pausadas", "todas"] },
      },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const mapa: Record<string, string> = {
        ativas: "active", sugeridas: "proposed", pausadas: "paused",
      };
      let q = ctx.sb.from("finance_rules")
        .select("id, match_type, match_value, set_category, autonomy, status, times_applied, reasoning")
        .order("times_applied", { ascending: false }).limit(100);
      const alvo = mapa[String(args.situacao ?? "ativas")];
      if (alvo) q = q.eq("status", alvo);

      const { data, error } = await q;
      if (error) return { error: error.message };
      return { regras: data ?? [], total: (data ?? []).length };
    },
  },

  {
    name: "mudar_situacao_da_regra",
    description:
      "Ativa, pausa ou recusa uma regra. Use para 'pare de aplicar a regra do posto', " +
      "'aceite a regra que você sugeriu para a Coremma' ou 'reative aquela regra'.",
    input_schema: {
      type: "object",
      properties: {
        regra_id: { type: "string" },
        nova_situacao: { type: "string", enum: ["ativa", "pausada", "recusada"] },
      },
      required: ["regra_id", "nova_situacao"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      const mapa: Record<string, string> = { ativa: "active", pausada: "paused", recusada: "rejected" };
      const { error } = await ctx.sb.from("finance_rules")
        .update({ status: mapa[String(args.nova_situacao)] })
        .eq("id", args.regra_id);
      if (error) return { error: error.message };
      return { ok: true, situacao: args.nova_situacao };
    },
  },

  {
    name: "criar_categoria_de_despesa",
    description:
      "Cria uma categoria nova no plano de contas, quando nenhuma existente serve. " +
      "Sempre confira a lista antes com listar_categorias_financeiras — categoria duplicada " +
      "divide o mesmo gasto em duas linhas do resultado.",
    input_schema: {
      type: "object",
      properties: {
        nome: { type: "string" },
        grupo: {
          type: "string",
          enum: ["custo_direto", "despesa_operacional", "financeiro", "nao_operacional", "receita"],
          description:
            "Onde entra no resultado. custo_direto = ligado à execução do serviço. " +
            "despesa_operacional = manter a empresa aberta. financeiro = juros e tarifas. " +
            "nao_operacional = NÃO entra no resultado (fatura de cartão, transferência própria).",
        },
      },
      required: ["nome", "grupo"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      const { error } = await ctx.sb.from("financial_categories").insert({
        name: String(args.nome).trim(),
        type: args.grupo === "receita" ? "receivable" : "payable",
        dre_group: args.grupo,
        active: true,
        sort_order: 900,
      });
      if (error) {
        if (/duplicate key|nome_tipo/i.test(error.message)) {
          return { error: `A categoria "${args.nome}" já existe.` };
        }
        return { error: error.message };
      }
      return { ok: true, categoria: args.nome, grupo: args.grupo };
    },
  },

  {
    name: "listar_categorias_financeiras",
    description: "Lista as categorias do plano de contas com o grupo de cada uma no resultado.",
    input_schema: {
      type: "object",
      properties: { tipo: { type: "string", enum: ["despesa", "receita"] } },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const cats = await categoriasValidas(ctx, args.tipo === "receita" ? "receivable" : "payable");
      return { categorias: cats, total: cats.length };
    },
  },

  // ── A CAIXA DE ENTRADA: propor é barato, aprovar cria lançamento ───────────────
  {
    name: "analisar_extrato_e_propor_lancamentos",
    description:
      "Varre as movimentações do banco que ainda não viraram lançamento e monta propostas de despesa, " +
      "já classificadas pelas regras. NÃO lança nada — só enche a fila para o gestor decidir. " +
      "Use para 'analise o extrato', 'o que ainda não foi lançado'.",
    input_schema: {
      type: "object",
      properties: {
        incluir_historico_antigo: {
          type: "boolean",
          description: "false (padrão) olha os últimos 90 dias; true varre tudo.",
        },
      },
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      return await chamarFinanceReview(ctx, { action: "generate", incluir_historico: !!args.incluir_historico_antigo });
    },
  },

  {
    name: "listar_propostas_de_lancamento",
    description:
      "Mostra o que está esperando decisão na caixa de entrada financeira: o que o sistema propôs lançar, " +
      "com valor, categoria, QUEM é a contraparte (e por qual prova), o que cadastrar quando ninguém foi " +
      "reconhecido e o VÍNCULO sugerido (conta, OS, pagamento/sinal que PODE JÁ ESTAR LANÇADO). Todo vínculo " +
      "é pergunta: antes de aprovar, pergunte se é aquele (casar) ou se é para lançar novo. Idem os_sugerida e " +
      "oc_sugerida: pergunte 'é da OS X?' / 'paga a OC Y?' e passe a resposta em aprovar (os / oc).",
    input_schema: {
      type: "object",
      properties: { limite: { type: "number" } },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const { data, error } = await ctx.sb
        .from("finance_review_queue")
        .select("id, title, suggested_amount, suggested_category, suggested_date, confidence, kind, evidencia, vinculo_sugerido, suggested_service_order_id, suggested_purchase_order_id")
        .eq("status", "pending")
        .order("suggested_amount", { ascending: false })
        .limit(Number(args.limite ?? 30));
      if (error) return { error: error.message };
      const linhas = (data ?? []) as any[];
      // Número da OS e da OC sugeridas: a pergunta "é da OS 60?" precisa do número, não do id.
      const idsOs = [...new Set(linhas.map((l) => l.suggested_service_order_id).filter(Boolean))];
      const idsOc = [...new Set(linhas.map((l) => l.suggested_purchase_order_id).filter(Boolean))];
      const [{ data: oss }, { data: ocs }] = await Promise.all([
        idsOs.length ? ctx.sb.from("service_orders").select("id, service_order_number").in("id", idsOs) : Promise.resolve({ data: [] }),
        idsOc.length ? ctx.sb.from("purchase_orders").select("id, po_number").in("id", idsOc) : Promise.resolve({ data: [] }),
      ]);
      const numeroDaOs = new Map(((oss ?? []) as any[]).map((o) => [o.id, o.service_order_number]));
      const numeroDaOc = new Map(((ocs ?? []) as any[]).map((o) => [o.id, o.po_number]));
      // Resumo curto por linha: o modelo precisa do que decide, não do objeto inteiro.
      const quem = (e: any) => {
        const r = e?.fornecedor ?? e?.favorecido ?? e?.cliente;
        return r ? `${r.nome} (por ${r.por})` : null;
      };
      const opcoes = (v: any) => (v ? [v.principal, ...(v.alternativas ?? [])] : []).map((o: any) => ({
        opcao_id: o.id, o_que: o.rotulo, valor: o.valor, pontos: o.confianca, ja_lancado: !!o.jaLancado,
        converte_orcamento: !!o.converteOrcamento,
      }));
      return {
        propostas: linhas.map((p) => ({
          id: p.id, tipo: p.kind === "create_receivable" ? "entrada" : p.kind === "create_payable" ? "saida" : p.kind,
          titulo: p.title, valor: Number(p.suggested_amount ?? 0), data: p.suggested_date,
          categoria: p.suggested_category, confianca: p.confidence,
          quem: quem(p.evidencia),
          cadastrar: p.evidencia?.cadastrar ?? null,
          pode_ja_estar_lancado: opcoes(p.vinculo_sugerido).some((o: any) => o.ja_lancado),
          vinculos: opcoes(p.vinculo_sugerido),
          // OS que é do próprio vínculo já é perguntada pelo vínculo; a anotada já foi dita.
          os_sugerida: p.suggested_service_order_id
            && ![p.vinculo_sugerido?.principal, ...(p.vinculo_sugerido?.alternativas ?? [])]
              .some((o: any) => o?.ordemDeServicoId === p.suggested_service_order_id)
            ? {
              os_id: p.suggested_service_order_id,
              numero: numeroDaOs.get(p.suggested_service_order_id) ?? null,
              ja_dita_na_anotacao: p.evidencia?.anotacao?.os_id === p.suggested_service_order_id,
            }
            : null,
          oc_sugerida: p.suggested_purchase_order_id
            ? { oc_id: p.suggested_purchase_order_id, numero: numeroDaOc.get(p.suggested_purchase_order_id) ?? null }
            : null,
        })),
        total: linhas.length,
        valor_total: linhas.reduce((s, p) => s + Number(p.suggested_amount ?? 0), 0),
      };
    },
  },

  {
    name: "aprovar_propostas_de_lancamento",
    description:
      "Aprova propostas da caixa de entrada, CRIANDO os lançamentos correspondentes — ou CASANDO com o que " +
      "já existe, quando o usuário escolheu um vínculo. Linha com vínculo sugerido é recusada pelo " +
      "servidor sem a escolha: pergunte e passe em `vinculos`. Só use quando o usuário confirmar quais aprovar.",
    input_schema: {
      type: "object",
      properties: {
        ids: { type: "array", items: { type: "string" }, description: "Ids das propostas a aprovar." },
        vinculos: {
          type: "object",
          description: "Por proposta: o opcao_id escolhido (de listar_propostas_de_lancamento) para casar, ou \"nenhum\" para lançar novo.",
          additionalProperties: { type: "string" },
        },
        os: {
          type: "object",
          description: "Por proposta: o os_id que o usuário CONFIRMOU (\"é desta OS\"), ou \"nenhuma\". Sem resposta, a despesa entra sem OS.",
          additionalProperties: { type: "string" },
        },
        oc: {
          type: "object",
          description: "Por proposta: o oc_id que o usuário confirmou que este pagamento quita, ou \"nenhuma\".",
          additionalProperties: { type: "string" },
        },
      },
      required: ["ids"],
    },
    // ALTA: cria lançamento contábil. Diferente de criar regra, isto não se desfaz
    // pausando nada — vira despesa registrada com data e valor.
    risk: "high",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      const overrides: Record<string, Record<string, unknown>> = {};
      const de = (id: string) => (overrides[id] ??= {});
      for (const [id, escolha] of Object.entries((args.vinculos ?? {}) as Record<string, string>)) {
        if (!escolha) continue;
        de(id).vinculo = escolha === "nenhum" ? "nenhum" : { id: String(escolha) };
      }
      // "É desta OS?" / "Paga esta OC?" respondidos pelo usuário (decisão do dono, 26/09/2026).
      const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      for (const [campo, mapa] of [["os", args.os], ["oc", args.oc]] as const) {
        for (const [id, v] of Object.entries((mapa ?? {}) as Record<string, string>)) {
          if (!v) continue;
          if (!/^nenhum/i.test(v) && !UUID.test(String(v))) {
            return { error: `Em ${campo}, use o ${campo}_id de listar_propostas_de_lancamento (não o número) ou "nenhuma".` };
          }
          const valor = /^nenhum/i.test(v) ? null : String(v);
          if (campo === "os") de(id).serviceOrderId = valor; else de(id).purchaseOrderId = valor;
        }
      }
      return await chamarFinanceReview(ctx, { action: "approve", ids: args.ids, overrides });
    },
  },

  {
    name: "recusar_propostas_de_lancamento",
    description: "Descarta propostas da caixa de entrada sem criar lançamento nenhum.",
    input_schema: {
      type: "object",
      properties: {
        ids: { type: "array", items: { type: "string" } },
        motivo: { type: "string" },
      },
      required: ["ids"],
    },
    // Baixa: recusar não cria nem apaga nada — a transação volta a ficar pendente.
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      return await chamarFinanceReview(ctx, { action: "reject", ids: args.ids, note: args.motivo ?? null });
    },
  },

  // A edge finance-review já sabe reclassificar, classificar por IA, sugerir regras e desfazer
  // — só faltava o agente poder pedir. Nenhuma destas cria lançamento.
  {
    name: "reclassificar_propostas_de_lancamento",
    description:
      "Reaplica as regras financeiras vigentes às propostas ainda pendentes da caixa de entrada " +
      "(categoria/favorecido). Use depois de criar ou mudar uma regra. Não lança nada.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(_args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      return await chamarFinanceReview(ctx, { action: "reclassify" });
    },
  },

  {
    name: "classificar_propostas_com_ia",
    description:
      "Pede à IA uma categoria para as propostas pendentes que as regras não classificaram, usando o " +
      "plano de contas e as decisões anteriores do gestor como exemplo. Só sugere (confiança limitada a 80); " +
      "nunca aprova. Custa uma chamada de modelo.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(_args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      return await chamarFinanceReview(ctx, { action: "classify_ai" });
    },
  },

  {
    name: "sugerir_regras_financeiras",
    description:
      "Olha os lançamentos já decididos pelo gestor e propõe regras de categoria para o que se repete " +
      "(mínimo 3 casos, sem divergência). As regras nascem como 'proposta' e só valem depois de aceitas.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(_args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      return await chamarFinanceReview(ctx, { action: "suggest_rules" });
    },
  },

  {
    name: "desfazer_propostas_ignoradas",
    description:
      "Volta para a fila propostas que foram recusadas/ignoradas por engano (e desfaz o lançamento que o " +
      "motor tiver criado para elas, se houver). Use quando o usuário disser que recusou sem querer.",
    input_schema: {
      type: "object",
      properties: { ids: { type: "array", items: { type: "string" }, description: "Ids das propostas." } },
      required: ["ids"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      return await chamarFinanceReview(ctx, { action: "undismiss", ids: args.ids });
    },
  },

  // ── CADASTRAR QUEM O EXTRATO TROUXE ─────────────────────────────────────────────
  // A IA escolhe a LINHA; o sistema preenche o resto: documento e nome do extrato, dados da
  // Receita quando é CNPJ, categoria pela atividade, e toda linha com o mesmo documento passa
  // a apontar para o cadastro. Não duplica: documento já cadastrado devolve o existente.
  {
    name: "cadastrar_contraparte_do_extrato",
    description:
      "Cadastra o fornecedor, favorecido ou cliente de uma linha do Extrato que ninguém reconheceu " +
      "(listar_propostas_de_lancamento mostra 'cadastrar'). Informe só a proposta; o sistema busca o " +
      "documento, os dados da Receita (CNPJ) e a categoria. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        proposta_id: { type: "string", description: "Id da proposta (de listar_propostas_de_lancamento)." },
        tipo: { type: "string", enum: ["fornecedor", "favorecido", "cliente"], description: "Só se o usuário disser outro tipo que o sugerido." },
        tipo_de_favorecido: { type: "string", enum: ["socio", "funcionario", "diarista", "prestador", "comissionado"] },
        nome: { type: "string", description: "Só se o usuário corrigir o nome." },
      },
      required: ["proposta_id"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      const { data: p } = await ctx.admin.from("finance_review_queue")
        .select("id, kind, suggested_category, evidencia, bank_transactions!finance_review_queue_bank_transaction_id_fkey(counterparty_name, counterparty_document, description)")
        .eq("id", String(args.proposta_id)).maybeSingle();
      if (!p) return { error: "Proposta não encontrada." };
      const sugestao = (p as any).evidencia?.cadastrar ?? null;
      const tx = (p as any).bank_transactions ?? {};
      const documento = String(sugestao?.documento ?? tx.counterparty_document ?? "").replace(/\D/g, "") || null;
      const tipo = String(args.tipo ?? sugestao?.tipo ?? ((p as any).kind === "create_receivable" ? "cliente" : documento?.length === 14 ? "fornecedor" : "favorecido"));

      let receita: any = null;
      if (documento && documento.length === 14) {
        const r = await chamarFinanceReview(ctx, { action: "consult_document", documento });
        receita = (r as any)?.dados ?? null;
      }
      const nome = String(args.nome ?? receita?.razao_social ?? sugestao?.nome ?? tx.counterparty_name ?? "").trim();
      if (!nome) return { error: "O extrato não traz o nome. Pergunte ao usuário como cadastrar." };
      const categoriaDaLinha = (p as any).suggested_category && (p as any).suggested_category !== "Outras despesas"
        ? (p as any).suggested_category : null;

      const { data, error } = await ctx.sb.rpc("cadastrar_contraparte", {
        p_tipo: tipo,
        p_dados: {
          documento, nome, nome_fantasia: receita?.nome_fantasia ?? null,
          tipo_de_favorecido: tipo === "favorecido" ? (args.tipo_de_favorecido ?? "prestador") : null,
          categoria: tipo === "cliente" ? null : (receita?.categoria_sugerida ?? categoriaDaLinha),
          telefone: receita?.telefone ?? null, email: receita?.email ?? null,
          cep: receita?.cep ?? null, logradouro: receita?.logradouro ?? null, numero: receita?.numero ?? null,
          complemento: receita?.complemento ?? null, bairro: receita?.bairro ?? null,
          cidade: receita?.cidade ?? null, uf: receita?.uf ?? null,
          observacao: receita?.cnae_descricao ? `Atividade na Receita: ${receita.cnae_descricao}` : "Cadastrado pelo assistente a partir do extrato",
        },
        p_autor: ctx.userId || null,
      });
      if (error) return { error: error.message.replace(/^(P0001|42501|23514):\s*/, "") };
      return { ...(data as Record<string, unknown>), situacao_na_receita: receita?.situacao ?? null };
    },
  },

  // ── CADASTRO DE FAVORECIDOS ───────────────────────────────────────────────────
  {
    name: "cadastrar_favorecido",
    description:
      "Cadastra quem recebe dinheiro sem ser fornecedor: sócio, funcionário, diarista, prestador ou " +
      "comissionado. Use quando o usuário disser 'cadastre o Fulano como diarista' ou ao lançar uma " +
      "despesa de pró-labore para alguém que ainda não existe.",
    input_schema: {
      type: "object",
      properties: {
        nome: { type: "string" },
        tipo: { type: "string", enum: ["socio", "funcionario", "diarista", "prestador", "comissionado"] },
        documento: { type: "string", description: "CPF ou CNPJ, só números." },
        chave_pix: { type: "string" },
        percentual_comissao: { type: "number", description: "Só para comissionado." },
      },
      required: ["nome", "tipo"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = bloqueiaSemAcesso(ctx);
      if (bloqueio) return bloqueio;
      const { data, error } = await ctx.sb.from("payees").insert({
        name: String(args.nome).trim(),
        kind: args.tipo,
        document: args.documento ? String(args.documento).replace(/\D/g, "") : null,
        pix_key: args.chave_pix ?? null,
        commission_percentage: args.tipo === "comissionado" ? args.percentual_comissao ?? null : null,
        active: true,
      }).select("id").single();
      if (error) {
        if (/documento_unico|duplicate key/i.test(error.message)) {
          return { error: "Já existe um favorecido com este CPF/CNPJ." };
        }
        return { error: error.message };
      }
      return { ok: true, id: (data as any).id, nome: args.nome, tipo: args.tipo };
    },
  },

  {
    name: "listar_favorecidos",
    description: "Lista sócios, funcionários, diaristas, prestadores e comissionados cadastrados.",
    input_schema: {
      type: "object",
      properties: {
        tipo: { type: "string", enum: ["socio", "funcionario", "diarista", "prestador", "comissionado"] },
      },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      let q = ctx.sb.from("payees")
        .select("id, name, kind, document, pix_key, commission_percentage")
        .eq("active", true).order("name");
      if (args.tipo) q = q.eq("kind", args.tipo);
      const { data, error } = await q;
      if (error) return { error: error.message };
      return { favorecidos: data ?? [], total: (data ?? []).length };
    },
  },

  // ── LEITURA DO RESULTADO ──────────────────────────────────────────────────────
  {
    name: "resultado_do_periodo",
    description:
      "Monta o resultado (DRE) de um ano ou mês: receita, custo dos serviços, despesas operacionais, " +
      "resultado financeiro e o que ficou fora do resultado. Use para 'como fechou julho', " +
      "'quanto gastamos com peças este ano', 'estamos no lucro?'.",
    input_schema: {
      type: "object",
      properties: {
        ano: { type: "number" },
        mes: { type: "number", description: "1 a 12. Omita para o ano inteiro." },
      },
      required: ["ano"],
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const ano = Number(args.ano);
      const mes = args.mes ? Number(args.mes) : null;
      if (mes !== null && (mes < 1 || mes > 12)) {
        return { error: "Mês precisa estar entre 1 e 12." };
      }

      // Último dia do mês calculado em UTC. `new Date(ano, mes, 0).toISOString()` usa o
      // fuso LOCAL para montar e converte para UTC ao serializar — num servidor a leste de
      // Greenwich isso volta um dia e o último dia do mês fica de fora do relatório.
      const ultimoDia = mes ? new Date(Date.UTC(ano, mes, 0)).getUTCDate() : 31;
      const de = mes ? `${ano}-${String(mes).padStart(2, "0")}-01` : `${ano}-01-01`;
      const ate = mes ? `${ano}-${String(mes).padStart(2, "0")}-${ultimoDia}` : `${ano}-12-31`;

      const [cats, pays, recs] = await Promise.all([
        ctx.sb.from("financial_categories").select("name, type, dre_group"),
        // Despesa cancelada não entra no resultado — mesma regra do DRE da tela.
        ctx.sb.from("payables").select("amount, expense_category").neq("status", "cancelled").gte("issue_date", de).lte("issue_date", ate),
        ctx.sb.from("receivables").select("amount, category, status").gte("issue_date", de).lte("issue_date", ate),
      ]);

      const grupoDe = new Map<string, string>();
      for (const c of (cats.data ?? []) as any[]) {
        if (c.dre_group) grupoDe.set(`${c.type}:${c.name}`, c.dre_group);
      }

      const total = (g: string) =>
        ((pays.data ?? []) as any[])
          .filter((p) => grupoDe.get(`payable:${p.expense_category}`) === g)
          .reduce((s, p) => s + Number(p.amount), 0);

      const receita = ((recs.data ?? []) as any[])
        .filter((r) => r.status !== "cancelled")
        .reduce((s, r) => s + Number(r.amount), 0);

      const custo = total("custo_direto");
      const despesa = total("despesa_operacional");
      const financeiro = total("financeiro");
      const foraDoResultado = total("nao_operacional");

      // Este número engana quando a receita ainda não foi conciliada — a caixa de entrada
      // lança despesa sozinha e receita nunca, então o resultado nasce pessimista.
      const { count: entradasPendentes } = await ctx.sb
        .from("bank_transactions")
        .select("id", { count: "exact", head: true })
        .eq("transaction_type", "credit").eq("reconciled", false).eq("source_type", "bank")
        .gte("transaction_date", de).lte("transaction_date", ate);

      return {
        periodo: mes ? `${String(mes).padStart(2, "0")}/${ano}` : String(ano),
        receita,
        custo_dos_servicos: custo,
        lucro_bruto: receita - custo,
        despesas_operacionais: despesa,
        resultado_operacional: receita - custo - despesa,
        resultado_financeiro: financeiro,
        resultado_do_periodo: receita - custo - despesa - financeiro,
        fora_do_resultado: foraDoResultado,
        aviso: (entradasPendentes ?? 0) > 0
          ? `ATENÇÃO: ${entradasPendentes} entrada(s) do banco ainda não viraram receita lançada. ` +
            "O resultado acima está incompleto do lado da receita e parece pior do que é. " +
            "Avise isto ao usuário antes de comentar o número."
          : null,
      };
    },
  },
];
