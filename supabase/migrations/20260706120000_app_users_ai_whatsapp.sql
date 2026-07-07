-- AI Operator — Fase 4: canal WhatsApp para equipe interna.
-- app_users ganha os campos necessários pra reconhecer um número de WhatsApp como
-- funcionário autorizado a comandar o ERP por mensagem (allowlist opt-in, default
-- desligado). phone_normalized é preenchido a partir de phone usando a função SQL
-- wa_normalize_phone já existente no banco (mesma normalização usada em
-- whatsapp_messages/whatsapp_leads/whatsapp_send_queue).

alter table public.app_users add column if not exists phone_normalized text;
alter table public.app_users add column if not exists ai_whatsapp_enabled boolean not null default false;
alter table public.app_users add column if not exists ai_whatsapp_pin_hash text;

-- Backfill idempotente: só preenche quem ainda não tem phone_normalized e tem phone.
update public.app_users
set phone_normalized = public.wa_normalize_phone(phone)
where phone_normalized is null
  and phone is not null
  and public.wa_normalize_phone(phone) is not null;

-- Único, mas parcial (permite múltiplos NULL) — dois usuários não podem compartilhar o
-- mesmo número habilitado para IA.
create unique index if not exists ux_app_users_phone_normalized
  on public.app_users using btree (phone_normalized)
  where phone_normalized is not null;

create index if not exists idx_app_users_ai_whatsapp_enabled
  on public.app_users using btree (phone_normalized)
  where ai_whatsapp_enabled = true;
