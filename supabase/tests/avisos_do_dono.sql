-- Prova: o portão "uma voz só" (migration 20261016101000_avisos_do_dono).
--
--   A1  anon/authenticated sem execute nas RPCs (service_role com); a tabela com RLS, anon sem nada,
--       authenticated só lê
--   A2  acorde às 10:00 de um dia útil = acordar com cartão; a mesma chave de novo = repetido
--   A3  o limite: 3 assuntos no mesmo dia → o 3º fica guardado (limite_do_dia) para o fechamento das 17:30
--   A4  um por assunto: o 2º aviso do mesmo assunto no dia fica guardado; com novo_fato acorda
--   A5  janela da manhã: 08:10 e 09:29 acordam SEM cartão; 09:30 acorda com cartão
--   A6  fora das 08–20: 06:00 → manhã de hoje; 07:59 → fechamento de hoje; 20:00 → manhã de amanhã
--   A7  a próxima mensagem fixa (sexta 17:31, sábado com D7 domingo/segunda, domingo, escritório, hoje, 23:30)
--   A8  deixar e acabar não gastam vaga
--   A9  aviso_reabrir: o acorde que não saiu volta a guardado e libera a vaga; o que não acordou não reabre
--   A10 entrega: antes da hora não sai; na hora sai; fila que falhou devolve; fila 'sent' entrega; fila
--       'pending' segura
--   A11 'hoje' só pela manhã, 'escritorio' só pelo fechamento
--   A12 sombra inclui sem fila (= entregue na sombra); ligado sem fila é recusado
--   A13 aviso_resolver: o guardado resolvido some
--   A14 só o admin lê os avisos (financeiro e técnico veem 0)
--   A15 as três chaves existem com os padrões; o financeiro não muda nenhuma (42501); o admin muda
--   A16 as regras do dono valem sem publicar código: acordes_por_dia = 1; sábado → segunda
--   A17 sombra e ligado não se misturam (limite e chave por modo)
--   A18 entrada ruim volta ok=false, sem gravar
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado; também roda no ensaio PGlite da bancada,
--   D:/IA-HBR/comprovantes-bancada/pglite-ensaio/rodar-uma-voz.mjs)
--
--   supabase db query --linked -f supabase/tests/avisos_do_dono.sql --output json
--
-- Seguro em produção: telefones de mentira 55000…, usuários de teste criados na transação, o relógio
-- de cada registro vem no "agora" (semana de 19 a 25/10/2026), as linhas da fila de envio são de mentira
-- e nascem 'sent'/'failed'/'pending' DENTRO da transação (o worker não as vê) — e termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp._fone() returns text language sql volatile as $$
  select '55000' || lpad((floor(random() * 1000000000))::bigint::text, 9, '0')
$$;

create function pg_temp._reg(p_phone text, p_agora text, p_chave text, p_destino text, p_assunto text default null,
                             p_novo boolean default false, p_modo text default 'sombra') returns jsonb language sql as $$
  select public.aviso_registrar(jsonb_build_object(
    'phone', p_phone, 'modo', p_modo, 'fonte', 'teste_portao', 'chave', p_chave, 'assunto', p_assunto,
    'destino', p_destino, 'novo_fato', p_novo, 'agora', p_agora, 'texto', 'aviso de teste'))
$$;

create function pg_temp._para(p_phone text, p_mensagem text, p_agora text, p_modo text default 'sombra') returns jsonb language sql as $$
  select public.avisos_para_a_mensagem(jsonb_build_object('phone', p_phone, 'modo', p_modo, 'mensagem', p_mensagem, 'agora', p_agora))
$$;

-- uma linha de mentira na fila de envio, já no estado pedido
create function pg_temp._fila(p_phone text, p_status text) returns uuid language sql as $$
  insert into public.whatsapp_send_queue (phone_normalized, message, source, status, sent_at)
  values (p_phone, 'teste uma voz ' || gen_random_uuid(), 'teste_uma_voz', p_status,
          case when p_status = 'sent' then now() end)
  returning id
$$;

create function pg_temp._usuario(p_papel text) returns uuid language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste portão ' || p_papel, 'teste-portao-' || v_id || '@teste.invalido', p_papel, true);
  return v_id;
end $$;

-- ═══ A1 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_f text;
  v_t text := 'public.avisos_do_dono';
  v_falhas text[] := '{}';
