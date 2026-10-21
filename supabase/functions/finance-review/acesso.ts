// Quem pode mexer na fila do Extrato pela edge finance-review (20/10/2026, spec-papelada-fix.md, item A3).
//
// Até aqui a edge conferia só o LOGIN (auth.getUser): qualquer pessoa com conta no app — um técnico, um
// vendedor — podia aprovar, recusar, desfazer e gerar propostas chamando a função direto, porque ela
// escreve com a chave de serviço (a RLS das tabelas não vale para ela). A tela já é só de admin e
// financeiro (ProtectedRoute roles={['admin','financial']}) e as tools do assistente também
// (CARGOS_FINANCEIRO); a edge agora diz o mesmo, com a MESMA função do banco que as RPCs do financeiro
// usam (is_admin_or_financial: app_users.role in ('admin','financial') e active).
//
// Vale para o JWT da tela e para a chamada interna que diz quem decide (x-cron-secret + acting_user_id:
// o assistente pelo WhatsApp, o sim do comprovante, o lote da papelada). A rodada agendada sem
// acting_user_id (generate/vigiar pelo cron) continua como antes: não é decisão de ninguém.
// Medido em 20/10/2026: 1 admin ativo (todas as 1.844 decisões da fila), 1 financeiro ativo (nenhuma
// decisão), nenhum outro cargo ativo — a trava não muda nada para quem usa hoje.
//
// Fecha na dúvida: se a conferência falhar, a ação não roda (503), em vez de rodar sem saber quem é.

// deno-lint-ignore no-explicit-any
type Admin = any;

export type Conferencia = { ok: true } | { ok: false; status: number; erro: string };

export const FRASE_SEM_CARGO = "Só administrador ou financeiro mexe na fila do Extrato";

export async function conferirCargo(admin: Admin, userId: string | null): Promise<Conferencia> {
  if (!userId) return { ok: false, status: 401, erro: "unauthorized" };
  try {
    const { data, error } = await admin.rpc("is_admin_or_financial", { _user_id: userId });
    if (error) return { ok: false, status: 503, erro: "Não consegui conferir o seu cargo agora — tente de novo em instantes" };
    if (data !== true) return { ok: false, status: 403, erro: FRASE_SEM_CARGO };
    return { ok: true };
  } catch {
    return { ok: false, status: 503, erro: "Não consegui conferir o seu cargo agora — tente de novo em instantes" };
  }
}
