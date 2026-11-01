-- Conferência DEPOIS de aplicar a Agenda de Produção, Fase 7c (os pacotes P1 a P6 e o P8): migrations 20261102100000..100550 (e a
-- correção da revisão 20261102100580/100590, se houver), as edge functions (task-automations com os passos 0a — as etapas — e 0b2a — quem
-- faz o quê —; ai-agent e erp-mcp com equipe_habilidade, servico_etapa, o foco habilidades e as 2 linhas do prompt) e (passo 5) a
-- migration de dado 20261102100600 — os 4 modos da 7c em teste — fila-do-dono/fase77c-publicar.md, passos 2–5 (e de novo a cada "ligar",
-- passos 6 e 7).
-- Spec: spec-fase7c.md §10 passo 1, §16.10 passo 1, §16.9 ("O que o P8 muda no P7"), R5.5 (o pós-deploy) e R5.7-9.
-- bancada: depende de 20261102100550
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só nas tabelas TEMPORÁRIAS do resultado); agenda_ver, agenda_habilidade_medidas,
-- agenda_tarefas_medidas e _agenda_linhas_do_fechamento são STABLE e não gravam; agenda_tarefas_rodar só é chamada com modo_tarefas
-- desligado, quando ela devolve {rodou: false} antes de qualquer escrita; termina em ROLLBACK. Na bancada (que não aplica a 20261102100600:
-- lá os modos ficam como a linha está, desligado) ele passa do mesmo jeito.
--
--   M  as 7 versões de estrutura da 7c (P1 a P6 e o P8) registradas em supabase_migrations.schema_migrations; a correção da revisão
--      (20261102100580/100590) e a de dado (100600, a sombra) são mostradas. A correção, quando existir, entra na tabela _pd_correcoes
--      (abaixo; o molde M1c/F5c da conferência da 7b): daí ela passa a ser EXIGIDA — M1c (registrada) e F5c (as funções que ela recria no
--      banco com o bloco dela; uma migration mais velha reaplicada por cima as voltaria sem a correção e nada mais acusaria). Na bancada sem
--      a correção registrada, as duas não saem (na bancada nada pode sair PULADO)
--   C  agenda_config: os 4 modos e os 28 parâmetros da 7c (32 colunas: 20 do P1, 12 do P8); os modos: com a 100600 registrada, sombra (ou
--      ligado, depois dos OKs); sem ela, desligado; o DEFAULT dos 4 é sombra; os_planejamento com as 7 colunas (o que a OS pede, o
--      responsável e a assinatura das etapas) e agenda_alocacoes com o critério
--   T  os 42 CHECKs por nome (28 de agenda_config, 5 de agenda_etiquetas, 2 de os_planejamento, 3 de os_tarefas, 3 de os_tarefas_dia e o de
--      agenda_alocacoes.criterio); as 3 tabelas novas com a RLS e só a política de leitura TO authenticated (e o anon sem privilégio nenhum
--      nelas); os 6 índices; os 8 gatilhos ligados (o do critério BEFORE INSERT em agenda_alocacoes); as listas fechadas com os da 7c
--      (habilidade nas 5; tarefa, etapa e tarefas) e a expressão de critica sem eles
--   F  as 49 funções novas existem; nenhuma das 75 da 7c executável por anon; as portas das novas e das recriadas que a 7c concede de novo
--      (as leituras: authenticated e service_role; o motor, a rodada e as de texto: só service_role; as peças de dentro: ninguém); as 26
--      recriadas estão no banco com o bloco do pacote mais novo que as recria (a versão certa) e, as recriadas duas vezes dentro da 7c,
--      também com o do pacote de antes; a régua do telefone (_agenda_equipe_tem_telefone) com a porta de leitura e sem anon
--   S  nenhum erro habilidade:% nem tarefas:% em 24 h nem aberto em app_error_logs (nem agenda:habilidade / agenda:tarefas do
--      task-automations); a última rodada de quem faz o quê e a das etapas (só mostra)
--   L  o foco *agenda quem faz* devolve o texto (com a leitura desligada: "a agenda de produção está desligada") e o mesmo texto duas vezes
--      (md5); as medidas de quem faz o quê e das etapas respondem; com modo_tarefas desligado a rodada das etapas devolve {rodou: false};
--      o fechamento de hoje responde, com toda linha em até 480 letras e, com modo_tarefas desligado, sem a linha das etapas
--   O md5 de cada função que a 7c cria ou recria fica no molde da 7b (sql/wf7c_md5_esperado.sql do scratchpad, gerado da bancada na ponta
--   por f7c/p7/md5-gerar.mjs; refazer depois de cada correção): rodar junto com este, depois do passo 2. Com a 7c publicada, o md5 da 7b
--   (sql/wf7b_md5_esperado.sql) e o da 7a (sql/wf7c2_md5_sem7b.sql) dão "diferentes" nas que a 7c recria: valem sql/wf7b_md5_sem7c.sql e
--   sql/wf7c2_md5_sem7b7c.sql (os mesmos sem elas).
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 2 (estrutura), de novo DEPOIS do passo 5 (a migration de dado) e depois de cada "ligar" de
--   fila-do-dono/fase77c-publicar.md, com o OK do dono (ou pelo OK permanente "publicar em teste cada etapa quando o pós-deploy der verde"):
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7c_pos_deploy.sql
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pd on commit drop as
select exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261102100600') as sombra,
       coalesce(current_setting('agenda_teste.fase7c', true), '') <> '' as bancada;

