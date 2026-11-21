-- Prova da Fase 1 do "Fechar juntas" (migration 20270220100000_fechar_juntas_fatura): a Fatura FAT-N, o
-- recebimento dela e as travas no banco. 20/11/2026.
--
--   A1  criar: 2 OS executadas do mesmo cliente viram a FAT-N (total = soma dos saldos, contas nas OS, view certa)
--   A2  criar de novo com as mesmas contas: devolve a mesma fatura (não cria outra)
--   A3  recusas: cadastro genérico, OS não executada (aguardando o cliente), OS cancelada, orçamento, conta de outro
--       titular, uma OS só, conta já em outra fatura — nenhuma fatura criada
--   B1  travas: cada caminho de escrita por fora recusa (55000) — alterar valor, cancelar, apagar, tirar da fatura,
--       pôr conta nova na fatura, baixa manual (register_payment), "Este Pix paga" direto, estornar pagamento antigo,
--       cancelar a OS, reabrir (cancelar pagamento), cobrança: dar baixa / cancelar / mudar valor / apagar
--   B2  o que continua livre: observação e lembrete da conta; envio da cobrança (sent + last_auto_sent_at)
--   C1  receber Pix parcial: a conta que vence primeiro recebe primeiro; a fatura continua aberta com o saldo
--   C2  receber Pix que fecha a fatura com R$ 5 a mais: os R$ 5 viram receita da última conta; fatura quitada
--   C3  fatura quitada não recebe de novo
--   C4  sobra: Pix R$ 50 a mais (10–100) e R$ 150 a mais (>100) recusados com a frase de cada faixa; dinheiro a mais
--       recusado (troco); nada gravado
--   C5  dinheiro: recebimento parcial em espécie (payment_method cash)
--   D1  desfazer a fatura com dinheiro recebido: recusado
--   D2  desfazer o recebimento em dinheiro (estornar_pagamento) e depois a fatura: contas e cobranças soltas, a trava
--       solta, a fatura fica como desfeita
--   D3  desfazer um recebimento do Pix (desfazer_aplicacao): a fatura quitada volta a aberta
--   D4  cobrar de novo só com a conta que ainda tem saldo: é a mesma fatura (não cria outra)
--   E1  cargos: técnico e vendedor externo recusados (42501) em criar/receber/desfazer; financeiro passa
--   E2  anon: sem execute nas 4 funções; sem leitura da view; ninguém grava direto em invoices
--   F1  Cobrar juntas pelo assistente (registrar envio sem fatura): cria a fatura e a cobrança nasce apontando para ela
--   F2  Cobrar juntas com uma OS em execução: sai sem fatura, como antes
--   F3  Enviar extrato (p_os nulo): não cria fatura
--   F4  tela: fatura criada antes do envio; o registro reaproveita a mesma e liga a cobrança que já existia
--
-- ═══ COMO RODAR ═══ (DEPOIS da migration aplicada; a partir do repositório principal, que é o linkado)
--
--   npx supabase@2.111.0 db query --linked -f supabase/tests/fechar_juntas_fatura.sql --output json
--
-- Ensaio ANTES de aplicar: um arquivo "begin; <a migration> <este corpo sem o begin> rollback;".
-- Seguro em produção: usuários, clientes, barcos, OS, contas e linhas de banco de TESTE criados aqui; nada é enviado.
-- ROLLBACK no fim (a sequência fatura_seq anda — sequência não volta no rollback; só números de teste se perdem).
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop')
$$;

create function pg_temp._usuario(p_role text) returns uuid language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste fatura (' || p_role || ')', 'teste-fatura-' || v_id || '@teste.invalido', p_role, true);
  return v_id;
end $$;

create function pg_temp._cliente(p_generico boolean default false) returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.clients (type, name, generico, phone, whatsapp)
  values ('individual', 'Cliente Teste Fatura ' || pg_temp._letras(6), p_generico, '(48) 3333-0000', '(48) 99999-0000')
  returning id into v_id;
  return v_id;
end $$;

