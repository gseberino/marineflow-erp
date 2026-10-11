-- Prova: o registro único de pergunta ativa (migrations 20261011200000 e 20261011201000).
--
--   T1 anon/authenticated sem execute nas 5 RPCs do registro (service_role com) e nos helpers
--   T2 duas perguntas abertas no mesmo telefone violam o índice único
--   T3 pergunta_registrar_externa substitui a pergunta do comprovante; o CMP volta para
--      aguardando_vez com o passo (nada do que foi respondido se perde)
--   T4 conversa desligada: registrar_externa não grava e pergunta_ocupado só olha a pendência viva
--   T5 pergunta vencida vira expirada na limpeza (e o CMP volta para a fila)
--   T6 pergunta_rotear acha a citada pelo wa_message_id mesmo depois de fechada; encerrar_externa
--      fecha só as que não são de comprovante
--   (revisão de 11/10/2026)
--   T7 a pergunta do CMP que a pendência acabou de substituir (empate) e, sem ativa, a última dele
--   T8 pergunta_interromper: o texto livre foi ao assistente com a pergunta do CMP aberta
--   T9 a citação acha o reenvio da pergunta e a foto do comprovante
--   T10 lista de opções do assistente de 4 h+ não segura o telefone
--   T11 desligar a conversa devolve o CMP à F1 (lido, fora da fila, com as respostas)
--   T12 o comprovante que acabou de chegar (a dica do texto solto)
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado P3 da spec da F2; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/whatsapp_perguntas.sql --output json
--
-- Seguro em produção: cria um dono de teste (admin com created_at em 2000, que vira o
-- _comprovante_dono() só dentro da transação), liga a conversa só dentro da transação, usa telefones
-- de mentira 55000… e termina em ROLLBACK. Sem id fixo nem data fixa.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx (dono uuid, phone text) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._telefone() returns text language sql volatile as $$
  select '55000' || lpad((floor(random() * 1000000000))::bigint::text, 9, '0')
$$;

-- conversa ligada e um dono de teste (o primeiro admin por created_at)
do $$
declare
  v_dono uuid := gen_random_uuid();
  v_phone text := pg_temp._telefone();
begin
  insert into public.app_users (id, full_name, email, role, active, phone_normalized, ai_whatsapp_enabled, created_at)
  values (v_dono, 'Dono de teste F2', 'teste-f2-' || v_dono || '@teste.invalido', 'admin', true, v_phone, true,
          now() - interval '30 years');
  insert into public.app_settings (key, value) values ('comprovante_fluxo', 'dono')
  on conflict (key) do update set value = excluded.value;
  insert into public.app_settings (key, value) values ('comprovante_conversa', 'on')
  on conflict (key) do update set value = excluded.value;
  insert into _ctx values (v_dono, v_phone);
end $$;

create function pg_temp._dono() returns uuid language sql stable as $$ select dono from _ctx $$;
create function pg_temp._phone() returns text language sql stable as $$ select phone from _ctx $$;

create function pg_temp._conversa(p_on boolean) returns void language sql as $$
  update public.app_settings set value = case when p_on then 'on' else 'off' end where key = 'comprovante_conversa'
$$;

-- um CMP lido do dono de teste (direto na tabela: o caminho da F1 tem os próprios testes)
create function pg_temp._cmp(p_valor numeric default 62.00) returns uuid language plpgsql as $$
declare
  v uuid;
begin
  insert into public.comprovantes (numero, situacao, modo, rota, origem, dono_id, wa_message_id, phone_normalized,
                                   tipo_whatsapp, recebido_em, arquivo_sha256, tipo, confianca, valor, valor_confianca,
                                   data_compra, data_confianca, forma_pagamento, lido_em)
  values (public._comprovante_proximo_numero(), 'lido', 'dono', 'comprovante', 'webhook', pg_temp._dono(),
          'TESTE-F2-' || gen_random_uuid(), pg_temp._phone(), 'image', now(),
          md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text),
          'nfce', 'alta', p_valor, 'alta', (now() at time zone 'America/Sao_Paulo')::date, 'alta', null, now())
  returning id into v;
  return v;
end $$;