-- A correção da revisão da 7c (spec R5.5: 20261102100580, entre o P8 e o dado; uma 2ª, 20261102100590). Hoje não há nenhuma: a tabela
-- fica vazia e o M1c/F5c não saem. QUEM CRIAR A CORREÇÃO acrescenta uma linha por migration — a versão, o que ela conserta, o texto que só
-- os blocos dela têm (a marca, ex.: '(correção da revisão da 7c') e as assinaturas das funções que ela recria (como to_regprocedure as lê) —
-- e passa a exigi-la também no publicar/exec/ligar-fase7c*.sql:
--   insert into _pd_correcoes values ('20261102100580', '<o que conserta>', '<a marca>', array['<função(args)>', …]);
create temp table _pd_correcoes (versao text primary key, nome text not null, marca text not null, funcoes text[] not null) on commit drop;

-- ── M. Versões registradas ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v),
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = v),
       null
  from unnest(array['20261102100000', '20261102100100', '20261102100200', '20261102100300', '20261102100400', '20261102100500',
                    '20261102100550']) v;

insert into _resultado
select format('M1c migration %s (%s) registrada', c.versao, c.nome),
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = c.versao),
       null
  from _pd_correcoes c
 where not ((select bancada from _pd)
            and not exists (select 1 from supabase_migrations.schema_migrations m where m.version = c.versao));

insert into _resultado
select 'M2 a correção da revisão (20261102100580/100590) e a migration de dado 20261102100600 (os 4 modos em teste) — só mostra', true,
       format('correção: %s; dado: %s',
              coalesce((select string_agg(m.version, ', ' order by m.version) from supabase_migrations.schema_migrations m
                         where m.version in ('20261102100580', '20261102100590')), 'nenhuma'),
              case when (select sombra from _pd) then 'registrada (passo 5 feito)' else 'não registrada (antes do passo 5)' end);

-- ── C. A configuração e as colunas ──────────────────────────────────────────────────────────────────────────
create temp table _pd_colunas (tabela text, coluna text) on commit drop;
insert into _pd_colunas
select 'agenda_config', x from unnest(array[
  -- P1 (20261102100000): os 3 modos e os 17 parâmetros de quem faz o quê
  'modo_habilidade', 'modo_lider', 'modo_habilidade_propor', 'habilidade_padrao', 'habilidade_dono', 'habilidade_nivel_energizado',
  'habilidade_nivel_comissionar', 'habilidade_nivel_diagnostico', 'habilidade_nivel_altura', 'habilidade_nivel_par',
  'habilidade_fechamento_cobre', 'habilidade_verbos', 'habilidade_regras', 'habilidade_palavras', 'habilidade_janela_dias',
  'habilidade_instala_dias', 'habilidade_instala_diarias', 'habilidade_hora', 'habilidade_conferir_semanas', 'lider_espera_max_du',
  -- P8 (20261102100550): o modo e os 11 parâmetros das etapas
  'modo_tarefas', 'tarefas_linhas_max', 'tarefas_texto_max', 'tarefas_fases', 'tarefas_horas_min', 'tarefas_pendente_meios',
  'tarefas_pendente_alerta', 'tarefas_sem_registro_du', 'tarefas_hora', 'tarefas_resposta_vale_dia', 'tarefas_concluir_sem_pendente',
  'tarefas_cobrar_vespera']) x
union all select 'os_planejamento', x from unnest(array['exigencias_ditas', 'exigencias_trecho', 'lider_payee_id', 'lider_em', 'lider_trecho',
  'tarefas_assinatura', 'tarefas_sincronizadas_em']) x
union all select 'agenda_alocacoes', x from unnest(array['criterio', 'criterio_detalhe']) x;

insert into _resultado
select 'C1 agenda_config tem os 4 modos e os 28 parâmetros da 7c (32 colunas: 20 do P1, 12 do P8)',
       count(*) filter (where c.column_name is null) = 0,
       format('%s de 32; faltam: %s', count(c.column_name), coalesce(string_agg(k.coluna, ', ') filter (where c.column_name is null), '—'))
  from _pd_colunas k
  left join information_schema.columns c on c.table_schema = 'public' and c.table_name = k.tabela and c.column_name = k.coluna
 where k.tabela = 'agenda_config';

