-- Retorno F5 (P1): configuração, colunas novas de service_orders, as 4 tabelas do orçamento, os checks recriados com os
-- valores da F5, o item do cartão sem caso (só com o seu ponteiro) e os grants. Roda só pela bancada (grupo 8, F5_ONDA=1).
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Só confere as próprias linhas sintéticas: chaves 000099xx, telefone
-- inventado 55479000150xx (nesta parte nenhuma função liga um ao outro), nomes inventados (Ana, João). Nenhuma mensagem é
-- lida nem gravada.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Roda p_sql e devolve 'passou' (desfazendo o que fez) ou 'SQLSTATE:restrição' do erro.
create or replace function pg_temp.retorno_f5_base_erro(p_sql text) returns text
language plpgsql as $f$
declare
  v_estado text;
  v_restricao text;
begin
  begin
    execute p_sql;
    raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_restricao = constraint_name;
    if v_estado = 'P0001' and sqlerrm = 'retorno_f5_desfaz' then
      return 'passou';
    end if;
    return v_estado || ':' || coalesce(nullif(v_restricao, ''), '-');
  end;
end $f$;

-- Roda p_sql (um select de uma coluna) como p_papel, com o login p_uid; devolve o valor ou 'erro SQLSTATE'.
create or replace function pg_temp.retorno_f5_base_como(p_papel text, p_uid uuid, p_sql text) returns text
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
  c_sem_cargo constant uuid := 'b1600000-0000-4000-8000-0000000015f1';
  c_fone constant text := '5547900015001';
  c_chave constant text := '00009901';
  c_chave2 constant text := '00009902';
  c_tabelas constant text[] := array['orcamento_envios', 'orcamento_acompanhamentos', 'orcamento_passos', 'orcamento_aceites'];
  c_colunas_os constant text[] := array['orcamento_enviado_em', 'orcamento_enviado_via', 'orcamento_enviado_chave', 'motivo_perda',
                                        'motivo_perda_em', 'motivo_perda_por', 'motivo_perda_nota'];
  -- 5. As listas vigentes em produção (pg_get_constraintdef, 12/11/2026), copiadas aqui: a F5 mantém todas e acrescenta as dela.
  c_emissor_antes constant text[] := array['retorno', 'fila', 'parceiro'];
  c_tipo_antes constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'coleta_numero_novo',
    'saudacao_numero_novo', 'adiamento', 'fim_do_dia', 'urgente', 'parar', 'cadastro_provisorio', 'acorde', 'fila',
    'modelo_aguarda_peca', 'modelo_peca_chegou', 'modelo_pronto', 'modelo_em_servico', 'modelo_liberado', 'modelo_retirada_nao',
    'modelo_ver_no_local', 'parceiro_ativacao', 'parceiro_recibo', 'parceiro_coleta', 'parceiro_aviso_cliente', 'parceiro_nao_mp_ok',
    'parceiro_painel', 'parceiro_patio', 'parceiro_eco', 'parceiro_pausa', 'parceiro_repassar', 'parceiro_recado'];
  c_origem_antes constant text[] := array['retorno_recibo', 'retorno_coleta', 'retorno_adiamento', 'retorno_modelo', 'retorno_parceiro',
    'retorno_aviso'];
  c_classe_antes constant text[] := array['resposta_imediata', 'resposta_atrasada', 'aviso', 'resumo_parceiro'];
  c_motivo_antes constant text[] := array['respondida_pelo_dono', 'caso_fechado', 'caso_vencido', 'nivel_nada', 'rajada', 'lote_global',
    'aguarda_transcricao', 'fora_da_janela', 'espacamento', 'teto_numero', 'teto_dia', 'teto_coleta', 'teto_saudacao', 'teto_volta',
    'atraso_longo', 'bloqueado', 'opt_out', 'cliente_final', 'pessoal', 'equipe', 'so_reativo', 'segura_tudo', 'segura_recibos',
    'tipo_desligado', 'modo', 'urgente_desligado', 'validador', 'texto', 'canal', 'provedor', 'reserva', 'erro', 'substituida',
    'sem_config', 'classe_nao_suportada', 'sem_numero', 'agenda_ja_acordou', 'duplicado_pergunta', 'sem_nome', 'recusaria_fila',
    'guardado_no_portao', 'acorde_repetido', 'fato_mudou', 'visita_a_combinar', 'parceiro_regra', 'veto', 'pausado', 'segura_patio',
    'teto_iniciadas', 'teto_painel', 'teto_eco', 'teto_patio', 'parceiro_desligado', 'cliente_nao_ouviu', 'numero_compartilhado'];
  c_tipo_item_antes constant text[] := array['modelo', 'peca_sem_registro', 'pronto_sem_palavra', 'retirada', 'ambiguo', 'numero_novo',
    'orcamento', 'adicional', 'livre'];
  c_caiu_antes constant text[] := array['respondida_pelo_dono', 'caso_fechado', 'fato_mudou', 'telefone_mudou', 'canal_bloqueado',
    'item_provisorio', 'sem_cadastro', 'contato_diferente', 'orc_existe', 'cliente_final', 'rascunho_sem_valor'];
  c_modelo_tipo_antes constant text[] := array['modelo_aguarda_peca', 'modelo_peca_chegou', 'modelo_pronto', 'modelo_em_servico',
    'modelo_liberado'];
  c_tipos_f5 constant text[] := array['orc_lembrete', 'orc_vespera', 'orc_encerramento', 'orc_fechado', 'orc_dados_nota'];
  c_motivos_f5 constant text[] := array['cliente_escreveu', 'encerrou', 'parar', 'dono_falou', 'segurado', 'status_mudou',
    'validade_mudou', 'sem_conversa', 'agenda_hoje', 'outra_voz_hoje', 'comercial_hoje', 'sem_sim', 'orcamento_desligado',
    'parceiro_cliente', 'aceite_mudou'];
  -- 7. Funções do orçamento abertas a authenticated de propósito: orcamento_validade_do_envio (F5, P2: confere o cargo) e
  --    orcamentos_para_agrupar (anterior à F5: a tela de agrupar orçamentos a chama). Nenhuma aberta a anon.
  c_abertas constant text[] := array['orcamento_validade_do_envio', 'orcamentos_para_agrupar'];
  v_cfg public.retorno_config;
  v text;
  v_tab text;
  v_col text;
  v_valor text;
  v_vals text[];
  v_cliente uuid;
  v_cliente2 uuid;
  v_unidade uuid;
  v_os uuid;
  v_os_padrao uuid;
  v_acomp uuid;
  v_passo uuid;
  v_envio uuid;
  v_aceite uuid;
  v_aceite2 uuid;
  v_cartao uuid;
  v_item_cad uuid;
  v_item_ac uuid;
  v_item_ac2 uuid;
  v_so uuid;
  v_aceite_do_item uuid;
  v_n integer;
  v_r record;
  v_n_fun integer := 0;
