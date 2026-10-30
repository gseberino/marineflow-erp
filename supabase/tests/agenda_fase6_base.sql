-- Prova da base da Agenda de Produção, Fase 6 (pacote P1): o modo e os parâmetros do aprendizado, os dias ditos no início e a
-- 1ª promessa (os_planejamento), as 2 tabelas do aprendizado e as listas fechadas ampliadas (migration 20261029100000), e as
-- portas das funções da medição (20261029100100).
-- bancada: depende de 20261029100950
--
--   B1 colunas, DEFAULTs e CHECKs (agenda_config, os_planejamento, agenda_medidas_os, agenda_aprendizado); todo CHECK novo de
--      agenda_config tem caso; as palavras da classe são uma lista fechada de pares
--   B2 RLS e privilégios (anon nada; o técnico não lê e não grava; os passos e o gravador sem grant a ninguém; definer só os 3
--      que escrevem; search_path fixo)
--   B3 a coluna gerada critica com aprendizado (as 7 críticas de antes iguais)
--   B4 as tabelas não se apagam; a medida só muda inteira (versão + 1 e o histórico); o valor aprendido não muda de item,
--      chave nem nível
--   B5 os CHECKs de rotina e de ação: aprender e aprendizado entram; o resto continua fora
--   B6 (correção C2, 20261029100950) os 4 parâmetros novos do aprendizado (as janelas da saúde e do foco) e os CHECKs
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase6_base.sql
--   Seguro em produção: as linhas de teste ("TESTE AG6") só são inseridas; termina em ROLLBACK. Não usa a fixture.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Executa um comando e diz que porta o recusou: o nome do CHECK, do índice único ou da FK; 'aceitou' quando entrou (e
-- desfaz); 'erro <estado>: <mensagem>' para o resto.
create function pg_temp.recusa(p_sql text) returns text language plpgsql as $f$
declare
  v_nome text; v_estado text; v_msg text;
begin
  begin
    execute p_sql;
    raise exception using errcode = 'P0001', message = '__aceitou__';
  exception when others then
    get stacked diagnostics v_nome = constraint_name, v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg = '__aceitou__' then return 'aceitou'; end if;
    if v_estado in ('23514', '23505', '23503', '23502', '23P01') then return coalesce(nullif(v_nome, ''), v_estado); end if;
    return 'erro ' || v_estado || ': ' || v_msg;
  end;
end $f$;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou 'erro <estado>: <mensagem>'.
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- O INSERT de uma linha de p_tabela com as colunas de p_linha (jsonb): só as chaves dadas entram (as outras ficam com o
-- DEFAULT).
create function pg_temp.ins(p_tabela text, p_linha jsonb) returns text language sql immutable as $f$
  select format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, %L::jsonb)',
                p_tabela, string_agg(format('%I', k), ', '), string_agg(format('%I', k), ', '), p_tabela, p_linha::text)
    from jsonb_object_keys(p_linha) k
$f$;

-- As linhas de teste: um cliente, o bem e duas OS dele (não dependem da fixture: a prova roda também em produção).
insert into public.clients (id, type, name) values ('d6000000-0000-4000-8000-0000000000e1', 'individual', 'TESTE AG6 Cliente');
insert into public.vessels (id, client_id, name, asset_type)
values ('d6000000-0000-4000-8000-0000000000e2', 'd6000000-0000-4000-8000-0000000000e1', 'TESTE AG6 Motorhome', 'Motorhome');
insert into public.service_orders (id, service_order_number, client_id, vessel_id, status)
values ('d6000000-0000-4000-8000-0000000000e3', 'OS-TESTE-AG6', 'd6000000-0000-4000-8000-0000000000e1',
        'd6000000-0000-4000-8000-0000000000e2', 'open'),
       ('d6000000-0000-4000-8000-0000000000e4', 'OS-TESTE-AG6b', 'd6000000-0000-4000-8000-0000000000e1',
        'd6000000-0000-4000-8000-0000000000e2', 'open');
insert into public.os_planejamento (service_order_id) values ('d6000000-0000-4000-8000-0000000000e3');

create temp table _base (nome text primary key, linha jsonb) on commit drop;
insert into _base values
  ('medida', jsonb_build_object('service_order_id', 'd6000000-0000-4000-8000-0000000000e4', 'classe_bem', 'rv',
                                'classe_sistema', 'energia', 'concluida_em', '2026-10-29', 'valida', false,
                                'motivo', 'sem_diaria', 'medida_em', '2026-10-30 16:05-03')),
  ('aprendizado', jsonb_build_object('item', 'fator', 'chave', 'teste:ag6', 'nivel', 'fina', 'n_min', 6,
                                     'calculado_em', '2026-10-30 16:05-03'));
create function pg_temp.medida(p_over jsonb) returns text language sql stable as $f$
  select pg_temp.ins('agenda_medidas_os', (select linha from _base where nome = 'medida') || p_over)
$f$;
create function pg_temp.aprend(p_over jsonb) returns text language sql stable as $f$
  select pg_temp.ins('agenda_aprendizado', (select linha from _base where nome = 'aprendizado') || p_over)
$f$;

-- O valor aprendido de teste que o caso "a mesma chave" e o B4 mexem.
do $$ begin
  execute pg_temp.aprend('{"id": "d6000000-0000-4000-8000-0000000000c1", "chave": "teste:ag6:1"}');
end $$;

