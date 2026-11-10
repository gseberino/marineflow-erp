-- Retorno F4 (P1): configuração, checks, tabelas do parceiro, FK de origem_parceiro_id e a porta da fila. Roda só pela
-- bancada (grupo 7, F4_ONDA=1). Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000140xx;
-- nomes, siglas e frases inventados.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Roda p_sql e devolve 'passou' (desfazendo o que fez) ou 'SQLSTATE:restrição' do erro.
create or replace function pg_temp.retorno_f4_base_erro(p_sql text) returns text
language plpgsql as $f$
declare
  v_estado text;
  v_restricao text;
begin
  begin
    execute p_sql;
    raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_restricao = constraint_name;
    if v_estado = 'P0001' and sqlerrm = 'retorno_f4_desfaz' then
      return 'passou';
    end if;
    return v_estado || ':' || coalesce(nullif(v_restricao, ''), '-');
  end;
end $f$;

-- Roda p_sql (um select de uma coluna) como p_papel, com o login p_uid; devolve o valor ou 'erro SQLSTATE'.
create or replace function pg_temp.retorno_f4_base_como(p_papel text, p_uid uuid, p_sql text) returns text
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
  c_sem_cargo constant uuid := 'b1600000-0000-4000-8000-0000000014f2';
  c_fone constant text := '5547900014001';
  c_chave constant text := '00014001';
  c_tabelas constant text[] := array['parceiros', 'parceiro_pessoas', 'parceiro_numeros', 'os_interessados', 'parceiro_vetos',
                                     'parceiro_cliente_sabe', 'parceiro_paineis', 'parceiro_fila', 'parceiro_pedidos'];
  c_tipos constant text[] := array['parceiro_ativacao', 'parceiro_recibo', 'parceiro_coleta', 'parceiro_aviso_cliente',
                                   'parceiro_nao_mp_ok', 'parceiro_painel', 'parceiro_patio', 'parceiro_eco', 'parceiro_pausa',
                                   'parceiro_repassar', 'parceiro_recado'];
  c_motivos constant text[] := array['parceiro_regra', 'veto', 'pausado', 'segura_patio', 'teto_iniciadas', 'teto_painel',
                                     'teto_eco', 'teto_patio', 'parceiro_desligado', 'cliente_nao_ouviu', 'numero_compartilhado'];
  v_cfg public.retorno_config;
  v text;
  v_tab text;
  v_tipo text;
  v_motivo text;
  v_msg uuid;
  v_abertura uuid;
  v_abertura2 uuid;
  v_cliente uuid;
  v_unidade uuid;
  v_os uuid;
  v_os2 uuid;
  v_parceiro uuid;
  v_parceiro_apagar uuid;
  v_pessoa uuid;
  v_pessoa2 uuid;
  v_id uuid;
  v_id2 uuid;
  v_n integer;
  v_r record;
  v_n_rel integer := 0;
  v_n_fun integer := 0;
