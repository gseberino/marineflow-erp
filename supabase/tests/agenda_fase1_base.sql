-- Prova da base da Agenda de Produção, Fase 1 (pacote P1): as 6 tabelas, o calendário e a semente
-- (migrations 20261024160000, 20261024160100 e 20261024160200).
-- bancada: depende de 20261024160200
--
--   A  estrutura e portas: RLS ligada nas 6 tabelas; policies só de leitura e TO authenticated; anon sem
--      privilégio nenhum; authenticated só lê; service_role escreve; agenda_config com 1 linha e os DEFAULTs
--      de como nasce (leitura em sombra, o resto desligado, plano versão 0, plano na quinta)
--   B  cada CHECK das 6 tabelas recusa uma linha errada (e a cobrança de que nenhum CHECK ficou sem caso); os
--      índices únicos e as FKs recusam o repetido e o inexistente; as linhas certas entram
--   C  calendário: agenda_feriado = feriados_2026_2035.json nos 3.652 dias (o JSON é gerado de feriados.ts);
--      Páscoa; dia útil (sábado, domingo, feriado, recesso); agenda_somar_du; agenda_du_entre;
--      agenda_data_dita (e o erro 22007 com a frase ao dono); agenda_dias_da_semana_ditos; os textos curtos
--   D  semente: com a fixture de 23/10, Roberto 5 linhas Σ 4,43, João 4 linhas Σ 2,33, Mickael nenhuma, sábado
--      nunca; reaplicar não duplica; mudança nas diárias troca só quem mudou e nunca toca a linha do dono.
--      Sem a fixture (produção), só as regras gerais
--   E  portas das funções: nenhuma agenda_*/_agenda_* executável por anon; o calendário para authenticated;
--      a semente só para service_role; _dia_curto para authenticated; só a semente é security definer
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261024160200
--     A bancada passa o JSON de paridade em agenda_teste.feriados; sem ele a linha C1 sai PULADO.
--   Em produção, só DEPOIS de aplicar as 3 migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase1_base.sql
--   Seguro em produção: a OS, a peça, a OC e a pessoa de teste (OS-TESTE-AG1, OC-TESTE-AG1, "TESTE AG1") só são
--   inseridas; a semente roda e é desfeita; termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Executa um comando e diz que porta o recusou: o nome do CHECK, do índice único ou da FK; 'aceitou' quando
-- entrou (e desfaz, para não sujar os casos seguintes); 'erro <estado>' para qualquer outra coisa.
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

-- Erro que o comando levanta: '<sqlstate> <mensagem>', ou 'sem erro'.
create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
declare
  v_estado text; v_msg text;
begin
  execute p_sql;
  return 'sem erro';
exception when others then
  get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  return v_estado || ' ' || v_msg;
end $f$;

