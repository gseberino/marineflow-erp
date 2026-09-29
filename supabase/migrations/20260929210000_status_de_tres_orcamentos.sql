-- Três orçamentos marcados "enviado" sem ter ido ao cliente (decisão do dono, 29/09/2026:
-- "Corrigir o status").
--
-- Até 26/09 o whatsapp-send marcava quote_status = 'sent' em qualquer envio com
-- context='quote', inclusive o dono mandando para si e o modo de teste (corrigido em
-- _shared/whatsapp/marcar-enviado.ts). Sobraram três:
--   ORÇ-00070: OS concluída, assinada pelo cliente em 29/07  -> 'approved'
--   ORÇ-00083: OS aprovada,  assinada pelo cliente em 23/08  -> 'approved'
--   ORÇ-00109: rascunho, foi só ao número de teste            -> 'draft'
--     (e deixa de gerar o aviso de "orçamento vencido")
--
-- Conferido antes: nenhum gatilho de service_orders lê quote_status, e o gatilho de
-- "alterado depois da assinatura" não olha esse campo (a assinatura continua válida). A
-- situação da OS (status) não muda. Cada linha só muda se ainda estiver 'sent', e cada
-- mudança fica no audit_log.

with alvo(numero, novo) as (
  values ('ORÇ-00070', 'approved'), ('ORÇ-00083', 'approved'), ('ORÇ-00109', 'draft')
), mudou as (
  update public.service_orders so
     set quote_status = alvo.novo
    from alvo
   where so.service_order_number = alvo.numero
     and so.quote_status = 'sent'
  returning so.id, so.service_order_number, alvo.novo
)
insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
select 'service_orders', m.id, 'update', 'claude (decisão do dono, 29/09/2026)',
       jsonb_build_object('quote_status', 'sent'), jsonb_build_object('quote_status', m.novo),
       m.service_order_number || ': marcado "enviado" sem ter ido ao cliente (envio ao número de teste ou ao próprio dono, antes da correção de 26/09).'
  from mudou m;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260929210000', 'status_de_tres_orcamentos')
on conflict do nothing;
