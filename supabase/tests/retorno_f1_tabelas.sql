-- Retorno F1 (P1): a configuração e as tabelas do retorno — a linha de retorno_config como nasce, os
-- checks (inclusive o grupo do caso e o so_reativo), a coerência de retorno_saidas e de
-- retorno_aberturas, as colunas novas de clients e whatsapp_leads, RLS e grants.
-- A varredura de grants das FUNÇÕES (7) fica no fim e pega todas as retorno_*, _retorno_* e
-- canal_pode_enviar da leva: a bancada (P15) roda este arquivo POR ÚLTIMO, depois de todas as
-- migrations (sem retorno_abrir, o P5, o arquivo falha de propósito).
-- O índice retorno_wa_enviadas_por_chave não é conferido: a bancada pula a criação dele.
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_tabelas.sql
-- Termina em ROLLBACK: nada fica gravado. Telefones de teste 55479000090xx; todo arranjo é desfeito
-- dentro do arquivo (sub-bloco que termina em 'desfaz').
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Roda p_sql e devolve 'passou' (desfazendo o que fez) ou 'SQLSTATE:restrição' do erro.
create or replace function pg_temp.retorno_f1_tabelas_erro(p_sql text) returns text
language plpgsql as $f$
declare
  v_estado text;
  v_restricao text;
begin
  begin
    execute p_sql;
    raise exception 'retorno_f1_desfaz' using errcode = 'P0001';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_restricao = constraint_name;
    if v_estado = 'P0001' and sqlerrm = 'retorno_f1_desfaz' then
      return 'passou';
    end if;
    return v_estado || ':' || coalesce(nullif(v_restricao, ''), '-');
  end;
end $f$;

-- Roda p_sql (um select de uma coluna) como p_papel, com o login p_uid; devolve o valor ou 'erro SQLSTATE'.
create or replace function pg_temp.retorno_f1_tabelas_como(p_papel text, p_uid uuid, p_sql text) returns text
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

do $tabelas$
declare
  c_mp constant uuid := 'ad4fea63-50af-45a3-b5ea-8724e63a5cb0';
  c_fortro constant uuid := '0ca417b8-711b-481c-9d3d-5b9c629cd99a';
  -- um login sem cargo de admin nem de financeiro (não existe em app_users)
  c_sem_cargo constant uuid := 'aa000000-0000-4000-8000-0000000090f1';
  v_cfg public.retorno_config;
  v_padrao public.retorno_config;
  v_nasceu_aqui boolean;
  v_tipos_antes text[];
  v_sem_linha boolean;
  v text;
  v_ins_saida text;
  v_ins_abertura text;
  v_m1 uuid; v_m2 uuid; v_m3 uuid; v_m4 uuid;
  v_a1 uuid;
  v_admin uuid;
  v_t text;
  v_rel regclass;
  v_n bigint;
  v_r record;
  v_n_tab int := 0;
  v_n_rel int := 0;
  v_n_fun int := 0;
  v_n_int int := 0;
  v_admin_conferido boolean := false;
