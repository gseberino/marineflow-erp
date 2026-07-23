-- Perfil de Comunicação por Contato (Camada de Inteligência de Comunicação, Fase 1).
-- Aditivo e reversível. Aplicado em produção via MCP apply_migration (comms_contact_profile_fields).
-- Para fornecedor, o "nome usado" é o trade_name já existente; display_name aqui fica de reserva.
alter table suppliers add column if not exists display_name text;
alter table suppliers add column if not exists communication_tone text;
alter table suppliers add column if not exists opt_out_whatsapp boolean not null default false;
alter table clients add column if not exists display_name text;
alter table clients add column if not exists communication_tone text;
alter table clients add column if not exists opt_out_whatsapp boolean not null default false;
comment on column clients.display_name is 'Nome usado na comunicacao (fantasia/primeiro nome), preferido sobre name.';
comment on column suppliers.display_name is 'Nome usado na comunicacao; a razao social nao deve ser usada em saudacao.';
