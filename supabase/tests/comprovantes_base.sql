-- Prova: base dos comprovantes da F1 (migrations 20261011100000 a 20261011103000).
--
--   T1 anon/authenticated sem execute em cada RPC e helper; service_role com execute nas 15 RPCs
--   T2 anon não lê comprovantes (nem a numeração)
--   T3 financeiro e técnico ATIVOS (criados na transação) veem 0 linhas; o admin vê
--   T4 numeração sem buraco depois de um rollback parcial (savepoint)
--   T5 codigo de 99999 = CMP-99999 e de 100000 = CMP-100000 (sem cortar)
--   T6 a mesma wa_message_id devolve novo=false; recusas: dono que não é admin, outro admin que não
--      é o dono, modo inválido, mensagem que não confere, key de outro telefone/fromMe; a key boa
--      é guardada só com as chaves do download
--   T7 o mesmo sha de um CMP vivo → duplicado, apagar_arquivo_agora
--   T8 legenda-chave numera em guardar_arquivo; o job sai no contrato v1
--   T9 o CHECK de nao_comprovante recusa linha com valor (e com texto do dono depois de apagado)
--   T9b só o admin muda app_settings.comprovante_fluxo (o financeiro recebe 42501)
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado P10 da spec; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/comprovantes_base.sql --output json
--
-- Seguro em produção: cria os próprios dados (mensagens e comprovantes de mentira, telefones
-- 55000…) dentro da transação e termina em ROLLBACK. Busca o admin, sem id fixo. O gatilho de
-- ai_jobs enfileira net.http_post só dentro da transação (o rollback desfaz a fila do pg_net).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._dono() returns uuid language sql stable as $$
  select coalesce(
    (select d.id from public._comprovante_dono() d),
    (select u.id from public.app_users u where u.role = 'admin' and u.active order by u.created_at limit 1))
$$;

create function pg_temp._telefone() returns text language sql volatile as $$
  select '55000' || lpad((floor(random() * 1000000000))::bigint::text, 9, '0')
$$;

create function pg_temp._sha() returns text language sql volatile as $$
  select md5(random()::text || clock_timestamp()::text) || md5(clock_timestamp()::text || random()::text)
$$;

-- um usuário ativo de mentira com o cargo dado (some no rollback); devolve o id
create function pg_temp._usuario(p_role text) returns uuid language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active, created_at)
  values (v_id, 'Teste ' || p_role, 'teste-' || v_id || '@teste.invalido', p_role, true, now());
  return v_id;
end $$;

-- mensagem do WhatsApp + comprovante_receber; devolve a saída da RPC
create function pg_temp._receber(
  p_modo text default 'dono', p_rota text default 'comprovante', p_origem text default 'webhook',
  p_forcado boolean default false, p_legenda text default null, p_phone text default null,
  p_recebido timestamptz default now(), p_wa text default null, p_dono uuid default null,
  p_key jsonb default null
) returns jsonb language plpgsql as $$
declare
  v_wa text := coalesce(p_wa, 'TESTE-' || gen_random_uuid());
  v_phone text := coalesce(p_phone, pg_temp._telefone());
  v_msg uuid;
begin
  select m.id into v_msg from public.whatsapp_messages m where m.wa_message_id = v_wa;
  if v_msg is null then
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
    values ('inbound', v_phone, 'image', coalesce(p_legenda, '[image]'), v_wa, p_recebido)
    returning id into v_msg;
  end if;
  return public.comprovante_receber(jsonb_build_object(
    'message_id', v_msg, 'wa_message_id', v_wa, 'phone_normalized', v_phone,
    'dono_id', coalesce(p_dono, pg_temp._dono()), 'modo', p_modo, 'rota', p_rota, 'origem', p_origem,
    'tipo_whatsapp', 'image', 'forcado', p_forcado, 'legenda', p_legenda, 'dica_da_legenda', null,
    'nome_arquivo', null, 'mime_declarado', 'image/jpeg', 'recebido_em', p_recebido, 'wa_key', p_key));
end $$;