-- ═══ T1 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_f text;
  v_expostas text[] := '{}';
  v_sem_srv text[] := '{}';
  v_rpcs text[] := array[
    'public.pergunta_rotear(text, text)',
    'public.pergunta_interromper(text)',
    'public.pergunta_ocupado(text)',
    'public.pergunta_registrar_externa(jsonb)',
    'public.pergunta_marcar_enviada(uuid, text)',
    'public.pergunta_encerrar_externa(text, text)'];
  v_helpers text[] := array[
    'public._pendencia_viva_do_telefone(text)',
    'public._comprovante_pergunta_saiu(uuid)',
    'public._comprovante_sair_da_conversa(uuid)',
    'public._pergunta_fechar(uuid, text, text, uuid)',
    'public._pergunta_limpar(text)',
    'public._pergunta_abrir(jsonb)',
    'public._comprovante_conversa_ligada()'];
begin
  foreach v_f in array v_rpcs || v_helpers loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
      v_expostas := v_expostas || v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs loop
    if not has_function_privilege('service_role', v_f, 'execute') then
      v_sem_srv := v_sem_srv || v_f;
    end if;
  end loop;
  insert into _resultado values ('T1 registro: anon/authenticated sem execute; service_role nas RPCs',
    cardinality(v_expostas) = 0 and cardinality(v_sem_srv) = 0
    and not has_table_privilege('anon', 'public.whatsapp_perguntas', 'select')
    and not has_table_privilege('authenticated', 'public.whatsapp_perguntas', 'insert'),
    'expostas: ' || coalesce(array_to_string(v_expostas, ', '), '') || ' | sem service_role: ' || coalesce(array_to_string(v_sem_srv, ', '), ''));
