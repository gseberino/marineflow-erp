-- Conferência DEPOIS de ligar a Agenda de Produção, Fase 4 (pacote P6): migrations 20261027100000..100600, as edge
-- functions, o front das telas de compra e (passo 3) a migration de dado 20261027101000 — os três modos do material em
-- sombra e o original herdado das linhas antigas — fila-do-dono/fase4-oks.md, passos 1–4.
-- bancada: depende de 20261027100600
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE (só na tabela TEMPORÁRIA do resultado); agenda_saude, agenda_ver e
-- agenda_espera_de_peca são STABLE e não gravam; termina em ROLLBACK. Na bancada (que não aplica a 20261027101000: lá os
-- modos ficam como a linha nasce, desligados) ele passa do mesmo jeito.
--
--   M  as 7 versões de estrutura da Fase 4 registradas em supabase_migrations.schema_migrations; as de dado (101000, a
--      sombra; 102000, o acento das cidades, opcional) são mostradas
--   C  agenda_config: as colunas novas existem; os três modos: com a 101000 registrada, sombra (ou ligado, depois dos OKs
--      dos passos 5–7); sem ela, desligado; o detector só ligado com a precisão pronta
--   T  as colunas novas nas tabelas de antes e as 3 tabelas novas: RLS ligada, policies só de leitura e TO authenticated,
--      anon sem nada, authenticated só lê
--   G  os gatilhos ligados: o original da previsão, os registros que não se apagam e só mudam no que podem, e as duas travas
--      da fila do fornecedor
--   F  funções: o contrato existe; nenhuma agenda_*/_agenda_*/os_*/_os_*/material_* executável por anon; a rodada do
--      material só service_role; as duas views novas/recriadas com security_invoker e sem anon (v_oc_itens_a_caminho com as
--      2 colunas do vínculo no fim); a agenda_ver aceita os focos compras e fornecedores
--   N  em sombra nada sai e nenhuma OS muda sozinha: sem o fornecedor nunca ligado, nada na fila agenda-fornecedor e
--      nenhuma mensagem em ligado; sem o material e o detector nunca ligados, nenhuma ação de material executada; toda linha
--      ligada a nota ou Pix tem a palavra do dono
--   S  agenda_saude().material: os zeros obrigatórios (vínculo sem o dono, a fila em sombra, fora da janela, acima do teto,
--      texto com valor ou cliente); previsao_sem_original = 0 depois da 101000 — ANTES dela é só aviso (as linhas que já
--      tinham previsão antes do gatilho do original: a 101000 grava o original delas); o ok da saúde (com o aviso de fora
--      antes da 101000); a rodada do material nas últimas 2 h (com algum modo fora de desligado) e nenhum erro material:% em
--      24 h nem aberto em app_error_logs
--   L  as leituras: a espera de peça e os focos compras e fornecedores devolvem texto dentro de texto_max; duas leituras
--      seguidas = o mesmo texto (md5)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 1 (estrutura) e de novo DEPOIS do passo 3 (a migration de dado) de fila-do-dono/
--   fase4-oks.md, com o OK do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase4_pos_deploy.sql
--   S7 só fica verde depois do 1º tique de 15 min do task-automations com a sombra ligada. Entre o passo 1 e o passo 3, S2
--   pode mostrar o aviso (linhas antigas sem o original) — e os pós-deploy das Fases 2 e 3, que conferem o ok da saúde,
--   podem acusar o mesmo; depois do passo 3, tudo verde.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _pd_sombra on commit drop as
select exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261027101000') as aplicada;

-- ── M. Versões registradas ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v),
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = v),
       null
  from unnest(array['20261027100000', '20261027100100', '20261027100200', '20261027100300', '20261027100400',
                    '20261027100500', '20261027100600']) v;

