-- Prova da migration de dado opcional da Fase 4 (pacote P6; 20261027102000_fornecedores_cidade_com_acento.sql, NOVO-agenda-30),
-- que a bancada NÃO aplica (FORA_DA_BANCADA): aqui ela roda como está, numa subtransação desfeita, sobre a carteira de sex
-- 30/10 (fixture-fase4.sql: a Premel e a Souper em "Itaja�", o dono-fornecedor em "ITAJA�"), com mais fornecedores de teste
-- com as grafias quebradas de produção.
-- bancada: depende de 20261027100600
--
--   A  só as 24 grafias da lista fechada mudam ("Itaja�" → "Itajaí", "ITAJA�" → "ITAJAÍ", "S�o Paulo" → "São Paulo", "Arma��o
--      dos B�zios" → "Armação dos Búzios"); a grafia quebrada fora da lista fica; nome, endereço, UF e cidade certa não mudam;
--      cada troca guarda o antes (fornecedores_cidade_corrigida); a agenda conta o prazo igual (entrega local)
--   I  idempotente: de novo não troca nada nem duplica o antes
--   P  a tabela do antes é fechada (RLS ligada; anon e authenticated sem privilégio)
--   D  o DESFAZER do cabeçalho: volta a cidade de antes só onde ela ainda é a que a migration gravou (a que o dono mudou
--      depois fica a dele); nada apagado
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há a migration como texto: PULADO. NUNCA rodar em produção como prova: lá a prova é o SELECT do
--   cabeçalho da migration (só leitura). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create function pg_temp.res(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false),
                                                      case when not coalesce(p_ok, false) then p_detalhe end))
$f$;
-- "#" = U+FFFD (o caractere quebrado da importação de 12/04)
create function pg_temp.q(p text) returns text language sql immutable as $f$ select replace(p, '#', chr(65533)) $f$;
create function pg_temp.cidade(p_id uuid) returns text language sql stable as $f$
  select s.city from public.suppliers s where s.id = p_id
$f$;

do $a$
declare
  v_mig   text := current_setting('agenda_teste.mig_acento_fase4', true);
  v_res   jsonb := '[]'::jsonb;
  v_desf  text;
  v_bloco text;
  v_foto  text;
  v_n     int;
  c_premel constant uuid := 'dd000000-0000-4000-8000-000000000001';
  c_souper constant uuid := 'dd000000-0000-4000-8000-000000000010';
  c_dono   constant uuid := 'dd000000-0000-4000-8000-000000000009';
  c_kes    constant uuid := 'dd000000-0000-4000-8000-000000000002';
  c_sp     constant uuid := 'd4000000-0000-4000-8000-0000000006a1';
  c_buz    constant uuid := 'd4000000-0000-4000-8000-0000000006a2';
  c_fora   constant uuid := 'd4000000-0000-4000-8000-0000000006a3';
  c_certa  constant uuid := 'd4000000-0000-4000-8000-0000000006a4';
