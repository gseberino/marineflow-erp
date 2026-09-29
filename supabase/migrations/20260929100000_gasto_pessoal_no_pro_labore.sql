-- Gasto pessoal do sócio desconta do pró-labore do mês (decisão do dono, 29/09/2026).
--
-- Os lançamentos em "Gasto Pessoal Sócio - Descontar PL" (compras pessoais que a empresa pagou)
-- ficavam fora da conta do pró-labore. O dono decidiu: "pode sim entrar na conta do pró-labore,
-- descontando parte do pagamento, pois são valores que foram gastos pessoais meus". Agora, em cada
-- mês aberto, a rotina soma esses gastos (pagos, do mês) e desconta do salário mínimo ANTES dos
-- Pix: o que sobra é o pró-labore dos Pix, e o resto dos Pix é retirada. O gasto continua com a
-- categoria dele. O total do mês (pró-labore dos Pix + gastos) nunca passa do salário mínimo;
-- se os gastos sozinhos passarem, todos os Pix do mês ficam como retirada, com aviso.
--
-- Só muda separar_pro_labore (texto de 20260928100000, conferido por md5 contra a produção).
-- Teste: supabase/tests/pro_labore_divisao.sql (conferências 13 a 15).

create or replace function public.separar_pro_labore(p_de date default null, p_ate date default null, p_autor uuid default null)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ate date := coalesce(p_ate, v_hoje);
  v_de date;
  v_socio record;
  v_mes date;
  v_salario numeric;
  v_restante numeric;
  g record;
  v_pl numeric;
  v_ret numeric;
  v_n integer;
  v_mudou integer := 0;
  v_adotados integer := 0;
  v_fechados integer := 0;
  v_meses jsonb := '[]'::jsonb;
  v_avisos text[] := array[]::text[];
  v_mes_pago numeric;
  v_mes_pl numeric;
  v_mes_ret numeric;
  v_mes_div integer;
  v_mes_mudou integer;
  v_pl_fora numeric;
  v_gastos numeric;
  v_unico boolean;