-- ── B1. Colunas, DEFAULTs e CHECKs ──────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B1a agenda_config: modo_aprendizado nasce desligado na linha e o DEFAULT da coluna é sombra; a lista vazia; os 43 parâmetros com o valor da spec (§4.1)',
       c.modo_aprendizado = 'desligado' and c.aprendizado_ligados = '{}'
       and (select pg_get_expr(d.adbin, d.adrelid) from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'modo_aprendizado') like '''sombra''%'
       and c.aprender_hora = time '16:00' and c.aprender_janela_dias = 365 and c.aprender_trava_dias = 28
       and c.fator_n_min = 6 and c.fator_percentil = 0.80 and c.fator_amostra_max = 20 and c.fator_min = 1.00
       and c.fator_max = 2.50 and c.fator_troca_max = 0.30
       and c.mo_n_min = 6 and c.mo_min = 300 and c.mo_troca_max = 0.25
       and c.presenca_n_min = 4 and c.presenca_intervencoes_min = 3 and c.presenca_taxa_min = 0.50
       and c.fornecedor_n_min = 5 and c.fornecedor_percentil = 0.80 and c.fornecedor_troca_max_du = 3
       and c.capacidade_semanas = 8 and c.capacidade_semanas_min = 4 and c.capacidade_meios_min = 2
       and c.capacidade_dono_min = 0.40 and c.capacidade_troca_max = 0.20
       and c.capacidade_motivos = '{equipe_faltou,urgencia_outra_os,trabalho_anterior,esqueci}'
       and c.cliente_n_min = 6 and c.aviso_n_min = 5 and c.aviso_folga_max_du = 5 and c.aviso_troca_max_du = 2
       and c.revisao_semanas = 8 and c.ppc_baixo = 0.60 and c.ppc_baixo_semanas = 3 and c.carga_ppc_baixo = 0.70
       and c.ppc_alto = 0.88 and c.ppc_alto_semanas = 4 and c.carga_ppc_alto = 0.85
       and c.solver_os_ativas = 25 and c.solver_pessoas = 6 and c.solver_curtas_dia = 2.0 and c.solver_descarte_pct = 0.20
       and c.solver_semanas = 4 and c.solver_gatilhos_min = 2
       and (select array_agg(e ->> 0 order by o) from jsonb_array_elements(c.classe_bens) with ordinality t(e, o)) = '{rv,barco}'
       and (select array_agg(e ->> 0 order by o) from jsonb_array_elements(c.classe_sistemas) with ordinality t(e, o))
           = '{diagnostico,energia,motor,conectividade,conforto}'
       -- o 1,5 de antes não muda: estouro_fator (o que o fator aprendido substitui) e fator_promessa (sem leitor)
       and c.estouro_fator = 1.50 and c.fator_promessa = 1.50
       and (select col_description('public.agenda_config'::regclass, a.attnum) from pg_attribute a
             where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'fator_promessa') like '%SEM LEITOR (NOVO-agenda-43)%',
       (to_jsonb(c) - 'classe_bens' - 'classe_sistemas')::text
  from public.agenda_config c;

insert into _resultado
select 'B1b agenda_config: as 45 colunas novas (o modo, a lista e os 43 parâmetros), todas NOT NULL com DEFAULT',
       count(*) = 45 and bool_and(a.attnotnull and a.atthasdef),
       count(*)::text || ' colunas; sem NOT NULL/DEFAULT: '
         || coalesce(string_agg(a.attname, ', ') filter (where not (a.attnotnull and a.atthasdef)), '—')
  from pg_attribute a
 where a.attrelid = 'public.agenda_config'::regclass and not a.attisdropped
   and a.attname in ('modo_aprendizado', 'aprendizado_ligados', 'aprender_hora', 'aprender_janela_dias', 'aprender_trava_dias',
                     'fator_n_min', 'fator_percentil', 'fator_amostra_max', 'fator_min', 'fator_max', 'fator_troca_max',
                     'mo_n_min', 'mo_min', 'mo_troca_max', 'presenca_n_min', 'presenca_intervencoes_min', 'presenca_taxa_min',
                     'fornecedor_n_min', 'fornecedor_percentil', 'fornecedor_troca_max_du', 'capacidade_semanas',
                     'capacidade_semanas_min', 'capacidade_meios_min', 'capacidade_dono_min', 'capacidade_troca_max',
                     'capacidade_motivos', 'cliente_n_min', 'aviso_n_min', 'aviso_folga_max_du', 'aviso_troca_max_du',
                     'revisao_semanas', 'ppc_baixo', 'ppc_baixo_semanas', 'carga_ppc_baixo', 'ppc_alto', 'ppc_alto_semanas',
                     'carga_ppc_alto', 'solver_os_ativas', 'solver_pessoas', 'solver_curtas_dia', 'solver_descarte_pct',
                     'solver_semanas', 'solver_gatilhos_min', 'classe_bens', 'classe_sistemas');

insert into _resultado
select 'B1c os_planejamento: as 4 colunas novas, todas nulas, com o tipo da spec',
       count(*) = 4
       and bool_and(not a.attnotnull and a.atthasdef = false)
       and string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
           = 'dias_no_inicio:numeric(4,1),dias_no_inicio_em:date,dias_no_inicio_fonte:text,prometido_primeiro_ate:date',
       string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
  from pg_attribute a
 where a.attrelid = 'public.os_planejamento'::regclass and not a.attisdropped
   and a.attname in ('dias_no_inicio', 'dias_no_inicio_fonte', 'dias_no_inicio_em', 'prometido_primeiro_ate');

create temp table _casos (grupo text, nome text, sql text, espera text) on commit drop;
insert into _casos values
  -- agenda_config
  ('config', 'modo_aprendizado', $q$update public.agenda_config set modo_aprendizado = 'x'$q$, 'agenda_config_modo_aprendizado_check'),
  ('config', 'item que não existe na lista', $q$update public.agenda_config set aprendizado_ligados = '{fator,comissao}'$q$, 'agenda_config_aprendizado_ligados_check'),
  ('config', 'rodada às 11:59', $q$update public.agenda_config set aprender_hora = '11:59'$q$, 'agenda_config_aprender_hora_check'),
  ('config', 'rodada depois do plano (16:31)', $q$update public.agenda_config set aprender_hora = '16:31'$q$, 'agenda_config_aprender_hora_check'),
  ('config', 'janela de 89 dias', $q$update public.agenda_config set aprender_janela_dias = 89$q$, 'agenda_config_aprender_janela_dias_check'),
  ('config', 'janela de 731 dias', $q$update public.agenda_config set aprender_janela_dias = 731$q$, 'agenda_config_aprender_janela_dias_check'),
  ('config', 'trava de 6 dias', $q$update public.agenda_config set aprender_trava_dias = 6$q$, 'agenda_config_aprender_trava_dias_check'),
  ('config', 'trava de 91 dias', $q$update public.agenda_config set aprender_trava_dias = 91$q$, 'agenda_config_aprender_trava_dias_check'),
  ('config', 'fator com 2 OS', $q$update public.agenda_config set fator_n_min = 2$q$, 'agenda_config_fator_n_min_check'),
  ('config', 'fator com 21 OS', $q$update public.agenda_config set fator_n_min = 21$q$, 'agenda_config_fator_n_min_check'),
  ('config', 'percentil do fator 0,49', $q$update public.agenda_config set fator_percentil = 0.49$q$, 'agenda_config_fator_percentil_check'),
  ('config', 'percentil do fator 0,96', $q$update public.agenda_config set fator_percentil = 0.96$q$, 'agenda_config_fator_percentil_check'),
  ('config', 'amostra de 5', $q$update public.agenda_config set fator_amostra_max = 5$q$, 'agenda_config_fator_amostra_max_check'),
  ('config', 'amostra de 61', $q$update public.agenda_config set fator_amostra_max = 61$q$, 'agenda_config_fator_amostra_max_check'),
  ('config', 'fator mínimo 0,99 (encurtaria o plano)', $q$update public.agenda_config set fator_min = 0.99$q$, 'agenda_config_fator_min_check'),
  ('config', 'fator mínimo igual ao máximo', $q$update public.agenda_config set fator_min = 1.50, fator_max = 1.50$q$, 'agenda_config_fator_min_check'),
  ('config', 'fator máximo 3,01', $q$update public.agenda_config set fator_max = 3.01$q$, 'agenda_config_fator_max_check'),
  ('config', 'fator máximo 1,49', $q$update public.agenda_config set fator_max = 1.49, fator_min = 1.00$q$, 'agenda_config_fator_max_check'),
  ('config', 'troca de fator 0,09', $q$update public.agenda_config set fator_troca_max = 0.09$q$, 'agenda_config_fator_troca_max_check'),
  ('config', 'troca de fator 1,01', $q$update public.agenda_config set fator_troca_max = 1.01$q$, 'agenda_config_fator_troca_max_check'),
  ('config', 'R$ por diária com 2 OS', $q$update public.agenda_config set mo_n_min = 2$q$, 'agenda_config_mo_n_min_check'),
  ('config', 'piso do R$ por diária 0', $q$update public.agenda_config set mo_min = 0$q$, 'agenda_config_mo_min_check'),
  ('config', 'piso do R$ por diária negativo', $q$update public.agenda_config set mo_min = -1$q$, 'agenda_config_mo_min_check'),
  ('config', 'troca do R$ por diária 51%', $q$update public.agenda_config set mo_troca_max = 0.51$q$, 'agenda_config_mo_troca_max_check'),
  ('config', 'troca do R$ por diária 4%', $q$update public.agenda_config set mo_troca_max = 0.04$q$, 'agenda_config_mo_troca_max_check'),
  ('config', 'presença com 21 OS', $q$update public.agenda_config set presenca_n_min = 21$q$, 'agenda_config_presenca_n_min_check'),
  ('config', 'presença com 1 intervenção', $q$update public.agenda_config set presenca_intervencoes_min = 1$q$, 'agenda_config_presenca_intervencoes_min_check'),
  ('config', 'presença com 11 intervenções', $q$update public.agenda_config set presenca_intervencoes_min = 11$q$, 'agenda_config_presenca_intervencoes_min_check'),
  ('config', 'taxa da presença 0,19', $q$update public.agenda_config set presenca_taxa_min = 0.19$q$, 'agenda_config_presenca_taxa_min_check'),
  ('config', 'fornecedor com 2 entregas', $q$update public.agenda_config set fornecedor_n_min = 2$q$, 'agenda_config_fornecedor_n_min_check'),
  ('config', 'percentil do fornecedor 0,96', $q$update public.agenda_config set fornecedor_percentil = 0.96$q$, 'agenda_config_fornecedor_percentil_check'),
  ('config', 'troca do fornecedor 11 dias úteis', $q$update public.agenda_config set fornecedor_troca_max_du = 11$q$, 'agenda_config_fornecedor_troca_max_du_check'),
  ('config', 'troca do fornecedor 0', $q$update public.agenda_config set fornecedor_troca_max_du = 0$q$, 'agenda_config_fornecedor_troca_max_du_check'),
  ('config', 'capacidade em 3 semanas', $q$update public.agenda_config set capacidade_semanas = 3$q$, 'agenda_config_capacidade_semanas_check'),
  ('config', 'capacidade em 27 semanas', $q$update public.agenda_config set capacidade_semanas = 27$q$, 'agenda_config_capacidade_semanas_check'),
  ('config', 'capacidade com 1 semana medida', $q$update public.agenda_config set capacidade_semanas_min = 1$q$, 'agenda_config_capacidade_semanas_min_check'),
  ('config', 'semanas medidas acima das semanas lidas', $q$update public.agenda_config set capacidade_semanas_min = 9$q$, 'agenda_config_capacidade_semanas_min_check'),
  ('config', 'semana com 0 meio-dia conta', $q$update public.agenda_config set capacidade_meios_min = 0$q$, 'agenda_config_capacidade_meios_min_check'),
  ('config', 'piso da carga do dono 0,19', $q$update public.agenda_config set capacidade_dono_min = 0.19$q$, 'agenda_config_capacidade_dono_min_check'),
  ('config', 'piso da carga do dono 0,81', $q$update public.agenda_config set capacidade_dono_min = 0.81$q$, 'agenda_config_capacidade_dono_min_check'),
  ('config', 'troca da capacidade 0,04', $q$update public.agenda_config set capacidade_troca_max = 0.04$q$, 'agenda_config_capacidade_troca_max_check'),
  ('config', 'motivo que não é da conferência', $q$update public.agenda_config set capacidade_motivos = '{esqueci,preguica}'$q$, 'agenda_config_capacidade_motivos_check'),
  ('config', 'pontualidade com 2 OS', $q$update public.agenda_config set cliente_n_min = 2$q$, 'agenda_config_cliente_n_min_check'),
  ('config', 'folga com 21 avisos', $q$update public.agenda_config set aviso_n_min = 21$q$, 'agenda_config_aviso_n_min_check'),
  ('config', 'folga do aviso até 11 dias úteis', $q$update public.agenda_config set aviso_folga_max_du = 11$q$, 'agenda_config_aviso_folga_max_du_check'),
  ('config', 'troca da folga 6 dias úteis', $q$update public.agenda_config set aviso_troca_max_du = 6$q$, 'agenda_config_aviso_troca_max_du_check'),
  ('config', 'revisão em 27 semanas', $q$update public.agenda_config set revisao_semanas = 27$q$, 'agenda_config_revisao_semanas_check'),
  ('config', 'revisão em 3 semanas', $q$update public.agenda_config set revisao_semanas = 3$q$, 'agenda_config_revisao_semanas_check'),
  ('config', 'plano baixo acima do alto', $q$update public.agenda_config set ppc_baixo = 0.90$q$, 'agenda_config_ppc_baixo_check'),
  ('config', 'plano baixo 0', $q$update public.agenda_config set ppc_baixo = 0$q$, 'agenda_config_ppc_baixo_check'),
  ('config', 'plano alto 101%', $q$update public.agenda_config set ppc_alto = 1.01$q$, 'agenda_config_ppc_alto_check'),
  ('config', 'plano baixo por 1 semana', $q$update public.agenda_config set ppc_baixo_semanas = 1$q$, 'agenda_config_ppc_baixo_semanas_check'),
  ('config', 'plano alto por 13 semanas', $q$update public.agenda_config set ppc_alto_semanas = 13$q$, 'agenda_config_ppc_alto_semanas_check'),
  ('config', 'carga recomendada (baixo) 0,49', $q$update public.agenda_config set carga_ppc_baixo = 0.49$q$, 'agenda_config_carga_ppc_baixo_check'),
  ('config', 'carga recomendada (alto) 1,01', $q$update public.agenda_config set carga_ppc_alto = 1.01$q$, 'agenda_config_carga_ppc_alto_check'),
  ('config', 'gatilho de 0 OS ativas', $q$update public.agenda_config set solver_os_ativas = 0$q$, 'agenda_config_solver_os_ativas_check'),
  ('config', 'gatilho de 0 pessoas', $q$update public.agenda_config set solver_pessoas = 0$q$, 'agenda_config_solver_pessoas_check'),
  ('config', 'gatilho de 0 curtas por dia', $q$update public.agenda_config set solver_curtas_dia = 0$q$, 'agenda_config_solver_curtas_dia_check'),
  ('config', 'gatilho de 51% descartadas', $q$update public.agenda_config set solver_descarte_pct = 0.51$q$, 'agenda_config_solver_descarte_pct_check'),
  ('config', 'gatilhos por 0 semanas', $q$update public.agenda_config set solver_semanas = 0$q$, 'agenda_config_solver_semanas_check'),
  ('config', '5 gatilhos (são 4)', $q$update public.agenda_config set solver_gatilhos_min = 5$q$, 'agenda_config_solver_gatilhos_min_check'),
  ('config', 'bens: lista vazia', $q$update public.agenda_config set classe_bens = '[]'$q$, 'agenda_config_classe_bens_check'),
  ('config', 'bens: par sem as palavras', $q$update public.agenda_config set classe_bens = '[["rv"]]'$q$, 'agenda_config_classe_bens_check'),
  ('config', 'bens: chave fora da lista', $q$update public.agenda_config set classe_bens = '[["casa","casa|apartamento"]]'$q$, 'agenda_config_classe_bens_check'),
  ('config', 'bens: chave repetida', $q$update public.agenda_config set classe_bens = '[["rv","motorhome"],["rv","camper"]]'$q$, 'agenda_config_classe_bens_check'),
  ('config', 'sistemas: chave fora da lista', $q$update public.agenda_config set classe_sistemas = '[["comida","cozinha"]]'$q$, 'agenda_config_classe_sistemas_check'),
  ('config', 'sistemas: objeto, não lista', $q$update public.agenda_config set classe_sistemas = '{"energia": "bateria"}'$q$, 'agenda_config_classe_sistemas_check'),
  ('config', 'sistemas: palavras vazias', $q$update public.agenda_config set classe_sistemas = '[["energia","  "]]'$q$, 'agenda_config_classe_sistemas_check'),
  ('config', 'os limites que entram (ligado, a lista inteira, 12:00 e 16:30, 90/7/3/0,50/6, 1,00–3,00, a carga e o planejador nos extremos, os sistemas em outra ordem)',
   $q$update public.agenda_config set modo_aprendizado = 'ligado',
        aprendizado_ligados = '{fator,mo,presenca,fornecedor,capacidade_dono,aviso_cliente,revisao}',
        aprender_hora = '12:00', aprender_janela_dias = 90, aprender_trava_dias = 7, fator_n_min = 3, fator_percentil = 0.50,
        fator_amostra_max = 6, fator_min = 1.00, fator_max = 3.00, fator_troca_max = 1.00, mo_min = 1, mo_troca_max = 0.05,
        capacidade_semanas = 26, capacidade_semanas_min = 26, capacidade_dono_min = 0.20, ppc_baixo = 0.01, ppc_alto = 1,
        carga_ppc_baixo = 0.50, carga_ppc_alto = 1.00, solver_descarte_pct = 0.05, solver_gatilhos_min = 4,
        capacidade_motivos = '{}',
        classe_sistemas = '[["energia","bateria"],["diagnostico","diagnost"]]'$q$, 'aceitou'),
  ('config', 'rodada no horário do plano (16:30) entra', $q$update public.agenda_config set aprender_hora = hora_do_plano$q$, 'aceitou'),
  -- os_planejamento (a OS de teste)
  ('planejamento', 'dias no início 0', $q$update public.os_planejamento set dias_no_inicio = 0, dias_no_inicio_fonte = 'dono', dias_no_inicio_em = '2026-10-30' where service_order_id = 'd6000000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_dias_no_inicio_check'),
  ('planejamento', 'dias no início fora do meio dia (1,3)', $q$update public.os_planejamento set dias_no_inicio = 1.3, dias_no_inicio_fonte = 'dono', dias_no_inicio_em = '2026-10-30' where service_order_id = 'd6000000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_dias_no_inicio_check'),
  ('planejamento', 'fonte sugerida (a sugestão nunca é congelada)', $q$update public.os_planejamento set dias_no_inicio = 2, dias_no_inicio_fonte = 'sugerida', dias_no_inicio_em = '2026-10-30' where service_order_id = 'd6000000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_dias_no_inicio_fonte_check'),
  ('planejamento', 'dias sem a fonte', $q$update public.os_planejamento set dias_no_inicio = 2, dias_no_inicio_em = '2026-10-30' where service_order_id = 'd6000000-0000-4000-8000-0000000000e3'$q$, 'dias_no_inicio_coerente'),
  ('planejamento', 'dias sem o dia do check-in', $q$update public.os_planejamento set dias_no_inicio = 2, dias_no_inicio_fonte = 'dono' where service_order_id = 'd6000000-0000-4000-8000-0000000000e3'$q$, 'dias_no_inicio_coerente'),
  ('planejamento', 'os dias do início (1,5, aceita) e a 1ª promessa sem prometido de agora (o aviso sem data zerou)',
   $q$update public.os_planejamento set dias_no_inicio = 1.5, dias_no_inicio_fonte = 'aceita', dias_no_inicio_em = '2026-10-26', prometido_primeiro_ate = '2026-10-23' where service_order_id = 'd6000000-0000-4000-8000-0000000000e3'$q$, 'aceitou'),
  -- agenda_medidas_os
  ('medida', 'bem fora da lista', pg_temp.medida('{"classe_bem": "casa"}'), 'agenda_medidas_os_classe_bem_check'),
  ('medida', 'sistema fora da lista', pg_temp.medida('{"classe_sistema": "cozinha"}'), 'agenda_medidas_os_classe_sistema_check'),
  ('medida', 'dias com a fonte fora da lista', pg_temp.medida('{"dias_no_inicio": 1, "dias_fonte": "chute"}'), 'agenda_medidas_os_dias_fonte_check'),
  ('medida', 'motivo fora da lista', pg_temp.medida('{"motivo": "preguica"}'), 'agenda_medidas_os_motivo_check'),
  ('medida', 'válida com motivo', pg_temp.medida('{"valida": true}'), 'medida_valida_sem_motivo'),
  ('medida', 'inválida sem motivo', pg_temp.medida('{"motivo": null}'), 'medida_valida_sem_motivo'),
  ('medida', 'fator na inválida', pg_temp.medida('{"fator": 1.25}'), 'medida_fator_so_valida'),
  ('medida', 'dias sem a fonte', pg_temp.medida('{"dias_no_inicio": 1}'), 'medida_dias_coerente'),
  ('medida', 'histórico de 21', pg_temp.medida(jsonb_build_object('historico', (select jsonb_agg(g) from generate_series(1, 21) g))), 'agenda_medidas_os_historico_check'),
  ('medida', 'histórico que não é lista', pg_temp.medida('{"historico": {}}'), 'agenda_medidas_os_historico_check'),
  ('medida', 'OS que não existe', pg_temp.medida('{"service_order_id": "d6000000-0000-4000-8000-0000000000ff"}'), 'agenda_medidas_os_service_order_id_fkey'),
  ('medida', 'sem a hora da medida', pg_temp.medida('{"medida_em": null}'), '23502'),
  ('medida', 'a válida com o fator, os meios e o cliente', pg_temp.medida('{"valida": true, "motivo": null, "fator": 1.75, "dias_no_inicio": 2, "dias_fonte": "dono", "meios_planejados": 4, "meios_cumpridos": 7, "diarias_ligadas": 4, "mo": 2760, "prometido_primeiro_ate": "2026-10-30", "atraso_cliente_du": -1, "avisos_enviados": 1, "aviso_faixa_ate": "2026-10-26", "aviso_estouro_du": 3}'), 'aceitou'),
  -- agenda_aprendizado
  ('aprendizado', 'item fora da lista', pg_temp.aprend('{"item": "comissao"}'), 'agenda_aprendizado_item_check'),
  ('aprendizado', 'nível fora da lista', pg_temp.aprend('{"nivel": "cidade"}'), 'agenda_aprendizado_nivel_check'),
  ('aprendizado', 'chave vazia', pg_temp.aprend('{"chave": ""}'), 'agenda_aprendizado_chave_check'),
  ('aprendizado', 'chave de 61', pg_temp.aprend(jsonb_build_object('chave', repeat('x', 61))), 'agenda_aprendizado_chave_check'),
  ('aprendizado', 'estado fora da lista', pg_temp.aprend('{"estado": "ligado"}'), 'agenda_aprendizado_estado_check'),
  ('aprendizado', 'em uso sem o valor', pg_temp.aprend('{"estado": "em_uso"}'), 'aprendizado_em_uso_coerente'),
  ('aprendizado', 'em teste com valor em uso', pg_temp.aprend('{"estado": "sombra", "em_uso": 1.7}'), 'aprendizado_em_uso_coerente'),
  ('aprendizado', 'medindo com valor em uso', pg_temp.aprend('{"em_uso": 1.7}'), 'aprendizado_em_uso_coerente'),
  ('aprendizado', 'pergunta sem a pergunta', pg_temp.aprend('{"estado": "pergunta"}'), 'aprendizado_pergunta_tem_id'),
  ('aprendizado', 'travado sem a data', pg_temp.aprend('{"estado": "travado"}'), 'aprendizado_travado_coerente'),
  ('aprendizado', 'a data da trava sem travado', pg_temp.aprend('{"travado_ate": "2026-11-27"}'), 'aprendizado_travado_coerente'),
  ('aprendizado', 'texto de 401', pg_temp.aprend(jsonb_build_object('texto', repeat('x', 401))), 'agenda_aprendizado_texto_check'),
  ('aprendizado', 'amostra de 61', pg_temp.aprend(jsonb_build_object('amostra', (select jsonb_agg(g) from generate_series(1, 61) g))), 'agenda_aprendizado_amostra_check'),
  ('aprendizado', 'detalhe que não é objeto', pg_temp.aprend('{"detalhe": []}'), 'agenda_aprendizado_detalhe_check'),
  ('aprendizado', 'histórico de 21', pg_temp.aprend(jsonb_build_object('historico', (select jsonb_agg(g) from generate_series(1, 21) g))), 'agenda_aprendizado_historico_check'),
  ('aprendizado', 'sem o mínimo', pg_temp.aprend('{"n_min": null}'), '23502'),
  ('aprendizado', 'a mesma chave do mesmo item', pg_temp.aprend('{"chave": "teste:ag6:1"}'), 'agenda_aprendizado_item_chave_key'),
  ('aprendizado', 'a mesma chave em outro item entra', pg_temp.aprend('{"item": "mo", "chave": "teste:ag6:1", "nivel": "todas"}'), 'aceitou'),
  ('aprendizado', 'em uso com o valor', pg_temp.aprend('{"estado": "em_uso", "em_uso": 1.7, "calculado": 1.7, "n": 7, "em_uso_desde": "2026-10-30 16:05-03"}'), 'aceitou'),
  ('aprendizado', 'na pergunta, guardando o que vale', pg_temp.aprend('{"estado": "pergunta", "em_uso": 1.7, "calculado": 2.1, "n": 8, "pergunta_id": "d6000000-0000-4000-8000-0000000000f1"}'), 'aceitou'),
  ('aprendizado', 'na pergunta, valendo o padrão', pg_temp.aprend('{"estado": "pergunta", "calculado": 2.1, "n": 8, "pergunta_id": "d6000000-0000-4000-8000-0000000000f1"}'), 'aceitou'),
  ('aprendizado', 'travado, guardando o que vale', pg_temp.aprend('{"estado": "travado", "em_uso": 1.7, "travado_ate": "2026-11-27", "travado_valor": 2.1}'), 'aceitou');

insert into _resultado
select format('B1 %s: %s', k.grupo, k.nome), r = k.espera, r
  from _casos k, lateral (select pg_temp.recusa(k.sql) as r) x;

-- Os 45 CHECKs de agenda_config desta migration (o do-bloco da §1): todos existem e cada um tem caso.
create temp table _checks_f6 (nome text primary key) on commit drop;
insert into _checks_f6
select 'agenda_config_' || n || '_check'
  from unnest(array['modo_aprendizado', 'aprendizado_ligados', 'aprender_hora', 'aprender_janela_dias', 'aprender_trava_dias',
                    'fator_n_min', 'fator_percentil', 'fator_amostra_max', 'fator_min', 'fator_max', 'fator_troca_max',
                    'mo_n_min', 'mo_min', 'mo_troca_max', 'presenca_n_min', 'presenca_intervencoes_min', 'presenca_taxa_min',
                    'fornecedor_n_min', 'fornecedor_percentil', 'fornecedor_troca_max_du', 'capacidade_semanas',
                    'capacidade_semanas_min', 'capacidade_meios_min', 'capacidade_dono_min', 'capacidade_troca_max',
                    'capacidade_motivos', 'cliente_n_min', 'aviso_n_min', 'aviso_folga_max_du', 'aviso_troca_max_du',
                    'revisao_semanas', 'ppc_baixo', 'ppc_alto', 'ppc_baixo_semanas', 'ppc_alto_semanas', 'carga_ppc_baixo',
                    'carga_ppc_alto', 'solver_os_ativas', 'solver_pessoas', 'solver_curtas_dia', 'solver_descarte_pct',
                    'solver_semanas', 'solver_gatilhos_min', 'classe_bens', 'classe_sistemas']) n;

insert into _resultado
select 'B1z os 45 CHECKs novos de agenda_config existem e todos têm caso (nenhum ficou sem prova)',
       count(*) = 45 and bool_and(exists (select 1 from pg_constraint c where c.conrelid = 'public.agenda_config'::regclass
                                                                         and c.conname = k.nome and c.contype = 'c'))
       and bool_and(exists (select 1 from _casos x where x.espera = k.nome)),
       format('%s; sem constraint: %s; sem caso: %s', count(*),
              coalesce(string_agg(k.nome, ', ') filter (where not exists (select 1 from pg_constraint c
                         where c.conrelid = 'public.agenda_config'::regclass and c.conname = k.nome)), '—'),
              coalesce(string_agg(k.nome, ', ') filter (where not exists (select 1 from _casos x where x.espera = k.nome)), '—'))
  from _checks_f6 k;

insert into _resultado
select 'B1z os CHECKs de os_planejamento, agenda_medidas_os e agenda_aprendizado têm caso',
       bool_and(exists (select 1 from _casos k where k.espera = c.conname)),
       coalesce(string_agg(c.conname, ', ') filter (where not exists (select 1 from _casos k where k.espera = c.conname)), '—')
  from pg_constraint c
 where c.contype = 'c'
   and ((c.conrelid = 'public.os_planejamento'::regclass
         and c.conname in ('dias_no_inicio_coerente', 'os_planejamento_dias_no_inicio_check', 'os_planejamento_dias_no_inicio_fonte_check'))
        or c.conrelid in ('public.agenda_medidas_os'::regclass, 'public.agenda_aprendizado'::regclass))
   -- FASE 7: o CHECK que a Fase 7a pôs em agenda_medidas_os (20261031100000: o fator da estimativa só na medida válida por
   -- orçamento) tem o caso dele em agenda_fase7a_base.sql (B1z). A lista dias_fonte ampliada continua com o nome e o caso daqui.
   and c.conname <> 'fator_orcamento_so_orcamento';
   -- FASE 7: fim

-- ── B2. RLS e privilégios ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B2a as 2 tabelas: RLS ligada e uma policy só, de leitura, TO authenticated',
       bool_and(c.relrowsecurity)
       and bool_and((select count(*) from pg_policy p where p.polrelid = c.oid) = 1)
       and bool_and((select bool_and(p.polcmd = 'r' and p.polroles = array[(select oid from pg_roles where rolname = 'authenticated')])
                       from pg_policy p where p.polrelid = c.oid)),
       string_agg(c.relname, ', ')
  from pg_class c
 where c.oid in ('public.agenda_medidas_os'::regclass, 'public.agenda_aprendizado'::regclass);

insert into _resultado
select 'B2b anon sem privilégio nenhum; authenticated só lê; service_role escreve',
       bool_and(not has_table_privilege('anon', t, 'select') and not has_table_privilege('anon', t, 'insert')
                and not has_table_privilege('anon', t, 'update') and not has_table_privilege('anon', t, 'delete'))
       and bool_and(has_table_privilege('authenticated', t, 'select') and not has_table_privilege('authenticated', t, 'insert')
                    and not has_table_privilege('authenticated', t, 'update') and not has_table_privilege('authenticated', t, 'delete'))
       and bool_and(has_table_privilege('service_role', t, 'insert') and has_table_privilege('service_role', t, 'update')),
       null
  from unnest(array['public.agenda_medidas_os', 'public.agenda_aprendizado']) t;

create temp table _funcoes_f6 (f text primary key, quem text) on commit drop;
insert into _funcoes_f6 values
  ('public._agenda_classe_pares_ok(jsonb, text[])', 'leitura'),
  ('public._agenda_classe_nome(text, text)', 'leitura'),
  ('public._agenda_classe_texto_do_nivel(text)', 'leitura'),
  ('public._agenda_percentil(numeric[], numeric)', 'leitura'),
  ('public._agenda_aprendizado_da_lista(text)', 'leitura'),
  ('public._agenda_aprendido(text, text)', 'leitura'),
  ('public._agenda_aprendizado_valor(text, numeric)', 'leitura'),
  ('public._agenda_aprendizado_texto(text, text, jsonb)', 'leitura'),
  -- FASE 6 (P2): a 20261029100200 abre a classe de campo como leitura (invoker; é lida de dentro de os_presenca_do_dono e
  -- da vigia, que o painel e o motor chamam). Antes dela, interna.
  ('public._agenda_classe_de_campo(uuid)',
   case when to_regprocedure('public.agenda_fator_de_campo(uuid, date)') is null then 'interna' else 'leitura' end),
  ('public._agenda_dias_no_inicio(uuid)', 'interna'),
  ('public._agenda_aprender_medir(date)', 'interna'),
  ('public._agenda_aprendizado_troca_cabe(text, text, numeric, numeric)', 'interna'),
  ('public._agenda_aprender_congelar(date)', 'escrita'),
  ('public.agenda_medir_os(uuid, date)', 'escrita'),
  ('public._agenda_aprendizado_gravar(text, text, text, numeric, integer, jsonb, numeric, jsonb, timestamptz)', 'escrita'),
  ('public._agenda_medidas_so_muda()', 'gatilho'),
  ('public._agenda_aprendizado_so_muda()', 'gatilho');

insert into _resultado
select 'B2c funções: anon nada; authenticated e service_role só as leituras e os textos; os passos, a medida e o gravador sem grant a ninguém, nem service_role; os gatilhos sem authenticated',
       bool_and(not has_function_privilege('anon', f, 'execute'))
       and bool_and(has_function_privilege('authenticated', f, 'execute') = (quem = 'leitura'))
       and bool_and(has_function_privilege('service_role', f, 'execute') = (quem = 'leitura') or quem = 'gatilho'),
       coalesce(string_agg(f, ', ') filter (where has_function_privilege('anon', f, 'execute')
                                      or has_function_privilege('authenticated', f, 'execute') <> (quem = 'leitura')
                                      or not (has_function_privilege('service_role', f, 'execute') = (quem = 'leitura') or quem = 'gatilho')), '—')
  from _funcoes_f6;

insert into _resultado
select 'B2d security definer só as 3 que escrevem (o congelar, a medida, o gravador); leituras STABLE/IMMUTABLE; search_path fixo em todas',
       bool_and(p.prosecdef = (k.quem = 'escrita'))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and bool_and(p.provolatile in ('s', 'i') or k.quem not in ('leitura')),
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ' order by p.proname)
  from _funcoes_f6 k join pg_proc p on p.oid = k.f::regprocedure;

insert into _resultado
select 'B2e as 17 funções novas da Fase 6 são todas as _agenda_/agenda_ das 2 migrations (nenhuma esquecida no B2c)',
       count(*) = 17, string_agg(p.proname, ', ' order by p.proname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('_agenda_classe_pares_ok', '_agenda_classe_nome', '_agenda_classe_texto_do_nivel', '_agenda_percentil',
                     '_agenda_aprendizado_da_lista', '_agenda_aprendido', '_agenda_aprendizado_valor', '_agenda_aprendizado_texto',
                     '_agenda_classe_de_campo', '_agenda_dias_no_inicio', '_agenda_aprender_medir',
                     '_agenda_aprendizado_troca_cabe', '_agenda_aprender_congelar', 'agenda_medir_os',
                     '_agenda_aprendizado_gravar', '_agenda_medidas_so_muda', '_agenda_aprendizado_so_muda');

insert into _resultado
select 'B2f o técnico: as tabelas voltam vazias e medir, congelar e gravar dão 42501; anon não lê nem lê o aprendido; o administrador lê',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select (select count(*) from public.agenda_medidas_os) + (select count(*) from public.agenda_aprendizado)$q$) = '0'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select public.agenda_medir_os('d6000000-0000-4000-8000-0000000000e3', date '2026-10-30')::text$q$) like 'erro 42501%'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select public._agenda_aprender_congelar(date '2026-10-30')::text$q$) like 'erro 42501%'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select public._agenda_aprendizado_gravar('fator', 'todas', 'todas', 1.7, 7, '[]', 1.5, '{}', now())::text$q$) like 'erro 42501%'
       and pg_temp.como(null, 'service_role',
             $q$select public._agenda_aprendizado_gravar('fator', 'todas', 'todas', 1.7, 7, '[]', 1.5, '{}', now())::text$q$) like 'erro 42501%'
       and pg_temp.como(null, 'anon', $q$select count(*)::text from public.agenda_aprendizado$q$) like 'erro 42501%'
       and pg_temp.como(null, 'anon', $q$select public._agenda_aprendido('fator', 'todas')::text$q$) like 'erro 42501%'
       -- o técnico lê o aprendido, mas não vê nada (a tabela e a config são fechadas para ele): nulo = o padrão
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select coalesce(public._agenda_aprendido('fator', 'teste:ag6:1')::text, 'nulo')$q$) = 'nulo'
       and pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated',
             $q$select count(*)::text from public.agenda_aprendizado where id = 'd6000000-0000-4000-8000-0000000000c1'$q$) = '1',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select public.agenda_medir_os('d6000000-0000-4000-8000-0000000000e3', date '2026-10-30')::text$q$);

-- ── B3. A coluna gerada critica com aprendizado ─────────────────────────────────────────────────────────
insert into _resultado
select 'B3a agenda_perguntas.critica: gerada (stored), com aprendizado e as 7 de antes, no mesmo lugar (antes de chave)',
       a.attgenerated = 's'
       and pg_get_expr(d.adbin, d.adrelid) like '%''aprendizado''%'
       and (select bool_and(pg_get_expr(d.adbin, d.adrelid) like '%''' || t || '''%')
              from unnest(array['nao_cabe', 'segundo_atraso', 'atraso_longo', 'remarcar_confirmado', 'fixada_pelo_dono', 'diaria',
                                'cliente_aviso']) t)
       and pg_get_expr(d.adbin, d.adrelid) !~ 'cliente_aprovar|cliente_resposta|''estouro''|''duracao'''
       and a.attnum < (select x.attnum from pg_attribute x where x.attrelid = a.attrelid and x.attname = 'chave'),
       format('attnum %s: %s', a.attnum, pg_get_expr(d.adbin, d.adrelid))
  from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica';

