-- Retorno F2 (P14): o acorde real. Relógios fixos em janeiro e fevereiro de 2027. Roda só pela bancada.
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000095xx; frases inventadas.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f2a_caso(p_fone text, p_nome text, p_aberta timestamptz, p_sinais jsonb default '{}'::jsonb)
returns uuid
language plpgsql as $f$
declare
  v_cl uuid;
  v_msg uuid;
  v_id uuid;
begin
  insert into public.clients (type, name, whatsapp) values ('individual', p_nome, p_fone) returning id into v_cl;
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', p_fone, 'text', 'frase inventada do teste', 'received', '{"data": {}}'::jsonb, p_aberta, p_aberta)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo, sinais)
  values (public._agenda_chave_telefone(p_fone), p_fone, '47', 'cliente', '{"papel": "cliente"}', v_cl, v_msg, v_msg,
          p_aberta, p_aberta, p_aberta, p_aberta, 'recibo', 'recibo_cliente', 'aberta', 'ligado', p_sinais)
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta, sinais)
  values (v_msg, v_id, public._agenda_chave_telefone(p_fone), p_aberta, p_aberta, 'x', true, p_sinais);
  return v_id;
end $f$;

create or replace function pg_temp.f2a_acorde(p_caso uuid, p_variante text, p_enviar timestamptz, p_por text default null)
returns uuid
language sql as $f$
  insert into public.retorno_saidas (abertura_id, tipo, variante, chave, phone_normalized, client_id, modo, estado, enviar_em, dados, dedupe_key)
  select a.id, 'acorde', p_variante, a.chave, a.phone_normalized, a.client_id, 'ligado', 'agendada', p_enviar,
         jsonb_build_object('por', p_por), 'teste:' || a.id || ':' || p_variante || ':' || gen_random_uuid()
    from public.retorno_aberturas a where a.id = p_caso
  returning id
$f$;

-- O recibo do caso, já ouvido: o aviso seguinte precisa dele para sair ligado.
create or replace function pg_temp.f2a_recibo_enviado(p_caso uuid, p_em timestamptz)
returns uuid
language sql as $f$
  insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, decidida_em, enviada_em, texto, dedupe_key)
  select a.id, 'recibo_cliente', 'retorno_recibo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', 'enviada',
         p_em, p_em, p_em, 'texto do recibo', 'retorno:' || a.id || ':recibo'
    from public.retorno_aberturas a where a.id = p_caso
  returning id
$f$;

create or replace function pg_temp.f2a_recibo(p_caso uuid, p_enviar timestamptz)
returns uuid
language sql as $f$
  insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo, enviar_em, dedupe_key)
  select a.id, 'recibo_cliente', 'retorno_recibo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', p_enviar,
         'retorno:' || a.id || ':recibo'
    from public.retorno_aberturas a where a.id = p_caso
  returning id
$f$;

create or replace function pg_temp.f2a_urgente(p_caso uuid, p_enviar timestamptz)
returns uuid
language sql as $f$
  insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, dedupe_key)
  select a.id, 'urgente', 'sem_acorde', 'retorno_recibo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', 'agendada',
         p_enviar, 'retorno:' || a.id || ':urgente'
    from public.retorno_aberturas a where a.id = p_caso
  returning id
$f$;

-- Libera o espaçamento e fecha o que ficou no meio, para o próximo pegar pegar só a do teste.
create or replace function pg_temp.f2a_livre()
returns void
language sql as $f$
  update public.retorno_config set proximo_envio_em = null;
  update public.retorno_saidas set estado = 'cancelada', motivo = 'substituida', decidida_em = '2027-01-01 12:00-03' where estado in ('preparada', 'enviando');
$f$;

create or replace function pg_temp.f2a_sem_cartao(p_agora timestamptz)
returns void
language plpgsql as $f$
declare r record;
begin
  for r in select c.id from public.retorno_cartoes c where c.estado = 'vivo' loop
    perform public._retorno_cartao_encerrar(r.id, 'caiu', 'rejected', 'teste', p_agora);
  end loop;
end $f$;

