-- Prova: o token do /api/pdf vale UMA vez, vence em 3 minutos, só o servidor emite e ninguém o lê
-- pela API (migration 20261006210000_token_de_pdf).
--
--   supabase db query --linked -f supabase/tests/token_de_pdf.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
grant all on _resultado to anon;

do $$
declare
  v_token text;
  v_velho text;
begin
  v_token := public.emitir_token_de_pdf('teste');
  insert into _resultado values ('T1 token longo', length(v_token) = 64, length(v_token)::text);
  insert into _resultado values ('T2 vale uma vez',
    public.consumir_token_de_pdf(v_token) and not public.consumir_token_de_pdf(v_token), 'segunda chamada recusada');

  v_velho := public.emitir_token_de_pdf('teste');
  update public.tokens_de_pdf set expira_em = now() - interval '1 second' where token = v_velho;
  insert into _resultado values ('T3 vencido nao vale', not public.consumir_token_de_pdf(v_velho), 'vencido');
  insert into _resultado values ('T4 curto ou nulo nao vale',
    not public.consumir_token_de_pdf('') and not public.consumir_token_de_pdf(null), '');

  insert into _resultado values ('T5 quem pode',
    not has_function_privilege('anon', 'public.emitir_token_de_pdf(text)', 'execute')
      and not has_function_privilege('authenticated', 'public.emitir_token_de_pdf(text)', 'execute')
      and has_function_privilege('service_role', 'public.emitir_token_de_pdf(text)', 'execute')
      and has_function_privilege('anon', 'public.consumir_token_de_pdf(text)', 'execute')
      and not has_table_privilege('anon', 'public.tokens_de_pdf', 'select')
      and not has_table_privilege('authenticated', 'public.tokens_de_pdf', 'select'),
    'emitir só o servidor; tabela fechada');
  insert into _resultado values ('T6 emitir pede finalidade', true, '');
  begin
    perform public.emitir_token_de_pdf('  ');
    update _resultado set ok = false, detalhe = 'aceitou sem finalidade' where teste = 'T6 emitir pede finalidade';
  exception when others then null;
  end;
end $$;

-- T7: como anon (a chave publicável do /api/pdf), consumir funciona e a tabela não aparece.
set local role anon;
insert into _resultado
select 'T7 anon consome mas nao le', public.consumir_token_de_pdf('x' || repeat('0', 63)) = false, 'token inexistente = false';
reset role;

select teste, ok, detalhe from _resultado order by teste;

rollback;
