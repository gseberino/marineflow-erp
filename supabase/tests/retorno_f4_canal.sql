-- Retorno F4 (P5): o canal e as saídas do parceiro. Primeiro a regressão com a F4 desligada (nada muda para o cliente, o
-- número novo e a F1–F3); depois a janela e o teto das classes novas, parceiro_agendar, cada linha do parceiro_pegar,
-- parceiro_saida_sem_linhas, parceiro_saida_autorizada, _parceiro_aplicar_efeitos e a triagem das regras 6 e 8. Roda só pela
-- bancada (grupo 7, F4_ONDA=4). Termina em ROLLBACK. Telefones de teste 55479000145xx e 55479000146xx; nomes inventados.
-- Relógio: ter 12/01/2027 10:00 (respostas e aviso) e sex 15/01/2027 17:50 (painel).
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f4c_cliente(p_nome text, p_fone text) returns uuid
language sql as $f$
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id
$f$;

create or replace function pg_temp.f4c_os(p_cliente uuid) returns uuid
language plpgsql as $f$
declare
  v_v uuid;
  v_id uuid;
begin
  insert into public.vessels (client_id, name, asset_type)
    values (p_cliente, 'Unidade ' || left(md5(p_cliente::text || clock_timestamp()::text), 6), 'Motorhome') returning id into v_v;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                     updated_at, grand_total)
  values ('OS-TF4C-' || left(md5(p_cliente::text || clock_timestamp()::text || random()::text), 8), p_cliente, v_v, 'open',
          'approved', 'repair', '2026-12-10 10:00-03', '2026-12-10 10:00-03', 0)
  returning id into v_id;
  return v_id;
end $f$;

create or replace function pg_temp.f4c_liga(p_os uuid, p_parceiro uuid, p_papel text, p_aviso_em timestamptz,
                                            p_aviso text default 'mensagem') returns uuid
language plpgsql as $f$
declare
  v uuid;
begin
  insert into public.os_interessados (service_order_id, parceiro_id, client_id, papel, situacao, origem, aviso_ao_cliente, aviso_em,
                                      confirmado_em)
  select so.id, p_parceiro, so.client_id, p_papel, 'confirmado', 'dono',
         case when p_aviso_em is null then 'nao_avisado' else p_aviso end, p_aviso_em, timestamptz '2027-01-01 10:00-03'
    from public.service_orders so where so.id = p_os
  returning id into v;
  return v;
end $f$;

-- A linha do painel (só ids, estado e data), como a P7 grava.
create or replace function pg_temp.f4c_linha(p_n integer, p_interessado uuid, p_estado text, p_desde date default null) returns jsonb
language sql as $f$
  select jsonb_build_object('n', p_n, 'interessado_id', oi.id, 'service_order_id', oi.service_order_id, 'estado', p_estado,
                            'desde', p_desde)
    from public.os_interessados oi where oi.id = p_interessado
$f$;

-- Os dados do painel e do pátio: as linhas e as duas listas na mesma ordem.
create or replace function pg_temp.f4c_dados(p_linhas jsonb, p_extra jsonb default '{}') returns jsonb
language sql as $f$
  select jsonb_build_object('linhas', p_linhas,
                            'os_ids', (select coalesce(jsonb_agg(x -> 'service_order_id' order by o), '[]'::jsonb)
                                         from jsonb_array_elements(p_linhas) with ordinality t(x, o)),
                            'interessado_ids', (select coalesce(jsonb_agg(x -> 'interessado_id' order by o), '[]'::jsonb)
                                                  from jsonb_array_elements(p_linhas) with ordinality t(x, o)))
         || p_extra
$f$;

-- A saída à parceira, pela porta única, com chave de teste.
create or replace function pg_temp.f4c_agenda(p_tipo text, p_var text, p_numero uuid, p_dados jsonb, p_em timestamptz, p_tag text,
                                              p_abertura uuid default null) returns uuid
language sql as $f$
  select public.parceiro_agendar(p_tipo, p_var, p_numero, p_abertura, p_dados, p_em, 'parceiro:teste:' || p_tag, null, null)
$f$;

-- O aviso ao cliente final, pela porta única.
create or replace function pg_temp.f4c_aviso(p_cliente uuid, p_parceiro uuid, p_ids uuid[], p_em timestamptz, p_tag text) returns uuid
language sql as $f$
  select public.parceiro_agendar('parceiro_aviso_cliente', null, null, null,
           jsonb_build_object('client_id', p_cliente, 'parceiro_id', p_parceiro, 'interessado_ids', to_jsonb(p_ids), 'papel', 'indicou'),
           p_em, 'parceiro:teste:' || p_tag, 'aviso',
           (select coalesce(nullif(c.whatsapp, ''), c.phone) from public.clients c where c.id = p_cliente))
$f$;

-- Um caso do parceiro (a abertura), com uma recebida de teste.
create or replace function pg_temp.f4c_caso(p_fone text, p_em timestamptz) returns uuid
language plpgsql as $f$
declare
  v_m uuid;
  v uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
    values ('inbound', p_fone, 'text', 'mensagem de teste f4 canal', 'teste-f4-canal-' || md5(p_fone || p_em::text || clock_timestamp()::text), p_em)
    returning id into v_m;
  -- um caso vivo por número (retorno_aberturas_uma_viva): o anterior fecha antes, como na vida real
  update public.retorno_aberturas a
     set estado = 'fechada', fechada_em = greatest(a.aberta_em, p_em), fechada_motivo = 'expirou'
   where a.chave = right(p_fone, 8) and a.estado in ('aberta', 'vencida');
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, primeira_msg_id, ultima_msg_id, aberta_em, gravada_em,
                                        ultima_em, ultima_gravada_em, nivel, motivo, tipo_recibo, modo)
    values (right(p_fone, 8), p_fone, '47', 'parceiro', public.quem_escreve(p_fone), v_m, v_m, p_em, p_em, p_em, p_em,
            'recibo', null, 'recibo_parceiro', 'sombra')
    returning id into v;
  return v;
end $f$;

create or replace function pg_temp.f4c_estado(p_id uuid) returns text
language sql as $f$
  select s.estado || '/' || coalesce(s.motivo, '') from public.retorno_saidas s where s.id = p_id
$f$;

-- Entre um caso de teste e outro: as saídas de teste somem e o espaçamento volta a zero.
create or replace function pg_temp.f4c_limpa() returns void
language sql as $f$
  delete from public.retorno_saidas where dedupe_key like 'parceiro:teste:%';
  update public.retorno_config set proximo_envio_em = null where id;
$f$;

do $canal$
declare
  c_t constant timestamptz := '2027-01-12 10:00-03';        -- ter
  c_painel constant timestamptz := '2027-01-15 17:50-03';   -- sex
  v_p uuid;
  v_carla uuid;
  v_compart uuid;
  v_n1 uuid;
  v_n2 uuid;
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_e uuid; v_f uuid; v_g uuid; v_h uuid;
  v_cli uuid;
  v_os_a uuid; v_os_b uuid; v_os_e uuid;
  v_va uuid; v_vb uuid; v_vc uuid; v_vd uuid; v_ve uuid; v_ve2 uuid; v_vf uuid; v_vg uuid; v_vh uuid;
  v_s uuid; v_s2 uuid; v_s3 uuid;
  v_caso uuid; v_caso2 uuid;
  v_painel uuid;
  v_r jsonb;
  v_x public.retorno_saidas;
  v_ab public.retorno_aberturas;
  v_oi public.os_interessados;
  v_n integer;
  v_t text;
  v_linhas jsonb;
  v_ids uuid[];
  v_m uuid;
  v_antes text;
  v_rec record;
  v_n_fun integer := 0;
  c_nomes constant text[] := array['Abigail', 'Benedito', 'Clarice', 'Durval', 'Eunice', 'Felisberto', 'Graciela', 'Heitor',
                                   'Iolanda', 'Jacinto', 'Leonora', 'Marcolino', 'Noemia', 'Otaviano', 'Perpetua', 'Quirino',
                                   'Rosalina', 'Severino', 'Tereza', 'Valdomiro'];
