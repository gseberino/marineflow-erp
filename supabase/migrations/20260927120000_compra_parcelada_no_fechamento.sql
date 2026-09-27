-- Compra parcelada no fechamento (27/09/2026, pendência 1 da lista do dono: "pode fazer o que
-- você precisa fazer").
--
-- O "Mês pronto?" acusava 62 lançamentos "com valor diferente do extrato" e agosto não fechava.
-- 58 eram compra parcelada no cartão: o lançamento é a COMPRA inteira e a linha do banco ligada a
-- ele é UMA parcela (R$ 457,36 da Instaladora Berlim contra a parcela 1/4 de R$ 114,34). Isso não
-- é erro — é o jeito certo de lançar compra parcelada (o motor faz assim desde 25/09).
--
-- Mas a mesma conferência achou o erro de verdade: compras lançadas uma vez POR PARCELA, cada vez
-- com o valor inteiro (Amazon 4 × R$ 602, Vila Verde 4 × R$ 1.652, Aliexpress 3 × R$ 466…),
-- criadas em lote em 29/07 e 05/08, antes da regra "a mesma compra não nasce duas vezes". Isso
-- conta a mesma despesa duas, três, quatro vezes. O item "Nenhuma despesa lançada em dobro"
-- passa a enxergá-las; a correção dos lançamentos antigos é à parte e só com o OK do dono.
--
-- Nada aqui apaga ou muda dado: uma função de apoio, uma visão nova, uma coluna nova no fim da
-- visão de conciliação e o "Mês pronto?" com os itens 3 e 4 ajustados.

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 1. A loja de uma parcela, do jeito que o motor agrupa (_shared/banking/installments.ts:
--    nomeSemParcela): quem recebeu — ou a descrição —, sem o "k/N" que alguns bancos põem no
--    nome ("Amazon Marketplace 2/4"), com os espaços juntados.
-- ───────────────────────────────────────────────────────────────────────────────────────────
create or replace function public._loja_da_parcela(p_quem text, p_descricao text)
returns text
language sql
immutable
set search_path = public
as $$
  select upper(translate(btrim(regexp_replace(
           regexp_replace(coalesce(nullif(btrim(p_quem), ''), p_descricao, ''), '\s*\d{1,2}\s*/\s*\d{1,2}\s*$', ''),
           '\s+', ' ', 'g')),
         'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'));
$$;

revoke all on function public._loja_da_parcela(text, text) from public, anon;
grant execute on function public._loja_da_parcela(text, text) to authenticated, service_role;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 2. Compras parceladas lançadas mais de uma vez.
--
--    A compra é: mesma conta (cartão), mesma loja, mesmo número de parcelas e o valor da parcela
--    igual com até 1 centavo por parcela de diferença (o cartão joga na primeira os centavos que
--    não dividem: Vila Verde, 275,35 na 1/6 e 275,32 nas outras). Só entra compra que tem ao menos UM lançamento com o valor inteiro (parcela × vezes):
--    lançar parcela por parcela, cada uma com o valor dela, soma certo e não é duplicata. Fica
--    o lançamento inteiro da parcela mais antiga; os outros da mesma compra repetem despesa.
--    Número de parcela repetido dentro da compra é ambíguo (podem ser duas compras iguais) e
--    fica de fora — como no motor, errar juntando compras diferentes é pior.
-- ───────────────────────────────────────────────────────────────────────────────────────────
create or replace view public.compras_parceladas_em_dobro with (security_invoker = on) as
with parcelas as (
  select p.id as payable_id, p.amount as lancado, p.issue_date, p.description,
         bt.bank_connection_id, bt.amount as parcela, bt.transaction_date,
         case when bt.installment_label ~ '^\d{1,2}/\d{1,2}$' then split_part(bt.installment_label, '/', 1)::int end as k,
         case when bt.installment_label ~ '^\d{1,2}/\d{1,2}$' then split_part(bt.installment_label, '/', 2)::int end as n,
         public._loja_da_parcela(bt.counterparty_name, bt.description) as loja
    from public.payables p
    join public.bank_transactions bt on bt.id = p.bank_transaction_id
   where p.status <> 'cancelled' and bt.installment_label ~ '^\d{1,2}/\d{1,2}$'
),
saltos as (
  select *, parcela - lag(parcela) over (partition by bank_connection_id, loja, n order by parcela, k, payable_id) as salto
    from parcelas
),
compras as (
  select *, sum(case when salto is null or salto > n * 0.01 then 1 else 0 end)
              over (partition by bank_connection_id, loja, n order by parcela, k, payable_id) as compra
    from saltos
),
grupos as (
  select bank_connection_id, loja, n, compra,
         count(*) as lancamentos,
         count(distinct k) as parcelas_distintas,
         count(*) filter (where abs(lancado - n * parcela) <= n * 0.01) as inteiras
    from compras
   group by bank_connection_id, loja, n, compra
),
marcadas as (
  select c.*, g.lancamentos, g.parcelas_distintas, g.inteiras,
         first_value(c.payable_id) over (partition by c.bank_connection_id, c.loja, c.n, c.compra
                                         order by (abs(c.lancado - c.n * c.parcela) <= c.n * 0.01) desc, c.k, c.payable_id) as fica
    from compras c
    join grupos g
      on g.bank_connection_id is not distinct from c.bank_connection_id
     and g.loja = c.loja and g.n = c.n and g.compra = c.compra
)
select payable_id,
       fica as payable_que_fica,
       loja,
       n as parcelas,
       k as parcela_do_lancamento,
       parcela as valor_da_parcela,
       lancado,
       issue_date,
       transaction_date,
       description
  from marcadas
 where inteiras >= 1 and lancamentos > 1 and parcelas_distintas = lancamentos and payable_id <> fica;

comment on view public.compras_parceladas_em_dobro is
  'Lançamentos que repetem uma compra parcelada já lançada pelo valor inteiro (fica o da parcela mais antiga). Ver 20260927120000.';
revoke all on public.compras_parceladas_em_dobro from anon;
grant select on public.compras_parceladas_em_dobro to authenticated;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 3. Conciliação: a compra parcelada casada com UMA parcela não é "valor diferente". Mesma
--    visão, mesmas colunas na mesma ordem; duas colunas novas no fim.
-- ───────────────────────────────────────────────────────────────────────────────────────────
create or replace view public.conciliacao_lancamentos with (security_invoker = on) as
 SELECT 'payable'::text AS lado,
    p.id,
    p.description,
    p.amount,
    p.status,
    p.due_date,
    p.issue_date,
    COALESCE(s.name, p.supplier_name) AS contraparte,
    p.expense_category AS categoria,
    p.bank_transaction_id,
        CASE
            WHEN p.bank_transaction_id IS NOT NULL THEN 'conciliado'::text
            WHEN p.payment_method = 'credito_fornecedor'::text THEN 'fora_do_banco'::text
            ELSE 'sem_extrato'::text
        END AS situacao,
    bt.transaction_date AS extrato_data,
    bt.amount AS extrato_valor,
    bt.description AS extrato_descricao,
        CASE
            WHEN p.bank_transaction_id IS NOT NULL THEN round(p.amount - bt.amount, 2)
            ELSE NULL::numeric
        END AS diferenca,
    p.origin = 'bank_reconciliation'::text OR (EXISTS ( SELECT 1
           FROM finance_review_queue q
          WHERE q.created_payable_id = p.id)) AS nasceu_do_extrato,
        CASE
            WHEN bt.installment_label ~ '^\d{1,2}/\d{1,2}$'
            THEN abs(p.amount - split_part(bt.installment_label, '/', 2)::integer * bt.amount)
                 <= split_part(bt.installment_label, '/', 2)::integer * 0.01
            ELSE false
        END AS compra_parcelada,
        CASE
            WHEN bt.installment_label ~ '^\d{1,2}/\d{1,2}$' THEN split_part(bt.installment_label, '/', 2)::integer
            ELSE NULL::integer
        END AS parcelas
   FROM payables p
     LEFT JOIN bank_transactions bt ON bt.id = p.bank_transaction_id
     LEFT JOIN suppliers s ON s.id = p.supplier_id
  WHERE p.status <> 'cancelled'::text
UNION ALL
 SELECT 'receivable'::text AS lado,
    r.id,
    r.description,
    r.amount,
    r.status,
    r.due_date,
    r.issue_date,
    c.name AS contraparte,
    r.category AS categoria,
    r.bank_transaction_id,
        CASE
            WHEN r.bank_transaction_id IS NOT NULL THEN 'conciliado'::text
            ELSE 'sem_extrato'::text
        END AS situacao,
    bt.transaction_date AS extrato_data,
    bt.amount AS extrato_valor,
    bt.description AS extrato_descricao,
        CASE
            WHEN r.bank_transaction_id IS NOT NULL THEN round(r.amount - bt.amount, 2)
            ELSE NULL::numeric
        END AS diferenca,
    (EXISTS ( SELECT 1
           FROM finance_review_queue q
          WHERE q.created_receivable_id = r.id)) AS nasceu_do_extrato,
    false AS compra_parcelada,
    NULL::integer AS parcelas
   FROM receivables r
     LEFT JOIN bank_transactions bt ON bt.id = r.bank_transaction_id
     LEFT JOIN clients c ON c.id = r.client_id
  WHERE r.status <> 'cancelled'::text;

revoke all on public.conciliacao_lancamentos from anon;
grant select on public.conciliacao_lancamentos to authenticated;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- 4. "Mês pronto?": o item 3 (despesa em dobro) passa a contar a compra parcelada lançada mais
--    de uma vez; o item 4 (valor diferente do extrato) deixa de contar a compra parcelada casada
--    com uma parcela; o item 5 trava só DESPESA sem categoria (recebimento sem categoria já entra
--    no DRE como Receita). O resto da função é o de produção (20260927100000), sem mudança.
-- ───────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.checklist_do_mes(p_ano integer, p_mes integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_ini date := make_date(p_ano, p_mes, 1);
  v_fim date := (make_date(p_ano, p_mes, 1) + interval '1 month - 1 day')::date;
  v_itens jsonb := '[]'::jsonb;
  v_n integer;
  v_n_parc integer;
  v_valor numeric;
  v_det text;
begin
  -- 1. Saldo de cada conta confere com o banco (a última conferência).
  select count(*), string_agg(c.label || ' difere ' || public._brl(abs(k.diferenca)), '; ')
    into v_n, v_det
    from public.bank_connections c
    join lateral (select * from public.bank_balance_checks b where b.bank_connection_id = c.id
                   order by b.conferido_em desc limit 1) k on true
   where coalesce(c.active, true) and not k.fecha;
  v_itens := v_itens || jsonb_build_object('chave', 'saldo_confere', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'O saldo de cada conta confere com o banco', 'quantidade', v_n,
    'detalhe', coalesce(v_det, 'Todas as contas conferem na última sincronização.'));

  -- 2. Nada do extrato do mês sem destino (nem lançado, nem casado, nem fora da fila).
  select count(*), coalesce(sum(t.amount), 0) into v_n, v_valor
    from public.bank_transactions_situacao t
   where t.transaction_date between v_ini and v_fim and t.situacao = 'nova'
     and coalesce(t.tx_status, '') <> 'PENDING';
  v_itens := v_itens || jsonb_build_object('chave', 'extrato_tratado', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Todo movimento do banco no mês tem destino', 'quantidade', v_n, 'valor', v_valor,
    'detalhe', case when v_n = 0 then 'Nada esperando no Extrato.' else v_n || ' linha(s) esperando no Extrato.' end);

  -- 3. Nenhuma despesa lançada em dobro: uma com banco e outra sem, mesmo valor, mesma
  --    contraparte, até 5 dias. (Duas COM banco são dois pagamentos reais.) Conta em aberto se
  --    compara pelo vencimento; pagamento já ligado a uma nota não é duplicata das parcelas dela;
  --    a parte paga com crédito do fornecedor não passa pelo banco (revisão de 27/09/2026).
  --    E a compra parcelada lançada mais de uma vez (compras_parceladas_em_dobro).
  select count(*) into v_n
    from public.payables a
    join public.payables b on b.id <> a.id
     and a.bank_transaction_id is not null and b.bank_transaction_id is null
     and b.status <> 'cancelled' and abs(a.amount - b.amount) < 0.01
     and abs(a.issue_date - case when b.status in ('pending', 'partially_paid', 'overdue') then b.due_date else b.issue_date end) <= 5
     and not (a.fiscal_note_id is not null and a.fiscal_note_id = b.fiscal_note_id)
     and b.payment_method is distinct from 'credito_fornecedor'
     and coalesce(a.supplier_id::text, upper(a.supplier_name), '') = coalesce(b.supplier_id::text, upper(b.supplier_name), '')
     and coalesce(a.supplier_id::text, upper(a.supplier_name), '') <> ''
   where a.status <> 'cancelled' and a.issue_date between v_ini and v_fim;
  select count(*), coalesce(sum(d.lancado), 0) into v_n_parc, v_valor
    from public.compras_parceladas_em_dobro d
   where d.issue_date between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'sem_duplicata', 'bloqueia', true, 'ok', v_n + v_n_parc = 0,
    'titulo', 'Nenhuma despesa lançada em dobro', 'quantidade', v_n + v_n_parc,
    'detalhe', case
      when v_n + v_n_parc = 0 then 'Nenhum par suspeito.'
      else concat_ws(' ',
        case when v_n > 0 then v_n || ' par(es) com o mesmo valor e fornecedor, um pelo banco e outro à mão.' end,
        case when v_n_parc > 0 then v_n_parc || ' lançamento(s) repetem uma compra parcelada já lançada ('
                                     || public._brl(v_valor) || ' a mais).' end)
    end);

  -- 4. Lançamento casado com o extrato pelo mesmo valor. A compra parcelada casada com UMA
  --    parcela tem a diferença esperada (a compra inteira contra a parcela) e não conta.
  select count(*) into v_n
    from public.conciliacao_lancamentos l
   where l.situacao = 'conciliado' and coalesce(l.diferenca, 0) <> 0 and not l.compra_parcelada
     and coalesce(l.extrato_data, l.issue_date) between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'conciliacao_bate', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Nenhum lançamento com valor diferente do extrato', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Todos batem (compra parcelada casada com uma parcela não conta).' else v_n || ' lançamento(s) difere(m) do banco — veja a Conciliação.' end);

  -- 5. Toda DESPESA tem categoria (sem ela o valor some do resultado). Recebimento sem categoria
  --    entra no DRE como Receita (useLancamentosDRE), então não trava o mês: os sinais de orçamento
  --    e as parcelas de NF-e nascem sem categoria, e agosto/2026 travava por 7 deles (27/09/2026).
  select count(*) into v_n from public.payables
   where status <> 'cancelled' and issue_date between v_ini and v_fim and expense_category is null;
  v_itens := v_itens || jsonb_build_object('chave', 'tudo_categorizado', 'bloqueia', true, 'ok', v_n = 0,
    'titulo', 'Toda despesa tem categoria', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Nenhuma despesa sem categoria (recebimento sem categoria entra como Receita).'
                    else v_n || ' despesa(s) sem categoria não entram no DRE.' end);

  -- 6. Aviso: pago sem nenhum rastro no banco (ou no caixa).
  select count(*) into v_n from public.conciliacao_lancamentos l
   where l.situacao = 'sem_extrato' and l.status = 'paid' and l.issue_date between v_ini and v_fim;
  v_itens := v_itens || jsonb_build_object('chave', 'pago_sem_banco', 'bloqueia', false, 'ok', v_n = 0,
    'titulo', 'Pagos com rastro no banco ou no caixa', 'quantidade', v_n,
    'detalhe', case when v_n = 0 then 'Todo pagamento tem rastro.' else v_n || ' lançamento(s) pago(s) sem linha do banco — confira na Conciliação.' end);

  -- 7. Aviso: "Outras despesas" costuma esconder o que merecia categoria própria.
  select count(*), coalesce(sum(amount), 0) into v_n, v_valor from public.payables
   where status <> 'cancelled' and issue_date between v_ini and v_fim and expense_category = 'Outras despesas';
  v_itens := v_itens || jsonb_build_object('chave', 'outras_despesas', 'bloqueia', false, 'ok', v_n = 0,
    'titulo', 'Pouco em "Outras despesas"', 'quantidade', v_n, 'valor', v_valor,
    'detalhe', case when v_n = 0 then 'Nada em "Outras despesas".' else v_n || ' lançamento(s), ' || public._brl(v_valor) || ', em "Outras despesas".' end);

  return jsonb_build_object(
    'ano', p_ano, 'mes', p_mes,
    'pronto', not exists (select 1 from jsonb_array_elements(v_itens) i where (i ->> 'bloqueia')::boolean and not (i ->> 'ok')::boolean),
    'itens', v_itens
  );
