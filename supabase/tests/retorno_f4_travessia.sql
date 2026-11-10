-- Retorno F4 (P15): a travessia do parceiro, a metade com banco. Os 5 cenários do plano (linha 638) e os 11 da F4, de ponta
-- a ponta, pelas portas reais: quem_escreve, _parceiro_confirmar, parceiro_ler_mensagem, parceiro_os_visivel, parceiro_linhas,
-- parceiro_patio_pedido, parceiro_pegar, parceiro_destino_do_pdf, parceiro_vinculo_cortar, retorno_dito e parceiro_aviso_rodada.
-- A outra metade (validador, guarda de valor, leitores, âncoras de código e a via reduzida no HTML) é o CI:
-- _shared/whatsapp/parceiro-travessia_test.ts. Roda só pela bancada (grupo 7, F4_ONDA=10). Termina em ROLLBACK. Telefones de
-- teste 55479000174xx (clientes) e 55479000175xx (parceiros); nomes e frases inventados. Relógio: ter 12/01/2027 10:00 e
-- sex 15/01/2027 17:50 (painel).
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f4t_cliente(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

create or replace function pg_temp.f4t_os(p_cliente uuid) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total)
  values ('OS-TF4T-' || left(md5(p_cliente::text || clock_timestamp()::text || random()::text), 8), p_cliente, v_v, 'open',
          'approved', 'repair', '2026-12-10 10:00-03', '2026-12-10 10:00-03', 0)
  returning id into v_id;
  return v_id;
end $f$;

create or replace function pg_temp.f4t_proposto(p_os uuid, p_parceiro uuid, p_papel text) returns uuid
language sql as $f$
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem)
  select so.id, p_parceiro, so.client_id, p_papel, 'proposto', 'dono' from public.service_orders so where so.id = p_os
  returning id
$f$;

create or replace function pg_temp.f4t_liga(p_os uuid, p_parceiro uuid, p_papel text, p_aviso_em timestamptz, p_pessoa uuid default null)
returns uuid
language sql as $f$
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, pessoa_id, papel, situacao, origem, aviso_ao_cliente,
                                      aviso_em, confirmado_em, pacote)
  select so.id, p_parceiro, so.client_id, p_pessoa, p_papel, 'confirmado', 'dono',
         case when p_aviso_em is null then 'nao_avisado' else 'mensagem' end, p_aviso_em, timestamptz '2027-01-01 10:00-03',
         case when p_papel in ('contratante', 'pagador') then 'completo' else 'status' end
    from public.service_orders so where so.id = p_os
  returning id
$f$;

create or replace function pg_temp.f4t_msg(p_fone text, p_corpo text, p_em timestamptz) returns uuid
language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at, hora_real)
  values ('inbound', p_fone, 'text', p_corpo, 'teste-f4-travessia-' || md5(p_fone || p_corpo || p_em::text || random()::text), p_em, p_em)
  returning id
$f$;

-- Pega a saída dada (as outras agendadas já devidas caem) e devolve o item; nulo se ela não saiu da fila.
create or replace function pg_temp.f4t_pega(p_saida uuid, p_agora timestamptz) returns jsonb
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
    return null;
  end if;
  return v;
end $f$;

create or replace function pg_temp.f4t_estado(p_saida uuid) returns text
language sql as $f$
  select s.estado || '/' || coalesce(s.motivo, '') from public.retorno_saidas s where s.id = p_saida
$f$;

create or replace function pg_temp.f4t_limpa() returns void
language sql as $f$
  update public.retorno_saidas s
     set estado = 'cancelada', motivo = 'substituida', decidida_em = now(), processando_ate = null
   where s.emissor = 'parceiro' and s.estado = 'agendada';
  update public.retorno_config set proximo_envio_em = null where id;
$f$;

