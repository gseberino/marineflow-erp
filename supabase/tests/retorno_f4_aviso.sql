-- Retorno F4 (P6): o aviso ao cliente final e o NÃO MP. Um aviso por par (com herança), o caminho sem telefone, número
-- compartilhado e da equipe, sombra → ligado, reenvio, registro pelo dono, a retenção do "não" e o veto por situação, que
-- vale para a OS futura e corta o painel na hora. Roda só pela bancada (grupo 7, F4_ONDA=5, F4_TESTES=retorno_f4_aviso).
-- Termina em ROLLBACK. Telefones de teste 55479000147xx e 55479000148xx; nomes inventados. Relógio: ter 12/01/2027 10:00
-- (avisos e respostas) e sex 15/01/2027 17:50 (painel).
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f4a_cliente(p_nome text, p_fone text, p_tipo text default 'individual') returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values (p_tipo, p_nome, p_fone) returning id
$f$;

create or replace function pg_temp.f4a_os(p_cliente uuid, p_bem text default 'Motorhome') returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), p_bem) returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total)
  values ('OS-TF4A-' || left(md5(p_cliente::text || clock_timestamp()::text || random()::text), 8), p_cliente, v_v, 'open',
          'approved', 'repair', '2026-12-10 10:00-03', '2026-12-10 10:00-03', 0)
  returning id into v_id;
  return v_id;
end $f$;

-- O vínculo proposto (o caminho do cartão, P8, chega a _parceiro_confirmar com ele).
create or replace function pg_temp.f4a_proposto(p_os uuid, p_parceiro uuid, p_papel text) returns uuid
language sql as $f$
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem)
  select so.id, p_parceiro, so.client_id, p_papel, 'proposto', 'dono' from public.service_orders so where so.id = p_os
  returning id
$f$;

-- O vínculo já confirmado e avisado (o arranjo de quem não é o assunto do item).
create or replace function pg_temp.f4a_liga(p_os uuid, p_parceiro uuid, p_papel text, p_aviso_em timestamptz) returns uuid
language sql as $f$
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem, aviso_ao_cliente, aviso_em,
                                      confirmado_em)
  select so.id, p_parceiro, so.client_id, p_papel, 'confirmado', 'dono',
         case when p_aviso_em is null then 'nao_avisado' else 'mensagem' end, p_aviso_em, timestamptz '2027-01-01 10:00-03'
    from public.service_orders so where so.id = p_os
  returning id
$f$;

