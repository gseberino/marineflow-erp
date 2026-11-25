-- Prova: a assinatura Claude pela pessoa do assinante — a LEITURA da chave ai_max_assinantes depois de gravada
-- (migration 20270301130000_assinatura_max_por_pessoa).
--
--   A0 de onde veio a chave: a que a migration gravou ou, no ensaio, a mesma gravação só dentro desta transação
--   A1 a chave existe, numa linha só
--   A2 lida como o servidor lê (minúscula; separada por vírgula, espaço ou ponto e vírgula), a lista tem exatamente UM
--      id com forma de id e nenhum pedaço descartado: é o que idDoAssinante exige para dizer quem é o assinante
--   A3 esse id é de um administrador ativo, e ele é o único administrador ativo
--   A4 nos últimos 90 dias, todo pedido ao Claude da assinatura foi dessa pessoa: nenhum turno muda de caminho
--   A5 gravar a chave de novo dá erro (a migration não tem "on conflict": chave repetida nunca passa calada)
--   A6 quem não está logado (anon) não lê a chave
--
-- O que este arquivo NÃO prova:
--   · que a migration recusa com 0 ou com 2 ou mais administradores ativos. O bloco dela roda uma vez só, no banco como
--     ele está no dia; a recusa está escrita nela (raise exception) e se lê lá. No ensaio, a A0 repete a mesma conta e,
--     se não achar exatamente 1, sai com ok = false dizendo quantos achou.
--   · a regra de quem passa (pessoa e não cargo, chave ausente, chave vazia): é do código e está provada em
--     supabase/functions/_shared/ai/max/claude-max_test.ts.
--
-- A2, A3 e A4 retratam o banco logo depois da migration. Se um dia o dono mudar a lista à mão (dois assinantes, outro
-- cargo), elas deixam de valer por decisão dele, não por defeito.
--
-- ═══ COMO RODAR ═══
--   npx supabase@2.111.0 db query --linked -f <caminho completo>/supabase/tests/assinatura_max_por_pessoa.sql --output json
--
-- Seguro em produção: termina em ROLLBACK e não mostra o id de ninguém (só contagens).
--   · DEPOIS de a migration estar aplicada: lê a chave que ela gravou.
--   · ANTES (ensaio): grava a chave pela mesma regra da migration, só dentro desta transação, e lê.
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- A0. A chave: a da migration ou, no ensaio, o mesmo bloco dela dentro desta transação ------------------------------
do $a0$
declare
  n int;
  ids text;
begin
  if exists (select 1 from public.app_settings where key = 'ai_max_assinantes') then
    insert into _resultado values ('A0 de onde veio a chave', true, 'a migration já foi aplicada: lendo a chave do banco');
    return;
  end if;
  select count(*), string_agg(id::text, ',') into n, ids
    from public.app_users
   where role = 'admin' and active;
  if n <> 1 then
    insert into _resultado values ('A0 de onde veio a chave', false,
      format('ensaio: esperava 1 administrador ativo (o assinante), achei %s: a migration vai recusar; decida a lista à mão', n));
    return;
  end if;
  insert into public.app_settings (key, value, description)
  values ('ai_max_assinantes', ids,
          'Quem pode usar a assinatura Claude (uso individual). Lista de app_users.id. Mesmo critério do gateway (CLAUDE_LOCAL_ALLOWED_REQUESTERS).');
  insert into _resultado values ('A0 de onde veio a chave', true,
    'ensaio: a migration ainda não foi aplicada; chave gravada só dentro desta transação');