exception when others then
  insert into _resultado values ('T1 registro: anon/authenticated sem execute; service_role nas RPCs', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T2 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_erro text := 'nenhum erro';
begin
  insert into public.whatsapp_perguntas (phone_normalized, origem, tipo, referencia_id, expira_em)
  values (v_phone, 'assistente', 'confirmacao', gen_random_uuid(), now() + interval '1 hour');
  begin
    insert into public.whatsapp_perguntas (phone_normalized, origem, tipo, referencia_id, expira_em)
    values (v_phone, 'lembrete_revisao', 'confirmacao', gen_random_uuid(), now() + interval '1 hour');
  exception when unique_violation then
    v_erro := sqlstate;
  end;
  -- fechada não conta: outra aberta entra
  update public.whatsapp_perguntas set status = 'respondida', fechada_em = now() where phone_normalized = v_phone;
  insert into public.whatsapp_perguntas (phone_normalized, origem, tipo, referencia_id, expira_em)
  values (v_phone, 'lembrete_revisao', 'confirmacao', gen_random_uuid(), now() + interval '1 hour');
  insert into _resultado values ('T2 duas abertas no mesmo telefone violam o índice único', v_erro = '23505',
    'segunda aberta: ' || v_erro || '; depois de fechar a 1ª, outra entra');
exception when others then
  insert into _resultado values ('T2 duas abertas no mesmo telefone violam o índice único', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T3 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_cmp uuid := pg_temp._cmp(70.10);
  v_p jsonb;
  v_pend uuid;
  v_r jsonb;
  v_linha record;
  v_velha record;
begin
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'pendentes', v_cmp);
  insert into public.ai_operator_pending_actions (action_name, title, payload, status, expires_at)
  values ('teste_f2', 'Lançar o almoço de teste', '{}'::jsonb, 'pending', now() + interval '1 hour')
  returning id into v_pend;
  v_r := public.pergunta_registrar_externa(jsonb_build_object(
    'phone', pg_temp._phone(), 'origem', 'assistente', 'tipo', 'confirmacao', 'referencia_id', v_pend,
    'titulo', 'Lançar o almoço de teste'));
  select situacao, passo into v_linha from public.comprovantes where id = v_cmp;
  select status, motivo into v_velha from public.whatsapp_perguntas where id = (v_p->>'pergunta_id')::uuid;
  insert into _resultado values ('T3 registrar_externa substitui a do CMP; o CMP volta com o passo',
    coalesce((v_p->>'perguntou')::boolean, false) and v_r->'substituiu'->>'origem' = 'comprovante'
    and v_velha.status = 'substituida' and v_velha.motivo = 'substituida_por:assistente'
    and v_linha.situacao = 'aguardando_vez' and v_linha.passo = v_p->>'passo'
    and (select count(*) from public.whatsapp_perguntas
          where phone_normalized = pg_temp._phone() and status = 'aberta' and origem = 'assistente' and referencia_id = v_pend) = 1,
    'perguntou=' || coalesce(v_p->>'perguntou', 'null') || ' passo=' || coalesce(v_p->>'passo', '-') || ' → ' || coalesce(v_linha.passo, '-')
    || ' situacao=' || v_linha.situacao || ' antiga=' || coalesce(v_velha.status, '-'));
  -- deixa o telefone livre para os próximos
  perform public.pergunta_encerrar_externa(pg_temp._phone(), 'respondida');
exception when others then
  insert into _resultado values ('T3 registrar_externa substitui a do CMP; o CMP volta com o passo', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T4 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_pend uuid;
  v_sess uuid;
  v_r jsonb;
  v_livre jsonb;
  v_ocup jsonb;
  v_antes integer;
begin
  perform pg_temp._conversa(false);
  select count(*) into v_antes from public.whatsapp_perguntas where phone_normalized = pg_temp._phone();
  insert into public.ai_operator_pending_actions (action_name, title, payload, status, expires_at)
  values ('teste_f2', 'Mandar o lembrete', '{}'::jsonb, 'pending', now() + interval '1 hour')
  returning id into v_pend;
  v_r := public.pergunta_registrar_externa(jsonb_build_object(
    'phone', pg_temp._phone(), 'origem', 'lembrete_revisao', 'tipo', 'confirmacao', 'referencia_id', v_pend, 'titulo', 'x'));
  -- uma aberta antiga não ocupa com a conversa desligada; só a pendência viva da sessão ocupa
  insert into public.whatsapp_perguntas (phone_normalized, origem, tipo, referencia_id, expira_em)
  values (pg_temp._phone(), 'acompanhar_conversa', 'confirmacao', v_pend, now() + interval '1 hour');
  v_livre := public.pergunta_ocupado(pg_temp._phone());
  insert into public.ai_operator_sessions (channel, external_thread_key, status, metadata, last_activity_at)
  values ('whatsapp', pg_temp._phone(), 'open', jsonb_build_object('pending_confirm_action_id', v_pend), now())
  returning id into v_sess;
  v_ocup := public.pergunta_ocupado(pg_temp._phone());
  insert into _resultado values ('T4 desligada: registrar não grava; ocupado só pela pendência viva',
    v_r->>'id' is null and (v_r->>'desligada')::boolean
    and (select count(*) from public.whatsapp_perguntas where phone_normalized = pg_temp._phone()) = v_antes + 1
    and (v_livre->>'ocupado')::boolean = false
    and (v_ocup->>'ocupado')::boolean = true and v_ocup->'por'->>'titulo' = 'Mandar o lembrete',
    'registrar=' || v_r::text || ' livre=' || v_livre::text || ' ocupado=' || v_ocup::text);
  delete from public.whatsapp_perguntas where phone_normalized = pg_temp._phone() and origem = 'acompanhar_conversa';
  delete from public.ai_operator_sessions where id = v_sess;
  perform pg_temp._conversa(true);
exception when others then
  insert into _resultado values ('T4 desligada: registrar não grava; ocupado só pela pendência viva', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T5 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_cmp uuid := pg_temp._cmp(81.30);
  v_p jsonb;
  v_rot jsonb;
  v_status text;
  v_sit text;
begin
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'pendentes', v_cmp);
  update public.whatsapp_perguntas set expira_em = now() - interval '1 minute' where id = (v_p->>'pergunta_id')::uuid;
  v_rot := public.pergunta_rotear(pg_temp._phone(), null);
  select status into v_status from public.whatsapp_perguntas where id = (v_p->>'pergunta_id')::uuid;
  select situacao into v_sit from public.comprovantes where id = v_cmp;
  insert into _resultado values ('T5 vencida vira expirada na limpeza; o CMP volta para a fila',
    coalesce((v_p->>'perguntou')::boolean, false) and v_status = 'expirada' and v_rot->'ativa' = 'null'::jsonb
    and v_sit = 'aguardando_vez' and (v_rot->>'conversa')::boolean,
    'status=' || coalesce(v_status, '-') || ' situacao=' || coalesce(v_sit, '-') || ' ativa=' || coalesce(v_rot->>'ativa', 'null'));
exception when others then
  insert into _resultado values ('T5 vencida vira expirada na limpeza; o CMP volta para a fila', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T6 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_cmp uuid := pg_temp._cmp(93.70);
  v_p jsonb;
  v_wa text := 'WA-TESTE-' || gen_random_uuid();
  v_rot jsonb;
  v_rot_aberta jsonb;
  v_pend uuid;
  v_n integer;
  v_fora jsonb;
begin
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_cmp);
  perform public.pergunta_marcar_enviada((v_p->>'pergunta_id')::uuid, v_wa);
  v_rot_aberta := public.pergunta_rotear(pg_temp._phone(), v_wa);
  perform public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'pular'));
  v_rot := public.pergunta_rotear(pg_temp._phone(), v_wa);
  -- de outro telefone (não é o dono): nada além de conversa=false
  v_fora := public.pergunta_rotear(pg_temp._telefone(), v_wa);
  -- encerrar_externa: fecha a do assistente, nunca a do comprovante
  perform public.comprovante_proxima_pergunta(pg_temp._phone(), 'pendentes', null);
  update public.whatsapp_perguntas set status = 'respondida', fechada_em = now()
   where phone_normalized = pg_temp._phone() and status = 'aberta';
  insert into public.ai_operator_pending_actions (action_name, title, payload, status, expires_at)
  values ('teste_f2', 'Outra coisa', '{}'::jsonb, 'pending', now() + interval '1 hour') returning id into v_pend;
  perform public.pergunta_registrar_externa(jsonb_build_object(
    'phone', pg_temp._phone(), 'origem', 'assistente', 'tipo', 'confirmacao', 'referencia_id', v_pend, 'titulo', 'Outra coisa'));
  v_n := public.pergunta_encerrar_externa(pg_temp._phone(), 'respondida');
  insert into _resultado values ('T6 citada achada pelo wa_message_id (aberta e fechada); encerrar_externa só fecha as externas',
    v_rot_aberta->'citada'->>'status' = 'aberta' and v_rot_aberta->'ativa'->>'wa_message_id' = v_wa
    and v_rot->'citada'->>'status' = 'cancelada' and v_rot->'citada'->>'origem' = 'comprovante'
    and v_rot->'citada'->>'referencia_id' = v_cmp::text
    and (v_fora->>'conversa')::boolean = false and (v_fora->>'dono')::boolean = false and not (v_fora ? 'citada')
    and v_n = 1,
    'citada aberta=' || coalesce(v_rot_aberta->'citada'->>'status', '-') || ' depois=' || coalesce(v_rot->'citada'->>'status', '-')
    || ' fora=' || v_fora::text || ' encerradas=' || v_n);