insert into _resultado
select 'B3b critica_tem_opcoes e critica_decidida continuam, lendo critica',
       count(*) = 2 and bool_and(pg_get_constraintdef(c.oid) like '%critica%'),
       string_agg(c.conname, ', ')
  from pg_constraint c
 where c.conrelid = 'public.agenda_perguntas'::regclass and c.conname in ('critica_tem_opcoes', 'critica_decidida');

do $b3$
declare
  v_res jsonb := '[]'::jsonb;
  r record;
  v_det text := '';
  v_ok boolean := true;
begin
  begin
    for r in select * from (values ('aprendizado', true), ('cliente_aviso', true), ('diaria', true), ('nao_cabe', true),
                                   ('estouro', false), ('duracao', false), ('cliente_resposta', false)) as t(tipo, critica)
    loop
      insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao)
      values (r.tipo, r.tipo || ':ag6', 'Pergunta de teste.', 'ligado',
              case when r.critica then '[{"n":1},{"n":2}]'::jsonb else '[]'::jsonb end, case when r.critica then 1 end);
      if (select p.critica from public.agenda_perguntas p where p.chave = r.tipo || ':ag6') is distinct from r.critica then
        v_ok := false;
        v_det := v_det || r.tipo || ' ';
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'B3c critica por tipo: aprendizado, cliente_aviso, diaria e nao_cabe sim; estouro, duracao e cliente_resposta não',
                        v_ok, nullif(v_det, ''));
    v_res := pg_temp.ok(v_res, 'B3d aprendizado sem opções é recusada (critica_tem_opcoes); respondida sem a opção também (critica_decidida)',
      pg_temp.recusa($q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('aprendizado', 'aprendizado:sem', 'Troca grande.', 'ligado')$q$)
        = 'critica_tem_opcoes'
      and pg_temp.recusa($q$update public.agenda_perguntas set estado = 'respondida', respondida_em = now() where chave = 'aprendizado:ag6'$q$)
        = 'critica_decidida');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b3$;

