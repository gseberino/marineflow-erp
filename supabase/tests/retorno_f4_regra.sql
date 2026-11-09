-- Retorno F4 (P3): a regra de ouro condição por condição, o lote sem nome, propor, confirmar (sem o caminho do aviso, que
-- é P6.2-15), requalificar, cortar, o destino do PDF, a semente e os números fora do assistente. Roda só pela bancada
-- (grupo 7, F4_ONDA=3). Termina em ROLLBACK. Telefones de teste 55479000143xx e 55479000144xx, e o final 7391 da semente;
-- nomes, siglas e frases inventados. Relógio fixo em ter 12/01/2027 15:00.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f4r_cliente(p_nome text, p_fone text, p_tipo text default 'individual') returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values (p_tipo, p_nome, p_fone) returning id
$f$;

-- Uma OS (e uma unidade, se não vier) do cliente, criada na data dada.
create or replace function pg_temp.f4r_os(p_cliente uuid, p_status text, p_bem text default 'Motorhome',
                                          p_criada timestamptz default '2026-12-10 10:00-03', p_vessel uuid default null,
                                          p_quote text default 'approved', p_origem_parceiro uuid default null) returns uuid
language plpgsql as $f$
declare
  v_v uuid := p_vessel;
  v_id uuid;
begin
  if v_v is null then
    insert into public.vessels (client_id, name, asset_type)
      values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), p_bem) returning id into v_v;
  end if;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total, origem_parceiro_id)
  values ('OS-TF4R-' || left(md5(p_cliente::text || clock_timestamp()::text || random()::text), 8), p_cliente, v_v, p_status,
          p_quote, 'repair', p_criada, p_criada, 0, p_origem_parceiro)
  returning id into v_id;
  return v_id;
end $f$;

-- Um vínculo da OS ao parceiro, direto na tabela (o arranjo; o caminho pelo cartão é da P8).
create or replace function pg_temp.f4r_liga(p_os uuid, p_parceiro uuid, p_papel text, p_situacao text, p_aviso_em timestamptz,
                                            p_aviso text default 'mensagem', p_origem text default 'dono') returns uuid
language plpgsql as $f$
declare
  v uuid;
begin
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem, aviso_ao_cliente, aviso_em,
                                      confirmado_em)
  select so.id, p_parceiro, so.client_id, p_papel, p_situacao, p_origem,
         case when p_aviso_em is null then 'nao_avisado' else p_aviso end, p_aviso_em,
         case when p_situacao in ('confirmado', 'pausado', 'recusado') then timestamptz '2027-01-01 10:00-03' end
    from public.service_orders so where so.id = p_os
  returning id into v;
  return v;
end $f$;

-- A regra de ouro de um vínculo: o motivo esperado (nulo = visível), sem deixar nulo passar calado.
create or replace function pg_temp.f4r_vis(p_rotulo text, p_id uuid, p_agora timestamptz, p_motivo text) returns void
language plpgsql as $f$
declare
  r jsonb := public.parceiro_os_visivel(p_id, p_agora);
begin
  if p_motivo is null then
    if r is distinct from '{"visivel": true, "motivo": null}'::jsonb then
      raise exception '%: visível esperado, veio %', p_rotulo, r;
    end if;
  elsif r is distinct from jsonb_build_object('visivel', false, 'motivo', p_motivo) then
    raise exception '%: esperado %, veio %', p_rotulo, p_motivo, r;
  end if;
end $f$;

do $regra$
declare
  c_t constant timestamptz := '2027-01-12 15:00-03';
  c_aviso constant timestamptz := '2027-01-11 14:00-03';   -- 25 h antes de c_t
  v_dono uuid;
  v_outro uuid := gen_random_uuid();
  v_mp uuid;              -- o cadastro de cliente da revenda de teste
  v_p uuid;               -- a revenda (com pátio)
  v_p_inativo uuid;
  v_p_lote uuid;          -- a revenda do lote
  v_carla uuid;
  v_fin uuid;
  v_num_carla uuid;
  v_num_fin uuid;
  v_a uuid; v_os_a uuid; v_i_a uuid;
  v_c uuid; v_os uuid; v_i uuid;
  v_i2 uuid;
  v_os2 uuid;
  v_vessel uuid;
  v_ids uuid[];
  v_r jsonb;
  v_oi public.os_interessados;
  v_rec record;
  v_n integer;
  v_t text;
  v_n_fun integer := 0;
  -- o lote
  v_os_pedido uuid; v_os_unidade uuid; v_os_propria uuid; v_os_carteira uuid; v_os_nome uuid; v_os_placa uuid;
  v_os_veto uuid; v_os_recusada uuid; v_os_rascunho uuid; v_os_antiga uuid;
  v_l2 uuid; v_v2 uuid;
  v_i_prop uuid; v_i_cart uuid; v_i_pedido uuid;
  v_semente jsonb;
