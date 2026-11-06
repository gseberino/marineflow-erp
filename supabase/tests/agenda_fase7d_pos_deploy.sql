-- Conferência DEPOIS de aplicar a Agenda de Produção, Fase 7d (os pacotes P1 a P8): migrations 20261107100000..100700, as funções de borda (ai-agent, erp-mcp, whatsapp-webhook,
-- ai-daily-briefing, whatsapp-queue-worker e task-automations, com o passo 0b3) e o dado 20261107100900 (a semente, onde_fica_desde e os 6 modos em teste): R6.11, passos 1 a 5.
-- Spec: spec-fase7d.md §8.3 (agenda_fase7d_pos_deploy.sql), §11, R6.10, R6.11. GERADO por scratchpad/agenda-pesquisa/f7d/p8/gerar-posdeploy.mjs (as listas saem das migrations).
-- bancada: depende de 20261107100700
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só nas tabelas TEMPORÁRIAS do resultado); agenda_saude, agenda_ver e as leituras do local são STABLE; termina em ROLLBACK.
-- Na bancada (que não aplica a 20261107100900: lá os modos ficam como a linha está, desligado) ele passa do mesmo jeito.
--
--   M  as 9 versões de estrutura registradas; o dado (100900) é mostrado
--   C  agenda_config: as 31 colunas da 7d; os 6 modos: com a 100900 registrada, sombra (ou ligado, depois dos OKs); sem ela, desligado; o DEFAULT é sombra; onde_fica_desde: gravada com o
--      dado, nula sem ele; cliente_tipos_ligados aceita onde_fica; os_planejamento com as 14 colunas
--   T  as 2 tabelas com RLS, só a política de leitura TO authenticated e o anon sem privilégio; o um pátio só; os gatilhos; as listas fechadas com o que a 7d somou; critica com acesso;
--      modelo = M11
--   F  as 45 funções novas existem; nenhuma das 80 é executável por anon; as 34 recriadas com bloco estão no banco com o do pacote mais novo que as recria (agenda_decisoes_abertas, language sql, fica com o md5)
--   S  nenhum erro local:% (nem agenda:local do task-automations) aberto em app_error_logs; a última rodada (só mostra)
--   L  agenda_saude().local responde, com os zeros; o foco *agenda locais* devolve texto dentro de texto_max e o mesmo texto duas vezes; o cartão responde; com o dado, 8 locais e 1 pátio
--   O md5 de cada função que a 7d cria ou recria fica em sql/wf7d_md5_esperado.sql do scratchpad (gerado por f7d/p8/md5-gerar.mjs, da bancada na ponta): rodar junto com este, depois do
--   passo 1. Com a 7d publicada, os md5 de antes dão "diferentes" nas que ela recria: valem sql/wf7d_md5_7c_sem7d.sql e sql/wf7d_md5_7b_sem7c7d.sql.
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 1 (estrutura), de novo DEPOIS do passo 3 (o dado) e depois de cada "ligar":
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7d_pos_deploy.sql
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pd on commit drop as
select exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261107100900') as dado;

-- ── M. As migrations ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v), exists (select 1 from supabase_migrations.schema_migrations m where m.version = v), null
  from unnest(array['20261107100000', '20261107100100', '20261107100200', '20261107100300', '20261107100400', '20261107100500', '20261107100550', '20261107100600', '20261107100700']) v;
insert into _resultado
select 'M2 a migration de dado 20261107100900 (a semente e os 6 modos em teste) — só mostra', true,
       case when (select dado from _pd) then 'registrada (passo 3 feito)' else 'não registrada (antes do passo 3)' end;

