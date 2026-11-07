-- Retorno F2 (P1): configuração, checks, tabelas e coluna nova. Roda só pela bancada, depois das migrations da F1 e da F2.
-- Termina em ROLLBACK: nada fica gravado. Telefones de teste 55479000091xx; frases inventadas.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Roda p_sql e devolve 'passou' (desfazendo o que fez) ou 'SQLSTATE:restrição' do erro.
create or replace function pg_temp.retorno_f2_base_erro(p_sql text) returns text
language plpgsql as $f$
declare
  v_estado text;
  v_restricao text;
begin
  begin
    execute p_sql;
    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_restricao = constraint_name;
    if v_estado = 'P0001' and sqlerrm = 'retorno_f2_desfaz' then
      return 'passou';
    end if;
    return v_estado || ':' || coalesce(nullif(v_restricao, ''), '-');
  end;
end $f$;

-- Roda p_sql (um select de uma coluna) como p_papel, com o login p_uid; devolve o valor ou 'erro SQLSTATE'.
create or replace function pg_temp.retorno_f2_base_como(p_papel text, p_uid uuid, p_sql text) returns text
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
  c_sem_cargo constant uuid := 'b1600000-0000-4000-8000-0000000009f1';
  c_fone constant text := '5547900009101';
  v_cfg public.retorno_config;
  v text;
  v_msg uuid;
  v_abertura uuid;
  v_vivo uuid;
  v_n integer;