-- ── A. Estrutura e portas ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('A1 RLS ligada: %s', t),
       coalesce((select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.' || t)), false),
       null
  from unnest(array['agenda_config', 'agenda_disponibilidade', 'os_planejamento', 'os_planejamento_equipe',
                    'os_material', 'agenda_rascunho']) t;

insert into _resultado
select format('A2 policies de %s: só leitura e TO authenticated', t),
       count(p.policyname) >= 1 and coalesce(bool_and(p.roles = '{authenticated}'::name[] and p.cmd = 'SELECT'), false),
       string_agg(p.policyname || ' ' || p.cmd || ' ' || p.roles::text, '; ')
  from unnest(array['agenda_config', 'agenda_disponibilidade', 'os_planejamento', 'os_planejamento_equipe',
                    'os_material', 'agenda_rascunho']) t
  left join pg_policies p on p.schemaname = 'public' and p.tablename = t
 group by t;

insert into _resultado
select format('A3 anon sem privilégio: %s', t),
       not (has_table_privilege('anon', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'insert')
            or has_table_privilege('anon', 'public.' || t, 'update') or has_table_privilege('anon', 'public.' || t, 'delete')
            or has_table_privilege('anon', 'public.' || t, 'truncate')),
       null
  from unnest(array['agenda_config', 'agenda_disponibilidade', 'os_planejamento', 'os_planejamento_equipe',
                    'os_material', 'agenda_rascunho']) t;

insert into _resultado
select format('A4 authenticated só lê, service_role escreve: %s', t),
       has_table_privilege('authenticated', 'public.' || t, 'select')
       and not (has_table_privilege('authenticated', 'public.' || t, 'insert')
                or has_table_privilege('authenticated', 'public.' || t, 'update')
                or has_table_privilege('authenticated', 'public.' || t, 'delete'))
       and has_table_privilege('service_role', 'public.' || t, 'insert')
       and has_table_privilege('service_role', 'public.' || t, 'update'),
       null
  from unnest(array['agenda_config', 'agenda_disponibilidade', 'os_planejamento', 'os_planejamento_equipe',
                    'os_material', 'agenda_rascunho']) t;

insert into _resultado
select 'A5 agenda_config tem exatamente 1 linha', (select count(*) from public.agenda_config) = 1,
       (select count(*) from public.agenda_config)::text;

-- modo_proposta e modo_vigia: a Fase 2 (20261025100000, a migration que cria agenda_alocacoes) os faz nascer 'sombra'.
insert into _resultado
select format('A6 agenda_config nasce com %s = %s', x.coluna, x.esperado),
       pg_get_expr(d.adbin, d.adrelid) = x.esperado,
       pg_get_expr(d.adbin, d.adrelid)
  from (values ('modo_leitura', '''sombra''::text'),
               ('modo_proposta', case when to_regclass('public.agenda_alocacoes') is null then '''desligado''::text'
                                      else '''sombra''::text' end),
               ('modo_vigia', case when to_regclass('public.agenda_alocacoes') is null then '''desligado''::text'
                                   else '''sombra''::text' end),
               ('modo_equipe', '''desligado''::text'),
               ('modo_cliente', '''desligado''::text'), ('versao_plano', '0'), ('dia_do_plano', '4'),
               ('medicao_semanas', '8'), ('equipe_recente_dias', '14'), ('frequencia_minima', '0.25'),
               ('carga_max', '0.80')) as x(coluna, esperado)
  left join pg_attribute a on a.attrelid = 'public.agenda_config'::regclass and a.attname = x.coluna
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum;

insert into _resultado
select 'A7 agenda_config sem folga remota nem limiar de turno (revisão §6 e §7)',
       not exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass and not a.attisdropped
                    and a.attname in ('folga_remoto_du', 'limiar_turno_livre', 'letras_fechamento_max')),
       null;

-- ── B. Cada CHECK recusa uma linha errada ───────────────────────────────────────────────────────────────
do $b$
declare
  v_barco  uuid := (select id from public.vessels where client_id is not null order by created_at, id limit 1);
  v_cliente uuid := (select client_id from public.vessels where id = v_barco);
  v_autor  uuid := (select id from public.app_users where role = 'admin' and active order by created_at, id limit 1);
  v_os uuid; v_os2 uuid; v_prod uuid; v_peca uuid; v_serv uuid; v_oc uuid; v_poi uuid; v_pessoa uuid;
  v_cmd text; v text; r record;
  v_testados text[] := '{}';
  v_sem_caso text;
begin
  if v_barco is null then raise exception 'FALHOU: nenhum barco cadastrado para montar a OS de teste'; end if;
  if v_autor is null then raise exception 'FALHOU: nenhum admin ativo para o rascunho de teste'; end if;

  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG1', 'open', 'approved') returning id into v_os;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG1-B', 'open', 'approved') returning id into v_os2;
  insert into public.products (name, stock_quantity) values ('TESTE AG1 — peça', 0) returning id into v_prod;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (v_os, v_prod, 2, 1, 1, 2, 2) returning id into v_peca;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total)
  values (v_os, 'TESTE AG1 — barramento e proteções', 'visit', 1, 2000, 2000) returning id into v_serv;
  insert into public.purchase_orders (po_number, status, service_order_id)
  values ('OC-TESTE-AG1', 'draft', v_os) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, description, quantity)
  values (v_oc, 'TESTE AG1 — compressor', 1) returning id into v_poi;
  insert into public.payees (name, kind) values ('TESTE AG1 — pessoa', 'prestador') returning id into v_pessoa;
  insert into public.os_planejamento (service_order_id) values (v_os);

  for r in
    select * from (values
      -- agenda_config (uma linha só; os parâmetros pelos limites)
      ('agenda_config_id_check', 'uma 2ª linha', $q$insert into public.agenda_config (id) values (false)$q$),
      ('agenda_config_pkey', 'a mesma linha de novo', $q$insert into public.agenda_config (id) values (true)$q$),
      ('agenda_config_jornada_horas_check', 'jornada 3 h', $q$update public.agenda_config set jornada_horas = 3$q$),
      ('agenda_config_carga_max_check', 'carga 0,3', $q$update public.agenda_config set carga_max = 0.3$q$),
      ('agenda_config_fator_promessa_check', 'fator 3', $q$update public.agenda_config set fator_promessa = 3$q$),
      ('agenda_config_wip_max_check', 'wip 4', $q$update public.agenda_config set wip_max = 4$q$),
      ('agenda_config_congelamento_du_check', 'congelamento 4', $q$update public.agenda_config set congelamento_du = 4$q$),
      ('agenda_config_horizonte_semanas_check', 'horizonte 1', $q$update public.agenda_config set horizonte_semanas = 1$q$),
      ('agenda_config_folga_material_du_check', 'folga 6', $q$update public.agenda_config set folga_material_du = 6$q$),
      ('agenda_config_prazo_classe_du_check', 'prazos em lista', $q$update public.agenda_config set prazo_classe_du = '[]'$q$),
      ('agenda_config_mo_por_diaria_preco_check', 'MO por diária 0', $q$update public.agenda_config set mo_por_diaria_preco = 0$q$),
      ('agenda_config_mo_por_diaria_real_check', 'MO real 0', $q$update public.agenda_config set mo_por_diaria_real = 0$q$),
      ('agenda_config_equipe_sugerida_check', 'equipe 4', $q$update public.agenda_config set equipe_sugerida = 4$q$),
      ('agenda_config_prazo_padrao_du_check', 'prazo 4', $q$update public.agenda_config set prazo_padrao_du = 4$q$),
      ('agenda_config_dia_do_plano_check', 'plano no sábado', $q$update public.agenda_config set dia_do_plano = 6$q$),
      ('agenda_config_medicao_semanas_check', 'medição 1', $q$update public.agenda_config set medicao_semanas = 1$q$),
      ('agenda_config_equipe_recente_dias_check', 'recência 6', $q$update public.agenda_config set equipe_recente_dias = 6$q$),
      ('agenda_config_frequencia_minima_check', 'frequência 1,5', $q$update public.agenda_config set frequencia_minima = 1.5$q$),
      ('agenda_config_peca_embutida_acima_check', 'peça embutida −1', $q$update public.agenda_config set peca_embutida_acima = -1$q$),
      ('agenda_config_texto_max_check', 'texto 300', $q$update public.agenda_config set texto_max = 300$q$),
      ('agenda_config_modo_leitura_check', 'modo talvez', $q$update public.agenda_config set modo_leitura = 'talvez'$q$),
      ('agenda_config_modo_proposta_check', 'modo talvez', $q$update public.agenda_config set modo_proposta = 'talvez'$q$),
      ('agenda_config_modo_vigia_check', 'modo talvez', $q$update public.agenda_config set modo_vigia = 'talvez'$q$),
      ('agenda_config_modo_equipe_check', 'modo talvez', $q$update public.agenda_config set modo_equipe = 'talvez'$q$),
      ('agenda_config_modo_cliente_check', 'modo talvez', $q$update public.agenda_config set modo_cliente = 'talvez'$q$),
      -- agenda_disponibilidade
      ('agenda_disponibilidade_turno_check', 'turno noite',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem) values ({pessoa}, '{1}', 'noite', 'disponivel', 'dono')$q$),
      ('agenda_disponibilidade_situacao_check', 'situação talvez',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem) values ({pessoa}, '{1}', 'talvez', 'dono')$q$),
      ('agenda_disponibilidade_origem_check', 'origem chute',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem) values ({pessoa}, '{1}', 'disponivel', 'chute')$q$),
      ('agenda_disponibilidade_frequencia_check', 'frequência 1,5',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, frequencia) values ({pessoa}, '{1}', 'disponivel', 'historico', 1.5)$q$),
      ('agenda_disponibilidade_nota_check', 'nota de 201',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, nota) values ({pessoa}, '{1}', 'disponivel', 'dono', repeat('x', 201))$q$),
      ('agenda_disponibilidade_trecho_check', 'trecho de 301',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, trecho) values ({pessoa}, '{1}', 'disponivel', 'dono', repeat('x', 301))$q$),
      ('padrao_ou_excecao', 'padrão e exceção juntos',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, periodo, situacao, origem) values ({pessoa}, '{1}', '[2026-11-03,2026-11-04]', 'disponivel', 'dono')$q$),
      ('padrao_ou_excecao', 'nem padrão nem exceção',
       $q$insert into public.agenda_disponibilidade (payee_id, situacao, origem) values ({pessoa}, 'disponivel', 'dono')$q$),
      ('dias_validos', 'domingo no padrão',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem) values ({pessoa}, '{7}', 'disponivel', 'dono')$q$),
      ('dias_validos', 'padrão sem dia',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem) values ({pessoa}, '{}', 'disponivel', 'dono')$q$),
      ('periodo_nao_vazio', 'exceção de período vazio',
       $q$insert into public.agenda_disponibilidade (periodo, situacao, origem) values ('empty', 'indisponivel', 'dono')$q$),
      ('padrao_tem_pessoa', 'padrão sem pessoa',
       $q$insert into public.agenda_disponibilidade (dias_semana, situacao, origem) values ('{1}', 'disponivel', 'dono')$q$),
      ('frequencia_so_historico', 'frequência dita pelo dono',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, frequencia) values ({pessoa}, '{1}', 'disponivel', 'dono', 0.5)$q$),
      ('frequencia_so_historico', 'histórico sem frequência',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem) values ({pessoa}, '{1}', 'disponivel', 'historico')$q$),
      ('aceitou', 'padrão do dono certo',
       $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, trecho) values ({pessoa}, '{1,2,3,4,5}', 'disponivel', 'dono', 'de segunda a sexta')$q$),
      ('aceitou', 'recesso certo (todos, dia inteiro)',
       $q$insert into public.agenda_disponibilidade (periodo, situacao, origem) values ('[2026-12-28,2026-12-31]', 'indisponivel', 'dono')$q$),
      -- os_planejamento (a linha da OS de teste já existe; os casos a mudam)
      ('os_planejamento_dias_check', 'dias 0,3',
       $q$update public.os_planejamento set dias = 0.3, estimativa_fonte = 'dono' where service_order_id = {os}$q$),
      ('os_planejamento_dias_check', 'dias 61',
       $q$update public.os_planejamento set dias = 61, estimativa_fonte = 'dono' where service_order_id = {os}$q$),
      ('os_planejamento_estimativa_fonte_check', 'a sugestão gravada como fonte',
       $q$update public.os_planejamento set dias = 1, estimativa_fonte = 'sugerida' where service_order_id = {os}$q$),
      ('os_planejamento_dono_presenca_check', 'presença às vezes',
       $q$update public.os_planejamento set dono_presenca = 'as_vezes' where service_order_id = {os}$q$),
      ('os_planejamento_nao_antes_motivo_check', 'motivo de 121',
       $q$update public.os_planejamento set nao_antes_de = '2026-11-03', nao_antes_motivo = repeat('x', 121) where service_order_id = {os}$q$),
      ('os_planejamento_escopo_em_aberto_check', 'escopo em aberto de 161',
       $q$update public.os_planejamento set escopo_em_aberto = repeat('x', 161) where service_order_id = {os}$q$),
      ('os_planejamento_escopo_decidido_check', 'escopo decidido de 161',
       $q$update public.os_planejamento set escopo_decidido = repeat('x', 161) where service_order_id = {os}$q$),
      ('os_planejamento_prioridade_manual_check', 'prioridade 4',
       $q$update public.os_planejamento set prioridade_manual = 4 where service_order_id = {os}$q$),
      ('os_planejamento_trecho_check', 'trecho de 501',
       $q$update public.os_planejamento set trecho = repeat('x', 501) where service_order_id = {os}$q$),
      ('os_planejamento_historico_check', 'histórico objeto',
       $q$update public.os_planejamento set historico = '{}' where service_order_id = {os}$q$),
      ('os_planejamento_historico_check', 'histórico com 21',
       $q$update public.os_planejamento set historico = (select jsonb_agg(g) from generate_series(1, 21) g) where service_order_id = {os}$q$),
      ('fonte_coerente', 'dias sem fonte',
       $q$update public.os_planejamento set dias = 1 where service_order_id = {os}$q$),
      ('motivo_coerente', '"não antes de" sem motivo',
       $q$update public.os_planejamento set nao_antes_de = '2026-11-03' where service_order_id = {os}$q$),
      ('espera_tem_revisao', 'congelada sem revisar_em',
       $q$update public.os_planejamento set congelada_ate = '2026-11-30' where service_order_id = {os}$q$),
      ('aceitou', 'dias 1,5 ditos pelo dono',
       $q$update public.os_planejamento set dias = 1.5, estimativa_fonte = 'dono', dono_presenca = 'abre_e_fecha', bem_indisponivel = '{[2026-10-23,2026-11-03)}' where service_order_id = {os}$q$),
      -- os_planejamento_equipe
      ('os_planejamento_equipe_turnos_check', 'turno noite',
       $q$insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values ({os}, {pessoa}, 'noite')$q$),
      ('os_planejamento_equipe_pkey', 'a mesma pessoa duas vezes',
       $q$insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values ({os}, {pessoa}, 'dia'), ({os}, {pessoa}, 'tarde')$q$),
      ('os_planejamento_equipe_payee_id_fkey', 'pessoa que não existe',
       $q$insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values ({os}, gen_random_uuid(), 'dia')$q$),
      ('os_planejamento_equipe_service_order_id_fkey', 'OS sem planejamento',
       $q$insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values ({os2}, {pessoa}, 'dia')$q$),
      ('aceitou', 'a pessoa à tarde',
       $q$insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values ({os}, {pessoa}, 'tarde')$q$),
      -- os_material
      ('os_material_origem_check', 'origem chute',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria) values ({os}, 'chute', 'x', 1)$q$),
      ('os_material_descricao_check', 'descrição de 201',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria) values ({os}, 'dono', repeat('x', 201), 1)$q$),
      ('os_material_quantidade_necessaria_check', 'precisa de 0',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao) values ({os}, 'dono', 'x', 0, 'dispensado')$q$),
      ('os_material_quantidade_na_mao_check', 'na mão −1',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao) values ({os}, 'dono', 'x', 1, -1)$q$),
      ('os_material_situacao_check', 'situação perdido',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao) values ({os}, 'dono', 'x', 1, 'perdido')$q$),
      ('os_material_fonte_check', 'fonte chute',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, fonte) values ({os}, 'dono', 'x', 1, 'chute')$q$),
      ('os_material_fornecedor_nome_check', 'fornecedor de 81',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, fornecedor_nome) values ({os}, 'dono', 'x', 1, repeat('x', 81))$q$),
      ('os_material_previsao_fonte_check', 'previsão de fonte chute',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao, previsao_ate, previsao_fonte) values ({os}, 'dono', 'x', 1, 'a_caminho', '2026-11-03', 'chute')$q$),
      ('os_material_trecho_check', 'trecho de 301',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, trecho) values ({os}, 'dono', 'x', 1, repeat('x', 301))$q$),
      ('os_material_evidencia_check', 'evidência em lista',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, evidencia) values ({os}, 'dono', 'x', 1, '[]')$q$),
      ('os_material_historico_check', 'histórico objeto',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, historico) values ({os}, 'dono', 'x', 1, '{}')$q$),
      ('um_vinculo', 'peça e linha de serviço juntas',
       $q$insert into public.os_material (service_order_id, service_order_part_id, service_order_service_id, origem, descricao, quantidade_necessaria) values ({os}, {peca}, {serv}, 'peca', 'x', 1)$q$),
      ('origem_coerente', 'peça sem a peça',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria) values ({os}, 'peca', 'x', 1)$q$),
      ('origem_coerente', 'texto livre sem a linha',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria) values ({os}, 'texto_livre', 'x', 1)$q$),
      ('origem_coerente', 'OC sem o item',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria) values ({os}, 'oc', 'x', 1)$q$),
      ('origem_coerente', 'linha do dono apontando a peça',
       $q$insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria) values ({os}, {peca}, 'dono', 'x', 1)$q$),
      ('na_mao_completo', 'na mão com 1 de 2',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, situacao, chegou_em) values ({os}, 'dono', 'x', 2, 1, 'na_mao', '2026-10-14')$q$),
      ('na_mao_completo', 'na mão sem a chegada',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, situacao) values ({os}, 'dono', 'x', 1, 1, 'na_mao')$q$),
      ('quantidade_coerente', 'mais na mão do que precisa',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, situacao) values ({os}, 'dono', 'x', 2, 3, 'dispensado')$q$),
      ('completo_e_na_mao', 'quantidade completa em falta',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao) values ({os}, 'dono', 'x', 1, 1)$q$),
      ('falta_sem_previsao', 'falta com previsão',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, previsao_ate, previsao_fonte) values ({os}, 'dono', 'x', 1, '2026-11-03', 'dono')$q$),
      ('compra_prevista_so_falta', 'compra combinada de item já comprado',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao, compra_prevista_em) values ({os}, 'dono', 'x', 1, 'comprado', '2026-10-27')$q$),
      ('previsao_tem_fonte', 'previsão sem fonte',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao, previsao_ate) values ({os}, 'dono', 'x', 1, 'a_caminho', '2026-11-03')$q$),
      ('previsao_tem_fonte', 'fonte sem previsão',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao, previsao_fonte) values ({os}, 'dono', 'x', 1, 'a_caminho', 'dono')$q$),
      ('faixa_coerente', 'faixa ao contrário',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao, previsao_de, previsao_ate, previsao_fonte) values ({os}, 'dono', 'x', 1, 'a_caminho', '2026-11-10', '2026-11-05', 'dono')$q$),
      ('faixa_coerente', 'começo de faixa sem fim',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao, previsao_de) values ({os}, 'dono', 'x', 1, 'a_caminho', '2026-11-05')$q$),
      ('os_material_peca', 'a mesma peça duas vezes',
       $q$insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria) values ({os}, {peca}, 'peca', 'x', 2), ({os}, {peca}, 'peca', 'y', 2)$q$),
      ('os_material_oc', 'o mesmo item de OC duas vezes',
       $q$insert into public.os_material (service_order_id, purchase_order_item_id, origem, descricao, quantidade_necessaria) values ({os}, {poi}, 'oc', 'x', 1), ({os}, {poi}, 'oc', 'y', 1)$q$),
      ('os_material_livre', 'a mesma linha de texto livre duas vezes',
       $q$insert into public.os_material (service_order_id, service_order_service_id, origem, descricao, quantidade_necessaria) values ({os}, {serv}, 'texto_livre', 'x', 1), ({os}, {serv}, 'texto_livre', 'y', 1)$q$),
      ('os_material_fornecedor_id_fkey', 'fornecedor que não existe',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, fornecedor_id) values ({os}, 'dono', 'x', 1, gen_random_uuid())$q$),
      ('aceitou', 'peça na mão completa',
       $q$insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, situacao, chegou_em, fonte, trecho) values ({os}, {peca}, 'peca', 'x', 2, 2, 'na_mao', '2026-10-23', 'dono', 'tá aqui')$q$),
      ('aceitou', 'o dono cita duas peças embutidas na mesma linha',
       $q$insert into public.os_material (service_order_id, service_order_service_id, origem, descricao, quantidade_necessaria) values ({os}, {serv}, 'dono', 'baterias', 1), ({os}, {serv}, 'dono', 'barramento', 1)$q$),
      ('aceitou', 'compressor a caminho com faixa do dono, pode começar sem',
       $q$insert into public.os_material (service_order_id, purchase_order_item_id, origem, descricao, quantidade_necessaria, situacao, critico, previsao_de, previsao_ate, previsao_original, previsao_fonte) values ({os}, {poi}, 'oc', 'compressor', 1, 'a_caminho', false, '2026-11-03', '2026-11-05', '2026-11-03', 'dono')$q$),
      ('aceitou', 'vou comprar terça na Premel',
       $q$insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, compra_prevista_em, fornecedor_nome) values ({os}, 'dono', 'x', 1, '2026-10-27', 'Premel')$q$),
      -- agenda_rascunho
      ('agenda_rascunho_canal_check', 'canal sms',
       $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, expira_em) values ({autor}, 'sms', 'planejar', 'planejar:t', '{}', 'x', now() + interval '1 day')$q$),
      ('agenda_rascunho_tipo_check', 'tipo outro',
       $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, expira_em) values ({autor}, 'whatsapp', 'outro', 'planejar:t', '{}', 'x', now() + interval '1 day')$q$),
      ('agenda_rascunho_chave_check', 'chave de 201',
       $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, expira_em) values ({autor}, 'whatsapp', 'planejar', repeat('x', 201), '{}', 'x', now() + interval '1 day')$q$),
      ('agenda_rascunho_texto_check', 'texto de 301',
       $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, expira_em) values ({autor}, 'whatsapp', 'planejar', 'planejar:t', '{}', repeat('x', 301), now() + interval '1 day')$q$),
      ('agenda_rascunho_trecho_check', 'trecho de 501',
       $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, trecho, expira_em) values ({autor}, 'whatsapp', 'planejar', 'planejar:t', '{}', 'x', repeat('x', 501), now() + interval '1 day')$q$),
      ('agenda_rascunho_estado_check', 'estado talvez',
       $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, estado, expira_em) values ({autor}, 'whatsapp', 'planejar', 'planejar:t', '{}', 'x', 'talvez', now() + interval '1 day')$q$),
      ('expira_depois', 'expira antes de nascer',
       $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, expira_em) values ({autor}, 'whatsapp', 'planejar', 'planejar:t', '{}', 'x', now() - interval '1 hour')$q$),
      ('agenda_rascunho_um_por_chave', 'duas abertas na mesma chave',
       $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, expira_em) values ({autor}, 'whatsapp', 'planejar', 'planejar:t', '{}', 'x', now() + interval '1 day'), ({autor}, 'painel', 'planejar', 'planejar:t', '{}', 'y', now() + interval '1 day')$q$),
      ('agenda_rascunho_autor_fkey', 'autor que não existe',
       $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, expira_em) values (gen_random_uuid(), 'whatsapp', 'planejar', 'planejar:t', '{}', 'x', now() + interval '1 day')$q$),
      ('aceitou', 'a aberta e a substituída na mesma chave',
       $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, estado, expira_em) values ({autor}, 'whatsapp', 'planejar', 'planejar:t', '{}', 'x', 'aberto', now() + interval '1 day'), ({autor}, 'whatsapp', 'planejar', 'planejar:t', '{}', 'y', 'substituido', now() + interval '1 day')$q$)
    ) as c(esperado, caso, comando)
  loop
    v_cmd := replace(replace(replace(replace(replace(replace(replace(r.comando,
               '{os2}', quote_literal(v_os2)), '{os}', quote_literal(v_os)), '{peca}', quote_literal(v_peca)),
               '{serv}', quote_literal(v_serv)), '{poi}', quote_literal(v_poi)), '{pessoa}', quote_literal(v_pessoa)),
               '{autor}', quote_literal(v_autor));
    v := pg_temp.recusa(v_cmd);
    v_testados := v_testados || r.esperado;
    insert into _resultado values (
      format('B %s: %s', case when r.esperado = 'aceitou' then 'entra' else 'recusa' end, r.caso),
      v = r.esperado,
      case when v = r.esperado then r.esperado else format('esperava %s, veio %s', r.esperado, v) end);
  end loop;

  -- Nenhum CHECK das 6 tabelas ficou sem caso (um CHECK novo sem teste reprova aqui). Os que a Fase 2 acrescentou a
  -- agenda_config e os_planejamento (20261025100000) têm o caso deles em agenda_fase2_base.sql, que cobra a lista.
  select string_agg(c.conname, ', ' order by c.conname) into v_sem_caso
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
   where n.nspname = 'public' and c.contype = 'c'
     and t.relname in ('agenda_config', 'agenda_disponibilidade', 'os_planejamento', 'os_planejamento_equipe',
                       'os_material', 'agenda_rascunho')
     and not (c.conname = any (v_testados))
     and not (c.conname = any (array[
       'agenda_config_hora_do_plano_check', 'agenda_config_presenca_curta_check', 'agenda_config_desfazer_validade_check',
       'agenda_config_interrupcoes_max_check', 'agenda_config_inicios_tentados_du_check',
       'agenda_config_atraso_longo_dias_check', 'agenda_config_remarcar_confirmado_du_check',
       'agenda_config_sem_registro_du_check', 'agenda_config_backlog_minimo_semanas_check',
       'agenda_config_perguntas_vezes_max_check', 'adiantavel_coerente']))
     -- FASE 3: os 19 que a Fase 3 pôs em agenda_config (20261026100000) têm o caso deles em agenda_fase3_base.sql, que
     -- cobra a lista; sem esta linha, este teste reprovaria por um CHECK que não é da Fase 1.
     and not (c.conname = any (array[
       'agenda_config_modo_diaria_check', 'agenda_config_equipe_janela_inicio_check', 'agenda_config_equipe_janela_fim_check',
       'agenda_config_equipe_hora_ficha_check', 'agenda_config_equipe_hora_confirmar_check',
       'agenda_config_equipe_hora_como_foi_check', 'agenda_config_equipe_silencio_ate_check',
       'agenda_config_equipe_proativas_dia_max_check', 'agenda_config_equipe_respostas_dia_max_check',
       'agenda_config_equipe_resposta_validade_check', 'agenda_config_diaria_janela_dias_check',
       'agenda_config_entrega_aviso_du_check', 'agenda_config_carona_por_os_dias_check',
       'agenda_config_carteira_laranja_du_check', 'agenda_config_carteira_vermelho_du_check', 'agenda_config_ppc_meta_check',
       -- (revisão da Fase 3, C1) a janela da resposta direta (NOVO-agenda-28)
       'agenda_config_equipe_resposta_direta_inicio_check', 'agenda_config_equipe_resposta_direta_fim_check',
       'agenda_config_equipe_resposta_direta_prazo_check']));
  insert into _resultado values ('B todo CHECK das 6 tabelas tem um caso que ele recusa', v_sem_caso is null, v_sem_caso);
end
$b$;

-- ── C. Calendário ───────────────────────────────────────────────────────────────────────────────────────
do $c$
declare
  v_json jsonb := nullif(current_setting('agenda_teste.feriados', true), '')::jsonb;
  v_dias int; v_dif int; v_primeira text; v_feriados int;
begin
  if v_json is null then
    insert into _resultado values ('C1 agenda_feriado = feriados_2026_2035.json (3.652 dias)', true,
      'PULADO: sem o JSON nesta sessão; a paridade roda na bancada (node scripts/bancada-agenda/rodar.mjs)');
    return;
  end if;
  select count(*),
         count(*) filter (where public.agenda_feriado(x.d) is distinct from v_json->'feriados'->>to_char(x.d, 'YYYY-MM-DD')),
         min(to_char(x.d, 'YYYY-MM-DD')) filter (where public.agenda_feriado(x.d) is distinct from v_json->'feriados'->>to_char(x.d, 'YYYY-MM-DD')),
         count(*) filter (where public.agenda_feriado(x.d) is not null)
    into v_dias, v_dif, v_primeira, v_feriados
    from generate_series(0, (v_json->>'ate')::date - (v_json->>'de')::date) g(i)
    cross join lateral (select (v_json->>'de')::date + g.i as d) x;
  insert into _resultado values ('C1 agenda_feriado = feriados_2026_2035.json (3.652 dias)',
    v_dias = 3652 and v_dias = (v_json->>'dias')::int and v_dif = 0
      and v_feriados = (select count(*) from jsonb_object_keys(v_json->'feriados')),
    format('%s dias, %s feriados, %s diferentes%s', v_dias, v_feriados, v_dif, coalesce(' (o 1º: ' || v_primeira || ')', '')));
end
$c$;

insert into _resultado
select format('C2 %s', x.caso), x.ok, null
  from (values
    ('Páscoa de 2026, 2027 e 2028 (como em feriados_test.ts)',
     public.agenda_pascoa(2026) = date '2026-04-05' and public.agenda_pascoa(2027) = date '2027-03-28'
       and public.agenda_pascoa(2028) = date '2028-04-16'),
    ('15/06 é o aniversário de Itajaí e 20/11 é Consciência Negra',
     public.agenda_feriado('2026-06-15') = 'aniversário de Itajaí' and public.agenda_feriado('2026-11-20') = 'Consciência Negra'),
    ('Sexta-feira Santa de 2026 e 2027',
     public.agenda_feriado('2026-04-03') = 'Sexta-feira Santa' and public.agenda_feriado('2027-03-26') = 'Sexta-feira Santa'),
    ('Carnaval, Corpus Christi e o 11/08 de SC não são feriado',
     public.agenda_feriado('2026-02-16') is null and public.agenda_feriado('2026-02-17') is null
       and public.agenda_feriado('2026-06-04') is null and public.agenda_feriado('2026-08-11') is null),
    ('feriado num domingo continua com nome (15/11/2026)', public.agenda_feriado('2026-11-15') = 'Proclamação da República'),
    ('sexta 23/10 é útil; sábado, domingo, Finados e 20/11 não',
     public.agenda_dia_util('2026-10-23') and not public.agenda_dia_util('2026-10-24') and not public.agenda_dia_util('2026-10-25')
       and not public.agenda_dia_util('2026-11-02') and not public.agenda_dia_util('2026-11-20')),
    ('agenda_somar_du(23/10, 6) = ter 03/11 (pula Finados)', public.agenda_somar_du('2026-10-23', 6) = date '2026-11-03'),
    ('agenda_somar_du(23/10, 16) = ter 17/11', public.agenda_somar_du('2026-10-23', 16) = date '2026-11-17'),
    ('agenda_somar_du(23/10, 17) = qua 18/11 e (23/10, 31) = qua 09/12 (a conta da §6)',
     public.agenda_somar_du('2026-10-23', 17) = date '2026-11-18' and public.agenda_somar_du('2026-10-23', 31) = date '2026-12-09'),
    ('agenda_somar_du com 0: o dia útil, ou o próximo',
     public.agenda_somar_du('2026-10-23', 0) = date '2026-10-23' and public.agenda_somar_du('2026-10-24', 0) = date '2026-10-26'),
    ('agenda_somar_du(03/11, −1) = sex 30/10 (para trás, pula Finados)', public.agenda_somar_du('2026-11-03', -1) = date '2026-10-30'),
    ('agenda_du_entre(17/10, 23/10) = 5', public.agenda_du_entre('2026-10-17', '2026-10-23') = 5),
    ('agenda_du_entre ao contrário é negativo, no mesmo dia é 0, por cima de Finados é 1',
     public.agenda_du_entre('2026-10-23', '2026-10-17') = -5 and public.agenda_du_entre('2026-10-23', '2026-10-23') = 0
       and public.agenda_du_entre('2026-10-30', '2026-11-03') = 1)
  ) as x(caso, ok);

-- Sábado útil e recesso: só dentro desta prova (desfeitos logo em seguida).
do $c3$
declare
  v_antes boolean := (select sabado_util from public.agenda_config);
  v_sabado boolean; v_recesso boolean; v_recesso_manha boolean; v_depois date; v_id uuid; v_id2 uuid;
begin
  update public.agenda_config set sabado_util = true;
  v_sabado := public.agenda_dia_util('2026-10-24');
  update public.agenda_config set sabado_util = v_antes;
  insert into public.agenda_disponibilidade (periodo, situacao, origem, trecho)
  values ('[2026-12-28,2026-12-31]', 'indisponivel', 'dono', 'recesso de fim de ano') returning id into v_id;
  insert into public.agenda_disponibilidade (periodo, turno, situacao, origem)
  values ('[2026-12-22,2026-12-22]', 'manha', 'indisponivel', 'dono') returning id into v_id2;
  v_recesso := not public.agenda_dia_util('2026-12-29');
  v_recesso_manha := public.agenda_dia_util('2026-12-22');
  v_depois := public.agenda_somar_du('2026-12-24', 1);
  delete from public.agenda_disponibilidade where id in (v_id, v_id2);
  insert into _resultado values
    ('C3 com sabado_util, o sábado vira útil', v_sabado, null),
    ('C3 recesso (todos, dia inteiro) não é útil; meio período não tira o dia', v_recesso and v_recesso_manha, null),
    ('C3 do Natal ao recesso e ao Ano-Novo: o 1º útil depois de 24/12 é seg 04/01/2027', v_depois = date '2027-01-04',
     v_depois::text);
end
$c3$;

insert into _resultado
select format('C4 agenda_data_dita("%s", %s) = %s', x.texto, x.sentido, x.esperado),
       public.agenda_data_dita(x.texto, date '2026-10-23', x.sentido)->>'de' = x.de
         and public.agenda_data_dita(x.texto, date '2026-10-23', x.sentido)->>'ate' = x.ate,
       public.agenda_data_dita(x.texto, date '2026-10-23', x.sentido)::text
  from (values
    ('dia 3', 'futuro', '2026-11-03', '2026-11-03', 'ter 03/11'),
    ('chegou dia 14', 'passado', '2026-10-14', '2026-10-14', 'qua 14/10'),
    ('terça', 'futuro', '2026-10-27', '2026-10-27', 'ter 27/10'),
    ('terça-feira que vem', 'futuro', '2026-10-27', '2026-10-27', 'ter 27/10'),
    ('terça passada', 'futuro', '2026-10-20', '2026-10-20', 'ter 20/10'),
    ('sexta', 'futuro', '2026-10-30', '2026-10-30', 'sex 30/10 (a de hoje se diz "hoje")'),
    ('03/11', 'futuro', '2026-11-03', '2026-11-03', 'ter 03/11'),
    ('3/11/2026', 'futuro', '2026-11-03', '2026-11-03', 'ter 03/11'),
    ('15/01', 'futuro', '2027-01-15', '2027-01-15', 'sex 15/01 (o ano que fica perto de hoje)'),
    ('3 de novembro', 'futuro', '2026-11-03', '2026-11-03', 'ter 03/11'),
    ('dia três', 'futuro', '2026-11-03', '2026-11-03', 'ter 03/11'),
    ('vinte e cinco', 'futuro', '2026-10-25', '2026-10-25', 'dom 25/10'),
    ('3', 'futuro', '2026-11-03', '2026-11-03', 'ter 03/11'),
    ('dia 14', 'qualquer', '2026-10-14', '2026-10-14', 'qua 14/10 (o mais perto)'),
    ('hoje', 'futuro', '2026-10-23', '2026-10-23', 'sex 23/10'),
    ('amanhã', 'futuro', '2026-10-24', '2026-10-24', 'sáb 24/10'),
    ('depois de amanhã', 'futuro', '2026-10-25', '2026-10-25', 'dom 25/10'),
    ('ontem', 'passado', '2026-10-22', '2026-10-22', 'qui 22/10'),
    ('anteontem', 'passado', '2026-10-21', '2026-10-21', 'qua 21/10'),
    ('daqui a 2 dias úteis', 'futuro', '2026-10-27', '2026-10-27', 'ter 27/10'),
    ('daqui a 3 dias', 'futuro', '2026-10-26', '2026-10-26', 'seg 26/10'),
    ('semana que vem', 'futuro', '2026-10-26', '2026-10-30', 'seg 26/10 a sex 30/10'),
    ('quinta da semana que vem', 'futuro', '2026-10-29', '2026-10-29', 'qui 29/10'),
    ('entre 3 e 5/11', 'futuro', '2026-11-03', '2026-11-05', 'ter 03/11 a qui 05/11'),
    ('de 3 a 5 de novembro', 'futuro', '2026-11-03', '2026-11-05', 'ter 03/11 a qui 05/11'),
    ('26/10 a 30/10', 'futuro', '2026-10-26', '2026-10-30', 'seg 26/10 a sex 30/10'),
    ('de segunda a sexta', 'futuro', '2026-10-26', '2026-10-30', 'seg 26/10 a sex 30/10'),
    ('dia 3 ou 4', 'futuro', '2026-11-03', '2026-11-04', 'ter 03/11 a qua 04/11'),
    ('entre dia 28 e dia 3', 'futuro', '2026-10-28', '2026-11-03', 'qua 28/10 a ter 03/11'),
    ('até sexta', 'futuro', '2026-10-23', '2026-10-30', 'sex 23/10 a sex 30/10'),
    ('a partir de terça', 'futuro', '2026-10-27', '2026-10-27', 'ter 27/10')
  ) as x(texto, sentido, de, ate, esperado);

insert into _resultado
select format('C5 %s', x.caso), x.ok, x.detalhe
  from (values
    ('o texto sai por _dia_curto: "dia 3" = "ter 03/11"',
     public.agenda_data_dita('dia 3', '2026-10-23')->>'texto' = 'ter 03/11',
     public.agenda_data_dita('dia 3', '2026-10-23')->>'texto'),
    ('o texto da faixa: "semana que vem" = "seg 26/10 a sex 30/10"',
     public.agenda_data_dita('semana que vem', '2026-10-23')->>'texto' = 'seg 26/10 a sex 30/10',
     public.agenda_data_dita('semana que vem', '2026-10-23')->>'texto'),
    ('lixo ("xyz") é 22007 com a frase ao dono',
     pg_temp.erro_de($q$select public.agenda_data_dita('xyz', '2026-10-23')$q$)
       = '22007 Não entendi a data "xyz". Diga como "dia 3", "03/11", "terça" ou "amanhã".',
     pg_temp.erro_de($q$select public.agenda_data_dita('xyz', '2026-10-23')$q$)),
    ('data que não existe (31/02) é 22007',
     pg_temp.erro_de($q$select public.agenda_data_dita('31/02', '2026-10-23')$q$) like '22007 %',
     pg_temp.erro_de($q$select public.agenda_data_dita('31/02', '2026-10-23')$q$)),
    ('texto vazio é 22007',
     pg_temp.erro_de($q$select public.agenda_data_dita('', '2026-10-23')$q$) like '22007 %', null),
    ('"2 dias" é duração, não data: 22007',
     pg_temp.erro_de($q$select public.agenda_data_dita('2 dias', '2026-10-23')$q$) like '22007 %', null),
    ('faixa ao contrário ("30/10 a 26/10") é 22007',
     pg_temp.erro_de($q$select public.agenda_data_dita('30/10 a 26/10', '2026-10-23')$q$) like '22007 %', null),
    ('sentido fora da lista é 22023',
     pg_temp.erro_de($q$select public.agenda_data_dita('dia 3', '2026-10-23', 'ontem')$q$) like '22023 %', null),
    ('determinística: a mesma entrada dá o mesmo resultado',
     public.agenda_data_dita('entre 3 e 5/11', '2026-10-23') = public.agenda_data_dita('entre 3 e 5/11', '2026-10-23'), null)
  ) as x(caso, ok, detalhe);

insert into _resultado
select format('C6 agenda_dias_da_semana_ditos("%s") = %s', x.texto, x.esperado::text),
       public.agenda_dias_da_semana_ditos(x.texto) = x.esperado,
       public.agenda_dias_da_semana_ditos(x.texto)::text
  from (values
    ('segunda a sexta', '{1,2,3,4,5}'::smallint[]),
    ('de segunda-feira até sexta-feira', '{1,2,3,4,5}'),
    ('seg, qua e sex', '{1,3,5}'),
    ('terças e quintas', '{2,4}'),
    ('todo dia', '{1,2,3,4,5}'),
    ('dia de semana', '{1,2,3,4,5}'),
    ('sábado', '{6}'),
    ('segunda a sábado', '{1,2,3,4,5,6}'),
    ('segunda a sexta menos quarta', '{1,2,4,5}'),
    ('sexta', '{5}')
  ) as x(texto, esperado);

insert into _resultado
select format('C7 %s', x.caso), x.ok, x.detalhe
  from (values
    ('dias: nada reconhecido é 22007 com a frase ao dono',
     pg_temp.erro_de($q$select public.agenda_dias_da_semana_ditos('xyz')$q$) like '22007 Não entendi os dias "xyz"%',
     pg_temp.erro_de($q$select public.agenda_dias_da_semana_ditos('xyz')$q$)),
    ('dias: domingo é 22007',
     pg_temp.erro_de($q$select public.agenda_dias_da_semana_ditos('domingo')$q$) like '22007 Domingo%', null),
    ('_agenda_lista: 1, 2, 3 e 5 itens com teto 3',
     public._agenda_lista(array['A'], 3) = 'A' and public._agenda_lista(array['A','B'], 3) = 'A e B'
       and public._agenda_lista(array['A','B','C'], 3) = 'A, B e C'
       and public._agenda_lista(array['A','B','C','D','E'], 3) = 'A, B, C e mais 2'
       and public._agenda_lista('{}'::text[], 3) = '' and public._agenda_lista(array['A', null, '', 'B'], null) = 'A e B',
     public._agenda_lista(array['A','B','C','D','E'], 3)),
    ('_agenda_dias: meio dia, 1 dia, 1,5 dia, 2 dias',
     public._agenda_dias(0.5) = 'meio dia' and public._agenda_dias(1) = '1 dia' and public._agenda_dias(1.5) = '1,5 dia'
       and public._agenda_dias(2) = '2 dias' and public._agenda_dias(2.50) = '2,5 dias',
     null),
    ('_agenda_faixa_dias: "1,5 a 3 dias", "meio dia a 1 dia", iguais = 1 só',
     public._agenda_faixa_dias(1.5, 3) = '1,5 a 3 dias' and public._agenda_faixa_dias(0.5, 1) = 'meio dia a 1 dia'
       and public._agenda_faixa_dias(2, 2) = '2 dias' and public._agenda_faixa_dias(4.5, 9) = '4,5 a 9 dias',
     public._agenda_faixa_dias(1.5, 3)),
    ('_agenda_nome_curto: Lenine, Flávio, César, MP, Kalmar, Érica',
     public._agenda_nome_curto('LENINE LORI BROCCA') = 'Lenine' and public._agenda_nome_curto('Flávio da Igreja') = 'Flávio'
       and public._agenda_nome_curto('César – Palazzo') = 'César' and public._agenda_nome_curto('MP MOTOR HOMES') = 'MP'
       and public._agenda_nome_curto('KALMAR PERSONAL BOATS') = 'Kalmar' and public._agenda_nome_curto('ÉRICA') = 'Érica'
       and public._agenda_nome_curto(null) is null,
     public._agenda_nome_curto('ÉRICA'))
  ) as x(caso, ok, detalhe);

-- ── D. Semente de disponibilidade ───────────────────────────────────────────────────────────────────────
do $d$
declare
  v_fixture boolean := exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002')
                   and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000004');
  v_rob  constant uuid := 'bb000000-0000-4000-8000-000000000002';
  v_joao constant uuid := 'bb000000-0000-4000-8000-000000000003';
  v_mick constant uuid := 'bb000000-0000-4000-8000-000000000004';
  r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb;
  v_dono uuid;
begin
  if not v_fixture then
    -- Produção: só as regras gerais (a semente é desfeita pelo rollback do fim).
    r1 := public.agenda_disponibilidade_semear(public._hoje_brt());
    r2 := public.agenda_disponibilidade_semear(public._hoje_brt());
    insert into _resultado values
      ('D0 sem a fixture: reaplicar a semente não muda nada',
       coalesce((r2->>'semeadas')::int, 0) = 0 and coalesce((r2->>'substituidas')::int, 0) = 0, (r2 - 'linhas')::text),
      ('D0 sem a fixture: nunca sábado; toda frequência >= a mínima',
       not exists (select 1 from public.agenda_disponibilidade d, public.agenda_config c
                    where d.origem = 'historico' and d.substituida_em is null
                      and (6 = any (d.dias_semana) or d.frequencia < c.frequencia_minima)), null);
    return;
  end if;

  delete from public.agenda_disponibilidade where origem = 'historico';
  r1 := public.agenda_disponibilidade_semear(date '2026-10-23');

  insert into _resultado
  select 'D1 Roberto: 5 linhas, seg a sex, Σ 4,43', count(*) = 5 and round(sum(frequencia), 2) = 4.43
           and array_agg(dias_semana[1] order by dias_semana[1]) = '{1,2,3,4,5}'::smallint[],
         format('%s linhas, Σ %s, dias %s', count(*), sum(frequencia), array_agg(dias_semana[1] order by dias_semana[1]))
    from public.agenda_disponibilidade where payee_id = v_rob and origem = 'historico' and substituida_em is null;
  insert into _resultado
  select 'D2 João: 4 linhas, ter a sex, Σ 2,33 (segunda 0 de 1: sem linha)', count(*) = 4 and round(sum(frequencia), 2) = 2.33
           and array_agg(dias_semana[1] order by dias_semana[1]) = '{2,3,4,5}'::smallint[],
         format('%s linhas, Σ %s, dias %s', count(*), sum(frequencia), array_agg(dias_semana[1] order by dias_semana[1]))
    from public.agenda_disponibilidade where payee_id = v_joao and origem = 'historico' and substituida_em is null;
  insert into _resultado
  select 'D3 Mickael fora (última diária 18/09, fora dos 14 dias)', count(*) = 0, count(*)::text
    from public.agenda_disponibilidade where payee_id = v_mick;
  insert into _resultado
  select 'D4 frequências: Roberto seg 3/5 e ter 5/6; João ter 1,5/3 e qua 2/3',
         bool_and(case
           when payee_id = v_rob and dias_semana = '{1}' then frequencia = 0.6
           when payee_id = v_rob and dias_semana = '{2}' then frequencia = 0.8333
           when payee_id = v_joao and dias_semana = '{2}' then frequencia = 0.5
           when payee_id = v_joao and dias_semana = '{3}' then frequencia = 0.6667
           else true end),
         string_agg(dias_semana::text || '=' || frequencia, ' ' order by payee_id, dias_semana)
    from public.agenda_disponibilidade where origem = 'historico' and substituida_em is null;
  insert into _resultado
  select 'D5 equipe: Σ 6,77 diárias por semana; × carga_max = 5,41',
         round(sum(d.frequencia), 2) = 6.77 and round(sum(d.frequencia) * max(c.carga_max), 2) = 5.41,
         format('Σ %s × %s', sum(d.frequencia), max(c.carga_max))
    from public.agenda_disponibilidade d cross join public.agenda_config c
   where d.origem = 'historico' and d.substituida_em is null;
  insert into _resultado values
    ('D6 a nota diz de onde veio: Roberto às segundas',
     (select nota from public.agenda_disponibilidade where payee_id = v_rob and dias_semana = '{1}' and substituida_em is null)
       = 'semente: 3 de 5 segundas (8 semanas até 17/10)',
     (select nota from public.agenda_disponibilidade where payee_id = v_rob and dias_semana = '{1}' and substituida_em is null)),
    ('D6 a nota diz de onde veio: João às terças',
     (select nota from public.agenda_disponibilidade where payee_id = v_joao and dias_semana = '{2}' and substituida_em is null)
       = 'semente: 1,5 de 3 terças (8 semanas até 17/10)',
     (select nota from public.agenda_disponibilidade where payee_id = v_joao and dias_semana = '{2}' and substituida_em is null)),
    ('D7 sábado nunca entra (os dois trabalharam sáb 17/10)',
     not exists (select 1 from public.agenda_disponibilidade where origem = 'historico' and 6 = any (dias_semana)), null),
    ('D7 linhas da semente: dia inteiro, disponível, um dia por linha',
     not exists (select 1 from public.agenda_disponibilidade where origem = 'historico'
                  and (turno is not null or situacao <> 'disponivel' or cardinality(dias_semana) <> 1 or periodo is not null)), null),
    ('D8 o retorno: 9 semeadas, janela 24/08 a 17/10',
     (r1->>'semeadas')::int = 9 and r1->'janela'->>'de' = '2026-08-24' and r1->'janela'->>'ate' = '2026-10-17'
       and r1->>'ultima_diaria' = '2026-10-17',
     (r1 - 'linhas')::text);

  -- Reaplicar não duplica nem troca nada.
  r2 := public.agenda_disponibilidade_semear(date '2026-10-23');
  insert into _resultado values
    ('D9 reaplicar não duplica: 0 semeadas, 0 trocadas, 2 mantidas, 9 linhas no total',
     (r2->>'semeadas')::int = 0 and (r2->>'substituidas')::int = 0 and (r2->>'mantidas')::int = 2
       and (select count(*) from public.agenda_disponibilidade where origem = 'historico') = 9,
     (r2 - 'linhas')::text);

  -- Mudou a diária de uma pessoa: só ela é trocada; quem saiu perde a linha velha; a do dono fica.
  insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, trecho)
  values (v_rob, '{6}', 'disponivel', 'dono', 'sábado, quando eu pedir') returning id into v_dono;
  insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, frequencia, nota)
  values (v_mick, '{2}', 'disponivel', 'historico', 0.5, 'semente antiga');
  delete from public.work_shifts where id = md5('ws:cc000000-0000-4000-8000-000000000002:2026-10-05')::uuid;
  r3 := public.agenda_disponibilidade_semear(date '2026-10-23');
  insert into _resultado values
    ('D10 a diária de 05/10 do Roberto some: ele é trocado (5 + a velha do Mickael), o João fica',
     (r3->>'semeadas')::int = 5 and (r3->>'substituidas')::int = 6 and (r3->>'mantidas')::int = 1,
     (r3 - 'linhas')::text),
    ('D10 Roberto às segundas vira 2 de 5 (0,4)',
     (select frequencia from public.agenda_disponibilidade where payee_id = v_rob and dias_semana = '{1}'
         and origem = 'historico' and substituida_em is null) = 0.4,
     (select frequencia::text from public.agenda_disponibilidade where payee_id = v_rob and dias_semana = '{1}'
         and origem = 'historico' and substituida_em is null)),
    ('D10 a linha do dono não é tocada',
     (select substituida_em is null and origem = 'dono' from public.agenda_disponibilidade where id = v_dono), null),
    ('D10 o Mickael não tem mais linha vigente; o rastro fica',
     not exists (select 1 from public.agenda_disponibilidade where payee_id = v_mick and substituida_em is null)
       and exists (select 1 from public.agenda_disponibilidade where payee_id = v_mick and substituida_em is not null), null);

  -- Antes de qualquer diária: não semeia.
  r4 := public.agenda_disponibilidade_semear(date '2026-01-01');
  insert into _resultado values
    ('D11 sem diárias até o dia: não semeia', (r4->>'semeadas')::int = 0 and r4->>'motivo' = 'sem diárias', r4::text);
end
$d$;

-- ── E. Portas das funções ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'E1 nenhuma função agenda_*/_agenda_* executável por anon',
       count(*) filter (where has_function_privilege('anon', p.oid, 'execute')) = 0 and count(*) >= 19,
       format('%s funções; com anon: %s', count(*),
              coalesce(string_agg(p.oid::regprocedure::text, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')), '—'))
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname ~ '^_?agenda_';

insert into _resultado
select 'E2 o calendário e os textos executam para authenticated e service_role',
       bool_and(has_function_privilege('authenticated', f::regprocedure, 'execute')
                and has_function_privilege('service_role', f::regprocedure, 'execute')),
       string_agg(f, ', ') filter (where not has_function_privilege('authenticated', f::regprocedure, 'execute'))
  from unnest(array[
    'public.agenda_pascoa(integer)', 'public.agenda_feriado(date)', 'public._agenda_cfg()', 'public.agenda_dia_util(date)',
    'public.agenda_somar_du(date,integer)', 'public.agenda_du_entre(date,date)', 'public._agenda_normal(text)',
    'public._agenda_preparar_data(text)', 'public._agenda_data_valida(integer,integer,integer)',
    'public._agenda_isodow_dito(text)', 'public._agenda_data_um(text,date,text,boolean,date,date)',
    'public.agenda_data_dita(text,date,text)', 'public._agenda_dias_ditos_parte(text)',
    'public.agenda_dias_da_semana_ditos(text)', 'public._agenda_lista(text[],integer)', 'public._agenda_dias(numeric)',
    'public._agenda_faixa_dias(numeric,numeric)', 'public._agenda_nome_curto(text)']) f;

insert into _resultado values
  ('E3 a semente só para service_role',
   not has_function_privilege('authenticated', 'public.agenda_disponibilidade_semear(date)', 'execute')
   and not has_function_privilege('anon', 'public.agenda_disponibilidade_semear(date)', 'execute')
   and has_function_privilege('service_role', 'public.agenda_disponibilidade_semear(date)', 'execute'), null),
  ('E4 _dia_curto para authenticated, nunca anon',
   has_function_privilege('authenticated', 'public._dia_curto(date)', 'execute')
   and not has_function_privilege('anon', 'public._dia_curto(date)', 'execute'), null);

-- Security definer só quem ESCREVE: a semente (P1) e, a partir do P5 (20261024160600), o rascunho e o *grava* (as RPCs
-- conferem o cargo em _autor_da_agenda; as _agenda_aplicar_* e o salvar são só de service_role). Leitura nunca.
-- A Fase 2 acrescenta as suas (cada pacote põe aqui as que criar; agenda_fase2_base.sql prova as portas delas):
--   20261025100000 — _agenda_payees_do_login (a policy do técnico atravessa payees, que é fechada para ele);
--   20261025100100 — _agenda_escrever_os (a única que liga a chave das datas) e _agenda_espelhar_datas;
--   20261025100200 — o motor que grava: agenda_propor, agenda_aplicar, agenda_descartar, agenda_desfazer,
--                    agenda_marcar_os (confere o administrador dentro) e agenda_decidir. As leituras do motor não;
--   20261025100300 — a conferência e a vigia: agenda_registrar_dia, agenda_conferir_dia, agenda_choveu,
--                    agenda_desfazer_dito (conferem o administrador dentro), agenda_replanejar, agenda_vigiar,
--                    agenda_fechamento_registrar e agenda_acorde_registrado. Os passos da vigia e a agenda_saude não;
--   20261025100400 — os pedidos da conversa: agenda_rascunho_marcar, agenda_rascunho_aplicar, agenda_rascunho_desfazer,
--                    agenda_rascunho_andamento e agenda_propor_dito (conferem o administrador dentro). A numeração
--                    (agenda_decisoes_abertas, agenda_propostas_abertas) e o _agenda_aplicar_pedido não;
--   20261025100500 — as leituras: _agenda_pessoa e _agenda_payees_do_usuario (só devolvem o nome e os payees que quem
--                    lê pode ver: payees é fechada para o técnico). As leituras e os textos não.
-- FASE 3: a Fase 3 acrescenta as suas (agenda_fase3_conclusao.sql prova as portas delas):
--   20261026100100 — _agenda_escrever_conclusao (a segunda que liga a chave agenda.porta) e _agenda_desfazer_marco (o
--                    desfazer da conclusão e da entrega). A leitura dos marcos (agenda_marcos_da_os) não.
--   20261026100200 — as palavras *concluiu* e *entreguei*: agenda_concluir_dito e agenda_entregar_dito (conferem o
--                    administrador dentro). A releitura (_agenda_rascunho_marco), a OS da entrega e os textos não.
--   20261026100300 — a rotina da equipe e a diária: agenda_equipe_ficha (lê as alocações para o webhook), a resposta
--                    da equipe, a rotina, a palavra *diária* (confere o administrador dentro), o envio à equipe
--                    (_agenda_equipe_registrar, _agenda_equipe_enfileirar), a trava da fila (_agenda_fila_da_equipe,
--                    gatilho) e a diária (_agenda_diaria_do_dia, _agenda_lancar_diaria, _agenda_decidir_diaria,
--                    _agenda_desfazer_diaria). Os textos, a leitura da resposta, a confirmação do dia e os passos não.
create temp table _definer_da_agenda (nome text primary key) on commit drop;
insert into _definer_da_agenda values
  ('agenda_disponibilidade_semear'), ('agenda_rascunho_planejar'), ('agenda_rascunho_material'),
  ('agenda_rascunho_disponibilidade'), ('agenda_rascunho_ler'), ('agenda_rascunho_gravar'), ('agenda_rascunho_descartar'),
  ('_agenda_rascunho_salvar'), ('_agenda_aplicar_planejar'), ('_agenda_aplicar_material'),
  ('_agenda_aplicar_disponibilidade'),
  -- Fase 2
  ('_agenda_payees_do_login'), ('_agenda_escrever_os'), ('_agenda_espelhar_datas'),
  ('agenda_propor'), ('agenda_aplicar'), ('agenda_descartar'), ('agenda_desfazer'), ('agenda_marcar_os'), ('agenda_decidir'),
  ('agenda_registrar_dia'), ('agenda_conferir_dia'), ('agenda_choveu'), ('agenda_desfazer_dito'), ('agenda_replanejar'),
  ('agenda_vigiar'), ('agenda_fechamento_registrar'), ('agenda_acorde_registrado'),
  ('agenda_rascunho_marcar'), ('agenda_rascunho_aplicar'), ('agenda_rascunho_desfazer'), ('agenda_rascunho_andamento'),
  ('agenda_propor_dito'),
  ('_agenda_pessoa'), ('_agenda_payees_do_usuario'),
  -- FASE 3
  ('_agenda_escrever_conclusao'), ('_agenda_desfazer_marco'),
  ('agenda_concluir_dito'), ('agenda_entregar_dito'),
  ('agenda_equipe_ficha'), ('agenda_resposta_da_equipe'), ('agenda_rotina_rodar'), ('agenda_diaria_dita'),
  ('_agenda_equipe_registrar'), ('_agenda_equipe_enfileirar'), ('_agenda_fila_da_equipe'),
  ('_agenda_diaria_do_dia'), ('_agenda_lancar_diaria'), ('_agenda_decidir_diaria'), ('_agenda_desfazer_diaria'),
  -- FASE 3 (P6): a simulação do livre de verdade (chama o motor, que é só do service_role) e a carona (marca carona_em)
  ('agenda_livre_de_verdade'), ('agenda_carona'),
  -- FASE 3 (P7a): as leituras das telas (conferem o administrador e leem o plano, as alocações e a equipe inteiros) e o
  -- Desfazer da tela (chama agenda_desfazer, que é só do service_role)
  ('agenda_tela_semana'), ('agenda_tela_carteira'), ('agenda_equipe_da_grade'), ('agenda_desfazer_pela_tela');

insert into _resultado
select 'E5 security definer só a semente e as escritas do rascunho (P5) e as da Fase 2; todas com search_path fixo',
       bool_and(p.prosecdef = (p.proname in (select nome from _definer_da_agenda)))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(p.proname, ', ') filter (where p.prosecdef <> (p.proname in (select nome from _definer_da_agenda))
                                              or p.proconfig is null)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname ~ '^_?agenda_';

select teste, ok, detalhe from _resultado order by teste;

rollback;