begin
  begin
  -- Arranjo: um cliente com unidade e duas OS, uma mensagem e dois casos, um parceiro com uma pessoa. Tudo inventado.
  insert into public.clients (type, name) values ('individual', 'Paulo Base F4 Teste') returning id into v_cliente;
  insert into public.vessels (client_id, name, asset_type) values (v_cliente, 'Estrada Base F4', 'Motorhome') returning id into v_unidade;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, grand_total)
    values ('ORÇ-TF4-BASE1', v_cliente, v_unidade, 'draft', 'draft', 'repair', 100) returning id into v_os;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, grand_total)
    values ('ORÇ-TF4-BASE2', v_cliente, v_unidade, 'draft', 'draft', 'repair', 100) returning id into v_os2;
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at, hora_real)
    values ('inbound', c_fone, 'text', 'mensagem de teste um', 'teste-f4-base-1', '2027-01-05 09:00-03', '2027-01-05 09:00-03') returning id into v_msg;
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Base F4', 'RBF', 'revenda_e_patio') returning id into v_parceiro;
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Apagar F4', 'RAF', 'revenda') returning id into v_parceiro_apagar;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_parceiro, 'Carla', 'comercial') returning id into v_pessoa;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_parceiro, null, 'comercial') returning id into v_pessoa2;

  -- 1. Os padrões: tudo nasce desligado ou no padrão seguro.
  select * into v_cfg from public.retorno_config;
  if v_cfg.parceiro_modo is distinct from 'desligado' or v_cfg.pdf_parceiro_ligado is not false
     or v_cfg.segura_patio is not false or v_cfg.painel_nivel is distinct from 'fechamento'
     or v_cfg.patio_nivel is distinct from 'cartao' or v_cfg.eco_modo is distinct from 'sombra' then
    raise exception '1a: um interruptor do parceiro não nasceu no padrão seguro';
  end if;
  if v_cfg.parceiro_carencia is distinct from interval '30 minutes' or v_cfg.parceiro_aviso_espera is distinct from interval '24 hours'
     or v_cfg.iniciadas_dia_max is distinct from 12 then
    raise exception '1b: carência, espera ou teto de iniciadas diferente do combinado';
  end if;
  if v_cfg.parceiro_tipos_ligados is distinct from '{}'::text[] or v_cfg.pdf_sem_espera_ligado is not false
     or v_cfg.parceiro_historico_na_ia is not false or v_cfg.parceiro_pdf_ate is not null then
    raise exception '1c: tipo ligado, PDF sem espera, histórico na IA ou marca do PDF nasceu fora do padrão';
  end if;
  if v_cfg.painel_fechamento_hora is distinct from time '17:30' or v_cfg.painel_hora is distinct from time '17:45'
     or v_cfg.painel_janela_fim is distinct from time '18:30' or v_cfg.painel_dia_max is distinct from 2
     or v_cfg.eco_dia_max is distinct from 2 or v_cfg.patio_dia_max is distinct from 3
     or v_cfg.patio_recibo_intervalo is distinct from interval '12 hours'
     or v_cfg.parceiro_rodape_intervalo is distinct from interval '7 days'
     or v_cfg.parceiro_retencao is distinct from interval '180 days' or v_cfg.painel_promover_apos is distinct from 10 then
    raise exception '1d: horas, tetos ou retenção diferentes do combinado';
  end if;

  -- 2. Os checks.
  v := pg_temp.retorno_f4_base_erro($q$update public.retorno_config set parceiro_modo = 'meio'$q$);
  if v is distinct from '23514:retorno_config_parceiro_modo_check' then
    raise exception '2a: parceiro_modo inválido passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro($q$update public.retorno_config set parceiro_tipos_ligados = array['parceiro_inventado']$q$);
  if v is distinct from '23514:retorno_config_parceiro_tipos_ligados_check' then
    raise exception '2b: tipo ligado fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro($q$update public.retorno_config set parceiro_modo = 'ligado', parceiro_tipos_ligados = array['parceiro_recibo', 'parceiro_painel']$q$);
  if v is distinct from 'passou' then
    raise exception '2c: ligar dois tipos da lista falhou (%)', v;
  end if;
  -- emissor 'parceiro', os 11 tipos, as origens e as classes novas.
  foreach v_tipo in array c_tipos loop
    v := pg_temp.retorno_f4_base_erro(format($q$insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                                values ('parceiro', %L, 'retorno_parceiro', 'resposta_imediata', %L, %L, 'sombra', '2027-01-05 09:30-03', %L)$q$,
                                             v_tipo, c_chave, c_fone, 'teste-f4-base:2d:' || v_tipo));
    if v is distinct from 'passou' then
      raise exception '2d: tipo % com emissor parceiro falhou (%)', v_tipo, v;
    end if;
  end loop;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                              values ('parceiro', 'parceiro_aviso_cliente', 'retorno_aviso', 'aviso', %L, %L, 'sombra', '2027-01-05 09:30-03', 'teste-f4-base:2e')$q$,
                                           c_chave, c_fone));
  if v is distinct from 'passou' then
    raise exception '2e: origem retorno_aviso com classe aviso falhou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                              values ('parceiro', 'parceiro_painel', 'retorno_parceiro', 'resumo_parceiro', %L, %L, 'sombra', '2027-01-05 17:45-03', 'teste-f4-base:2f')$q$,
                                           c_chave, c_fone));
  if v is distinct from 'passou' then
    raise exception '2f: classe resumo_parceiro falhou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.retorno_saidas (emissor, tipo, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                              values ('outro', 'parceiro_recibo', %L, %L, 'sombra', '2027-01-05 09:30-03', 'teste-f4-base:2g')$q$,
                                           c_chave, c_fone));
  if v is distinct from '23514:retorno_saidas_emissor_check' then
    raise exception '2g: emissor fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.retorno_saidas (emissor, tipo, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                              values ('parceiro', 'parceiro_recibo', 'comercial', %L, %L, 'sombra', '2027-01-05 09:30-03', 'teste-f4-base:2h')$q$,
                                           c_chave, c_fone));
  if v is distinct from '23514:retorno_saidas_classe_check' then
    raise exception '2h: classe fora da lista passou (%)', v;
  end if;
  -- Os 11 motivos novos, numero_compartilhado inclusive.
  foreach v_motivo in array c_motivos loop
    v := pg_temp.retorno_f4_base_erro(format($q$insert into public.retorno_saidas (emissor, tipo, chave, phone_normalized, modo, estado, motivo, decidida_em, enviar_em, dedupe_key)
                                                values ('parceiro', 'parceiro_recibo', %L, %L, 'sombra', 'recusada', %L, '2027-01-05 09:30-03', '2027-01-05 09:30-03', %L)$q$,
                                             c_chave, c_fone, v_motivo, 'teste-f4-base:2i:' || v_motivo));
    if v is distinct from 'passou' then
      raise exception '2i: motivo % falhou (%)', v_motivo, v;
    end if;
  end loop;
  -- O caso do parceiro: papel 'parceiro' e tipo de recibo 'recibo_parceiro'.
  insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, primeira_msg_id, aberta_em, gravada_em,
                                        ultima_em, ultima_gravada_em, nivel, tipo_recibo, modo)
    values (c_chave, c_fone, 'parceiro', '{"papel": "parceiro"}', v_msg, '2027-01-05 09:00-03', '2027-01-05 09:00-03',
            '2027-01-05 09:00-03', '2027-01-05 09:00-03', 'recibo', 'recibo_parceiro', 'sombra')
    returning id into v_abertura;
  if v_abertura is null then
    raise exception '2j: o caso do parceiro não nasceu';
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$update public.retorno_aberturas set tipo_recibo = 'recibo_inventado' where id = %L$q$, v_abertura));
  if v is distinct from '23514:retorno_aberturas_tipo_recibo_check' then
    raise exception '2k: tipo de recibo fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$update public.retorno_aberturas set papel = 'revenda' where id = %L$q$, v_abertura));
  if v is distinct from '23514:retorno_aberturas_papel_check' then
    raise exception '2l: papel fora da lista passou (%)', v;
  end if;

  -- 3. os_interessados.
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, pacote, origem)
                                              values (%L, %L, %L, 'indicou', 'completo', 'numero_do_pedido')$q$, v_os, v_parceiro, v_cliente));
  if v is distinct from '23514:os_interessados_completo' then
    raise exception '3a: indicou com pacote completo passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, pacote, origem)
                                              values (%L, %L, %L, 'anfitria', 'completo', 'carteira')$q$, v_os, v_parceiro, v_cliente));
  if v is null or v not in ('23514:os_interessados_completo', '23514:os_interessados_anfitria') then
    raise exception '3b: anfitriã com pacote completo passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem)
                                              values (%L, %L, %L, 'indicou', 'confirmado', 'numero_do_pedido')$q$, v_os, v_parceiro, v_cliente));
  if v is distinct from '23514:os_interessados_confirmado' then
    raise exception '3c: confirmado sem confirmado_em passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.os_interessados (service_order_id, parceiro_id, client_id, situacao, confirmado_em, origem)
                                              values (%L, %L, %L, 'confirmado', '2027-01-05 10:00-03', 'carteira')$q$, v_os, v_parceiro, v_cliente));
  if v is distinct from '23514:os_interessados_confirmado' then
    raise exception '3d: confirmado sem papel passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.os_interessados (service_order_id, parceiro_id, client_id, origem)
                                              values (%L, %L, %L, 'carteira')$q$, v_os, v_parceiro, v_cliente));
  if v is distinct from 'passou' then
    raise exception '3e: proposto sem papel falhou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, origem, aviso_em)
                                              values (%L, %L, %L, 'indicou', 'numero_do_pedido', '2027-01-05 10:00-03')$q$, v_os, v_parceiro, v_cliente));
  if v is distinct from '23514:os_interessados_aviso' then
    raise exception '3f: aviso_em sem aviso_ao_cliente passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, origem, aviso_ao_cliente)
                                              values (%L, %L, %L, 'indicou', 'numero_do_pedido', 'pela_revenda')$q$, v_os, v_parceiro, v_cliente));
  if v is distinct from '23514:os_interessados_aviso' then
    raise exception '3g: aviso_ao_cliente sem aviso_em passou (%)', v;
  end if;
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, origem)
    values (v_os, v_parceiro, v_cliente, 'indicou', 'numero_do_pedido') returning id into v_id;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, origem)
                                              values (%L, %L, %L, 'contratante', 'propria')$q$, v_os, v_parceiro, v_cliente));
  if v is distinct from '23505:os_interessados_um_comercial' then
    raise exception '3h: indicou e contratante da mesma OS e parceiro passaram (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, origem)
                                              values (%L, %L, %L, 'anfitria', 'carteira')$q$, v_os, v_parceiro, v_cliente));
  if v is distinct from 'passou' then
    raise exception '3i: indicou e anfitriã da mesma OS e parceiro falhou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$update public.os_interessados set situacao = 'confirmado', confirmado_em = '2027-01-05 10:00-03',
                                                 aviso_ao_cliente = 'pessoalmente', aviso_em = '2027-01-05 10:00-03', pacote = 'status'
                                              where id = %L$q$, v_id));
  if v is distinct from 'passou' then
    raise exception '3j: confirmar com papel, hora e aviso registrado falhou (%)', v;
  end if;

  -- 4. parceiro_numeros.
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, recebe_documento)
    values (v_pessoa, '5547900014002', '00014002', '47', true) returning id into v_id2;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd)
                                              values (%L, '554790014002', '00014002', '47')$q$, v_pessoa2));
  if v is distinct from '23505:parceiro_numeros_um_vivo' then
    raise exception '4a: dois números vivos com a mesma chave passaram (%)', v;
  end if;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao)
    values (v_pessoa2, '5547900014003', '00014003', '47', 'recusado');
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd)
                                              values (%L, '5547900014003', '00014003', '47')$q$, v_pessoa));
  if v is distinct from 'passou' then
    raise exception '4b: um recusado e um proposto com a mesma chave falhou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, recebe_documento)
                                              values (%L, '5547900014004', '00014004', '47', true)$q$, v_pessoa));
  if v is distinct from '23505:parceiro_numeros_um_documento' then
    raise exception '4c: dois números com documento vivos na mesma pessoa passaram (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$update public.parceiro_numeros set situacao = 'confirmado' where id = %L$q$, v_id2));
  if v is distinct from '23514:parceiro_numeros_confirmado' then
    raise exception '4d: número confirmado sem confirmado_em passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd)
                                              values (%L, '5547900014005', '4005', '47')$q$, v_pessoa));
  if v is distinct from '23514:parceiro_numeros_chave_check' then
    raise exception '4e: chave sem 8 dígitos passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro($q$insert into public.parceiros (nome, sigla, tipo) values ('Outra com a mesma sigla', 'rbf', 'revenda')$q$);
  if v is distinct from '23505:parceiros_sigla_unica' then
    raise exception '4f: sigla repetida em outra caixa passou (%)', v;
  end if;

  -- 5. Grants: anon nada nas 9 tabelas; login sem cargo lê 0; a coluna nova de service_orders fechada ao anônimo.
  foreach v_tab in array c_tabelas loop
    v := pg_temp.retorno_f4_base_como('anon', null, format('select count(*)::text from public.%I', v_tab));
    if v is distinct from 'erro 42501' then
      raise exception '5a: anon leu % (%)', v_tab, v;
    end if;
    v := pg_temp.retorno_f4_base_como('authenticated', c_sem_cargo, format('select count(*)::text from public.%I', v_tab));
    if v is distinct from '0' then
      raise exception '5b: login sem cargo leu % (%)', v_tab, v;
    end if;
  end loop;
  v := pg_temp.retorno_f4_base_como('anon', null, $q$select origem_parceiro_id::text from public.service_orders limit 1$q$);
  if v is distinct from 'erro 42501' then
    raise exception '5c: anon leu service_orders.origem_parceiro_id (%)', v;
  end if;
  if has_column_privilege('anon', 'public.service_orders', 'origem_parceiro_id', 'select') then
    raise exception '5d: anon lê origem_parceiro_id';
  end if;
  v := pg_temp.retorno_f4_base_como('authenticated', c_sem_cargo,
                                    format($q$select public._parceiro_fila_por('vinculo', %L::uuid, %L::uuid, 'teste-f4-base:5e', null)::text$q$, v_parceiro, v_id));
  if v is distinct from 'erro 42501' then
    raise exception '5e: authenticated chamou _parceiro_fila_por (%)', v;
  end if;

  -- 6. A FK de origem_parceiro_id: id que não existe recusa; apagar o parceiro zera.
  v := pg_temp.retorno_f4_base_erro(format($q$update public.service_orders set origem_parceiro_id = gen_random_uuid() where id = %L$q$, v_os));
  if v is distinct from '23503:service_orders_origem_parceiro_fk' then
    raise exception '6a: parceiro inexistente passou (%)', v;
  end if;
  update public.service_orders set origem_parceiro_id = v_parceiro_apagar, origem = 'retorno_parceiro' where id = v_os2;
  delete from public.parceiros where id = v_parceiro_apagar;
  if (select so.origem_parceiro_id from public.service_orders so where so.id = v_os2) is not null then
    raise exception '6b: apagar o parceiro não zerou origem_parceiro_id';
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$update public.service_orders set origem = 'tela' where id = %L$q$, v_os2));
  if v is distinct from '23514:service_orders_origem_check' then
    raise exception '6c: origem fora da lista passou (%)', v;
  end if;

  -- 7. O tamanho do texto: 1.500 só para o parceiro; as outras saídas continuam em 600.
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, texto, dedupe_key)
                                              values ('parceiro', 'parceiro_painel', 'retorno_parceiro', 'resumo_parceiro', %L, %L, 'sombra', '2027-01-05 17:45-03', %L, 'teste-f4-base:7a')$q$,
                                           c_chave, c_fone, repeat('a', 1400)));
  if v is distinct from 'passou' then
    raise exception '7a: 1.400 caracteres ao parceiro falharam (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, texto, dedupe_key)
                                              values ('parceiro', 'parceiro_painel', 'retorno_parceiro', 'resumo_parceiro', %L, %L, 'sombra', '2027-01-05 17:45-03', %L, 'teste-f4-base:7b')$q$,
                                           c_chave, c_fone, repeat('a', 1501)));
  if v is distinct from '23514:retorno_saidas_texto_check' then
    raise exception '7b: 1.501 caracteres ao parceiro passaram (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.retorno_saidas (emissor, abertura_id, tipo, chave, phone_normalized, modo, enviar_em, texto, dedupe_key)
                                              values ('retorno', %L, 'recibo_cliente', %L, %L, 'sombra', '2027-01-05 09:30-03', %L, 'teste-f4-base:7c')$q$,
                                           v_abertura, c_chave, c_fone, repeat('a', 601)));
  if v is distinct from '23514:retorno_saidas_texto_check' then
    raise exception '7c: 601 caracteres ao cliente passaram (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.retorno_saidas (emissor, abertura_id, tipo, chave, phone_normalized, modo, enviar_em, texto, dedupe_key)
                                              values ('retorno', %L, 'recibo_cliente', %L, %L, 'sombra', '2027-01-05 09:30-03', %L, 'teste-f4-base:7d')$q$,
                                           v_abertura, c_chave, c_fone, repeat('a', 600)));
  if v is distinct from 'passou' then
    raise exception '7d: 600 caracteres ao cliente falharam (%)', v;
  end if;

  -- 8. Os padrões novos do PDF à mão e do C13.
  if v_cfg.pdf_mao_modo is distinct from 'desligado' or v_cfg.parceiro_cadastro_ligado is not false
     or v_cfg.parceiro_coleta_espera is distinct from interval '24 hours'
     or v_cfg.parceiro_pedido_validade is distinct from interval '14 days' then
    raise exception '8a: PDF à mão, cadastro do C13 ou réguas da coleta fora do padrão';
  end if;
  v := pg_temp.retorno_f4_base_erro($q$update public.retorno_config set pdf_mao_modo = 'sempre'$q$);
  if v is distinct from '23514:retorno_config_pdf_mao_modo_check' then
    raise exception '8b: pdf_mao_modo inválido passou (%)', v;
  end if;

  -- 9. parceiro_pedidos: um por caso; caiu_motivo em lista fechada.
  insert into public.parceiro_pedidos (abertura_id, parceiro_id, pessoa_id) values (v_abertura, v_parceiro, v_pessoa);
  v := pg_temp.retorno_f4_base_erro(format($q$insert into public.parceiro_pedidos (abertura_id, parceiro_id) values (%L, %L)$q$, v_abertura, v_parceiro));
  if v is distinct from '23505:parceiro_pedidos_um_por_caso' then
    raise exception '9a: dois pedidos no mesmo caso passaram (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$update public.parceiro_pedidos set estado = 'caiu', caiu_motivo = 'cansou' where abertura_id = %L$q$, v_abertura));
  if v is distinct from '23514:parceiro_pedidos_caiu_motivo_check' then
    raise exception '9b: caiu_motivo fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$update public.parceiro_pedidos set estado = 'caiu', caiu_motivo = 'sem_resposta' where abertura_id = %L$q$, v_abertura));
  if v is distinct from 'passou' then
    raise exception '9c: caiu sem_resposta falhou (%)', v;
  end if;

  -- 10. _parceiro_fila_por: a mesma chave dá uma linha; prioridade pelo tipo; caiu volta; no_cartao e feito ficam; p_reabrir só no pedido.
  v_id := public._parceiro_fila_por('vinculo', v_parceiro, v_id, 'vinculo:teste-f4-base', null, '{"em": "2027-01-05"}');
  v_id2 := public._parceiro_fila_por('vinculo', v_parceiro, v_os, 'vinculo:teste-f4-base', '2027-01-20 00:00-03', '{"outro": 1}');
  select count(*) into v_n from public.parceiro_fila f where f.chave = 'vinculo:teste-f4-base';
  if v_n is distinct from 1 or v_id is distinct from v_id2 then
    raise exception '10a: a mesma chave deu % linhas', v_n;
  end if;
  select * into v_r from public.parceiro_fila f where f.id = v_id;
  if v_r.dados is distinct from '{"em": "2027-01-05", "outro": 1}'::jsonb or v_r.valido_ate is distinct from '2027-01-20 00:00-03'::timestamptz
     or v_r.prioridade is distinct from 8 or v_r.estado is distinct from 'espera' then
    raise exception '10b: a chave repetida não atualizou dados e validade como combinado (%)', row_to_json(v_r);
  end if;
  for v_r in
    select x.tipo, x.esperada
      from (values ('painel', 1), ('patio', 2), ('pergunta', 3), ('pedido', 3), ('retido', 4), ('pdf_mao', 5),
                   ('aviso', 6), ('repassar', 7), ('vinculo', 8)) as x(tipo, esperada)
  loop
    v_id2 := public._parceiro_fila_por(v_r.tipo, v_parceiro, v_os, 'prioridade:teste-f4-base:' || v_r.tipo, null);
    if (select f.prioridade from public.parceiro_fila f where f.id = v_id2) is distinct from v_r.esperada::smallint then
      raise exception '10c: prioridade errada no tipo %', v_r.tipo;
    end if;
  end loop;
  update public.parceiro_fila set estado = 'caiu', decidido_em = '2027-01-05 11:00-03' where id = v_id;
  perform public._parceiro_fila_por('vinculo', v_parceiro, v_os, 'vinculo:teste-f4-base', null);
  if (select f.estado from public.parceiro_fila f where f.id = v_id) is distinct from 'espera' then
    raise exception '10d: caiu não voltou a espera';
  end if;
  update public.parceiro_fila set estado = 'no_cartao' where id = v_id;
  perform public._parceiro_fila_por('vinculo', v_parceiro, v_os, 'vinculo:teste-f4-base', null);
  if (select f.estado from public.parceiro_fila f where f.id = v_id) is distinct from 'no_cartao' then
    raise exception '10e: no_cartao mudou com a chave repetida';
  end if;
  update public.parceiro_fila set estado = 'feito', decidido_em = '2027-01-05 11:00-03' where id = v_id;
  perform public._parceiro_fila_por('vinculo', v_parceiro, v_os, 'vinculo:teste-f4-base', null);
  if (select f.estado from public.parceiro_fila f where f.id = v_id) is distinct from 'feito' then
    raise exception '10f: feito mudou com a chave repetida';
  end if;
  v_id2 := public._parceiro_fila_por('pedido', v_parceiro, v_abertura, 'pedido:teste-f4-base', null);
  update public.parceiro_fila set estado = 'feito', decidido_em = '2027-01-05 11:00-03' where id = v_id2;
  perform public._parceiro_fila_por('pedido', v_parceiro, v_abertura, 'pedido:teste-f4-base', null);
  if (select f.estado from public.parceiro_fila f where f.id = v_id2) is distinct from 'feito' then
    raise exception '10g: pedido feito voltou sem p_reabrir';
  end if;
  perform public._parceiro_fila_por('pedido', v_parceiro, v_abertura, 'pedido:teste-f4-base', null, '{}', true);
  if (select f.estado from public.parceiro_fila f where f.id = v_id2) is distinct from 'espera' then
    raise exception '10h: p_reabrir no pedido não levou feito a espera';
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$select public._parceiro_fila_por('vinculo', %L::uuid, %L::uuid, 'vinculo:teste-f4-base', null, '{}', true)$q$, v_parceiro, v_os));
  if v is distinct from '22023:-' then
    raise exception '10i: p_reabrir em outro tipo passou (%)', v;
  end if;
  v := pg_temp.retorno_f4_base_erro(format($q$select public._parceiro_fila_por('corte', %L::uuid, %L::uuid, 'corte:teste-f4-base', null)$q$, v_parceiro, v_os));
  if v is distinct from '22023:-' then
    raise exception '10j: tipo fora da fila passou (%)', v;
  end if;
  if (select f.estado from public.parceiro_fila f where f.id = v_id) is distinct from 'feito' then
    raise exception '10k: a chamada recusada mudou a linha';
  end if;

  -- 11. A varredura do parceiro (a de retorno_f1_tabelas só pega retorno_*): tabela com RLS e sem anon; função interna fechada;
  --     função pública só do service_role; SECURITY DEFINER sempre com search_path.
  for v_r in
    select c.oid, c.relname, c.relkind, c.relrowsecurity
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and (c.relname ~ '^parceiro' or c.relname = 'os_interessados') and c.relkind in ('r', 'p', 'v', 'm')
  loop
    v_n_rel := v_n_rel + 1;
    if has_table_privilege('anon', v_r.oid, 'select, insert, update, delete, truncate, references, trigger') then
      raise exception '11a: anon tem privilégio em %', v_r.relname;
    end if;
    if v_r.relkind in ('r', 'p') and not v_r.relrowsecurity then
      raise exception '11a: a tabela % está sem RLS', v_r.relname;
    end if;
    if v_r.relkind in ('r', 'p') and has_table_privilege('authenticated', v_r.oid, 'insert, update, delete, truncate') then
      raise exception '11a: authenticated escreve em %', v_r.relname;
    end if;
    if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = v_r.relname
                                            and p.roles is distinct from array['authenticated']::name[]) then
      raise exception '11a: policy de % sem TO authenticated', v_r.relname;
    end if;
  end loop;
  if v_n_rel < 9 then
    raise exception '11b: a varredura achou só % tabelas do parceiro', v_n_rel;
  end if;
  for v_r in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?parceiro_'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_r.oid, 'execute') or has_function_privilege('authenticated', v_r.oid, 'execute') then
      raise exception '11c: % aberta a anon/authenticated', v_r.nome;
    end if;
    if v_r.proname !~ '^_' and not has_function_privilege('service_role', v_r.oid, 'execute') then
      raise exception '11c: % sem execute para o service_role', v_r.nome;
    end if;
    if v_r.prosecdef and not exists (select 1 from unnest(v_r.config) o where o ~ '^search_path=') then
      raise exception '11c: % é SECURITY DEFINER sem search_path', v_r.nome;
    end if;
  end loop;
  if v_n_fun < 1 then
    raise exception '11d: a varredura não achou _parceiro_fila_por';
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_base', true, '{}');
end
$base$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
