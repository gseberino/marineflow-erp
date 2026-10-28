-- Conferência DEPOIS de aplicar a Agenda de Produção, Fase 6 (pacote P8): migrations 20261029100000..100800, as edge functions
-- (task-automations com a rodada, ai-agent e erp-mcp com o foco), o front do cartão "Plano" e (passo 3) a migration de dado
-- 20261029101000 — modo_aprendizado em sombra — fila-do-dono/fase6-oks.md, passos 1–3 (e de novo a cada item ligado, passo 4).
-- bancada: depende de 20261029100900
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só nas tabelas TEMPORÁRIAS do resultado); agenda_saude, agenda_ver
-- e os_plano_da_os são STABLE e não gravam; termina em ROLLBACK. Na bancada (que não aplica a 20261029101000: lá o modo fica
-- como a linha está, desligado) ele passa do mesmo jeito.
--
--   M  as 9 versões de estrutura da Fase 6 registradas em supabase_migrations.schema_migrations; a de dado (101000, a sombra)
--      é mostrada
--   C  agenda_config: o modo e a lista do aprendizado e os 43 parâmetros existem; modo_aprendizado: com a 101000 registrada,
--      sombra (ou ligado, depois dos OKs); sem ela, desligado; a lista só com itens conhecidos, e vazia fora de ligado
--   T  as 4 colunas novas de os_planejamento e as 2 tabelas novas: RLS ligada, policies só de leitura e TO authenticated,
--      anon sem nada, authenticated só lê
--   F  as funções da Fase 6 existem; nenhuma executável por anon; agenda_aprender só service_role; os passos (_agenda_aprender_*),
--      o gravador e a decisão sem grant a ninguém (nem service_role); agenda_ver com os 19 focos (aprendizado); o cartão com a
--      linha do fator de campo
--   S  agenda_saude().aprendizado: os 6 zeros obrigatórios; o modo que a saúde mostra é o da linha; nenhum erro aprender:% em
--      24 h nem aberto em app_error_logs; a rodada do dia depois das 16:00 (só mostra antes do 1º tique dela)
--   L  as leituras: o foco aprendizado devolve texto dentro de texto_max e o mesmo texto duas vezes (md5)
--   K  (correção C1, 20261029100900) registrada; as 2 colunas e o CHECK novos de os_planejamento; o sem_fim; as 2 funções
--      novas e as portas; o "já rodou hoje?" pelo índice novo
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 1 (estrutura), de novo DEPOIS do passo 3 (a migration de dado) e depois de cada item ligado
--   de fila-do-dono/fase6-oks.md, com o OK do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase6_pos_deploy.sql
--   S4 só fica verde depois do 1º tique de 15 min do task-automations a partir das 16:00 (a rodada é uma vez por dia).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pd_sombra on commit drop as
select exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261029101000') as aplicada;

-- ── M. Versões registradas ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v),
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = v),
       null
  from unnest(array['20261029100000', '20261029100100', '20261029100200', '20261029100300', '20261029100400',
                    '20261029100500', '20261029100600', '20261029100700', '20261029100800']) v;

insert into _resultado
select 'M2 a migration de dado 20261029101000 (modo_aprendizado em sombra) — só mostra', true,
       case when (select aplicada from _pd_sombra) then 'registrada (passo 3 feito)' else 'não registrada (antes do passo 3)' end;