begin
  foreach v_f in array array['public.aviso_registrar(jsonb)', 'public.aviso_reabrir(jsonb)', 'public.avisos_para_a_mensagem(jsonb)',
                             'public.avisos_incluir_na_mensagem(jsonb)', 'public.aviso_resolver(jsonb)',
                             'public._aviso_proxima_mensagem(timestamp with time zone, text, text)'] loop
    if has_function_privilege('anon', v_f, 'execute') then v_falhas := v_falhas || ('anon executa ' || v_f); end if;
    if has_function_privilege('authenticated', v_f, 'execute') then v_falhas := v_falhas || ('authenticated executa ' || v_f); end if;
    if not has_function_privilege('service_role', v_f, 'execute') then v_falhas := v_falhas || ('service_role sem ' || v_f); end if;
  end loop;
  if not (select relrowsecurity from pg_class where oid = v_t::regclass) then v_falhas := v_falhas || ('RLS desligada ' || v_t); end if;
  if has_table_privilege('anon', v_t, 'select') or has_table_privilege('anon', v_t, 'insert') then v_falhas := v_falhas || ('anon em ' || v_t); end if;
  if has_table_privilege('authenticated', v_t, 'insert') or has_table_privilege('authenticated', v_t, 'update')
     or has_table_privilege('authenticated', v_t, 'delete') then v_falhas := v_falhas || ('authenticated escreve ' || v_t); end if;
  insert into _resultado values ('A1 RPCs só para service_role; tabela fechada', cardinality(v_falhas) = 0,
    coalesce(nullif(array_to_string(v_falhas, ', '), ''), '6 funções e 1 tabela conferidas'));
end $$;

-- ═══ A2 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  a jsonb;
  b jsonb;
begin
  a := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'golpe:x@teste.invalido', 'acorde');
  b := pg_temp._reg(v_p, '2026-10-21 11:00:00-03', 'golpe:x@teste.invalido', 'acorde');
  insert into _resultado values ('A2 acorde às 10:00 acorda com cartão; a mesma chave de novo é repetido',
    a->>'decisao' = 'acordar' and (a->>'cartao')::boolean and (a->>'acordes_hoje')::int = 1
      and b->>'decisao' = 'repetido' and b->>'antes' = 'acordar'
      and (select count(*) from public.avisos_do_dono where phone_normalized = v_p) = 1,
    'a=' || (a->>'decisao') || '/cartao=' || (a->>'cartao') || ' b=' || (b->>'decisao'));
end $$;

-- ═══ A3 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  a jsonb; b jsonb; c jsonb;
begin
  a := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a3:1', 'acorde', 'assunto:1');
  b := pg_temp._reg(v_p, '2026-10-21 10:10:00-03', 'a3:2', 'acorde', 'assunto:2');
  c := pg_temp._reg(v_p, '2026-10-21 10:20:00-03', 'a3:3', 'acorde', 'assunto:3');
  insert into _resultado values ('A3 o 3º acorde do dia fica guardado para o fechamento das 17:30',
    a->>'decisao' = 'acordar' and b->>'decisao' = 'acordar' and c->>'decisao' = 'guardar'
      and c->>'motivo' = 'limite_do_dia' and c->>'mensagem' = 'fechamento'
      and (c->>'entregar_a_partir_de')::timestamptz = '2026-10-21 17:30:00-03'::timestamptz,
    a->>'decisao' || ', ' || (b->>'decisao') || ', ' || (c->>'decisao') || '/' || coalesce(c->>'motivo', '-') || ' → '
      || coalesce(c->>'mensagem', '-') || ' ' || coalesce(c->>'entregar_a_partir_de', '-'));
end $$;

-- ═══ A4 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  a jsonb; b jsonb; c jsonb;
begin
  a := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a4:quer_fechar', 'acorde', 'contato:5547000000001');
  b := pg_temp._reg(v_p, '2026-10-21 11:00:00-03', 'a4:de_novo', 'acorde', 'contato:5547000000001');
  c := pg_temp._reg(v_p, '2026-10-21 14:15:00-03', 'a4:desistiu', 'acorde', 'contato:5547000000001', true);
  insert into _resultado values ('A4 um acorde por assunto no dia; fato novo (novo_fato) acorda de novo',
    a->>'decisao' = 'acordar' and b->>'decisao' = 'guardar' and b->>'motivo' = 'assunto_ja_acordou_hoje'
      and c->>'decisao' = 'acordar',
    a->>'decisao' || ', ' || (b->>'decisao') || '/' || coalesce(b->>'motivo', '-') || ', novo_fato=' || (c->>'decisao'));
