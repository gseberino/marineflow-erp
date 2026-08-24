// Ferramentas de jornada: registrar o dia trabalhado e apurar o que pagar.
//
// São CINCO, de propósito. Cada ferramenta custa ~256 tokens em toda chamada do agente (ver
// plans/marineflow-otimizacao-prompt-e-tokens.md), então a régua é alta: entra o que a pessoa
// realmente diz no WhatsApp, não tudo o que o banco permite. Cadastro de perfil, correção de
// turno aprovado e relatório ficam na tela.
//
// A lição que este módulo tenta não repetir: `log_service_order_hours` existe, é ensinada no
// system prompt, e nunca foi chamada uma única vez. Ferramenta que espera iniciativa não é usada.
// Por isso o desenho aposta na PERGUNTA do fim do dia (motor de automações), e estas ferramentas
// são só o que responde a ela.

import type { ToolDef } from "./registry.ts";
import { apurar, diasDoPeriodo, type Turno, type WorkProfile } from "../../payroll/calculo.ts";

/** Acha o perfil de pagamento vigente de quem está logado. Sem perfil, não há como calcular nada —
 *  e o erro precisa dizer o que fazer, não só que faltou.
 *
 *  Procura por DOIS caminhos porque quem trabalha nem sempre tem login: o perfil pode estar no
 *  favorecido (`payees`, a identidade de PAGAMENTO) e a conta ser criada depois. Quando isso
 *  acontece, `payees.app_user_id` liga os dois e o perfil continua sendo do favorecido — o
 *  histórico não muda de dono só porque a pessoa ganhou acesso ao sistema. */
async function perfilVigente(sb: any, appUserId: string) {
  const { data: direto } = await sb
    .from("work_profiles").select("*")
    .eq("app_user_id", appUserId).is("vigencia_fim", null).maybeSingle();
  if (direto) return direto;

  const { data: payee } = await sb
    .from("payees").select("id").eq("app_user_id", appUserId).maybeSingle();
  if (!payee) return null;

  const { data: viaPayee } = await sb
    .from("work_profiles").select("*")
    .eq("payee_id", payee.id).is("vigencia_fim", null).maybeSingle();
  return viaPayee ?? null;
}

/** Resolve por nome quando o dono registra pela equipe ("o Felipe fez diária hoje").
 *  Procura em app_users e em payees — freelancer não tem login. */
async function acharPerfilPorNome(sb: any, nome: string) {
  const termo = `%${nome.trim()}%`;
  const { data: users } = await sb.from("app_users").select("id, full_name").ilike("full_name", termo).eq("active", true);
  const { data: pys } = await sb.from("payees").select("id, name").ilike("name", termo).eq("active", true);

  const candidatos: Array<{ tipo: "user" | "payee"; id: string; nome: string }> = [
    ...(users ?? []).map((u: any) => ({ tipo: "user" as const, id: u.id, nome: u.full_name })),
    ...(pys ?? []).map((p: any) => ({ tipo: "payee" as const, id: p.id, nome: p.name })),
  ];
  if (candidatos.length === 0) return { erro: `Não achei ninguém chamado "${nome}" entre a equipe e os favorecidos.` };
  if (candidatos.length > 1) {
    return { ambiguo: candidatos.map((c) => c.nome), erro: `Mais de uma pessoa casa com "${nome}": ${candidatos.map((c) => c.nome).join(", ")}. Diga o nome completo.` };
  }
  const c = candidatos[0];
  const q = sb.from("work_profiles").select("*").is("vigencia_fim", null);
  const { data: perfil } = c.tipo === "user"
    ? await q.eq("app_user_id", c.id).maybeSingle()
    : await q.eq("payee_id", c.id).maybeSingle();
  if (!perfil) return { erro: `${c.nome} não tem perfil de pagamento cadastrado. Cadastre em Equipe → Perfil de pagamento antes de apontar jornada.` };
  return { perfil, nome: c.nome };
}

const hojeLocal = () =>
  new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit", day: "2-digit" })
    .format(new Date());

/** "2h", "1h30", "90min", "8" -> minutos. Mesma gramática de log_service_order_hours, para não
 *  obrigar a pessoa a aprender duas formas de dizer a mesma coisa. */
