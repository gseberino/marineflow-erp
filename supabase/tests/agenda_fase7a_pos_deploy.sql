-- Conferência DEPOIS de aplicar a Agenda de Produção, Fase 7a (os 13 pacotes, P1 a P13): migrations 20261031100000..100950, as
-- edge functions (ai-agent e erp-mcp com as palavras e o foco *agenda gestor*; ai-daily-briefing com a vaga da agenda no
-- fechamento) e (passo 3) a migration de dado 20261031100990 — os 5 modos do gestor em teste — fila-do-dono/fase7a-oks.md,
-- passos 1–3 (e de novo a cada "ligar", passos 4 e 6 a 9). Spec: spec-fase7a.md §8.4 (agenda_fase7a_pos_deploy.sql) e §10 passo 1.
-- bancada: depende de 20261031100980
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só nas tabelas TEMPORÁRIAS do resultado); agenda_saude e agenda_ver são
-- STABLE e não gravam; termina em ROLLBACK. Na bancada (que não aplica a 20261031100990 nem tem pg_cron: lá os modos ficam como a
-- linha está, desligado, e o job só é mostrado) ele passa do mesmo jeito.
--
--   M  as 13 versões de estrutura da 7a e a da correção da revisão (100980) registradas em supabase_migrations.schema_migrations;
--      a de dado (100990, a sombra) é mostrada
--   C  agenda_config: os 5 modos, a lista das regras, a palavra e os 29 parâmetros do gestor existem; os modos: com a 100990
--      registrada, sombra (ou ligado, depois dos OKs); sem ela, desligado; a lista só com regras conhecidas; o gestor que marca
--      ligado tem a data do ligar (marcar_sozinho_desde)
--   T  as colunas novas de os_planejamento, agenda_alocacoes (com o gatilho da fonte), os_material, agenda_perguntas e
--      agenda_medidas_os; o diário agenda_gestor_dia: RLS ligada, policies só de leitura e TO authenticated, anon sem nada,
--      authenticated só lê; não se apaga; as listas fechadas com os tipos do gestor
--   F  as 59 funções novas da 7a existem (54 dos pacotes, 5 da correção); nenhuma executável por anon; as portas de cada grupo (as leituras: authenticated e
--      service_role; a rodada, as palavras e as do motor: só service_role; os passos e os gravadores: ninguém); nenhuma função
--      da agenda para anon; agenda_ver com o foco gestor
--   J  o job agenda-gestor do pg_cron: '7,23,37,53 10-23 * * 1-6' (a correção: os minutos ímpares), ativo, com as duas instruções (o statement_timeout de
--      gestor_tempo_max e a rodada) — sem pg_cron (a bancada), só mostra
--   S  agenda_saude().gestor: os 12 zeros obrigatórios (zeros_ok); os modos que a saúde mostra são os da linha; nenhum erro
--      gestor:% em 24 h nem aberto em app_error_logs; a última rodada do gestor (só mostra)
--   L  o foco gestor devolve o conteúdo dentro de texto_max mais o "Como eu conto" (a correção) e o mesmo texto duas vezes (md5)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 1 (estrutura), de novo DEPOIS do passo 3 (a migration de dado) e depois de cada "ligar" de
--   fila-do-dono/fase7a-oks.md, com o OK do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_pos_deploy.sql
--   J2 só fica verde em produção (com pg_cron); S5 mostra a última rodada do gestor (com os modos desligados, o job não grava
--   rodada: nenhuma, e está certo).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pd_sombra on commit drop as
select exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261031100990') as aplicada;

-- ── M. Versões registradas ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v),
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = v),
       null
  from unnest(array['20261031100000', '20261031100100', '20261031100200', '20261031100300', '20261031100400',
                    '20261031100500', '20261031100600', '20261031100700', '20261031100750', '20261031100800',
                    '20261031100850', '20261031100900', '20261031100950',
                    -- a correção dos achados da revisão da 7a
                    '20261031100980']) v;

insert into _resultado
select 'M2 a migration de dado 20261031100990 (os 5 modos do gestor em teste) — só mostra', true,
       case when (select aplicada from _pd_sombra) then 'registrada (passo 3 feito)' else 'não registrada (antes do passo 3)' end;

