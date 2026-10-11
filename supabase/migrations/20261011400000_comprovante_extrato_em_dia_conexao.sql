-- Comprovantes F3 (11/10/2026): a conta SEM MOVIMENTO não segura o "quem pagou?" da regra E.
--
-- _comprovante_extrato_em_dia (20261011302000) só olhava o extrato: toda conta que se mexeu perto da
-- compra (linha entre D-30 e D+5) precisava ter linha de D+5 em diante importada depois de D+5. O Nubank
-- PJ não está com a sincronização parada — está sem movimento (sincroniza todo dia: ok, UPDATED, o saldo
-- do provedor bate com o calculado na conferência diária; última linha do extrato em 18/09). Pela regra
-- antiga ele segurava TODA compra de 14/09 em diante: o "quem pagou?" nunca era perguntado e o CMP virava
-- 'abandonado' em 30 dias (45 no crédito) sem o dono ter sido perguntado (nem o reembolso ao sócio ou ao
-- técnico nas Diárias oferecido).
--
-- Agora a conta fica em dia por linha nova (como antes) OU pela saúde da conexão: a última sincronização
-- deu certo (last_sync_status 'ok'), o item está UPDATED no Pluggy, o que ele trouxe já foi importado
-- (last_synced_at >= provider_updated_at) e o Pluggy foi ao banco (provider_updated_at, a idade real do
-- extrato — 20261006230000) depois que D+5 terminou. last_synced_at sozinho não serve: avança mesmo com o
-- item OUTDATED. No cartão a margem é D+13 (D+5 + os 8 dias de atraso máximo medidos no cartão do C6 desde
-- 29/09): uma sincronização ok logo depois de D+5 não prova que a compra no cartão já chegou. Conexão sem
-- esses dados (manual, nunca sincronizada, com erro ou OUTDATED) continua segurando.
--
-- Mesma assinatura e casca (sql, stable, security definer, search_path vazio, sem grant para ninguém).
-- Só função. Não escreve dados. Idempotente.

create or replace function public._comprovante_extrato_em_dia(c public.comprovantes)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select c.data_confirmada is not null and not exists (
    select 1
      from (select distinct t.bank_connection_id as conexao, coalesce(t.source_type, 'bank') as fonte
              from public.bank_transactions t
              join public.bank_connections bc on bc.id = t.bank_connection_id and bc.active and coalesce(bc.provider, '') <> 'caixa'
             where coalesce(t.source_type, 'bank') in ('bank', 'credit_card')
               and t.transaction_date between c.data_confirmada - 30 and c.data_confirmada + 5) a
      join public.bank_connections bc on bc.id = a.conexao
     where not exists (select 1 from public.bank_transactions n
                        where n.bank_connection_id = a.conexao and coalesce(n.source_type, 'bank') = a.fonte
                          and n.transaction_date >= c.data_confirmada + 5
                          and n.created_at >= ((c.data_confirmada + 5)::timestamp at time zone 'America/Sao_Paulo'))
       and not coalesce(bc.last_sync_status = 'ok' and bc.provider_status = 'UPDATED'
                        and bc.last_synced_at >= bc.provider_updated_at
                        and bc.provider_updated_at >= ((c.data_confirmada + case when a.fonte = 'credit_card' then 13 else 6 end)::timestamp
                                                       at time zone 'America/Sao_Paulo'), false));
$$;

comment on function public._comprovante_extrato_em_dia(public.comprovantes) is
  'O extrato de cada conta da empresa que se mexeu perto da compra já chegou até D+5: por linha nova importada '
  'depois de D+5, ou porque a conexão sincronizou bem (ok, UPDATED, importada) com o Pluggy indo ao banco '
  'depois de D+5 (D+13 no cartão). A conta sem movimento (Nubank PJ) não segura; a sincronização parada, sim.';

revoke all on function public._comprovante_extrato_em_dia(public.comprovantes) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: o helper continua sem grant para ninguém e o corpo novo é o que ficou.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text := 'public._comprovante_extrato_em_dia(public.comprovantes)';
begin
  if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute')
     or has_function_privilege('service_role', v_f, 'execute') then
    raise exception 'helper interno da conciliação alcançável: %', v_f;
  end if;
  if not (select prosecdef from pg_proc where oid = v_f::regprocedure)
     or (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_f::regprocedure) <> 'sql' then
    raise exception '_comprovante_extrato_em_dia mudou de casca (deve seguir sql e security definer)';
  end if;
  if position('provider_updated_at' in pg_get_functiondef(v_f::regprocedure)) = 0 then
    raise exception '_comprovante_extrato_em_dia sem a saúde da conexão';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011400000', 'comprovante_extrato_em_dia_conexao')
on conflict do nothing;
