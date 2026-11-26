-- Prova: o histórico de quedas do assistente só é lido e gravado pelo servidor, guarda no máximo uma queda aberta por
-- tipo, recusa valor fora das listas, e a chave do vigia existe (migration 20270301110000_assistente_quedas).
--
--   Q1 RLS ligada e nenhuma policy
--   Q2 anon e authenticated sem nenhum privilégio (tabela e colunas)
--   Q3 anon: ler e gravar dão "permission denied" (erro, nunca lista vazia calada)
--   Q4 authenticated (um administrador logado): ler, inserir, alterar e apagar dão "permission denied"
--   Q5 o servidor (service_role) grava e lê
--   Q6 uma queda aberta por tipo: a 2ª do mesmo tipo é recusada; de outro tipo, não; fechada a 1ª, abre outra
--   Q7 os CHECKs: tipo, causa, fechada_por, dono_soube, avisado_por e o tamanho do detalhe
--   Q8 a chave vigia_assistente existe com um dos três valores
--
-- ═══ COMO RODAR ═══
--
--   npx supabase@2.111.0 db query --linked -f <caminho completo>/supabase/tests/assistente_quedas.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Dentro da transação fecha as quedas que estiverem abertas (para o índice de
-- "uma aberta por tipo" não esbarrar numa queda de verdade) e grava linhas de teste; nada disso fica. A tabela final tem
-- de mostrar ok = true em todas as linhas.
--
-- ANTES de a migration estar aplicada: rodar o ensaio (a migration, sem a última linha do registro, + este corpo na
-- mesma transação).
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
grant all on _resultado to authenticated, anon, service_role;

-- as quedas de verdade que estiverem abertas saem do caminho (volta tudo no rollback)
update public.assistente_quedas set ate = now(), fechada_por = 'sem_prova' where ate is null;

-- Q1. RLS ligada e nenhuma policy -------------------------------------------------------------------------------------
insert into _resultado
select 'Q1 RLS ligada e nenhuma policy',
       (select c.relrowsecurity from pg_class c where c.oid = 'public.assistente_quedas'::regclass)
   and (select count(*) = 0 from pg_policies where schemaname = 'public' and tablename = 'assistente_quedas'),
       coalesce((select string_agg(policyname || ':' || cmd || ':' || roles::text, ' | ')
                   from pg_policies where schemaname = 'public' and tablename = 'assistente_quedas'), 'sem policy');

-- Q2. anon e authenticated sem nenhum privilégio ----------------------------------------------------------------------
insert into _resultado
select 'Q2 anon e authenticated sem privilégio (tabela e colunas)',
       not exists (
         select 1 from unnest(array['anon', 'authenticated']) papel,
                       unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) priv
          where has_table_privilege(papel, 'public.assistente_quedas', priv))
   and not exists (
         select 1 from pg_attribute a, unnest(array['anon', 'authenticated']) papel, unnest(array['select', 'insert', 'update', 'references']) priv
          where a.attrelid = 'public.assistente_quedas'::regclass and a.attnum > 0 and not a.attisdropped
            and has_column_privilege(papel, 'public.assistente_quedas', a.attname, priv)),
       'privilégios conferidos um a um';

-- Q3. anon: ler e gravar dão erro -------------------------------------------------------------------------------------
do $q3$
declare v_ler boolean := false; v_gravar boolean := false; v_msg text := '';
begin
  begin
    set local role anon;
    perform id from public.assistente_quedas limit 1;
    v_msg := v_msg || 'leu; ';
  exception when insufficient_privilege then v_ler := true;
  end;
  reset role;
  begin
    set local role anon;
    insert into public.assistente_quedas (tipo, causa, desde) values ('claude', 'login', now());
    v_msg := v_msg || 'gravou; ';
  exception when insufficient_privilege then v_gravar := true;
  end;
  reset role;
  insert into _resultado values ('Q3 anon: ler e gravar recusados', v_ler and v_gravar, coalesce(nullif(v_msg, ''), 'permission denied nos dois'));
end
$q3$;

-- Q4. authenticated (um administrador logado): nada ------------------------------------------------------------------
do $q4$
declare
  v_quem uuid := (select id from public.app_users where role = 'admin' and active order by created_at limit 1);
  v_ler boolean := false; v_ins boolean := false; v_upd boolean := false; v_del boolean := false; v_msg text := '';
begin
  if v_quem is null then
    insert into _resultado values ('Q4 administrador logado: tudo recusado', true, 'PULADO: sem administrador ativo');
    return;
  end if;
  perform set_config('request.jwt.claim.sub', v_quem::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_quem, 'role', 'authenticated')::text, true);
  begin
    set local role authenticated;
    perform id from public.assistente_quedas limit 1;
    v_msg := v_msg || 'leu; ';
  exception when insufficient_privilege then v_ler := true;
  end;
  reset role;
  begin
    set local role authenticated;
    insert into public.assistente_quedas (tipo, causa, desde) values ('claude', 'login', now());
    v_msg := v_msg || 'inseriu; ';
  exception when insufficient_privilege then v_ins := true;
  end;
  reset role;
  begin
    set local role authenticated;
    update public.assistente_quedas set causa = 'limite' where tipo = 'claude';
    v_msg := v_msg || 'alterou; ';
  exception when insufficient_privilege then v_upd := true;
  end;
  reset role;
  begin
    set local role authenticated;
    delete from public.assistente_quedas where tipo = 'claude';
    v_msg := v_msg || 'apagou; ';
  exception when insufficient_privilege then v_del := true;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('Q4 administrador logado: tudo recusado', v_ler and v_ins and v_upd and v_del,
    coalesce(nullif(v_msg, ''), 'permission denied nos quatro'));
