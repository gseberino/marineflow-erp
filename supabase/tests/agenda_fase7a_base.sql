-- Prova da base da Agenda de Produção, Fase 7a (pacote P1): os interruptores, as regras e os parâmetros do gestor da agenda, as
-- colunas novas (a fonte 'orcamento', a marca de dupla, o "compre até" gravado, o prazo da pergunta, a medida contra a estimativa),
-- as listas fechadas ampliadas, o diário do gestor e as funções da base (migration 20261031100000), e as duas fixtures da etapa
-- (o replay real de 29/10 e a sintética).
-- bancada: depende de 20261031100000
--
--   B1 colunas, DEFAULTs e CHECKs (os 56 da migration) (agenda_config, os_planejamento, agenda_alocacoes, os_material, agenda_perguntas,
--      agenda_medidas_os, agenda_gestor_dia); cada CHECK novo tem um caso que ele recusa; a regex inválida não entra
--   B2 RLS e privilégios (anon nada; o técnico não lê e não grava o diário; o ampliador e o gravador sem grant a ninguém; os
--      ajudantes STABLE com execute para authenticated; definer só o gravador; search_path fixo)
--   B3 as listas fechadas (as de antes iguais e na mesma ordem; as novas aceitas; critica com onda/dia_avisado/dia_prometido/
--      sabado e as 8 de antes iguais) e o ampliador (soma sem repetir, idempotente, nome errado e regra que não é lista recusados)
--   B4 _agenda_gestor_regra e _agenda_gestor_modo (desligado/sombra/ligado × a variável agenda.gestor × gestor_so_propor × a
--      lista); a lista das regras é a mesma no DEFAULT, no CHECK e no portão
--   B5 _agenda_dia_avisado (a ficha ligada enfileirada = equipe; o cliente ouviu = cliente; cliente vence equipe; nada = null)
--   B6 o gatilho da fonte da duração (o item criar da proposta; o planejamento; a reserva = null; o dito fica; senão sugerida)
--   B7 as fixtures: o replay de 29/10 monta a carteira real (as 11, as 45 linhas, as 19 de material, a equipe pela semente, as 12
--      reservas do Lenine, as 3 perguntas, a config de produção) e a sintética monta as 8 OS dela
--   B8 _agenda_perguntas_antes recriada: o prazo vai de nulo a um valor uma vez, na aberta; a opção padrão é uma das opções; a
--      cópia é o corpo de 20261026100000 fora dos blocos "-- FASE 7:"
--   B9 o diário do gestor: o gravador (as 4 chaves, o histórico, o tipo de cada chave, os modos) e o registro não se apaga; a
--      medida muda inteira também nas 3 colunas novas
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_base.sql
--   Seguro em produção: as linhas de teste ("TESTE AG7A") só são inseridas; termina em ROLLBACK. B5 a B8 usam as fixtures e só
--   rodam na bancada (fora dela saem PULADO).
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

-- O erro (sqlstate) de um comando, ou 'ok'.
create function pg_temp.estado(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate;
end $f$;

-- Os literais de uma lista fechada (o CHECK pelo nome), na ordem.
create function pg_temp.lista(p_tabela regclass, p_nome text) returns text[] language sql stable as $f$
  select array_agg(m[1] order by o)
    from pg_constraint c, regexp_matches(pg_get_constraintdef(c.oid), '''([^'']*)''', 'g') with ordinality t(m, o)
   where c.conrelid = p_tabela and c.conname = p_nome
$f$;

-- As linhas de teste (não dependem das fixtures: B1 a B4 e B9 rodam também em produção). A OS e a pessoa: um cliente, o bem, uma
-- OS aberta e um diarista ativo.
insert into public.clients (id, type, name) values ('d7a00000-0000-4000-8000-0000000000e1', 'individual', 'TESTE AG7A Cliente');
insert into public.vessels (id, client_id, name, asset_type)
values ('d7a00000-0000-4000-8000-0000000000e2', 'd7a00000-0000-4000-8000-0000000000e1', 'TESTE AG7A Motorhome', 'Motorhome');
insert into public.service_orders (id, service_order_number, client_id, vessel_id, status)
values ('d7a00000-0000-4000-8000-0000000000e3', 'OS-TESTE-AG7A', 'd7a00000-0000-4000-8000-0000000000e1',
        'd7a00000-0000-4000-8000-0000000000e2', 'open');
insert into public.payees (id, name, kind, active) values ('d7a00000-0000-4000-8000-0000000000e4', 'TESTE AG7A Pessoa', 'prestador', true);
insert into public.os_planejamento (service_order_id) values ('d7a00000-0000-4000-8000-0000000000e3');
insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria)
values ('d7a00000-0000-4000-8000-0000000000e5', 'd7a00000-0000-4000-8000-0000000000e3', 'dono', 'TESTE AG7A peça', 1);
insert into public.agenda_propostas (id, escopo, periodo, versao_base, modo, estado, itens, parametros, criada_por, expira_em)
values ('d7a00000-0000-4000-8000-0000000000e6', 'os', daterange('2026-11-03', '2026-11-07'), 0, 'sombra', 'aberta',
        '[{"op": "criar", "os": "d7a00000-0000-4000-8000-0000000000e3", "fonte": "orcamento"}]',
        '{"p_hoje": "2026-10-29"}', 'motor', now() + interval '1 day');

create temp table _base (nome text primary key, sql text) on commit drop;
insert into _base values
  ('aloc', $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, proposta_id%s) values ('d7a00000-0000-4000-8000-0000000000e3', 'd7a00000-0000-4000-8000-0000000000e4', '2026-11-03', 'manha', 'proposta', 'd7a00000-0000-4000-8000-0000000000e6'%s)$q$),
  ('perg', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo%s) values ('situacao', 'situacao:teste-ag7a', 'Pergunta de teste.', 'ligado'%s)$q$),
  ('medida', $q$insert into public.agenda_medidas_os (service_order_id, classe_bem, classe_sistema, concluida_em, medida_em%s) values ('d7a00000-0000-4000-8000-0000000000e3', 'rv', 'energia', '2026-10-29', '2026-10-29 16:05-03'%s)$q$),
  ('dia', $q$insert into public.agenda_gestor_dia (dia, calculado_em, modos%s) values ('2026-10-29', '2026-10-29 16:52-03', '{}'%s)$q$);
-- O INSERT de teste de p_nome com as colunas e os valores a mais.
create function pg_temp.mais(p_nome text, p_cols text, p_vals text) returns text language sql stable as $f$
  select format((select sql from _base where nome = p_nome), coalesce(', ' || p_cols, ''), coalesce(', ' || p_vals, ''))
$f$;

