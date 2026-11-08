-- Conferência DEPOIS de aplicar a Agenda de Produção, Fase 7f ("falar só o que importa"; os pacotes P1 a P4 e P7): as migrations 20261109100000, 100100, 100200, 100300 e
-- 100600, as funções de borda (ai-agent, erp-mcp, whatsapp-webhook, ai-daily-briefing e task-automations, com o passo 0e) e o dado 20261109100900 (os 3 modos com código em teste):
-- R8.14, passos 1 a 5 de fila-do-dono/fase77f-publicar.md. Spec: spec-fase7f.md §8.3 (agenda_fase7f_pos_deploy.sql), §11, R8.13, R8.14; as notas de P1 a P7 (notas-fase7f.md).
-- As listas saem do replay (f7f/p8/gerar.mjs: estado-b4 + o delta de produção de 08/11 + as 5 migrations 2× cada) e foram conferidas contra as notas de P1 a P7: 38 funções
-- (28 novas e 10 recriadas), nenhuma esquecida e nenhuma a mais, e os grants que as notas dizem.
-- bancada: depende de 20261109100600
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só nas tabelas TEMPORÁRIAS do resultado); agenda_saude e _agenda_ver_decisoes são STABLE; termina em ROLLBACK.
-- Na bancada (que não aplica a 20261109100900: lá os 6 modos ficam como a linha nasce, desligados) ele passa do mesmo jeito.
--
--   M  as 5 versões de estrutura registradas; o dado (100900) é mostrado
--   C  agenda_config: as 21 colunas e os 20 CHECKs da 7f; os 6 modos: com a 100900 registrada, os 3 com código (bloco, prazo, lote) em sombra — ou ligado, na ordem dos OKs: o
--      lote e o prazo só com o bloco ligado —, e os 3 sem código (previsto, convite, camadas) desligados enquanto as funções do P5 e do P6 não existirem; sem ela, os 6
--      desligados; o DEFAULT dos 6 é sombra; cliente_tipos_ligados sem semana enquanto as camadas não ligam; o freio (só mostra); agenda_perguntas com as 7 colunas e os 3 CHECKs;
--      agenda_equipe_mensagens com as 2 colunas
--   T  o CHECK dono_aviso_conta_mudanca presente e agenda_dono_avisos_acao_ids_check ausente; veto_nao_critica e pergunta_veto_so_com_padrao ausentes, veto_padrao_tem_prazo
--      presente; as listas fechadas com o que a 7f somou; o gatilho agenda_perguntas_padrao; modelo M12 para semana
--   F  cada uma das 38 funções da 7f (e o título, que só ganhou grant): a assinatura, 1 por nome, security definer, volatilidade, search_path=public e os grants (anon e PUBLIC
--      nunca); 1 assinatura de agenda_aviso_enfileirar, a de 7 argumentos; as recriadas com a marca do pacote mais novo que as recria
--   Z  agenda_saude().comunicacao com os 6 zeros em 0 e zeros_ok; os modos que ela lê = os da linha; *agenda pendências* pelo service_role sem erro (o caminho do WhatsApp,
--      NOVO-agenda-121); a mesma leitura duas vezes = o mesmo texto
--   S  nenhum erro comunicar:% (nem agenda:comunicar do task-automations) nas últimas 24 h; com o dado, a rodada comunicar dos últimos 30 min (o passo 0e do task-automations,
--      seg a sáb; no domingo só mostra); o cron do task-automations ativo de 15 em 15 min (sem pg_cron, só mostra)
--   O md5 de cada função que a 7f cria ou recria fica em sql/wf7f_md5_esperado.sql do scratchpad, e a 7a a 7d no que a 7f não toca em sql/wf7f_md5_7d_sem7f.sql: rodar junto com
--   este, depois do passo 1. Com a 7f publicada, os md5 da 7d (wf7d_md5_esperado e wf7d_md5_7a_sem7b7c7d) dão "diferentes" nas 9 que ela recria: vale o wf7f_md5_7d_sem7f.
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 1 (estrutura), de novo DEPOIS do passo 3 (o dado), no dia seguinte e antes de cada "ligar":
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7f_pos_deploy.sql
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pd on commit drop as
select exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261109100900') as dado,
       to_regprocedure('public._agenda_comunicar_previsto(date, timestamptz)') is not null
         and to_regprocedure('public._agenda_comunicar_mudancas_equipe(date, timestamptz)') is not null as p5_previsto,
       to_regprocedure('public._agenda_comunicar_convites(date, timestamptz)') is not null
         and to_regprocedure('public._agenda_comunicar_convites_vencidos(date, timestamptz)') is not null as p5_convite,
       to_regprocedure('public._agenda_cliente_semana(date, timestamptz)') is not null
         and to_regprocedure('public._agenda_cliente_camada(uuid, date)') is not null as p6_camadas;