end
$q4$;

-- Q5. o servidor grava e lê -------------------------------------------------------------------------------------------
do $q5$
declare v_id uuid; v_n int; v_msg text;
begin
  begin
    set local role service_role;
    insert into public.assistente_quedas (tipo, causa, detalhe, desde, ate, fechada_por)
    values ('gateway', 'programa_parado', 'sem_sinal', now() - interval '2 hours', now() - interval '1 hour', 'batimento')
    returning id into v_id;
    select count(*) into v_n from public.assistente_quedas where id = v_id;
    update public.assistente_quedas set dono_soube = 'aviso', avisado_em = now(), avisado_por = 'sino' where id = v_id;
    reset role;
  exception when others then
    v_msg := sqlstate || ' ' || sqlerrm;
  end;
  reset role;
  insert into _resultado values ('Q5 o servidor grava, lê e altera', v_msg is null and v_n = 1, coalesce(v_msg, 'gravou e leu 1 linha'));
end
$q5$;

-- Q6. uma queda aberta por tipo ---------------------------------------------------------------------------------------
do $q6$
declare v_primeira uuid; v_segunda boolean := false; v_outro_tipo boolean := false; v_depois boolean := false; v_msg text := '';
begin
  insert into public.assistente_quedas (tipo, causa, desde) values ('claude', 'login', now() - interval '30 minutes') returning id into v_primeira;
  begin
    insert into public.assistente_quedas (tipo, causa, desde) values ('claude', 'limite', now());
    v_msg := v_msg || 'abriu a 2ª do mesmo tipo; ';
  exception when unique_violation then v_segunda := true;
  end;
  begin
    insert into public.assistente_quedas (tipo, causa, desde) values ('gateway', 'sem_rede', now());
    insert into public.assistente_quedas (tipo, causa, desde) values ('whatsapp', 'pc_fora', now());
    v_outro_tipo := true;
  exception when others then v_msg := v_msg || 'outro tipo recusado: ' || sqlerrm || '; ';
  end;
  begin
    update public.assistente_quedas set ate = now(), fechada_por = 'job_bom' where id = v_primeira;
    insert into public.assistente_quedas (tipo, causa, desde) values ('claude', 'limite', now());
    v_depois := true;
  exception when others then v_msg := v_msg || 'não abriu depois de fechar: ' || sqlerrm || '; ';
  end;
  insert into _resultado values ('Q6 uma queda aberta por tipo', v_segunda and v_outro_tipo and v_depois,
    coalesce(nullif(v_msg, ''), '2ª do mesmo tipo recusada; outro tipo e depois de fechar, aceitas'));
end
$q6$;

-- Q7. os CHECKs -------------------------------------------------------------------------------------------------------
do $q7$
declare
  v_casos jsonb := jsonb_build_array(
    jsonb_build_object('t', 'tipo', 'sql', $s$insert into public.assistente_quedas (tipo, causa, desde, ate) values ('email', 'login', now(), now())$s$),
    jsonb_build_object('t', 'causa', 'sql', $s$insert into public.assistente_quedas (tipo, causa, desde, ate) values ('claude', 'sem_credito', now(), now())$s$),
    jsonb_build_object('t', 'fechada_por', 'sql', $s$insert into public.assistente_quedas (tipo, causa, desde, ate, fechada_por) values ('claude', 'login', now(), now(), 'teste')$s$),
    jsonb_build_object('t', 'dono_soube', 'sql', $s$insert into public.assistente_quedas (tipo, causa, desde, ate, dono_soube) values ('claude', 'login', now(), now(), 'email')$s$),
    jsonb_build_object('t', 'avisado_por', 'sql', $s$insert into public.assistente_quedas (tipo, causa, desde, ate, avisado_por) values ('claude', 'login', now(), now(), 'push')$s$),
    jsonb_build_object('t', 'detalhe', 'sql', $s$insert into public.assistente_quedas (tipo, causa, desde, ate, detalhe) values ('claude', 'login', now(), now(), repeat('x', 301))$s$)
  );
  c jsonb; v_passou text := ''; v_n int := 0;
begin
  for c in select * from jsonb_array_elements(v_casos) loop
    begin
      execute c->>'sql';
      v_passou := v_passou || (c->>'t') || ' aceitou valor de fora; ';
    exception when check_violation then v_n := v_n + 1;
    end;
  end loop;
  insert into _resultado values ('Q7 CHECKs recusam valor fora das listas e detalhe longo', v_n = 6 and v_passou = '',
    coalesce(nullif(v_passou, ''), v_n || ' de 6 recusados'));
end
$q7$;

-- Q8. a chave do vigia ------------------------------------------------------------------------------------------------
insert into _resultado
select 'Q8 a chave vigia_assistente existe com um dos três valores',
       coalesce((select value in ('desligado', 'sombra', 'ligado') from public.app_settings where key = 'vigia_assistente'), false),
       coalesce((select value from public.app_settings where key = 'vigia_assistente'), 'AUSENTE');

select teste, ok, detalhe from _resultado order by teste;

rollback;