-- ── C. A configuração ───────────────────────────────────────────────────────────────────────────────────
create temp table _pd_colunas (tabela text, coluna text) on commit drop;
insert into _pd_colunas
select 'agenda_config', x from unnest(array['modo_marcar_sozinho', 'marcar_regras', 'gestor_so_propor', 'gestor_so_propor_em',
  'marcar_sozinho_desde', 'modo_vaga_fechamento', 'fechamento_vagas_agenda', 'estimativa_max_diarias', 'mo_fora_regex',
  'diagnostico_dias', 'sem_mo_dias', 'equipe_padrao', 'dupla_gatilhos', 'dupla_notas', 'situacao_dias', 'quanto_falta_dias',
  'veto_du', 'veto_hora', 'ficha_veto_dias', 'critico_valor_min', 'prazo_sem_fornecedor_du', 'compra_interna_du',
  'compra_urgente_du', 'gestor_hora_revisao', 'gestor_tempo_max', 'aprovada_sem_data_min', 'modo_encaixe_aprovacao',
  'modo_revisao_diaria', 'modo_compre_ate', 'gestor_k_os', 'gestor_k_dias_avisados', 'compre_ate_empurroes_max',
  'compras_aviso_du', 'sabado_manha', 'simular_orcamento_acima', 'simular_orcamento_dias']) x
union all
select 'os_planejamento', x from unnest(array['dupla_dita', 'dupla_meios', 'dupla_motivo', 'dupla_em', 'dp_no_inicio']) x
union all select 'agenda_alocacoes', 'duracao_fonte'
union all
select 'os_material', x from unnest(array['compre_ate', 'compre_ate_base', 'compre_ate_em', 'cobrado_em', 'cobrado_vezes',
                                          'empurrada_vezes', 'defeito_em']) x
union all select 'agenda_perguntas', x from unnest(array['veto_ate', 'opcao_padrao']) x
union all select 'agenda_medidas_os', x from unnest(array['fator_orcamento', 'dp_no_inicio', 'dp_reais']) x;

insert into _resultado
select 'C1 agenda_config tem os 5 modos, a lista das regras, a palavra (e quando foi dita), a data do ligar e os 29 parâmetros do gestor (36 colunas)',
       count(*) filter (where c.column_name is null) = 0,
       format('%s de 36; faltam: %s', count(c.column_name), coalesce(string_agg(k.coluna, ', ') filter (where c.column_name is null), '—'))
  from _pd_colunas k
  left join information_schema.columns c on c.table_schema = 'public' and c.table_name = k.tabela and c.column_name = k.coluna
 where k.tabela = 'agenda_config';

insert into _resultado
select 'C2 os 5 modos do gestor: com a 100990 registrada, sombra (ou ligado com os OKs); sem ela, desligado',
       case when (select aplicada from _pd_sombra)
            then array[c.modo_marcar_sozinho, c.modo_vaga_fechamento, c.modo_encaixe_aprovacao, c.modo_revisao_diaria, c.modo_compre_ate]
                 <@ array['sombra', 'ligado']
            else array[c.modo_marcar_sozinho, c.modo_vaga_fechamento, c.modo_encaixe_aprovacao, c.modo_revisao_diaria, c.modo_compre_ate]
                 <@ array['desligado'] end,
       format('marcar %s, vaga %s, encaixe %s, revisao %s, compre_ate %s; só propor: %s', c.modo_marcar_sozinho,
              c.modo_vaga_fechamento, c.modo_encaixe_aprovacao, c.modo_revisao_diaria, c.modo_compre_ate, c.gestor_so_propor)
  from public.agenda_config c where c.id;

insert into _resultado
select 'C3 as regras só as conhecidas (as 15 de AG7-01/AG7-09); o gestor que marca ligado tem a data do ligar (marcar_sozinho_desde)',
       c.marcar_regras <@ array['estimativa', 'mo_limpa', 'uma_pessoa', 'diagnostico', 'situacao', 'sem_peca', 'embutida_suposta',
                                'critico_por_valor', 'prazo_padrao', 'compra_firme', 'teto_equipe', 'zona_travada', 'onda', 'escada',
                                'sinal_cobrar']
       and (c.modo_marcar_sozinho <> 'ligado' or c.marcar_sozinho_desde is not null),
       c.marcar_regras::text || ' desde ' || coalesce(c.marcar_sozinho_desde::text, '—')
  from public.agenda_config c where c.id;

