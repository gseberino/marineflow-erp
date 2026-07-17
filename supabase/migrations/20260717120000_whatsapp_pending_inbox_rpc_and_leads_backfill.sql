-- Caixa de entrada pendente a partir da FONTE DA VERDADE (whatsapp_messages), nao do
-- cache whatsapp_leads (que congelou em 2026-06-04 porque o webhook so gravava updated_at).
-- Um telefone e "pendente" se a ultima mensagem recebida veio DEPOIS da ultima enviada.
-- Exclui numeros da equipe interna (app_users com IA no WhatsApp habilitada).
create or replace function public.whatsapp_pending_inbox(
  _since timestamptz default null,
  _limit int default 15
) returns table (
  phone text,
  contato text,
  is_client boolean,
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,
  unread_count int,
  last_body text
) language sql stable set search_path to 'public' as $fn$
  with agg as (
    select
      m.phone_normalized as phone,
      max(m.occurred_at) filter (where m.direction = 'inbound')  as last_in,
      max(m.occurred_at) filter (where m.direction = 'outbound') as last_out
    from whatsapp_messages m
    where (_since is null or m.occurred_at >= _since)
    group by m.phone_normalized
  ),
  pending as (
    select * from agg
    where last_in is not null and (last_out is null or last_in > last_out)
  ),
  enriched as (
    select
      p.phone, p.last_in, p.last_out,
      (select mm.client_id from whatsapp_messages mm
         where mm.phone_normalized = p.phone order by mm.occurred_at desc limit 1) as client_id,
      (select mm.body from whatsapp_messages mm
         where mm.phone_normalized = p.phone and mm.direction = 'inbound'
         order by mm.occurred_at desc limit 1) as last_body
    from pending p
    where not exists (
      select 1 from app_users u
      where u.phone_normalized = p.phone and u.ai_whatsapp_enabled = true
    )
  )
  select
    e.phone,
    coalesce(nullif(c.name, ''), nullif(l.name, ''), e.phone) as contato,
    (c.id is not null or l.linked_client_id is not null) as is_client,
    e.last_in as last_inbound_at,
    e.last_out as last_outbound_at,
    coalesce(l.unread_count, 0)::int as unread_count,
    e.last_body
  from enriched e
  left join clients c on c.id = e.client_id
  left join whatsapp_leads l on l.phone_normalized = e.phone
  order by e.last_in desc
  limit _limit;
$fn$;

-- Backfill: corrige os campos de frescor do cache whatsapp_leads a partir das mensagens
-- (leads existentes que ficaram congelados em 04/06). Consumidores: UI e alerta periodico.
update whatsapp_leads l set
  last_inbound_at  = agg.last_in,
  last_outbound_at = agg.last_out,
  last_message_at  = greatest(agg.last_in, coalesce(agg.last_out, agg.last_in)),
  updated_at       = now()
from (
  select phone_normalized,
         max(occurred_at) filter (where direction = 'inbound')  as last_in,
         max(occurred_at) filter (where direction = 'outbound') as last_out
  from whatsapp_messages
  group by phone_normalized
) agg
where agg.phone_normalized = l.phone_normalized
  and (
    l.last_inbound_at is distinct from agg.last_in
    or l.last_outbound_at is distinct from agg.last_out
  );