insert into _resultado
select 'M2 as migrations de dado: 20261027101000 (a sombra) e 20261027102000 (o acento das cidades, opcional) — só mostra',
       true,
       format('101000 %s; 102000 %s',
              case when (select aplicada from _pd_sombra) then 'registrada (passo 3 feito)' else 'não registrada (antes do passo 3)' end,
              case when exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261027102000')
                   then 'registrada' else 'não registrada (opcional, OK à parte)' end);

-- ── C. A configuração ───────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('C1 agenda_config.%s existe (o DEFAULT é o único lugar do número)', c),
       exists (select 1 from information_schema.columns k
                where k.table_schema = 'public' and k.table_name = 'agenda_config' and k.column_name = c),
       null
  from unnest(array['modo_material', 'modo_detector', 'modo_fornecedor', 'oc_viva_dias', 'remessa_dias', 'material_inicio_dias',
                    'material_pergunta_validade', 'nfe_opcoes_max', 'pix_janela_dias', 'pix_valor_minimo',
                    'pix_perguntas_semana_max', 'pix_categorias', 'prazo_longo_du', 'detector_janela_horas', 'detector_lote_max',
                    'detector_precisao_minima', 'detector_minimo_julgados', 'detector_tolerancia_du',
                    'fornecedor_janela_inicio', 'fornecedor_janela_fim', 'fornecedor_sabado', 'fornecedor_dia_max',
                    'fornecedor_semana_max', 'fornecedor_total_dia_max', 'fornecedor_conversa_dias',
                    'fornecedores_principais_max']) c;

insert into _resultado
select 'C2 os três modos do material: com a 101000 registrada, sombra (ou ligado com o OK dos passos 5–7); sem ela, desligado',
       coalesce(bool_and(case when (select aplicada from _pd_sombra)
                              then c.modo_material in ('sombra', 'ligado') and c.modo_detector in ('sombra', 'ligado')
                                   and c.modo_fornecedor in ('sombra', 'ligado')
                              else c.modo_material = 'desligado' and c.modo_detector = 'desligado'
                                   and c.modo_fornecedor = 'desligado' end), false),
       string_agg(format('material %s, detector %s, fornecedor %s', c.modo_material, c.modo_detector, c.modo_fornecedor), '; ')
  from public.agenda_config c;

insert into _resultado
select 'C3 a sombra da Fase 4 só com a vigia da Fase 2 ligada (pré-requisito da §10): com a 101000 registrada, modo_vigia = ligado',
       coalesce(bool_and(c.modo_vigia = 'ligado' or not (select aplicada from _pd_sombra)), false),
       string_agg(format('leitura %s, proposta %s, vigia %s', c.modo_leitura, c.modo_proposta, c.modo_vigia), '; ')
  from public.agenda_config c;

insert into _resultado
select 'C4 o detector só ligado com a precisão pronta (pelo menos detector_minimo_julgados casos e detector_precisao_minima de acerto em 14 dias)',
       c.modo_detector <> 'ligado'
       or coalesce((public.agenda_detector_precisao(public._hoje_brt() - 13, public._hoje_brt()) ->> 'pronto_para_ligar')::boolean, false),
       format('detector %s; %s', c.modo_detector, public.agenda_detector_precisao(public._hoje_brt() - 13, public._hoje_brt()) ->> 'texto')
  from public.agenda_config c;

-- ── T. As colunas e as tabelas ──────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('T1 %s.%s existe', x.tabela, x.coluna),
       exists (select 1 from information_schema.columns k
                where k.table_schema = 'public' and k.table_name = x.tabela and k.column_name = x.coluna),
       null
  from (values ('suppliers', 'modalidade'), ('suppliers', 'prazo_dias_uteis'), ('suppliers', 'prazo_dias_corridos'),
               ('suppliers', 'prazo_fonte'), ('suppliers', 'prazo_informado_em'), ('suppliers', 'prazo_trecho'),
               ('purchase_order_items', 'service_order_part_id'), ('purchase_order_items', 'service_order_service_id'),
               ('os_material', 'comprado_fonte'), ('os_material', 'previsao_original_fonte'),
               ('os_material', 'previsao_original_em'), ('os_material', 'remessa_id')) x(tabela, coluna);

