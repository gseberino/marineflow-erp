-- Retorno rápido ao cliente, F0b (06/11/2026): a linha de base do retorno, medida sempre do mesmo jeito.
--
-- O tempo de resposta medido em 31/10 (verificação V3, fatos.md §1.1) pela HORA REAL das mensagens:
-- a hora de gravação (occurred_at) engana — 387 recebidas gravadas com mais de 12 h de atraso. Aqui
-- a mesma consulta da V3 vira:
--   · retorno_medidas_base(início, fim): os blocos de mensagens recebidas (rajada até a 1ª saída), com
--     categoria, grupo, a 1ª resposta de qualquer origem e a humana, abertura, pedido e queda — o
--     período por parâmetro, para conferir contra a V3 no mesmo período;
--   · retorno_medidas_blocos: visão materializada dos últimos 90 dias até ontem, recalculada 1 vez por
--     noite (cron retorno-medidas, 02:40 de Brasília, antes do backup das 03:30) — nunca consultada ao
--     vivo pela página (o incidente de 17/08 foi consulta pesada repetida);
--   · retorno_medidas: os números por grupo (mediana, P75, P90, % em 5 min, 30 min, 1 h, 4 h, 24 h,
--     sem resposta, só a resposta humana), como a TR21 da V3.
-- A hora usada é hora_real; sem ela, o messageTimestamp do raw_payload; sem ele, occurred_at.
-- O feriado do "horário comercial" vem de agenda_feriado (a V3 tirava só o 12/10).
-- Sem dado de cliente na saída: sem o texto das mensagens.
--
-- Sem dado alterado. Reverter: cron.unschedule('retorno-medidas'), drop view, drop materialized view, drop function.