create function pg_temp._chegada(
  p_modo text default 'dono', p_rota text default 'comprovante', p_origem text default 'webhook',
  p_forcado boolean default false, p_legenda text default null, p_phone text default null,
  p_recebido timestamptz default now()
) returns uuid language sql as $$
  select (pg_temp._receber(p_modo, p_rota, p_origem, p_forcado, p_legenda, p_phone, p_recebido)->>'id')::uuid
$$;

create function pg_temp._caminho(p_id uuid, p_ext text default 'jpg') returns text language sql stable as $$
  select to_char(now() at time zone 'America/Sao_Paulo', 'YYYY/MM') || '/' || p_id || '.' || p_ext
$$;

create function pg_temp._url(p_id uuid, p_ext text default 'jpg') returns text language sql stable as $$
  select 'https://teste.supabase.co/storage/v1/object/sign/comprovantes/' || pg_temp._caminho(p_id, p_ext) || '?token=teste'
$$;

create function pg_temp._guardar(p_id uuid, p_sha text default null, p_ext text default 'jpg', p_mime text default 'image/jpeg')
returns jsonb language sql as $$
  select public.comprovante_guardar_arquivo(
    p_id,
    jsonb_build_object('path', pg_temp._caminho(p_id, p_ext), 'mime_real', p_mime, 'bytes', 1234,
                       'sha256', coalesce(p_sha, pg_temp._sha())),
    pg_temp._url(p_id, p_ext))
$$;

-- ═══ T1 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_f text;
  v_expostas text[] := '{}';
  v_sem_srv text[] := '{}';
  v_rpcs text[] := array[
    'public.comprovante_receber(jsonb)',
    'public.comprovante_guardar_arquivo(uuid, jsonb, text)',
    'public.comprovante_download_falhou(uuid, text)',
    'public.comprovante_pedir_leitura(uuid, text)',
    'public.comprovante_aplicar_leitura(uuid)',
    'public.comprovante_falhou(uuid, text)',
    'public.comprovante_reservar_aviso(text, boolean)',
    'public.comprovante_no_dropbox(uuid, text, text, text)',
    'public.comprovante_dropbox_falhou(uuid, text)',
    'public.comprovante_arquivo_apagado(uuid)',
    'public.comprovantes_vigia_lote(integer)',
    'public.comprovantes_relatorio_sombra(timestamptz)',
    'public.comprovante_entrega_falhou(uuid)',
    'public.comprovante_aviso_falhou(uuid[])',
    'public.comprovante_ja_encaminhado(uuid)'];
  v_helpers text[] := array[
    'public._comprovantes_manutencao()',
    'public._app_settings_chaves_do_dono()',
    'public._comprovante_proximo_numero()',
    'public._comprovante_e_compra(text, text, boolean)',
    'public._comprovante_mascarar_cpf(text)',
    'public._comprovante_dono()',
    'public._comprovante_dados_do_arquivo(public.comprovantes)',
    'public._comprovante_criar_job(uuid, text, smallint)',
    'public._comprovante_encaminhar(uuid)',
    'public._ai_jobs_comprovante_lido()',
    'public._comprovantes_vigia_tem_trabalho()'];