begin
  begin
  update public.retorno_config
     set modo = 'sombra', identificacao_nova = true, parceiro_modo = 'desligado', tipos_ligados = '{}', parceiro_tipos_ligados = '{}',
         proximo_envio_em = null, segura_tudo_ate = null, so_reativo = false, segura_patio = false, patio_nivel = 'cartao',
         eco_modo = 'sombra', carencia_min = 2, respostas_dia_max = 40, iniciadas_dia_max = 12
   where id;

  -- Arranjo: a revenda, a Carla (com nome, recebe o painel) e o número compartilhado.
  insert into public.parceiros (nome, sigla, tipo) values ('Revenda Canal F4', 'RCF', 'revenda_e_patio') returning id into v_p;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, 'Carla', 'comercial') returning id into v_carla;
  insert into public.parceiro_pessoas (parceiro_id, nome, papel) values (v_p, null, 'comercial') returning id into v_compart;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_carla, '5547900014501', '00014501', '47', 'confirmado', c_t - interval '30 days', true) returning id into v_n1;
  insert into public.parceiro_numeros (pessoa_id, phone_normalized, chave, ddd, situacao, confirmado_em, recebe_painel)
    values (v_compart, '5547900014502', '00014502', '47', 'confirmado', c_t - interval '30 days', false) returning id into v_n2;
  v_a := pg_temp.f4c_cliente('Ana Canal', '5547900014511');
  v_b := pg_temp.f4c_cliente('Bruno Canal', '5547900014512');
  v_c := pg_temp.f4c_cliente('Caio Canal', '5547900014513');
  v_d := pg_temp.f4c_cliente('Dora Canal', '5547900014514');
  v_e := pg_temp.f4c_cliente('Elma Canal', '5547900014515');
  v_f := pg_temp.f4c_cliente('Fausto Canal', '5547900014516');
  v_g := pg_temp.f4c_cliente('Gina Canal', '5547900014517');
  v_h := pg_temp.f4c_cliente('Hilda Canal', '5547900014518');
  v_os_a := pg_temp.f4c_os(v_a);
  v_os_b := pg_temp.f4c_os(v_b);
  v_os_e := pg_temp.f4c_os(v_e);
  v_va := pg_temp.f4c_liga(v_os_a, v_p, 'indicou', c_t - interval '25 hours');
  v_vb := pg_temp.f4c_liga(v_os_b, v_p, 'indicou', c_t - interval '25 hours');
  v_vc := pg_temp.f4c_liga(pg_temp.f4c_os(v_c), v_p, 'indicou', null);
  v_vd := pg_temp.f4c_liga(pg_temp.f4c_os(v_d), v_p, 'indicou', null);
  v_ve := pg_temp.f4c_liga(v_os_e, v_p, 'indicou', c_t - interval '25 hours');
  v_ve2 := pg_temp.f4c_liga(v_os_e, v_p, 'anfitria', c_t - interval '25 hours');
  v_vf := pg_temp.f4c_liga(pg_temp.f4c_os(v_f), v_p, 'indicou', c_t - interval '3 days', 'pela_revenda');
  v_vg := pg_temp.f4c_liga(pg_temp.f4c_os(v_g), v_p, 'indicou', null);
  v_vh := pg_temp.f4c_liga(pg_temp.f4c_os(v_h), v_p, 'indicou', null);

  -- ══ Regressão com a F4 desligada: nada muda para o cliente, o número novo e a F1–F3 ══
  -- R1. As classes novas continuam classe_nao_suportada (F1, retorno_f1_canal 2a e 2d); a resposta, igual.
  v_r := public.canal_pode_enviar('5547900014511', 'aviso', 'retorno_aviso', c_t);
  if v_r is distinct from '{"pode": false, "motivo": "classe_nao_suportada", "enviar_em": null}'::jsonb then
    raise exception 'R1a: aviso com a F4 desligada (%)', v_r;
  end if;
  v_r := public.canal_pode_enviar('5547900014501', 'resumo_parceiro', 'retorno_parceiro', c_painel);
  if v_r is distinct from '{"pode": false, "motivo": "classe_nao_suportada", "enviar_em": null}'::jsonb then
    raise exception 'R1b: resumo_parceiro com a F4 desligada (%)', v_r;
  end if;
  v_r := public.canal_pode_enviar('5547900014511', 'resposta_imediata', 'retorno_recibo', c_t);
  if v_r is distinct from '{"pode": true, "motivo": null, "enviar_em": null}'::jsonb then
    raise exception 'R1c: a resposta ao cliente mudou (%)', v_r;
  end if;
  -- R2. A janela das classes novas: fora, sem abertura (F1, retorno_f1_canal 9q); a da resposta, igual.
  if public._retorno_janela('aviso', c_t, '00014511') is distinct from '{"dentro": false, "enviar_em": null}'::jsonb
     or public._retorno_janela('resumo_parceiro', c_painel, '00014501') is distinct from '{"dentro": false, "enviar_em": null}'::jsonb
     or public._retorno_janela('resposta_imediata', c_t, '00014511') is distinct from '{"dentro": true, "enviar_em": null}'::jsonb then
    raise exception 'R2: janela com a F4 desligada';
  end if;
  -- R3 e 22c. Saída do parceiro agendada: retorno_pegar nunca a pega; parceiro_pegar a cancela (parceiro_desligado).
  v_s := pg_temp.f4c_agenda('parceiro_pausa', 'pausar', v_n1, '{}', c_t - interval '1 minute', 'r3');
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
    values ('retorno', 'recibo_cliente', 'retorno_recibo', 'resposta_imediata', '00014511', '5547900014511', 'sombra',
            c_t - interval '2 minutes', 'teste-f4-canal:r3:retorno')
    returning id into v_s2;
  perform public.retorno_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'agendada/' then
    raise exception 'R3a: retorno_pegar mexeu na saída do parceiro (%)', pg_temp.f4c_estado(v_s);
  end if;
  if pg_temp.f4c_estado(v_s2) is not distinct from 'agendada/' then
    raise exception 'R3b: retorno_pegar não pegou a saída do retorno';
  end if;
  if public.parceiro_pegar(c_t) is not null or pg_temp.f4c_estado(v_s) is distinct from 'cancelada/parceiro_desligado' then
    raise exception '22c: parceiro desligado não cancelou (%)', pg_temp.f4c_estado(v_s);
  end if;
  -- R4 e 8. retorno_saida_autorizada da saída do retorno, como antes.
  if public.retorno_saida_autorizada(gen_random_uuid(), '5547900014511', c_t) is distinct from '{"pode": false, "motivo": "sem_saida"}'::jsonb then
    raise exception 'R4a: sem saída';
  end if;
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
    values ('retorno', 'recibo_cliente', 'retorno_recibo', 'resposta_imediata', '00014511', '5547900014511', 'sombra',
            c_t + interval '1 hour', 'teste-f4-canal:r4:retorno')
    returning id into v_s2;
  if public.retorno_saida_autorizada(v_s2, '5547900014511', c_t) is distinct from '{"pode": false, "motivo": "estado"}'::jsonb then
    raise exception 'R4b/8: a autorização da saída do retorno mudou (%)', public.retorno_saida_autorizada(v_s2, '5547900014511', c_t);
  end if;
  -- R5. retorno_registrar_decisao: estado de partida errado, como antes.
  if public.retorno_registrar_decisao(v_s2, 'sombra', '{}', c_t) is distinct from '{"ok": false, "erro": "estado"}'::jsonb then
    raise exception 'R5: retorno_registrar_decisao mudou';
  end if;
  delete from public.retorno_saidas where dedupe_key like 'teste-f4-canal:%';
  perform pg_temp.f4c_limpa();

  -- ══ A F4 em sombra ══
  update public.retorno_config set parceiro_modo = 'sombra' where id;

  -- 1. As classes novas no canal, com a origem do parceiro.
  if public.canal_pode_enviar('5547900014511', 'aviso', 'retorno_aviso', c_t) is distinct from '{"pode": true, "motivo": null, "enviar_em": null}'::jsonb then
    raise exception '1a: aviso dentro da janela (%)', public.canal_pode_enviar('5547900014511', 'aviso', 'retorno_aviso', c_t);
  end if;
  if public.canal_pode_enviar('5547900014511', 'aviso', 'retorno_recibo', c_t) ->> 'motivo' is distinct from 'classe_nao_suportada' then
    raise exception '1b: aviso com a origem do retorno passou';
  end if;
  v_r := public.canal_pode_enviar('5547900014511', 'aviso', 'retorno_aviso', '2027-01-12 21:00-03');
  if v_r ->> 'motivo' is distinct from 'fora_da_janela' or (v_r ->> 'enviar_em')::timestamptz is distinct from '2027-01-13 08:00-03'::timestamptz then
    raise exception '1c: aviso às 21:00 (%)', v_r;
  end if;
  -- sábado de manhã: dentro; sábado 13:30: a segunda 08:00
  if (public.canal_pode_enviar('5547900014511', 'aviso', 'retorno_aviso', '2027-01-16 10:00-03') ->> 'pode')::boolean is not true then
    raise exception '1d: aviso no sábado de manhã';
  end if;
  v_r := public.canal_pode_enviar('5547900014511', 'aviso', 'retorno_aviso', '2027-01-16 13:30-03');
  if (v_r ->> 'enviar_em')::timestamptz is distinct from '2027-01-18 08:00-03'::timestamptz then
    raise exception '1e: aviso no sábado à tarde (%)', v_r;
  end if;
  -- sexta 17:45: o painel sai; 17:00 espera as 17:45; 18:30 já não sai no dia
  if (public.canal_pode_enviar('5547900014501', 'resumo_parceiro', 'retorno_parceiro', '2027-01-15 17:45-03') ->> 'pode')::boolean is not true then
    raise exception '1f: painel sexta 17:45';
  end if;
  v_r := public.canal_pode_enviar('5547900014501', 'resumo_parceiro', 'retorno_parceiro', '2027-01-15 17:00-03');
  if v_r ->> 'motivo' is distinct from 'fora_da_janela' or (v_r ->> 'enviar_em')::timestamptz is distinct from '2027-01-15 17:45-03'::timestamptz then
    raise exception '1g: painel 17:00 (%)', v_r;
  end if;
  v_r := public.canal_pode_enviar('5547900014501', 'resumo_parceiro', 'retorno_parceiro', '2027-01-15 18:30-03');
  if v_r is distinct from '{"pode": false, "motivo": "fora_da_janela", "enviar_em": null}'::jsonb then
    raise exception '1h: painel 18:30 (%)', v_r;
  end if;
  if public._retorno_janela('resumo_parceiro', '2027-01-16 17:50-03', '00014501') is distinct from '{"dentro": false, "enviar_em": null}'::jsonb then
    raise exception '1i: painel no sábado';
  end if;

  -- 2. O teto das iniciadas: 11 avisos e painéis decididos hoje + 1 da agenda = 12. A resposta não entra.
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, estado, enviar_em, decidida_em,
                                     enviada_em, texto, dedupe_key)
  select 'parceiro', case when g % 2 = 0 then 'parceiro_eco' else 'parceiro_painel' end, 'retorno_parceiro',
         case when g % 2 = 0 then 'aviso' else 'resumo_parceiro' end, '00014501', '5547900014501', 'ligado', 'enviada',
         c_t - interval '2 hours', c_t - interval '2 hours', c_t - interval '2 hours', 'texto de teste do teto',
         'parceiro:teste:teto:' || g
    from generate_series(1, 11) g;
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate, aprovacao,
                                               estado, dedupe_key, enviada_em, criada_em)
    values (v_a, v_os_a, 'pronto_lembrete', 'rodada', 'ligado', 'mensagem de teste (F4 canal)', c_t - interval '1 hour',
            c_t + interval '8 hours', 'livre', 'enviada', 'agenda-cliente:teste:f4canal', c_t - interval '1 hour', c_t - interval '2 hours');
  v_r := public.canal_pode_enviar('5547900014511', 'aviso', 'retorno_aviso', c_t);
  if v_r ->> 'motivo' is distinct from 'teto_iniciadas' or (v_r ->> 'enviar_em')::timestamptz is distinct from '2027-01-13 08:00-03'::timestamptz then
    raise exception '2a: teto das iniciadas no aviso (%)', v_r;
  end if;
  if (public.canal_pode_enviar('5547900014511', 'resposta_imediata', 'retorno_recibo', c_t) ->> 'pode')::boolean is not true then
    raise exception '2b: a resposta entrou no teto das iniciadas';
  end if;
  -- 4j. Linha 9: o teto das iniciadas com hora futura só reagenda (a ativação, classe aviso).
  v_s := pg_temp.f4c_agenda('parceiro_ativacao', null, v_n1, '{}', c_t - interval '1 minute', '4j');
  perform public.parceiro_pegar(c_t);
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.estado is distinct from 'agendada' or v_x.enviar_em is distinct from '2027-01-13 08:00-03'::timestamptz then
    raise exception '4j: a ativação no teto das iniciadas não reagendou (% % % %)', v_x.estado, v_x.motivo, v_x.enviar_em, v_x.dados -> 'erro';
  end if;
  -- o registro da agenda não se apaga nem muda (_agenda_registro_nao_apaga, so_muda): fica, e sozinho conta 1 de 12 no teto
  perform pg_temp.f4c_limpa();

  -- 21. Com respostas_dia_max atingido, a resposta dá teto_dia e o aviso sai; aviso e painel nunca dão teto_dia.
  update public.retorno_config set respostas_dia_max = 0 where id;
  if public.canal_pode_enviar('5547900014511', 'resposta_imediata', 'retorno_recibo', c_t) ->> 'motivo' is distinct from 'teto_dia'
     or (public.canal_pode_enviar('5547900014511', 'aviso', 'retorno_aviso', c_t) ->> 'pode')::boolean is not true
     or (public.canal_pode_enviar('5547900014501', 'resumo_parceiro', 'retorno_parceiro', c_painel) ->> 'pode')::boolean is not true then
    raise exception '21: teto das respostas';
  end if;
  update public.retorno_config set respostas_dia_max = 40 where id;

  -- 23. parceiro_agendar: nenhum ou os dois destinos dão 22023.
  begin
    perform public.parceiro_agendar('parceiro_pausa', 'pausar', null, null, '{}', c_t, 'parceiro:teste:23a', null, null);
    raise exception '23a: aceitou sem destino' using errcode = 'P0002';
  exception when sqlstate '22023' then
    null;
  end;
  begin
    perform public.parceiro_agendar('parceiro_pausa', 'pausar', v_n1, null, '{}', c_t, 'parceiro:teste:23b', null, '5547900014511');
    raise exception '23b: aceitou os dois destinos' using errcode = 'P0002';
  exception when sqlstate '22023' then
    null;
  end;
  begin
    perform public.parceiro_agendar('parceiro_pausa', 'pausar', v_n1, null, '{}', c_t, 'parceiro:teste:23c', 'aviso', null);
    raise exception '23c: aceitou a classe errada' using errcode = 'P0002';
  exception when sqlstate '22023' then
    null;
  end;
  -- com o tipo em sombra, a chave ganha :sombra e nasce agendada, em sombra, com os ids do número
  v_s := pg_temp.f4c_agenda('parceiro_pausa', 'pausar', v_n1, jsonb_build_object('numero_id', gen_random_uuid()), c_t, '23d');
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.dedupe_key is distinct from 'parceiro:teste:23d:sombra' or v_x.emissor is distinct from 'parceiro' or v_x.estado is distinct from 'agendada'
     or v_x.origem is distinct from 'retorno_parceiro' or v_x.classe is distinct from 'resposta_imediata' or v_x.chave is distinct from '00014501'
     or (v_x.dados ->> 'numero_id')::uuid is distinct from v_n1 or (v_x.dados ->> 'parceiro_id')::uuid is distinct from v_p then
    raise exception '23d: a saída agendada nasceu errada';
  end if;
  if pg_temp.f4c_agenda('parceiro_pausa', 'pausar', v_n1, '{}', c_t, '23d') is distinct from v_s then
    raise exception '23e: a mesma chave criou outra saída';
  end if;
  perform pg_temp.f4c_limpa();

  -- 3. retorno_pegar não pega o emissor parceiro; parceiro_pegar não pega o resto. 4a: a sombra (linhas 8 e 10).
  v_s := pg_temp.f4c_agenda('parceiro_pausa', 'pausar', v_n1, '{}', c_t - interval '1 minute', '3');
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, enviar_em, dedupe_key)
    values ('retorno', 'recibo_cliente', 'retorno_recibo', 'resposta_imediata', '00014511', '5547900014511', 'sombra',
            c_t - interval '2 minutes', 'teste-f4-canal:3:retorno')
    returning id into v_s2;
  v_r := public.parceiro_pegar(c_t);
  if (v_r ->> 'saida_id')::uuid is distinct from v_s or pg_temp.f4c_estado(v_s2) is distinct from 'agendada/' then
    raise exception '3a: parceiro_pegar pegou outra saída (%)', v_r;
  end if;
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.estado is distinct from 'preparada' or v_x.modo is distinct from 'sombra' or v_x.texto is distinct from 'Combinado: o resumo fica pausado. Para voltar, mande *retomar*.'
     or v_x.dados ->> 'sombra_motivo' is distinct from 'parceiro_modo' or v_r ->> 'modo' is distinct from 'sombra'
     or v_r -> 'validador' ->> 'audiencia' is distinct from 'parceiro' or v_r ->> 'origem' is distinct from 'retorno_parceiro'
     or v_r ->> 'dedupe_key' !~ '^parceiro:' or v_r ? 'linhas' then
    raise exception '4a: a pausa em sombra (%)', v_r;
  end if;
  perform public.retorno_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'preparada/' then
    raise exception '3b: retorno_pegar mexeu na saída do parceiro';
  end if;
  delete from public.retorno_saidas where dedupe_key like 'teste-f4-canal:%';
  perform pg_temp.f4c_limpa();

  -- ── 4. Cada linha do parceiro_pegar ──
  -- Linha 1: o número que deixou de ser confirmado.
  update public.parceiro_numeros set situacao = 'pausado' where id = v_n1;
  v_s := pg_temp.f4c_agenda('parceiro_pausa', 'pausar', v_n1, '{}', c_t - interval '1 minute', '4b');
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/parceiro_regra' then
    raise exception '4b: linha 1 (%)', pg_temp.f4c_estado(v_s);
  end if;
  update public.parceiro_numeros set situacao = 'confirmado' where id = v_n1;
  -- Linha 2: a pessoa pausada (o eco cai antes da linha 6); o número que não recebe o resumo.
  update public.parceiro_pessoas set pausado_em = c_t - interval '1 day' where id = v_carla;
  v_s := pg_temp.f4c_agenda('parceiro_eco', 'pronto', v_n1, pg_temp.f4c_dados(jsonb_build_array(pg_temp.f4c_linha(1, v_va, 'pronto'))),
                            c_t - interval '1 minute', '4c');
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/pausado' then
    raise exception '4c: linha 2, pessoa pausada (%)', pg_temp.f4c_estado(v_s);
  end if;
  update public.parceiro_pessoas set pausado_em = null where id = v_carla;
  v_s := pg_temp.f4c_agenda('parceiro_eco', 'pronto', v_n2, pg_temp.f4c_dados(jsonb_build_array(pg_temp.f4c_linha(1, v_va, 'pronto'))),
                            c_t - interval '1 minute', '4d');
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/pausado' then
    raise exception '4d: linha 2, número sem recebe_painel (%)', pg_temp.f4c_estado(v_s);
  end if;
  -- Linha 3: segura pátio.
  update public.retorno_config set segura_patio = true where id;
  v_s := pg_temp.f4c_agenda('parceiro_patio', 'vazio', v_n1, '{}', c_t - interval '1 minute', '4e');
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/segura_patio' then
    raise exception '4e: linha 3 (%)', pg_temp.f4c_estado(v_s);
  end if;
  update public.retorno_config set segura_patio = false where id;
  perform pg_temp.f4c_limpa();
  -- Linha 4: teto do pátio (3 por número e dia), do eco e do painel (por parceiro e dia).
  for v_n in 1 .. 3 loop
    v_s := pg_temp.f4c_agenda('parceiro_patio', 'vazio', v_n1, '{}', c_t - interval '1 minute', '4f' || v_n);
    perform public.parceiro_pegar(c_t);
    if pg_temp.f4c_estado(v_s) is distinct from 'preparada/' then
      raise exception '4f: pátio % de 3 (%)', v_n, pg_temp.f4c_estado(v_s);
    end if;
  end loop;
  v_s := pg_temp.f4c_agenda('parceiro_patio', 'vazio', v_n1, '{}', c_t - interval '1 minute', '4f4');
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/teto_patio' then
    raise exception '4f: o 4º pátio do dia (%)', pg_temp.f4c_estado(v_s);
  end if;
  insert into public.retorno_saidas (emissor, tipo, origem, classe, chave, phone_normalized, modo, estado, enviar_em, decidida_em,
                                     enviada_em, texto, dados, dedupe_key)
  select 'parceiro', t.tipo, 'retorno_parceiro', t.classe, '00014501', '5547900014501', 'ligado', 'enviada',
         c_t - interval '2 hours', c_t - interval '2 hours', c_t - interval '2 hours', 'texto de teste do teto',
         jsonb_build_object('parceiro_id', v_p), 'parceiro:teste:teto:' || t.tipo || g
    from generate_series(1, 2) g,
         (values ('parceiro_eco', 'aviso'), ('parceiro_painel', 'resumo_parceiro')) t(tipo, classe);
  v_s := pg_temp.f4c_agenda('parceiro_eco', 'pronto', v_n1, pg_temp.f4c_dados(jsonb_build_array(pg_temp.f4c_linha(1, v_va, 'pronto'))),
                            c_t - interval '1 minute', '4g');
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/teto_eco' then
    raise exception '4g: teto do eco (%)', pg_temp.f4c_estado(v_s);
  end if;
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1, pg_temp.f4c_dados(jsonb_build_array(pg_temp.f4c_linha(1, v_va, 'em_servico'))),
                            c_t - interval '1 minute', '4h');
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/teto_painel' then
    raise exception '4h: teto do painel (%)', pg_temp.f4c_estado(v_s);
  end if;
  perform pg_temp.f4c_limpa();
  -- Linha 8a: segura tudo reagenda, com a marca.
  update public.retorno_config set segura_tudo_ate = c_t + interval '1 hour' where id;
  v_s := pg_temp.f4c_agenda('parceiro_pausa', 'retomar', v_n1, '{}', c_t - interval '1 minute', '4i');
  perform public.parceiro_pegar(c_t);
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.estado is distinct from 'agendada' or v_x.enviar_em is distinct from c_t + interval '1 hour'
     or coalesce((v_x.dados ->> 'segurada')::boolean, false) is not true then
    raise exception '4i: segura tudo não reagendou (%)', pg_temp.f4c_estado(v_s);
  end if;
  update public.retorno_config set segura_tudo_ate = null where id;
  -- Linha 9: o canal recusa (opt-out do número) com o motivo dele.
  insert into public.whatsapp_blocked_numbers (phone_normalized, reason, tipo, created_at)
    values ('5547900014501', 'Teste F4 canal', 'opt_out', c_t - interval '1 day');
  perform public.parceiro_pegar(c_t + interval '1 hour');
  -- o motivo é o do canal: canal_bloqueado (F0a) dá 'bloqueado' para todo número em whatsapp_blocked_numbers
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/bloqueado' then
    raise exception '4k: linha 9, canal (%)', pg_temp.f4c_estado(v_s);
  end if;
  delete from public.whatsapp_blocked_numbers where phone_normalized = '5547900014501' and reason = 'Teste F4 canal';
  perform pg_temp.f4c_limpa();

  -- 9a e 20. Aviso às 22:30: reagendado para as 08:00; nesse meio-tempo o veto o derruba (linha 1a).
  v_s := pg_temp.f4c_aviso(v_g, v_p, array[v_vg], '2027-01-12 22:30-03', '9a');
  perform public.parceiro_pegar('2027-01-12 22:30-03');
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.estado is distinct from 'agendada' or v_x.enviar_em is distinct from '2027-01-13 08:00-03'::timestamptz then
    raise exception '9a: o aviso das 22:30 (% %)', v_x.estado, v_x.enviar_em;
  end if;
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem) values (v_g, v_p, '2027-01-13 07:00-03', 'nao_mp');
  perform public.parceiro_pegar('2027-01-13 08:00-03');
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/veto' then
    raise exception '20a: o aviso reagendado não caiu com o veto (%)', pg_temp.f4c_estado(v_s);
  end if;
  -- 20 e 26. Os outros motivos de _parceiro_aviso_ainda_vale; numero_compartilhado gravado sem 23514.
  v_s := pg_temp.f4c_aviso(v_h, v_p, array[v_vh], c_t - interval '1 minute', '20b');
  if public._parceiro_aviso_ainda_vale(v_s, c_t) is not null then
    raise exception '20b: o aviso que vale (%)', public._parceiro_aviso_ainda_vale(v_s, c_t);
  end if;
  update public.os_interessados set situacao = 'pausado' where id = v_vh;
  if public._parceiro_aviso_ainda_vale(v_s, c_t) is distinct from 'parceiro_regra' then
    raise exception '20c: vínculo cortado';
  end if;
  update public.os_interessados set situacao = 'recusado' where id = v_vh;
  if public._parceiro_aviso_ainda_vale(v_s, c_t) is distinct from 'parceiro_regra' then
    raise exception '20d: vínculo recusado';
  end if;
  update public.os_interessados set situacao = 'confirmado' where id = v_vh;
  perform pg_temp.f4c_cliente('Hilda Outra Canal', '5547900014518');
  if public._parceiro_aviso_ainda_vale(v_s, c_t) is distinct from 'numero_compartilhado' then
    raise exception '20e: número compartilhado (%)', public._parceiro_aviso_ainda_vale(v_s, c_t);
  end if;
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/numero_compartilhado' then
    raise exception '26: linha 1a com numero_compartilhado (%)', pg_temp.f4c_estado(v_s);
  end if;
  perform pg_temp.f4c_limpa();

  -- 9b. Recibo de sáb 21:40 com carência de 30 min: reagendado para a manhã, sem recusada.
  v_caso := pg_temp.f4c_caso('5547900014502', '2027-01-16 21:40-03');
  v_s := pg_temp.f4c_agenda('parceiro_recibo', null, v_n2, '{}', '2027-01-16 22:10-03', '9b', v_caso);
  perform public.parceiro_pegar('2027-01-16 22:10-03');
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.estado is distinct from 'agendada' or v_x.enviar_em <= '2027-01-16 22:10-03'::timestamptz
     or (v_x.enviar_em at time zone 'America/Sao_Paulo')::date is distinct from '2027-01-17'::date then
    raise exception '9b: o recibo de sábado à noite (% %)', v_x.estado, v_x.enviar_em;
  end if;
  perform pg_temp.f4c_limpa();

  -- 12. O recibo sai sem o bloco (patio_nivel 'cartao', e com segura_patio); o pátio vazio sai; painel sem lista cai.
  v_caso := pg_temp.f4c_caso('5547900014501', c_t - interval '40 minutes');
  v_s := pg_temp.f4c_agenda('parceiro_recibo', null, v_n1, '{}', c_t - interval '10 minutes', '12a', v_caso);
  perform public.parceiro_pegar(c_t);
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.estado is distinct from 'preparada' or coalesce((v_x.dados ->> 'bloco_patio')::boolean, true) is not false
     or v_x.dados -> 'interessado_ids' is distinct from '[]'::jsonb or v_x.dados -> 'os_ids' is distinct from '[]'::jsonb
     or v_x.texto is distinct from 'Carla, aqui é a Claudia, assistente virtual da HBR. Já passei sua mensagem ao Gustavo, e ele retorna para vocês ' || public._retorno_quando_fala(v_x.dados ->> 'quando', v_x.dados ->> 'hora') || '.' then
    raise exception '12a: o recibo com patio_nivel cartao (% / %)', pg_temp.f4c_estado(v_s), v_x.texto;
  end if;
  perform pg_temp.f4c_limpa();
  update public.retorno_config set patio_nivel = 'direto', segura_patio = true where id;
  v_s := pg_temp.f4c_agenda('parceiro_recibo', null, v_n1, '{}', c_t - interval '10 minutes', '12b', v_caso);
  perform public.parceiro_pegar(c_t);
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.estado is distinct from 'preparada' or coalesce((v_x.dados ->> 'bloco_patio')::boolean, true) is not false
     or v_x.texto like '%Enquanto isso%' then
    raise exception '12b: o recibo com segura_patio (%)', pg_temp.f4c_estado(v_s);
  end if;
  update public.retorno_config set patio_nivel = 'cartao', segura_patio = false where id;
  perform pg_temp.f4c_limpa();
  v_s := pg_temp.f4c_agenda('parceiro_patio', 'vazio', v_n1, '{}', c_t - interval '1 minute', '12c');
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'preparada/'
     or (select s.texto from public.retorno_saidas s where s.id = v_s) is distinct from 'Pátio HBR: nenhum veículo dos clientes de vocês por aqui agora.' then
    raise exception '12c: o pátio vazio (%)', pg_temp.f4c_estado(v_s);
  end if;
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1, pg_temp.f4c_dados('[]'::jsonb), c_painel - interval '1 minute', '12d');
  perform public.parceiro_pegar(c_painel);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/parceiro_regra' then
    raise exception '12d: painel sem lista (%)', pg_temp.f4c_estado(v_s);
  end if;
  perform pg_temp.f4c_limpa();

  -- ── 5, 13 e 17. O painel na sexta 17:50: OS que caiu, anfitriã e linha que dá 22023 ──
  insert into public.parceiro_paineis (parceiro_id, dia, estado, mudou, linhas, impressao)
    values (v_p, '2027-01-15', 'aprovado', true,
            jsonb_build_array(pg_temp.f4c_linha(1, v_va, 'em_servico'), pg_temp.f4c_linha(2, v_vb, 'andamento', '2027-01-08')), 'teste')
    returning id into v_painel;
  v_linhas := jsonb_build_array(pg_temp.f4c_linha(1, v_va, 'em_servico'), pg_temp.f4c_linha(2, v_vb, 'andamento', '2027-01-08'));
  -- 5. Veto na 2ª: ela sai da linha e a 1ª segue.
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem) values (v_b, v_p, c_painel - interval '1 hour', 'nao_mp');
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1, pg_temp.f4c_dados(v_linhas, jsonb_build_object('painel_id', v_painel, 'dia', '2027-01-15')),
                            c_painel - interval '1 minute', '5a');
  v_r := public.parceiro_pegar(c_painel);
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.estado is distinct from 'preparada' or coalesce(v_x.texto, '') not like '%Ana C.%' or v_x.texto like '%Bruno%'
     or v_x.dados -> 'interessado_ids' is distinct from jsonb_build_array(v_va) or v_x.dados -> 'os_ids' is distinct from jsonb_build_array(v_os_a)
     or jsonb_array_length(v_r -> 'linhas') is distinct from 1 or v_r -> 'linhas' -> 0 ->> 'n' is distinct from '1' then
    raise exception '5a: veto na 2ª linha (% / %)', pg_temp.f4c_estado(v_s), v_x.texto;
  end if;
  if not exists (select 1 from jsonb_array_elements(v_x.dados -> 'visibilidade') v
                  where (v ->> 'interessado_id')::uuid = v_vb and v ->> 'motivo' = 'veto')
     or not exists (select 1 from jsonb_array_elements((select pp.linhas from public.parceiro_paineis pp where pp.id = v_painel)) l
                     where (l ->> 'interessado_id')::uuid = v_vb and l ->> 'fora_por' = 'regra') then
    raise exception '5b: a visibilidade ou a linha fora do painel não foram gravadas';
  end if;
  perform pg_temp.f4c_limpa();
  -- 5. Veto nas duas: cai com parceiro_regra.
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem) values (v_a, v_p, c_painel - interval '1 hour', 'nao_mp');
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1, pg_temp.f4c_dados(v_linhas), c_painel - interval '1 minute', '5c');
  perform public.parceiro_pegar(c_painel);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/parceiro_regra' then
    raise exception '5c: veto nas duas (%)', pg_temp.f4c_estado(v_s);
  end if;
  delete from public.parceiro_vetos where parceiro_id = v_p and client_id in (v_a, v_b);
  perform pg_temp.f4c_limpa();
  -- 13. A linha comercial e a de anfitriã da mesma OS: a saída confere pelo interessado_id; a anfitriã nunca é citada.
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1, pg_temp.f4c_dados(jsonb_build_array(pg_temp.f4c_linha(1, v_ve2, 'em_servico'))),
                            c_painel - interval '1 minute', '13a');
  perform public.parceiro_pegar(c_painel);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/parceiro_regra' then
    raise exception '13a: a anfitriã foi citada (%)', pg_temp.f4c_estado(v_s);
  end if;
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1, pg_temp.f4c_dados(jsonb_build_array(pg_temp.f4c_linha(1, v_ve, 'em_servico'))),
                            c_painel - interval '1 minute', '13b');
  perform public.parceiro_pegar(c_painel);
  if pg_temp.f4c_estado(v_s) is distinct from 'preparada/' then
    raise exception '13b: a linha comercial da mesma OS (%)', pg_temp.f4c_estado(v_s);
  end if;
  perform pg_temp.f4c_limpa();
  -- 17. Linha 7: a linha que dá 22023 (peça chegou sem data) sai com fora_por 'texto', e o resto segue; com todas, recusada/texto.
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1,
                            pg_temp.f4c_dados(jsonb_build_array(pg_temp.f4c_linha(1, v_va, 'em_servico'), pg_temp.f4c_linha(2, v_vb, 'peca_chegou'))),
                            c_painel - interval '1 minute', '17a');
  perform public.parceiro_pegar(c_painel);
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.estado is distinct from 'preparada' or v_x.texto like '%Bruno%'
     or v_x.dados -> 'interessado_ids' is distinct from jsonb_build_array(v_va)
     or not exists (select 1 from jsonb_array_elements(v_x.dados -> 'linhas_fora') f
                     where (f ->> 'interessado_id')::uuid = v_vb and f ->> 'fora_por' = 'texto') then
    raise exception '17a: a linha com 22023 (% / %)', pg_temp.f4c_estado(v_s), v_x.texto;
  end if;
  perform pg_temp.f4c_limpa();
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1,
                            pg_temp.f4c_dados(jsonb_build_array(pg_temp.f4c_linha(1, v_vb, 'peca_chegou'))), c_painel - interval '1 minute', '17b');
  perform public.parceiro_pegar(c_painel);
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/texto' then
    raise exception '17b: todas as linhas com 22023 (%)', pg_temp.f4c_estado(v_s);
  end if;
  perform pg_temp.f4c_limpa();
  -- 11. O painel que perde a janela do dia (18:35) cai, sem reagendar para amanhã.
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1, pg_temp.f4c_dados(jsonb_build_array(pg_temp.f4c_linha(1, v_va, 'em_servico'))),
                            '2027-01-15 18:30-03', '11');
  perform public.parceiro_pegar('2027-01-15 18:35-03');
  if pg_temp.f4c_estado(v_s) is distinct from 'recusada/fora_da_janela' then
    raise exception '11: painel fora da janela (%)', pg_temp.f4c_estado(v_s);
  end if;
  perform pg_temp.f4c_limpa();

  -- 19. parceiro_saida_sem_linhas: tira a linha, refaz o texto e as listas, marca o painel; tudo tirado: {caiu: true}.
  update public.parceiro_paineis set linhas = v_linhas where id = v_painel;
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1, pg_temp.f4c_dados(v_linhas, jsonb_build_object('painel_id', v_painel)),
                            c_painel - interval '1 minute', '19');
  perform public.parceiro_pegar(c_painel);
  if pg_temp.f4c_estado(v_s) is distinct from 'preparada/'
     or coalesce((select s.texto from public.retorno_saidas s where s.id = v_s), '') not like '%Bruno C.%' then
    raise exception '19a: o painel de duas linhas não foi reservado (%)', pg_temp.f4c_estado(v_s);
  end if;
  v_r := public.parceiro_saida_sem_linhas(v_s, array[2], '[{"n": 2, "regras": ["nome_de_outro"]}]'::jsonb, c_painel + interval '10 seconds');
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_r ? 'caiu' or v_r ->> 'texto' is distinct from v_x.texto or v_x.texto like '%Bruno%' or coalesce(v_x.texto, '') not like '%1. Motorhome de Ana C.%'
     or jsonb_array_length(v_r -> 'linhas') is distinct from 1 or v_r -> 'validador' ->> 'audiencia' is distinct from 'parceiro'
     or v_x.dados -> 'interessado_ids' is distinct from jsonb_build_array(v_va) or v_x.dados -> 'os_ids' is distinct from jsonb_build_array(v_os_a)
     or not exists (select 1 from jsonb_array_elements(v_x.dados -> 'linhas_fora') f
                     where (f ->> 'interessado_id')::uuid = v_vb and f ->> 'fora_por' = 'validador')
     or not exists (select 1 from jsonb_array_elements((select pp.linhas from public.parceiro_paineis pp where pp.id = v_painel)) l
                     where (l ->> 'interessado_id')::uuid = v_vb and l ->> 'fora_por' = 'validador') then
    raise exception '19b: tirar a linha 2 (%)', v_r;
  end if;
  v_r := public.parceiro_saida_sem_linhas(v_s, array[1], '[{"n": 1, "regras": ["dado_pessoal"]}]'::jsonb, c_painel + interval '20 seconds');
  if coalesce((v_r ->> 'caiu')::boolean, false) is not true then
    raise exception '19c: tudo tirado não caiu (%)', v_r;
  end if;
  perform pg_temp.f4c_limpa();

  -- ── 18 e 10. O corte: 20 OS saem em 14 linhas e "E mais 6 veículos.", e o painel ligado de mais de 600 caracteres
  --    vai a enviando, sem 23514 ──
  v_linhas := '[]'::jsonb;
  for v_n in 1 .. 20 loop
    v_cli := pg_temp.f4c_cliente(c_nomes[v_n] || ' Canal', '55479000146' || lpad(v_n::text, 2, '0'));
    v_linhas := v_linhas || jsonb_build_array(pg_temp.f4c_linha(v_n, pg_temp.f4c_liga(pg_temp.f4c_os(v_cli), v_p, 'indicou',
                                                                 c_t - interval '25 hours'), 'andamento', '2027-01-08'));
  end loop;
  update public.retorno_config set parceiro_modo = 'ligado', parceiro_tipos_ligados = array['parceiro_painel'] where id;
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1, pg_temp.f4c_dados(v_linhas, jsonb_build_object('dia', '2027-01-15')),
                            c_painel - interval '1 minute', '18');
  v_r := public.parceiro_pegar(c_painel);
  select * into v_x from public.retorno_saidas s where s.id = v_s;
  if v_x.estado is distinct from 'enviando' or v_x.modo is distinct from 'ligado' or char_length(v_x.texto) <= 600
     or char_length(v_x.texto) > 1500 or array_length(string_to_array(v_x.texto, E'\n'), 1) > 18
     or coalesce(v_x.texto, '') not like '%E mais 6 veículos.%' or coalesce(v_x.texto, '') not like 'Pátio HBR · sex (15/01)%'
     or coalesce(v_x.texto, '') not like '%Valores e dados ficam com cada cliente.'
     or jsonb_array_length(v_x.dados -> 'linhas') is distinct from 14 or jsonb_array_length(v_x.dados -> 'linhas_cortadas') is distinct from 6
     or jsonb_array_length(v_x.dados -> 'interessado_ids') is distinct from 14 or (v_x.dados ->> 'mais')::int is distinct from 6
     or jsonb_array_length(v_r -> 'linhas') is distinct from 14 then
    raise exception '18/10: o corte do painel (% / % caracteres)', pg_temp.f4c_estado(v_s), char_length(v_x.texto);
  end if;
  -- 6. parceiro_saida_autorizada (e retorno_saida_autorizada, que passa a ela): pode; telefone; reserva; 24 h; veto;
  --    anfitriã; exceção forçada.
  v_r := public.parceiro_saida_autorizada(v_s, '5547900014501', c_painel + interval '10 seconds');
  if v_r is distinct from '{"pode": true, "motivo": null}'::jsonb
     or public.retorno_saida_autorizada(v_s, '5547900014501', c_painel + interval '10 seconds') is distinct from v_r then
    raise exception '6a: a saída reservada não foi autorizada (%)', v_r;
  end if;
  if public.parceiro_saida_autorizada(v_s, '5547900014511', c_painel + interval '10 seconds') ->> 'motivo' is distinct from 'telefone'
     or public.parceiro_saida_autorizada(v_s, '5547900014501', c_painel + interval '3 minutes') ->> 'motivo' is distinct from 'reserva_vencida' then
    raise exception '6b: telefone ou reserva';
  end if;
  v_ids := array(select x::uuid from jsonb_array_elements_text(v_x.dados -> 'interessado_ids') x);
  update public.os_interessados set aviso_em = c_painel - interval '1 hour' where id = v_ids[3];
  if public.parceiro_saida_autorizada(v_s, '5547900014501', c_painel + interval '10 seconds') ->> 'motivo' is distinct from 'parceiro_regra' then
    raise exception '6c: 24 h não passadas';
  end if;
  update public.os_interessados set aviso_em = c_t - interval '25 hours' where id = v_ids[3];
  insert into public.parceiro_vetos (client_id, parceiro_id, em, origem)
    select oi.client_id, v_p, c_painel - interval '1 minute', 'nao_mp' from public.os_interessados oi where oi.id = v_ids[5];
  if public.parceiro_saida_autorizada(v_s, '5547900014501', c_painel + interval '10 seconds') ->> 'motivo' is distinct from 'parceiro_regra' then
    raise exception '6d: veto';
  end if;
  delete from public.parceiro_vetos where parceiro_id = v_p;
  update public.retorno_saidas
     set dados = dados || jsonb_build_object('interessado_ids', jsonb_build_array(v_ve2), 'os_ids', jsonb_build_array(v_os_e))
   where id = v_s;
  if public.parceiro_saida_autorizada(v_s, '5547900014501', c_painel + interval '10 seconds') ->> 'motivo' is distinct from 'parceiro_regra' then
    raise exception '6e/13c: a anfitriã passou na última trava';
  end if;
  update public.retorno_saidas set dados = dados || '{"interessado_ids": ["x"], "os_ids": ["x"]}'::jsonb where id = v_s;
  if public.parceiro_saida_autorizada(v_s, '5547900014501', c_painel + interval '10 seconds') is distinct from '{"pode": false, "motivo": "erro"}'::jsonb then
    raise exception '6f: exceção forçada';
  end if;
  perform pg_temp.f4c_limpa();

  -- 9c. Dois painéis no mesmo minuto (dois números): saem os dois, o 2º depois de proximo_envio_em.
  update public.parceiro_numeros set recebe_painel = true where id = v_n2;
  v_linhas := jsonb_build_array(pg_temp.f4c_linha(1, v_va, 'em_servico'));
  v_s := pg_temp.f4c_agenda('parceiro_painel', null, v_n1, pg_temp.f4c_dados(v_linhas), c_painel - interval '1 minute', '9c1');
  v_s2 := pg_temp.f4c_agenda('parceiro_painel', null, v_n2, pg_temp.f4c_dados(v_linhas), c_painel - interval '59 seconds', '9c2');
  perform public.parceiro_pegar(c_painel);
  if pg_temp.f4c_estado(v_s) is distinct from 'enviando/' then
    raise exception '9c: o 1º painel (%)', pg_temp.f4c_estado(v_s);
  end if;
  -- a 2ª chamada pega o 2º painel, que espera o espaçamento sorteado
  perform public.parceiro_pegar(c_painel);
  select * into v_x from public.retorno_saidas s where s.id = v_s2;
  if v_x.estado is distinct from 'agendada' or v_x.enviar_em is distinct from (select c.proximo_envio_em from public.retorno_config c where c.id)
     or v_x.enviar_em <= c_painel then
    raise exception '9c: o 2º painel não esperou o espaçamento (% %)', v_x.estado, v_x.enviar_em;
  end if;
  perform public.parceiro_pegar(v_x.enviar_em);
  if pg_temp.f4c_estado(v_s2) is distinct from 'enviando/' then
    raise exception '9c: o 2º painel não saiu (%)', pg_temp.f4c_estado(v_s2);
  end if;
  update public.parceiro_numeros set recebe_painel = false where id = v_n2;
  perform pg_temp.f4c_limpa();

  -- ── 7 e 27. _parceiro_aplicar_efeitos pelo retorno_registrar_decisao ──
  update public.retorno_config set parceiro_tipos_ligados = array['parceiro_aviso_cliente', 'parceiro_coleta'] where id;
  -- 7. Enviada grava o aviso (mensagem, aviso_em, aviso_saida_id).
  v_s := pg_temp.f4c_aviso(v_c, v_p, array[v_vc], c_t - interval '1 minute', '7a');
  v_r := public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'enviando/' or v_r -> 'validador' ->> 'audiencia' is distinct from 'cliente'
     or coalesce((select s.texto from public.retorno_saidas s where s.id = v_s), '') not like '%responda NÃO RCF.' then
    raise exception '7a: o aviso não foi reservado (% / %)', pg_temp.f4c_estado(v_s), v_r;
  end if;
  v_r := public.retorno_registrar_decisao(v_s, 'enviada', '{"provider_message_id": "TESTE-F4"}'::jsonb, c_t + interval '30 seconds');
  select * into v_oi from public.os_interessados oi where oi.id = v_vc;
  if (v_r ->> 'ok')::boolean is not true or v_oi.aviso_ao_cliente is distinct from 'mensagem'
     or v_oi.aviso_em is distinct from c_t + interval '30 seconds' or v_oi.aviso_saida_id is distinct from v_s then
    raise exception '7b: a enviada não gravou o aviso (%)', v_r;
  end if;
  -- 7. Incerta não conta como aviso.
  update public.retorno_config set proximo_envio_em = null where id;
  v_s := pg_temp.f4c_aviso(v_d, v_p, array[v_vd], c_t - interval '1 minute', '7c');
  perform public.parceiro_pegar(c_t);
  v_r := public.retorno_registrar_decisao(v_s, 'incerta', '{}'::jsonb, c_t + interval '30 seconds');
  select * into v_oi from public.os_interessados oi where oi.id = v_vd;
  if (v_r ->> 'ok')::boolean is not true or v_oi.aviso_ao_cliente is distinct from 'nao_avisado' or v_oi.aviso_em is not null
     or v_oi.aviso_saida_id is not null then
    raise exception '7c: a incerta gravou o aviso (%)', v_r;
  end if;
  -- 27. O vínculo registrado "pela revenda" ganha só aviso_saida_id, sem mudar o aviso_em.
  update public.retorno_config set proximo_envio_em = null where id;
  v_s := pg_temp.f4c_aviso(v_f, v_p, array[v_vf], c_t - interval '1 minute', '27a');
  perform public.parceiro_pegar(c_t);
  v_r := public.retorno_registrar_decisao(v_s, 'enviada', '{}'::jsonb, c_t + interval '30 seconds');
  select * into v_oi from public.os_interessados oi where oi.id = v_vf;
  if (v_r ->> 'ok')::boolean is not true or v_oi.aviso_ao_cliente is distinct from 'pela_revenda'
     or v_oi.aviso_em is distinct from c_t - interval '3 days' or v_oi.aviso_saida_id is distinct from v_s then
    raise exception '27a: o vínculo pela revenda (%)', v_r;
  end if;
  -- 27. A coleta decidida em sombra soma coleta_n no caso.
  update public.retorno_config set parceiro_tipos_ligados = '{}', proximo_envio_em = null where id;
  v_caso := pg_temp.f4c_caso('5547900014502', c_t - interval '40 minutes');
  v_s := pg_temp.f4c_agenda('parceiro_coleta', 'veiculo_nome', v_n2, '{}', c_t - interval '10 minutes', '27b', v_caso);
  perform public.parceiro_pegar(c_t);
  v_r := public.retorno_registrar_decisao(v_s, 'sombra', '{}'::jsonb, c_t + interval '10 seconds');
  if (v_r ->> 'ok')::boolean is not true or (select a.coleta_n from public.retorno_aberturas a where a.id = v_caso) is distinct from 1 then
    raise exception '27b: a coleta em sombra não somou coleta_n (%)', v_r;
  end if;
  perform pg_temp.f4c_limpa();

  -- ── 22. Os modos ──
  -- modo 'sombra' e parceiro_modo 'ligado': sai de verdade (enviando).
  update public.retorno_config set parceiro_modo = 'ligado', parceiro_tipos_ligados = array['parceiro_pausa'], proximo_envio_em = null where id;
  v_s := pg_temp.f4c_agenda('parceiro_pausa', 'pausar', v_n1, '{}', c_t - interval '1 minute', '22a');
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'enviando/' or (select s.modo from public.retorno_saidas s where s.id = v_s) is distinct from 'ligado' then
    raise exception '22a: parceiro ligado com o retorno em sombra (%)', pg_temp.f4c_estado(v_s);
  end if;
  -- modo 'desligado': nulo, e a saída continua agendada.
  update public.retorno_config set modo = 'desligado' where id;
  v_s := pg_temp.f4c_agenda('parceiro_pausa', 'retomar', v_n1, '{}', c_t - interval '1 minute', '22b');
  if public.parceiro_pegar(c_t) is not null or pg_temp.f4c_estado(v_s) is distinct from 'agendada/' then
    raise exception '22b: retorno desligado (%)', pg_temp.f4c_estado(v_s);
  end if;
  update public.retorno_config set modo = 'sombra', parceiro_modo = 'sombra', parceiro_tipos_ligados = '{}' where id;
  -- 8. A saída com chave real que cai em sombra troca a chave.
  update public.retorno_saidas set dedupe_key = 'parceiro:teste:22b-real' where id = v_s;
  perform public.parceiro_pegar(c_t);
  if (select s.dedupe_key from public.retorno_saidas s where s.id = v_s) is distinct from 'parceiro:teste:22b-real:sombra:' || v_s then
    raise exception '8: a chave real em sombra não foi trocada';
  end if;
  perform pg_temp.f4c_limpa();

  -- ── 15. Teto da linha 4, com as saídas gravadas direto ──
  v_caso := pg_temp.f4c_caso('5547900014501', c_t - interval '50 minutes');
  v_s := pg_temp.f4c_agenda('parceiro_coleta', 'veiculo_nome', v_n1, '{}', c_t - interval '20 minutes', 'col1', v_caso);
  perform public.parceiro_pegar(c_t - interval '20 minutes');
  v_s2 := pg_temp.f4c_agenda('parceiro_coleta', 'whatsapp', v_n1, '{}', c_t - interval '10 minutes', 'col2', v_caso);
  perform public.parceiro_pegar(c_t - interval '10 minutes');
  if pg_temp.f4c_estado(v_s) is distinct from 'preparada/' or pg_temp.f4c_estado(v_s2) is distinct from 'preparada/' then
    raise exception '15a: as duas coletas do mesmo caso (% %)', pg_temp.f4c_estado(v_s), pg_temp.f4c_estado(v_s2);
  end if;
  if (select s.texto from public.retorno_saidas s where s.id = v_s2) is distinct from
     'O cliente tem WhatsApp? Se autorizar, me passa o número que o Gustavo fala direto.' then
    raise exception '15b: P04 sem pedido saiu com nome';
  end if;
  -- 15d antes do 2º caso: a 3ª coleta é do 1º caso, que fecha quando o 2º abre
  v_s3 := pg_temp.f4c_agenda('parceiro_coleta', 'whatsapp', v_n1, '{}', c_t - interval '1 minute', 'col3', v_caso);
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s3) is distinct from 'recusada/teto_coleta' then
    raise exception '15d: 3ª coleta do caso (%)', pg_temp.f4c_estado(v_s3);
  end if;
  v_caso2 := pg_temp.f4c_caso('5547900014501', c_t - interval '5 minutes');
  v_s3 := pg_temp.f4c_agenda('parceiro_recibo', null, v_n1, '{}', c_t - interval '1 minute', 'rec2', v_caso2);
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s3) is distinct from 'recusada/teto_numero' then
    raise exception '15c: recibo de outro caso em 12 h (%)', pg_temp.f4c_estado(v_s3);
  end if;
  perform pg_temp.f4c_limpa();

  -- ── 25. Linha 1b: a resposta humana do dono à chave depois da abertura cancela; sem ela, sai ──
  v_caso := pg_temp.f4c_caso('5547900014502', c_t - interval '40 minutes');
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at, raw_payload)
    values ('outbound', '5547900014502', 'text', 'ok', 'teste-f4-canal-25-ok', c_t - interval '20 minutes', '{"data": {}}'::jsonb);
  v_s := pg_temp.f4c_agenda('parceiro_recibo', null, v_n2, '{}', c_t - interval '10 minutes', '25a', v_caso);
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'cancelada/respondida_pelo_dono'
     or (select a.respondida_em from public.retorno_aberturas a where a.id = v_caso) is null then
    raise exception '25a: a resposta do dono não cancelou o P02 (%)', pg_temp.f4c_estado(v_s);
  end if;
  v_caso2 := pg_temp.f4c_caso('5547900014502', c_t - interval '15 minutes');
  v_s := pg_temp.f4c_agenda('parceiro_recibo', null, v_n2, '{}', c_t - interval '5 minutes', '25b', v_caso2);
  perform public.parceiro_pegar(c_t);
  if pg_temp.f4c_estado(v_s) is distinct from 'preparada/'
     or coalesce((select s.texto from public.retorno_saidas s where s.id = v_s), '') not like 'Aqui é a Claudia, assistente virtual da HBR. Já passei%' then
    raise exception '25b: sem resposta do dono, o P02 não saiu (%)', pg_temp.f4c_estado(v_s);
  end if;
  perform pg_temp.f4c_limpa();

  -- ── 14 e 24. A triagem das regras 6 e 8, pelo caminho real (retorno_abrir) ──
  -- Os casos de teste dos dois números fecham antes, para cada frase abrir caso novo.
  update public.retorno_aberturas set estado = 'fechada', fechada_em = '2027-01-13 09:00-03', fechada_motivo = 'dono'
   where chave in ('00014501', '00014502') and estado <> 'fechada';
  select md5(string_agg(so.id::text || so.status || coalesce(so.origem_parceiro_id::text, ''), ',' order by so.id)) into v_antes
    from public.service_orders so where so.client_id in (v_a, v_b);
  v_antes := v_antes || (select md5(string_agg(oi.id::text || oi.situacao || coalesce(oi.papel, ''), ',' order by oi.id))
                           from public.os_interessados oi where oi.parceiro_id = v_p);
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
    values ('inbound', '5547900014501', 'text', 'pode fazer a troca da bateria', 'teste-f4-canal-14a', '2027-01-13 10:00-03')
    returning id into v_m;
  v_r := public.retorno_abrir(v_m, false, '2027-01-13 10:00:05-03');
  v_caso := (v_r ->> 'abertura_id')::uuid;
  if (v_r ->> 'ok')::boolean is not true or v_r ->> 'papel' is distinct from 'parceiro'
     or not exists (select 1 from public.retorno_saidas s where s.abertura_id = v_caso and s.tipo = 'parceiro_recado')
     or exists (select 1 from public.retorno_saidas s where s.abertura_id = v_caso and s.tipo = 'parceiro_recibo') then
    raise exception '14a: "pode fazer" não agendou o recado (%)', v_r;
  end if;
  if (select md5(string_agg(so.id::text || so.status || coalesce(so.origem_parceiro_id::text, ''), ',' order by so.id))
        from public.service_orders so where so.client_id in (v_a, v_b))
     || (select md5(string_agg(oi.id::text || oi.situacao || coalesce(oi.papel, ''), ',' order by oi.id))
           from public.os_interessados oi where oi.parceiro_id = v_p) is distinct from v_antes then
    raise exception '14b: "pode fazer" mexeu em OS ou vínculo';
  end if;
  -- 8 e 24: duas perguntas, 2 h entre elas, sem saída humana: recibo, pergunta na fila e insistências 1.
  -- o caso do bloco 25, no mesmo número, fecha antes: senão a 1ª pergunta entra nele
  update public.retorno_aberturas a
     set estado = 'fechada', fechada_em = greatest(a.aberta_em, '2027-01-13 10:00-03'::timestamptz), fechada_motivo = 'expirou'
   where a.chave = '00014502' and a.estado in ('aberta', 'vencida');
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
    values ('inbound', '5547900014502', 'text', 'como tá a bateria do joão?', 'teste-f4-canal-14c', '2027-01-13 11:00-03')
    returning id into v_m;
  v_r := public.retorno_abrir(v_m, false, '2027-01-13 11:00:05-03');
  v_caso2 := (v_r ->> 'abertura_id')::uuid;
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
    values ('inbound', '5547900014502', 'text', 'e então, alguma novidade da bateria?', 'teste-f4-canal-14d', '2027-01-13 13:00-03')
    returning id into v_m;
  v_r := public.retorno_abrir(v_m, false, '2027-01-13 13:00:05-03');
  select * into v_ab from public.retorno_aberturas a where a.id = v_caso2;
  if (v_r ->> 'abertura_id')::uuid is distinct from v_caso2 or v_ab.nivel is distinct from 'recibo' or v_ab.motivo is not null
     or v_ab.tipo_recibo is distinct from 'recibo_parceiro' or v_ab.intencao is distinct from 'outro' or v_ab.insistencias is distinct from 1 then
    raise exception '24a: o caso do parceiro gravou errado (% % % % %)', v_ab.nivel, v_ab.motivo, v_ab.tipo_recibo, v_ab.intencao, v_ab.insistencias;
  end if;
  if not exists (select 1 from public.retorno_saidas s where s.abertura_id = v_caso2 and s.tipo = 'parceiro_recibo')
     or not exists (select 1 from public.parceiro_fila f where f.chave = 'pergunta:' || v_caso2 and f.tipo = 'pergunta') then
    raise exception '14c: a pergunta não agendou o P02 nem entrou na fila';
  end if;
  -- 24: sem mensagem por 4 h e sem resposta do dono, o vigia não fecha o caso do parceiro.
  update public.retorno_saidas set estado = 'cancelada', motivo = 'substituida', decidida_em = '2027-01-13 13:01-03'
   where abertura_id in (v_caso, v_caso2) and estado = 'agendada';
  perform public.retorno_vigia('2027-01-13 18:00-03');
  if (select a.estado from public.retorno_aberturas a where a.id = v_caso2) is distinct from 'aberta' then
    raise exception '24b: o vigia fechou o caso do parceiro';
  end if;

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
  if to_regprocedure('public.parceiro_pegar(timestamptz)') is null
     or to_regprocedure('public.parceiro_saida_autorizada(uuid, text, timestamptz)') is null or v_n_fun < 20 then
    raise exception 'grants: a varredura não achou as funções da P5 (%)', v_n_fun;
  end if;

  raise exception 'retorno_f4_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate is distinct from 'P0001' or sqlerrm is distinct from 'retorno_f4_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f4_canal', true, '{}');
end
$canal$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
