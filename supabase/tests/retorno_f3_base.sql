-- Retorno F3 (P1): configuração, checks, tabelas novas e colunas fechadas ao anônimo. Roda só pela bancada (grupo 5).
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000092xx; nomes e frases inventados.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Roda p_sql e devolve 'passou' (desfazendo o que fez) ou 'SQLSTATE:restrição' do erro.
create or replace function pg_temp.retorno_f3_base_erro(p_sql text) returns text
language plpgsql as $f$
declare
  v_estado text;
  v_restricao text;
begin
  begin
    execute p_sql;
    raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_restricao = constraint_name;
    if v_estado = 'P0001' and sqlerrm = 'retorno_f3_desfaz' then
      return 'passou';
    end if;
    return v_estado || ':' || coalesce(nullif(v_restricao, ''), '-');
  end;
end $f$;

-- Roda p_sql (um select de uma coluna) como p_papel, com o login p_uid; devolve o valor ou 'erro SQLSTATE'.
create or replace function pg_temp.retorno_f3_base_como(p_papel text, p_uid uuid, p_sql text) returns text
language plpgsql as $f$
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
    v := 'erro ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

do $base$
declare
  c_sem_cargo constant uuid := 'b1600000-0000-4000-8000-0000000009f2';
  c_fone constant text := '5547900009201';
  c_chave constant text := '00009201';
  v_cfg public.retorno_config;
  v text;
  v_msg uuid;
  v_msg2 uuid;
  v_abertura uuid;
  v_abertura2 uuid;
  v_cartao uuid;
  v_cliente uuid;
  v_unidade uuid;
  v_unidade_apagar uuid;
  v_os uuid;
  v_previa uuid;
  v_preenchida uuid;
  v_ins_previa text;
  v_motivo text;
