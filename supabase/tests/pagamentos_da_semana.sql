-- Prova: a fila de pagamentos da semana sai na ordem da consequência do atraso, com o reembolso ao sócio fora dela, e o
-- dono define o grupo de um fornecedor uma vez (migration 20270224100000_pagamentos_da_semana).
--
-- ═══ COMO RODAR ═══
--
--   npx supabase@2.111.0 db query --linked -f <caminho completo>/supabase/tests/pagamentos_da_semana.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria contas a pagar de teste só dentro da transação (nomes com um sufixo
-- aleatório). A função devolve também as contas reais em aberto, então as provas olham só as contas de teste (pelo id)
-- e as invariantes do conjunto. A tabela final tem de mostrar ok = true em todas as linhas.
--
-- ANTES de a migration estar aplicada: rodar o ensaio (a migration + este corpo na mesma transação).
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Uma conta a pagar de teste.
create function pg_temp.conta(p_nome text, p_valor numeric, p_venc date, p_categoria text default null, p_linha text default null,
                              p_status text default 'pending', p_pago numeric default 0, p_notas text default null,
                              p_origem text default 'manual') returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into public.payables (supplier_name, description, issue_date, due_date, amount, status, paid_amount, balance_amount,
                               origin, boleto_linha, expense_category, notes)
  values (p_nome, 'conta de teste dos pagamentos da semana', p_venc - 10, p_venc, p_valor, p_status, p_pago, p_valor - p_pago,
          p_origem, p_linha, p_categoria, p_notas)
  returning id into v;
  return v;
end $$;

-- A conta dentro da resposta (null = não veio).
create function pg_temp.na_fila(r jsonb, p_id uuid) returns jsonb
language sql as $$ select c from jsonb_array_elements(r->'contas') c where (c->>'id')::uuid = p_id $$;

-- A posição (1 = primeira) de uma conta na fila.
create function pg_temp.posicao(r jsonb, p_id uuid) returns int
language sql as $$ select n::int from jsonb_array_elements(r->'contas') with ordinality as t(c, n) where (c->>'id')::uuid = p_id $$;

do $$
declare
  v_hoje date := public._hoje_brt();
  v_ate date := v_hoje + 5;
  s text := ' ' || replace(gen_random_uuid()::text, '-', '');
  c_imposto uuid; c_internet uuid; c_boleto uuid; c_resto uuid; c_resto2 uuid; c_cedo uuid; c_tarde uuid;
  c_depois uuid; c_paga uuid; c_cancelada uuid; c_parcial uuid; c_socio uuid; c_sem_nome uuid; c_folha uuid;
  r jsonb; r2 jsonb; d jsonb;
  n int; v_txt text;
