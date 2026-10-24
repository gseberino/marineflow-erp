-- Conferência DEPOIS de ligar a Agenda de Produção, Fase 2 (pacote P6): migrations 20261025100000..100500, as edge
-- functions, o front e (passo 4) os modos em sombra — fila-do-dono/fase2-oks.md, passos 1–5.
-- bancada: depende de 20261025100500
--
-- SÓ LEITURA: nenhum INSERT, UPDATE ou DELETE em tabela do sistema (só na tabela temporária do resultado); agenda_saude
-- é STABLE e não grava; termina em ROLLBACK. Não depende da fixture: vale para a carteira de produção e para a da
-- bancada (que não aplica a migration de dado 20261025101000: lá os modos ficam como a Fase 1 deixou).
--
--   M  as 6 versões de estrutura da Fase 2 estão registradas em supabase_migrations.schema_migrations; a de dado
--      (101000, os modos em sombra) é mostrada
--   C  agenda_config: uma linha; as 10 colunas novas existem; modo_proposta/modo_vigia: com a 101000 registrada, sombra
--      (ou ligado, depois dos passos 6–7); sem ela, desligado; equipe e cliente desligados (Fases 3 e 5)
--   T  as 5 tabelas novas: RLS ligada, policies só de leitura e TO authenticated, anon sem nada, authenticated só lê
--   G  os gatilhos das invariantes ligados (12 nas tabelas da agenda e o das datas em service_orders)
--   F  funções: o contrato existe; nenhuma agenda_*/_agenda_*/os_* executável por anon; v_agenda_dia com
--      security_invoker e sem anon
--   S  agenda_saude(): ok; criticas.sem_decisao = 0 e pela_regra_sem_decisao = 0 (a métrica "ação crítica sem decisão"
--      tem de ser 0 sempre); choques = 0; a vigia rodou nas últimas 2 h (com algum modo fora de desligado); nenhum erro
--      da agenda em app_error_logs nas últimas 24 h
--   N  em sombra (antes do passo 6): nada publicado nem executado — 0 alocação vigente, 0 ação executada pelo motor, a
--      versão do plano em 0; toda proposta da vigia em modo sombra
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 4 de fila-do-dono/fase2-oks.md (estrutura, edge functions, front e os modos em
--   sombra), com o OK do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase2_pos_deploy.sql
--   S3 só fica verde depois do 1º tique de 15 min da vigia; S4 a partir do 2º dia, se a vigia não estiver falhando.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- ── M. Versões registradas ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v),
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = v),
       null
  from unnest(array['20261025100000', '20261025100100', '20261025100200', '20261025100300', '20261025100400',
                    '20261025100500']) v;

insert into _resultado
select 'M2 a migration de dado 20261025101000 (modos em sombra): registrada ou não (só mostra; C2 confere o modo)', true,
       case when exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261025101000')
            then 'registrada (passo 4 feito)' else 'não registrada (antes do passo 4)' end;

-- ── C. A configuração ───────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'C1 agenda_config tem exatamente uma linha', count(*) = 1, count(*)::text from public.agenda_config;

insert into _resultado
select format('C1 agenda_config.%s existe (o DEFAULT é o único lugar do número)', c),
       exists (select 1 from information_schema.columns k
                where k.table_schema = 'public' and k.table_name = 'agenda_config' and k.column_name = c),
       null
  from unnest(array['hora_do_plano', 'presenca_curta', 'desfazer_validade', 'interrupcoes_max', 'inicios_tentados_du',
                    'atraso_longo_dias', 'remarcar_confirmado_du', 'sem_registro_du', 'backlog_minimo_semanas',
                    'perguntas_vezes_max']) c;

