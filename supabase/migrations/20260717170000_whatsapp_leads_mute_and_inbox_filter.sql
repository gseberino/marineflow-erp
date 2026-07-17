-- Completa a Fase 1 (Mensagens) do piloto: permite silenciar um contato ("nao e relevante")
-- para reduzir ruido no digest/caixa de entrada — especialmente fornecedores no numero misto.
-- Ferramentas do agente: mute_contact / unmute_contact (setam/limpam muted_at).
alter table public.whatsapp_leads add column if not exists muted_at timestamptz;

-- RPC whatsapp_pending_inbox passa a EXCLUIR contatos silenciados (lead com muted_at preenchido).
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
      and coalesce(m.is_broadcast, false) = false
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
  where l.muted_at is null          -- exclui contatos silenciados
  order by e.last_in desc
  limit _limit;
$fn$;