-- ── M. As migrations ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v), exists (select 1 from supabase_migrations.schema_migrations m where m.version = v), null
  from unnest(array['20261109100000', '20261109100100', '20261109100200', '20261109100300', '20261109100600']) v;
insert into _resultado
select 'M2 a migration de dado 20261109100900 (os 3 modos com código em teste) — só mostra', true,
       case when (select dado from _pd) then 'registrada (passo 3 feito)' else 'não registrada (antes do passo 3)' end;

-- ── C. A configuração e as colunas ────────────────────────────────────────────────────────────────
insert into _resultado
select 'C1 agenda_config tem as 21 colunas da 7f (os 6 modos e os 15 parâmetros) e os 20 CHECKs por nome',
       count(*) filter (where c.column_name is null) = 0
       and (select count(*) from pg_constraint k where k.conrelid = 'public.agenda_config'::regclass and k.conname = any (array[
             'agenda_config_modo_bloco_agenda_check', 'agenda_config_modo_veto_check', 'agenda_config_modo_lote_dono_check', 'agenda_config_modo_equipe_previsto_check',
             'agenda_config_modo_equipe_convite_check', 'agenda_config_modo_cliente_camadas_check', 'agenda_config_bloco_max_chars_check', 'agenda_config_bloco_decisoes_max_check',
             'agenda_config_bloco_mudancas_max_check', 'agenda_config_bloco_compras_max_check', 'agenda_config_bloco_compras_du_check', 'agenda_config_veto_tipos_check',
             'agenda_config_perguntas_abertas_max_check', 'agenda_config_dono_semana_aviso_check', 'agenda_config_dono_semana_hora_check',
             'agenda_config_equipe_convite_antecedencia_h_check', 'agenda_config_cliente_dia_exato_du_check', 'agenda_config_cliente_semana_du_check',
             'agenda_config_cliente_camadas_para_check', 'agenda_config_comunicar_tempo_max_check'])) = 20,
       format('%s de 21; faltam: %s', count(c.column_name), coalesce(string_agg(k.x, ', ') filter (where c.column_name is null), '—'))
  from unnest(array[
  'modo_bloco_agenda', 'modo_veto', 'modo_lote_dono', 'modo_equipe_previsto', 'modo_equipe_convite', 'modo_cliente_camadas',
  'bloco_max_chars', 'bloco_decisoes_max', 'bloco_mudancas_max', 'bloco_compras_max', 'bloco_compras_du', 'veto_tipos', 'perguntas_abertas_max', 'perguntas_primeiro',
  'dono_semana_aviso', 'dono_semana_hora', 'equipe_convite_antecedencia_h', 'cliente_dia_exato_du', 'cliente_semana_du', 'cliente_camadas_para', 'comunicar_tempo_max']) k(x)
  left join information_schema.columns c on c.table_schema = 'public' and c.table_name = 'agenda_config' and c.column_name = k.x;
