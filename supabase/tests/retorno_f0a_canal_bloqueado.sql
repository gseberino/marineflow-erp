-- Retorno F0a-1: canal_bloqueado e a recusa do "Cliente Final" na fila.
-- Run: npx supabase db query --linked -f supabase/tests/retorno_f0a_canal_bloqueado.sql
-- Termina em ROLLBACK: nada fica gravado, e a fila não vê linha que não foi confirmada.
begin;

do $$
declare
  v_generico uuid := (select id from public.clients where generico limit 1);
  v_cliente uuid := (select id from public.clients where not generico and active limit 1);
  v_fornecedor uuid := (select id from public.suppliers where active limit 1);
  v_dono text := (select phone_normalized from public.app_users where active and phone_normalized is not null limit 1);
  v_fila uuid;
  v_status text;
  v_motivo text;
begin
  if v_generico is null or v_cliente is null or v_fornecedor is null or v_dono is null then
    raise exception '0: faltou cadastro para o teste (genérico %, cliente %, fornecedor %, dono %)',
      v_generico, v_cliente, v_fornecedor, v_dono;
  end if;

  -- 1. O telefone do "Cliente Final", com e sem 55, com máscara e sem o 9 da frente.
  update public.clients set phone = '5547900007001', whatsapp = null where id = v_generico;
  if public.canal_bloqueado('5547900007001') is distinct from 'cliente_final'
     or public.canal_bloqueado('(47) 90000-7001') is distinct from 'cliente_final'
     or public.canal_bloqueado('4700007001') is distinct from 'cliente_final' then
    raise exception '1: o número do Cliente Final não foi recusado em todas as grafias';
  end if;

  -- 2. Número sem nada: livre. Nulo ou curto: livre (não há o que comparar).
  if public.canal_bloqueado('5547900007999') is not null
     or public.canal_bloqueado(null) is not null
     or public.canal_bloqueado('1234') is not null then
    raise exception '2: número sem cadastro bloqueado';
  end if;

  -- 3. Lista de bloqueio.
  insert into public.whatsapp_blocked_numbers (phone_normalized, reason) values ('5547900007002', 'teste F0a');
  if public.canal_bloqueado('47 9 0000-7002') is distinct from 'bloqueado' then
    raise exception '3: número da lista de bloqueio não recusado';
  end if;

  -- 4. Cliente que pediu para não receber, pelo whatsapp ou pelo phone.
  update public.clients set whatsapp = '(47) 90000-7003', phone = '5547900007004', opt_out_whatsapp = true where id = v_cliente;
  if public.canal_bloqueado('5547900007003') is distinct from 'opt_out'
     or public.canal_bloqueado('5547900007004') is distinct from 'opt_out' then
    raise exception '4: opt-out do cliente não recusado';
  end if;
  update public.clients set opt_out_whatsapp = false where id = v_cliente;
  if public.canal_bloqueado('5547900007003') is not null then
    raise exception '4b: cliente sem opt-out ficou bloqueado';
  end if;

  -- 5. Fornecedor que pediu para não receber.
  update public.suppliers set phone = '5547900007005', opt_out_whatsapp = true where id = v_fornecedor;
  if public.canal_bloqueado('5547900007005') is distinct from 'opt_out' then
    raise exception '5: opt-out do fornecedor não recusado';
  end if;

  -- 6. O número da equipe nunca é bloqueado, nem se cair no Cliente Final ou na lista.
  update public.clients set phone = v_dono where id = v_generico;
  insert into public.whatsapp_blocked_numbers (phone_normalized, reason) values (v_dono, 'teste F0a');
  if public.canal_bloqueado(v_dono) is not null then
    raise exception '6: o número da equipe foi bloqueado';
  end if;
  update public.clients set phone = '5547900007001' where id = v_generico;

  -- 7. Fila: para o Cliente Final nasce cancelada, com o motivo; para outro número, pendente.
  insert into public.whatsapp_send_queue (phone_normalized, message, source)
    values ('5547900007001', 'teste F0a', 'ai_agent') returning id, status, failed_reason into v_fila, v_status, v_motivo;
  if v_status is distinct from 'cancelled' or v_motivo not like 'Recusado:%Cliente Final%' then
    raise exception '7: linha da fila ao Cliente Final ficou %, motivo %', v_status, v_motivo;
  end if;
  insert into public.whatsapp_send_queue (phone_normalized, message, source)
    values ('5547900007999', 'teste F0a', 'ai_agent') returning id, status into v_fila, v_status;
  if v_status is distinct from 'pending' then
    raise exception '7b: linha comum da fila ficou %', v_status;
  end if;

  -- 8. Trocar o telefone de uma linha pendente para o do Cliente Final também cancela.
  update public.whatsapp_send_queue set phone_normalized = '5547900007001' where id = v_fila
    returning status into v_status;
  if v_status is distinct from 'cancelled' then
    raise exception '8: troca de telefone para o Cliente Final ficou %', v_status;
  end if;

  -- 9. Só o servidor chama: anon e authenticated não executam.
  if has_function_privilege('anon', 'public.canal_bloqueado(text)', 'execute')
     or has_function_privilege('authenticated', 'public.canal_bloqueado(text)', 'execute')
     or not has_function_privilege('service_role', 'public.canal_bloqueado(text)', 'execute') then
    raise exception '9: permissão de execução errada em canal_bloqueado';
  end if;

  raise notice 'retorno_f0a_canal_bloqueado: OK';
end $$;

rollback;