do $acorde$
declare
  c_grupo constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'adiamento', 'fim_do_dia'];
  c_ligado constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'adiamento', 'fim_do_dia', 'urgente', 'acorde'];
  c_d1 constant timestamptz := '2027-01-19 00:00:00-03';   -- terça
  c_d2 constant timestamptz := '2027-01-20 00:00:00-03';
  c_d3 constant timestamptz := '2027-01-21 00:00:00-03';
  c_d4 constant timestamptz := '2027-01-22 00:00:00-03';
  c_d5 constant timestamptz := '2027-01-26 00:00:00-03';
  c_d6 constant timestamptz := '2027-01-27 00:00:00-03';
  c_d7 constant timestamptz := '2027-01-28 00:00:00-03';
  c_d8 constant timestamptz := '2027-01-29 00:00:00-03';
  c_d9 constant timestamptz := '2027-02-02 00:00:00-03';
  c_d10 constant timestamptz := '2027-02-03 00:00:00-03';
  c_d11 constant timestamptz := '2027-02-04 00:00:00-03';
  v_phone text;
  v_modo text;
  v_caso uuid; v_caso2 uuid; v_caso3 uuid;
  v_s uuid; v_s2 uuid; v_s3 uuid;
  v_sa public.retorno_saidas;
  v_av uuid;
  v_r jsonb;
  v_t text;
  v_n integer;
  v_cfg public.retorno_config;
  v_falhou boolean;