create function pg_temp._numero_livre(p_prefixo text default 'OS-') returns text language plpgsql as $$
declare
  v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders where service_order_number = p_prefixo || v_num) loop
    v_num := v_num + 1;
  end loop;
  return p_prefixo || v_num;
end $$;

create function pg_temp._os(p_cli uuid, p_status text default 'invoiced', p_prefixo text default 'OS-') returns uuid
language plpgsql as $$
declare
  v_ves uuid;
  v_os uuid;
begin
  insert into public.vessels (client_id, name) values (p_cli, 'Barco' || pg_temp._letras(8)) returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, converted_to_os_at, created_at)
  values (pg_temp._numero_livre(p_prefixo), p_cli, v_ves, p_status, 'approved', now(), clock_timestamp())
  returning id into v_os;
  return v_os;
end $$;

-- Conta com vencimento em current_date + p_dias (mês aberto); p_pago entra como pagamento de ONTEM (antes da fatura).
create function pg_temp._conta(p_cli uuid, p_os uuid, p_valor numeric, p_dias integer, p_pago numeric default 0)
returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, paid_amount,
                                  balance_amount, status)
  values (p_cli, p_os, 'Teste fatura: conta ' || pg_temp._letras(4), current_date, current_date + p_dias, p_valor, p_pago,
          p_valor - p_pago, case when p_pago >= p_valor then 'paid' when p_pago > 0 then 'partially_paid' else 'pending' end)
  returning id into v_id;
  if p_pago > 0 then
    insert into public.payments (receivable_id, amount, payment_date, payment_method, installments, card_fee_percent,
                                 net_amount, notes, status, created_at)
    values (v_id, p_pago, current_date - 1, 'cash', 1, 0, p_pago, 'Teste fatura: pago antes', 'confirmed', now() - interval '1 day');
  end if;
  return v_id;
end $$;

create function pg_temp._pix(p_valor numeric) returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, bank_connection_id, reconciled)
  values (current_date, 'TESTE fatura Pix recebido', p_valor, 'credit',
          (select id from public.bank_connections where provider <> 'caixa' order by created_at limit 1), false)
  returning id into v_id;
  return v_id;
end $$;