-- C2: os valores do dado. Com a 100900: os 3 com código em sombra, ou ligado na ordem dos OKs (o lote e o prazo só com o bloco ligado: ligar-fase7f.sql); os 3 sem código
-- desligados enquanto o pacote deles não existir (com as funções do P5 ou do P6 no banco, o que o dado deles puser). Sem a 100900, os 6 desligados.
insert into _resultado
select 'C2 os 6 modos com os valores do dado: com ele, bloco, prazo e lote em teste (ou ligados na ordem dos OKs) e previsto, convite e camadas desligados; sem ele, os 6 desligados',
       case when (select dado from _pd)
            then c.modo_bloco_agenda in ('sombra', 'ligado')
                 and (c.modo_lote_dono = 'sombra' or (c.modo_lote_dono = 'ligado' and c.modo_bloco_agenda = 'ligado'))
                 and (c.modo_veto = 'sombra' or (c.modo_veto = 'ligado' and c.modo_bloco_agenda = 'ligado'))
                 and (c.modo_equipe_previsto = 'desligado' or (select p5_previsto from _pd))
                 and (c.modo_equipe_convite = 'desligado' or (select p5_convite from _pd))
                 and (c.modo_cliente_camadas = 'desligado' or (select p6_camadas from _pd))
            else array[c.modo_bloco_agenda, c.modo_veto, c.modo_lote_dono, c.modo_equipe_previsto, c.modo_equipe_convite, c.modo_cliente_camadas] <@ array['desligado'] end,
       format('bloco %s, prazo %s, lote %s, previsto %s, convite %s, camadas %s; o freio %s', c.modo_bloco_agenda, c.modo_veto, c.modo_lote_dono, c.modo_equipe_previsto,
              c.modo_equipe_convite, c.modo_cliente_camadas, c.gestor_so_propor)
  from public.agenda_config c where c.id;
