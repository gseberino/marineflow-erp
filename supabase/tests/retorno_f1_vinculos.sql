-- Retorno F1 (P16): o lote de vínculos (F0b-10) — retorno_vinculos_candidatos e retorno_vincular_lead.
-- A lista é pela chave de 8 dígitos e o DDD (quem_escreve), nunca pelo nome: unico (com letra),
-- compartilhado e parceiro (sem letra); as letras pulam E, I, N, O e S. O vínculo só vale para o unico com
-- o cliente da chave e nunca sobrescreve o client_id de uma mensagem que já tem outro.
-- Isolamento dos leads reais (266 pendentes em 01/11): dentro do arranjo, todo cliente que não é deste
-- arquivo entra em retorno_config.clientes_parceiros, e os leads reais saem "parceiro" (sem letra). Só os
-- sintéticos ficam "unico", e as letras são deles. Nenhuma linha real de whatsapp_leads, whatsapp_messages
-- ou clients é escrita; a linha de retorno_config muda e volta no fim do sub-bloco.
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_vinculos.sql
-- Termina em ROLLBACK: nada fica gravado. Telefones de teste 55479000096xx; o arranjo inteiro é desfeito
-- dentro do arquivo (sub-bloco que termina em 'desfaz').
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Roda p_sql (um select de uma coluna) como p_papel, com o login p_uid; devolve o valor ou 'erro SQLSTATE'.
create or replace function pg_temp.retorno_f1_vinculos_como(p_papel text, p_uid uuid, p_sql text) returns text
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

do $vinculos$
declare
  -- um login sem cargo de admin nem de financeiro (não existe em app_users)
  c_sem_cargo constant uuid := 'aa000000-0000-4000-8000-0000000096f1';
  c_letras constant text[] := array['A', 'B', 'C', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'P', 'Q', 'R', 'T',
                                    'U', 'V', 'W', 'X', 'Y', 'Z', 'AA', 'AB'];
  v_f record;
  v_r record;
  v text;
  v_n int;
  v_n2 int;
  v_letras text[];
  v_nomes text[];
  v_ids uuid[];
  -- os 7 "unico", em ordem de nome: Abel, Bruna, Caio, Dora, Érico, Fábio, Gil
  v_c_abel uuid; v_c_bruna uuid; v_c_caio uuid; v_c_dora uuid; v_c_erico uuid; v_c_fabio uuid; v_c_gil uuid;
  v_l_abel uuid; v_l_bruna uuid; v_l_caio uuid; v_l_dora uuid; v_l_erico uuid; v_l_fabio uuid; v_l_gil uuid;
  -- os outros cadastros e leads
  v_c_dois_a uuid; v_c_dois_b uuid; v_c_parc uuid; v_c_link uuid; v_c_generico uuid; v_c_inativo uuid;
  v_c_semi uuid; v_c_equipe uuid; v_c_grupo uuid; v_c_transm uuid; v_forn uuid; v_payee uuid;
  v_l_dois uuid; v_l_parc uuid; v_l_link uuid; v_l_nome uuid; v_l_generico uuid; v_l_inativo uuid;
  v_l_semi uuid; v_l_forn uuid; v_l_equipe uuid; v_l_sem_chave uuid; v_l_grupo uuid; v_l_transm uuid;
  -- as mensagens do número do Abel (e uma da Bruna)
  v_m_in uuid; v_m_out uuid; v_m_outro uuid; v_m_sem55 uuid; v_m_outro_ddd uuid; v_m_outra_chave uuid;
  v_sinteticos uuid[];
  v_leads_todos uuid[];
  v_parceiros_antes uuid[];
  v_fora jsonb;
  v_lista jsonb;
  v_linha jsonb;
  r_um jsonb; r_de_novo jsonb; r_compart jsonb; r_nao_casa jsonb; r_parceiro jsonb;
  r_inexistente jsonb; r_link jsonb; r_semi jsonb; r_generico jsonb; r_equipe jsonb; r_grupo jsonb; r_transm jsonb;
  v_recusas jsonb;
  v_lead_abel jsonb;
  v_leads_final jsonb;
  v_msgs jsonb; v_msgs_de_novo jsonb; v_msgs_final jsonb;
  v_audit jsonb;
  v_audit_n int;
  v_audit_n_final int;
  v_sem_cfg_lista text;
  v_sem_cfg_vincular text;
  v_chegou boolean := false;