-- ── C. A configuração ───────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'C1 agenda_config tem o modo, a lista e os 43 parâmetros do aprendizado',
       count(*) = 45, format('%s de 45; faltam: %s', count(*),
         coalesce((select string_agg(x, ', ') from unnest(array['modo_aprendizado', 'aprendizado_ligados', 'aprender_hora',
           'fator_n_min', 'fator_percentil', 'fator_troca_max', 'capacidade_dono_min', 'aviso_folga_max_du', 'classe_bens',
           'classe_sistemas']) x where x not in (select column_name from information_schema.columns
                                                 where table_schema = 'public' and table_name = 'agenda_config')), '—'))
  from information_schema.columns c
 where c.table_schema = 'public' and c.table_name = 'agenda_config'
   and c.column_name in ('modo_aprendizado', 'aprendizado_ligados', 'aprender_hora', 'aprender_janela_dias', 'aprender_trava_dias',
     'fator_n_min', 'fator_percentil', 'fator_amostra_max', 'fator_min', 'fator_max', 'fator_troca_max', 'mo_n_min', 'mo_min',
     'mo_troca_max', 'presenca_n_min', 'presenca_intervencoes_min', 'presenca_taxa_min', 'fornecedor_n_min',
     'fornecedor_percentil', 'fornecedor_troca_max_du', 'capacidade_semanas', 'capacidade_semanas_min', 'capacidade_meios_min',
     'capacidade_dono_min', 'capacidade_troca_max', 'capacidade_motivos', 'cliente_n_min', 'aviso_n_min', 'aviso_folga_max_du',
     'aviso_troca_max_du', 'revisao_semanas', 'ppc_baixo', 'ppc_baixo_semanas', 'carga_ppc_baixo', 'ppc_alto',
     'ppc_alto_semanas', 'carga_ppc_alto', 'solver_os_ativas', 'solver_pessoas', 'solver_curtas_dia', 'solver_descarte_pct',
     'solver_semanas', 'solver_gatilhos_min', 'classe_bens', 'classe_sistemas');

insert into _resultado
select 'C2 modo_aprendizado: com a 101000 registrada, sombra (ou ligado com os OKs); sem ela, desligado',
       case when (select aplicada from _pd_sombra) then c.modo_aprendizado in ('sombra', 'ligado')
            else c.modo_aprendizado = 'desligado' end,
       c.modo_aprendizado || ' ' || c.aprendizado_ligados::text
  from public.agenda_config c;

insert into _resultado
select 'C3 a lista só com itens conhecidos, e vazia fora de ligado (em sombra a lista não vale; cada item é um OK)',
       c.aprendizado_ligados <@ array['fator', 'mo', 'presenca', 'fornecedor', 'capacidade_dono', 'aviso_cliente', 'revisao']
       and (c.modo_aprendizado = 'ligado' or c.aprendizado_ligados = '{}'),
       c.aprendizado_ligados::text
  from public.agenda_config c;

-- ── T. As colunas e as tabelas ──────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'T1 os_planejamento tem as 4 colunas novas (os dias no início, a fonte, o dia e a 1ª promessa)', count(*) = 4,
       string_agg(c.column_name, ', ')
  from information_schema.columns c
 where c.table_schema = 'public' and c.table_name = 'os_planejamento'
   and c.column_name in ('dias_no_inicio', 'dias_no_inicio_fonte', 'dias_no_inicio_em', 'prometido_primeiro_ate');

insert into _resultado
select format('T2 %s: RLS ligada; policies só de leitura e TO authenticated; anon sem nada; authenticated só lê', t),
       coalesce((select k.relrowsecurity from pg_class k where k.oid = to_regclass('public.' || t)), false)
       and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = t
                          and (p.cmd <> 'SELECT' or not (p.roles @> array['authenticated']::name[]) or p.roles @> array['anon']::name[]))
       and exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = t and p.cmd = 'SELECT')
       and not has_table_privilege('anon', 'public.' || t, 'select')
       and has_table_privilege('authenticated', 'public.' || t, 'select')
       and not has_table_privilege('authenticated', 'public.' || t, 'insert')
       and not has_table_privilege('authenticated', 'public.' || t, 'update')
       and not has_table_privilege('authenticated', 'public.' || t, 'delete'),
       null
  from unnest(array['agenda_medidas_os', 'agenda_aprendizado']) t;

