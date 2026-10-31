-- Conferência DEPOIS de aplicar a Agenda de Produção, Fase 7b (os pacotes P1 a P6): migrations 20261101100000..100500 (e a correção
-- 100800/100850, se houver), as edge functions (task-automations com o passo 0b1 da semana da equipe; ai-agent e erp-mcp com a dupla
-- e a semana nas ferramentas e as 2 linhas do prompt), o front (o bloco Equipe do cartão da OS) e (passo 3) a migration de dado
-- 20261101100900 — os 5 modos da 7b em teste — fila-do-dono/fase7b-oks.md, passos 1–3 (e de novo a cada "ligar", passos 4 a 8).
-- Spec: spec-fase7b.md §8.3 (agenda_fase7b_pos_deploy.sql), §R4.7 e §10 passo 1.
-- bancada: depende de 20261101100400
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só nas tabelas TEMPORÁRIAS do resultado); agenda_saude, os_plano_da_os e
-- agenda_ver são STABLE e não gravam; termina em ROLLBACK. Na bancada (que não aplica a 20261101100900: lá os modos ficam como a linha
-- está, desligado) ele passa do mesmo jeito.
--
--   M  as 5 versões de estrutura da 7b (P1 a P5) e a do P6 (20261101100500) registradas em supabase_migrations.schema_migrations; a
--      correção (100800/100850) e a de dado (100900, a sombra) são mostradas. Na bancada, antes de o P6 estar no ramo, as 3 linhas do
--      P6 (M1b, F1b, F5b) não saem (na bancada nada pode sair PULADO); em produção e na bancada com o P6, saem e têm de passar
--   C  agenda_config: os 5 modos e os 21 parâmetros da 7b (26 colunas), sem equipe_inativo_dias; os modos: com a 100900 registrada,
--      sombra (ou ligado, depois dos OKs); sem ela, desligado; agenda_gestor_dia.chamar (jsonb, não nulo); agenda_disponibilidade
--      com semana_dita, mensagem_id e pergunta_id
--   T  os 26 CHECKs por nome do P1, o índice agenda_disp_semana, as listas fechadas com os valores da 7b (so_pontas, dias,
--      dias_semana — fora da expressão de critica — e equipe_semana)
--   F  as funções novas de P2 a P6 existem; nenhuma executável por anon; as portas de cada grupo (as leituras: authenticated e
--      service_role; a rodada e as de texto: só service_role; o gravador e o motivo da pergunta do dono: ninguém); as recriadas de P1
--      a P6 estão com o bloco da 7b (a versão certa); o rascunho dos dias com a assinatura de 9 argumentos (a de 8 saiu)
--   S  agenda_saude().equipe_dias: os 11 zeros obrigatórios (zeros_ok); os modos que a saúde mostra são os da linha; nenhum erro
--      equipe_semana:% em 24 h nem aberto em app_error_logs; a última rodada da semana da equipe (só mostra)
--   L  o cartão da OS tem a chave equipe (nula com modo_dupla desligado; com o texto fora dele); os focos equipe e gestor devolvem o
--      texto e o mesmo texto duas vezes (md5)
--   O md5 de cada função que a 7b cria ou recria fica no molde da 7a (sql/wf7b_md5_esperado.sql do scratchpad, gerado da bancada na
--   ponta por f7b/p5/md5-gerar.mjs; refazer depois do P6 e de cada correção): rodar junto com este, depois do passo 1.
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 1 (estrutura), de novo DEPOIS do passo 3 (a migration de dado) e depois de cada "ligar" de
--   fila-do-dono/fase7b-oks.md, com o OK do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7b_pos_deploy.sql
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pd on commit drop as
select exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261101100900') as sombra,
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261101100500') as p6,
       coalesce(current_setting('agenda_teste.fase7b', true), '') <> '' as bancada;

-- ── M. Versões registradas ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v),
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = v),
       null
  from unnest(array['20261101100000', '20261101100100', '20261101100200', '20261101100300', '20261101100400']) v;