-- ── C. A configuração e as colunas ────────────────────────────────────────────────────────────────
insert into _resultado
select 'C1 agenda_config tem as 31 colunas da 7d (os 6 modos, os 24 parâmetros e onde_fica_desde)', count(*) filter (where c.column_name is null) = 0,
       format('%s de 31; faltam: %s', count(c.column_name), coalesce(string_agg(k.x, ', ') filter (where c.column_name is null), '—'))
  from unnest(array[
  'modo_local_calendario', 'modo_local_autorizacao', 'modo_bem', 'modo_patio', 'modo_viagem', 'modo_mesmo_local',
  'local_conferencia_validade_dias', 'autorizacao_antecedencia_du', 'acesso_urgente_du', 'marina_reserva_antecedencia_du', 'garagem_reserva_min_meios', 'horario_tolerancia_min',
  'patio_entrada_antecedencia_du', 'patio_retirada_du', 'patio_tentativas', 'temporada_meses', 'viagem_uf_bate_volta', 'deslocamento_regional_max_min',
  'deslocamento_bate_volta_max_min', 'deslocamento_fator_estrada', 'deslocamento_kmh', 'bate_volta_meios_dia', 'pernoite_ida_meios', 'viagem_km_bate_volta',
  'viagem_km_pernoite', 'onde_fica_janela_dias', 'onde_fica_antes_dias', 'onde_fica_desde', 'local_hora', 'bem_agua_palavras',
  'bem_seco_palavras']) k(x)
  left join information_schema.columns c on c.table_schema = 'public' and c.table_name = 'agenda_config' and c.column_name = k.x;