insert into _resultado
select 'C2 os modos da Fase 2: com a 101000 registrada, sombra (ou ligado com o OK dos passos 6–7); sem ela, desligado',
       coalesce(bool_and(case when exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261025101000')
                              then c.modo_proposta in ('sombra', 'ligado') and c.modo_vigia in ('sombra', 'ligado')
                              else c.modo_proposta = 'desligado' and c.modo_vigia = 'desligado' end), false),
       string_agg(format('proposta %s, vigia %s, leitura %s', c.modo_proposta, c.modo_vigia, c.modo_leitura), '; ')
  from public.agenda_config c;

insert into _resultado
select 'C3 o que é das Fases 3 e 5 continua desligado (equipe, cliente)',
       coalesce(bool_and(c.modo_equipe = 'desligado' and c.modo_cliente = 'desligado'), false),
       string_agg(format('equipe %s, cliente %s', c.modo_equipe, c.modo_cliente), '; ')
  from public.agenda_config c;

insert into _resultado
select 'C4 a coluna nova do plano por OS existe (os_planejamento.adiantavel_patio_dias)',
       exists (select 1 from information_schema.columns k
                where k.table_schema = 'public' and k.table_name = 'os_planejamento' and k.column_name = 'adiantavel_patio_dias'),
       null;