insert into _resultado
select 'M1b migration 20261101100500 (o P6: quem chamar e a dupla completa) registrada', (select p6 from _pd), null
 where not (select bancada and not p6 from _pd);

insert into _resultado
select 'M2 a correção da revisão (20261101100800/100850) e a migration de dado 20261101100900 (os 5 modos em teste) — só mostra', true,
       format('correção: %s; dado: %s',
              coalesce((select string_agg(m.version, ', ' order by m.version) from supabase_migrations.schema_migrations m
                         where m.version in ('20261101100800', '20261101100850')), 'nenhuma'),
              case when (select sombra from _pd) then 'registrada (passo 3 feito)' else 'não registrada (antes do passo 3)' end);

-- ── C. A configuração ───────────────────────────────────────────────────────────────────────────────────
create temp table _pd_colunas (tabela text, coluna text) on commit drop;
insert into _pd_colunas
select 'agenda_config', x from unnest(array['modo_dias', 'modo_dupla', 'modo_sabado', 'modo_cadastro', 'modo_chamar',
  'equipe_hora_dias', 'equipe_dias_semanas_a_frente', 'equipe_dias_tentar_dias', 'equipe_dias_fechar_antes', 'dono_dias_semanal',
  'dono_como_tecnico', 'dono_carga_max', 'dias_semana_motivos', 'dupla_tec_viagem_min', 'dupla_espera_max_du', 'novato_dias',
  'novato_diarias', 'novato_sozinho', 'sob_demanda_sozinho', 'falta_semanas', 'falta_dias_min', 'equipe_chamada_dias',
  'equipe_chamada_prazo_du', 'equipe_cadastro_abertas_max', 'chamar_min_meios', 'chamar_max_os']) x
union all select 'agenda_gestor_dia', 'chamar'
union all select 'agenda_disponibilidade', x from unnest(array['semana_dita', 'mensagem_id', 'pergunta_id']) x;

insert into _resultado
select 'C1 agenda_config tem os 5 modos e os 21 parâmetros da 7b (26 colunas) e não tem equipe_inativo_dias',
       count(*) filter (where c.column_name is null) = 0
       and not exists (select 1 from information_schema.columns c2 where c2.table_schema = 'public' and c2.table_name = 'agenda_config'
                         and c2.column_name = 'equipe_inativo_dias'),
       format('%s de 26; faltam: %s', count(c.column_name), coalesce(string_agg(k.coluna, ', ') filter (where c.column_name is null), '—'))
  from _pd_colunas k
  left join information_schema.columns c on c.table_schema = 'public' and c.table_name = k.tabela and c.column_name = k.coluna
 where k.tabela = 'agenda_config';

insert into _resultado
select 'C2 os 5 modos da 7b: com a 100900 registrada, sombra (ou ligado com os OKs); sem ela, desligado',
       case when (select sombra from _pd)
            then array[c.modo_dias, c.modo_dupla, c.modo_sabado, c.modo_cadastro, c.modo_chamar] <@ array['sombra', 'ligado']
            else array[c.modo_dias, c.modo_dupla, c.modo_sabado, c.modo_cadastro, c.modo_chamar] <@ array['desligado'] end,
       format('dias %s, dupla %s, sabado %s, cadastro %s, chamar %s; dono_carga_max %s, dono_como_tecnico %s, sabado_manha %s',
              c.modo_dias, c.modo_dupla, c.modo_sabado, c.modo_cadastro, c.modo_chamar, c.dono_carga_max, c.dono_como_tecnico,
              c.sabado_manha)
  from public.agenda_config c where c.id;

insert into _resultado
select format('C3 %s tem as colunas da 7b (%s)', k.tabela, string_agg(k.coluna, ', ')),
       count(*) filter (where c.column_name is null) = 0
       and (k.tabela <> 'agenda_gestor_dia'
            or exists (select 1 from information_schema.columns c2 where c2.table_schema = 'public' and c2.table_name = 'agenda_gestor_dia'
                         and c2.column_name = 'chamar' and c2.data_type = 'jsonb' and c2.is_nullable = 'NO')),
       coalesce('faltam: ' || string_agg(k.coluna, ', ') filter (where c.column_name is null), null)
  from _pd_colunas k
  left join information_schema.columns c on c.table_schema = 'public' and c.table_name = k.tabela and c.column_name = k.coluna
 where k.tabela <> 'agenda_config'
 group by k.tabela;