begin
  begin
    select d.phone into v_phone from public._comprovante_dono() d;
    v_modo := public._retorno_modo_da_voz();
    update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
    update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
    update public.ai_operator_sessions set metadata = metadata - 'pendencias_guardadas' where external_thread_key = v_phone;
    update public.retorno_saidas set estado = 'cancelada', motivo = 'substituida', decidida_em = '2027-01-01 12:00-03' where estado = 'agendada';
    update public.retorno_config
       set modo = 'ligado', tipos_ligados = c_ligado, cartao_ligado = true, variantes_ligadas = false, segura_tudo_ate = null, segura_recibos = false,
           proximo_envio_em = null, respostas_dia_max = 200, meio_dia_ligado = false, fora_ate = null, so_reativo = false,
           so_reativo_motivo = null, so_reativo_desde = null, erros_seguidos = 0, promessa_faixa = '{}';

    -- 1. Às 10:00, com cartão livre: enviada, aguarda o cartão, o cartão abre, e o minuto seguinte não repete.
    v_caso := pg_temp.f2a_caso('5547900009501', 'Alice Acorde Teste', c_d1 + interval '8 hours');
    v_s := pg_temp.f2a_acorde(v_caso, 'passagem', c_d1 + interval '10 hours', 'risco');
    v_r := public.retorno_vigia_cartao(c_d1 + interval '10 hours');
    select * into v_sa from public.retorno_saidas s where s.id = v_s;
    if v_sa.estado <> 'enviada' or not coalesce((v_sa.dados ->> 'aguarda_cartao')::boolean, false) or v_sa.dados ->> 'aviso_id' is null then
      raise exception '1a: (%) / %', v_r, to_jsonb(v_sa);
    end if;
    v_av := (v_sa.dados ->> 'aviso_id')::uuid;
    select a.texto into v_t from public.avisos_do_dono a where a.id = v_av;
    if v_t not like '%: risco. *retorno* abre o cartão.' or v_t like '%frase inventada%' then
      raise exception '1b: A01 (%)', v_t;
    end if;
    v_r := public._retorno_cartao_devido(c_d1 + interval '10 hours 1 minute');
    if v_r ->> 'gatilho' is distinct from 'acorde' or v_r ->> 'aviso_id' is distinct from v_av::text then
      raise exception '1c: devido (%)', v_r;
    end if;
    v_r := public.retorno_cartao_abrir('acorde', c_d1 + interval '10 hours 1 minute', v_av);
    if v_r ->> 'acao' is distinct from 'cartao' then
      raise exception '1d: abrir (%)', v_r;
    end if;
    if (select s.dados ? 'aguarda_cartao' from public.retorno_saidas s where s.id = v_s) then
      raise exception '1e: aguarda_cartao ficou';
    end if;
    if public._retorno_cartao_devido(c_d1 + interval '10 hours 2 minutes') is not null then
      raise exception '1f: o minuto seguinte repetiu';
    end if;
    perform pg_temp.f2a_sem_cartao(c_d1 + interval '10 hours 3 minutes');

    -- 1g. Às 08:30: sem cartão, o A01 vai pela fila.
    v_caso := pg_temp.f2a_caso('5547900009502', 'Bruna Acorde Teste', c_d2 + interval '7 hours');
    v_s := pg_temp.f2a_acorde(v_caso, 'passagem', c_d2 + interval '8 hours 30 minutes', 'reclamacao');
    perform public.retorno_vigia_cartao(c_d2 + interval '8 hours 30 minutes');
    select * into v_sa from public.retorno_saidas s where s.id = v_s;
    v_av := (v_sa.dados ->> 'aviso_id')::uuid;
    if v_sa.estado <> 'enviada' or v_sa.dados ? 'aguarda_cartao' or v_av is null then
      raise exception '1g: %', to_jsonb(v_sa);
    end if;
    if not exists (select 1 from public.whatsapp_send_queue q
                    where q.dedupe_key = 'aviso:' || v_av and q.source = 'me_acorde' and q.priority = 1 and q.phone_normalized = v_phone) then
      raise exception '1h: o A01 não entrou na fila';
    end if;

    -- 1i. Às 10:00, com cartão vivo: A01 na fila, e o minuto seguinte não repete.
    v_r := public.retorno_cartao_abrir('puxar', c_d2 + interval '9 hours 50 minutes');
    if v_r ->> 'acao' is distinct from 'cartao' then
      raise exception '1i: puxar (%)', v_r;
    end if;
    v_caso2 := pg_temp.f2a_caso('5547900009503', 'Carla Acorde Teste', c_d2 + interval '9 hours');
    v_s2 := pg_temp.f2a_acorde(v_caso2, 'passagem', c_d2 + interval '10 hours', 'quer_dono');
    perform public.retorno_vigia_cartao(c_d2 + interval '10 hours');
    select * into v_sa from public.retorno_saidas s where s.id = v_s2;
    v_av := (v_sa.dados ->> 'aviso_id')::uuid;
    v_r := public.retorno_cartao_abrir('acorde', c_d2 + interval '10 hours 1 minute', v_av);
    if v_r ->> 'acao' is distinct from 'ja_vivo'
       or not exists (select 1 from public.whatsapp_send_queue q where q.dedupe_key = 'aviso:' || v_av)
       or public._retorno_cartao_devido(c_d2 + interval '10 hours 2 minutes') is not null then
      raise exception '1j: (%)', v_r;
    end if;
    perform pg_temp.f2a_sem_cartao(c_d2 + interval '10 hours 3 minutes');

    -- 2. Um por minuto; o 3º do dia fica guardado.
    v_caso := pg_temp.f2a_caso('5547900009504', 'Dora Acorde Teste', c_d3 + interval '8 hours');
    v_caso2 := pg_temp.f2a_caso('5547900009505', 'Elza Acorde Teste', c_d3 + interval '8 hours');
    v_caso3 := pg_temp.f2a_caso('5547900009506', 'Fabi Acorde Teste', c_d3 + interval '8 hours');
    v_s := pg_temp.f2a_acorde(v_caso, 'passagem', c_d3 + interval '10 hours', 'risco');
    v_s2 := pg_temp.f2a_acorde(v_caso2, 'relogio', c_d3 + interval '10 hours');
    v_s3 := pg_temp.f2a_acorde(v_caso3, 'relogio', c_d3 + interval '10 hours');
    perform public.retorno_vigia_cartao(c_d3 + interval '10 hours');
    select count(*) into v_n from public.retorno_saidas s where s.id in (v_s, v_s2, v_s3) and s.estado = 'agendada';
    if v_n <> 2 or (select s.estado from public.retorno_saidas s where s.id = v_s) <> 'enviada' then
      raise exception '2a: um por minuto, com a passagem antes do relógio (agendadas: %)', v_n;
    end if;
    perform public.retorno_vigia_cartao(c_d3 + interval '10 hours 1 minute');
    perform public.retorno_vigia_cartao(c_d3 + interval '10 hours 2 minutes');
    -- o relógio empata pelo id: um dos dois é o 3º do dia
    select * into v_sa from public.retorno_saidas s where s.id in (v_s2, v_s3) and s.estado = 'cancelada';
    if not found or v_sa.motivo <> 'guardado_no_portao'
       or (select count(*) from public.retorno_saidas s where s.id in (v_s, v_s2, v_s3) and s.estado = 'enviada') <> 2 then
      raise exception '2b: %', to_jsonb(v_sa);
    end if;
    if (select a.situacao from public.avisos_do_dono a where a.id = (v_sa.dados ->> 'aviso_id')::uuid) <> 'guardado' then
      raise exception '2c: o aviso não ficou guardado';
    end if;
    update public.retorno_saidas s set dados = s.dados - 'aguarda_cartao' where s.tipo = 'acorde' and s.dados ? 'aguarda_cartao';

    -- 3. O mesmo assunto do "me acorde se" já acordou hoje: guardado, sem acorde em dobro.
    v_caso := pg_temp.f2a_caso('5547900009507', 'Gina Acorde Teste', c_d4 + interval '8 hours');
    v_r := public.aviso_registrar(jsonb_build_object('phone', v_phone, 'modo', v_modo, 'fonte', 'me_acorde', 'chave', 'teste-assunto-9507',
      'assunto', 'contato:5547900009507', 'destino', 'acorde', 'texto', 'Teste', 'agora', c_d4 + interval '9 hours 40 minutes'));
    if v_r ->> 'decisao' is distinct from 'acordar' then
      raise exception '3a: (%)', v_r;
    end if;
    v_s := pg_temp.f2a_acorde(v_caso, 'passagem', c_d4 + interval '10 hours', 'reclamacao');
    perform public.retorno_vigia_cartao(c_d4 + interval '10 hours');
    select * into v_sa from public.retorno_saidas s where s.id = v_s;
    if v_sa.estado <> 'cancelada' or v_sa.motivo <> 'guardado_no_portao' then
      raise exception '3b: %', to_jsonb(v_sa);
    end if;

    -- 4. A agenda já acordou: a saída nasceu cancelada e o vigia não toca nela.
    v_caso := pg_temp.f2a_caso('5547900009508', 'Hilda Acorde Teste', c_d4 + interval '8 hours');
    v_s := pg_temp.f2a_acorde(v_caso, 'passagem', c_d4 + interval '10 hours 5 minutes', 'risco');
    update public.retorno_saidas s set estado = 'cancelada', motivo = 'agenda_ja_acordou', decidida_em = c_d4 + interval '10 hours 5 minutes' where s.id = v_s;
    perform public.retorno_vigia_cartao(c_d4 + interval '10 hours 6 minutes');
    if (select s.motivo from public.retorno_saidas s where s.id = v_s) <> 'agenda_ja_acordou' then
      raise exception '4: o vigia mexeu na saída cancelada';
    end if;

    -- 5. URGENTE com vaga: T24. Sem vaga: T25. Às 20:15: T25.
    v_caso := pg_temp.f2a_caso('5547900009509', 'Iara Acorde Teste', c_d5 + interval '7 hours');
    perform pg_temp.f2a_recibo_enviado(v_caso, c_d5 + interval '8 hours');
    v_s := pg_temp.f2a_urgente(v_caso, c_d5 + interval '10 hours');
    perform pg_temp.f2a_livre();
    v_r := public.retorno_pegar(c_d5 + interval '10 hours');
    if v_r ->> 'variante' is distinct from 'acorde' or v_r ->> 'modo' is distinct from 'ligado'
       or v_r ->> 'texto' is distinct from 'Avisei o Gustavo agora mesmo, Iara.' then
      raise exception '5a: (%)', v_r;
    end if;
    if not exists (select 1 from public.retorno_saidas s
                    where s.abertura_id = v_caso and s.tipo = 'acorde' and s.variante = 'urgente' and s.estado = 'enviada') then
      raise exception '5b: o acorde do urgente não ficou registrado';
    end if;
    update public.retorno_saidas s set dados = s.dados - 'aguarda_cartao' where s.tipo = 'acorde' and s.dados ? 'aguarda_cartao';
    perform public.aviso_registrar(jsonb_build_object('phone', v_phone, 'modo', v_modo, 'fonte', 'me_acorde', 'chave', 'teste-vaga-9510',
      'assunto', 'contato:outro', 'destino', 'acorde', 'texto', 'Teste', 'agora', c_d5 + interval '10 hours 10 minutes'));
    v_caso := pg_temp.f2a_caso('5547900009510', 'Julia Acorde Teste', c_d5 + interval '7 hours');
    perform pg_temp.f2a_recibo_enviado(v_caso, c_d5 + interval '8 hours');
    v_s := pg_temp.f2a_urgente(v_caso, c_d5 + interval '10 hours 20 minutes');
    perform pg_temp.f2a_livre();
    v_r := public.retorno_pegar(c_d5 + interval '10 hours 20 minutes');
    if v_r ->> 'variante' is distinct from 'sem_acorde' or v_r ->> 'texto' not like 'Anotei como urgente, Julia.%' then
      raise exception '5c: (%)', v_r;
    end if;
    v_caso := pg_temp.f2a_caso('5547900009511', 'Karen Acorde Teste', c_d6 + interval '19 hours');
    perform pg_temp.f2a_recibo_enviado(v_caso, c_d6 + interval '20 hours');
    v_s := pg_temp.f2a_urgente(v_caso, c_d6 + interval '20 hours 15 minutes');
    perform pg_temp.f2a_livre();
    v_r := public.retorno_pegar(c_d6 + interval '20 hours 15 minutes');
    if v_r ->> 'variante' is distinct from 'sem_acorde' then
      raise exception '5d: às 20:15 (%)', v_r;
    end if;

    -- 6. Pressa às 10:00: com vaga, promete o fechamento pelo acorde; sem vaga, a faixa normal.
    v_caso := pg_temp.f2a_caso('5547900009512', 'Lara Acorde Teste', c_d7 + interval '9 hours 50 minutes', '{"pressa": true}'::jsonb);
    v_s := pg_temp.f2a_recibo(v_caso, c_d7 + interval '10 hours');
    perform pg_temp.f2a_livre();
    v_r := public.retorno_pegar(c_d7 + interval '10 hours');
    select * into v_sa from public.retorno_saidas s where s.id = v_s;
    if v_sa.dados -> 'prazo' ->> 'fonte' is distinct from 'acorde' or v_sa.dados -> 'prazo' ->> 'hora' is distinct from '19h' then
      raise exception '6a: sinais % / acordes % / avisos %', (select a.sinais from public.retorno_aberturas a where a.id = v_caso),
        (select jsonb_agg(jsonb_build_object('estado', x.estado, 'motivo', x.motivo, 'dados', x.dados)) from public.retorno_saidas x where x.abertura_id = v_caso and x.tipo = 'acorde'),
        (select jsonb_agg(jsonb_build_object('dia', y.dia, 'situacao', y.situacao, 'motivo', y.motivo, 'assunto', y.assunto)) from public.avisos_do_dono y where y.dia = '2027-01-28');
    end if;
    update public.retorno_saidas s set dados = s.dados - 'aguarda_cartao' where s.tipo = 'acorde' and s.dados ? 'aguarda_cartao';
    perform public.aviso_registrar(jsonb_build_object('phone', v_phone, 'modo', v_modo, 'fonte', 'me_acorde', 'chave', 'teste-vaga-9513',
      'assunto', 'contato:outro', 'destino', 'acorde', 'texto', 'Teste', 'agora', c_d7 + interval '10 hours 1 minute'));
    v_caso := pg_temp.f2a_caso('5547900009513', 'Mara Acorde Teste', c_d7 + interval '9 hours 50 minutes', '{"pressa": true}'::jsonb);
    v_s := pg_temp.f2a_recibo(v_caso, c_d7 + interval '10 hours 5 minutes');
    perform pg_temp.f2a_livre();
    v_r := public.retorno_pegar(c_d7 + interval '10 hours 5 minutes');
    select * into v_sa from public.retorno_saidas s where s.id = v_s;
    if v_sa.dados -> 'prazo' ->> 'fonte' is not distinct from 'acorde' then
      raise exception '6b: sem vaga prometeu pelo acorde (%)', to_jsonb(v_sa);
    end if;

    -- 7. 08:00: quem ficou para hoje é o 1º acorde.
    v_caso := pg_temp.f2a_caso('5547900009514', 'Nina Acorde Teste', c_d8 - interval '1 day');
    update public.retorno_aberturas a set topo_dia = (c_d8 at time zone 'America/Sao_Paulo')::date where a.id = v_caso;
    v_caso2 := pg_temp.f2a_caso('5547900009515', 'Olga Acorde Teste', c_d8 + interval '7 hours');
    v_s2 := pg_temp.f2a_acorde(v_caso2, 'passagem', c_d8 + interval '7 hours 59 minutes', 'risco');
    perform public.retorno_vigia_cartao(c_d8 + interval '8 hours');
    select * into v_sa from public.retorno_saidas s where s.abertura_id = v_caso and s.tipo = 'acorde' and s.variante = 'venceu';
    if v_sa.estado is distinct from 'enviada' then
      raise exception '7a: %', to_jsonb(v_sa);
    end if;
    if (select s.estado from public.retorno_saidas s where s.id = v_s2) <> 'agendada' then
      raise exception '7b: a passagem foi antes do venceu';
    end if;
    update public.retorno_saidas s set estado = 'cancelada', motivo = 'substituida', decidida_em = c_d8 + interval '8 hours' where s.estado = 'agendada';

    -- 8. Com o acorde fora dos ligados, tudo igual à F1. Com ele ligado, o passo 7 do vigia não toca.
    update public.retorno_config set tipos_ligados = c_grupo;
    v_caso := pg_temp.f2a_caso('5547900009516', 'Paula Acorde Teste', c_d9 + interval '8 hours');
    v_s := pg_temp.f2a_acorde(v_caso, 'passagem', c_d9 + interval '10 hours', 'risco');
    perform public.retorno_vigia_cartao(c_d9 + interval '10 hours');
    if (select s.estado from public.retorno_saidas s where s.id = v_s) <> 'agendada' then
      raise exception '8a: o acorde real rodou com a chave desligada';
    end if;
    perform public.retorno_vigia(c_d9 + interval '10 hours');
    select * into v_sa from public.retorno_saidas s where s.id = v_s;
    if v_sa.estado <> 'sombra' or not v_sa.dados ? 'acordaria' then
      raise exception '8b: %', to_jsonb(v_sa);
    end if;
    update public.retorno_config set tipos_ligados = c_ligado, so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null;
    v_s2 := pg_temp.f2a_acorde(v_caso, 'relogio', c_d9 + interval '10 hours 5 minutes');
    perform public.retorno_vigia(c_d9 + interval '10 hours 5 minutes');
    if (select s.estado from public.retorno_saidas s where s.id = v_s2) <> 'agendada' then
      raise exception '8c: o passo 7 tocou o acorde real';
    end if;
    update public.retorno_saidas s set estado = 'cancelada', motivo = 'substituida', decidida_em = c_d9 + interval '11 hours' where s.id = v_s2;
    update public.retorno_config set so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null;

    -- 9. Ligar: o update único passa; só um dos dois, não.
    update public.retorno_config set tipos_ligados = c_grupo, meio_dia_ligado = false;
    v_falhou := false;
    begin
      update public.retorno_config set tipos_ligados = c_grupo || array['urgente']::text[];
    exception when check_violation then
      v_falhou := true;
    end;
    if not v_falhou then
      raise exception '9a: urgente sem acorde passou';
    end if;
    v_falhou := false;
    begin
      update public.retorno_config set meio_dia_ligado = true;
    exception when check_violation then
      v_falhou := true;
    end;
    if not v_falhou then
      raise exception '9b: meio-dia sem urgente passou';
    end if;
    update public.retorno_config set tipos_ligados = tipos_ligados || array['urgente', 'acorde']::text[], meio_dia_ligado = true where id;

    -- 10. 09:12 com o grupo novo e o meio-dia: ligado, promete 14h, X2 19h, e o adiamento das 13:30 sai ligado.
    v_caso := pg_temp.f2a_caso('5547900009517', 'Rita Acorde Teste', c_d10 + interval '9 hours 5 minutes');
    v_s := pg_temp.f2a_recibo(v_caso, c_d10 + interval '9 hours 12 minutes');
    perform pg_temp.f2a_livre();
    v_r := public.retorno_pegar(c_d10 + interval '9 hours 12 minutes');
    select * into v_sa from public.retorno_saidas s where s.id = v_s;
    if v_r ->> 'modo' is distinct from 'ligado' or v_sa.dados -> 'prazo' ->> 'hora' is distinct from '14h'
       or (v_sa.dados -> 'prazo' ->> 'x2')::timestamptz is distinct from c_d10 + interval '19 hours' then
      raise exception '10a: (%) / %', v_r, to_jsonb(v_sa);
    end if;
    v_r := public.retorno_registrar_decisao(v_s, 'enviada', '{"provider_message_id": "teste"}'::jsonb, c_d10 + interval '9 hours 12 minutes 10 seconds');
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      raise exception '10b: (%)', v_r;
    end if;
    perform public.retorno_vigia(c_d10 + interval '13 hours 31 minutes');
    update public.retorno_config set so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null, proximo_envio_em = null;
    select * into v_sa from public.retorno_saidas s where s.abertura_id = v_caso and s.tipo = 'adiamento';
    if not found then
      raise exception '10c: o adiamento não nasceu';
    end if;
    v_r := public.retorno_pegar(c_d10 + interval '13 hours 32 minutes');
    if v_r ->> 'saida_id' is distinct from v_sa.id::text or v_r ->> 'modo' is distinct from 'ligado' or v_r ->> 'variante' is distinct from 'com_nome' then
      raise exception '10d: (%)', v_r;
    end if;
    perform pg_temp.f2a_livre();

    -- 11. Reclamação depois de um acorde não tira o acorde; o validador reprovando o urgente tira urgente, acorde e meio-dia juntos.
    if not coalesce((public._retorno_sinais('Péssimo atendimento, quero reclamar, é um absurdo') ->> 'reclamacao')::boolean, false) then
      raise exception '11a: a frase de teste não é reclamação';
    end if;
    v_caso := pg_temp.f2a_caso('5547900009518', 'Sara Acorde Teste', c_d11 + interval '7 hours');
    insert into public.retorno_saidas (abertura_id, tipo, variante, chave, phone_normalized, client_id, modo, estado, enviar_em, decidida_em, enviada_em, dedupe_key)
    select a.id, 'acorde', 'passagem', a.chave, a.phone_normalized, a.client_id, 'ligado', 'enviada',
           c_d11 + interval '8 hours', c_d11 + interval '8 hours', c_d11 + interval '8 hours', 'teste:reclamacao:9518'
      from public.retorno_aberturas a where a.id = v_caso;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('inbound', '5547900009518', 'text', 'Péssimo atendimento, quero reclamar, é um absurdo', 'received', '{"data": {}}'::jsonb,
            c_d11 + interval '9 hours', c_d11 + interval '9 hours');
    perform public.retorno_vigia(c_d11 + interval '9 hours 30 minutes');
    update public.retorno_config set so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null;
    select * into v_cfg from public.retorno_config;
    if not ('acorde' = any (v_cfg.tipos_ligados)) or not ('urgente' = any (v_cfg.tipos_ligados)) or not v_cfg.meio_dia_ligado then
      raise exception '11b: a reclamação derrubou o acorde (%)', v_cfg.tipos_ligados;
    end if;
    insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo, estado, motivo, enviar_em, decidida_em, dedupe_key)
    select a.id, 'urgente', 'sem_acorde', 'retorno_recibo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', 'recusada', 'validador',
           c_d11 + interval '10 hours', c_d11 + interval '10 hours' + make_interval(mins => g), 'teste:validador:' || g
      from public.retorno_aberturas a, generate_series(1, 3) g where a.id = v_caso;
    perform public.retorno_vigia(c_d11 + interval '10 hours 10 minutes');
    select * into v_cfg from public.retorno_config;
    if 'acorde' = any (v_cfg.tipos_ligados) or 'urgente' = any (v_cfg.tipos_ligados) or v_cfg.meio_dia_ligado then
      raise exception '11c: o rebaixamento não levou o grupo (% / %)', v_cfg.tipos_ligados, v_cfg.meio_dia_ligado;
    end if;
    if exists (select 1 from public.app_error_logs l where l.message like 'retorno_vigia: %' and l.last_seen_at > now() - interval '1 minute') then
      raise exception '11d: o vigia registrou erro';
    end if;

    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f2_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_acorde', true, '{}');
end
$acorde$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
