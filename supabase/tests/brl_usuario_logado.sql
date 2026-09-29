-- Prova: o dono logado consegue ver "O mês está pronto?" (checklist_do_mes) e visitante anônimo
-- continua sem executar _brl (migration 20260929200000_brl_para_usuario_logado).
--
-- ═══ COMO RODAR ═══
--
--   supabase db query --linked -f supabase/tests/brl_usuario_logado.sql --output json
--
-- Seguro em produção: só lê, e a transação inteira termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_admin uuid;
  v_ok boolean;
  v_det text;
  m int;
begin
  -- O admin que existe no login e está ativo: há cadastros antigos de admin em app_users sem
  -- usuário no auth, e com eles as funções de cargo respondem false.
  select a.id into v_admin
    from public.app_users a join auth.users u on u.id = a.id
   where a.role = 'admin' and a.active
   limit 1;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);

  -- Agosto (o mês a fechar) e setembro (o corrente): os dois com a conferência de saldo, que é
  -- onde _brl entra quando uma conta não fecha.
  foreach m in array array[8, 9] loop
    begin
      set local role authenticated;
      perform public.checklist_do_mes(2026, m);
      v_ok := true;
      v_det := 'rodou como usuário logado';
    exception when others then
      v_ok := false;
      v_det := sqlerrm;
    end;
    reset role;
    insert into _resultado values (format('checklist_do_mes(2026, %s) como usuário logado', m), v_ok, v_det);
  end loop;

  insert into _resultado values
    ('authenticated executa _brl',
     has_function_privilege('authenticated', 'public._brl(numeric)', 'execute'), 'precisa ser true'),
    ('anon NÃO executa _brl',
     not has_function_privilege('anon', 'public._brl(numeric)', 'execute'), 'precisa continuar fechado');
end $$;

select * from _resultado order by teste;

rollback;
