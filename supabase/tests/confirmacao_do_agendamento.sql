-- Confirmação do agendamento por "SIM". Run: npx supabase db query --linked -f supabase/tests/confirmacao_do_agendamento.sql
-- Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai (a fila não vê o que não foi confirmado).
begin;

do $$
declare
  v_os uuid;
  v_cliente uuid;
  v_fone text := '5547900001234';
  v_admin uuid := (select id from public.app_users where role = 'admin' and active limit 1);
  r jsonb;
begin
  -- 1. O que é "sim".
  if not (public._e_concordancia('Sim') and public._e_concordancia('sim!') and public._e_concordancia('SIM, confirmo')
          and public._e_concordancia('Ok, obrigado') and public._e_concordancia('👍') and public._e_concordancia('Confirmado.')
          and public._e_concordancia('sim sim') and public._e_concordancia('Pode ser, até lá')) then
    raise exception '1: concordância curta não reconhecida';
  end if;
  if public._e_concordancia('sim, mas preciso remarcar') or public._e_concordancia('não') or public._e_concordancia('simples')
     or public._e_concordancia('pode ser amanhã?') or public._e_concordancia('') or public._e_concordancia(null)
     or public._e_concordancia('Sim, porém chego 10h') then
    raise exception '1: frase que não é só concordância foi aceita';
  end if;

  -- 2. O fluxo, numa OS de verdade posta como agendada só dentro desta transação.
  select s.id, s.client_id into v_os, v_cliente from public.service_orders s where s.client_id is not null limit 1;
  update public.clients set whatsapp = '(47) 90000-1234', opt_out_whatsapp = false where id = v_cliente;
  -- Nenhuma outra OS do mesmo cliente pode estar esperando confirmação (senão "sim" é ambíguo).
  update public.service_orders set client_confirmation_requested_at = null where client_id = v_cliente and id <> v_os;
  update public.service_orders set status = 'scheduled', scheduled_start_at = now() + interval '1 day' where id = v_os;

  r := public.pedir_confirmacao_do_agendamento(v_os, v_admin);
  if not (r ->> 'ok')::boolean then raise exception '2: pedir falhou: %', r; end if;
  if not exists (select 1 from public.whatsapp_send_queue where source = 'agenda-confirmacao' and source_ref_id = v_os
                  and message ilike '%responder SIM%') then
    raise exception '2: a mensagem não entrou na fila';
  end if;

  r := public.registrar_confirmacao_do_cliente(v_fone, 'sim, mas preciso remarcar', null);
  if (r ->> 'confirmou')::boolean then raise exception '2: "sim, mas…" confirmou'; end if;

  r := public.registrar_confirmacao_do_cliente(v_fone, 'Sim!', null);
  if not (r ->> 'confirmou')::boolean then raise exception '2: "Sim!" não confirmou: %', r; end if;
  if not exists (select 1 from public.service_orders where id = v_os and client_confirmed_at is not null
                  and client_confirmed_for = scheduled_start_at) then
    raise exception '2: a OS não ficou confirmada para a data dela';
  end if;
  if not exists (select 1 from public.app_notifications where type = 'agendamento_confirmado' and navigate_to = '/v2/service-orders/' || v_os) then
    raise exception '2: o dono não foi avisado no sino';
  end if;

  -- Segundo "sim" não confirma de novo (já respondido).
  r := public.registrar_confirmacao_do_cliente(v_fone, 'sim', null);
  if (r ->> 'confirmou')::boolean then raise exception '2: confirmou duas vezes'; end if;

  -- 3. Quem pode chamar.
  if has_function_privilege('anon', 'public.pedir_confirmacao_do_agendamento(uuid, uuid)', 'execute') then
    raise exception '3: anon não pode pedir confirmação';
  end if;
  if has_function_privilege('authenticated', 'public.registrar_confirmacao_do_cliente(text, text, uuid)', 'execute')
     or has_function_privilege('anon', 'public.registrar_confirmacao_do_cliente(text, text, uuid)', 'execute') then
    raise exception '3: só o sistema registra a confirmação';
  end if;
end $$;

select 'ok: SIM reconhecido, "sim, mas…" não confirma, OS confirmada para a data, sino avisado, permissões certas' as resultado;
rollback;
