-- Prova: o Pix dividido (pró-labore + retirada de sócio) se comporta como UM pagamento
-- (migration 20260928100000_pro_labore_pelo_salario_minimo).
--
-- ═══ COMO RODAR ═══
--
--   supabase db query --linked -f supabase/tests/pro_labore_divisao.sql --output json
--
-- Seguro em produção: cada teste roda num bloco que se desfaz (exceção proposital no fim) e a
-- transação inteira termina em ROLLBACK. Usa o Pix dividido mais recente que existir; sem nenhum,
-- os testes que precisam dele saem como "sem dado".
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- O Pix dividido mais recente: principal, parte e a linha do banco.
create temp table _grupo on commit drop as
select p.id as raiz, x.id as parte, p.bank_transaction_id as linha, p.payee_id as socio,
       p.issue_date as data, p.amount + x.amount as total
  from public.payables p
  join public.payables x on x.divisao_id = p.id and x.status <> 'cancelled'
 where p.divisao_id is null and p.status = 'paid'
 order by p.issue_date desc, p.id
 limit 1;

do $$
declare
  g record;
  v text;
  v_n integer;
begin
  select * into g from _grupo;
  if g.raiz is null then
    insert into _resultado values ('grupo', true, 'sem Pix dividido no banco: testes de comportamento pulados');
    return;
  end if;

  -- T1. Lançamento avulso numa linha dividida é barrado pela trava.
  begin
    insert into public.payables (description, issue_date, due_date, amount, status, bank_transaction_id, origin)
    values ('teste avulso', g.data, g.data, 10, 'paid', g.linha, 'manual');
    insert into _resultado values ('T1 trava', false, 'entrou lançamento avulso na linha dividida');
  exception when exclusion_violation then
    insert into _resultado values ('T1 trava', true, 'barrado pela payables_uma_por_transacao');
  end;

  -- T2. Mexer no valor de uma parte sozinha não passa na conferência.
  begin
    update public.payables set amount = amount + 1 where id = g.parte;
    set constraints all immediate;
    insert into _resultado values ('T2 conferência', false, 'a parte mudou de valor sozinha');
  exception when check_violation then
    insert into _resultado values ('T2 conferência', true, left(sqlerrm, 120));
  end;

  -- T3. Desfazer pela PARTE junta tudo e devolve a linha à fila.
  begin
    v := public.desfazer_aprovacao('payable', g.parte, 'teste automático', null) ->> 'message';
    set constraints all immediate;
    select count(*) into v_n from public.payables where bank_transaction_id = g.linha;
    if v_n = 0 and (select status = 'cancelled' and amount = g.total from public.payables where id = g.raiz) then
      v := 'ok: ' || v;
    else
      v := 'FALHOU: ' || v_n || ' lançamento(s) vivos na linha';
    end if;
    raise exception 'fim do teste' using errcode = 'P0001', detail = v;
  exception when sqlstate 'P0001' then
    get stacked diagnostics v = pg_exception_detail;
    insert into _resultado values ('T3 desfazer pela parte', v like 'ok:%', v);
  end;

  -- T4. Cancelar pelo PRINCIPAL cancela o pagamento inteiro.
  begin
    v := public.cancelar_lancamento('payable', g.raiz, 'teste automático', null) ->> 'message';
    set constraints all immediate;
    select count(*) into v_n from public.payables where (id = g.raiz or divisao_id = g.raiz) and status <> 'cancelled';
    raise exception 'fim do teste' using errcode = 'P0001', detail = case when v_n = 0 then 'ok: ' || v else 'FALHOU: sobrou parte viva' end;
  exception when sqlstate 'P0001' then
    get stacked diagnostics v = pg_exception_detail;
    insert into _resultado values ('T4 cancelar pelo principal', v like 'ok:%', v);
  end;

  -- T5. Corrigir não desencontra as partes; a troca pró-labore × retirada é da regra.
  begin
    perform public.corrigir_lancamento('payable', g.parte,
      jsonb_build_object('payee_id', (select id from public.payees where id <> g.socio limit 1)), 'teste', null);
    insert into _resultado values ('T5a favorecido de uma parte só', false, 'mudou');
  exception when check_violation then
    insert into _resultado values ('T5a favorecido de uma parte só', true, 'recusado');
  end;
  if public._socio_com_pro_labore_pelo_minimo(g.socio) then
    begin
      perform public.corrigir_lancamento('payable', g.parte, '{"expense_category": "Pró-labore"}'::jsonb, 'teste', null);
      insert into _resultado values ('T5b retirada → pró-labore à mão', false, 'mudou');
    exception when check_violation then
      insert into _resultado values ('T5b retirada → pró-labore à mão', true, 'recusado');
    end;
  end if;
  begin
    v := public.corrigir_lancamento('payable', g.parte, '{"notes": "teste automático"}'::jsonb, 'teste', null) ->> 'message';
    raise exception 'fim do teste' using errcode = 'P0001', detail = 'ok: ' || v;
  exception when sqlstate 'P0001' then
    get stacked diagnostics v = pg_exception_detail;
    insert into _resultado values ('T5c anotação na parte', v like 'ok:%', v);
  end;

  -- T6. A separação é idempotente no mês do Pix.
  begin
    v := public.separar_pro_labore(date_trunc('month', g.data)::date, (date_trunc('month', g.data) + interval '1 month - 1 day')::date, null) ->> 'lancamentos_mudados';
    raise exception 'fim do teste' using errcode = 'P0001', detail = v;
  exception when sqlstate 'P0001' then
    get stacked diagnostics v = pg_exception_detail;
    insert into _resultado values ('T6 separar de novo não muda nada', v = '0', v || ' lançamento(s) mudariam');
  end;

  -- T7. O Extrato com saldo mostra a linha dividida uma vez só.
  select count(*) into v_n
    from public.bank_transactions t
    cross join lateral public.extrato_da_conta(t.bank_connection_id, g.data, g.data) e
   where t.id = g.linha and e.id = g.linha;
  insert into _resultado values ('T7 extrato: uma linha', v_n = 1, v_n || ' linha(s)');

  -- T8. A Conciliação não acusa diferença nas partes.
  select count(*) into v_n from public.conciliacao_lancamentos
   where id in (g.raiz, g.parte) and coalesce(diferenca, 0) <> 0;
  insert into _resultado values ('T8 conciliação sem diferença', v_n = 0, v_n || ' parte(s) com diferença');