do $travessia$
declare
  c_t constant timestamptz := '2027-01-12 10:00-03';        -- ter
  c_painel constant timestamptz := '2027-01-15 17:50-03';   -- sex
  v_dono uuid;
  v_p uuid; v_q uuid;
  v_carla uuid; v_fabia uuid; v_vania uuid;
  v_n_carla uuid; v_n_q uuid;
  v_cr uuid;
  v_m uuid; v_n uuid; v_a uuid; v_b uuid; v_g uuid; v_h uuid; v_k uuid; v_t uuid; v_u uuid; v_s uuid; v_v uuid; v_w uuid; v_x uuid;
  v_os_b uuid; v_os_c uuid; v_os_d uuid; v_os_e uuid; v_os_k uuid; v_os_r uuid;
  v_i_m uuid; v_i_n uuid; v_i_b uuid; v_i_g uuid; v_i_g2 uuid; v_i_h uuid; v_i_k uuid; v_i_t uuid; v_i_u uuid; v_i_s uuid; v_i_v uuid;
  v_i_w uuid; v_i_x uuid; v_i_c uuid; v_i_d uuid; v_i_e uuid; v_i_r uuid;
  v_r jsonb;
  v_item jsonb;
  v_saida uuid;
  v_msg uuid;
  v_linhas jsonb;
  v_sx public.retorno_saidas;
