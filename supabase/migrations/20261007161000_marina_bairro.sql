-- Marina guarda o bairro (07/10/2026, defeitos de tela).
--
-- POR QUE: o cadastro de marina (MarinaFormDialog → AddressFields) mostra o campo Bairro — e o CEP
-- até o preenche sozinho —, mas a tabela não tinha a coluna: o que se digitava era descartado ao
-- salvar, sem aviso. A coluna nasce vazia (nenhum dado muda); a tela e o update_marina/create_marina
-- do assistente passam a gravá-la. Número e complemento continuam dentro de address_line_1.
--
-- Leitura: `authenticated` tem SELECT na tabela inteira (vê a coluna nova); `anon` só tem SELECT por
-- coluna (links públicos) — a coluna nova nasce FECHADA para ele, de propósito.

alter table public.marinas add column if not exists neighborhood text;

comment on column public.marinas.neighborhood is 'Bairro (tela de marina e assistente). Número e complemento ficam em address_line_1.';

do $$
begin
  if has_column_privilege('anon', 'public.marinas', 'neighborhood', 'select') then
    raise exception 'marinas.neighborhood aberta ao anon';
  end if;
  if not has_column_privilege('authenticated', 'public.marinas', 'neighborhood', 'select') then
    raise exception 'marinas.neighborhood sem leitura para quem está logado';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261007161000', 'marina_bairro')
on conflict do nothing;