end $$;

-- ═══ A5 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  a jsonb; b jsonb; c jsonb;
begin
  a := pg_temp._reg(pg_temp._fone(), '2026-10-21 08:10:00-03', 'a5:0810', 'acorde');
  b := pg_temp._reg(pg_temp._fone(), '2026-10-21 09:29:00-03', 'a5:0929', 'acorde');
  c := pg_temp._reg(pg_temp._fone(), '2026-10-21 09:30:00-03', 'a5:0930', 'acorde');
  insert into _resultado values ('A5 08:10 e 09:29 acordam sem cartão (janela da manhã); 09:30 com cartão',
    a->>'decisao' = 'acordar' and not (a->>'cartao')::boolean and a->>'motivo' = 'janela_da_manha'
      and b->>'decisao' = 'acordar' and not (b->>'cartao')::boolean
      and c->>'decisao' = 'acordar' and (c->>'cartao')::boolean and c->>'motivo' is null,
    '08:10 cartao=' || (a->>'cartao') || ' 09:29 cartao=' || (b->>'cartao') || ' 09:30 cartao=' || (c->>'cartao'));
end $$;

-- ═══ A6 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  a jsonb; b jsonb; c jsonb;
begin
  a := pg_temp._reg(pg_temp._fone(), '2026-10-21 06:00:00-03', 'a6:0600', 'acorde');
  b := pg_temp._reg(pg_temp._fone(), '2026-10-21 07:59:00-03', 'a6:0759', 'acorde');
  c := pg_temp._reg(pg_temp._fone(), '2026-10-21 20:00:00-03', 'a6:2000', 'acorde');
  insert into _resultado values ('A6 fora das 08–20 fica guardado: 06:00 → manhã de hoje; 07:59 → fechamento; 20:00 → manhã de amanhã',
    a->>'decisao' = 'guardar' and a->>'motivo' = 'fora_da_janela' and a->>'mensagem' = 'manha'
      and (a->>'entregar_a_partir_de')::timestamptz = '2026-10-21 07:30:00-03'::timestamptz
      and b->>'decisao' = 'guardar' and b->>'mensagem' = 'fechamento'
      and (b->>'entregar_a_partir_de')::timestamptz = '2026-10-21 17:30:00-03'::timestamptz
      and c->>'decisao' = 'guardar' and c->>'mensagem' = 'manha'
      and (c->>'entregar_a_partir_de')::timestamptz = '2026-10-22 07:30:00-03'::timestamptz,
    '06:00→' || coalesce(a->>'mensagem', '-') || ' 07:59→' || coalesce(b->>'mensagem', '-') || ' 20:00→' || coalesce(c->>'mensagem', '-'));
end $$;

-- ═══ A7 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_falhas text[] := '{}';
  v_caso record;
  v_r record;