exception when others then
  insert into _resultado values ('A0 de onde veio a chave', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end
$a0$;

-- A lista como o servidor a lê (claude-max.ts, listaDosAssinantes): minúscula, separada por vírgula, espaço ou ponto e
-- vírgula, sem repetição. tem_forma_de_id = o pedaço é um uuid; o que não é, o servidor descarta.
create temp table _lista on commit drop as
  select x.pedaco,
         x.pedaco ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' as tem_forma_de_id
    from (select distinct regexp_split_to_table(lower(s.value), '[\s,;]+') as pedaco
            from public.app_settings s
           where s.key = 'ai_max_assinantes') x
   where x.pedaco <> '';

-- A1. A chave existe, numa linha só ---------------------------------------------------------------------------------
insert into _resultado
select 'A1 a chave existe, numa linha só', count(*) = 1, count(*) || ' linha(s) com a chave'
  from public.app_settings
 where key = 'ai_max_assinantes';

-- A2. Exatamente um id, com forma de id, e nada descartado ----------------------------------------------------------
insert into _resultado
select 'A2 a lista tem exatamente um id, com forma de id, e nenhum pedaço descartado',
       count(*) filter (where tem_forma_de_id) = 1 and count(*) filter (where not tem_forma_de_id) = 0,
       count(*) filter (where tem_forma_de_id) || ' id(s) e ' || count(*) filter (where not tem_forma_de_id) || ' pedaço(s) sem forma de id'
  from _lista;

-- A3. O id é de um administrador ativo, e ele é o único -------------------------------------------------------------
insert into _resultado
select 'A3 o id da lista é de um administrador ativo, e ele é o único administrador ativo',
       c.da_lista = 1 and c.ativos = 1 and c.ids = 1,
       c.da_lista || ' id(s) da lista de administrador ativo; ' || c.ativos || ' administrador(es) ativo(s) no cadastro'
  from (select (select count(*) from _lista l join public.app_users u on u.id::text = l.pedaco
                 where l.tem_forma_de_id and u.role = 'admin' and u.active) as da_lista,
               (select count(*) from public.app_users where role = 'admin' and active) as ativos,
               (select count(*) from _lista where tem_forma_de_id) as ids) c;

-- A4. Nenhum turno muda de caminho: em 90 dias, todo pedido ao Claude da assinatura foi do assinante ----------------
-- Pedido sem autor (automação) não é turno de ninguém: aparece no detalhe e não reprova.
insert into _resultado
select 'A4 em 90 dias, todo pedido ao Claude da assinatura foi do assinante',
       count(*) filter (where p.requested_by is not null and not p.do_assinante) = 0,
       count(*) || ' pedido(s); ' || count(*) filter (where p.requested_by is not null and not p.do_assinante)
         || ' de quem não está na lista; ' || count(*) filter (where p.requested_by is null) || ' sem autor'
  from (select j.requested_by,
               coalesce(j.requested_by::text in (select l.pedaco from _lista l where l.tem_forma_de_id), false) as do_assinante
          from public.ai_jobs j
         where j.provider = 'claude-local'
           and j.created_at > now() - interval '90 days') p;

-- A5. Gravar a chave de novo dá erro --------------------------------------------------------------------------------
do $a5$
declare v_ok boolean := false; v_msg text := 'gravou de novo sem erro';
begin
  if not exists (select 1 from public.app_settings where key = 'ai_max_assinantes') then
    insert into _resultado values ('A5 gravar a chave de novo dá erro', false, 'a chave não existe: nada a repetir');
    return;
  end if;
  begin
    insert into public.app_settings (key, value, description)
    values ('ai_max_assinantes', '', 'teste: esta linha não pode entrar');
  exception when unique_violation then
    v_ok := true; v_msg := 'chave repetida recusada';
  end;
  insert into _resultado values ('A5 gravar a chave de novo dá erro', v_ok, v_msg);
end
$a5$;

-- A6. Quem não está logado não lê a chave ---------------------------------------------------------------------------
do $a6$
declare v_n int := -1; v_ok boolean := false; v_msg text := 'não conferido';
begin
  begin
    set local role anon;
    select count(*) into v_n from public.app_settings where key = 'ai_max_assinantes';
    v_ok := v_n = 0;
    v_msg := 'sem login enxerga ' || v_n || ' linha(s) da chave';
  exception when insufficient_privilege then
    v_ok := true; v_msg := 'permission denied';
  end;
  reset role;
  insert into _resultado values ('A6 quem não está logado não lê a chave', v_ok, v_msg);
end
$a6$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
