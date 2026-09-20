-- Open Finance D4 (decisão do dono, 17/09/2026): conferência saldo × soma das transações.
--
-- A conferência que já existia (banking-sync.conferirSaldo) compara o saldo da conta com o
-- "saldo após a última transação" que o provedor manda por transação. O C6 via Pluggy não
-- manda esse campo (todas as 1.818 transações vêm sem saldo), então ela nunca conferiu nada
-- desde 08/08. Esta versão não depende do campo: fixa uma LINHA DE BASE por conexão
-- (saldo do banco − soma de tudo que já foi importado, no dia em que a base é fixada) e, a
-- cada sincronização, espera que saldo_base + soma das transações até hoje = saldo do banco.
-- Se um lançamento deixar de ser importado, a diferença aparece e não some sozinha.

alter table public.bank_connections
  add column if not exists saldo_base numeric(14,2),
  add column if not exists saldo_base_em date;

comment on column public.bank_connections.saldo_base is
  'Saldo do banco menos a soma das transações importadas no dia em que a base foi fixada. saldo_base + soma(transações até hoje) deve dar o saldo atual do banco.';

-- Soma das transações "de conta" (não cartão), já efetivadas, até uma data, por conexão.
create or replace function public.soma_transacoes_conexao(p_conexao uuid, p_ate date)
returns table (soma numeric, quantidade bigint)
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(sum(t.amount), 0)::numeric as soma, count(*) as quantidade
    from public.bank_transactions t
   where t.bank_connection_id = p_conexao
     and coalesce(t.source_type, 'bank') = 'bank'
     and coalesce(t.tx_status, '') <> 'PENDING'
     and t.transaction_date <= p_ate;
$$;

revoke all on function public.soma_transacoes_conexao(uuid, date) from public, anon;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260920100000', 'saldo_base_conexao_bancaria')
on conflict do nothing;