-- ── T. As 5 tabelas novas ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('T1 %s existe, com RLS ligada', t),
       coalesce((select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.' || t)), false),
       case when to_regclass('public.' || t) is null then 'a tabela não existe' end
  from unnest(array['agenda_propostas', 'agenda_perguntas', 'agenda_acoes', 'agenda_alocacoes', 'agenda_vigia_rodadas']) t;

insert into _resultado
select format('T2 %s: policies só de leitura e TO authenticated', t),
       count(p.policyname) >= 1 and coalesce(bool_and(p.roles = '{authenticated}'::name[] and p.cmd = 'SELECT'), false),
       string_agg(p.policyname || ' ' || p.cmd || ' ' || p.roles::text, '; ')
  from unnest(array['agenda_propostas', 'agenda_perguntas', 'agenda_acoes', 'agenda_alocacoes', 'agenda_vigia_rodadas']) t
  left join pg_policies p on p.schemaname = 'public' and p.tablename = t
 group by t;

insert into _resultado
select format('T3 %s: anon sem nada; authenticated só lê', t),
       to_regclass('public.' || t) is not null
       and not (has_table_privilege('anon', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'insert')
                or has_table_privilege('anon', 'public.' || t, 'update') or has_table_privilege('anon', 'public.' || t, 'delete'))
       and has_table_privilege('authenticated', 'public.' || t, 'select')
       and not (has_table_privilege('authenticated', 'public.' || t, 'insert')
                or has_table_privilege('authenticated', 'public.' || t, 'update')
                or has_table_privilege('authenticated', 'public.' || t, 'delete')),
       case when to_regclass('public.' || t) is null then 'a tabela não existe' end
  from unnest(array['agenda_propostas', 'agenda_perguntas', 'agenda_acoes', 'agenda_alocacoes', 'agenda_vigia_rodadas']) t;

-- ── G. Os gatilhos das invariantes ──────────────────────────────────────────────────────────────────────
-- 'O' = ligado (origin). Desligado ('D') deixaria o publicado mutável, o crítico sem decisão ou a data da OS solta.
insert into _resultado
select format('G1 gatilho %s em %s ligado', g.nome, g.tabela),
       exists (select 1 from pg_trigger tg
                where tg.tgrelid = to_regclass('public.' || g.tabela) and tg.tgname = g.nome and not tg.tgisinternal
                  and tg.tgenabled = 'O'),
       null
  from (values ('agenda_alocacoes', 'agenda_alocacoes_antes'), ('agenda_alocacoes', 'agenda_alocacoes_imutavel'),
               ('agenda_alocacoes', 'agenda_alocacoes_nao_apaga'), ('agenda_alocacoes', 'agenda_alocacoes_versao'),
               ('agenda_propostas', 'agenda_propostas_nao_apaga'), ('agenda_propostas', 'agenda_propostas_so_fecha'),
               ('agenda_perguntas', 'agenda_perguntas_nao_apaga'), ('agenda_perguntas', 'agenda_perguntas_antes'),
               ('agenda_acoes', 'agenda_acoes_nao_apaga'), ('agenda_acoes', 'agenda_acoes_so_desfaz'),
               ('agenda_acoes', 'agenda_acoes_critica_decidida'), ('service_orders', 'trg_so_datas_pela_agenda')) g(tabela, nome);

insert into _resultado
select 'G2 as duas EXCLUDE de agenda_alocacoes existem (choque vigente e choque dentro da proposta)',
       count(*) = 2, string_agg(c.conname, ', ' order by c.conname)
  from pg_constraint c
 where c.conrelid = to_regclass('public.agenda_alocacoes') and c.contype = 'x';

-- ── F. Funções ──────────────────────────────────────────────────────────────────────────────────────────
-- O contrato: o que as ferramentas, as palavras, a vigia, o secretário, a tela e a aprovação chamam.
insert into _resultado
select format('F1 %s existe', f), exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f), null
  from unnest(array[
    'os_transicionar_status', 'agenda_propor', 'agenda_validar', 'agenda_aplicar', 'agenda_desfazer', 'agenda_acao_desfazivel',
    'agenda_marcar_os', 'agenda_decidir', 'agenda_os_do_dia', 'agenda_registrar_dia', 'agenda_conferir_dia', 'agenda_choveu',
    'agenda_desfazer_dito', 'agenda_replanejar', 'agenda_vigiar', 'agenda_saude', 'agenda_fechamento_registrar',
    'agenda_acorde_registrado', 'agenda_rascunho_marcar', 'agenda_rascunho_aplicar', 'agenda_rascunho_desfazer',
    'agenda_rascunho_andamento', 'agenda_propor_dito', 'agenda_decisoes_abertas', 'agenda_propostas_abertas',
    'agenda_linhas_do_dia', 'agenda_estado_das_os', 'agenda_ver', 'agenda_textos_do_fechamento', 'get_agenda_conflicts']) f;

insert into _resultado
select 'F2 nenhuma função da agenda (agenda_*, _agenda_*, os_*, _os_*) executável por anon',
       count(*) > 0 and count(*) filter (where has_function_privilege('anon', p.oid, 'execute')) = 0,
       format('%s funções; com anon: %s', count(*),
              coalesce(string_agg(p.proname, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')), 'nenhuma'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname ~ '^(_?agenda_|_?os_)';

insert into _resultado
select 'F3 as RPCs que a conversa e as palavras chamam alcançam authenticated (painel) e service_role (WhatsApp)',
       count(*) = 9 and bool_and(has_function_privilege('authenticated', p.oid, 'execute')
                                 and has_function_privilege('service_role', p.oid, 'execute')),
       string_agg(p.proname, ', ' order by p.proname)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('agenda_rascunho_marcar', 'agenda_rascunho_aplicar', 'agenda_rascunho_desfazer', 'agenda_rascunho_andamento',
                     'agenda_propor_dito', 'agenda_conferir_dia', 'agenda_choveu', 'agenda_desfazer_dito', 'agenda_rascunho_gravar');

insert into _resultado
select 'F4 o motor e a vigia só para service_role (o modelo não alcança: a ferramenta vai pelo agenda_propor_dito)',
       count(*) = 3 and count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute')) = 0,
       format('%s funções; com authenticated: %s', count(*),
              coalesce(string_agg(p.proname, ', ') filter (where has_function_privilege('authenticated', p.oid, 'execute')), 'nenhuma'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname in ('agenda_propor', 'agenda_aplicar', 'agenda_vigiar');

insert into _resultado
select 'F5 v_agenda_dia com security_invoker e sem anon',
       to_regclass('public.v_agenda_dia') is not null
       and coalesce((select 'security_invoker=on' = any (c.reloptions) or 'security_invoker=true' = any (c.reloptions)
                       from pg_class c where c.oid = to_regclass('public.v_agenda_dia')), false)
       and not has_table_privilege('anon', 'public.v_agenda_dia', 'select'),
       (select c.reloptions::text from pg_class c where c.oid = to_regclass('public.v_agenda_dia'));

-- ── S. A saúde ──────────────────────────────────────────────────────────────────────────────────────────
create temp table _saude on commit drop as select public.agenda_saude() as s;

insert into _resultado
select 'S1 nenhuma ação crítica executada sem a decisão do dono (criticas.sem_decisao = 0 e pela_regra_sem_decisao = 0)',
       (s #>> '{criticas,sem_decisao}')::int = 0 and (s #>> '{criticas,pela_regra_sem_decisao}')::int = 0,
       s -> 'criticas' ->> 'sem_decisao' || ' sem decisão; ' || (s -> 'criticas' ->> 'pela_regra_sem_decisao') || ' pela regra'
  from _saude;

insert into _resultado
select 'S2 nenhum choque de pessoa no plano vigente e agenda_saude ok',
       (s #>> '{invariantes,choques}')::int = 0 and (s ->> 'ok')::boolean, (s -> 'invariantes')::text
  from _saude;

insert into _resultado
select 'S3 a vigia rodou nas últimas 2 h (com o modo da proposta ou da vigia fora de desligado; desligada ela não roda)',
       (s #>> '{vigia,rodou_nas_ultimas_2h}')::boolean
       or (s #>> '{modos,proposta}' = 'desligado' and s #>> '{modos,vigia}' = 'desligado'),
       format('modos %s; última rodada %s', s -> 'modos', coalesce(s #>> '{vigia,ultima_rodada}', 'nenhuma'))
  from _saude;

insert into _resultado
select 'S4 nenhum erro da agenda (context agenda) em app_error_logs nas últimas 24 h',
       (s #>> '{vigia,erros_24h}')::int = 0, s #>> '{vigia,erros_24h}'
  from _saude;

-- ── N. Em sombra nada muda ──────────────────────────────────────────────────────────────────────────────
-- Antes do passo 6 (modo_proposta fora de ligado e nenhuma versão do plano): nada vigente, nada executado pelo motor.
-- Depois de ligar e voltar a sombra (passo 8), o publicado fica: N1 e N2 só valem enquanto nada foi publicado.
insert into _resultado
select 'N1 em sombra, antes de ligar: nenhuma alocação vigente (publicada ou fixada)',
       c.modo_proposta = 'ligado' or c.versao_plano > 0
       or not exists (select 1 from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada')),
       format('proposta %s, versão do plano %s', c.modo_proposta, c.versao_plano)
  from public.agenda_config c;

insert into _resultado
select 'N2 em sombra, antes de ligar: nenhuma ação executada pelo motor, pela vigia ou pela conferência',
       c.modo_proposta = 'ligado' or c.versao_plano > 0
       or not exists (select 1 from public.agenda_acoes a where a.executada and a.origem in ('motor', 'vigia', 'conferencia')),
       (select count(*)::text from public.agenda_acoes a where a.executada and a.origem in ('motor', 'vigia', 'conferencia'))
  from public.agenda_config c;

insert into _resultado
select 'N3 em sombra: toda proposta da vigia e do motor nasce em modo sombra (nenhuma ligada sem o OK)',
       c.modo_proposta = 'ligado' or c.versao_plano > 0
       or not exists (select 1 from public.agenda_propostas p where p.modo <> 'sombra' and p.criada_por in ('motor', 'vigia')),
       (select string_agg(distinct p.modo || '/' || p.criada_por, ', ') from public.agenda_propostas p)
  from public.agenda_config c;

select teste, ok, detalhe from _resultado order by teste;

rollback;