begin
  -- Há um sócio só na regra? Então o gasto pessoal lançado sem favorecido é dele. Com mais de um,
  -- só conta o gasto que tem o favorecido do sócio.
  v_unico := (select count(*) from public.payees p
               where p.kind = 'socio' and public._socio_com_pro_labore_pelo_minimo(p.id)) = 1;

  for v_socio in
    select p.id, p.name, regexp_replace(coalesce(p.document, ''), '\D', '', 'g') as doc
      from public.payees p
     where p.kind = 'socio' and public._socio_com_pro_labore_pelo_minimo(p.id)
     order by p.name
  loop
    -- Pagamento ao CPF do sócio sem o favorecido ligado (ex.: veio por uma regra de fornecedor).
    if length(v_socio.doc) in (11, 14) then
      with adotados as (
        update public.payables p
           set payee_id = v_socio.id
          from public.bank_transactions bt
         where bt.id = p.bank_transaction_id and p.payee_id is null and p.status = 'paid'
           and p.expense_category in ('Pró-labore', 'Retirada de sócio')
           and regexp_replace(coalesce(bt.counterparty_document, ''), '\D', '', 'g') = v_socio.doc
           and not public.periodo_esta_fechado(p.issue_date)
        returning p.id, p.amount, p.bank_transaction_id)
      insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, valor, detalhe)
      select 'identificou_socio', v_autor, a.bank_transaction_id, a.id, a.amount,
             'Pagamento ao CPF de ' || v_socio.name || ' ligado ao favorecido dele (documento igual identifica).'
               || case when v_autor is null then ' Rotina automática.' else '' end
        from adotados a;
      get diagnostics v_n = row_count;
      v_adotados := v_adotados + v_n;
    end if;

    v_de := date_trunc('month', coalesce(p_de,
              (select min(p.issue_date) from public.payables p
                where p.payee_id = v_socio.id and p.status = 'paid'
                  and p.expense_category in ('Pró-labore', 'Retirada de sócio')),
              v_hoje))::date;
    if v_ate < v_de then
      continue;
    end if;

    v_mes := v_de;
    while v_mes <= v_ate loop
      v_salario := public._salario_minimo_em(v_mes);
      if public.periodo_esta_fechado(v_mes) then
        v_fechados := v_fechados + 1;
      elsif v_salario is null or v_salario <= 0 then
        -- Só avisa se o sócio tem pagamento no mês (sem pagamento, não há o que separar).
        if exists (select 1 from public.payables p
                    where p.payee_id = v_socio.id and p.status = 'paid'
                      and p.expense_category in ('Pró-labore', 'Retirada de sócio')
                      and p.issue_date >= v_mes and p.issue_date < (v_mes + interval '1 month')::date) then
          v_avisos := v_avisos || ('Falta o salário mínimo de ' || extract(year from v_mes)::int
                                   || ' em Configurações (chave salario_minimo, "' || extract(year from v_mes)::int
                                   || '-01-01": valor): o pró-labore de ' || to_char(v_mes, 'MM/YYYY') || ' ficou como estava.');
        end if;
      else
        -- Pró-labore que já está num pagamento fora da regra (uma parte trocada à mão para outra
        -- categoria, por exemplo) conta no limite do mês: o mês nunca passa do salário mínimo.
        select coalesce(sum(x.amount), 0) into v_pl_fora
          from public.payables x
         where x.payee_id = v_socio.id and x.status = 'paid' and x.expense_category = 'Pró-labore'
           and x.issue_date >= v_mes and x.issue_date < (v_mes + interval '1 month')::date
           and exists (
             select 1 from public.payables y
              where (y.id = coalesce(x.divisao_id, x.id) or y.divisao_id = coalesce(x.divisao_id, x.id))
                and y.status <> 'cancelled'
                and (coalesce(y.expense_category, '') not in ('Pró-labore', 'Retirada de sócio')
                     or y.payee_id is distinct from v_socio.id or y.status <> 'paid'));
        -- Gasto pessoal que a empresa pagou desconta do pró-labore do mês (decisão do dono,
        -- 29/09/2026: "são gastos pessoais meus, que deverão ser evitados"). Conta antes dos Pix:
        -- o que sobra do salário mínimo é o pró-labore dos Pix, e o resto é retirada. O gasto
        -- fica com a categoria dele; só muda quanto dos Pix é pró-labore.
        select coalesce(sum(x.amount), 0) into v_gastos
          from public.payables x
         where x.status = 'paid' and x.expense_category = 'Gasto Pessoal Sócio - Descontar PL'
           and x.issue_date >= v_mes and x.issue_date < (v_mes + interval '1 month')::date
           and (x.payee_id = v_socio.id or (x.payee_id is null and v_unico));
        if v_gastos > greatest(0, v_salario - v_pl_fora) then
          v_avisos := v_avisos || ('Os gastos pessoais de ' || v_socio.name || ' em ' || to_char(v_mes, 'MM/YYYY')
                                   || ' (' || public._brl(v_gastos) || ') passam do salário mínimo do mês ('
                                   || public._brl(v_salario) || '): todos os Pix do mês ficaram como retirada.');
        end if;
        v_restante := greatest(0, v_salario - v_pl_fora - v_gastos);
        v_mes_pago := 0; v_mes_pl := 0; v_mes_ret := 0; v_mes_div := 0; v_mes_mudou := 0;
        for g in
          select r.id,
                 r.bank_transaction_id,
                 abs(bt.amount) as valor_linha,
                 (select sum(x.amount) from public.payables x
                   where (x.id = r.id or x.divisao_id = r.id) and x.status <> 'cancelled') as total,
                 exists (select 1 from public.payments pm where pm.payable_id = r.id and pm.status = 'confirmed') as tem_pagamento
            from public.payables r
            left join public.bank_transactions bt on bt.id = r.bank_transaction_id
           where r.payee_id = v_socio.id and r.divisao_id is null and r.status = 'paid'
             and r.issue_date >= v_mes and r.issue_date < (v_mes + interval '1 month')::date
             -- O pagamento inteiro é do sócio, pago, e só pró-labore/retirada. Outra categoria numa
             -- parte (gasto pessoal, por exemplo) é decisão à mão: fica como está.
             and not exists (
               select 1 from public.payables x
                where (x.id = r.id or x.divisao_id = r.id) and x.status <> 'cancelled'
                  and (coalesce(x.expense_category, '') not in ('Pró-labore', 'Retirada de sócio')
                       or x.payee_id is distinct from v_socio.id or x.status <> 'paid'))
           order by r.issue_date, bt.transaction_date nulls last, bt.created_at nulls last, r.created_at, r.id
        loop
          -- Divide só o Pix comum: ligado ao banco, com a soma igual ao valor da linha e sem
          -- pagamento registrado à parte. Compra parcelada e afins vão inteiras.
          if g.bank_transaction_id is not null and not g.tem_pagamento and abs(g.total - g.valor_linha) <= 0.005 then
            v_pl := least(v_restante, g.total);
          else
            v_pl := case when g.total <= v_restante then g.total else 0 end;
          end if;
          v_ret := g.total - v_pl;
          -- Cada pagamento num bloco próprio: se um der erro (categoria desativada, mês fechado no
          -- meio), ele fica como estava e os outros seguem. A conferência das partes roda aqui
          -- dentro, e não só no fim da transação, para o erro cair neste bloco.
          begin
            v_n := public._aplicar_pro_labore(g.id, v_pl, v_ret, v_salario, v_mes, v_autor);
            if v_n < 0 then
              raise exception 'o lançamento mudou durante a separação; fica para a próxima rodada';
            end if;
            set constraints public.payables_divisao_confere immediate;
            set constraints public.payables_divisao_confere deferred;
            v_mes_mudou := v_mes_mudou + v_n;
          exception when others then
            v_avisos := v_avisos || ('Não consegui separar o pagamento de ' || public._brl(g.total) || ' de '
                                     || v_socio.name || ' (' || to_char(v_mes, 'MM/YYYY') || ', lançamento ' || g.id
                                     || '): ' || sqlerrm || '. Ficou como estava.');
            -- Ficou como estava: o pró-labore que ele já tem conta no limite do mês.
            select coalesce(sum(x.amount) filter (where x.expense_category = 'Pró-labore'), 0),
                   coalesce(sum(x.amount) filter (where x.expense_category = 'Retirada de sócio'), 0)
              into v_pl, v_ret
              from public.payables x
             where (x.id = g.id or x.divisao_id = g.id) and x.status <> 'cancelled';
          end;
          v_restante := greatest(0, v_restante - v_pl);
          v_mes_pago := v_mes_pago + g.total;
          v_mes_pl := v_mes_pl + v_pl;
          v_mes_ret := v_mes_ret + v_ret;
          if v_pl > 0 and v_ret > 0 then
            v_mes_div := v_mes_div + 1;
          end if;
        end loop;
        v_mudou := v_mudou + v_mes_mudou;
        if v_mes_pago > 0 or v_pl_fora > 0 or v_gastos > 0 then
          v_meses := v_meses || jsonb_build_object(
            'socio', v_socio.name, 'mes', to_char(v_mes, 'YYYY-MM'), 'salario_minimo', v_salario,
            'pago', v_mes_pago, 'pro_labore', v_mes_pl + v_pl_fora, 'retirada', v_mes_ret,
            'pro_labore_fora_da_regra', v_pl_fora, 'gastos_pessoais', v_gastos,
            'divididos', v_mes_div, 'mudados', v_mes_mudou,
            'faltou_para_o_minimo', greatest(0, v_salario - v_mes_pl - v_pl_fora - v_gastos));
        end if;
      end if;
      v_mes := (v_mes + interval '1 month')::date;
    end loop;
  end loop;

  if cardinality(v_avisos) > 0 then
    -- source só aceita frontend/edge/db; quem avisa vai no contexto.
    perform public.log_app_error('db', array_to_string(v_avisos, ' | '), 'separar_pro_labore',
                                 case when v_autor is null then 'rotina' else 'manual' end, 'warn',
                                 jsonb_build_object('avisos', to_jsonb(v_avisos)));
  end if;
  return jsonb_build_object('ok', true, 'ate', v_ate, 'lancamentos_mudados', v_mudou,
                            'favorecido_pelo_documento', v_adotados, 'meses_fechados', v_fechados,
                            'meses', v_meses, 'avisos', to_jsonb(v_avisos));
end;
$$;

revoke all on function public.separar_pro_labore(date, date, uuid) from public, anon, authenticated;
grant execute on function public.separar_pro_labore(date, date, uuid) to service_role;
