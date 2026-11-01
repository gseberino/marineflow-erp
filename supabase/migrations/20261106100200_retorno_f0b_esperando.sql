-- Retorno rápido ao cliente, F0b (06/11/2026): "quem espera resposta" sem as três falhas medidas.
--
-- whatsapp_esperando_resposta é a base do acorde (acompanhar-conversas) e do Secretário (manhã e
-- fechamento). Três consertos, sem mudar as colunas nem o sentido das horas (occurred_at, a de
-- gravação: o acorde compara com ela e a carência do lote de ressincronização depende dela):
--
-- 1. Só a saída do DONO responde (saida_humana, a regra única de _saida_e_humana). Com a fila e o
--    lembrete de cobrança gravando na conversa, a mensagem automática faria o cliente sumir da
--    lista como se tivesse sido respondido. Nula (gravada antes da coluna existir) conta como antes.
-- 2. Quem é o número vem de quem_escreve, não do "limit 1" pelos 8 dígitos: com 2 clientes no
--    mesmo número, a lista dizia o nome de um deles ao acaso. Agora diz "(número de 2 clientes)",
--    sem escolher. O cliente ligado à conversa (client_id da última mensagem) segue valendo
--    primeiro, como antes. Fornecedor só ativo (o "limit 1" contava os 310 inativos).
-- 3. Robô não espera resposta (_retorno_e_automatico): mensagem modelo, botões, lista ou
--    interativa da Evolution; ou o mesmo texto longo (60+ caracteres) 3 vezes em 30 dias do mesmo
--    número. Medido em 90 dias: 125 mensagens modelo de 22 números; texto longo repetido, só a
--    resposta automática da MP (23 vezes) — repetição curta ("ok", "bom dia") é conversa e fica.
--
-- Sem dado. Reverter: recriar a função de 20261006120000 e drop de _retorno_e_automatico.

create or replace function public._retorno_e_automatico(p_phone text, p_body text, p_raw jsonb, p_quando timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (jsonb_typeof(p_raw -> 'data' -> 'message') = 'object'
       and (p_raw -> 'data' -> 'message') ?| array['templateMessage', 'buttonsMessage', 'listMessage', 'interactiveMessage'])
    or (length(btrim(coalesce(p_body, ''))) >= 60
        and (select count(*) from public.whatsapp_messages m
              where m.phone_normalized = p_phone and m.direction = 'inbound'
                and m.occurred_at > coalesce(p_quando, now()) - interval '30 days'
                and m.occurred_at <= coalesce(p_quando, now())
                and btrim(lower(m.body)) = btrim(lower(p_body))) >= 3),
    false);
$$;

comment on function public._retorno_e_automatico(text, text, jsonb, timestamptz) is
  'Retorno F0b: a recebida é de robô (mensagem modelo, botões, lista, interativa; ou o mesmo texto de 60+ caracteres 3 vezes em 30 dias).';

revoke all on function public._retorno_e_automatico(text, text, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public._retorno_e_automatico(text, text, jsonb, timestamptz) to service_role;

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
           -- Retorno F0b: só a saída do dono responde; a automática (saida_humana = false) não.
           max(m.occurred_at) filter (where m.direction = 'outbound' and m.saida_humana is not false) as last_out,
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
      ult.body as last_body,
      public.quem_escreve(p.phone) as quem
    from pendentes p
    left join lateral (
      select mm.body, mm.raw_payload from public.whatsapp_messages mm
       where mm.phone_normalized = p.phone and mm.direction = 'inbound' order by mm.occurred_at desc limit 1
    ) ult on true
    where not exists (select 1 from public.app_users u where u.phone_normalized = p.phone and u.ai_whatsapp_enabled = true)
      and not public._retorno_e_automatico(p.phone, ult.body, ult.raw_payload, p.last_in)
  )
  select
    e.phone,
    case
      when c.id is null and cf.id is null and e.quem ->> 'papel' = 'cliente_ambiguo'
        then coalesce(nullif(l.name, ''), e.phone) || ' (número de ' || jsonb_array_length(e.quem -> 'clientes') || ' clientes)'
      else coalesce(nullif(c.name, ''), nullif(cf.name, ''), nullif(l.name, ''), e.phone)
    end as contato,
    case
      when c.id is not null or l.linked_client_id is not null or e.quem ->> 'papel' in ('cliente', 'cliente_ambiguo') then 'cliente'
      when e.tem_fornecedor or e.quem ->> 'papel' = 'fornecedor' then 'fornecedor'
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
  -- Cliente reconhecido pelo telefone do cadastro (quem_escreve: 1 cliente ativo), mesmo sem a conversa ligada à ficha.
  left join public.clients cf on c.id is null and cf.id = (e.quem ->> 'cliente_id')::uuid
  where l.muted_at is null
  order by
    case when c.id is not null or l.linked_client_id is not null or e.quem ->> 'papel' in ('cliente', 'cliente_ambiguo') then 0 else 1 end,
    e.last_in desc
  limit _limit;
$$;

revoke all on function public.whatsapp_esperando_resposta(timestamptz, integer) from public, anon, authenticated;
grant execute on function public.whatsapp_esperando_resposta(timestamptz, integer) to service_role;