-- ── B1. Colunas, DEFAULTs e CHECKs ──────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B1a agenda_config: os 5 interruptores nascem desligados na linha e o DEFAULT da coluna é sombra; as 15 regras; os parâmetros com o valor da spec e das respostas do dono (§4.1, AG7-06 7, AG7-07 1 e 7, veto às 18:00)',
       c.modo_marcar_sozinho = 'desligado' and c.modo_vaga_fechamento = 'desligado' and c.modo_encaixe_aprovacao = 'desligado'
       and c.modo_revisao_diaria = 'desligado' and c.modo_compre_ate = 'desligado'
       and (select bool_and(pg_get_expr(d.adbin, d.adrelid) like '''sombra''%')
              from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = 'public.agenda_config'::regclass
               and a.attname in ('modo_marcar_sozinho', 'modo_vaga_fechamento', 'modo_encaixe_aprovacao', 'modo_revisao_diaria',
                                 'modo_compre_ate'))
       and c.marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
       and not c.gestor_so_propor and c.gestor_so_propor_em is null and c.marcar_sozinho_desde is null
       and c.fechamento_vagas_agenda = 1 and c.estimativa_max_diarias = 8.0
       and c.mo_fora_regex = '\m(deslocamento|viagem|translado|visita tecnica|km rodado|frete)\M'
       and c.diagnostico_dias = 0.5 and c.sem_mo_dias = 1.0 and c.equipe_padrao = 1 and c.equipe_sugerida = 2
       and (select array_agg(e ->> 0 || ':' || (e ->> 2) || ':' || (e ->> 3) order by o)
              from jsonb_array_elements(c.dupla_gatilhos) with ordinality t(e, o))
           = '{banco_cc:inicio:2,bateria_pesada:inicio:2,ca_energizado:fim:2,icamento:inicio:2}'
       and strpos(c.dupla_gatilhos -> 2 ->> 1, 'sistema eletrico (ac|ca)\M|') > 0 and c.dupla_notas -> 0 ->> 0 = 'confinado'
       and c.situacao_dias = 30 and c.quanto_falta_dias = 1.0 and c.veto_du = 1 and c.veto_hora = time '18:00'
       and c.ficha_veto_dias = 21 and c.critico_valor_min = 300 and c.prazo_sem_fornecedor_du = 7 and c.compra_interna_du = 1
       and c.compra_urgente_du = 7 and c.gestor_hora_revisao = time '16:45' and c.gestor_tempo_max = interval '45 seconds'
       and c.aprovada_sem_data_min = 30 and c.gestor_k_os = 2 and c.gestor_k_dias_avisados = 1 and c.compre_ate_empurroes_max = 2
       and c.compras_aviso_du = 2 and c.sabado_manha = 'so_prazo' and c.simular_orcamento_acima = 20000
       and c.simular_orcamento_dias = 30,
       (to_jsonb(c) - 'dupla_gatilhos' - 'dupla_notas')::text
  from public.agenda_config c;

insert into _resultado
select 'B1b agenda_config: as 36 colunas novas — 34 NOT NULL com DEFAULT; gestor_so_propor_em e marcar_sozinho_desde nulas, sem DEFAULT',
       count(*) = 36
       and count(*) filter (where a.attnotnull and a.atthasdef) = 34
       and bool_and(not a.attnotnull and not a.atthasdef) filter (where a.attname in ('gestor_so_propor_em', 'marcar_sozinho_desde')),
       count(*)::text || ' colunas; sem NOT NULL/DEFAULT: '
         || coalesce(string_agg(a.attname, ', ') filter (where not (a.attnotnull and a.atthasdef)), '—')
  from pg_attribute a
 where a.attrelid = 'public.agenda_config'::regclass and not a.attisdropped
   and a.attname in ('modo_marcar_sozinho', 'marcar_regras', 'gestor_so_propor', 'gestor_so_propor_em', 'marcar_sozinho_desde',
                     'modo_vaga_fechamento', 'fechamento_vagas_agenda', 'estimativa_max_diarias', 'mo_fora_regex',
                     'diagnostico_dias', 'sem_mo_dias', 'equipe_padrao', 'dupla_gatilhos', 'dupla_notas', 'situacao_dias',
                     'quanto_falta_dias', 'veto_du', 'veto_hora', 'ficha_veto_dias', 'critico_valor_min', 'prazo_sem_fornecedor_du',
                     'compra_interna_du', 'compra_urgente_du', 'gestor_hora_revisao', 'gestor_tempo_max', 'aprovada_sem_data_min',
                     'modo_encaixe_aprovacao', 'modo_revisao_diaria', 'modo_compre_ate', 'gestor_k_os', 'gestor_k_dias_avisados',
                     'compre_ate_empurroes_max', 'compras_aviso_du', 'sabado_manha', 'simular_orcamento_acima',
                     'simular_orcamento_dias');

insert into _resultado
select 'B1c as colunas novas das outras tabelas, com o tipo da spec (cobrado_vezes e empurrada_vezes NOT NULL default 0; o resto nulo)',
       string_agg(c.relname || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod)
                  || case when a.attnotnull then '!' else '' end, ',' order by c.relname, a.attname)
       = 'agenda_alocacoes.duracao_fonte:text,'
         'agenda_medidas_os.dp_no_inicio:numeric(5,2),agenda_medidas_os.dp_reais:numeric(6,2),agenda_medidas_os.fator_orcamento:numeric(4,2),'
         'agenda_perguntas.opcao_padrao:smallint,agenda_perguntas.veto_ate:timestamp with time zone,'
         'os_material.cobrado_em:timestamp with time zone,os_material.cobrado_vezes:smallint!,os_material.compre_ate:date,'
         'os_material.compre_ate_base:jsonb,os_material.compre_ate_em:timestamp with time zone,'
         'os_material.defeito_em:timestamp with time zone,os_material.empurrada_vezes:smallint!,'
         'os_planejamento.dp_no_inicio:numeric(5,2),os_planejamento.dupla_dita:text,'
         'os_planejamento.dupla_em:timestamp with time zone,os_planejamento.dupla_meios:smallint,os_planejamento.dupla_motivo:text',
       string_agg(c.relname || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod)
                  || case when a.attnotnull then '!' else '' end, ',' order by c.relname, a.attname)
  from pg_attribute a join pg_class c on c.oid = a.attrelid
 where not a.attisdropped
   and ((c.oid = 'public.os_planejamento'::regclass and a.attname in ('dupla_dita', 'dupla_meios', 'dupla_motivo', 'dupla_em', 'dp_no_inicio'))
     or (c.oid = 'public.agenda_alocacoes'::regclass and a.attname = 'duracao_fonte')
     or (c.oid = 'public.os_material'::regclass and a.attname in ('compre_ate', 'compre_ate_base', 'compre_ate_em', 'cobrado_em',
                                                                  'cobrado_vezes', 'empurrada_vezes', 'defeito_em'))
     or (c.oid = 'public.agenda_perguntas'::regclass and a.attname in ('veto_ate', 'opcao_padrao'))
     or (c.oid = 'public.agenda_medidas_os'::regclass and a.attname in ('fator_orcamento', 'dp_no_inicio', 'dp_reais')));

create temp table _casos (grupo text, nome text, sql text, espera text) on commit drop;
insert into _casos values
  -- agenda_config (os 33 CHECKs)
  ('config', 'modo_marcar_sozinho x', $q$update public.agenda_config set modo_marcar_sozinho = 'x'$q$, 'agenda_config_modo_marcar_sozinho_check'),
  ('config', 'modo_vaga_fechamento x', $q$update public.agenda_config set modo_vaga_fechamento = 'x'$q$, 'agenda_config_modo_vaga_fechamento_check'),
  ('config', 'modo_encaixe_aprovacao x', $q$update public.agenda_config set modo_encaixe_aprovacao = 'x'$q$, 'agenda_config_modo_encaixe_aprovacao_check'),
  ('config', 'modo_revisao_diaria x', $q$update public.agenda_config set modo_revisao_diaria = 'x'$q$, 'agenda_config_modo_revisao_diaria_check'),
  ('config', 'modo_compre_ate x', $q$update public.agenda_config set modo_compre_ate = 'x'$q$, 'agenda_config_modo_compre_ate_check'),
  ('config', 'regra que não existe (a sinal_reserva saiu: AG7-09)', $q$update public.agenda_config set marcar_regras = '{estimativa,sinal_reserva}'$q$, 'agenda_config_marcar_regras_check'),
  ('config', '3 vagas no fechamento', $q$update public.agenda_config set fechamento_vagas_agenda = 3$q$, 'agenda_config_fechamento_vagas_agenda_check'),
  ('config', 'teto da estimativa 1,5 diária', $q$update public.agenda_config set estimativa_max_diarias = 1.5$q$, 'agenda_config_estimativa_max_diarias_check'),
  ('config', 'teto da estimativa 30,5 diárias', $q$update public.agenda_config set estimativa_max_diarias = 30.5$q$, 'agenda_config_estimativa_max_diarias_check'),
  ('config', 'regex da mão de obra com 2 letras', $q$update public.agenda_config set mo_fora_regex = 'ab'$q$, 'agenda_config_mo_fora_regex_check'),
  ('config', 'regex da mão de obra que não compila', $q$update public.agenda_config set mo_fora_regex = '\m(deslocamento|viagem'$q$, 'agenda_config_mo_fora_regex_check'),
  ('config', 'gatilhos de dupla: lista vazia', $q$update public.agenda_config set dupla_gatilhos = '[]'$q$, 'agenda_config_dupla_gatilhos_check'),
  ('config', 'gatilhos de dupla: motivo fora da lista', $q$update public.agenda_config set dupla_gatilhos = '[["solda","solda","inicio",2]]'$q$, 'agenda_config_dupla_gatilhos_check'),
  ('config', 'gatilhos de dupla: motivo repetido', $q$update public.agenda_config set dupla_gatilhos = '[["banco_cc","litio","inicio",2],["banco_cc","agm","inicio",2]]'$q$, 'agenda_config_dupla_gatilhos_check'),
  ('config', 'gatilhos de dupla: onde fora da lista', $q$update public.agenda_config set dupla_gatilhos = '[["banco_cc","litio","meio",2]]'$q$, 'agenda_config_dupla_gatilhos_check'),
  ('config', 'gatilhos de dupla: 9 meios-dias', $q$update public.agenda_config set dupla_gatilhos = '[["banco_cc","litio","inicio",9]]'$q$, 'agenda_config_dupla_gatilhos_check'),
  ('config', 'gatilhos de dupla: regex que não compila', $q$update public.agenda_config set dupla_gatilhos = '[["banco_cc","litio(","inicio",2]]'$q$, 'agenda_config_dupla_gatilhos_check'),
  ('config', 'gatilhos de dupla: sem os meios-dias', $q$update public.agenda_config set dupla_gatilhos = '[["banco_cc","litio","inicio"]]'$q$, 'agenda_config_dupla_gatilhos_check'),
  ('config', 'notas de dupla: regex que não compila', $q$update public.agenda_config set dupla_notas = '[["confinado","paiol("]]'$q$, 'agenda_config_dupla_notas_check'),
  ('config', 'notas de dupla: motivo vazio', $q$update public.agenda_config set dupla_notas = '[["","paiol"]]'$q$, 'agenda_config_dupla_notas_check'),
  ('config', 'notas de dupla: objeto, não lista', $q$update public.agenda_config set dupla_notas = '{"confinado": "paiol"}'$q$, 'agenda_config_dupla_notas_check'),
  ('config', 'diagnóstico de 0,3 dia (fora do meio dia)', $q$update public.agenda_config set diagnostico_dias = 0.3$q$, 'agenda_config_diagnostico_dias_check'),
  ('config', 'diagnóstico de 2,5 dias', $q$update public.agenda_config set diagnostico_dias = 2.5$q$, 'agenda_config_diagnostico_dias_check'),
  ('config', 'sem mão de obra 5,5 dias', $q$update public.agenda_config set sem_mo_dias = 5.5$q$, 'agenda_config_sem_mo_dias_check'),
  ('config', 'sem mão de obra 0,7 dia', $q$update public.agenda_config set sem_mo_dias = 0.7$q$, 'agenda_config_sem_mo_dias_check'),
  ('config', 'equipe padrão 0', $q$update public.agenda_config set equipe_padrao = 0$q$, 'agenda_config_equipe_padrao_check'),
  ('config', 'equipe padrão 4', $q$update public.agenda_config set equipe_padrao = 4$q$, 'agenda_config_equipe_padrao_check'),
  ('config', 'parada há 6 dias', $q$update public.agenda_config set situacao_dias = 6$q$, 'agenda_config_situacao_dias_check'),
  ('config', 'quanto falta 0,7 dia', $q$update public.agenda_config set quanto_falta_dias = 0.7$q$, 'agenda_config_quanto_falta_dias_check'),
  ('config', 'prazo de 4 dias úteis', $q$update public.agenda_config set veto_du = 4$q$, 'agenda_config_veto_du_check'),
  ('config', 'prazo às 07:59 (antes da janela)', $q$update public.agenda_config set veto_hora = '07:59'$q$, 'agenda_config_veto_hora_check'),
  ('config', 'prazo na hora da ficha (19:30)', $q$update public.agenda_config set veto_hora = equipe_hora_ficha$q$, 'agenda_config_veto_hora_check'),
  ('config', 'janela da ficha de 61 dias', $q$update public.agenda_config set ficha_veto_dias = 61$q$, 'agenda_config_ficha_veto_dias_check'),
  ('config', 'item crítico a partir de R$ 5.001', $q$update public.agenda_config set critico_valor_min = 5001$q$, 'agenda_config_critico_valor_min_check'),
  ('config', 'item crítico a partir de −R$ 1', $q$update public.agenda_config set critico_valor_min = -1$q$, 'agenda_config_critico_valor_min_check'),
  ('config', 'prazo sem fornecedor 0', $q$update public.agenda_config set prazo_sem_fornecedor_du = 0$q$, 'agenda_config_prazo_sem_fornecedor_du_check'),
  ('config', 'prazo sem fornecedor 21', $q$update public.agenda_config set prazo_sem_fornecedor_du = 21$q$, 'agenda_config_prazo_sem_fornecedor_du_check'),
  ('config', 'compra interna 11 dias úteis', $q$update public.agenda_config set compra_interna_du = 11$q$, 'agenda_config_compra_interna_du_check'),
  ('config', 'compra urgente 21 dias úteis', $q$update public.agenda_config set compra_urgente_du = 21$q$, 'agenda_config_compra_urgente_du_check'),
  ('config', 'revisão na hora do plano (16:30)', $q$update public.agenda_config set gestor_hora_revisao = hora_do_plano$q$, 'agenda_config_revisao_depois_do_plano_check'),
  ('config', 'revisão depois da janela (19:01)', $q$update public.agenda_config set gestor_hora_revisao = '19:01'$q$, 'agenda_config_gestor_hora_revisao_check'),
  ('config', 'rodada de 9 segundos', $q$update public.agenda_config set gestor_tempo_max = '9 seconds'$q$, 'agenda_config_gestor_tempo_max_check'),
  ('config', 'rodada de 121 segundos', $q$update public.agenda_config set gestor_tempo_max = '121 seconds'$q$, 'agenda_config_gestor_tempo_max_check'),
  ('config', 'aprovada sem data 14 min', $q$update public.agenda_config set aprovada_sem_data_min = 14$q$, 'agenda_config_aprovada_sem_data_min_check'),
  ('config', 'onda com 0 OS', $q$update public.agenda_config set gestor_k_os = 0$q$, 'agenda_config_gestor_k_os_check'),
  ('config', 'onda com 11 dias avisados', $q$update public.agenda_config set gestor_k_dias_avisados = 11$q$, 'agenda_config_gestor_k_dias_avisados_check'),
  ('config', '0 empurrões', $q$update public.agenda_config set compre_ate_empurroes_max = 0$q$, 'agenda_config_compre_ate_empurroes_max_check'),
  ('config', 'compras a 6 dias úteis', $q$update public.agenda_config set compras_aviso_du = 6$q$, 'agenda_config_compras_aviso_du_check'),
  ('config', 'sábado sempre', $q$update public.agenda_config set sabado_manha = 'sempre'$q$, 'agenda_config_sabado_manha_check'),
  ('config', 'orçamento a partir de −R$ 1', $q$update public.agenda_config set simular_orcamento_acima = -1$q$, 'agenda_config_simular_orcamento_acima_check'),
  ('config', 'orçamentos de 6 dias', $q$update public.agenda_config set simular_orcamento_dias = 6$q$, 'agenda_config_simular_orcamento_dias_check'),
  ('config', 'os limites que entram (os 5 ligados, a lista vazia, os extremos de cada parâmetro, a regex de antes de 1 linha)',
   $q$update public.agenda_config set modo_marcar_sozinho = 'ligado', modo_vaga_fechamento = 'ligado',
        modo_encaixe_aprovacao = 'ligado', modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado', marcar_regras = '{}',
        gestor_so_propor = true, gestor_so_propor_em = now(), marcar_sozinho_desde = now(),
        fechamento_vagas_agenda = 2, estimativa_max_diarias = 30, mo_fora_regex = 'frete', diagnostico_dias = 2, sem_mo_dias = 0.5,
        equipe_padrao = 3, dupla_gatilhos = '[["icamento","guindaste","fim",8]]', dupla_notas = '[]', situacao_dias = 120,
        quanto_falta_dias = 5, veto_du = 0, veto_hora = cliente_janela_inicio, ficha_veto_dias = 0, critico_valor_min = 0,
        prazo_sem_fornecedor_du = 20, compra_interna_du = 0, compra_urgente_du = 0, gestor_hora_revisao = cliente_janela_fim,
        gestor_tempo_max = '120 seconds', aprovada_sem_data_min = 240, gestor_k_os = 10, gestor_k_dias_avisados = 0,
        compre_ate_empurroes_max = 5, compras_aviso_du = 0, sabado_manha = 'nunca', simular_orcamento_acima = 0,
        simular_orcamento_dias = 120$q$, 'aceitou'),
  -- os_planejamento (a OS de teste)
  ('planejamento', 'dupla "meio" fora da lista', $q$update public.os_planejamento set dupla_dita = 'meio' where service_order_id = 'd7a00000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_dupla_dita_check'),
  ('planejamento', 'dupla em 21 meios-dias', $q$update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 21 where service_order_id = 'd7a00000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_dupla_meios_check'),
  ('planejamento', 'motivo da dupla com 81 letras', $q$update public.os_planejamento set dupla_motivo = repeat('x', 81) where service_order_id = 'd7a00000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_dupla_motivo_check'),
  ('planejamento', 'dupla no início sem os meios-dias', $q$update public.os_planejamento set dupla_dita = 'inicio' where service_order_id = 'd7a00000-0000-4000-8000-0000000000e3'$q$, 'dupla_meios_coerente'),
  ('planejamento', 'dupla a OS inteira com meios-dias', $q$update public.os_planejamento set dupla_dita = 'todos', dupla_meios = 2 where service_order_id = 'd7a00000-0000-4000-8000-0000000000e3'$q$, 'dupla_meios_coerente'),
  ('planejamento', 'meios-dias sem a marca (a regra)', $q$update public.os_planejamento set dupla_meios = 2 where service_order_id = 'd7a00000-0000-4000-8000-0000000000e3'$q$, 'dupla_meios_coerente'),
  ('planejamento', 'fonte da estimativa "chute"', $q$update public.os_planejamento set dias = 2, estimativa_fonte = 'chute' where service_order_id = 'd7a00000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_estimativa_fonte_check'),
  ('planejamento', 'fonte dos dias no início "chute"', $q$update public.os_planejamento set dias_no_inicio = 2, dias_no_inicio_fonte = 'chute', dias_no_inicio_em = '2026-10-29' where service_order_id = 'd7a00000-0000-4000-8000-0000000000e3'$q$, 'os_planejamento_dias_no_inicio_fonte_check'),
  ('planejamento', 'a estimativa do orçamento gravada (fonte orcamento, nos dias e no início), dupla nos 2 primeiros meios-dias',
   $q$update public.os_planejamento set dias = 6, estimativa_fonte = 'orcamento', estimativa_em = now(), dias_no_inicio = 6, dias_no_inicio_fonte = 'orcamento', dias_no_inicio_em = '2026-10-29', dp_no_inicio = 5.97, dupla_dita = 'inicio', dupla_meios = 2, dupla_motivo = 'banco de baterias', dupla_em = now() where service_order_id = 'd7a00000-0000-4000-8000-0000000000e3'$q$, 'aceitou'),
  -- agenda_alocacoes (o meio-dia proposto da OS de teste)
  ('alocacao', 'fonte da duração "chute"', pg_temp.mais('aloc', 'duracao_fonte', $v$'chute'$v$), 'agenda_alocacoes_duracao_fonte_check'),
  ('alocacao', 'cancelada por um motivo que não existe', $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, cancelada_motivo) values ('d7a00000-0000-4000-8000-0000000000e3', 'd7a00000-0000-4000-8000-0000000000e4', '2026-11-03', 'manha', 'cancelada', 'preguica')$q$, 'agenda_alocacoes_cancelada_motivo_check'),
  ('alocacao', 'cancelada porque a estimativa mudou (reestimada) entra',
   $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, cancelada_motivo) values ('d7a00000-0000-4000-8000-0000000000e3', 'd7a00000-0000-4000-8000-0000000000e4', '2026-11-03', 'manha', 'cancelada', 'reestimada')$q$, 'aceitou'),
  ('alocacao', 'a fonte orcamento entra', pg_temp.mais('aloc', 'duracao_fonte', $v$'orcamento'$v$), 'aceitou'),
  -- os_material (a linha de teste)
  ('material', 'compre até sem a conta', $q$update public.os_material set compre_ate = '2026-10-29' where id = 'd7a00000-0000-4000-8000-0000000000e5'$q$, 'compre_ate_coerente'),
  ('material', 'a conta sem o compre até', $q$update public.os_material set compre_ate_base = '{"prazo": 7}' where id = 'd7a00000-0000-4000-8000-0000000000e5'$q$, 'compre_ate_coerente'),
  ('material', 'a conta que não é objeto', $q$update public.os_material set compre_ate = '2026-10-29', compre_ate_base = '[7]' where id = 'd7a00000-0000-4000-8000-0000000000e5'$q$, 'os_material_compre_ate_base_check'),
  ('material', 'cobrado 51 vezes', $q$update public.os_material set cobrado_vezes = 51 where id = 'd7a00000-0000-4000-8000-0000000000e5'$q$, 'os_material_cobrado_vezes_check'),
  ('material', 'empurrada 21 vezes', $q$update public.os_material set empurrada_vezes = 21 where id = 'd7a00000-0000-4000-8000-0000000000e5'$q$, 'os_material_empurrada_vezes_check'),
  ('material', 'empurrada −1 vez', $q$update public.os_material set empurrada_vezes = -1 where id = 'd7a00000-0000-4000-8000-0000000000e5'$q$, 'os_material_empurrada_vezes_check'),
  ('material', 'o compre até gravado, cobrado, empurrado e o defeito',
   $q$update public.os_material set compre_ate = '2026-10-29', compre_ate_base = '{"primeiro": "2026-11-10", "folga": 1, "prazo": 7, "prazo_fonte": "padrao", "interno": 1}', compre_ate_em = now(), cobrado_em = now(), cobrado_vezes = 2, empurrada_vezes = 1, defeito_em = now() where id = 'd7a00000-0000-4000-8000-0000000000e5'$q$, 'aceitou'),
  -- agenda_perguntas
  ('pergunta', 'opção padrão sem o prazo', pg_temp.mais('perg', 'opcoes, recomendacao, opcao_padrao', $v$'[{"n":1},{"n":2}]', 1, 1$v$), 'veto_padrao_tem_prazo'),
  ('pergunta', 'prazo em pergunta crítica (a onda)', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao, veto_ate) values ('onda', 'onda:teste-ag7a', 'Pergunta de teste.', 'ligado', '[{"n":1},{"n":2},{"n":3}]', 1, now() + interval '1 day')$q$, 'veto_nao_critica'),
  ('pergunta', 'tipo que não existe ("equipe": é equipe_cadastro)', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('equipe', 'equipe:teste-ag7a', 'Pergunta de teste.', 'ligado')$q$, 'agenda_perguntas_tipo_check'),
  ('pergunta', 'a pergunta do gestor com o prazo e a opção padrão', pg_temp.mais('perg', 'opcoes, recomendacao, veto_ate, opcao_padrao', $v$'[{"n":1},{"n":2},{"n":3}]', 1, now() + interval '1 day', 1$v$), 'aceitou'),
  ('pergunta', 'prazo sem opção padrão (a chamada do 7b, a proposta do 7c)', pg_temp.mais('perg', 'veto_ate', $v$now() + interval '1 day'$v$), 'aceitou'),
  -- agenda_medidas_os
  ('medida', 'fator da estimativa numa medida do dono', pg_temp.mais('medida', 'valida, motivo, dias_no_inicio, dias_fonte, fator_orcamento', $v$true, null, 2, 'dono', 1.25$v$), 'fator_orcamento_so_orcamento'),
  ('medida', 'fator da estimativa numa medida que não vale', pg_temp.mais('medida', 'valida, motivo, dias_no_inicio, dias_fonte, fator_orcamento', $v$false, 'sem_diaria', 2, 'orcamento', 1.25$v$), 'fator_orcamento_so_orcamento'),
  ('medida', 'a medida contra a estimativa (fonte orcamento, o fator dela à parte, as diárias)', pg_temp.mais('medida', 'valida, motivo, dias_no_inicio, dias_fonte, fator_orcamento, dp_no_inicio, dp_reais', $v$true, null, 6, 'orcamento', 1.17, 5.97, 7.00$v$), 'aceitou'),
  -- agenda_gestor_dia
  ('diario', 'modos que não são objeto', $q$insert into public.agenda_gestor_dia (dia, calculado_em, modos) values ('2026-10-29', now(), '[]')$q$, 'agenda_gestor_dia_modos_check'),
  ('diario', 'sombra que não é objeto', pg_temp.mais('dia', 'sombra', $v$'[]'$v$), 'agenda_gestor_dia_sombra_check'),
  ('diario', 'orçamentos que não são lista', pg_temp.mais('dia', 'orcamentos', $v$'{}'$v$), 'agenda_gestor_dia_orcamentos_check'),
  ('diario', 'compras que não são lista', pg_temp.mais('dia', 'compras', $v$'{}'$v$), 'agenda_gestor_dia_compras_check'),
  ('diario', 'linha do fechamento com 641 letras', pg_temp.mais('dia', 'texto_sombra', $v$repeat('x', 641)$v$), 'agenda_gestor_dia_texto_sombra_check'),
  ('diario', 'histórico de 21', pg_temp.mais('dia', 'historico', $v$(select jsonb_agg(g) from generate_series(1, 21) g)$v$), 'agenda_gestor_dia_historico_check'),
  ('diario', 'o mesmo dia duas vezes', $q$insert into public.agenda_gestor_dia (dia, calculado_em, modos) values ('2026-10-28', now(), '{}'), ('2026-10-28', now(), '{}')$q$, 'agenda_gestor_dia_pkey'),
  ('diario', 'o dia com tudo', pg_temp.mais('dia', 'sombra, orcamentos, compras, texto_sombra', $v$'{"itens": []}', '[]', '[]', repeat('x', 640)$v$), 'aceitou');

insert into _resultado
select format('B1 %s: %s', k.grupo, k.nome), r = k.espera, r
  from _casos k, lateral (select pg_temp.recusa(k.sql) as r) x;

-- Todos os CHECKs desta migration: existem e cada um tem caso (um CHECK novo sem prova reprova aqui).
create temp table _checks_f7a (tabela regclass, nome text, primary key (tabela, nome)) on commit drop;
insert into _checks_f7a
select 'public.agenda_config'::regclass, 'agenda_config_' || n || '_check'
  from unnest(array['modo_marcar_sozinho', 'modo_vaga_fechamento', 'modo_encaixe_aprovacao', 'modo_revisao_diaria',
                    'modo_compre_ate', 'marcar_regras', 'fechamento_vagas_agenda', 'estimativa_max_diarias', 'mo_fora_regex',
                    'dupla_gatilhos', 'dupla_notas', 'diagnostico_dias', 'sem_mo_dias', 'equipe_padrao', 'situacao_dias',
                    'quanto_falta_dias', 'veto_du', 'veto_hora', 'ficha_veto_dias', 'critico_valor_min', 'prazo_sem_fornecedor_du',
                    'compra_interna_du', 'compra_urgente_du', 'gestor_hora_revisao', 'gestor_tempo_max', 'aprovada_sem_data_min',
                    'gestor_k_os', 'gestor_k_dias_avisados', 'compre_ate_empurroes_max', 'compras_aviso_du', 'sabado_manha',
                    'simular_orcamento_acima', 'simular_orcamento_dias', 'revisao_depois_do_plano']) n
union all
select t::regclass, n from (values
  ('public.os_planejamento', 'os_planejamento_dupla_dita_check'), ('public.os_planejamento', 'os_planejamento_dupla_meios_check'),
  ('public.os_planejamento', 'os_planejamento_dupla_motivo_check'), ('public.os_planejamento', 'dupla_meios_coerente'),
  ('public.os_planejamento', 'os_planejamento_estimativa_fonte_check'),
  ('public.os_planejamento', 'os_planejamento_dias_no_inicio_fonte_check'),
  ('public.agenda_alocacoes', 'agenda_alocacoes_duracao_fonte_check'),
  ('public.agenda_alocacoes', 'agenda_alocacoes_cancelada_motivo_check'),
  ('public.os_material', 'compre_ate_coerente'), ('public.os_material', 'os_material_compre_ate_base_check'),
  ('public.os_material', 'os_material_cobrado_vezes_check'), ('public.os_material', 'os_material_empurrada_vezes_check'),
  ('public.agenda_perguntas', 'veto_padrao_tem_prazo'), ('public.agenda_perguntas', 'veto_nao_critica'),
  ('public.agenda_perguntas', 'agenda_perguntas_tipo_check'),
  ('public.agenda_medidas_os', 'fator_orcamento_so_orcamento'),
  ('public.agenda_gestor_dia', 'agenda_gestor_dia_modos_check'), ('public.agenda_gestor_dia', 'agenda_gestor_dia_sombra_check'),
  ('public.agenda_gestor_dia', 'agenda_gestor_dia_orcamentos_check'), ('public.agenda_gestor_dia', 'agenda_gestor_dia_compras_check'),
  ('public.agenda_gestor_dia', 'agenda_gestor_dia_texto_sombra_check'),
  ('public.agenda_gestor_dia', 'agenda_gestor_dia_historico_check')) as x(t, n);

insert into _resultado
select 'B1z os 56 CHECKs desta migration existem e todos têm caso (nenhum ficou sem prova)',
       count(*) = 56 and bool_and(exists (select 1 from pg_constraint c where c.conrelid = k.tabela and c.conname = k.nome
                                                                       and c.contype = 'c'))
       and bool_and(exists (select 1 from _casos x where x.espera = k.nome)),
       format('%s; sem constraint: %s; sem caso: %s', count(*),
              coalesce(string_agg(k.nome, ', ') filter (where not exists (select 1 from pg_constraint c
                         where c.conrelid = k.tabela and c.conname = k.nome)), '—'),
              coalesce(string_agg(k.nome, ', ') filter (where not exists (select 1 from _casos x where x.espera = k.nome)), '—'))
  from _checks_f7a k;

insert into _resultado
select 'B1y agenda_gestor_dia: todo CHECK da tabela está na lista do B1z (nenhum a mais sem caso)',
       coalesce(bool_and(exists (select 1 from _checks_f7a k where k.nome = c.conname)), false),
       string_agg(c.conname, ', ')
  from pg_constraint c where c.conrelid = 'public.agenda_gestor_dia'::regclass and c.contype = 'c';

-- ── B2. RLS e privilégios ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B2a agenda_gestor_dia: RLS ligada e uma policy só, de leitura, TO authenticated; o registro não se apaga (gatilho)',
       c.relrowsecurity
       and (select count(*) from pg_policy p where p.polrelid = c.oid) = 1
       and (select bool_and(p.polcmd = 'r' and p.polroles = array[(select oid from pg_roles where rolname = 'authenticated')])
              from pg_policy p where p.polrelid = c.oid)
       and exists (select 1 from pg_trigger t where t.tgrelid = c.oid and t.tgname = 'agenda_gestor_dia_nao_apaga'
                                              and t.tgfoid = 'public._agenda_registro_nao_apaga()'::regprocedure),
       null
  from pg_class c where c.oid = 'public.agenda_gestor_dia'::regclass;

insert into _resultado
select 'B2b agenda_gestor_dia: anon sem privilégio nenhum; authenticated só lê; service_role escreve',
       not has_table_privilege('anon', t, 'select') and not has_table_privilege('anon', t, 'insert')
       and not has_table_privilege('anon', t, 'update') and not has_table_privilege('anon', t, 'delete')
       and has_table_privilege('authenticated', t, 'select') and not has_table_privilege('authenticated', t, 'insert')
       and not has_table_privilege('authenticated', t, 'update') and not has_table_privilege('authenticated', t, 'delete')
       and has_table_privilege('service_role', t, 'insert') and has_table_privilege('service_role', t, 'update'),
       null
  from (select 'public.agenda_gestor_dia' as t) x;

create temp table _funcoes_f7a (f text primary key, quem text) on commit drop;
insert into _funcoes_f7a values
  ('public._agenda_regex_valido(text)', 'leitura'),
  ('public._agenda_dupla_lista_ok(jsonb, boolean)', 'leitura'),
  ('public._agenda_gestor_regra(text)', 'leitura'),
  ('public._agenda_gestor_modo(text)', 'leitura'),
  ('public._agenda_dia_avisado(uuid, uuid, date)', 'leitura'),
  ('public._agenda_ampliar_lista(regclass, text, text, text[])', 'interna'),
  ('public._agenda_gestor_dia_gravar(date, text, jsonb, timestamptz)', 'escrita'),
  ('public._agenda_alocacao_fonte()', 'gatilho');

insert into _resultado
select 'B2c funções: anon nada; authenticated e service_role só os ajudantes de leitura (o portão, o modo, o dia avisado e os validadores); o ampliador e o gravador sem grant a ninguém, nem service_role; o gatilho sem authenticated',
       bool_and(not has_function_privilege('anon', f, 'execute'))
       and bool_and(has_function_privilege('authenticated', f, 'execute') = (quem = 'leitura'))
       and bool_and(has_function_privilege('service_role', f, 'execute') = (quem = 'leitura') or quem = 'gatilho'),
       coalesce(string_agg(f, ', ') filter (where has_function_privilege('anon', f, 'execute')
                                      or has_function_privilege('authenticated', f, 'execute') <> (quem = 'leitura')
                                      or not (has_function_privilege('service_role', f, 'execute') = (quem = 'leitura') or quem = 'gatilho')), '—')
  from _funcoes_f7a;

insert into _resultado
select 'B2d security definer só o gravador do diário; os ajudantes STABLE ou IMMUTABLE e invoker; search_path fixo em todas',
       bool_and(p.prosecdef = (k.quem = 'escrita'))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and bool_and(p.provolatile in ('s', 'i') or k.quem <> 'leitura'),
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ' order by p.proname)
  from _funcoes_f7a k join pg_proc p on p.oid = k.f::regprocedure;

insert into _resultado
select 'B2e as 8 funções novas da 7a P1 são todas as desta migration (nenhuma esquecida no B2c); _agenda_perguntas_antes continua sem grant',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('_agenda_regex_valido', '_agenda_dupla_lista_ok', '_agenda_gestor_regra', '_agenda_gestor_modo',
                             '_agenda_dia_avisado', '_agenda_ampliar_lista', '_agenda_gestor_dia_gravar', '_agenda_alocacao_fonte')) = 8
       and not has_function_privilege('anon', 'public._agenda_perguntas_antes()', 'execute')
       and not has_function_privilege('authenticated', 'public._agenda_perguntas_antes()', 'execute'),
       null;

insert into _resultado
select 'B2f o técnico: o diário volta vazio, gravar e ampliar dão 42501; anon não lê o diário nem chama o portão; o administrador lê',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select count(*)::text from public.agenda_gestor_dia$q$) = '0'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select public._agenda_gestor_dia_gravar(date '2026-10-29', 'compras', '[]', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select public._agenda_ampliar_lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', 'rotina', array['x'])::text$q$) like 'erro 42501%'
       and pg_temp.como(null, 'service_role',
             $q$select public._agenda_gestor_dia_gravar(date '2026-10-29', 'compras', '[]', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$insert into public.agenda_gestor_dia (dia, calculado_em, modos) values ('2026-10-29', now(), '{}') returning 'x'$q$) like 'erro 42501%'
       and pg_temp.como(null, 'anon', $q$select count(*)::text from public.agenda_gestor_dia$q$) like 'erro 42501%'
       and pg_temp.como(null, 'anon', $q$select public._agenda_gestor_regra('estimativa')::text$q$) like 'erro 42501%'
       and pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated',
             $q$select public._agenda_gestor_regra('estimativa')::text || '/' || public._agenda_gestor_modo('marcar')$q$) = 'false/desligado',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated', $q$select count(*)::text from public.agenda_gestor_dia$q$);

-- ── B3. As listas fechadas e o ampliador ────────────────────────────────────────────────────────────────
insert into _resultado
select format('B3a %s: as de antes iguais e na mesma ordem, e as novas no fim', t.nome),
       pg_temp.lista(t.tabela::regclass, t.nome) = t.espera, array_to_string(pg_temp.lista(t.tabela::regclass, t.nome), ',')
  from (values
    ('public.agenda_perguntas', 'agenda_perguntas_tipo_check',
     '{nao_cabe,segundo_atraso,atraso_longo,remarcar_confirmado,fixada_pelo_dono,conferencia,chegou,parada,estouro,duracao,material_conferir,padrao_do_dono,diaria,diaria_ligar,equipe_resposta,concluir,entrega,nfe_vincular,pix_material,previsao_fornecedor,fornecedor_cadastro,fornecedores_prazo,cliente_aprovar,cliente_aviso,cliente_resposta,aprendizado,equipe_sem_dias,situacao,estimativa,equipe_cadastro,reavaliar,reestimar,ficha_estimativa,bem_livre,compre_ate,sinal,onda,dia_avisado,dia_prometido,sabado}'::text[]),
    ('public.agenda_acoes', 'agenda_acoes_tipo_check',
     '{publicar,criar,mover,cancelar,fixar,promover_reserva,soltar_reserva,status,resultado,desfazer,diaria,concluir,entregar,equipe,material,fornecedor,cliente,aprendizado,estimar,reestimar,reparar,gestor,dupla}'::text[]),
    ('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', '{vigia,rotina,material,cliente,aprender,gestor}'::text[]),
    ('public.agenda_equipe_mensagens', 'agenda_equipe_mensagens_recusa_motivo_check',
     '{teto,janela,domingo,sem_telefone,sem_plano,parou,modo,veto}'::text[]),
    ('public.agenda_alocacoes', 'agenda_alocacoes_cancelada_motivo_check',
     '{replanejado,desfeito,os_saiu,pessoa,material,cliente,clima,condicao_vencida,promovida,dono,espera,reestimada}'::text[]),
    ('public.os_planejamento', 'os_planejamento_estimativa_fonte_check', '{dono,aceita,orcamento}'::text[]),
    ('public.os_planejamento', 'os_planejamento_dias_no_inicio_fonte_check', '{dono,aceita,orcamento}'::text[]),
    ('public.agenda_medidas_os', 'agenda_medidas_os_dias_fonte_check', '{dono,aceita,sugerida,orcamento}'::text[]),
    -- o sinal não vira reserva (AG7-09): condicao_tipo não muda
    ('public.agenda_alocacoes', 'agenda_alocacoes_condicao_tipo_check', '{compra,material,conferir_material,duracao}'::text[])
  ) as t(tabela, nome, espera);

insert into _resultado
select 'B3b agenda_perguntas.critica: gerada (stored), com onda, dia_avisado, dia_prometido e sabado e as 8 de antes, nesta ordem (o 7d e o 7g copiam esta expressão)',
       a.attgenerated = 's'
       and (select array_agg(m[1] order by o) from regexp_matches(pg_get_expr(d.adbin, d.adrelid), '''([^'']*)''', 'g') with ordinality t(m, o))
           = '{nao_cabe,segundo_atraso,atraso_longo,remarcar_confirmado,fixada_pelo_dono,diaria,cliente_aviso,aprendizado,onda,dia_avisado,dia_prometido,sabado}',
       pg_get_expr(d.adbin, d.adrelid)
  from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica';

do $b3$
declare
  v_res jsonb := '[]'::jsonb;
  r record;
  v_ruins text := '';
  v_def text;
  v_det text;
  v_l1 text[];
  v_l2 text[];
begin
  -- Cada tipo novo entra, e é crítico só onda, dia_avisado, dia_prometido e sabado (as críticas com opções e recomendação).
  -- (numa subtransação desfeita: as perguntas de teste não ficam, o B7 conta as abertas do replay)
  begin
  for r in select * from (values ('situacao', false), ('estimativa', false), ('equipe_cadastro', false), ('reavaliar', false),
                                 ('reestimar', false), ('ficha_estimativa', false), ('bem_livre', false), ('compre_ate', false),
                                 ('sinal', false), ('onda', true), ('dia_avisado', true), ('dia_prometido', true), ('sabado', true),
                                 ('nao_cabe', true), ('aprendizado', true), ('estouro', false), ('equipe_sem_dias', false))
                           as t(tipo, critica)
  loop
    begin
      insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao)
      values (r.tipo, r.tipo || ':teste-ag7a-b3', 'Pergunta de teste.', 'ligado',
              case when r.critica then '[{"n":1},{"n":2}]'::jsonb else '[]'::jsonb end, case when r.critica then 1 end);
      if (select p.critica from public.agenda_perguntas p where p.chave = r.tipo || ':teste-ag7a-b3') is distinct from r.critica then
        v_ruins := v_ruins || r.tipo || '(critica?) ';
      end if;
    exception when others then
      v_ruins := v_ruins || r.tipo || '(' || sqlerrm || ') ';
    end;
  end loop;
  raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when others then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  v_res := pg_temp.ok(v_res, 'B3c os 13 tipos novos de pergunta entram; só onda, dia_avisado, dia_prometido e sabado são críticos (e as de antes continuam como eram)',
                      v_ruins = '', nullif(v_ruins, ''));

  -- O ampliador numa tabela de teste.
  create temp table _amp (x text check (x in ('a', 'b')), y text check (y = 'um'), z int check (z > 0)) on commit drop;
  -- (cada chamada do ampliador num comando próprio: a leitura do catálogo de uma função STABLE não vê o que o mesmo comando mudou)
  v_l1 := public._agenda_ampliar_lista('_amp'::regclass, '_amp_x_check', 'x', array['c', 'a', 'c', 'd']);
  v_res := pg_temp.ok(v_res, 'B3d o ampliador soma sem repetir, na ordem (os de antes, depois os novos), e devolve a lista final',
    v_l1 = '{a,b,c,d}' and pg_temp.lista('_amp'::regclass, '_amp_x_check') = '{a,b,c,d}',
    array_to_string(pg_temp.lista('_amp'::regclass, '_amp_x_check'), ','));
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c where c.conrelid = '_amp'::regclass and c.conname = '_amp_x_check';
  v_l1 := public._agenda_ampliar_lista('_amp'::regclass, '_amp_x_check', 'x', array['d', 'b']);
  v_l2 := public._agenda_ampliar_lista('_amp'::regclass, '_amp_x_check', 'x', '{}');
  v_res := pg_temp.ok(v_res, 'B3e rodar de novo não muda nada (idempotente: a mesma lista, o mesmo CHECK); lista vazia também',
    v_l1 = '{a,b,c,d}' and v_l2 = '{a,b,c,d}'
    and (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = '_amp'::regclass and c.conname = '_amp_x_check') = v_def,
    v_def);
  v_det := pg_temp.recusa($q$insert into _amp (y) values ('dois')$q$);
  v_l1 := public._agenda_ampliar_lista('_amp'::regclass, '_amp_y_check', 'y', array['dois']);
  v_res := pg_temp.ok(v_res, 'B3f a lista de um valor só ("y = ''um''") também se amplia; o valor novo é recusado antes e aceito depois',
    v_det = '_amp_y_check' and v_l1 = '{um,dois}' and pg_temp.recusa($q$insert into _amp (y) values ('dois')$q$) = 'aceitou',
    array_to_string(pg_temp.lista('_amp'::regclass, '_amp_y_check'), ','));
  v_res := pg_temp.ok(v_res, 'B3g CHECK que não existe = 42704; CHECK que não é lista da coluna (z > 0, ou de outra coluna) = 22023',
    pg_temp.estado($q$select public._agenda_ampliar_lista('_amp'::regclass, '_amp_w_check', 'x', array['e'])$q$) = '42704'
    and pg_temp.estado($q$select public._agenda_ampliar_lista('_amp'::regclass, '_amp_z_check', 'z', array['5'])$q$) = '22023'
    and pg_temp.estado($q$select public._agenda_ampliar_lista('_amp'::regclass, '_amp_x_check', 'y', array['e'])$q$) = '22023',
    pg_temp.estado($q$select public._agenda_ampliar_lista('_amp'::regclass, '_amp_z_check', 'z', array['5'])$q$));
  perform pg_temp.gravar(v_res);
end
$b3$;

-- ── B4. O portão e o modo ───────────────────────────────────────────────────────────────────────────────
do $b4$
declare
  v_res jsonb := '[]'::jsonb;
  v_def text[];
  v_chk text[];
  v_erro text := '';
  r text;
  -- (modo, variável, só propor, a regra na lista) → o portão
  c record;
  v_mp text := (select modo_proposta from public.agenda_config where id);
begin
  -- A lista: o DEFAULT, o CHECK e o portão são a mesma (três fontes do mesmo padrão, provadas iguais).
  select array_agg(m[1] order by o) into v_def
    from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum,
         regexp_matches(pg_get_expr(d.adbin, d.adrelid), '([a-z_]+)', 'g') with ordinality t(m, o)
   where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'marcar_regras' and m[1] not in ('text');
  v_chk := pg_temp.lista('public.agenda_config'::regclass, 'agenda_config_marcar_regras_check');
  foreach r in array v_def loop
    if pg_temp.estado(format('select public._agenda_gestor_regra(%L)', r)) <> 'ok' then v_erro := v_erro || r || ' '; end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B4a as 15 regras: o DEFAULT de marcar_regras = o CHECK = o que o portão aceita; regra que não existe (sinal_reserva) e nula = 22023',
    cardinality(v_def) = 15 and v_def = v_chk and v_erro = ''
    and pg_temp.estado($q$select public._agenda_gestor_regra('sinal_reserva')$q$) = '22023'
    and pg_temp.estado($q$select public._agenda_gestor_regra(null)$q$) = '22023',
    format('default %s; check %s; recusadas: %s', array_to_string(v_def, ','), array_to_string(v_chk, ','), v_erro));

  for c in select * from (values
      ('desligado', '',       false, true,  false, 'desligado: as Fases 1–6, byte a byte'),
      ('sombra',    '',       false, true,  false, 'sombra (fora da simulação): nada muda'),
      ('ligado',    '',       false, true,  true,  'ligado: a regra vale'),
      ('ligado',    '',       true,  true,  false, 'ligado com *gestor, só propor*: não vale'),
      ('ligado',    '',       false, false, false, 'ligado com a regra fora de marcar_regras: não vale'),
      ('desligado', 'sombra', false, true,  true,  'dentro da simulação da sombra: vale (qualquer modo)'),
      ('desligado', 'sombra', false, false, false, 'dentro da simulação, a regra fora da lista: não vale'),
      ('sombra',    'sombra', true,  true,  true,  'dentro da simulação, mesmo com *só propor*: vale (a sombra é o que ele faria)'),
      ('ligado',    'outra',  false, true,  true,  'a variável com outro valor não conta')
    ) as t(modo, var, so_propor, na_lista, espera, nome)
  loop
    update public.agenda_config
       set modo_marcar_sozinho = c.modo, gestor_so_propor = c.so_propor,
           marcar_regras = case when c.na_lista then marcar_regras else array_remove(marcar_regras, 'estimativa') end
     where id;
    perform set_config('agenda.gestor', c.var, true);
    v_res := pg_temp.ok(v_res, 'B4b o portão: ' || c.nome,
      public._agenda_gestor_regra('estimativa') = c.espera,
      public._agenda_gestor_regra('estimativa')::text);
    perform set_config('agenda.gestor', '', true);
    update public.agenda_config set marcar_regras = default where id;
  end loop;

  -- O modo efetivo.
  update public.agenda_config set modo_marcar_sozinho = 'desligado', modo_encaixe_aprovacao = 'desligado',
         modo_revisao_diaria = 'desligado', modo_compre_ate = 'desligado', modo_vaga_fechamento = 'desligado',
         gestor_so_propor = false where id;
  v_res := pg_temp.ok(v_res, 'B4c o modo: tudo desligado = desligado nos 5',
    public._agenda_gestor_modo('marcar') = 'desligado' and public._agenda_gestor_modo('encaixe') = 'desligado'
    and public._agenda_gestor_modo('revisao') = 'desligado' and public._agenda_gestor_modo('compre_ate') = 'desligado'
    and public._agenda_gestor_modo('vaga') = 'desligado', null);
  update public.agenda_config set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'sombra', modo_revisao_diaria = 'ligado',
         modo_compre_ate = 'desligado', modo_vaga_fechamento = 'ligado' where id;
  v_res := pg_temp.ok(v_res, 'B4d o modo: cada um lê o seu interruptor',
    public._agenda_gestor_modo('marcar') = 'ligado' and public._agenda_gestor_modo('encaixe') = 'sombra'
    and public._agenda_gestor_modo('revisao') = 'ligado' and public._agenda_gestor_modo('compre_ate') = 'desligado'
    and public._agenda_gestor_modo('vaga') = 'ligado', null);
  update public.agenda_config set gestor_so_propor = true where id;
  v_res := pg_temp.ok(v_res, 'B4e o modo com *gestor, só propor*: o ligado de marcar/encaixe/revisao/compre_ate vale sombra; o desligado fica desligado; a vaga do fechamento não muda',
    public._agenda_gestor_modo('marcar') = 'sombra' and public._agenda_gestor_modo('encaixe') = 'sombra'
    and public._agenda_gestor_modo('revisao') = 'sombra' and public._agenda_gestor_modo('compre_ate') = 'desligado'
    and public._agenda_gestor_modo('vaga') = 'ligado',
    concat_ws(',', public._agenda_gestor_modo('marcar'), public._agenda_gestor_modo('encaixe'), public._agenda_gestor_modo('revisao'),
              public._agenda_gestor_modo('compre_ate'), public._agenda_gestor_modo('vaga')));
  update public.agenda_config set gestor_so_propor = false, modo_marcar_sozinho = 'desligado' where id;
  perform set_config('agenda.gestor', 'sombra', true);
  v_res := pg_temp.ok(v_res, 'B4f o modo dentro da simulação: marcar = sombra (mesmo desligado); os outros não mudam pela variável',
    public._agenda_gestor_modo('marcar') = 'sombra' and public._agenda_gestor_modo('encaixe') = 'sombra'
    and public._agenda_gestor_modo('revisao') = 'ligado' and public._agenda_gestor_modo('compre_ate') = 'desligado', null);
  perform set_config('agenda.gestor', '', true);
  v_res := pg_temp.ok(v_res, 'B4g modo que não existe (bem_cliente saiu) e nulo = 22023',
    pg_temp.estado($q$select public._agenda_gestor_modo('bem_cliente')$q$) = '22023'
    and pg_temp.estado($q$select public._agenda_gestor_modo(null)$q$) = '22023', null);
  -- O modo de quem faz cada tipo novo de pergunta (_agenda_modo_da_pergunta recriada: a limpeza da vigia fecha a de teste
  -- quando o modo dela está ligado).
  update public.agenda_config set modo_marcar_sozinho = 'ligado', modo_revisao_diaria = 'sombra', modo_compre_ate = 'desligado',
         modo_proposta = 'sombra' where id;
  v_res := pg_temp.ok(v_res, 'B4h o modo de quem faz os 13 tipos novos: dia_avisado e dia_prometido = o da proposta; reavaliar e reestimar = o da revisão; compre_ate = o da cobrança; os outros 8 = o do gestor que marca',
    (select string_agg(t || '=' || public._agenda_modo_da_pergunta(t, t || ':x'), ',' order by t)
       from unnest(array['situacao', 'estimativa', 'equipe_cadastro', 'reavaliar', 'reestimar', 'ficha_estimativa', 'bem_livre',
                         'compre_ate', 'sinal', 'onda', 'dia_avisado', 'dia_prometido', 'sabado']) t)
    = 'bem_livre=ligado,compre_ate=desligado,dia_avisado=sombra,dia_prometido=sombra,equipe_cadastro=ligado,estimativa=ligado,'
      'ficha_estimativa=ligado,onda=ligado,reavaliar=sombra,reestimar=sombra,sabado=ligado,sinal=ligado,situacao=ligado'
    and public._agenda_modo_da_pergunta('nao_cabe', 'x') = 'sombra' and public._agenda_modo_da_pergunta('outro', 'x') is null,
    (select string_agg(t || '=' || coalesce(public._agenda_modo_da_pergunta(t, t || ':x'), '-'), ',' order by t)
       from unnest(array['situacao', 'estimativa', 'equipe_cadastro', 'reavaliar', 'reestimar', 'ficha_estimativa', 'bem_livre',
                         'compre_ate', 'sinal', 'onda', 'dia_avisado', 'dia_prometido', 'sabado']) t));
  update public.agenda_config set gestor_so_propor = true where id;
  v_res := pg_temp.ok(v_res, 'B4i com *gestor, só propor*, os tipos do gestor que marca ficam com o modo sombra (a limpeza não fecha a pergunta de teste dele)',
    public._agenda_modo_da_pergunta('situacao', 'situacao:x') = 'sombra', public._agenda_modo_da_pergunta('situacao', 'situacao:x'));
  v_res := pg_temp.ok(v_res, 'B4j todo tipo da lista fechada tem o modo de quem o faz (o tipo novo sem modo reprova aqui)',
    not exists (select 1 from unnest(pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')) t
                 where public._agenda_modo_da_pergunta(t, t || ':x') is null), null);
  update public.agenda_config set modo_marcar_sozinho = 'desligado', modo_encaixe_aprovacao = 'desligado',
         modo_revisao_diaria = 'desligado', modo_compre_ate = 'desligado', modo_vaga_fechamento = 'desligado',
         gestor_so_propor = false, modo_proposta = v_mp where id;
  perform pg_temp.gravar(v_res);
end
$b4$;

-- ── B9. O diário do gestor e a medida (antes das fixtures: rodam também em produção) ────────────────────
do $b9$
declare
  v_res jsonb := '[]'::jsonb;
  g public.agenda_gestor_dia;
begin
  perform public._agenda_gestor_dia_gravar(date '2026-10-28', 'sombra', '{"itens": [1], "md5": "a"}', timestamptz '2026-10-28 16:52-03');
  select * into g from public.agenda_gestor_dia where dia = date '2026-10-28';
  v_res := pg_temp.ok(v_res, 'B9a a 1ª gravação do dia cria o registro com a chave, os modos na hora e as outras chaves vazias',
    g.sombra = '{"itens": [1], "md5": "a"}' and g.orcamentos = '[]' and g.compras = '[]' and g.texto_sombra is null
    and g.historico = '[]' and g.calculado_em = timestamptz '2026-10-28 16:52-03'
    and g.modos = '{"marcar": "desligado", "encaixe": "desligado", "revisao": "desligado", "compre_ate": "desligado", "vaga": "desligado", "so_propor": false}',
    to_jsonb(g)::text);
  perform public._agenda_gestor_dia_gravar(date '2026-10-28', 'compras', '[{"fornecedor": "Kamell"}]', timestamptz '2026-10-28 17:00-03');
  perform public._agenda_gestor_dia_gravar(date '2026-10-28', 'texto_sombra', to_jsonb('Eu marcaria assim.'::text), timestamptz '2026-10-28 17:01-03');
  perform public._agenda_gestor_dia_gravar(date '2026-10-28', 'sombra', '{"itens": [2], "md5": "b"}', timestamptz '2026-10-28 17:02-03');
  perform public._agenda_gestor_dia_gravar(date '2026-10-28', 'sombra', '{"itens": [2], "md5": "b"}', timestamptz '2026-10-28 17:03-03');
  select * into g from public.agenda_gestor_dia where dia = date '2026-10-28';
  v_res := pg_temp.ok(v_res, 'B9b reescrever uma chave guarda a de antes no histórico (o vazio e o igual não entram); as outras chaves ficam',
    g.sombra = '{"itens": [2], "md5": "b"}' and g.compras = '[{"fornecedor": "Kamell"}]' and g.texto_sombra = 'Eu marcaria assim.'
    and jsonb_array_length(g.historico) = 1 and g.historico -> 0 ->> 'chave' = 'sombra'
    and g.historico -> 0 -> 'antes' = '{"itens": [1], "md5": "a"}' and g.calculado_em = timestamptz '2026-10-28 17:03-03',
    g.historico::text);
  v_res := pg_temp.ok(v_res, 'B9c chave que não existe, sombra que não é objeto, compras que não são lista e sem o dia = recusados',
    pg_temp.estado($q$select public._agenda_gestor_dia_gravar(date '2026-10-28', 'fora', '[]', now())$q$) = '22023'
    and pg_temp.estado($q$select public._agenda_gestor_dia_gravar(date '2026-10-28', 'sombra', '[]', now())$q$) = '22023'
    and pg_temp.estado($q$select public._agenda_gestor_dia_gravar(date '2026-10-28', 'compras', '{}', now())$q$) = '22023'
    and pg_temp.estado($q$select public._agenda_gestor_dia_gravar(date '2026-10-28', 'texto_sombra', '[]', now())$q$) = '22023'
    and pg_temp.estado($q$select public._agenda_gestor_dia_gravar(null, 'compras', '[]', now())$q$) = '22004'
    and pg_temp.estado(format('select public._agenda_gestor_dia_gravar(date %L, %L, %L::jsonb, now())', '2026-10-28', 'texto_sombra',
                              to_jsonb(repeat('x', 641))::text)) = '23514', null);
  v_res := pg_temp.ok(v_res, 'B9d o diário não se apaga',
    pg_temp.recusa($q$delete from public.agenda_gestor_dia where dia = '2026-10-28'$q$) = 'erro P0001: O registro da agenda não se apaga.',
    pg_temp.recusa($q$delete from public.agenda_gestor_dia where dia = '2026-10-28'$q$));

  -- A medida muda inteira também nas 3 colunas novas (o gatilho da Fase 6 deixa: versão + 1 e o histórico). Numa subtransação
  -- desfeita: a medida não se apaga, e o replay (B7) apaga as OS.
  begin
  insert into public.agenda_medidas_os (service_order_id, classe_bem, classe_sistema, concluida_em, valida, motivo, medida_em)
  values ('d7a00000-0000-4000-8000-0000000000e3', 'rv', 'energia', '2026-10-29', false, 'sem_diaria', '2026-10-29 16:05-03');
  v_res := pg_temp.ok(v_res, 'B9e a medida muda inteira com o fator da estimativa, as diárias estimadas e as reais (versão + 1 e o histórico)',
    pg_temp.recusa($q$update public.agenda_medidas_os set valida = true, motivo = null, dias_no_inicio = 6, dias_fonte = 'orcamento', fator_orcamento = 1.17, dp_no_inicio = 5.97, dp_reais = 7, versao = versao + 1, historico = '[{"em": "2026-10-30"}]' where service_order_id = 'd7a00000-0000-4000-8000-0000000000e3'$q$) = 'aceitou'
    and pg_temp.recusa($q$update public.agenda_medidas_os set dp_reais = 7 where service_order_id = 'd7a00000-0000-4000-8000-0000000000e3'$q$)
        = 'erro P0001: A medida só muda inteira: versão + 1 e o que mudou no histórico.', null);
  raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when others then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(v_res);
end
$b9$;

-- ── B5 a B8: com as fixtures (o replay de 29/10 e a sintética, por cima) ────────────────────────────────
do $fx$
declare
  v_res  jsonb := '[]'::jsonb;
  v_joao uuid;
  v_os   uuid;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_tabelas_fase3', true), '');
  v_fonte text;
  v_novo text;
  v_q    uuid;
  v_n    int;
  c_os   constant text := 'f7a00000-0000-4000-8000-000000097';
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('B5 a B8 (as fixtures da 7a)', true,
      'PULADO: sem agenda_teste.replay2910 e agenda_teste.fase7a (rode pela bancada)');
    return;
  end if;

  -- ── B7. O replay de 29/10 ──────────────────────────────────────────────────────────────────────────────
  execute current_setting('agenda_teste.replay2910');
  v_res := pg_temp.ok(v_res, 'B7a o replay: a carteira das 11 de 29/10 (as 45 linhas de serviço, as 19 de material), 20 OS com os orçamentos',
    (select count(*) from public.os_carteira(date '2026-10-29')) = 11
    and (select string_agg(k.numero, ',' order by k.numero) from public.os_carteira(date '2026-10-29') k)
        = 'ORÇ-00083,ORÇ-00095,OS-00032,OS-00033,OS-00069,OS-00074,OS-00076,OS-00096,OS-00104,OS-00112,OS-00130'
    and (select count(*) from public.service_order_services s
          where s.service_order_id in (select k.service_order_id from public.os_carteira(date '2026-10-29') k)) = 45
    and (select count(*) from public.os_material) = 19 and (select count(*) from public.service_orders) = 20
    and (select count(*) from public.service_orders where service_order_number like 'OS-00%' and status = 'completed') = 0,
    (select string_agg(k.numero, ',' order by k.numero) from public.os_carteira(date '2026-10-29') k));
  v_res := pg_temp.ok(v_res, 'B7b o replay: a duração realista de hoje das 11 (Lenine 3, Vanderlei 3,5, Giancarlo 5, Nelson 2, Flávio 2, Kalmar 9 e 7,5, Robson 1, Rodrigo 0,5 e 0,5; MP sem base)',
    (select string_agg(k.numero || '=' || coalesce(public.os_duracao_sugerida(k.service_order_id) ->> 'dias_realista', '-'), ','
                       order by k.numero) from public.os_carteira(date '2026-10-29') k)
    = 'ORÇ-00083=1,ORÇ-00095=-,OS-00032=9,OS-00033=7.5,OS-00069=3.5,OS-00074=3,OS-00076=0.5,OS-00096=0.5,OS-00104=2,OS-00112=2,OS-00130=5',
    (select string_agg(k.numero || '=' || coalesce(public.os_duracao_sugerida(k.service_order_id) ->> 'dias_realista', '-'), ','
                       order by k.numero) from public.os_carteira(date '2026-10-29') k));
  v_res := pg_temp.ok(v_res, 'B7c o replay: a equipe de 29/10 — o dono único (sem linha de disponibilidade), Roberto 5 e João 4 linhas da semente, Mickael com perfil e sem linha, Alex sem perfil e sem linha',
    (select p.name from public.payees p where p.id = public._agenda_dono(null)) = 'Gustavo'
    and (select string_agg(p.name || ':' || (select count(*) from public.agenda_disponibilidade d
                                               where d.payee_id = p.id and d.substituida_em is null and d.origem = 'historico')
                           || ':' || (select count(*) from public.work_profiles w where w.payee_id = p.id), ',' order by p.name)
           from public.payees p)
        = 'Alex:0:0,Gustavo:0:0,João:4:1,Mickael:0:1,Roberto:5:1'
    and not exists (select 1 from public.agenda_disponibilidade where origem <> 'historico')
    and (select round(sum(frequencia), 4) from public.agenda_disponibilidade where payee_id = (select id from public.payees where name = 'Roberto'))
        = 4.4524,
    (select string_agg(p.name || ':' || p.kind, ',' order by p.name) from public.payees p));
  v_res := pg_temp.ok(v_res, 'B7d o replay: as 12 reservas do Lenine (Roberto e João, manhã e tarde de qui 05, sex 06 e ter 10/11, condicionadas a "tem peça a comprar?") e as 3 perguntas ligadas abertas',
    (select count(*) from public.agenda_alocacoes a join public.service_orders so on so.id = a.service_order_id
      where so.service_order_number = 'OS-00074' and a.estado = 'publicada' and a.tipo = 'reserva'
        and a.condicao_tipo = 'conferir_material' and a.dia in ('2026-11-05', '2026-11-06', '2026-11-10')) = 12
    and (select count(*) from public.agenda_alocacoes) = 12
    and (select string_agg(q.tipo, ',' order by q.tipo) from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'ligado')
        = 'fornecedor_cadastro,fornecedores_prazo,material_conferir',
    (select string_agg(q.tipo || ':' || q.estado, ',') from public.agenda_perguntas q));
  v_res := pg_temp.ok(v_res, 'B7e o replay: a linha de agenda_config de produção (as Fases 1–6 ligadas), com a Fase 7 desligada; os sinais pagos e a OC do compressor',
    (select modo_leitura = 'ligado' and modo_proposta = 'ligado' and modo_vigia = 'ligado' and modo_cliente = 'ligado'
            and modo_aprendizado = 'ligado' and modo_marcar_sozinho = 'desligado' and modo_compre_ate = 'desligado'
       from public.agenda_config)
    and (select string_agg(k.numero || '=' || k.sinal_pago, ',' order by k.numero) from public.os_carteira(date '2026-10-29') k
          where k.sinal_pago > 0) = 'OS-00069=4500.00,OS-00074=2280.00,OS-00104=2070.00,OS-00112=7600.00,OS-00130=3869.50'
    and exists (select 1 from public.purchase_orders where po_number = 'OC-00004' and status = 'draft'),
    (select string_agg(k.numero || '=' || k.sinal_pago, ',' order by k.numero) from public.os_carteira(date '2026-10-29') k));
  v_res := pg_temp.ok(v_res, 'B7f o replay: só o primeiro nome (clientes, pessoas, fornecedores), nenhum e-mail real nem telefone real',
    not exists (select 1 from public.clients where name ~ '\s') and not exists (select 1 from public.payees where name ~ '\s')
    and not exists (select 1 from public.suppliers where name ~ '\s')
    and not exists (select 1 from public.app_users where email !~ '@replay2910\.invalid$')
    and not exists (select 1 from public.payees where phone is not null and phone !~ '^55479000000[0-9]{2}$'),
    (select string_agg(name, ',' order by name) from public.clients));

  -- ── A sintética por cima ───────────────────────────────────────────────────────────────────────────────
  execute current_setting('agenda_teste.fase7a');
  select id into v_joao from public.payees where name = 'João';
  v_res := pg_temp.ok(v_res, 'B7g a sintética: as 8 OS dela na carteira (19), o rastro do Paulo, a dupla do Sérgio, o deslocamento da Tânia, o prometido da Úrsula, o sinal da Vera, as 3 do João e a ficha dele',
    (select count(*) from public.os_carteira(date '2026-10-29')) = 19
    and exists (select 1 from public.work_shift_os x where x.service_order_id = (c_os || '001')::uuid)
    and (select dupla_dita from public.os_planejamento where service_order_id = (c_os || '002')::uuid) = 'todos'
    and exists (select 1 from public.os_material where service_order_id = (c_os || '002')::uuid and situacao = 'na_mao')
    and exists (select 1 from public.service_order_services where service_order_id = (c_os || '003')::uuid
                                                              and name_snapshot = 'Deslocamento técnico' and billing_unit_snapshot = 'hour')
    and (select prometido_tipo from public.os_planejamento where service_order_id = (c_os || '004')::uuid) = 'firme'
    and (select k.sinal_pendente from public.os_carteira(date '2026-10-29') k where k.numero = 'OS-97005') = 1000
    and (select count(*) from public.agenda_alocacoes where payee_id = v_joao and tipo = 'execucao' and estado = 'publicada') = 3
    and not exists (select 1 from public.agenda_disponibilidade where dias_semana = '{6}'),
    null);

  -- ── B5. O dia avisado ──────────────────────────────────────────────────────────────────────────────────
  v_res := pg_temp.ok(v_res, 'B5a a ficha ligada enfileirada do João de ter 03/11 = equipe; outro dia dele = null; outra pessoa no mesmo dia = null',
    public._agenda_dia_avisado(v_joao, (c_os || '006')::uuid, date '2026-11-03') = 'equipe'
    and public._agenda_dia_avisado(v_joao, null, date '2026-11-03') = 'equipe'
    and public._agenda_dia_avisado(v_joao, (c_os || '008')::uuid, date '2026-11-04') is null
    and public._agenda_dia_avisado((select id from public.payees where name = 'Roberto'), (c_os || '006')::uuid, date '2026-11-03') is null,
    public._agenda_dia_avisado(v_joao, (c_os || '006')::uuid, date '2026-11-03'));
  v_res := pg_temp.ok(v_res, 'B5b o prometido firme da Úrsula (09 a 10/11) = cliente; fora dele = null; sem a OS = null',
    public._agenda_dia_avisado(null, (c_os || '004')::uuid, date '2026-11-09') = 'cliente'
    and public._agenda_dia_avisado(null, (c_os || '004')::uuid, date '2026-11-10') = 'cliente'
    and public._agenda_dia_avisado(null, (c_os || '004')::uuid, date '2026-11-11') is null
    and public._agenda_dia_avisado(null, null, date '2026-11-09') is null, null);
  -- cliente vence equipe: a ficha do João de 09/11 e o prometido da Úrsula no mesmo dia
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
  values (v_joao, date '2026-11-09', 'ficha', 'ligado', 'Amanhã: Úrsula.', timestamptz '2026-11-06 19:30-03', 'respondida',
          'teste-ag7a:ficha:joao:2026-11-09');
  update public.os_planejamento set prometido_tipo = 'faixa', prometido_de = date '2026-11-16', prometido_ate = date '2026-11-20',
         prometido_original_ate = date '2026-11-20' where service_order_id = (c_os || '006')::uuid;
  update public.service_orders set client_confirmed_for = timestamptz '2026-11-04 08:00-03' where id = (c_os || '008')::uuid;
  v_res := pg_temp.ok(v_res, 'B5c cliente vence equipe; a ficha respondida conta; o prometido em faixa não conta; o client_confirmed_for conta',
    public._agenda_dia_avisado(v_joao, (c_os || '004')::uuid, date '2026-11-09') = 'cliente'
    and public._agenda_dia_avisado(v_joao, null, date '2026-11-09') = 'equipe'
    and public._agenda_dia_avisado(null, (c_os || '006')::uuid, date '2026-11-17') is null
    and public._agenda_dia_avisado(v_joao, (c_os || '008')::uuid, date '2026-11-04') = 'cliente', null);
  -- a ficha em sombra, a recusada, a só registrada e o "como foi" não contam
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key)
  values (v_joao, date '2026-11-12', 'ficha', 'sombra', 'Amanhã: x.', timestamptz '2026-11-11 19:30-03', 'registrada', null, 'teste-ag7a:1'),
         (v_joao, date '2026-11-13', 'ficha', 'ligado', 'Amanhã: x.', timestamptz '2026-11-12 19:30-03', 'recusada', 'veto', 'teste-ag7a:2'),
         (v_joao, date '2026-11-16', 'ficha', 'ligado', 'Amanhã: x.', timestamptz '2026-11-13 19:30-03', 'registrada', null, 'teste-ag7a:3'),
         (v_joao, date '2026-11-17', 'como_foi', 'ligado', 'Como foi?', timestamptz '2026-11-17 17:00-03', 'enfileirada', null, 'teste-ag7a:4');
  v_res := pg_temp.ok(v_res, 'B5d a ficha em sombra, a recusada (pelo motivo novo: veto), a só registrada e o "como foi" não avisam o dia',
    public._agenda_dia_avisado(v_joao, null, date '2026-11-12') is null and public._agenda_dia_avisado(v_joao, null, date '2026-11-13') is null
    and public._agenda_dia_avisado(v_joao, null, date '2026-11-16') is null and public._agenda_dia_avisado(v_joao, null, date '2026-11-17') is null,
    null);

  -- ── B6. O gatilho da fonte da duração ──────────────────────────────────────────────────────────────────
  v_res := pg_temp.ok(v_res, 'B6a as 3 do João nasceram sem proposta: a fonte é a do planejamento (o dono disse meio dia) — dono; as reservas do Lenine ficaram sem fonte',
    (select bool_and(duracao_fonte = 'dono') from public.agenda_alocacoes where payee_id = v_joao and tipo = 'execucao')
    and (select bool_and(duracao_fonte is null) from public.agenda_alocacoes where tipo = 'reserva'), null);
  insert into public.agenda_propostas (id, escopo, periodo, versao_base, modo, estado, itens, parametros, criada_por, expira_em)
  values ('d7a00000-0000-4000-8000-0000000000f1', 'os', daterange('2026-11-11', '2026-11-14'), 0, 'sombra', 'aberta',
          jsonb_build_array(jsonb_build_object('op', 'criar', 'os', (c_os || '003')::text, 'fonte', 'orcamento'),
                            jsonb_build_object('op', 'criar', 'os', (c_os || '005')::text, 'fonte', 'xyz')),
          '{"p_hoje": "2026-10-29"}', 'motor', now() + interval '1 day');
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, estado, proposta_id)
  values ('d7a00000-0000-4000-8000-0000000000a1', (c_os || '003')::uuid, v_joao, date '2026-11-11', 'manha', 'proposta',
          'd7a00000-0000-4000-8000-0000000000f1'),
         ('d7a00000-0000-4000-8000-0000000000a2', (c_os || '005')::uuid, v_joao, date '2026-11-11', 'tarde', 'proposta',
          'd7a00000-0000-4000-8000-0000000000f1'),
         ('d7a00000-0000-4000-8000-0000000000a3', (c_os || '006')::uuid, v_joao, date '2026-11-12', 'manha', 'proposta',
          'd7a00000-0000-4000-8000-0000000000f1');
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, estado, proposta_id, duracao_fonte)
  values ('d7a00000-0000-4000-8000-0000000000a4', (c_os || '003')::uuid, v_joao, date '2026-11-12', 'tarde', 'proposta',
          'd7a00000-0000-4000-8000-0000000000f1', 'aceita');
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, estado, proposta_id, tipo, reserva_de,
                                       duracao_fonte)
  values ('d7a00000-0000-4000-8000-0000000000a5', (c_os || '003')::uuid, v_joao, date '2026-11-13', 'manha', 'proposta',
          'd7a00000-0000-4000-8000-0000000000f1', 'reserva', 'teto', 'orcamento');
  v_res := pg_temp.ok(v_res, 'B6b a fonte do item criar da proposta (orcamento); o item com fonte que não existe cai para sugerida; a OS que não está nos itens usa o planejamento; a dita fica; a reserva nunca tem fonte',
    (select string_agg(right(id::text, 2) || '=' || coalesce(duracao_fonte, '-'), ',' order by id) from public.agenda_alocacoes
      where id::text like 'd7a00000-0000-4000-8000-0000000000a%') = 'a1=orcamento,a2=sugerida,a3=dono,a4=aceita,a5=-',
    (select string_agg(right(id::text, 2) || '=' || coalesce(duracao_fonte, '-'), ',' order by id) from public.agenda_alocacoes
      where id::text like 'd7a00000-0000-4000-8000-0000000000a%'));
  v_res := pg_temp.ok(v_res, 'B6c o gatilho só olha o INSERT: a alocação que muda de estado guarda a fonte com que nasceu',
    pg_temp.recusa($q$update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'reestimada' where id = 'd7a00000-0000-4000-8000-0000000000a1'$q$) = 'aceitou'
    and (select duracao_fonte from public.agenda_alocacoes where id = 'd7a00000-0000-4000-8000-0000000000a1') = 'orcamento', null);

  -- ── B8. _agenda_perguntas_antes recriada ───────────────────────────────────────────────────────────────
  select id into v_q from public.agenda_perguntas where tipo = 'material_conferir' and estado = 'aberta';
  update public.agenda_perguntas set veto_ate = timestamptz '2026-10-30 18:00-03', mostrada_vezes = 1, mostrada_em = now(),
         mostrada_via = 'fechamento' where id = v_q;
  v_res := pg_temp.ok(v_res, 'B8a o prazo vai de nulo a um valor UMA vez, na pergunta aberta (quem mostra com o prazo escrito grava); de um valor a outro, não',
    (select veto_ate from public.agenda_perguntas where id = v_q) = timestamptz '2026-10-30 18:00-03'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = timestamptz %L, mostrada_vezes = 2 where id = %L',
                              '2026-10-30 18:00-03', v_q)) = 'aceitou'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = timestamptz %L where id = %L', '2026-11-03 18:00-03', v_q))
        = 'erro P0001: A pergunta não muda o que pergunta: só se mostra, se responde ou se resolve.'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = null where id = %L', v_q))
        = 'erro P0001: A pergunta não muda o que pergunta: só se mostra, se responde ou se resolve.',
    pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = timestamptz %L where id = %L', '2026-11-03 18:00-03', v_q)));
  select id into v_q from public.agenda_perguntas where tipo = 'fornecedores_prazo' and estado = 'aberta';
  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_q;
  v_res := pg_temp.ok(v_res, 'B8b a pergunta fechada não ganha prazo; a opção padrão tem de ser uma das opções (a recomendação e a escolhida, como antes)',
    pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = now() where id = %L', v_q))
        = 'erro P0001: A pergunta fechada não muda: a decisão registrada fica como foi.'
    and pg_temp.recusa(pg_temp.mais('perg', 'opcoes, recomendacao, veto_ate, opcao_padrao', $v$'[{"n":1},{"n":2}]', 1, now() + interval '1 day', 3$v$))
        = 'erro P0001: A opção que vale sem resposta tem de ser uma das opções da pergunta.'
    and pg_temp.recusa(pg_temp.mais('perg', 'opcoes, recomendacao', $v$'[{"n":1},{"n":2}]', 3$v$))
        = 'erro P0001: A recomendação tem de ser uma das opções da pergunta.', null);
  if v_mig = '' then
    v_res := pg_temp.ok(v_res, 'B8c _agenda_perguntas_antes: a cópia', true, 'PULADO: sem agenda_teste.mig_tabelas_fase3 (rode pela bancada)');
  else
    v_fonte := replace(v_mig, E'\r\n', E'\n');
    v_fonte := substr(v_fonte, position('create or replace function public._agenda_perguntas_antes(' in v_fonte));
    v_fonte := substr(v_fonte, position(E'\nas $function$' in v_fonte) + length(E'\nas $function$'));
    v_fonte := left(v_fonte, position('$function$' in v_fonte) - 1);
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = 'public._agenda_perguntas_antes()'::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: fim', 'g');
    v_res := pg_temp.ok(v_res, 'B8c _agenda_perguntas_antes: sem os 2 blocos "-- FASE 7:", é o corpo de 20261026100000 (a mais nova antes da 7a)',
      v_n = 2 and v_fonte <> ''
      and array_to_string(array(
            select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7:' and l !~ '-- FASE 7: fim' then 1
                                                 when l ~ '-- FASE 7: fim' then -1 else 0 end)
                                        over (order by o rows between unbounded preceding and current row) as dentro,
                                  l ~ '-- FASE 7: fim' as fecha
                             from unnest(string_to_array(v_novo, E'\n')) with ordinality u(l, o)) x
             where dentro = 0 and not fecha order by o), E'\n') = v_fonte,
      format('blocos %s; fonte %s letras; novo %s letras', v_n, length(v_fonte), length(v_novo)));
  end if;

  perform pg_temp.gravar(v_res);
end
$fx$;

-- ── B8d. A cópia de _agenda_modo_da_pergunta (de 20261030100500, a mais nova) ───────────────────────────
do $b8d$
declare
  v_mig   text := coalesce(current_setting('agenda_teste.mig_correcao_revisao', true), '');
  v_fonte text;
  v_novo  text;
  v_sem   text;
  v_n     int;
begin
  if v_mig = '' then
    insert into _resultado values ('B8d _agenda_modo_da_pergunta: a cópia', true, 'PULADO: sem agenda_teste.mig_correcao_revisao (rode pela bancada)');
    return;
  end if;
  v_fonte := replace(v_mig, E'\r\n', E'\n');
  v_fonte := substr(v_fonte, position('create or replace function public._agenda_modo_da_pergunta(' in v_fonte));
  v_fonte := substr(v_fonte, position(E'\nas $function$' in v_fonte) + length(E'\nas $function$'));
  v_fonte := left(v_fonte, position('$function$' in v_fonte) - 1);
  select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = 'public._agenda_modo_da_pergunta(text, text)'::regprocedure;
  select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: fim', 'g');
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7:' and l !~ '-- FASE 7: fim' then 1
                                                when l ~ '-- FASE 7: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '-- FASE 7: fim' as fecha
                            from unnest(string_to_array(v_novo, E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n') into v_sem;
  insert into _resultado values ('B8d _agenda_modo_da_pergunta: sem o bloco "-- FASE 7:", é o corpo de 20261030100500 (a mais nova antes da 7a); só o service_role executa, como antes',
    v_n = 1 and v_fonte <> '' and v_sem = v_fonte
    and not has_function_privilege('anon', 'public._agenda_modo_da_pergunta(text, text)', 'execute')
    and not has_function_privilege('authenticated', 'public._agenda_modo_da_pergunta(text, text)', 'execute')
    and has_function_privilege('service_role', 'public._agenda_modo_da_pergunta(text, text)', 'execute'),
    format('blocos %s; fonte %s letras; novo sem o bloco %s letras', v_n, length(v_fonte), length(v_sem)));
end
$b8d$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