-- ── B4. Os registros não se apagam e só mudam o permitido ───────────────────────────────────────────────
do $b4$
declare
  v_res jsonb := '[]'::jsonb;
  c_os   constant uuid := 'd6000000-0000-4000-8000-0000000000e4';
  c_apr  constant uuid := 'd6000000-0000-4000-8000-0000000000c1';
  m public.agenda_medidas_os;
begin
  begin
    execute pg_temp.medida('{}');
    v_res := pg_temp.ok(v_res, 'B4a a medida não se apaga; o valor aprendido também não',
      pg_temp.recusa(format('delete from public.agenda_medidas_os where service_order_id = %L', c_os)) = 'erro P0001: O registro da agenda não se apaga.'
      and pg_temp.recusa(format('delete from public.agenda_aprendizado where id = %L', c_apr)) = 'erro P0001: O registro da agenda não se apaga.');
    v_res := pg_temp.ok(v_res, 'B4b a medida não muda sem versão + 1 e uma entrada nova no histórico',
      pg_temp.recusa(format('update public.agenda_medidas_os set motivo = ''sem_plano'' where service_order_id = %L', c_os))
        = 'erro P0001: A medida só muda inteira: versão + 1 e o que mudou no histórico.'
      and pg_temp.recusa(format('update public.agenda_medidas_os set motivo = ''sem_plano'', versao = versao + 1 where service_order_id = %L', c_os))
        = 'erro P0001: A medida só muda inteira: versão + 1 e o que mudou no histórico.'
      and pg_temp.recusa(format('update public.agenda_medidas_os set motivo = ''sem_plano'', versao = versao + 2, historico = ''[{"versao": 1}]'' where service_order_id = %L', c_os))
        = 'erro P0001: A medida só muda inteira: versão + 1 e o que mudou no histórico.');
    v_res := pg_temp.ok(v_res, 'B4c a medida não muda de OS',
      pg_temp.recusa(format('update public.agenda_medidas_os set service_order_id = %L, versao = versao + 1, historico = ''[{"versao": 1}]'' where service_order_id = %L',
                            'd6000000-0000-4000-8000-0000000000e3', c_os))
        = 'erro P0001: A medida é da OS: a OS não muda.');
    update public.agenda_medidas_os
       set motivo = 'sem_plano', versao = versao + 1,
           historico = '[{"em": "2026-10-30", "versao": 1, "antes": {"motivo": "sem_diaria"}, "depois": {"motivo": "sem_plano"}}]'
     where service_order_id = c_os;
    select * into m from public.agenda_medidas_os where service_order_id = c_os;
    v_res := pg_temp.ok(v_res, 'B4d com versão + 1 e o histórico a medida muda inteira',
      m.versao = 2 and m.motivo = 'sem_plano' and jsonb_array_length(m.historico) = 1, to_jsonb(m)::text);
    v_res := pg_temp.ok(v_res, 'B4e o valor aprendido não muda de item, de chave nem de nível',
      (select bool_and(pg_temp.recusa(format('update public.agenda_aprendizado set %s where id = %L', s, c_apr))
                       = 'erro P0001: O valor aprendido não muda de item, de chave nem de nível.')
         from unnest(array[$s$item = 'mo'$s$, $s$chave = 'teste:ag6:2'$s$, $s$nivel = 'todas'$s$,
                           $s$id = 'd6000000-0000-4000-8000-0000000000c9'$s$]) s));
    update public.agenda_aprendizado
       set calculado = 1.7, n = 7, estado = 'em_uso', em_uso = 1.7, texto = 'Teste.', em_uso_desde = now(),
           historico = '[{"em": "2026-10-30", "antes": {"estado": "medindo"}, "depois": {"estado": "em_uso"}}]'
     where id = c_apr;
    v_res := pg_temp.ok(v_res, 'B4f o resto do valor aprendido muda (o calculado, o n, o estado, o em uso, o texto, o histórico)',
      (select estado = 'em_uso' and em_uso = 1.7 and n = 7 from public.agenda_aprendizado where id = c_apr));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b4$;