begin
  for v_caso in
    select * from (values
      ('sexta 17:31',            '2026-10-23 17:31:00-03', 'proxima_fixa', 'domingo', 'manha',      '2026-10-24 07:30:00-03'),
      ('sexta 17:29',            '2026-10-23 17:29:00-03', 'proxima_fixa', 'domingo', 'fechamento', '2026-10-23 17:30:00-03'),
      ('sábado 10:00 (domingo)', '2026-10-24 10:00:00-03', 'proxima_fixa', 'domingo', 'manha',      '2026-10-25 07:30:00-03'),
      ('sábado 18:00 (segunda)', '2026-10-24 18:00:00-03', 'proxima_fixa', 'segunda', 'manha',      '2026-10-26 07:30:00-03'),
      ('domingo 07:00',          '2026-10-25 07:00:00-03', 'proxima_fixa', 'domingo', 'manha',      '2026-10-25 07:30:00-03'),
      ('domingo 10:00',          '2026-10-25 10:00:00-03', 'proxima_fixa', 'domingo', 'manha',      '2026-10-26 07:30:00-03'),
      ('quarta 23:30 (fuso)',    '2026-10-21 23:30:00-03', 'proxima_fixa', 'domingo', 'manha',      '2026-10-22 07:30:00-03'),
      ('escritório quarta 10:00','2026-10-21 10:00:00-03', 'escritorio',   'domingo', 'fechamento', '2026-10-21 17:30:00-03'),
      ('escritório sexta 18:00', '2026-10-23 18:00:00-03', 'escritorio',   'domingo', 'fechamento', '2026-10-26 17:30:00-03'),
      ('escritório sábado',      '2026-10-24 09:00:00-03', 'escritorio',   'domingo', 'fechamento', '2026-10-26 17:30:00-03'),
      ('hoje segunda 06:00',     '2026-10-19 06:00:00-03', 'hoje',         'domingo', 'manha',      '2026-10-19 07:30:00-03'),
      ('hoje segunda 10:00',     '2026-10-19 10:00:00-03', 'hoje',         'domingo', 'manha',      '2026-10-20 07:30:00-03')
    ) as t(nome, agora, destino, sabado, mensagem, a_partir)
  loop
    select * into v_r from public._aviso_proxima_mensagem(v_caso.agora::timestamptz, v_caso.destino, v_caso.sabado);
    if v_r.mensagem is distinct from v_caso.mensagem or v_r.a_partir is distinct from v_caso.a_partir::timestamptz then
      v_falhas := v_falhas || (v_caso.nome || ': ' || coalesce(v_r.mensagem, '-') || ' ' || coalesce(v_r.a_partir::text, '-'));
    end if;
  end loop;
  insert into _resultado values ('A7 a próxima mensagem fixa (12 casos: sexta, sábado D7, domingo, fuso, escritório, hoje)',
    cardinality(v_falhas) = 0, coalesce(nullif(array_to_string(v_falhas, '; '), ''), '12 casos certos'));
end $$;

-- ═══ A8 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  a jsonb; b jsonb; c jsonb; d jsonb; e jsonb;
begin
  a := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a8:lembrete', 'deixar');
  b := pg_temp._reg(v_p, '2026-10-21 10:01:00-03', 'a8:revisao', 'deixar');
  c := pg_temp._reg(v_p, '2026-10-21 10:02:00-03', 'a8:vence_hoje', 'acaba');
  d := pg_temp._reg(v_p, '2026-10-21 10:03:00-03', 'a8:acorde1', 'acorde', 'a8:x');
  e := pg_temp._reg(v_p, '2026-10-21 10:04:00-03', 'a8:acorde2', 'acorde', 'a8:y');
  insert into _resultado values ('A8 deixar e acabar não gastam vaga do dia',
    a->>'decisao' = 'deixar' and a->>'situacao' = 'deixado' and b->>'decisao' = 'deixar'
      and c->>'decisao' = 'acabar' and c->>'situacao' = 'acabou' and a->>'mensagem' is null
      and d->>'decisao' = 'acordar' and e->>'decisao' = 'acordar',
    a->>'decisao' || ', ' || (b->>'decisao') || ', ' || (c->>'decisao') || ', ' || (d->>'decisao') || ', ' || (e->>'decisao'));
end $$;

-- ═══ A9 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  a jsonb; b jsonb; r jsonb; c jsonb; r2 jsonb; v_sit text;
begin
  a := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a9:1', 'acorde', 'a9:1');
  b := pg_temp._reg(v_p, '2026-10-21 10:05:00-03', 'a9:2', 'acorde', 'a9:2');
  r := public.aviso_reabrir(jsonb_build_object('id', a->>'id', 'agora', '2026-10-21 10:06:00-03'));
  c := pg_temp._reg(v_p, '2026-10-21 10:10:00-03', 'a9:3', 'acorde', 'a9:3');
  r2 := public.aviso_reabrir(jsonb_build_object('id', a->>'id', 'agora', '2026-10-21 10:11:00-03'));
  select situacao into v_sit from public.avisos_do_dono where id = (a->>'id')::uuid;
  insert into _resultado values ('A9 o acorde que não saiu volta a guardado e libera a vaga; reabrir de novo não faz nada',
    r->>'resultado' = 'reaberto' and r->>'mensagem' = 'fechamento' and v_sit = 'guardado'
      and c->>'decisao' = 'acordar' and r2->>'resultado' = 'nao_estava_acordado'
      and (select reaberto from public.avisos_do_dono where id = (a->>'id')::uuid) = 1
      and (select motivo from public.avisos_do_dono where id = (a->>'id')::uuid) = 'envio_falhou',
    'reabrir=' || (r->>'resultado') || ' depois=' || (c->>'decisao') || ' 2ª=' || (r2->>'resultado'));