insert into _resultado
select 'C2 os 4 modos da 7c: com a 100600 registrada, sombra (ou ligado com os OKs); sem ela, desligado; o DEFAULT dos 4 é sombra',
       case when (select sombra from _pd)
            then array[c.modo_habilidade, c.modo_lider, c.modo_habilidade_propor, c.modo_tarefas] <@ array['sombra', 'ligado']
            else array[c.modo_habilidade, c.modo_lider, c.modo_habilidade_propor, c.modo_tarefas] <@ array['desligado'] end
       and (select count(*) from information_schema.columns d
             where d.table_schema = 'public' and d.table_name = 'agenda_config'
               and d.column_name in ('modo_habilidade', 'modo_lider', 'modo_habilidade_propor', 'modo_tarefas')
               and d.column_default like '''sombra''%') = 4,
       format('habilidade %s, lider %s, habilidade_propor %s, tarefas %s; habilidade_hora %s, tarefas_hora %s, veto_du %s, veto_hora %s',
              c.modo_habilidade, c.modo_lider, c.modo_habilidade_propor, c.modo_tarefas, c.habilidade_hora, c.tarefas_hora, c.veto_du,
              c.veto_hora)
  from public.agenda_config c where c.id;

insert into _resultado
select format('C3 %s tem as colunas da 7c (%s)', k.tabela, string_agg(k.coluna, ', ')),
       count(*) filter (where c.column_name is null) = 0
       and (k.tabela <> 'agenda_alocacoes'
            or exists (select 1 from information_schema.columns c2 where c2.table_schema = 'public' and c2.table_name = 'agenda_alocacoes'
                         and c2.column_name = 'criterio_detalhe' and c2.data_type = 'jsonb' and c2.is_nullable = 'NO')),
       coalesce('faltam: ' || string_agg(k.coluna, ', ') filter (where c.column_name is null), null)
  from _pd_colunas k
  left join information_schema.columns c on c.table_schema = 'public' and c.table_name = k.tabela and c.column_name = k.coluna
 where k.tabela <> 'agenda_config'
 group by k.tabela;

-- ── T. Os CHECKs, as tabelas, os índices, os gatilhos e as listas ────────────────────────────────────────────────
insert into _resultado
select 'T1 os 42 CHECKs por nome da 7c (28 de agenda_config, 5 de agenda_etiquetas, 2 de os_planejamento, 3 de os_tarefas, 3 de os_tarefas_dia, 1 de agenda_alocacoes)',
       count(*) filter (where k.oid is null) = 0,
       coalesce('faltam: ' || string_agg(n.tabela || '.' || n.nome, ', ') filter (where k.oid is null), '42')
  from (select 'agenda_config' as tabela, x as nome from unnest(array[
          'agenda_config_modo_habilidade_check', 'agenda_config_modo_lider_check', 'agenda_config_modo_habilidade_propor_check',
          'agenda_config_habilidade_padrao_check', 'agenda_config_habilidade_dono_check', 'agenda_config_habilidade_nivel_energizado_check',
          'agenda_config_habilidade_nivel_comissionar_check', 'agenda_config_habilidade_nivel_diagnostico_check',
          'agenda_config_habilidade_nivel_altura_check', 'agenda_config_habilidade_nivel_par_check', 'agenda_config_habilidade_regras_check',
          'agenda_config_habilidade_palavras_check', 'agenda_config_habilidade_janela_dias_check', 'agenda_config_habilidade_instala_dias_check',
          'agenda_config_habilidade_instala_diarias_check', 'agenda_config_habilidade_hora_check',
          'agenda_config_habilidade_conferir_semanas_check', 'agenda_config_lider_espera_max_du_check', 'agenda_config_modo_tarefas_check',
          'agenda_config_tarefas_fases_check', 'agenda_config_tarefas_hora_check', 'agenda_config_tarefas_horas_min_check',
          'agenda_config_tarefas_linhas_max_check', 'agenda_config_tarefas_pendente_alerta_check', 'agenda_config_tarefas_pendente_meios_check',
          'agenda_config_tarefas_resposta_vale_dia_check', 'agenda_config_tarefas_sem_registro_du_check',
          'agenda_config_tarefas_texto_max_check']) x
        union all select 'agenda_etiquetas', x from unnest(array['etiqueta_dono_vale', 'etiqueta_nivel_zero', 'etiqueta_proposta_sem_data',
          'etiqueta_substituida', 'etiqueta_vale_tem_data']) x
        union all select 'os_planejamento', x from unnest(array['os_planejamento_exigencias_ditas_check', 'os_planejamento_lider_coerente']) x
        union all select 'os_tarefas', x from unnest(array['os_tarefas_dono_tem_trecho', 'os_tarefas_feita_coerente',
          'os_tarefas_pendente_coerente']) x
        union all select 'os_tarefas_dia', x from unnest(array['os_tarefas_dia_cancelada', 'os_tarefas_dia_resultado_coerente',
          'os_tarefas_dia_so_termina']) x
        union all select 'agenda_alocacoes', 'agenda_alocacoes_criterio_check') n
  left join pg_constraint k on k.conname = n.nome and k.conrelid = to_regclass('public.' || n.tabela);

insert into _resultado
select format('T2 a tabela %s: RLS ligada, só a política de leitura (SELECT, TO authenticated); authenticated só lê e o anon não tem privilégio nenhum', t.t),
       c.oid is not null and c.relrowsecurity
       and (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = t.t) = 1
       and exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = t.t and p.policyname = t.t || '_leitura'
                     and p.cmd = 'SELECT' and p.roles = array['authenticated']::name[])
       and not has_table_privilege('anon', c.oid, 'select, insert, update, delete')
       and has_table_privilege('authenticated', c.oid, 'select')
       and not has_table_privilege('authenticated', c.oid, 'insert, update, delete'),
       format('rls %s; políticas: %s', c.relrowsecurity,
              (select string_agg(p.policyname || ' ' || p.cmd || ' ' || array_to_string(p.roles, ','), '; ')
                 from pg_policies p where p.schemaname = 'public' and p.tablename = t.t))
  from unnest(array['agenda_etiquetas', 'os_tarefas', 'os_tarefas_dia']) t(t)
  left join pg_class c on c.oid = to_regclass('public.' || t.t);

insert into _resultado
select 'T3 os 6 índices da 7c (as etiquetas por pessoa e a viva; as etapas da OS e a viva; o plano do meio-dia e a linha única do dia)',
       count(*) filter (where to_regclass('public.' || i.i) is null) = 0,
       coalesce('faltam: ' || string_agg(i.i, ', ') filter (where to_regclass('public.' || i.i) is null), '6')
  from unnest(array['agenda_etiquetas_pessoa', 'agenda_etiquetas_viva', 'os_tarefas_da_os', 'os_tarefas_viva', 'os_tarefas_dia_meio',
                    'os_tarefas_dia_uma']) i(i);

insert into _resultado
select 'T4 os 8 gatilhos da 7c ligados, cada um com a sua função (o do critério BEFORE INSERT em agenda_alocacoes; os de "só muda o que pode" e "nunca apaga" das 3 tabelas novas)',
       count(*) filter (where t.oid is null or t.tgenabled <> 'O' or t.tgfoid <> to_regproc('public.' || g.f)) = 0
       and coalesce((select (t2.tgtype & 2) = 2 and (t2.tgtype & 4) = 4 and (t2.tgtype & 1) = 1 from pg_trigger t2
                      where t2.tgrelid = 'public.agenda_alocacoes'::regclass and t2.tgname = 'agenda_alocacoes_criterio'), false),
       coalesce('com defeito: ' || string_agg(g.tab || '.' || g.g, ', ') filter (where t.oid is null or t.tgenabled <> 'O'
                                                                          or t.tgfoid <> to_regproc('public.' || g.f)), '8')
  from (values ('agenda_alocacoes', 'agenda_alocacoes_criterio', '_agenda_alocacao_criterio'),
               ('agenda_etiquetas', 'agenda_etiquetas_exclusiva', '_agenda_etiquetas_exclusiva'),
               ('agenda_etiquetas', 'agenda_etiquetas_nao_apaga', '_agenda_registro_nao_apaga'),
               ('agenda_etiquetas', 'agenda_etiquetas_so_muda', '_agenda_etiquetas_so_muda'),
               ('os_tarefas', 'os_tarefas_nao_apaga', '_agenda_registro_nao_apaga'),
               ('os_tarefas', 'os_tarefas_so_muda', '_os_tarefas_so_muda'),
               ('os_tarefas_dia', 'os_tarefas_dia_nao_apaga', '_agenda_registro_nao_apaga'),
               ('os_tarefas_dia', 'os_tarefas_dia_so_muda', '_os_tarefas_dia_so_muda')) g(tab, g, f)
  left join pg_trigger t on t.tgrelid = to_regclass('public.' || g.tab) and t.tgname = g.g and not t.tgisinternal;

insert into _resultado
select 'T5 as listas fechadas com os da 7c: habilidade na pergunta, na ação, no rascunho, na rotina e no cancelamento da alocação; tarefa na pergunta e na ação; etapa no rascunho; tarefas na rotina — e a expressão de critica sem habilidade nem tarefa',
       coalesce(bool_and(pg_get_constraintdef(k.oid) like '%''' || l.v || '''%'), false)
       and count(k.oid) = 9
       and (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
             where d.adrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica') !~ '''(habilidade|tarefa)''',
       coalesce('sem o valor: ' || string_agg(l.tabela || ' ' || l.v, ', ') filter (where k.oid is null or pg_get_constraintdef(k.oid) not like '%''' || l.v || '''%'), null)
  from (values ('agenda_perguntas', 'agenda_perguntas_tipo_check', 'habilidade'), ('agenda_acoes', 'agenda_acoes_tipo_check', 'habilidade'),
               ('agenda_rascunho', 'agenda_rascunho_tipo_check', 'habilidade'),
               ('agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', 'habilidade'),
               ('agenda_alocacoes', 'agenda_alocacoes_cancelada_motivo_check', 'habilidade'),
               ('agenda_perguntas', 'agenda_perguntas_tipo_check', 'tarefa'), ('agenda_acoes', 'agenda_acoes_tipo_check', 'tarefa'),
               ('agenda_rascunho', 'agenda_rascunho_tipo_check', 'etapa'),
               ('agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', 'tarefas')) l(tabela, nome, v)
  left join pg_constraint k on k.conrelid = to_regclass('public.' || l.tabela) and k.conname = l.nome;

-- ── F. As funções ───────────────────────────────────────────────────────────────────────────────────────
-- As 75 da 7c (gerado da bancada na ponta por scratchpad f7c/p7/funcoes-gerar.mjs): a assinatura; a porta (leitura = authenticated e
-- service_role; service_role = só ele; interna = ninguém, nem o service_role); o pacote da definição mais nova; se é nova; se a porta é
-- conferida (as novas e as recriadas cujo grant/revoke a 7c refaz; as outras recriadas mantêm a porta de antes: só "nunca anon"); e os
-- pacotes da 7c que a recriam (as recriadas duas vezes dentro da 7c levam o bloco dos dois).
create temp table _pd_funcoes (f text primary key, porta text not null, pacote text not null, nova boolean not null, confere boolean not null,
                               pacotes text not null) on commit drop;
insert into _pd_funcoes values
  ('_agenda_alocacao_criterio()', 'service_role', 'P2', true, true, 'P2'),
  ('_agenda_alocacoes_imutavel()', 'service_role', 'P2', false, true, 'P2'),
  ('_agenda_alocs_do_bloco(jsonb, jsonb)', 'service_role', 'P2', false, true, 'P2'),
  ('_agenda_aplicar_etapa(uuid, jsonb, text, date, timestamptz)', 'interna', 'P8', true, true, 'P8'),
  ('_agenda_aplicar_habilidade(uuid, jsonb, text, date, timestamptz)', 'interna', 'P4', true, true, 'P4'),
  ('_agenda_atende(integer, integer[], integer[], integer[], integer[], boolean, integer, jsonb)', 'interna', 'P1', true, true, 'P1'),
  ('_agenda_aviso_da_habilidade(uuid, jsonb, date)', 'interna', 'P2', true, true, 'P2'),
  ('_agenda_aviso_fora_texto(jsonb, uuid[])', 'interna', 'P6', false, false, 'P6'),
  ('_agenda_contexto(date, date, date, uuid[], uuid[])', 'service_role', 'P2', false, true, 'P2'),
  ('_agenda_du_h(boolean[], integer, integer)', 'interna', 'P1', true, true, 'P1'),
  ('_agenda_e_novato(uuid, date)', 'leitura', 'P1', false, true, 'P1'),
  ('_agenda_encaixar(jsonb, jsonb, jsonb)', 'service_role', 'P2', false, true, 'P2'),
  ('_agenda_etapa_frase(jsonb)', 'service_role', 'P8', true, true, 'P8'),
  ('_agenda_etiqueta_texto(text, smallint)', 'leitura', 'P1', true, true, 'P1'),
  ('_agenda_etiquetas_exclusiva()', 'service_role', 'P1', true, true, 'P1'),
  ('_agenda_etiquetas_so_muda()', 'service_role', 'P1', true, true, 'P1'),
  ('_agenda_exigencia_texto(integer, text, boolean)', 'leitura', 'P1', true, true, 'P1'),
  ('_agenda_gestor_motivo_ordem(text)', 'leitura', 'P6', false, false, 'P6'),
  ('_agenda_gestor_motivo_texto(text)', 'leitura', 'P6', false, false, 'P6'),
  ('_agenda_gestor_reparo(uuid, date, timestamptz)', 'interna', 'P3', false, true, 'P3'),
  ('_agenda_habilidade_conferir(date, timestamptz)', 'interna', 'P5', true, true, 'P5'),
  ('_agenda_habilidade_config_ok(text, jsonb)', 'leitura', 'P1', true, true, 'P1'),
  ('_agenda_habilidade_frase(jsonb)', 'service_role', 'P4', true, true, 'P4'),
  ('_agenda_habilidade_pergunta_texto(date, uuid[])', 'interna', 'P5', true, true, 'P5'),
  ('_agenda_habilidade_perguntas_os(date, timestamptz)', 'interna', 'P5', true, true, 'P5'),
  ('_agenda_habilidade_propor(date, timestamptz)', 'interna', 'P5', true, true, 'P5'),
  ('_agenda_habilidade_vetos(date, timestamptz)', 'interna', 'P5', true, true, 'P5'),
  ('_agenda_ler_tarefas_da_resposta(text, jsonb)', 'interna', 'P8', true, true, 'P8'),
  ('_agenda_lider_da_os(uuid, date, uuid[])', 'interna', 'P1', true, true, 'P1'),
  ('_agenda_lideres_ausentes(date, date, date)', 'interna', 'P1', true, true, 'P1'),
  ('_agenda_linha_da_semana(uuid, jsonb, boolean, date)', 'leitura', 'P6', false, false, 'P6'),
  ('_agenda_linhas_do_fechamento(date)', 'leitura', 'P8', false, true, 'P5,P8'),
  ('_agenda_meios_sem_quem_pede(date, date, date, uuid[], boolean)', 'interna', 'P1', true, true, 'P1'),
  ('_agenda_modo_da_pergunta(text, text)', 'service_role', 'P8', false, true, 'P1,P8'),
  ('_agenda_por_que_nao(jsonb, jsonb, integer, integer)', 'service_role', 'P2', false, true, 'P2'),
  ('_agenda_rascunho_frase(text, jsonb)', 'service_role', 'P8', false, false, 'P4,P8'),
  ('_agenda_rotina_conclusao(date, timestamptz)', 'interna', 'P8', false, false, 'P8'),
  ('_agenda_so_diaristas(jsonb, integer)', 'service_role', 'P2', false, true, 'P2'),
  ('_agenda_tarefa_casar(uuid, text)', 'interna', 'P8', true, true, 'P8'),
  ('_agenda_tarefa_datas(date, date)', 'leitura', 'P8', true, true, 'P8'),
  ('_agenda_tarefa_fase(text, jsonb)', 'leitura', 'P8', true, true, 'P8'),
  ('_agenda_tarefa_texto(text, integer)', 'leitura', 'P8', true, true, 'P8'),
  ('_agenda_tarefas_conferir(date, timestamptz)', 'interna', 'P8', true, true, 'P8'),
  ('_agenda_tarefas_congelar(date, timestamptz)', 'interna', 'P8', true, true, 'P8'),
  ('_agenda_tarefas_da_pessoa(uuid, date, date)', 'leitura', 'P8', true, true, 'P8'),
  ('_agenda_tarefas_excecoes(date, timestamptz, uuid[])', 'interna', 'P8', true, true, 'P8'),
  ('_agenda_tarefas_fases_ok(jsonb)', 'leitura', 'P8', true, true, 'P8'),
  ('_agenda_tarefas_lista_texto(jsonb, integer, integer, boolean, boolean)', 'leitura', 'P8', true, true, 'P8'),
  ('_agenda_tarefas_planejar(uuid, date, text)', 'interna', 'P8', true, true, 'P8'),
  ('_agenda_tarefas_registrar(uuid[], text, text, text, uuid, timestamptz)', 'interna', 'P8', true, true, 'P8'),
  ('_agenda_tarefas_sincronizar(uuid, date, timestamptz)', 'interna', 'P8', true, true, 'P8'),
  ('_agenda_tarefas_texto_confere(text, jsonb)', 'interna', 'P8', true, true, 'P8'),
  ('_agenda_tecnico_declarado(uuid, date)', 'leitura', 'P1', false, true, 'P1'),
  ('_agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer)', 'service_role', 'P2', false, true, 'P2'),
  ('_agenda_ver_habilidades(date, timestamptz, uuid)', 'leitura', 'P6', true, true, 'P6'),
  ('_agenda_ver_os(uuid, date)', 'leitura', 'P8', false, false, 'P8'),
  ('_agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date)', 'service_role', 'P3', false, true, 'P3'),
  ('_os_tarefas_dia_so_muda()', 'interna', 'P8', true, true, 'P8'),
  ('_os_tarefas_so_muda()', 'interna', 'P8', true, true, 'P8'),
  ('agenda_dia_da_pessoa(uuid, date, date)', 'leitura', 'P8', false, false, 'P8'),
  ('agenda_equipe_ficha(uuid, date, date)', 'service_role', 'P8', false, false, 'P8'),
  ('agenda_habilidade(date, timestamptz)', 'service_role', 'P5', true, true, 'P5'),
  ('agenda_habilidade_medidas(date, date, date)', 'leitura', 'P5', true, true, 'P5'),
  ('agenda_habilidades(date, uuid[])', 'leitura', 'P1', true, true, 'P1'),
  ('agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'service_role', 'P2', false, true, 'P2'),
  ('agenda_rascunho_etapa(uuid, text, text, text, text, text, text[], text, date)', 'leitura', 'P8', true, true, 'P8'),
  ('agenda_rascunho_gravar(uuid, date)', 'leitura', 'P8', false, false, 'P4,P8'),
  ('agenda_rascunho_habilidade(uuid, text, text, text, text, text, text, text, boolean, text, date)', 'leitura', 'P4', true, true, 'P4'),
  ('agenda_resposta_da_equipe(text, text, text, timestamptz)', 'service_role', 'P8', false, false, 'P8'),
  ('agenda_tarefas_medidas(date, date, date)', 'leitura', 'P8', true, true, 'P8'),
  ('agenda_tarefas_rodar(date, timestamptz)', 'service_role', 'P8', true, true, 'P8'),
  ('agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)', 'leitura', 'P6', false, true, 'P6'),
  ('os_exigencias(uuid, date)', 'leitura', 'P1', true, true, 'P1'),
  ('os_tarefas_da_os(uuid, date)', 'leitura', 'P8', true, true, 'P8'),
  ('os_tarefas_fonte(uuid, date)', 'leitura', 'P8', true, true, 'P8');

insert into _resultado
select format('F1 as %s funções novas da 7c existem (P1 12, P2 2, P4 3, P5 7, P6 1, P8 24)', count(*)),
       count(*) filter (where to_regprocedure('public.' || f) is null) = 0,
       coalesce(string_agg(f, ', ') filter (where to_regprocedure('public.' || f) is null), 'todas')
  from _pd_funcoes where nova;

insert into _resultado
select format('F2 nenhuma das %s funções da 7c (novas e recriadas) executável por anon', count(*)),
       count(*) filter (where to_regprocedure('public.' || f) is not null
                          and has_function_privilege('anon', to_regprocedure('public.' || f), 'execute')) = 0,
       string_agg(f, ', ') filter (where to_regprocedure('public.' || f) is not null
                                     and has_function_privilege('anon', to_regprocedure('public.' || f), 'execute'))
  from _pd_funcoes;

insert into _resultado
select format('F3 as portas de %s (%s funções): %s', x.porta, count(*),
              case x.porta when 'leitura' then 'authenticated e service_role'
                           when 'service_role' then 'só service_role' else 'ninguém (nem service_role)' end),
       bool_and(case x.porta
                  when 'leitura' then has_function_privilege('authenticated', x.o, 'execute') and has_function_privilege('service_role', x.o, 'execute')
                  when 'service_role' then not has_function_privilege('authenticated', x.o, 'execute') and has_function_privilege('service_role', x.o, 'execute')
                  else not has_function_privilege('authenticated', x.o, 'execute') and not has_function_privilege('service_role', x.o, 'execute') end),
       string_agg(x.f, ', ') filter (where not case x.porta
                  when 'leitura' then has_function_privilege('authenticated', x.o, 'execute') and has_function_privilege('service_role', x.o, 'execute')
                  when 'service_role' then not has_function_privilege('authenticated', x.o, 'execute') and has_function_privilege('service_role', x.o, 'execute')
                  else not has_function_privilege('authenticated', x.o, 'execute') and not has_function_privilege('service_role', x.o, 'execute') end)
  from (select f, porta, to_regprocedure('public.' || f) as o from _pd_funcoes where confere) x
 where x.o is not null
 group by x.porta;

insert into _resultado
select 'F4 nenhuma função da agenda (agenda_*, _agenda_*, os_*, _os_*) executável por anon',
       count(*) = 0, string_agg(p.proname, ', ')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname ~ '^(_?agenda_|_?os_)'
   and has_function_privilege('anon', p.oid, 'execute');

-- as recriadas: a versão no banco é a do pacote mais novo da 7c que a recria (o bloco "-- FASE 7c: (7c Pn"); uma migration mais velha
-- reaplicada depois (da 7b, da 7a, ou um pacote da 7c fora de ordem) a voltaria sem ele — o md5 esperado também pega, mas é outro arquivo
insert into _resultado
select format('F5 as %s recriadas pela 7c estão no banco com o bloco do pacote mais novo que as recria (a versão certa)', count(*)),
       count(*) filter (where p.oid is null or p.prosrc not like '%(7c ' || r.pacote || '%') = 0,
       coalesce(string_agg(r.f || ' (' || r.pacote || ')', ', ') filter (where p.oid is null or p.prosrc not like '%(7c ' || r.pacote || '%'), 'todas')
  from _pd_funcoes r left join pg_proc p on p.oid = to_regprocedure('public.' || r.f)
 where not r.nova;

insert into _resultado
select format('F5b as %s recriadas duas vezes dentro da 7c têm também o bloco do pacote de antes (_agenda_modo_da_pergunta P1, _agenda_rascunho_frase e agenda_rascunho_gravar P4, _agenda_linhas_do_fechamento P5)', count(distinct r.f)),
       count(*) filter (where p.oid is null or p.prosrc not like '%(7c ' || k.pac || '%') = 0,
       coalesce(string_agg(r.f || ' (' || k.pac || ')', ', ') filter (where p.oid is null or p.prosrc not like '%(7c ' || k.pac || '%'), 'todas')
  from _pd_funcoes r cross join lateral unnest(string_to_array(r.pacotes, ',')) k(pac)
  left join pg_proc p on p.oid = to_regprocedure('public.' || r.f)
 where r.pacotes like '%,%';

insert into _resultado
select format('F5c as %s funções da %s (%s) estão no banco com o bloco dela', count(*), c.versao, c.nome),
       count(*) filter (where p.oid is null or p.prosrc not like '%' || c.marca || '%') = 0,
       coalesce(string_agg(f.f, ', ') filter (where p.oid is null or p.prosrc not like '%' || c.marca || '%'), 'todas')
  from _pd_correcoes c cross join lateral unnest(c.funcoes) f(f)
  left join pg_proc p on p.oid = to_regprocedure('public.' || f.f)
 where not ((select bancada from _pd)
            and not exists (select 1 from supabase_migrations.schema_migrations m where m.version = c.versao))
 group by c.versao, c.nome;

insert into _resultado
select 'F6 a régua do telefone (_agenda_equipe_tem_telefone) com a porta de leitura do P8 (authenticated e service_role; o fechamento a lê pelo painel) e nunca anon',
       to_regprocedure('public._agenda_equipe_tem_telefone(uuid)') is not null
       and has_function_privilege('authenticated', 'public._agenda_equipe_tem_telefone(uuid)'::regprocedure, 'execute')
       and has_function_privilege('service_role', 'public._agenda_equipe_tem_telefone(uuid)'::regprocedure, 'execute')
       and not has_function_privilege('anon', 'public._agenda_equipe_tem_telefone(uuid)'::regprocedure, 'execute'),
       null;

-- ── S. Os erros e as rodadas ─────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'S1 nenhum erro habilidade:% nem tarefas:% (agenda) nem agenda:habilidade / agenda:tarefas (task-automations) em 24 h nem aberto em app_error_logs',
       count(*) filter (where e.last_seen_at > now() - interval '24 hours') = 0 and count(*) filter (where e.resolved_at is null) = 0,
       format('24 h: %s; abertos: %s; o último: %s', count(*) filter (where e.last_seen_at > now() - interval '24 hours'),
              count(*) filter (where e.resolved_at is null), coalesce(max(e.last_seen_at)::text, 'nenhum'))
  from public.app_error_logs e
 where (e.context = 'agenda' and (e.action like 'habilidade:%' or e.action like 'tarefas:%'))
    or (e.context = 'task-automations' and e.action in ('agenda:habilidade', 'agenda:tarefas'));

insert into _resultado
select format('S2 a última rodada de %s (só mostra; a de quem faz o quê roda uma vez por dia a partir de habilidade_hora, a das etapas a cada tique com modo_tarefas fora de desligado)', r.r),
       true,
       coalesce((select format('%s (hoje %s), %s ms, erros %s, modos %s', v.rodou_em, v.p_hoje, v.duracao_ms, v.erros,
                               coalesce(v.contagens ->> 'modos', v.contagens ->> 'modo', '—'))
                   from public.agenda_vigia_rodadas v where v.rotina = r.r order by v.rodou_em desc limit 1), 'nenhuma')
  from unnest(array['habilidade', 'tarefas']) r(r);

-- ── L. As leituras ─────────────────────────────────────────────────────────────────────────────────────
create temp table _pd_leituras on commit drop as
select public.agenda_ver(p_foco => 'habilidades') as v1, public.agenda_ver(p_foco => 'habilidades') as v2,
       (select c.modo_leitura from public.agenda_config c where c.id) as leitura;

insert into _resultado
select 'L1 o foco *agenda quem faz* devolve o texto (com a leitura desligada: "a agenda de produção está desligada") e o mesmo texto duas vezes (md5)',
       case when l.leitura = 'desligado' then l.v1 ->> 'rota' = 'desligada'
            else coalesce((l.v1 ->> 'ok')::boolean, false) and l.v1 ->> 'rota' = 'habilidades' and length(l.v1 ->> 'texto') > 0
                 and length(l.v1 ->> 'texto') <= 1500 end
       and md5(coalesce(l.v1 ->> 'texto', '')) = md5(coalesce(l.v2 ->> 'texto', '')),
       format('%s caracteres: %s', length(l.v1 ->> 'texto'), left(l.v1 ->> 'texto', 300))
  from _pd_leituras l;

insert into _resultado
select 'L2 as medidas de quem faz o quê (agenda_habilidade_medidas dos últimos 30 dias) respondem — só mostra os números',
       x.m ? 'sozinho_em_risco' and x.m ? 'troca_de_lider' and x.m ? 'dono_em_tarefa_de_outro',
       left((x.m - 'detalhe')::text, 600)
  from (select public.agenda_habilidade_medidas(public._hoje_brt() - 30, public._hoje_brt(), public._hoje_brt()) as m) x;

insert into _resultado
select 'L3 as medidas das etapas (agenda_tarefas_medidas dos últimos 30 dias) respondem — só mostra os números',
       x.m is not null and jsonb_typeof(x.m) = 'object',
       left(x.m::text, 600)
  from (select public.agenda_tarefas_medidas(public._hoje_brt() - 30, public._hoje_brt(), public._hoje_brt()) as m) x;

insert into _resultado
select 'L4 a rodada das etapas: com modo_tarefas desligado (antes do dado), agenda_tarefas_rodar devolve {rodou: false} sem gravar nada; fora de desligado ela é do task-automations (o pos-vivo a confere)',
       case when c.modo_tarefas = 'desligado'
            then public.agenda_tarefas_rodar(public._hoje_brt(), now()) = '{"rodou": false, "modo": "desligado"}'::jsonb
            else true end,
       case when c.modo_tarefas = 'desligado' then 'desligado: ' || public.agenda_tarefas_rodar(public._hoje_brt(), now())::text
            else 'modo_tarefas ' || c.modo_tarefas || ': a rodada é do task-automations (publicar/exec/pos-vivo-fase7c.sql)' end
  from public.agenda_config c where c.id;

insert into _resultado
select 'L5 o fechamento de hoje (_agenda_linhas_do_fechamento) responde, toda linha em até 480 letras e, com modo_tarefas desligado, sem a linha das etapas',
       coalesce(bool_and(length(l ->> 'texto') <= 480), true)
       and (c.modo_tarefas <> 'desligado' or coalesce(bool_and(l ->> 'texto' not like 'Etapas%' and l ->> 'texto' not like 'Em teste: Etapas%'), true)),
       format('%s linhas: %s', count(l), coalesce(string_agg((l ->> 'tipo') || ' ' || (l ->> 'perda') || ' ' || (l ->> 'modo'), '; '), '—'))
  from public.agenda_config c
  left join lateral jsonb_array_elements(public._agenda_linhas_do_fechamento(public._hoje_brt())) l on true
 where c.id
 group by c.modo_tarefas;

select teste, ok, detalhe from _resultado order by teste;

rollback;
