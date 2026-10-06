-- A idade real do dado de cada banco (06/10/2026, pedido do dono: "Atualizar extrato").
--
-- O botão "Atualizar extrato" lê o que o Pluggy já trouxe; o MeuPluggy vai ao banco sozinho uma
-- vez a cada 24 h e não aceita pedido de "ir agora". Sem a data do Pluggy, "atualizado agora"
-- parecia querer dizer "tem a compra de agora". banking-sync grava item.lastUpdatedAt e
-- item.nextAutoSyncAt a cada leitura.
--
-- (Nasceu como 20261006210000 junto com um tíquete de PDF; a sessão das Diárias publicou antes a
-- MESMA versão com o mesmo mecanismo — tokens_de_pdf —, que ficou. Esta leva só as colunas.)
alter table public.bank_connections
  add column if not exists provider_updated_at timestamptz,
  add column if not exists provider_next_sync_at timestamptz;

comment on column public.bank_connections.provider_updated_at is
  'Quando o Pluggy foi ao banco por último (item.lastUpdatedAt) — a idade real do extrato.';
comment on column public.bank_connections.provider_next_sync_at is
  'Próxima ida automática do Pluggy ao banco (item.nextAutoSyncAt), quando ele informa.';

insert into supabase_migrations.schema_migrations (version, name)
values ('20261006230000', 'extrato_idade_do_dado');