begin
  -- P1: a ordem — grupo primeiro (mesmo vencendo depois), vencimento dentro do grupo
  c_resto    := pg_temp.conta('TESTE RESTO' || s, 31.07, v_hoje - 20, 'Material de escritório');
  c_boleto   := pg_temp.conta('TESTE BOLETO' || s, 32.07, v_hoje - 15, null, '99990000000000000000000000000000000000000000001', 'pending', 0, null, 'boleto');
  c_internet := pg_temp.conta('TESTE INTERNET' || s, 33.07, v_hoje - 1, 'Telefonia e internet');
  c_imposto  := pg_temp.conta('TESTE IMPOSTO' || s, 34.07, v_hoje + 3, 'Impostos e taxas');
  c_folha    := pg_temp.conta('TESTE FOLHA' || s, 35.07, v_hoje + 4, null, null, 'pending', 0, null, 'folha');
  c_cedo     := pg_temp.conta('TESTE DIARIA A' || s, 36.07, v_hoje - 30, 'Diárias de freelancers');
  c_tarde    := pg_temp.conta('TESTE DIARIA B' || s, 37.07, v_hoje - 2, 'Diárias de freelancers');
  r := public.pagamentos_da_semana(v_hoje, v_ate);

  insert into _resultado values ('P1 a ordem é grupo e, dentro dele, vencimento: diárias, imposto, folha, internet, boleto, resto',
    pg_temp.posicao(r, c_cedo) < pg_temp.posicao(r, c_tarde)
    and pg_temp.posicao(r, c_tarde) < pg_temp.posicao(r, c_imposto)
    and pg_temp.posicao(r, c_imposto) < pg_temp.posicao(r, c_folha)
    and pg_temp.posicao(r, c_folha) < pg_temp.posicao(r, c_internet)
    and pg_temp.posicao(r, c_internet) < pg_temp.posicao(r, c_boleto)
    and pg_temp.posicao(r, c_boleto) < pg_temp.posicao(r, c_resto),
    format('%s %s %s %s %s %s %s', pg_temp.posicao(r, c_cedo), pg_temp.posicao(r, c_tarde), pg_temp.posicao(r, c_imposto),
           pg_temp.posicao(r, c_folha), pg_temp.posicao(r, c_internet), pg_temp.posicao(r, c_boleto), pg_temp.posicao(r, c_resto)));

  insert into _resultado values ('P2 cada conta no seu grupo (1 pessoas e impostos, 2 corta serviço, 3 boleto, 4 resto)',
    (pg_temp.na_fila(r, c_cedo)->>'grupo')::int = 1 and (pg_temp.na_fila(r, c_imposto)->>'grupo')::int = 1
    and (pg_temp.na_fila(r, c_folha)->>'grupo')::int = 1 and (pg_temp.na_fila(r, c_internet)->>'grupo')::int = 2
    and (pg_temp.na_fila(r, c_boleto)->>'grupo')::int = 3 and (pg_temp.na_fila(r, c_resto)->>'grupo')::int = 4, '');

  d := pg_temp.na_fila(r, c_boleto);
  insert into _resultado values ('P3 a conta traz valor, vencimento, vencida e a linha do boleto',
    (d->>'valor')::numeric = 32.07 and (d->>'vencimento')::date = v_hoje - 15 and (d->>'vencida')::boolean
    and d->>'boleto_linha' = '99990000000000000000000000000000000000000000001'
    and not (pg_temp.na_fila(r, c_imposto)->>'vencida')::boolean, d::text);

  insert into _resultado values ('P4 boleto sem categoria e sem resposta do dono: grupo "a definir"; com categoria, não',
    (pg_temp.na_fila(r, c_boleto)->>'a_definir')::boolean and not (pg_temp.na_fila(r, c_internet)->>'a_definir')::boolean
    and not (pg_temp.na_fila(r, c_resto)->>'a_definir')::boolean, '');

  -- P5: a janela e a situação
  c_depois    := pg_temp.conta('TESTE DEPOIS' || s, 41.07, v_ate + 1, 'Impostos e taxas');
  c_paga      := pg_temp.conta('TESTE PAGA' || s, 42.07, v_hoje - 3, 'Impostos e taxas', null, 'paid', 42.07);
  c_cancelada := pg_temp.conta('TESTE CANCELADA' || s, 43.07, v_hoje - 3, 'Impostos e taxas', null, 'cancelled');
  c_parcial   := pg_temp.conta('TESTE PARCIAL' || s, 44.07, v_hoje - 3, 'Impostos e taxas', null, 'partially_paid', 14.07);
  r := public.pagamentos_da_semana(v_hoje, v_ate);
  insert into _resultado values ('P5 fora da janela, paga e cancelada não entram; a paga em parte entra pelo que falta',
    pg_temp.na_fila(r, c_depois) is null and pg_temp.na_fila(r, c_paga) is null and pg_temp.na_fila(r, c_cancelada) is null
    and (pg_temp.na_fila(r, c_parcial)->>'valor')::numeric = 30.00, coalesce(pg_temp.na_fila(r, c_parcial)::text, 'sem a parcial'));

  insert into _resultado values ('P6 a mesma conta entra quando a janela alcança o vencimento dela',
    pg_temp.na_fila(public.pagamentos_da_semana(v_hoje, v_ate + 1), c_depois) is not null, '');

  -- P7: o que o sócio pagou do bolso fica fora da fila, numa conta à parte
  r2 := public.pagamentos_da_semana(v_hoje, v_ate);
  c_socio := pg_temp.conta(null, 45.07, v_hoje - 9, 'Diárias de freelancers', null, 'pending', 0, 'Reembolso ao sócio — pago do bolso para Fulano.');
  r := public.pagamentos_da_semana(v_hoje, v_ate);
  insert into _resultado values ('P7 reembolso ao sócio: fora da fila e da soma, contado em reembolsos',
    pg_temp.na_fila(r, c_socio) is null
    and (r->'reembolsos'->>'n')::int = (r2->'reembolsos'->>'n')::int + 1
    and (r->'reembolsos'->>'total')::numeric = (r2->'reembolsos'->>'total')::numeric + 45.07
    and (r->>'soma')::numeric = (r2->>'soma')::numeric, (r->'reembolsos')::text);

  -- P8: invariantes do conjunto (com as contas reais junto)
  select count(*), coalesce(sum((c->>'valor')::numeric), 0) into n, v_txt from jsonb_array_elements(r->'contas') c where (c->>'vencida')::boolean;
  insert into _resultado values ('P8 soma = a soma das contas da fila; vencido = as vencidas; hoje e ate como pedidos',
    (r->>'soma')::numeric = (select coalesce(sum((c->>'valor')::numeric), 0) from jsonb_array_elements(r->'contas') c)
    and (r->'vencido'->>'n')::int = n and (r->'vencido'->>'total')::numeric = v_txt::numeric
    and (r->>'hoje')::date = v_hoje and (r->>'ate')::date = v_ate
    and not exists (select 1 from jsonb_array_elements(r->'contas') c where (c->>'valor')::numeric <= 0),
    format('soma %s vencido %s', r->>'soma', r->'vencido'));

  insert into _resultado values ('P9 a fila está ordenada inteira (grupo, vencimento), não só as contas de teste',
    not exists (
      select 1 from jsonb_array_elements(r->'contas') with ordinality as a(c, n)
        join jsonb_array_elements(r->'contas') with ordinality as b(c, n) on b.n = a.n + 1
       where ((a.c->>'grupo')::int, (a.c->>'vencimento')::date) > ((b.c->>'grupo')::int, (b.c->>'vencimento')::date)), '');

  -- P10: sem p_ate, a janela vai até o domingo da semana
  insert into _resultado values ('P10 sem p_ate: terça vai até domingo; segunda também; no domingo é o próprio dia',
    (public.pagamentos_da_semana(date '2026-11-24')->>'ate')::date = date '2026-11-29'
    and (public.pagamentos_da_semana(date '2026-11-23')->>'ate')::date = date '2026-11-29'
    and (public.pagamentos_da_semana(date '2026-11-29')->>'ate')::date = date '2026-11-29', '');

  -- P11: o saldo é o último que cada banco ativo informou (o Caixa em dinheiro não entra)
  insert into _resultado values ('P11 saldo no banco = soma do último saldo informado por banco ativo',
    (r->>'saldo_no_banco')::numeric is not distinct from (
      select round(sum(u.saldo), 2) from public.bank_connections c
       cross join lateral (select k.saldo_do_provedor as saldo from public.bank_balance_checks k
                            where k.bank_connection_id = c.id and k.saldo_do_provedor is not null
                            order by k.conferido_em desc limit 1) u
       where c.active and c.provider <> 'caixa'), coalesce(r->>'saldo_no_banco', 'nulo'));

  -- P12–P15: o dono define o grupo de um fornecedor
  c_resto2 := pg_temp.conta('  teste resto' || s || '  ', 46.07, v_hoje + 2);  -- o mesmo nome, com caixa e espaços diferentes
  d := public.definir_prioridade_de_pagamento(c_boleto, 2);
  r := public.pagamentos_da_semana(v_hoje, v_ate);
  insert into _resultado values ('P12 definir o grupo: a conta muda de grupo e deixa de ser "a definir"',
    (d->>'ok')::boolean and (d->>'grupo')::int = 2 and (d->>'contas_em_aberto')::int = 1
    and (pg_temp.na_fila(r, c_boleto)->>'grupo')::int = 2 and not (pg_temp.na_fila(r, c_boleto)->>'a_definir')::boolean
    and pg_temp.posicao(r, c_boleto) < pg_temp.posicao(r, c_resto), d::text);

  d := public.definir_prioridade_de_pagamento(c_resto, 1);
  r := public.pagamentos_da_semana(v_hoje, v_ate);
  insert into _resultado values ('P13 vale para o fornecedor: a outra conta do mesmo nome (caixa e espaços à parte) muda junto',
    (d->>'contas_em_aberto')::int = 2
    and (pg_temp.na_fila(r, c_resto)->>'grupo')::int = 1 and (pg_temp.na_fila(r, c_resto2)->>'grupo')::int = 1
    and pg_temp.posicao(r, c_resto) < pg_temp.posicao(r, c_internet), d::text);

  perform public.definir_prioridade_de_pagamento(c_resto, 4);
  r := public.pagamentos_da_semana(v_hoje, v_ate);
  select count(*) into n from public.pagamento_prioridades where quem = public._quem_da_conta(null, 'TESTE RESTO' || s);
  insert into _resultado values ('P14 definir de novo troca o grupo, sem linha em dobro',
    n = 1 and (pg_temp.na_fila(r, c_resto)->>'grupo')::int = 4, n::text);

  c_sem_nome := pg_temp.conta(null, 47.07, v_hoje + 1);
  v_txt := '';
  begin perform public.definir_prioridade_de_pagamento(c_resto, 5); v_txt := v_txt || 'aceitou grupo 5; '; exception when others then null; end;
  begin perform public.definir_prioridade_de_pagamento(c_resto, null); v_txt := v_txt || 'aceitou grupo nulo; '; exception when others then null; end;
  begin perform public.definir_prioridade_de_pagamento(gen_random_uuid(), 2); v_txt := v_txt || 'aceitou conta que não existe; '; exception when others then null; end;
  begin perform public.definir_prioridade_de_pagamento(c_sem_nome, 2); v_txt := v_txt || 'aceitou conta sem quem cobra; '; exception when others then null; end;
  insert into _resultado values ('P15 recusa grupo fora de 1–4, conta que não existe e conta sem quem cobra', v_txt = '', v_txt);

  insert into _resultado values ('P16 a chave de quem cobra: o cadastro vence o nome; nome sem caixa nem espaços; vazio = nulo',
    public._quem_da_conta('00000000-0000-0000-0000-000000000001', 'Qualquer') = '00000000-0000-0000-0000-000000000001'
    and public._quem_da_conta(null, '  Unifique ') = 'unifique'
    and public._quem_da_conta(null, '   ') is null and public._quem_da_conta(null, null) is null, '');