begin
  begin
  select d.id into v_dono from public._comprovante_dono() d;
  if v_dono is null then
    raise exception '0: sem o dono (_comprovante_dono) no banco';
  end if;
  update public.retorno_config
     set modo = 'sombra', identificacao_nova = true, parceiro_modo = 'ligado',
         parceiro_tipos_ligados = array['parceiro_aviso_cliente', 'parceiro_nao_mp_ok', 'parceiro_painel', 'parceiro_patio']::text[],
         tipos_ligados = '{}', proximo_envio_em = null, segura_tudo_ate = null, so_reativo = false, segura_patio = false,
         patio_nivel = 'direto', eco_modo = 'sombra', carencia_min = 2, respostas_dia_max = 40, iniciadas_dia_max = 50,
         pdf_parceiro_ligado = true, pdf_sem_espera_ligado = false
   where id;

  -- O parceiro: Carla (comercial, painel e documento) e Fábia (financeiro, documento). O cliente da própria revenda.
  v_cr := pg_temp.f4t_cliente('Revenda Travessia Ltda', '5547900017599');
  insert into public.parceiros (nome, sigla, tipo, client_id) values ('Revenda Travessia F4', 'RTV', 'revenda_e_patio', v_cr) returning id into v_p;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Fábia', 'financeiro') returning id into v_fabia;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel, recebe_documento)
    values (v_carla, '5547900017501', '00017501', '47', 'confirmado', c_t - interval '30 days', true, true) returning id into v_n_carla;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, uso, recebe_documento)
    values (v_fabia, '5547900017502', '00017502', '47', 'confirmado', c_t - interval '30 days', 'financeiro', true);
  -- O parceiro sem vínculo nenhum.
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Vazia Travessia F4', 'RVT', 'revenda') returning id into v_q;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_q, 'Vânia', 'comercial') returning id into v_vania;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_vania, '5547900017511', '00017511', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_n_q;
  if public.quem_escreve('5547900017501') ->> 'papel' is distinct from 'parceiro' then
    raise exception '0b: o número confirmado da parceira não é parceiro (%)', public.quem_escreve('5547900017501');
  end if;

  -- ══ Cenário 1: número compartilhado — ninguém vira parceiro, ninguém recebe o aviso, e o NÃO veta os dois clientes ══
  v_m := pg_temp.f4t_cliente('Mia Travessia', '5547900017401');
  v_n := pg_temp.f4t_cliente('Nil Travessia', '5547900017401');
  if public.quem_escreve('5547900017401') ->> 'papel' = 'parceiro' then
    raise exception '1a: o número compartilhado virou parceiro';
  end if;
  v_i_m := pg_temp.f4t_proposto(pg_temp.f4t_os(v_m), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_i_m, v_dono, null, c_t);
  if v_r ->> 'motivo_aviso' is distinct from 'numero_compartilhado'
     or exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_aviso_cliente' and s.phone_normalized = '5547900017401') then
    raise exception '1b: o número compartilhado recebeu o aviso (%)', v_r;
  end if;
  v_i_n := pg_temp.f4t_liga(pg_temp.f4t_os(v_n), v_p, 'indicou', c_t - interval '3 days');
  v_r := public.parceiro_ler_mensagem(pg_temp.f4t_msg('5547900017401', 'nao rtv', c_t + interval '1 minute'), c_t + interval '1 minute');
  if v_r ->> 'acao' is distinct from 'veto'
     or (select count(*) from public.parceiro_vetos pv where pv.client_id in (v_m, v_n) and pv.parceiro_id = v_p) is distinct from 2::bigint then
    raise exception '1c: o NÃO do número compartilhado não vetou os dois (%)', v_r;
  end if;
  if public.parceiro_os_visivel(v_i_n, c_t + interval '1 hour') ->> 'motivo' is distinct from 'veto' then
    raise exception '1d: o vínculo do outro cliente do número continua visível';
  end if;
  perform pg_temp.f4t_limpa();

  -- ══ Cenário 2: telefone A pedindo OS de B — nada de B vai a A ══
  v_a := pg_temp.f4t_cliente('Abel Travessia', '5547900017402');
  perform pg_temp.f4t_os(v_a);
  v_b := pg_temp.f4t_cliente('Bia Travessia', '5547900017403');
  v_os_b := pg_temp.f4t_os(v_b);
  v_i_b := pg_temp.f4t_liga(v_os_b, v_p, 'indicou', c_t - interval '3 days');
  if public.quem_escreve('5547900017402') ->> 'papel' is distinct from 'cliente' then
    raise exception '2a: A não é cliente (%)', public.quem_escreve('5547900017402');
  end if;
  for v_msg in
    select pg_temp.f4t_msg('5547900017402', x, c_t + interval '2 minutes') from unnest(array['pátio', 'como está o motorhome da Bia?', 'ver patio']) x
  loop
    if public.parceiro_ler_mensagem(v_msg, c_t + interval '2 minutes') ->> 'acao' is distinct from 'nada' then
      raise exception '2b: a mensagem de A foi lida como do parceiro';
    end if;
  end loop;
  if exists (select 1 from public.retorno_saidas s where s.emissor = 'parceiro' and s.phone_normalized = '5547900017402') then
    raise exception '2c: uma saída do parceiro foi a A';
  end if;
  if not exists (select 1 from jsonb_array_elements(public.parceiro_linhas(v_p, c_t)) l where l ->> 'interessado_id' = v_i_b::text) then
    raise exception '2d: a OS de B não está nas linhas da parceira';
  end if;

  -- ══ Cenário 3: parceiro sem vínculo — o pátio não tem linha nenhuma e responde vazio ══
  if exists (select 1 from jsonb_array_elements(public.parceiro_linhas(v_q, c_t)) l where l ->> 'n' is not null) then
    raise exception '3a: o parceiro sem vínculo tem linha';
  end if;
  -- no nível do cartão (o da 1ª semana), como em P7.3-8g: a resposta vazia já nasce agendada
  update public.retorno_config set patio_nivel = 'cartao' where id;
  v_r := public.parceiro_patio_pedido(v_n_q, pg_temp.f4t_msg('5547900017511', 'pátio', c_t), c_t);
  select * into v_sx from public.retorno_saidas s where s.id = nullif(v_r ->> 'saida_id', '')::uuid;
  if v_r ->> 'acao' is distinct from 'vazio' or v_sx.variante is distinct from 'vazio' or (v_sx.dados ->> 'sem_linhas')::boolean is not true
     or coalesce(jsonb_array_length(case when jsonb_typeof(v_sx.dados -> 'interessado_ids') = 'array' then v_sx.dados -> 'interessado_ids' end), 0) <> 0 then
    raise exception '3b: o pátio sem vínculo (%)', v_r;
  end if;
  update public.retorno_config set patio_nivel = 'direto' where id;
  if public.parceiro_patio_pedido(v_n_q, pg_temp.f4t_msg('5547900017511', 'patio', c_t + interval '1 minute'), c_t + interval '1 minute') ->> 'acao'
     is distinct from 'vazio' then
    raise exception '3c: o pátio sem vínculo, direto';
  end if;
  perform pg_temp.f4t_limpa();

  -- ══ Cenário 4: NÃO MP corta na hora, no painel agendado e na OS futura ══
  v_g := pg_temp.f4t_cliente('Gil Travessia', '5547900017404');
  v_h := pg_temp.f4t_cliente('Hil Travessia', '5547900017405');
  v_i_g := pg_temp.f4t_liga(pg_temp.f4t_os(v_g), v_p, 'indicou', c_painel - interval '3 days');
  v_i_h := pg_temp.f4t_liga(pg_temp.f4t_os(v_h), v_p, 'indicou', c_painel - interval '3 days');
  v_saida := public.parceiro_agendar('parceiro_painel', 'padrao', v_n_carla, null,
           (select jsonb_build_object('linhas', jsonb_agg(jsonb_build_object('n', x.n, 'interessado_id', oi.id, 'service_order_id', oi.service_order_id,
                                                                                'estado', 'em_servico', 'desde', null) order by x.n),
                                      'os_ids', jsonb_agg(to_jsonb(oi.service_order_id) order by x.n),
                                      'interessado_ids', jsonb_agg(to_jsonb(oi.id) order by x.n))
              from (values (1, v_i_g), (2, v_i_h)) as x(n, id) join public.os_interessados oi on oi.id = x.id),
           c_painel - interval '1 minute', 'parceiro:teste:travessia:painel4', 'resumo_parceiro', null);
  v_r := public.parceiro_ler_mensagem(pg_temp.f4t_msg('5547900017404', 'NÃO RTV', c_painel - interval '30 seconds'), c_painel - interval '30 seconds');
  if v_r ->> 'acao' is distinct from 'veto' then
    raise exception '4a: o NÃO de G (%)', v_r;
  end if;
  v_item := pg_temp.f4t_pega(v_saida, c_painel);
  select * into v_sx from public.retorno_saidas s where s.id = v_saida;
  if v_item is null or v_sx.dados -> 'interessado_ids' is distinct from jsonb_build_array(v_i_h)
     or coalesce(v_sx.texto, '') not like '%Hil T.%' or v_sx.texto like '%Gil%' then
    raise exception '4b: o veto não cortou a linha do painel agendado (% %)', pg_temp.f4t_estado(v_saida), v_sx.texto;
  end if;
  v_i_g2 := pg_temp.f4t_liga(pg_temp.f4t_os(v_g), v_p, 'indicou', c_t - interval '2 days');
  if public.parceiro_os_visivel(v_i_g2, c_painel) is distinct from '{"visivel": false, "motivo": "veto"}'::jsonb then
    raise exception '4c: a OS futura de quem vetou (%)', public.parceiro_os_visivel(v_i_g2, c_painel);
  end if;
  perform pg_temp.f4t_limpa();

  -- ══ Cenário 5: anfitriã sem status — nunca no painel, no pátio nem no eco ══
  v_k := pg_temp.f4t_cliente('Kai Travessia', '5547900017406');
  v_os_k := pg_temp.f4t_os(v_k);
  v_i_k := pg_temp.f4t_liga(v_os_k, v_p, 'anfitria', c_t - interval '3 days');
  if public.parceiro_os_visivel(v_i_k, c_t) is distinct from '{"visivel": false, "motivo": "anfitria"}'::jsonb then
    raise exception '5a: a anfitriã ficou visível (%)', public.parceiro_os_visivel(v_i_k, c_t);
  end if;
  if exists (select 1 from jsonb_array_elements(public.parceiro_linhas(v_p, c_t)) l where l ->> 'interessado_id' = v_i_k::text) then
    raise exception '5b: a anfitriã nas linhas do painel e do pátio';
  end if;
  v_r := public.parceiro_patio_pedido(v_n_carla, pg_temp.f4t_msg('5547900017501', 'pátio', c_t + interval '3 minutes'), c_t + interval '3 minutes');
  select * into v_sx from public.retorno_saidas s where s.id = nullif(v_r ->> 'saida_id', '')::uuid;
  if v_sx.id is null or (v_sx.dados -> 'interessado_ids') @> to_jsonb(array[v_i_k]) or (v_sx.dados -> 'os_ids') @> to_jsonb(array[v_os_k]) then
    raise exception '5c: o pátio citou a anfitriã (%)', v_r;
  end if;
  perform pg_temp.f4t_limpa();
  v_saida := public.parceiro_agendar('parceiro_eco', 'pronto', v_n_carla, null,
           jsonb_build_object('os_ids', jsonb_build_array(v_os_k), 'interessado_ids', jsonb_build_array(v_i_k), 'service_order_id', v_os_k),
           c_t, 'parceiro:teste:travessia:eco5', 'aviso');
  perform pg_temp.f4t_pega(v_saida, c_t + interval '4 minutes');
  if pg_temp.f4t_estado(v_saida) ~ '^(preparada|enviando|enviada)/' then
    raise exception '5d: o eco da anfitriã saiu (%)', pg_temp.f4t_estado(v_saida);
  end if;
  perform pg_temp.f4t_limpa();

  -- ══ F4-a: aviso sem 24 h — nada aparece antes; depois, sim ══
  v_t := pg_temp.f4t_cliente('Tom Travessia', '5547900017407');
  v_i_t := pg_temp.f4t_proposto(pg_temp.f4t_os(v_t), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_i_t, v_dono, null, c_t);
  v_saida := nullif(v_r ->> 'saida_id', '')::uuid;
  if v_saida is null or pg_temp.f4t_pega(v_saida, c_t) is null then
    raise exception 'a1: o aviso não saiu da fila (%)', v_r;
  end if;
  perform public.retorno_registrar_decisao(v_saida, 'enviada', '{}', c_t);
  if public.parceiro_os_visivel(v_i_t, c_t + interval '3 hours') ->> 'motivo' is distinct from 'antes_de_24h'
     or public.parceiro_os_visivel(v_i_t, c_t + interval '25 hours') ->> 'visivel' is distinct from 'true' then
    raise exception 'a2: a carência de 24 h depois do aviso (% / %)', public.parceiro_os_visivel(v_i_t, c_t + interval '3 hours'),
      public.parceiro_os_visivel(v_i_t, c_t + interval '25 hours');
  end if;
  perform pg_temp.f4t_limpa();

  -- ══ F4-b: aviso incerto — não conta: o vínculo segue sem aviso ══
  v_u := pg_temp.f4t_cliente('Ugo Travessia', '5547900017408');
  v_i_u := pg_temp.f4t_proposto(pg_temp.f4t_os(v_u), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_i_u, v_dono, null, c_t);
  v_saida := nullif(v_r ->> 'saida_id', '')::uuid;
  if v_saida is null or pg_temp.f4t_pega(v_saida, c_t) is null then
    raise exception 'b1: o aviso não saiu da fila (%)', v_r;
  end if;
  perform public.retorno_registrar_decisao(v_saida, 'incerta', '{}', c_t);
  if (select oi.aviso_ao_cliente from public.os_interessados oi where oi.id = v_i_u) is distinct from 'nao_avisado'
     or public.parceiro_os_visivel(v_i_u, c_t + interval '30 hours') ->> 'motivo' is distinct from 'sem_aviso' then
    raise exception 'b2: o aviso incerto contou (%)', public.parceiro_os_visivel(v_i_u, c_t + interval '30 hours');
  end if;
  perform pg_temp.f4t_limpa();

  -- ══ F4-d: segura pátio — só o dono; e solta ══
  v_r := public.retorno_dito('{"comando": "segura", "alvo": "patio"}', v_dono, c_t);
  if (select c.segura_patio from public.retorno_config c where c.id) is not true then
    raise exception 'd1: segura pátio não gravou (%)', v_r;
  end if;
  if public.retorno_dito('{"comando": "solta", "alvo": "patio"}', gen_random_uuid(), c_t) ->> 'motivo' is distinct from 'nao_e_o_dono'
     or (select c.segura_patio from public.retorno_config c where c.id) is not true then
    raise exception 'd2: quem não é o dono soltou o pátio';
  end if;
  perform public.retorno_dito('{"comando": "solta", "alvo": "patio"}', v_dono, c_t);
  if (select c.segura_patio from public.retorno_config c where c.id) is not false then
    raise exception 'd3: solta pátio não gravou';
  end if;

  -- ══ F4-e, f e k: o PDF — valor nunca a quem só indicou; só a pessoa do vínculo; via reduzida fora da OS da revenda ══
  if public.parceiro_destino_do_pdf(v_os_b, v_dono, null, c_t) ->> 'motivo' is distinct from 'papel' then
    raise exception 'e1: o PDF à que só indicou (%)', public.parceiro_destino_do_pdf(v_os_b, v_dono, null, c_t);
  end if;
  v_os_c := pg_temp.f4t_os(pg_temp.f4t_cliente('Caio Travessia', '5547900017409'));
  v_i_c := pg_temp.f4t_liga(v_os_c, v_p, 'contratante', c_t - interval '3 days', v_carla);
  v_r := public.parceiro_destino_do_pdf(v_os_c, v_dono, null, c_t);
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'phone' is distinct from '5547900017501' or (v_r ->> 'reduzir')::boolean is not true then
    raise exception 'f1: a contratante recebe no número da pessoa do vínculo, em via reduzida (%)', v_r;
  end if;
  v_os_d := pg_temp.f4t_os(pg_temp.f4t_cliente('Dora Travessia', '5547900017410'));
  v_i_d := pg_temp.f4t_liga(v_os_d, v_p, 'pagador', c_t - interval '3 days');
  if public.parceiro_destino_do_pdf(v_os_d, v_dono, null, c_t) ->> 'phone' is distinct from '5547900017502' then
    raise exception 'f2: a pagadora recebe no financeiro (%)', public.parceiro_destino_do_pdf(v_os_d, v_dono, null, c_t);
  end if;
  v_os_e := pg_temp.f4t_os(pg_temp.f4t_cliente('Edu Travessia', '5547900017411'));
  v_i_e := pg_temp.f4t_liga(v_os_e, v_p, 'contratante', c_t - interval '3 days');
  if public.parceiro_destino_do_pdf(v_os_e, v_dono, null, c_t) ->> 'motivo' is distinct from 'destino_ambiguo' then
    raise exception 'f3: sem a pessoa do vínculo e com dois números de documento (%)', public.parceiro_destino_do_pdf(v_os_e, v_dono, null, c_t);
  end if;
  begin
    perform public.parceiro_destino_do_pdf(v_os_c, gen_random_uuid(), null, c_t);
    raise exception 'f4: quem não é o dono leu o destino';
  exception when sqlstate '42501' then
    null;
  end;
  v_os_r := pg_temp.f4t_os(v_cr);
  v_i_r := pg_temp.f4t_liga(v_os_r, v_p, 'contratante', c_t - interval '3 days', v_carla);
  if public.parceiro_destino_do_pdf(v_os_r, v_dono, null, c_t) ->> 'reduzir' is distinct from 'false' then
    raise exception 'k1: na OS da própria revenda a via não precisa ser reduzida (%)', public.parceiro_destino_do_pdf(v_os_r, v_dono, null, c_t);
  end if;

  -- ══ F4-g: sombra → ligado no mesmo par — o aviso de sombra não conta, e ao ligar sai 1 aviso real ══
  update public.retorno_config set parceiro_modo = 'sombra' where id;
  v_s := pg_temp.f4t_cliente('Sol Travessia', '5547900017412');
  v_i_s := pg_temp.f4t_proposto(pg_temp.f4t_os(v_s), v_p, 'indicou');
  v_r := public._parceiro_confirmar(v_i_s, v_dono, null, c_t);
  v_saida := nullif(v_r ->> 'saida_id', '')::uuid;
  if v_saida is null or pg_temp.f4t_pega(v_saida, c_t) is null then
    raise exception 'g1: o aviso de sombra não saiu da fila (%)', v_r;
  end if;
  perform public.retorno_registrar_decisao(v_saida, 'sombra', '{}', c_t);
  if (select oi.aviso_em from public.os_interessados oi where oi.id = v_i_s) is not null then
    raise exception 'g2: o aviso de sombra contou como aviso';
  end if;
  update public.retorno_config set parceiro_modo = 'ligado' where id;
  perform public.parceiro_aviso_rodada(c_t + interval '5 minutes');
  select * into v_sx from public.retorno_saidas s where s.dedupe_key = 'parceiro:aviso:' || v_s || ':' || v_p;
  if v_sx.id is null or pg_temp.f4t_pega(v_sx.id, c_t + interval '5 minutes') is null then
    raise exception 'g3: ao ligar, o aviso real não nasceu';
  end if;
  perform public.retorno_registrar_decisao(v_sx.id, 'enviada', '{}', c_t + interval '6 minutes');
  perform public.parceiro_aviso_rodada(c_t + interval '10 minutes');
  if (select count(*) from public.retorno_saidas s where s.tipo = 'parceiro_aviso_cliente' and s.dados ->> 'client_id' = v_s::text
        and s.dedupe_key !~ ':sombra') is distinct from 1::bigint
     or (select oi.aviso_em from public.os_interessados oi where oi.id = v_i_s) is distinct from c_t + interval '6 minutes' then
    raise exception 'g4: sombra → ligado não deu 1 aviso real com aviso_em';
  end if;
  perform pg_temp.f4t_limpa();

  -- ══ F4-i: PARAR depois do aviso — fecha a OS na hora (5b), e o leitor do parceiro não consome o parar ══
  v_w := pg_temp.f4t_cliente('Wil Travessia', '5547900017413');
  v_i_w := pg_temp.f4t_liga(pg_temp.f4t_os(v_w), v_p, 'indicou', c_t - interval '3 days');
  if public.parceiro_os_visivel(v_i_w, c_t) ->> 'visivel' is distinct from 'true' then
    raise exception 'i1: o vínculo avisado não está visível (%)', public.parceiro_os_visivel(v_i_w, c_t);
  end if;
  if public.parceiro_ler_mensagem(pg_temp.f4t_msg('5547900017413', 'parar', c_t), c_t) is distinct from '{"consumida": false, "acao": "nada", "motivo": null}'::jsonb then
    raise exception 'i2: o parar foi consumido pelo leitor do parceiro';
  end if;
  update public.clients set opt_out_whatsapp = true where id = v_w;
  if public.parceiro_os_visivel(v_i_w, c_t + interval '1 minute') ->> 'motivo' is distinct from 'opt_out' then
    raise exception 'i3: o opt-out depois do aviso não fechou a OS (%)', public.parceiro_os_visivel(v_i_w, c_t + interval '1 minute');
  end if;

  -- ══ F4-j: corte pelo dono — pausar, retomar, recusar e veto do dono ══
  v_x := pg_temp.f4t_cliente('Xavi Travessia', '5547900017414');
  v_i_x := pg_temp.f4t_liga(pg_temp.f4t_os(v_x), v_p, 'indicou', c_t - interval '3 days');
  v_r := public.parceiro_vinculo_cortar(v_i_x, 'pausar', v_dono, c_t);
  if (v_r ->> 'ok')::boolean is not true or public.parceiro_os_visivel(v_i_x, c_t) ->> 'visivel' is distinct from 'false' then
    raise exception 'j1: pausar (%)', v_r;
  end if;
  perform public.parceiro_vinculo_cortar(v_i_x, 'retomar', v_dono, c_t + interval '1 minute');
  if public.parceiro_os_visivel(v_i_x, c_t + interval '1 minute') ->> 'visivel' is distinct from 'true' then
    raise exception 'j2: retomar não devolveu a OS';
  end if;
  perform public.parceiro_vinculo_cortar(v_i_x, 'veto_dono', v_dono, c_t + interval '2 minutes');
  if not exists (select 1 from public.parceiro_vetos pv where pv.client_id = v_x and pv.parceiro_id = v_p and pv.origem = 'dono')
     or public.parceiro_os_visivel(v_i_x, c_t + interval '3 minutes') ->> 'motivo' is distinct from 'veto' then
    raise exception 'j3: o veto do dono';
  end if;
  v_r := public.parceiro_vinculo_cortar(v_i_c, 'recusar', v_dono, c_t + interval '4 minutes');
  if (select oi.situacao from public.os_interessados oi where oi.id = v_i_c) is distinct from 'recusado'
     or public.parceiro_destino_do_pdf(v_os_c, v_dono, null, c_t + interval '5 minutes') ->> 'ok' is distinct from 'false' then
    raise exception 'j4: recusar não fechou o vínculo nem o PDF (%)', v_r;
  end if;

  -- ══ F4-c: pausa da parceira — o painel cai, e retomar devolve ══
  v_r := public.parceiro_ler_mensagem(pg_temp.f4t_msg('5547900017501', 'pausar', c_painel - interval '2 minutes'), c_painel - interval '2 minutes');
  if v_r ->> 'acao' is distinct from 'pausar' or (select pe.pausado_em from public.parceiro_pessoas pe where pe.id = v_carla) is null then
    raise exception 'c1: pausar (%)', v_r;
  end if;
  perform pg_temp.f4t_limpa();
  v_saida := public.parceiro_agendar('parceiro_painel', 'padrao', v_n_carla, null,
           jsonb_build_object('linhas', jsonb_build_array(jsonb_build_object('n', 1, 'interessado_id', v_i_h, 'service_order_id',
                                (select oi.service_order_id from public.os_interessados oi where oi.id = v_i_h), 'estado', 'em_servico')),
                              'os_ids', jsonb_build_array((select oi.service_order_id from public.os_interessados oi where oi.id = v_i_h)),
                              'interessado_ids', jsonb_build_array(v_i_h)),
           c_painel, 'parceiro:teste:travessia:painel-pausa', 'resumo_parceiro');
  perform pg_temp.f4t_pega(v_saida, c_painel + interval '1 minute');
  if pg_temp.f4t_estado(v_saida) is distinct from 'recusada/pausado' then
    raise exception 'c2: o painel à pessoa pausada não caiu (%)', pg_temp.f4t_estado(v_saida);
  end if;
  v_r := public.parceiro_ler_mensagem(pg_temp.f4t_msg('5547900017501', 'retomar', c_painel + interval '2 minutes'), c_painel + interval '2 minutes');
  if v_r ->> 'acao' is distinct from 'retomar' or (select pe.pausado_em from public.parceiro_pessoas pe where pe.id = v_carla) is not null then
    raise exception 'c3: retomar (%)', v_r;
  end if;
  perform pg_temp.f4t_limpa();

  -- ══ F4-h: NÃO MP com parceiro_modo = 'desligado' — o veto vale, e nada responde ══
  update public.retorno_config set parceiro_modo = 'desligado' where id;
  v_v := pg_temp.f4t_cliente('Vera Travessia', '5547900017415');
  v_i_v := pg_temp.f4t_liga(pg_temp.f4t_os(v_v), v_p, 'indicou', c_t - interval '3 days');
  v_r := public.parceiro_ler_mensagem(pg_temp.f4t_msg('5547900017415', 'não rtv', c_t + interval '7 minutes'), c_t + interval '7 minutes');
  if v_r ->> 'acao' is distinct from 'veto'
     or not exists (select 1 from public.parceiro_vetos pv where pv.client_id = v_v and pv.parceiro_id = v_p and pv.origem = 'nao_mp') then
    raise exception 'h1: o NÃO com o parceiro desligado não vetou (%)', v_r;
  end if;
  if exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_nao_mp_ok' and s.phone_normalized = '5547900017415'
              and s.estado in ('agendada', 'preparada', 'enviando', 'enviada')) then
    raise exception 'h2: com o parceiro desligado, a confirmação do NÃO foi agendada';
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_travessia', true, '{}');
end
$travessia$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
