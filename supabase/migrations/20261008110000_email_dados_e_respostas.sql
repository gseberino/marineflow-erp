-- E-mail, etapas 4 e 5 (08/10/2026, dono: "pode seguir com as etapas; o assistente só escreve
-- rascunhos de resposta a e-mails considerados importantes, não automáticos nem propaganda, e
-- somente se eu pedir").
--
-- 4) O que se extrai de cada e-mail, conferido por cálculo (sem IA): NF-e anexa (chave com DV,
--    destinada à HBR, emitente, número, valor) e boletos (linha digitável com DV, valor e
--    vencimento). Nada vira lançamento nem estoque sozinho: a NF-e aparece em Entrada de
--    Mercadoria › "Notas recebidas por e-mail" para conferir e importar; o boleto é informado.
alter table public.email_messages
  add column if not exists dados_extraidos jsonb;

comment on column public.email_messages.dados_extraidos is
  '{ nfes: [{anexo_id, chave, emitente, numero, valor, data, para_empresa}], boletos: [{linha, valor, vencimento}] } — conferido por DV.';

-- 5) Rascunho de resposta: o assistente escreve SÓ quando o dono pede, e o envio só sai com o "sim"
--    dele (ferramenta de risco alto). Fica registrado o que foi escrito, por quem, e se saiu.
create table if not exists public.email_respostas (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.email_messages(id) on delete cascade,
  account_id uuid not null references public.email_accounts(id) on delete cascade,
  para text not null,
  assunto text not null,
  texto text not null,
  status text not null default 'rascunho' check (status in ('rascunho', 'enviado', 'descartado', 'falhou')),
  criado_por uuid,
  criado_em timestamptz not null default now(),
  enviado_em timestamptz,
  erro text
);
create index if not exists email_respostas_message_idx on public.email_respostas (message_id);

alter table public.email_respostas enable row level security;
revoke all on table public.email_respostas from public, anon;
grant select on table public.email_respostas to authenticated;
grant all on table public.email_respostas to service_role;
drop policy if exists email_respostas_admin_select on public.email_respostas;
create policy email_respostas_admin_select on public.email_respostas
  for select to authenticated using (public.is_admin(auth.uid()));

insert into supabase_migrations.schema_migrations (version, name)
values ('20261008110000', 'email_dados_e_respostas');
