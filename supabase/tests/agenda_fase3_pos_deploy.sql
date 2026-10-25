-- Conferência DEPOIS de ligar a Agenda de Produção, Fase 3 (pacote P7b): migrations 20261026100000..100700, as edge
-- functions, o front e (passo 4) a migration de dado 20261026101000 — os modos da equipe e da diária em sombra e a lista da
-- rotina — fila-do-dono/fase3-oks.md, passos 1–5.
-- bancada: depende de 20261026100700
--
-- SÓ LEITURA EM PRODUÇÃO: nenhum INSERT, UPDATE ou DELETE em tabela do sistema (só em tabelas e numa função TEMPORÁRIAS:
-- o resultado e a cópia da releitura das cobranças do replay); agenda_saude é STABLE e não grava; termina em ROLLBACK. Na
-- bancada (que não aplica a migration de dado 20261026101000: lá os modos ficam como a linha nasce), o bloco Q monta antes as
-- 21 conclusões do replay e uma conclusão pela porta nas tabelas, dentro desta transação (o ROLLBACK desfaz) — em produção
-- esse bloco não roda e o Q lê as OS de verdade.
--
--   M  as 8 versões de estrutura da Fase 3 registradas em supabase_migrations.schema_migrations; a de dado (101000) é
--      mostrada
--   C  agenda_config: uma linha; as 16 colunas novas existem; modo_equipe/modo_diaria: com a 101000 registrada, sombra (ou
--      ligado, depois dos passos 7–8); sem ela, desligado; a sombra da equipe só com a proposta ligada (passo 0); modo_cliente
--      desligado (Fase 5); comissao_config com o pagamento desligado
--   T  as colunas novas nas tabelas de antes e as 4 tabelas novas: RLS ligada, policies só de leitura e TO authenticated,
--      anon sem nada, authenticated só lê
--   G  os gatilhos das invariantes ligados (a entrega só pela porta, o registro da equipe que não se apaga, a fila da equipe
--      na janela e no teto, a diária só com a confirmação) e o CHECK da entrega depois da conclusão
--   F  funções: o contrato existe; nenhuma agenda_*/_agenda_*/os_*/_os_*/comissao_* executável por anon; as internas só
--      service_role; a porta com o D11 (o levantamento); v_dias_por_os_e_pessoa com security_invoker e sem anon
--   E  a lista da rotina (agenda_equipe_contato): todo 'regra' cumpre a regra da d14 (ativo, da equipe, telefone, perfil de
--      diária); o dono nunca; quem está nela (só o primeiro nome)
--   N  em sombra nada sai e nada é lançado: nenhuma linha agenda-equipe pendente na fila fora de ligado; sem a equipe nunca
--      ligada, nenhuma linha agenda-equipe na fila e nenhuma mensagem em modo ligado; sem a diária nunca ligada, nenhuma
--      diária lançada pela agenda
--   S  agenda_saude(): ok; os zeros obrigatórios — crítica sem decisão, acima do teto, fora da janela (também o que saiu fora
--      dela), diária sem confirmação, turno sobrescrito, conclusão sem cobrança quando devia, pagamento de comissão de
--      técnico; a rotina rodou nas últimas 2 h (com a equipe ou a diária fora de desligado) e sem erro em 24 h
--   Q  o replay das conclusões, só leitura (§5.6 c): cada OS concluída ou faturada, no estado de ANTES da saída, passa pela
--      releitura das cobranças JÁ APLICADA (_os_recebiveis_da_conclusao, o corpo de produção numa cópia temporária que lê as
--      cobranças de antes da saída); cada uma cai na classe dela; a contagem de 24/10 (A 1 · B 5 · C 3 · D 9 · E 1 · F 2);
--      as concluídas depois de 24/10 caem em A, D ou E; a conclusão pela porta compara com as cobranças que ela registrou
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, DEPOIS do passo 4 de fila-do-dono/fase3-oks.md (estrutura, edge functions, front e a migration de dado),
--   com o OK do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase3_pos_deploy.sql
--   S7 só fica verde depois do 1º tique de 15 min da rotina; S8 a partir do 2º dia, se a rotina não estiver falhando.
--   Os pós-deploy das Fases 1 e 2 continuam verdes depois da 101000 (eles passaram a aceitar a sombra da Fase 3).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

-- ── M. Versões registradas ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M1 migration %s registrada', v),
       exists (select 1 from supabase_migrations.schema_migrations m where m.version = v),
       null
  from unnest(array['20261026100000', '20261026100100', '20261026100200', '20261026100300', '20261026100400',
                    '20261026100500', '20261026100600', '20261026100700']) v;

insert into _resultado
select 'M2 a migration de dado 20261026101000 (equipe e diária em sombra, a lista da rotina): registrada ou não (só mostra; C3 confere o modo)',
       true,
       case when exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261026101000')
            then 'registrada (passo 4 feito)' else 'não registrada (antes do passo 4)' end;