-- ── B5. Os CHECKs de rotina e de ação ───────────────────────────────────────────────────────────────────
insert into _resultado
select format('B5 %s', k.nome), r = k.espera, r
  from (values
    ('ação aprendizado da vigia entra', $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto) values ('2026-10-30', true, 'vigia', 'aprendizado', 'Passei a usar 1,7×.')$q$, 'aceitou'),
    ('ação cliente continua entrando', $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto) values ('2026-10-30', true, 'cliente', 'cliente', 'Flávio confirmou.')$q$, 'aceitou'),
    ('ação de tipo que não existe', $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto) values ('2026-10-30', true, 'vigia', 'aprender', 'Aprendi.')$q$, 'agenda_acoes_tipo_check'),
    ('ação de origem que não existe (a origem continua a de antes)', $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto) values ('2026-10-30', true, 'aprendizado', 'aprendizado', 'Aprendi.')$q$, 'agenda_acoes_origem_check'),
    ('rodada aprender entra', $q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('aprender', '2026-10-30', now(), 'sombra', 'sombra')$q$, 'aceitou'),
    ('rodada cliente continua entrando', $q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('cliente', '2026-10-30', now(), 'sombra', 'sombra')$q$, 'aceitou'),
    ('rodada de rotina que não existe', $q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('aprendizado', '2026-10-30', now(), 'sombra', 'sombra')$q$, 'agenda_vigia_rodadas_rotina_check'),
    ('pergunta de tipo que não existe', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('aprender', 'aprender:x', 'Aprendo?', 'ligado')$q$, 'agenda_perguntas_tipo_check')
  ) as k(nome, sql, espera), lateral (select pg_temp.recusa(k.sql) as r) x;