-- ── T. As colunas, o gatilho, o diário e as listas ─────────────────────────────────────────────────────────────
insert into _resultado
select format('T1 %s tem as %s colunas novas da 7a', k.tabela, count(*)),
       count(*) filter (where c.column_name is null) = 0,
       coalesce('faltam: ' || string_agg(k.coluna, ', ') filter (where c.column_name is null), string_agg(k.coluna, ', '))
  from _pd_colunas k
  left join information_schema.columns c on c.table_schema = 'public' and c.table_name = k.tabela and c.column_name = k.coluna
 where k.tabela <> 'agenda_config'
 group by k.tabela;

insert into _resultado
select 'T2 o gatilho da fonte da duração (agenda_alocacoes_fonte, antes do insert) existe e chama _agenda_alocacao_fonte',
       exists (select 1 from pg_trigger t where t.tgrelid = 'public.agenda_alocacoes'::regclass and t.tgname = 'agenda_alocacoes_fonte'
                 and not t.tgisinternal and t.tgfoid = to_regprocedure('public._agenda_alocacao_fonte()')),
       null;

insert into _resultado
select 'T3 agenda_gestor_dia: RLS ligada; policies só de leitura e TO authenticated; anon sem nada; authenticated só lê; não se apaga',
       coalesce((select k.relrowsecurity from pg_class k where k.oid = to_regclass('public.agenda_gestor_dia')), false)
       and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'agenda_gestor_dia'
                          and (p.cmd <> 'SELECT' or not (p.roles @> array['authenticated']::name[]) or p.roles @> array['anon']::name[]))
       and exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = 'agenda_gestor_dia' and p.cmd = 'SELECT')
       and not has_table_privilege('anon', 'public.agenda_gestor_dia', 'select')
       and has_table_privilege('authenticated', 'public.agenda_gestor_dia', 'select')
       and not has_table_privilege('authenticated', 'public.agenda_gestor_dia', 'insert')
       and not has_table_privilege('authenticated', 'public.agenda_gestor_dia', 'update')
       and not has_table_privilege('authenticated', 'public.agenda_gestor_dia', 'delete')
       and exists (select 1 from pg_trigger t where t.tgrelid = 'public.agenda_gestor_dia'::regclass
                     and t.tgname = 'agenda_gestor_dia_nao_apaga' and not t.tgisinternal),
       null;

