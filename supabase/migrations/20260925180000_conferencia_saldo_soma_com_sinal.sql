-- Conferência de saldo: débito passa a SUBTRAIR.
--
-- A função somava `amount` sem olhar o sentido. No banco o valor é sempre positivo e o
-- sentido fica em `transaction_type`, então cada débito SOMAVA ao saldo calculado. A prova,
-- no C6 em 22/09/2026: entraram R$ 7.262,99 e saíram R$ 4.591,75; o banco subiu R$ 2.671,24
-- (a diferença) e o sistema subiu R$ 11.854,74 (a soma). A linha de base de
-- −R$ 1.525.206,47 gravada em 20/09 era o mesmo erro, e as contas do Nubank e da InfinitePay
-- só "fechavam" porque não tiveram movimento.
--
-- Efeito para o dono: quatro alertas "Pode faltar lançamento" pelo WhatsApp (22 a 25/09).
-- Não faltava nada.
--
-- Duplicata de importação também sai da soma: é a mesma movimentação trazida duas vezes
-- (arquivo OFX e sincronização), marcada e tirada da fila, e contá-la dobraria o valor.

create or replace function public.soma_transacoes_conexao(p_conexao uuid, p_ate date)
returns table (soma numeric, quantidade bigint)
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(sum(case when t.transaction_type = 'credit' then t.amount else -t.amount end), 0)::numeric as soma,
         count(*) as quantidade
    from public.bank_transactions t
   where t.bank_connection_id = p_conexao
     and coalesce(t.source_type, 'bank') = 'bank'
     and coalesce(t.tx_status, '') <> 'PENDING'
     and coalesce(t.dismissed_kind, '') <> 'duplicata'
     and t.transaction_date <= p_ate;
$$;

revoke all on function public.soma_transacoes_conexao(uuid, date) from public, anon;

-- A base foi calculada com a soma errada: apagar para a próxima sincronização refazer.
update public.bank_connections set saldo_base = null, saldo_base_em = null;

-- As conferências que acusaram diferença com a conta errada continuam no histórico, marcadas.
update public.bank_balance_checks
   set observacao = '[Conta errada, corrigida em 25/09/2026: débitos eram somados] ' || coalesce(observacao, '')
 where fecha = false
   and coalesce(observacao, '') not like '[Conta errada%';

insert into supabase_migrations.schema_migrations (version, name)
values ('20260925180000', 'conferencia_saldo_soma_com_sinal')
on conflict do nothing;