end;
$function$;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- Conferências: se algo acima não ficou como deveria, nada é gravado.
-- ───────────────────────────────────────────────────────────────────────────────────────────
do $$
begin
  if (select reloptions from pg_class where oid = 'public.conciliacao_lancamentos'::regclass) is distinct from array['security_invoker=on']
     or (select reloptions from pg_class where oid = 'public.compras_parceladas_em_dobro'::regclass) is distinct from array['security_invoker=on'] then
    raise exception 'uma das visões perdeu o security_invoker';
  end if;
  if has_table_privilege('anon', 'public.conciliacao_lancamentos', 'SELECT')
     or has_table_privilege('anon', 'public.compras_parceladas_em_dobro', 'SELECT')
     or has_function_privilege('anon', 'public._loja_da_parcela(text,text)', 'EXECUTE') then
    raise exception 'anon enxerga a conciliação ou as compras em dobro';
  end if;
  if public._loja_da_parcela(null, 'Amazon Marketplace 2/4') <> 'AMAZON MARKETPLACE'
     or public._loja_da_parcela('EC          *INOHOUSE', 'EC          *INOHOUSE  SO JOS        BRA') <> 'EC *INOHOUSE' then
    raise exception 'a loja da parcela não saiu como o motor agrupa';
  end if;
end $$;
