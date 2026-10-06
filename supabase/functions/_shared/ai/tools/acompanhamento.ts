// Acompanhar conversa e lembrar de responder (06/10/2026, plans/marineflow-acompanhar-conversa.md).
//
// "Acompanhe a conversa do Miguel e me mantenha informado" → acompanhar_conversa: o vigia
// acompanhar-conversas avisa o dono, no intervalo, quando o Miguel está esperando resposta — e já
// traz a sugestão de resposta para confirmar. "Me lembra de responder o Nelson às 14h" → o mesmo,
// com lembrar_em (aviso único). Interno: não fala com ninguém além do dono, por isso risco baixo.
import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolCtx, type ToolDef } from "./registry.ts";
import { horarioDoAgendamento, quandoPorExtenso, telefoneLegivel, telefoneParaEnvio } from "./agendamento.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Contato = { phone: string; nome: string | null };

/** "Miguel", "47 99915-9654" ou o cliente do cadastro → o número da conversa e o nome. */
export async function resolverContato(
  ctx: Pick<ToolCtx, "admin">,
  args: Record<string, unknown>,
): Promise<Contato | { error: string; opcoes?: string[] }> {
  const { admin } = ctx;
  if (args.client_id) {
    const { data: c } = await admin.from("clients").select("name, display_name, whatsapp, phone").eq("id", args.client_id).maybeSingle();
    const phone = telefoneParaEnvio(c?.whatsapp || c?.phone);
    if (!phone) return { error: "Esse cliente não tem WhatsApp/telefone no cadastro." };
    return { phone, nome: c?.display_name || c?.name || null };
  }
  if (args.phone) {
    const phone = telefoneParaEnvio(args.phone);
    if (!phone) return { error: `Número "${String(args.phone)}" inválido. Peça o WhatsApp com DDD.` };
    const { data: l } = await admin.from("whatsapp_leads").select("name").eq("phone_normalized", phone).maybeSingle();
    return { phone, nome: l?.name || (typeof args.contato === "string" ? args.contato : null) };
  }
  const nome = String(args.contato ?? "").trim();
  if (!nome) return { error: "Diga de quem é a conversa (nome, número ou cliente)." };
  const termo = `%${nome.replace(/[%_]/g, "")}%`;
  const [{ data: leads }, { data: clientes }] = await Promise.all([
    admin.from("whatsapp_leads").select("name, phone_normalized").ilike("name", termo).limit(6),
    admin.from("clients").select("name, display_name, whatsapp, phone").ilike("name", termo).limit(6),
  ]);
  const achados = new Map<string, string>();
  for (const c of (clientes ?? []) as any[]) {
    const p = telefoneParaEnvio(c.whatsapp || c.phone);
    if (p) achados.set(p, c.display_name || c.name);
  }
  for (const l of (leads ?? []) as any[]) {
    if (l.phone_normalized && !achados.has(l.phone_normalized)) achados.set(l.phone_normalized, l.name);
  }
  if (achados.size === 0) return { error: `Não achei conversa de "${nome}". Peça o número ou o nome como está no WhatsApp.` };
  if (achados.size > 1) {
    return {
      error: `Há ${achados.size} conversas para "${nome}". Pergunte qual (ou peça o número).`,
      opcoes: [...achados].map(([p, n]) => `${n} — ${telefoneLegivel(p)}`),
    };
  }
  const [[phone, nomeAchado]] = [...achados];
  return { phone, nome: nomeAchado };
}

function prazo(bruto: unknown, agora: Date): Date | { error: string } {
  if (bruto === undefined || bruto === null || bruto === "") return new Date(agora.getTime() + 7 * 24 * 3600 * 1000);
  const s = String(bruto).trim();
  const d = new Date(/^\d{4}-\d{2}-\d{2}$/.test(s) ? `${s}T20:00:00-03:00` : /[zZ]|[+-]\d{2}:?\d{2}$/.test(s) ? s : `${s}-03:00`);
  if (!Number.isFinite(d.getTime()) || d.getTime() <= agora.getTime()) return { error: `Prazo "${s}" inválido ou já passado.` };
  return d;
}

