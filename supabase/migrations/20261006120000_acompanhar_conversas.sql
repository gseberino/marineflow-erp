-- Acompanhar conversa, lembrar de responder e cumprir o prometido (06/10/2026).
-- Plano: plans/marineflow-acompanhar-conversa.md. Não escreve dados de negócio: cria a tabela dos
-- acompanhamentos, uma lista nova de "esperando resposta" (a antiga continua para quem já usa), duas
-- chaves de configuração e o agendamento do vigia. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. Os acompanhamentos pedidos pelo dono (ou detectados numa promessa dele)
-- ---------------------------------------------------------------------------------------------
create table if not exists public.whatsapp_acompanhamentos (
  id               uuid primary key default gen_random_uuid(),
  phone_normalized text not null,
  contato          text,
  modo             text not null default 'acompanhar',
  intervalo_min    integer not null default 120,
  ate              timestamptz not null default (now() + interval '7 days'),
  lembrar_em       timestamptz,
  promessa         text,
  status           text not null default 'ativo',
  encerrado_motivo text,
  ultimo_aviso_em  timestamptz,
  avisos_dia       date,
  avisos_no_dia    integer not null default 0,
  criado_por       uuid references auth.users(id) on delete set null,
  origem_mensagem  uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint whatsapp_acompanhamentos_modo_chk check (modo in ('acompanhar', 'lembrar_em', 'promessa')),
  constraint whatsapp_acompanhamentos_status_chk check (status in ('ativo', 'encerrado')),
  constraint whatsapp_acompanhamentos_intervalo_chk check (intervalo_min between 15 and 10080),
  constraint whatsapp_acompanhamentos_lembrar_chk check (modo = 'acompanhar' or lembrar_em is not null),
  constraint whatsapp_acompanhamentos_promessa_len check (promessa is null or char_length(promessa) <= 1000)
);

comment on table public.whatsapp_acompanhamentos is
  'Conversas que o dono pediu para acompanhar (avisos no intervalo com sugestão de resposta), lembretes de responder numa hora e promessas dele detectadas nas mensagens. O vigia é a edge acompanhar-conversas.';

-- Uma conversa acompanhada de cada vez por número (pedir de novo atualiza a existente).
create unique index if not exists whatsapp_acompanhamentos_um_ativo
  on public.whatsapp_acompanhamentos (phone_normalized)
  where status = 'ativo' and modo = 'acompanhar';
-- A mesma mensagem não gera duas promessas.
create unique index if not exists whatsapp_acompanhamentos_promessa_unica
  on public.whatsapp_acompanhamentos (origem_mensagem)
  where origem_mensagem is not null;
create index if not exists whatsapp_acompanhamentos_ativos
  on public.whatsapp_acompanhamentos (status, modo) where status = 'ativo';

alter table public.whatsapp_acompanhamentos enable row level security;
revoke all on table public.whatsapp_acompanhamentos from public, anon, authenticated;
grant select, update on table public.whatsapp_acompanhamentos to authenticated;
grant all on table public.whatsapp_acompanhamentos to service_role;

drop policy if exists whatsapp_acompanhamentos_admin_le on public.whatsapp_acompanhamentos;
create policy whatsapp_acompanhamentos_admin_le on public.whatsapp_acompanhamentos
  for select to authenticated using (public.is_admin((select auth.uid())));
drop policy if exists whatsapp_acompanhamentos_admin_muda on public.whatsapp_acompanhamentos;
create policy whatsapp_acompanhamentos_admin_muda on public.whatsapp_acompanhamentos
  for update to authenticated using (public.is_admin((select auth.uid()))) with check (public.is_admin((select auth.uid())));

