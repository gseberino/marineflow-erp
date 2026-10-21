-- Prova: a voz única LIGADA de verdade (secretário, Passo 4, P4.5, migration 20261020200000_avisos_acorde_que_nao_saiu).
--
--   L1  avisos_para_a_mensagem continua só para service_role (anon/authenticated sem execute)
--   L2  o acorde que a fila NÃO entregou (linha 'aviso:<id>' failed) volta a guardado na próxima mensagem fixa e sai
--       nela: motivo envio_falhou, sem cartão, reaberto 1, acordes_voltaram = 1; a vaga do dia fica livre
--   L3  fila 'pending' e 'sent' não mexem no acorde (o WhatsApp ainda pode voltar; o que saiu, saiu); 'cancelled' devolve
--   L4  o ciclo inteiro no modo ligado: guardado → incluído com a fila (pending: espera) → a fila falhou → volta e vai
--       na mensagem seguinte → incluído de novo → fila 'sent' → entregue (nunca se perde, nunca duplica)
--   L5  acorde de mais de 7 dias não é conferido (nem devolvido)
--   L6  a conferência é por modo: a chamada do ligado não mexe no acorde da sombra
--   L7  o acorde sem linha na fila (saiu por outro caminho: turno do assistente, envio direto) fica como acordou
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado; também roda no ensaio PGlite da bancada,
--   D:/IA-HBR/comprovantes-bancada/pglite-ensaio/rodar-uma-voz-ligado.mjs)
--
--   supabase db query --linked -f supabase/tests/avisos_ligado.sql --output json
--
-- Seguro em produção: telefones de mentira 55000…, o relógio de cada registro vem no "agora" (semana de 19 a 25/10/2026),
-- as linhas da fila de envio são de mentira, nascem 'sent'/'failed'/'pending'/'cancelled' DENTRO da transação (o worker não
-- as vê) e têm chave 'aviso:<id de mentira>' — e termina em ROLLBACK. Rodar DEPOIS da migration 20261020200000.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp._fone() returns text language sql volatile as $$
  select '55000' || lpad((floor(random() * 1000000000))::bigint::text, 9, '0')
$$;

create function pg_temp._reg(p_phone text, p_agora text, p_chave text, p_destino text, p_assunto text default null,
                             p_modo text default 'ligado') returns jsonb language sql as $$
  select public.aviso_registrar(jsonb_build_object(
    'phone', p_phone, 'modo', p_modo, 'fonte', 'teste_ligado', 'chave', p_chave, 'assunto', p_assunto,
    'destino', p_destino, 'agora', p_agora, 'texto', 'aviso de teste (ligado)'))
$$;

create function pg_temp._para(p_phone text, p_mensagem text, p_agora text, p_modo text default 'ligado') returns jsonb language sql as $$
  select public.avisos_para_a_mensagem(jsonb_build_object('phone', p_phone, 'modo', p_modo, 'mensagem', p_mensagem, 'agora', p_agora))
$$;

-- a linha da fila de um acorde (a chave que linhaDoAcordeNaFila grava), já no estado pedido
create function pg_temp._fila_do_acorde(p_phone text, p_aviso uuid, p_status text) returns uuid language sql as $$
  insert into public.whatsapp_send_queue (phone_normalized, message, source, status, sent_at, dedupe_key)
  values (p_phone, 'teste acorde ' || p_aviso, 'teste_uma_voz', p_status, case when p_status = 'sent' then now() end,
          'aviso:' || p_aviso::text)
  returning id
$$;

-- uma linha de mensagem fixa de mentira
create function pg_temp._fila(p_phone text, p_status text) returns uuid language sql as $$
  insert into public.whatsapp_send_queue (phone_normalized, message, source, status, sent_at)
  values (p_phone, 'teste fixa ' || gen_random_uuid(), 'teste_uma_voz', p_status, case when p_status = 'sent' then now() end)
  returning id
$$;

-- ═══ L1 ═══════════════════════════════════════════════════════════════════════════════════════
insert into _resultado values ('L1 avisos_para_a_mensagem só para service_role',
  not has_function_privilege('anon', 'public.avisos_para_a_mensagem(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.avisos_para_a_mensagem(jsonb)', 'execute')
  and has_function_privilege('service_role', 'public.avisos_para_a_mensagem(jsonb)', 'execute'), null);

-- ═══ L2 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._fone();
  r jsonb;
  p jsonb;
  v_id uuid;
  v_aviso record;
  v_acordes integer;
