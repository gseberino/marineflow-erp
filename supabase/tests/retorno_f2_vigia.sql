-- Retorno F2 (P11 e P13): a carona, o meio-dia, o vigia do cartão, a promoção e as medidas. Roda só pela bancada.
-- Termina em ROLLBACK, e o bloco se desfaz sozinho. Telefones de teste 55479000099xx; frases inventadas.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

create or replace function pg_temp.f2v_caso(p_fone text, p_aberta timestamptz, p_nome text, p_body text default 'preciso falar sobre a lancha')
returns uuid
language plpgsql as $f$
declare
  v_cl uuid;
  v_msg uuid;
  v_id uuid;
begin
  insert into public.clients (type, name, whatsapp)
  values ('individual', p_nome, '(47) ' || substr(p_fone, 5, 5) || '-' || substr(p_fone, 10))
  returning id into v_cl;
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
  values ('inbound', p_fone, 'text', p_body, 'received', '{"data": {}}'::jsonb, p_aberta, p_aberta)
  returning id into v_msg;
  insert into public.retorno_aberturas (chave, phone_normalized, ddd, papel, quem, client_id, primeira_msg_id, ultima_msg_id, aberta_em,
                                        gravada_em, ultima_em, ultima_gravada_em, nivel, tipo_recibo, estado, modo)
  values (public._agenda_chave_telefone(p_fone), p_fone, '47', 'cliente', '{"papel": "cliente"}', v_cl, v_msg, v_msg,
          p_aberta, p_aberta, p_aberta, p_aberta, 'recibo', 'recibo_cliente', 'aberta', 'sombra')
  returning id into v_id;
  insert into public.retorno_mensagens (whatsapp_message_id, abertura_id, chave, recebida_em, gravada_em, corpo_hash, pede_resposta)
  values (v_msg, v_id, public._agenda_chave_telefone(p_fone), p_aberta, p_aberta, 'x', true);
  return v_id;
end $f$;

do $vigia$
declare
  c_agora constant timestamptz := '2026-11-10 15:00:00-03';   -- terça
  c_grupo constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'adiamento', 'fim_do_dia'];
  v_dono uuid;
  v_phone text;
  v_r jsonb;
  v_c1 uuid; v_c2 uuid;
  v_cartao uuid;
  v_pend uuid;
  v_ses uuid;
  v_outra uuid;
  v_s uuid;
  i integer;
  v_t timestamptz;
