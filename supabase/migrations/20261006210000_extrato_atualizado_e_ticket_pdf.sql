-- Extrato atualizado + PDF de relatório pelo assistente (06/10/2026, pedido do dono).
--
-- 1) A idade real do dado de cada banco. O botão "Atualizar extrato" lê o que o Pluggy já
--    trouxe; o MeuPluggy vai ao banco sozinho uma vez a cada 24 h e não aceita pedido de "ir
--    agora". Sem a data do Pluggy, "atualizado agora" parecia querer dizer "tem a compra de
--    agora". banking-sync grava item.lastUpdatedAt e item.nextAutoSyncAt a cada leitura.
alter table public.bank_connections
  add column if not exists provider_updated_at timestamptz,
  add column if not exists provider_next_sync_at timestamptz;

comment on column public.bank_connections.provider_updated_at is
  'Quando o Pluggy foi ao banco por último (item.lastUpdatedAt) — a idade real do extrato.';
comment on column public.bank_connections.provider_next_sync_at is
  'Próxima ida automática do Pluggy ao banco (item.nextAutoSyncAt), quando ele informa.';

-- 2) Tíquete de uso único para o /api/pdf (Vercel). O renderizador aceitava só o JWT de um
--    usuário ou o token do link de uma OS. Relatório financeiro pedido pelo WhatsApp não tem
--    nenhum dos dois (o assistente roda com a chave de serviço). A função do servidor cria um
--    tíquete aleatório que vale 3 minutos; o /api/pdf o gasta pela função abaixo, com a chave
--    pública. Ninguém lê a tabela: sem policy, e sem grant para anon/authenticated.
create table if not exists public.pdf_tickets (
  token uuid primary key default gen_random_uuid(),
  motivo text not null,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null default now() + interval '3 minutes'
);
alter table public.pdf_tickets enable row level security;
revoke all on table public.pdf_tickets from public, anon, authenticated;
grant all on table public.pdf_tickets to service_role;

-- Gasta o tíquete: devolve true uma vez só, e apaga os vencidos de passagem.
create or replace function public.usar_ticket_pdf(p_token uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  delete from public.pdf_tickets where expira_em < now() - interval '1 hour';
  delete from public.pdf_tickets where token = p_token and expira_em > now() returning true into v_ok;
  return coalesce(v_ok, false);
end;
$$;

revoke all on function public.usar_ticket_pdf(uuid) from public;
revoke all on function public.usar_ticket_pdf(uuid) from anon;
revoke all on function public.usar_ticket_pdf(uuid) from authenticated;
-- O /api/pdf chama com a chave pública (anon). O que ela permite: gastar um uuid aleatório que só
-- a função do servidor conhece, nos 3 minutos dele. Não lê, não lista, não cria.
grant execute on function public.usar_ticket_pdf(uuid) to anon, authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261006210000', 'extrato_atualizado_e_ticket_pdf');