create or replace function public.retorno_medidas_base(p_ini timestamptz, p_fim timestamptz)
returns table (
  ph text, cat text, grupo text, nucleo boolean, pedido boolean, abertura boolean, em_queda boolean,
  numero_novo boolean, comercial boolean, inicio timestamptz, ini_local timestamp, dow int, hora int,
  resp_qualquer timestamptz, resp_auto boolean, resp_humana timestamptz, espera_min numeric, espera_hum numeric,
  msgs int, msgs_validas int
)
language sql
stable
security definer
set search_path = public
as $$
  with
  cfg as (select p_ini as ini, p_fim as fim),
  -- Quedas de captura: silêncio global > 16 h que cobre >= 3 horas úteis (seg-sex 8-17h, Brasília).
  quedas as (
    select ant as q_ini, occurred_at as q_fim from (
      select occurred_at, lag(occurred_at) over (order by occurred_at) ant
      from public.whatsapp_messages where occurred_at >= p_ini - interval '35 days') g
    where occurred_at - ant > interval '16 hours'
      and (select count(*) from generate_series(date_trunc('hour', ant), occurred_at, interval '1 hour') h
           where extract(isodow from h at time zone 'America/Sao_Paulo') between 1 and 5
             and extract(hour from h at time zone 'America/Sao_Paulo') between 8 and 17) >= 3
  ),
  equipe8 as (
    select right(phone_normalized,8) p8 from public.app_users where phone_normalized is not null
    union select right(regexp_replace(phone,'\D','','g'),8) from public.payees where length(regexp_replace(coalesce(phone,''),'\D','','g')) >= 8
  ),
  cliente8 as (
    select right(regexp_replace(t,'\D','','g'),8) p8, min(c.created_at) desde, min(c.id::text) client_id,
           bool_or(c.name ~* '^\s*mp\y' and c.name ~* 'motor') eh_mp
    from public.clients c, unnest(array[c.phone, c.whatsapp]) t
    where length(regexp_replace(coalesce(t,''),'\D','','g')) >= 8 group by 1
    union all
    select right(regexp_replace(vc.phone,'\D','','g'),8), min(vc.created_at), min(v.client_id::text), false
    from public.vessel_contacts vc join public.vessels v on v.id = vc.vessel_id
    where length(regexp_replace(coalesce(vc.phone,''),'\D','','g')) >= 8 group by 1
  ),
  forn8 as (
    select right(regexp_replace(phone,'\D','','g'),8) p8 from public.suppliers where length(regexp_replace(coalesce(phone,''),'\D','','g')) >= 8
  ),
  api as (  -- envios pela API (assistente/sistema), para separar do que foi digitado no celular
    select changed_at, new_value->>'phone' ph from public.audit_log where action = 'whatsapp_send_api' and changed_at >= p_ini - interval '65 days'
  ),
  m0 as (
    select m.id, m.direction, m.phone_normalized ph, right(m.phone_normalized,8) p8, m.message_type, m.body, coalesce(m.hora_real, case when (m.raw_payload->'data'->>'messageTimestamp') ~ '^[0-9]{10}$' then to_timestamp((m.raw_payload->'data'->>'messageTimestamp')::bigint) end, m.occurred_at) as occurred_at,
           m.client_id, m.lead_id, m.supplier_id,
           coalesce(m.raw_payload->'data'->>'messageType','') rtype,
           (m.direction = 'outbound' and (coalesce(m.raw_payload->>'via','') = 'whatsapp-send'
              or exists (select 1 from api a where a.ph = m.phone_normalized
                          and a.changed_at between m.occurred_at - interval '90 seconds' and m.occurred_at + interval '90 seconds'))) as auto
    from public.whatsapp_messages m
    where coalesce(m.is_broadcast, false) = false and m.occurred_at >= p_ini - interval '54 days'
      and length(m.phone_normalized) between 12 and 13
    union all
    -- envio pela API que NÃO entrou em whatsapp_messages (antes de 15/10 o whatsapp-send só gravava audit_log)
    select null::uuid, 'outbound', a.ph, right(a.ph,8), 'text', '[envio pela API, só no audit_log]', a.changed_at,
           null::uuid, null::uuid, null::uuid, '', true
    from api a
    where length(coalesce(a.ph,'')) between 12 and 13
      and not exists (select 1 from public.whatsapp_messages w where w.phone_normalized = a.ph and w.direction = 'outbound'
                        and w.occurred_at between a.changed_at - interval '90 seconds' and a.changed_at + interval '90 seconds')
  ),
  contato as (
    select ph, p8,
      bool_or(supplier_id is not null) tem_forn_msg,
      bool_or(client_id is not null) tem_cli_msg,
      min(occurred_at) primeira_msg,
      (array_agg(direction order by occurred_at))[1] primeira_dir,
      count(*) filter (where direction='inbound') ent,
      count(*) filter (where direction='inbound' and rtype in ('templateMessage','buttonsMessage','listMessage','interactiveMessage')) robo
    from m0 group by ph, p8
  ),
  classe as (
    select c.*,
      case
        when exists (select 1 from equipe8 e where e.p8 = c.p8) then 'x_equipe'
        when c.ent > 0 and c.robo::numeric / c.ent >= 0.3 then 'x_robo'
        when exists (select 1 from cliente8 k where k.p8 = c.p8 and k.eh_mp) then 'parceiro_mp'
        when c.tem_cli_msg or exists (select 1 from cliente8 k where k.p8 = c.p8)
             or exists (select 1 from public.whatsapp_leads l where l.phone_normalized = c.ph and l.linked_client_id is not null) then 'cliente'
        when c.tem_forn_msg or exists (select 1 from forn8 f where f.p8 = c.p8) then 'x_fornecedor'
        -- fornecedor/vendedor sem cadastro: o próprio contato escreve como quem vende (cotação, estoque, catálogo, resposta automática de empresa)
        when exists (select 1 from m0 v where v.ph = c.ph and v.direction = 'inbound' and v.occurred_at >= p_ini - interval '54 days'
                       and v.body ~* '(segue (a |o |nossa |nosso )?(cota[cç][aã]o|tabela|proposta|or[cç]amento|pedido|dav)|tabela (de pre[cç]os|permak)|pronta entrega|em estoque|n[aã]o temos em estoque|representante comercial|consultor[a]? (comercial|empresarial)|cat[aá]logo|condi[cç][oõ]es especiais|ipi\y|agradecemos (seu|o|pelo) (contato|interesse)|hor[aá]rio de atendimento|deixe sua mensagem)')
          then 'x_vendedor'
        else 'sem_cadastro'
      end as cat,
      (c.primeira_msg >= (select ini from cfg) and c.primeira_dir = 'inbound') as numero_novo
    from contato c
  ),
  m1 as (
    select m.*,
      (m.direction = 'inbound' and (
          m.body is null or m.body = '[conteúdo vazio]'
          or m.rtype in ('reactionMessage','stickerMessage','secretEncryptedMessage','placeholderMessage','protocolMessage')
          or m.message_type = 'sticker'
          or (m.message_type = 'text' and m.body !~ '[[:alnum:]]')
          or m.body ~* '^[\s[:punct:]]*((ok+|okay|blz|beleza|valeu|vlw|obrigad[oa]s?|muit[oa] obrigad[oa]|brigad[oa]|show( de bola)?|top|perfeito|combinado|certo|fechado|t[aá] ?bom|t[aá] ?certo|t[aá] ?ok|de nada|abra[cç]os?|[oó]tim[oa]|excelente|maravilha|legal|joia|tranquilo|entendi(do)?|disponha|grat[oa]|agrade[cç]o|perfeito|isso a[ií]( mesmo)?|ok ok)[\s[:punct:]]*)+[^[:alnum:]]*$'
          -- fecho curto: até 40 caracteres, sem "?", com palavra de fecho ("Valeu mano", "Show meu amigo", "Oi ok", "Vou ver.")
          or (length(m.body) <= 40 and m.body !~ '\?' and m.body !~ '^🎤'
              and m.body ~* '^(\S+\s+)?(ok|okay|valeu|vlw|obrigad[oa]|brigad[oa]|show|blz|blza|beleza|fechou|fechado|combinado|perfeito|top|certo|tmj|tranquilo|joia|massa|demais|[oó]tim[oa]|entendi|t[aá] (bom|certo|ok)|vou ver|pode deixar|deixa comigo|abra[cç]o|boa noite|bom descanso)\y')
      )) as ack,
      sum(case when m.direction = 'outbound' then 1 else 0 end) over (partition by m.ph order by m.occurred_at, m.direction desc, m.id rows unbounded preceding) as nsai
    from m0 m
  ),
  bloco as (
    select b.ph, b.nsai,
      min(b.occurred_at) filter (where not b.ack) as inicio,
      max(b.occurred_at) as ultimo,
      count(*) as msgs,
      count(*) filter (where not b.ack) as msgs_validas,
      string_agg(left(b.body, 300), ' | ' order by b.occurred_at) filter (where not b.ack) as texto
    from m1 b where b.direction = 'inbound' group by b.ph, b.nsai
  ),
  bloco_r as (
    select b.*, k.cat, k.numero_novo, k.primeira_msg,
      (select o.occurred_at from m1 o where o.ph = b.ph and o.direction = 'outbound' and o.nsai = b.nsai + 1) as resp_qualquer,
      (select o.auto from m1 o where o.ph = b.ph and o.direction = 'outbound' and o.nsai = b.nsai + 1) as resp_auto,
      (select min(o.occurred_at) from m1 o where o.ph = b.ph and o.direction = 'outbound' and not o.auto and o.occurred_at > b.inicio) as resp_humana,
      (select max(o.occurred_at) from m0 o where o.ph = b.ph and o.occurred_at < b.inicio) as msg_anterior
    from bloco b join classe k on k.ph = b.ph
    where b.inicio is not null
  ),
  blocos as (
    select r.*,
      -- espera_min = até a 1ª saída de QUALQUER origem (o que o cliente vê); espera_hum = só a digitada (celular/web/tela)
      extract(epoch from (r.resp_qualquer - r.inicio)) / 60.0 as espera_min,
      extract(epoch from (r.resp_humana - r.inicio)) / 60.0 as espera_hum,
      (r.inicio at time zone 'America/Sao_Paulo') as ini_local,
      extract(isodow from r.inicio at time zone 'America/Sao_Paulo') as dow,
      extract(hour from r.inicio at time zone 'America/Sao_Paulo') as hora,
      (extract(isodow from r.inicio at time zone 'America/Sao_Paulo') between 1 and 5
        and public.agenda_feriado((r.inicio at time zone 'America/Sao_Paulo')::date) is null
        and (r.inicio at time zone 'America/Sao_Paulo')::time >= time '08:00'
        and (r.inicio at time zone 'America/Sao_Paulo')::time < time '18:00') as comercial,
      -- contaminado por queda: a queda começa antes da resposta medida E dentro das primeiras 72 h da espera
      -- (uma resposta "perdida" depois de 72 h não muda a faixa: a espera já passou de 72 h de qualquer jeito)
      exists (select 1 from quedas q where q.q_ini < least(coalesce(r.resp_qualquer, 'infinity'::timestamptz), r.inicio + interval '72 hours')
                                       and q.q_fim > r.inicio) as em_queda,
      -- "abertura": a espera começa depois de >= 4 h sem nenhuma mensagem do número (nova demanda, não meio de conversa)
      (r.msg_anterior is null or r.inicio - r.msg_anterior >= interval '4 hours') as abertura,
      -- pedido explícito: pergunta ou palavra de pedido no bloco; ou o 1º bloco de um número (alguém nos procurando)
      (r.msg_anterior is null or r.texto ~ '\?' or r.texto ~* '(or[cç]a|preciso|precisa|precisamos|pode(ria)?s?\y|consegue|conseguiria|quando|quanto|\yqual|quais|como (fa[cç]o|est[aá]|ficou|que|vai)|onde|tem como|gostaria|queria|quero|favor|aguardo|previs[aã]o|novidade|alguma (posi[cç][aã]o|not[ií]cia)|me (liga|ligue|retorn)|retorno|urgente|ajuda|d[aá] pra|disponibilidade|hor[aá]rio|agendar|marcar|visita|valor|pre[cç]o|pronto|liberad|retirar|buscar)') as pedido
    from bloco_r r
    where r.inicio >= (select ini from cfg) and r.inicio < (select fim from cfg)
  ),
  servico as (  -- número sem cadastro que fala de serviço/orçamento em alguma recebida da janela (proxy de lead/cliente)
    select distinct ph from m0
    where direction = 'inbound' and occurred_at >= (select ini from cfg)
      and body ~* '(or[cç]amento|servi[cç]o|instala|consert|reparo|manuten[cç]|revis[aã]o|motorhome|motor ?home|trailer|barco|lancha|embarca[cç]|veleiro|bateria|el[eé]tric|gerador|ar.condicionado|inversor|solar|geladeira|bomba|guincho|luz|fia[cç][aã]o|curto|carregador|quanto (custa|fica|sai|cobra)|valor|pre[cç]o|visita|or[cç]a)'
  )
  select bl.ph, bl.cat,
    case when bl.cat = 'cliente' then '1 cliente cadastrado'
         when bl.cat = 'sem_cadastro' and bl.ph in (select ph from servico) then '2 sem cadastro, fala de serviço'
         when bl.cat = 'sem_cadastro' then '3 sem cadastro, outro assunto'
         when bl.cat = 'parceiro_mp' then '4 parceiro MP' else bl.cat end,
    bl.cat in ('cliente', 'sem_cadastro') and (bl.cat = 'cliente' or bl.ph in (select ph from servico)),
    bl.pedido, bl.abertura, bl.em_queda, bl.numero_novo, bl.comercial,
    bl.inicio, bl.ini_local, bl.dow::int, bl.hora::int, bl.resp_qualquer, bl.resp_auto, bl.resp_humana,
    bl.espera_min::numeric, bl.espera_hum::numeric, bl.msgs::int, bl.msgs_validas::int
  from blocos bl;