-- ---------------------------------------------------------------------------------------------
-- 2. "Esperando resposta" sem ruído (o resumo das 07:30 passa a usar esta)
--    categoria: cliente / fornecedor / contato. encerrada: a última mensagem é só um fecho
--    ("ok", "obrigado", 👍…) — conta, mas não pede resposta.
-- ---------------------------------------------------------------------------------------------
create or replace function public.whatsapp_esperando_resposta(_since timestamptz default null, _limit integer default 30)
returns table (
  phone text, contato text, categoria text, encerrada boolean,
  last_inbound_at timestamptz, last_outbound_at timestamptz, unread_count integer, last_body text
)
language sql
stable
set search_path = ''
as $$
  with agg as (
    select m.phone_normalized as phone,
           max(m.occurred_at) filter (where m.direction = 'inbound')  as last_in,
           max(m.occurred_at) filter (where m.direction = 'outbound') as last_out,
           bool_or(m.supplier_id is not null) as tem_fornecedor
      from public.whatsapp_messages m
     where (_since is null or m.occurred_at >= _since)
       and coalesce(m.is_broadcast, false) = false
     group by m.phone_normalized
  ),
  pendentes as (
    select * from agg where last_in is not null and (last_out is null or last_in > last_out)
  ),
  enriquecido as (
    select p.*,
      (select mm.client_id from public.whatsapp_messages mm
        where mm.phone_normalized = p.phone order by mm.occurred_at desc limit 1) as client_id,
      (select mm.body from public.whatsapp_messages mm
        where mm.phone_normalized = p.phone and mm.direction = 'inbound' order by mm.occurred_at desc limit 1) as last_body
    from pendentes p
    where not exists (select 1 from public.app_users u where u.phone_normalized = p.phone and u.ai_whatsapp_enabled = true)
  )
  select
    e.phone,
    coalesce(nullif(c.name, ''), nullif(cf.name, ''), nullif(l.name, ''), e.phone) as contato,
    case
      when c.id is not null or l.linked_client_id is not null or cf.id is not null then 'cliente'
      when e.tem_fornecedor or exists (
        select 1 from public.suppliers s
         where length(regexp_replace(coalesce(s.phone, ''), '\D', '', 'g')) >= 8
           and right(regexp_replace(s.phone, '\D', '', 'g'), 8) = right(e.phone, 8)
      ) then 'fornecedor'
      else 'contato'
    end as categoria,
    coalesce(e.last_body ~* '^\s*(ok+|okay|blz|beleza|valeu|vlw|obrigad[oa]s?|brigad[oa]|show|top|perfeito|combinado|certo|fechado|t[aá] ?bom|tudo bem|de nada|abra[cç]o|👍+|🙏+|👌+|✅+|😊+|🤝+)[\s!.,]*$', false) as encerrada,
    e.last_in as last_inbound_at,
    e.last_out as last_outbound_at,
    coalesce(l.unread_count, 0)::int as unread_count,
    e.last_body
  from enriquecido e
  left join public.clients c on c.id = e.client_id
  left join public.whatsapp_leads l on l.phone_normalized = e.phone
  -- Cliente reconhecido pelo telefone do cadastro, mesmo sem a conversa ligada à ficha.
  left join lateral (
    select cl.id, cl.name from public.clients cl
     where length(regexp_replace(coalesce(cl.whatsapp, cl.phone, ''), '\D', '', 'g')) >= 8
       and right(regexp_replace(coalesce(cl.whatsapp, cl.phone), '\D', '', 'g'), 8) = right(e.phone, 8)
     limit 1
  ) cf on c.id is null
  where l.muted_at is null
  order by
    case when c.id is not null or l.linked_client_id is not null or cf.id is not null then 0 else 1 end,
    e.last_in desc
  limit _limit;
$$;

revoke all on function public.whatsapp_esperando_resposta(timestamptz, integer) from public, anon, authenticated;
grant execute on function public.whatsapp_esperando_resposta(timestamptz, integer) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 3. Configuração: detectar promessas (liga/desliga) e o cursor do vigia
-- ---------------------------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('acompanhar_promessas', 'on',
   'Detecta promessas do dono nas mensagens do WhatsApp ("te mando amanhã") e lembra na hora (on/off).'),
  ('acompanhar_cursor', '',
   'Até onde o vigia acompanhar-conversas já leu as mensagens do dono (uso interno).')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. O vigia, a cada 15 minutos (a edge decide se é horário de avisar)
-- ---------------------------------------------------------------------------------------------
do $$
begin
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'acompanhar-conversas';
  perform cron.schedule(
    'acompanhar-conversas',
    '*/15 * * * *',
    $cron$
    SELECT net.http_post(
      url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/acompanhar-conversas',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 120000
    );
    $cron$
  );
end $$;

-- ---------------------------------------------------------------------------------------------
-- Verificação
-- ---------------------------------------------------------------------------------------------
do $$
begin
  if has_function_privilege('anon', 'public.whatsapp_esperando_resposta(timestamptz, integer)', 'execute')
     or has_function_privilege('authenticated', 'public.whatsapp_esperando_resposta(timestamptz, integer)', 'execute') then
    raise exception 'whatsapp_esperando_resposta exposta além do previsto';
  end if;
  if has_table_privilege('anon', 'public.whatsapp_acompanhamentos', 'select') then
    raise exception 'whatsapp_acompanhamentos legível por anon';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.whatsapp_acompanhamentos'::regclass) then
    raise exception 'RLS desligada em whatsapp_acompanhamentos';
  end if;
  if not exists (select 1 from cron.job where jobname = 'acompanhar-conversas') then
    raise exception 'vigia não agendado';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261006120000', 'acompanhar_conversas')
on conflict do nothing;