-- ── F. As funções ───────────────────────────────────────────────────────────────────────────────────────
create temp table _pd_funcoes (f text primary key, porta text not null) on commit drop;
insert into _pd_funcoes values
  -- as leituras e os textos: authenticated e service_role
  ('_agenda_ver_aprendizado(date)', 'leitura'), ('agenda_fator_de_campo(uuid, date)', 'leitura'),
  ('_agenda_atraso_do_fornecedor(uuid)', 'leitura'), ('_agenda_carga_da_pessoa(uuid)', 'leitura'),
  ('_agenda_aprendido(text, text)', 'leitura'), ('_agenda_aprendizado_texto(text, text, jsonb)', 'leitura'),
  ('_agenda_percentil(numeric[], numeric)', 'leitura'), ('_agenda_mo_por_diaria_real()', 'leitura'),
  ('_agenda_presenca_aprendida(uuid)', 'leitura'), ('_agenda_classe_de_campo(uuid)', 'leitura'),
  ('agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)', 'leitura'), ('os_plano_da_os(uuid, date)', 'leitura'),
  ('_agenda_ver_fornecedores(date)', 'leitura'),
  -- a rodada: só o service_role (o task-automations)
  ('agenda_aprender(date, timestamptz)', 'service_role'),
  -- os passos, o gravador, a medida e a decisão: ninguém de fora (nem o service_role)
  ('_agenda_aprender_congelar(date)', 'interna'), ('_agenda_aprender_medir(date)', 'interna'),
  ('agenda_medir_os(uuid, date)', 'interna'),
  ('_agenda_aprender_fator(date, timestamptz)', 'interna'), ('_agenda_aprender_mo(date, timestamptz)', 'interna'),
  ('_agenda_aprender_presenca(date, timestamptz)', 'interna'), ('_agenda_aprender_fornecedor(date, timestamptz)', 'interna'),
  ('_agenda_aprender_capacidade(date, timestamptz)', 'interna'), ('_agenda_aprender_cliente(date, timestamptz)', 'interna'),
  ('_agenda_aprender_revisao(date, timestamptz)', 'interna'), ('_agenda_aprender_solver(date, timestamptz)', 'interna'),
  ('_agenda_aprendizado_gravar(text, text, text, numeric, integer, jsonb, numeric, jsonb, timestamptz)', 'interna'),
  ('_agenda_aprendizado_carga(numeric, numeric, uuid, timestamptz)', 'interna');

insert into _resultado
select 'F1 as funções da Fase 6 que a conferência olha existem', count(*) filter (where to_regprocedure('public.' || f) is null) = 0,
       coalesce(string_agg(f, ', ') filter (where to_regprocedure('public.' || f) is null), 'todas')
  from _pd_funcoes;

insert into _resultado
select 'F2 nenhuma delas executável por anon',
       count(*) filter (where to_regprocedure('public.' || f) is not null
                          and has_function_privilege('anon', to_regprocedure('public.' || f), 'execute')) = 0,
       string_agg(f, ', ') filter (where to_regprocedure('public.' || f) is not null
                                     and has_function_privilege('anon', to_regprocedure('public.' || f), 'execute'))
  from _pd_funcoes;

insert into _resultado
select format('F3 as portas de %s: %s', x.porta, case x.porta when 'leitura' then 'authenticated e service_role'
                                                     when 'service_role' then 'só service_role' else 'ninguém (nem service_role)' end),
       bool_and(case x.porta
                  when 'leitura' then has_function_privilege('authenticated', x.o, 'execute') and has_function_privilege('service_role', x.o, 'execute')
                  when 'service_role' then not has_function_privilege('authenticated', x.o, 'execute') and has_function_privilege('service_role', x.o, 'execute')
                  else not has_function_privilege('authenticated', x.o, 'execute') and not has_function_privilege('service_role', x.o, 'execute') end),
       string_agg(x.f, ', ') filter (where not case x.porta
                  when 'leitura' then has_function_privilege('authenticated', x.o, 'execute') and has_function_privilege('service_role', x.o, 'execute')
                  when 'service_role' then not has_function_privilege('authenticated', x.o, 'execute') and has_function_privilege('service_role', x.o, 'execute')
                  else not has_function_privilege('authenticated', x.o, 'execute') and not has_function_privilege('service_role', x.o, 'execute') end)
  from (select f, porta, to_regprocedure('public.' || f) as o from _pd_funcoes) x
 where x.o is not null
 group by x.porta;