end $$;

-- ═══ A10 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  g jsonb;
  v_id uuid;
  antes jsonb; na_hora jsonb; depois_falha jsonb; segurando jsonb; final jsonb;
  v_falhou uuid; v_pendente uuid; v_saiu uuid;
  v_inc1 jsonb; v_inc2 jsonb; v_inc3 jsonb;
  v_sit_pendente text; v_sit_final text;
begin
  g := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a10:guardado', 'proxima_fixa');
  v_id := (g->>'id')::uuid;
  antes := pg_temp._para(v_p, 'fechamento', '2026-10-21 17:00:00-03');
  na_hora := pg_temp._para(v_p, 'fechamento', '2026-10-21 17:30:00-03');
  -- o fechamento leva, mas a fila falha: volta e a manhã seguinte leva
  v_falhou := pg_temp._fila(v_p, 'failed');
  v_inc1 := public.avisos_incluir_na_mensagem(jsonb_build_object('phone', v_p, 'modo', 'sombra', 'ids', jsonb_build_array(v_id), 'fila_id', v_falhou));
  depois_falha := pg_temp._para(v_p, 'manha', '2026-10-22 07:30:00-03');
  -- a manhã leva e ainda está na fila (pending): não volta, não é entregue
  v_pendente := pg_temp._fila(v_p, 'pending');
  v_inc2 := public.avisos_incluir_na_mensagem(jsonb_build_object('phone', v_p, 'modo', 'sombra', 'ids', jsonb_build_array(v_id), 'fila_id', v_pendente));
  segurando := pg_temp._para(v_p, 'fechamento', '2026-10-22 17:30:00-03');
  select situacao into v_sit_pendente from public.avisos_do_dono where id = v_id;
  -- a fila sai: entregue
  update public.whatsapp_send_queue set status = 'sent', sent_at = now() where id = v_pendente;
  final := pg_temp._para(v_p, 'manha', '2026-10-23 07:30:00-03');
  select situacao into v_sit_final from public.avisos_do_dono where id = v_id;
  insert into _resultado values ('A10 entrega: antes da hora não; na hora sim; fila que falhou devolve; pending segura; sent entrega',
    g->>'decisao' = 'guardar' and jsonb_array_length(antes->'avisos') = 0 and jsonb_array_length(na_hora->'avisos') = 1
      and (v_inc1->>'incluidos')::int = 1
      and (depois_falha->>'voltaram')::int = 1 and jsonb_array_length(depois_falha->'avisos') = 1
      and (depois_falha->'avisos'->0->>'id')::uuid = v_id
      and (v_inc2->>'incluidos')::int = 1 and jsonb_array_length(segurando->'avisos') = 0
      and (segurando->>'voltaram')::int = 0 and v_sit_pendente = 'incluido'
      and (final->>'entregues')::int = 1 and jsonb_array_length(final->'avisos') = 0 and v_sit_final = 'entregue',
    'antes=' || jsonb_array_length(antes->'avisos') || ' na_hora=' || jsonb_array_length(na_hora->'avisos')
      || ' voltaram=' || (depois_falha->>'voltaram') || ' pendente=' || v_sit_pendente || ' final=' || v_sit_final);
end $$;

-- ═══ A11 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  h jsonb; e jsonb;
  manha jsonb; fecha jsonb;
begin
  -- domingo 07:00: 'hoje' → manhã de domingo 07:30; 'escritorio' → fechamento de segunda 17:30
  h := pg_temp._reg(v_p, '2026-10-25 07:00:00-03', 'a11:hoje', 'hoje');
  e := pg_temp._reg(v_p, '2026-10-25 07:00:00-03', 'a11:escritorio', 'escritorio');
  manha := pg_temp._para(v_p, 'manha', '2026-10-27 07:30:00-03');
  fecha := pg_temp._para(v_p, 'fechamento', '2026-10-27 17:30:00-03');
  insert into _resultado values ('A11 hoje só pela manhã; escritório só pelo fechamento',
    jsonb_array_length(manha->'avisos') = 1 and manha->'avisos'->0->>'destino' = 'hoje'
      and jsonb_array_length(fecha->'avisos') = 1 and fecha->'avisos'->0->>'destino' = 'escritorio',
    'manhã leva ' || coalesce(manha->'avisos'->0->>'destino', '-') || ' (' || jsonb_array_length(manha->'avisos')
      || '); fechamento leva ' || coalesce(fecha->'avisos'->0->>'destino', '-') || ' (' || jsonb_array_length(fecha->'avisos') || ')');