insert into _resultado
select 'T4 as listas fechadas com os do gestor: os 13 tipos de pergunta, as 4 críticas novas, as 5 ações, a rotina gestor, o cancelamento reestimada, a recusa veto e a fonte orcamento',
       (select pg_get_constraintdef(k.oid) from pg_constraint k
         where k.conrelid = 'public.agenda_perguntas'::regclass and k.conname = 'agenda_perguntas_tipo_check')
         ~ all (array['''situacao''', '''estimativa''', '''equipe_cadastro''', '''reavaliar''', '''reestimar''', '''ficha_estimativa''',
                      '''bem_livre''', '''compre_ate''', '''sinal''', '''onda''', '''dia_avisado''', '''dia_prometido''', '''sabado'''])
       and (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
             where d.adrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica')
         ~ all (array['''onda''', '''dia_avisado''', '''dia_prometido''', '''sabado'''])
       and (select pg_get_constraintdef(k.oid) from pg_constraint k
             where k.conrelid = 'public.agenda_acoes'::regclass and k.conname = 'agenda_acoes_tipo_check')
         ~ all (array['''estimar''', '''reestimar''', '''reparar''', '''gestor''', '''dupla'''])
       and (select pg_get_constraintdef(k.oid) from pg_constraint k
             where k.conrelid = 'public.agenda_vigia_rodadas'::regclass and k.conname = 'agenda_vigia_rodadas_rotina_check') ~ '''gestor'''
       and (select pg_get_constraintdef(k.oid) from pg_constraint k
             where k.conrelid = 'public.agenda_alocacoes'::regclass and k.conname = 'agenda_alocacoes_cancelada_motivo_check') ~ '''reestimada'''
       and (select pg_get_constraintdef(k.oid) from pg_constraint k
             where k.conrelid = 'public.agenda_equipe_mensagens'::regclass and k.conname = 'agenda_equipe_mensagens_recusa_motivo_check') ~ '''veto'''
       and (select pg_get_constraintdef(k.oid) from pg_constraint k
             where k.conrelid = 'public.os_planejamento'::regclass and k.conname = 'os_planejamento_estimativa_fonte_check') ~ '''orcamento''',
       null;

-- ── F. As funções ───────────────────────────────────────────────────────────────────────────────────────
create temp table _pd_funcoes (f text primary key, porta text not null) on commit drop;
insert into _pd_funcoes values
  -- as leituras e os textos (STABLE/IMMUTABLE, invoker): authenticated (a tela e o agenda_ver) e service_role
  ('_agenda_regex_valido(text)', 'leitura'), ('_agenda_dupla_lista_ok(jsonb, boolean)', 'leitura'),
  ('_agenda_gestor_regra(text)', 'leitura'), ('_agenda_gestor_modo(text)', 'leitura'),
  ('_agenda_dia_avisado(uuid, uuid, date)', 'leitura'), ('_agenda_nome_do_servico(text)', 'leitura'),
  ('_agenda_peca_embutida(uuid)', 'leitura'), ('_agenda_os_situacao(uuid, date)', 'leitura'),
  ('_agenda_gestor_estimativa(uuid, date)', 'leitura'), ('_agenda_veto_ate(timestamptz, smallint)', 'leitura'),
  ('_agenda_ver_gestor(date)', 'leitura'), ('_agenda_gestor_motivo_texto(text)', 'leitura'),
  ('_agenda_gestor_motivo_ordem(text)', 'leitura'), ('_agenda_gestor_faixa(date, date)', 'leitura'),
  ('_agenda_gestor_pessoas(jsonb)', 'leitura'), ('_agenda_gestor_compra_da_os(uuid, date)', 'leitura'),
  ('_agenda_gestor_dupla_texto(jsonb)', 'leitura'), ('_agenda_plano_estimativa(jsonb, date)', 'leitura'),
  ('_agenda_os_por_estimativa(uuid, date)', 'leitura'), ('_agenda_os_compra_pendente(uuid, date)', 'leitura'),
  ('_agenda_cliente_estimativa_liberada(text)', 'leitura'), ('_agenda_ficha_liberada(uuid, date, timestamptz)', 'leitura'),
  -- (a correção da revisão, 20261031100980) o juntar do foco gestor
  ('_agenda_gestor_juntar(text[], integer, text)', 'leitura'),
  -- a rodada, as palavras e as contas do motor: só o service_role (o job, o ai-agent/erp-mcp e o motor)
  ('agenda_gestor_rodar(date, timestamptz)', 'service_role'), ('agenda_gestor_dito(uuid, boolean, date, timestamptz)', 'service_role'),
  ('agenda_dupla_dita(uuid, text, boolean, date, timestamptz)', 'service_role'), ('_agenda_alocacao_fonte()', 'service_role'),
  ('_agenda_gestor_onda_conta(jsonb)', 'service_role'), ('_agenda_zona_fora(jsonb, uuid, jsonb)', 'service_role'),
  -- os passos da rodada, os gravadores e o despacho: ninguém de fora (nem o service_role)
  ('_agenda_ampliar_lista(regclass, text, text, text[])', 'interna'),
  ('_agenda_gestor_dia_gravar(date, text, jsonb, timestamptz)', 'interna'),
  ('_agenda_gestor_perguntar(text, text, uuid, text, jsonb, smallint, timestamptz, smallint, text, timestamptz)', 'interna'),
  ('_agenda_gestor_perguntas_da_os(uuid, date, timestamptz, boolean)', 'interna'),
  ('_agenda_gestor_gravar_dias(uuid, numeric, text, uuid, timestamptz)', 'interna'),
  ('_agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'interna'),
  ('_agenda_gestor_vetos(date, timestamptz)', 'interna'), ('_agenda_gestor_equipe(date, timestamptz)', 'interna'),
  ('_agenda_gestor_sombra(date, timestamptz)', 'interna'), ('_agenda_gestor_perguntas(date, timestamptz)', 'interna'),
  ('_agenda_gestor_encaixe(date, timestamptz)', 'interna'), ('_agenda_gestor_onda(uuid, date, timestamptz)', 'interna'),
  ('_agenda_gestor_revisao(date, timestamptz)', 'interna'), ('_agenda_gestor_reparo(uuid, date, timestamptz)', 'interna'),
  ('_agenda_gestor_reparar(uuid, date, timestamptz)', 'interna'), ('_agenda_gestor_corte(uuid, date, timestamptz)', 'interna'),
  ('_agenda_gestor_reestimar(uuid, date, timestamptz, uuid)', 'interna'),
  ('_agenda_gestor_perguntas_da_revisao(uuid, date, timestamptz, boolean)', 'interna'),
  ('_agenda_gestor_compra_conta(uuid, date)', 'interna'), ('_agenda_compras_da_semana(date)', 'interna'),
  ('_agenda_gestor_compre_ate(date, timestamptz)', 'interna'), ('_agenda_gestor_fichas(date, timestamptz)', 'interna'),
  ('_agenda_gestor_sinal(date, timestamptz)', 'interna'), ('_agenda_gestor_sabado(date, timestamptz)', 'interna'),
  ('_agenda_gestor_orcamentos(date, timestamptz)', 'interna'), ('_agenda_gestor_bem(date, timestamptz)', 'interna'),
  -- (a correção da revisão, 20261031100980) o *desfaz* que vale, a conta em pessoa-meio-dia e a memória da duração na rodada
  ('_agenda_gestor_desfeito(uuid, timestamptz)', 'interna'), ('_agenda_gestor_pessoa_meios(uuid, date, jsonb)', 'interna'),
  ('_agenda_rodada_duracao_lembrar(text)', 'interna'), ('_agenda_rodada_duracao_guardar(text, bigint, jsonb)', 'interna');

insert into _resultado
select format('F1 as %s funções novas da 7a existem', count(*)), count(*) filter (where to_regprocedure('public.' || f) is null) = 0,
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
select 'F5 a agenda_ver tem o foco gestor (_agenda_ver_gestor)',
       p.prosrc like '%_agenda_ver_gestor(%', null
  from pg_proc p where p.oid = to_regprocedure('public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)');

-- ── J. O job agenda-gestor (pg_cron) ──────────────────────────────────────────────────────────────────────
do $j$
declare
  v_job record;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    insert into _resultado values ('J1 o job agenda-gestor (pg_cron) — sem a extensão (a bancada): só mostra', true, 'sem pg_cron');
    return;
  end if;
  execute $q$select j.schedule, j.command, j.active from cron.job j where j.jobname = 'agenda-gestor' limit 1$q$ into v_job;
  insert into _resultado values ('J1 o job agenda-gestor existe no pg_cron', v_job is not null and v_job.schedule is not null, null);
  insert into _resultado
  values ('J2 o job agenda-gestor: ''7,23,37,53 10-23 * * 1-6'' (os minutos ímpares: a correção da revisão), ativo, com o statement_timeout de gestor_tempo_max e a rodada (_hoje_brt() e now())',
          coalesce(v_job.schedule = '7,23,37,53 10-23 * * 1-6' and v_job.active
                   and v_job.command like '%statement_timeout%' and v_job.command like '%gestor_tempo_max%'
                   and v_job.command like '%agenda_gestor_rodar(public._hoje_brt(), now())%', false),
          coalesce(v_job.schedule, '—') || ' ' || coalesce(v_job.active::text, '—'));
end
$j$;

-- ── S. A saúde do gestor ───────────────────────────────────────────────────────────────────────────────
create temp table _saude on commit drop as select public.agenda_saude() as s;

insert into _resultado
select format('S1 gestor.%s = 0', k), coalesce((s #>> array['gestor', k])::int, -1) = 0, s #>> array['gestor', k]
  from _saude, unnest(array['zona_travada_mexida', 'dia_avisado_sem_pergunta', 'estimativa_sem_pergunta', 'prazo_em_critica',
                            'prazo_em_dia_prometido', 'aprovada_sem_data', 'rodada_gestor_atrasada',
                            'cliente_estimativa_sem_aprovacao', 'ficha_estimativa_sem_veto', 'onda_aplicada_sem_pergunta',
                            'alocacao_sem_fonte', 'regra_em_sombra_aplicada']) k;

insert into _resultado
select 'S2 os zeros do gestor entram no ok (zeros_ok); prazo_vencido_sem_mostrar só se conta (só mostra)',
       coalesce((s #>> '{gestor,zeros_ok}')::boolean, false),
       'prazo_vencido_sem_mostrar = ' || coalesce(s #>> '{gestor,prazo_vencido_sem_mostrar}', '—')
  from _saude;

insert into _resultado
select 'S3 os modos que a saúde mostra são os da linha (com *gestor, só propor*, os 4 do gestor valem teste)',
       s #>> '{gestor,modos,vaga}' = c.modo_vaga_fechamento
       and (s #>> '{gestor,modos,so_propor}')::boolean = c.gestor_so_propor
       and s #>> '{gestor,modos,marcar}' = case when c.gestor_so_propor and c.modo_marcar_sozinho = 'ligado' then 'sombra' else c.modo_marcar_sozinho end
       and s #>> '{gestor,modos,encaixe}' = case when c.gestor_so_propor and c.modo_encaixe_aprovacao = 'ligado' then 'sombra' else c.modo_encaixe_aprovacao end
       and s #>> '{gestor,modos,revisao}' = case when c.gestor_so_propor and c.modo_revisao_diaria = 'ligado' then 'sombra' else c.modo_revisao_diaria end
       and s #>> '{gestor,modos,compre_ate}' = case when c.gestor_so_propor and c.modo_compre_ate = 'ligado' then 'sombra' else c.modo_compre_ate end,
       (s -> 'gestor' -> 'modos')::text
  from _saude, public.agenda_config c where c.id;

insert into _resultado
select 'S4 nenhum erro da rodada do gestor (gestor:%) nas últimas 24 h', coalesce((s #>> '{gestor,erros_24h}')::int, 0) = 0,
       s #>> '{gestor,erros_24h}'
  from _saude;

insert into _resultado
select 'S5 a última rodada do gestor (só mostra; com os modos desligados o job não grava rodada)', true,
       format('última rodada %s; rodadas em 24 h: %s; os diários rodaram hoje: %s', coalesce(s #>> '{gestor,ultima_rodada}', 'nenhuma'),
              coalesce(s #>> '{gestor,rodadas_24h}', '0'), coalesce(s #>> '{gestor,diaria_hoje}', 'false'))
  from _saude;

insert into _resultado
select 'S6 nenhum erro do gestor (context agenda, action gestor:%) aberto em app_error_logs',
       count(*) = 0, coalesce(string_agg(e.action || ': ' || left(e.message, 80), ' | '), 'nenhum')
  from public.app_error_logs e
 where e.resolved_at is null and e.context = 'agenda' and e.action like 'gestor:%';

-- ── L. As leituras ──────────────────────────────────────────────────────────────────────────────────────
create temp table _pd_leituras on commit drop as
select public.agenda_ver(p_foco => 'gestor') as ges, public.agenda_ver(p_foco => 'gestor') as ges2,
       (select c.texto_max from public.agenda_config c where c.id) as texto_max,
       (select c.modo_leitura from public.agenda_config c where c.id) as leitura;

insert into _resultado
select 'L1 o foco gestor devolve texto dentro de texto_max mais o "Como eu conto" (com a leitura desligada: "a agenda de produção está desligada")',
       case when l.leitura = 'desligado' then l.ges ->> 'rota' = 'desligada'
            -- (a correção da revisão: o conteúdo até texto_max e o "Como eu conto", a última linha, depois dele)
            else (l.ges ->> 'ok')::boolean and length(l.ges ->> 'texto') between 1
                 and l.texto_max + 1 + length(split_part(l.ges ->> 'texto', E'\n', array_length(string_to_array(l.ges ->> 'texto', E'\n'), 1))) end,
       format('%s caracteres', length(l.ges ->> 'texto'))
  from _pd_leituras l;

insert into _resultado
select 'L2 duas leituras seguidas do foco gestor = o mesmo texto (md5)',
       md5(coalesce(l.ges ->> 'texto', '')) = md5(coalesce(l.ges2 ->> 'texto', '')), null
  from _pd_leituras l;

select teste, ok, detalhe from _resultado order by teste;

rollback;
