-- Retorno F4 (P2): quem_escreve com o parceiro, retorno_identificar, retorno_abrir e a triagem do parceiro nas regras 1 a 4
-- (as regras 5 a 8 agendam por parceiro_agendar, da P5, e são testadas em P5.3 e P10.2). Roda só pela bancada (grupo 7,
-- F4_ONDA=2). Termina em ROLLBACK. Telefones de teste 55479000141xx; nomes, siglas e frases inventados.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Uma recebida de texto de teste, na hora dada.
create or replace function pg_temp.retorno_f4_ident_msg(p_fone text, p_corpo text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at, hora_real)
  values ('inbound', p_fone, 'text', p_corpo, 'teste-f4-ident-' || md5(p_fone || p_corpo || p_em::text), p_em, p_em)
  returning id into v;
  return v;
end $f$;

do $ident$
declare
  c_t constant timestamptz := '2027-01-05 10:00-03';
  v_cfg public.retorno_config;
  v_mp uuid;                -- o cadastro de cliente da revenda de teste (como a MP)
  v_x uuid;                 -- outro cliente, dono de um número que também foi confirmado como da revenda
  v_y uuid;
  v_p_a uuid;               -- a revenda (com cadastro de cliente)
  v_p_b uuid;               -- o pátio (sem cadastro de cliente)
  v_p_c uuid;               -- um parceiro inativo
  v_carla uuid;
  v_compart uuid;
  v_bruna uuid;
  v_dora uuid;
  v_eva uuid;
  v_num_carla uuid;
  v_num_bruna uuid;
  v_num_compart uuid;
  v_lead1 uuid;
  v_lead2 uuid;
  q jsonb;
  v_r jsonb;
  v_m uuid;
  v_caso uuid;
  v_caso2 uuid;
  v_saida uuid;
  v_ab public.retorno_aberturas;
  v_n integer;
  v_t text;
  v_rec record;
  v_n_fun integer := 0;