-- ── B6. A correção C2 (20261029100950): os 4 parâmetros novos (item 12) ─────────────────────────────────────
-- As janelas do aprendizado que estavam escritas nas funções moram em agenda_config: NOT NULL, com o DEFAULT de antes, e cada
-- CHECK tem caso (abaixo e acima).
insert into _resultado
select 'B6a (C2, item 12) agenda_config: aprender_saude_dias 7, aprender_atraso_h 26, aprender_parar_dias 30 e aprender_respostas_dias 30, NOT NULL com DEFAULT',
       count(*) = 4 and bool_and(a.attnotnull and a.atthasdef)
       and (select format('%s %s %s %s', c.aprender_saude_dias, c.aprender_atraso_h, c.aprender_parar_dias, c.aprender_respostas_dias)
              from public.agenda_config c where c.id) = '7 26 30 30',
       string_agg(a.attname, ', ' order by a.attname)
  from pg_attribute a
 where a.attrelid = 'public.agenda_config'::regclass and not a.attisdropped
   and a.attname in ('aprender_saude_dias', 'aprender_atraso_h', 'aprender_parar_dias', 'aprender_respostas_dias');

create temp table _casos_c2 (nome text, sql text, espera text) on commit drop;
insert into _casos_c2 values
  ('saúde de 0 dias', $q$update public.agenda_config set aprender_saude_dias = 0$q$, 'agenda_config_aprender_saude_dias_check'),
  ('saúde de 31 dias', $q$update public.agenda_config set aprender_saude_dias = 31$q$, 'agenda_config_aprender_saude_dias_check'),
  ('rodada atrasada em 24 h', $q$update public.agenda_config set aprender_atraso_h = 24$q$, 'agenda_config_aprender_atraso_h_check'),
  ('rodada atrasada em 73 h', $q$update public.agenda_config set aprender_atraso_h = 73$q$, 'agenda_config_aprender_atraso_h_check'),
  ('métricas de 6 dias', $q$update public.agenda_config set aprender_parar_dias = 6$q$, 'agenda_config_aprender_parar_dias_check'),
  ('métricas de 91 dias', $q$update public.agenda_config set aprender_parar_dias = 91$q$, 'agenda_config_aprender_parar_dias_check'),
  ('respostas de 6 dias', $q$update public.agenda_config set aprender_respostas_dias = 6$q$, 'agenda_config_aprender_respostas_dias_check'),
  ('respostas de 91 dias', $q$update public.agenda_config set aprender_respostas_dias = 91$q$, 'agenda_config_aprender_respostas_dias_check');
