// O mês e as contas, pela conversa — as mesmas funções do banco que a tela usa.
//
// "O mês está pronto?", "fecha agosto", "quanto tem no C6?", "o que você lançou sozinho
// essa semana?", "para de lançar sozinho". A IA escolhe a função e os argumentos de negócio
// (mês, conta pelo nome); o banco faz a conta — saldo, verificação, trava.
import { blockTechnician, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
// LGPD (leva 8): o título da proposta nasce do nome do banco ("Despesa: 12345678901-JOAO…") — CPF mascarado ao modelo.
import { nomeSemCpf as mascararCpfNoTexto } from "../../banking/contraparte.ts";

const CARGOS_FINANCEIRO: Role[] = ["admin", "financial"];

function semAcesso(ctx: ToolCtx): { error: string } | null {
  const b = blockTechnician(ctx);
  if (b) return b;
  if (!CARGOS_FINANCEIRO.includes(ctx.userRole as Role)) return { error: "Apenas administrador ou financeiro." };
  return null;
}

/** Mês anterior ao de hoje — o mês que normalmente se fecha. */
export function mesAnterior(hoje = new Date()): { ano: number; mes: number } {
  const m = hoje.getMonth(); // 0-11; o anterior em 1-12 é o próprio m
  return m === 0 ? { ano: hoje.getFullYear() - 1, mes: 12 } : { ano: hoje.getFullYear(), mes: m };
}

/** Mês pedido; sem ano, o mais recente que já aconteceu ('dezembro' em janeiro = ano passado). */
export function mesDosArgs(args: Record<string, unknown>, hoje = new Date()): { ano: number; mes: number } {
  const padrao = mesAnterior(hoje);
  if (args.mes == null) return { ano: Number(args.ano ?? padrao.ano), mes: padrao.mes };
  const mes = Number(args.mes);
  const ano = args.ano != null ? Number(args.ano) : (mes > hoje.getMonth() + 1 ? hoje.getFullYear() - 1 : hoje.getFullYear());
  return { ano, mes };
}

/** A conta pelo nome que a pessoa falou ("C6", "nubank", "caixa"). */
async function acharConta(ctx: ToolCtx, nome: unknown): Promise<{ id: string; label: string } | { error: string }> {
  const { data, error } = await ctx.admin.from("bank_connections").select("id, label").eq("active", true);
  if (error) return { error: `Não consegui ler as contas bancárias (${error.message}).` };
  const contas = (data ?? []) as { id: string; label: string }[];
  if (contas.length === 0) return { error: "Nenhuma conta conectada." };
  if (!nome) return contas.length === 1 ? contas[0] : { error: `Qual conta? ${contas.map((c) => c.label).join(", ")}` };
  const alvo = String(nome).toLowerCase();
  const achadas = contas.filter((c) => c.label.toLowerCase().includes(alvo));
  if (achadas.length === 1) return achadas[0];
  return { error: `Não achei uma conta só com "${nome}". Contas: ${contas.map((c) => c.label).join(", ")}` };
}

export const fechamentoTools: ToolDef[] = [
  {
    name: "verificar_mes",
    description:
      "Responde 'o mês está pronto para fechar?': saldo de cada conta confere com o banco, extrato sem nada esperando, " +
      "sem despesa em dobro, lançamentos batendo com o extrato, tudo com categoria. Sem mês, usa o mês passado. Só leitura. " +
      "Para mostrar QUAIS linhas estão por trás de uma pendência, repita com `detalhar` = a chave da pendência.",
    input_schema: {
      type: "object",
      properties: {
        mes: { type: "number", description: "1 a 12" },
        ano: { type: "number" },
        detalhar: { type: "string", description: "Chave de uma pendência (vem em `pendencias[].chave`) para listar as linhas dela." },
      },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const { ano, mes } = mesDosArgs(args);
      // As linhas por trás de uma pendência — a mesma lista do "Ver" da tela (30/09/2026).
      if (args.detalhar) {
        const { data, error } = await ctx.sb.rpc("linhas_do_checklist", { p_ano: ano, p_mes: mes, p_chave: String(args.detalhar) });
        if (error) return { error: error.message };
        const linhas = (data ?? []) as Array<Record<string, unknown>>;
        return {
          mes: `${String(mes).padStart(2, "0")}/${ano}`, pendencia: String(args.detalhar), total: linhas.length,
          linhas: linhas.slice(0, 30).map((l) => ({ data: l.data, valor: l.valor, descricao: l.descricao, quem: l.quem, detalhe: l.detalhe })),
          ...(linhas.length > 30 ? { aviso: `Mostrando 30 de ${linhas.length}; a lista inteira está em Conciliação › Fechar o mês › Ver.` } : {}),
        };
      }
      const { data, error } = await ctx.sb.rpc("checklist_do_mes", { p_ano: ano, p_mes: mes });
      if (error) return { error: error.message };
      const r = data as { pronto: boolean; itens: Array<Record<string, unknown>> };
      return {
        mes: `${String(mes).padStart(2, "0")}/${ano}`,
        pronto: r.pronto,
        pendencias: r.itens.filter((i) => !i.ok).map((i) => ({ chave: i.chave, o_que: i.titulo, detalhe: i.detalhe, bloqueia: i.bloqueia })),
        ok: r.itens.filter((i) => i.ok).map((i) => i.titulo),
      };
    },
  },
  {
    name: "fechar_mes",
    description:
      "Fecha um mês: depois disso nenhum lançamento com data nele entra ou muda. O sistema verifica de novo antes; " +
      "com pendência, só fecha se o usuário der um motivo (fica na trilha). Só administrador. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        mes: { type: "number", description: "1 a 12" },
        ano: { type: "number" },
        motivo: { type: "string", description: "Só quando o usuário decidir fechar com pendência — por quê." },
      },
      required: ["mes"],
    },
    risk: "high",
    roles: ["admin"],
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const { ano, mes } = mesDosArgs(args);
      const { data, error } = await ctx.sb.rpc("fechar_mes", {
        p_ano: ano, p_mes: mes, p_motivo: typeof args.motivo === "string" ? args.motivo : null, p_autor: ctx.userId || null,
      });
      if (error) return { error: error.message.replace(/^(P0001|42501|23514):\s*/, "") };
      return data;
    },
  },
  {
    name: "consultar_conta",
    description:
      "Saldo e movimento de uma conta (C6, Nubank, InfinitePay, Caixa…) num mês: saldo no início e no fim, entradas, " +
      "saídas e quantas linhas ainda esperam decisão. Use para 'quanto tem no C6?', 'como foi o mês no Nubank?'. Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        conta: { type: "string", description: "Parte do nome da conta. Omitir se houver uma só." },
        mes: { type: "number" }, ano: { type: "number" },
      },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const conta = await acharConta(ctx, args.conta);
      if ("error" in conta) return conta;
      const hoje = new Date();
      const ano = Number(args.ano ?? hoje.getFullYear());
      const mes = Number(args.mes ?? hoje.getMonth() + 1);
      const de = `${ano}-${String(mes).padStart(2, "0")}-01`;
      const ate = new Date(ano, mes, 0).toISOString().slice(0, 10);
      const { data, error } = await ctx.sb.rpc("extrato_da_conta", { p_conexao: conta.id, p_de: de, p_ate: ate });
      if (error) return { error: error.message };
      const linhas = ((data ?? []) as any[]).filter((l) => !l.pendente);
      const comSaldo = linhas.filter((l) => l.saldo_apos != null);
      const maisNova = comSaldo[0];
      const maisAntiga = comSaldo[comSaldo.length - 1];
      return {
        conta: conta.label,
        mes: `${String(mes).padStart(2, "0")}/${ano}`,
        saldo_no_fim: maisNova ? Number(maisNova.saldo_apos) : null,
        saldo_no_inicio: maisAntiga ? Number(maisAntiga.saldo_apos) - Number(maisAntiga.valor) : null,
        entradas: linhas.filter((l) => Number(l.valor) > 0).reduce((s, l) => s + Number(l.valor), 0),
        saidas: linhas.filter((l) => Number(l.valor) < 0).reduce((s, l) => s - Number(l.valor), 0),
        movimentos: linhas.length,
        esperando_decisao: linhas.filter((l) => l.proposta_id || l.situacao === "nova").length,
        aviso: maisNova ? undefined : "Saldo ainda sem linha de base — aparece depois da próxima sincronização.",
      };
    },
  },
  {
    name: "configurar_lancamento_automatico",
    description:
      "Liga ou desliga o 'lançar sozinho' (saídas de confiança alta abaixo do limite de lote). Use para 'para de lançar sozinho' " +
      "ou 'pode voltar a lançar sozinho'. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: { ligado: { type: "boolean" } },
      required: ["ligado"],
    },
    risk: "medium",
    roles: ["admin"],
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const { error } = await ctx.admin.from("app_settings")
        .upsert({ key: "finance_auto_approve", value: args.ligado ? "on" : "off" }, { onConflict: "key" });
      if (error) return { error: error.message };
      await ctx.admin.from("reconciliation_log").insert({
        acao: "configurou_automatico", autor: ctx.userId || null,
        detalhe: args.ligado ? "Ligou o lançar sozinho" : "Desligou o lançar sozinho",
      });
      return { ok: true, ligado: !!args.ligado };
    },
  },
  {
    name: "listar_lancados_sozinhos",
    description:
      "O que o sistema lançou sem clique nos últimos dias (por regra sua ou por confiança alta) e as contas que ele baixou " +
      "sozinho pelo boleto (por = 'baixa pelo boleto': a conta já existia e o banco mostrou o pagamento), com o id do lançamento " +
      "para desfazer (desfazer_aprovacao_de_lancamento). Traz também o recebimento baixado pelo boleto (por = 'recebimento pelo " +
      "boleto': conta a receber de NF-e com boleto, e o banco mostrou o crédito do boleto de mesmo valor no dia do vencimento): vem " +
      "com receivable_id e se desfaz com desfazer_aprovacao_de_lancamento passando receivable_id — a conta volta a ficar em aberto " +
      "e a linha do banco volta para a fila ('desfaz a baixa da Apolo': ache o id aqui). valor_total soma só as saídas; os " +
      "recebimentos somam à parte (valor_recebido_pelo_boleto). Diz também se o lançar sozinho está ligado. Só leitura.",
    input_schema: { type: "object", properties: { dias: { type: "number", description: "Padrão 7." } } },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const desde = new Date(Date.now() - Math.min(90, Number(args.dias ?? 7)) * 86_400_000).toISOString();
      const [{ data, error }, { data: cfg, error: erroCfg }] = await Promise.all([
        ctx.admin.from("finance_review_queue")
          .select("title, suggested_amount, suggested_category, suggested_date, automatica, created_payable_id, bank_transaction_id, kind")
          .not("automatica", "is", null).eq("status", "approved").gte("decided_at", desde)
          .order("decided_at", { ascending: false }).limit(50),
        ctx.admin.from("app_settings").select("value").eq("key", "finance_auto_approve").maybeSingle(),
      ]);
      // Erro engolido diria "nada lançado sozinho" e "desligado" — as duas coisas como fato.
      if (error) throw new Error(`Não consegui ler o que foi lançado sozinho: ${error.message}`);
      if (erroCfg) throw new Error(`Não consegui ler se o lançar sozinho está ligado: ${erroCfg.message}`);
      // Baixa pelo boleto (22/11/2026): a conta não nasceu da proposta — é a que está casada com a linha do banco.
      // Baixa desfeita por outro caminho não tem mais conta casada: sai da lista.
      const doBoleto = ((data ?? []) as any[]).filter((l) => l.automatica === "boleto" && l.bank_transaction_id);
      // Recebimento baixado pelo boleto (24/11/2026): a mesma marca 'boleto', mas a proposta é de entrada (kind
      // 'create_receivable') e a conta casada com a linha do banco está em receivables. Procurada só em payables, a
      // baixa pareceria desfeita e sumiria daqui — sem id para desfazer. Linha sem kind (dado antigo) é conta a pagar.
      const ehRecebimento = (l: any) => l.automatica === "boleto" && l.kind === "create_receivable";
      const dePagar = doBoleto.filter((l) => !ehRecebimento(l));
      const deReceber = doBoleto.filter(ehRecebimento);
      const contaDaLinha = new Map<string, string>();
      if (dePagar.length > 0) {
        const { data: casadas, error: erroCasadas } = await ctx.admin.from("payables")
          .select("id, bank_transaction_id").in("bank_transaction_id", dePagar.map((l) => l.bank_transaction_id));
        if (erroCasadas) throw new Error(`Não consegui ler as contas baixadas pelo boleto: ${erroCasadas.message}`);
        for (const c of (casadas ?? []) as any[]) contaDaLinha.set(String(c.bank_transaction_id), String(c.id));
      }
      // O título da proposta é só "Receita: CREDITO DE BOLETO": quem pagou e qual parcela vêm da conta. A categoria
      // também (24/11/2026): a da proposta ("Outras receitas") é a da receita nova que NÃO foi criada — a baixa casou a
      // linha com a conta da nota. Dita ao dono, viraria "a venda entrou como Outras receitas", que ninguém gravou.
      const casadoComALinha = new Map<string, { id: string; o_que: string; categoria: string | null }>();
      if (deReceber.length > 0) {
        const { data: recebidas, error: erroRecebidas } = await ctx.admin.from("receivables")
          .select("id, bank_transaction_id, description, category, clients!receivables_client_id_fkey(name)")
          .in("bank_transaction_id", deReceber.map((l) => l.bank_transaction_id));
        if (erroRecebidas) throw new Error(`Não consegui ler os recebimentos baixados pelo boleto: ${erroRecebidas.message}`);
        for (const c of (recebidas ?? []) as any[]) {
          const cliente = (Array.isArray(c.clients) ? c.clients[0]?.name : c.clients?.name) ?? null;
          casadoComALinha.set(String(c.bank_transaction_id), {
            id: String(c.id),
            o_que: `Recebimento: ${[cliente, c.description].filter(Boolean).join(" — ") || "conta a receber"}`,
            categoria: c.category ?? null,
          });
        }
      }
      // A marca que revive (24/11/2026): o desfazer não toca na fila — a proposta fica approved + 'boleto' para sempre.
      // Se o dono desfaz a baixa e depois casa À MÃO a mesma linha do banco (com a mesma conta ou com outra), "existe
      // conta casada com a linha" volta a ser verdade e isto diria "baixei sozinho" o que ele decidiu. A baixa só vale
      // se o registro da linha tiver EXATAMENTE UMA entrada, e ela for a da baixa: acao 'conciliou', detalhe começando
      // por "Baixa automática pelo boleto" e a mesma conta. É exato porque a função do banco nunca baixa linha que já
      // tenha qualquer registro: o que vier depois (desfazer, casar de novo, corrigir) é mão do dono. Só no lado de
      // RECEBER — a conta a pagar continua como estava. Erro engolido aqui diria "nada baixado" como fato.
      const recebidoDaLinha = new Map<string, { id: string; o_que: string; categoria: string | null }>();
      if (casadoComALinha.size > 0) {
        const { data: registros, error: erroRegistros } = await ctx.admin.from("reconciliation_log")
          .select("bank_transaction_id, receivable_id, acao, detalhe")
          .in("bank_transaction_id", [...casadoComALinha.keys()]);
        if (erroRegistros) {
          throw new Error(`Não consegui conferir se os recebimentos baixados pelo boleto continuam valendo: ${erroRegistros.message}`);
        }
        const registrosDaLinha = new Map<string, any[]>();
        for (const g of (registros ?? []) as any[]) {
          // a faxina da própria varredura (proposta repetida fechada) não é mão de ninguém: não conta
          if (g.acao === "tirou_da_fila_ja_lancada") continue;
          const linha = String(g.bank_transaction_id);
          registrosDaLinha.set(linha, [...(registrosDaLinha.get(linha) ?? []), g]);
        }
        // (as vivas entram num mapa novo, em vez de tirar as outras do primeiro: esta ferramenta roda direto pela rede
        // do admin, e a guarda de perfil-operacao_test.ts lê este corpo atrás de qualquer chamada de apagar)
        for (const [linha, casado] of casadoComALinha) {
          const daLinha = registrosDaLinha.get(linha) ?? [];
          const baixaViva = daLinha.length === 1 && daLinha[0].acao === "conciliou"
            && String(daLinha[0].detalhe ?? "").startsWith("Baixa automática pelo boleto")
            && String(daLinha[0].receivable_id ?? "") === casado.id;
          if (baixaViva) recebidoDaLinha.set(linha, casado);
        }
      }
      const lista = ((data ?? []) as any[])
        .filter((l) => l.automatica !== "boleto"
          || (ehRecebimento(l) ? recebidoDaLinha.has(String(l.bank_transaction_id)) : contaDaLinha.has(String(l.bank_transaction_id))))
        .map((l) => {
          const recebido = ehRecebimento(l) ? recebidoDaLinha.get(String(l.bank_transaction_id)) : undefined;
          if (recebido) {
            return {
              o_que: mascararCpfNoTexto(recebido.o_que), valor: Number(l.suggested_amount), categoria: recebido.categoria, data: l.suggested_date,
              por: "recebimento pelo boleto", payable_id: null, receivable_id: recebido.id,
            };
          }
          return {
            o_que: mascararCpfNoTexto(l.title ?? null), valor: Number(l.suggested_amount), categoria: l.suggested_category, data: l.suggested_date,
            por: l.automatica === "regra" ? "regra sua" : l.automatica === "boleto" ? "baixa pelo boleto" : "confiança alta",
            payable_id: l.automatica === "boleto" ? contaDaLinha.get(String(l.bank_transaction_id)) ?? null : l.created_payable_id,
          };
        });
      // valor_total é "quanto saiu sem clique": entrada de cliente somada ali deixaria o número sem sentido (24/11/2026).
      const recebidos = lista.filter((l) => l.por === "recebimento pelo boleto");
      return {
        ligado: String((cfg as any)?.value ?? "off") === "on",
        total: lista.length, valor_total: lista.filter((l) => l.por !== "recebimento pelo boleto").reduce((s, l) => s + l.valor, 0), lancados: lista,
        ...(recebidos.length > 0
          ? { recebimentos_pelo_boleto: recebidos.length, valor_recebido_pelo_boleto: Math.round(recebidos.reduce((s, l) => s + l.valor, 0) * 100) / 100 }
          : {}),
      };
    },
  },
];
