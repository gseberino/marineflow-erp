-- Prova: serviços do prestador na conta corrente (migration 20270105102000_servicos_do_prestador) e o
-- "Registrar pagamento" da tela para ele (T12–T16, migration 20270113100000_pagamento_do_prestador_pela_tela).
--
-- ═══ COMO RODAR ═══
--
--   npx supabase@2.111.0 db query --linked -f supabase/tests/servicos_do_prestador.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria um prestador de teste com CNPJ fictício e usa duas OS reais
-- (uma paga, uma não paga) só dentro da transação. A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_hoje date := public._hoje_brt();
  v_dono uuid;
  v_fav uuid;
  v_paga uuid;
  v_aberta uuid;
  v_base numeric;
  v_esperado numeric;
  v_serv uuid;
  v_cnpj text := '99' || lpad((floor(random() * 1000000000000))::bigint::text, 12, '0');
  r jsonb;
  c jsonb;
  v_msg text;
  v_antes numeric;
  v_dia uuid;
  v_sem uuid;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  select so.id into v_paga from public.service_orders so
   where so.payment_status = 'paid' and so.status <> 'cancelled' and so.labor_cost_total > 0
   order by so.created_at desc limit 1;
  select so.id into v_aberta from public.service_orders so
   where so.payment_status = 'unpaid' and so.status not in ('cancelled') and so.grand_total > 0
   order by so.created_at desc limit 1;

  insert into public.payees (name, kind, active, conta_corrente_desde, document)
  values ('Prestador Teste ' || substr(md5(random()::text), 1, 6), 'prestador', true, v_hoje - 30, v_cnpj)
  returning id into v_fav;
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               payee_id, origin)
  values ('Pix serviço', v_hoje - 20, v_hoje - 20, 300, 300, 0, 'paid', 'Serviços de terceiros', v_fav, 'bank_reconciliation'),
         ('Pix almoço', v_hoje - 19, v_hoje - 19, 50, 50, 0, 'paid', 'Alimentação de campo', v_fav, 'bank_reconciliation');

  -- T01. Valor combinado em OS não paga: fora do saldo, "aguardando o cliente pagar".
  r := public.registrar_servico_prestador(v_fav, v_aberta, 500, null, null, 'Troca do banco de baterias', v_hoje - 10, v_dono);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T01 combinado em OS nao paga fica fora do saldo',
    (r ->> 'entra_na_conta')::boolean = false and (c ->> 'saldo_final')::numeric = -300
      and (c ->> 'aguardando_cliente')::numeric = 500 and c ->> 'estado' = 'adiantado'
      and (c -> 'favorecido' ->> 'modo') = 'servico',
    format('entra=%s saldo=%s aguardando=%s estado=%s', r ->> 'entra_na_conta', c ->> 'saldo_final',
           c ->> 'aguardando_cliente', c ->> 'estado'));

  -- T02. Percentual da mão de obra em OS já paga: entra na conta, congelado.
  v_base := public._base_do_servico(v_paga, 'mao_de_obra');
  v_esperado := round(0.30 * greatest(v_base, 0), 2);
  r := public.registrar_servico_prestador(v_fav, v_paga, null, 30, 'mao_de_obra', null, null, v_dono);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T02 percentual em OS paga entra na conta',
    (r ->> 'entra_na_conta')::boolean and (r ->> 'valor')::numeric = v_esperado
      and (c ->> 'saldo_final')::numeric = -300 + v_esperado and (c ->> 'servicos')::numeric = v_esperado
      and exists (select 1 from jsonb_array_elements(c -> 'linhas') x where x ->> 'tipo' = 'servico'),
    format('base=%s esperado=%s valor=%s saldo=%s', v_base, v_esperado, r ->> 'valor', c ->> 'saldo_final'));

  -- T03. Registrar de novo na mesma OS corrige (não duplica).
  r := public.registrar_servico_prestador(v_fav, v_paga, 200, null, null, null, null, v_dono);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T03 mesma OS substitui',
    (r ->> 'substituiu')::boolean and (c ->> 'saldo_final')::numeric = -100
      and (select count(*) from public.commissions where payee_id = v_fav and service_order_id = v_paga
                                                  and status is distinct from 'cancelled') = 1,
    format('saldo=%s', c ->> 'saldo_final'));

  -- T04. O cliente paga a OS aberta: o gatilho põe o serviço na conta.
  update public.service_orders set payment_status = 'paid' where id = v_aberta;
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T04 OS paga poe o servico na conta',
    (c ->> 'saldo_final')::numeric = 400 and (c ->> 'aguardando_cliente')::numeric = 0
      and (select cliente_pagou_em from public.commissions where payee_id = v_fav and service_order_id = v_aberta
                                                            and status is distinct from 'cancelled') is not null,
    format('saldo=%s aguardando=%s', c ->> 'saldo_final', c ->> 'aguardando_cliente'));

  -- T05. Pagamento estornado: o serviço volta a aguardar o cliente.
  update public.service_orders set payment_status = 'unpaid' where id = v_aberta;
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T05 estorno tira o servico da conta',
    (c ->> 'saldo_final')::numeric = -100 and (c ->> 'aguardando_cliente')::numeric = 500,
    format('saldo=%s aguardando=%s', c ->> 'saldo_final', c ->> 'aguardando_cliente'));

  -- T06. Apagar o serviço da OS paga.
  select id into v_serv from public.commissions where payee_id = v_fav and service_order_id = v_paga
                                                   and status is distinct from 'cancelled';
  r := public.apagar_servico_prestador(v_serv, v_dono);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T06 apagar tira da conta',
    (r ->> 'apagado')::boolean and (c ->> 'saldo_final')::numeric = -300,
    format('saldo=%s', c ->> 'saldo_final'));

  -- T07. Percentual sem base: pergunta a base, não grava.
  begin
    perform public.registrar_servico_prestador(v_fav, v_paga, null, 20, null, null, null, v_dono);
    v_msg := 'gravou';
  exception when others then v_msg := sqlerrm;
  end;
  insert into _resultado values ('T07 percentual sem base pergunta', v_msg like '%base%', v_msg);

  -- T08. Simular não grava.
  r := public.registrar_servico_prestador(v_fav, v_paga, 150, null, null, null, null, v_dono, true);
  insert into _resultado values ('T08 simular nao grava',
    (r ->> 'simulacao')::boolean and r ->> 'message' like '%Valor combinado%'
      and not exists (select 1 from public.commissions where payee_id = v_fav and service_order_id = v_paga
                                                         and status is distinct from 'cancelled'),
    r ->> 'message');

  -- T09. O recibo de diárias recusa o prestador.
  begin
    insert into public.acertos_diarias (favorecido_id, de, ate, saldo_anterior, dias, trabalhado, pago_no_periodo,
                                        valor_do_acerto, criado_por)
    values (v_fav, v_hoje - 30, v_hoje, 0, 0, 0, 0, 0, v_dono);
    v_msg := 'gravou';
  exception when others then v_msg := sqlerrm;
  end;
  insert into _resultado values ('T09 recibo de diarias recusa prestador', v_msg like 'Recibo de diárias é só para diarista%', v_msg);

  -- T10. O resumo mostra o prestador.
  c := public.resumo_freelancers(null, null, v_dono);
  insert into _resultado values ('T10 resumo inclui o prestador',
    exists (select 1 from jsonb_array_elements(c -> 'pessoas') x where (x ->> 'id')::uuid = v_fav and x ->> 'modo' = 'servico'),
    null);

  -- T11. Quem executa: anon não; authenticated sim.
  insert into _resultado values ('T11 anon nao executa',
    not has_function_privilege('anon', 'public.registrar_servico_prestador(uuid, uuid, numeric, numeric, text, text, date, uuid, boolean)', 'execute')
      and not has_function_privilege('anon', 'public.servicos_do_prestador(uuid, uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public._base_do_servico(uuid, text)', 'execute')
      and has_function_privilege('authenticated', 'public.registrar_servico_prestador(uuid, uuid, numeric, numeric, text, text, date, uuid, boolean)', 'execute'),
    null);
  -- T12. "Registrar pagamento" da tela (registrar_pagamento_do_freelancer, 13/11/2026): o prestador entra;
  -- em dinheiro vai ao Caixa em "Serviços de terceiros", com "Pagamento de serviços", e desconta do saldo.
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  v_antes := (c ->> 'saldo_final')::numeric;
  r := public.registrar_pagamento_do_freelancer(v_fav, 123.45, v_hoje, 'dinheiro', null, '{}'::uuid[], null, v_dono);
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  insert into _resultado values ('T12 pagamento do prestador pela tela: Servicos de terceiros e desconta',
    coalesce((r ->> 'ok')::boolean, false)
      and coalesce((select pa.expense_category = 'Serviços de terceiros' and pa.description like 'Pagamento de serviços — %'
                      from public.payables pa where pa.id = (r ->> 'payable_id')::uuid), false)
      and round((c ->> 'saldo_final')::numeric, 2) = round(v_antes - 123.45, 2),
    format('msg=%s saldo %s -> %s', r ->> 'message', v_antes, c ->> 'saldo_final'));

  -- T13. Pix do prestador: anotado em "Serviços de terceiros" (valor quebrado para não casar com linha real).
  r := public.registrar_pagamento_do_freelancer(v_fav, 517.39, v_hoje, 'pix', null, '{}'::uuid[], null, v_dono);
  insert into _resultado values ('T13 Pix do prestador anotado em Servicos de terceiros',
    coalesce((r ->> 'ok')::boolean, false)
      and coalesce((select an.categoria = 'Serviços de terceiros' and an.favorecido_id = v_fav
                      from public.anotacoes_do_extrato an where an.id = (r ->> 'anotacao_id')::uuid), false),
    r ->> 'message');

  -- T14. Prestador não divide reembolso de comprovante: recusa com o caminho.
  begin
    r := public.registrar_pagamento_do_freelancer(v_fav, 100, v_hoje, 'dinheiro', null, array[gen_random_uuid()], null, v_dono);
    v_msg := 'gravou';
  exception when others then v_msg := sqlerrm;
  end;
  insert into _resultado values ('T14 prestador nao divide reembolso', v_msg like 'Reembolso de comprovante só se divide%', v_msg);

  -- T15. Diarista: nada muda (Diárias de freelancers, "Pagamento de diárias").
  insert into public.payees (name, kind, active, conta_corrente_desde)
  values ('Diarista Teste ' || substr(md5(random()::text), 1, 6), 'diarista', true, v_hoje - 30) returning id into v_dia;
  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio)
  values (v_dia, 'freelancer', 'diaria', 300, v_hoje - 30);
  r := public.registrar_pagamento_do_freelancer(v_dia, 80, v_hoje, 'dinheiro', null, '{}'::uuid[], null, v_dono);
  insert into _resultado values ('T15 diarista continua em Diarias de freelancers',
    coalesce((select pa.expense_category = 'Diárias de freelancers' and pa.description like 'Pagamento de diárias — Diarista%'
                from public.payables pa where pa.id = (r ->> 'payable_id')::uuid), false),
    r ->> 'message');

  -- T16. Prestador SEM conta corrente continua recusado (só entra quem tem conta corrente).
  insert into public.payees (name, kind, active) values ('Prestador Sem Conta ' || substr(md5(random()::text), 1, 6), 'prestador', true)
  returning id into v_sem;
  begin
    r := public.registrar_pagamento_do_freelancer(v_sem, 50, v_hoje, 'dinheiro', null, '{}'::uuid[], null, v_dono);
    v_msg := 'gravou';
  exception when others then v_msg := sqlerrm;
  end;
  insert into _resultado values ('T16 prestador sem conta corrente continua recusado', v_msg like 'Freelancer de diária não encontrado%', v_msg);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