end $$;

-- ═══ A12 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  s jsonb; l jsonb; i1 jsonb; i2 jsonb; v_sit text;
begin
  s := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a12:sombra', 'proxima_fixa');
  l := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a12:ligado', 'proxima_fixa', null, false, 'ligado');
  i1 := public.avisos_incluir_na_mensagem(jsonb_build_object('phone', v_p, 'modo', 'sombra', 'ids', jsonb_build_array(s->>'id')));
  i2 := public.avisos_incluir_na_mensagem(jsonb_build_object('phone', v_p, 'modo', 'ligado', 'ids', jsonb_build_array(l->>'id')));
  select situacao into v_sit from public.avisos_do_dono where id = (s->>'id')::uuid;
  insert into _resultado values ('A12 sombra inclui sem fila (entregue na sombra); ligado sem fila é recusado',
    (i1->>'incluidos')::int = 1 and v_sit = 'entregue' and (i2->>'ok')::boolean = false
      and (select situacao from public.avisos_do_dono where id = (l->>'id')::uuid) = 'guardado',
    'sombra=' || v_sit || ' ligado ok=' || (i2->>'ok'));
end $$;

-- ═══ A13 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  g jsonb; r jsonb; m jsonb;
begin
  g := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a13:cliente', 'proxima_fixa');
  r := public.aviso_resolver(jsonb_build_object('phone', v_p, 'modo', 'sombra', 'ids', jsonb_build_array(g->>'id'), 'motivo', 'cliente_respondido'));
  m := pg_temp._para(v_p, 'fechamento', '2026-10-21 17:30:00-03');
  insert into _resultado values ('A13 o guardado resolvido some da mensagem fixa',
    (r->>'resolvidos')::int = 1 and jsonb_array_length(m->'avisos') = 0
      and (select situacao || '/' || motivo from public.avisos_do_dono where id = (g->>'id')::uuid) = 'resolvido/cliente_respondido',
    'resolvidos=' || (r->>'resolvidos') || ' na mensagem=' || jsonb_array_length(m->'avisos'));
end $$;

-- ═══ A14 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  v_quem uuid;
  v_papel text;
  v_viu integer;
  v_viram text := '';
  v_vazou boolean := false;
  v_admin uuid := pg_temp._usuario('admin');
  v_viu_admin integer;