insert into _resultado
select format('T2 %s existe, com RLS ligada', t),
       coalesce((select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.' || t)), false),
       case when to_regclass('public.' || t) is null then 'a tabela não existe' end
  from unnest(array['material_remessas', 'material_sinais', 'agenda_fornecedor_mensagens']) t;

insert into _resultado
select format('T3 %s: policies só de leitura e TO authenticated', t),
       count(p.policyname) >= 1 and coalesce(bool_and(p.roles = '{authenticated}'::name[] and p.cmd = 'SELECT'), false),
       string_agg(p.policyname || ' ' || p.cmd || ' ' || p.roles::text, '; ')
  from unnest(array['material_remessas', 'material_sinais', 'agenda_fornecedor_mensagens']) t
  left join pg_policies p on p.schemaname = 'public' and p.tablename = t
 group by t;

insert into _resultado
select format('T4 %s: anon sem nada; authenticated só lê', t),
       to_regclass('public.' || t) is not null
       and not (has_table_privilege('anon', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'insert')
                or has_table_privilege('anon', 'public.' || t, 'update') or has_table_privilege('anon', 'public.' || t, 'delete'))
       and has_table_privilege('authenticated', 'public.' || t, 'select')
       and not (has_table_privilege('authenticated', 'public.' || t, 'insert')
                or has_table_privilege('authenticated', 'public.' || t, 'update')
                or has_table_privilege('authenticated', 'public.' || t, 'delete')),
       case when to_regclass('public.' || t) is null then 'a tabela não existe' end
  from unnest(array['material_remessas', 'material_sinais', 'agenda_fornecedor_mensagens']) t;

-- ── G. Os gatilhos ──────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('G1 gatilho %s em %s ligado', g.nome, g.tabela),
       exists (select 1 from pg_trigger tg
                where tg.tgrelid = to_regclass('public.' || g.tabela) and tg.tgname = g.nome and not tg.tgisinternal
                  and tg.tgenabled = 'O'),
       null
  from (values ('os_material', 'os_material_previsao_original'),
               ('material_remessas', 'material_remessas_nao_apaga'), ('material_remessas', 'material_remessas_so_muda'),
               ('material_sinais', 'material_sinais_nao_apaga'), ('material_sinais', 'material_sinais_so_muda'),
               ('agenda_fornecedor_mensagens', 'agenda_fornecedor_mensagens_nao_apaga'),
               ('agenda_fornecedor_mensagens', 'agenda_fornecedor_mensagens_so_muda')) g(tabela, nome);

insert into _resultado
select 'G2 as duas travas da fila do fornecedor (a 2ª trava: a inserção e a nova tentativa), só para source agenda-fornecedor',
       count(*) = 2 and coalesce(bool_and(pg_get_triggerdef(tg.oid) like '%agenda-fornecedor%' and tg.tgenabled = 'O'), false),
       string_agg(tg.tgname, ', ')
  from pg_trigger tg
 where tg.tgrelid = to_regclass('public.whatsapp_send_queue') and not tg.tgisinternal
   and tg.tgfoid = to_regprocedure('public._agenda_fila_do_fornecedor()');

-- ── F. As funções e as views ────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('F1 %s existe', f), exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f), null
  from unnest(array[
    '_agenda_prazo_do_fornecedor', '_agenda_chegada_estimada', 'agenda_rascunho_fornecedor', '_agenda_aplicar_fornecedor',
    'agenda_ocs_com_material_vivo', 'material_remessas_do_email', '_agenda_material_notas', '_agenda_material_pix',
    'material_sinal_registrar', 'agenda_mensagens_de_fornecedor', 'agenda_detector_precisao', '_agenda_desfazer_material',
    'agenda_material_vigiar', '_agenda_fornecedor_registrar', '_agenda_fornecedor_enfileirar', '_agenda_fila_do_fornecedor',
    '_agenda_fornecedores_principais', '_agenda_espera_linhas', 'agenda_espera_de_peca', '_agenda_ver_compras',
    '_agenda_ver_fornecedores']) f;

insert into _resultado
select 'F2 nenhuma função da agenda e do material (agenda_*, _agenda_*, os_*, _os_*, material_*) executável por anon',
       count(*) > 0 and count(*) filter (where has_function_privilege('anon', p.oid, 'execute')) = 0,
       format('%s funções; com anon: %s', count(*),
              coalesce(string_agg(p.proname, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')), 'nenhuma'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname ~ '^(_?agenda_|_?os_|material_)';

insert into _resultado
select 'F3 a rodada do material só para service_role (o task-automations), nunca authenticated',
       coalesce(bool_and(has_function_privilege('service_role', p.oid, 'execute')
                         and not has_function_privilege('authenticated', p.oid, 'execute')), false),
       string_agg(pg_get_function_identity_arguments(p.oid), ' | ')
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname = 'agenda_material_vigiar';

insert into _resultado
select format('F4 %s com security_invoker e sem anon', v),
       to_regclass('public.' || v) is not null
       and coalesce((select 'security_invoker=on' = any (c.reloptions) or 'security_invoker=true' = any (c.reloptions)
                       from pg_class c where c.oid = to_regclass('public.' || v)), false)
       and not has_table_privilege('anon', 'public.' || v, 'select'),
       (select c.reloptions::text from pg_class c where c.oid = to_regclass('public.' || v))
  from unnest(array['v_agenda_espera_de_peca', 'v_oc_itens_a_caminho']) v;

insert into _resultado
select 'F5 v_oc_itens_a_caminho com as 2 colunas do vínculo da linha no fim (service_order_part_id, service_order_service_id)',
       (select array_agg(a.attname::text order by a.attnum desc) from pg_attribute a
         where a.attrelid = to_regclass('public.v_oc_itens_a_caminho') and a.attnum > 0 and not a.attisdropped)
         [1:2] = array['service_order_service_id', 'service_order_part_id'],
       null;

insert into _resultado
select 'F6 a agenda_ver aceita os focos compras e fornecedores (e a mensagem do foco que não existe cita os 17)',
       p.prosrc like '%''compras'', ''fornecedores'') then%'
       and p.prosrc like '%comissao, equipe, compras ou fornecedores)%',
       null
  from pg_proc p where p.oid = to_regprocedure('public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)');

-- ── N. Em sombra nada sai e nenhuma OS muda sozinha ─────────────────────────────────────────────────────
insert into _resultado
select 'N1 o fornecedor nunca ligado (nenhuma rodada do material com fornecedor ligado): nada na fila agenda-fornecedor e nenhuma mensagem em ligado',
       exists (select 1 from public.agenda_vigia_rodadas r where r.rotina = 'material' and r.contagens #>> '{modos,fornecedor}' = 'ligado')
       or c.modo_fornecedor = 'ligado'
       or (not exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor')
           and not exists (select 1 from public.agenda_fornecedor_mensagens m where m.modo = 'ligado')),
       format('fila agenda-fornecedor %s; mensagens em ligado %s; registradas em sombra %s',
              (select count(*) from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor'),
              (select count(*) from public.agenda_fornecedor_mensagens m where m.modo = 'ligado'),
              (select count(*) from public.agenda_fornecedor_mensagens m where m.modo = 'sombra'))
  from public.agenda_config c;

insert into _resultado
select 'N2 o material e o detector nunca ligados: nenhuma mudança de material executada pela agenda (a nota e a conversa só em teste)',
       exists (select 1 from public.agenda_vigia_rodadas r where r.rotina = 'material'
                  and (r.contagens #>> '{modos,material}' = 'ligado' or r.contagens #>> '{modos,detector}' = 'ligado'))
       or c.modo_material = 'ligado' or c.modo_detector = 'ligado'
       or not exists (select 1 from public.agenda_acoes a where a.tipo = 'material' and a.executada and a.origem in ('nota', 'fornecedor')),
       format('executadas %s; em teste %s',
              (select count(*) from public.agenda_acoes a where a.tipo = 'material' and a.executada and a.origem in ('nota', 'fornecedor')),
              (select count(*) from public.agenda_acoes a where a.tipo = 'material' and not a.executada))
  from public.agenda_config c;

create temp table _saude on commit drop as select public.agenda_saude() as s;

insert into _resultado
select 'N3 toda linha ligada a nota ou Pix tem a palavra do dono (material.vinculo_sem_resposta_do_dono = 0)',
       (s #>> '{material,vinculo_sem_resposta_do_dono}')::int = 0, s #>> '{material,vinculo_sem_resposta_do_dono}'
  from _saude;

-- ── S. A saúde do material ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('S1 material.fornecedor.%s = 0', k),
       (s #>> array['material', 'fornecedor', k])::int = 0, s #>> array['material', 'fornecedor', k]
  from _saude, unnest(array['na_fila_em_sombra', 'fora_da_janela', 'acima_do_teto', 'com_valor_ou_cliente']) k;

-- O aviso do P5: a linha que já tinha previsão ANTES do gatilho do original (as Fases 1–3 no ar antes da Fase 4) não tem
-- original. Antes da 101000 é só aviso (ela grava o original herdado); depois, tem de ser 0.
insert into _resultado
select 'S2 material.previsao_sem_original: 0 depois da 101000; antes dela, só aviso (as linhas antigas — a 101000 grava o original delas)',
       (s #>> '{material,previsao_sem_original}')::int = 0 or not (select aplicada from _pd_sombra),
       case when (s #>> '{material,previsao_sem_original}')::int = 0 then '0'
            when (select aplicada from _pd_sombra) then format('%s linha(s) com previsão sem o original DEPOIS da 101000: defeito',
                                                               s #>> '{material,previsao_sem_original}')
            else format('AVISO: %s linha(s) antiga(s) com previsão sem o original; a 101000 (passo 3) grava o original delas',
                        s #>> '{material,previsao_sem_original}') end
  from _saude;

insert into _resultado
select 'S3 a saúde ok (os zeros das Fases 2, 3 e 4 juntos); antes da 101000, o único zero que pode faltar é o do aviso S2',
       (s ->> 'ok')::boolean
       or (not (select aplicada from _pd_sombra) and (s #>> '{material,previsao_sem_original}')::int > 0
           and (s #>> '{material,vinculo_sem_resposta_do_dono}')::int = 0
           and (s #>> '{material,fornecedor,na_fila_em_sombra}')::int = 0 and (s #>> '{material,fornecedor,fora_da_janela}')::int = 0
           and (s #>> '{material,fornecedor,acima_do_teto}')::int = 0 and (s #>> '{material,fornecedor,com_valor_ou_cliente}')::int = 0
           and (s #>> '{criticas,sem_decisao}')::int = 0 and (s #>> '{criticas,pela_regra_sem_decisao}')::int = 0
           and (s #>> '{invariantes,choques}')::int = 0),
       format('ok %s; previsao_sem_original %s', s ->> 'ok', s #>> '{material,previsao_sem_original}')
  from _saude;

insert into _resultado
select 'S4 os modos que a saúde mostra são os da linha',
       s #>> '{material,modos,material}' = c.modo_material and s #>> '{material,modos,detector}' = c.modo_detector
       and s #>> '{material,modos,fornecedor}' = c.modo_fornecedor, (s #> '{material,modos}')::text
  from _saude, public.agenda_config c;

insert into _resultado
select 'S5 nenhum erro do material (material:%) nas últimas 24 h',
       coalesce((s #>> '{material,erros_24h}')::int, 0) = 0, s #>> '{material,erros_24h}'
  from _saude;

insert into _resultado
select 'S6 nenhum erro do material (context agenda, action material:% ou agenda:material-vigia) aberto em app_error_logs',
       count(*) = 0, coalesce(string_agg(e.action || ': ' || left(e.message, 80), ' | '), 'nenhum')
  from public.app_error_logs e
 where e.resolved_at is null
   and ((e.context = 'agenda' and e.action like 'material:%') or e.action in ('agenda:material-vigia', 'agenda:remessas'));

insert into _resultado
select 'S7 a rodada do material rodou nas últimas 2 h (com algum modo do material fora de desligado; desligada ela não roda)',
       coalesce((s #>> '{material,rodou_nas_ultimas_2h}')::boolean, false)
       or (c.modo_material = 'desligado' and c.modo_detector = 'desligado' and c.modo_fornecedor = 'desligado'),
       format('última rodada %s', coalesce(s #>> '{material,ultima_rodada}', 'nenhuma'))
  from _saude, public.agenda_config c;

-- ── L. As leituras ──────────────────────────────────────────────────────────────────────────────────────
create temp table _pd_leituras on commit drop as
select public.agenda_ver(p_foco => 'compras') as compras, public.agenda_ver(p_foco => 'compras') as compras2,
       public.agenda_ver(p_foco => 'fornecedores') as forn, public.agenda_ver(p_foco => 'fornecedores') as forn2,
       public.agenda_espera_de_peca() as espera,
       (select c.texto_max from public.agenda_config c) as texto_max,
       (select c.modo_leitura from public.agenda_config c) as leitura;

insert into _resultado
select 'L1 os focos compras e fornecedores devolvem texto dentro de texto_max (com a leitura desligada: "a agenda de produção está desligada")',
       case when l.leitura = 'desligado' then l.compras ->> 'rota' = 'desligada' and l.forn ->> 'rota' = 'desligada'
            else (l.compras ->> 'ok')::boolean and length(l.compras ->> 'texto') between 1 and l.texto_max
                 and (l.forn ->> 'ok')::boolean and length(l.forn ->> 'texto') between 1 and l.texto_max end,
       format('compras %s caracteres; fornecedores %s', length(l.compras ->> 'texto'), length(l.forn ->> 'texto'))
  from _pd_leituras l;

insert into _resultado
select 'L2 duas leituras seguidas = o mesmo texto (md5)',
       md5(coalesce(l.compras ->> 'texto', '')) = md5(coalesce(l.compras2 ->> 'texto', ''))
       and md5(coalesce(l.forn ->> 'texto', '')) = md5(coalesce(l.forn2 ->> 'texto', '')), null
  from _pd_leituras l;

-- A mediana da espera conta as OS da carteira e as concluídas nos últimos 180 dias (e a OC ligada à linha); a da saúde,
-- toda OS aprovada nos últimos 90 dias (e só a OC da linha). Na carteira de hoje elas batem; a diferença é mostrada, não
-- reprova (uma OS aprovada há menos de 90 dias que saiu da carteira sem saída registrada conta só na saúde).
insert into _resultado
select 'L3 a espera de peça responde (as OS e a mediana dos 90 dias; mostra o tempo até comprar e a mediana da saúde ao lado)',
       l.espera ? 'os' and jsonb_typeof(l.espera -> 'os') = 'array',
       format('%s · mediana %s (saúde %s)', coalesce(l.espera ->> 'texto', 'sem OS com material na carteira'),
              coalesce(l.espera ->> 'mediana_ate_comprar_90d', '—'), coalesce(s #>> '{material,espera,mediana_ate_comprar_90d}', '—'))
  from _pd_leituras l, _saude;

select teste, ok, detalhe from _resultado order by teste;

rollback;