export const acompanhamentoTools: ToolDef[] = [
  {
    name: "acompanhar_conversa",
    description:
      "ACOMPANHA uma conversa do WhatsApp PARA O USUÁRIO: quando o contato estiver esperando resposta há mais que o intervalo, o sistema avisa o usuário no WhatsApp e já traz a sugestão de resposta para ele confirmar. " +
      "Use para 'acompanhe a conversa do Miguel', 'me mantenha informado do Nelson', 'me avisa se o Juliano responder e eu não'. " +
      "Com lembrar_em vira LEMBRETE ÚNICO de responder: 'me lembra de responder o Nelson às 14h'. " +
      "Contato: contato (nome), phone ou client_id. Não fala com o contato — só avisa o usuário. Avisos só entre 8h e 20h (seg–sáb), no máximo 3 por conversa por dia.",
    input_schema: {
      type: "object",
      properties: {
        contato: { type: "string", description: "Nome do contato como está no WhatsApp ou no cadastro." },
        phone: { type: "string", description: "Número do contato (qualquer formato)." },
        client_id: { type: "string", description: "UUID do cliente do cadastro." },
        intervalo_horas: { type: "number", description: "De quanto em quanto tempo avisar enquanto ele espera resposta (padrão 2h; mínimo 0,25)." },
        ate: { type: "string", description: "Até quando acompanhar (data ou data/hora; padrão: 7 dias)." },
        lembrar_em: { type: "string", description: "Lembrete único de responder nesta hora (horário de Brasília, ex.: 2026-10-07T14:00)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const contato = await resolverContato(ctx, args);
      if ("error" in contato) return contato;
      const agora = new Date();
      const { admin, userId } = ctx;

      if (args.lembrar_em) {
        const hora = horarioDoAgendamento(args.lembrar_em, agora);
        if ("error" in hora) return hora;
        const { error } = await admin.from("whatsapp_acompanhamentos").insert({
          phone_normalized: contato.phone, contato: contato.nome, modo: "lembrar_em", lembrar_em: hora.iso, criado_por: userId,
        });
        if (error) throw error;
        return {
          ok: true,
          lembrete: `${quandoPorExtenso(hora.iso)} (Brasília)`,
          contato: contato.nome,
          whatsapp: telefoneLegivel(contato.phone),
          orientacao: "Confirme ao usuário em uma linha: quando vai lembrar e de quem. Diga que o aviso já virá com a sugestão de resposta.",
        };
      }

      const horas = args.intervalo_horas === undefined ? 2 : Number(args.intervalo_horas);
      if (!Number.isFinite(horas) || horas < 0.25 || horas > 168) return { error: "Intervalo entre 15 minutos (0,25h) e 7 dias." };
      const ate = prazo(args.ate, agora);
      if ("error" in ate) return ate;
      const linha = {
        phone_normalized: contato.phone, contato: contato.nome, modo: "acompanhar",
        intervalo_min: Math.round(horas * 60), ate: ate.toISOString(), criado_por: userId,
      };
      // Pedir de novo atualiza o acompanhamento que já existe (um por conversa).
      const { data: existente } = await admin.from("whatsapp_acompanhamentos").select("id")
        .eq("phone_normalized", contato.phone).eq("modo", "acompanhar").eq("status", "ativo").maybeSingle();
      const { error } = existente
        ? await admin.from("whatsapp_acompanhamentos").update({ ...linha, updated_at: agora.toISOString() }).eq("id", existente.id)
        : await admin.from("whatsapp_acompanhamentos").insert(linha);
      if (error) throw error;
      return {
        ok: true,
        acompanhando: contato.nome || telefoneLegivel(contato.phone),
        whatsapp: telefoneLegivel(contato.phone),
        intervalo: horas >= 1 ? `${horas}h` : `${Math.round(horas * 60)} min`,
        ate: quandoPorExtenso(ate.toISOString()),
        ...(existente ? { atualizado: true } : {}),
        orientacao: "Confirme ao usuário em uma linha: de quem, de quanto em quanto tempo e até quando. Avisos só entre 8h e 20h (seg–sáb).",
      };
    },
  },
  {
    name: "listar_acompanhamentos",
    description: "Lista as conversas acompanhadas, os lembretes de responder e as promessas que o sistema vai lembrar.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(_args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { data, error } = await ctx.admin.from("whatsapp_acompanhamentos")
        .select("id, contato, phone_normalized, modo, intervalo_min, ate, lembrar_em, promessa, ultimo_aviso_em")
        .eq("status", "ativo").order("created_at", { ascending: true }).limit(30);
      if (error) throw error;
      return {
        total: (data ?? []).length,
        itens: (data ?? []).map((a: any) => ({
          id: a.id,
          contato: a.contato || telefoneLegivel(a.phone_normalized),
          tipo: a.modo === "acompanhar" ? "acompanhando" : a.modo === "lembrar_em" ? "lembrete de responder" : "promessa",
          ...(a.modo === "acompanhar"
            ? { intervalo: `${a.intervalo_min / 60}h`, ate: quandoPorExtenso(a.ate) }
            : { quando: quandoPorExtenso(a.lembrar_em) }),
          ...(a.promessa ? { promessa: a.promessa } : {}),
          ...(a.ultimo_aviso_em ? { ultimo_aviso: quandoPorExtenso(a.ultimo_aviso_em) } : {}),
        })),
      };
    },
  },
  {
    name: "parar_acompanhamento",
    description: "Para de acompanhar uma conversa ou cancela um lembrete/promessa: 'para de acompanhar o Miguel', 'esquece o lembrete do Nelson', 'já resolvi a promessa do frete'. Informe contato/phone/client_id (encerra tudo daquele contato) ou o id.",
    input_schema: {
      type: "object",
      properties: {
        id: { type: "string", description: "id de listar_acompanhamentos (encerra só esse)." },
        contato: { type: "string" },
        phone: { type: "string" },
        client_id: { type: "string" },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const fim = { status: "encerrado", encerrado_motivo: "pedido do dono", updated_at: new Date().toISOString() };
      let q = admin.from("whatsapp_acompanhamentos").update(fim).eq("status", "ativo");
      if (args.id && UUID_RE.test(String(args.id))) {
        q = q.eq("id", args.id);
      } else {
        const contato = await resolverContato(ctx, args);
        if ("error" in contato) return contato;
        q = q.eq("phone_normalized", contato.phone);
      }
      const { data, error } = await q.select("id");
      if (error) throw error;
      const n = (data ?? []).length;
      return n ? { ok: true, encerrados: n } : { ok: true, encerrados: 0, aviso: "Não havia acompanhamento ativo para isso." };
    },
  },
];