create or replace function pg_temp.f4a_msg(p_fone text, p_corpo text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', p_fone, 'text', p_corpo, 'teste-f4-aviso-' || md5(p_fone || p_corpo || p_em::text || random()::text), p_em)
  returning id
$f$;

-- Quantos avisos (reais e de sombra) o par tem.
create or replace function pg_temp.f4a_avisos(p_cliente uuid, p_parceiro uuid) returns integer
language sql as $f$
  select count(*)::integer from public.retorno_saidas s
   where s.emissor = 'parceiro' and s.tipo = 'parceiro_aviso_cliente'
     and s.dados ->> 'client_id' = p_cliente::text and s.dados ->> 'parceiro_id' = p_parceiro::text
$f$;

-- Pega a saída dada: as outras agendadas já devidas caem (substituida), o espaçamento volta a zero, e a fila tem de
-- devolver exatamente ela.
create or replace function pg_temp.f4a_pega(p_saida uuid, p_agora timestamptz) returns jsonb
language plpgsql as $f$
declare
  v jsonb;
begin
  update public.retorno_saidas s
     set estado = 'cancelada', motivo = 'substituida', decidida_em = p_agora, processando_ate = null
   where s.emissor = 'parceiro' and s.estado = 'agendada' and s.id <> p_saida and s.enviar_em <= p_agora;
  update public.retorno_config set proximo_envio_em = null where id;
  v := public.parceiro_pegar(p_agora);
  if v is null or (v ->> 'saida_id')::uuid is distinct from p_saida then
    raise exception 'pega: esperava a saída %, veio % (%)', p_saida, v ->> 'saida_id',
      (select s.estado || '/' || coalesce(s.motivo, '') from public.retorno_saidas s where s.id = p_saida);
  end if;
  return v;
end $f$;

-- Pega e registra como enviada a saída de aviso dada (a que a confirmação devolveu).
create or replace function pg_temp.f4a_envia(p_saida uuid, p_agora timestamptz) returns void
language plpgsql as $f$
begin
  if p_saida is null then
    raise exception 'envia: sem saída';
  end if;
  perform pg_temp.f4a_pega(p_saida, p_agora);
  if public.retorno_registrar_decisao(p_saida, 'enviada', '{}', p_agora) ->> 'estado' is distinct from 'enviada' then
    raise exception 'envia: o aviso não ficou enviada';
  end if;
end $f$;

create or replace function pg_temp.f4a_limpa() returns void
language sql as $f$
  update public.retorno_saidas s
     set estado = 'cancelada', motivo = 'substituida', decidida_em = now(), processando_ate = null
   where s.emissor = 'parceiro' and s.estado = 'agendada';
  update public.retorno_config set proximo_envio_em = null where id;
$f$;

do $aviso$
declare
  c_t constant timestamptz := '2027-01-12 10:00-03';        -- ter
  c_painel constant timestamptz := '2027-01-15 17:50-03';   -- sex
  v_dono uuid;
  v_p uuid;
  v_carla uuid;
  v_n1 uuid;
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_e uuid; v_f uuid; v_g uuid; v_h uuid; v_k uuid; v_l uuid; v_m uuid; v_o uuid;
  v_q uuid; v_r1 uuid; v_s1 uuid; v_t uuid; v_u uuid; v_v uuid; v_x uuid; v_w uuid; v_y uuid; v_z uuid; v_j uuid;
  v_i1 uuid; v_i2 uuid; v_i3 uuid; v_ib uuid; v_ic uuid; v_id uuid; v_ie uuid; v_ig uuid; v_ih uuid; v_ik uuid; v_il1 uuid;
  v_il2 uuid; v_im uuid; v_io uuid; v_iq uuid; v_ir uuid; v_is uuid; v_it uuid; v_iu uuid; v_iv uuid; v_ix uuid; v_iw1 uuid;
  v_iw2 uuid; v_iy uuid; v_iz uuid; v_ij uuid; v_if uuid;
  v_s uuid; v_s2 uuid;
  v_r jsonb;
  v_item jsonb;
  v_x public.retorno_saidas;
  v_oi public.os_interessados;
  v_msg uuid;
  v_n integer;
  v_rec record;
  v_n_fun integer := 0;
begin
  begin
  select d.id into v_dono from public._comprovante_dono() d;
  if v_dono is null then
    raise exception '0: sem o dono (_comprovante_dono) no banco';
  end if;
  update public.retorno_config
     set modo = 'sombra', identificacao_nova = true, parceiro_modo = 'ligado',
         parceiro_tipos_ligados = array['parceiro_aviso_cliente', 'parceiro_nao_mp_ok', 'parceiro_painel']::text[],
         tipos_ligados = '{}', proximo_envio_em = null, segura_tudo_ate = null, so_reativo = false, segura_patio = false,
         eco_modo = 'sombra', carencia_min = 2, respostas_dia_max = 40, iniciadas_dia_max = 50
   where id;

  -- Arranjo: a revenda e a Carla, que recebe o painel.
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Aviso F4', 'RAF', 'revenda_e_patio') returning id into v_p;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_carla, '5547900014801', '00014801', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_n1;

  -- ── 1 e 15. Com telefone, a confirmação agenda 1 aviso; o 2º vínculo do par entra na mesma saída; o 3º, depois do
  --    envio, herda o aviso_em e não agenda outro ──
  v_a := pg_temp.f4a_cliente('Abel Aviso', '5547900014711');
  v_i1 := pg_temp.f4a_proposto(pg_temp.f4a_os(v_a), v_p, 'indicou');
  v_i2 := pg_temp.f4a_proposto(pg_temp.f4a_os(v_a), v_p, 'indicou');
  v_i3 := pg_temp.f4a_proposto(pg_temp.f4a_os(v_a), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_i1, v_dono, null, c_t);
  if v_r ->> 'aviso' is distinct from 'agendado' or nullif(v_r ->> 'saida_id', '') is null then
    raise exception '1a/15b: a confirmação com telefone não agendou o aviso (%)', v_r;
  end if;
  v_s := (v_r ->> 'saida_id')::uuid;
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.tipo is distinct from 'parceiro_aviso_cliente' or v_x.classe is distinct from 'aviso'
     or v_x.origem is distinct from 'retorno_aviso' or v_x.estado is distinct from 'agendada'
     or v_x.dedupe_key is distinct from 'parceiro:aviso:' || v_a || ':' || v_p
     or v_x.phone_normalized is distinct from '5547900014711'
     or v_x.dados -> 'interessado_ids' is distinct from jsonb_build_array(v_i1)
     or v_x.dados ->> 'papel' is distinct from 'indicou' then
    raise exception '1b: a saída do aviso nasceu errada (% % % %)', v_x.dedupe_key, v_x.estado, v_x.dados, v_x.phone_normalized;
  end if;
  v_r := public._parceiro_confirmar(v_i2, v_dono, null, c_t);
  if nullif(v_r ->> 'saida_id', '')::uuid is distinct from v_s or pg_temp.f4a_avisos(v_a, v_p) is distinct from 1 then
    raise exception '1c: o 2º vínculo do par agendou outro aviso (% %)', v_r, pg_temp.f4a_avisos(v_a, v_p);
  end if;
  if (select s.dados -> 'interessado_ids' from public.retorno_saidas s where s.id = v_s) is distinct from jsonb_build_array(v_i1, v_i2) then
    raise exception '1d: a saída que espera não passou a cobrir o 2º vínculo';
  end if;
  v_item := pg_temp.f4a_pega(v_s, c_t);
  if coalesce(v_item ->> 'texto', '') not like '%Como você veio pela RAF, ela também acompanha o andamento do seu motorhome, sem valores.%'
     or v_item -> 'validador' ->> 'audiencia' is distinct from 'cliente' then
    raise exception '1e: o texto do aviso (%)', v_item ->> 'texto';
  end if;
  perform public.retorno_registrar_decisao(v_s, 'enviada', '{}', c_t + interval '1 minute');
  for v_oi in select * from public.os_interessados oi where oi.id in (v_i1, v_i2) loop
    if v_oi.aviso_ao_cliente is distinct from 'mensagem' or v_oi.aviso_em is distinct from c_t + interval '1 minute'
       or v_oi.aviso_saida_id is distinct from v_s then
      raise exception '1f: o envio não gravou o aviso nos dois vínculos (%)', v_oi.id;
    end if;
  end loop;
  v_r := public._parceiro_confirmar(v_i3, v_dono, null, c_t + interval '10 minutes');
  select * into v_oi from public.os_interessados oi where oi.id = v_i3;
  if nullif(v_r ->> 'saida_id', '')::uuid is distinct from v_s or v_oi.aviso_saida_id is distinct from v_s
     or v_oi.aviso_em is distinct from c_t + interval '1 minute' or v_oi.aviso_ao_cliente is distinct from 'mensagem'
     or pg_temp.f4a_avisos(v_a, v_p) is distinct from 1 then
    raise exception '1g: o 3º vínculo não herdou o aviso (% % %)', v_r, v_oi.aviso_em, pg_temp.f4a_avisos(v_a, v_p);
  end if;
  perform pg_temp.f4a_limpa();

  -- ── 2 e 15. Sem telefone: confirma, nada agendado, nao_avisado e o item aviso na fila ──
  v_b := pg_temp.f4a_cliente('Bento Aviso', null);
  v_ib := pg_temp.f4a_proposto(pg_temp.f4a_os(v_b), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_ib, v_dono, null, c_t);
  select * into v_oi from public.os_interessados oi where oi.id = v_ib;
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'aviso' is distinct from 'pendente' or v_r ->> 'motivo_aviso' is distinct from 'sem_telefone'
     or v_oi.situacao is distinct from 'confirmado' or v_oi.aviso_ao_cliente is distinct from 'nao_avisado' or v_oi.aviso_em is not null
     or pg_temp.f4a_avisos(v_b, v_p) is distinct from 0 then
    raise exception '2/15a: sem telefone (% %)', v_r, v_oi.aviso_ao_cliente;
  end if;
  if not exists (select 1 from public.parceiro_fila f where f.chave = 'aviso:' || v_ib and f.tipo = 'aviso' and f.estado = 'espera'
                    and f.referencia = v_ib) then
    raise exception '2b: o item aviso não entrou na fila';
  end if;

  -- ── 6. parceiro_aviso_registrar: só o dono; registra uma vez ──
  begin
    perform public.parceiro_aviso_registrar(v_ib, 'pessoalmente', gen_random_uuid(), c_t);
    raise exception '6a: quem não é o dono registrou o aviso';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    perform public.parceiro_aviso_registrar(v_ib, 'por_carta', v_dono, c_t);
    raise exception '6b: como fora da lista passou';
  exception when sqlstate '22023' then
    null;
  end;
  v_r := public.parceiro_aviso_registrar(v_ib, 'pessoalmente', v_dono, c_t + interval '5 minutes');
  select * into v_oi from public.os_interessados oi where oi.id = v_ib;
  if (v_r ->> 'ok')::boolean is not true or v_oi.aviso_ao_cliente is distinct from 'pessoalmente'
     or v_oi.aviso_em is distinct from c_t + interval '5 minutes' then
    raise exception '6c: o registro do dono não gravou (% %)', v_r, v_oi.aviso_ao_cliente;
  end if;
  if public.parceiro_aviso_registrar(v_ib, 'pela_revenda', v_dono, c_t) ->> 'motivo' is distinct from 'ja_avisado' then
    raise exception '6d: registrar de novo não recusou';
  end if;

  -- ── 3 e 16. O NÃO MP por situação ──
  -- cliente com vínculo: veto, Q03 e consome; repetir não duplica
  v_c := pg_temp.f4a_cliente('Cida Aviso', '5547900014713');
  v_ic := pg_temp.f4a_liga(pg_temp.f4a_os(v_c), v_p, 'indicou', c_t - interval '2 days');
  v_msg := pg_temp.f4a_msg('5547900014713', 'NÃO RAF', c_t);
  v_r := public.parceiro_veto_dito('00014713', '5547900014713', 'RAF', v_msg, c_t);
  if (v_r ->> 'consumida')::boolean is not true or v_r ->> 'acao' is distinct from 'veto' or (v_r ->> 'vetados')::integer is distinct from 1
     or nullif(v_r ->> 'saida_id', '') is null then
    raise exception '3a/16a: o veto do cliente com vínculo (%)', v_r;
  end if;
  if not exists (select 1 from public.parceiro_vetos pv where pv.client_id = v_c and pv.parceiro_id = v_p and pv.origem = 'nao_mp'
                    and pv.whatsapp_message_id = v_msg and pv.em = c_t)
     or (select oi.veto_do_cliente_em from public.os_interessados oi where oi.id = v_ic) is distinct from c_t then
    raise exception '3b: o veto não foi gravado';
  end if;
  select * into v_x from public.retorno_saidas s where s.id = (v_r ->> 'saida_id')::uuid;
  if v_x.tipo is distinct from 'parceiro_nao_mp_ok' or v_x.variante is distinct from 'com_nome'
     or v_x.dedupe_key is distinct from 'parceiro:nao_mp:' || v_c || ':' || v_p or v_x.phone_normalized is distinct from '5547900014713' then
    raise exception '16b: a saída Q03 (% %)', v_x.dedupe_key, v_x.variante;
  end if;
  v_r := public.parceiro_veto_dito('00014713', '5547900014713', 'raf', v_msg, c_t + interval '1 minute');
  if (v_r ->> 'vetados')::integer is distinct from 0 or nullif(v_r ->> 'saida_id', '')::uuid is distinct from v_x.id
     or (select count(*) from public.parceiro_vetos pv where pv.client_id = v_c) is distinct from 1::bigint
     or (select count(*) from public.retorno_saidas s where s.tipo = 'parceiro_nao_mp_ok' and s.dados ->> 'client_id' = v_c::text) is distinct from 1::bigint then
    raise exception '3c: repetir o veto duplicou (%)', v_r;
  end if;
  v_item := pg_temp.f4a_pega(v_x.id, c_t + interval '1 minute');
  if v_item ->> 'texto' is distinct from 'Combinado, ' || public._retorno_nome(v_c) || ': o andamento fica só entre nós.' then
    raise exception '16c: o texto do Q03 (%)', v_item ->> 'texto';
  end if;

  -- número ambíguo: veto nos dois, 1 saída só (Q03b), sem 22023
  v_d := pg_temp.f4a_cliente('Dulce Aviso', '5547900014714');
  v_e := pg_temp.f4a_cliente('Edu Aviso', '5547900014714');
  v_id := pg_temp.f4a_liga(pg_temp.f4a_os(v_d), v_p, 'indicou', c_t - interval '2 days');
  v_ie := pg_temp.f4a_liga(pg_temp.f4a_os(v_e), v_p, 'indicou', c_t - interval '2 days');
  v_msg := pg_temp.f4a_msg('5547900014714', 'nao raf', c_t + interval '2 minutes');
  v_r := public.parceiro_veto_dito('00014714', '5547900014714', 'RAF', v_msg, c_t + interval '2 minutes');
  if (v_r ->> 'consumida')::boolean is not true or (v_r ->> 'vetados')::integer is distinct from 2
     or (select count(*) from public.parceiro_vetos pv where pv.client_id in (v_d, v_e) and pv.parceiro_id = v_p) is distinct from 2::bigint then
    raise exception '3d/16d: o veto no número ambíguo (%)', v_r;
  end if;
  if (select count(*) from public.retorno_saidas s where s.tipo = 'parceiro_nao_mp_ok' and s.phone_normalized = '5547900014714') is distinct from 1::bigint then
    raise exception '16e: o número ambíguo ganhou mais de uma resposta';
  end if;
  select * into v_x from public.retorno_saidas s where s.id = (v_r ->> 'saida_id')::uuid;
  if v_x.variante is distinct from 'sem_nome' or v_x.dedupe_key is distinct from 'parceiro:nao_mp:chave:00014714:' || v_p then
    raise exception '16f: a resposta do ambíguo (% %)', v_x.variante, v_x.dedupe_key;
  end if;
  v_item := pg_temp.f4a_pega(v_x.id, c_t + interval '2 minutes');
  if v_item ->> 'texto' is distinct from 'Combinado: o andamento fica só entre nós.'
     or (select s.estado from public.retorno_saidas s where s.id = v_x.id) is distinct from 'enviando' then
    raise exception '16g: o Q03b caiu (% %)', v_item ->> 'texto', pg_temp.f4a_avisos(v_d, v_p);
  end if;

  -- cliente sem vínculo e sem aviso: grava o veto, não responde e não consome
  v_f := pg_temp.f4a_cliente('Fabi Aviso', '5547900014715');
  v_msg := pg_temp.f4a_msg('5547900014715', 'não quero a raf', c_t + interval '3 minutes');
  v_r := public.parceiro_veto_dito('00014715', '5547900014715', 'RAF', v_msg, c_t + interval '3 minutes');
  if (v_r ->> 'consumida')::boolean is not false or v_r ->> 'acao' is distinct from 'veto' or (v_r ->> 'vetados')::integer is distinct from 1
     or nullif(v_r ->> 'saida_id', '') is not null
     or not exists (select 1 from public.parceiro_vetos pv where pv.client_id = v_f and pv.parceiro_id = v_p) then
    raise exception '3e/16h: cliente sem vínculo (%)', v_r;
  end if;

  -- número desconhecido: nada
  select count(*) into v_n from public.parceiro_vetos;
  v_r := public.parceiro_veto_dito('00014799', '5547900014799', 'RAF', null, c_t);
  if (v_r ->> 'consumida')::boolean is not false or v_r ->> 'acao' is distinct from 'nada'
     or (select count(*) from public.parceiro_vetos) is distinct from v_n::bigint then
    raise exception '3f/16i: número desconhecido (%)', v_r;
  end if;
  perform pg_temp.f4a_limpa();

  -- ── 4. O veto vale para a OS criada depois ──
  v_if := pg_temp.f4a_liga(pg_temp.f4a_os(v_f), v_p, 'indicou', c_t - interval '2 days');
  if public.parceiro_os_visivel(v_if, c_t + interval '1 hour') is distinct from '{"visivel": false, "motivo": "veto"}'::jsonb then
    raise exception '4a: a OS nova do cliente vetado (%)', public.parceiro_os_visivel(v_if, c_t + interval '1 hour');
  end if;
  v_ic := pg_temp.f4a_liga(pg_temp.f4a_os(v_c), v_p, 'indicou', c_t - interval '2 days');
  if public.parceiro_os_visivel(v_ic, c_t + interval '1 hour') ->> 'motivo' is distinct from 'veto' then
    raise exception '4b: a OS nova do cliente que vetou com vínculo';
  end if;

  -- ── 5. O veto corta na hora: o painel agendado perde a linha ──
  v_g := pg_temp.f4a_cliente('Gil Aviso', '5547900014716');
  v_h := pg_temp.f4a_cliente('Hil Aviso', '5547900014717');
  v_ig := pg_temp.f4a_liga(pg_temp.f4a_os(v_g), v_p, 'indicou', c_painel - interval '3 days');
  v_ih := pg_temp.f4a_liga(pg_temp.f4a_os(v_h), v_p, 'indicou', c_painel - interval '3 days');
  v_s := public.parceiro_agendar('parceiro_painel', 'padrao', v_n1, null,
           (select jsonb_build_object('linhas', jsonb_agg(jsonb_build_object('n', x.n, 'interessado_id', oi.id, 'service_order_id', oi.service_order_id,
                                                                                'estado', 'em_servico', 'desde', null) order by x.n),
                                      'os_ids', jsonb_agg(to_jsonb(oi.service_order_id) order by x.n),
                                      'interessado_ids', jsonb_agg(to_jsonb(oi.id) order by x.n))
              from (values (1, v_ig), (2, v_ih)) as x(n, id) join public.os_interessados oi on oi.id = x.id),
           c_painel - interval '1 minute', 'parceiro:teste:aviso:painel5', 'resumo_parceiro', null);
  v_msg := pg_temp.f4a_msg('5547900014716', 'nao raf', c_painel - interval '30 seconds');
  perform public.parceiro_veto_dito('00014716', '5547900014716', 'RAF', v_msg, c_painel - interval '30 seconds');
  v_item := pg_temp.f4a_pega(v_s, c_painel);
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.dados -> 'interessado_ids' is distinct from jsonb_build_array(v_ih)
     or not exists (select 1 from jsonb_array_elements(v_x.dados -> 'linhas_fora') f
                     where f ->> 'interessado_id' = v_ig::text and f ->> 'fora_por' = 'regra')
     or coalesce(v_x.texto, '') not like '%1. Motorhome de Hil A.: em serviço hoje.%' or v_x.texto like '%Gil%' then
    raise exception '5: o veto não cortou a linha do painel (% %)', v_x.dados -> 'interessado_ids', v_x.texto;
  end if;
  perform pg_temp.f4a_limpa();

  -- ── 7. Aviso em sombra não conta: a chave termina em :sombra e o aviso_em continua nulo ──
  update public.retorno_config set parceiro_modo = 'sombra' where id;
  v_k := pg_temp.f4a_cliente('Kai Aviso', '5547900014718');
  v_ik := pg_temp.f4a_proposto(pg_temp.f4a_os(v_k), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_ik, v_dono, null, c_t);
  v_s := nullif(v_r ->> 'saida_id', '')::uuid;
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.dedupe_key is distinct from 'parceiro:aviso:' || v_k || ':' || v_p || ':sombra' or v_x.modo is distinct from 'sombra' then
    raise exception '7a: o aviso em sombra (% %)', v_r, v_x.dedupe_key;
  end if;
  perform pg_temp.f4a_pega(v_s, c_t);
  perform public.retorno_registrar_decisao(v_s, 'sombra', '{}', c_t);
  select * into v_oi from public.os_interessados oi where oi.id = v_ik;
  if (select s.estado from public.retorno_saidas s where s.id = v_s) is distinct from 'sombra'
     or v_oi.aviso_em is not null or v_oi.aviso_ao_cliente is distinct from 'nao_avisado' or v_oi.aviso_saida_id is not null then
    raise exception '7b: o aviso em sombra contou como aviso';
  end if;

  -- ── 9. Sombra → ligado: a rodada seguinte agenda e envia 1 aviso real, e não um 2º ──
  update public.retorno_config set parceiro_modo = 'ligado' where id;
  v_r := public.parceiro_aviso_rodada(c_t + interval '5 minutes');
  select * into v_x from public.retorno_saidas s where s.dedupe_key = 'parceiro:aviso:' || v_k || ':' || v_p;
  if v_x.id is null or v_x.estado is distinct from 'agendada' or v_x.modo is distinct from 'ligado' then
    raise exception '9a: a rodada não criou o aviso real (% %)', v_r, v_x.estado;
  end if;
  perform pg_temp.f4a_pega(v_x.id, c_t + interval '5 minutes');
  perform public.retorno_registrar_decisao(v_x.id, 'enviada', '{}', c_t + interval '6 minutes');
  perform public.parceiro_aviso_rodada(c_t + interval '10 minutes');
  if (select oi.aviso_em from public.os_interessados oi where oi.id = v_ik) is distinct from c_t + interval '6 minutes'
     or (select count(*) from public.retorno_saidas s where s.tipo = 'parceiro_aviso_cliente' and s.dados ->> 'client_id' = v_k::text
          and s.dedupe_key !~ ':sombra') is distinct from 1::bigint then
    raise exception '9b: sombra → ligado não deu 1 aviso real com aviso_em';
  end if;
  perform pg_temp.f4a_limpa();

  -- ── 10. Dois vínculos do mesmo par em sombra: ao ligar, 1 aviso só e aviso_em nos dois ──
  update public.retorno_config set parceiro_modo = 'sombra' where id;
  v_l := pg_temp.f4a_cliente('Lia Aviso', '5547900014719');
  v_il1 := pg_temp.f4a_proposto(pg_temp.f4a_os(v_l), v_p, 'indicou');
  v_il2 := pg_temp.f4a_proposto(pg_temp.f4a_os(v_l), v_p, 'indicou');
  perform public._parceiro_confirmar(v_il1, v_dono, null, c_t);
  perform public._parceiro_confirmar(v_il2, v_dono, null, c_t + interval '1 second');
  if pg_temp.f4a_avisos(v_l, v_p) is distinct from 1 then
    raise exception '10a: dois avisos em sombra no mesmo par';
  end if;
  perform pg_temp.f4a_limpa();
  update public.retorno_config set parceiro_modo = 'ligado' where id;
  perform public.parceiro_aviso_rodada(c_t + interval '20 minutes');
  select * into v_x from public.retorno_saidas s where s.dedupe_key = 'parceiro:aviso:' || v_l || ':' || v_p;
  if v_x.id is null or v_x.dados -> 'interessado_ids' is distinct from jsonb_build_array(v_il1, v_il2) then
    raise exception '10b: o aviso real do par não cobre os dois vínculos (%)', v_x.dados;
  end if;
  perform pg_temp.f4a_pega(v_x.id, c_t + interval '20 minutes');
  perform public.retorno_registrar_decisao(v_x.id, 'enviada', '{}', c_t + interval '21 minutes');
  if (select count(*) from public.os_interessados oi where oi.id in (v_il1, v_il2) and oi.aviso_em = c_t + interval '21 minutes'
        and oi.aviso_saida_id = v_x.id) is distinct from 2::bigint
     or (select count(*) from public.retorno_saidas s where s.tipo = 'parceiro_aviso_cliente' and s.dados ->> 'client_id' = v_l::text
          and s.dedupe_key !~ ':sombra') is distinct from 1::bigint then
    raise exception '10c: o par em sombra ao ligar não deu 1 aviso com aviso_em nos dois';
  end if;
  perform pg_temp.f4a_limpa();

  -- ── 11 e 15. Número compartilhado por dois clientes, ou de parceiro_numeros: numero_compartilhado, sem saída ──
  v_m := pg_temp.f4a_cliente('Mia Aviso', '5547900014720');
  perform pg_temp.f4a_cliente('Nil Aviso', '5547900014720');
  v_im := pg_temp.f4a_proposto(pg_temp.f4a_os(v_m), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_im, v_dono, null, c_t);
  if v_r ->> 'aviso' is distinct from 'pendente' or v_r ->> 'motivo_aviso' is distinct from 'numero_compartilhado'
     or pg_temp.f4a_avisos(v_m, v_p) is distinct from 0
     or (select oi.aviso_ao_cliente from public.os_interessados oi where oi.id = v_im) is distinct from 'nao_avisado'
     or not exists (select 1 from public.parceiro_fila f where f.chave = 'aviso:' || v_im) then
    raise exception '11a/15c: número de dois clientes (%)', v_r;
  end if;
  v_o := pg_temp.f4a_cliente('Ota Aviso', '5547900014721');
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao)
    values (v_carla, '5547900014721', '00014721', '47', 'proposto');
  v_io := pg_temp.f4a_proposto(pg_temp.f4a_os(v_o), v_p, 'indicou');
  -- ainda proposto: o aviso recusa pela situação do vínculo, antes do telefone
  if public.parceiro_aviso_agendar(v_io, c_t) is distinct from '{"ok": false, "motivo": "nao_confirmado"}'::jsonb then
    raise exception '11c: aviso de vínculo proposto (%)', public.parceiro_aviso_agendar(v_io, c_t);
  end if;
  v_r := public._parceiro_confirmar(v_io, v_dono, null, c_t);
  if v_r ->> 'motivo_aviso' is distinct from 'numero_compartilhado' or pg_temp.f4a_avisos(v_o, v_p) is distinct from 0 then
    raise exception '11b: número que está em parceiro_numeros (%)', v_r;
  end if;

  -- ── 8. Número da HBR no vínculo: não recebe aviso (equipe no canal) ──
  insert into public.payees (name, kind, active, phone) values ('Equipe Aviso F4', 'prestador', true, '5547900014722');
  v_q := pg_temp.f4a_cliente('Quel Aviso', '5547900014722');
  v_iq := pg_temp.f4a_proposto(pg_temp.f4a_os(v_q), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_iq, v_dono, null, c_t);
  if v_r ->> 'motivo_aviso' is distinct from 'numero_compartilhado' or pg_temp.f4a_avisos(v_q, v_p) is distinct from 0
     or public.canal_pode_enviar('5547900014722', 'aviso', 'retorno_aviso', c_t) ->> 'motivo' is distinct from 'equipe' then
    raise exception '8: o número da equipe (% %)', v_r, public.canal_pode_enviar('5547900014722', 'aviso', 'retorno_aviso', c_t);
  end if;

  -- ── 18. Cliente sem nome utilizável: sem_nome e o item aviso ──
  v_z := pg_temp.f4a_cliente('Zeta Aviso Ltda', '5547900014730', 'company');
  v_iz := pg_temp.f4a_proposto(pg_temp.f4a_os(v_z), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_iz, v_dono, null, c_t);
  if public._retorno_nome(v_z) is not null or v_r ->> 'motivo_aviso' is distinct from 'sem_nome'
     or pg_temp.f4a_avisos(v_z, v_p) is distinct from 0
     or not exists (select 1 from public.parceiro_fila f where f.chave = 'aviso:' || v_iz) then
    raise exception '18: cliente sem nome (%)', v_r;
  end if;

  -- ── 12. parceiro_aviso_reenviar: até 2 vezes; a 3ª recusa; só o dono ──
  v_r1 := pg_temp.f4a_cliente('Rui Aviso', '5547900014723');
  v_ir := pg_temp.f4a_proposto(pg_temp.f4a_os(v_r1), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_ir, v_dono, null, c_t);
  perform public._parceiro_pegar_fechar((v_r ->> 'saida_id')::uuid, 'recusada', 'canal', null, c_t);
  begin
    perform public.parceiro_aviso_reenviar(v_ir, gen_random_uuid(), c_t);
    raise exception '12a: quem não é o dono reenviou';
  exception when sqlstate '42501' then
    null;
  end;
  v_r := public.parceiro_aviso_reenviar(v_ir, v_dono, c_t + interval '1 minute');
  if (v_r ->> 'ok')::boolean is not true
     or (select s.dedupe_key from public.retorno_saidas s where s.id = (v_r ->> 'saida_id')::uuid)
        is distinct from 'parceiro:aviso:' || v_r1 || ':' || v_p || ':r1' then
    raise exception '12b: o 1º reenvio (%)', v_r;
  end if;
  v_r := public.parceiro_aviso_reenviar(v_ir, v_dono, c_t + interval '2 minutes');
  if (select s.dedupe_key from public.retorno_saidas s where s.id = nullif(v_r ->> 'saida_id', '')::uuid)
     is distinct from 'parceiro:aviso:' || v_r1 || ':' || v_p || ':r2' then
    raise exception '12c: o 2º reenvio (%)', v_r;
  end if;
  if public.parceiro_aviso_reenviar(v_ir, v_dono, c_t + interval '3 minutes') is distinct from '{"ok": false, "motivo": "limite"}'::jsonb
     or pg_temp.f4a_avisos(v_r1, v_p) is distinct from 3 then
    raise exception '12d: o 3º reenvio não recusou';
  end if;
  perform pg_temp.f4a_limpa();

  -- ── 13. O registrado "pela revenda" que ganha telefone: entra no aviso, as duas travas deixam passar, sai 1, grava
  --    aviso_saida_id e não muda aviso_em ──
  v_s1 := pg_temp.f4a_cliente('Sol Aviso', null);
  v_is := pg_temp.f4a_proposto(pg_temp.f4a_os(v_s1), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_is, v_dono, 'pela_revenda', c_t);
  if v_r ->> 'aviso' is distinct from 'pela_revenda' then
    raise exception '13a: o registro pela revenda (%)', v_r;
  end if;
  update public.parceiro_fila set estado = 'feito', decidido_em = c_t where chave = 'aviso:' || v_is;
  update public.clients set whatsapp = '5547900014724' where id = v_s1;
  perform public.parceiro_aviso_rodada(c_t + interval '1 hour');
  select * into v_x from public.retorno_saidas s where s.dedupe_key = 'parceiro:aviso:' || v_s1 || ':' || v_p;
  if v_x.id is null or v_x.dados -> 'interessado_ids' is distinct from jsonb_build_array(v_is) then
    raise exception '13b: o registrado com telefone não entrou no aviso (%)', v_x.dados;
  end if;
  perform pg_temp.f4a_pega(v_x.id, c_t + interval '1 hour');
  if public.parceiro_saida_autorizada(v_x.id, '5547900014724', c_t + interval '1 hour') is distinct from '{"pode": true, "motivo": null}'::jsonb then
    raise exception '13c: a última trava barrou o registrado (%)', public.parceiro_saida_autorizada(v_x.id, '5547900014724', c_t + interval '1 hour');
  end if;
  perform public.retorno_registrar_decisao(v_x.id, 'enviada', '{}', c_t + interval '61 minutes');
  select * into v_oi from public.os_interessados oi where oi.id = v_is;
  if v_oi.aviso_saida_id is distinct from v_x.id or v_oi.aviso_em is distinct from c_t or v_oi.aviso_ao_cliente is distinct from 'pela_revenda' then
    raise exception '13d: o registrado ganhou carência nova ou ficou sem aviso_saida_id (% %)', v_oi.aviso_em, v_oi.aviso_saida_id;
  end if;
  -- o nao_avisado que ganha telefone: 1 aviso e a carência abre
  v_t := pg_temp.f4a_cliente('Teo Aviso', null);
  v_it := pg_temp.f4a_proposto(pg_temp.f4a_os(v_t), v_p, 'indicou');
  perform public._parceiro_confirmar(v_it, v_dono, null, c_t);
  update public.clients set whatsapp = '5547900014725' where id = v_t;
  perform public.parceiro_aviso_rodada(c_t + interval '2 hours');
  select * into v_x from public.retorno_saidas s where s.dedupe_key = 'parceiro:aviso:' || v_t || ':' || v_p;
  perform pg_temp.f4a_pega(v_x.id, c_t + interval '2 hours');
  perform public.retorno_registrar_decisao(v_x.id, 'enviada', '{}', c_t + interval '2 hours');
  if (select oi.aviso_em from public.os_interessados oi where oi.id = v_it) is distinct from c_t + interval '2 hours'
     or public.parceiro_os_visivel(v_it, c_t + interval '3 hours') ->> 'motivo' is distinct from 'antes_de_24h' then
    raise exception '13e: o nao_avisado com telefone novo';
  end if;
  -- o registrado com o item aviso já feito, e o aviso novo recusado: nasce aviso:<interessado>:<saida>
  v_u := pg_temp.f4a_cliente('Uri Aviso', null);
  v_iu := pg_temp.f4a_proposto(pg_temp.f4a_os(v_u), v_p, 'indicou');
  perform public._parceiro_confirmar(v_iu, v_dono, 'pessoalmente', c_t);
  update public.parceiro_fila set estado = 'feito', decidido_em = c_t where chave = 'aviso:' || v_iu;
  update public.clients set whatsapp = '5547900014726' where id = v_u;
  perform public.parceiro_aviso_rodada(c_t + interval '3 hours');
  select * into v_x from public.retorno_saidas s where s.dedupe_key = 'parceiro:aviso:' || v_u || ':' || v_p;
  perform pg_temp.f4a_pega(v_x.id, c_t + interval '3 hours');
  perform public.retorno_registrar_decisao(v_x.id, 'recusada', '{"motivo": "canal"}', c_t + interval '3 hours');
  perform public.parceiro_aviso_rodada(c_t + interval '3 hours 1 minute');
  if not exists (select 1 from public.parceiro_fila f
                  where f.chave = 'aviso:' || v_iu || ':' || v_x.id and f.tipo = 'aviso' and f.estado = 'espera'
                    and f.referencia = v_iu and f.dados ->> 'saida_id' = v_x.id::text)
     or (select f.estado from public.parceiro_fila f where f.chave = 'aviso:' || v_iu) is distinct from 'feito' then
    raise exception '13f: o aviso recusado do registrado não pôs aviso:<interessado>:<saida> na fila';
  end if;
  -- a rodada seguinte não duplica nem reenvia sozinha
  perform public.parceiro_aviso_rodada(c_t + interval '3 hours 2 minutes');
  if (select count(*) from public.parceiro_fila f where f.chave like 'aviso:' || v_iu || ':%') is distinct from 1::bigint
     or pg_temp.f4a_avisos(v_u, v_p) is distinct from 1 then
    raise exception '13g: a rodada reenviou ou duplicou o item';
  end if;
  perform pg_temp.f4a_limpa();

  -- ── 14. parceiro_reter_resposta: "não" nas 24 h depois do aviso retém; fora das 24 h, nada ──
  v_v := pg_temp.f4a_cliente('Vivi Aviso', '5547900014727');
  v_iv := pg_temp.f4a_proposto(pg_temp.f4a_os(v_v), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_iv, v_dono, null, c_t + interval '4 hours');
  perform pg_temp.f4a_envia(nullif(v_r ->> 'saida_id', '')::uuid, c_t + interval '4 hours');
  v_msg := pg_temp.f4a_msg('5547900014727', 'não obrigado', c_t + interval '7 hours');
  v_r := public.parceiro_reter_resposta('00014727', v_msg, c_t + interval '7 hours');
  if (v_r ->> 'retidos')::integer is distinct from 1
     or (select oi.retido_em from public.os_interessados oi where oi.id = v_iv) is distinct from c_t + interval '7 hours'
     or public.parceiro_os_visivel(v_iv, c_t + interval '40 hours') ->> 'motivo' is distinct from 'retido'
     or not exists (select 1 from public.parceiro_fila f where f.chave = 'retido:' || v_iv and f.tipo = 'retido' and f.referencia = v_iv) then
    raise exception '14a: o "não" nas 24 h não reteve (%)', v_r;
  end if;

  v_j := pg_temp.f4a_cliente('Xavi Aviso', '5547900014728');
  v_ij := pg_temp.f4a_proposto(pg_temp.f4a_os(v_j), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_ij, v_dono, null, c_t + interval '4 hours');
  perform pg_temp.f4a_envia(nullif(v_r ->> 'saida_id', '')::uuid, c_t + interval '4 hours');
  v_msg := pg_temp.f4a_msg('5547900014728', 'nao', c_t + interval '29 hours');
  v_r := public.parceiro_reter_resposta('00014728', v_msg, c_t + interval '29 hours');
  if (v_r ->> 'retidos')::integer is distinct from 0 or (select oi.retido_em from public.os_interessados oi where oi.id = v_ij) is not null then
    raise exception '14b: o "não" fora das 24 h reteve (%)', v_r;
  end if;

  -- ── 17. O papel no aviso: indicou e contratante no par → Q04/Q05; só indicou → Q01/Q02; palavras diferentes → veículo ──
  v_w := pg_temp.f4a_cliente('Wal Aviso', '5547900014729');
  v_iw1 := pg_temp.f4a_proposto(pg_temp.f4a_os(v_w, 'Motorhome'), v_p, 'indicou');
  v_iw2 := pg_temp.f4a_proposto(pg_temp.f4a_os(v_w, 'Lancha'), v_p, 'contratante');
  v_r := public._parceiro_confirmar(v_iw1, v_dono, null, c_t);
  perform public._parceiro_confirmar(v_iw2, v_dono, null, c_t);
  v_s := (v_r ->> 'saida_id')::uuid;
  if (select s.dados ->> 'papel' from public.retorno_saidas s where s.id = v_s) is distinct from 'contratante' then
    raise exception '17a: o papel mais forte do par não foi ao aviso';
  end if;
  v_item := pg_temp.f4a_pega(v_s, c_t + interval '5 hours');
  if coalesce(v_item ->> 'texto', '') not like '%Este serviço no seu veículo está sendo feito por meio da RAF, e ela acompanha o andamento.%'
     or v_item ->> 'texto' like '%veio pela%' then
    raise exception '17b: contratante no par não usou Q04/Q05 (%)', v_item ->> 'texto';
  end if;
  v_y := pg_temp.f4a_cliente('Yan Aviso', '5547900014731');
  v_iy := pg_temp.f4a_proposto(pg_temp.f4a_os(v_y, 'Motorhome'), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_iy, v_dono, null, c_t);
  v_item := pg_temp.f4a_pega((v_r ->> 'saida_id')::uuid, c_t + interval '5 hours');
  if coalesce(v_item ->> 'texto', '') not like '%Como você veio pela RAF, ela também acompanha o andamento do seu motorhome, sem valores.%' then
    raise exception '17c: só indicou não usou Q01/Q02 (%)', v_item ->> 'texto';
  end if;

  -- ── A varredura do parceiro: as funções da P6 fechadas a anon e authenticated ──
  for v_rec in
    select p.oid, p.proname, p.oid::regprocedure::text as nome, p.prosecdef, coalesce(p.proconfig, '{}') as config
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname ~ '^_?parceiro_'
  loop
    v_n_fun := v_n_fun + 1;
    if has_function_privilege('anon', v_rec.oid, 'execute') or has_function_privilege('authenticated', v_rec.oid, 'execute') then
      raise exception 'grants: % aberta a anon/authenticated', v_rec.nome;
    end if;
    if v_rec.proname !~ '^_' and not has_function_privilege('service_role', v_rec.oid, 'execute') then
      raise exception 'grants: % sem execute para o service_role', v_rec.nome;
    end if;
    if v_rec.prosecdef and not exists (select 1 from unnest(v_rec.config) o where o ~ '^search_path=') then
      raise exception 'grants: % é SECURITY DEFINER sem search_path', v_rec.nome;
    end if;
  end loop;
  if to_regprocedure('public.parceiro_aviso_agendar(uuid, timestamptz)') is null
     or to_regprocedure('public.parceiro_veto_dito(text, text, text, uuid, timestamptz)') is null
     or to_regprocedure('public.parceiro_reter_resposta(text, uuid, timestamptz)') is null then
    raise exception 'grants: a varredura não achou as funções da P6 (%)', v_n_fun;
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_aviso', true, '{}');
end
$aviso$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