begin
  -- ── 1. A linha de retorno_config como nasce ──────────────────────────────────────────────────────────
  select * into v_cfg from public.retorno_config where id;
  if not found then
    raise exception '1: retorno_config sem a linha de configuração';
  end if;
  -- A linha nasceu NESTA transação (a bancada aplicou o P1 agora) quando o xmin dela é o da transação.
  -- Depois do pacote de 10/11 a bancada não reaplica o P1, e a linha conferida é a de produção, inclusive
  -- no portão de 16/11. Por isso a conferência se divide em duas:
  -- - SEMPRE (linha nova ou de produção), o que nada muda antes de ligar o 1º grupo (24/11, com OK
  --   nomeado): modo nunca 'ligado' ('desligado' é o reverter sem deploy da seção 8.2); tipos_ligados
  --   vazio; meio_dia_ligado false (o meio-dia só existe na F2); fila_modo 'conta' (a 'trava' só depois de
  --   24/11, com OK); promessa_faixa vazia (a calibração vai ao dono no fim da sombra, e o alongamento
  --   automático só conta recibo enviado, que a sombra não tem). Um tipo ligado antes da hora falha aqui.
  -- - SÓ na linha nova, o que muda em produção sem estar errado: modo exatamente 'sombra';
  --   identificacao_nova false (liga em 11/11); so_reativo false (o disjuntor pode desarmar em produção);
  --   clientes_parceiros com a MP e a Förtro (a dúvida 1 pode esvaziar a lista).
  -- Os padrões das colunas (1e) e os checks (2) são conferidos sempre.
  select (r.xmin::text = (pg_current_xact_id()::text::numeric % 4294967296)::text) into v_nasceu_aqui
    from public.retorno_config r where r.id;
  v_tipos_antes := v_cfg.tipos_ligados;
  if v_cfg.modo = 'ligado' or v_cfg.tipos_ligados is distinct from '{}'::text[]
     or v_cfg.meio_dia_ligado is distinct from false or v_cfg.fila_modo is distinct from 'conta'
     or v_cfg.promessa_faixa is distinct from '{}'::jsonb then
    raise exception '1a: retorno_config saiu da sombra antes da hora (modo, tipos_ligados, meio_dia_ligado, fila_modo ou promessa_faixa): %',
      to_jsonb(v_cfg);
  end if;
  if v_nasceu_aqui then
    if v_cfg.modo is distinct from 'sombra' or v_cfg.identificacao_nova is distinct from false
       or v_cfg.so_reativo is distinct from false then
      raise exception '1: retorno_config não nasceu em sombra e desligada: %', to_jsonb(v_cfg);
    end if;
    if cardinality(v_cfg.clientes_parceiros) <> 2
       or not (v_cfg.clientes_parceiros @> array[c_mp, c_fortro]) then
      raise exception '1b: clientes_parceiros não tem só a MP e a Förtro: %', v_cfg.clientes_parceiros;
    end if;
  end if;
  if (public._retorno_cfg()).id is distinct from true or (public._retorno_cfg()).modo is distinct from v_cfg.modo then
    raise exception '1c: _retorno_cfg() não devolveu a linha';
  end if;
  -- Sem a linha, _retorno_cfg() devolve nulo (quem chama trata como desligado); e a linha só com os
  -- padrões das colunas nasce em sombra, com tudo desligado.
  begin
    delete from public.retorno_config;
    v_sem_linha := (public._retorno_cfg()).id is null;
    insert into public.retorno_config default values returning * into v_padrao;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if v_sem_linha is not true then
    raise exception '1d: sem a linha, _retorno_cfg() não devolveu nulo';
  end if;
  if v_padrao.id is distinct from true or v_padrao.modo is distinct from 'sombra'
     or v_padrao.tipos_ligados is distinct from '{}'::text[] or v_padrao.identificacao_nova is distinct from false
     or v_padrao.meio_dia_ligado is distinct from false or v_padrao.fila_modo is distinct from 'conta'
     or v_padrao.so_reativo is distinct from false or v_padrao.promessa_faixa is distinct from '{}'::jsonb
     or v_padrao.silencio_modo is distinct from 'sombra' or v_padrao.segura_recibos is distinct from false then
    raise exception '1e: os padrões das colunas não nascem em sombra e desligados: %', to_jsonb(v_padrao);
  end if;

  -- ── 2. Os checks de retorno_config ───────────────────────────────────────────────────────────────────
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set tipos_ligados = '{urgente}'$q$);
  if v is distinct from '23514:retorno_config_tipos_ligados_check' then
    raise exception '2a: tipos_ligados aceitou urgente (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set tipos_ligados = '{acorde}'$q$);
  if v is distinct from '23514:retorno_config_tipos_ligados_check' then
    raise exception '2b: tipos_ligados aceitou acorde (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set fila_modo = 'x'$q$);
  if v is distinct from '23514:retorno_config_fila_modo_check' then
    raise exception '2c: fila_modo aceitou x (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set cliente_resposta_direta_inicio = '07:00', cliente_resposta_direta_fim = '06:00'$q$);
  if v is distinct from '23514:retorno_config_janela' then
    raise exception '2d: janela de resposta com fim antes do início passou (%)', v;
  end if;
  -- O grupo do caso liga junto (E.6).
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set tipos_ligados = '{recibo_cliente}'$q$);
  if v is distinct from '23514:retorno_config_grupo_recibo' then
    raise exception '2e: recibo_cliente ligou sem adiamento e fim do dia (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set tipos_ligados = '{recibo_ambiguo,adiamento}'$q$);
  if v is distinct from '23514:retorno_config_grupo_recibo' then
    raise exception '2f: recibo_ambiguo ligou sem o fim do dia (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set tipos_ligados = '{coleta_numero_novo}'$q$);
  if v is distinct from '23514:retorno_config_grupo_coleta' then
    raise exception '2g: coleta_numero_novo ligou sem recibo_numero_novo (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set tipos_ligados = '{cadastro_provisorio}'$q$);
  if v is distinct from '23514:retorno_config_grupo_cadastro' then
    raise exception '2h: cadastro_provisorio ligou sem a coleta (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set so_reativo = true, so_reativo_motivo = null, so_reativo_desde = now()$q$);
  if v is distinct from '23514:retorno_config_so_reativo' then
    raise exception '2i: so_reativo ligou sem motivo (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set so_reativo = false, so_reativo_motivo = 'conexao', so_reativo_desde = null$q$);
  if v is distinct from '23514:retorno_config_so_reativo' then
    raise exception '2j: so_reativo_motivo sem so_reativo passou (%)', v;
  end if;
  -- O que pode: o 1º grupo inteiro; o só-reativo com motivo e desde; o grupo do número novo inteiro.
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set tipos_ligados = '{recibo_cliente,adiamento,fim_do_dia}'$q$);
  if v is distinct from 'passou' then
    raise exception '2k: o grupo recibo_cliente + adiamento + fim_do_dia não passou (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set so_reativo = true, so_reativo_motivo = 'conexao', so_reativo_desde = now()$q$);
  if v is distinct from 'passou' then
    raise exception '2l: so_reativo com motivo e desde não passou (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_erro($q$update public.retorno_config set tipos_ligados = '{recibo_numero_novo,coleta_numero_novo,cadastro_provisorio,adiamento,fim_do_dia}'$q$);
  if v is distinct from 'passou' then
    raise exception '2m: o grupo do número novo inteiro não passou (%)', v;
  end if;
  if (select tipos_ligados from public.retorno_config where id) is distinct from v_tipos_antes then
    raise exception '2n: o teste deixou tipos_ligados mudado';
  end if;

  -- ── 3 a 6: arranjo com mensagens e linhas sintéticas, desfeito no fim do sub-bloco ──────────────────
  begin
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status)
      values ('inbound', '5547900009061', 'text', 'teste F1 tabelas 1', 'received') returning id into v_m1;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status)
      values ('inbound', '5547900009061', 'text', 'teste F1 tabelas 2', 'received') returning id into v_m2;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status)
      values ('inbound', '5547900009061', 'text', 'teste F1 tabelas 3', 'received') returning id into v_m3;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status)
      values ('inbound', '5547900009062', 'text', 'teste F1 tabelas 4', 'received') returning id into v_m4;

    -- 3. Coerência de retorno_saidas: cada linha quebra UMA regra só.
    v_ins_saida := $q$insert into public.retorno_saidas (emissor, fila_id, tipo, chave, phone_normalized, modo, estado,
                        motivo, texto, enviada_em, enviar_em, dedupe_key)
                      values (%L, %L, %L, '00009061', '5547900009061', 'sombra', %L, %L, %L, %L, '2026-12-01 10:00-03', %L)$q$;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'retorno', null, 'recibo_cliente', 'enviada', null,
                                                'Recebi sua mensagem.', null, 'teste-f1-tabelas:3a'));
    if v is distinct from '23514:retorno_saidas_enviada' then
      raise exception '3a: enviada sem enviada_em passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'retorno', null, 'recibo_cliente', 'agendada', null,
                                                null, now(), 'teste-f1-tabelas:3b'));
    if v is distinct from '23514:retorno_saidas_enviada' then
      raise exception '3b: enviada_em sem estado enviada passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'retorno', null, 'recibo_cliente', 'recusada', null,
                                                null, null, 'teste-f1-tabelas:3c'));
    if v is distinct from '23514:retorno_saidas_motivo' then
      raise exception '3c: recusada sem motivo passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'retorno', null, 'recibo_cliente', 'cancelada', null,
                                                null, null, 'teste-f1-tabelas:3d'));
    if v is distinct from '23514:retorno_saidas_motivo' then
      raise exception '3d: cancelada sem motivo passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'fila', null, 'fila', 'contada', null,
                                                null, null, 'teste-f1-tabelas:3e'));
    if v is distinct from '23514:retorno_saidas_fila' then
      raise exception '3e: linha da fila sem fila_id passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'retorno', null, 'fila', 'contada', null,
                                                null, null, 'teste-f1-tabelas:3f'));
    if v is distinct from '23514:retorno_saidas_contada' then
      raise exception '3f: contada de emissor retorno passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'fila', gen_random_uuid(), 'fila', 'agendada', null,
                                                null, null, 'teste-f1-tabelas:3g'));
    if v is distinct from '23514:retorno_saidas_contada' then
      raise exception '3g: linha da fila fora do estado contada passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'retorno', null, 'recibo_cliente', 'preparada', null,
                                                null, null, 'teste-f1-tabelas:3h'));
    if v is distinct from '23514:retorno_saidas_texto' then
      raise exception '3h: preparada sem texto passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'retorno', null, 'recibo_cliente', 'agendada', null,
                                                'oi', null, 'teste-f1-tabelas:3i'));
    if v is distinct from '23514:retorno_saidas_texto_check' then
      raise exception '3i: texto de 2 caracteres passou (%)', v;
    end if;
    -- O que pode: a linha da fila contada; o acorde em sombra sem texto; a recusada com motivo.
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'fila', gen_random_uuid(), 'fila', 'contada', null,
                                                null, null, 'teste-f1-tabelas:3j'));
    if v is distinct from 'passou' then
      raise exception '3j: a linha da fila contada não passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'retorno', null, 'acorde', 'sombra', null,
                                                null, null, 'teste-f1-tabelas:3k'));
    if v is distinct from 'passou' then
      raise exception '3k: o acorde em sombra sem texto não passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_saida, 'retorno', null, 'recibo_cliente', 'recusada', 'validador',
                                                null, null, 'teste-f1-tabelas:3l'));
    if v is distinct from 'passou' then
      raise exception '3l: a recusada com motivo não passou (%)', v;
    end if;
    -- dedupe_key repetida: 23505.
    v := pg_temp.retorno_f1_tabelas_erro($q$insert into public.retorno_saidas (tipo, chave, phone_normalized, modo, enviar_em, dedupe_key)
                                            values ('recibo_cliente', '00009061', '5547900009061', 'sombra', '2026-12-01 10:00-03', 'teste-f1-tabelas:dup'),
                                                   ('adiamento', '00009061', '5547900009061', 'sombra', '2026-12-01 18:30-03', 'teste-f1-tabelas:dup')$q$);
    if v is distinct from '23505:retorno_saidas_dedupe_key_key' then
      raise exception '3m: dedupe_key repetida passou (%)', v;
    end if;

    -- 4. Um caso vivo por chave.
    v_ins_abertura := $q$insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, primeira_msg_id,
                           aberta_em, gravada_em, ultima_em, ultima_gravada_em, nivel, motivo, modo, estado, fechada_em,
                           fechada_motivo, cumprida_em, cumprida_por)
                         values (%L, '5547900009061', 'cliente', '{"papel": "cliente"}', %L, '2026-12-01 09:00-03',
                           '2026-12-01 09:00-03', '2026-12-01 09:00-03', '2026-12-01 09:00-03', %L, %L, 'sombra', %L, %L,
                           %L, %L, %L)$q$;
    insert into public.retorno_aberturas (chave, phone_normalized, papel, quem, primeira_msg_id, aberta_em, gravada_em,
                                          ultima_em, ultima_gravada_em, nivel, modo)
      values ('00009061', '5547900009061', 'cliente', '{"papel": "cliente"}', v_m1, '2026-12-01 09:00-03',
              '2026-12-01 09:00-03', '2026-12-01 09:00-03', '2026-12-01 09:00-03', 'recibo', 'sombra')
      returning id into v_a1;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_abertura, '00009061', v_m2, 'recibo', null, 'aberta', null, null, null, null));
    if v is distinct from '23505:retorno_aberturas_uma_viva' then
      raise exception '4a: duas aberturas vivas na mesma chave (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_abertura, '00009061', v_m2, 'recibo', null, 'vencida', null, null, null, null));
    if v is distinct from '23505:retorno_aberturas_uma_viva' then
      raise exception '4b: uma aberta e uma vencida na mesma chave (%)', v;
    end if;
    -- Fechadas não contam: duas fechadas e uma aberta na mesma chave convivem.
    execute format(v_ins_abertura, '00009061', v_m2, 'recibo', null, 'fechada', '2026-12-01 10:00-03', 'conteudo',
                   '2026-12-01 10:00-03', 'celular');
    execute format(v_ins_abertura, '00009061', v_m3, 'nada', 'robo', 'fechada', '2026-12-01 13:00-03', 'nada', null, null);
    if (select count(*) from public.retorno_aberturas where chave = '00009061' and primeira_msg_id in (v_m1, v_m2, v_m3)) <> 3 then
      raise exception '4c: a fechada e a aberta na mesma chave não conviveram';
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_abertura, '00009062', v_m1, 'recibo', null, 'aberta', null, null, null, null));
    if v is distinct from '23505:retorno_aberturas_primeira_msg_id_key' then
      raise exception '4d: a mesma mensagem abriu dois casos (%)', v;
    end if;
    -- Coerência do caso.
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_abertura, '00009062', v_m4, 'recibo', null, 'fechada', null, 'conteudo', null, null));
    if v is distinct from '23514:retorno_aberturas_fechada' then
      raise exception '4e: fechada sem fechada_em passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_abertura, '00009062', v_m4, 'nada', null, 'aberta', null, null, null, null));
    if v is distinct from '23514:retorno_aberturas_motivo' then
      raise exception '4f: nível nada sem motivo passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_abertura, '00009062', v_m4, 'recibo', 'robo', 'aberta', null, null, null, null));
    if v is distinct from '23514:retorno_aberturas_motivo' then
      raise exception '4g: recibo com motivo de nada passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_abertura, '00009062', v_m4, 'recibo', null, 'aberta', null, null,
                                                '2026-12-01 10:00-03', null));
    if v is distinct from '23514:retorno_aberturas_cumprida' then
      raise exception '4h: cumprida sem cumprida_por passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro(format(v_ins_abertura, '9001', v_m4, 'recibo', null, 'aberta', null, null, null, null));
    if v is distinct from '23514:retorno_aberturas_chave_check' then
      raise exception '4i: chave sem 8 dígitos passou (%)', v;
    end if;

    -- 5. As colunas novas de clients e whatsapp_leads.
    v := pg_temp.retorno_f1_tabelas_erro($q$insert into public.clients (type, name, provisorio) values ('individual', 'Teste F1 provisório', true)$q$);
    if v is distinct from '23514:clients_provisorio_origem' then
      raise exception '5a: cliente provisório sem origem passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro($q$insert into public.clients (type, name, origem) values ('individual', 'Teste F1 origem', 'tela')$q$);
    if v is distinct from '23514:clients_origem_check' then
      raise exception '5b: origem fora de retorno passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro($q$insert into public.clients (type, name, provisorio, origem) values ('individual', 'Teste F1 provisório', true, 'retorno')$q$);
    if v is distinct from 'passou' then
      raise exception '5c: cliente provisório do retorno não passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro($q$insert into public.whatsapp_leads (phone_normalized, lead_tipo) values ('5547900009010', 'vendedor')$q$);
    if v is distinct from '23514:whatsapp_leads_lead_tipo_check' then
      raise exception '5d: lead_tipo vendedor passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro($q$insert into public.whatsapp_leads (phone_normalized, coleta) values ('5547900009010', '[]')$q$);
    if v is distinct from '23514:whatsapp_leads_coleta_check' then
      raise exception '5e: coleta que não é objeto passou (%)', v;
    end if;
    v := pg_temp.retorno_f1_tabelas_erro($q$insert into public.whatsapp_leads (phone_normalized, lead_tipo, coleta) values ('5547900009010', 'pessoal', '{"nome": "Teste"}')$q$);
    if v is distinct from 'passou' then
      raise exception '5f: lead pessoal com coleta não passou (%)', v;
    end if;
    if exists (select 1 from public.clients where id = c_mp and (provisorio is distinct from false or origem is not null)) then
      raise exception '5g: cadastro existente (MP) não ficou com provisorio = false e origem nula';
    end if;

    -- 6. RLS e grants das tabelas novas, cada uma com pelo menos uma linha para a RLS ter o que esconder.
    insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta)
      values (v_m1, v_a1, '00009061', '2026-12-01 09:00-03', '2026-12-01 09:00-03', md5('teste F1 tabelas 1'), true);
    insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, modo, enviar_em, dedupe_key)
      values (v_a1, 'recibo_cliente', '00009061', '5547900009061', 'sombra', '2026-12-01 09:02-03', 'teste-f1-tabelas:6');
    insert into public.retorno_silencios (dia, desde, detectado_em, saidas_humanas, caiu_avisado)
      values ('2026-12-01', '2026-12-01 12:00-03', '2026-12-01 15:00-03', 0, false);
    insert into public.retorno_alongamentos (faixa, de, para, casos, pct)
      values ('tarde', '{"dias": 0, "hora": "19:00"}', '{"dias": 1, "hora": "10:00"}', 20, 0.75);

    select id into v_admin from public.app_users
     where active and role in ('admin', 'financial') order by created_at limit 1;
    if exists (select 1 from public.app_users where id = c_sem_cargo) then
      raise exception '6: o login sintético sem cargo existe em app_users';
    end if;

    foreach v_t in array array['retorno_config', 'retorno_aberturas', 'retorno_mensagens', 'retorno_saidas',
                               'retorno_silencios', 'retorno_alongamentos'] loop
      v_n_tab := v_n_tab + 1;
      v_rel := to_regclass('public.' || v_t);
      if v_rel is null then
        raise exception '6: a tabela % não existe', v_t;
      end if;
      execute format('select count(*) from public.%I', v_t) into v_n;
      if v_n < 1 then
        raise exception '6: % sem linha para conferir a RLS', v_t;
      end if;
      if not (select c.relrowsecurity from pg_class c where c.oid = v_rel) then
        raise exception '6: % sem RLS', v_t;
      end if;
      if has_table_privilege('anon', v_rel, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '6: anon tem privilégio em %', v_t;
      end if;
      if not has_table_privilege('authenticated', v_rel, 'select') then
        raise exception '6: authenticated sem select em %', v_t;
      end if;
      if has_table_privilege('authenticated', v_rel, 'insert, update, delete, truncate, references, trigger') then
        raise exception '6: authenticated pode escrever em %', v_t;
      end if;
      if not (has_table_privilege('service_role', v_rel, 'select') and has_table_privilege('service_role', v_rel, 'insert')
              and has_table_privilege('service_role', v_rel, 'update') and has_table_privilege('service_role', v_rel, 'delete')) then
        raise exception '6: service_role sem acesso completo a %', v_t;
      end if;
      if not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = v_t
                        and p.cmd = 'SELECT' and p.roles = array['authenticated']::name[])
         or exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = v_t
                       and (p.cmd <> 'SELECT' or p.roles <> array['authenticated']::name[])) then
        raise exception '6: as policies de % não são só leitura de authenticated', v_t;
      end if;
      v := pg_temp.retorno_f1_tabelas_como('anon', null, format('select count(*)::text from public.%I', v_t));
      if v is distinct from 'erro 42501' then
        raise exception '6: anon leu % (%)', v_t, v;
      end if;
      v := pg_temp.retorno_f1_tabelas_como('authenticated', c_sem_cargo, format('select count(*)::text from public.%I', v_t));
      if v is distinct from '0' then
        raise exception '6: login sem cargo leu % (%)', v_t, v;
      end if;
      if v_admin is not null then
        v := pg_temp.retorno_f1_tabelas_como('authenticated', v_admin, format('select count(*)::text from public.%I', v_t));
        if (case when v ~ '^[0-9]+$' then v::bigint else 0 end) < 1 then
          raise exception '6: o admin não leu % (%)', v_t, v;
        end if;
        v_admin_conferido := true;
      end if;
    end loop;

    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if v_n_tab <> 6 then
    raise exception '6: o arranjo não chegou ao fim (% tabelas conferidas)', v_n_tab;
  end if;

  -- 6b. Toda relação retorno_* da leva: anon nada; tabela com RLS; view com security_invoker e sem
  --     leitura de authenticated (a regra geral; pega também as da F0b e as das outras partes).
  for v_r in
    select c.oid, c.relname, c.relkind, c.relrowsecurity, coalesce(c.reloptions, '{}') as opcoes
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname ~ '^retorno_' and c.relkind in ('r', 'p', 'v', 'm')
  loop
    v_n_rel := v_n_rel + 1;
    if has_table_privilege('anon', v_r.oid, 'select, insert, update, delete, truncate, references, trigger') then
      raise exception '6b: anon tem privilégio em %', v_r.relname;
    end if;
    if v_r.relkind in ('r', 'p') and not v_r.relrowsecurity then
      raise exception '6b: a tabela % está sem RLS', v_r.relname;
    end if;
    if v_r.relkind in ('v', 'm') and has_table_privilege('authenticated', v_r.oid, 'select, insert, update, delete') then
      raise exception '6b: authenticated lê a view %', v_r.relname;
    end if;
    if v_r.relkind = 'v'
       and not exists (select 1 from unnest(v_r.opcoes) o where o ~* '^security_invoker=(on|true|yes|1)$') then
      raise exception '6b: a view % está sem security_invoker', v_r.relname;
    end if;
  end loop;

  -- ── 7. Grants das funções da leva (fica no fim: a bancada roda este arquivo depois de tudo) ──────────
  for v_r in
    select p.oid, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^(retorno_|canal_pode_enviar)'
       and p.proname <> 'retorno_medidas_base'   -- da F0b
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_r.oid, 'execute') or has_function_privilege('authenticated', v_r.oid, 'execute') then
      raise exception '7: % aberta a anon/authenticated', v_r.nome;
    end if;
    if not has_function_privilege('service_role', v_r.oid, 'execute') then
      raise exception '7: % sem execute para o service_role', v_r.nome;
    end if;
    if v_r.prosecdef and not exists (select 1 from unnest(v_r.config) o where o ~ '^search_path=') then
      raise exception '7: % é SECURITY DEFINER sem search_path', v_r.nome;
    end if;
  end loop;
  for v_r in
    select p.oid, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_retorno_'
  loop
    v_n_int := v_n_int + 1;
    if has_function_privilege('anon', v_r.oid, 'execute') or has_function_privilege('authenticated', v_r.oid, 'execute') then
      raise exception '7b: a interna % aberta a anon/authenticated', v_r.nome;
    end if;
    if v_r.prosecdef and not exists (select 1 from unnest(v_r.config) o where o ~ '^search_path=') then
      raise exception '7b: a interna % é SECURITY DEFINER sem search_path', v_r.nome;
    end if;
  end loop;
  if to_regprocedure('public.retorno_identificar(text)') is null or to_regprocedure('public._retorno_cfg()') is null then
    raise exception '7c: retorno_identificar ou _retorno_cfg não existe';
  end if;
  if to_regprocedure('public.retorno_abrir(uuid, boolean, timestamptz)') is null then
    raise exception '7c: retorno_abrir (P5) não existe: este arquivo roda depois de todas as migrations da F1 (P15)';
  end if;

  -- 42501 de verdade, chamando como anon e como authenticated.
  v := pg_temp.retorno_f1_tabelas_como('anon', null, $q$select public.retorno_abrir(null::uuid)::text$q$);
  if v is distinct from 'erro 42501' then
    raise exception '7d: anon chamou retorno_abrir (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_como('authenticated', c_sem_cargo, $q$select public.retorno_abrir(null::uuid)::text$q$);
  if v is distinct from 'erro 42501' then
    raise exception '7e: authenticated chamou retorno_abrir (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_como('anon', null, $q$select public.retorno_identificar('5547900009061')::text$q$);
  if v is distinct from 'erro 42501' then
    raise exception '7f: anon chamou retorno_identificar (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_como('authenticated', c_sem_cargo, $q$select public.retorno_identificar('5547900009061')::text$q$);
  if v is distinct from 'erro 42501' then
    raise exception '7g: authenticated chamou retorno_identificar (%)', v;
  end if;
  v := pg_temp.retorno_f1_tabelas_como('authenticated', c_sem_cargo, $q$select (public._retorno_cfg()).modo$q$);
  if v is distinct from 'erro 42501' then
    raise exception '7h: authenticated chamou _retorno_cfg (%)', v;
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_tabelas', true,
          jsonb_build_object('tabelas', v_n_tab, 'relacoes_retorno', v_n_rel, 'funcoes', v_n_fun, 'internas', v_n_int,
                             'admin_conferido', v_admin_conferido, 'config_nasceu_aqui', v_nasceu_aqui,
                             'config_modo', v_cfg.modo, 'config_tipos_ligados', cardinality(v_cfg.tipos_ligados),
                             'config_identificacao_nova', v_cfg.identificacao_nova));
end
$tabelas$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
