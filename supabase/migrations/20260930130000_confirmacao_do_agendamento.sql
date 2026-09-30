-- Confirmação do agendamento por "SIM" (decisão do dono em 30/09/2026: "quero assim").
--
-- A regra R15 cria, na véspera, a tarefa "confirmar com fulano o atendimento de amanhã" e dizia
-- "use o botão de confirmação na Agenda" — botão que nunca existiu. Agora:
--   · pedir_confirmacao_do_agendamento: o botão da tarefa manda ao cliente a mensagem pedindo
--     "responda SIM" (humano decide, um a um: disparo automático é o que mais bloqueia número) e
--     anota o pedido na OS;
--   · registrar_confirmacao_do_cliente: o webhook chama a cada mensagem de cliente; se for uma
--     concordância curta ("sim", "confirmo", "ok", 👍) de quem teve pedido nas últimas 72 h, a OS
--     fica confirmada PARA AQUELA DATA e o dono é avisado no sino. "Sim, mas preciso remarcar"
--     NÃO confirma: só frase curta de concordância, sem mais nada.
-- WhatsApp da Evolution não tem botão: a confirmação é por texto.

alter table public.service_orders
  add column if not exists client_confirmation_requested_at timestamptz,
  add column if not exists client_confirmed_at timestamptz,
  add column if not exists client_confirmed_for timestamptz;

comment on column public.service_orders.client_confirmed_for is
  'O horário (scheduled_start_at) que o cliente confirmou por WhatsApp. Remarcou → a confirmação antiga não vale para a data nova.';

-- Concordância curta, e nada além dela. Normaliza caixa, acento e pontuação.
create or replace function public._e_concordancia(p_texto text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(
    btrim(regexp_replace(
      regexp_replace(translate(lower(coalesce(p_texto, '')), 'áàâãéêíóôõúüç', 'aaaaeeiooouuc'), '[^a-z0-9👍 ]', ' ', 'g'),
      '\s+', ' ', 'g'))
    ~ '^(sim|s|ss|confirmo|confirmado|confirmada|ok|okay|beleza|blz|combinado|certo|perfeito|pode ser|👍)( (sim|confirmo|confirmado|confirmada|ok|obrigado|obrigada|valeu|combinado|perfeito|certo|pode ser|tudo certo|ate la|te espero|estarei la|👍))*$',
    false);
$$;

create or replace function public.pedir_confirmacao_do_agendamento(p_os uuid, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := coalesce(auth.uid(), p_autor);
  v_os record;
  v_fone text;
  v_teste boolean;
  v_fone_teste text;
  v_destino text;
  v_nome text;
  v_quando text;
  v_msg text;
begin
  if v_autor is not null and not exists (
    select 1 from public.app_users u where u.id = v_autor and u.active and u.role in ('admin', 'financial', 'seller')) then
    raise exception 'Sem permissão para falar com o cliente pelo WhatsApp.' using errcode = '42501';
  end if;

  select s.id, s.service_order_number, s.status, s.scheduled_start_at,
         c.name as cliente, c.phone, c.whatsapp, c.opt_out_whatsapp, v.name as barco
    into v_os
    from public.service_orders s
    left join public.clients c on c.id = s.client_id
    left join public.vessels v on v.id = s.vessel_id
   where s.id = p_os;
  if v_os.id is null then raise exception 'OS não encontrada.'; end if;
  if v_os.status <> 'scheduled' or v_os.scheduled_start_at is null then
    raise exception 'A OS % não está agendada.', v_os.service_order_number;
  end if;
  if v_os.scheduled_start_at < now() then
    raise exception 'O atendimento da OS % já passou.', v_os.service_order_number;
  end if;
  if coalesce(v_os.opt_out_whatsapp, false) then
    raise exception 'Este cliente pediu para não receber WhatsApp: confirme por telefone.';
  end if;
  v_fone := regexp_replace(coalesce(nullif(v_os.whatsapp, ''), v_os.phone, ''), '\D', '', 'g');
  if length(v_fone) < 10 then raise exception 'Cliente sem telefone cadastrado.'; end if;
  if length(v_fone) in (10, 11) then v_fone := '55' || v_fone; end if;

  v_teste := coalesce((select value::text from public.app_settings where key = 'wa_test_mode'), 'false') in ('true', '"true"');
  v_fone_teste := regexp_replace(coalesce((select value::text from public.app_settings where key = 'wa_test_number'), ''), '\D', '', 'g');
  if v_teste and v_fone_teste = '' then raise exception 'Modo de teste ligado sem número de teste configurado.'; end if;
  v_destino := case when v_teste then v_fone_teste else v_fone end;

  v_nome := coalesce(nullif(split_part(btrim(coalesce(v_os.cliente, '')), ' ', 1), ''), '');
  v_quando := (array['domingo','segunda','terça','quarta','quinta','sexta','sábado'])[extract(dow from v_os.scheduled_start_at at time zone 'America/Sao_Paulo')::int + 1]
    || ' (' || to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'DD/MM') || ') às '
    || to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'HH24"h"MI');
  v_msg := 'Olá' || case when v_nome <> '' then ', ' || initcap(v_nome) else '' end || '! Aqui é da HBR Marine. '
    || 'Confirmando o atendimento' || coalesce(' no ' || nullif(v_os.barco, ''), '') || ' ' || v_quando || '. '
    || 'Pode responder SIM para confirmar? Se precisar remarcar, é só avisar por aqui. 👍';

  insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, priority)
  values (v_destino, v_msg, 'agenda-confirmacao', v_os.id, 3);

  update public.service_orders
     set client_confirmation_requested_at = now(), client_confirmed_at = null, client_confirmed_for = null
   where id = v_os.id;

  return jsonb_build_object('ok', true, 'teste', v_teste, 'mensagem', v_msg,
    'message', case when v_teste then 'Mensagem na fila (modo de teste: vai para o número de teste).'
                    else 'Pedido de confirmação enviado a ' || coalesce(v_os.cliente, 'o cliente') || '. Quando ele responder SIM, a OS fica confirmada.' end);