exception when others then
  insert into _resultado values ('T6 citada achada pelo wa_message_id (aberta e fechada); encerrar_externa só fecha as externas', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T7 (revisão de 11/10/2026): a pergunta do CMP que a pendência do assistente acabou de substituir ═══
do $$
declare
  v_cmp uuid := pg_temp._cmp(104.20);
  v_p jsonb;
  v_pend uuid;
  v_rot jsonb;
  v_rot_depois jsonb;
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now() where phone_normalized = pg_temp._phone() and status = 'aberta';
  -- tudo aqui roda numa transação (o mesmo now()): as perguntas dos testes anteriores ficam para trás
  update public.whatsapp_perguntas set aberta_em = aberta_em - interval '1 hour', fechada_em = fechada_em - interval '1 hour'
   where phone_normalized = pg_temp._phone();
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_cmp);
  insert into public.ai_operator_pending_actions (action_name, title, payload, status, expires_at)
  values ('teste_f2', 'Mandar o orçamento', '{}'::jsonb, 'pending', now() + interval '1 hour') returning id into v_pend;
  perform public.pergunta_registrar_externa(jsonb_build_object(
    'phone', pg_temp._phone(), 'origem', 'assistente', 'tipo', 'confirmacao', 'referencia_id', v_pend, 'titulo', 'Mandar o orçamento'));
  -- a ativa agora é do assistente; a do CMP (aberta a menos de 2 min dela) volta como empate
  v_rot := public.pergunta_rotear(pg_temp._phone(), null);
  -- respondida a pendência, a pergunta do CMP fica como "a última, substituída" (resposta atrasada vai a ela)
  perform public.pergunta_encerrar_externa(pg_temp._phone(), 'respondida');
  v_rot_depois := public.pergunta_rotear(pg_temp._phone(), null);
  insert into _resultado values ('T7 rotear: a pergunta do CMP substituída há menos de 2 min (empate) e, sem ativa, a última dele',
    v_rot->'ativa'->>'origem' = 'assistente' and v_rot->'cmp_substituido'->>'id' = v_p->>'pergunta_id'
    and v_rot->'cmp_substituido'->>'referencia_codigo' = (select codigo from public.comprovantes where id = v_cmp)
    and v_rot_depois->'ativa' = 'null'::jsonb and v_rot_depois->'ultima_do_cmp'->>'id' = v_p->>'pergunta_id'
    and v_rot_depois->'ultima_do_cmp'->>'passo' = v_p->>'passo',
    'substituido=' || coalesce(v_rot->'cmp_substituido'->>'id', '-') || ' ultima=' || coalesce(v_rot_depois->'ultima_do_cmp'->>'passo', '-'));