insert into _resultado
select 'C3 o DEFAULT dos 6 modos é sombra (a linha nasce desligada)', count(*) = 6, format('%s de 6', count(*))
  from information_schema.columns d
 where d.table_schema = 'public' and d.table_name = 'agenda_config'
   and d.column_name in ('modo_bloco_agenda', 'modo_veto', 'modo_lote_dono', 'modo_equipe_previsto', 'modo_equipe_convite', 'modo_cliente_camadas')
   and d.column_default like '''sombra''%';
insert into _resultado
select 'C4 cliente_tipos_ligados sem semana enquanto as camadas não ligam (o dado não a põe; só o "OK semana prevista ao cliente")',
       not ('semana' = any (c.cliente_tipos_ligados)) or c.modo_cliente_camadas = 'ligado', array_to_string(c.cliente_tipos_ligados, ', ')
  from public.agenda_config c where c.id;
insert into _resultado
select 'C5 o freio — só mostra (com gestor_so_propor, o prazo ligado vale como em teste: nada vence)', true,
       format('gestor_so_propor %s desde %s', c.gestor_so_propor, c.gestor_so_propor_em)
  from public.agenda_config c where c.id;
insert into _resultado
select 'C6 agenda_perguntas com as 7 colunas e os 3 CHECKs da 7f; agenda_equipe_mensagens com dias e alocacao_ids',
       (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'agenda_perguntas'
           and c.column_name in ('padrao_chave', 'padrao_efeito', 'veto_espera', 'veto_teria_em', 'destrava', 'assumida_por', 'assumida_em')) = 7
       and (select count(*) from pg_constraint k where k.conrelid = 'public.agenda_perguntas'::regclass
              and k.conname in ('pergunta_padrao_coerente', 'pergunta_assumida_coerente', 'pergunta_assumida_fechada')) = 3
       and (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'agenda_equipe_mensagens'
              and c.column_name in ('dias', 'alocacao_ids')) = 2,
       null;

-- ── T. As tabelas e as listas ─────────────────────────────────────────────────────────────────────
insert into _resultado
select 'T1 agenda_dono_avisos: o CHECK dono_aviso_conta_mudanca (a mensagem da semana sem ação, só com pergunta) presente e agenda_dono_avisos_acao_ids_check ausente',
       exists (select 1 from pg_constraint k where k.conrelid = 'public.agenda_dono_avisos'::regclass and k.conname = 'dono_aviso_conta_mudanca'
                 and pg_get_constraintdef(k.oid) like '%agenda-dono:semana:%' and pg_get_constraintdef(k.oid) like '%pergunta_ids%')
       and not exists (select 1 from pg_constraint k where k.conrelid = 'public.agenda_dono_avisos'::regclass and k.conname = 'agenda_dono_avisos_acao_ids_check')
       and not exists (select 1 from pg_constraint k where k.conrelid = 'public.agenda_dono_avisos'::regclass and k.contype = 'c'
                         and pg_get_constraintdef(k.oid) ~ '^CHECK \(\(cardinality\(acao_ids\) > 0\)\)$'),
       (select string_agg(k.conname, ', ' order by k.conname) from pg_constraint k where k.conrelid = 'public.agenda_dono_avisos'::regclass and k.contype = 'c');
insert into _resultado
select 'T2 agenda_perguntas: veto_nao_critica e pergunta_veto_so_com_padrao ausentes (R8.5-1, AG7-15); veto_padrao_tem_prazo presente',
       not exists (select 1 from pg_constraint k where k.conrelid = 'public.agenda_perguntas'::regclass and k.conname in ('veto_nao_critica', 'pergunta_veto_so_com_padrao'))
       and exists (select 1 from pg_constraint k where k.conrelid = 'public.agenda_perguntas'::regclass and k.conname = 'veto_padrao_tem_prazo'),
       null;
insert into _resultado
select format('T3 a lista %s tem %s', x.nome, x.valor), pg_get_constraintdef(k.oid) like '%''' || x.valor || '''%', null
  from (values ('agenda_acoes_tipo_check', 'assumir'), ('agenda_perguntas_respondida_via_check', 'prazo'), ('agenda_vigia_rodadas_rotina_check', 'comunicar'),
               ('agenda_equipe_mensagens_tipo_check', 'previsto'), ('agenda_equipe_mensagens_tipo_check', 'mudanca'), ('agenda_equipe_mensagens_tipo_check', 'convite'),
               ('agenda_cliente_mensagens_tipo_check', 'semana'), ('agenda_config_cliente_tipos_ligados_check', 'semana')) x(nome, valor)
  left join pg_constraint k on k.conname = x.nome;
insert into _resultado
select 'T4 o gatilho agenda_perguntas_padrao (BEFORE INSERT, ativo) e o modelo M12 para semana',
       exists (select 1 from pg_trigger g where g.tgrelid = 'public.agenda_perguntas'::regclass and g.tgname = 'agenda_perguntas_padrao' and not g.tgisinternal
                 and g.tgenabled <> 'D' and g.tgfoid = to_regprocedure('public._agenda_perguntas_padrao()') and (g.tgtype & 2) = 2 and (g.tgtype & 4) = 4)
       and (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
             where d.adrelid = 'public.agenda_cliente_mensagens'::regclass and a.attname = 'modelo') ~ 'semana.*M12',
       null;

-- ── F. As funções ─────────────────────────────────────────────────────────────────────────────────
-- (assinatura, security definer, volatilidade, quem executa além do dono: authenticated e/ou service_role; o resto nunca, nem anon nem PUBLIC; o tipo)
create temp table _pd_f (f text primary key, definer boolean not null, vol "char" not null, papeis text not null, tipo text not null) on commit drop;
insert into _pd_f values
  ('_agenda_bloco_destino(text)', false, 'i', '', 'nova'),
  ('_agenda_bloco_linha(text,text,integer,integer,uuid,jsonb)', false, 'i', '', 'nova'),
  ('_agenda_classe_da_saida(text,uuid,date,timestamptz)', false, 's', '', 'nova'),
  ('_agenda_comunicar_destrava(date,timestamptz)', false, 'v', '', 'nova'),
  ('_agenda_comunicar_lote_guardaria(date,timestamptz)', false, 's', '', 'nova'),
  ('_agenda_comunicar_quinta(date,timestamptz)', false, 'v', '', 'nova'),
  ('_agenda_comunicar_teto(date,timestamptz)', false, 'v', '', 'nova'),
  ('_agenda_destrava(public.agenda_perguntas,date)', false, 's', '', 'nova'),
  ('_agenda_e_excecao(jsonb,date,timestamptz)', false, 's', '', 'nova'),
  ('_agenda_fala_modo(text)', false, 's', 'authenticated service_role', 'nova'),
  ('_agenda_feito_planejado(date)', false, 's', '', 'nova'),
  ('_agenda_gestor_vetos(date,timestamptz)', false, 'v', '', 'recriada'),
  ('_agenda_lote_cota(date)', false, 's', '', 'nova'),
  ('_agenda_lote_fora(jsonb)', false, 's', '', 'nova'),
  ('_agenda_lote_ligado()', false, 's', '', 'nova'),
  ('_agenda_lote_mudancas(date)', false, 's', '', 'nova'),
  ('_agenda_lote_texto(jsonb)', false, 'i', '', 'nova'),
  ('_agenda_padrao_da_pergunta(text,boolean,uuid,jsonb,smallint,uuid[])', false, 's', '', 'nova'),
  ('_agenda_pergunta_assumir(uuid,text,date,timestamptz)', false, 'v', '', 'nova'),
  ('_agenda_pergunta_espera(public.agenda_perguntas,date)', false, 's', '', 'nova'),
  ('_agenda_pergunta_frases(public.agenda_perguntas,date)', false, 's', '', 'nova'),
  ('_agenda_pergunta_linha(uuid,date,timestamptz)', false, 's', '', 'nova'),
  ('_agenda_perguntas_antes()', false, 'v', 'service_role', 'recriada'),
  ('_agenda_perguntas_padrao()', true, 'v', '', 'nova'),
  ('_agenda_saude_comunicacao(date,timestamptz)', true, 's', 'authenticated service_role', 'nova'),
  ('_agenda_titulo_da_pergunta(text)', false, 'i', 'authenticated service_role', 'grant'),
  ('_agenda_ver_decisoes(date,timestamptz)', false, 's', 'authenticated service_role', 'recriada'),
  ('_agenda_zona(uuid,uuid,date,date)', false, 's', '', 'nova'),
  ('agenda_aviso_enfileirar(text,uuid[],uuid[],boolean,date,timestamptz,boolean)', true, 'v', 'service_role', 'recriada'),
  ('agenda_aviso_pecas(date,timestamptz)', true, 's', 'service_role', 'recriada'),
  ('agenda_bloco_do_fechamento(date,timestamptz,jsonb)', true, 's', 'authenticated service_role', 'nova'),
  ('agenda_comunicar_rodar(date,timestamptz)', true, 'v', 'service_role', 'nova'),
  ('agenda_decidir(uuid,smallint,uuid,text,text,date,timestamptz)', true, 'v', 'service_role', 'recriada'),
  ('agenda_desfazer(uuid,uuid,text,date,timestamptz)', true, 'v', 'service_role', 'recriada'),
  ('agenda_fechamento_registrar(date,jsonb,text,timestamptz)', true, 'v', 'service_role', 'recriada'),
  ('agenda_perguntas_em_ordem(date,timestamptz)', true, 's', 'authenticated service_role', 'nova'),
  ('agenda_saude(date,timestamptz)', false, 's', 'authenticated service_role', 'recriada'),
  ('agenda_textos_do_fechamento(date,date)', false, 's', 'authenticated service_role', 'recriada'),
  ('agenda_veto_dito(uuid,text,text,date,timestamptz)', true, 'v', 'service_role', 'nova');
insert into _resultado
select format('F1 %s (%s): existe, 1 por nome, %s, %s, search_path=public, executa: %s', r.f, r.tipo, case when r.definer then 'definer' else 'invoker' end,
              case r.vol when 'i' then 'immutable' when 's' then 'stable' else 'volatile' end, coalesce(nullif(r.papeis, ''), 'ninguém de fora')),
       p.oid is not null
       and (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) = 1
       and p.prosecdef = r.definer and p.provolatile = r.vol and 'search_path=public' = any (coalesce(p.proconfig, '{}'))
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('public', p.oid, 'execute')
       and has_function_privilege('authenticated', p.oid, 'execute') = (r.papeis like '%authenticated%')
       and has_function_privilege('service_role', p.oid, 'execute') = (r.papeis like '%service_role%'),
       case when p.oid is null then 'NÃO EXISTE'
            else format('assinaturas %s; definer %s; %s; %s; anon %s, public %s, authenticated %s, service_role %s',
                        (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname), p.prosecdef, p.provolatile, p.proconfig,
                        has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('public', p.oid, 'execute'),
                        has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('service_role', p.oid, 'execute')) end
  from _pd_f r
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f);
insert into _resultado
select 'F2 agenda_aviso_enfileirar: 1 assinatura, a de 7 argumentos (p_semana boolean DEFAULT false); a de 6 saiu',
       count(*) = 1 and bool_and(pg_get_function_arguments(p.oid) like '%p_semana boolean DEFAULT false%')
       and to_regprocedure('public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz)') is null,
       string_agg(pg_get_function_identity_arguments(p.oid), ' | ')
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'agenda_aviso_enfileirar';
insert into _resultado
select format('F3 %s com a marca do pacote mais novo que a recria (%s): uma migration mais velha reaplicada a voltaria', x.f, x.marca),
       p.oid is not null and p.prosrc like '%(' || x.marca || '%', null
  from (values ('_agenda_perguntas_antes', '7f P7'), ('_agenda_ver_decisoes', '7f P7'), ('agenda_saude', '7f P7'), ('agenda_aviso_pecas', '7f P4'),
               ('agenda_aviso_enfileirar', '7f P4'), ('agenda_comunicar_rodar', '7f P4'), ('agenda_textos_do_fechamento', '7f P3'), ('agenda_fechamento_registrar', '7f P3'),
               ('_agenda_gestor_vetos', '7f P2'), ('agenda_decidir', '7f P2'), ('agenda_desfazer', '7f P2')) x(f, marca)
  left join lateral (select y.oid, y.prosrc from pg_proc y where y.pronamespace = 'public'::regnamespace and y.proname = x.f limit 1) p on true;
insert into _resultado
select 'F4 as funções do P5 e do P6 — só mostra (sem elas, os 3 da equipe e do cliente ficam desligados e o ligar-fase7f.sql recusa)', true,
       format('P5 previsto %s, P5 convite %s, P6 camadas %s', (select p5_previsto from _pd), (select p5_convite from _pd), (select p6_camadas from _pd));

-- ── Z. A saúde e as leituras ──────────────────────────────────────────────────────────────────────
create temp table _pd_z on commit drop as
select public.agenda_saude() -> 'comunicacao' as com, (select to_jsonb(c) from public.agenda_config c where c.id) as cfg;
insert into _resultado
select 'Z1 agenda_saude().comunicacao: os 6 zeros em 0 e zeros_ok',
       coalesce((z.com ->> 'zeros_ok')::boolean, false)
       and (select count(*) from unnest(array['assumida_sem_prazo_mostrado', 'assumida_que_esperava', 'assumida_tipo_proibido', 'teto_passou_sem_motivo', 'bloco_grande',
                                              'excecao_acima_do_teto']) k where z.com ->> k = '0') = 6,
       left(z.com::text, 900)
  from _pd_z z;
insert into _resultado
select 'Z2 a saúde lê os 6 modos crus da linha (o freio não os troca ali)',
       z.com -> 'modos' = jsonb_build_object('bloco', z.cfg ->> 'modo_bloco_agenda', 'lote', z.cfg ->> 'modo_lote_dono', 'veto', z.cfg ->> 'modo_veto',
                                             'previsto', z.cfg ->> 'modo_equipe_previsto', 'convite', z.cfg ->> 'modo_equipe_convite', 'camadas', z.cfg ->> 'modo_cliente_camadas'),
       (z.com -> 'modos')::text
  from _pd_z z;
-- Z3: *agenda pendências* (o foco decisoes) pelo service_role, o papel do ai-agent e do erp-mcp no WhatsApp: com 8 abertas, o corte chama _agenda_titulo_da_pergunta, que
-- até a 7f não tinha grant (NOVO-agenda-121). Troca de papel só dentro deste bloco e volta ao de antes; sem poder trocar, confere os grants da leitura.
create temp table _pd_sr (texto text, texto2 text, erro text, trocou boolean) on commit drop;
do $sr$
declare
  v_antes text := current_user;
  v_t     text;
  v_t2    text;
  v_erro  text;
  v_troca boolean := true;
begin
  begin
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    execute 'set local role service_role';
  exception when others then
    v_troca := false;
    v_erro := 'não trocou de papel: ' || sqlerrm;
  end;
  if v_troca then
    begin
      v_t := public._agenda_ver_decisoes(public._hoje_brt(), now()) ->> 'texto';
      v_t2 := public._agenda_ver_decisoes(public._hoje_brt(), now()) ->> 'texto';
    exception when others then
      v_erro := sqlstate || ': ' || sqlerrm;
    end;
    execute format('set local role %I', v_antes);
  end if;
  perform set_config('request.jwt.claims', '', true);
  insert into _pd_sr values (v_t, v_t2, v_erro, v_troca);
end
$sr$;
insert into _resultado
select 'Z3 *agenda pendências* pelo service_role (o caminho do WhatsApp): sem erro, com texto (NOVO-agenda-121)',
       case when s.trocou then s.erro is null and coalesce(length(s.texto), 0) > 0
            else has_function_privilege('service_role', 'public._agenda_ver_decisoes(date, timestamptz)', 'execute')
                 and has_function_privilege('service_role', 'public._agenda_titulo_da_pergunta(text)', 'execute')
                 and has_function_privilege('service_role', 'public.agenda_perguntas_em_ordem(date, timestamptz)', 'execute') end,
       case when s.trocou then coalesce(s.erro, format('%s letras', length(s.texto))) else s.erro || ' (conferido pelos grants)' end
  from _pd_sr s;
insert into _resultado
select 'Z4 duas leituras seguidas de *agenda pendências* = o mesmo texto (md5)', not s.trocou or md5(coalesce(s.texto, '')) = md5(coalesce(s.texto2, '')), null
  from _pd_sr s;

-- ── S. Sem erro, e o tique ────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'S1 nenhum erro da rodada comunicar nas últimas 24 h (comunicar:% e agenda:comunicar do task-automations)', count(*) = 0,
       coalesce(string_agg(distinct e.context || '/' || e.action, ', '), 'nenhum')
  from public.app_error_logs e
 where e.last_seen_at >= now() - interval '24 hours'
   and ((e.context = 'agenda' and e.action like 'comunicar:%') or (e.context = 'task-automations' and e.action = 'agenda:comunicar'));
insert into _resultado
select 'S2 o passo 0e do task-automations chama agenda_comunicar_rodar: com o dado, uma rodada comunicar nos últimos 30 min, sem erro (sem o dado, ou no domingo, só mostra)',
       case when not (select dado from _pd) or extract(isodow from public._hoje_brt()) = 7 then true
            else exists (select 1 from public.agenda_vigia_rodadas r where r.rotina = 'comunicar' and r.rodou_em >= now() - interval '30 minutes' and r.erros = 0) end,
       coalesce((select format('a última: %s, erros %s, %s ms', r.rodou_em, r.erros, r.duracao_ms) from public.agenda_vigia_rodadas r where r.rotina = 'comunicar'
                  order by r.rodou_em desc limit 1), 'ainda não rodou');
create temp table _pd_cron (achou boolean, quando text, ativo boolean) on commit drop;
do $cr$
begin
  if to_regclass('cron.job') is not null then
    execute $q$insert into _pd_cron select true, j.schedule, j.active from cron.job j where j.jobname = 'task-automations' limit 1$q$;
  end if;
end
$cr$;
insert into _resultado
select 'S3 o cron do task-automations ativo, de 15 em 15 minutos (sem pg_cron, só mostra)',
       case when to_regclass('cron.job') is null then true else coalesce((select c.ativo and c.quando = '*/15 * * * *' from _pd_cron c), false) end,
       coalesce((select format('%s, ativo %s', c.quando, c.ativo) from _pd_cron c), case when to_regclass('cron.job') is null then 'sem pg_cron (bancada)' else 'não achei o job' end);

select teste, ok, detalhe from _resultado order by teste;

rollback;