begin
  -- quarta 21/10 10:00: acorda com cartão; entra na fila e a fila desiste (WhatsApp fora até as 20h)
  r := pg_temp._reg(v_phone, '2026-10-21T13:00:00Z', 'l2:a', 'acorde', 'l2:assunto');
  v_id := (r->>'id')::uuid;
  perform pg_temp._fila_do_acorde(v_phone, v_id, 'failed');
  -- o fechamento das 17:30 leva
  p := pg_temp._para(v_phone, 'fechamento', '2026-10-21T20:30:00Z');
  select a.situacao, a.motivo, a.cartao, a.reaberto, a.mensagem into v_aviso from public.avisos_do_dono a where a.id = v_id;
  select count(*) into v_acordes from public.avisos_do_dono a
   where a.phone_normalized = v_phone and a.modo = 'ligado' and a.dia = date '2026-10-21' and a.situacao = 'acordou';
  insert into _resultado values ('L2 acorde que a fila não entregou volta a guardado e sai na próxima mensagem fixa',
    r->>'decisao' = 'acordar' and (r->>'cartao')::boolean
    and (p->>'acordes_voltaram')::int = 1 and jsonb_array_length(p->'avisos') = 1 and (p->'avisos'->0->>'id')::uuid = v_id
    and v_aviso.situacao = 'guardado' and v_aviso.motivo = 'envio_falhou' and not v_aviso.cartao and v_aviso.reaberto = 1
    and v_aviso.mensagem = 'fechamento' and v_acordes = 0,
    format('decisao=%s voltaram=%s avisos=%s situacao=%s motivo=%s reaberto=%s acordes=%s',
           r->>'decisao', p->>'acordes_voltaram', jsonb_array_length(p->'avisos'), v_aviso.situacao, v_aviso.motivo, v_aviso.reaberto, v_acordes));
end $$;

-- ═══ L3 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._fone();
  v_pend uuid;
  v_sent uuid;
  v_canc uuid;
  p jsonb;
  v_sit text[];
begin
  v_pend := (pg_temp._reg(v_phone, '2026-10-21T13:00:00Z', 'l3:pend', 'acorde', 'l3:a')->>'id')::uuid;
  v_sent := (pg_temp._reg(v_phone, '2026-10-21T13:05:00Z', 'l3:sent', 'acorde', 'l3:b')->>'id')::uuid;
  perform pg_temp._fila_do_acorde(v_phone, v_pend, 'pending');
  perform pg_temp._fila_do_acorde(v_phone, v_sent, 'sent');
  p := pg_temp._para(v_phone, 'fechamento', '2026-10-21T20:30:00Z');
  select array_agg(a.situacao order by a.chave) into v_sit from public.avisos_do_dono a where a.id in (v_pend, v_sent);
  -- outro dia: 'cancelled' também devolve
  v_canc := (pg_temp._reg(v_phone, '2026-10-22T13:00:00Z', 'l3:canc', 'acorde', 'l3:c')->>'id')::uuid;
  perform pg_temp._fila_do_acorde(v_phone, v_canc, 'cancelled');
  insert into _resultado values ('L3 fila pending e sent não mexem no acorde; cancelled devolve',
    (p->>'acordes_voltaram')::int = 0 and jsonb_array_length(p->'avisos') = 0 and v_sit = array['acordou', 'acordou']
    and (pg_temp._para(v_phone, 'fechamento', '2026-10-22T20:30:00Z')->>'acordes_voltaram')::int = 1,
    format('voltaram=%s avisos=%s situacoes=%s', p->>'acordes_voltaram', jsonb_array_length(p->'avisos'), v_sit));
end $$;

-- ═══ L4 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._fone();
  v_id uuid;
  v_f1 uuid;
  v_f2 uuid;
  p1 jsonb;
  p2 jsonb;
  p3 jsonb;
  p4 jsonb;
  i1 jsonb;
  i2 jsonb;
  v_fim record;