insert into _resultado
select 'F4 nenhuma função da agenda (agenda_*, _agenda_*, os_*, _os_*) executável por anon',
       count(*) = 0, string_agg(p.proname, ', ')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname ~ '^(_?agenda_|_?os_)'
   and has_function_privilege('anon', p.oid, 'execute');

insert into _resultado
select 'F5 a agenda_ver tem o foco aprendizado e a lista dos 19; o cartão tem a linha do fator de campo (duracao.campo)',
       p.prosrc like '%''aprendizado'') then%' and p.prosrc like '%_agenda_ver_aprendizado(p_hoje)%'
       and (select q.prosrc from pg_proc q where q.oid = to_regprocedure('public.os_plano_da_os(uuid, date)')) like '%''campo'', v_campo%',
       null
  from pg_proc p where p.oid = to_regprocedure('public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)');

-- ── S. A saúde do aprendizado ───────────────────────────────────────────────────────────────────────────
create temp table _saude on commit drop as select public.agenda_saude() as s;

insert into _resultado
select format('S1 aprendizado.%s = 0', k), coalesce((s #>> array['aprendizado', k])::int, -1) = 0, s #>> array['aprendizado', k]
  from _saude, unnest(array['em_uso_com_amostra_pequena', 'em_uso_fora_de_ligado', 'troca_grande_sem_pergunta',
                            'rodada_atrasada', 'medida_sem_classe', 'fator_fora_dos_limites']) k;

insert into _resultado
select 'S2 o modo e a lista que a saúde mostra são os da linha',
       s #>> '{aprendizado,modo}' = c.modo_aprendizado and s #> '{aprendizado,ligados}' = to_jsonb(c.aprendizado_ligados),
       (s #>> '{aprendizado,modo}') || ' ' || (s #> '{aprendizado,ligados}')::text
  from _saude, public.agenda_config c;

insert into _resultado
select 'S3 nenhum erro da rodada do aprendizado (aprender:%) nas últimas 24 h', coalesce((s #>> '{aprendizado,erros_24h}')::int, 0) = 0,
       s #>> '{aprendizado,erros_24h}'
  from _saude;

insert into _resultado
select 'S4 a rodada do aprendizado de hoje (depois das 16:00, quando o task-automations já chama a rodada) — só mostra antes disso',
       true, format('última rodada %s; rodou hoje: %s', coalesce(s #>> '{aprendizado,ultima_rodada}', 'nenhuma'),
                    coalesce(s #>> '{aprendizado,rodou_hoje}', 'false'))
  from _saude;

insert into _resultado
select 'S5 nenhum erro do aprendizado (context agenda, action aprender:%; agenda:aprender) aberto em app_error_logs',
       count(*) = 0, coalesce(string_agg(e.action || ': ' || left(e.message, 80), ' | '), 'nenhum')
  from public.app_error_logs e
 where e.resolved_at is null
   and ((e.context = 'agenda' and e.action like 'aprender:%') or e.action like 'agenda:aprender%');

-- ── L. As leituras ──────────────────────────────────────────────────────────────────────────────────────
create temp table _pd_leituras on commit drop as
select public.agenda_ver(p_foco => 'aprendizado') as apr, public.agenda_ver(p_foco => 'aprendizado') as apr2,
       (select c.texto_max from public.agenda_config c) as texto_max,
       (select c.modo_leitura from public.agenda_config c) as leitura;

insert into _resultado
select 'L1 o foco aprendizado devolve texto dentro de texto_max (com a leitura desligada: "a agenda de produção está desligada")',
       case when l.leitura = 'desligado' then l.apr ->> 'rota' = 'desligada'
            else (l.apr ->> 'ok')::boolean and length(l.apr ->> 'texto') between 1 and l.texto_max end,
       format('%s caracteres', length(l.apr ->> 'texto'))
  from _pd_leituras l;

insert into _resultado
select 'L2 duas leituras seguidas do foco aprendizado = o mesmo texto (md5)',
       md5(coalesce(l.apr ->> 'texto', '')) = md5(coalesce(l.apr2 ->> 'texto', '')), null
  from _pd_leituras l;

-- ── K. A correção C1 (20261029100900) ─────────────────────────────────────────────────────────────────────
insert into _resultado
select 'K1 (C1) a migration 20261029100900 (a correção dos cálculos) registrada',
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261029100900'), null;
insert into _resultado
select 'K2 (C1, item 3) os_planejamento tem presenca_publicada e presenca_publicada_motivo, com o CHECK presenca_publicada_coerente',
       count(*) = 2 and exists (select 1 from pg_constraint c where c.conrelid = 'public.os_planejamento'::regclass
                                                             and c.conname = 'presenca_publicada_coerente'),
       string_agg(column_name, ', ')
  from information_schema.columns
 where table_schema = 'public' and table_name = 'os_planejamento' and column_name in ('presenca_publicada', 'presenca_publicada_motivo');
insert into _resultado
select 'K3 (C1, item 9) a lista de agenda_medidas_os.motivo aceita sem_fim',
       pg_get_constraintdef(c.oid) like '%sem_fim%', pg_get_constraintdef(c.oid)
  from pg_constraint c where c.conrelid = 'public.agenda_medidas_os'::regclass and c.conname = 'agenda_medidas_os_motivo_check';
insert into _resultado
select 'K4 (C1) as 2 funções novas existem; nenhuma para anon; _agenda_concluida_em sem grant a ninguém',
       to_regprocedure('public._agenda_fornecedor_da_medida(uuid)') is not null
       and to_regprocedure('public._agenda_concluida_em(uuid)') is not null
       and not has_function_privilege('anon', 'public._agenda_fornecedor_da_medida(uuid)', 'execute')
       and not has_function_privilege('anon', 'public._agenda_concluida_em(uuid)', 'execute')
       and not has_function_privilege('authenticated', 'public._agenda_concluida_em(uuid)', 'execute')
       and not has_function_privilege('service_role', 'public._agenda_concluida_em(uuid)', 'execute'),
       null;
-- (B4) o "já rodou hoje?" da rodada do aprendizado pelo índice: com a varredura sequencial proibida (só nesta transação, que
-- termina em ROLLBACK), o plano usa agenda_vigia_rodadas_rotina_dia; o plano de verdade (com a tabela do tamanho que ela tem)
-- só é mostrado.
do $k5$
declare
  l text;
  v_com text := '';
  v_sem text := '';
begin
  for l in execute $q$explain select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = date '2026-10-30'$q$ loop
    v_sem := v_sem || l || ' ';
  end loop;
  set local enable_seqscan = off;
  for l in execute $q$explain select 1 from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = date '2026-10-30'$q$ loop
    v_com := v_com || l || ' ';
  end loop;
  set local enable_seqscan = on;
  insert into _resultado values ('K5 (C1, B4) o "já rodou hoje?" da rodada pode ir pelo índice agenda_vigia_rodadas_rotina_dia (sem varrer a tabela)',
    v_com like '%agenda_vigia_rodadas_rotina_dia%', left(v_com, 300));
  insert into _resultado values ('K6 (C1, B4) o plano de agora (só mostra; com poucas rodadas o Postgres ainda pode preferir varrer)', true,
    left(v_sem, 300));
end
$k5$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