insert into _resultado
select 'B6b (C2, item 12) ' || k.nome || ' é recusado por ' || k.espera, pg_temp.recusa(k.sql) = k.espera, pg_temp.recusa(k.sql)
  from _casos_c2 k;
insert into _resultado
select 'B6c (C2, item 12) os 4 CHECKs novos existem e cada um tem caso; os limites aceitam (1 e 30 dias; 25 e 72 h; 7 e 90 dias)',
       count(*) = 4 and bool_and(exists (select 1 from _casos_c2 x where x.espera = c.conname))
       and pg_temp.recusa($q$update public.agenda_config set aprender_saude_dias = 1, aprender_atraso_h = 25, aprender_parar_dias = 7, aprender_respostas_dias = 7$q$) = 'aceitou'
       and pg_temp.recusa($q$update public.agenda_config set aprender_saude_dias = 30, aprender_atraso_h = 72, aprender_parar_dias = 90, aprender_respostas_dias = 90$q$) = 'aceitou',
       string_agg(c.conname, ', ' order by c.conname)
  from pg_constraint c
 where c.conrelid = 'public.agenda_config'::regclass and c.contype = 'c'
   and c.conname in ('agenda_config_aprender_saude_dias_check', 'agenda_config_aprender_atraso_h_check',
                     'agenda_config_aprender_parar_dias_check', 'agenda_config_aprender_respostas_dias_check');
select teste, ok, detalhe from _resultado order by teste;

rollback;
