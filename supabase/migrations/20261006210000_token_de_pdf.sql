-- Token de uso único para o servidor de PDF (/api/pdf), para documento que não é de uma ordem.
--
-- POR QUE (pedido do dono, 06/10/2026): "me manda o extrato do Roberto em PDF" pelo WhatsApp, "da
-- mesma forma como o PDF do orçamento". O /api/pdf (Chromium no Vercel) só renderiza para quem tem
-- o JWT de um usuário logado ou o share_token de UMA ORDEM (o portal do cliente). No WhatsApp não
-- há JWT — o assistente roda com a chave de serviço — e extrato de freelancer não tem ordem.
--
-- COMO: a edge function (só ela: service_role) pede um token aleatório de 256 bits, que vale 3
-- minutos e UMA chamada; o /api/pdf o consome (apaga) ao conferir. Usado ou vencido, não serve mais.
-- O token não vai para mensagem, legenda nem log — só no cabeçalho x-pdf-token da chamada ao PDF.

create table if not exists public.tokens_de_pdf (
  token text primary key,
  finalidade text not null,
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null default now() + interval '3 minutes'
);

comment on table public.tokens_de_pdf is
  'Credencial de uso único do /api/pdf para documentos sem ordem (extrato de diárias pelo assistente). Só service_role emite; o /api/pdf consome.';

-- Ninguém lê nem escreve pela API: só as duas funções abaixo (e a chave de serviço).
alter table public.tokens_de_pdf enable row level security;
revoke all on public.tokens_de_pdf from public, anon, authenticated;

create or replace function public.emitir_token_de_pdf(p_finalidade text)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if nullif(btrim(coalesce(p_finalidade, '')), '') is null then
    raise exception 'Diga para que é o token (ex.: extrato de diárias).';
  end if;
  delete from public.tokens_de_pdf where expira_em < now();
  insert into public.tokens_de_pdf (token, finalidade) values (v_token, btrim(p_finalidade));
  return v_token;
end;
$$;

-- Vale uma vez: confere e apaga na mesma instrução. Anon PODE chamar (o /api/pdf usa a chave
-- publicável); sem o token certo, devolve false e não revela nada.
create or replace function public.consumir_token_de_pdf(p_token text)
returns boolean
language sql
volatile
security definer
set search_path = public
as $$
  with usado as (
    delete from public.tokens_de_pdf
     where token = p_token and expira_em > now() and length(coalesce(p_token, '')) >= 32
    returning 1
  )
  select exists (select 1 from usado);
$$;

revoke all on function public.emitir_token_de_pdf(text) from public, anon, authenticated;
grant execute on function public.emitir_token_de_pdf(text) to service_role;
revoke all on function public.consumir_token_de_pdf(text) from public;
grant execute on function public.consumir_token_de_pdf(text) to anon, authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261006210000', 'token_de_pdf')
on conflict (version) do nothing;
