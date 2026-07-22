import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { generatePONumber } from "./purchasing.ts";
import { chaveTelefone } from "../phone.ts";

// Módulo de COTAÇÃO a fornecedores (Fase 2 · Etapa 1).
// Operação real: compra sob demanda (sem estoque) → todo orçamento gera cotação.
// Itens são MISTURADOS: parte do catálogo (product_id) e parte texto livre — por isso
// tudo aqui trabalha com `description` obrigatória e `product_id` opcional.

// Numeração no mesmo esquema não-atômico já usado em generatePONumber (purchasing.ts):
// suficiente para um operador único; evita criar sequence só para isso.
async function generateQuoteCode(admin: any): Promise<string> {
  const { data } = await admin.from("quote_requests").select("code").order("created_at", { ascending: false }).limit(1);
  let seq = 1;
  const last = data?.[0]?.code;
  if (last) {
    const m = String(last).match(/(\d+)$/);
    if (m) seq = parseInt(m[1], 10) + 1;
  }
  return `COT-${String(seq).padStart(5, "0")}`;
}

/** Carrega os itens de um orçamento/OS já no formato de item de cotação (peças + serviços/materiais). */
async function loadItemsFromServiceOrder(sb: any, soId: string) {
  const { data: parts } = await sb
    .from("service_order_parts")
    .select("id, product_id, quantity, products(name)")
    .eq("service_order_id", soId);
  const { data: services } = await sb
    .from("service_order_services")
    .select("id, name_snapshot, quantity")
    .eq("service_order_id", soId);
  const out: Array<Record<string, unknown>> = [];
  for (const p of (parts as any[]) || []) {
    out.push({
      product_id: p.product_id ?? null,
      description: p.products?.name || "Produto",
      quantity: Number(p.quantity) || 1,
      service_order_part_id: p.id,
      service_order_service_id: null,
    });
  }
  for (const s of (services as any[]) || []) {
    out.push({
      product_id: null,
      description: s.name_snapshot || "Item",
      quantity: Number(s.quantity) || 1,
      service_order_part_id: null,
      service_order_service_id: s.id,
    });
  }
  return out;
}