exception when others then
  insert into _resultado values ('T7 rotear: a pergunta do CMP substituída há menos de 2 min (empate) e, sem ativa, a última dele', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T8: o texto livre foi ao assistente — a pergunta do CMP fica "interrompida" ═══════════════
do $$
declare
  v_cmp uuid := pg_temp._cmp(115.40);
  v_p jsonb;
  v_1 boolean;
  v_2 boolean;
  v_rot jsonb;
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now() where phone_normalized = pg_temp._phone() and status = 'aberta';
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_cmp);
  v_1 := public.pergunta_interromper(pg_temp._phone());
  v_2 := public.pergunta_interromper(pg_temp._phone());
  v_rot := public.pergunta_rotear(pg_temp._phone(), null);
  insert into _resultado values ('T8 pergunta_interromper marca a pergunta aberta do CMP (uma vez) e o rotear mostra',
    v_1 and not v_2 and v_rot->'ativa'->>'id' = v_p->>'pergunta_id' and v_rot->'ativa'->>'interrompida_em' is not null
    and not public.pergunta_interromper(pg_temp._telefone()),
    'primeira=' || v_1 || ' segunda=' || v_2 || ' interrompida=' || coalesce(v_rot->'ativa'->>'interrompida_em', '-'));
exception when others then
  insert into _resultado values ('T8 pergunta_interromper marca a pergunta aberta do CMP (uma vez) e o rotear mostra', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T9: a citação acha o reenvio da pergunta e a FOTO do comprovante ═══════════════════════════
do $$
declare
  v_cmp uuid := pg_temp._cmp(126.60);
  v_p jsonb;
  v_wa1 text := 'WA-1-' || gen_random_uuid();
  v_wa2 text := 'WA-2-' || gen_random_uuid();
  v_rot jsonb;
  v_foto jsonb;
  v_enviada timestamptz;
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now() where phone_normalized = pg_temp._phone() and status = 'aberta';
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_cmp);
  perform public.pergunta_marcar_enviada((v_p->>'pergunta_id')::uuid, v_wa1);
  perform public.pergunta_marcar_enviada((v_p->>'pergunta_id')::uuid, v_wa2);
  select enviada_em into v_enviada from public.whatsapp_perguntas where id = (v_p->>'pergunta_id')::uuid;
  v_rot := public.pergunta_rotear(pg_temp._phone(), v_wa2);
  v_foto := public.pergunta_rotear(pg_temp._phone(), (select wa_message_id from public.comprovantes where id = v_cmp));
  insert into _resultado values ('T9 citação: o reenvio da pergunta (wa_message_ids) e a foto do CMP (citado_cmp)',
    v_rot->'citada'->>'id' = v_p->>'pergunta_id' and v_enviada is not null
    and v_foto->'citada' = 'null'::jsonb and v_foto->'citado_cmp'->>'id' = v_cmp::text
    and (v_foto->'citado_cmp'->>'gravado')::boolean = false,
    'reenvio=' || coalesce(v_rot->'citada'->>'id' = v_p->>'pergunta_id', false) || ' foto=' || coalesce(v_foto->'citado_cmp'->>'codigo', '-'));
