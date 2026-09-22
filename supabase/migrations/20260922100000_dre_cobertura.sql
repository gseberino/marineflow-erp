-- Cobertura do DRE (22/09/2026): quanto do dinheiro que passou pelo banco o resultado explica.
--
-- Motivo: medido hoje, 2026 tem R$ 501.686 de entrada na conta e R$ 188.489 lançados como
-- receita (38%), contra 96% do lado da despesa. O DRE mostra quase toda a despesa e menos da
-- metade do faturamento, então exibe prejuízo onde não há. O aviso que existia no painel
-- contava só "entradas não conciliadas do ano" — não dava percentual, não respeitava o mês
-- escolhido e ignorava o lado da despesa.
--
-- Esta função é a conta única: o painel, o agente e o briefing passam a ler daqui.
--
-- Bases, de propósito diferentes e declaradas:
--   · lançamento (receivables/payables) por `issue_date` — é o que o DRE usa;
--   · banco (bank_transactions) por `transaction_date`, só conta corrente e já efetivado.
-- Um mês pode passar de 100% quando a conta foi emitida num mês e paga noutro. Isso é
-- descasamento de data, não dado a mais — quem lê o percentual precisa saber disso.

create or replace function public.dre_cobertura(p_ano integer)
returns table (
  mes integer,
  receita_lancada numeric,
  entrada_banco numeric,
  despesa_lancada numeric,
  saida_banco numeric
)
language sql
stable
security invoker
set search_path = public
as $$
  with meses as (select generate_series(1, 12) m),
  rec as (
    select extract(month from issue_date)::int m, sum(amount) total
      from public.receivables
     where extract(year from issue_date) = p_ano
       and coalesce(status, '') <> 'cancelled'
     group by 1
  ),
  pag as (
    select extract(month from issue_date)::int m, sum(amount) total
      from public.payables
     where extract(year from issue_date) = p_ano
     group by 1
  ),
  banco as (
    select extract(month from transaction_date)::int m,
           sum(amount) filter (where transaction_type = 'credit') entradas,
           sum(amount) filter (where transaction_type = 'debit') saidas
      from public.bank_transactions
     where extract(year from transaction_date) = p_ano
       and coalesce(source_type, 'bank') = 'bank'
       and coalesce(tx_status, '') <> 'PENDING'
     group by 1
  )
  select meses.m,
         coalesce(rec.total, 0)::numeric,
         coalesce(banco.entradas, 0)::numeric,
         coalesce(pag.total, 0)::numeric,
         coalesce(banco.saidas, 0)::numeric
    from meses
    left join rec on rec.m = meses.m
    left join pag on pag.m = meses.m
    left join banco on banco.m = meses.m
   order by meses.m;
$$;

revoke all on function public.dre_cobertura(integer) from public, anon;
grant execute on function public.dre_cobertura(integer) to authenticated;

comment on function public.dre_cobertura(integer) is
  'Por mês do ano: receita e despesa lançadas (por issue_date, base do DRE) contra entradas e saídas do banco (por transaction_date, conta corrente efetivada). Serve ao selo de confiabilidade do DRE.';

insert into supabase_migrations.schema_migrations (version, name)
values ('20260922100000', 'dre_cobertura')
on conflict do nothing;
