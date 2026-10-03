-- Vigia do WhatsApp: novo estado "travado" (aparece conectado, mas o envio não sai).
--
-- POR QUE: em 03/10/2026 o PC voltou de uma queda com o relógio errado; a Evolution respondia
-- "open" e a mensagem do Extrato das 15:25 ficou PENDING para sempre, sem nada entrar. O vigia só
-- olhava o connectionState e não viu nada; o dono descobriu testando. Agora a função
-- whatsapp-conexao confere o último envio do ERP (sem confirmação há 10+ min e ainda PENDING como
-- última mensagem da conversa) e grava "travado" — que conta como fora do ar para o aviso no sino.
--
-- Só muda a regra da coluna; nenhuma linha é escrita.

alter table public.whatsapp_conexao_vigia drop constraint if exists whatsapp_conexao_vigia_estado_check;
alter table public.whatsapp_conexao_vigia add constraint whatsapp_conexao_vigia_estado_check
  check (estado in ('open', 'connecting', 'close', 'inacessivel', 'travado'));

insert into supabase_migrations.schema_migrations (version, name)
values ('20261003190000', 'whatsapp_vigia_travado')
on conflict do nothing;