begin
  begin
    select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;
    update public.ai_operator_pending_actions set status = 'expired' where status = 'pending';
    update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now(), motivo = 'teste' where status = 'aberta';
    update public.retorno_config
       set modo = 'sombra', tipos_ligados = '{}', cartao_ligado = true, carona_ligada = true, carona_em = null, meio_dia_ligado = false;

    -- ── Carona ──
    if public.retorno_carona(v_dono, c_agora) is not null then
      raise exception 'c1: carona sem casos';
    end if;
    v_c1 := pg_temp.f2v_caso('5547900009901', c_agora - interval '1 hour', 'Rodrigo Vigia Teste', 'FRASE-MARCADA-F2 preciso falar');
    if public.retorno_carona('b1600000-0000-4000-8000-0000000009f4', c_agora) is not null then
      raise exception 'c2: carona de quem não é o dono';
    end if;
    update public.retorno_config set carona_ligada = false;
    if public.retorno_carona(v_dono, c_agora) is not null then
      raise exception 'c3: carona desligada';
    end if;
    update public.retorno_config set carona_ligada = true;
    v_r := public.retorno_carona(v_dono, c_agora);
    if v_r ->> 'texto' is distinct from 'Retorno: 1 esperando (Rodrigo, desde 14:00) · *retorno*' then
      raise exception 'c4: texto (%)', v_r;
    end if;
    if v_r::text like '%FRASE-MARCADA%' then
      raise exception 'c5: texto do cliente na carona';
    end if;
    if public.retorno_carona(v_dono, c_agora + interval '29 minutes') is not null then
      raise exception 'c6: 29 min depois';
    end if;
    if public.retorno_carona(v_dono, c_agora + interval '31 minutes') is null then
      raise exception 'c7: 31 min depois';
    end if;

    -- ── Vigia: queda ──
    v_c2 := pg_temp.f2v_caso('5547900009902', c_agora - interval '30 minutes', 'Paulo Vigia Teste');
    v_r := public.retorno_cartao_abrir('puxar', c_agora);
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    select c.pendencia_id, c.sessao_id into v_pend, v_ses from public.retorno_cartoes c where c.id = v_cartao;
    update public.retorno_cartoes set enviado_em = c_agora where id = v_cartao;
    -- a carona com cartão vivo
    update public.retorno_config set carona_em = null;
    if public.retorno_carona(v_dono, c_agora) ->> 'texto' is distinct from 'Retorno: cartão aberto, 2 casos · *retorno*' then
      raise exception 'c8: carona com cartão vivo';
    end if;
    -- eco do dono depois do cartão derruba só aquele item
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('outbound', '5547900009901', 'text', 'já te respondo por aqui', 'sent', '{"data": {}}'::jsonb, c_agora + interval '5 minutes', c_agora + interval '5 minutes');
    v_r := public.retorno_vigia_cartao(c_agora + interval '6 minutes');
    if (v_r ->> 'caidos')::integer <> 1 then
      raise exception 'q1: queda (%)', v_r;
    end if;
    if (select i.estado || '/' || i.caiu_motivo from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 1) is distinct from 'caiu/respondida_pelo_dono'
       or (select i.estado from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = 2) <> 'vivo' then
      raise exception 'q2: o outro item caiu';
    end if;
    if (select c.texto from public.retorno_cartoes c where c.id = v_cartao) like '%Rodrigo%' then
      raise exception 'q3: o texto não foi regravado';
    end if;
    -- todos caíram: cartão caiu, pendência rejeitada, ponteiro vazio, pergunta cancelada, sem mensagem
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('outbound', '5547900009902', 'text', 'já te respondo por aqui', 'sent', '{"data": {}}'::jsonb, c_agora + interval '7 minutes', c_agora + interval '7 minutes');
    perform public.retorno_vigia_cartao(c_agora + interval '8 minutes');
    if (select c.estado from public.retorno_cartoes c where c.id = v_cartao) <> 'caiu'
       or (select p.status from public.ai_operator_pending_actions p where p.id = v_pend) <> 'rejected'
       or (select s.metadata ->> 'pending_confirm_action_id' from public.ai_operator_sessions s where s.id = v_ses) is not null then
      raise exception 'q4: cartão caiu';
    end if;
    if exists (select 1 from public.whatsapp_perguntas w where w.phone_normalized = v_phone and w.status = 'aberta') then
      raise exception 'q5: pergunta segue aberta';
    end if;

    -- com o ponteiro em outra pendência, ele fica
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id in (v_c1, v_c2);
    v_c1 := pg_temp.f2v_caso('5547900009903', c_agora - interval '10 minutes', 'Ana Vigia Teste');
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '9 minutes');
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    select c.pendencia_id, c.sessao_id into v_pend, v_ses from public.retorno_cartoes c where c.id = v_cartao;
    update public.retorno_cartoes set enviado_em = c_agora + interval '9 minutes' where id = v_cartao;
    v_outra := gen_random_uuid();
    update public.ai_operator_sessions set metadata = metadata || jsonb_build_object('pending_confirm_action_id', v_outra) where id = v_ses;
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, hora_real, occurred_at)
    values ('outbound', '5547900009903', 'text', 'já te respondo por aqui', 'sent', '{"data": {}}'::jsonb, c_agora + interval '10 minutes', c_agora + interval '10 minutes');
    perform public.retorno_vigia_cartao(c_agora + interval '11 minutes');
    if (select s.metadata ->> 'pending_confirm_action_id' from public.ai_operator_sessions s where s.id = v_ses) is distinct from v_outra::text then
      raise exception 'q6: mexeu no ponteiro de outra pendência';
    end if;
    update public.ai_operator_sessions set metadata = metadata - 'pending_confirm_action_id' where id = v_ses;

    -- 2. 24 h: expirou.
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where id = v_c1;
    v_c1 := pg_temp.f2v_caso('5547900009904', c_agora - interval '10 minutes', 'Bia Vigia Teste');
    v_r := public.retorno_cartao_abrir('puxar', c_agora + interval '12 minutes');
    v_cartao := (v_r ->> 'cartao_id')::uuid;
    select c.pendencia_id into v_pend from public.retorno_cartoes c where c.id = v_cartao;
    update public.retorno_cartoes set enviado_em = c_agora + interval '12 minutes' where id = v_cartao;
    perform public.retorno_vigia_cartao(c_agora + interval '25 hours');
    if (select c.estado from public.retorno_cartoes c where c.id = v_cartao) <> 'expirou'
       or (select p.status from public.ai_operator_pending_actions p where p.id = v_pend) <> 'expired' then
      raise exception 'e1: expirou';
    end if;

    -- 3. Promoção: 3 dias, e só no dia seguinte; 2 aprovações no mesmo dia contam 1.
    update public.retorno_modelo_tipos set nivel = 'cartao', aprovados_dias = '{}', aprovados_usos = 0, promocao_suspensa_ate = null;
    perform public._retorno_contar_aprovacao('modelo_pronto', '2026-11-09 10:00-03');
    perform public._retorno_contar_aprovacao('modelo_pronto', '2026-11-09 11:00-03');
    if (select cardinality(t.aprovados_dias) from public.retorno_modelo_tipos t where t.tipo = 'modelo_pronto') <> 1 then
      raise exception 'p1: o mesmo dia contou 2';
    end if;
    perform public._retorno_contar_aprovacao('modelo_pronto', '2026-11-10 10:00-03');
    perform public._retorno_contar_aprovacao('modelo_pronto', '2026-11-11 10:00-03');
    perform public.retorno_vigia_cartao('2026-11-11 18:00-03');
    if (select t.nivel from public.retorno_modelo_tipos t where t.tipo = 'modelo_pronto') <> 'cartao' then
      raise exception 'p2: promoveu no 3º dia';
    end if;
    perform public.retorno_vigia_cartao('2026-11-12 08:00-03');
    if (select t.nivel from public.retorno_modelo_tipos t where t.tipo = 'modelo_pronto') <> 'sozinho' then
      raise exception 'p3: não promoveu no dia seguinte';
    end if;
    -- modelo_liberado conta usos, no mesmo dia
    for i in 1 .. 3 loop
      perform public._retorno_contar_aprovacao('modelo_liberado', '2026-11-09 10:00-03');
    end loop;
    perform public.retorno_vigia_cartao('2026-11-09 11:00-03');
    if (select t.nivel from public.retorno_modelo_tipos t where t.tipo = 'modelo_liberado') <> 'sozinho' then
      raise exception 'p4: usos';
    end if;
    -- suspensa não promove
    update public.retorno_modelo_tipos set aprovados_dias = array[date '2026-11-02', date '2026-11-03', date '2026-11-04'],
           promocao_suspensa_ate = '2026-11-20 00:00-03' where tipo = 'modelo_em_servico';
    perform public.retorno_vigia_cartao('2026-11-12 08:00-03');
    if (select t.nivel from public.retorno_modelo_tipos t where t.tipo = 'modelo_em_servico') <> 'cartao' then
      raise exception 'p5: suspensa promoveu';
    end if;

    -- 4. Fadiga: 3 aprovações rápidas suspendem; 2 rápidas e 1 lenta não.
    insert into public.retorno_cartoes (gatilho, dia, estado, hash, texto, criado_em, expira_em)
    values ('puxar', '2026-11-12', 'decidido', 'h', 'x', '2026-11-12 09:00-03', '2026-11-13 09:00-03') returning id into v_cartao;
    insert into public.retorno_cartao_itens (cartao_id, n, abertura_id, tipo_item, modelo_tipo, hash, estado)
    values (v_cartao, 1, v_c1, 'modelo', 'modelo_aguarda_peca', 'i', 'feito');
    insert into public.retorno_toques (em, cartao_id, palavra, latencia_s, rapido) values
      ('2026-11-12 09:01-03', v_cartao, 'sim_pin', 1, true), ('2026-11-12 09:02-03', v_cartao, 'sim_pin', 1, true), ('2026-11-12 09:03-03', v_cartao, 'sim_pin', 60, false);
    perform public.retorno_vigia_cartao('2026-11-12 10:00-03');
    if (select t.promocao_suspensa_ate from public.retorno_modelo_tipos t where t.tipo = 'modelo_aguarda_peca') is not null then
      raise exception 'f1: 2 rápidas e 1 lenta suspendeu';
    end if;
    update public.retorno_toques set rapido = true where cartao_id = v_cartao;
    perform public.retorno_vigia_cartao('2026-11-12 10:00-03');
    if (select t.promocao_suspensa_ate from public.retorno_modelo_tipos t where t.tipo = 'modelo_aguarda_peca') is null then
      raise exception 'f2: 3 rápidas não suspenderam';
    end if;

    -- 5. Rebaixamento e *errado*.
    update public.retorno_modelo_tipos set nivel = 'sozinho', promovido_em = '2026-11-01 00:00-03' where tipo = 'modelo_pronto';
    insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, decidida_em, enviada_em, texto, letra, letra_dia, dados, dedupe_key)
    select a.id, 'modelo_pronto', 'retorno_modelo', 'resposta_imediata', a.chave, a.phone_normalized, a.client_id, 'ligado', 'enviada',
           '2026-11-10 10:00-03', '2026-11-10 10:00-03', '2026-11-10 10:00-03', 'Bia, o serviço está pronto.', 'Z', date '2026-11-10', '{"sozinho": true}', 'teste-f2-vigia:z'
      from public.retorno_aberturas a where a.id = v_c1
    returning id into v_s;
    v_r := public.retorno_dito('{"comando": "errado", "letra": "Z"}', v_dono, '2026-11-10 19:00-03');
    if v_r ->> 'texto' is distinct from 'Anotei: ''pronto'' voltou ao cartão e não sai mais sozinho. Se quiser corrigir com Bia, responda pelo celular.' then
      raise exception 'r1: errado (%)', v_r;
    end if;
    if (select t.nivel || '/' || t.rebaixado_motivo from public.retorno_modelo_tipos t where t.tipo = 'modelo_pronto') is distinct from 'cartao/errado' then
      raise exception 'r2: não rebaixou';
    end if;
    if not (select s.dados ? 'errado_em' from public.retorno_saidas s where s.id = v_s) then
      raise exception 'r3: errado_em';
    end if;
    v_r := public.retorno_dito('{"comando": "errado", "letra": "Z"}', v_dono, '2026-11-10 19:01-03');
    if v_r ->> 'texto' is distinct from 'Não achei a letra Z no último "Mandei sozinho".' then
      raise exception 'r4: 2º errado (%)', v_r;
    end if;
    -- depois do fechamento seguinte, não vale
    update public.retorno_saidas set dados = dados - 'errado_em' where id = v_s;
    v_r := public.retorno_dito('{"comando": "errado", "letra": "Z"}', v_dono, '2026-11-11 18:00-03');
    if v_r ->> 'texto' is distinct from 'Não achei a letra Z no último "Mandei sozinho".' then
      raise exception 'r5: depois do fechamento seguinte (%)', v_r;
    end if;
    -- 3 recusas do validador na última hora
    update public.retorno_modelo_tipos set nivel = 'sozinho', promovido_em = '2026-11-01 00:00-03' where tipo = 'modelo_em_servico';
    for i in 1 .. 3 loop
      insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, modo, estado, motivo, enviar_em, decidida_em, dedupe_key)
      select a.id, 'modelo_em_servico', a.chave, a.phone_normalized, 'ligado', 'recusada', 'validador', '2026-11-12 09:00-03', '2026-11-12 09:30-03', 'teste-f2-vigia:v' || i
        from public.retorno_aberturas a where a.id = v_c1;
    end loop;
    perform public.retorno_vigia_cartao('2026-11-12 10:00-03');
    if (select t.nivel || '/' || t.rebaixado_motivo from public.retorno_modelo_tipos t where t.tipo = 'modelo_em_servico') is distinct from 'cartao/validador' then
      raise exception 'r6: validador';
    end if;

    -- 8. Saída aprovada recusada: aviso uma vez, sem texto do cliente e sem gastar acorde.
    insert into public.retorno_saidas (abertura_id, tipo, chave, phone_normalized, modo, estado, motivo, enviar_em, decidida_em, dados, dedupe_key)
    select a.id, 'modelo_aguarda_peca', a.chave, a.phone_normalized, 'ligado', 'recusada', 'validador', '2026-11-12 09:00-03', '2026-11-12 09:30-03',
           '{"aprovada": true}', 'teste-f2-vigia:recusa'
      from public.retorno_aberturas a where a.id = v_c1
    returning id into v_s;
    v_r := public.retorno_vigia_cartao('2026-11-12 10:00-03');
    if (v_r ->> 'avisos')::integer <> 1 then
      raise exception 'a1: aviso (%)', v_r;
    end if;
    if (public.retorno_vigia_cartao('2026-11-12 10:01-03') ->> 'avisos')::integer <> 0 then
      raise exception 'a2: avisou duas vezes';
    end if;

    -- ── Meio-dia ──
    update public.retorno_config set modo = 'ligado', tipos_ligados = c_grupo || array['urgente', 'acorde'], meio_dia_ligado = true;
    update public.retorno_aberturas set estado = 'fechada', fechada_em = c_agora, fechada_motivo = 'nada' where estado <> 'fechada';
    v_c1 := pg_temp.f2v_caso('5547900009905', '2026-11-10 09:00-03', 'Duda Vigia Teste');
    update public.retorno_aberturas set prometido_fonte = 'meio_dia', prometido_ate = '2026-11-10 14:00-03' where id = v_c1;
    if public._retorno_cartao_devido('2026-11-10 12:29-03') is not null then
      raise exception 'm1: 12:29';
    end if;
    if public._retorno_cartao_devido('2026-11-10 12:30-03') ->> 'gatilho' is distinct from 'meio_dia' then
      raise exception 'm2: 12:30';
    end if;
    if not public.retorno_tem_vencido('2026-11-10 12:30-03') then
      raise exception 'm3: tem_vencido com cartão devido';
    end if;
    if public._retorno_cartao_devido('2026-11-10 14:00-03') is not null then
      raise exception 'm4: 14:00';
    end if;
    if public._retorno_cartao_devido('2026-11-14 12:30-03') is not null then
      raise exception 'm5: sábado';
    end if;
    update public.retorno_aberturas set prometido_fonte = 'fechamento' where id = v_c1;
    if public._retorno_cartao_devido('2026-11-10 12:30-03') is not null then
      raise exception 'm6: sem caso do meio-dia';
    end if;
    update public.retorno_aberturas set prometido_fonte = 'meio_dia' where id = v_c1;
    v_r := public.retorno_cartao_abrir('meio_dia', '2026-11-10 12:30-03');
    if v_r ->> 'acao' <> 'cartao' or v_r ->> 'texto' not like 'Retorno · meio-dia · 1 esperando%' then
      raise exception 'm7: abrir (%)', v_r;
    end if;
    if public._retorno_cartao_devido('2026-11-10 12:31-03') is not null then
      raise exception 'm8: 2ª chamada no mesmo dia';
    end if;
    if not exists (select 1 from public.avisos_do_dono a where a.chave = 'retorno:meio_dia:2026-11-10' and a.situacao = 'deixado') then
      raise exception 'm9: portão';
    end if;

    -- 7. Medidas.
    v_t := c_agora;
    if not exists (select 1 from public.retorno_f2_medidas m where m.semana = date '2026-11-09') then
      raise exception 'v1: medidas sem a semana';
    end if;
    begin
      set local role anon;
      perform 1 from public.retorno_f2_medidas;
      reset role;
      raise exception 'v2: anon leu as medidas';
    exception when insufficient_privilege then
      reset role;
    end;
    if public._retorno_horas_uteis('2026-11-10 09:00-03', '2026-11-11 09:00-03') <> 10 then
      raise exception 'v3: horas úteis (%)', public._retorno_horas_uteis('2026-11-10 09:00-03', '2026-11-11 09:00-03');
    end if;

    raise exception 'retorno_f2_desfaz' using errcode = 'P0001';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> 'retorno_f2_desfaz' then
      raise;
    end if;
  end;
  insert into _bancada (arquivo, ok, numeros) values ('retorno_f2_vigia', true, '{}');
end
$vigia$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