exception when others then
  insert into _resultado values ('T9 citação: o reenvio da pergunta (wa_message_ids) e a foto do CMP (citado_cmp)', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T10: lista de opções velha (4 h+) não segura o telefone ═══════════════════════════════════
do $$
declare
  v_sess uuid;
  v_velha jsonb;
  v_nova jsonb;
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now() where phone_normalized = pg_temp._phone() and status = 'aberta';
  insert into public.ai_operator_sessions (channel, external_thread_key, status, metadata, last_activity_at)
  values ('whatsapp', pg_temp._phone(), 'open', '{"pending_options":[{"n":1,"label":"x"}]}'::jsonb, now() - interval '5 hours')
  returning id into v_sess;
  v_velha := public.pergunta_ocupado(pg_temp._phone());
  update public.ai_operator_sessions set last_activity_at = now() - interval '1 hour' where id = v_sess;
  v_nova := public.pergunta_ocupado(pg_temp._phone());
  delete from public.ai_operator_sessions where id = v_sess;
  insert into _resultado values ('T10 opções do assistente de 5 h atrás não ocupam; de 1 h ocupam',
    (v_velha->>'ocupado')::boolean = false and (v_nova->>'ocupado')::boolean = true,
    'velha=' || v_velha::text || ' nova=' || v_nova::text);
exception when others then
  insert into _resultado values ('T10 opções do assistente de 5 h atrás não ocupam; de 1 h ocupam', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T11: desligar a conversa devolve o CMP à F1 (lido, fora da fila, com as respostas) ═════════
do $$
declare
  v_cmp uuid := pg_temp._cmp(137.80);
  v_p jsonb;
  v_w record;
  c record;
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now() where phone_normalized = pg_temp._phone() and status = 'aberta';
  perform public.comprovante_conversa_entrar(array[v_cmp]);
  update public.comprovantes set destino = 'empresa' where id = v_cmp;
  v_p := public.comprovante_proxima_pergunta(pg_temp._phone(), 'cmp', v_cmp);
  perform pg_temp._conversa(false);
  perform public._comprovantes_manutencao();
  select status, motivo into v_w from public.whatsapp_perguntas where id = (v_p->>'pergunta_id')::uuid;
  select situacao, fila_desde, destino into c from public.comprovantes where id = v_cmp;
  perform pg_temp._conversa(true);
  insert into _resultado values ('T11 conversa desligada: a pergunta fecha e o CMP volta a lido, fora da fila, com as respostas',
    v_w.status = 'cancelada' and v_w.motivo = 'conversa_desligada'
    and c.situacao = 'lido' and c.fila_desde is null and c.destino = 'empresa'
    -- religada: o "cmp N" o traz de volta (as respostas ficam)
    and (public.comprovante_comando(jsonb_build_object('phone', pg_temp._phone(), 'comando', 'cmp',
           'numero', (select numero from public.comprovantes where id = v_cmp)))->>'resultado') = 'pergunta'
    and (select destino from public.comprovantes where id = v_cmp) = 'empresa',
    'pergunta=' || coalesce(v_w.status, '-') || '/' || coalesce(v_w.motivo, '-') || ' cmp=' || coalesce(c.situacao, '-'));
exception when others then
  perform pg_temp._conversa(true);
  insert into _resultado values ('T11 conversa desligada: a pergunta fecha e o CMP volta a lido, fora da fila, com as respostas', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T12: o comprovante que acabou de chegar (para a dica do texto solto) ══════════════════════
do $$
declare
  v_cmp uuid := pg_temp._cmp(148.90);
  v_rot jsonb;
begin
  update public.whatsapp_perguntas set status = 'cancelada', fechada_em = now() where phone_normalized = pg_temp._phone() and status = 'aberta';
  update public.comprovantes set ultima_pergunta_em = now() where phone_normalized = pg_temp._phone() and id <> v_cmp;
  v_rot := public.pergunta_rotear(pg_temp._phone(), null);
  insert into _resultado values ('T12 rotear: o CMP que chegou há menos de 2 min e ainda não foi perguntado (cmp_chegando)',
    v_rot->'cmp_chegando'->>'id' = v_cmp::text,
    'chegando=' || coalesce(v_rot->'cmp_chegando'->>'codigo', '-'));
exception when others then
  insert into _resultado values ('T12 rotear: o CMP que chegou há menos de 2 min e ainda não foi perguntado (cmp_chegando)', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
