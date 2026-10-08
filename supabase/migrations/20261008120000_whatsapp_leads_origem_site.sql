-- Origem do lead do WhatsApp (08/10/2026): quem chega pelo formulário do site novo
-- (hbrmarine.com.br/orcamento) manda uma mensagem pronta que começa com
-- "vim pelo site da HBR Systems". O webhook lê os campos (tipo, modelo, local, serviço,
-- detalhes) e grava aqui, para o painel e para medir quantos contatos o site traz.
alter table public.whatsapp_leads
  add column if not exists origem text,
  add column if not exists dados_site jsonb;

alter table public.whatsapp_leads drop constraint if exists whatsapp_leads_origem_check;
alter table public.whatsapp_leads
  add constraint whatsapp_leads_origem_check check (origem is null or origem in ('site'));

comment on column public.whatsapp_leads.origem is 'De onde o contato veio. ''site'' = formulário de orçamento do site (mensagem com "vim pelo site da HBR Systems").';
comment on column public.whatsapp_leads.dados_site is 'Campos lidos da mensagem do site: nome, tipo, modelo, local, servico, detalhes.';

-- Aviso ao dono quando chega contato do site. Liga por padrão; 'false' desliga.
insert into public.app_settings (key, value, description)
values ('whatsapp_aviso_lead_site', 'true', 'Avisar no WhatsApp do dono (whatsapp_reminder_recipients) quando chegar contato pelo formulário do site.')
on conflict (key) do nothing;