end;
$$;

revoke all on function public.pedir_confirmacao_do_agendamento(uuid, uuid) from public, anon;
grant execute on function public.pedir_confirmacao_do_agendamento(uuid, uuid) to authenticated, service_role;

create or replace function public.registrar_confirmacao_do_cliente(p_phone text, p_body text, p_message_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_os record;
  v_n int;
  v_quando text;
begin
  if length(v_fone) < 8 or not public._e_concordancia(p_body) then
    return jsonb_build_object('confirmou', false);
  end if;

  -- OS agendada, com pedido de confirmação nas últimas 72 h e ainda sem resposta, deste cliente.
  select count(*) into v_n
    from public.service_orders s join public.clients c on c.id = s.client_id
   where s.status = 'scheduled' and s.scheduled_start_at > now() - interval '2 hours'
     and s.client_confirmation_requested_at > now() - interval '72 hours'
     and s.client_confirmed_at is null
     and right(regexp_replace(coalesce(nullif(c.whatsapp, ''), c.phone, ''), '\D', '', 'g'), 8) = right(v_fone, 8);
  if v_n = 0 then return jsonb_build_object('confirmou', false); end if;

  if v_n > 1 then
    -- Duas OS esperando: "sim" não diz qual. Avisa o dono em vez de adivinhar.
    insert into public.app_notifications (user_id, type, title, body, navigate_to)
    select u.id, 'agendamento_confirmado', 'Cliente respondeu SIM, mas há ' || v_n || ' OS esperando confirmação',
           'Confira com o cliente qual atendimento ele confirmou.', '/agenda'
      from public.app_users u where u.role = 'admin' and u.active;
    return jsonb_build_object('confirmou', false, 'ambigua', v_n);
  end if;

  select s.id, s.service_order_number, s.scheduled_start_at, c.name as cliente into v_os
    from public.service_orders s join public.clients c on c.id = s.client_id
   where s.status = 'scheduled' and s.scheduled_start_at > now() - interval '2 hours'
     and s.client_confirmation_requested_at > now() - interval '72 hours'
     and s.client_confirmed_at is null
     and right(regexp_replace(coalesce(nullif(c.whatsapp, ''), c.phone, ''), '\D', '', 'g'), 8) = right(v_fone, 8);

  update public.service_orders
     set client_confirmed_at = now(), client_confirmed_for = v_os.scheduled_start_at
   where id = v_os.id;

  v_quando := to_char(v_os.scheduled_start_at at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24"h"MI');
  insert into public.app_notifications (user_id, type, title, body, navigate_to)
  select u.id, 'agendamento_confirmado', coalesce(v_os.cliente, 'Cliente') || ' confirmou o atendimento',
         'OS ' || v_os.service_order_number || ', ' || v_quando || ' — respondeu "' || left(btrim(p_body), 40) || '" pelo WhatsApp.',
         '/v2/service-orders/' || v_os.id
    from public.app_users u where u.role = 'admin' and u.active;

  return jsonb_build_object('confirmou', true, 'os', v_os.service_order_number);
end;
$$;

revoke all on function public.registrar_confirmacao_do_cliente(text, text, uuid) from public, anon, authenticated;
grant execute on function public.registrar_confirmacao_do_cliente(text, text, uuid) to service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260930130000', 'confirmacao_do_agendamento')
on conflict do nothing;