-- ── T. Os CHECKs, o índice e as listas ─────────────────────────────────────────────────────────────────────
insert into _resultado
select 'T1 os 26 CHECKs por nome do P1 (22 de agenda_config, 3 de agenda_disponibilidade, o de agenda_gestor_dia.chamar)',
       count(*) filter (where k.oid is null) = 0,
       coalesce('faltam: ' || string_agg(n.nome, ', ') filter (where k.oid is null), '26')
  from unnest(array['agenda_config_modo_dias_check', 'agenda_config_modo_dupla_check', 'agenda_config_modo_sabado_check',
    'agenda_config_modo_cadastro_check', 'agenda_config_modo_chamar_check', 'agenda_config_equipe_hora_dias_check',
    'agenda_config_equipe_dias_semanas_a_frente_check', 'agenda_config_equipe_dias_tentar_dias_check',
    'agenda_config_equipe_dias_fechar_antes_check', 'agenda_config_dono_carga_max_check', 'agenda_config_dias_semana_motivos_check',
    'agenda_config_dupla_tec_viagem_min_check', 'agenda_config_dupla_espera_max_du_check', 'agenda_config_novato_dias_check',
    'agenda_config_novato_diarias_check', 'agenda_config_falta_semanas_check', 'agenda_config_falta_dias_min_check',
    'agenda_config_equipe_chamada_dias_check', 'agenda_config_equipe_chamada_prazo_du_check',
    'agenda_config_equipe_cadastro_abertas_max_check', 'agenda_config_chamar_min_meios_check', 'agenda_config_chamar_max_os_check',
    'disp_semana_e_segunda', 'disp_semana_so_excecao', 'disp_so_pontas_excecao', 'agenda_gestor_dia_chamar_check']) n(nome)
  left join pg_constraint k on k.conname = n.nome and k.connamespace = 'public'::regnamespace;

insert into _resultado
select 'T2 o índice agenda_disp_semana (a semana presa de cada pessoa) existe',
       to_regclass('public.agenda_disp_semana') is not null, null;