export function minutosDeTexto(txt: string): number | null {
  const s = String(txt).trim().toLowerCase().replace(",", ".");
  let m = s.match(/^(\d+(?:\.\d+)?)\s*h(?:oras?)?$/);
  if (m) return Math.round(parseFloat(m[1]) * 60);
  m = s.match(/^(\d+)\s*h\s*(\d{1,2})$/);
  if (m) return Number(m[1]) * 60 + Number(m[2]);
  m = s.match(/^(\d+)\s*(?:min|minutos?)$/);
  if (m) return Number(m[1]);
  m = s.match(/^(\d+(?:\.\d+)?)$/);
  if (m) return Math.round(parseFloat(m[1]) * 60);
  return null;
}

export const jornadaTools: ToolDef[] = [
  {
    name: "registrar_jornada",
    description:
      "Registra jornada de trabalho de um dia: início de expediente ('cheguei', 'comecei'), dia inteiro já fechado ('trabalhei 8h hoje', 'das 8 às 17 com 1h de almoço') ou diária ('hoje foi diária'). Sem pessoa informada, é de quem está falando. Informe pessoa para registrar por outro (só gestor). Isto é jornada da PESSOA — o que ela recebe; hora gasta numa OS é log_service_order_hours, que alimenta o que o CLIENTE paga. O registro entra como rascunho e só vira dinheiro depois de aprovado.",
    input_schema: {
      type: "object",
      properties: {
        pessoa: { type: "string", description: "Nome de quem trabalhou. Omitir = quem está falando." },
        data: { type: "string", description: "Dia da jornada em YYYY-MM-DD. Padrão: hoje." },
        duracao: { type: "string", description: "Duração trabalhada: '8h', '1h30', '90min'. Use quando a pessoa disser quanto trabalhou." },
        inicio: { type: "string", description: "Início em ISO. Use para 'cheguei' (sem fim) ou 'das 8 às 17'." },
        fim: { type: "string", description: "Fim em ISO." },
        intervalo_minutos: { type: "number", description: "Almoço/pausa em minutos, descontado da duração." },
        tipo: { type: "string", enum: ["normal", "diaria", "folga", "falta", "atestado", "feriado"], description: "Padrão: normal. Use 'diaria' quando o combinado for por dia, não por hora." },
        ordem_servico: { type: "string", description: "OS em que o dia foi trabalhado, se foi só uma ('diária no barco do Rodrigo'). UUID ou número (OS-00042). Omita para dia de oficina, deslocamento ou administrativo." },
        observacao: { type: "string" },
      },
      required: [],
    },
    risk: "low",
    // Registrar a própria jornada é rotina. Registrar a de outra pessoa mexe no que ELA recebe,
    // então passa pela confirmação.
    computeRisk: (args: any) => (args?.pessoa ? "medium" : "low"),
    async execute(args, { sb, userId, userRole }) {
      const data = String(args.data || hojeLocal());
      let perfil: any = null;
      let dono = "você";

      if (args.pessoa) {
        if (!["admin", "financial"].includes(String(userRole))) {
          return { error: "Só gestor pode apontar jornada de outra pessoa." };
        }
        const r = await acharPerfilPorNome(sb, String(args.pessoa));
        if ((r as any).erro) return { error: (r as any).erro };
        perfil = (r as any).perfil; dono = (r as any).nome;
      } else {
        perfil = await perfilVigente(sb, userId);
        if (!perfil) {
          return { error: "Você não tem perfil de pagamento cadastrado (valor da hora ou da diária). Peça ao administrador para criar em Equipe → Perfil de pagamento — sem ele não dá para calcular o que pagar." };
        }
      }

      const tipo = String(args.tipo || "normal");
      let inicio: string | null = args.inicio ? String(args.inicio) : null;
      let fim: string | null = args.fim ? String(args.fim) : null;
      let duracaoMin: number | null = null;

      if (args.duracao) {
        duracaoMin = minutosDeTexto(String(args.duracao));
        if (duracaoMin === null) return { error: `Não entendi a duração "${args.duracao}". Use '8h', '1h30' ou '90min'.` };
      }

      // "Cheguei" sem hora = agora.
      if (!inicio && !fim && duracaoMin === null && tipo === "normal") {
        inicio = new Date().toISOString();
      }

      // Turno já aberto no mesmo dia: fechar antes de abrir outro evita dois relógios correndo.
      if (inicio && !fim && duracaoMin === null) {
        const { data: aberto } = await sb.from("work_shifts")
          .select("id, inicio").eq("work_profile_id", perfil.id).is("fim", null).eq("data", data).maybeSingle();
        if (aberto) {
          return { error: `Já existe um expediente aberto em ${data} desde ${new Date(aberto.inicio).toLocaleTimeString("pt-BR", { timeZone: "America/Sao_Paulo", hour: "2-digit", minute: "2-digit" })}. Feche com fechar_jornada antes de abrir outro.` };
        }
      }

      // A OS do dia é o que liga o custo de folha ao serviço (view v_custo_real_mao_de_obra_por_os).
      // Entra AQUI, na mesma frase em que a pessoa registra o dia, e não numa segunda ferramenta:
      // `log_service_order_hours` existe há meses, é ensinada no prompt e nunca foi chamada — pedir
      // uma segunda iniciativa é o que faz o dado nunca existir.
      let ordemServicoId: string | null = null;
      if (args.ordem_servico) {
        const termo = String(args.ordem_servico).trim();
        const ehUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(termo);
        const { data: os } = await (ehUUID
          ? sb.from("service_orders").select("id, service_order_number").eq("id", termo).maybeSingle()
          : sb.from("service_orders").select("id, service_order_number").eq("service_order_number", termo).maybeSingle());
        if (!os) return { error: `Não achei a OS "${termo}". Confira o número — o dia não foi registrado.` };
        ordemServicoId = os.id;
      }

      const linha: Record<string, unknown> = {
        work_profile_id: perfil.id,
        data,
        inicio, fim,
        intervalo_minutos: Number(args.intervalo_minutos) || 0,
        tipo,
        origem: "agente",
        status: "rascunho",
        observacao: args.observacao || null,
        registrado_por: userId,
        service_order_id: ordemServicoId,
      };
      if (duracaoMin !== null && !fim) {
        // Duração declarada sem relógio: grava a duração direto. É o caso mais comum no WhatsApp.
        linha.duracao_minutos = duracaoMin;
      }

      const { data: turno, error } = await sb.from("work_shifts").insert(linha).select().single();
      if (error) return { error: `Não consegui registrar: ${error.message}` };

      const emAberto = !!inicio && !fim && duracaoMin === null;
      return {
        ok: true,
        turno_id: turno.id,
        de_quem: dono,
        data,
        tipo,
        em_aberto: emAberto,
        horas: turno.duracao_minutos ? Math.round((turno.duracao_minutos / 60) * 100) / 100 : null,
        ordem_servico_id: ordemServicoId,
        status: "rascunho",
        nota: emAberto
          ? "Expediente aberto. Diga 'terminei' quando sair."
          : "Registrado como rascunho — entra no cálculo depois de aprovado.",
      };
    },
  },

  {
    name: "fechar_jornada",
    description:
      "Fecha o expediente aberto ('terminei', 'saí', 'acabei por hoje'), calcula a duração e mostra o total do dia. Use quando existir um expediente aberto por registrar_jornada. Sem pessoa informada, é de quem está falando.",
    input_schema: {
      type: "object",
      properties: {
        pessoa: { type: "string", description: "Nome. Omitir = quem está falando." },
        fim: { type: "string", description: "Hora de término em ISO. Padrão: agora." },
        intervalo_minutos: { type: "number", description: "Almoço/pausa em minutos, a descontar." },
        observacao: { type: "string", description: "O que foi feito no dia." },
      },
      required: [],
    },
    risk: "low",
    computeRisk: (args: any) => (args?.pessoa ? "medium" : "low"),
    async execute(args, { sb, userId, userRole }) {
      let perfil: any = null;
      if (args.pessoa) {
        if (!["admin", "financial"].includes(String(userRole))) return { error: "Só gestor pode fechar a jornada de outra pessoa." };
        const r = await acharPerfilPorNome(sb, String(args.pessoa));
        if ((r as any).erro) return { error: (r as any).erro };
        perfil = (r as any).perfil;
      } else {
        perfil = await perfilVigente(sb, userId);
        if (!perfil) return { error: "Você não tem perfil de pagamento cadastrado." };
      }

      const { data: aberto } = await sb.from("work_shifts")
        .select("*").eq("work_profile_id", perfil.id).is("fim", null)
        .order("data", { ascending: false }).limit(1).maybeSingle();
      if (!aberto) return { error: "Não achei expediente aberto para fechar. Se quiser lançar o dia inteiro, use registrar_jornada com a duração." };

      const fim = args.fim ? String(args.fim) : new Date().toISOString();
      const upd: Record<string, unknown> = { fim };
      if (args.intervalo_minutos != null) upd.intervalo_minutos = Number(args.intervalo_minutos);
      if (args.observacao) upd.observacao = args.observacao;

      const { data: turno, error } = await sb.from("work_shifts").update(upd).eq("id", aberto.id).select().single();
      if (error) return { error: `Não consegui fechar: ${error.message}` };

      const { data: doDia } = await sb.from("work_shifts")
        .select("duracao_minutos").eq("work_profile_id", perfil.id).eq("data", turno.data);
      const totalMin = (doDia ?? []).reduce((a: number, x: any) => a + (x.duracao_minutos ?? 0), 0);

      return {
        ok: true,
        turno_id: turno.id,
        data: turno.data,
        horas_do_turno: Math.round(((turno.duracao_minutos ?? 0) / 60) * 100) / 100,
        horas_no_dia: Math.round((totalMin / 60) * 100) / 100,
        status: turno.status,
        nota: "Rascunho — entra no cálculo depois de aprovado.",
      };
    },
  },

  {
    name: "minhas_horas",
    description:
      "Mostra a jornada registrada num período: horas por dia, diárias, o que está em rascunho e o que já foi aprovado. Use para 'quantas horas eu fiz esse mês?', 'o que o Felipe apontou essa semana?'. Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        pessoa: { type: "string", description: "Nome. Omitir = quem está falando." },
        de: { type: "string", description: "Data inicial YYYY-MM-DD. Padrão: primeiro dia do mês." },
        ate: { type: "string", description: "Data final YYYY-MM-DD. Padrão: hoje." },
      },
      required: [],
    },
    risk: "low",
    async execute(args, { sb, userId, userRole }) {
      let perfil: any = null;
      if (args.pessoa) {
        if (!["admin", "financial"].includes(String(userRole))) return { error: "Só gestor pode ver a jornada de outra pessoa." };
        const r = await acharPerfilPorNome(sb, String(args.pessoa));
        if ((r as any).erro) return { error: (r as any).erro };
        perfil = (r as any).perfil;
      } else {
        perfil = await perfilVigente(sb, userId);
        if (!perfil) return { error: "Você não tem perfil de pagamento cadastrado." };
      }

      const hoje = hojeLocal();
      const de = String(args.de || `${hoje.slice(0, 7)}-01`);
      const ate = String(args.ate || hoje);

      const { data: turnos } = await sb.from("work_shifts")
        .select("data, tipo, duracao_minutos, status, observacao")
        .eq("work_profile_id", perfil.id).gte("data", de).lte("data", ate)
        .order("data", { ascending: true });

      const lista = turnos ?? [];
      const totalMin = lista.reduce((a: number, t: any) => a + (t.duracao_minutos ?? 0), 0);
      return {
        periodo: { de, ate },
        total_horas: Math.round((totalMin / 60) * 100) / 100,
        diarias: lista.filter((t: any) => t.tipo === "diaria").length,
        em_rascunho: lista.filter((t: any) => t.status === "rascunho").length,
        aprovados: lista.filter((t: any) => t.status === "aprovado").length,
        dias: lista.map((t: any) => ({
          data: t.data, tipo: t.tipo,
          horas: t.duracao_minutos ? Math.round((t.duracao_minutos / 60) * 100) / 100 : null,
          status: t.status,
        })),
      };
    },
  },

  {
    name: "apurar_pagamento",
    description:
      "Calcula quanto pagar a alguém num período, com a conta aberta: horas normais, extras, adicional noturno, domingos, diárias, comissões e DSR. NÃO grava nem gera conta a pagar — é prévia. Use para 'quanto vou receber esse mês?', 'quanto devo pro Felipe?'. Considera apenas jornada APROVADA por padrão.",
    input_schema: {
      type: "object",
      properties: {
        pessoa: { type: "string", description: "Nome. Omitir = quem está falando." },
        de: { type: "string", description: "Data inicial YYYY-MM-DD. Padrão: primeiro dia do mês." },
        ate: { type: "string", description: "Data final YYYY-MM-DD. Padrão: hoje." },
        incluir_rascunho: { type: "boolean", description: "Incluir jornada ainda não aprovada. Padrão: false." },
      },
      required: [],
    },
    risk: "low",
    async execute(args, { sb, userId, userRole }) {
      let perfil: any = null;
      let nome = "você";
      if (args.pessoa) {
        if (!["admin", "financial"].includes(String(userRole))) return { error: "Só gestor pode apurar pagamento de outra pessoa." };
        const r = await acharPerfilPorNome(sb, String(args.pessoa));
        if ((r as any).erro) return { error: (r as any).erro };
        perfil = (r as any).perfil; nome = (r as any).nome;
      } else {
        perfil = await perfilVigente(sb, userId);
        if (!perfil) return { error: "Você não tem perfil de pagamento cadastrado." };
      }

      const hoje = hojeLocal();
      const de = String(args.de || `${hoje.slice(0, 7)}-01`);
      const ate = String(args.ate || hoje);

      let q = sb.from("work_shifts")
        .select("id, data, inicio, fim, intervalo_minutos, duracao_minutos, tipo, status")
        .eq("work_profile_id", perfil.id).gte("data", de).lte("data", ate);
      if (!args.incluir_rascunho) q = q.in("status", ["aprovado", "pago"]);
      const { data: turnos } = await q.order("data", { ascending: true });

      // Comissões do período entram na mesma conta — já existem e são parte do que a pessoa recebe.
      let comissoes = 0;
      if (perfil.app_user_id) {
        const { data: com } = await sb.from("commissions")
          .select("amount").eq("user_id", perfil.app_user_id)
          .gte("created_at", `${de}T00:00:00-03:00`).lte("created_at", `${ate}T23:59:59-03:00`);
        comissoes = (com ?? []).reduce((a: number, c: any) => a + Number(c.amount || 0), 0);
      }

      const { diasUteis, domingosEFeriados } = diasDoPeriodo(de, ate);
      const r = apurar(perfil as WorkProfile, (turnos ?? []) as Turno[], { comissoes, diasUteis, domingosEFeriados });

      return {
        de_quem: nome,
        periodo: { de, ate },
        base: args.incluir_rascunho ? "jornada aprovada + rascunho" : "somente jornada aprovada",
        turnos_considerados: (turnos ?? []).length,
        horas: { normais: r.horas_normais, extras: r.horas_extras, noturnas: r.horas_noturnas, domingo: r.horas_domingo },
        diarias: { inteiras: r.diarias_inteiras, meias: r.diarias_meias },
        valores: {
          normais: r.valor_normais, extras: r.valor_extras, noturnas: r.valor_noturnas,
          domingo: r.valor_domingo, diarias: r.valor_diarias, mensal: r.valor_mensal,
          comissoes: r.valor_comissoes, dsr: r.valor_dsr, descontos: r.descontos,
        },
        total_bruto: r.valor_bruto,
        avisos: r.avisos,
        nota: "Prévia — não gera conta a pagar. Para fechar de fato e gerar o pagamento, use fechar_folha.",
      };
    },
  },
  {
    name: "fechar_folha",
    description:
      "Fecha o período de pagamento da equipe: apura todo mundo que tem perfil, GERA UMA CONTA A PAGAR por pessoa e marca os dias como pagos. Ação de dinheiro — pede confirmação. Use para 'fecha a folha do mês', 'pode pagar a equipe', 'fecha o pagamento da quinzena'. Só considera jornada APROVADA. Um período só pode ser fechado uma vez.",
    input_schema: {
      type: "object",
      properties: {
        de: { type: "string", description: "Data inicial YYYY-MM-DD. Padrão: primeiro dia do mês corrente." },
        ate: { type: "string", description: "Data final YYYY-MM-DD. Padrão: hoje." },
        vencimento: { type: "string", description: "Vencimento das contas geradas YYYY-MM-DD. Padrão: 5 dias após o fim do período." },
        descricao: { type: "string", description: "Rótulo do período, ex.: 'Folha agosto/2026'." },
      },
      required: [],
    },
    risk: "high",
    roles: ["admin", "financial"],
    async execute(args, { sb, userId, userRole }) {
      // Defesa em profundidade: o filtro de `roles` já tira esta ferramenta da lista do técnico,
      // mas o canal WhatsApp roda com service-role e sem RLS de usuário — a checagem tem que
      // existir aqui também. A RPC repete a validação pela terceira vez, no banco.
      if (!["admin", "financial"].includes(String(userRole))) {
        return { error: "Só gestor pode fechar folha." };
      }

      const hoje = hojeLocal();
      const de = String(args.de || `${hoje.slice(0, 7)}-01`);
      const ate = String(args.ate || hoje);
      if (ate < de) return { error: `Período inválido: ${ate} é anterior a ${de}.` };

      const { data: perfis } = await sb
        .from("work_profiles")
        .select("*, payees(name), app_users(full_name)")
        .is("vigencia_fim", null);
      if (!perfis?.length) {
        return { error: "Ninguém tem perfil de pagamento cadastrado — não há o que fechar. Cadastre em Equipe → Perfil de pagamento." };
      }

      const { diasUteis, domingosEFeriados } = diasDoPeriodo(de, ate);
      const linhas: Array<Record<string, unknown>> = [];
      const semTurno: string[] = [];
      const avisos: string[] = [];

      for (const perfil of perfis) {
        const nome = perfil.payees?.name || perfil.app_users?.full_name || "equipe";

        // Só jornada APROVADA entra na folha. Rascunho é o que a pessoa apontou e ninguém conferiu:
        // pagar por ele transformaria o apontamento em autorização de pagamento.
        const { data: turnos } = await sb.from("work_shifts")
          .select("id, data, inicio, fim, intervalo_minutos, duracao_minutos, tipo, status")
          .eq("work_profile_id", perfil.id)
          .gte("data", de).lte("data", ate)
          .eq("status", "aprovado")
          .order("data", { ascending: true });

        let comissoes = 0;
        if (perfil.app_user_id) {
          const { data: com } = await sb.from("commissions")
            .select("amount").eq("user_id", perfil.app_user_id)
            .gte("created_at", `${de}T00:00:00-03:00`).lte("created_at", `${ate}T23:59:59-03:00`);
          comissoes = (com ?? []).reduce((a: number, c: any) => a + Number(c.amount || 0), 0);
        }

        if (!turnos?.length && comissoes === 0) { semTurno.push(nome); continue; }

        const r = apurar(perfil as WorkProfile, (turnos ?? []) as Turno[], { comissoes, diasUteis, domingosEFeriados });
        if (r.avisos.length) avisos.push(`${nome}: ${r.avisos.join("; ")}`);
        if (r.valor_bruto <= 0) { semTurno.push(nome); continue; }

        linhas.push({
          work_profile_id: perfil.id, nome,
          horas_normais: r.horas_normais, horas_extras: r.horas_extras,
          horas_noturnas: r.horas_noturnas, horas_domingo: r.horas_domingo,
          diarias_inteiras: r.diarias_inteiras, diarias_meias: r.diarias_meias,
          valor_normais: r.valor_normais, valor_extras: r.valor_extras,
          valor_noturnas: r.valor_noturnas, valor_domingo: r.valor_domingo,
          valor_diarias: r.valor_diarias, valor_mensal: r.valor_mensal,
          valor_comissoes: r.valor_comissoes, valor_dsr: r.valor_dsr,
          descontos: r.descontos, valor_bruto: r.valor_bruto,
          // Retenção de ISS/INSS fica em ZERO até a contadora confirmar o que Itajaí exige do
          // prestador. Chutar retenção é errar o valor pago a alguém — e o erro só aparece no
          // recibo da pessoa. Quando confirmar, entra aqui e o líquido muda sozinho.
          retencoes: 0,
          detalhamento: r.detalhamento,
          turno_ids: (turnos ?? []).map((t: any) => t.id),
        });
      }

      if (!linhas.length) {
        return {
          error: `Nenhuma jornada aprovada entre ${de} e ${ate} — nada a pagar.`,
          dica: semTurno.length ? `Sem jornada aprovada no período: ${semTurno.join(", ")}. Se alguém apontou e falta aprovar, aprove antes de fechar.` : undefined,
        };
      }

      const { data: fechamento, error } = await sb.rpc("gravar_fechamento_de_folha", {
        p_de: de, p_ate: ate,
        p_descricao: args.descricao || `Folha ${de} a ${ate}`,
        p_linhas: linhas,
        p_ator: userId,
        p_vencimento: args.vencimento || null,
      });

      if (error) {
        // 23505 = o índice único de (de, ate). É o caso de repetir o comando, e a mensagem tem que
        // dizer isso, não vazar o nome do índice.
        if (String(error.code) === "23505") {
          return { error: `O período de ${de} a ${ate} já foi fechado. Consulte a folha desse período em vez de fechar de novo.` };
        }
        return { error: `Não consegui fechar a folha: ${error.message}` };
      }

      return {
        ok: true,
        ...fechamento,
        sem_jornada_no_periodo: semTurno.length ? semTurno : undefined,
        avisos: avisos.length ? avisos : undefined,
        nota: "As contas a pagar foram criadas como PENDENTES — o pagamento em si continua sendo registrado no financeiro. Freelancer: anexe a NFS-e dele na conta antes de pagar.",
      };
    },
  },
];