begin
  -- quarta 21/10 18:00: guardado (proxima_fixa) para a manhã de quinta
  v_id := (pg_temp._reg(v_phone, '2026-10-21T21:00:00Z', 'l4:g', 'proxima_fixa', 'l4:a')->>'id')::uuid;
  -- a manhã de quinta (07:30) leva; entra na fila (pending)
  p1 := pg_temp._para(v_phone, 'manha', '2026-10-22T10:30:00Z');
  v_f1 := pg_temp._fila(v_phone, 'pending');
  i1 := public.avisos_incluir_na_mensagem(jsonb_build_object('phone', v_phone, 'modo', 'ligado', 'ids', jsonb_build_array(v_id), 'fila_id', v_f1));
  -- às 09:00 a fila ainda tenta: nada volta, nada sai de novo
  p2 := pg_temp._para(v_phone, 'manha', '2026-10-22T12:00:00Z');
  -- a manhã desistiu (WhatsApp fora): o fechamento das 17:30 leva de novo
  update public.whatsapp_send_queue set status = 'failed' where id = v_f1;
  p3 := pg_temp._para(v_phone, 'fechamento', '2026-10-22T20:30:00Z');
  v_f2 := pg_temp._fila(v_phone, 'sent');
  i2 := public.avisos_incluir_na_mensagem(jsonb_build_object('phone', v_phone, 'modo', 'ligado', 'ids', jsonb_build_array(v_id), 'fila_id', v_f2));
  -- a manhã seguinte confere: entregue (e não volta)
  p4 := pg_temp._para(v_phone, 'manha', '2026-10-23T10:30:00Z');
  select a.situacao, a.fila_id, a.reaberto, a.entregue_em is not null as entregue into v_fim from public.avisos_do_dono a where a.id = v_id;
  insert into _resultado values ('L4 ciclo ligado: guardado → incluído (pending espera) → falhou → volta → incluído → sent = entregue',
    jsonb_array_length(p1->'avisos') = 1 and (i1->>'incluidos')::int = 1
    and jsonb_array_length(p2->'avisos') = 0 and (p2->>'voltaram')::int = 0
    and (p3->>'voltaram')::int = 1 and jsonb_array_length(p3->'avisos') = 1 and (i2->>'incluidos')::int = 1
    and (p4->>'entregues')::int = 1 and jsonb_array_length(p4->'avisos') = 0
    and v_fim.situacao = 'entregue' and v_fim.fila_id = v_f2 and v_fim.reaberto = 1 and v_fim.entregue,
    format('p1=%s i1=%s p2=%s p3v=%s p3=%s i2=%s p4e=%s fim=%s', jsonb_array_length(p1->'avisos'), i1->>'incluidos',
           jsonb_array_length(p2->'avisos'), p3->>'voltaram', jsonb_array_length(p3->'avisos'), i2->>'incluidos', p4->>'entregues', v_fim.situacao));
end $$;

-- ═══ L5 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._fone();
  v_id uuid;
  p jsonb;
begin
  v_id := (pg_temp._reg(v_phone, '2026-10-10T13:00:00Z', 'l5:velho', 'acorde', 'l5:a')->>'id')::uuid;
  perform pg_temp._fila_do_acorde(v_phone, v_id, 'failed');
  p := pg_temp._para(v_phone, 'fechamento', '2026-10-21T20:30:00Z');
  insert into _resultado values ('L5 acorde de mais de 7 dias não é conferido',
    (p->>'acordes_voltaram')::int = 0 and (select a.situacao from public.avisos_do_dono a where a.id = v_id) = 'acordou',
    format('voltaram=%s', p->>'acordes_voltaram'));
end $$;

-- ═══ L6 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._fone();
  v_id uuid;
  p jsonb;
begin
  v_id := (pg_temp._reg(v_phone, '2026-10-21T13:00:00Z', 'l6:sombra', 'acorde', 'l6:a', 'sombra')->>'id')::uuid;
  perform pg_temp._fila_do_acorde(v_phone, v_id, 'failed');
  p := pg_temp._para(v_phone, 'fechamento', '2026-10-21T20:30:00Z', 'ligado');
  insert into _resultado values ('L6 a chamada do ligado não mexe no acorde da sombra',
    (p->>'acordes_voltaram')::int = 0 and (select a.situacao from public.avisos_do_dono a where a.id = v_id) = 'acordou',
    format('voltaram=%s', p->>'acordes_voltaram'));
end $$;

-- ═══ L7 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._fone();
  v_id uuid;
  p jsonb;
begin
  v_id := (pg_temp._reg(v_phone, '2026-10-21T13:00:00Z', 'l7:direto', 'acorde', 'l7:a')->>'id')::uuid;
  p := pg_temp._para(v_phone, 'fechamento', '2026-10-21T20:30:00Z');
  insert into _resultado values ('L7 acorde sem linha na fila (saiu por outro caminho) fica como acordou',
    (p->>'acordes_voltaram')::int = 0 and jsonb_array_length(p->'avisos') = 0
    and (select a.situacao from public.avisos_do_dono a where a.id = v_id) = 'acordou',
    format('voltaram=%s avisos=%s', p->>'acordes_voltaram', jsonb_array_length(p->'avisos')));
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