insert into _resultado
select 'C2 os 6 modos: com o dado, sombra (ou ligado com os OKs); sem ele, desligado; o DEFAULT é sombra; onde_fica_desde gravada só com o dado',
       case when (select dado from _pd)
            then array[c.modo_local_calendario, c.modo_local_autorizacao, c.modo_bem, c.modo_patio, c.modo_viagem, c.modo_mesmo_local] <@ array['sombra', 'ligado'] and c.onde_fica_desde is not null
            else array[c.modo_local_calendario, c.modo_local_autorizacao, c.modo_bem, c.modo_patio, c.modo_viagem, c.modo_mesmo_local] <@ array['desligado'] and c.onde_fica_desde is null end
       and (select count(*) from information_schema.columns d
             where d.table_schema = 'public' and d.table_name = 'agenda_config'
               and d.column_name in ('modo_local_calendario', 'modo_local_autorizacao', 'modo_bem', 'modo_patio', 'modo_viagem', 'modo_mesmo_local')
               and d.column_default like '''sombra''%') = 6,
       format('calendario %s, acesso %s, bem %s, patio %s, viagem %s, mesmo_local %s; onde_fica_desde %s; o freio %s',
              c.modo_local_calendario, c.modo_local_autorizacao, c.modo_bem, c.modo_patio, c.modo_viagem, c.modo_mesmo_local, c.onde_fica_desde, c.gestor_so_propor)
  from public.agenda_config c where c.id;
insert into _resultado
select 'C3 o M11 só com o OK: fora de cliente_tipos_ligados (ou com "OK mandar a pergunta onde fica"); só mostra', true,
       case when 'onde_fica' = any (c.cliente_tipos_ligados) then 'na lista: o dono deu o OK?' else 'fora da lista (em teste)' end
  from public.agenda_config c where c.id;
insert into _resultado
select 'C4 os_planejamento tem as 14 colunas da 7d', count(*) filter (where c.column_name is null) = 0,
       coalesce('faltam: ' || string_agg(k.x, ', ') filter (where c.column_name is null), null)
  from unnest(array['local_id', 'local_fonte', 'local_em', 'bem_situacao', 'bem_situacao_fonte', 'bem_situacao_em', 'bem_exige', 'descer_quem', 'entrada_em', 'retirada_em', 'entrada_fonte', 'viagem', 'reserva_marina_ok_em', 'descida_ok_em']) k(x)
  left join information_schema.columns c on c.table_schema = 'public' and c.table_name = 'os_planejamento' and c.column_name = k.x;

-- ── T. As tabelas e as listas ─────────────────────────────────────────────────────────────────────
insert into _resultado
select format('T1 %s: a RLS, só a política de leitura TO authenticated, o anon sem privilégio', t),
       coalesce((select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass), false)
       and (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = t) = 1
       and (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = t and p.cmd = 'SELECT' and p.roles = '{authenticated}') = 1
       and not has_table_privilege('anon', 'public.' || t, 'select, insert, update, delete')
       and not has_table_privilege('authenticated', 'public.' || t, 'insert, update, delete'),
       null
  from unnest(array['agenda_locais', 'os_autorizados']) t;
insert into _resultado
select 'T2 um pátio da HBR só (o índice) e os gatilhos: não apaga, o histórico',
       exists (select 1 from pg_indexes i where i.schemaname = 'public' and i.indexname = 'agenda_locais_um_patio_hbr')
       and (select count(*) from pg_trigger g where g.tgrelid in ('public.agenda_locais'::regclass, 'public.os_autorizados'::regclass) and not g.tgisinternal and g.tgenabled <> 'D') >= 3,
       null;
insert into _resultado
select format('T3 a lista %s tem %s', x.nome, x.valor), pg_get_constraintdef(k.oid) like '%''' || x.valor || '''%', null
  from (values ('agenda_perguntas_tipo_check', 'local'), ('agenda_perguntas_tipo_check', 'combinar'), ('agenda_perguntas_tipo_check', 'acesso'),
               ('agenda_acoes_tipo_check', 'local'), ('agenda_vigia_rodadas_rotina_check', 'local'), ('agenda_alocacoes_cancelada_motivo_check', 'local'),
               ('agenda_cliente_mensagens_tipo_check', 'onde_fica'), ('agenda_config_cliente_tipos_ligados_check', 'onde_fica')) x(nome, valor)
  left join pg_constraint k on k.conname = x.nome;
insert into _resultado
select 'T4 as colunas geradas: critica com acesso; modelo com M11',
       (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
         where d.adrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica') like '%acesso%'
       and (select pg_get_expr(d.adbin, d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
             where d.adrelid = 'public.agenda_cliente_mensagens'::regclass and a.attname = 'modelo') like '%onde_fica%M11%',
       null;

-- ── F. As funções ─────────────────────────────────────────────────────────────────────────────────
create temp table _pd_recriadas (f text primary key, pacote text not null) on commit drop;
insert into _pd_recriadas values
  ('_agenda_aplicar_planejar', 'P7'),
  ('_agenda_cliente_da_os', 'P8'),
  ('_agenda_cliente_o_que', 'P6'),
  ('_agenda_cliente_revalidar', 'P6'),
  ('_agenda_cliente_teria_feito', 'P6'),
  ('_agenda_cliente_texto', 'P6'),
  ('_agenda_cliente_tipo_texto', 'P6'),
  ('_agenda_contexto', 'P4'),
  ('_agenda_ctx_com', 'P4'),
  ('_agenda_encaixar', 'P4'),
  ('_agenda_gestor_pessoa_meios', 'P4'),
  ('_agenda_gestor_reparo', 'P4'),
  ('_agenda_linhas_do_fechamento', 'P5'),
  ('_agenda_local_da_os', 'P8'),
  ('_agenda_melhor', 'P4'),
  ('_agenda_modo_da_pergunta', 'P1'),
  ('_agenda_por_que_nao', 'P4'),
  ('_agenda_rascunho_frase', 'P7'),
  ('_agenda_tentar_bloco', 'P4'),
  ('_agenda_validar_itens', 'P4'),
  ('_agenda_ver_clientes', 'P6'),
  ('_agenda_ver_decisoes', 'P5'),
  ('_agenda_violacoes', 'P4'),
  ('agenda_cliente_vigiar', 'P6'),
  ('agenda_decidir', 'P5'),
  ('agenda_desfazer', 'P5'),
  ('agenda_equipe_ficha', 'P8'),
  ('agenda_propor', 'P4'),
  ('agenda_rascunho_aplicar', 'P6b'),
  ('agenda_rascunho_planejar', 'P7'),
  ('agenda_resposta_do_cliente', 'P6'),
  ('agenda_saude', 'P8'),
  ('agenda_ver', 'P8'),
  ('os_plano_da_os', 'P8');
insert into _resultado
select format('F1 as %s funções novas da 7d existem', count(*)), count(*) filter (where p.oid is null) = 0,
       coalesce('faltam: ' || string_agg(n, ', ') filter (where p.oid is null), null)
  from unnest(array[
  '_agenda_autorizacao_da_os', '_agenda_cliente_anotar_onde', '_agenda_cliente_ja_atendida', '_agenda_cliente_onde_falta', '_agenda_cliente_onde_fica', '_agenda_combinar_da_os',
  '_agenda_combinar_texto', '_agenda_desfazer_local', '_agenda_disse_em_palavras', '_agenda_disse_os_numeros', '_agenda_estado_do_bem', '_agenda_gestor_estrada',
  '_agenda_irmao_chave', '_agenda_locais_historico', '_agenda_local_bloco', '_agenda_local_calendario', '_agenda_local_combinar', '_agenda_local_conferido',
  '_agenda_local_conflitos', '_agenda_local_decidir', '_agenda_local_deslocamento', '_agenda_local_mascara', '_agenda_local_modo', '_agenda_local_no',
  '_agenda_local_palavras', '_agenda_local_proposto', '_agenda_local_resolver', '_agenda_local_resolvido', '_agenda_local_restaurar', '_agenda_patio_cabe',
  '_agenda_patio_contexto', '_agenda_patio_frase', '_agenda_patio_intervalo', '_agenda_planejar_linhas', '_agenda_saude_local', '_agenda_troca_evitada',
  '_agenda_ver_locais', '_agenda_viagem_da_os', '_agenda_viagem_extra', '_agenda_viagem_por_municipio', '_agenda_viagem_suposicao', 'agenda_feriado_do_local',
  'agenda_feriado_municipal', 'agenda_local_vigiar', 'agenda_resolver_local']) n
  left join lateral (select x.oid from pg_proc x where x.pronamespace = 'public'::regnamespace and x.proname = n limit 1) p on true;
insert into _resultado
select 'F2 nenhuma função da 7d é executável por anon', count(*) filter (where has_function_privilege('anon', p.oid, 'execute')) = 0,
       coalesce(string_agg(p.oid::regprocedure::text, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')), 'nenhuma')
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname = any (array[
  '_agenda_autorizacao_da_os', '_agenda_cliente_anotar_onde', '_agenda_cliente_ja_atendida', '_agenda_cliente_onde_falta', '_agenda_cliente_onde_fica', '_agenda_combinar_da_os',
  '_agenda_combinar_texto', '_agenda_desfazer_local', '_agenda_disse_em_palavras', '_agenda_disse_os_numeros', '_agenda_estado_do_bem', '_agenda_gestor_estrada',
  '_agenda_irmao_chave', '_agenda_locais_historico', '_agenda_local_bloco', '_agenda_local_calendario', '_agenda_local_combinar', '_agenda_local_conferido',
  '_agenda_local_conflitos', '_agenda_local_decidir', '_agenda_local_deslocamento', '_agenda_local_mascara', '_agenda_local_modo', '_agenda_local_no',
  '_agenda_local_palavras', '_agenda_local_proposto', '_agenda_local_resolver', '_agenda_local_resolvido', '_agenda_local_restaurar', '_agenda_patio_cabe',
  '_agenda_patio_contexto', '_agenda_patio_frase', '_agenda_patio_intervalo', '_agenda_planejar_linhas', '_agenda_saude_local', '_agenda_troca_evitada',
  '_agenda_ver_locais', '_agenda_viagem_da_os', '_agenda_viagem_extra', '_agenda_viagem_por_municipio', '_agenda_viagem_suposicao', 'agenda_feriado_do_local',
  'agenda_feriado_municipal', 'agenda_local_vigiar', 'agenda_resolver_local',
  '_agenda_aplicar_planejar', '_agenda_cliente_da_os', '_agenda_cliente_o_que', '_agenda_cliente_revalidar', '_agenda_cliente_teria_feito', '_agenda_cliente_texto',
  '_agenda_cliente_tipo_texto', '_agenda_contexto', '_agenda_ctx_com', '_agenda_encaixar', '_agenda_gestor_pessoa_meios', '_agenda_gestor_reparo',
  '_agenda_linhas_do_fechamento', '_agenda_local_da_os', '_agenda_melhor', '_agenda_modo_da_pergunta', '_agenda_por_que_nao', '_agenda_rascunho_frase',
  '_agenda_tentar_bloco', '_agenda_validar_itens', '_agenda_ver_clientes', '_agenda_ver_decisoes', '_agenda_violacoes', 'agenda_cliente_vigiar',
  'agenda_decidir', 'agenda_decisoes_abertas', 'agenda_desfazer', 'agenda_equipe_ficha', 'agenda_propor', 'agenda_rascunho_aplicar',
  'agenda_rascunho_planejar', 'agenda_resposta_do_cliente', 'agenda_saude', 'os_plano_da_os', 'agenda_ver']);
insert into _resultado
select format('F3 as %s recriadas estão no banco com o bloco do pacote mais novo que as recria (a versão certa)', count(*)),
       count(*) filter (where p.oid is null or p.prosrc not like '%(7d ' || r.pacote || '%') = 0,
       coalesce(string_agg(r.f || ' (' || r.pacote || ')', ', ') filter (where p.oid is null or p.prosrc not like '%(7d ' || r.pacote || '%'), 'todas')
  from _pd_recriadas r
  left join lateral (select x.oid, x.prosrc from pg_proc x where x.pronamespace = 'public'::regnamespace and x.proname = r.f limit 1) p on true;

-- ── S. Sem erro ───────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'S1 nenhum erro aberto da rodada do local (local:%, agenda:local)', count(*) = 0, coalesce(string_agg(distinct e.action, ', '), 'nenhum')
  from public.app_error_logs e
 where e.resolved_at is null and ((e.context = 'agenda' and e.action like 'local:%') or (e.context = 'task-automations' and e.action = 'agenda:local'));
insert into _resultado
select 'S2 a última rodada do local — só mostra', true,
       coalesce((select format('%s (erros %s)', r.rodou_em, r.erros) from public.agenda_vigia_rodadas r where r.rotina = 'local' order by r.rodou_em desc limit 1), 'ainda não rodou');

-- ── L. As leituras ────────────────────────────────────────────────────────────────────────────────
create temp table _pd_leituras on commit drop as
select public.agenda_ver(p_foco => 'locais') as foco, public.agenda_ver(p_foco => 'locais') as foco2,
       public.agenda_saude() -> 'local' as saude,
       (select c.texto_max from public.agenda_config c where c.id) as texto_max,
       (select c.modo_leitura from public.agenda_config c where c.id) as leitura;
insert into _resultado
select 'L1 agenda_saude().local: os zeros obrigatórios (só depois da 1ª rodada, com os modos ligados, eles podem acusar)',
       coalesce((l.saude ->> 'zeros_ok')::boolean, false), l.saude::text
  from _pd_leituras l;
insert into _resultado
select 'L2 o foco *agenda locais* devolve texto dentro de texto_max (com a leitura desligada: a frase de sempre)',
       case when l.leitura = 'desligado' then l.foco ->> 'rota' = 'desligada'
            else (l.foco ->> 'ok')::boolean and length(l.foco ->> 'texto') between 1 and l.texto_max end,
       format('%s letras', length(l.foco ->> 'texto'))
  from _pd_leituras l;
insert into _resultado
select 'L3 duas leituras seguidas do foco = o mesmo texto (md5)', md5(coalesce(l.foco ->> 'texto', '')) = md5(coalesce(l.foco2 ->> 'texto', '')), null
  from _pd_leituras l;
insert into _resultado
select 'L4 o cartão responde com a chave local', count(*) = count(*) filter (where public.os_plano_da_os(k.service_order_id) ? 'local'), format('%s OS', count(*))
  from public.os_carteira(public._hoje_brt()) k;
insert into _resultado
select 'L5 com o dado: 8 locais ativos e um pátio da HBR, a MP (sem o dado, só mostra)',
       case when (select dado from _pd) then count(*) filter (where l.ativo) >= 8 and count(*) filter (where l.ativo and l.tipo = 'patio_hbr' and l.nome = 'MP Motorhomes') = 1 else true end,
       format('%s locais', count(*))
  from public.agenda_locais l;

select teste, ok, detalhe from _resultado order by teste;

rollback;