begin
  -- 1. Os padrões e os 5 tipos.
  select * into v_cfg from public.retorno_config;
  if v_cfg.cartao_ligado or v_cfg.carona_ligada or v_cfg.variantes_ligadas then
    raise exception '1a: alguma chave da F2 não nasceu desligada';
  end if;
  if v_cfg.cartao_max_itens <> 3 or v_cfg.cartao_validade <> interval '24 hours' or v_cfg.carona_intervalo <> interval '30 minutes'
     or v_cfg.modelo_dias_aprovacao <> 3 or v_cfg.modelo_usos_liberado <> 3 or v_cfg.modelo_repete_fato <> interval '24 hours'
     or v_cfg.fato_pronto_idade <> interval '48 hours' or v_cfg.fato_servico_idade <> interval '24 hours'
     or v_cfg.fato_peca_idade <> interval '7 days' or v_cfg.auditoria_cada <> 10 or v_cfg.fadiga_s <> 3
     or v_cfg.fadiga_vezes <> 3 or v_cfg.fadiga_suspende <> interval '7 days' or v_cfg.rebaixa_edicao_pct <> 0.20
     or v_cfg.cartao_tentativas <> 3 or v_cfg.liberado_validade <> interval '14 days' or v_cfg.pessoal_ultimo is not null then
    raise exception '1b: padrão diferente do combinado';
  end if;
  select count(*) into v_n from public.retorno_modelo_tipos where nivel = 'desligado';
  if v_n <> 5 then
    raise exception '1c: % tipos desligados, esperava 5', v_n;
  end if;
  if (select regua from public.retorno_modelo_tipos where tipo = 'modelo_liberado') <> 'usos' then
    raise exception '1d: modelo_liberado sem a régua de usos';
  end if;

  -- 2. Os grupos da configuração.
  v := pg_temp.retorno_f2_base_erro($q$update public.retorno_config set tipos_ligados = '{urgente}'$q$);
  if v is distinct from '23514:retorno_config_grupo_acorde' then
    raise exception '2a: urgente sem acorde passou (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_erro($q$update public.retorno_config set tipos_ligados = '{urgente,acorde}'$q$);
  if v is distinct from 'passou' then
    raise exception '2b: urgente com acorde falhou (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_erro($q$update public.retorno_config set tipos_ligados = '{outro}'$q$);
  if v is distinct from '23514:retorno_config_tipos_ligados_check' then
    raise exception '2c: tipo fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_erro($q$update public.retorno_config set tipos_ligados = '{recibo_cliente}'$q$);
  if v is distinct from '23514:retorno_config_grupo_recibo' then
    raise exception '2d: o grupo do recibo da F1 parou de valer (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_erro($q$update public.retorno_config set modo = 'ligado', meio_dia_ligado = true, tipos_ligados = '{}'$q$);
  if v is distinct from '23514:retorno_config_meio_dia_urgente' then
    raise exception '2e: meio-dia ligado sem urgente passou (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_erro($q$update public.retorno_config set modo = 'sombra', meio_dia_ligado = true, tipos_ligados = '{}'$q$);
  if v is distinct from 'passou' then
    raise exception '2f: meio-dia em sombra falhou (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_erro($q$update public.retorno_config set modo = 'ligado', meio_dia_ligado = true, tipos_ligados = '{urgente,acorde}'$q$);
  if v is distinct from 'passou' then
    raise exception '2g: meio-dia com urgente falhou (%)', v;
  end if;

  -- 3. Um cartão vivo só, um meio-dia por dia.
  insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
    values ('puxar', '2026-12-01', 'vivo', 'h1', 'cartão', '2026-12-02 09:00-03')
    returning id into v_vivo;
  v := pg_temp.retorno_f2_base_erro($q$insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
                                       values ('puxar', '2026-12-01', 'vivo', 'h2', 'cartão', '2026-12-02 09:00-03')$q$);
  if v is distinct from '23505:retorno_cartoes_um_vivo' then
    raise exception '3a: dois cartões vivos passaram (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_erro($q$insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
                                       values ('puxar', '2026-12-01', 'decidido', 'h2', 'cartão', '2026-12-02 09:00-03')$q$);
  if v is distinct from 'passou' then
    raise exception '3b: um vivo e um decidido falhou (%)', v;
  end if;
  insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
    values ('meio_dia', '2026-12-01', 'decidido', 'h3', 'cartão', '2026-12-02 12:30-03');
  v := pg_temp.retorno_f2_base_erro($q$insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
                                       values ('meio_dia', '2026-12-01', 'lista', 'h4', 'cartão', '2026-12-02 12:30-03')$q$);
  if v is distinct from '23505:retorno_cartoes_meio_dia_um' then
    raise exception '3c: dois meio-dia no mesmo dia passaram (%)', v;
  end if;
  update public.retorno_cartoes set estado = 'falhou' where gatilho = 'meio_dia' and dia = '2026-12-01';
  v := pg_temp.retorno_f2_base_erro($q$insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, expira_em)
                                       values ('meio_dia', '2026-12-01', 'lista', 'h4', 'cartão', '2026-12-02 12:30-03')$q$);
  if v is distinct from 'passou' then
    raise exception '3d: meio-dia depois de um que falhou não passou (%)', v;
  end if;

  -- 4. Os itens. A abertura exige uma mensagem, e a mensagem de teste é de número inventado.
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
    values ('inbound', c_fone, 'text', 'mensagem de teste', 'teste-f2-base-1', '2026-12-01 09:00-03')
    returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, primeira_msg_id, aberta_em, gravada_em,
                                        ultima_em, ultima_gravada_em, nivel, modo)
    values ('00009101', c_fone, 'cliente', '{"papel": "cliente"}', v_msg, '2026-12-01 09:00-03', '2026-12-01 09:00-03',
            '2026-12-01 09:00-03', '2026-12-01 09:00-03', 'recibo', 'sombra')
    returning id into v_abertura;
  v := pg_temp.retorno_f2_base_erro(format($q$insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, hash)
                                              values (%L, 4, %L, 'livre', 'i')$q$, v_vivo, v_abertura));
  if v is distinct from '23514:retorno_cartao_itens_n_check' then
    raise exception '4a: item 4 passou (%)', v;
  end if;
  insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, hash)
    values (v_vivo, 1, v_abertura, 'livre', 'i');
  v := pg_temp.retorno_f2_base_erro(format($q$insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, hash)
                                              values (%L, 1, %L, 'livre', 'i')$q$, v_vivo, v_abertura));
  if v is distinct from '23505:retorno_cartao_itens_cartao_id_n_key' then
    raise exception '4b: dois itens com o mesmo número passaram (%)', v;
  end if;

  -- 5. Saída de modelo.
  v := pg_temp.retorno_f2_base_erro(format($q$insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                              values (%L, 'modelo_pronto', 'retorno_modelo', 'resposta_imediata', '00009101', %L, 'sombra', '2026-12-01 09:02-03', 'teste-f2-base:5a')$q$,
                                           v_abertura, c_fone));
  if v is distinct from 'passou' then
    raise exception '5a: saída de modelo falhou (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_erro(format($q$insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                              values (%L, 'modelo_pronto', 'x', 'resposta_imediata', '00009101', %L, 'sombra', '2026-12-01 09:02-03', 'teste-f2-base:5b')$q$,
                                           v_abertura, c_fone));
  if v is distinct from '23514:retorno_saidas_origem_check' then
    raise exception '5b: origem fora da lista passou (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_erro(format($q$insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, modo, estado, motivo, enviar_em, dedupe_key)
                                              values (%L, 'recibo_cliente', '00009101', %L, 'sombra', 'cancelada', 'fato_mudou', '2026-12-01 09:02-03', 'teste-f2-base:5c')$q$,
                                           v_abertura, c_fone));
  if v is distinct from 'passou' then
    raise exception '5c: motivo novo falhou (%)', v;
  end if;

  -- 6. Cumprida pelo cartão.
  v := pg_temp.retorno_f2_base_erro(format($q$update public.retorno_aberturas set cumprida_em = '2026-12-01 10:00-03', cumprida_por = 'cartao' where id = %L$q$, v_abertura));
  if v is distinct from 'passou' then
    raise exception '6: cumprida_por = cartao falhou (%)', v;
  end if;

  -- 7. Grants: as 4 tabelas fechadas ao anônimo; quem não é admin nem financeiro lê zero linhas.
  v := pg_temp.retorno_f2_base_como('anon', null, $q$select count(*)::text from public.retorno_cartoes$q$);
  if v is distinct from 'erro 42501' then
    raise exception '7a: anon leu retorno_cartoes (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_como('anon', null, $q$select count(*)::text from public.retorno_cartao_itens$q$);
  if v is distinct from 'erro 42501' then
    raise exception '7b: anon leu retorno_cartao_itens (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_como('anon', null, $q$select count(*)::text from public.retorno_toques$q$);
  if v is distinct from 'erro 42501' then
    raise exception '7c: anon leu retorno_toques (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_como('anon', null, $q$select count(*)::text from public.retorno_modelo_tipos$q$);
  if v is distinct from 'erro 42501' then
    raise exception '7d: anon leu retorno_modelo_tipos (%)', v;
  end if;
  v := pg_temp.retorno_f2_base_como('authenticated', c_sem_cargo, $q$select count(*)::text from public.retorno_cartoes$q$);
  if v is distinct from '0' then
    raise exception '7e: login sem cargo leu o cartão (%)', v;
  end if;

  -- 8. A coluna nova nasce fechada ao anônimo.
  if has_column_privilege('anon', 'public.service_orders', 'liberado_retirada_em', 'select')
     or has_column_privilege('anon', 'public.service_orders', 'liberado_retirada_por', 'select') then
    raise exception '8: anon lê a marca do libera';
  end if;

  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_base', true, '{}');
end
$base$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