begin
  -- ── 0. As funções: atributos, a saída do contrato C-VINC e quem chama ─────────────────────────────────
  select p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config, pg_get_function_result(p.oid) as saida
    into v_f
    from pg_proc p where p.oid = to_regprocedure('public.retorno_vinculos_candidatos()');
  if not found then
    raise exception '0: retorno_vinculos_candidatos não existe';
  end if;
  if v_f.provolatile <> 's' or not v_f.prosecdef or not ('search_path=public' = any (v_f.config)) then
    raise exception '0a: retorno_vinculos_candidatos não é STABLE + SECURITY DEFINER com search_path = public';
  end if;
  if v_f.saida is distinct from 'TABLE(letra text, lead_id uuid, phone text, tipo text, clientes jsonb)' then
    raise exception '0b: a saída de retorno_vinculos_candidatos está fora do contrato C-VINC: %', v_f.saida;
  end if;
  select p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config, pg_get_function_result(p.oid) as saida
    into v_f
    from pg_proc p where p.oid = to_regprocedure('public.retorno_vincular_lead(uuid, uuid)');
  if not found then
    raise exception '0c: retorno_vincular_lead(uuid, uuid) não existe';
  end if;
  if v_f.provolatile <> 'v' or not v_f.prosecdef or not ('search_path=public' = any (v_f.config))
     or v_f.saida is distinct from 'jsonb' then
    raise exception '0d: retorno_vincular_lead não é VOLATILE + SECURITY DEFINER com search_path = public, devolvendo jsonb';
  end if;
  foreach v in array array['public.retorno_vinculos_candidatos()', 'public.retorno_vincular_lead(uuid, uuid)'] loop
    if has_function_privilege('anon', v, 'execute') or has_function_privilege('authenticated', v, 'execute')
       or not has_function_privilege('service_role', v, 'execute') then
      raise exception '0e: % não é só do service_role', v;
    end if;
  end loop;
  if to_regprocedure('public._retorno_letra_do_lote(integer)') is null then
    raise exception '0f: _retorno_letra_do_lote(integer) não existe';
  end if;
  select p.provolatile into v_f
    from pg_proc p where p.oid = to_regprocedure('public._retorno_letra_do_lote(integer)');
  if v_f.provolatile <> 'i'
     or has_function_privilege('anon', 'public._retorno_letra_do_lote(integer)', 'execute')
     or has_function_privilege('authenticated', 'public._retorno_letra_do_lote(integer)', 'execute') then
    raise exception '0f: _retorno_letra_do_lote não é IMMUTABLE ou está aberta a anon/authenticated';
  end if;

  -- ── 1. As letras ──────────────────────────────────────────────────────────────────────────────────────
  -- 1a. As 23 primeiras são as da especificação: A … Z sem E, I, N, O e S; depois AA, AB.
  select array_agg(public._retorno_letra_do_lote(g) order by g) into v_letras from generate_series(1, 23) g;
  if v_letras is distinct from c_letras then
    raise exception '1a: as 23 primeiras letras não são as da especificação: %', v_letras;
  end if;
  -- 1b. A passagem para duas e três letras.
  if public._retorno_letra_do_lote(42) is distinct from 'AZ' or public._retorno_letra_do_lote(43) is distinct from 'BA'
     or public._retorno_letra_do_lote(462) is distinct from 'ZZ' or public._retorno_letra_do_lote(463) is distinct from 'AAA' then
    raise exception '1b: a passagem para duas e três letras errou (42 %, 43 %, 462 %, 463 %)',
      public._retorno_letra_do_lote(42), public._retorno_letra_do_lote(43),
      public._retorno_letra_do_lote(462), public._retorno_letra_do_lote(463);
  end if;
  -- 1c. Fora de n >= 1: nula.
  if public._retorno_letra_do_lote(0) is not null or public._retorno_letra_do_lote(-1) is not null
     or public._retorno_letra_do_lote(null) is not null then
    raise exception '1c: posição fora de n >= 1 deu letra';
  end if;
  -- 1d. Em 1.000 posições, nenhuma letra repete, e nenhuma usa E, I, N, O, S ou sai de A–Z.
  select count(distinct x.l), count(*) filter (where x.l is null or x.l !~ '^[A-Z]+$' or x.l ~ '[EINOS]')
    into v_n, v_n2
    from (select public._retorno_letra_do_lote(g) as l from generate_series(1, 1000) g) x;
  if v_n <> 1000 or v_n2 <> 0 then
    raise exception '1d: em 1.000 posições, % letras distintas e % com E, I, N, O, S ou fora de A–Z', v_n, v_n2;
  end if;

  -- ── 2. O arranjo, desfeito no fim do sub-bloco ────────────────────────────────────────────────────────
  select clientes_parceiros into v_parceiros_antes from public.retorno_config where id;
  if not found then
    raise exception '2: retorno_config sem a linha de configuração';
  end if;

  begin
    -- Os 7 "unico", inseridos fora da ordem de nome. O nome curto vem do display_name quando há (Abel, Dora,
    -- Érico, Fábio, Gil), do name quando não há (Bruna) e quando o display_name está em branco (Caio).
    -- Os telefones vão noutra ordem (Dora 9601, Fábio 9602, Bruna 9603, Gil 9604, Caio 9605, Érico 9606,
    -- Abel 9607), sem nenhuma posição igual à da ordem de nome: a ordem pelo telefone ou pela chave (o
    -- desempate da função) nunca passa no 3b, nem a pelo nome com acento (Érico iria para o fim).
    insert into public.clients (type, name, display_name, whatsapp)
      values ('individual', 'Teste F1 vínculos Gil', 'Gil F1 vínculos', '(47) 90000-9604') returning id into v_c_gil;
    insert into public.clients (type, name, display_name, phone)
      values ('individual', 'Caio Teste F1 vínculos', '   ', '47 90000-9605') returning id into v_c_caio;
    insert into public.clients (type, name, display_name, whatsapp)
      values ('individual', 'Teste F1 vínculos Érico', 'Érico F1 vínculos', '(47) 90000-9606') returning id into v_c_erico;
    insert into public.clients (type, name, display_name, whatsapp)
      values ('individual', 'Teste F1 vínculos Abel', 'Abel F1 vínculos', '(47) 90000-9607') returning id into v_c_abel;
    insert into public.clients (type, name, display_name, whatsapp)
      values ('company', 'Teste F1 vínculos Fábio', 'Fábio F1 vínculos', '(47) 90000-9602') returning id into v_c_fabio;
    insert into public.clients (type, name, display_name, whatsapp)
      values ('individual', 'Teste F1 vínculos Dora', 'DORA F1 VÍNCULOS', '(47) 90000-9601') returning id into v_c_dora;
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Bruna Teste F1 vínculos', '(47) 90000-9603') returning id into v_c_bruna;
    -- Um telefone de dois clientes: compartilhado.
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Teste F1 vínculos dois A', '(47) 90000-9610') returning id into v_c_dois_a;
    insert into public.clients (type, name, phone)
      values ('company', 'Teste F1 vínculos dois B', '47 90000-9610') returning id into v_c_dois_b;
    -- Cliente que também é parceiro (entra em clientes_parceiros abaixo).
    insert into public.clients (type, name, whatsapp)
      values ('company', 'Teste F1 vínculos parceiro', '(47) 90000-9611') returning id into v_c_parc;
    -- O do lead já vinculado; o "Cliente Final" (genérico) e o inativo, que nunca identificam; o do lead
    -- pendente que já tem linked_client_id.
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Teste F1 vínculos já vinculado', '(47) 90000-9612') returning id into v_c_link;
    insert into public.clients (type, name, whatsapp, generico)
      values ('individual', 'Teste F1 vínculos Cliente Final', '(47) 90000-9614', true) returning id into v_c_generico;
    insert into public.clients (type, name, whatsapp, active)
      values ('individual', 'Teste F1 vínculos inativo', '(47) 90000-9615', false) returning id into v_c_inativo;
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Teste F1 vínculos meio vinculado', '(47) 90000-9616') returning id into v_c_semi;
    -- Fornecedor ativo; e a equipe (payee) com o número também num cadastro de cliente.
    insert into public.suppliers (name, phone, active)
      values ('Teste F1 vínculos fornecedor', '(47) 90000-9617', true) returning id into v_forn;
    insert into public.payees (name, phone)
      values ('Teste F1 vínculos equipe', '(47) 90000-9618') returning id into v_payee;
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Teste F1 vínculos da equipe', '(47) 90000-9618') returning id into v_c_equipe;
    -- Os clientes com que um grupo e uma lista de transmissão casariam pela chave.
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Teste F1 vínculos do grupo', '(47) 90000-9620') returning id into v_c_grupo;
    insert into public.clients (type, name, whatsapp)
      values ('individual', 'Teste F1 vínculos da transmissão', '(47) 90000-9621') returning id into v_c_transm;

    -- Os leads, em outra ordem, com nomes que ordenariam ao contrário (o nome do lead nunca entra).
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009603', 'Lead F1 vínculos Y') returning id into v_l_bruna;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009604', 'Lead F1 vínculos A') returning id into v_l_gil;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009607', 'Lead F1 vínculos Z') returning id into v_l_abel;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009606', 'Lead F1 vínculos C') returning id into v_l_erico;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009605', 'Lead F1 vínculos X') returning id into v_l_caio;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009602', 'Lead F1 vínculos B') returning id into v_l_fabio;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009601', 'Lead F1 vínculos W') returning id into v_l_dora;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009610', 'Lead F1 vínculos dois') returning id into v_l_dois;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009611', 'Lead F1 vínculos parceiro') returning id into v_l_parc;
    insert into public.whatsapp_leads (phone_normalized, name, status, linked_client_id)
      values ('5547900009612', 'Lead F1 vínculos já vinculado', 'linked', v_c_link) returning id into v_l_link;
    -- O mesmo nome do cliente Abel, de outro telefone: nome nunca identifica.
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009613', 'Teste F1 vínculos Abel') returning id into v_l_nome;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009614', 'Lead F1 vínculos Cliente Final') returning id into v_l_generico;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009615', 'Lead F1 vínculos inativo') returning id into v_l_inativo;
    insert into public.whatsapp_leads (phone_normalized, name, linked_client_id)
      values ('5547900009616', 'Lead F1 vínculos meio vinculado', v_c_semi) returning id into v_l_semi;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009617', 'Lead F1 vínculos fornecedor') returning id into v_l_forn;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('5547900009618', 'Lead F1 vínculos equipe') returning id into v_l_equipe;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('teste-f1-vinculos-96', 'Lead F1 vínculos sem chave') returning id into v_l_sem_chave;
    insert into public.whatsapp_leads (phone_normalized, name)
      values ('1203630000009620@g.us', 'Lead F1 vínculos grupo') returning id into v_l_grupo;
    insert into public.whatsapp_leads (phone_normalized, name, is_broadcast)
      values ('5547900009621', 'Lead F1 vínculos transmissão', true) returning id into v_l_transm;

    v_sinteticos := array[v_c_abel, v_c_bruna, v_c_caio, v_c_dora, v_c_erico, v_c_fabio, v_c_gil, v_c_dois_a, v_c_dois_b,
                          v_c_link, v_c_generico, v_c_inativo, v_c_semi, v_c_equipe, v_c_grupo, v_c_transm];
    v_leads_todos := array[v_l_abel, v_l_bruna, v_l_caio, v_l_dora, v_l_erico, v_l_fabio, v_l_gil, v_l_dois, v_l_parc,
                           v_l_link, v_l_nome, v_l_generico, v_l_inativo, v_l_semi, v_l_forn, v_l_equipe, v_l_sem_chave,
                           v_l_grupo, v_l_transm];

    -- Isola dos leads reais: todo cliente fora de v_sinteticos (os reais, inclusive a MP e a Förtro, e o
    -- parceiro sintético) vai para clientes_parceiros. Os leads reais saem "parceiro", sem letra.
    update public.retorno_config
       set clientes_parceiros = array(select c.id from public.clients c where c.id <> all (v_sinteticos) order by c.id)
     where id;

    -- As mensagens do número do Abel: sem client_id (recebida e enviada), com outro client_id (a da Bruna),
    -- o mesmo número sem o 55, o mesmo final de 8 dígitos noutro DDD; e uma do número da Bruna.
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status)
      values ('inbound', '5547900009607', 'text', 'teste F1 vínculos 1', 'received') returning id into v_m_in;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status)
      values ('outbound', '5547900009607', 'text', 'teste F1 vínculos 2', 'sent') returning id into v_m_out;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, client_id)
      values ('inbound', '5547900009607', 'text', 'teste F1 vínculos 3', 'received', v_c_bruna) returning id into v_m_outro;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status)
      values ('inbound', '47900009607', 'text', 'teste F1 vínculos 4', 'received') returning id into v_m_sem55;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status)
      values ('inbound', '5511900009607', 'text', 'teste F1 vínculos 5', 'received') returning id into v_m_outro_ddd;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status)
      values ('inbound', '5547900009603', 'text', 'teste F1 vínculos 6', 'received') returning id into v_m_outra_chave;

    -- A lista inteira, na ordem em que a função devolve.
    select coalesce(jsonb_agg(jsonb_build_object('letra', r.letra, 'lead_id', r.lead_id, 'phone', r.phone, 'tipo', r.tipo,
                                                 'clientes', r.clientes, 'ord', r.ord) order by r.ord), '[]'::jsonb)
      into v_lista
      from public.retorno_vinculos_candidatos() with ordinality as r(letra, lead_id, phone, tipo, clientes, ord);

    -- Sem a linha de configuração as duas funções levantam 55000 (falha fecha).
    begin
      delete from public.retorno_config;
      begin
        perform count(*) from public.retorno_vinculos_candidatos();
        v_sem_cfg_lista := 'não subiu';
      exception when others then
        v_sem_cfg_lista := sqlstate;
      end;
      begin
        perform public.retorno_vincular_lead(v_l_bruna, v_c_bruna);
        v_sem_cfg_vincular := 'não subiu';
      exception when others then
        v_sem_cfg_vincular := sqlstate;
      end;
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;

    -- O vínculo do unico (Abel): o lead, as mensagens e o audit_log.
    r_um := public.retorno_vincular_lead(v_l_abel, v_c_abel);
    select jsonb_build_object('status', l.status, 'linked_client_id', l.linked_client_id) into v_lead_abel
      from public.whatsapp_leads l where l.id = v_l_abel;
    select jsonb_object_agg(m.id::text, coalesce(m.client_id::text, 'nulo')) into v_msgs
      from public.whatsapp_messages m
     where m.id in (v_m_in, v_m_out, v_m_outro, v_m_sem55, v_m_outro_ddd, v_m_outra_chave);
    select count(*), (array_agg(to_jsonb(a)))[1] into v_audit_n, v_audit
      from public.audit_log a where a.table_name = 'whatsapp_leads' and a.record_id = v_l_abel;

    -- A 2ª chamada e as recusas.
    r_de_novo := public.retorno_vincular_lead(v_l_abel, v_c_abel);
    select jsonb_object_agg(m.id::text, coalesce(m.client_id::text, 'nulo')) into v_msgs_de_novo
      from public.whatsapp_messages m
     where m.id in (v_m_in, v_m_out, v_m_outro, v_m_sem55, v_m_outro_ddd, v_m_outra_chave);
    r_compart := public.retorno_vincular_lead(v_l_dois, v_c_dois_a);
    r_nao_casa := public.retorno_vincular_lead(v_l_bruna, v_c_caio);
    r_parceiro := public.retorno_vincular_lead(v_l_parc, v_c_parc);
    r_inexistente := public.retorno_vincular_lead(gen_random_uuid(), v_c_abel);
    r_link := public.retorno_vincular_lead(v_l_link, v_c_link);
    r_semi := public.retorno_vincular_lead(v_l_semi, v_c_semi);
    r_generico := public.retorno_vincular_lead(v_l_generico, v_c_generico);
    r_equipe := public.retorno_vincular_lead(v_l_equipe, v_c_equipe);
    r_grupo := public.retorno_vincular_lead(v_l_grupo, v_c_grupo);
    r_transm := public.retorno_vincular_lead(v_l_transm, v_c_transm);

    select jsonb_object_agg(l.id::text, jsonb_build_object('status', l.status, 'linked_client_id', l.linked_client_id))
      into v_leads_final
      from public.whatsapp_leads l where l.id = any (v_leads_todos);
    select jsonb_object_agg(m.id::text, coalesce(m.client_id::text, 'nulo')) into v_msgs_final
      from public.whatsapp_messages m
     where m.id in (v_m_in, v_m_out, v_m_outro, v_m_sem55, v_m_outro_ddd, v_m_outra_chave);
    select count(*) into v_audit_n_final
      from public.audit_log a where a.table_name = 'whatsapp_leads' and a.record_id = any (v_leads_todos);

    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if not v_chegou then
    raise exception '2a: o arranjo não chegou ao fim';
  end if;
  if exists (select 1 from public.clients where id in (v_c_abel, v_c_parc, v_c_dois_a))
     or exists (select 1 from public.whatsapp_leads where id in (v_l_abel, v_l_bruna))
     or exists (select 1 from public.audit_log where table_name = 'whatsapp_leads' and record_id = v_l_abel)
     or (select clientes_parceiros from public.retorno_config where id) is distinct from v_parceiros_antes then
    raise exception '2b: o arranjo não foi desfeito';
  end if;

  -- ── 3. A lista ────────────────────────────────────────────────────────────────────────────────────────
  -- 3a. Toda linha no contrato C-VINC: tipo da lista fechada; letra só no unico; clientes = [{id, nome}].
  for v_r in select e.value as linha from jsonb_array_elements(v_lista) e loop
    if coalesce(v_r.linha ->> 'tipo', '') not in ('unico', 'compartilhado', 'parceiro')
       or ((v_r.linha ->> 'tipo') = 'unico') is distinct from (jsonb_typeof(v_r.linha -> 'letra') = 'string')
       or jsonb_typeof(v_r.linha -> 'lead_id') is distinct from 'string'
       or jsonb_typeof(v_r.linha -> 'phone') is distinct from 'string'
       or jsonb_typeof(v_r.linha -> 'clientes') is distinct from 'array'
       or jsonb_array_length(v_r.linha -> 'clientes') < 1
       or exists (select 1 from jsonb_array_elements(v_r.linha -> 'clientes') c
                   where case when jsonb_typeof(c.value) = 'object'
                              then (select array_agg(k order by k collate "C") from jsonb_object_keys(c.value) k)
                         end is distinct from array['id', 'nome']) then
      raise exception '3a: linha fora do contrato C-VINC: %', v_r.linha;
    end if;
  end loop;
  select count(*), count(distinct e.value ->> 'lead_id') into v_n, v_n2 from jsonb_array_elements(v_lista) e;
  if v_n <> v_n2 then
    raise exception '3a: um lead apareceu duas vezes na lista (% linhas, % leads)', v_n, v_n2;
  end if;

  -- 3b. Os unico são só os 7 sintéticos, em ordem de nome curto (sem acento), nunca pelo nome do lead nem
  --     pelo telefone ou pela chave (os telefones vão noutra ordem).
  select array_agg((e.value ->> 'lead_id')::uuid order by (e.value ->> 'ord')::int),
         array_agg(e.value ->> 'letra' order by (e.value ->> 'ord')::int),
         array_agg(e.value -> 'clientes' -> 0 ->> 'nome' order by (e.value ->> 'ord')::int)
    into v_ids, v_letras, v_nomes
    from jsonb_array_elements(v_lista) e where e.value ->> 'tipo' = 'unico';
  if v_ids is distinct from array[v_l_abel, v_l_bruna, v_l_caio, v_l_dora, v_l_erico, v_l_fabio, v_l_gil] then
    raise exception '3b: os unico não são os 7 sintéticos em ordem de nome: % (nomes %)', v_ids, v_nomes;
  end if;
  -- 3c. Com 7 unico, as letras são A, B, C, D, F, G, H (sem E).
  if v_letras is distinct from array['A', 'B', 'C', 'D', 'F', 'G', 'H'] then
    raise exception '3c: com 7 unico, as letras não são A, B, C, D, F, G, H: %', v_letras;
  end if;
  -- 3d. O nome curto: o display_name quando há; o name quando não há ou está em branco.
  if v_nomes is distinct from array['Abel', 'Bruna', 'Caio', 'Dora', 'Érico', 'Fábio', 'Gil'] then
    raise exception '3d: os nomes curtos dos unico erraram: %', v_nomes;
  end if;

  -- 3e. O telefone que casa com 1 cliente ativo: unico, letra A, o telefone do lead e só o cliente dele.
  select e.value into v_linha from jsonb_array_elements(v_lista) e where (e.value ->> 'lead_id')::uuid = v_l_abel;
  if v_linha ->> 'tipo' is distinct from 'unico' or v_linha ->> 'letra' is distinct from 'A'
     or v_linha ->> 'phone' is distinct from '5547900009607'
     or v_linha -> 'clientes' is distinct from jsonb_build_array(jsonb_build_object('id', v_c_abel, 'nome', 'Abel')) then
    raise exception '3e: o lead de 1 cliente não saiu unico com a letra A: %', v_linha;
  end if;
  -- 3f. O telefone de 2 clientes: compartilhado, sem letra, com os dois.
  v_linha := null;
  select e.value into v_linha from jsonb_array_elements(v_lista) e where (e.value ->> 'lead_id')::uuid = v_l_dois;
  if v_linha ->> 'tipo' is distinct from 'compartilhado' or jsonb_typeof(v_linha -> 'letra') is distinct from 'null'
     or jsonb_array_length(v_linha -> 'clientes') is distinct from 2
     or (select array_agg(c.value ->> 'id' order by c.value ->> 'id') from jsonb_array_elements(v_linha -> 'clientes') c)
        is distinct from (select array_agg(x::text order by x::text) from unnest(array[v_c_dois_a, v_c_dois_b]) x) then
    raise exception '3f: o telefone de 2 clientes não saiu compartilhado sem letra: %', v_linha;
  end if;
  -- 3g. O cliente em clientes_parceiros: parceiro, sem letra.
  v_linha := null;
  select e.value into v_linha from jsonb_array_elements(v_lista) e where (e.value ->> 'lead_id')::uuid = v_l_parc;
  if v_linha ->> 'tipo' is distinct from 'parceiro' or jsonb_typeof(v_linha -> 'letra') is distinct from 'null'
     or v_linha -> 'clientes' -> 0 ->> 'id' is distinct from v_c_parc::text
     or jsonb_array_length(v_linha -> 'clientes') is distinct from 1 then
    raise exception '3g: o cliente parceiro não saiu parceiro sem letra: %', v_linha;
  end if;
  -- 3h. Não aparecem: o já vinculado (linked, e o pendente com linked_client_id); o do mesmo nome de outro
  --     telefone; o do "Cliente Final"; o do inativo; fornecedor; equipe; sem chave; grupo; transmissão.
  v_fora := jsonb_build_object('ja_vinculado', v_l_link, 'pendente_com_vinculo', v_l_semi, 'mesmo_nome', v_l_nome,
                               'cliente_final', v_l_generico, 'inativo', v_l_inativo, 'fornecedor', v_l_forn,
                               'equipe', v_l_equipe, 'sem_chave', v_l_sem_chave, 'grupo', v_l_grupo,
                               'transmissao', v_l_transm);
  for v_r in select f.key as rotulo, (f.value #>> '{}')::uuid as lead from jsonb_each(v_fora) f loop
    if exists (select 1 from jsonb_array_elements(v_lista) e where (e.value ->> 'lead_id')::uuid = v_r.lead) then
      raise exception '3h (%): o lead apareceu na lista', v_r.rotulo;
    end if;
  end loop;
  -- 3i. Nenhum nome completo (de cliente ou de lead) na lista: só o nome curto do cliente.
  if position('F1 v' in v_lista::text) > 0 then
    raise exception '3i: um nome completo apareceu na lista';
  end if;

  -- ── 4. O vínculo ──────────────────────────────────────────────────────────────────────────────────────
  -- 4a. O unico: ok, com as 3 mensagens do mesmo telefone que estavam sem client_id.
  if r_um is distinct from '{"ok": true, "mensagens": 3}'::jsonb then
    raise exception '4a: o vínculo do unico não devolveu {"ok": true, "mensagens": 3}: %', r_um;
  end if;
  if v_lead_abel is distinct from jsonb_build_object('status', 'linked', 'linked_client_id', v_c_abel) then
    raise exception '4b: o lead não ficou linked com o cliente: %', v_lead_abel;
  end if;
  -- 4c. As sem client_id do mesmo telefone (com e sem o 55, recebida e enviada) ficam preenchidas; a que já
  --     tinha outro client_id fica intacta; a de outro DDD e a de outro número ficam nulas.
  if v_msgs ->> v_m_in::text is distinct from v_c_abel::text or v_msgs ->> v_m_out::text is distinct from v_c_abel::text
     or v_msgs ->> v_m_sem55::text is distinct from v_c_abel::text then
    raise exception '4c: as mensagens sem client_id do mesmo telefone não ficaram com o cliente: %', v_msgs;
  end if;
  if v_msgs ->> v_m_outro::text is distinct from v_c_bruna::text then
    raise exception '4d: o vínculo sobrescreveu o client_id que a mensagem já tinha: %', v_msgs;
  end if;
  if v_msgs ->> v_m_outro_ddd::text is distinct from 'nulo' or v_msgs ->> v_m_outra_chave::text is distinct from 'nulo' then
    raise exception '4e: a mensagem de outro DDD ou de outro número ganhou o cliente: %', v_msgs;
  end if;
  -- 4f. Uma linha em audit_log, com o que vinculou (e os ids, para desfazer).
  if v_audit_n is distinct from 1 then
    raise exception '4f: o vínculo gravou % linhas em audit_log (esperada 1)', v_audit_n;
  end if;
  if v_audit ->> 'action' is distinct from 'update' or v_audit ->> 'changed_by' is distinct from 'retorno'
     or v_audit ->> 'reason' is distinct from 'Lote de vínculos (sim do dono)'
     or v_audit -> 'new_value' is distinct from jsonb_build_object('client_id', v_c_abel, 'mensagens', 3)
     or v_audit -> 'previous_value' ->> 'status' is distinct from 'pending'
     or jsonb_typeof(v_audit -> 'previous_value' -> 'linked_client_id') is distinct from 'null'
     or (select array_agg(x order by x) from jsonb_array_elements_text(v_audit -> 'previous_value' -> 'mensagens_sem_cliente') x)
        is distinct from (select array_agg(y::text order by y::text) from unnest(array[v_m_in, v_m_out, v_m_sem55]) y) then
    raise exception '4f: a linha de audit_log está errada: %', v_audit;
  end if;
  -- 4g. A 2ª chamada: estado, sem mexer em mensagem nem gravar outra linha.
  if r_de_novo is distinct from '{"ok": false, "motivo": "estado"}'::jsonb then
    raise exception '4g: a 2ª chamada não devolveu estado: %', r_de_novo;
  end if;
  if v_msgs_de_novo is distinct from v_msgs or v_msgs_final is distinct from v_msgs then
    raise exception '4g: a 2ª chamada ou uma recusa mexeu nas mensagens: % → %', v_msgs, v_msgs_final;
  end if;
  if v_audit_n_final is distinct from 1 then
    raise exception '4g: as recusas gravaram em audit_log (% linhas no fim)', v_audit_n_final;
  end if;
  -- 4h. Cada recusa com o seu motivo.
  v_recusas := jsonb_build_object(
    'compartilhado', jsonb_build_array(r_compart, 'compartilhado'),
    'cliente_diferente', jsonb_build_array(r_nao_casa, 'nao_casa'),
    'parceiro', jsonb_build_array(r_parceiro, 'parceiro'),
    'lead_inexistente', jsonb_build_array(r_inexistente, 'estado'),
    'ja_vinculado', jsonb_build_array(r_link, 'estado'),
    'pendente_com_vinculo', jsonb_build_array(r_semi, 'estado'),
    'grupo', jsonb_build_array(r_grupo, 'estado'),
    'transmissao', jsonb_build_array(r_transm, 'estado'),
    'cliente_final', jsonb_build_array(r_generico, 'nao_casa'),
    'equipe', jsonb_build_array(r_equipe, 'nao_casa'));
  for v_r in select k.key as rotulo, k.value -> 0 as resposta, k.value ->> 1 as motivo from jsonb_each(v_recusas) k loop
    if v_r.resposta is distinct from jsonb_build_object('ok', false, 'motivo', v_r.motivo) then
      raise exception '4h (%): esperado {"ok": false, "motivo": "%"}, veio %', v_r.rotulo, v_r.motivo, v_r.resposta;
    end if;
  end loop;
  -- 4i. Só o lead do Abel mudou: os outros ficam como nasceram.
  if v_leads_final -> v_l_abel::text is distinct from jsonb_build_object('status', 'linked', 'linked_client_id', v_c_abel)
     or v_leads_final -> v_l_link::text is distinct from jsonb_build_object('status', 'linked', 'linked_client_id', v_c_link)
     or v_leads_final -> v_l_semi::text is distinct from jsonb_build_object('status', 'pending', 'linked_client_id', v_c_semi) then
    raise exception '4i: o estado final dos leads vinculados errou: %', v_leads_final;
  end if;
  for v_r in select x as lead from unnest(array[v_l_bruna, v_l_caio, v_l_dora, v_l_erico, v_l_fabio, v_l_gil, v_l_dois,
                                                v_l_parc, v_l_nome, v_l_generico, v_l_inativo, v_l_forn, v_l_equipe,
                                                v_l_sem_chave, v_l_grupo, v_l_transm]) x loop
    if v_leads_final -> v_r.lead::text is distinct from '{"status": "pending", "linked_client_id": null}'::jsonb then
      raise exception '4i: um lead recusado mudou: % → %', v_r.lead, v_leads_final -> v_r.lead::text;
    end if;
  end loop;
  -- 4j. Sem a linha de configuração: 55000 nas duas.
  if v_sem_cfg_lista is distinct from '55000' or v_sem_cfg_vincular is distinct from '55000' then
    raise exception '4j: sem a linha de configuração não levantou 55000 (lista %, vínculo %)', v_sem_cfg_lista, v_sem_cfg_vincular;
  end if;

  -- ── 5. Grants: 42501 de verdade, chamando como anon e como authenticated ───────────────────────────────
  v := pg_temp.retorno_f1_vinculos_como('anon', null, $q$select count(*)::text from public.retorno_vinculos_candidatos()$q$);
  if v is distinct from 'erro 42501' then
    raise exception '5a: anon chamou retorno_vinculos_candidatos (%)', v;
  end if;
  v := pg_temp.retorno_f1_vinculos_como('authenticated', c_sem_cargo, $q$select count(*)::text from public.retorno_vinculos_candidatos()$q$);
  if v is distinct from 'erro 42501' then
    raise exception '5b: authenticated chamou retorno_vinculos_candidatos (%)', v;
  end if;
  v := pg_temp.retorno_f1_vinculos_como('anon', null, $q$select public.retorno_vincular_lead(null::uuid, null::uuid)::text$q$);
  if v is distinct from 'erro 42501' then
    raise exception '5c: anon chamou retorno_vincular_lead (%)', v;
  end if;
  v := pg_temp.retorno_f1_vinculos_como('authenticated', c_sem_cargo, $q$select public.retorno_vincular_lead(null::uuid, null::uuid)::text$q$);
  if v is distinct from 'erro 42501' then
    raise exception '5d: authenticated chamou retorno_vincular_lead (%)', v;
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_vinculos', true,
          jsonb_build_object('lista', jsonb_array_length(v_lista), 'unicos', cardinality(v_ids), 'letras', v_letras,
                             'mensagens_vinculadas', r_um -> 'mensagens',
                             'recusas', (select count(*) from jsonb_object_keys(v_recusas)),
                             'fora_da_lista', (select count(*) from jsonb_object_keys(v_fora))));
end
$vinculos$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
