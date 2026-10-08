// Edge Function: email-responder — envia UMA resposta que o dono aprovou (08/10/2026, etapa 5).
//
// Quem chama: a tool enviar_resposta_email, que é de risco ALTO — só roda depois do "sim" do dono
// (pendência confirmada). Aqui não se decide nada: recebe o id do rascunho, confere que ele ainda é
// rascunho e que o e-mail original pode ser respondido (_shared/email/resposta.ts), e envia pela
// MESMA caixa que recebeu (SMTP da GoDaddy, senha do segredo da caixa), como resposta na mesma
// conversa (In-Reply-To/References). Depois guarda uma cópia em Enviados (IMAP APPEND) para a
// resposta aparecer no programa de e-mail do dono.
//
// Autenticação: x-cron-secret (chamada interna do assistente) ou JWT de admin.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import nodemailer from "npm:nodemailer@6.9.10";
import MailComposer from "npm:nodemailer@6.9.10/lib/mail-composer/index.js";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { timingSafeEqual } from "../_shared/cron-auth.ts";
import { ClienteImap } from "../_shared/email/imap.ts";
import { cabecalhosDeResposta, pastaDeEnviados, podeResponder } from "../_shared/email/resposta.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};
const jr = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, "Content-Type": "application/json" } });

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  // Interno (assistente, com o segredo do cron) ou administrador logado.
  const segredo = req.headers.get("x-cron-secret") ?? "";
  const esperado = Deno.env.get("CRON_SECRET") ?? "";
  if (!(esperado && segredo && timingSafeEqual(segredo, esperado))) {
    const token = (req.headers.get("Authorization") || "").replace("Bearer ", "");
    const { data: u } = token ? await admin.auth.getUser(token) : { data: null };
    if (!u?.user) return jr({ error: "unauthorized" }, 401);
    const { data: perfil } = await admin.from("app_users").select("role, active").eq("id", u.user.id).maybeSingle();
    if (perfil?.role !== "admin" || perfil.active === false) return jr({ error: "forbidden" }, 403);
  }

  const body = await req.json().catch(() => ({}));
  const id = String(body.rascunho_id ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(id)) return jr({ error: "rascunho_id inválido" }, 400);

  const { data: r, error: rErr } = await admin.from("email_respostas")
    .select("id, status, para, assunto, texto, message_id, account_id").eq("id", id).maybeSingle();
  if (rErr) return jr({ error: `não li o rascunho: ${rErr.message}` }, 500);
  if (!r) return jr({ error: "rascunho não encontrado" }, 404);
  if (r.status !== "rascunho") return jr({ error: `esse rascunho já está ${r.status}` }, 409);

  const [{ data: m }, { data: conta }] = await Promise.all([
    admin.from("email_messages").select("message_id, references_ids, from_address, triage_class, muted, client_id, supplier_id").eq("id", r.message_id).maybeSingle(),
    admin.from("email_accounts").select("address, label, secret_name, imap_host, imap_port").eq("id", r.account_id).maybeSingle(),
  ]);
  if (!m || !conta) return jr({ error: "e-mail original ou caixa não encontrados" }, 404);
  const pode = podeResponder(m);
  if (!pode.ok) return jr({ error: `não respondo: ${pode.motivo}` }, 422);
  const senha = Deno.env.get(String(conta.secret_name ?? ""));
  if (!senha) return jr({ error: `segredo ${conta.secret_name} não cadastrado` }, 500);

  const nome = Deno.env.get("SMTP_FROM_NAME") || "HBR Marine";
  const mensagem = new MailComposer({
    from: { name: nome, address: conta.address },
    to: r.para,
    subject: r.assunto,
    text: r.texto,
    headers: cabecalhosDeResposta(m.message_id, m.references_ids),
  });
  const bruto: Uint8Array = await new Promise((ok, falha) => mensagem.compile().build((e: Error | null, b: Uint8Array) => (e ? falha(e) : ok(b))));

  try {
    const porta = Number(Deno.env.get("SMTP_PORT") || 465);
    const transporte = nodemailer.createTransport({
      host: Deno.env.get("SMTP_HOST") || "smtpout.secureserver.net",
      port: porta,
      secure: porta === 465,
      auth: { user: conta.address, pass: senha },
    });
    await transporte.sendMail({ envelope: { from: conta.address, to: [r.para] }, raw: bruto });
  } catch (e) {
    const erro = String((e as Error)?.message ?? e).slice(0, 300);
    await admin.from("email_respostas").update({ status: "falhou", erro }).eq("id", id);
    return jr({ error: `o envio falhou: ${erro}` }, 502);
  }
  await admin.from("email_respostas").update({ status: "enviado", enviado_em: new Date().toISOString(), erro: null }).eq("id", id);

  // Cópia em Enviados: se falhar, a resposta já saiu — só avisa.
  let copia: string = "não guardada";
  let cli: ClienteImap | null = null;
  try {
    cli = await ClienteImap.conectar(conta.imap_host ?? "imap.secureserver.net", conta.imap_port ?? 993);
    await cli.login(conta.address, senha);
    const pasta = pastaDeEnviados(await cli.listarPastas());
    if (pasta) {
      await cli.anexarNaPasta(pasta, bruto);
      copia = pasta;
    }
  } catch (e) {
    console.warn("[email-responder] cópia em Enviados falhou:", (e as Error)?.message ?? e);
  } finally {
    await cli?.sair();
  }
  return jr({ ok: true, enviado_de: conta.address, para: r.para, copia_em: copia });
});