-- O sqlstate + a mensagem do erro, ou null se rodou.
create function pg_temp._erro_sql(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

-- Uma consulta como um papel (e um login): o texto que volta ou "erro <sqlstate>: <mensagem>".
create function pg_temp._como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- ═══ A, B, C, D (um cliente, duas faturas) ══════════════════════════════════════════════════
do $$
declare
  v_fin uuid := pg_temp._usuario('financial');
  v_cli uuid := pg_temp._cliente();
  v_gen uuid := pg_temp._cliente(true);
  v_outro uuid := pg_temp._cliente();
  a uuid; b uuid; c uuid; d uuid; e uuid; o_exec uuid; o_canc uuid; o_orc uuid; o_gen1 uuid; o_gen2 uuid;
  ca uuid; cb uuid; cc uuid; cd uuid; ce uuid; c_exec uuid; c_canc uuid; c_orc uuid; c_out uuid; g1 uuid; g2 uuid;
  k uuid;
  f1 uuid; f2 uuid;
  r jsonb; r2 jsonb;
  v text; v2 text; v3 text; v4 text; v5 text; v6 text; v7 text; v8 text; v9 text; v10 text; v11 text; v12 text;
  v_pix uuid;
  v_pag uuid;
  v_qtd integer;
  x record;
begin
  a := pg_temp._os(v_cli, 'invoiced');
  b := pg_temp._os(v_cli, 'completed');
  ca := pg_temp._conta(v_cli, a, 1650, 1);          -- a primeira a vencer
  cb := pg_temp._conta(v_cli, b, 520, 2, 500);      -- saldo R$ 20 (R$ 500 pagos ontem)
  insert into public.collections (service_order_id, receivable_id, client_id, amount, due_date, status, description)
  values (a, ca, v_cli, 1650, current_date + 1, 'pending', 'Teste fatura: cobrança da conta') returning id into k;

  -- A1
  r := public.fatura_criar(v_cli, array[cb, ca], v_fin);
  f1 := (r ->> 'fatura_id')::uuid;
  select * into x from public.faturas_resumo where id = f1;
  insert into _resultado values ('A1 criar: 2 OS executadas viram a FAT-N, total = soma dos saldos, cobrança aberta aponta',
    (r ->> 'criada')::boolean and (r ->> 'numero') ~ '^FAT-[0-9]{5}$' and (r ->> 'total')::numeric = 1670
    and (select count(*) from public.receivables where invoice_id = f1) = 2
    and (select service_order_id from public.receivables where id = ca) = a
    and (select service_order_id from public.receivables where id = cb) = b
    and (select status from public.invoices where id = f1) = 'open'
    and (select invoice_id from public.collections where id = k) = f1
    and x.saldo = 1670 and x.recebido = 0 and x.contas = 2 and x.total = 1670 and cardinality(x.os) = 2
    and (select due_date from public.invoices where id = f1) = current_date + 1,
    r::text || ' | ' || row_to_json(x)::text);

  -- A2
  r2 := public.fatura_criar(v_cli, array[ca, cb, ca], v_fin);
  insert into _resultado values ('A2 mesmas contas: devolve a mesma fatura, sem criar outra',
    not (r2 ->> 'criada')::boolean and (r2 ->> 'fatura_id')::uuid = f1
    and (select count(*) from public.invoices where client_id = v_cli) = 1,
    r2::text);

  -- A3
  c := pg_temp._os(v_cli, 'invoiced');
  cc := pg_temp._conta(v_cli, c, 300, 3);
  o_exec := pg_temp._os(v_cli, 'awaiting_client');
  c_exec := pg_temp._conta(v_cli, o_exec, 396, 3);
  o_canc := pg_temp._os(v_cli, 'cancelled');
  c_canc := pg_temp._conta(v_cli, o_canc, 100, 3);
  o_orc := pg_temp._os(v_cli, 'completed', 'ORÇ-');
  c_orc := pg_temp._conta(v_cli, o_orc, 100, 3);
  c_out := pg_temp._conta(v_outro, c, 80, 3);
  o_gen1 := pg_temp._os(v_gen, 'invoiced');
  o_gen2 := pg_temp._os(v_gen, 'invoiced');
  g1 := pg_temp._conta(v_gen, o_gen1, 100, 3);
  g2 := pg_temp._conta(v_gen, o_gen2, 100, 3);
  v := pg_temp._erro_sql(format('select public.fatura_criar(%L, array[%L, %L]::uuid[], %L)', v_gen, g1, g2, v_fin));
  v2 := pg_temp._erro_sql(format('select public.fatura_criar(%L, array[%L, %L]::uuid[], %L)', v_cli, cc, c_exec, v_fin));
  v3 := pg_temp._erro_sql(format('select public.fatura_criar(%L, array[%L, %L]::uuid[], %L)', v_cli, cc, c_canc, v_fin));
  v4 := pg_temp._erro_sql(format('select public.fatura_criar(%L, array[%L, %L]::uuid[], %L)', v_cli, cc, c_orc, v_fin));
  v5 := pg_temp._erro_sql(format('select public.fatura_criar(%L, array[%L, %L]::uuid[], %L)', v_cli, cc, c_out, v_fin));
  d := pg_temp._os(v_cli, 'invoiced');
  cd := pg_temp._conta(v_cli, d, 200, 4);
  ce := pg_temp._conta(v_cli, d, 50, 5);
  v6 := pg_temp._erro_sql(format('select public.fatura_criar(%L, array[%L, %L]::uuid[], %L)', v_cli, cd, ce, v_fin));
  v7 := pg_temp._erro_sql(format('select public.fatura_criar(%L, array[%L, %L]::uuid[], %L)', v_cli, ca, cc, v_fin));
  insert into _resultado values ('A3 recusas: genérico, OS não executada, cancelada, orçamento, outro titular, 1 OS só, conta já em fatura',
    v like '22023 O cadastro % é genérico%' and v2 like '22023 Só OS já executada%aguardando o cliente%'
    and v3 like '22023 Só OS já executada%cancelada%' and v4 like '22023 Só OS já executada%é orçamento%'
    and v5 like '22023 Estas contas não são de %' and v6 like '22023 Uma fatura junta contas de 2 OS ou mais%'
    and v7 like '22023 Estas contas já estão numa fatura%FAT-%'
    and (select count(*) from public.invoices where client_id in (v_cli, v_gen)) = 1,
    concat_ws(' | ', v, v2, v3, v4, v5, v6, v7));

  -- B1 travas: cada caminho de escrita por fora
  select p.id into v_pag from public.payments p where p.receivable_id = cb;
  v := pg_temp._erro_sql(format('update public.receivables set amount = 1 where id = %L', ca));
  v2 := pg_temp._erro_sql(format($q$update public.receivables set status = 'cancelled' where id = %L$q$, ca));
  v3 := pg_temp._erro_sql(format('delete from public.receivables where id = %L', ca));
  v4 := pg_temp._erro_sql(format('update public.receivables set invoice_id = null where id = %L', ca));
  v5 := pg_temp._erro_sql(format($q$insert into public.receivables (client_id, service_order_id, description, issue_date, due_date,
          amount, paid_amount, balance_amount, status, invoice_id) values (%L, %L, 'Teste fatura: intrusa', current_date,
          current_date, 10, 0, 10, 'pending', %L)$q$, v_cli, c, f1));
  v6 := pg_temp._erro_sql(format($q$select public.register_payment_and_update_balance(%L, null, 100, current_date, 'pix', 1, 0, 100, 'baixa manual', %L)$q$, ca, v_fin));
  v_pix := pg_temp._pix(100);
  v7 := pg_temp._erro_sql(format($q$select public.aplicar_entrada_em_contas(%L, jsonb_build_array(jsonb_build_object('receivable_id', %L::uuid, 'valor', 100)), null, %L)$q$, v_pix, ca, v_fin));
  v8 := pg_temp._erro_sql(format($q$select public.estornar_pagamento(%L, 'estorno por fora', %L)$q$, v_pag, v_fin));
  v9 := pg_temp._erro_sql(format($q$select public.cancel_service_order_cascade(%L, 'teste cancelar')$q$, a));
  v10 := pg_temp._erro_sql(format($q$update public.payments set status = 'cancelled', cancelled_at = now() where id = %L$q$, v_pag));
  v11 := pg_temp._erro_sql(format($q$update public.collections set status = 'paid', paid_at = now() where id = %L$q$, k));
  v12 := concat_ws(' / ',
           pg_temp._erro_sql(format($q$update public.collections set status = 'cancelled' where id = %L$q$, k)),
           pg_temp._erro_sql(format('update public.collections set amount = 1 where id = %L', k)),
           pg_temp._erro_sql(format('delete from public.collections where id = %L', k)));
  insert into _resultado values ('B1 travas: alterar, cancelar, apagar, tirar/pôr na fatura, baixa manual, Este Pix paga, estorno, cancelar OS, reabrir, cobrança',
    v like '55000 A conta % está na fatura FAT-%' and v2 like '55000 %' and v3 like '55000 % não pode ser apagada%'
    and v4 like '55000 % só entra ou sai da fatura%' and v5 like '55000 Uma conta só entra numa fatura%'
    and v6 like '55000 % está na fatura FAT-%receber e estornar é pela fatura%' and v7 like '55000 %fatura%'
    and v8 like '55000 %' and v9 like '55000 %' and v10 like '55000 %' and v11 like '55000 Esta cobrança é da fatura%'
    and v12 like '55000 %/ 55000 %/ 55000 %não pode ser apagada%'
    and (select amount from public.receivables where id = ca) = 1650
    and (select status from public.service_orders where id = a) = 'invoiced'
    and (select status from public.payments where id = v_pag) = 'confirmed'
    and not exists (select 1 from public.payments where bank_transaction_id = v_pix),
    concat_ws(' | ', v, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12));

  -- B2 o que continua livre
  v := pg_temp._erro_sql(format($q$update public.receivables set notes = 'anotado', reminder_sent_at = now() where id = %L$q$, ca));
  v2 := pg_temp._erro_sql(format($q$update public.collections set status = 'sent', last_auto_sent_at = now() where id = %L$q$, k));
  insert into _resultado values ('B2 livre: observação e lembrete da conta; envio da cobrança',
    v is null and v2 is null and (select status from public.collections where id = k) = 'sent',
    concat_ws(' | ', v, v2));

  -- C1 Pix parcial: R$ 1.000 → a conta da OS A (vence primeiro) recebe tudo
  v_pix := pg_temp._pix(1000);
  r := public.fatura_receber(f1, v_pix, null, null, null, v_fin);
  select * into x from public.faturas_resumo where id = f1;
  insert into _resultado values ('C1 Pix parcial: quem vence primeiro recebe primeiro; fatura aberta com o saldo',
    (r ->> 'recebido')::numeric = 1000 and (r ->> 'saldo')::numeric = 670 and not (r ->> 'quitada')::boolean
    and (select paid_amount from public.receivables where id = ca) = 1000
    and (select status from public.receivables where id = ca) = 'partially_paid'
    and (select paid_amount from public.receivables where id = cb) = 500
    and (select count(*) from public.payments where bank_transaction_id = v_pix and status = 'confirmed' and payment_method = 'pix') = 1
    and x.recebido = 1000 and x.saldo = 670 and x.status = 'open',
    r::text || ' | ' || row_to_json(x)::text);

  -- C2 Pix R$ 675 fecha a fatura (saldo 670): A recebe 650, B recebe 20 + R$ 5 de receita
  v_pix := pg_temp._pix(675);
  r := public.fatura_receber(f1, v_pix, null, null, 'Pix do cliente', v_fin);
  select * into x from public.faturas_resumo where id = f1;
  insert into _resultado values ('C2 Pix com R$ 5 a mais: receita na última conta; fatura quitada; cobrança da conta paga',
    (r ->> 'quitada')::boolean and (r ->> 'saldo')::numeric = 0
    and (select status from public.receivables where id = ca) = 'paid'
    and (select amount from public.receivables where id = cb) = 525
    and (select status from public.receivables where id = cb) = 'paid'
    and (select status from public.invoices where id = f1) = 'paid'
    and (select status from public.collections where id = k) = 'paid'
    and x.recebido = 1675 and x.saldo = 0,
    r::text || ' | ' || row_to_json(x)::text);

  -- C3
  v_pix := pg_temp._pix(10);
  v := pg_temp._erro_sql(format('select public.fatura_receber(%L, %L, null, null, null, %L)', f1, v_pix, v_fin));
  insert into _resultado values ('C3 fatura quitada não recebe de novo', v like '22023 A fatura % já está quitada%', v);

  -- C4 sobras (fatura 2: OS C R$ 300 + OS D R$ 250)
  r := public.fatura_criar(v_cli, array[cc, cd, ce], v_fin);
  f2 := (r ->> 'fatura_id')::uuid;
  v := pg_temp._erro_sql(format('select public.fatura_receber(%L, %L, null, null, null, %L)', f2, pg_temp._pix(600), v_fin));
  v2 := pg_temp._erro_sql(format('select public.fatura_receber(%L, %L, null, null, null, %L)', f2, pg_temp._pix(700), v_fin));
  v3 := pg_temp._erro_sql(format('select public.fatura_receber(%L, null, 551, null, null, %L)', f2, v_fin));
  v4 := pg_temp._erro_sql(format('select public.fatura_receber(%L, null, null, null, null, %L)', f2, v_fin));
  insert into _resultado values ('C4 sobra: R$ 50 a mais (é do dono) e R$ 150 (avaliar) recusados; dinheiro a mais recusado',
    (r ->> 'total')::numeric = 550
    and v like '22023 %Entre R$ 10 e R$ 100 a mais é decisão do dono%' and v2 like '22023 %Acima de R$ 100%avaliar%'
    and v3 like '22023 %o resto é troco%' and v4 like '22023 Diga de onde veio o dinheiro%'
    and public._fatura_saldo(f2) = 550 and public._fatura_recebido(f2) = 0,
    concat_ws(' | ', r::text, v, v2, v3, v4));

  -- C5 dinheiro: R$ 350 → C (vence +3) recebe 300, a 1ª de D (vence +4) recebe 50
  r := public.fatura_receber(f2, null, 350, null, null, v_fin);
  insert into _resultado values ('C5 dinheiro: parcial em espécie, pela ordem do vencimento',
    (r ->> 'saldo')::numeric = 200 and (select status from public.receivables where id = cc) = 'paid'
    and (select paid_amount from public.receivables where id = cd) = 50
    and (select paid_amount from public.receivables where id = ce) = 0
    and (select count(*) from public.payments where receivable_id in (cc, cd) and payment_method = 'cash' and status = 'confirmed') = 2,
    r::text);

  -- D1
  v := pg_temp._erro_sql(format('select public.fatura_desfazer(%L, null, %L)', f2, v_fin));
  insert into _resultado values ('D1 desfazer com dinheiro recebido: recusado', v like '22023 Já entrou R$ 350,00 pela fatura%', v);

  -- D2 desfazer os recebimentos em dinheiro, depois a fatura
  for v_pag in select p.id from public.payments p where p.receivable_id in (cc, cd) and p.status = 'confirmed' loop
    perform public.fatura_desfazer_recebimento(v_pag, 'Teste: lançado errado', v_fin);
  end loop;
  r := public.fatura_desfazer(f2, 'Teste: desfazer', v_fin);
  v := pg_temp._erro_sql(format('update public.receivables set amount = 301 where id = %L', cc));
  insert into _resultado values ('D2 desfazer recebimento (estorno) e a fatura: contas soltas, trava solta, fatura desfeita',
    (select status from public.invoices where id = f2) = 'cancelled'
    and not exists (select 1 from public.receivables where invoice_id = f2)
    and not exists (select 1 from public.collections where invoice_id = f2)
    and (select paid_amount from public.receivables where id = cc) = 0
    and v is null and (r ->> 'contas')::int = 3,
    concat_ws(' | ', r::text, v));

  -- D3 desfazer um recebimento do Pix na fatura quitada (o de R$ 675)
  select p.id into v_pag from public.payments p join public.bank_transactions t on t.id = p.bank_transaction_id
   where p.receivable_id = cb and p.status = 'confirmed' and t.amount = 675;
  r := public.fatura_desfazer_recebimento(v_pag, 'Teste: Pix errado', v_fin);
  insert into _resultado values ('D3 desfazer recebimento do Pix (desfazer_aplicacao): a fatura volta a aberta',
    (select status from public.invoices where id = f1) = 'open' and (r ->> 'saldo')::numeric = 20
    and (select amount from public.receivables where id = cb) = 520
    and (select status from public.payments where id = v_pag) = 'cancelled',
    r::text);

  -- D4 cobrar de novo depois do parcial: só a conta que ainda tem saldo (a da OS B) → é a mesma fatura
  r := public.fatura_criar(v_cli, array[cb], v_fin);
  insert into _resultado values ('D4 de novo só com a conta que ainda tem saldo: devolve a mesma fatura',
    not (r ->> 'criada')::boolean and (r ->> 'fatura_id')::uuid = f1 and (r ->> 'saldo')::numeric = 20,
    r::text);
exception when others then
  insert into _resultado values ('A–D', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ E cargos e anon ════════════════════════════════════════════════════════════════════════
do $$
declare
  v_fin uuid := pg_temp._usuario('financial');
  v_adm uuid := pg_temp._usuario('admin');
  v_tec uuid := pg_temp._usuario('technician');
  v_ven uuid := pg_temp._usuario('external_seller');
  v_cli uuid := pg_temp._cliente();
  a uuid := pg_temp._os(v_cli, 'invoiced');
  b uuid := pg_temp._os(v_cli, 'invoiced');
  ca uuid; cb uuid; f uuid;
  r jsonb;
  v text; v2 text; v3 text; v4 text; v5 text; v6 text; v7 text; v8 text;
begin
  ca := pg_temp._conta(v_cli, a, 100, 1);
  cb := pg_temp._conta(v_cli, b, 200, 2);
  v := pg_temp._erro_sql(format('select public.fatura_criar(%L, array[%L, %L]::uuid[], %L)', v_cli, ca, cb, v_tec));
  v2 := pg_temp._erro_sql(format('select public.fatura_criar(%L, array[%L, %L]::uuid[], %L)', v_cli, ca, cb, v_ven));
  v3 := pg_temp._como(v_tec, 'authenticated', format('select public.fatura_criar(%L, array[%L, %L]::uuid[])::text', v_cli, ca, cb));
  v4 := pg_temp._erro_sql(format('select public.fatura_criar(%L, array[%L, %L]::uuid[], null)', v_cli, ca, cb));
  r := (pg_temp._como(v_fin, 'authenticated', format('select public.fatura_criar(%L, array[%L, %L]::uuid[])::text', v_cli, ca, cb)))::jsonb;
  f := (r ->> 'fatura_id')::uuid;
  v5 := pg_temp._erro_sql(format('select public.fatura_receber(%L, null, 10, null, null, %L)', f, v_tec));
  v6 := pg_temp._erro_sql(format('select public.fatura_desfazer(%L, null, %L)', f, v_ven));
  v7 := pg_temp._como(v_adm, 'authenticated', format($q$select (public.fatura_receber(%L, null, 10, null, null) ->> 'saldo')$q$, f));
  insert into _resultado values ('E1 cargos: técnico e vendedor externo recusados (42501); financeiro e administrador passam',
    v like '42501 Só administrador ou financeiro%' and v2 like '42501 %' and v3 like 'erro 42501: %'
    and v4 like '42501 Faça login%' and v5 like '42501 %' and v6 like '42501 %'
    and f is not null and v7 = '290.00',
    concat_ws(' | ', v, v2, v3, v4, r::text, v5, v6, v7));

  -- E2 anon e escrita direta
  v := pg_temp._como(null, 'anon', 'select count(*)::text from public.faturas_resumo');
  v2 := pg_temp._como(null, 'anon', format('select public.fatura_criar(%L, array[%L]::uuid[])::text', v_cli, ca));
  v3 := pg_temp._como(v_fin, 'authenticated',
          format($q$insert into public.invoices (invoice_number, client_id, issue_date, due_date) values ('FAT-TESTE', %L, current_date, current_date) returning 'criou'$q$, v_cli));
  v4 := pg_temp._como(v_fin, 'authenticated', format($q$update public.invoices set total_amount = 1 where id = %L returning 'mudou'$q$, f));
  v5 := pg_temp._como(v_fin, 'authenticated', format('select saldo::text from public.faturas_resumo where id = %L', f));
  v6 := pg_temp._como(v_tec, 'authenticated', format('select count(*)::text from public.faturas_resumo where id = %L', f));
  insert into _resultado values ('E2 anon sem execute nem leitura; ninguém grava direto em invoices; técnico não vê a fatura',
    v like 'erro 42501:%' and v2 like 'erro 42501:%' and v3 like 'erro 42501:%' and v4 like 'erro 42501:%'
    and v5 = '290.00' and v6 = '0'
    and not has_function_privilege('anon', 'public.fatura_criar(uuid, uuid[], uuid)', 'execute')
    and not has_function_privilege('anon', 'public.fatura_desfazer(uuid, text, uuid)', 'execute')
    and not has_function_privilege('anon', 'public.fatura_receber(uuid, uuid, numeric, date, text, uuid)', 'execute')
    and not has_function_privilege('anon', 'public.fatura_desfazer_recebimento(uuid, text, uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public._fatura_impedimento(uuid, uuid[])', 'execute'),
    concat_ws(' | ', v, v2, v3, v4, v5, v6));
exception when others then
  insert into _resultado values ('E', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ F Cobrar juntas usa a fatura ═══════════════════════════════════════════════════════════
do $$
declare
  v_fin uuid := pg_temp._usuario('financial');
  v_cli uuid := pg_temp._cliente();
  v_cli2 uuid := pg_temp._cliente();
  v_cli3 uuid := pg_temp._cliente();
  v_cli4 uuid := pg_temp._cliente();
  a uuid; b uuid; c uuid; d uuid; e uuid; g uuid; h uuid; i uuid;
  ca uuid; cb uuid; cc uuid; cd uuid; ce uuid; cg uuid; ch uuid; ci uuid;
  k uuid;
  r jsonb; rf jsonb;
  v_fat uuid;
begin
  -- F1 assistente: registra o envio de 2 OS executadas sem fatura → a fatura nasce aqui
  a := pg_temp._os(v_cli, 'invoiced');  b := pg_temp._os(v_cli, 'completed');
  ca := pg_temp._conta(v_cli, a, 1650, 1);  cb := pg_temp._conta(v_cli, b, 20, 2);
  r := public.cobrar_juntas_registrar_envio(v_cli, array[ca, cb], array[a, b], null, v_fin);
  select f.id into v_fat from public.invoices f where f.client_id = v_cli;
  insert into _resultado values ('F1 Cobrar juntas (assistente): cria a fatura e as cobranças nascem apontando para ela',
    v_fat is not null and jsonb_array_length(r -> 'faturas') = 1 and (r ->> 'criadas')::int = 2
    and (select count(*) from public.collections where receivable_id in (ca, cb) and invoice_id = v_fat and status = 'sent') = 2
    and (select count(*) from public.receivables where invoice_id = v_fat) = 2,
    r::text);

  -- F2 com uma OS em execução: sai sem fatura, como antes
  c := pg_temp._os(v_cli2, 'invoiced');  d := pg_temp._os(v_cli2, 'in_progress');
  cc := pg_temp._conta(v_cli2, c, 300, 1);  cd := pg_temp._conta(v_cli2, d, 400, 2);
  r := public.cobrar_juntas_registrar_envio(v_cli2, array[cc, cd], array[c, d], null, v_fin);
  insert into _resultado values ('F2 Cobrar juntas com OS em execução: sem fatura, cobranças registradas como antes',
    not exists (select 1 from public.invoices where client_id = v_cli2) and (r ->> 'registradas')::int = 2
    and jsonb_array_length(r -> 'faturas') = 0
    and not exists (select 1 from public.collections where receivable_id in (cc, cd) and invoice_id is not null),
    r::text);

  -- F3 Enviar extrato (p_os nulo): não cria fatura
  e := pg_temp._os(v_cli3, 'invoiced');  g := pg_temp._os(v_cli3, 'invoiced');
  ce := pg_temp._conta(v_cli3, e, 100, 1);  cg := pg_temp._conta(v_cli3, g, 100, 2);
  r := public.cobrar_juntas_registrar_envio(v_cli3, array[ce, cg], null, null, v_fin);
  insert into _resultado values ('F3 Enviar extrato: não cria fatura',
    not exists (select 1 from public.invoices where client_id = v_cli3) and (r ->> 'registradas')::int = 2,
    r::text);

  -- F4 tela: a fatura nasce antes do envio; o registro usa a mesma e liga a cobrança que já existia
  h := pg_temp._os(v_cli4, 'invoiced');  i := pg_temp._os(v_cli4, 'completed');
  ch := pg_temp._conta(v_cli4, h, 500, 1);  ci := pg_temp._conta(v_cli4, i, 250, 2);
  rf := public.fatura_criar(v_cli4, array[ch, ci], v_fin);
  insert into public.collections (service_order_id, receivable_id, client_id, amount, due_date, status, description)
  values (h, ch, v_cli4, 500, current_date + 1, 'pending', 'Teste fatura: cobrança antiga') returning id into k;
  r := public.cobrar_juntas_registrar_envio(v_cli4, array[ch, ci], array[h, i], null, v_fin);
  insert into _resultado values ('F4 tela: registro reaproveita a fatura criada antes do envio e liga a cobrança antiga',
    (select count(*) from public.invoices where client_id = v_cli4) = 1
    and (r -> 'faturas' ->> 0) = (rf ->> 'numero') and (r ->> 'criadas')::int = 1
    and (select invoice_id from public.collections where id = k) = (rf ->> 'fatura_id')::uuid
    and (select status from public.collections where id = k) = 'sent'
    and (select count(*) from public.collections where receivable_id = ci and invoice_id = (rf ->> 'fatura_id')::uuid) = 1,
    r::text || ' | ' || rf::text);
exception when others then
  insert into _resultado values ('F', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
