-- HBR AI Gateway: o hbr-pc-1 (gateway do Claude) passa a pegar só claude-local (11/10/2026).
--
-- Com a 20261011104000 o banco decide o provider de cada worker; nulo = todos. Antes de existir
-- qualquer token do HBR Doc Worker, o worker do Claude fica restrito ao que ele faz hoje (os 167
-- jobs até 10/10 foram todos claude-local). Só mexe se ainda estiver nulo: quem já configurou à mão
-- não é sobrescrito.
--
-- GRAVA DADO — OK NOMEADO: update em ai_gateway_workers (linha hbr-pc-1). Idempotente.
-- Depende da 20261011104000 (coluna allowed_providers).

update public.ai_gateway_workers
   set allowed_providers = array['claude-local']
 where id = 'hbr-pc-1'
   and allowed_providers is null;

do $$
begin
  if exists (select 1 from public.ai_gateway_workers where id = 'hbr-pc-1')
     and not exists (select 1 from public.ai_gateway_workers
                      where id = 'hbr-pc-1' and 'claude-local' = any (allowed_providers)) then
    raise exception 'hbr-pc-1 ficou sem claude-local em allowed_providers: o assistente pararia';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011106000', 'ai_gateway_hbr_pc_1_so_claude')
on conflict do nothing;
