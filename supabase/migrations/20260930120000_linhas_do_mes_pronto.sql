-- "O mês está pronto?": as linhas por trás de cada aviso (pedido do dono, 30/09/2026).
--
-- O dono via "36 linha(s) esperando no Extrato" ou "2 lançamentos em Outras despesas" e não
-- tinha como chegar a elas dali. Esta função devolve as linhas de UM item do checklist_do_mes,
-- com os MESMOS filtros (se um mudar, o outro muda junto — estão lado a lado de propósito), para
-- a tela abrir uma janela com a lista e, em cada lançamento, o "Corrigir" que o ERP já tem.
--
-- Regras conferidas contra a versão de 20260927120000 (compra parcelada casada com uma parcela não
-- conta; recebimento sem categoria entra como Receita e não trava o mês).
--
-- Security invoker, como o checklist: quem não vê pró-labore pela RLS também não o vê aqui.

create or replace function public.linhas_do_checklist(p_ano integer, p_mes integer, p_chave text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_ini date := make_date(p_ano, p_mes, 1);
  v_fim date := (make_date(p_ano, p_mes, 1) + interval '1 month - 1 day')::date;
  v jsonb;
begin
  if p_chave = 'saldo_confere' then
    select jsonb_agg(jsonb_build_object(
             'tipo', 'conta', 'id', c.id, 'data', (k.conferido_em at time zone 'America/Sao_Paulo')::date,
             'valor', k.diferenca, 'descricao', c.label, 'quem', null,
             'detalhe', 'O saldo calculado difere do banco em ' || public._brl(abs(k.diferenca)) || '.') order by c.label)
      into v
      from public.bank_connections c
      join lateral (select * from public.bank_balance_checks b where b.bank_connection_id = c.id
                     order by b.conferido_em desc limit 1) k on true
     where coalesce(c.active, true) and not k.fecha;

  elsif p_chave = 'extrato_tratado' then
    select jsonb_agg(x.linha order by x.data, x.valor desc) into v from (
      select t.transaction_date as data, t.amount as valor,
             jsonb_build_object(
               'tipo', 'extrato', 'id', t.id, 'data', t.transaction_date,
               'valor', case when t.transaction_type = 'debit' then -t.amount else t.amount end,
               'descricao', coalesce(t.description, 'Sem descrição'),
               'quem', coalesce(t.counterparty_name, t.merchant_name),
               'detalhe', case when t.transaction_type = 'debit' then 'Saída esperando destino no Extrato.' else 'Entrada esperando destino no Extrato.' end) as linha
        from public.bank_transactions_situacao t
       where t.transaction_date between v_ini and v_fim and t.situacao = 'nova'
         and coalesce(t.tx_status, '') <> 'PENDING'
       order by t.transaction_date, t.amount desc
       limit 200) x;

  elsif p_chave = 'sem_duplicata' then
    select jsonb_agg(jsonb_build_object(
             'tipo', 'payable', 'id', b.id, 'data', b.issue_date, 'valor', -b.amount,
             'descricao', coalesce(b.description, b.supplier_name, 'Sem descrição'),
             'quem', coalesce(b.supplier_name, ''),
             'detalhe', 'Lançada à mão; igual a uma pelo banco de ' || to_char(a.issue_date, 'DD/MM') || ' (' || coalesce(a.description, '') || ').')
             order by b.issue_date)
      into v
      from public.payables a
      join public.payables b on b.id <> a.id
       and a.bank_transaction_id is not null and b.bank_transaction_id is null
       and b.status <> 'cancelled' and abs(a.amount - b.amount) < 0.01
       and abs(a.issue_date - b.issue_date) <= 5
       and coalesce(a.supplier_id::text, upper(a.supplier_name), '') = coalesce(b.supplier_id::text, upper(b.supplier_name), '')
       and coalesce(a.supplier_id::text, upper(a.supplier_name), '') <> ''
     where a.status <> 'cancelled' and a.issue_date between v_ini and v_fim;

  elsif p_chave in ('conciliacao_bate', 'pago_sem_banco') then
    select jsonb_agg(jsonb_build_object(
             'tipo', l.lado, 'id', l.id, 'data', coalesce(l.extrato_data, l.issue_date),
             'valor', case when l.lado = 'payable' then -l.amount else l.amount end,
             'descricao', coalesce(l.description, 'Sem descrição'), 'quem', l.contraparte,
             'detalhe', case when p_chave = 'conciliacao_bate'
                             then 'O banco mostra ' || public._brl(l.extrato_valor) || '; a diferença é ' || public._brl(abs(l.diferenca)) || '.'
                             else 'Pago, mas sem linha do banco nem do caixa.' end)
             order by coalesce(l.extrato_data, l.issue_date))
      into v
      from public.conciliacao_lancamentos l
     where case when p_chave = 'conciliacao_bate'
                then l.situacao = 'conciliado' and coalesce(l.diferenca, 0) <> 0 and not l.compra_parcelada
                     and coalesce(l.extrato_data, l.issue_date) between v_ini and v_fim
                else l.situacao = 'sem_extrato' and l.status = 'paid' and l.issue_date between v_ini and v_fim end;

  elsif p_chave = 'tudo_categorizado' then
    select jsonb_agg(x.linha order by x.data) into v from (
      select p.issue_date as data, jsonb_build_object('tipo', 'payable', 'id', p.id, 'data', p.issue_date, 'valor', -p.amount,
               'descricao', coalesce(p.description, 'Sem descrição'), 'quem', p.supplier_name, 'detalhe', 'Despesa sem categoria.') as linha
        from public.payables p
       where p.status <> 'cancelled' and p.issue_date between v_ini and v_fim and p.expense_category is null) x;

  elsif p_chave = 'outras_despesas' then
    select jsonb_agg(jsonb_build_object(
             'tipo', 'payable', 'id', p.id, 'data', p.issue_date, 'valor', -p.amount,
             'descricao', coalesce(p.description, 'Sem descrição'), 'quem', p.supplier_name,
             'detalhe', 'Em "Outras despesas": merece uma categoria própria?') order by p.issue_date)
      into v
      from public.payables p
     where p.status <> 'cancelled' and p.issue_date between v_ini and v_fim and p.expense_category = 'Outras despesas';

  else
    raise exception 'Item do "Mês pronto?" desconhecido: %', p_chave;
  end if;

  return coalesce(v, '[]'::jsonb);
end;
$$;

revoke all on function public.linhas_do_checklist(integer, integer, text) from public, anon;
grant execute on function public.linhas_do_checklist(integer, integer, text) to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260930120000', 'linhas_do_mes_pronto')
on conflict do nothing;