begin
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
    insert into _resultado values ('T1 execute só para service_role',
      cardinality(v_expostas) = 0 and cardinality(v_sem_srv) = 0,
      case when cardinality(v_expostas) = 0 and cardinality(v_sem_srv) = 0
           then cardinality(v_rpcs || v_helpers) || ' funções conferidas'
           else 'expostas: ' || array_to_string(v_expostas, ', ') || ' | sem service_role: ' || array_to_string(v_sem_srv, ', ') end);
  exception when others then
    insert into _resultado values ('T1 execute só para service_role', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T2 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_leu text[] := '{}';
  v_t text;
begin
  foreach v_t in array array['comprovantes', 'comprovantes_numeracao'] loop
    begin
      set local role anon;
      execute format('select count(*) from public.%I', v_t);
      reset role;
      v_leu := v_leu || ('anon lê ' || v_t);
    exception when insufficient_privilege then
      null;
    end;
    reset role;
  end loop;
  begin
    set local role anon;
    insert into public.comprovantes (modo, rota, dono_id, wa_message_id, phone_normalized, tipo_whatsapp, recebido_em)
    values ('dono', 'comprovante', gen_random_uuid(), 'TESTE-anon', '5500000000000', 'image', now());
    reset role;
    v_leu := v_leu || 'anon insere em comprovantes'::text;
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  begin
    set local role authenticated;
    perform count(*) from public.comprovantes_numeracao;
    reset role;
    v_leu := v_leu || 'authenticated lê a numeração'::text;
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  insert into _resultado values ('T2 anon não lê nem escreve; numeração fechada', cardinality(v_leu) = 0,
    coalesce(nullif(array_to_string(v_leu, ', '), ''), 'recusado com 42501'));
end $$;

-- ═══ T3 ═══════════════════════════════════════════════════════════════════════════════════════
-- Usuários de verdade (ativos, com cargo em app_users), criados na transação: uma troca por engano
-- de is_admin por is_admin_or_financial na policy faz o financeiro ver a linha e o teste falhar.
do $$
declare
  v_id uuid;
  v_dono uuid := pg_temp._dono();
  v_quem uuid;
  v_papel text;
  v_viu integer;
  v_viram text := '';
  v_vazou boolean := false;
  v_viu_dono integer;
begin
  begin
    v_id := pg_temp._chegada();
    foreach v_papel in array array['financial', 'technician'] loop
      v_quem := pg_temp._usuario(v_papel);
      perform set_config('request.jwt.claim.sub', v_quem::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_quem, 'role', 'authenticated')::text, true);
      set local role authenticated;
      select count(*) into v_viu from public.comprovantes;
      reset role;
      v_viram := v_viram || v_papel || ' vê ' || v_viu || '; ';
      v_vazou := v_vazou or v_viu <> 0;
    end loop;
    perform set_config('request.jwt.claim.sub', v_dono::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_dono, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into v_viu_dono from public.comprovantes where id = v_id;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into _resultado values ('T3 só o admin lê', not v_vazou and v_viu_dono = 1,
      v_viram || 'admin vê a linha de teste: ' || v_viu_dono);
  exception when others then
    reset role;
    insert into _resultado values ('T3 só o admin lê', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T4 ═══════════════════════════════════════════════════════════════════════════════════════
-- O bloco BEGIN … EXCEPTION do plpgsql é um savepoint: o número tirado dentro dele volta no rollback.
do $$
declare
  v_a integer;
  v_b integer;
  v_desfeito integer;
begin
  begin
    v_a := public._comprovante_proximo_numero();
    begin
      v_desfeito := public._comprovante_proximo_numero();
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      null;
    end;
    v_b := public._comprovante_proximo_numero();
    insert into _resultado values ('T4 numeração sem buraco', v_b = v_a + 1 and v_desfeito = v_a + 1,
      v_a || ' → (' || v_desfeito || ' desfeito) → ' || v_b);
  exception when others then
    insert into _resultado values ('T4 numeração sem buraco', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T5 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_a text;
  v_b text;
begin
  begin
    insert into public.comprovantes (numero, modo, rota, dono_id, wa_message_id, phone_normalized, tipo_whatsapp,
                                     recebido_em, arquivo_sha256)
    values (99999, 'dono', 'comprovante', pg_temp._dono(), 'TESTE-' || gen_random_uuid(), pg_temp._telefone(), 'image',
            now(), pg_temp._sha())
    returning codigo into v_a;
    insert into public.comprovantes (numero, modo, rota, dono_id, wa_message_id, phone_normalized, tipo_whatsapp,
                                     recebido_em, arquivo_sha256)
    values (100000, 'dono', 'comprovante', pg_temp._dono(), 'TESTE-' || gen_random_uuid(), pg_temp._telefone(), 'image',
            now(), pg_temp._sha())
    returning codigo into v_b;
    insert into _resultado values ('T5 codigo sem cortar depois de 99999', v_a = 'CMP-99999' and v_b = 'CMP-100000', v_a || ', ' || v_b);
  exception when others then
    insert into _resultado values ('T5 codigo sem cortar depois de 99999', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T6 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_wa text := 'TESTE-' || gen_random_uuid();
  v_phone text := pg_temp._telefone();
  v_1 jsonb;
  v_2 jsonb;
  v_nao_admin text := 'nenhum erro';
  v_outro_admin text := 'nenhum erro';
  v_modo_ruim text := 'nenhum erro';
  v_msg_errada text := 'nenhum erro';
  v_key_alheia text := 'nenhum erro';
  v_key_minha text := 'nenhum erro';
  v_wa_k text := 'TESTE-' || gen_random_uuid();
  v_k jsonb;
  v_guardada jsonb;
  v_m uuid;
begin
  begin
    v_1 := pg_temp._receber(p_wa => v_wa, p_phone => v_phone);
    v_2 := pg_temp._receber(p_wa => v_wa, p_phone => v_phone);
    begin
      perform pg_temp._receber(p_dono => gen_random_uuid());
    exception when others then
      v_nao_admin := sqlstate;
    end;
    begin
      perform pg_temp._receber(p_dono => pg_temp._usuario('admin'));   -- admin, mas não é o dono
    exception when others then
      v_outro_admin := sqlstate;
    end;
    begin
      perform pg_temp._receber(p_modo => 'off');
    exception when others then
      v_modo_ruim := sqlstate;
    end;
    -- a mensagem é de outro telefone (ou foi ENVIADA): não abre linha
    begin
      insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id)
      values ('outbound', v_phone, 'image', '[image]', 'TESTE-' || gen_random_uuid())
      returning id into v_m;
      perform public.comprovante_receber(jsonb_build_object(
        'message_id', v_m, 'wa_message_id', (select wa_message_id from public.whatsapp_messages where id = v_m),
        'phone_normalized', v_phone, 'dono_id', pg_temp._dono(), 'modo', 'dono', 'rota', 'comprovante',
        'origem', 'webhook', 'tipo_whatsapp', 'image', 'forcado', false, 'legenda', null, 'dica_da_legenda', null,
        'nome_arquivo', null, 'mime_declarado', null, 'recebido_em', now()));
    exception when others then
      v_msg_errada := sqlstate;
    end;
    -- key de OUTRA conversa (outro telefone) e key enviada pelo sistema (fromMe)
    begin
      perform pg_temp._receber(p_phone => v_phone, p_wa => v_wa_k || '-alheia',
        p_key => jsonb_build_object('id', v_wa_k || '-alheia', 'remoteJid', '5511988887777@s.whatsapp.net', 'fromMe', false));
    exception when others then
      v_key_alheia := sqlstate;
    end;
    begin
      perform pg_temp._receber(p_phone => v_phone, p_wa => v_wa_k || '-fm',
        p_key => jsonb_build_object('id', v_wa_k || '-fm', 'remoteJid', v_phone || '@s.whatsapp.net', 'fromMe', true));
    exception when others then
      v_key_minha := sqlstate;
    end;
    v_k := pg_temp._receber(p_phone => v_phone, p_wa => v_wa_k,
      p_key => jsonb_build_object('id', v_wa_k, 'remoteJid', v_phone || '@s.whatsapp.net', 'fromMe', false,
                                  'remoteJidAlt', '123@lid', 'participant', 'lixo', 'qualquer', 'coisa'));
    select wa_key into v_guardada from public.comprovantes where id = (v_k->>'id')::uuid;
    insert into _resultado values ('T6 receber idempotente e recusas',
      (v_1->>'novo')::boolean and not (v_2->>'novo')::boolean and v_1->>'id' = v_2->>'id'
      and v_1->>'situacao' = 'recebido' and v_nao_admin = '42501' and v_outro_admin = '42501'
      and v_modo_ruim = '22023' and v_msg_errada = '22023' and v_key_alheia = '22023' and v_key_minha = '22023'
      and v_guardada = jsonb_build_object('id', v_wa_k, 'remoteJid', v_phone || '@s.whatsapp.net', 'fromMe', false,
                                          'remoteJidAlt', '123@lid'),
      'novo ' || (v_1->>'novo') || ' → ' || (v_2->>'novo') || '; dono não admin ' || v_nao_admin
      || '; outro admin ' || v_outro_admin || '; modo off ' || v_modo_ruim || '; mensagem enviada ' || v_msg_errada
      || '; key alheia ' || v_key_alheia || '; key fromMe ' || v_key_minha || '; guardada ' || coalesce(v_guardada::text, '-'));
  exception when others then
    insert into _resultado values ('T6 receber idempotente e recusas', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T7 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_sha text := pg_temp._sha();
  v_a uuid;
  v_b uuid;
  v_ga jsonb;
  v_gb jsonb;
  b public.comprovantes;
begin
  begin
    v_a := pg_temp._chegada(p_forcado => true, p_legenda => 'cupom');
    v_ga := pg_temp._guardar(v_a, v_sha);                 -- vira CMP na chegada
    v_b := pg_temp._chegada();
    v_gb := pg_temp._guardar(v_b, v_sha);
    select * into b from public.comprovantes where id = v_b;
    insert into _resultado values ('T7 mesmo arquivo de um CMP vivo = duplicado',
      v_gb->>'decisao' = 'duplicado' and (v_gb->>'apagar_arquivo_agora')::boolean
      and v_gb->'duplicado'->>'codigo' = v_ga->>'codigo' and v_gb->>'job_id' is null
      and b.situacao = 'cancelado' and b.motivo_cancelamento = 'arquivo_repetido' and b.duplicado_de = v_a
      and b.arquivo_apagar_apos <= now() and b.numero is null,
      (v_gb->>'decisao') || ' de ' || coalesce(v_gb->'duplicado'->>'codigo', '?') || '; situacao ' || b.situacao);
  exception when others then
    insert into _resultado values ('T7 mesmo arquivo de um CMP vivo = duplicado', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T8 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_f uuid;
  v_n uuid;
  v_gf jsonb;
  v_gn jsonb;
  jf public.ai_jobs;
  jn public.ai_jobs;
  f public.comprovantes;
  n public.comprovantes;
  v_ok boolean;
begin
  begin
    v_f := pg_temp._chegada(p_forcado => true, p_legenda => 'cupom');
    v_gf := pg_temp._guardar(v_f);
    v_n := pg_temp._chegada(p_modo => 'dono', p_rota => 'ambos', p_legenda => 'lança na OS do Brisa');
    v_gn := pg_temp._guardar(v_n);
    select * into f from public.comprovantes where id = v_f;
    select * into n from public.comprovantes where id = v_n;
    select * into jf from public.ai_jobs where id = (v_gf->>'job_id')::uuid;
    select * into jn from public.ai_jobs where id = (v_gn->>'job_id')::uuid;
    v_ok := v_gf->>'decisao' = 'na_fila' and f.numero is not null and f.codigo = v_gf->>'codigo' and f.situacao = 'na_fila'
      and n.numero is null and v_gn->>'codigo' is null
      and jf.provider = 'local-doc' and jf.model = 'leitor-v1' and jf.task_profile = 'comprovante'
      and jf.response_format = 'json' and jf.prompt = 'ler_comprovante' and jf.source = 'marineflow'
      and jf.requested_by = f.dono_id and jf.timeout_seconds = 180 and jf.max_attempts = 2 and not jf.allow_fallback
      and jf.deadline_at between now() + interval '23 hours 59 minutes' and now() + interval '24 hours 1 minute'
      and jf.priority = 40 and jn.priority = 30
      and jf.metadata->>'tipo' = 'comprovante_leitura' and jf.metadata->>'tentativa' = '1'
      and jf.metadata->>'comprovante_id' = v_f::text
      and jf.input->>'modo' = 'completo' and jn.input->>'modo' = 'triagem'
      and jf.input->'arquivo'->>'sha256' = f.arquivo_sha256 and jf.input->'origem'->>'forcado' = 'true'
      and jf.input::text not like '%cupom%' and jf.input::text not like '%' || f.phone_normalized || '%'
      and n.encaminhamento = 'chegada' and n.encaminhado_ao_assistente_em is not null;
    insert into _resultado values ('T8 legenda-chave numera na chegada; job no contrato v1', v_ok,
      coalesce(f.codigo, 'sem número') || '; prioridades ' || jf.priority || '/' || jn.priority
      || '; modos ' || (jf.input->>'modo') || '/' || (jn.input->>'modo'));
  exception when others then
    insert into _resultado values ('T8 legenda-chave numera na chegada; job no contrato v1', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T9 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
begin
  begin
    insert into public.comprovantes (situacao, modo, rota, dono_id, wa_message_id, phone_normalized, tipo_whatsapp,
                                     recebido_em, valor)
    values ('nao_comprovante', 'dono', 'comprovante', pg_temp._dono(), 'TESTE-' || gen_random_uuid(),
            pg_temp._telefone(), 'image', now(), 10);
    insert into _resultado values ('T9 nao_comprovante não guarda valor', false, 'entrou nao_comprovante com valor');
  exception when check_violation then
    insert into _resultado values ('T9 nao_comprovante não guarda valor', true, 'recusado: ' || left(sqlerrm, 100));
  when others then
    insert into _resultado values ('T9 nao_comprovante não guarda valor', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
  -- depois de apagado o original, nem o texto do dono fica (decisão 13)
  begin
    insert into public.comprovantes (situacao, modo, rota, dono_id, wa_message_id, phone_normalized, tipo_whatsapp,
                                     recebido_em, legenda, arquivo_apagado_em)
    values ('nao_comprovante', 'dono', 'ambos', pg_temp._dono(), 'TESTE-' || gen_random_uuid(),
            pg_temp._telefone(), 'image', now(), 'lança na OS do Brisa', now());
    insert into _resultado values ('T9 nao_comprovante sem texto depois de apagado', false, 'entrou com legenda e original apagado');
  exception when check_violation then
    insert into _resultado values ('T9 nao_comprovante sem texto depois de apagado', true, 'recusado: ' || left(sqlerrm, 100));
  when others then
    insert into _resultado values ('T9 nao_comprovante sem texto depois de apagado', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T9b ══════════════════════════════════════════════════════════════════════════════════════
-- O gatilho _app_settings_chaves_do_dono lê auth.uid(): com as claims de um financeiro ATIVO, mudar
-- (ou apagar) comprovante_fluxo dá 42501; com as do admin, passa. value = value: nada muda de fato.
do $$
declare
  v_fin uuid;
  v_dono uuid := pg_temp._dono();
  v_upd text := 'nenhum erro';
  v_del text := 'nenhum erro';
  v_admin text := 'nenhum erro';
  v_outra text := 'nenhum erro';
begin
  begin
    v_fin := pg_temp._usuario('financial');
    perform set_config('request.jwt.claim.sub', v_fin::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_fin, 'role', 'authenticated')::text, true);
    begin
      update public.app_settings set value = value where key = 'comprovante_fluxo';
    exception when others then
      v_upd := sqlstate;
    end;
    begin
      delete from public.app_settings where key = 'comprovante_fluxo';
    exception when others then
      v_del := sqlstate;
    end;
    begin
      -- chave qualquer (de mentira, some no rollback): o financeiro segue livre nela
      insert into public.app_settings (key, value) values ('teste_comprovantes_chave_livre', 'a');
      update public.app_settings set value = 'b' where key = 'teste_comprovantes_chave_livre';
    exception when others then
      v_outra := sqlstate;
    end;
    perform set_config('request.jwt.claim.sub', v_dono::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_dono, 'role', 'authenticated')::text, true);
    begin
      update public.app_settings set value = value where key = 'comprovante_fluxo';
    exception when others then
      v_admin := sqlstate;
    end;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into _resultado values ('T9b só o admin muda comprovante_fluxo',
      v_upd = '42501' and v_del = '42501' and v_admin = 'nenhum erro' and v_outra = 'nenhum erro'
      and exists (select 1 from public.app_settings where key = 'comprovante_fluxo'),
      'financeiro: update ' || v_upd || ', delete ' || v_del || ', outra chave ' || v_outra || '; admin ' || v_admin);
  exception when others then
    insert into _resultado values ('T9b só o admin muda comprovante_fluxo', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
