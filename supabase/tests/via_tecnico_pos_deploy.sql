-- Prova: a via do técnico pelo WhatsApp (migration 20270120100000_via_tecnico_responsavel).
--
-- ═══ COMO RODAR ═══
--
--   npx supabase@2.111.0 db query --linked -f supabase/tests/via_tecnico_pos_deploy.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Marca um responsável numa linha real e grava um envio de teste só dentro
-- da transação. A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_linha uuid;
  v_os uuid;
  v_pessoa uuid;
  v_id uuid;
  v_msg text;
begin
  -- 1. A coluna: existe, aponta para payees e solta (set null) quando o favorecido some.
  insert into _resultado select '1 coluna responsavel_payee_id em service_order_services',
    exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'service_order_services'
             and column_name = 'responsavel_payee_id' and data_type = 'uuid'), null;
  insert into _resultado select '1b FK para payees com on delete set null',
    exists (select 1 from pg_constraint where conrelid = 'public.service_order_services'::regclass and contype = 'f'
             and confrelid = 'public.payees'::regclass and confdeltype = 'n'
             and pg_get_constraintdef(oid) like '%(responsavel_payee_id)%'), null;
  -- 2. O portal do cliente (anon) não lê a coluna nova. Em produção o anon lê service_order_services só por coluna
  --    (20261001230000) e a coluna nova não está na lista. Na bancada da agenda este item dá false: lá o anon tem a
  --    tabela inteira, porque o revoke de 01/10 é anterior ao recorte da bancada.
  insert into _resultado select '2 anon não lê responsavel_payee_id',
    not has_column_privilege('anon', 'public.service_order_services', 'responsavel_payee_id', 'SELECT'), null;
  -- 3. A tabela do registro: RLS ligada, anon sem nada, logado só lê (a política filtra o admin), escrita só pela chave de serviço.
  insert into _resultado select '3 via_tecnico_envios com RLS',
    (select relrowsecurity from pg_class where oid = 'public.via_tecnico_envios'::regclass), null;
  insert into _resultado select '3b anon sem SELECT/INSERT',
    not has_table_privilege('anon', 'public.via_tecnico_envios', 'SELECT')
    and not has_table_privilege('anon', 'public.via_tecnico_envios', 'INSERT'), null;
  insert into _resultado select '3c logado só lê',
    has_table_privilege('authenticated', 'public.via_tecnico_envios', 'SELECT')
    and not has_table_privilege('authenticated', 'public.via_tecnico_envios', 'INSERT')
    and not has_table_privilege('authenticated', 'public.via_tecnico_envios', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.via_tecnico_envios', 'DELETE'), null;
  insert into _resultado select '3d uma política, de SELECT, só para authenticated',
    (select count(*) = 1 and bool_and(cmd = 'SELECT' and roles = '{authenticated}') from pg_policies
      where schemaname = 'public' and tablename = 'via_tecnico_envios'), null;

  -- 4. Marcar o responsável numa linha real (dentro da transação) e gravar um envio de teste.
  select s.id, s.service_order_id into v_linha, v_os from public.service_order_services s order by s.created_at desc limit 1;
  select p.id into v_pessoa from public.payees p where p.active and p.kind in ('socio', 'funcionario', 'diarista', 'prestador') order by p.name limit 1;
  update public.service_order_services set responsavel_payee_id = v_pessoa where id = v_linha;
  insert into _resultado select '4 marca o responsável na linha',
    (select responsavel_payee_id = v_pessoa from public.service_order_services where id = v_linha), null;

  insert into public.via_tecnico_envios (service_order_id, payee_id, origem, estado, destino, impressao, servicos)
  values (v_os, v_pessoa, 'assistente', 'enviado', '5547999990000', 'teste', 1) returning id into v_id;
  insert into _resultado select '4b grava um envio', v_id is not null, null;

  -- 5. As travas da tabela.
  begin
    insert into public.via_tecnico_envios (service_order_id, payee_id, origem, estado) values (v_os, v_pessoa, 'agenda', 'falhou');
    insert into _resultado values ('5 falhou sem motivo é recusado', false, 'aceitou');
  exception when check_violation then
    insert into _resultado values ('5 falhou sem motivo é recusado', true, null);
  end;
  begin
    insert into public.via_tecnico_envios (service_order_id, origem, estado) values (v_os, 'agenda', 'enviado');
    insert into _resultado values ('5b sem pessoa nem usuário é recusado', false, 'aceitou');
  exception when check_violation then
    insert into _resultado values ('5b sem pessoa nem usuário é recusado', true, null);
  end;
  begin
    insert into public.via_tecnico_envios (service_order_id, payee_id, origem, estado, destino) values (v_os, v_pessoa, 'agenda', 'enviado', '+55 47 9999');
    insert into _resultado values ('5c destino com símbolo é recusado', false, 'aceitou');
  exception when check_violation then
    insert into _resultado values ('5c destino com símbolo é recusado', true, null);
  end;
exception when others then
  get stacked diagnostics v_msg = message_text;
  insert into _resultado values ('erro inesperado', false, v_msg);
end $$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