end $$;

insert into _resultado
select 'P17 anon e authenticated não executam as funções nem leem a tabela',
       not has_function_privilege('anon', 'public.pagamentos_da_semana(date, date)', 'execute')
   and not has_function_privilege('authenticated', 'public.pagamentos_da_semana(date, date)', 'execute')
   and not has_function_privilege('anon', 'public.definir_prioridade_de_pagamento(uuid, int, uuid)', 'execute')
   and not has_function_privilege('authenticated', 'public.definir_prioridade_de_pagamento(uuid, int, uuid)', 'execute')
   and not has_function_privilege('anon', 'public._quem_da_conta(uuid, text)', 'execute')
   and not has_function_privilege('authenticated', 'public._quem_da_conta(uuid, text)', 'execute')
   and not has_table_privilege('anon', 'public.pagamento_prioridades', 'select')
   and not has_table_privilege('authenticated', 'public.pagamento_prioridades', 'select')
   and not has_table_privilege('authenticated', 'public.pagamento_prioridades', 'insert'), ''
union all
select 'P18 service_role executa e grava; a tabela tem RLS ligada',
       has_function_privilege('service_role', 'public.pagamentos_da_semana(date, date)', 'execute')
   and has_function_privilege('service_role', 'public.definir_prioridade_de_pagamento(uuid, int, uuid)', 'execute')
   and has_table_privilege('service_role', 'public.pagamento_prioridades', 'insert')
   and (select relrowsecurity from pg_class where oid = 'public.pagamento_prioridades'::regclass), '';

select teste, ok, detalhe from _resultado order by (substring(teste from 'P(\d+)'))::int, teste;

rollback;