-- ── C. A configuração ───────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'C1 agenda_config tem exatamente uma linha', count(*) = 1, count(*)::text from public.agenda_config;

insert into _resultado
select format('C2 agenda_config.%s existe (o DEFAULT é o único lugar do número)', c),
       exists (select 1 from information_schema.columns k
                where k.table_schema = 'public' and k.table_name = 'agenda_config' and k.column_name = c),
       null
  from unnest(array['modo_diaria', 'equipe_janela_inicio', 'equipe_janela_fim', 'equipe_hora_ficha', 'equipe_hora_confirmar',
                    'equipe_silencio_ate', 'equipe_hora_como_foi', 'equipe_proativas_dia_max', 'equipe_respostas_dia_max',
                    'equipe_resposta_validade', 'diaria_janela_dias', 'entrega_aviso_du', 'carona_por_os_dias',
                    'carteira_laranja_du', 'carteira_vermelho_du', 'ppc_meta',
                    -- (C1, NOVO-agenda-28) a janela da resposta direta
                    'equipe_resposta_direta_inicio', 'equipe_resposta_direta_fim', 'equipe_resposta_direta_prazo']) c;

insert into _resultado
select 'C3 os modos da Fase 3: com a 101000 registrada, sombra (ou ligado com o OK dos passos 7–8); sem ela, desligado',
       coalesce(bool_and(case when exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261026101000')
                              then c.modo_equipe in ('sombra', 'ligado') and c.modo_diaria in ('sombra', 'ligado')
                              else c.modo_equipe = 'desligado' and c.modo_diaria = 'desligado' end), false),
       string_agg(format('equipe %s, diária %s', c.modo_equipe, c.modo_diaria), '; ')
  from public.agenda_config c;