insert into _resultado
select 'T3 as listas fechadas com os da 7b: so_pontas, a mensagem dias, a pergunta dias_semana (fora da expressão de critica) e a rotina equipe_semana',
       (select pg_get_constraintdef(k.oid) from pg_constraint k
         where k.conrelid = 'public.agenda_disponibilidade'::regclass and k.conname = 'agenda_disponibilidade_situacao_check') ~ '''so_pontas'''
       and (select pg_get_constraintdef(k.oid) from pg_constraint k
             where k.conrelid = 'public.agenda_equipe_mensagens'::regclass and k.conname = 'agenda_equipe_mensagens_tipo_check') ~ '''dias'''
       and (select pg_get_constraintdef(k.oid) from pg_constraint k
             where k.conrelid = 'public.agenda_perguntas'::regclass and k.conname = 'agenda_perguntas_tipo_check') ~ '''dias_semana'''
       and (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
             where d.adrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica') !~ '''dias_semana'''
       and (select pg_get_constraintdef(k.oid) from pg_constraint k
             where k.conrelid = 'public.agenda_vigia_rodadas'::regclass and k.conname = 'agenda_vigia_rodadas_rotina_check') ~ '''equipe_semana''',
       null;

-- ── F. As funções ───────────────────────────────────────────────────────────────────────────────────────
create temp table _pd_funcoes (f text primary key, porta text not null, pacote text not null) on commit drop;
insert into _pd_funcoes values
  -- as leituras (STABLE/IMMUTABLE, invoker): authenticated (o painel e o foco equipe) e service_role
  ('_agenda_dias_curtos(smallint[], boolean)', 'leitura', 'P2'), ('_agenda_semana_perguntada(date)', 'leitura', 'P2'),
  ('_agenda_dias_declarados(uuid, date)', 'leitura', 'P2'), ('_agenda_chance_de_falta(uuid, date)', 'leitura', 'P2'),
  ('_agenda_pessoa_extra_id()', 'leitura', 'P4'), ('_agenda_e_novato(uuid, date)', 'leitura', 'P4'),
  ('_agenda_e_sob_demanda(uuid, date)', 'leitura', 'P4'), ('_agenda_dupla_da_os(uuid)', 'leitura', 'P4'),
  ('_agenda_dupla_no_plano(uuid, date)', 'leitura', 'P5'), ('_agenda_saude_equipe7b(date, timestamptz)', 'leitura', 'P5'),
  -- a rodada da semana da equipe e as de texto da conversa: só o service_role (o task-automations, o WhatsApp)
  ('_agenda_semana_dita(text, text, date)', 'service_role', 'P2'), ('_agenda_ler_dias_da_equipe(text)', 'service_role', 'P3'),
  ('_agenda_equipe_previstas_hoje(uuid, date, timestamptz)', 'service_role', 'P3'),
  ('_agenda_equipe_texto_dias(uuid, date)', 'service_role', 'P3'), ('agenda_equipe_semana(date, timestamptz)', 'service_role', 'P3'),
  -- o gravador da semana e o motivo da pergunta do dono: ninguém de fora (nem o service_role)
  ('_agenda_equipe_dias_gravar(uuid, date, smallint[], boolean, text, text, timestamptz, uuid, uuid, uuid)', 'interna', 'P2'),
  ('_agenda_dias_semana_motivos(date, date)', 'interna', 'P3'),
  -- o P6 (quem chamar e a dupla completa): as portas são as do P6; aqui só existir e nunca anon
  -- FASE 7b (P6): as 5 do P6 (com _agenda_meios_frase, que a spec não nomeava) são peças de dentro: ninguém de fora (nem o
  -- service_role); só a rodada do gestor (definer) as chama. A porta entra no F3 (interna).
  ('_agenda_dupla_faltando(uuid, date)', 'interna', 'P6'), ('_agenda_quem_chamar(date, timestamptz)', 'interna', 'P6'),
  ('_agenda_gestor_chamar(date, timestamptz)', 'interna', 'P6'), ('_agenda_gestor_dupla(date, timestamptz)', 'interna', 'P6'),
  ('_agenda_meios_frase(jsonb, boolean)', 'interna', 'P6');

insert into _resultado
select format('F1 as %s funções novas de P2 a P5 existem', count(*)),
       count(*) filter (where to_regprocedure('public.' || f) is null) = 0,
       coalesce(string_agg(f, ', ') filter (where to_regprocedure('public.' || f) is null), 'todas')
  from _pd_funcoes where pacote <> 'P6';

insert into _resultado
select 'F1b as 5 funções novas do P6 existem (_agenda_dupla_faltando, _agenda_quem_chamar, _agenda_gestor_chamar, _agenda_gestor_dupla, _agenda_meios_frase)',
       count(*) filter (where to_regprocedure('public.' || f) is null) = 0,
       coalesce(string_agg(f, ', ') filter (where to_regprocedure('public.' || f) is null), 'todas')
  from _pd_funcoes where pacote = 'P6'
 having not (select bancada and not p6 from _pd);

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
  from (select f, porta, to_regprocedure('public.' || f) as o from _pd_funcoes where porta <> 'p6') x
 where x.o is not null
 group by x.porta;

insert into _resultado
select 'F4 nenhuma função da agenda (agenda_*, _agenda_*, os_*, _os_*) executável por anon',
       count(*) = 0, string_agg(p.proname, ', ')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname ~ '^(_?agenda_|_?os_)'
   and has_function_privilege('anon', p.oid, 'execute');

-- as recriadas: a versão no banco é a da 7b (tem o bloco "-- FASE 7b")
create temp table _pd_recriadas (f text primary key, pacote text not null) on commit drop;
insert into _pd_recriadas values
  ('_agenda_modo_da_pergunta(text, text)', 'P1'),
  ('agenda_capacidade(date, date, date)', 'P2'), ('agenda_capacidade_semanal(date)', 'P2'),
  ('agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text)', 'P2'),
  ('_agenda_aplicar_disponibilidade(uuid, jsonb, text, date)', 'P2'), ('agenda_rascunho_gravar(uuid, date)', 'P2'),
  ('agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)', 'P2'), ('_agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)', 'P2'),
  ('_agenda_rascunho_frase(text, jsonb)', 'P2'),
  ('_agenda_equipe_registrar(uuid, date, text, text, timestamptz, date, text)', 'P3'), ('_agenda_rotina_sem_resposta(date, timestamptz)', 'P3'),
  ('agenda_resposta_da_equipe(text, text, text, timestamptz)', 'P3'),
  ('agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', 'P3'), ('agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'P3'),
  ('_agenda_ver_equipe(date)', 'P3'), ('_agenda_linhas_do_fechamento(date)', 'P3'), ('_agenda_gestor_equipe(date, timestamptz)', 'P3'),
  ('os_duracao_sugerida(uuid)', 'P4'), ('agenda_meios_da_os(uuid, date)', 'P4'),
  ('_agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)', 'P4'), ('_agenda_tecnicos_da_grade(date)', 'P4'),
  ('_agenda_carga_da_pessoa(uuid)', 'P4'), ('_agenda_gestor_pessoa_meios(uuid, date, jsonb)', 'P4'),
  ('_agenda_contexto(date, date, date, uuid[], uuid[])', 'P4'),
  ('_agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer)', 'P4'),
  ('_agenda_encaixar(jsonb, jsonb, jsonb)', 'P4'), ('_agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)', 'P4'),
  ('_agenda_melhor(jsonb, jsonb)', 'P4'), ('agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'P4'),
  ('_agenda_gestor_sabado(date, timestamptz)', 'P4'),
  ('os_plano_da_os(uuid, date)', 'P5'), ('agenda_saude(date, timestamptz)', 'P5'),
  ('agenda_gestor_rodar(date, timestamptz)', 'P6'), ('_agenda_gestor_dia_gravar(date, text, jsonb, timestamptz)', 'P6'),
  ('_agenda_ver_gestor(date)', 'P6'), ('agenda_livre_de_verdade(date, timestamptz)', 'P6'),
  ('_agenda_gestor_corte(uuid, date, timestamptz)', 'P6');

insert into _resultado
select format('F5 as %s recriadas de P1 a P5 estão no banco com o bloco da 7b (a versão certa)', count(*)),
       count(*) filter (where p.oid is null or p.prosrc not like '%-- FASE 7b%') = 0,
       coalesce(string_agg(r.f, ', ') filter (where p.oid is null or p.prosrc not like '%-- FASE 7b%'), 'todas')
  from _pd_recriadas r left join pg_proc p on p.oid = to_regprocedure('public.' || r.f)
 where r.pacote <> 'P6';

insert into _resultado
select 'F5b as 5 recriadas do P6 (e _agenda_dias_semana_motivos com o motivo chamar) estão no banco com o bloco da 7b',
       count(*) filter (where p.oid is null or p.prosrc not like '%-- FASE 7b%') = 0
       and coalesce((select p2.prosrc like '%chamar%' from pg_proc p2 where p2.oid = to_regprocedure('public._agenda_dias_semana_motivos(date, date)')), false),
       coalesce(string_agg(r.f, ', ') filter (where p.oid is null or p.prosrc not like '%-- FASE 7b%'), 'todas')
  from _pd_recriadas r left join pg_proc p on p.oid = to_regprocedure('public.' || r.f)
 where r.pacote = 'P6'
 having not (select bancada and not p6 from _pd);

insert into _resultado
select 'F6 o rascunho dos dias com a semana (9 argumentos) existe e a assinatura de 8 saiu (o ai-agent chama pelo nome)',
       to_regprocedure('public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text)') is not null
       and to_regprocedure('public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date)') is null,
       null;

-- ── S. A saúde dos dias da equipe e da dupla ─────────────────────────────────────────────────────────────────
create temp table _pd_saude on commit drop as
select public.agenda_saude() as s;

insert into _resultado
select 'S1 agenda_saude().equipe_dias: os 11 zeros obrigatórios (zeros_ok) e os modos da linha',
       coalesce((x.s #>> '{equipe_dias,zeros_ok}')::boolean, false)
       and x.s #>> '{equipe_dias,modos,dias}' = c.modo_dias and x.s #>> '{equipe_dias,modos,dupla}' = c.modo_dupla
       and x.s #>> '{equipe_dias,modos,sabado}' = c.modo_sabado and x.s #>> '{equipe_dias,modos,cadastro}' = c.modo_cadastro
       and x.s #>> '{equipe_dias,modos,chamar}' = c.modo_chamar,
       left((x.s -> 'equipe_dias')::text, 900)
  from _pd_saude x, public.agenda_config c where c.id;

insert into _resultado
select 'S2 nenhum erro equipe_semana:% em 24 h (a saúde) nem aberto em app_error_logs',
       coalesce((x.s #>> '{equipe_dias,erros_24h}')::int, 0) = 0
       and not exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action like 'equipe_semana:%'
                         and e.resolved_at is null),
       format('24 h: %s; abertos: %s', x.s #>> '{equipe_dias,erros_24h}',
              (select count(*) from public.app_error_logs e where e.context = 'agenda' and e.action like 'equipe_semana:%' and e.resolved_at is null))
  from _pd_saude x;

insert into _resultado
select 'S3 a última rodada da semana da equipe (só mostra; sem modo_dias nem modo_cadastro fora de desligado, ela não grava rodada)', true,
       format('última: %s; em 24 h: %s; números: %s', coalesce(x.s #>> '{equipe_dias,ultima_rodada}', 'nenhuma'),
              x.s #>> '{equipe_dias,rodadas_24h}', left((x.s #> '{equipe_dias,numeros}')::text, 500))
  from _pd_saude x;

-- ── L. As leituras ─────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'L1 o cartão da OS tem a chave equipe: nula com modo_dupla desligado; com ele fora de desligado, o texto (na OS que ainda vai ser feita)',
       case when k.service_order_id is null then true
            when c.modo_dupla = 'desligado' then public.os_plano_da_os(k.service_order_id) ? 'equipe'
                                                 and public.os_plano_da_os(k.service_order_id) -> 'equipe' = 'null'::jsonb
            else public.os_plano_da_os(k.service_order_id) #>> '{equipe,texto}' is not null end,
       case when k.service_order_id is null then 'PULADO: nenhuma OS na carteira'
            else coalesce(public.os_plano_da_os(k.service_order_id) #>> '{equipe,texto}', '(nula)') end
  from public.agenda_config c
  left join lateral (select x.service_order_id from public.os_carteira(public._hoje_brt()) x
                      join public.service_orders so on so.id = x.service_order_id
                     where so.status not in ('completed', 'invoiced', 'cancelled')
                     order by so.service_order_number limit 1) k on true
 where c.id;

create temp table _pd_leituras on commit drop as
select f, public.agenda_ver(p_foco => f) as v1, public.agenda_ver(p_foco => f) as v2,
       (select c.modo_leitura from public.agenda_config c where c.id) as leitura
  from unnest(array['equipe', 'gestor']) f;

insert into _resultado
select format('L2 o foco %s devolve o texto (com a leitura desligada: "a agenda de produção está desligada") e o mesmo texto duas vezes (md5)', l.f),
       case when l.leitura = 'desligado' then l.v1 ->> 'rota' = 'desligada'
            else coalesce((l.v1 ->> 'ok')::boolean, false) and length(l.v1 ->> 'texto') > 0 end
       and md5(coalesce(l.v1 ->> 'texto', '')) = md5(coalesce(l.v2 ->> 'texto', '')),
       format('%s caracteres: %s', length(l.v1 ->> 'texto'), left(l.v1 ->> 'texto', 240))
  from _pd_leituras l;

select teste, ok, detalhe from _resultado order by teste;

rollback;