begin
  begin
  select d.id into v_dono from public._comprovante_dono() d;
  if v_dono is null then
    raise exception '0: sem o dono (_comprovante_dono) no banco';
  end if;
  if (select c.parceiro_modo from public.retorno_config c where c.id) is distinct from 'desligado' then
    raise exception '0: parceiro_modo de partida não é desligado';
  end if;

  -- Arranjo comum: a revenda com cadastro de cliente, uma pessoa comercial e uma do financeiro.
  v_mp := pg_temp.f4r_cliente('Revenda Regra F4 Ltda', '5547900014390', 'company');
  insert into public.parceiros (nome, sigla, tipo, client_id) values ('Revenda Regra F4', 'RRF', 'revenda_e_patio', v_mp) returning id into v_p;
  insert into public.parceiros (nome, sigla, tipo, ativo) values ('Inativa Regra F4', 'IRF', 'revenda', false) returning id into v_p_inativo;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Fábia', 'financeiro') returning id into v_fin;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_documento, recebe_painel)
    values (v_carla, '5547900014401', '00014401', '47', 'confirmado', c_t - interval '30 days', true, true) returning id into v_num_carla;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, uso)
    values (v_fin, '5547900014402', '00014402', '47', 'confirmado', c_t - interval '30 days', 'financeiro') returning id into v_num_fin;

  -- ── A regra de ouro, uma condição por vez (10 = visível) ──
  v_a := pg_temp.f4r_cliente('Abel Regra F4', '5547900014301');
  v_os_a := pg_temp.f4r_os(v_a, 'open');
  v_i_a := pg_temp.f4r_liga(v_os_a, v_p, 'indicou', 'confirmado', c_aviso);
  perform pg_temp.f4r_vis('r10', v_i_a, c_t, null);
  perform pg_temp.f4r_vis('r1', gen_random_uuid(), c_t, 'sem_linha');
  -- 2. parceiro inativo
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_a, 'open'), v_p_inativo, 'indicou', 'confirmado', c_aviso);
  perform pg_temp.f4r_vis('r2', v_i, c_t, 'parceiro_inativo');
  -- 3. anfitriã (13: confirmada, com aviso e 24 h, nunca visível) e papel nulo
  v_c := pg_temp.f4r_cliente('Bia Regra F4', '5547900014302');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'anfitria', 'confirmado', c_aviso);
  perform pg_temp.f4r_vis('r3a/13', v_i, c_t, 'anfitria');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, null, 'proposto', null, 'mensagem', 'carteira');
  perform pg_temp.f4r_vis('r3b', v_i, c_t, 'nao_confirmado');
  -- 4. não confirmado (proposto com papel; pausado)
  v_c := pg_temp.f4r_cliente('Caio Regra F4', '5547900014303');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'proposto', null);
  perform pg_temp.f4r_vis('r4a', v_i, c_t, 'nao_confirmado');
  v_c := pg_temp.f4r_cliente('Cora Regra F4', '5547900014304');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'pausado', c_aviso);
  perform pg_temp.f4r_vis('r4b', v_i, c_t, 'nao_confirmado');
  -- 5. veto no próprio vínculo
  v_c := pg_temp.f4r_cliente('Davi Regra F4', '5547900014305');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', c_aviso);
  update public.os_interessados set veto_do_cliente_em = c_t - interval '1 hour' where id = v_i;
  perform pg_temp.f4r_vis('r5', v_i, c_t, 'veto');
  -- ninguém olha o futuro: antes do veto, visível
  perform pg_temp.f4r_vis('r5b', v_i, c_t - interval '2 hours', null);
  -- 5a. retido (23: retido_em preenchido)
  v_c := pg_temp.f4r_cliente('Elis Regra F4', '5547900014306');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', c_aviso);
  update public.os_interessados set retido_em = c_t - interval '1 hour' where id = v_i;
  perform pg_temp.f4r_vis('r5a/23b', v_i, c_t, 'retido');
  -- 5b. opt-out no cadastro
  v_c := pg_temp.f4r_cliente('Fred Regra F4', '5547900014307');
  update public.clients set opt_out_whatsapp = true where id = v_c;
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', c_aviso);
  perform pg_temp.f4r_vis('r5b', v_i, c_t, 'opt_out');
  -- 6. sem aviso
  v_c := pg_temp.f4r_cliente('Gil Regra F4', '5547900014308');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', null);
  perform pg_temp.f4r_vis('r6', v_i, c_t, 'sem_aviso');
  -- 7 e 11. aviso há 23 h: antes_de_24h; há 24 h e 1 min: visível
  v_c := pg_temp.f4r_cliente('Hugo Regra F4', '5547900014309');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', c_t - interval '23 hours');
  perform pg_temp.f4r_vis('r7/11a', v_i, c_t, 'antes_de_24h');
  perform pg_temp.f4r_vis('11b', v_i, c_t + interval '1 hour 1 minute', null);
  -- 12. p_agora antes do aviso: sem_aviso (ninguém olha o futuro)
  perform pg_temp.f4r_vis('12', v_i_a, c_aviso - interval '1 hour', 'sem_aviso');
  -- 8 e 21. OS fora da regra 8
  v_c := pg_temp.f4r_cliente('Iara Regra F4', '5547900014310');
  v_os := pg_temp.f4r_os(v_c, 'completed');
  v_i := pg_temp.f4r_liga(v_os, v_p, 'indicou', 'confirmado', c_aviso);
  perform pg_temp.f4r_vis('r8/21a', v_i, c_t, 'os_fora');
  -- com a palavra de conclusão do dono há 10 h: viva (concluída recente)
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, texto)
    values (c_t - interval '10 hours', ((c_t - interval '10 hours') at time zone 'America/Sao_Paulo')::date, true, 'dono', 'concluir',
            v_os, 'concluiu no teste');
  perform pg_temp.f4r_vis('21b', v_i, c_t, null);
  -- a mesma palavra fica velha depois de fato_pronto_idade (48 h)
  perform pg_temp.f4r_vis('21c', v_i, c_t + interval '40 hours', 'os_fora');
  -- liberada para retirada há 3 dias, sem entrega: viva; com delivered_at, fora
  v_os := pg_temp.f4r_os(v_c, 'completed');
  update public.service_orders set liberado_retirada_em = c_t - interval '3 days' where id = v_os;
  v_i := pg_temp.f4r_liga(v_os, v_p, 'indicou', 'confirmado', c_aviso);
  perform pg_temp.f4r_vis('21d', v_i, c_t, null);
  update public.service_orders set delivered_at = c_t - interval '1 day' where id = v_os;
  perform pg_temp.f4r_vis('21e', v_i, c_t, 'os_fora');
  -- rascunho sem origem do parceiro: fora; com a origem deste parceiro: visível
  v_os := pg_temp.f4r_os(v_c, 'draft', 'Motorhome', '2026-12-10 10:00-03', null, 'draft');
  v_i := pg_temp.f4r_liga(v_os, v_p, 'indicou', 'confirmado', c_aviso);
  perform pg_temp.f4r_vis('21f', v_i, c_t, 'os_fora');
  update public.service_orders set origem_parceiro_id = v_p where id = v_os;
  perform pg_temp.f4r_vis('21g', v_i, c_t, null);
  -- OS agrupada (merged_into_id): fora
  update public.service_orders set merged_into_id = v_os_a where id = v_os;
  perform pg_temp.f4r_vis('21h', v_i, c_t, 'os_fora');
  -- 9. cliente inativo; cliente genérico sem telefone
  v_c := pg_temp.f4r_cliente('Joel Regra F4', '5547900014311');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', c_aviso);
  update public.clients set active = false where id = v_c;
  perform pg_temp.f4r_vis('r9a', v_i, c_t, 'cliente_fora');
  insert into public.clients (type, name, generico) values ('individual', 'Genérico Regra F4', true) returning id into v_c;
  v_i2 := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', c_aviso);
  perform pg_temp.f4r_vis('r9b', v_i2, c_t, 'cliente_fora');

  -- 14. Veto em parceiro_vetos, gravado por outra OS do mesmo cliente (vale sem OS).
  v_c := pg_temp.f4r_cliente('Kátia Regra F4', '5547900014312');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', c_aviso);
  perform pg_temp.f4r_vis('14a', v_i, c_t, null);
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem) values (v_c, v_p, c_t - interval '2 hours', 'nao_mp');
  perform pg_temp.f4r_vis('14b', v_i, c_t, 'veto');

  -- 23. PARAR gravado depois do aviso: opt_out, e a OS some.
  v_c := pg_temp.f4r_cliente('Lia Regra F4', '5547900014313');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', c_aviso);
  perform pg_temp.f4r_vis('23a', v_i, c_t, null);
  insert into public.whatsapp_blocked_numbers (phone_normalized, reason, tipo, created_at)
    values ('5547900014313', 'Teste F4 regra', 'opt_out', c_t - interval '1 hour');
  perform pg_temp.f4r_vis('23b', v_i, c_t, 'opt_out');

  -- 20. parceiro_os_visiveis: nunca anfitriã, sem aviso, pausado ou genérico; só os visíveis acima.
  select array_agg(x.interessado_id order by x.interessado_id) into v_ids from public.parceiro_os_visiveis(v_p, c_t) x;
  if v_ids is distinct from (select array_agg(x.id order by x.id) from public.os_interessados x
                               where x.parceiro_id = v_p and (public.parceiro_os_visivel(x.id, c_t) ->> 'visivel')::boolean is true)
     or not (v_i_a = any (v_ids)) then
    raise exception '20a: parceiro_os_visiveis diferente da regra de ouro (%)', v_ids;
  end if;
  if exists (select 1 from public.parceiro_os_visiveis(v_p, c_t) x
               join public.os_interessados oi on oi.id = x.interessado_id
               join public.clients cl on cl.id = oi.client_id
              where oi.papel = 'anfitria' or oi.aviso_em is null or oi.situacao = 'pausado' or cl.generico) then
    raise exception '20b: parceiro_os_visiveis devolveu anfitriã, sem aviso, pausado ou genérico';
  end if;
  if exists (select 1 from public.parceiro_os_visiveis(v_p, c_t) x where x.papel is null or x.vessel_id is null) then
    raise exception '20c: linha sem papel ou sem unidade';
  end if;

  -- ── 15, 16 e 22. O lote, por sinal objetivo (só as OS deste teste; a carteira real também aparece e é ignorada) ──
  insert into public.parceiros (nome, sigla, tipo, client_id) values ('Revenda Lote F4', 'RLF', 'revenda_e_patio', v_mp) returning id into v_p_lote;
  -- numero_do_pedido: rascunho pedido pela revenda (unidade náutica: sem carteira)
  v_c := pg_temp.f4r_cliente('Marta Lote F4', '5547900014321');
  v_os_pedido := pg_temp.f4r_os(v_c, 'draft', 'Lancha', '2026-12-20 10:00-03', null, 'draft', v_p_lote);
  -- unidade_anterior: a mesma unidade e o mesmo cliente com vínculo comercial confirmado (contratante) numa OS antiga
  v_l2 := pg_temp.f4r_cliente('Lúcia Lote F4', '5547900014322');
  insert into public.vessels (client_id, name, asset_type, hull_id_or_registration)
    values (v_l2, 'Sereia Lote', 'Lancha', 'PLC1F44') returning id into v_v2;
  v_os_antiga := pg_temp.f4r_os(v_l2, 'completed', 'Lancha', '2026-06-01 10:00-03', v_v2);
  perform pg_temp.f4r_liga(v_os_antiga, v_p_lote, 'contratante', 'confirmado', '2026-06-02 10:00-03');
  v_os_unidade := pg_temp.f4r_os(v_l2, 'open', 'Lancha', '2026-12-21 10:00-03', v_v2);
  -- propria: a OS da própria revenda
  v_os_propria := pg_temp.f4r_os(v_mp, 'open', 'Lancha', '2026-12-22 10:00-03');
  -- carteira: motorhome na carteira, sem outro sinal
  v_c := pg_temp.f4r_cliente('Nara Lote F4', '5547900014324');
  v_os_carteira := pg_temp.f4r_os(v_c, 'open', 'Motorhome', '2026-12-23 10:00-03');
  -- nome igual ao de um cliente ligado, sem sinal: nunca propõe
  v_c := pg_temp.f4r_cliente('Lúcia Lote F4', '5547900014325');
  v_os_nome := pg_temp.f4r_os(v_c, 'open', 'Lancha', '2026-12-24 10:00-03');
  -- a mesma placa e o mesmo nome de unidade de outro cliente, sem sinal e sem carteira: nunca propõe
  v_c := pg_temp.f4r_cliente('Otto Lote F4', '5547900014326');
  insert into public.vessels (client_id, name, asset_type, hull_id_or_registration)
    values (v_c, 'Sereia Lote', 'Lancha', 'PLC1F44') returning id into v_vessel;
  v_os_placa := pg_temp.f4r_os(v_c, 'open', 'Lancha', '2026-12-25 10:00-03', v_vessel);
  -- cliente com veto do par: fora
  v_c := pg_temp.f4r_cliente('Pia Lote F4', '5547900014327');
  v_os_veto := pg_temp.f4r_os(v_c, 'open', 'Motorhome', '2026-12-26 10:00-03');
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem) values (v_c, v_p_lote, c_t - interval '5 days', 'nao_mp');
  -- 16. par recusado, com sinal forte: nunca volta
  v_c := pg_temp.f4r_cliente('Rui Lote F4', '5547900014328');
  v_os_recusada := pg_temp.f4r_os(v_c, 'draft', 'Lancha', '2026-12-27 10:00-03', null, 'draft', v_p_lote);
  perform pg_temp.f4r_liga(v_os_recusada, v_p_lote, 'indicou', 'recusado', null);
  -- 22. rascunho fora da regra 8 (sem origem do parceiro e fora da carteira): nunca proposto
  v_c := pg_temp.f4r_cliente('Saulo Lote F4', '5547900014329');
  v_os_rascunho := pg_temp.f4r_os(v_c, 'draft', 'Motorhome', '2026-12-28 10:00-03', null, 'draft');

  v_ids := array[v_os_pedido, v_os_unidade, v_os_propria, v_os_carteira, v_os_nome, v_os_placa, v_os_veto, v_os_recusada,
                 v_os_rascunho, v_os_antiga];
  for v_rec in
    select x.service_order_id, x.sinal, x.papel_proposto, x.tem_telefone, x.numero, x.bem
      from public.parceiro_lote_candidatos(v_p_lote, c_t, 500) x
     where x.service_order_id = any (v_ids)
  loop
    v_t := case v_rec.service_order_id
      when v_os_pedido then 'numero_do_pedido|indicou'
      when v_os_unidade then 'unidade_anterior|contratante'
      when v_os_propria then 'propria|contratante'
      when v_os_carteira then 'carteira|'
      else 'nao_devia'
    end;
    if v_t is distinct from v_rec.sinal || '|' || coalesce(v_rec.papel_proposto, '') then
      raise exception '15/22: OS % no lote com sinal % e papel % (esperado %)', v_rec.numero, v_rec.sinal, v_rec.papel_proposto, v_t;
    end if;
    if v_rec.tem_telefone is not true or v_rec.numero is null then
      raise exception '15: candidato sem telefone ou sem número (%)', v_rec.numero;
    end if;
  end loop;
  select count(*) into v_n from public.parceiro_lote_candidatos(v_p_lote, c_t, 500) x where x.service_order_id = any (v_ids);
  if v_n is distinct from 4 then
    raise exception '15: o lote trouxe % das 4 OS com sinal', v_n;
  end if;
  -- O pátio sem revenda: a carteira não entra para parceiro sem pátio.
  update public.parceiros set tipo = 'revenda' where id = v_p_lote;
  if exists (select 1 from public.parceiro_lote_candidatos(v_p_lote, c_t, 500) x where x.service_order_id = v_os_carteira) then
    raise exception '15: carteira proposta a parceiro sem pátio';
  end if;
  update public.parceiros set tipo = 'revenda_e_patio' where id = v_p_lote;
  -- Parceiro inativo: lote vazio.
  if exists (select 1 from public.parceiro_lote_candidatos(v_p_inativo, c_t, 500)) then
    raise exception '15: lote de parceiro inativo';
  end if;

  -- ── 26 e 17. parceiro_propor ──
  begin
    perform public.parceiro_propor('[]'::jsonb, v_outro);
    raise exception '26: propor aceitou autor que não é o dono' using errcode = 'P0002';
  exception when sqlstate '42501' then
    null;
  end;
  begin
    perform public.parceiro_propor(jsonb_build_array(jsonb_build_object('service_order_id', v_os_pedido, 'parceiro_id', v_p_lote,
                                   'origem', 'numero_do_pedido', 'papel', null)), v_dono);
    raise exception '26: papel nulo aceito fora de carteira e dono' using errcode = 'P0002';
  exception when sqlstate '22023' then
    null;
  end;
  select jsonb_agg(jsonb_build_object('service_order_id', x.service_order_id, 'parceiro_id', v_p_lote, 'client_id', x.client_id,
                                      'origem', x.sinal, 'papel', x.papel_proposto, 'pessoa_id', null))
    into v_r
    from public.parceiro_lote_candidatos(v_p_lote, c_t, 500) x
   where x.service_order_id = any (v_ids);
  v_r := v_r || jsonb_build_array(jsonb_build_object('service_order_id', v_os_recusada, 'parceiro_id', v_p_lote,
                                                     'origem', 'numero_do_pedido', 'papel', 'indicou'));
  v_r := public.parceiro_propor(v_r, v_dono);
  if jsonb_array_length(v_r -> 'propostos') is distinct from 4
     or v_r -> 'recusados' is distinct from jsonb_build_array(jsonb_build_object('service_order_id', v_os_recusada, 'motivo', 'ja_decidido')) then
    raise exception '26a: 1ª chamada do propor (%)', v_r;
  end if;
  if exists (select 1 from public.os_interessados oi where oi.parceiro_id = v_p_lote and oi.service_order_id = any (v_ids)
                and oi.situacao = 'confirmado' and oi.service_order_id <> v_os_antiga) then
    raise exception '17: o propor gravou confirmado';
  end if;
  select oi.id into v_i_prop from public.os_interessados oi where oi.parceiro_id = v_p_lote and oi.service_order_id = v_os_propria;
  select oi.id into v_i_cart from public.os_interessados oi where oi.parceiro_id = v_p_lote and oi.service_order_id = v_os_carteira;
  select oi.id into v_i_pedido from public.os_interessados oi where oi.parceiro_id = v_p_lote and oi.service_order_id = v_os_pedido;
  select * into v_oi from public.os_interessados oi where oi.id = v_i_cart;
  if v_oi.papel is not null or v_oi.origem is distinct from 'carteira' or v_oi.situacao is distinct from 'proposto' then
    raise exception '26b: a carteira gravou papel ou situação errados';
  end if;
  -- o vínculo entra na fila do cartão, com a prioridade de vinculo (8)
  select count(*) into v_n from public.parceiro_fila f
   where f.tipo = 'vinculo' and f.prioridade = 8 and f.estado = 'espera'
     and f.chave in ('vinculo:' || v_i_prop, 'vinculo:' || v_i_cart, 'vinculo:' || v_i_pedido);
  if v_n is distinct from 3 then
    raise exception '26c: vínculos na fila: %', v_n;
  end if;
  -- 2ª chamada igual: nenhuma linha nova; tudo ja_decidido
  select count(*) into v_n from public.os_interessados oi where oi.parceiro_id = v_p_lote;
  v_r := public.parceiro_propor(jsonb_build_array(
           jsonb_build_object('service_order_id', v_os_pedido, 'parceiro_id', v_p_lote, 'origem', 'numero_do_pedido', 'papel', 'indicou'),
           jsonb_build_object('service_order_id', v_os_carteira, 'parceiro_id', v_p_lote, 'origem', 'carteira', 'papel', null)), v_dono);
  if jsonb_array_length(v_r -> 'propostos') is distinct from 0 or jsonb_array_length(v_r -> 'recusados') is distinct from 2
     or (select count(*) from public.os_interessados oi where oi.parceiro_id = v_p_lote) is distinct from v_n then
    raise exception '26d: a 2ª chamada não foi idempotente (%)', v_r;
  end if;
  -- veto e OS fora
  v_r := public.parceiro_propor(jsonb_build_array(
           jsonb_build_object('service_order_id', v_os_veto, 'parceiro_id', v_p_lote, 'origem', 'carteira', 'papel', null),
           jsonb_build_object('service_order_id', v_os_rascunho, 'parceiro_id', v_p_lote, 'origem', 'dono', 'papel', null)), v_dono);
  if v_r -> 'recusados' is distinct from jsonb_build_array(
       jsonb_build_object('service_order_id', v_os_veto, 'motivo', 'veto'),
       jsonb_build_object('service_order_id', v_os_rascunho, 'motivo', 'os_fora')) then
    raise exception '26e: veto e OS fora (%)', v_r;
  end if;
  -- 15/16 de novo: depois do propor, nada do teste volta ao lote
  if exists (select 1 from public.parceiro_lote_candidatos(v_p_lote, c_t, 500) x where x.service_order_id = any (v_ids)) then
    raise exception '16: par com linha voltou ao lote';
  end if;

  -- ── 18 e 27. _parceiro_confirmar (o caminho com e sem telefone passa por parceiro_aviso_agendar: P6.2-15) ──
  begin
    perform public._parceiro_confirmar(v_i_cart, v_outro, null, c_t);
    raise exception '18a: confirmar aceitou autor que não é o dono' using errcode = 'P0002';
  exception when sqlstate '42501' then
    null;
  end;
  v_r := public._parceiro_confirmar(v_i_cart, v_dono, null, c_t);
  select * into v_oi from public.os_interessados oi where oi.id = v_i_cart;
  if v_r is distinct from '{"ok": false, "motivo": "sem_papel"}'::jsonb or v_oi.situacao is distinct from 'proposto'
     or v_oi.papel is not null or v_oi.confirmado_em is not null then
    raise exception '18b: papel nulo sem p_papel (%)', v_r;
  end if;
  -- letra P: anfitriã, confirmada sem aviso
  v_r := public._parceiro_confirmar(v_i_cart, v_dono, null, c_t, 'anfitria');
  select * into v_oi from public.os_interessados oi where oi.id = v_i_cart;
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'aviso' is distinct from 'nenhum' or v_oi.situacao is distinct from 'confirmado'
     or v_oi.papel is distinct from 'anfitria' or v_oi.pacote is distinct from 'status' or v_oi.aviso_em is not null
     or v_oi.confirmado_por is distinct from v_dono then
    raise exception '18c: anfitriã (%)', v_r;
  end if;
  perform pg_temp.f4r_vis('18d', v_i_cart, c_t + interval '3 days', 'anfitria');
  -- confirmado não se confirma de novo
  v_r := public._parceiro_confirmar(v_i_cart, v_dono, null, c_t);
  if v_r is distinct from '{"ok": false, "motivo": "nao_proposto"}'::jsonb then
    raise exception '18e: confirmou de novo (%)', v_r;
  end if;
  -- 27. OS da própria parceira: proprio_parceiro e aviso_em, sem aviso agendado
  v_r := public._parceiro_confirmar(v_i_prop, v_dono, null, c_t);
  select * into v_oi from public.os_interessados oi where oi.id = v_i_prop;
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'aviso' is distinct from 'proprio_parceiro'
     or v_oi.aviso_ao_cliente is distinct from 'proprio_parceiro' or v_oi.aviso_em is distinct from c_t
     or v_oi.papel is distinct from 'contratante' or v_oi.pacote is distinct from 'completo' then
    raise exception '27a: OS da própria parceira (%)', v_r;
  end if;
  if exists (select 1 from public.retorno_saidas s where s.tipo = 'parceiro_aviso_cliente' and s.client_id = v_mp) then
    raise exception '27b: a própria parceira ganhou aviso';
  end if;
  -- as 24 h correm do mesmo jeito
  perform pg_temp.f4r_vis('27c', v_i_prop, c_t + interval '23 hours', 'antes_de_24h');
  perform pg_temp.f4r_vis('27d', v_i_prop, c_t + interval '24 hours', null);

  -- ── 19 e 28. parceiro_requalificar ──
  v_c := pg_temp.f4r_cliente('Tânia Regra F4', '5547900014331');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', c_aviso);
  begin
    perform public.parceiro_requalificar(v_i, 'contratante', v_outro);
    raise exception '19a: requalificar aceitou autor que não é o dono' using errcode = 'P0002';
  exception when sqlstate '42501' then
    null;
  end;
  v_r := public.parceiro_requalificar(v_i, 'contratante', v_dono, 'decisao_do_dono', c_t, v_carla);
  select * into v_oi from public.os_interessados oi where oi.id = v_i;
  if (v_r ->> 'ok')::boolean is not true or v_oi.papel is distinct from 'contratante' or v_oi.pacote is distinct from 'completo'
     or v_oi.base is distinct from 'decisao_do_dono' or v_oi.pessoa_id is distinct from v_carla then
    raise exception '19b: requalificar de indicou para contratante (%)', v_r;
  end if;
  if not exists (select 1 from public.audit_log a
                  where a.table_name = 'os_interessados' and a.record_id = v_i and a.action = 'update' and a.changed_by = 'dono'
                    and a.new_value ->> 'papel' = 'contratante') then
    raise exception '19c/28a: requalificar sem linha em audit_log';
  end if;
  -- de volta a indicou: o pacote completo cai para status (o check não deixa completo a quem só indicou)
  v_r := public.parceiro_requalificar(v_i, 'indicou', v_dono);
  select * into v_oi from public.os_interessados oi where oi.id = v_i;
  if v_oi.pacote is distinct from 'status' or v_oi.papel is distinct from 'indicou' then
    raise exception '19d: requalificar de volta a indicou (%)', v_r;
  end if;
  v_r := public.parceiro_requalificar(v_i_pedido, 'contratante', v_dono);
  if v_r is distinct from '{"ok": false, "motivo": "nao_confirmado"}'::jsonb
     or (select oi.situacao from public.os_interessados oi where oi.id = v_i_pedido) is distinct from 'proposto' then
    raise exception '19e: requalificar aceitou proposto (%)', v_r;
  end if;
  v_r := public.parceiro_requalificar(v_i_cart, 'contratante', v_dono);
  if v_r is distinct from '{"ok": false, "motivo": "anfitria"}'::jsonb then
    raise exception '19f: requalificar aceitou anfitriã (%)', v_r;
  end if;
  v_r := public.parceiro_requalificar(v_i, 'anfitria', v_dono);
  if v_r is distinct from '{"ok": false, "motivo": "anfitria"}'::jsonb then
    raise exception '19g: requalificar levou a anfitriã (%)', v_r;
  end if;

  -- ── 24 e 28. parceiro_vinculo_cortar, com parceiro_modo = 'desligado' ──
  v_c := pg_temp.f4r_cliente('Ulisses Regra F4', '5547900014332');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', c_aviso);
  begin
    perform public.parceiro_vinculo_cortar(v_i, 'pausar', v_outro, c_t);
    raise exception '24a: cortar aceitou autor que não é o dono' using errcode = 'P0002';
  exception when sqlstate '42501' then
    null;
  end;
  v_r := public.parceiro_vinculo_cortar(v_i, 'pausar', v_dono, c_t);
  if (v_r ->> 'ok')::boolean is not true or (select oi.situacao from public.os_interessados oi where oi.id = v_i) is distinct from 'pausado' then
    raise exception '24b: pausar (%)', v_r;
  end if;
  perform pg_temp.f4r_vis('24c', v_i, c_t, 'nao_confirmado');
  v_r := public.parceiro_vinculo_cortar(v_i, 'retomar', v_dono, c_t);
  select * into v_oi from public.os_interessados oi where oi.id = v_i;
  if (v_r ->> 'ok')::boolean is not true or v_oi.situacao is distinct from 'confirmado' or v_oi.aviso_em is distinct from c_aviso then
    raise exception '24d: retomar (%)', v_r;
  end if;
  perform pg_temp.f4r_vis('24e', v_i, c_t, null);
  v_r := public.parceiro_vinculo_cortar(v_i, 'retomar', v_dono, c_t);
  if v_r is distinct from '{"ok": false, "motivo": "nao_pausado"}'::jsonb then
    raise exception '24f: retomar o que não está pausado (%)', v_r;
  end if;
  -- veto do dono: grava parceiro_vetos com origem 'dono' e vale para a OS criada depois
  v_r := public.parceiro_vinculo_cortar(v_i, 'veto_dono', v_dono, c_t);
  if (v_r ->> 'ok')::boolean is not true
     or (select v.origem || '|' || v.em::text from public.parceiro_vetos v where v.client_id = v_c and v.parceiro_id = v_p)
        is distinct from 'dono|' || c_t::text then
    raise exception '24g: veto do dono (%)', v_r;
  end if;
  perform pg_temp.f4r_vis('24h', v_i, c_t + interval '1 minute', 'veto');
  v_os2 := pg_temp.f4r_os(v_c, 'open', 'Motorhome', c_t + interval '1 hour');
  v_i2 := pg_temp.f4r_liga(v_os2, v_p, 'indicou', 'confirmado', c_t + interval '2 hours');
  perform pg_temp.f4r_vis('24i', v_i2, c_t + interval '3 days', 'veto');
  -- recusar: para sempre
  v_c := pg_temp.f4r_cliente('Vera Regra F4', '5547900014333');
  v_i := pg_temp.f4r_liga(pg_temp.f4r_os(v_c, 'open'), v_p, 'indicou', 'confirmado', c_aviso);
  v_r := public.parceiro_vinculo_cortar(v_i, 'recusar', v_dono, c_t);
  if (v_r ->> 'ok')::boolean is not true or (select oi.situacao from public.os_interessados oi where oi.id = v_i) is distinct from 'recusado' then
    raise exception '24j: recusar (%)', v_r;
  end if;
  select count(*) into v_n from public.audit_log a
   where a.table_name = 'os_interessados' and a.action = 'update' and a.changed_by = 'dono'
     and a.new_value ->> 'acao' in ('pausar', 'retomar', 'veto_dono', 'recusar')
     and a.record_id in (select oi.id from public.os_interessados oi where oi.parceiro_id = v_p);
  if v_n is distinct from 4 then
    raise exception '24k/28b: audit_log do cortar: % linhas', v_n;
  end if;
  if (select c.parceiro_modo from public.retorno_config c where c.id) is distinct from 'desligado' then
    raise exception '24l: o teste do cortar não rodou com o parceiro desligado';
  end if;

  -- ── O destino do PDF (P12.2) ──
  v_c :=pg_temp.f4r_cliente('Wagner Regra F4', '5547900014334');
  v_os := pg_temp.f4r_os(v_c, 'open');
  v_i := pg_temp.f4r_liga(v_os, v_p, 'contratante', 'confirmado', c_aviso);
  update public.os_interessados set pessoa_id = v_carla where id = v_i;
  begin
    perform public.parceiro_destino_do_pdf(v_os, v_outro, null, c_t);
    raise exception 'pdf-a: destino aceitou autor que não é o dono' using errcode = 'P0002';
  exception when sqlstate '42501' then
    null;
  end;
  v_r := public.parceiro_destino_do_pdf(v_os, v_dono, null, c_t);
  if v_r ->> 'motivo' is distinct from 'desligado' or (v_r ->> 'ok')::boolean is not false then
    raise exception 'pdf-b: com pdf_parceiro_ligado falso (%)', v_r;
  end if;
  update public.retorno_config set pdf_parceiro_ligado = true where id;
  v_r := public.parceiro_destino_do_pdf(v_os, v_dono, null, c_t);
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'phone' is distinct from '5547900014401' or v_r ->> 'chave8' is distinct from '00014401'
     or v_r ->> 'papel' is distinct from 'contratante' or (v_r ->> 'interessado_id')::uuid is distinct from v_i
     or (v_r ->> 'parceiro_id')::uuid is distinct from v_p or (v_r ->> 'reduzir')::boolean is not true
     or v_r ->> 'rotulo' is distinct from 'RRF (Carla, ••4401)' then
    raise exception 'pdf-c: contratante (%)', v_r;
  end if;
  -- pagador: o número do financeiro
  update public.os_interessados set papel = 'pagador', pacote = 'completo' where id = v_i;
  v_r := public.parceiro_destino_do_pdf(v_os, v_dono, v_p, c_t);
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'phone' is distinct from '5547900014402' then
    raise exception 'pdf-d: pagador (%)', v_r;
  end if;
  -- dois números financeiros: ambíguo, nunca por nome
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, uso)
    values (v_fin, '5547900014403', '00014403', '47', 'confirmado', c_t - interval '30 days', 'financeiro');
  v_r := public.parceiro_destino_do_pdf(v_os, v_dono, null, c_t);
  if v_r ->> 'motivo' is distinct from 'destino_ambiguo' or v_r ->> 'frase' is distinct from 'Não sei qual número da RRF recebe este PDF; nada saiu.' then
    raise exception 'pdf-e: dois números (%)', v_r;
  end if;
  -- indicou: nunca
  update public.os_interessados set papel = 'indicou', pacote = 'status' where id = v_i;
  v_r := public.parceiro_destino_do_pdf(v_os, v_dono, null, c_t);
  if v_r ->> 'motivo' is distinct from 'papel' or (v_r ->> 'ok')::boolean is not false then
    raise exception 'pdf-f: quem só indicou (%)', v_r;
  end if;
  -- contratante sem aviso: sem_aviso; com pdf_sem_espera_ligado, sai; o veto continua fechando
  update public.os_interessados set papel = 'contratante', pacote = 'completo', aviso_ao_cliente = 'nao_avisado', aviso_em = null where id = v_i;
  v_r := public.parceiro_destino_do_pdf(v_os, v_dono, null, c_t);
  if v_r ->> 'motivo' is distinct from 'sem_aviso' then
    raise exception 'pdf-g: sem aviso (%)', v_r;
  end if;
  update public.retorno_config set pdf_sem_espera_ligado = true where id;
  v_r := public.parceiro_destino_do_pdf(v_os, v_dono, null, c_t);
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'phone' is distinct from '5547900014401' then
    raise exception 'pdf-h: sem espera ligado (%)', v_r;
  end if;
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem) values (v_c, v_p, c_t - interval '1 minute', 'nao_mp');
  v_r := public.parceiro_destino_do_pdf(v_os, v_dono, null, c_t);
  if v_r ->> 'motivo' is distinct from 'veto' then
    raise exception 'pdf-i: veto com sem espera ligado (%)', v_r;
  end if;
  -- sem vínculo
  v_r := public.parceiro_destino_do_pdf(v_os_a, v_dono, v_p_lote, c_t);
  if v_r ->> 'motivo' is distinct from 'sem_vinculo' then
    raise exception 'pdf-j: sem vínculo (%)', v_r;
  end if;
  update public.retorno_config set pdf_parceiro_ligado = false, pdf_sem_espera_ligado = false where id;

  -- ── 25. parceiro_semear ──
  insert into public.payees (name, kind, active, phone) values ('Equipe Regra F4', 'prestador', true, '5547900014493');
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
    values ('inbound', '5547900007391', 'text', 'oi teste f4', 'teste-f4-regra-13', c_t - interval '10 days'),
           ('inbound', '554700007391', 'text', 'oi teste f4', 'teste-f4-regra-12', c_t - interval '9 days');
  v_semente := jsonb_build_array(jsonb_build_object(
    'nome', 'Semente Regra F4', 'sigla', 'SRF', 'tipo', 'revenda_e_patio', 'client_id', null,
    'pessoas', jsonb_build_array(
      jsonb_build_object('nome', 'Carla', 'papel', 'comercial', 'numeros', jsonb_build_array(
        jsonb_build_object('telefone', '5547900007391', 'rotulo', 'comercial', 'uso', 'comercial', 'recebe_painel', true, 'recebe_documento', false),
        jsonb_build_object('telefone', '5547900014493', 'rotulo', 'x', 'uso', 'comercial', 'recebe_painel', false, 'recebe_documento', false),
        jsonb_build_object('telefone', '123', 'uso', 'comercial', 'recebe_painel', false, 'recebe_documento', false),
        jsonb_build_object('telefone', '5547900014494', 'recebe_painel', false, 'recebe_documento', false),
        jsonb_build_object('telefone', '5547900014401', 'uso', 'comercial', 'recebe_painel', false, 'recebe_documento', false))),
      jsonb_build_object('nome', null, 'papel', 'comercial', 'numeros', jsonb_build_array(
        jsonb_build_object('telefone', '47900014495', 'uso', 'comercial', 'recebe_painel', true, 'recebe_documento', false))))));
  begin
    perform public.parceiro_semear(v_semente, v_outro);
    raise exception '25a: semear aceitou autor que não é o dono' using errcode = 'P0002';
  exception when sqlstate '42501' then
    null;
  end;
  v_r := public.parceiro_semear(v_semente, v_dono);
  if (v_r ->> 'ok')::boolean is not true or (v_r ->> 'parceiros')::int is distinct from 1 or (v_r ->> 'pessoas')::int is distinct from 2
     or (v_r ->> 'numeros')::int is distinct from 2 or (v_r ->> 'atualizados')::int is distinct from 0
     or v_r -> 'recusados' is distinct from jsonb_build_array(
          jsonb_build_object('final', '••4493', 'motivo', 'numero_da_equipe'),
          jsonb_build_object('final', '••123', 'motivo', 'telefone_invalido'),
          jsonb_build_object('final', '••4494', 'motivo', 'campo_faltando'),
          jsonb_build_object('final', '••4401', 'motivo', 'numero_de_outro_parceiro')) then
    raise exception '25b: 1ª semente (%)', v_r;
  end if;
  select n.* into v_rec
    from public.parceiro_numeros n
    join public.parceiro_pessoas p on p.id = n.pessoa_id
    join public.parceiros pa on pa.id = p.parceiro_id
   where pa.sigla = 'SRF' and n.chave = '00007391';
  if v_rec.situacao is distinct from 'confirmado' or v_rec.confirmado_por is distinct from v_dono or v_rec.ddd is distinct from '47'
     or v_rec.phone_normalized is distinct from '5547900007391' or v_rec.recebe_painel is not true or v_rec.rotulo is distinct from 'comercial' then
    raise exception '25c: número da semente gravado errado';
  end if;
  if not exists (select 1 from public.parceiro_numeros n join public.parceiro_pessoas p on p.id = n.pessoa_id
                  where n.chave = '00014495' and p.nome is null and n.phone_normalized = '5547900014495') then
    raise exception '25d: número compartilhado (sem nome, com 55 acrescentado)';
  end if;
  -- as duas formas do telefone de final 7391 na exclusão do detector
  select count(*) into v_n from public.agenda_detector_exclusions e
   where e.phone_normalized in ('5547900007391', '554700007391') and e.label = 'parceiro';
  if v_n is distinct from 2 then
    raise exception '25e: formas do telefone na exclusão: %', v_n;
  end if;
  if not exists (select 1 from public.agenda_detector_exclusions e where e.phone_normalized = '5547900014495') then
    raise exception '25f: a forma de 13 dígitos do compartilhado não entrou';
  end if;
  -- 2ª chamada: não duplica e devolve atualizados (com o rótulo novo)
  v_semente := jsonb_set(v_semente, '{0,pessoas,0,numeros,0,rotulo}', '"Carla celular"');
  v_r := public.parceiro_semear(v_semente, v_dono);
  if (v_r ->> 'parceiros')::int is distinct from 0 or (v_r ->> 'pessoas')::int is distinct from 0
     or (v_r ->> 'numeros')::int is distinct from 0 or (v_r ->> 'atualizados')::int is distinct from 2 then
    raise exception '25g: 2ª semente (%)', v_r;
  end if;
  if (select count(*) from public.parceiros pa where pa.sigla = 'SRF') is distinct from 1
     or (select count(*) from public.parceiro_numeros n where n.chave in ('00007391', '00014495')) is distinct from 2
     or (select n.rotulo from public.parceiro_numeros n where n.chave = '00007391') is distinct from 'Carla celular'
     or (select count(*) from public.agenda_detector_exclusions e where e.phone_normalized in ('5547900007391', '554700007391')) is distinct from 2 then
    raise exception '25h: a 2ª semente duplicou';
  end if;
  -- o número semeado identifica: quem_escreve dá parceiro
  if public.quem_escreve('5547900007391') ->> 'papel' is distinct from 'parceiro' then
    raise exception '25i: o número semeado não identifica o parceiro (%)', public.quem_escreve('5547900007391');
  end if;

  -- ── parceiro_numeros_fora_da_ia (P12.4) ──
  update public.retorno_config set parceiro_historico_na_ia = false where id;
  if not (array['00014401', '00007391']::text[] <@ public.parceiro_numeros_fora_da_ia())
     or exists (select 1 from unnest(public.parceiro_numeros_fora_da_ia()) x where x !~ '^[0-9]{8}$') then
    raise exception 'ia-a: chaves fora do assistente (%)', public.parceiro_numeros_fora_da_ia();
  end if;
  update public.retorno_config set parceiro_historico_na_ia = true where id;
  if public.parceiro_numeros_fora_da_ia() is distinct from '{}'::text[] then
    raise exception 'ia-b: com a chave ligada, a lista não ficou vazia';
  end if;
  update public.retorno_config set parceiro_historico_na_ia = false where id;

  -- ── A varredura do parceiro: as funções fechadas a anon e authenticated ──
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
  if to_regprocedure('public.parceiro_os_visivel(uuid, timestamptz)') is null
     or to_regprocedure('public.parceiro_semear(jsonb, uuid)') is null or v_n_fun < 12 then
    raise exception 'grants: a varredura não achou as funções da P3 (%)', v_n_fun;
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_regra', true, '{}');
end
$regra$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
