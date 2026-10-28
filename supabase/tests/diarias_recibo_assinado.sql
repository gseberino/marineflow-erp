-- Prova: o papel assinado fica anexado ao recibo (migration 20261027210000_diarias_recibo_assinado).
--
--   supabase db query --linked -f supabase/tests/diarias_recibo_assinado.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria um freelancer de teste com CPF fictício.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_dono uuid;
  v_hoje date := public._hoje_brt();
  v_fav uuid;
  r jsonb;
  v_ac uuid;
  v_antigo uuid;
  v_linha record;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  r := public.cadastrar_freelancer('Teste Assinado ' || lpad((floor(random() * 1000000))::int::text, 6, '0'),
                                   100, v_hoje - 10, null, null, null, null, null, false, v_dono);
  v_fav := (r ->> 'favorecido_id')::uuid;
  update public.payees set document = '999' || lpad((floor(random() * 100000000))::int::text, 8, '0') where id = v_fav;
  perform public.registrar_diaria(v_fav, v_hoje - 5, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category, payee_id, origin)
  values ('Pix teste assinado', v_hoje - 4, v_hoje - 4, 100, 100, 0, 'paid', 'Diárias de freelancers', v_fav, 'bank_reconciliation');
  v_ac := (public.fechar_acerto_diarias(v_fav, null, false, v_dono) ->> 'id')::uuid;

  -- A1. Anexa: marca assinado e guarda o caminho.
  r := public.anexar_recibo_assinado(v_ac, 'diarias/recibos/' || v_ac || '/papel.jpg', v_dono);
  select * into v_linha from public.acertos_diarias where id = v_ac;
  insert into _resultado values ('A1 anexa', (r ->> 'ok')::boolean and v_linha.assinado_em is not null
    and v_linha.assinatura_arquivo = 'diarias/recibos/' || v_ac || '/papel.jpg', r ->> 'message');

  -- A2. Arquivo de outra pasta é recusado.
  begin
    perform public.anexar_recibo_assinado(v_ac, 'diarias/recibos/outro/papel.jpg', v_dono);
    insert into _resultado values ('A2 outra pasta', false, 'aceitou');
  exception when others then
    insert into _resultado values ('A2 outra pasta', sqlerrm like 'Arquivo fora da pasta%', sqlerrm);
  end;

  -- A3. Acerto do modelo antigo (sem documento) e recibo reaberto não recebem papel.
  insert into public.acertos_diarias (favorecido_id, de, ate, saldo_anterior, dias, trabalhado, pago_no_periodo, valor_do_acerto, criado_por)
  values (v_fav, v_hoje - 60, v_hoje - 50, 0, 1, 100, 0, 100, v_dono) returning id into v_antigo;
  begin
    perform public.anexar_recibo_assinado(v_antigo, 'diarias/recibos/' || v_antigo || '/x.jpg', v_dono);
    insert into _resultado values ('A3a modelo antigo', false, 'aceitou');
  exception when others then
    insert into _resultado values ('A3a modelo antigo', sqlerrm like '%modelo antigo%', sqlerrm);
  end;
  perform public.reabrir_acerto_diarias(v_ac, 'teste', v_dono);
  begin
    perform public.anexar_recibo_assinado(v_ac, 'diarias/recibos/' || v_ac || '/papel2.jpg', v_dono);
    insert into _resultado values ('A3b reaberto', false, 'aceitou');
  exception when others then
    insert into _resultado values ('A3b reaberto', sqlerrm like '%reaberto%', sqlerrm);
  end;

  -- A4. Quem pode.
  insert into _resultado values ('A4 permissoes',
    not has_function_privilege('anon', 'public.anexar_recibo_assinado(uuid, text, uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.anexar_recibo_assinado(uuid, text, uuid)', 'execute'), null);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