begin
  perform pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a14:1', 'acorde');
  perform pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a14:2', 'proxima_fixa');
  begin
    foreach v_papel in array array['financial', 'technician'] loop
      v_quem := pg_temp._usuario(v_papel);
      perform set_config('request.jwt.claim.sub', v_quem::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_quem, 'role', 'authenticated')::text, true);
      set local role authenticated;
      select count(*) into v_viu from public.avisos_do_dono where phone_normalized = v_p;
      reset role;
      v_viram := v_viram || v_papel || ' vê ' || v_viu || '; ';
      v_vazou := v_vazou or v_viu <> 0;
    end loop;
    perform set_config('request.jwt.claim.sub', v_admin::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into v_viu_admin from public.avisos_do_dono where phone_normalized = v_p;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into _resultado values ('A14 só o admin lê os avisos', not v_vazou and v_viu_admin = 2,
      v_viram || 'admin vê ' || v_viu_admin);
  exception when others then
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into _resultado values ('A14 só o admin lê os avisos', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ A15 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_fin uuid := pg_temp._usuario('financial');
  v_admin uuid := pg_temp._usuario('admin');
  v_chave text;
  v_recusas integer := 0;
  v_admin_mudou boolean;
  v_padrao boolean;
begin
  v_padrao := (select value from public.app_settings where key = 'voz_unica') is not null
    and (select (value::jsonb->>'acordes_por_dia')::int from public.app_settings where key = 'voz_unica_regras') is not null
    and (select value from public.app_settings where key = 'acompanhar_freio') is not null;
  perform set_config('request.jwt.claim.sub', v_fin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_fin, 'role', 'authenticated')::text, true);
  foreach v_chave in array array['voz_unica', 'voz_unica_regras', 'acompanhar_freio'] loop
    begin
      update public.app_settings set value = value where key = v_chave;
    exception when insufficient_privilege then
      v_recusas := v_recusas + 1;
    end;
  end loop;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  update public.app_settings set value = 'sombra' where key = 'voz_unica';
  v_admin_mudou := (select value from public.app_settings where key = 'voz_unica') = 'sombra';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('A15 as 3 chaves existem; o financeiro não muda nenhuma (42501); o admin muda',
    v_padrao and v_recusas = 3 and v_admin_mudou,
    'existem=' || v_padrao || ' recusas=' || v_recusas || '/3 admin=' || v_admin_mudou || ' (desfeito no rollback)');
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('A15 as 3 chaves existem; o financeiro não muda nenhuma (42501); o admin muda', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ A16 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  v_antes text;
  a jsonb; b jsonb; s jsonb;
begin
  select value into v_antes from public.app_settings where key = 'voz_unica_regras';
  update public.app_settings set value = '{"acordes_por_dia":1,"sabado":"segunda"}' where key = 'voz_unica_regras';
  a := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a16:1', 'acorde', 'a16:1');
  b := pg_temp._reg(v_p, '2026-10-21 10:10:00-03', 'a16:2', 'acorde', 'a16:2');
  s := pg_temp._reg(v_p, '2026-10-24 18:00:00-03', 'a16:sabado', 'proxima_fixa');
  update public.app_settings set value = v_antes where key = 'voz_unica_regras';
  insert into _resultado values ('A16 regras do dono sem publicar código: 1 acorde por dia; excesso de sábado na segunda',
    a->>'decisao' = 'acordar' and b->>'decisao' = 'guardar' and b->>'motivo' = 'limite_do_dia' and (b->>'limite')::int = 1
      and (s->>'entregar_a_partir_de')::timestamptz = '2026-10-26 07:30:00-03'::timestamptz,
    a->>'decisao' || ', ' || (b->>'decisao') || '/' || coalesce(b->>'motivo', '-') || '; sábado → ' || coalesce(s->>'entregar_a_partir_de', '-'));
end $$;

-- ═══ A17 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  s1 jsonb; s2 jsonb; s3 jsonb; l1 jsonb; l2 jsonb;
begin
  s1 := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a17:1', 'acorde', 'a17:1');
  s2 := pg_temp._reg(v_p, '2026-10-21 10:01:00-03', 'a17:2', 'acorde', 'a17:2');
  s3 := pg_temp._reg(v_p, '2026-10-21 10:02:00-03', 'a17:3', 'acorde', 'a17:3');
  l1 := pg_temp._reg(v_p, '2026-10-21 10:03:00-03', 'a17:1', 'acorde', 'a17:1', false, 'ligado');
  l2 := pg_temp._reg(v_p, '2026-10-21 10:04:00-03', 'a17:2', 'acorde', 'a17:2', false, 'ligado');
  insert into _resultado values ('A17 sombra e ligado não se misturam (o limite e a chave são por modo)',
    s3->>'decisao' = 'guardar' and l1->>'decisao' = 'acordar' and l2->>'decisao' = 'acordar',
    'sombra 3º=' || (s3->>'decisao') || ' ligado 1º=' || (l1->>'decisao') || ' 2º=' || (l2->>'decisao'));
end $$;

-- ═══ A18 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_p text := pg_temp._fone();
  a jsonb; b jsonb; c jsonb; d jsonb;
begin
  a := public.aviso_registrar(jsonb_build_object('modo', 'sombra', 'fonte', 'teste_portao', 'chave', 'a18:1', 'destino', 'acorde'));
  b := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a18:2', 'gritar');
  c := pg_temp._reg(v_p, 'ontem', 'a18:3', 'acorde');
  d := pg_temp._reg(v_p, '2026-10-21 10:00:00-03', 'a18:4', 'acorde', null, false, 'alto');
  insert into _resultado values ('A18 entrada ruim volta ok=false e não grava',
    (a->>'ok')::boolean = false and (b->>'ok')::boolean = false and (c->>'ok')::boolean = false and (d->>'ok')::boolean = false
      and not exists (select 1 from public.avisos_do_dono where phone_normalized = v_p),
    'sem telefone=' || (a->>'ok') || ' destino=' || (b->>'ok') || ' agora=' || (c->>'ok') || ' modo=' || (d->>'ok'));
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