begin
  begin
  -- Arranjo: dois clientes inventados (a Ana com unidade e um orçamento; o João sem nada), um cartão antigo já decidido.
  insert into public.clients (type, name) values ('individual', 'Ana Base F5 Teste') returning id into v_cliente;
  insert into public.clients (type, name) values ('individual', 'João Base F5 Teste') returning id into v_cliente2;
  insert into public.vessels (client_id, name, asset_type) values (v_cliente, 'Unidade Base F5', 'Motorhome') returning id into v_unidade;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, grand_total)
    values ('ORÇ-TF5-BASE1', v_cliente, v_unidade, 'draft', 'draft', 'repair', 100) returning id into v_os;
  insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
    values ('puxar', '2027-01-12', 'decidido', 'teste-f5-base', 'Cartão de teste da F5', '2027-01-12 23:00-03') returning id into v_cartao;

  -- 1. Os padrões das colunas (não a linha real, que o dono muda): os 9 interruptores desligados e as réguas do K7.
  -- (sem "if not exists": o conferidor de plpgsql lê esse "if" como bloco; o teste roda uma vez por transação.)
  create temp table _retorno_cfg_padrao_f5 (like public.retorno_config including defaults);
  insert into _retorno_cfg_padrao_f5 default values;
  select * into v_cfg from _retorno_cfg_padrao_f5;
  if v_cfg.orcamento_modo is distinct from 'desligado' or v_cfg.validade_envio_ligada is not false
     or v_cfg.envio_mao_modo is distinct from 'desligado' or v_cfg.aceite_modo is distinct from 'desligado'
     or v_cfg.aceite_audio is not false or v_cfg.dados_nota_ligado is not false or v_cfg.orcamento_segura is not false
     or v_cfg.encerrar_marca_perdido is not false or v_cfg.motivo_marca_aberto is not false then
    raise exception '1a: um interruptor da F5 não nasceu desligado';
  end if;
  if v_cfg.cadencia_lembrete_du is distinct from 2 or v_cfg.cadencia_encerra_du is distinct from 1
     or v_cfg.cadencia_hora is distinct from time '10:00' or v_cfg.cadencia_inicio is distinct from time '09:00'
     or v_cfg.cadencia_fim is distinct from time '17:00' then
    raise exception '1b: as réguas do K7 (2 dias úteis, 1 dia útil, 10:00 entre 09:00 e 17:00) nasceram diferentes';
  end if;
  if v_cfg.cadencia_dono_carencia is distinct from interval '2 hours' or v_cfg.cadencia_conversa is distinct from interval '365 days'
     or v_cfg.aceite_janela is distinct from interval '30 days' or v_cfg.dados_nota_janela is distinct from interval '7 days'
     or v_cfg.orcamento_envio_ate is not null or v_cfg.orcamento_aceite_ate is not null then
    raise exception '1c: carência, janelas ou marcas d''água nasceram fora do combinado';
  end if;

  -- 2. A cadência exige a validade do envio; a hora da cadência fica dentro da janela comercial; as listas fechadas.
  v := pg_temp.retorno_f5_base_erro($q$update public.retorno_config set orcamento_modo = 'sombra', validade_envio_ligada = false where id$q$);
  if v is distinct from '23514:retorno_config_cadencia_com_validade' then
    raise exception '2a: cadência sem a validade do envio passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro($q$update public.retorno_config set orcamento_modo = 'sombra', validade_envio_ligada = true where id$q$);
  if v is distinct from 'passou' then
    raise exception '2b: cadência em sombra com a validade ligada falhou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro($q$update public.retorno_config set cadencia_hora = '08:00' where id$q$);
  if v is distinct from '23514:retorno_config_janela_comercial' then
    raise exception '2c: hora da cadência fora da janela comercial passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro($q$update public.retorno_config set validade_envio_ligada = true, orcamento_modo = 'meio' where id$q$);
  if v is distinct from '23514:retorno_config_orcamento_modo_check' then
    raise exception '2d: orcamento_modo fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro($q$update public.retorno_config set envio_mao_modo = 'perguntar' where id$q$);
  if v is distinct from '23514:retorno_config_envio_mao_modo_check' then
    raise exception '2e: envio_mao_modo fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro($q$update public.retorno_config set aceite_modo = 'ligado' where id$q$);
  if v is distinct from '23514:retorno_config_aceite_modo_check' then
    raise exception '2f: aceite_modo fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro($q$update public.retorno_config set cadencia_lembrete_du = 6 where id$q$);
  if v is distinct from '23514:retorno_config_cadencia_lembrete_du_check' then
    raise exception '2g: lembrete em 6 dias úteis passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro($q$update public.retorno_config set cadencia_encerra_du = 0 where id$q$);
  if v is distinct from '23514:retorno_config_cadencia_encerra_du_check' then
    raise exception '2h: encerramento em 0 dia útil passou (%)', v;
  end if;

  -- 3. As colunas novas de service_orders e as tabelas: listas fechadas e regras de linha.
  v := pg_temp.retorno_f5_base_erro(format($q$update public.service_orders set motivo_perda = 'qualquer' where id = %L$q$, v_os));
  if v is distinct from '23514:service_orders_motivo_perda_check' then
    raise exception '3a: motivo_perda fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.service_orders set orcamento_enviado_chave = '123' where id = %L$q$, v_os));
  if v is distinct from '23514:service_orders_orcamento_enviado_chave_check' then
    raise exception '3b: chave sem 8 dígitos passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.service_orders set orcamento_enviado_via = 'whatsapp' where id = %L$q$, v_os));
  if v is distinct from '23514:service_orders_orcamento_enviado_via_check' then
    raise exception '3c: via do envio fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.service_orders set motivo_perda_por = 'ia' where id = %L$q$, v_os));
  if v is distinct from '23514:service_orders_motivo_perda_por_check' then
    raise exception '3d: motivo_perda_por fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.service_orders set motivo_perda_nota = repeat('a', 201) where id = %L$q$, v_os));
  if v is distinct from '23514:service_orders_motivo_perda_nota_check' then
    raise exception '3e: nota do motivo com 201 caracteres passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.service_orders
                                                 set motivo_perda = 'sumiu', motivo_perda_por = 'dono', motivo_perda_em = '2027-01-20 10:00-03',
                                                     motivo_perda_nota = 'nota de teste', orcamento_enviado_via = 'tela',
                                                     orcamento_enviado_chave = %L, orcamento_enviado_em = '2027-01-12 10:00-03'
                                               where id = %L$q$, c_chave, v_os));
  if v is distinct from 'passou' then
    raise exception '3f: colunas novas com valores da lista falharam (%)', v;
  end if;
  -- O acompanhamento: um por orçamento; parado exige parou_por; encerrado se e só se tem encerramento.
  insert into public.orcamento_acompanhamentos (service_order_id, client_id, chave, enviado_em, validade_ate, modo)
    values (v_os, v_cliente, c_chave, '2027-01-12 10:00-03', '2027-01-19', 'sombra') returning id into v_acomp;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_acompanhamentos set estado = 'encerrado' where id = %L$q$, v_acomp));
  if (v ~ '^23514:orcamento_acompanhamentos_check[0-9]*$') is not true then
    raise exception '3g: acompanhamento encerrado sem encerramento passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_acompanhamentos set encerramento = 'enviado' where id = %L$q$, v_acomp));
  if (v ~ '^23514:orcamento_acompanhamentos_check[0-9]*$') is not true then
    raise exception '3h: encerramento num acompanhamento ativo passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_acompanhamentos set estado = 'encerrado', encerramento = 'sem_mensagem',
                                                                                         desfecho_proposto = 'sumiu' where id = %L$q$, v_acomp));
  if v is distinct from 'passou' then
    raise exception '3i: encerrado sem mensagem e desfecho proposto falhou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_acompanhamentos set estado = 'parado' where id = %L$q$, v_acomp));
  if (v ~ '^23514:orcamento_acompanhamentos_check[0-9]*$') is not true then
    raise exception '3j: parado sem parou_por passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_acompanhamentos set estado = 'parado', parou_por = 'chuva' where id = %L$q$, v_acomp));
  if v is distinct from '23514:orcamento_acompanhamentos_parou_por_check' then
    raise exception '3k: parou_por fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.orcamento_acompanhamentos (service_order_id, client_id, chave, enviado_em, validade_ate, modo)
                                              values (%L, %L, %L, '2027-01-13 10:00-03', '2027-01-20', 'sombra')$q$, v_os, v_cliente, c_chave));
  if v is distinct from '23505:orcamento_acompanhamentos_service_order_id_key' then
    raise exception '3l: dois acompanhamentos do mesmo orçamento passaram (%)', v;
  end if;
  -- Os passos: prazo nunca antes do dia; pulado exige motivo da lista; um de cada por acompanhamento.
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.orcamento_passos (acompanhamento_id, passo, tipo, dia, ate)
                                              values (%L, 'lembrete', 'orc_lembrete', '2027-01-14', '2027-01-13')$q$, v_acomp));
  if (v ~ '^23514:orcamento_passos_check[0-9]*$') is not true then
    raise exception '3m: passo com o prazo antes do dia passou (%)', v;
  end if;
  insert into public.orcamento_passos (acompanhamento_id, passo, tipo, dia, ate)
    values (v_acomp, 'lembrete', 'orc_lembrete', '2027-01-14', '2027-01-15') returning id into v_passo;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_passos set estado = 'pulado' where id = %L$q$, v_passo));
  if (v ~ '^23514:orcamento_passos_check[0-9]*$') is not true then
    raise exception '3n: passo pulado sem motivo passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_passos set estado = 'pulado', motivo = 'chuva' where id = %L$q$, v_passo));
  if v is distinct from '23514:orcamento_passos_motivo_check' then
    raise exception '3o: motivo do passo fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_passos set estado = 'pulado', motivo = 'sem_sim' where id = %L$q$, v_passo));
  if v is distinct from 'passou' then
    raise exception '3p: passo pulado sem_sim falhou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_passos set estado = 'cancelado', motivo = 'parou' where id = %L$q$, v_passo));
  if v is distinct from 'passou' then
    raise exception '3q: passo cancelado com motivo falhou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_passos set motivo = 'texto' where id = %L$q$, v_passo));
  if (v ~ '^23514:orcamento_passos_check[0-9]*$') is not true then
    raise exception '3r: motivo num passo previsto passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.orcamento_passos (acompanhamento_id, passo, tipo, dia, ate)
                                              values (%L, 'lembrete', 'orc_lembrete', '2027-01-15', '2027-01-15')$q$, v_acomp));
  if v is distinct from '23505:orcamento_passos_acompanhamento_id_passo_key' then
    raise exception '3s: dois lembretes no mesmo acompanhamento passaram (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.orcamento_passos (acompanhamento_id, passo, tipo, dia, ate, texto_aprovado)
                                              values (%L, 'vespera', 'orc_vespera', '2027-01-18', '2027-01-18', repeat('a', 601))$q$, v_acomp));
  if v is distinct from '23514:orcamento_passos_texto_aprovado_check' then
    raise exception '3t: texto aprovado com 601 caracteres passou (%)', v;
  end if;
  -- Os envios: a via em lista fechada; um evento por (ordem, via, hora).
  insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em, marcou)
    values (v_os, v_cliente, 'tela', c_chave, true, '2027-01-12 10:00-03', true) returning id into v_envio;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em)
                                              values (%L, %L, 'whatsapp', %L, true, '2027-01-12 11:00-03')$q$, v_os, v_cliente, c_chave));
  if v is distinct from '23514:orcamento_envios_via_check' then
    raise exception '3u: via do envio fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.orcamento_envios (service_order_id, client_id, via, chave, ao_cliente, em)
                                              values (%L, %L, 'tela', %L, true, '2027-01-12 10:00-03')$q$, v_os, v_cliente, c_chave));
  if v is distinct from '23505:orcamento_envios_service_order_id_via_em_key' then
    raise exception '3v: o mesmo envio duas vezes passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.orcamento_envios (service_order_id, via, chave, ao_cliente, em)
                                              values (%L, 'marcado', null, false, '2027-01-12 12:00-03')$q$, v_os));
  if v is distinct from 'passou' then
    raise exception '3w: marcação à mão sem chave nem cliente falhou (%)', v;
  end if;
  -- O aceite: estado e sinal em lista fechada; a mensagem do cliente (só o id) prova um aceite só.
  insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, service_order_id, sinal_lido, estado, total_visto)
    values (gen_random_uuid(), v_cliente, c_chave, array[v_os], v_os, 'pode fazer', 'detectado', 100) returning id into v_aceite;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, sinal_lido, estado)
                                              select a.whatsapp_message_id, a.client_id, a.chave, a.candidatos, 'fechado', 'duvida'
                                                from public.orcamento_aceites a where a.id = %L$q$, v_aceite));
  if v is distinct from '23505:orcamento_aceites_whatsapp_message_id_key' then
    raise exception '3x: dois aceites da mesma mensagem passaram (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_aceites set estado = 'aprovado' where id = %L$q$, v_aceite));
  if v is distinct from '23514:orcamento_aceites_estado_check' then
    raise exception '3y: estado do aceite fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_aceites set sinal_lido = repeat('a', 41) where id = %L$q$, v_aceite));
  if v is distinct from '23514:orcamento_aceites_sinal_lido_check' then
    raise exception '3z: sinal lido com 41 caracteres passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_aceites set resultado = '[]' where id = %L$q$, v_aceite));
  if v is distinct from '23514:orcamento_aceites_resultado_check' then
    raise exception '3za: resultado que não é objeto passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_aceites set dados_estado = 'talvez' where id = %L$q$, v_aceite));
  if v is distinct from '23514:orcamento_aceites_dados_estado_check' then
    raise exception '3zb: dados_estado fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.orcamento_aceites set estado = 'substituido', resultado = '{"substituido_por": "x"}'
                                               where id = %L$q$, v_aceite));
  if v is distinct from 'passou' then
    raise exception '3zc: estado substituido falhou (%)', v;
  end if;

  -- 4. O item do cartão sem caso existe só com o seu ponteiro.
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, hash)
                                              values (%L, 1, null, 'modelo', 'h-4a')$q$, v_cartao));
  if v is distinct from '23514:retorno_cartao_itens_caso_ou_ponteiro' then
    raise exception '4a: item modelo sem caso passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, hash)
                                              values (%L, 1, null, 'cadencia', 'h-4b')$q$, v_cartao));
  if v is distinct from '23514:retorno_cartao_itens_caso_ou_ponteiro' then
    raise exception '4b: item cadencia sem passo passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, aceite_id, hash)
                                              values (%L, 1, null, 'cadencia', %L, 'h-4c')$q$, v_cartao, v_aceite));
  if v is distinct from '23514:retorno_cartao_itens_caso_ou_ponteiro' then
    raise exception '4c: item cadencia com o ponteiro do aceite passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, hash)
                                              values (%L, 3, null, 'aceite', 'h-4d')$q$, v_cartao));
  if v is distinct from '23514:retorno_cartao_itens_caso_ou_ponteiro' then
    raise exception '4d: item aceite sem aceite_id e sem caso passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, aceite_id, hash)
                                              values (%L, 3, null, 'dados_nota', %L, 'h-4e')$q$, v_cartao, v_aceite));
  if v is distinct from 'passou' then
    raise exception '4e: item dados_nota com aceite_id falhou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, hash)
                                              values (%L, 3, null, 'inventado', 'h-4f')$q$, v_cartao));
  if v is distinct from '23514:retorno_cartao_itens_tipo_item_check' then
    raise exception '4f: tipo de item fora da lista passou (%)', v;
  end if;
  insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, passo_id, hash, estado)
    values (v_cartao, 1, null, 'cadencia', v_passo, 'h-cad', 'feito') returning id into v_item_cad;
  insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, aceite_id, service_order_id, hash, estado)
    values (v_cartao, 2, null, 'aceite', v_aceite, v_os, 'h-ac', 'feito') returning id into v_item_ac;
  if v_item_cad is null or v_item_ac is null then
    raise exception '4g: o item cadencia ou o item aceite com o seu ponteiro não nasceu';
  end if;
  foreach v_valor in array array['cliente_escreveu', 'orcamento_mudou', 'segurado'] loop
    v := pg_temp.retorno_f5_base_erro(format($q$update public.retorno_cartao_itens set estado = 'caiu', caiu_motivo = %L where id = %L$q$, v_valor, v_item_ac));
    if v is distinct from 'passou' then
      raise exception '4h: caiu_motivo % falhou (%)', v_valor, v;
    end if;
  end loop;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.retorno_cartao_itens set estado = 'caiu', caiu_motivo = 'sumiu' where id = %L$q$, v_item_ac));
  if v is distinct from '23514:retorno_cartao_itens_caiu_motivo_check' then
    raise exception '4i: caiu_motivo fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro(format($q$update public.retorno_cartao_itens set tirado_em = '2027-01-14 10:00-03', selecionado = false where id = %L$q$, v_item_ac));
  if v is distinct from 'passou' then
    raise exception '4j: marcar tirado_em falhou (%)', v;
  end if;

  -- 5. Os checks recriados: todos os valores vigentes de produção e os da F5.
  for v_r in
    select x.tabela, x.nome, x.antes, x.novos
      from (values
        ('retorno_saidas', 'retorno_saidas_emissor_check', c_emissor_antes, array['orcamento']::text[]),
        ('retorno_saidas', 'retorno_saidas_tipo_check', c_tipo_antes, c_tipos_f5),
        ('retorno_saidas', 'retorno_saidas_origem_check', c_origem_antes, array['retorno_orcamento']::text[]),
        ('retorno_saidas', 'retorno_saidas_classe_check', c_classe_antes, array['comercial']::text[]),
        ('retorno_saidas', 'retorno_saidas_motivo_check', c_motivo_antes, c_motivos_f5),
        ('retorno_cartao_itens', 'retorno_cartao_itens_tipo_item_check', c_tipo_item_antes, array['aceite', 'dados_nota', 'cadencia']::text[]),
        ('retorno_cartao_itens', 'retorno_cartao_itens_caiu_motivo_check', c_caiu_antes,
         array['cliente_escreveu', 'orcamento_mudou', 'segurado']::text[]),
        ('retorno_modelo_tipos', 'retorno_modelo_tipos_tipo_check', c_modelo_tipo_antes,
         array['orc_lembrete', 'orc_vespera', 'orc_encerramento']::text[])
      ) as x(tabela, nome, antes, novos)
  loop
    v_vals := null;
    select array(select m[1] from regexp_matches(pg_get_constraintdef(c.oid), '''([^'']*)''', 'g') as m) into v_vals
      from pg_constraint c
     where c.conrelid = ('public.' || v_r.tabela)::regclass and c.conname = v_r.nome and c.contype = 'c';
    if v_vals is null then
      raise exception '5a: o check % não existe', v_r.nome;
    end if;
    if (v_r.antes <@ v_vals) is not true then
      raise exception '5b: o check % perdeu valor vigente: %', v_r.nome,
        (select string_agg(a, ', ') from unnest(v_r.antes) a where a <> all (v_vals));
    end if;
    if (v_r.novos <@ v_vals) is not true then
      raise exception '5c: o check % não tem os valores da F5: %', v_r.nome,
        (select string_agg(a, ', ') from unnest(v_r.novos) a where a <> all (v_vals));
    end if;
  end loop;
  -- E na prática: a saída do orçamento (sem caso) com cada tipo novo, e recusada com cada motivo novo.
  foreach v_valor in array c_tipos_f5 loop
    v := pg_temp.retorno_f5_base_erro(format($q$insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                                values ('orcamento', %L, 'retorno_orcamento', %L, %L, %L, 'sombra', '2027-01-14 10:00-03', %L)$q$,
                                             v_valor, case when v_valor in ('orc_fechado', 'orc_dados_nota') then 'resposta_imediata' else 'comercial' end,
                                             c_chave, c_fone, 'orcamento:teste-f5-base:5d:' || v_valor));
    if v is distinct from 'passou' then
      raise exception '5d: saída do orçamento do tipo % falhou (%)', v_valor, v;
    end if;
  end loop;
  foreach v_valor in array c_motivos_f5 loop
    v := pg_temp.retorno_f5_base_erro(format($q$insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, estado, motivo,
                                                                                 decidida_em, enviar_em, dedupe_key)
                                                values ('orcamento', 'orc_lembrete', 'retorno_orcamento', 'comercial', %L, %L, 'sombra', 'recusada', %L,
                                                        '2027-01-14 10:00-03', '2027-01-14 10:00-03', %L)$q$,
                                             c_chave, c_fone, v_valor, 'orcamento:teste-f5-base:5e:' || v_valor));
    if v is distinct from 'passou' then
      raise exception '5e: motivo % falhou (%)', v_valor, v;
    end if;
  end loop;
  v := pg_temp.retorno_f5_base_erro(format($q$insert into public.retorno_saidas (emissor, tipo, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                              values ('orcamento', 'orc_inventado', %L, %L, 'sombra', '2027-01-14 10:00-03', 'orcamento:teste-f5-base:5f')$q$,
                                           c_chave, c_fone));
  if v is distinct from '23514:retorno_saidas_tipo_check' then
    raise exception '5f: tipo de saída fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f5_base_erro($q$insert into public.retorno_modelo_tipos (tipo) values ('orc_fechado')$q$);
  if v is distinct from '23514:retorno_modelo_tipos_tipo_check' then
    raise exception '5g: orc_fechado entrou em retorno_modelo_tipos (%)', v;
  end if;

  -- 6. Os 3 tipos da cadência nascem desligados, na régua de dias; o "Fechado" e os dados da nota nunca são promovíveis.
  select count(*) into v_n from public.retorno_modelo_tipos t
   where t.tipo in ('orc_lembrete', 'orc_vespera', 'orc_encerramento')
     and t.nivel = 'desligado' and t.regua = 'dias' and t.promovido_em is null;
  if v_n is distinct from 3 then
    raise exception '6a: % dos 3 tipos da cadência nasceram desligados na régua de dias', v_n;
  end if;
  select count(*) into v_n from public.retorno_modelo_tipos t where t.tipo in ('orc_fechado', 'orc_dados_nota');
  if v_n is distinct from 0 then
    raise exception '6b: orc_fechado ou orc_dados_nota em retorno_modelo_tipos (%)', v_n;
  end if;

  -- 7. Grants. As 4 tabelas: RLS, anon nada, authenticated só lê e só com is_admin_or_financial (login sem cargo lê 0 das
  --    linhas sintéticas acima), service_role escreve. As colunas novas de service_orders fechadas ao anônimo. E a varredura
  --    das funções do orçamento pelo nome (revogar de public não fecha o anon).
  if not exists (select 1 from public.orcamento_envios e where e.id = v_envio)
     or not exists (select 1 from public.orcamento_acompanhamentos a where a.id = v_acomp)
     or not exists (select 1 from public.orcamento_passos p where p.id = v_passo)
     or not exists (select 1 from public.orcamento_aceites a where a.id = v_aceite) then
    raise exception '7a: falta linha sintética numa das 4 tabelas (o 0 do login sem cargo não provaria nada)';
  end if;
  foreach v_tab in array c_tabelas loop
    v := pg_temp.retorno_f5_base_como('anon', null, format('select count(*)::text from public.%I', v_tab));
    if v is distinct from 'erro 42501' then
      raise exception '7b: anon leu % (%)', v_tab, v;
    end if;
    v := pg_temp.retorno_f5_base_como('authenticated', c_sem_cargo, format('select count(*)::text from public.%I', v_tab));
    if v is distinct from '0' then
      raise exception '7c: login sem cargo leu % (%)', v_tab, v;
    end if;
    if has_table_privilege('anon', ('public.' || v_tab)::regclass, 'select, insert, update, delete, truncate, references, trigger') then
      raise exception '7d: anon tem privilégio em %', v_tab;
    end if;
    if has_table_privilege('authenticated', ('public.' || v_tab)::regclass, 'insert, update, delete, truncate') then
      raise exception '7e: authenticated escreve em %', v_tab;
    end if;
    -- Com várias permissões numa chamada, has_table_privilege diz se tem QUALQUER uma: aqui, uma por chamada.
    if has_table_privilege('authenticated', ('public.' || v_tab)::regclass, 'select') is not true
       or has_table_privilege('service_role', ('public.' || v_tab)::regclass, 'select') is not true
       or has_table_privilege('service_role', ('public.' || v_tab)::regclass, 'insert') is not true
       or has_table_privilege('service_role', ('public.' || v_tab)::regclass, 'update') is not true
       or has_table_privilege('service_role', ('public.' || v_tab)::regclass, 'delete') is not true then
      raise exception '7f: authenticated não lê ou service_role não escreve em %', v_tab;
    end if;
    if (select c.relrowsecurity from pg_class c where c.oid = ('public.' || v_tab)::regclass) is not true then
      raise exception '7g: % está sem RLS', v_tab;
    end if;
    select count(*) into v_n from pg_policies p
     where p.schemaname = 'public' and p.tablename = v_tab and p.cmd = 'SELECT'
       and p.roles = array['authenticated']::name[] and p.qual ~ 'is_admin_or_financial';
    if v_n is distinct from 1
       or exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = v_tab
                                               and (p.cmd <> 'SELECT' or p.roles is distinct from array['authenticated']::name[])) then
      raise exception '7h: a policy de % não é só a leitura de admin e financeiro TO authenticated', v_tab;
    end if;
  end loop;
  foreach v_col in array c_colunas_os loop
    if has_column_privilege('anon', 'public.service_orders', v_col, 'select')
       or has_column_privilege('anon', 'public.service_orders', v_col, 'update') then
      raise exception '7i: anon lê ou escreve service_orders.%', v_col;
    end if;
  end loop;
  v := pg_temp.retorno_f5_base_como('anon', null, $q$select motivo_perda from public.service_orders limit 1$q$);
  if v is distinct from 'erro 42501' then
    raise exception '7j: anon leu service_orders.motivo_perda (%)', v;
  end if;
  for v_r in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?orcamento'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_r.oid, 'execute') then
      raise exception '7k: % aberta a anon', v_r.nome;
    end if;
    if has_function_privilege('authenticated', v_r.oid, 'execute') and v_r.proname <> all (c_abertas) then
      raise exception '7l: % aberta a authenticated', v_r.nome;
    end if;
    if v_r.prosecdef and not exists (select 1 from unnest(v_r.config) o where o ~ '^search_path=') then
      raise exception '7m: % é SECURITY DEFINER sem search_path', v_r.nome;
    end if;
  end loop;
  if v_n_fun < 1 then
    raise exception '7n: a varredura das funções do orçamento não achou nenhuma (o filtro quebrou)';
  end if;

  -- 9. O padrão da validade (K6, D-16): a coluna passa a 7, a 3ª fonte do mesmo número.
  select c.column_default into v from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'service_orders' and c.column_name = 'quote_validity_days';
  if v is distinct from '7' then
    raise exception '9a: o padrão de quote_validity_days é % (esperava 7)', v;
  end if;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, grand_total)
    values ('ORÇ-TF5-BASE2', v_cliente, v_unidade, 'draft', 'draft', 'repair', 50) returning id into v_os_padrao;
  if (select so.quote_validity_days from public.service_orders so where so.id = v_os_padrao) is distinct from 7 then
    raise exception '9b: orçamento novo sem validade não nasceu com 7 dias';
  end if;

  -- 4b. Apagar a ordem (por último: apaga o arranjo do 7). Nenhum 23514; acompanhamento, passo, envio e item cadencia somem
  --     em cascata; o aceite (a prova da mensagem) e o item aceite ficam, com a ordem nula nos dois.
  begin
    delete from public.service_orders where id = v_os;
  exception when others then
    raise exception '4b: apagar a ordem falhou (%: %)', sqlstate, sqlerrm;
  end;
  if exists (select 1 from public.orcamento_acompanhamentos a where a.id = v_acomp)
     or exists (select 1 from public.orcamento_passos p where p.id = v_passo)
     or exists (select 1 from public.orcamento_envios e where e.id = v_envio)
     or exists (select 1 from public.retorno_cartao_itens i where i.id = v_item_cad) then
    raise exception '4b: acompanhamento, passo, envio ou item cadencia sobrou depois de apagar a ordem';
  end if;
  v_so := null;
  select a.service_order_id into v_so from public.orcamento_aceites a where a.id = v_aceite;
  if not found then
    raise exception '4b: o aceite sumiu junto com a ordem';
  end if;
  if v_so is not null then
    raise exception '4b: o aceite ficou com a ordem apagada';
  end if;
  v_so := null;
  v_aceite_do_item := null;
  select i.service_order_id, i.aceite_id into v_so, v_aceite_do_item from public.retorno_cartao_itens i where i.id = v_item_ac;
  if not found then
    raise exception '4b: o item aceite sumiu junto com a ordem';
  end if;
  if v_so is not null or v_aceite_do_item is distinct from v_aceite then
    raise exception '4b: o item aceite não ficou com a ordem nula e o mesmo aceite';
  end if;
  -- Apagar o cliente apaga o aceite e o item juntos (cascata por client_id e aceite_id). O João não tem ordem nem unidade.
  insert into public.orcamento_aceites (whatsapp_message_id, client_id, chave, candidatos, sinal_lido, estado)
    values (gen_random_uuid(), v_cliente2, c_chave2, '{}', 'aprovado', 'duvida') returning id into v_aceite2;
  insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, aceite_id, hash, estado)
    values (v_cartao, 3, null, 'aceite', v_aceite2, 'h-ac2', 'feito') returning id into v_item_ac2;
  begin
    delete from public.clients where id = v_cliente2;
  exception when others then
    raise exception '4b: apagar o cliente falhou (%: %)', sqlstate, sqlerrm;
  end;
  if exists (select 1 from public.orcamento_aceites a where a.id = v_aceite2)
     or exists (select 1 from public.retorno_cartao_itens i where i.id = v_item_ac2) then
    raise exception '4b: o aceite ou o item aceite sobrou depois de apagar o cliente';
  end if;

  raise exception 'retorno_f5_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f5_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f5_base', true, '{}');
end
$base$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
