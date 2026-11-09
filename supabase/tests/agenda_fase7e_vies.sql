-- Prova do viés na duração da Agenda de Produção, Fase 7e (pacote P3; migration 20261111100200; spec-fase7e §5.2, §8.3 e o bloco R7: R7.3-2, R7.5-8, 10, 11, 12, R7.6, R7.8, R7.13).
-- bancada: depende de 20261111100200
--
--   V0  as funções: portas, tipo; o que a migration não recriou
--   V1  o aprendido: os números da §8.2 (1,11; 1,17; 0,99; 1,16; dono 1,02 e 1,04), as chaves, a volta a medindo, a janela, o erro de uma chave
--   V2  os_duracao_sugerida: V2a byte a byte em sombra e no freio; V2b as 3 saídas com o viés (freio solto; uma_pessoa, R$ aprendido, nenhuma); V2c diagnóstico sem viés; V2d sem base sem viés; V2e o texto
--   V3  agenda_meios_da_os: V3a byte a byte em sombra e no freio; V3b a dupla ligada conserva o viés; V3c a fonte orcamento gravada (OS-00069, 7,5); V3d marcado × agora; V3e sem chave em sombra (0 chamada)
--   V4  o publicado não muda: a OS marcada guarda o total
--   V5  d12: o R$ aprendido não entra na duração com viés em uso
--   V6  as cópias: tirados os blocos do P3, o corpo é o da origem
--   V7  o dono (AG7-33): os 2 números; a dupla dita intacta; repetir = vies_dono_fixo (frase até o *grava*); dizer o corrigido também; sobrevive ao passo 2; acima do máximo não corrige; só com vies_corrige_dono
--   V8  a armadilha da medida: dp_bruto, pm_estimados, pm_plano e pessoas sem o viés (com freio, sem freio, com viés em uso, com vies_marcado); agenda.sem_vies volta ao valor de antes
--   V9  agenda_aplicar: sem correção aplicada, o número do item, como antes (sombra, desligado, proposta antiga); com ela, dias sem o viés e o aprovado em aprovado_com_vies; o total lido fica o publicado, antes e depois da marcação, com a dupla, sem empilhar o dono:
--   V10 a sombra não chama nada de novo (as funções novas trocadas por versões que lançam)
--
-- ═══ COMO RODAR ═══  Na bancada: node scripts/bancada-agenda/rodar.mjs. Em produção, só DEPOIS de aplicar a migration, com o OK: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7e_vies.sql
--   Tudo dentro de begin/rollback. O que usa fixture só roda na bancada (fora dela sai PULADO). Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- ── V0. As funções (sem fixture) ───────────────────────────────────────────────────────────────────
create temp table _f7e_p3 (f text primary key, quem text) on commit drop;
insert into _f7e_p3 values
  ('public._agenda_dias_com_vies(jsonb, numeric)', 'leitura'),
  ('public._agenda_vies_dono_da_os(uuid)', 'leitura'),
  ('public._agenda_aprender_vies(date, timestamptz)', 'passo');

insert into _resultado
select 'V0a as 3 funções novas existem; as 2 de leitura têm porta para authenticated e service_role; o passo sem grant nem service_role; anon nada',
       count(*) = 3
       and bool_and(not has_function_privilege('anon', f::regprocedure, 'execute'))
       and bool_and(has_function_privilege('authenticated', f::regprocedure, 'execute') = (quem = 'leitura'))
       and bool_and(has_function_privilege('service_role', f::regprocedure, 'execute') = (quem = 'leitura')),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f::regprocedure, 'execute')
                                      or has_function_privilege('authenticated', f::regprocedure, 'execute') <> (quem = 'leitura')
                                      or has_function_privilege('service_role', f::regprocedure, 'execute') <> (quem = 'leitura'))
  from _f7e_p3;

insert into _resultado
select 'V0b as de leitura são stable; o passo é volatile e definer com search_path fixo',
       bool_and(p.provolatile = 's') filter (where p.oid in ('public._agenda_dias_com_vies(jsonb, numeric)'::regprocedure, 'public._agenda_vies_dono_da_os(uuid)'::regprocedure))
       and (select p2.prosecdef and p2.provolatile = 'v' and exists (select 1 from unnest(p2.proconfig) c where c like 'search_path=%')
              from pg_proc p2 where p2.oid = 'public._agenda_aprender_vies(date, timestamptz)'::regprocedure),
       null
  from pg_proc p where p.oid in ('public._agenda_dias_com_vies(jsonb, numeric)'::regprocedure, 'public._agenda_vies_dono_da_os(uuid)'::regprocedure);

insert into _resultado
select 'V0c os_planejamento.aprovado_com_vies existe, jsonb, nula, sem padrão (só nasce com a duração aprovada com o viés)',
       count(*) = 1 and bool_and(a.atttypid = 'jsonb'::regtype and not a.attnotnull and not a.atthasdef), null
  from pg_attribute a where a.attrelid = 'public.os_planejamento'::regclass and a.attname = 'aprovado_com_vies' and not a.attisdropped;

-- ── A fixture e os ajudantes ───────────────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' then
    execute current_setting('agenda_teste.fase7e');
    -- Só as OS-7E* interessam (as outras fixtures saem do caminho, como no teste do P2), e o congelar só roda nelas
    perform set_config('marineflow.agrupar_orcamentos', 'on', true);
    update public.service_orders set merged_into_id = 'e7e00000-0000-4000-8000-000000000e00'
     where service_order_number not like 'OS-7E%' and service_order_number <> 'OS-E0' and merged_into_id is null;
    perform set_config('marineflow.agrupar_orcamentos', '', true);
  end if;
end
$carga$;

create function pg_temp.fx() returns boolean language sql stable as $f$ select coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' $f$;
create function pg_temp.os(p_nome text) returns uuid language sql immutable as $f$ select md5('e7e:os:' || p_nome)::uuid $f$;
create function pg_temp.dono() returns uuid language sql stable as $f$ select public._agenda_dono(null) $f$;
create function pg_temp.adm() returns uuid language sql stable as $f$ select id from public.app_users where role = 'admin' and active order by id limit 1 $f$;
create function pg_temp.caio() returns uuid language sql immutable as $f$ select 'e7e00000-0000-4000-8000-00000000aa01'::uuid $f$;
-- Uma OS aberta nova (rv ou barco, pelo veículo da fixture). O serviço dá a classe (bateria/inversor = energia).
create function pg_temp.aberta(p_n int, p_mo numeric, p_servico text default 'Instalação de inversor e baterias', p_horas numeric default 0, p_status text default 'approved',
                               p_veiculo uuid default 'e7e00000-0000-4000-8000-000000000b02', p_tipo text default 'repair') returns uuid language plpgsql as $f$
declare
  v_os uuid := md5('e7e:v:' || p_n)::uuid;
begin
  perform set_config('agenda.porta', 'on', true);
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
  values (v_os, 'OS-7EV' || p_n, 'e7e00000-0000-4000-8000-000000000c02', p_veiculo, p_status, 'approved', p_tipo,
          timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-02 10:00-03', p_mo);
  if p_horas > 0 then
    insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
    values (v_os, p_servico, 'hour', p_horas, 0, 0, timestamptz '2026-12-01 10:00-03');
  end if;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (v_os, p_servico, 'visit', 1, p_mo, p_mo, timestamptz '2026-12-01 10:00-03');
  perform set_config('agenda.porta', 'off', true);
  return v_os;
end $f$;
-- Os dias ditos, do jeito que estão em produção (dono, aceita) ou como a pergunta grava (orcamento)
create function pg_temp.dias(p_os uuid, p_dias numeric, p_fonte text) returns void language sql as $f$
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, atualizado_em)
  values (p_os, p_dias, p_fonte, timestamptz '2026-12-05 10:00-03', timestamptz '2026-12-05 10:00-03')
  on conflict (service_order_id) do update set dias = excluded.dias, estimativa_fonte = excluded.estimativa_fonte, estimativa_em = excluded.estimativa_em
$f$;
-- Um viés em uso (a chave e o valor; a linha que o gravador deixa)
create function pg_temp.vies(p_chave text, p_uso numeric, p_n int default 5) returns void language sql as $f$
  insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em)
  values ('vies', p_chave, case when p_chave like '%:todas' then 'todas' else 'fina' end, 1, 1, p_n, p_uso, p_uso, 'em_uso', now())
  on conflict (item, chave) do update set em_uso = excluded.em_uso, calculado = excluded.calculado, estado = 'em_uso', n = excluded.n
$f$;
-- O dono aprova uma duração só sugerida: a proposta com o item (fonte sugerida, os dias que foram mostrados) e as alocações de verdade (N meios-dias de Zeca a partir de p_de, dia útil); agenda_aplicar pela via do dono
create function pg_temp.aprova(p_os uuid, p_dias numeric, p_de date default date '2027-02-08', p_hoje date default date '2027-01-07', p_agora timestamptz default timestamptz '2027-01-07 10:00-03') returns jsonb language plpgsql as $f$
declare
  v_prop uuid;
  cf     public.agenda_config := public._agenda_cfg();
begin
  insert into public.agenda_propostas (escopo, periodo, os_alvo, modo, estado, versao_base, itens, parametros, expira_em, criada_por)
  values ('os', daterange(p_hoje, p_de + 60, '[]'), array[p_os], 'ligado', 'aberta', cf.versao_plano,
          jsonb_build_array(jsonb_build_object('os', p_os, 'op', 'criar', 'tipo', 'execucao', 'fonte', 'sugerida', 'dias', p_dias, 'texto', 'marcar', 'motivo', 'teste', 'alocacoes', '[]'::jsonb, 'fixar_dono', false,
            'critica', null, 'pergunta_chave', null, 'decisao', null, 'espera', false, 'interrupcoes', 0, 'meios_do_dono', 0, 'evento_real', false, 'aviso_material', null, 'de', p_de, 'ate', p_de)),
          jsonb_build_object('p_hoje', p_hoje), greatest(now(), p_agora) + interval '1 day', 'dono') returning id into v_prop;
  perform set_config('agenda.hoje', p_hoje::text, true);
  return public.agenda_aplicar(v_prop, array[p_os], 'dono', null, null, p_hoje, p_agora);
end $f$;
-- Publica N meios-dias para a OS (o plano que o motor marcou: o caminho inteiro, agenda_marcar_os, roda no replay real em f7e/p3/aprova.mjs)
create function pg_temp.publica(p_os uuid, p_n int, p_de date default date '2027-02-08') returns void language plpgsql as $f$
declare
  v_d date := p_de;
  v_t text := 'manha';
  k   int;