begin
  begin
  -- O retorno em sombra, a identificação nova ligada e o parceiro em sombra (a regra 1 é testada à parte).
  update public.retorno_config
     set modo = 'sombra', identificacao_nova = true, parceiro_modo = 'sombra', tipos_ligados = '{}',
         carencia_min = 2, carencia_dono_ativo_min = 10, dono_ativo_janela_min = 15
   where id;
  select * into v_cfg from public.retorno_config;

  -- Arranjo. A revenda tem cadastro de cliente com dois telefones (whatsapp 14101, phone 14102).
  insert into public.clients (type, name, whatsapp, phone)
    values ('company', 'Revenda Ident F4 Ltda', '5547900014101', '5547900014102') returning id into v_mp;
  insert into public.clients (type, name, whatsapp) values ('individual', 'Ximena Ident F4', '5547900014105') returning id into v_x;
  insert into public.clients (type, name, phone) values ('individual', 'Yara Ident F4', '5547900014108') returning id into v_y;
  update public.retorno_config set clientes_parceiros = array[v_mp] where id;

  insert into public.parceiros (nome, sigla, tipo, client_id) values ('Revenda Ident F4', 'RIF', 'revenda_e_patio', v_mp) returning id into v_p_a;
  insert into public.parceiros (nome, sigla, tipo) values ('Pátio Ident F4', 'PIF', 'patio') returning id into v_p_b;
  insert into public.parceiros (nome, sigla, tipo, ativo) values ('Inativo Ident F4', 'IIF', 'revenda', false) returning id into v_p_c;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p_a, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p_a, null, 'comercial') returning id into v_compart;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p_b, 'Bruna', 'dono') returning id into v_bruna;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel, ativo) values (v_p_a, 'Dora', 'financeiro', false) returning id into v_dora;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p_c, 'Eva', 'comercial') returning id into v_eva;

  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em)
    values (v_carla, '5547900014101', '00014101', '47', 'confirmado', c_t - interval '1 day') returning id into v_num_carla;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em)
    values (v_compart, '5547900014103', '00014103', '47', 'confirmado', c_t - interval '1 day') returning id into v_num_compart;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em)
    values (v_bruna, '5547900014104', '00014104', '47', 'confirmado', c_t - interval '1 day') returning id into v_num_bruna;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em)
    values (v_carla, '5547900014105', '00014105', '47', 'confirmado', c_t - interval '1 day');
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao)
    values (v_carla, '5547900014106', '00014106', '47', 'proposto');
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao)
    values (v_carla, '5547900014107', '00014107', '47', 'pausado');
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao)
    values (v_carla, '5547900014108', '00014108', '47', 'recusado');
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em)
    values (v_carla, '5547900014109', '00014109', '48', 'confirmado', c_t - interval '1 day');
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em)
    values (v_dora, '5547900014110', '00014110', '47', 'confirmado', c_t - interval '1 day');
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em)
    values (v_eva, '5547900014111', '00014111', '47', 'confirmado', c_t - interval '1 day');

  -- 1. Número confirmado de parceiro sem cadastro de cliente: papel parceiro, com pessoa, parceiro e número.
  q := public.quem_escreve('5547900014104');
  if q ->> 'papel' is distinct from 'parceiro' or (q ->> 'pessoa_id')::uuid is distinct from v_bruna
     or (q ->> 'parceiro_id')::uuid is distinct from v_p_b or (q ->> 'numero_id')::uuid is distinct from v_num_bruna
     or q ->> 'chave' is distinct from '00014104' or q ->> 'ddd' is distinct from '47'
     or jsonb_typeof(q -> 'cliente_id') is distinct from 'null' then
    raise exception '1a: número confirmado do pátio (%)', q;
  end if;
  v_r := public.retorno_identificar('5547900014104');
  if v_r ->> 'papel' is distinct from 'parceiro' or jsonb_typeof(v_r -> 'client_id') is distinct from 'null' then
    raise exception '1b: retorno_identificar do pátio sem cadastro (%)', v_r;
  end if;

  -- 2. O número do cadastro da revenda, confirmado como pessoa: parceiro, com o cliente da revenda, e o client_id dela.
  q := public.quem_escreve('5547900014101');
  if q ->> 'papel' is distinct from 'parceiro' or (q ->> 'cliente_id')::uuid is distinct from v_mp
     or (q ->> 'pessoa_id')::uuid is distinct from v_carla or (q ->> 'parceiro_id')::uuid is distinct from v_p_a then
    raise exception '2a: número da revenda confirmado (%)', q;
  end if;
  v_r := public.retorno_identificar('5547900014101');
  if v_r ->> 'papel' is distinct from 'parceiro' or (v_r ->> 'client_id')::uuid is distinct from v_mp then
    raise exception '2b: retorno_identificar não devolveu o cliente da revenda (%)', v_r;
  end if;
  -- O outro telefone do cadastro da revenda, sem linha em parceiro_numeros, segue cliente, como hoje.
  q := public.quem_escreve('5547900014102');
  if q ->> 'papel' is distinct from 'cliente' or (q ->> 'cliente_id')::uuid is distinct from v_mp then
    raise exception '2c: o telefone da revenda fora de parceiro_numeros mudou (%)', q;
  end if;

  -- 3. Número confirmado da revenda que também é de outro cliente: o cliente vence.
  q := public.quem_escreve('5547900014105');
  if q ->> 'papel' is distinct from 'cliente' or (q ->> 'cliente_id')::uuid is distinct from v_x then
    raise exception '3: número de outro cliente virou parceiro (%)', q;
  end if;

  -- 4. Proposto, pausado ou recusado não mudam nada.
  foreach v_t in array array['5547900014106', '5547900014107'] loop
    q := public.quem_escreve(v_t);
    if q ->> 'papel' is distinct from 'novo' then
      raise exception '4a: número % não confirmado virou % (%)', v_t, q ->> 'papel', q;
    end if;
  end loop;
  q := public.quem_escreve('5547900014108');
  if q ->> 'papel' is distinct from 'cliente' or (q ->> 'cliente_id')::uuid is distinct from v_y then
    raise exception '4b: número recusado de cliente mudou (%)', q;
  end if;

  -- 5. DDD diferente não vira parceiro; nem pessoa inativa; nem parceiro inativo.
  foreach v_t in array array['5547900014109', '5547900014110', '5547900014111'] loop
    q := public.quem_escreve(v_t);
    if q ->> 'papel' is distinct from 'novo' then
      raise exception '5: número % virou % (%)', v_t, q ->> 'papel', q;
    end if;
  end loop;

  -- 6. O parceiro nunca recebe fato por retorno_fatos_do_contato.
  v_r := public.retorno_fatos_do_contato('5547900014101', c_t);
  if v_r -> 'os' is distinct from '[]'::jsonb or v_r ->> 'papel' is distinct from 'parceiro' then
    raise exception '6: fatos do contato do parceiro (%)', v_r;
  end if;

  -- 7. Lote de vínculos: o número confirmado sai da lista; o da revenda não confirmado continua 'parceiro', sem letra.
  insert into public.whatsapp_leads (phone_normalized, name) values ('5547900014101', 'Lead Ident F4 um') returning id into v_lead1;
  insert into public.whatsapp_leads (phone_normalized, name) values ('5547900014102', 'Lead Ident F4 dois') returning id into v_lead2;
  if exists (select 1 from public.retorno_vinculos_candidatos() c where c.lead_id = v_lead1) then
    raise exception '7a: o número confirmado da revenda ficou no lote de vínculos';
  end if;
  select * into v_rec from public.retorno_vinculos_candidatos() c where c.lead_id = v_lead2;
  if not found or v_rec.tipo is distinct from 'parceiro' or v_rec.letra is not null then
    raise exception '7b: o número não confirmado da revenda saiu do lote ou ganhou letra';
  end if;

  -- 9. Com parceiro_modo = 'desligado' (regra 1): o caso abre em nada/parceiro_f4 e nenhuma saída nasce.
  update public.retorno_config set parceiro_modo = 'desligado' where id;
  v_m := pg_temp.retorno_f4_ident_msg('5547900014103', 'como está o motorhome do cliente?', c_t);
  v_r := public.retorno_abrir(v_m, false, c_t + interval '5 seconds');
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'acao' is distinct from 'nova' or v_r ->> 'papel' is distinct from 'parceiro'
     or v_r ->> 'nivel' is distinct from 'nada' or v_r ->> 'motivo' is distinct from 'parceiro_f4' then
    raise exception '9a: abertura com o parceiro desligado (%)', v_r;
  end if;
  v_caso := (v_r ->> 'abertura_id')::uuid;
  select * into v_ab from public.retorno_aberturas a where a.id = v_caso;
  if v_ab.tipo_recibo is not null or v_ab.client_id is distinct from v_mp or v_ab.intencao is distinct from 'outro' then
    raise exception '9b: o caso do parceiro desligado gravou tipo de recibo, cliente ou intenção errados';
  end if;
  if exists (select 1 from public.retorno_saidas s where s.abertura_id = v_caso) then
    raise exception '9c: o parceiro desligado ganhou saída';
  end if;
  -- Regra 1 antes da 2: tudo consumido, mas desligado, continua parceiro_f4.
  update public.retorno_mensagens set consumida = true where abertura_id = v_caso;
  v_r := public._retorno_triar(v_caso, c_t + interval '1 minute');
  if v_r ->> 'motivo' is distinct from 'parceiro_f4' then
    raise exception '9d: a regra 1 não veio antes da 2 (%)', v_r;
  end if;

  -- 10. O rótulo: a sigla e a pessoa (ou "comercial"), nunca dígito.
  v_t := public._retorno_rotulo(v_caso, c_t + interval '1 minute');
  if v_t is distinct from 'RIF (comercial)' or v_t ~ '[0-9]' then
    raise exception '10a: rótulo do número compartilhado (%)', v_t;
  end if;

  -- 8 e 12. Regra 2 pelo caminho real: *pátio*, *pausar* e *retomar* consumidas, com o parceiro em sombra: nada/agenda_consumiu,
  --         sem recibo.
  update public.retorno_config set parceiro_modo = 'sombra' where id;
  v_m := pg_temp.retorno_f4_ident_msg('5547900014101', 'pátio', c_t + interval '1 hour');
  v_r := public.retorno_abrir(v_m, true, c_t + interval '1 hour 5 seconds');
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'nivel' is distinct from 'nada' or v_r ->> 'motivo' is distinct from 'agenda_consumiu' then
    raise exception '12a: pátio consumido (%)', v_r;
  end if;
  v_caso2 := (v_r ->> 'abertura_id')::uuid;
  foreach v_t in array array['pausar', 'retomar'] loop
    v_m := pg_temp.retorno_f4_ident_msg('5547900014101', v_t, c_t + interval '1 hour 1 minute');
    v_r := public.retorno_abrir(v_m, true, c_t + interval '1 hour 1 minute 5 seconds');
    if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'abertura_id')::uuid is distinct from v_caso2
       or v_r ->> 'nivel' is distinct from 'nada' or v_r ->> 'motivo' is distinct from 'agenda_consumiu' then
      raise exception '12b: % consumido (%)', v_t, v_r;
    end if;
  end loop;
  if exists (select 1 from public.retorno_saidas s where s.abertura_id = v_caso2) then
    raise exception '12c: palavra consumida do parceiro ganhou saída';
  end if;
  select * into v_ab from public.retorno_aberturas a where a.id = v_caso2;
  if v_ab.tipo_recibo is not null or v_ab.papel is distinct from 'parceiro' then
    raise exception '12d: o caso das palavras consumidas gravou tipo de recibo';
  end if;
  v_t := public._retorno_rotulo(v_caso2, c_t + interval '2 hours');
  if v_t is distinct from 'RIF (Carla)' or v_t ~ '[0-9]' then
    raise exception '10b: rótulo da pessoa com nome (%)', v_t;
  end if;

  -- 8. Regra 3 (nada pede resposta) e regra 4 (canal), direto na triagem; cada uma cancela a agendada do caso.
  --    Caso sintético do pátio, com uma mensagem que não pede resposta.
  update public.retorno_aberturas set estado = 'fechada', fechada_em = c_t + interval '2 hours', fechada_motivo = 'dono'
   where id in (v_caso, v_caso2);
  v_m := pg_temp.retorno_f4_ident_msg('5547900014104', 'obrigada', c_t + interval '3 hours');
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, primeira_msg_id, ultima_msg_id, aberta_em, gravada_em,
                                        ultima_em, ultima_gravada_em, nivel, motivo, modo)
    values ('00014104', '5547900014104', '47', 'parceiro', public.quem_escreve('5547900014104'), v_m, v_m,
            c_t + interval '3 hours', c_t + interval '3 hours', c_t + interval '3 hours', c_t + interval '3 hours',
            'nada', 'nao_pede_resposta', 'sombra')
    returning id into v_caso;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta, pede_motivo)
    values (v_m, v_caso, '00014104', c_t + interval '3 hours', c_t + interval '3 hours', md5('obrigada'), false, 'agradecimento');
  insert into public.retorno_saidas (emissor, abertura_id, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
    values ('parceiro', v_caso, 'parceiro_recibo', 'retorno_parceiro', 'resposta_imediata', '00014104', '5547900014104', 'sombra',
            c_t + interval '3 hours 30 minutes', 'teste-f4-ident:8:recibo')
    returning id into v_saida;
  v_r := public._retorno_triar(v_caso, c_t + interval '3 hours 1 minute');
  select * into v_ab from public.retorno_aberturas a where a.id = v_caso;
  if v_r ->> 'motivo' is distinct from 'nao_pede_resposta' or v_ab.nivel is distinct from 'nada'
     or v_ab.motivo is distinct from 'nao_pede_resposta' or v_ab.tipo_recibo is not null then
    raise exception '8a: regra 3 (%)', v_r;
  end if;
  if (select s.estado || '/' || coalesce(s.motivo, '') from public.retorno_saidas s where s.id = v_saida) is distinct from 'cancelada/nivel_nada' then
    raise exception '8b: a regra 3 não cancelou a agendada do caso';
  end if;
  -- Regra 4: agora a mensagem pede resposta, mas o número está na lista de bloqueio (spam) e depois com opt-out.
  update public.retorno_mensagens set pede_resposta = true, pede_motivo = null where whatsapp_message_id = v_m;
  insert into public.retorno_saidas (emissor, abertura_id, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
    values ('parceiro', v_caso, 'parceiro_recibo', 'retorno_parceiro', 'resposta_imediata', '00014104', '5547900014104', 'sombra',
            c_t + interval '3 hours 30 minutes', 'teste-f4-ident:8:recibo2')
    returning id into v_saida;
  insert into public.whatsapp_blocked_numbers (phone_normalized, reason, tipo, created_at)
    values ('5547900014104', 'Teste F4 identificação', 'spam', c_t - interval '1 day');
  v_r := public._retorno_triar(v_caso, c_t + interval '3 hours 2 minutes');
  select * into v_ab from public.retorno_aberturas a where a.id = v_caso;
  if v_r ->> 'motivo' is distinct from 'bloqueado' or v_ab.nivel is distinct from 'nada' or v_ab.motivo is distinct from 'bloqueado'
     or v_ab.tipo_recibo is not null then
    raise exception '8c: regra 4, bloqueado (%)', v_r;
  end if;
  if (select s.estado || '/' || coalesce(s.motivo, '') from public.retorno_saidas s where s.id = v_saida) is distinct from 'cancelada/nivel_nada' then
    raise exception '8d: a regra 4 não cancelou a agendada do caso';
  end if;
  update public.whatsapp_blocked_numbers set tipo = 'opt_out' where phone_normalized = '5547900014104' and reason = 'Teste F4 identificação';
  v_r := public._retorno_triar(v_caso, c_t + interval '3 hours 3 minutes');
  if v_r ->> 'motivo' is distinct from 'opt_out' then
    raise exception '8e: regra 4, opt-out (%)', v_r;
  end if;
  delete from public.whatsapp_blocked_numbers where phone_normalized = '5547900014104' and reason = 'Teste F4 identificação';
  update public.parceiro_numeros set uso = 'pessoal' where id = v_num_bruna;
  v_r := public._retorno_triar(v_caso, c_t + interval '3 hours 4 minutes');
  if v_r ->> 'motivo' is distinct from 'pessoal' then
    raise exception '8f: regra 4, número pessoal (%)', v_r;
  end if;
  update public.parceiro_numeros set uso = 'comercial' where id = v_num_bruna;
  insert into public.whatsapp_leads (phone_normalized, name, lead_tipo) values ('5547900014104', 'Lead Ident F4 pessoal', 'pessoal');
  v_r := public._retorno_triar(v_caso, c_t + interval '3 hours 5 minutes');
  if v_r ->> 'motivo' is distinct from 'pessoal' then
    raise exception '8g: regra 4, lead pessoal (%)', v_r;
  end if;
  -- Regra 2 direto: tudo consumido.
  update public.retorno_mensagens set consumida = true where whatsapp_message_id = v_m;
  v_r := public._retorno_triar(v_caso, c_t + interval '3 hours 6 minutes');
  if v_r ->> 'motivo' is distinct from 'agenda_consumiu' then
    raise exception '8h: regra 2 direto (%)', v_r;
  end if;
  -- Ninguém olha o futuro: a mensagem gravada depois de p_agora não conta (o caso fica sem mensagem até então).
  v_r := public._retorno_triar(v_caso, c_t + interval '2 hours');
  if v_r ->> 'motivo' is distinct from 'nao_pede_resposta' then
    raise exception '8i: a triagem viu mensagem do futuro (%)', v_r;
  end if;
  -- Caso fechado não muda; caso que não é de parceiro dá 22023.
  update public.retorno_aberturas set estado = 'fechada', fechada_em = c_t + interval '4 hours', fechada_motivo = 'dono' where id = v_caso;
  v_r := public._parceiro_triar(v_caso, c_t + interval '5 hours');
  select * into v_ab from public.retorno_aberturas a where a.id = v_caso;
  if v_r ->> 'estado' is distinct from 'fechada' or v_ab.motivo is distinct from 'nao_pede_resposta' then
    raise exception '8j: o caso fechado mudou (%)', v_r;
  end if;
  v_m := pg_temp.retorno_f4_ident_msg('5547900014105', 'oi, tudo bem?', c_t + interval '6 hours');
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, motivo, modo)
    values ('00014105', '5547900014105', '47', 'cliente', public.quem_escreve('5547900014105'), v_x, v_m, v_m,
            c_t + interval '6 hours', c_t + interval '6 hours', c_t + interval '6 hours', c_t + interval '6 hours',
            'nada', 'nao_pede_resposta', 'sombra')
    returning id into v_caso2;
  begin
    perform public._parceiro_triar(v_caso2, c_t + interval '6 hours 1 minute');
    raise exception '8k: _parceiro_triar aceitou caso que não é de parceiro' using errcode = 'P0002';
  exception when sqlstate '22023' then
    null;
  end;

  -- 13. A varredura do parceiro: as funções novas fechadas a anon e authenticated.
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?parceiro_'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute') then
      raise exception '13: % aberta a anon/authenticated', v_rec.nome;
    end if;
    if v_rec.proname !~ '^_' and not has_function_privilege('service_role', v_rec.oid, 'execute') then
      raise exception '13: % sem execute para o service_role', v_rec.nome;
    end if;
    if v_rec.prosecdef and not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
      raise exception '13: % é SECURITY DEFINER sem search_path', v_rec.nome;
    end if;
  end loop;
  if to_regprocedure('public._parceiro_triar(uuid, timestamptz)') is null or v_n_fun < 2 then
    raise exception '13: a varredura não achou _parceiro_triar';
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_identificacao', true, '{}');
end
$ident$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