export const quoteTools: ToolDef[] = [
  {
    name: "create_quote_request",
    description:
      "Cria uma COTAÇÃO (pedido de preço a fornecedores) e devolve o código COT-XXXXX com os itens numerados. NÃO envia nada — depois use send_supplier_quote_request com o quote_request_id para disparar. Se você passar service_order_id e omitir items, os itens do orçamento (peças e serviços/materiais) entram automaticamente. Itens aceitam produto do catálogo (product_id) OU só descrição (texto livre).",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID do orçamento/OS de origem (opcional, mas recomendado — é o que permite devolver o custo depois)." },
        supplier_ids: { type: "array", items: { type: "string" }, description: "Fornecedores a cotar (use suggest_suppliers para achar)." },
        items: {
          type: "array",
          description: "Itens a cotar. Omita para puxar automaticamente do service_order_id.",
          items: {
            type: "object",
            properties: {
              description: { type: "string", description: "Descrição do item (obrigatória, mesmo com product_id)." },
              quantity: { type: "number" },
              product_id: { type: "string", description: "UUID do produto do catálogo, se houver." },
            },
            required: ["description"],
          },
        },
        notes: { type: "string", description: "Observação ao fornecedor (prazo desejado, condições)." },
      },
      required: ["supplier_ids"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb, admin, userId } = ctx;

      const supplierIds: string[] = Array.isArray(args.supplier_ids) ? args.supplier_ids.filter(Boolean) : [];
      if (supplierIds.length === 0) return { error: "Informe ao menos um fornecedor (supplier_ids)." };

      let items: Array<Record<string, unknown>> = Array.isArray(args.items) && args.items.length > 0 ? args.items : [];
      if (items.length === 0) {
        if (!args.service_order_id) return { error: "Informe items ou um service_order_id para puxar os itens do orçamento." };
        items = await loadItemsFromServiceOrder(sb, args.service_order_id);
        if (items.length === 0) return { error: "Esse orçamento/OS não tem itens para cotar." };
      }

      const code = await generateQuoteCode(admin);
      const { data: req, error: reqErr } = await sb
        .from("quote_requests")
        .insert({
          code,
          service_order_id: args.service_order_id ?? null,
          status: "open",
          sent_supplier_ids: supplierIds,
          notes: args.notes ?? null,
          created_by: userId ?? null,
        })
        .select("id, code")
        .single();
      if (reqErr) throw reqErr;

      const rows = items.map((it, i) => ({
        quote_request_id: req.id,
        product_id: (it.product_id as string) ?? null,
        description: String(it.description ?? "Item"),
        quantity: Number(it.quantity) || 1,
        service_order_part_id: (it.service_order_part_id as string) ?? null,
        service_order_service_id: (it.service_order_service_id as string) ?? null,
        position: i + 1,
      }));
      const { error: itErr } = await sb.from("quote_request_items").insert(rows);
      if (itErr) throw itErr;

      const { data: sups } = await sb.from("suppliers").select("id, name, phone").in("id", supplierIds);
      const fornecedores = (sups || []).map((s: any) => ({
        supplier_id: s.id,
        nome: s.name,
        tem_whatsapp: !!s.phone,
      }));

      return {
        ok: true,
        quote_request_id: req.id,
        codigo: req.code,
        itens: rows.map((r) => ({ n: r.position, descricao: r.description, quantidade: r.quantity, do_catalogo: !!r.product_id })),
        fornecedores,
        proximo_passo: `Para disparar, chame send_supplier_quote_request com quote_request_id=${req.id}.`,
      };
    },
  },
  {
    name: "get_quote_comparison",
    description:
      "Mostra o comparativo de uma COTAÇÃO: cada item × cada fornecedor, com preço, prazo e de ONDE o número veio (trecho de origem). Use para responder 'como está a COT-00042?'. Só leitura — não aplica custo nem cria ordem de compra.",
    input_schema: {
      type: "object",
      properties: {
        quote_request_id: { type: "string", description: "UUID da cotação." },
        code: { type: "string", description: "Código COT-XXXXX (alternativa ao id)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      if (!args.quote_request_id && !args.code) return { error: "Informe quote_request_id ou code (COT-XXXXX)." };

      let q = sb.from("quote_requests").select("id, code, status, service_order_id, sent_supplier_ids, notes, created_at");
      q = args.quote_request_id ? q.eq("id", args.quote_request_id) : q.eq("code", String(args.code).toUpperCase());
      const { data: req, error } = await q.maybeSingle();
      if (error) throw error;
      if (!req) return { error: "Cotação não encontrada." };

      const { data: items } = await sb
        .from("quote_request_items")
        .select("id, position, description, quantity, product_id")
        .eq("quote_request_id", req.id)
        .order("position", { ascending: true });
      const { data: resps } = await sb
        .from("quote_responses")
        .select("id, supplier_id, quote_request_item_id, unit_price, lead_time_days, source, source_excerpt, confirmed")
        .eq("quote_request_id", req.id);

      const supplierIds = [...new Set([...(req.sent_supplier_ids || []), ...((resps || []).map((r: any) => r.supplier_id))])].filter(Boolean);
      const { data: sups } = supplierIds.length
        ? await sb.from("suppliers").select("id, name").in("id", supplierIds)
        : { data: [] };
      const nameById: Record<string, string> = Object.fromEntries((sups || []).map((s: any) => [s.id, s.name]));

      const comparativo = (items || []).map((it: any) => {
        const respostas = (resps || [])
          .filter((r: any) => r.quote_request_item_id === it.id)
          .map((r: any) => ({
            response_id: r.id,
            fornecedor: nameById[r.supplier_id] || r.supplier_id,
            preco_unitario: r.unit_price != null ? Number(r.unit_price) : null,
            prazo_dias: r.lead_time_days ?? null,
            origem: r.source,
            trecho_origem: r.source_excerpt || null,
            confirmado: !!r.confirmed,
          }))
          .sort((a: any, b: any) => (a.preco_unitario ?? Infinity) - (b.preco_unitario ?? Infinity));
        return { n: it.position, descricao: it.description, quantidade: Number(it.quantity), respostas, sem_resposta: respostas.length === 0 };
      });

      const semResposta = (req.sent_supplier_ids || []).filter(
        (sid: string) => !(resps || []).some((r: any) => r.supplier_id === sid),
      ).map((sid: string) => nameById[sid] || sid);

      return {
        codigo: req.code,
        status: req.status,
        orcamento_id: req.service_order_id,
        criada_em: req.created_at,
        comparativo,
        fornecedores_sem_resposta: semResposta,
        aviso: "Preços vêm de extração — confirme antes de aplicar custo ou gerar ordem de compra.",
      };
    },
  },
  {
    name: "record_quote_response",
    description:
      "Registra o preço/prazo que UM fornecedor respondeu para UM item de uma cotação. Use ao ler a resposta do fornecedor (texto, áudio transcrito, PDF ou imagem). Sempre preencha source_excerpt com o trecho exato de onde tirou o número — é o que permite auditar. NÃO aplica custo no orçamento (isso é apply_quote_price).",
    input_schema: {
      type: "object",
      properties: {
        quote_request_id: { type: "string", description: "UUID da cotação (ou use code)." },
        code: { type: "string", description: "Código COT-XXXXX (alternativa ao id)." },
        supplier_id: { type: "string", description: "UUID do fornecedor que respondeu." },
        item_position: { type: "number", description: "Número do item na cotação (1, 2, 3...)." },
        unit_price: { type: "number", description: "Preço unitário em R$." },
        lead_time_days: { type: "number", description: "Prazo de entrega em dias." },
        source: { type: "string", enum: ["text", "audio", "pdf", "image", "manual"], description: "De onde veio a informação." },
        source_excerpt: { type: "string", description: "Trecho exato da resposta de onde saiu o preço/prazo." },
      },
      required: ["supplier_id", "item_position"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      if (!args.quote_request_id && !args.code) return { error: "Informe quote_request_id ou code (COT-XXXXX)." };

      let q = sb.from("quote_requests").select("id, code, status");
      q = args.quote_request_id ? q.eq("id", args.quote_request_id) : q.eq("code", String(args.code).toUpperCase());
      const { data: req } = await q.maybeSingle();
      if (!req) return { error: "Cotação não encontrada." };
      if (req.status !== "open") return { error: `Cotação ${req.code} está ${req.status} — reabra antes de registrar respostas.` };

      const { data: item } = await sb
        .from("quote_request_items")
        .select("id, description")
        .eq("quote_request_id", req.id)
        .eq("position", Number(args.item_position))
        .maybeSingle();
      if (!item) return { error: `Item ${args.item_position} não existe na cotação ${req.code}.` };

      const { data, error } = await sb
        .from("quote_responses")
        .insert({
          quote_request_id: req.id,
          supplier_id: args.supplier_id,
          quote_request_item_id: item.id,
          unit_price: args.unit_price ?? null,
          lead_time_days: args.lead_time_days ?? null,
          source: args.source || "text",
          source_excerpt: args.source_excerpt ?? null,
          confirmed: false,
        })
        .select("id")
        .single();
      if (error) throw error;

      return {
        ok: true,
        response_id: data.id,
        cotacao: req.code,
        item: `${args.item_position}. ${item.description}`,
        registrado: { preco_unitario: args.unit_price ?? null, prazo_dias: args.lead_time_days ?? null, origem: args.source || "text" },
        aviso: "Registrado como proposta. Nada foi aplicado ao orçamento ainda.",
      };
    },
  },
  {
    name: "read_supplier_messages",
    description:
      "Lê as mensagens recentes RECEBIDAS de um fornecedor no WhatsApp e mostra, junto, as cotações abertas dele com os itens numerados. Use quando o usuário disser 'o fornecedor X respondeu' / 'lê a resposta do X'. Depois de ler, registre cada preço com record_quote_response (preenchendo source_excerpt com o trecho exato). Se a resposta vier como áudio, imagem ou PDF, isto será sinalizado — avise o usuário que ainda não leio esse formato e peça o valor por texto.",
    input_schema: {
      type: "object",
      properties: {
        supplier_id: { type: "string", description: "UUID do fornecedor." },
        days: { type: "number", description: "Janela em dias (padrão 7)." },
        limit: { type: "number", description: "Máximo de mensagens (padrão 20, teto 50)." },
      },
      required: ["supplier_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;

      const { data: sup } = await sb.from("suppliers").select("id, name, phone").eq("id", args.supplier_id).maybeSingle();
      if (!sup) return { error: "Fornecedor não encontrado." };
      if (!sup.phone) return { error: `${sup.name} não tem WhatsApp cadastrado.` };

      // Resolução oficial: usa o VÍNCULO gravado (supplier_id) e, como rede de segurança, o
      // casamento por telefone pelos últimos 8 dígitos (imune ao 9º dígito). Ver _shared/ai/phone.ts.
      const chave = chaveTelefone(sup.phone);
      if (!chave) return { error: "Telefone do fornecedor é curto demais para casar mensagens." };

      const since = new Date(Date.now() - (Number(args.days) || 7) * 86400000).toISOString();
      const teto = Math.min(Number(args.limit) || 20, 50);
      const colunas = "id, body, message_type, occurred_at, created_at, wa_message_id";

      // Duas consultas simples em vez de um .or() composto: o filtro combinado do PostgREST
      // seria mais enxuto, mas esta forma é determinística e fácil de conferir. Mescla e
      // deduplica por id — uma mensagem pode casar pelos dois critérios.
      const [porVinculo, porTelefone] = await Promise.all([
        sb.from("whatsapp_messages").select(colunas)
          .eq("direction", "inbound").eq("supplier_id", sup.id)
          .gte("created_at", since).order("created_at", { ascending: false }).limit(teto),
        sb.from("whatsapp_messages").select(colunas)
          .eq("direction", "inbound").like("phone_normalized", `%${chave}`)
          .gte("created_at", since).order("created_at", { ascending: false }).limit(teto),
      ]);
      if (porVinculo.error) throw porVinculo.error;
      if (porTelefone.error) throw porTelefone.error;

      const porId = new Map<string, any>();
      for (const m of [...(porVinculo.data || []), ...(porTelefone.data || [])]) porId.set(m.id, m);
      const msgs = [...porId.values()]
        .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
        .slice(0, teto);

      // Cotações abertas em que este fornecedor foi incluído — o contexto para extrair.
      const { data: reqs } = await sb
        .from("quote_requests")
        .select("id, code, created_at")
        .eq("status", "open")
        .contains("sent_supplier_ids", [sup.id])
        .order("created_at", { ascending: false })
        .limit(5);
      const cotacoes = [];
      for (const r of (reqs as any[]) || []) {
        const { data: its } = await sb
          .from("quote_request_items")
          .select("position, description, quantity")
          .eq("quote_request_id", r.id)
          .order("position", { ascending: true });
        cotacoes.push({
          quote_request_id: r.id,
          codigo: r.code,
          itens: (its || []).map((i: any) => ({ n: i.position, descricao: i.description, quantidade: Number(i.quantity) })),
        });
      }

      const mensagens = (msgs || []).map((m: any) => {
        const b = String(m.body || "").trim();
        // Mídia ainda NÃO lida (só o marcador cru do webhook).
        const naoLida = b === "[image]" ? "imagem" : b === "[document]" ? "pdf/arquivo" : b === "[audio]" ? "audio" : b === "[video]" ? "video" : null;
        // Já convertida em texto: 🎤 áudio transcrito, 📄 PDF lido, 📷 imagem lida.
        const origem = b.startsWith("🎤") ? "audio" : b.startsWith("📄") ? "pdf" : b.startsWith("📷") ? "image" : "text";
        return {
          quando: m.occurred_at || m.created_at,
          message_id: m.id, // use este id em read_supplier_media
          origem, // use como `source` no record_quote_response
          texto: naoLida ? null : b,
          midia_nao_lida: naoLida,
        };
      });

      const temNaoLida = mensagens.some((m: any) => m.midia_nao_lida === "imagem" || m.midia_nao_lida === "pdf/arquivo");
      const notas: string[] = [];
      if (cotacoes.length === 0) notas.push("Este fornecedor não tem cotação aberta — confirme com o usuário a qual cotação a resposta pertence.");
      if (cotacoes.length > 1) notas.push("Há MAIS DE UMA cotação aberta com este fornecedor — pergunte ao usuário a qual a resposta se refere.");
      if (temNaoLida) notas.push("Há PDF/imagem ainda não lido — chame read_supplier_media(message_id) para converter em texto antes de registrar preços.");

      return {
        fornecedor: sup.name,
        cotacoes_abertas: cotacoes,
        mensagens,
        nota: notas.length ? notas.join(" ") : null,
      };
    },
  },
  {
    name: "create_purchase_order_from_quote",
    description:
      "Gera a ORDEM DE COMPRA de UM fornecedor a partir dos preços já ESCOLHIDOS numa cotação (os que passaram por apply_quote_price). Fecha o ciclo: cotou → escolheu → custo no orçamento → OC pro fornecedor. Funciona tanto com item do catálogo quanto com item de texto livre. Só inclui preços confirmados — se nada foi escolhido ainda, avisa e não cria nada.",
    input_schema: {
      type: "object",
      properties: {
        quote_request_id: { type: "string", description: "UUID da cotação (ou use code)." },
        code: { type: "string", description: "Código COT-XXXXX (alternativa ao id)." },
        supplier_id: { type: "string", description: "Fornecedor escolhido — a OC é por fornecedor." },
        expected_date: { type: "string", description: "Data prevista de entrega (ISO), opcional." },
        notes: { type: "string", description: "Observação na OC, opcional." },
      },
      required: ["supplier_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb, admin, userId } = ctx;
      if (!args.quote_request_id && !args.code) return { error: "Informe quote_request_id ou code (COT-XXXXX)." };

      let q = sb.from("quote_requests").select("id, code, service_order_id");
      q = args.quote_request_id ? q.eq("id", args.quote_request_id) : q.eq("code", String(args.code).toUpperCase());
      const { data: req } = await q.maybeSingle();
      if (!req) return { error: "Cotação não encontrada." };

      const { data: resps } = await sb
        .from("quote_responses")
        .select("id, quote_request_item_id, unit_price")
        .eq("quote_request_id", req.id)
        .eq("supplier_id", args.supplier_id)
        .eq("confirmed", true);
      if (!resps || resps.length === 0) {
        return { error: "Nenhum preço confirmado desse fornecedor nesta cotação. Use apply_quote_price para escolher antes de gerar a OC." };
      }

      const itemIds = resps.map((r: any) => r.quote_request_item_id).filter(Boolean);
      const { data: items } = await sb
        .from("quote_request_items")
        .select("id, product_id, description, quantity")
        .in("id", itemIds);
      const itemById: Record<string, any> = Object.fromEntries((items || []).map((i: any) => [i.id, i]));

      const linhas = resps
        .map((r: any) => {
          const it = itemById[r.quote_request_item_id];
          if (!it) return null;
          const qty = Number(it.quantity) || 1;
          const cost = Number(r.unit_price) || 0;
          return { product_id: it.product_id ?? null, description: it.description, quantity: qty, unit_cost: cost, subtotal: qty * cost };
        })
        .filter(Boolean) as Array<Record<string, any>>;
      if (linhas.length === 0) return { error: "Não consegui montar os itens da OC a partir da cotação." };

      const total = Math.round(linhas.reduce((a, l) => a + Number(l.subtotal), 0) * 100) / 100;
      const poNumber = await generatePONumber(admin);

      // created_by e total_amount são NOT NULL nesta tabela — preenchidos explicitamente.
      const { data: po, error: poErr } = await sb
        .from("purchase_orders")
        .insert({
          po_number: poNumber,
          supplier_id: args.supplier_id,
          service_order_id: req.service_order_id ?? null,
          expected_date: args.expected_date ?? null,
          notes: args.notes ?? `Gerada da cotação ${req.code}`,
          status: "draft",
          total_amount: total,
          created_by: userId,
        })
        .select("id, po_number")
        .single();
      if (poErr) throw poErr;

      const { error: itErr } = await sb.from("purchase_order_items").insert(
        linhas.map((l) => ({
          purchase_order_id: po.id,
          product_id: l.product_id,
          description: l.description,
          quantity: l.quantity,
          unit_cost: l.unit_cost,
        })),
      );
      if (itErr) throw itErr;

      const { data: sup } = await sb.from("suppliers").select("name").eq("id", args.supplier_id).maybeSingle();
      return {
        ok: true,
        ordem_de_compra: po.po_number,
        purchase_order_id: po.id,
        fornecedor: sup?.name || args.supplier_id,
        cotacao: req.code,
        itens: linhas.map((l) => ({ descricao: l.description, quantidade: l.quantity, custo_unitario: l.unit_cost })),
        total,
      };
    },
  },
  {
    name: "read_supplier_media",
    description:
      "Converte em TEXTO um PDF ou IMAGEM que o fornecedor mandou no WhatsApp (ex.: orçamento em PDF, foto da cotação). Use quando read_supplier_messages sinalizar 'midia_nao_lida'. Depois de ler, registre os preços com record_quote_response usando source='pdf' ou 'image' e o trecho extraído em source_excerpt. Se a mídia for antiga, pode ter expirado — nesse caso peça o valor por texto ao usuário.",
    input_schema: {
      type: "object",
      properties: {
        message_id: { type: "string", description: "UUID da mensagem (campo message_id de read_supplier_messages)." },
      },
      required: ["message_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      try {
        const r = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/whatsapp-read-media`, {
          method: "POST",
          // Só Authorization com service-role (sem `apikey`) — mesma lição do envio de WhatsApp:
          // apikey anon junto de bearer service_role faz o gateway devolver 401.
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
          },
          body: JSON.stringify({ message_id: args.message_id }),
        });
        const body = await r.json().catch(() => ({}));
        if (!r.ok) return { error: (body as any)?.error || `HTTP ${r.status}` };
        if ((body as any)?.ok === false) {
          return { error: (body as any)?.error || (body as any)?.disabled || "não foi possível ler a mídia", dica: "Peça ao usuário o preço por texto." };
        }
        return { ok: true, tipo: (body as any)?.kind || null, texto: (body as any)?.text || (body as any)?.skipped || null };
      } catch (e: any) {
        return { error: e?.message || "falha ao ler a mídia" };
      }
    },
  },
  {
    name: "apply_quote_price",
    description:
      "Aplica o preço cotado de UM fornecedor ao item do ORÇAMENTO de origem e recalcula total e margem. É o passo final da cotação — use SÓ depois que o usuário escolher explicitamente qual fornecedor. PEÇA do catálogo: o preço vira CUSTO do item (margem recalcula). MATERIAL/SERVIÇO de texto livre: não existe campo de custo no sistema, então é preciso markup_percent para definir o PREÇO DE VENDA — sem ele a tool explica e não altera nada.",
    input_schema: {
      type: "object",
      properties: {
        response_id: { type: "string", description: "UUID da resposta escolhida (campo response_id de get_quote_comparison)." },
        markup_percent: { type: "number", description: "Margem sobre o custo, em % (ex.: 40 = vender por custo x1,4). Obrigatório para material/serviço; opcional para peça (se informado, também ajusta o preço de venda)." },
      },
      required: ["response_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;

      const { data: resp } = await sb
        .from("quote_responses")
        .select("id, quote_request_id, supplier_id, quote_request_item_id, unit_price")
        .eq("id", args.response_id)
        .maybeSingle();
      if (!resp) return { error: "Resposta de cotação não encontrada." };
      if (resp.unit_price == null) return { error: "Essa resposta não tem preço registrado." };
      const preco = Number(resp.unit_price);

      const { data: item } = await sb
        .from("quote_request_items")
        .select("id, description, service_order_part_id, service_order_service_id")
        .eq("id", resp.quote_request_item_id)
        .maybeSingle();
      if (!item) return { error: "Item da cotação não encontrado." };
      if (!item.service_order_part_id && !item.service_order_service_id) {
        return { error: "Esse item da cotação não está amarrado a nenhuma linha de orçamento — não há onde aplicar o preço." };
      }

      const { data: req } = await sb.from("quote_requests").select("id, code, service_order_id").eq("id", resp.quote_request_id).maybeSingle();
      const soId = req?.service_order_id;
      if (!soId) return { error: "Essa cotação não tem orçamento de origem." };

      const { data: so } = await sb.from("service_orders").select("status").eq("id", soId).maybeSingle();
      if (!so) return { error: "Orçamento/OS de origem não encontrado." };
      if (so.status === "cancelled") return { error: "OS cancelada não pode ser alterada." };
      if (so.status === "invoiced") return { error: "OS já faturada não pode ter valores alterados." };

      const markup = args.markup_percent != null ? Number(args.markup_percent) : null;
      if (markup != null && markup < 0) return { error: "markup_percent não pode ser negativo." };
      const precoVenda = markup != null ? Math.round(preco * (1 + markup / 100) * 100) / 100 : null;

      let antes: Record<string, unknown> = {};
      let depois: Record<string, unknown> = {};

      if (item.service_order_part_id) {
        const { data: part } = await sb
          .from("service_order_parts")
          .select("id, quantity, unit_cost_snapshot, unit_sale_snapshot")
          .eq("id", item.service_order_part_id)
          .maybeSingle();
        if (!part) return { error: "A linha de peça do orçamento não existe mais." };
        const qty = Number(part.quantity) || 1;
        antes = { custo_unitario: Number(part.unit_cost_snapshot) || 0, preco_venda: Number(part.unit_sale_snapshot) || 0 };

        const upd: Record<string, unknown> = { unit_cost_snapshot: preco, line_total_cost: preco * qty };
        if (precoVenda != null) {
          upd.unit_sale_snapshot = precoVenda;
          upd.line_total_sale = precoVenda * qty;
        }
        const { error } = await sb.from("service_order_parts").update(upd).eq("id", part.id);
        if (error) throw error;
        depois = { custo_unitario: preco, preco_venda: precoVenda ?? (Number(part.unit_sale_snapshot) || 0) };
      } else {
        // Material/serviço de texto livre: NÃO existe coluna de custo — só dá pra mexer no preço de venda.
        if (precoVenda == null) {
          return {
            needs_markup: true,
            message: `"${item.description}" é material/serviço (texto livre) e o sistema não guarda custo nessa linha. Custo cotado: R$ ${preco.toFixed(2)}. Me diga a margem (markup_percent) que eu aplico o preço de venda — ou aplique o valor manualmente com edit_service_order_item.`,
            custo_cotado: preco,
          };
        }
        const { data: svc } = await sb
          .from("service_order_services")
          .select("id, quantity, unit_price_snapshot")
          .eq("id", item.service_order_service_id)
          .maybeSingle();
        if (!svc) return { error: "A linha de material/serviço do orçamento não existe mais." };
        const qty = Number(svc.quantity) || 1;
        antes = { preco_venda: Number(svc.unit_price_snapshot) || 0 };
        const { error } = await sb
          .from("service_order_services")
          .update({ unit_price_snapshot: precoVenda, line_total: precoVenda * qty })
          .eq("id", svc.id);
        if (error) throw error;
        depois = { preco_venda: precoVenda, custo_cotado: preco };
      }

      // Marca a escolhida e desmarca as concorrentes do MESMO item.
      await sb.from("quote_responses").update({ confirmed: false }).eq("quote_request_item_id", item.id);
      await sb.from("quote_responses").update({ confirmed: true }).eq("id", resp.id);

      try { await sb.rpc("recalc_so_totals", { so_id: soId }); } catch { /* best-effort */ }

      const { data: soAfter } = await sb.from("service_orders").select("grand_total").eq("id", soId).maybeSingle();
      const { data: partsCost } = await sb.from("service_order_parts").select("line_total_cost").eq("service_order_id", soId);
      const custoPecas = (partsCost || []).reduce((a: number, p: any) => a + (Number(p.line_total_cost) || 0), 0);
      const grand = Number(soAfter?.grand_total) || 0;
      const margem = grand > 0 ? Math.round(((grand - custoPecas) / grand) * 1000) / 10 : null;

      const { data: sup } = await sb.from("suppliers").select("name").eq("id", resp.supplier_id).maybeSingle();

      return {
        ok: true,
        cotacao: req?.code,
        item: item.description,
        fornecedor: sup?.name || resp.supplier_id,
        antes,
        depois,
        total_orcamento: grand,
        margem_bruta_pct: margem,
      };
    },
  },
];