insert into _resultado
select 'C4 a sombra da equipe só depois da Fase 2 ligada: com a 101000 registrada, modo_proposta = ligado (passo 0)',
       coalesce(bool_and(c.modo_proposta = 'ligado'
                         or not exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261026101000')), false),
       string_agg(format('proposta %s, vigia %s, leitura %s', c.modo_proposta, c.modo_vigia, c.modo_leitura), '; ')
  from public.agenda_config c;

insert into _resultado
select 'C5 o que é da Fase 5 continua desligado (cliente)',
       coalesce(bool_and(c.modo_cliente = 'desligado'), false), string_agg(c.modo_cliente, ', ')
  from public.agenda_config c;

insert into _resultado
select 'C6 comissao_config: uma linha e o pagamento desligado (só muda com o "pode pagar assim" do dono, noutra fase)',
       count(*) = 1 and coalesce(bool_and(k.pagamento = 'desligado'), false),
       string_agg(format('pct %s, pagamento %s, início %s', k.pct, k.pagamento, coalesce(k.inicio::text, 'o dono ainda não disse')), '; ')
  from public.comissao_config k;

-- ── T. As colunas e as tabelas ──────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('T1 %s.%s existe', x.tabela, x.coluna),
       exists (select 1 from information_schema.columns k
                where k.table_schema = 'public' and k.table_name = x.tabela and k.column_name = x.coluna),
       null
  from (values ('service_orders', 'delivered_at'), ('agenda_alocacoes', 'work_shift_id'), ('agenda_acoes', 'payee_id'),
               ('agenda_acoes', 'work_shift_id'), ('agenda_acoes', 'receivable_ids'), ('agenda_perguntas', 'payee_id'),
               ('agenda_perguntas', 'carona_em'), ('agenda_vigia_rodadas', 'rotina'), ('agenda_vigia_rodadas', 'modo_equipe'),
               ('agenda_vigia_rodadas', 'modo_diaria')) x(tabela, coluna);

insert into _resultado
select format('T2 %s existe, com RLS ligada', t),
       coalesce((select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.' || t)), false),
       case when to_regclass('public.' || t) is null then 'a tabela não existe' end
  from unnest(array['agenda_equipe_contato', 'agenda_equipe_mensagens', 'agenda_intervencoes_do_dono', 'comissao_config']) t;

insert into _resultado
select format('T3 %s: policies só de leitura e TO authenticated', t),
       count(p.policyname) >= 1 and coalesce(bool_and(p.roles = '{authenticated}'::name[] and p.cmd = 'SELECT'), false),
       string_agg(p.policyname || ' ' || p.cmd || ' ' || p.roles::text, '; ')
  from unnest(array['agenda_equipe_contato', 'agenda_equipe_mensagens', 'agenda_intervencoes_do_dono', 'comissao_config']) t
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
  from unnest(array['agenda_equipe_contato', 'agenda_equipe_mensagens', 'agenda_intervencoes_do_dono', 'comissao_config']) t;

-- ── G. Os gatilhos das invariantes ──────────────────────────────────────────────────────────────────────
-- 'O' = ligado (origin). Desligado ('D') deixaria a entrega por fora, o registro da equipe apagável, a mensagem à equipe
-- fora da janela ou acima do teto, ou a diária sem a confirmação.
insert into _resultado
select format('G1 gatilho %s em %s ligado', g.nome, g.tabela),
       exists (select 1 from pg_trigger tg
                where tg.tgrelid = to_regclass('public.' || g.tabela) and tg.tgname = g.nome and not tg.tgisinternal
                  and tg.tgenabled = 'O'),
       null
  from (values ('service_orders', 'trg_so_entrega_pela_porta'),
               ('agenda_equipe_mensagens', 'agenda_equipe_mensagens_nao_apaga'),
               ('agenda_equipe_mensagens', 'agenda_equipe_mensagens_so_responde'),
               ('whatsapp_send_queue', 'trg_agenda_fila_da_equipe'),
               ('whatsapp_send_queue', 'trg_agenda_fila_da_equipe_tentativa'),
               ('agenda_acoes', 'agenda_acoes_diaria_confirmada')) g(tabela, nome);

insert into _resultado
select 'G2 o CHECK so_entrega_depois_da_conclusao existe (entrega só depois da saída)',
       exists (select 1 from pg_constraint c
                where c.conrelid = to_regclass('public.service_orders') and c.conname = 'so_entrega_depois_da_conclusao'),
       null;

-- ── F. Funções ──────────────────────────────────────────────────────────────────────────────────────────
-- O contrato: o que a tela, o assistente, as palavras, a rotina, o webhook, o secretário e a assinatura chamam.
insert into _resultado
select format('F1 %s existe', f), exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f), null
  from unnest(array[
    'os_transicionar_status', 'os_registrar_marco', 'agenda_marcos_da_os', 'agenda_concluir_dito', 'agenda_entregar_dito',
    'agenda_equipe_ficha', 'agenda_resposta_da_equipe', 'agenda_rotina_rodar', 'agenda_diaria_dita', 'agenda_diaria_da_agenda',
    'comissao_tecnicos_do_mes', 'comissao_resumo_do_mes', 'agenda_ppc', 'agenda_livre_de_verdade', 'agenda_carona',
    'ai_job_registrar_os', 'os_status_da_tela', 'agenda_tela_semana', 'agenda_tela_carteira', 'os_plano_da_os',
    'agenda_equipe_da_grade', 'os_planejar_pela_tela', 'agenda_desfazer_pela_tela', '_os_recebiveis_da_conclusao',
    '_os_levantamentos_pendentes', '_os_porta_regra']) f;

insert into _resultado
select 'F2 nenhuma função da agenda (agenda_*, _agenda_*, os_*, _os_*, comissao_*) executável por anon',
       count(*) > 0 and count(*) filter (where has_function_privilege('anon', p.oid, 'execute')) = 0,
       format('%s funções; com anon: %s', count(*),
              coalesce(string_agg(p.proname, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')), 'nenhuma'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname ~ '^(_?agenda_|_?os_|comissao_)';

insert into _resultado
select 'F3 as internas só para service_role (a rotina, a resposta da equipe, a ficha, a carona, as OS do turno, a releitura das cobranças)',
       count(*) = 6 and count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute')) = 0
       and bool_and(has_function_privilege('service_role', p.oid, 'execute')),
       format('%s funções; com authenticated: %s', count(*),
              coalesce(string_agg(p.proname, ', ') filter (where has_function_privilege('authenticated', p.oid, 'execute')), 'nenhuma'))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('agenda_rotina_rodar', 'agenda_resposta_da_equipe', 'agenda_equipe_ficha', 'agenda_carona',
                     'ai_job_registrar_os', '_os_recebiveis_da_conclusao');

insert into _resultado
select 'F4 a porta é uma só (9 argumentos) e confere o levantamento na conclusão (D11, 20261026100700)',
       count(*) = 1 and bool_and(p.prosrc like '%_os_levantamentos_pendentes(p_os)%' and p.prosrc like '%-- FASE 3 (P7b):%'),
       string_agg(pg_get_function_identity_arguments(p.oid), ' | ')
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname = 'os_transicionar_status';

insert into _resultado
select 'F5 v_dias_por_os_e_pessoa com security_invoker e sem anon',
       to_regclass('public.v_dias_por_os_e_pessoa') is not null
       and coalesce((select 'security_invoker=on' = any (c.reloptions) or 'security_invoker=true' = any (c.reloptions)
                       from pg_class c where c.oid = to_regclass('public.v_dias_por_os_e_pessoa')), false)
       and not has_table_privilege('anon', 'public.v_dias_por_os_e_pessoa', 'select'),
       (select c.reloptions::text from pg_class c where c.oid = to_regclass('public.v_dias_por_os_e_pessoa'));

-- ── E. A lista da rotina ────────────────────────────────────────────────────────────────────────────────
-- A regra da d14 que vale para sempre (a "diária recente" é do dia da semente e não se confere depois): quem entrou pela
-- regra é favorecido ativo da equipe, com telefone e perfil de diária. O dono (sócio) nunca está na lista.
insert into _resultado
select 'E1 todo nome que entrou pela regra é da equipe: ativo, não sócio, com telefone e com perfil de diária',
       count(*) filter (where not (p.active and p.kind in ('prestador', 'diarista', 'funcionario')
                                  and length(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g')) >= 10
                                  and exists (select 1 from public.work_profiles w
                                               where w.payee_id = p.id and w.modo_pagamento = 'diaria'))) = 0,
       coalesce(string_agg(split_part(p.name, ' ', 1), ', ')
                  filter (where not (p.active and p.kind in ('prestador', 'diarista', 'funcionario')
                                     and length(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g')) >= 10
                                     and exists (select 1 from public.work_profiles w
                                                  where w.payee_id = p.id and w.modo_pagamento = 'diaria'))), 'nenhum fora da regra')
  from public.agenda_equipe_contato l join public.payees p on p.id = l.payee_id
 where l.incluido_por = 'regra';

insert into _resultado
select 'E2 o dono (sócio) nunca está na lista da rotina',
       not exists (select 1 from public.agenda_equipe_contato l join public.payees p on p.id = l.payee_id where p.kind = 'socio'),
       null;

insert into _resultado
select 'E3 com a 101000 registrada a lista tem alguém (em 24/10 a regra dava só o Roberto); sem ela, vazia — mostra quem',
       case when exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261026101000')
            then exists (select 1 from public.agenda_equipe_contato)
            else not exists (select 1 from public.agenda_equipe_contato) end,
       coalesce((select string_agg(split_part(p.name, ' ', 1) || ' (' || l.incluido_por
                                   || case when l.recebe_rotina then '' else ', parado' end || ')', ', ' order by p.name)
                   from public.agenda_equipe_contato l join public.payees p on p.id = l.payee_id), 'ninguém');

-- ── N. Em sombra nada sai e nada é lançado ──────────────────────────────────────────────────────────────
insert into _resultado
select 'N1 com a equipe fora de ligado, nenhuma mensagem à equipe esperando na fila (a rotina faz falhar no tique seguinte)',
       c.modo_equipe = 'ligado'
       or not exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-equipe' and q.status in ('pending', 'sending')),
       format('equipe %s; agenda-equipe esperando: %s', c.modo_equipe,
              (select count(*) from public.whatsapp_send_queue q where q.source = 'agenda-equipe' and q.status in ('pending', 'sending')))
  from public.agenda_config c;

insert into _resultado
select 'N2 a equipe nunca ligada (nenhuma rodada com modo_equipe ligado): nenhuma linha agenda-equipe na fila e nenhuma mensagem em modo ligado',
       exists (select 1 from public.agenda_vigia_rodadas r where r.modo_equipe = 'ligado') or c.modo_equipe = 'ligado'
       or (not exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-equipe')
           and not exists (select 1 from public.agenda_equipe_mensagens m where m.modo = 'ligado')),
       format('fila agenda-equipe %s; mensagens em ligado %s; registradas em sombra %s',
              (select count(*) from public.whatsapp_send_queue q where q.source = 'agenda-equipe'),
              (select count(*) from public.agenda_equipe_mensagens m where m.modo = 'ligado'),
              (select count(*) from public.agenda_equipe_mensagens m where m.modo = 'sombra'))
  from public.agenda_config c;

insert into _resultado
select 'N3 a diária nunca ligada (nenhuma rodada com modo_diaria ligado): nenhuma diária lançada pela agenda (só as em teste)',
       exists (select 1 from public.agenda_vigia_rodadas r where r.modo_diaria = 'ligado') or c.modo_diaria = 'ligado'
       or not exists (select 1 from public.agenda_acoes a where a.tipo = 'diaria' and a.executada and a.origem <> 'dono'),
       format('lançadas pela agenda %s; em teste %s',
              (select count(*) from public.agenda_acoes a where a.tipo = 'diaria' and a.executada and a.origem <> 'dono'),
              (select count(*) from public.agenda_acoes a where a.tipo = 'diaria' and not a.executada))
  from public.agenda_config c;

-- ── S. A saúde ──────────────────────────────────────────────────────────────────────────────────────────
create temp table _saude on commit drop as select public.agenda_saude() as s;

insert into _resultado
select 'S1 nenhuma ação crítica executada sem a decisão do dono (criticas.sem_decisao = 0 e pela_regra_sem_decisao = 0)',
       (s #>> '{criticas,sem_decisao}')::int = 0 and (s #>> '{criticas,pela_regra_sem_decisao}')::int = 0,
       s -> 'criticas' ->> 'sem_decisao' || ' sem decisão; ' || (s -> 'criticas' ->> 'pela_regra_sem_decisao') || ' pela regra'
  from _saude;

insert into _resultado
select 'S2 a equipe: nenhuma pessoa acima do teto do dia e nada na fila (ou enviado) fora da janela',
       (s #>> '{equipe,acima_do_teto}')::int = 0 and (s #>> '{equipe,fora_da_janela}')::int = 0, (s -> 'equipe')::text
  from _saude;

insert into _resultado
select 'S3 a diária: nenhuma lançada sem a confirmação e nenhum turno existente sobrescrito pela agenda',
       (s #>> '{diarias,sem_confirmacao}')::int = 0 and (s #>> '{diarias,sobrescreveu_turno}')::int = 0, (s -> 'diarias')::text
  from _saude;

insert into _resultado
select 'S4 a conclusão pela porta: nenhuma OS concluída sem a cobrança que a condição manda (sem_recebivel_quando_devia = 0)',
       coalesce((s #>> '{conclusao,sem_recebivel_quando_devia}')::int, -1) = 0, (s -> 'conclusao')::text
  from _saude;

insert into _resultado
select 'S5 a comissão: pagamento desligado e nenhuma conta a pagar de comissão de técnico em 7 dias',
       s #>> '{comissao,pagamento}' = 'desligado' and (s #>> '{comissao,payables_de_comissao_tecnico_7d}')::int = 0,
       (s -> 'comissao')::text
  from _saude;

insert into _resultado
select 'S6 agenda_saude ok (os zeros das Fases 2 e 3 juntos) e nenhum choque de pessoa no plano vigente',
       (s ->> 'ok')::boolean and (s #>> '{invariantes,choques}')::int = 0, (s -> 'invariantes')::text
  from _saude;

insert into _resultado
select 'S7 a rotina rodou nas últimas 2 h (com a equipe ou a diária fora de desligado; desligada ela não roda)',
       coalesce((s #>> '{rotina,rodou_nas_ultimas_2h}')::boolean, false)
       or (s #>> '{modos_fase3,equipe}' = 'desligado' and s #>> '{modos_fase3,diaria}' = 'desligado'),
       format('modos %s; última rodada %s', s -> 'modos_fase3', coalesce(s #>> '{rotina,ultima_rodada}', 'nenhuma'))
  from _saude;

insert into _resultado
select 'S8 nenhum erro da rotina (rotina:%) em app_error_logs nas últimas 24 h',
       coalesce((s #>> '{rotina,erros_24h}')::int, 0) = 0, s #>> '{rotina,erros_24h}'
  from _saude;

-- ── Q. O replay das conclusões, só leitura (§5.6 c) ─────────────────────────────────────────────────────
-- A releitura das cobranças (_os_recebiveis_da_conclusao) lê as cobranças de AGORA; a conclusão de verdade viu as de ANTES
-- da saída. Por isso o corpo dela, como está em produção (pg_proc.prosrc), é copiado para uma função TEMPORÁRIA que lê as
-- mesmas OS e condições e, no lugar de public.receivables, as cobranças de antes da saída (_pd_antes). Cada troca tem de
-- casar o número exato de vezes: se o corpo mudar, a linha Q0 diz qual.
--   · conclusão pela tela (sem ação concluir da porta): antes = criadas mais de 5 min antes da saída + os sinais criados até
--     ela; o gabarito = as não sinal criadas a até 5 min da saída; o dia = a saída em Brasília (a regra do replay da bancada);
--   · conclusão pela porta (ação concluir executada e não desfeita): antes = as que não estão em receivable_ids e foram
--     criadas antes da ação; o gabarito = as de receivable_ids; o dia = o dia da ação (o p_hoje da porta);
--   · a parcela "na entrega" do gabarito pode vencer no dia UTC da saída (o gatilho de produção; NOVO-agenda-21, decisão do
--     dono): a conclusão depois das 21h de Brasília tem o saldo no dia seguinte, e a comparação aceita esse dia.
create temp table _pd_so on commit drop as
select so.id, so.service_order_number, so.status, so.check_out_at, so.grand_total, so.labor_cost_total, so.parts_cost_total,
       so.operational_cost_total, so.travel_cost_total, so.subcontract_cost_total, so.is_travel_billable, so.discount_amount,
       so.tax_amount, so.custom_payment_installments, so.payment_condition_preset_id
  from public.service_orders so where false;
create temp table _pd_presets on commit drop as
select pc.id, pc.installments from public.payment_condition_presets pc where false;
create temp table _pd_antes on commit drop as
select r.id, r.service_order_id, r.description, r.amount, r.due_date, r.created_at, r.due_on_completion, r.status
  from public.receivables r where false;
create temp table _pd_resultado (numero text primary key, saida date, saida_utc date, via text, classe text, motivo text,
                                 linhas jsonb, tela jsonb) on commit drop;

do $q$
declare
  v_bancada boolean := coalesce(current_setting('agenda_teste.replay_conclusoes', true), '') <> '';
  v_ids     uuid[];
  v_src     text;
  v_falta   text;
  o         record;
  v_acao    public.agenda_acoes%rowtype;
  v_dia     date;
  v_tela    jsonb;
  v_vivo_antes boolean;
  v_classe  text;
  r         jsonb;
  v_preset  uuid;
  v_os      uuid;
  v_contagem jsonb;
  c_cli     constant uuid := 'c3400000-0000-4000-8000-0000000000d1';
  c_barco   constant uuid := 'c3410000-0000-4000-8000-0000000000d1';
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_porta   constant uuid := 'c3420000-0000-4000-8000-0000000000d1';
begin
  if to_regprocedure('public._os_recebiveis_da_conclusao(uuid, date)') is null then
    insert into _resultado values ('Q0 a releitura das cobranças (_os_recebiveis_da_conclusao) existe', false, 'não existe: falta 20261026100100');
    return;
  end if;

  -- Só na bancada: as 21 conclusões do replay (só números) e uma conclusão pela porta (com a saída de antes da hora da porta,
  -- como a entrega pela conferência), nas tabelas, dentro desta transação.
  if v_bancada then
    execute current_setting('agenda_teste.replay_conclusoes');
    insert into public.clients (id, type, name) values (c_cli, 'individual', 'Cliente TESTE P7b pós-deploy');
    insert into public.vessels (id, client_id, name) values (c_barco, c_cli, 'Barco TESTE P7b pós-deploy');
    for o in select * from _replay_os order by check_out_at, numero loop
      v_os := md5('pd:' || o.numero)::uuid;
      v_preset := null;
      if o.tem_preset then
        v_preset := md5('pd-preset:' || o.numero)::uuid;
        insert into public.payment_condition_presets (id, label, installments)
        values (v_preset, 'TESTE P7b pós-deploy ' || o.numero, o.preset_installments);
      end if;
      insert into public.service_orders (id, client_id, vessel_id, service_order_number, status, quote_status,
                                         payment_condition_preset_id, custom_payment_installments, grand_total,
                                         labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total,
                                         subcontract_cost_total, is_travel_billable, discount_amount, tax_amount,
                                         created_at, converted_to_os_at, check_out_at)
      values (v_os, c_cli, c_barco, o.numero, 'in_progress', 'approved', v_preset, o.custom_payment_installments, o.grand_total,
              o.labor_cost_total, o.parts_cost_total, o.operational_cost_total, o.travel_cost_total, o.subcontract_cost_total,
              coalesce(o.is_travel_billable, true), o.discount_amount, o.tax_amount, o.created_at, o.converted_to_os_at,
              o.check_out_at);
      insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
                                      balance_amount, is_deposit, due_on_completion, created_at)
      select c_cli, v_os, 'TESTE P7b pós-deploy', x.issue_date, x.due_date, x.amount, x.status, x.paid_amount, x.balance_amount,
             x.is_deposit, x.due_on_completion, x.created_at
        from _replay_rec x where x.numero = o.numero order by x.n;
      v_ids := coalesce(v_ids, '{}') || v_os;
    end loop;
    -- A conclusão pela porta: 50% na aprovação + 50% na entrega, sem sinal; a saída 21:10 e a porta às 21:40 (a entrega
    -- conferida depois conclui com a hora dita): o gabarito vem da ação, não da janela de 5 min; e depois das 21h o saldo
    -- "na entrega" vence no dia UTC seguinte (NOVO-agenda-21), o que a comparação aceita.
    insert into public.payment_condition_presets (id, label, installments)
    values (md5('pd-preset:porta')::uuid, 'TESTE P7b pós-deploy porta',
            '[{"label":"Entrada 50%","tipo":"aprovacao","services_pct":50,"parts_pct":50,"expenses_pct":50,"days_after_approval":0},
              {"label":"Saldo 50%","tipo":"entrega","services_pct":50,"parts_pct":50,"expenses_pct":50,"days_after_approval":0}]');
    insert into public.service_orders (id, client_id, vessel_id, service_order_number, status, quote_status,
                                       payment_condition_preset_id, grand_total, labor_cost_total, parts_cost_total,
                                       created_at, converted_to_os_at)
    values (c_porta, c_cli, c_barco, 'OS-09901', 'in_progress', 'approved', md5('pd-preset:porta')::uuid, 1000, 1000, 0,
            timestamptz '2026-10-20 12:00-03', timestamptz '2026-10-20 12:00-03');
    r := public.os_transicionar_status(c_porta, 'completed', 'dono', null, c_admin, null, date '2026-10-29',
                                       timestamptz '2026-10-29 21:40-03', timestamptz '2026-10-29 21:10-03');
    if not coalesce((r ->> 'ok')::boolean, false) then
      raise exception 'pós-deploy (bancada): a conclusão pela porta não passou: %', r;
    end if;
    v_ids := v_ids || c_porta;
  end if;

  insert into _pd_so
  select so.id, so.service_order_number, so.status, so.check_out_at, so.grand_total, so.labor_cost_total, so.parts_cost_total,
         so.operational_cost_total, so.travel_cost_total, so.subcontract_cost_total, so.is_travel_billable, so.discount_amount,
         so.tax_amount, so.custom_payment_installments, so.payment_condition_preset_id
    from public.service_orders so
   where so.check_out_at is not null
     and case when v_bancada then so.id = any (v_ids) else so.status in ('completed', 'invoiced') end;
  insert into _pd_presets select pc.id, pc.installments from public.payment_condition_presets pc
   where pc.id in (select s.payment_condition_preset_id from _pd_so s);

  -- A cópia da releitura, lendo as cobranças de antes da saída.
  v_src := replace((select p.prosrc from pg_proc p where p.oid = 'public._os_recebiveis_da_conclusao(uuid, date)'::regprocedure),
                   E'\r\n', E'\n');
  v_falta := concat_ws('; ',
    case when (length(v_src) - length(replace(v_src, 'public.service_orders so', ''))) / length('public.service_orders so') <> 1
         then 'public.service_orders so ≠ 1 vez' end,
    case when (length(v_src) - length(replace(v_src, 'public.payment_condition_presets pc', '')))
              / length('public.payment_condition_presets pc') <> 1
         then 'public.payment_condition_presets pc ≠ 1 vez' end,
    case when (length(v_src) - length(replace(v_src, 'public.receivables rc', ''))) / length('public.receivables rc') <> 2
         then 'public.receivables rc ≠ 2 vezes' end,
    case when position('public.receivables ' in replace(v_src, 'public.receivables rc', '')) > 0
         then 'outra leitura de public.receivables' end);
  insert into _resultado values ('Q0 a cópia temporária da releitura de produção troca só as leituras (OS, condição, cobranças de antes)',
                                 nullif(v_falta, '') is null, nullif(v_falta, ''));
  if nullif(v_falta, '') is not null then
    return;
  end if;
  v_src := replace(replace(replace(v_src, 'public.service_orders so', 'pg_temp._pd_so so'),
                           'public.payment_condition_presets pc', 'pg_temp._pd_presets pc'),
                   'public.receivables rc', 'pg_temp._pd_antes rc');
  execute format('create function pg_temp._pd_recebiveis(p_os uuid, p_data date) returns jsonb language plpgsql stable as %L',
                 v_src);

  v_contagem := (select jsonb_build_object('cobrancas', count(*), 'acoes', (select count(*) from public.agenda_acoes),
                                           'os', (select count(*) from public.service_orders))
                   from public.receivables);
  for o in select * from _pd_so order by check_out_at, service_order_number loop
    select a.* into v_acao
      from public.agenda_acoes a
     where a.service_order_id = o.id and a.tipo = 'concluir' and a.executada and a.desfeita_em is null
     order by a.criada_em desc, a.id desc
     limit 1;
    delete from _pd_antes;
    if v_acao.id is not null then
      -- pela porta
      v_dia := v_acao.dia;
      insert into _pd_antes
      select x.id, x.service_order_id, x.description, x.amount, x.due_date, x.created_at, x.due_on_completion, x.status
        from public.receivables x
       where x.service_order_id = o.id and not (x.id = any (v_acao.receivable_ids)) and x.created_at < v_acao.criada_em;
      select jsonb_agg(jsonb_build_object('amount', x.amount, 'status', x.status, 'issue_date', x.issue_date,
                                          'due_date', x.due_date, 'due_on_completion', x.due_on_completion,
                                          'created_at', x.created_at)
                        -- a ordem em que a porta as criou (a das parcelas): a hora é a mesma, a da transação
                        order by array_position(v_acao.receivable_ids, x.id))
        into v_tela
        from public.receivables x where x.id = any (v_acao.receivable_ids);
    else
      -- pela tela (ou por fora), a regra do replay da bancada
      v_dia := (o.check_out_at at time zone 'America/Sao_Paulo')::date;
      insert into _pd_antes
      select x.id, x.service_order_id, x.description, x.amount, x.due_date, x.created_at, x.due_on_completion, x.status
        from public.receivables x
       where x.service_order_id = o.id
         and (x.created_at < o.check_out_at - interval '5 minutes' or (x.is_deposit and x.created_at <= o.check_out_at));
      select jsonb_agg(jsonb_build_object('amount', x.amount, 'status', x.status, 'issue_date', x.issue_date,
                                          'due_date', x.due_date, 'due_on_completion', x.due_on_completion,
                                          'created_at', x.created_at) order by x.created_at, x.id)
        into v_tela
        from public.receivables x
       where x.service_order_id = o.id and not x.is_deposit
         and abs(extract(epoch from (x.created_at - o.check_out_at))) <= 300;
    end if;
    v_vivo_antes := exists (select 1 from _pd_antes x where x.status <> 'cancelled');
    r := pg_temp._pd_recebiveis(o.id, v_dia);
    v_classe := case
      when v_vivo_antes
        then case when exists (select 1 from jsonb_array_elements(coalesce(v_tela, '[]')) t where t ->> 'status' = 'cancelled')
                  then 'C' else 'D' end
      when v_acao.id is not null and r ->> 'motivo' = 'total_zero' and v_tela is null then 'E'
      when v_tela is null then 'F'
      when (select bool_and((t ->> 'amount')::numeric = 0) from jsonb_array_elements(v_tela) t) then 'E'
      when v_acao.id is null
           and (select min((t ->> 'created_at')::timestamptz) from jsonb_array_elements(v_tela) t) < timestamptz '2026-09-23 00:00-03'
        then 'B'
      else 'A' end;
    insert into _pd_resultado values (o.service_order_number, (o.check_out_at at time zone 'America/Sao_Paulo')::date,
                                      (o.check_out_at at time zone 'UTC')::date,
                                      case when v_acao.id is not null then 'porta' else 'tela' end, v_classe, r ->> 'motivo',
                                      r -> 'linhas', v_tela);
  end loop;
  -- Q4: o replay só leu (a cópia é STABLE e lê tabelas temporárias): as cobranças, as ações e as OS do sistema iguais.
  insert into _resultado
  select 'Q4 o replay só leu: as cobranças, as ações da agenda e as OS iguais antes e depois',
         jsonb_build_object('cobrancas', count(*), 'acoes', (select count(*) from public.agenda_acoes),
                            'os', (select count(*) from public.service_orders)) = v_contagem,
         v_contagem::text
    from public.receivables;
end
$q$;

-- Q1: a classe e o que ela espera da releitura.
insert into _resultado
select format('Q1 %s (%s, %s) classe %s', x.numero, to_char(x.saida, 'DD/MM'), x.via, x.classe),
       case x.classe
         when 'A' then x.motivo in ('parcelas', 'titulo_unico')
                       and jsonb_array_length(coalesce(x.linhas, '[]')) = jsonb_array_length(x.tela)
                       and not exists (
                         select 1
                           from jsonb_array_elements(x.tela) with ordinality t(l, o)
                           left join jsonb_array_elements(x.linhas) with ordinality b(l, o) on b.o = t.o
                          where b.l is null
                             or (b.l ->> 'amount')::numeric <> (t.l ->> 'amount')::numeric
                             or (b.l ->> 'issue_date')::date <> (t.l ->> 'issue_date')::date
                             -- a parcela "na entrega" vence no dia UTC da saída (o gatilho de produção, NOVO-agenda-21): a conclusão
                             -- depois das 21h de Brasília tem o saldo no dia seguinte, e isso não é divergência da regra
                             or ((b.l ->> 'due_date')::date <> (t.l ->> 'due_date')::date
                                 and not ((t.l ->> 'due_on_completion')::boolean and (t.l ->> 'due_date')::date = x.saida_utc))
                             or (b.l ->> 'due_on_completion')::boolean <> (t.l ->> 'due_on_completion')::boolean)
         when 'B' then x.motivo = 'titulo_unico' and jsonb_array_length(x.tela) = 1
                       and x.linhas -> 0 ->> 'description' = x.numero
                       and (x.linhas -> 0 ->> 'amount')::numeric = (x.tela -> 0 ->> 'amount')::numeric
                       and (x.linhas -> 0 ->> 'issue_date')::date = (x.tela -> 0 ->> 'issue_date')::date
                       and (x.linhas -> 0 ->> 'due_date')::date = (x.tela -> 0 ->> 'due_date')::date
         when 'C' then x.motivo = 'ja_tem'
         when 'D' then x.motivo = 'ja_tem'
         when 'E' then x.motivo = 'total_zero'
         -- concluída fora da tela, sem nada na hora: só mostra o que a releitura daria (na bancada o TS confere, R3)
         when 'F' then x.motivo is not null
       end,
       format('releitura %s %s | gabarito %s', x.motivo, coalesce(x.linhas::text, '[]'), coalesce(x.tela::text, '—'))
  from _pd_resultado x;

-- Q2: a contagem de 24/10 (a mesma do replay da bancada).
insert into _resultado
select 'Q2 as classes das conclusões até 24/10: A 1 · B 5 · C 3 · D 9 · E 1 · F 2',
       string_agg(c.classe || ' ' || coalesce(n.qtd, 0), ' · ' order by c.classe) = 'A 1 · B 5 · C 3 · D 9 · E 1 · F 2',
       string_agg(c.classe || ' ' || coalesce(n.qtd, 0) || coalesce(' (' || n.quais || ')', ''), ' · ' order by c.classe)
  from (values ('A'), ('B'), ('C'), ('D'), ('E'), ('F')) c(classe)
  left join (select x.classe, count(*) as qtd, string_agg(x.numero, ', ' order by x.numero) as quais
               from _pd_resultado x where x.saida <= date '2026-10-24' group by x.classe) n on n.classe = c.classe
having exists (select 1 from _pd_resultado);

-- Q3: depois de 24/10 (a tela de antes da porta e a porta), toda conclusão cai em A, D ou E (o total zerado sem cobrança).
insert into _resultado
select 'Q3 depois de 24/10, toda conclusão cai em A, D ou E',
       coalesce(bool_and(x.classe in ('A', 'D', 'E')), true),
       coalesce(string_agg(x.numero || ' ' || x.via || ' ' || x.classe, ', ' order by x.numero), 'nenhuma conclusão depois de 24/10')
  from _pd_resultado x where x.saida > date '2026-10-24'
having exists (select 1 from _pd_resultado);

select teste, ok, detalhe from _resultado order by teste;

rollback;