begin
  if coalesce(v_mig, '') = '' or coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('A0 a migration 20261027102000 como texto', true,
      'PULADO: sem agenda_teste.mig_acento_fase4 ou agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  v_bloco := substr(v_mig, position(E'\n-- DESFAZER' in v_mig) + 1);
  v_bloco := left(v_bloco, position(E'\n--\n' in v_bloco));
  select string_agg(substr(t.l, 3), E'\n' order by t.n) into v_desf
    from regexp_split_to_table(v_bloco, E'\n') with ordinality t(l, n)
   where t.l like '--   %';

  execute current_setting('agenda_teste.fase4');
  -- mais grafias de produção: "S�o Paulo", "Arma��o dos B�zios" (dois quebrados seguidos), uma quebrada FORA da lista
  -- ("Cuiab�") e uma cidade certa; com nome e endereço quebrados (não podem mudar)
  insert into public.suppliers (id, name, city, state, address_line_1, active) values
    (c_sp, pg_temp.q('DISTRIBUIDORA S#O PAULO (AG4A)'), pg_temp.q('S#o Paulo'), 'SP', pg_temp.q('Rua Jo#o, 1'), true),
    (c_buz, 'NAUTICA BUZIOS (AG4A)', pg_temp.q('Arma##o dos B#zios'), 'RJ', null, false),
    (c_fora, 'PECAS CUIABA (AG4A)', pg_temp.q('Cuiab#'), 'MT', null, true),
    (c_certa, 'ITAJAI CERTO (AG4A)', 'Itajaí', 'SC', null, true);

  begin
    v_foto := (select md5(string_agg(concat_ws('|', s.id, s.name, s.trade_name, s.state, s.address_line_1, s.cnpj_cpf, s.phone, s.active),
                                     ';' order by s.id)) from public.suppliers s);
    v_n := (select count(*) from public.suppliers where strpos(coalesce(city, ''), chr(65533)) > 0);
    execute v_mig;
    v_res := pg_temp.res(v_res, 'A1 as grafias da lista mudam: "Itaja�" → Itajaí (Premel, Souper), "ITAJA�" → ITAJAÍ, "S�o Paulo" → São Paulo, "Arma��o dos B�zios" → Armação dos Búzios (também o inativo)',
      pg_temp.cidade(c_premel) = 'Itajaí' and pg_temp.cidade(c_souper) = 'Itajaí' and pg_temp.cidade(c_dono) = 'ITAJAÍ'
      and pg_temp.cidade(c_sp) = 'São Paulo' and pg_temp.cidade(c_buz) = 'Armação dos Búzios',
      concat_ws(' | ', pg_temp.cidade(c_premel), pg_temp.cidade(c_dono), pg_temp.cidade(c_sp), pg_temp.cidade(c_buz)));
    v_res := pg_temp.res(v_res, 'A2 a grafia quebrada fora da lista ("Cuiab�") e a cidade certa ficam; nome, endereço, UF e o resto do cadastro não mudam',
      pg_temp.cidade(c_fora) = pg_temp.q('Cuiab#') and pg_temp.cidade(c_certa) = 'Itajaí' and pg_temp.cidade(c_kes) = 'Vila Velha'
      and (select md5(string_agg(concat_ws('|', s.id, s.name, s.trade_name, s.state, s.address_line_1, s.cnpj_cpf, s.phone, s.active),
                                 ';' order by s.id)) from public.suppliers s) = v_foto
      and (select name from public.suppliers where id = c_sp) = pg_temp.q('DISTRIBUIDORA S#O PAULO (AG4A)'), null);
    v_res := pg_temp.res(v_res, 'A3 cada troca guarda o antes (5 linhas: a cidade quebrada e a nova); só sobra com U+FFFD a de fora da lista',
      (select count(*) from public.fornecedores_cidade_corrigida) = 5 and v_n = 6
      and (select cidade_antes = pg_temp.q('Itaja#') and cidade_depois = 'Itajaí' from public.fornecedores_cidade_corrigida
            where supplier_id = c_premel)
      and (select count(*) from public.suppliers where strpos(coalesce(city, ''), chr(65533)) > 0) = 1,
      (select string_agg(cidade_depois, ', ' order by cidade_depois) from public.fornecedores_cidade_corrigida));
    v_res := pg_temp.res(v_res, 'A4 a agenda conta o prazo igual: a Premel continua entrega local, 1 dia útil (agora pela cidade escrita certa)',
      public._agenda_prazo_do_fornecedor(c_premel) ->> 'classe' = 'entrega_local'
      and public._agenda_lugar_texto((select city from public.suppliers where id = c_premel), 'SC') = 'Itajaí/SC', null);

    v_foto := (select md5(string_agg(concat_ws('|', s.id, s.city, s.updated_at), ';' order by s.id)) from public.suppliers s)
              || (select count(*)::text from public.fornecedores_cidade_corrigida);
    execute v_mig;
    v_res := pg_temp.res(v_res, 'I1 idempotente: de novo não troca nada (nem a hora da mudança) nem duplica o antes',
      (select md5(string_agg(concat_ws('|', s.id, s.city, s.updated_at), ';' order by s.id)) from public.suppliers s)
      || (select count(*)::text from public.fornecedores_cidade_corrigida) = v_foto, null);
    v_res := pg_temp.res(v_res, 'P1 a tabela do antes é fechada: RLS ligada; anon e authenticated sem select',
      (select c.relrowsecurity from pg_class c where c.oid = 'public.fornecedores_cidade_corrigida'::regclass)
      and not has_table_privilege('anon', 'public.fornecedores_cidade_corrigida', 'select')
      and not has_table_privilege('authenticated', 'public.fornecedores_cidade_corrigida', 'select'), null);

    -- D: o DESFAZER (a Souper o dono mudou depois: fica a dele)
    v_res := pg_temp.res(v_res, 'D0 o cabeçalho tem o DESFAZER: um UPDATE, nenhum DELETE',
      v_desf is not null and (length(v_desf) - length(replace(v_desf, 'update public.', ''))) / length('update public.') = 1
      and position('delete' in lower(v_desf)) = 0, coalesce(v_desf, '(sem o bloco)'));
    update public.suppliers set city = 'Navegantes' where id = c_souper;
    execute v_desf;
    v_res := pg_temp.res(v_res, 'D1 o DESFAZER volta a cidade quebrada onde ela ainda é a da migration; a que o dono mudou fica; o antes continua guardado',
      pg_temp.cidade(c_premel) = pg_temp.q('Itaja#') and pg_temp.cidade(c_dono) = pg_temp.q('ITAJA#')
      and pg_temp.cidade(c_sp) = pg_temp.q('S#o Paulo') and pg_temp.cidade(c_buz) = pg_temp.q('Arma##o dos B#zios')
      and pg_temp.cidade(c_souper) = 'Navegantes' and pg_temp.cidade(c_certa) = 'Itajaí'
      and (select count(*) from public.fornecedores_cidade_corrigida) = 5,
      concat_ws(' | ', pg_temp.cidade(c_premel), pg_temp.cidade(c_souper)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(v_res) e;
end
$a$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