begin
  for k in 1 .. p_n loop
    while not public.agenda_dia_util(v_d) loop v_d := v_d + 1; end loop;
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (p_os, 'e7e00000-0000-4000-8000-00000000aa02', v_d, v_t, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2027-01-07 10:00-03');
    if v_t = 'manha' then v_t := 'tarde'; else v_t := 'manha'; v_d := v_d + 1; end if;
  end loop;
end $f$;
-- O que vale em cada caso: o interruptor, o aprendizado ligado e o freio. Sem o freio, as regras do gestor valem.
create function pg_temp.modo(p_modo text, p_freio boolean) returns void language sql as $f$
  update public.agenda_config
     set modo_vies = p_modo, modo_aprendizado = 'ligado', gestor_so_propor = p_freio, modo_marcar_sozinho = 'ligado', vies_corrige_dono = true
   where id
$f$;
create function pg_temp.lines(p_t text) returns setof text language sql immutable as $f$ select regexp_split_to_table(p_t, E'\n') $f$;
-- Tira os blocos do P3 de um corpo (linha a linha, como o montador faz)
create function pg_temp.sem_p3(p_t text) returns text language plpgsql immutable as $f$
declare
  l text;
  fora text[] := '{}';
  dentro boolean := false;
begin
  for l in select pg_temp.lines(replace(p_t, E'\r\n', E'\n')) loop
    if not dentro and l ~ '^\s*-- (FASE 7e: \(7e P3|\(7e P3)' then dentro := true; continue; end if;
    if dentro and l ~ '^\s*-- (FASE 7e: fim|\(7e: fim\))' then dentro := false; continue; end if;
    if dentro then continue; end if;
    fora := fora || l;
  end loop;
  return array_to_string(fora, E'\n');
end $f$;
-- O corpo de antes (o da origem), como função temporária com outro nome, para o byte a byte
create function pg_temp.criar_antes() returns void language plpgsql as $f$
declare
  v_m text := coalesce(current_setting('agenda_teste.mig_vies_fase7e', true), '');
  v_i int;
  v_c text;
begin
  v_i := position('create or replace function public.os_duracao_sugerida(' in v_m);
  v_c := substr(v_m, v_i, position(E'\n$function$;' in substr(v_m, v_i)) + 11);
  v_c := pg_temp.sem_p3(v_c);
  execute replace(v_c, 'create or replace function public.os_duracao_sugerida(p_so_id uuid)', 'create or replace function pg_temp.antes_dur(p_so_id uuid)');
  v_i := position('create or replace function public.agenda_meios_da_os(' in v_m);
  v_c := substr(v_m, v_i, position(E'\n$function$;' in substr(v_m, v_i)) + 11);
  v_c := pg_temp.sem_p3(v_c);
  execute replace(v_c, 'create or replace function public.agenda_meios_da_os(p_so_id uuid, p_hoje date)', 'create or replace function pg_temp.antes_meios(p_so_id uuid, p_hoje date)');
end $f$;

-- ── V1. O aprendido ────────────────────────────────────────────────────────────────────────────────
do $v1$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  c_agora constant timestamptz := timestamptz '2027-01-07 16:05-03';
  r jsonb;
  v_calc numeric;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V1 o aprendido', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    -- V1, Z1 e R1 são casos do teste do P2 (a porta da medição e a reaberta), com razões próprias; aqui valem só as 8 OS do viés, as 2 do dono e as inválidas
    perform set_config('marineflow.agrupar_orcamentos', 'on', true);
    update public.service_orders set merged_into_id = 'e7e00000-0000-4000-8000-000000000e00' where id in (pg_temp.os('V1'), pg_temp.os('Z1'), pg_temp.os('R1'));
    perform set_config('marineflow.agrupar_orcamentos', '', true);
    update public.agenda_config set modo_aprendizado = 'ligado', modo_vies = 'sombra', gestor_so_propor = true where id;
    perform public._agenda_aprender_congelar(c_hoje);
    perform public._agenda_aprender_medir(c_hoje);
    r := public._agenda_aprender_vies(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'V1a sem erro em nenhuma chave', (r ->> 'erros')::int = 0, r::text);
    select calculado into v_calc from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas';
    v_res := pg_temp.ok(v_res, 'V1b o geral: mediana 1,175, Z = 8/13 → 1,11 (a §8.2)', v_calc = 1.11, format('%s', v_calc));
    select calculado into v_calc from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:rv:energia';
    v_res := pg_temp.ok(v_res, 'V1c rv:energia: mediana 1,25, Z = 4/9, base o geral sem arredondar → 1,17', v_calc = 1.17, format('%s', v_calc));
    select calculado into v_calc from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:rv:geral';
    v_res := pg_temp.ok(v_res, 'V1d rv:geral: mediana 0,80, Z = 3/8 → 0,99 (abaixo de 1)', v_calc = 0.99, format('%s', v_calc));
    select calculado into v_calc from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:barco:energia';
    v_res := pg_temp.ok(v_res, 'V1e barco:energia: 1,40, Z = 1/6 → 1,16', v_calc = 1.16, format('%s', v_calc));
    select calculado into v_calc from public.agenda_aprendizado where item = 'vies' and chave = 'dono:todas';
    v_res := pg_temp.ok(v_res, 'V1f dono:todas: mediana 1,075, Z = 2/7 → 1,02', v_calc = 1.02, format('%s', v_calc));
    select calculado into v_calc from public.agenda_aprendizado where item = 'vies' and chave = 'dono:rv:diagnostico';
    v_res := pg_temp.ok(v_res, 'V1g dono:rv:diagnostico → 1,04 (base o geral do dono sem arredondar)', v_calc = 1.04, format('%s', v_calc));
    v_res := pg_temp.ok(v_res, 'V1h em teste (sombra) nada em uso e a amostra guarda as OS',
      (select estado = 'sombra' and em_uso is null and n = 8 and jsonb_array_length(amostra) = 8 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas'),
      (select format('estado=%s em_uso=%s n=%s', estado, em_uso, n) from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas'));
    v_res := pg_temp.ok(v_res, 'V1i o grupo do dono não entra no estimador: só as 2 OS do dono em dono:*',
      (select n = 2 from public.agenda_aprendizado where item = 'vies' and chave = 'dono:todas')
      and (select n = 8 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas'), null);
    v_res := pg_temp.ok(v_res, 'V1p o detalhe da classe guarda o geral sem arredondar (1,1077) e a mediana e o z dela (0,4444)',
      (select (detalhe ->> 'geral')::numeric = 1.1077 and (detalhe ->> 'mediana')::numeric = 1.25 and (detalhe ->> 'z')::numeric = 0.4444 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:rv:energia'),
      (select detalhe::text from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:rv:energia'));
    -- os limites da config: vies_max corta, a amostra máxima corta (fator_amostra_max)
    update public.agenda_config set vies_max = 1.05 where id;
    r := public._agenda_aprender_vies(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'V1n o valor fica entre vies_min e vies_max (vies_max 1,05 corta 1,11 e 1,17)',
      (select calculado = 1.05 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas') and (select calculado = 1.05 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:rv:energia'), r::text);
    update public.agenda_config set vies_max = 2.50, fator_amostra_max = 6 where id;
    r := public._agenda_aprender_vies(c_hoje, c_agora);
    update public.agenda_config set vies_max = 2.50, vies_min = 1.00 where id;
    r := public._agenda_aprender_vies(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'V1q o piso vies_min (1,00) corta a classe abaixo dele (rv:geral 0,99 → 1,00)', (select calculado = 1 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:rv:geral'), r::text);
    update public.agenda_config set vies_min = 0.50 where id;
    v_res := pg_temp.ok(v_res, 'V1o fator_amostra_max: só as 6 mais recentes de cada chave (o geral com 8 fica com n = 6; rv:energia, com 4, fica com 4)',
      (select n = 6 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas') and (select n = 4 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:rv:energia'), r::text);
    update public.agenda_config set fator_amostra_max = 20 where id;
    -- a segunda rodada não muda
    r := public._agenda_aprender_vies(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'V1j 2ª rodada igual', (select calculado = 1.11 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas'), r::text);
    -- ligado: o gravador anda; a classe sai do geral em uso como padrão
    update public.agenda_config set modo_vies = 'ligado', gestor_so_propor = false where id;
    r := public._agenda_aprender_vies(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'V1k ligado sem freio: o gravador põe em uso (1,00 → 1,11; a classe, 1,17), padrão da classe = o geral em uso',
      (select estado = 'em_uso' and em_uso = 1.11 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:todas')
      and (select em_uso = 1.17 and padrao = 1.11 from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:rv:energia'),
      (select format('uso=%s padrao=%s', em_uso, padrao) from public.agenda_aprendizado where item = 'vies' and chave = 'estimativa:rv:energia'));
    -- a chave sem medida volta a medir (o molde do fator): lá para frente, nenhuma medida na janela
    r := public._agenda_aprender_vies(date '2031-01-07', c_agora);
    v_res := pg_temp.ok(v_res, 'V1l sem medida na janela: as chaves voltam a medindo (n = 0, sem calculado), sem apagar', (select bool_and(n = 0 and estado = 'medindo' and calculado is null) from public.agenda_aprendizado where item = 'vies'), r::text);
    -- o erro de uma chave vai ao log e o resto segue
    execute $f$create or replace function public._agenda_aprendizado_gravar(p_item text, p_chave text, p_nivel text, p_calculado numeric, p_n integer, p_amostra jsonb, p_padrao numeric, p_detalhe jsonb, p_agora timestamp with time zone)
      returns jsonb language plpgsql as $g$ begin if p_chave = 'estimativa:rv:energia' then raise exception 'estouro'; end if; return '{"estado":"medindo"}'::jsonb; end $g$;$f$;
    r := public._agenda_aprender_vies(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'V1m o erro de uma chave vai a aprender:vies e as outras seguem (erros = 1)',
      (r ->> 'erros')::int = 1 and (r ->> 'chaves')::int >= 5
      and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'aprender:vies'),
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v1$;

-- ── V2. os_duracao_sugerida ────────────────────────────────────────────────────────────────────────
do $v2$
declare
  v_res jsonb := '[]'::jsonb;
  v_os  uuid;
  v_osd uuid;
  v_osb uuid;
  v_oss uuid[];
  v_d   jsonb;
  m     text;
  f     boolean;
  v_a   jsonb;
  v_b   jsonb;
  v_dif int;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V2 duração', true, 'PULADO: sem a fixture'));
    return;
  end if;
  perform pg_temp.criar_antes();
  begin
    v_os := pg_temp.aberta(1, 3820);                                  -- rv:energia, dp 5
    v_osd := pg_temp.aberta(2, 1000, 'DIAGNÓSTICO TÉCNICO NO LOCAL', p_tipo => 'diagnosis');
    v_osb := pg_temp.aberta(3, 0, 'Sem preço');
    v_oss := array[v_os, v_osd, v_osb, pg_temp.aberta(4, 1910, 'Reparo na porta da cabine'), pg_temp.aberta(5, 7640, 'Instalação de inversor', 40)];
    perform pg_temp.vies('estimativa:rv:energia', 1.20);
    perform pg_temp.vies('estimativa:todas', 1.10);
    -- V2a: nas 4 combinações que não usam o viés, igual ao corpo de antes, byte a byte, em cada OS (e sem chave nenhuma): desligado, sombra, ligado com o freio
    v_dif := 0;
    for m, f in select * from (values ('desligado', true), ('sombra', true), ('ligado', true), ('sombra', false)) x(a, b) loop
      perform pg_temp.modo(m, f);
      select count(*) into v_a from unnest(v_oss) o where public.os_duracao_sugerida(o) ? 'vies';
      v_dif := v_dif + (select count(*)::int from unnest(v_oss) o where public.os_duracao_sugerida(o) <> pg_temp.antes_dur(o)) + (v_a #>> '{}')::int;
    end loop;
    v_res := pg_temp.ok(v_res, 'V2a desligado, sombra e ligado com o freio: o mesmo de antes byte a byte, sem chave vies, em toda OS', v_dif = 0, format('diferentes: %s', v_dif));

    -- V2b: as 3 saídas com o freio solto
    perform pg_temp.modo('ligado', false);
    -- saída 1: a regra uma_pessoa ligada: pessoas_motivo na saída + vies
    v_d := public.os_duracao_sugerida(v_os);
    v_res := pg_temp.ok(v_res, 'V2b1 saída da regra (uma_pessoa, freio solto): dias_realista de antes e as chaves do viés (1,20 × 5 = 6 dias, 1 pessoa)',
      v_d ->> 'pessoas_motivo' = 'regra' and (v_d ->> 'vies')::numeric = 1.2 and (v_d ->> 'dias_realista')::numeric = 5 and (v_d ->> 'dias_planejado')::numeric = 6 and (v_d ->> 'dp_planejado')::numeric = 6
      and (v_d ->> 'pessoas_planejado')::int = 1 and v_d ->> 'vies_chave' = 'estimativa:rv:energia', v_d::text);
    -- saída 2: sem a regra, com o R$ aprendido (d12: o R$ da config)
    update public.agenda_config set modo_marcar_sozinho = 'desligado', modo_dupla = 'ligado', aprendizado_ligados = array['fator', 'mo'] where id;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em) values ('mo', 'todas', 'todas', 764, 3, 8, 382, 382, 'em_uso', now());
    v_d := public.os_duracao_sugerida(v_os);
    v_res := pg_temp.ok(v_res, 'V2b2 saída do R$ aprendido, sem a regra: mo_fonte aprendido e as chaves do viés (dias_planejado pelo R$ da config, d12)',
      v_d ->> 'mo_fonte' = 'aprendido' and (v_d ->> 'vies')::numeric = 1.2 and (v_d ->> 'dias_planejado')::numeric = 6 and (v_d ->> 'dp_realista')::numeric = 10 and not v_d ? 'pessoas_motivo', v_d::text);
    update public.agenda_aprendizado set em_uso = null, estado = 'medindo' where item = 'mo';
    -- saída 3: nem a regra nem o aprendido: a saída final (o caso que o R7.5-8 aponta: sem isto o viés nunca rodaria em produção)
    v_d := public.os_duracao_sugerida(v_os);
    v_res := pg_temp.ok(v_res, 'V2b3 a saída final (sem regra, sem aprendido): as chaves do viés', (v_d ->> 'vies')::numeric = 1.2 and (v_d ->> 'dias_planejado')::numeric = 6 and not v_d ? 'mo_fonte', v_d::text);
    v_res := pg_temp.ok(v_res, 'V2b4 as chaves de antes não mudam com o viés (dias_realista, dp_realista, pessoas, sugerida)',
      (v_d ->> 'dias_realista')::numeric = 5 and (v_d ->> 'dp_realista')::numeric = 5 and (v_d ->> 'pessoas')::int = 1 and (v_d ->> 'sugerida')::numeric = 4,
      format('dias_realista=%s dp=%s sug=%s', v_d ->> 'dias_realista', v_d ->> 'dp_realista', v_d ->> 'sugerida'));
    -- as pessoas não mudam com o viés: as da sugestão (a dupla dita pelo dono: 2 pessoas; 6 ÷ 2 = 3 dias)
    perform pg_temp.modo('ligado', false);
    update public.agenda_config set modo_dupla = 'sombra', equipe_sugerida = 2 where id;
    insert into public.os_planejamento (service_order_id, dupla_dita) values (v_os, 'todos') on conflict (service_order_id) do update set dupla_dita = 'todos';
    v_d := public.os_duracao_sugerida(v_os);
    v_res := pg_temp.ok(v_res, 'V2b6 com a dupla dita, 2 pessoas (R7.5-12): dias_planejado = dp 6 ÷ 2 = 3, pessoas_planejado 2 (a regra de cima não recalcula)',
      (v_d ->> 'pessoas')::int = 2 and (v_d ->> 'pessoas_planejado')::int = 2 and (v_d ->> 'dias_planejado')::numeric = 3 and (v_d ->> 'dp_planejado')::numeric = 6, v_d::text);
    update public.os_planejamento set dupla_dita = null where service_order_id = v_os;
    -- a estimativa por horas: dp = horas ÷ jornada (8), 40 h = 5 × 1,2 = 6 dias, com a mão de obra baixa
    perform pg_temp.aberta(60, 100, 'Reparo na porta da cabine', 40);
    v_d := public.os_duracao_sugerida(md5('e7e:v:60')::uuid);
    v_res := pg_temp.ok(v_res, 'V2b8 pelas horas: 40 h ÷ 8 × 1,10 (geral, sem linha fina) = dp 5,5 (a MO de 100 é menor)', (v_d ->> 'dp_planejado')::numeric = 5.5, v_d::text);
    -- a OS pequena: nunca menos de meio dia (dp 0,16 ÷ 1 = 0,16 → arredonda a 0; o piso devolve 0,5)
    perform pg_temp.aberta(59, 100, 'Reparo na porta da cabine');
    v_d := public.os_duracao_sugerida(md5('e7e:v:59')::uuid);
    v_res := pg_temp.ok(v_res, 'V2b7 serviço pequeno: dias_planejado nunca menos de meio dia', (v_d ->> 'dias_planejado')::numeric = 0.5, v_d::text);
    -- a classe sem linha vai no geral (a OS sai por uma pessoa: a regra volta)
    perform pg_temp.modo('ligado', false);
    update public.agenda_config set modo_dupla = 'sombra' where id;
    v_d := public.os_duracao_sugerida(v_oss[4]);
    v_res := pg_temp.ok(v_res, 'V2b5 sem linha fina, o geral: a chave é estimativa:todas (1,10) e a OS de 1.910 sai com 3 dias (dp 2,5 × 1,1 = 2,75 → 3)',
      v_d ->> 'vies_chave' = 'estimativa:todas' and (v_d ->> 'vies')::numeric = 1.1 and (v_d ->> 'dias_planejado')::numeric = 3, v_d::text);
    perform pg_temp.modo('ligado', false);
    v_res := pg_temp.ok(v_res, 'V2c diagnóstico sem viés (R7.5-9): a saída do diagnóstico não ganha chave', (public.os_duracao_sugerida(v_osd) ->> 'diagnostico') = 'true' and not public.os_duracao_sugerida(v_osd) ? 'vies', null);
    v_res := pg_temp.ok(v_res, 'V2d sem base sem viés', (public.os_duracao_sugerida(v_osb) ->> 'sem_base') = 'true' and not public.os_duracao_sugerida(v_osb) ? 'vies', null);
    -- V2e o texto do cartão (§6.4), maior e menor que 1
    v_d := public.os_duracao_sugerida(v_os);
    v_res := pg_temp.ok(v_res, 'V2e o texto com viés > 1 (§6.4): "Estimativa minha: 5 dias pelo valor do orçamento × 1,2 (as OS de energia em motorhome costumam levar mais) = 6 dias."',
      v_d ->> 'texto_vies' = 'Estimativa minha: 5 dias pelo valor do orçamento × 1,2 (as OS de energia em motorhome costumam levar mais) = 6 dias.', v_d ->> 'texto_vies');
    perform pg_temp.vies('estimativa:rv:energia', 0.80);
    v_d := public.os_duracao_sugerida(v_os);
    v_res := pg_temp.ok(v_res, 'V2e2 o texto com viés < 1: "costumam levar um pouco menos"', v_d ->> 'texto_vies' like '%× 0,8 (as OS de energia em motorhome costumam levar um pouco menos) = 4 dias.', v_d ->> 'texto_vies');
    -- a conta que não muda o número não vira frase ("5 dias × 1,02 = 5 dias"), mas as chaves seguem
    perform pg_temp.vies('estimativa:rv:energia', 1.02);
    v_d := public.os_duracao_sugerida(v_os);
    v_res := pg_temp.ok(v_res, 'V2e3 5 dias × 1,02 = 5 dias: sem texto_vies, com vies e dias_planejado (os números existem, a frase não diz nada)',
      not v_d ? 'texto_vies' and (v_d ->> 'vies')::numeric = 1.02 and (v_d ->> 'dias_planejado')::numeric = 5, v_d::text);
    -- viés 1 (o valor exato em uso): sem chave nenhuma
    perform pg_temp.vies('estimativa:rv:energia', 1);
    update public.agenda_aprendizado set em_uso = null, estado = 'medindo' where item = 'vies' and chave = 'estimativa:todas';
    v_res := pg_temp.ok(v_res, 'V2f viés exato 1: sem chave (a saída de antes)', public.os_duracao_sugerida(v_os) = pg_temp.antes_dur(v_os), null);
    -- com o freio, mesmo com o viés em uso, nada
    perform pg_temp.vies('estimativa:rv:energia', 1.20);
    perform pg_temp.modo('ligado', true);
    v_res := pg_temp.ok(v_res, 'V2g com o freio ligado (produção), o modo ligado não vale: sem chave', not public.os_duracao_sugerida(v_os) ? 'vies', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v2$;

-- ── V3, V4, V5. agenda_meios_da_os ─────────────────────────────────────────────────────────────────
do $v3$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_os  uuid;
  v_ped uuid;
  v_gr  uuid;
  v_oss uuid[];
  v_m   jsonb;
  m     text;
  f     boolean;
  v_dif int;
  v_a   int;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V3 meios', true, 'PULADO: sem a fixture'));
    return;
  end if;
  perform pg_temp.criar_antes();
  begin
    v_os := pg_temp.aberta(11, 3820);        -- dp 5
    v_ped := pg_temp.aberta(12, 1910);       -- dp 2,5
    v_gr := pg_temp.aberta(13, 3056);        -- dp 4: a gravada
    perform pg_temp.dias(v_gr, 7.5, 'orcamento');
    v_oss := array[v_os, v_ped, v_gr, pg_temp.aberta(14, 0, 'Sem preço'), pg_temp.aberta(15, 1000, 'DIAGNÓSTICO TÉCNICO NO LOCAL', p_tipo => 'diagnosis')];
    perform pg_temp.vies('estimativa:rv:energia', 1.20);
    perform pg_temp.vies('dono:todas', 1.20);
    -- V3a byte a byte
    v_dif := 0;
    for m, f in select * from (values ('desligado', true), ('sombra', true), ('ligado', true), ('sombra', false)) x(a, b) loop
      perform pg_temp.modo(m, f);
      v_dif := v_dif + (select count(*)::int from unnest(v_oss) o where public.agenda_meios_da_os(o, c_hoje) is distinct from pg_temp.antes_meios(o, c_hoje));
    end loop;
    v_res := pg_temp.ok(v_res, 'V3a desligado, sombra e ligado com o freio: agenda_meios_da_os igual ao de antes, byte a byte, em toda OS', v_dif = 0, format('diferentes: %s', v_dif));

    -- V3 fonte do estimador corrigida, freio solto (orcamento com a estimativa do gestor)
    perform pg_temp.modo('ligado', false);
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3b fonte do estimador, freio solto: dias = 6 (5 × 1,20), total 12, com vies e vies_fonte = agora',
      v_m ->> 'fonte' in ('orcamento', 'sugerida') and (v_m ->> 'dias')::numeric = 6 and (v_m ->> 'total')::int = 12 and (v_m ->> 'vies')::numeric = 1.2 and v_m ->> 'vies_fonte' = 'agora' and (v_m ->> 'dias_sem_vies')::numeric = 5, v_m::text);
    -- V3b a dupla ligada: o viés sobrevive (R7.5-10)
    update public.agenda_config set modo_dupla = 'ligado' where id;
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2 where service_order_id = v_os;
    insert into public.os_planejamento (service_order_id, dupla_dita, dupla_meios) select v_os, 'inicio', 2 where not exists (select 1 from public.os_planejamento where service_order_id = v_os);
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    -- sem o viés: pme = 10 (5 dias × 2), ni = 2, nf = 0, total = 8. Com o viés: pme = 12 (dp 6 × 2), total = 10
    v_res := pg_temp.ok(v_res, 'V3c dupla ligada: o total conserva o viés (pme 12, total 10; sem o viés seria 10 e 8)',
      (v_m #>> '{dupla,pm_estimativa}')::int = 12 and (v_m ->> 'total')::int = 10 and (v_m ->> 'dias')::numeric = 6 and (v_m ->> 'vies')::numeric = 1.2, v_m::text);
    perform set_config('agenda.sem_vies', 'on', true);
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3c2 a mesma OS sem o viés (agenda.sem_vies): pme 10, total 8, dias 5, sem as chaves',
      (v_m #>> '{dupla,pm_estimativa}')::int = 10 and (v_m ->> 'total')::int = 8 and (v_m ->> 'dias')::numeric = 5 and not v_m ? 'vies', v_m::text);
    perform set_config('agenda.sem_vies', '', true);
    -- o R$ aprendido não entra: as diárias-pessoa da conta da dupla são as do R$ da config × viés (d12), não dp_realista (aprendido) × viés
    update public.agenda_config set aprendizado_ligados = array['fator', 'mo'] where id;
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, estado, calculado_em) values ('mo', 'todas', 'todas', 764, 3, 8, 382, 382, 'em_uso', now())
      on conflict (item, chave) do update set em_uso = 382, calculado = 382, estado = 'em_uso', n = 8;
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3c3 dupla com o R$ aprendido em uso: pme = dp da config × 2 = 12 (não 2 × 10 × 1,20)', (v_m #>> '{dupla,pm_estimativa}')::int = 12, v_m::text);
    update public.agenda_aprendizado set em_uso = null, estado = 'medindo' where item = 'mo';
    update public.agenda_config set modo_dupla = 'sombra' where id;
    update public.os_planejamento set dupla_dita = null, dupla_meios = null where service_order_id = v_os;
    -- V3c a fonte orcamento gravada (OS-00069, R7.5-11): sobre p.dias, não sobre a estimativa (dp 4 daria outro número)
    v_m := public.agenda_meios_da_os(v_gr, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3d orcamento gravado (R7.5-11): 7,5 × 1,20 = 9 (round de 18 ÷ 2), sobre p.dias; dias_sem_vies = 7,5',
      (v_m ->> 'dias')::numeric = 9 and (v_m ->> 'total')::int = 18 and (v_m ->> 'dias_sem_vies')::numeric = 7.5 and v_m ->> 'fonte' = 'orcamento', v_m::text);
    update public.agenda_config set gestor_so_propor = true where id;
    v_m := public.agenda_meios_da_os(v_gr, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3d2 orcamento gravado com o freio (fonte vira sugerida): sem viés, 7,5', (v_m ->> 'dias')::numeric = 7.5 and v_m ->> 'fonte' = 'sugerida', v_m::text);
    -- com o freio, a marcação vale (R7.14: o desligar não apaga a OS marcada)
    update public.os_planejamento set marcado_em = date '2027-01-05', vies_marcado = 1.4, vies_marcado_chave = 'estimativa:rv:energia', tempo_compra_marcado = 1, folga_compra_marcada = 0 where service_order_id = v_gr;
    v_m := public.agenda_meios_da_os(v_gr, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3e a OS marcada guarda o valor com o freio (R7.14): 7,5 × 1,40 = 10,5, vies_fonte = marcado',
      (v_m ->> 'dias')::numeric = 10.5 and v_m ->> 'vies_fonte' = 'marcado', v_m::text);
    update public.agenda_config set gestor_so_propor = false where id;
    -- V3e o marcado vale sobre o de agora
    v_m := public.agenda_meios_da_os(v_gr, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3f o marcado (1,40) vale sobre o de agora (1,20), sem o freio', (v_m ->> 'dias')::numeric = 10.5 and (v_m ->> 'vies')::numeric = 1.4 and v_m ->> 'vies_fonte' = 'marcado', v_m::text);
    -- marcada 1,00: não aplica nada e não tem chave (V4: o publicado não muda)
    insert into public.os_planejamento (service_order_id, marcado_em, vies_marcado, tempo_compra_marcado, folga_compra_marcada) values (v_ped, date '2027-01-05', 1, 1, 0)
    on conflict (service_order_id) do update set marcado_em = excluded.marcado_em, vies_marcado = excluded.vies_marcado, tempo_compra_marcado = excluded.tempo_compra_marcado, folga_compra_marcada = excluded.folga_compra_marcada;
    v_m := public.agenda_meios_da_os(v_ped, c_hoje);
    v_res := pg_temp.ok(v_res, 'V4a OS marcada com 1,00: o total não muda com o viés em uso e a saída não tem chave vies (§3.1-10)', (v_m ->> 'total')::int = 5 and (v_m ->> 'dias')::numeric = 2.5 and not v_m ? 'vies', v_m::text);
    -- o viés de outra conta (dono:) não vale no estimador
    update public.os_planejamento set vies_marcado = 1.5, vies_marcado_chave = 'dono:todas' where service_order_id = v_ped;
    v_m := public.agenda_meios_da_os(v_ped, c_hoje);
    v_res := pg_temp.ok(v_res, 'V4b marcado de outra conta (dono:) não vale nos dias do estimador: vale o de agora (1,20 → 3 dias)', (v_m ->> 'dias')::numeric = 3 and v_m ->> 'vies_fonte' = 'agora', v_m::text);
    -- a fonte orcamento gravada com viés muito baixo (0,30, o mínimo do CHECK): nunca menos de meio dia (0,5 × 0,3 × 2 = 0,3, arredonda a 0)
    update public.agenda_aprendizado set em_uso = 0.30, calculado = 0.30 where item = 'vies' and chave = 'estimativa:rv:energia';
    v_ped := pg_temp.aberta(18, 3056);
    perform pg_temp.dias(v_ped, 0.5, 'orcamento');
    v_m := public.agenda_meios_da_os(v_ped, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3j orcamento gravado com viés muito baixo: o piso de meio dia (0,5), e o número não muda: não é correção (sem chave)', (v_m ->> 'dias')::numeric = 0.5 and not v_m ? 'vies' and not v_m ? 'dias_sem_vies', v_m::text);
    update public.agenda_aprendizado set em_uso = 1.20, calculado = 1.20 where item = 'vies' and chave = 'estimativa:rv:energia';
    v_ped := md5('e7e:v:12')::uuid;
    -- estimador que o arredondamento apaga: 5 × 1,02 = 5,1 → 5
    v_ped := pg_temp.aberta(19, 3820);
    update public.agenda_aprendizado set em_uso = 1.02, calculado = 1.02 where item = 'vies' and chave = 'estimativa:rv:energia';
    v_m := public.agenda_meios_da_os(v_ped, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3k o estimador que o arredondamento apaga (5 × 1,02 = 5): sem vies nem dias_sem_vies (a saída de antes)', (v_m ->> 'dias')::numeric = 5 and not v_m ? 'vies' and not v_m ? 'dias_sem_vies', v_m::text);
    update public.agenda_aprendizado set em_uso = 1.20, calculado = 1.20 where item = 'vies' and chave = 'estimativa:rv:energia';
    v_ped := md5('e7e:v:12')::uuid;
    -- V3g guardas do estimador: sem base (gravada, com marcação diferente de 1) e diagnóstico não têm viés (R7.5-8, R7.5-9), mesmo com o congelado
    v_ped := pg_temp.aberta(16, 0, 'Sem preço');
    perform pg_temp.dias(v_ped, 3, 'orcamento');
    update public.os_planejamento set marcado_em = date '2027-01-05', vies_marcado = 1.5, vies_marcado_chave = 'estimativa:todas', tempo_compra_marcado = 1, folga_compra_marcada = 0 where service_order_id = v_ped;
    v_m := public.agenda_meios_da_os(v_ped, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3h sem base com a marcação ≠ 1: nada (dias 3, sem chave vies): o viés mede o estimador', (v_m ->> 'dias')::numeric = 3 and not v_m ? 'vies', v_m::text);
    v_ped := pg_temp.aberta(17, 3056, 'Instalação de inversor', p_tipo => 'diagnosis');
    perform pg_temp.modo('ligado', true);
    insert into public.os_planejamento (service_order_id, marcado_em, vies_marcado, vies_marcado_chave, tempo_compra_marcado, folga_compra_marcada) values (v_ped, date '2027-01-05', 1.5, 'estimativa:todas', 1, 0);
    v_m := public.agenda_meios_da_os(v_ped, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3i diagnóstico (a régua sem o freio) com a marcação ≠ 1, com o freio: nada (2 pessoas: 2 dias, a conta de antes)', (v_m ->> 'dias')::numeric = 2 and not v_m ? 'vies', v_m::text);
    perform pg_temp.modo('ligado', false);
    update public.agenda_aprendizado set em_uso = 1.20, calculado = 1.20, estado = 'em_uso' where item = 'vies';
    v_ped := md5('e7e:v:12')::uuid;
    -- V5 d12: o R$ aprendido não entra nos dias com o viés
    update public.os_planejamento set vies_marcado = null, vies_marcado_chave = null, marcado_em = null, tempo_compra_marcado = null, folga_compra_marcada = null where service_order_id = v_ped;
    update public.agenda_config set aprendizado_ligados = array['fator', 'mo'] where id;
    update public.agenda_aprendizado set em_uso = 382, calculado = 382, estado = 'em_uso' where item = 'mo';
    v_m := public.agenda_meios_da_os(v_ped, c_hoje);
    v_res := pg_temp.ok(v_res, 'V5a d12: dias com viés pelo R$ da config (2,5 × 1,2 = 3), não pelo aprendido (5 × 1,2 = 6)', (v_m ->> 'dias')::numeric = 3, v_m::text);
    update public.agenda_aprendizado set em_uso = null, estado = 'medindo' where item = 'mo';
    -- V3 sem viés em uso: nada
    update public.agenda_aprendizado set em_uso = null, estado = 'medindo' where item = 'vies';
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V3g sem viés em uso (nada ainda): dias 5, sem chave', (v_m ->> 'dias')::numeric = 5 and not v_m ? 'vies', v_m::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v3$;

-- ── V4b e §8.2 "Marcação": a rodada congela 1,00 antes de aprender; o viés muda e o total da OS marcada não ─────────
do $v4$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_os uuid;
  v_antes jsonb;
  v_m jsonb;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V4 a marcação', true, 'PULADO: sem a fixture'));
    return;
  end if;
  begin
    perform pg_temp.modo('ligado', false);
    update public.agenda_config set aprendizado_ligados = array['fator', 'mo'] where id;
    v_os := pg_temp.aberta(21, 3820);
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_os, pg_temp.caio(), date '2027-01-08', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2027-01-05 16:30-03');
    v_antes := public.agenda_meios_da_os(v_os, c_hoje);
    perform public._agenda_aprender_congelar_marcacao(c_hoje);
    v_res := pg_temp.ok(v_res, 'V4c a marcação congela 1,00 quando nada estava em uso', (select vies_marcado = 1 and marcado_em = date '2027-01-05' from public.os_planejamento where service_order_id = v_os), null);
    perform pg_temp.vies('estimativa:rv:energia', 1.17);
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V4d o viés vira 1,17 e o total da OS marcada não muda (§8.2 "Marcação")', (v_m ->> 'total')::int = (v_antes ->> 'total')::int and not v_m ? 'vies', v_m::text);
    -- e uma não marcada, com o mesmo viés, muda
    v_os := pg_temp.aberta(22, 3820);
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V4e a mesma conta numa OS não marcada muda (5 × 1,17 = 5,85 → 6)', (v_m ->> 'dias')::numeric = 6, v_m::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v4$;

-- ── V7. O dono (AG7-33) ────────────────────────────────────────────────────────────────────────────
do $v7$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  c_agora constant timestamptz := timestamptz '2027-01-07 10:00-03';
  v_os uuid;
  v_m  jsonb;
  v_r  jsonb;
  v_pl public.os_planejamento;
  v_prim numeric;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V7 o dono', true, 'PULADO: sem a fixture'));
    return;
  end if;
  begin
    perform pg_temp.modo('ligado', false);
    perform set_config('agenda.hoje', c_hoje::text, true);
    perform set_config('agenda.agora', c_agora::text, true);
    perform pg_temp.vies('dono:todas', 1.20, 5);
    v_os := pg_temp.aberta(31, 3820);
    perform pg_temp.dias(v_os, 3, 'dono');
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7a os 2 números: dias 3 × 1,2 = 3,5 (round de 7,2 ÷ 2), dias_dono 3, fonte dono, com o texto "Você disse 3 dias; contei 3,5 (nos serviços assim, os seus dias levaram 1,2×; 5 OS)."',
      (v_m ->> 'dias')::numeric = 3.5 and (v_m ->> 'dias_dono')::numeric = 3 and (v_m ->> 'total')::int = 7 and v_m ->> 'fonte' = 'dono'
      and v_m ->> 'texto_vies' = 'Você disse 3 dias; contei 3,5 (nos serviços assim, os seus dias levaram 1,2×; 5 OS).', v_m::text);
    -- a aceita também
    update public.os_planejamento set estimativa_fonte = 'aceita' where service_order_id = v_os;
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7b fonte aceita corrige igual, e o texto não diz que ele disse: "Você aceitou 3 dias; contei 3,5"', (v_m ->> 'dias')::numeric = 3.5 and v_m ->> 'texto_vies' like 'Você aceitou 3 dias; contei 3,5 (%', v_m ->> 'texto_vies');
    update public.os_planejamento set estimativa_fonte = 'dono' where service_order_id = v_os;
    -- a dupla dita fica intacta (a correção só muda os dias)
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2 where service_order_id = v_os;
    update public.agenda_config set modo_dupla = 'ligado' where id;
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7c a dupla dita intacta (R7.3-2): dias 3,5, total 7, ni 2, nf 0 (dita), dupla_dita igual',
      (v_m ->> 'total')::int = 7 and (v_m #>> '{dupla,ni}')::int = 2 and (v_m #>> '{dupla,nf}')::int = 0
      and (select dupla_dita = 'inicio' and dupla_meios = 2 from public.os_planejamento where service_order_id = v_os), v_m::text);
    update public.os_planejamento set dupla_dita = null, dupla_meios = null where service_order_id = v_os;
    update public.agenda_config set modo_dupla = 'sombra' where id;
    -- freio: sem correção; vies_corrige_dono falso: sem correção
    update public.agenda_config set gestor_so_propor = true where id;
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7d com o freio ligado: sem correção (dias 3, sem chaves)', (v_m ->> 'dias')::numeric = 3 and not v_m ? 'dias_dono', v_m::text);
    update public.agenda_config set gestor_so_propor = false, vies_corrige_dono = false where id;
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7e vies_corrige_dono falso: sem correção', (v_m ->> 'dias')::numeric = 3 and not v_m ? 'dias_dono', v_m::text);
    update public.agenda_config set vies_corrige_dono = true where id;
    -- o rascunho do dono repete os dias (a frase até o *grava*): a saída
    perform public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', v_os::text, '{"dias": 3}'::jsonb, 'são 3 dias mesmo', c_hoje);
    v_r := public.agenda_rascunho_gravar(pg_temp.adm(), c_hoje);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V7f repetir os dias depois de ver a correção, da frase ao *grava*: vies_dono_fixo, vies_marcado 1,00, marcado_em e o que a marcação congelaria',
      coalesce((v_r ->> 'ok')::boolean, false) and v_pl.vies_dono_fixo and v_pl.vies_marcado = 1 and v_pl.vies_marcado_chave is null and v_pl.marcado_em = c_hoje and v_pl.tempo_compra_marcado is not null and v_pl.folga_compra_marcada = 0 and v_pl.dias = 3,
      format('%s | fixo=%s m=%s em=%s t=%s', v_r, v_pl.vies_dono_fixo, v_pl.vies_marcado, v_pl.marcado_em, v_pl.tempo_compra_marcado));
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7g depois da saída: vale o número dele (3), sem correção e sem o texto', (v_m ->> 'dias')::numeric = 3 and not v_m ? 'vies', v_m::text);
    -- o histórico guarda o antes e o depois
    v_res := pg_temp.ok(v_res, 'V7h o histórico registra a saída (antes e depois de vies_dono_fixo)',
      exists (select 1 from jsonb_array_elements(v_pl.historico) h where h #>> '{depois,vies_dono_fixo}' = 'true' and h #>> '{antes,vies_dono_fixo}' = 'false'), v_pl.historico::text);
    -- sobrevive ao passo 2 (a OS voltou à fila sem compromisso vigente: a soltura não apaga a saída)
    perform public._agenda_aprender_congelar_marcacao(c_hoje);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V7i sobrevive ao passo 2 da marcação (soltar da fila): vies_dono_fixo, vies_marcado e marcado_em continuam',
      v_pl.vies_dono_fixo and v_pl.vies_marcado = 1 and v_pl.marcado_em = c_hoje, format('fixo=%s m=%s em=%s', v_pl.vies_dono_fixo, v_pl.vies_marcado, v_pl.marcado_em));
    -- dizer o número corrigido que eu mostrei também é a saída; v_old.dias = 3, ele diz 3,5
    v_os := pg_temp.aberta(32, 3820);
    perform pg_temp.dias(v_os, 3, 'dono');
    perform public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', v_os::text, '{"dias": 3.5}'::jsonb, 'pode ser 3,5 dias', c_hoje);
    v_r := public.agenda_rascunho_gravar(pg_temp.adm(), c_hoje);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7j dizer o corrigido (3,5) também é a saída: grava 3,5 e não corrige mais (senão 3,5 × 1,2 = 4 viraria 4)',
      v_pl.vies_dono_fixo and v_pl.dias = 3.5 and (v_m ->> 'dias')::numeric = 3.5 and not v_m ? 'vies', format('%s | fixo=%s dias=%s %s', v_r, v_pl.vies_dono_fixo, v_pl.dias, v_m));
    -- um número novo não é a saída
    v_os := pg_temp.aberta(33, 3820);
    perform pg_temp.dias(v_os, 3, 'dono');
    perform public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', v_os::text, '{"dias": 5}'::jsonb, 'são 5 dias', c_hoje);
    v_r := public.agenda_rascunho_gravar(pg_temp.adm(), c_hoje);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V7k um número novo não é a saída: grava 5, continua corrigindo (6)', not v_pl.vies_dono_fixo and v_pl.dias = 5 and (public.agenda_meios_da_os(v_os, c_hoje) ->> 'dias')::numeric = 6, format('%s fixo=%s', v_r, v_pl.vies_dono_fixo));
    -- os_planejar_pela_tela, repetir, mesma saída
    v_os := pg_temp.aberta(34, 3820);
    perform pg_temp.dias(v_os, 3, 'dono');
    perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.adm(), 'role', 'authenticated')::text, true);
    perform public.os_planejar_pela_tela(v_os, 3, c_hoje);
    perform set_config('request.jwt.claims', '', true);
    v_res := pg_temp.ok(v_res, 'V7l pela tela, repetir a duração: a mesma saída', (select vies_dono_fixo from public.os_planejamento where service_order_id = v_os), null);
    -- acima do máximo não corrige
    update public.agenda_config set estimativa_max_diarias = 3 where id;
    v_os := pg_temp.aberta(35, 3820);
    perform pg_temp.dias(v_os, 3, 'dono');
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7m acima de estimativa_max_diarias (3 × 1,2 = 3,5 > 3): a correção não entra; vale o número dele e o texto diz os dois',
      (v_m ->> 'dias')::numeric = 3 and coalesce((v_m ->> 'vies_acima_max')::boolean, false) and (v_m ->> 'dias_corrigidos')::numeric = 3.5
      and v_m ->> 'texto_vies' like 'Você disse 3 dias; pelo histórico dos seus dias seriam 3,5 dias (%' and v_m ->> 'texto_vies' like '%fico com o seu número.', v_m::text);
    -- repetir acima do máximo não é saída (nem há o que recusar)
    perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.adm(), 'role', 'authenticated')::text, true);
    perform public.os_planejar_pela_tela(v_os, 3, c_hoje);
    perform set_config('request.jwt.claims', '', true);
    v_res := pg_temp.ok(v_res, 'V7n acima do máximo, repetir não marca a saída (não há correção a recusar)', not (select vies_dono_fixo from public.os_planejamento where service_order_id = v_os), null);
    update public.agenda_config set estimativa_max_diarias = 20 where id;
    -- o piso dos dias do dono, com o viés no mínimo do CHECK (0,30): nunca menos de meio dia
    perform pg_temp.vies('dono:todas', 0.30, 5);
    v_os := pg_temp.aberta(39, 3820);
    perform pg_temp.dias(v_os, 0.5, 'dono');
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7t o piso dos dias do dono (0,5 × 0,3 = 0,15 → meio dia): o número não muda, sem correção', (v_m ->> 'dias')::numeric = 0.5 and not v_m ? 'dias_dono' and not v_m ? 'vies', v_m::text);
    perform pg_temp.vies('dono:todas', 1.20, 5);
    -- sem correção em uso, repetir não é a saída: não há o que recusar
    v_os := pg_temp.aberta(40, 3820);
    perform pg_temp.dias(v_os, 3, 'dono');
    update public.agenda_config set modo_vies = 'sombra' where id;
    perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.adm(), 'role', 'authenticated')::text, true);
    perform public.os_planejar_pela_tela(v_os, 3, c_hoje);
    perform set_config('request.jwt.claims', '', true);
    v_res := pg_temp.ok(v_res, 'V7u sem correção em uso (modo em teste), repetir os dias não marca a saída', not (select vies_dono_fixo from public.os_planejamento where service_order_id = v_os), null);
    update public.agenda_config set modo_vies = 'ligado' where id;
    -- com marcação feita antes, a saída guarda o dia da marcação e a chave (a conta do dono) vai para o histórico
    v_os := pg_temp.aberta(43, 3820);
    perform pg_temp.dias(v_os, 3, 'dono');
    update public.os_planejamento set marcado_em = date '2027-01-05', vies_marcado = 1.4, vies_marcado_chave = 'dono:todas', tempo_compra_marcado = 1, folga_compra_marcada = 0 where service_order_id = v_os;
    perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.adm(), 'role', 'authenticated')::text, true);
    perform public.os_planejar_pela_tela(v_os, 3, c_hoje);
    perform set_config('request.jwt.claims', '', true);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V7v a OS já marcada: a saída guarda o dia da marcação (05/01, não hoje), zera a chave e o congelado vira 1,00',
      v_pl.vies_dono_fixo and v_pl.marcado_em = date '2027-01-05' and v_pl.vies_marcado = 1 and v_pl.vies_marcado_chave is null,
      format('em=%s m=%s c=%s', v_pl.marcado_em, v_pl.vies_marcado, v_pl.vies_marcado_chave));
    v_res := pg_temp.ok(v_res, 'V7w o histórico guarda a chave que saiu (a conta do dono volta a 1,00 às claras)',
      exists (select 1 from jsonb_array_elements(v_pl.historico) h where h #>> '{antes,vies_marcado_chave}' = 'dono:todas' and h -> 'depois' ? 'vies_marcado_chave' and h #>> '{depois,vies_marcado_chave}' is null and (h #>> '{antes,vies_marcado}')::numeric = 1.4 and (h #>> '{depois,vies_marcado}')::numeric = 1), v_pl.historico::text);
    -- as diárias da correção: com 2 pessoas, conta dias × pessoas (R7.3-2: "diárias")
    v_os := pg_temp.aberta(38, 3820);
    perform pg_temp.dias(v_os, 3, 'dono');
    update public.os_planejamento set dupla_dita = 'todos' where service_order_id = v_os;
    update public.agenda_config set estimativa_max_diarias = 5, equipe_sugerida = 2 where id;
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7r 2 pessoas: 3,5 × 2 = 7 diárias > 5 = acima do máximo (a conta é por diárias, não por dias)',
      coalesce((v_m ->> 'vies_acima_max')::boolean, false) and (v_m ->> 'dias')::numeric = 3, v_m::text);
    update public.agenda_config set estimativa_max_diarias = 20, equipe_sugerida = 2 where id;
    update public.os_planejamento set dupla_dita = null where service_order_id = v_os;
    -- a fonte aceita não vira a saída (só o que ele disse como dono)
    perform public._agenda_aplicar_planejar(pg_temp.adm(), v_os, '{"dias": 3, "estimativa_fonte": "aceita"}'::jsonb, 'aceito a estimativa', c_hoje);
    v_res := pg_temp.ok(v_res, 'V7s repetir pela fonte aceita não marca a saída (só o que ele diz como dono)', not (select vies_dono_fixo from public.os_planejamento where service_order_id = v_os), null);
    -- Correção que o arredondamento apaga não é correção (defeito 3 da conferência): 3 × 1,02 = 3
    perform pg_temp.vies('dono:todas', 1.02, 5);
    v_os := pg_temp.aberta(44, 3820);
    perform pg_temp.dias(v_os, 3, 'dono');
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7x dono disse 3, viés 1,02: 3 continua; sem dias_dono, sem texto, sem vies (a saída de antes)', (v_m ->> 'dias')::numeric = 3 and not v_m ? 'dias_dono' and not v_m ? 'texto_vies' and not v_m ? 'vies', v_m::text);
    perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.adm(), 'role', 'authenticated')::text, true);
    perform public.os_planejar_pela_tela(v_os, 3, c_hoje);
    perform set_config('request.jwt.claims', '', true);
    v_res := pg_temp.ok(v_res, 'V7y repetir o 3 sem correção nenhuma não grava a saída nem congela a compra',
      (select not vies_dono_fixo and marcado_em is null and tempo_compra_marcado is null and vies_marcado is null from public.os_planejamento where service_order_id = v_os), null);
    update public.agenda_config set estimativa_max_diarias = 2 where id;
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7z acima do máximo com o arredondamento apagando: nada a dizer (sem vies_acima_max nem texto)', not v_m ? 'vies_acima_max' and not v_m ? 'texto_vies', v_m::text);
    update public.agenda_config set estimativa_max_diarias = 20 where id;
    -- acima do máximo numa aceita: o verbo certo
    perform pg_temp.vies('dono:todas', 1.20, 5);
    update public.agenda_config set estimativa_max_diarias = 3 where id;
    v_os := pg_temp.aberta(45, 3820);
    perform pg_temp.dias(v_os, 3, 'aceita');
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7z2 aceita acima do máximo: "Você aceitou", nunca "Você disse"', v_m ->> 'texto_vies' like 'Você aceitou 3 dias; pelo histórico%', v_m ->> 'texto_vies');
    update public.agenda_config set estimativa_max_diarias = 20 where id;
    -- a classe do dono: a fina vence a geral
    perform pg_temp.vies('dono:rv:energia', 1.5, 3);
    v_os := pg_temp.aberta(36, 3820);
    perform pg_temp.dias(v_os, 4, 'dono');
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7o a chave fina do dono vence a geral (dono:rv:energia 1,5; 3 OS): 4 × 1,5 = 6', (v_m ->> 'dias')::numeric = 6 and v_m ->> 'texto_vies' like '%levaram 1,5×; 3 OS).', v_m::text);
    -- marcação de OS com dias do dono usa a chave dono:
    v_os := pg_temp.aberta(37, 3820);
    perform pg_temp.dias(v_os, 4, 'dono');
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_os, pg_temp.caio(), date '2027-01-11', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2027-01-06 16:30-03');
    perform public._agenda_aprender_congelar_marcacao(c_hoje);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V7p a marcação de OS com dias do dono congela pela chave dono: (1,5, dono:rv:energia), não pela do estimador',
      v_pl.vies_marcado = 1.5 and v_pl.vies_marcado_chave = 'dono:rv:energia', format('m=%s c=%s', v_pl.vies_marcado, v_pl.vies_marcado_chave));
    -- e depois de marcada, a chave aprendida mudar não muda os dias
    perform pg_temp.vies('dono:rv:energia', 1.8, 9);
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V7q marcada: o dono: novo (1,8) não muda os dias, e o texto diz o congelado (1,5)', (v_m ->> 'dias')::numeric = 6 and v_m ->> 'vies_fonte' = 'marcado' and v_m ->> 'texto_vies' like '%levaram 1,5×; 9 OS).', v_m::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v7$;

-- ── V8. A armadilha da medida ─────────────────────────────────────────────────────────────────────
do $v8$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_oss uuid[];
  v_os uuid;
  r record;
  v_foto jsonb;
  v_base jsonb;
  v_prev text;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V8 a medida', true, 'PULADO: sem a fixture'));
    return;
  end if;
  -- A OS do dono (5 dias ditos, 10 meios), uma com a estimativa e uma com a marcação; concluídas, para medir
  perform set_config('agenda.hoje', c_hoje::text, true);
  for r in select * from (values
      ('sem viés, com freio', 'sombra', true, null::numeric),
      ('sem viés, freio solto', 'ligado', false, null::numeric),
      ('viés em uso, freio solto', 'ligado', false, 1.30),
      ('viés em uso, com freio', 'ligado', true, 1.30),
      ('vies_marcado 1,40, com freio', 'sombra', true, 1.40)) t(nome, modo, freio, valor)
  loop
    begin
      perform pg_temp.modo(r.modo, r.freio);
      if r.valor = 1.30 then
        perform pg_temp.vies('estimativa:rv:energia', 1.30);
        perform pg_temp.vies('dono:todas', 1.30);
      end if;
      -- 2 OS concluídas novas, com a mesma forma: a do dono (5 dias) e a pela estimativa (3 dias de mão de obra)
      v_os := md5('e7e:v8:dono')::uuid;
      perform set_config('agenda.porta', 'on', true);
      insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, check_in_at, check_out_at, delivered_at, grand_total)
      values (v_os, 'OS-7EV801', 'e7e00000-0000-4000-8000-000000000c02', 'e7e00000-0000-4000-8000-000000000b02', 'completed', 'approved', 'repair',
              timestamptz '2026-11-01 10:00-03', timestamptz '2026-12-15 10:00-03', timestamptz '2026-11-02 10:00-03', timestamptz '2026-12-07 08:00-03', timestamptz '2026-12-11 17:00-03', timestamptz '2026-12-12 10:00-03', 3820);
      insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
      values (v_os, 'Instalação de inversor e baterias', 'visit', 1, 3820, 3820, timestamptz '2026-11-01 10:00-03');
      perform set_config('agenda.porta', 'off', true);
      insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, atualizado_em) values (v_os, 5, 'dono', timestamptz '2026-11-20 10:00-03', timestamptz '2026-11-20 10:00-03');
      if r.valor = 1.40 then
        update public.os_planejamento set marcado_em = date '2026-12-05', vies_marcado = 1.40, vies_marcado_chave = 'dono:todas', tempo_compra_marcado = 1, folga_compra_marcada = 0 where service_order_id = v_os;
      end if;
      insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, resultado, resultado_via, resultado_em)
      select v_os, 'e7e00000-0000-4000-8000-00000000aa02'::uuid, d::date, t, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-12-06 16:30-03', 'cumprido', 'dia_feito', (d::date + time '17:30') at time zone 'America/Sao_Paulo'
        from generate_series(date '2026-12-07', date '2026-12-11', interval '1 day') d, unnest(array['manha', 'tarde']) t;
      perform public._agenda_aprender_congelar(c_hoje);
      perform public.agenda_medir_os(v_os, c_hoje);
      select jsonb_build_object('pm_plano', pl.pm_plano_no_inicio, 'pessoas', pl.pessoas_no_inicio, 'dp', pl.dp_bruto_no_inicio, 'pm_est', m.pm_estimados, 'pm_dono', m.pm_plano_dono, 'razao_dono', m.razao_dono)
        into v_foto
        from public.os_planejamento pl join public.agenda_medidas_os m on m.service_order_id = pl.service_order_id where pl.service_order_id = v_os;
      if v_base is null then
        v_base := v_foto;
        v_res := pg_temp.ok(v_res, 'V8a a base (sem viés nenhum): pm_plano 10, dp bruto 5, pm_estimados 10, pm_plano_dono 10, razao_dono 1',
          (v_foto ->> 'pm_plano')::numeric = 10 and (v_foto ->> 'dp')::numeric = 5 and (v_foto ->> 'pm_est')::numeric = 10 and (v_foto ->> 'pm_dono')::numeric = 10 and (v_foto ->> 'razao_dono')::numeric = 1, v_foto::text);
      else
        v_res := pg_temp.ok(v_res, 'V8b ' || r.nome || ': pm_plano, pessoas, dp bruto, pm_estimados, pm_plano_dono e razao_dono iguais à base (a medida não lê o viés)', v_foto = v_base, v_foto::text || ' // base ' || v_base::text);
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- a OS aprovada com o viés (dias sem o viés, o aprovado à parte): pm_plano e razao_dono medem o número sem o viés
  begin
    perform pg_temp.modo('ligado', false);
    v_os := md5('e7e:v8:ap')::uuid;
    perform set_config('agenda.porta', 'on', true);
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, check_in_at, check_out_at, delivered_at, grand_total)
    values (v_os, 'OS-7EV802', 'e7e00000-0000-4000-8000-000000000c02', 'e7e00000-0000-4000-8000-000000000b02', 'completed', 'approved', 'repair',
            timestamptz '2026-11-01 10:00-03', timestamptz '2026-12-15 10:00-03', timestamptz '2026-11-02 10:00-03', timestamptz '2026-12-07 08:00-03', timestamptz '2026-12-11 17:00-03', timestamptz '2026-12-12 10:00-03', 3820);
    insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
    values (v_os, 'Instalação de inversor e baterias', 'visit', 1, 3820, 3820, timestamptz '2026-11-01 10:00-03');
    perform set_config('agenda.porta', 'off', true);
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, atualizado_em, aprovado_com_vies)
    values (v_os, 5, 'aceita', timestamptz '2026-11-20 10:00-03', timestamptz '2026-11-20 10:00-03', jsonb_build_object('dias', 6, 'total', 12, 'vies', 1.2, 'em', date '2026-11-20'));
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, resultado, resultado_via, resultado_em)
    select v_os, 'e7e00000-0000-4000-8000-00000000aa02'::uuid, d::date, t, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-12-06 16:30-03', 'cumprido', 'dia_feito', (d::date + time '17:30') at time zone 'America/Sao_Paulo'
      from generate_series(date '2026-12-07', date '2026-12-11', interval '1 day') d, unnest(array['manha', 'tarde']) t;
    perform public._agenda_aprender_congelar(c_hoje);
    perform public.agenda_medir_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V8f aprovada com o viés: o plano lê 6 dias, a medida lê 5 (pm_plano 10, pm_plano_dono 10, razao_dono = 10 ÷ 10, sem o 12 do aprovado)',
      (select (public.agenda_meios_da_os(v_os, c_hoje) ->> 'total')::int = 12 and pl.pm_plano_no_inicio = 10 and m.pm_plano_dono = 10 and m.razao_dono = 1 and m.dias_no_inicio = 5
         from public.os_planejamento pl join public.agenda_medidas_os m on m.service_order_id = pl.service_order_id where pl.service_order_id = v_os),
      (select format('pm_plano=%s pm_dono=%s razao=%s dias_inicio=%s', pl.pm_plano_no_inicio, m.pm_plano_dono, m.razao_dono, m.dias_no_inicio) from public.os_planejamento pl join public.agenda_medidas_os m on m.service_order_id = pl.service_order_id where pl.service_order_id = v_os));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- agenda.sem_vies volta ao valor de antes (com valor, vazio, e depois de erro numa OS do laço)
  begin
    perform pg_temp.modo('ligado', false);
    v_os := pg_temp.aberta(41, 1910, p_status => 'completed');
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set check_in_at = timestamptz '2026-12-07 08:00-03', check_out_at = timestamptz '2026-12-07 17:00-03', delivered_at = timestamptz '2026-12-08 10:00-03' where id = v_os;
    perform set_config('agenda.porta', 'off', true);
    perform set_config('agenda.sem_vies', 'xpto', true);
    perform public._agenda_aprender_congelar(c_hoje);
    v_res := pg_temp.ok(v_res, 'V8c agenda.sem_vies volta ao valor de antes (xpto) depois do congelar', current_setting('agenda.sem_vies') = 'xpto', current_setting('agenda.sem_vies'));
    perform set_config('agenda.sem_vies', '', true);
    perform public._agenda_aprender_congelar(c_hoje);
    v_res := pg_temp.ok(v_res, 'V8d volta vazio', current_setting('agenda.sem_vies') = '', current_setting('agenda.sem_vies'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v_os := pg_temp.aberta(42, 1910, p_status => 'completed');
    perform set_config('agenda.porta', 'on', true);
    update public.service_orders set check_in_at = timestamptz '2026-12-07 08:00-03', check_out_at = timestamptz '2026-12-07 17:00-03', delivered_at = timestamptz '2026-12-08 10:00-03' where id = v_os;
    perform set_config('agenda.porta', 'off', true);
    execute format($f$create or replace function public._agenda_margem_dono_e_pessoa(p_os uuid) returns boolean language plpgsql stable set search_path to 'public' as $g$
      begin if p_os = %L then raise exception 'erro de propósito'; end if; return false; end $g$;$f$, v_os);
    perform set_config('agenda.sem_vies', 'antes', true);
    perform public._agenda_aprender_congelar(c_hoje);
    v_res := pg_temp.ok(v_res, 'V8e erro numa OS do laço: agenda.sem_vies volta pelo rollback do bloco, e a seguinte não herda "on"', current_setting('agenda.sem_vies') = 'antes', current_setting('agenda.sem_vies'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v8$;

-- ── V9. agenda_aplicar: a duração aprovada ──────────────────────────────────────────────────────────
do $v9$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  v_os uuid;
  v_r jsonb;
  v_m jsonb;
  v_pl public.os_planejamento;
  r record;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V9 aplicar', true, 'PULADO: sem a fixture'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  -- Sem correção aplicada, grava o número do item, como antes: sombra, desligado, viés que o arredondamento apaga, item já sem o viés. A proposta pode ser velha: o item (7) é o aprovado, a estimativa de agora (5) não manda
  for r in select * from (values ('desligado', true, 7::numeric, 'V9a desligado, item antigo'), ('sombra', true, 7, 'V9b sombra, item antigo'), ('ligado', true, 7, 'V9c ligado com o freio (efetivo sombra), item antigo')) x(modo, freio, item, nome) loop
    begin
      perform pg_temp.modo(r.modo, r.freio);
      update public.agenda_config set modo_proposta = 'ligado', marcar_regras = array_remove(marcar_regras, 'estimativa') where id;
      perform pg_temp.vies('estimativa:rv:energia', 1.20);
      v_os := pg_temp.aberta(51, 3820);   -- estimativa de agora: 5 dias
      v_r := pg_temp.aprova(v_os, r.item);
      select * into v_pl from public.os_planejamento where service_order_id = v_os;
      v_res := pg_temp.ok(v_res, r.nome || ': grava o número do item (7), como antes do P3, e não guarda aprovado',
        coalesce((v_r ->> 'ok')::boolean, false) and v_pl.dias = 7 and v_pl.estimativa_fonte = 'aceita' and v_pl.aprovado_com_vies is null, format('%s | dias=%s', v_r, v_pl.dias));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  begin
    perform pg_temp.modo('ligado', false);
    update public.agenda_config set modo_proposta = 'ligado', marcar_regras = array_remove(marcar_regras, 'estimativa') where id;
    perform pg_temp.vies('estimativa:rv:energia', 1.02);
    v_os := pg_temp.aberta(52, 3820);   -- 5 × 1,02 = 5: o arredondamento apaga
    v_r := pg_temp.aprova(v_os, 5);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V9d correção que o arredondamento apaga: grava o item, sem aprovado', v_pl.dias = 5 and v_pl.aprovado_com_vies is null, format('dias=%s ap=%s', v_pl.dias, v_pl.aprovado_com_vies));
    -- o item já sem o viés (a proposta é de antes de o viés entrar em uso)
    perform pg_temp.vies('estimativa:rv:energia', 1.20);
    v_os := pg_temp.aberta(53, 3820);
    v_r := pg_temp.aprova(v_os, 5);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V9e item já sem o viés, viés em uso agora: grava o item (5), sem aprovado', v_pl.dias = 5 and v_pl.aprovado_com_vies is null, format('dias=%s ap=%s', v_pl.dias, v_pl.aprovado_com_vies));
    -- com correção aplicada de fato: dois números, com as alocações de verdade
    v_os := pg_temp.aberta(54, 3820);   -- 5 sem o viés, 6 com: 12 meios-dias
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_r := pg_temp.aprova(v_os, (v_m ->> 'dias')::numeric);
    perform pg_temp.publica(v_os, (v_m ->> 'total')::int);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V9f aprovada com o viés: dias 5 (sem o viés, a medida), aceita, e o aprovado guarda 6 dias, total 12, viés 1,2',
      coalesce((v_r ->> 'ok')::boolean, false) and v_pl.dias = 5 and v_pl.estimativa_fonte = 'aceita'
      and (v_pl.aprovado_com_vies ->> 'dias')::numeric = 6 and (v_pl.aprovado_com_vies ->> 'total')::int = 12 and (v_pl.aprovado_com_vies ->> 'vies')::numeric = 1.2,
      format('%s | dias=%s ap=%s', v_r, v_pl.dias, v_pl.aprovado_com_vies));
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V9g lido depois de aprovar: dias 6, total 12, fonte aceita, 12 vigentes, nada a marcar nem a sobrar; vies_fonte aprovado, dias_sem_vies 5, sem "Você disse"',
      (v_m ->> 'dias')::numeric = 6 and (v_m ->> 'total')::int = 12 and v_m ->> 'fonte' = 'aceita' and (v_m ->> 'vigentes')::int = 12 and (v_m ->> 'restantes')::numeric = 0
      and v_m ->> 'vies_fonte' = 'aprovado' and (v_m ->> 'dias_sem_vies')::numeric = 5 and not v_m ? 'dias_dono' and not v_m ? 'texto_vies' and jsonb_array_length(v_m -> 'molde') = 12, v_m::text);
    -- a marcação e a rodada seguinte não mexem no que foi aprovado
    perform public._agenda_aprender_congelar_marcacao(c_hoje);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V9h depois da marcação: dias 6, total 12, e a marcação da aprovada é da conta do estimador (estimativa:rv:energia, 1,20), não dono:',
      (v_m ->> 'dias')::numeric = 6 and (v_m ->> 'total')::int = 12 and v_pl.vies_marcado = 1.2 and v_pl.vies_marcado_chave = 'estimativa:rv:energia', format('%s | %s %s', v_m ->> 'total', v_pl.vies_marcado, v_pl.vies_marcado_chave));
    perform pg_temp.vies('estimativa:rv:energia', 1.40);
    perform pg_temp.vies('dono:todas', 1.50, 7);
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V9i o viés muda (1,40) e o dono: entra (1,50): não muda nem empilha, vale o aprovado (6 dias, total 12)',
      (v_m ->> 'dias')::numeric = 6 and (v_m ->> 'total')::int = 12 and not v_m ? 'dias_dono', v_m::text);
    -- com o freio de volta, o aprovado segue
    perform pg_temp.modo('ligado', true);
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V9j o freio de volta não mexe no que foi aprovado (6 dias, total 12; o P7 diz no cartão)', (v_m ->> 'dias')::numeric = 6 and (v_m ->> 'total')::int = 12, v_m::text);
    perform set_config('agenda.sem_vies', 'on', true);
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V9k o que a medida lê (agenda.sem_vies): 5 dias, total 10, sem chave', (v_m ->> 'dias')::numeric = 5 and (v_m ->> 'total')::int = 10 and not v_m ? 'vies_fonte', v_m::text);
    perform set_config('agenda.sem_vies', '', true);
    perform pg_temp.modo('ligado', false);
    -- o dono diz os dias de novo: o aprovado sai e o histórico guarda
    perform public._agenda_aplicar_planejar(pg_temp.adm(), v_os, '{"dias": 4, "estimativa_fonte": "dono"}'::jsonb, 'são 4 dias', c_hoje);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V9l o dono diz os dias de novo: vale o que ele disse, o aprovado sai e o histórico guarda o de antes',
      v_pl.dias = 4 and v_pl.estimativa_fonte = 'dono' and v_pl.aprovado_com_vies is null
      and exists (select 1 from jsonb_array_elements(v_pl.historico) h where (h #>> '{antes,aprovado_com_vies,dias}')::numeric = 6), v_pl.historico::text);
    -- o aprovado só vale na fonte aceita (reestimar a OS para orçamento não pode ler o aprovado antigo)
    v_os := pg_temp.aberta(57, 3820);
    perform pg_temp.dias(v_os, 4, 'orcamento');
    update public.os_planejamento set aprovado_com_vies = jsonb_build_object('dias', 6, 'total', 12, 'vies', 1.2, 'em', c_hoje) where service_order_id = v_os;
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V9o fonte orcamento com aprovado antigo: lê os dias dela (4 × 1,4 = 5,6 → 5,5), sem o aprovado', (v_m ->> 'dias')::numeric = 5.5 and v_m ->> 'vies_fonte' <> 'aprovado', v_m::text);
    -- a aceita antiga (dias já ditos antes, não desta aprovação): o aprovado não entra nela
    v_os := pg_temp.aberta(58, 3820);
    perform pg_temp.dias(v_os, 4, 'aceita');
    v_r := pg_temp.aprova(v_os, 6);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V9p a OS que já tinha dias aceitos não muda ao ser aprovada de novo: dias 4 e sem aprovado', v_pl.dias = 4 and v_pl.aprovado_com_vies is null, format('dias=%s ap=%s', v_pl.dias, v_pl.aprovado_com_vies));
    -- o orçamento gravado (fonte orcamento, sem a regra estimativa lê como sugerida) não vira aceita nem aprovado ao ser aprovado: o item é da fila e a linha já tem dias
    v_os := pg_temp.aberta(61, 3820);
    perform pg_temp.dias(v_os, 4, 'orcamento');
    v_r := pg_temp.aprova(v_os, 6);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V9q fonte orcamento gravada, item sugerida: dias 4 e sem aprovado (a linha já tinha dias)', v_pl.dias = 4 and v_pl.estimativa_fonte = 'orcamento' and v_pl.aprovado_com_vies is null, format('dias=%s fonte=%s ap=%s', v_pl.dias, v_pl.estimativa_fonte, v_pl.aprovado_com_vies));
    -- a proposta velha, com a estimativa andando: dias do item, total pelo que ela tem (sem a conta da dupla)
    perform pg_temp.vies('estimativa:rv:energia', 1.20);
    v_os := pg_temp.aberta(55, 3820);
    v_r := pg_temp.aprova(v_os, 7);
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_res := pg_temp.ok(v_res, 'V9m proposta velha (item 7, agora 6): o aprovado é o item (7 dias, total 14), dias 5 sem o viés',
      v_pl.dias = 5 and (v_pl.aprovado_com_vies ->> 'dias')::numeric = 7 and (v_pl.aprovado_com_vies ->> 'total')::int = 14, v_pl.aprovado_com_vies::text);
    -- com a dupla ligada: o total publicado não é dias × 2
    update public.agenda_config set modo_dupla = 'ligado' where id;
    v_os := pg_temp.aberta(56, 3820);
    insert into public.os_planejamento (service_order_id, dupla_dita, dupla_meios) values (v_os, 'inicio', 2);
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_r := pg_temp.aprova(v_os, (v_m ->> 'dias')::numeric);
    perform pg_temp.publica(v_os, (v_m ->> 'total')::int, date '2027-03-08');
    select * into v_pl from public.os_planejamento where service_order_id = v_os;
    v_m := public.agenda_meios_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'V9n dupla ligada: aprovado 6 dias, total 10 (12 − 2 de dupla); lido depois, o mesmo (a aceita não refaz a dupla, mas o total publicado fica); pm da dupla 12',
      coalesce((v_r ->> 'ok')::boolean, false) and (v_pl.aprovado_com_vies ->> 'total')::int = 10 and (v_m ->> 'dias')::numeric = 6 and (v_m ->> 'total')::int = 10 and (v_m #>> '{dupla,pm}')::int = 12 and (v_m ->> 'restantes')::numeric = 0,
      format('%s | total=%s pm=%s restantes=%s', v_r ->> 'ok', v_m ->> 'total', v_m #>> '{dupla,pm}', v_m ->> 'restantes'));
    update public.agenda_config set modo_dupla = 'sombra' where id;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v9$;

-- ── V10. A sombra não chama nada de novo ───────────────────────────────────────────────────────────
do $v10$
declare
  v_res jsonb := '[]'::jsonb;
  v_os uuid;
  v_osd uuid;
  v_d jsonb;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V10 sombra', true, 'PULADO: sem a fixture'));
    return;
  end if;
  begin
    v_os := pg_temp.aberta(61, 3820);
    v_osd := pg_temp.aberta(62, 3820);
    perform pg_temp.dias(v_osd, 3, 'dono');
    -- as funções do viés lançam: em sombra nenhuma pode ser chamada (R7.8-1; M1c)
    execute $f$create or replace function public._agenda_vies_da_os(p_os uuid) returns jsonb language plpgsql stable as $g$ begin raise exception 'chamou _agenda_vies_da_os em sombra'; end $g$;$f$;
    execute $f$create or replace function public._agenda_vies_dono_da_os(p_os uuid) returns jsonb language plpgsql stable as $g$ begin raise exception 'chamou _agenda_vies_dono_da_os em sombra'; end $g$;$f$;
    execute $f$create or replace function public._agenda_margem_em_uso(p_item text, p_chave text) returns numeric language plpgsql stable as $g$ begin raise exception 'chamou _agenda_margem_em_uso em sombra'; end $g$;$f$;
    execute $f$create or replace function public._agenda_dias_com_vies(p_sug jsonb, p_vies numeric) returns jsonb language plpgsql stable as $g$ begin raise exception 'chamou _agenda_dias_com_vies em sombra'; end $g$;$f$;
    update public.agenda_config set modo_vies = 'sombra', modo_aprendizado = 'ligado', gestor_so_propor = false where id;
    v_d := public.os_duracao_sugerida(v_os);
    v_res := pg_temp.ok(v_res, 'V10a os_duracao_sugerida em sombra não chama o viés', not v_d ? 'vies', null);
    v_d := public.agenda_meios_da_os(v_os, date '2027-01-07');
    v_res := pg_temp.ok(v_res, 'V10b agenda_meios_da_os em sombra (OS sem dias): nada', not v_d ? 'vies', null);
    v_d := public.agenda_meios_da_os(v_osd, date '2027-01-07');
    v_res := pg_temp.ok(v_res, 'V10c agenda_meios_da_os em sombra (OS com dias do dono): nada, só a leitura da config', not v_d ? 'vies', null);
    update public.agenda_config set modo_vies = 'desligado' where id;
    v_res := pg_temp.ok(v_res, 'V10d desligado: as 3 também', not public.os_duracao_sugerida(v_os) ? 'vies' and not public.agenda_meios_da_os(v_os, date '2027-01-07') ? 'vies' and not public.agenda_meios_da_os(v_osd, date '2027-01-07') ? 'vies', null);
    -- com a marcação na mão (sem modo) não se chama função
    update public.agenda_config set modo_vies = 'sombra' where id;
    insert into public.os_planejamento (service_order_id, marcado_em, vies_marcado, tempo_compra_marcado, folga_compra_marcada) values (v_os, date '2027-01-05', 1, 1, 0) on conflict (service_order_id) do update set marcado_em = excluded.marcado_em, vies_marcado = excluded.vies_marcado;
    v_d := public.agenda_meios_da_os(v_os, date '2027-01-07');
    v_res := pg_temp.ok(v_res, 'V10e marcada com 1,00 em sombra: não chama nada', not v_d ? 'vies', null);
    -- ligado com o freio: os_duracao_sugerida nem chama o viés (o portão de custo vê a linha)
    update public.agenda_config set modo_vies = 'ligado', gestor_so_propor = true where id;
    v_res := pg_temp.ok(v_res, 'V10f ligado com o freio: os_duracao_sugerida não chama o viés', not public.os_duracao_sugerida(v_os) ? 'vies', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v10$;

-- ── V6. As cópias ──────────────────────────────────────────────────────────────────────────────────
do $v6$
declare
  v_res jsonb := '[]'::jsonb;
  v_m text := coalesce(current_setting('agenda_teste.mig_vies_fase7e', true), '');
  r record;
begin
  if v_m = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V6 as cópias', true, 'PULADO: sem a migration como texto (rode pela bancada)'));
    return;
  end if;
  v_res := pg_temp.ok(v_res, 'V6a a migration não recria o que R7.1 proíbe (_agenda_aprendido, agenda_aprender, agenda_propor, agenda_vigiar, agenda_cliente_vigiar)',
    v_m !~ 'create or replace function public\._agenda_aprendido\(' and v_m !~ 'function public\.agenda_aprender\(' and v_m !~ 'function public\.agenda_propor\(' and v_m !~ 'function public\.agenda_vigiar\(' and v_m !~ 'function public\.agenda_cliente_vigiar\(', null);
  v_res := pg_temp.ok(v_res, 'V6b _agenda_vies_da_os é a do P2 (não foi recriada)', v_m !~ 'create or replace function public\._agenda_vies_da_os\(', null);
  for r in select * from (values
    ('os_duracao_sugerida', 'public.os_duracao_sugerida(uuid)', 'd9045ab0351f3c4bd2d5e8a3d3d4bef3'),
    ('agenda_meios_da_os', 'public.agenda_meios_da_os(uuid, date)', '33c1422c7bfdbcd66813b41f67abb82b'),
    ('_agenda_aplicar_planejar', 'public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)', '98673d30737ab66bfc48e0f9a3677bea'),
    ('_agenda_aprender_congelar', 'public._agenda_aprender_congelar(date)', '1b5eb8c0b65b6d5ec4944286378e7ada'),
    ('_agenda_aprender_congelar_marcacao', 'public._agenda_aprender_congelar_marcacao(date)', '2d940a4694bf412f65ea40eb5d0d4166'),
    ('agenda_aplicar', 'public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz)', 'eb892b79d7f5683f9846f689c3b1b2c3')) t(nome, assin, md5o)
  loop
    v_res := pg_temp.ok(v_res, 'V6c ' || r.nome || ': tirados os blocos do P3, o corpo é o da origem (md5)',
      md5(pg_temp.sem_p3((select prosrc from pg_proc where oid = r.assin::regprocedure))) = r.md5o,
      md5(pg_temp.sem_p3((select prosrc from pg_proc where oid = r.assin::regprocedure))));
  end loop;
  perform pg_temp.gravar(v_res);
end
$v6$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