$$;

comment on function public.retorno_medidas_base(timestamptz, timestamptz) is
  'Retorno F0b: os blocos de mensagens recebidas no período, com a 1ª resposta pela hora real (a consulta da V3 de 31/10, período por parâmetro). Sem texto.';

revoke all on function public.retorno_medidas_base(timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_medidas_base(timestamptz, timestamptz) to service_role;

drop view if exists public.retorno_medidas;
drop materialized view if exists public.retorno_medidas_blocos;
create materialized view public.retorno_medidas_blocos as
  select b.*, now() as calculado_em
    from public.retorno_medidas_base(
           (date_trunc('day', now() at time zone 'America/Sao_Paulo') - interval '90 days') at time zone 'America/Sao_Paulo',
           date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo') b;

revoke all on public.retorno_medidas_blocos from public, anon, authenticated;
grant select on public.retorno_medidas_blocos to service_role;

-- Os números por grupo, como a TR21 da V3: fora das quedas de captura e sem equipe, robô, fornecedor
-- e vendedor. Sem resposta = infinito nos percentis.
create view public.retorno_medidas with (security_invoker = on) as
with b as (
  select * from public.retorno_medidas_blocos where not em_queda and cat not like 'x_%'
),
g as (
  select grupo as gr, b.* from b
  union all select '5 NÚCLEO = 1+2 (clientes e leads de serviço)', b.* from b where nucleo
  union all select '6 TUDO menos MP (1+2+3)', b.* from b where cat in ('cliente', 'sem_cadastro')
  union all select grupo || ' · pedido', b.* from b where pedido
  union all select '5 NÚCLEO · pedido', b.* from b where nucleo and pedido
  union all select '5 NÚCLEO · abertura', b.* from b where nucleo and abertura
  union all select '5 NÚCLEO · abertura com pedido', b.* from b where nucleo and abertura and pedido
  union all select '4 parceiro MP · abertura', b.* from b where cat = 'parceiro_mp' and abertura
)
select g.gr as grupo,
  count(*) as blocos, count(distinct g.ph) as contatos,
  round(percentile_disc(0.5) within group (order by coalesce(g.espera_min, 1e9))::numeric, 0) as mediana_min,
  round(percentile_disc(0.75) within group (order by coalesce(g.espera_min, 1e9))::numeric, 0) as p75_min,
  round(percentile_disc(0.9) within group (order by coalesce(g.espera_min, 1e9))::numeric, 0) as p90_min,
  round(100.0 * count(*) filter (where g.espera_min <= 5) / count(*), 1) as pct_5min,
  round(100.0 * count(*) filter (where g.espera_min <= 30) / count(*), 1) as pct_30min,
  round(100.0 * count(*) filter (where g.espera_min <= 60) / count(*), 1) as pct_1h,
  round(100.0 * count(*) filter (where g.espera_min <= 240) / count(*), 1) as pct_4h,
  round(100.0 * count(*) filter (where g.espera_min <= 1440) / count(*), 1) as pct_24h,
  round(100.0 * count(*) filter (where g.resp_qualquer is null) / count(*), 1) as pct_sem_resposta,
  round(percentile_disc(0.5) within group (order by coalesce(g.espera_hum, 1e9))::numeric, 0) as mediana_humana_min,
  round(100.0 * count(*) filter (where g.espera_hum <= 60) / count(*), 1) as pct_1h_humana,
  min(g.inicio) as de, max(g.inicio) as ate, max(g.calculado_em) as calculado_em
from g group by g.gr;

revoke all on public.retorno_medidas from public, anon, authenticated;
grant select on public.retorno_medidas to service_role;

-- 1 vez por noite: 02:40 de Brasília (05:40 UTC), antes do backup das 03:30.
select cron.unschedule(jobid) from cron.job where jobname = 'retorno-medidas';
select cron.schedule('retorno-medidas', '40 5 * * *', $c$refresh materialized view public.retorno_medidas_blocos$c$);