begin
  begin
  -- Arranjo: uma mensagem, um caso e um cartão vivo. Número inventado; o bloco desfaz tudo.
  insert into public.clients (type, name) values ('individual', 'Paulo Base F3 Teste') returning id into v_cliente;
  insert into public.vessels (client_id, name, asset_type) values (v_cliente, 'Brisa Base F3', 'Lancha') returning id into v_unidade;
  insert into public.vessels (client_id, name, asset_type) values (v_cliente, 'Sumidouro F3', 'Lancha') returning id into v_unidade_apagar;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, grand_total)
    values ('ORÇ-TF3-BASE', v_cliente, v_unidade, 'draft', 'draft', 'repair', 100) returning id into v_os;
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
    values ('inbound', c_fone, 'text', 'mensagem de teste um', 'teste-f3-base-1', '2026-12-08 09:00-03') returning id into v_msg;
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
    values ('inbound', '5547900009202', 'text', 'mensagem de teste dois', 'teste-f3-base-2', '2026-12-08 09:00-03') returning id into v_msg2;
  insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, client_id, primeira_msg_id, aberta_em, gravada_em,
                                        ultima_em, ultima_gravada_em, nivel, modo)
    values (c_chave, c_fone, 'cliente', '{"papel": "cliente"}', v_cliente, v_msg, '2026-12-08 09:00-03', '2026-12-08 09:00-03',
            '2026-12-08 09:00-03', '2026-12-08 09:00-03', 'recibo', 'sombra')
    returning id into v_abertura;
  insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, primeira_msg_id, aberta_em, gravada_em,
                                        ultima_em, ultima_gravada_em, nivel, modo)
    values ('00009202', '5547900009202', 'cliente', '{"papel": "cliente"}', v_msg2, '2026-12-08 09:00-03', '2026-12-08 09:00-03',
            '2026-12-08 09:00-03', '2026-12-08 09:00-03', 'recibo', 'sombra')
    returning id into v_abertura2;
  insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
    values ('puxar', '2026-12-08', 'vivo', 'h-f3', 'cartão', '2026-12-09 09:00-03') returning id into v_cartao;
  insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, hash)
    values (v_cartao, 1, v_abertura, 'orcamento', 'i-f3');

  -- 1. Os padrões. Tudo nasce desligado e a proposta exige o ditado ligado.
  -- 12/11/2026: "nasce desligada" se confere no PADRÃO das colunas, numa linha nova de uma cópia da tabela: a linha real
  -- muda quando o dono liga as chaves (11/11: cartão e carona ligados; prévia em sombra), e o teste não pode depender disso.
  create temp table if not exists _retorno_cfg_padrao_f3 (like public.retorno_config including defaults);
  truncate _retorno_cfg_padrao_f3;
  insert into _retorno_cfg_padrao_f3 default values;
  select * into v_cfg from _retorno_cfg_padrao_f3;
  if v_cfg.previa_modo is distinct from 'desligado' or v_cfg.previa_ditado_ligado then
    raise exception '1a: a proposta não nasceu desligada';
  end if;
  if v_cfg.validade_orcamento_dias is distinct from 7 or v_cfg.previa_max_linhas is distinct from 12
     or v_cfg.previa_idade_max is distinct from interval '18 months' or v_cfg.previa_preco_velho is distinct from interval '180 days' then
    raise exception '1b: padrão diferente do combinado';
  end if;
  v := pg_temp.retorno_f3_base_erro($q$update public.retorno_config set previa_modo = 'ligado'$q$);
  if v is distinct from '23514:retorno_config_proposta_exige_ditado' then
    raise exception '1c: proposta ligada sem o ditado passou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro($q$update public.retorno_config set previa_modo = 'ligado', previa_ditado_ligado = true$q$);
  if v is distinct from 'passou' then
    raise exception '1d: proposta ligada com o ditado falhou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro($q$update public.retorno_config set validade_orcamento_dias = 0$q$);
  if v is distinct from '23514:retorno_config_validade_orcamento_dias_check' then
    raise exception '1e: validade 0 passou (%)', v;
  end if;

  -- 2. Os checks novos.
  v := pg_temp.retorno_f3_base_erro($q$update public.retorno_config set previa_modo = 'sim'$q$);
  if v is distinct from '23514:retorno_config_previa_modo_check' then
    raise exception '2a: previa_modo inválido passou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro(format($q$insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                              values (%L, 'modelo_ver_no_local', 'retorno_modelo', 'resposta_imediata', %L, %L, 'sombra', '2026-12-08 09:05-03', 'teste-f3-base:2b')$q$,
                                           v_abertura, c_chave, c_fone));
  if v is distinct from 'passou' then
    raise exception '2b: tipo modelo_ver_no_local falhou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro(format($q$insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, modo, estado, motivo, enviar_em, dedupe_key)
                                              values (%L, 'recibo_cliente', %L, %L, 'sombra', 'cancelada', 'visita_a_combinar', '2026-12-08 09:05-03', 'teste-f3-base:2c')$q$,
                                           v_abertura, c_chave, c_fone));
  if v is distinct from 'passou' then
    raise exception '2c: motivo visita_a_combinar falhou (%)', v;
  end if;
  -- O check antigo segue fechado para o que não está na lista.
  v := pg_temp.retorno_f3_base_erro(format($q$insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                              values (%L, 'tipo_que_nao_existe', %L, %L, 'sombra', '2026-12-08 09:05-03', 'teste-f3-base:2d')$q$,
                                           v_abertura, c_chave, c_fone));
  if v is distinct from '23514:retorno_saidas_tipo_check' then
    raise exception '2d: tipo fora da lista passou (%)', v;
  end if;
  foreach v_motivo in array array['item_provisorio', 'sem_cadastro', 'contato_diferente', 'orc_existe', 'cliente_final', 'rascunho_sem_valor'] loop
    v := pg_temp.retorno_f3_base_erro(format($q$update public.retorno_cartao_itens set estado = 'caiu', caiu_motivo = %L where abertura_id = %L$q$, v_motivo, v_abertura));
    if v is distinct from 'passou' then
      raise exception '2e: caiu_motivo % falhou (%)', v_motivo, v;
    end if;
  end loop;
  v := pg_temp.retorno_f3_base_erro(format($q$update public.retorno_cartao_itens set estado = 'caiu', caiu_motivo = 'motivo_que_nao_existe' where abertura_id = %L$q$, v_abertura));
  if v is distinct from '23514:retorno_cartao_itens_caiu_motivo_check' then
    raise exception '2f: caiu_motivo fora da lista passou (%)', v;
  end if;

  -- 3. A proposta: um estado de cada por caso, preço zero recusado, coluna do item.
  v_ins_previa := $q$insert into public.retorno_previa (abertura_id, chave, origem, titulo, estado, modo, hash)
                     values (%L, %L, 'historico', 'Baterias', %L, %L, md5(random()::text))$q$;
  insert into public.retorno_previa (abertura_id, chave, origem, titulo, estado, modo, hash)
    values (v_abertura, c_chave, 'historico', 'Baterias', 'proposta', 'ligado', 'h1') returning id into v_previa;
  v := pg_temp.retorno_f3_base_erro(format(v_ins_previa, v_abertura, c_chave, 'proposta', 'ligado'));
  if v is distinct from '23505:retorno_previa_uma_proposta' then
    raise exception '3a: duas propostas no mesmo caso passaram (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro(format(v_ins_previa, v_abertura2, '00009202', 'sombra', 'sombra'));
  if v is distinct from 'passou' then
    raise exception '3b: sombra em outro caso falhou (%)', v;
  end if;
  insert into public.retorno_previa (abertura_id, chave, origem, titulo, estado, modo, hash)
    values (v_abertura2, '00009202', 'historico', 'Baterias', 'sombra', 'sombra', 'h2');
  v := pg_temp.retorno_f3_base_erro(format(v_ins_previa, v_abertura2, '00009202', 'sombra', 'sombra'));
  if v is distinct from '23505:retorno_previa_uma_sombra' then
    raise exception '3c: duas sombras no mesmo caso passaram (%)', v;
  end if;
  -- Sombra e proposta do mesmo caso convivem (ditado na semana de sombra, P6.2).
  v := pg_temp.retorno_f3_base_erro(format(v_ins_previa, v_abertura, c_chave, 'sombra', 'sombra'));
  if v is distinct from 'passou' then
    raise exception '3d: 1 sombra e 1 proposta do mesmo caso não conviveram (%)', v;
  end if;
  -- Descartada não conta para os índices.
  v := pg_temp.retorno_f3_base_erro(format(v_ins_previa, v_abertura, c_chave, 'descartada', 'ligado'));
  if v is distinct from 'passou' then
    raise exception '3e: descartada ao lado de uma viva falhou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro(format($q$insert into public.retorno_previa (abertura_id, chave, origem, titulo, estado, modo, hash)
                                              values (%L, '123', 'historico', 'Baterias', 'descartada', 'ligado', 'h')$q$, v_abertura));
  if v is distinct from '23514:retorno_previa_chave_check' then
    raise exception '3f: chave inválida passou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro(format($q$insert into public.retorno_previa (abertura_id, chave, origem, titulo, estado, modo, hash)
                                              values (%L, %L, 'outra', 'Baterias', 'descartada', 'ligado', 'h')$q$, v_abertura, c_chave));
  if v is distinct from '23514:retorno_previa_origem_check' then
    raise exception '3g: origem fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro(format($q$insert into public.retorno_previa_linhas (previa_id, ordem, tipo, nome, quantidade, preco, preco_fonte, estado)
                                              values (%L, 1, 'peca', 'Bateria', 1, 0, 'dito', 'ok')$q$, v_previa));
  if v is distinct from '23514:retorno_previa_linhas_preco_check' then
    raise exception '3h: preço zero passou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro(format($q$insert into public.retorno_previa_linhas (previa_id, ordem, tipo, nome, quantidade, preco, preco_fonte, estado)
                                              values (%L, 1, 'peca', 'Bateria', 1, null, 'sem_preco', 'provisorio')$q$, v_previa));
  if v is distinct from 'passou' then
    raise exception '3i: linha sem preço falhou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro(format($q$update public.retorno_cartao_itens set previa_id = %L, acao_sim = 'orcar' where abertura_id = %L$q$, v_previa, v_abertura));
  if v is distinct from 'passou' then
    raise exception '3j: previa_id + acao_sim falhou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro(format($q$update public.retorno_cartao_itens set acao_sim = 'outra' where abertura_id = %L$q$, v_abertura));
  if v is distinct from '23514:retorno_cartao_itens_acao_sim_check' then
    raise exception '3k: acao_sim fora da lista passou (%)', v;
  end if;

  -- 4. Grants: duas tabelas fechadas ao anônimo; colunas novas de service_orders fechadas; quem não é admin nem financeiro lê zero.
  v := pg_temp.retorno_f3_base_como('anon', null, $q$select count(*)::text from public.retorno_previa$q$);
  if v is distinct from 'erro 42501' then
    raise exception '4a: anon leu retorno_previa (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_como('anon', null, $q$select count(*)::text from public.retorno_previa_linhas$q$);
  if v is distinct from 'erro 42501' then
    raise exception '4b: anon leu retorno_previa_linhas (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_como('anon', null, $q$select origem from public.service_orders limit 1$q$);
  if v is distinct from 'erro 42501' then
    raise exception '4c: anon leu service_orders.origem (%)', v;
  end if;
  if has_column_privilege('anon', 'public.service_orders', 'origem', 'select')
     or has_column_privilege('anon', 'public.service_orders', 'origem_chave8', 'select')
     or has_column_privilege('anon', 'public.service_orders', 'origem_parceiro_id', 'select') then
    raise exception '4d: anon lê as colunas de origem';
  end if;
  v := pg_temp.retorno_f3_base_como('authenticated', c_sem_cargo, $q$select count(*)::text from public.retorno_previa$q$);
  if v is distinct from '0' then
    raise exception '4e: login sem cargo leu retorno_previa (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_como('authenticated', c_sem_cargo, $q$select count(*)::text from public.retorno_previa_linhas$q$);
  if v is distinct from '0' then
    raise exception '4f: login sem cargo leu retorno_previa_linhas (%)', v;
  end if;

  -- 5. Rastro em service_orders: 7 dígitos recusa, 8 dígitos passa, origem fora da lista recusa.
  v := pg_temp.retorno_f3_base_erro(format($q$update public.service_orders set origem_chave8 = '1234567' where id = %L$q$, v_os));
  if v is distinct from '23514:service_orders_origem_chave8_check' then
    raise exception '5a: origem_chave8 de 7 dígitos passou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro(format($q$update public.service_orders set origem_chave8 = '12345678', origem = 'retorno_previa' where id = %L$q$, v_os));
  if v is distinct from 'passou' then
    raise exception '5b: origem_chave8 de 8 dígitos falhou (%)', v;
  end if;
  v := pg_temp.retorno_f3_base_erro(format($q$update public.service_orders set origem = 'tela' where id = %L$q$, v_os));
  if v is distinct from '23514:service_orders_origem_check' then
    raise exception '5c: origem fora da lista passou (%)', v;
  end if;

  -- 6. A unidade do caso: nasce nula e volta a nula quando a unidade é apagada.
  select unidade_escolhida_id, visita_a_combinar_em into v_preenchida, v from public.retorno_aberturas where id = v_abertura;
  if v_preenchida is not null or v is not null then
    raise exception '6a: as colunas novas do caso não nasceram nulas';
  end if;
  update public.retorno_aberturas set unidade_escolhida_id = v_unidade_apagar where id = v_abertura;
  delete from public.vessels where id = v_unidade_apagar;
  select unidade_escolhida_id into v_preenchida from public.retorno_aberturas where id = v_abertura;
  if v_preenchida is not null then
    raise exception '6b: a unidade apagada ficou no caso';
  end if;

  raise exception 'retorno_f3_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f3_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f3_base', true, '{}');
end
$base$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