end $$;

-- T9. Só o sistema chama a separação e as peças internas.
insert into _resultado
select 'T9 permissões',
       not (has_function_privilege('anon', 'public.separar_pro_labore(date,date,uuid)', 'EXECUTE')
            or has_function_privilege('authenticated', 'public.separar_pro_labore(date,date,uuid)', 'EXECUTE')
            or has_function_privilege('anon', 'public._juntar_divisao(uuid,text,uuid)', 'EXECUTE')
            or has_function_privilege('authenticated', 'public._juntar_divisao(uuid,text,uuid)', 'EXECUTE')
            or has_function_privilege('authenticated', 'public._aplicar_pro_labore(uuid,numeric,numeric,numeric,date,uuid)', 'EXECUTE')),
       'separar, juntar e aplicar fechados para anon e authenticated';

-- T10. Toda linha dividida soma o valor do banco (varredura completa).
insert into _resultado
select 'T10 todas as divisões somam a linha', count(*) = 0, count(*) || ' linha(s) com soma diferente'
  from (select p.bank_transaction_id, sum(p.amount) soma
          from public.payables p
         where p.status <> 'cancelled' and p.bank_transaction_id in (select bank_transaction_id from public.payables where divisao_id is not null and status <> 'cancelled')
         group by 1) s
  join public.bank_transactions t on t.id = s.bank_transaction_id
 where abs(s.soma - abs(t.amount)) > 0.005;

select teste, ok, detalhe from _resultado order by teste;
rollback;
