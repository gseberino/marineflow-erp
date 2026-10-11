-- Prova: leitura, encaminhamento, aviso, gatilho e vigia dos comprovantes da F1
-- (migrations 20261011100000 a 20261011103000).
--
--   T10 tabela de _comprovante_e_compra (Apêndice C da spec, todas as combinações)
--   T11 saída v1 de NFC-e → cmp, campos, fornecedor pelo CNPJ comparando só dígitos (+ defesas)
--   T12 chave repetida → cancelado e o número já nascido fica queimado
--   T13 legenda-chave + tela_erro → cancelado, número queimado, encaminhar=true
--   T14 o texto sai de ai_jobs.response e vai para leitura_texto; a URL some; CPF mascarado em leitura
--   T15 deadline_exceeded → reenfileirar; pedir_leitura aceita uma vez e recusa a segunda; a falha
--       seguinte encaminha (sem legenda-chave) mesmo dias depois
--   T16 placeholders do mesmo telefone em 120 s → o segundo dispensado_agrupado; com legenda não
--       agrupa; repescagem e sombra nunca encaminham
--   T17 reservar_aviso espera a fila e respeita p_forcar (e os 10 minutos)
--   T18 o gatilho só enfileira net.http_post com metadata.tipo certo e mudança real de status
--   T19 vigia_lote reserva (duas chamadas seguidas não devolvem o mesmo baixar/dropbox) e expurga
--   T20 aplicar duas vezes o mesmo job → a segunda é ignorado
--   T21 o texto do encaminhamento sai da linha: reescrever whatsapp_messages.body não muda nada
--   T22 rede de 1 h: "recebido" sem desfecho vira falhou sem_desfecho (e encaminha sem legenda-chave)
--   T23 entrega que lança: conta, desiste na 3ª (falhou entrega_falhou, encaminha, job limpo)
--   T24 aviso que não saiu: a reserva volta com espera de 5 min; na 5ª falha desiste
--   T25 apagar o original de um não comprovante leva o texto do dono; o de um CMP fica
--   T26 o webhook já mandou ao assistente (prazo do receber): o banco não encaminha de novo
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado P10 da spec; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/comprovantes_leitura.sql --output json
--
-- Seguro em produção: cria os próprios dados (mensagens, comprovantes, jobs e um fornecedor de
-- mentira, CNPJ e chave aleatórios) dentro da transação e termina em ROLLBACK. O job "concluído"
-- é simulado por UPDATE em ai_jobs (como o worker faria); a fila do pg_net que o gatilho enche
-- some no rollback. Busca o admin, sem id fixo.
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

create function pg_temp._digitos(p_n integer) returns text language sql volatile as $$
  select string_agg((floor(random() * 10))::int::text, '') from generate_series(1, p_n)
$$;

create function pg_temp._chegada(
  p_modo text default 'dono', p_rota text default 'comprovante', p_origem text default 'webhook',
  p_forcado boolean default false, p_legenda text default null, p_phone text default null,
  p_recebido timestamptz default now()
) returns uuid language plpgsql as $$
declare
  v_wa text := 'TESTE-' || gen_random_uuid();
  v_phone text := coalesce(p_phone, pg_temp._telefone());
  v_msg uuid;
begin
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, wa_message_id, occurred_at)
  values ('inbound', v_phone, 'image', coalesce(p_legenda, '[image]'), v_wa, p_recebido)
  returning id into v_msg;
  return (public.comprovante_receber(jsonb_build_object(
    'message_id', v_msg, 'wa_message_id', v_wa, 'phone_normalized', v_phone,
    'dono_id', pg_temp._dono(), 'modo', p_modo, 'rota', p_rota, 'origem', p_origem,
    'tipo_whatsapp', 'image', 'forcado', p_forcado, 'legenda', p_legenda, 'dica_da_legenda', null,
    'nome_arquivo', null, 'mime_declarado', 'image/jpeg', 'recebido_em', p_recebido))->>'id')::uuid;
end $$;

create function pg_temp._url(p_id uuid) returns text language sql stable as $$
  select 'https://teste.supabase.co/storage/v1/object/sign/comprovantes/'
         || to_char(now() at time zone 'America/Sao_Paulo', 'YYYY/MM') || '/' || p_id || '.jpg?token=teste'
$$;

create function pg_temp._guardar(p_id uuid, p_sha text default null) returns jsonb language sql as $$
  select public.comprovante_guardar_arquivo(
    p_id,
    jsonb_build_object('path', to_char(now() at time zone 'America/Sao_Paulo', 'YYYY/MM') || '/' || p_id || '.jpg',
                       'mime_real', 'image/jpeg', 'bytes', 1234, 'sha256', coalesce(p_sha, pg_temp._sha())),
    pg_temp._url(p_id))
$$;

create function pg_temp._sha_de(p_id uuid) returns text language sql stable as $$
  select arquivo_sha256 from public.comprovantes where id = p_id
$$;

create function pg_temp._job_de(p_id uuid) returns uuid language sql stable as $$
  select job_id from public.comprovantes where id = p_id
$$;

-- saída v1 do leitor (contrato 5.2) com os campos e confianças dados
create function pg_temp._saida(
  p_sha text, p_tipo text default 'nfce', p_conf text default 'alta',
  p_campos jsonb default '{}', p_confs jsonb default '{}', p_texto text default '', p_motivos jsonb default '["teste"]'
) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'versao', 1,
    'leitor', jsonb_build_object('versao', 'leitor-v1.0.0', 'motores', jsonb_build_object('paddle', 'ppocrv5-latin')),
    'modo', 'triagem',
    'arquivo', jsonb_build_object('sha256', p_sha, 'sha256_confere', true, 'mime_real', 'image/jpeg',
                                  'paginas', 1, 'largura', 1600, 'altura', 1200),
    'classificacao', jsonb_build_object('tipo', p_tipo, 'confianca', p_conf, 'motivos', p_motivos),
    'campos', jsonb_build_object('valor_total', null, 'data', null, 'hora', null, 'pagamento', null,
                                 'emitente_cnpj', null, 'chave44', null, 'favorecido_doc', null,
                                 'linha_digitavel', null, 'e2e', null, 'documentos', '[]'::jsonb) || coalesce(p_campos, '{}'),
    'confianca_dos_campos', coalesce(p_confs, '{}'),
    'origem_dos_campos', '{}'::jsonb,
    'alertas', '[]'::jsonb,
    'texto', jsonb_build_object('fonte', case when p_texto = '' then 'nenhum' else 'ocr' end,
                                'caracteres', char_length(p_texto), 'conteudo', p_texto),
    'etapas', '[]'::jsonb,
    'tempo_total_ms', 1234,
    'segunda_leitura', null)
$$;

-- o worker conclui / falha o job (como ai_gateway_complete_job / fail_job fariam)
create function pg_temp._concluir(p_job uuid, p_data jsonb) returns void language sql as $$
  update public.ai_jobs
     set status = 'completed', completed_at = now(), provider_used = 'local-doc', model_used = 'leitor-v1+teste',
         response = jsonb_build_object('format', 'json', 'text', 'teste', 'data', p_data)
   where id = p_job
$$;

create function pg_temp._falhar(p_job uuid, p_codigo text) returns void language sql as $$
  update public.ai_jobs set status = 'failed', completed_at = now(), error_code = p_codigo, error = 'teste'
   where id = p_job
$$;

-- chega, guarda e lê: devolve a saída de comprovante_aplicar_leitura
create function pg_temp._ler(p_id uuid, p_tipo text default 'nao_documento', p_conf text default 'alta',
                             p_campos jsonb default '{}', p_confs jsonb default '{}', p_texto text default '')
returns jsonb language plpgsql as $$
declare
  v_job uuid;
begin
  if pg_temp._job_de(p_id) is null then
    perform pg_temp._guardar(p_id);
  end if;
  v_job := pg_temp._job_de(p_id);
  perform pg_temp._concluir(v_job, pg_temp._saida(pg_temp._sha_de(p_id), p_tipo, p_conf, p_campos, p_confs, p_texto));
  return public.comprovante_aplicar_leitura(v_job);
end $$;

-- ═══ T10 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_t text;
  v_c text;
  v_f boolean;
  v_esperado boolean;
  v_erros text[] := '{}';
  v_n integer := 0;
  v_pagamento text[] := array['nfce', 'nfe_danfe', 'nfe_xml', 'nfse', 'cupom_nao_fiscal', 'pix', 'boleto_pago',
                              'boleto', 'cartao', 'fatura', 'guia', 'recibo', 'agendado'];
  v_so_com_legenda text[] := array['pedido', 'outro', 'nao_documento'];
  v_nunca text[] := array['tela_erro', 'recebimento'];
begin
  foreach v_t in array v_pagamento || v_so_com_legenda || v_nunca loop
    foreach v_c in array array['alta', 'media', 'baixa'] loop
      foreach v_f in array array[false, true] loop
        -- Apêndice C, linha a linha
        v_esperado := case
          when v_t = any (v_nunca) then false
          when v_t = any (v_so_com_legenda) then v_f
          else v_f or v_c in ('alta', 'media') end;
        v_n := v_n + 1;
        if public._comprovante_e_compra(v_t, v_c, v_f) is distinct from v_esperado then
          v_erros := v_erros || (v_t || '/' || v_c || '/' || v_f);
        end if;
      end loop;
    end loop;
  end loop;
  insert into _resultado values ('T10 Apêndice C (é compra?)', cardinality(v_erros) = 0 and v_n = 108,
    case when cardinality(v_erros) = 0 then v_n || ' combinações' else 'erradas: ' || array_to_string(v_erros, ', ') end);
end $$;

-- ═══ T11 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_cnpj text := pg_temp._digitos(14);
  v_chave text := pg_temp._digitos(44);
  v_dia text := to_char((now() at time zone 'America/Sao_Paulo')::date - 2, 'YYYY-MM-DD');
  v_sup uuid;
  v_id uuid;
  r jsonb;
  c public.comprovantes;
  v2 uuid;
  r2 jsonb;
  c2 public.comprovantes;
begin
  begin
    insert into public.suppliers (name, trade_name, cnpj_cpf)
    values ('FORNECEDOR TESTE LTDA', 'FORNECEDOR TESTE',
            substr(v_cnpj, 1, 2) || '.' || substr(v_cnpj, 3, 3) || '.' || substr(v_cnpj, 6, 3) || '/'
            || substr(v_cnpj, 9, 4) || '-' || substr(v_cnpj, 13, 2))
    returning id into v_sup;
    v_id := pg_temp._chegada();
    r := pg_temp._ler(v_id, 'nfce', 'alta',
      jsonb_build_object('valor_total', '62.00', 'data', v_dia, 'hora', '12:57:56', 'pagamento', 'debito',
                         'emitente_cnpj', v_cnpj, 'chave44', v_chave),
      '{"valor_total":"media","data":"media","hora":"media","pagamento":"media","emitente_cnpj":"alta","chave44":"alta"}',
      'NFC-E TESTE TOTAL 62,00');
    select * into c from public.comprovantes where id = v_id;
    insert into _resultado values ('T11 NFC-e vira CMP com campos e fornecedor',
      r->>'decisao' = 'cmp' and r->>'codigo' ~ '^CMP-[0-9]{5,}$' and (r->>'subir_dropbox')::boolean
      and c.situacao = 'lido' and c.valor = 62.00 and c.valor_confianca = 'media'
      and c.data_compra = v_dia::date and c.hora_compra = '12:57:56'::time and c.forma_pagamento = 'debito'
      and c.emitente_cnpj = v_cnpj and c.cnpj_confianca = 'alta' and c.chave_acesso = v_chave
      and c.supplier_id = v_sup and c.fornecedor_nome = 'FORNECEDOR TESTE'
      and r->'resumo'->>'valor' = '62.00' and r->'arquivo'->>'arquivo_path' = c.arquivo_path
      and c.dropbox_proxima_em > now() and c.tipo = 'nfce' and c.confianca = 'alta',
      coalesce(r->>'decisao', '?') || ' ' || coalesce(c.codigo, '?') || ' valor ' || coalesce(c.valor::text, '-')
      || ' fornecedor ' || coalesce(c.fornecedor_nome, '-'));

    -- defesas: data no futuro, valor malformado e CPF sem máscara viram vazio + alerta
    v2 := pg_temp._chegada();
    r2 := pg_temp._ler(v2, 'nfce', 'media',
      jsonb_build_object('valor_total', '4.00,00',
                         'data', to_char((now() at time zone 'America/Sao_Paulo')::date + 3, 'YYYY-MM-DD'),
                         'favorecido_doc', '12345678909', 'hora', '24:00:00'));
    select * into c2 from public.comprovantes where id = v2;
    insert into _resultado values ('T11b campo fora do formato vira vazio + alerta (nunca derruba)',
      r2->>'decisao' = 'cmp' and c2.valor is null and c2.data_compra is null and c2.favorecido_doc is null
      and c2.hora_compra is null
      and c2.alertas @> array['data_futura', 'campo_descartado:valor_total', 'campo_descartado:favorecido_doc',
                              'campo_descartado:hora'],
      array_to_string(c2.alertas, ', '));
  exception when others then
    insert into _resultado values ('T11 NFC-e vira CMP com campos e fornecedor', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T12 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_chave text := pg_temp._digitos(44);
  v_a uuid;
  v_b uuid;
  v_gb jsonb;
  ra jsonb;
  rb jsonb;
  b public.comprovantes;
  v_prox integer;
begin
  begin
    v_a := pg_temp._chegada();
    ra := pg_temp._ler(v_a, 'nfce', 'alta', jsonb_build_object('chave44', v_chave), '{"chave44":"alta"}');
    v_b := pg_temp._chegada(p_forcado => true, p_legenda => 'cupom');
    v_gb := pg_temp._guardar(v_b);                          -- o número nasce aqui
    rb := pg_temp._ler(v_b, 'nfce', 'alta', jsonb_build_object('chave44', v_chave), '{"chave44":"alta"}');
    select * into b from public.comprovantes where id = v_b;
    v_prox := public._comprovante_proximo_numero();
    insert into _resultado values ('T12 chave repetida cancela e queima o número',
      ra->>'decisao' = 'cmp' and rb->>'decisao' = 'duplicado' and b.situacao = 'cancelado'
      and b.motivo_cancelamento = 'chave_repetida' and b.duplicado_de = v_a
      and b.codigo = v_gb->>'codigo' and b.numero is not null and v_prox > b.numero
      and b.arquivo_apagar_apos = b.recebido_em + interval '7 days' and not (rb->>'encaminhar')::boolean,
      coalesce(rb->>'decisao', '?') || '; ' || coalesce(b.codigo, '?') || ' queimado; próximo número ' || v_prox);
  exception when others then
    insert into _resultado values ('T12 chave repetida cancela e queima o número', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T13 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_id uuid;
  v_g jsonb;
  r jsonb;
  c public.comprovantes;
begin
  begin
    v_id := pg_temp._chegada(p_forcado => true, p_legenda => 'pix');
    v_g := pg_temp._guardar(v_id);
    r := pg_temp._ler(v_id, 'tela_erro', 'media');
    select * into c from public.comprovantes where id = v_id;
    insert into _resultado values ('T13 legenda-chave + tela de erro: cancelado e segue ao assistente',
      r->>'decisao' = 'cancelado' and c.situacao = 'cancelado' and c.motivo_cancelamento = 'leitura_tela_erro'
      and c.numero is not null and c.codigo = v_g->>'codigo'
      and (r->>'encaminhar')::boolean and r->>'texto_para_assistente' = 'pix'
      and c.encaminhamento = 'apos_leitura' and c.arquivo_apagar_apos = c.recebido_em + interval '7 days'
      and not (r->>'subir_dropbox')::boolean,
      coalesce(r->>'decisao', '?') || ' ' || coalesce(c.codigo, '?') || ' encaminhar=' || coalesce(r->>'encaminhar', '?'));
  exception when others then
    insert into _resultado values ('T13 legenda-chave + tela de erro: cancelado e segue ao assistente', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T14 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_id uuid;
  v_job uuid;
  v_texto text := 'MERCADO TESTE CPF 123.456.789-09 TOTAL 10,00';
  r jsonb;
  c public.comprovantes;
  j public.ai_jobs;
  v_saida jsonb;
begin
  begin
    v_id := pg_temp._chegada();
    perform pg_temp._guardar(v_id);
    v_job := pg_temp._job_de(v_id);
    -- um leitor com defeito que deixasse CPF formatado fora do texto: o banco mascara mesmo assim
    v_saida := pg_temp._saida(pg_temp._sha_de(v_id), 'cupom_nao_fiscal', 'media',
                 jsonb_build_object('valor_total', '10.00',
                   'documentos', jsonb_build_array(jsonb_build_object('tipo', 'cpf', 'valor', '123.456.789-09', 'valido', true))),
                 '{"valor_total":"media"}', v_texto, '["cpf 987.654.321-00 no cupom"]');
    perform pg_temp._concluir(v_job, v_saida);
    r := public.comprovante_aplicar_leitura(v_job);
    select * into c from public.comprovantes where id = v_id;
    select * into j from public.ai_jobs where id = v_job;
    insert into _resultado values ('T14 texto só em leitura_texto; URL some; CPF mascarado em leitura',
      r->>'decisao' = 'cmp'
      and c.leitura_texto = v_texto
      and not (c.leitura ? 'texto')
      and c.leitura::text not like '%123.456.789-09%' and c.leitura::text like '%***.***.789-09%'
      and c.leitura::text not like '%987.654.321-00%'
      and not (j.response->'data' ? 'texto') and j.response::text not like '%MERCADO TESTE%'
      and j.response->>'text' = 'cupom_nao_fiscal media'
      and not (j.input->'arquivo' ? 'url') and j.input->'arquivo'->>'sha256' = c.arquivo_sha256
      and j.metadata ? 'entregue_em',
      'leitura sem texto: ' || (not (c.leitura ? 'texto')) || '; url no job: ' || (j.input->'arquivo' ? 'url'));
  exception when others then
    insert into _resultado values ('T14 texto só em leitura_texto; URL some; CPF mascarado em leitura', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T15 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_id uuid;
  v_j1 uuid;
  v_j2 uuid;
  r1 jsonb;
  p1 jsonb;
  p2 jsonb;
  r2 jsonb;
  r1b jsonb;
  p3 jsonb;
  c public.comprovantes;
  v_tent text;
begin
  begin
    -- PC desligado: a foto chegou há 3 dias e o prazo do job venceu
    v_id := pg_temp._chegada(p_recebido => now() - interval '3 days');
    perform pg_temp._guardar(v_id);
    v_j1 := pg_temp._job_de(v_id);
    perform pg_temp._falhar(v_j1, 'deadline_exceeded');
    r1 := public.comprovante_aplicar_leitura(v_j1);
    p1 := public.comprovante_pedir_leitura(v_id, pg_temp._url(v_id));
    v_j2 := (p1->>'job_id')::uuid;
    select metadata->>'tentativa' into v_tent from public.ai_jobs where id = v_j2;
    p2 := public.comprovante_pedir_leitura(v_id, pg_temp._url(v_id));
    perform pg_temp._falhar(v_j2, 'deadline_exceeded');
    r2 := public.comprovante_aplicar_leitura(v_j2);
    r1b := public.comprovante_aplicar_leitura(v_j1);
    p3 := public.comprovante_pedir_leitura(v_id, pg_temp._url(v_id));
    select * into c from public.comprovantes where id = v_id;
    insert into _resultado values ('T15 reenfileira uma vez; depois falha e encaminha',
      r1->>'decisao' = 'reenfileirar' and not (r1->>'encaminhar')::boolean
      and (p1->>'ok')::boolean and v_j2 is not null and v_j2 <> v_j1 and v_tent = '2'
      and not (p2->>'ok')::boolean
      and r2->>'decisao' = 'falhou' and (r2->>'encaminhar')::boolean and r2->>'texto_para_assistente' = '[image]'
      and r1b->>'decisao' = 'ignorado' and not (p3->>'ok')::boolean
      and c.situacao = 'falhou' and c.erro = 'deadline_exceeded' and c.reenfileirado and c.leituras = 2
      and c.numero is null and c.arquivo_apagar_apos = c.recebido_em + interval '7 days',
      (r1->>'decisao') || ' → pedir ' || (p1->>'ok') || '/' || (p2->>'ok') || ' (' || coalesce(p2->>'motivo', '') || ') → '
      || (r2->>'decisao') || ' encaminhar=' || (r2->>'encaminhar'));
  exception when others then
    insert into _resultado values ('T15 reenfileira uma vez; depois falha e encaminha', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T16 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_e uuid; v_f uuid;
  ra jsonb; rb jsonb; rc jsonb; rd jsonb; re jsonb; rf jsonb;
  b public.comprovantes; d public.comprovantes; e public.comprovantes;
begin
  begin
    v_a := pg_temp._chegada(p_phone => v_phone);
    ra := pg_temp._ler(v_a);                                                    -- nao_documento
    v_b := pg_temp._chegada(p_phone => v_phone);
    rb := pg_temp._ler(v_b);
    v_c := pg_temp._chegada(p_forcado => true, p_legenda => 'pix', p_phone => v_phone);
    rc := pg_temp._ler(v_c, 'tela_erro', 'media');
    v_d := pg_temp._chegada(p_origem => 'repescagem', p_phone => v_phone);
    rd := pg_temp._ler(v_d);
    v_e := pg_temp._chegada(p_modo => 'sombra', p_rota => 'ambos', p_phone => v_phone);
    re := pg_temp._ler(v_e);
    v_f := pg_temp._chegada(p_modo => 'dono', p_rota => 'ambos', p_legenda => 'lança na OS do Brisa', p_phone => v_phone);
    rf := pg_temp._ler(v_f);
    select * into b from public.comprovantes where id = v_b;
    select * into d from public.comprovantes where id = v_d;
    select * into e from public.comprovantes where id = v_e;
    insert into _resultado values ('T16 encaminhamento: agrupa placeholders; legenda, repescagem e sombra',
      (ra->>'encaminhar')::boolean
      and not (rb->>'encaminhar')::boolean and b.encaminhamento = 'dispensado_agrupado' and b.situacao = 'nao_comprovante'
      and (rc->>'encaminhar')::boolean
      and not (rd->>'encaminhar')::boolean and d.encaminhamento is null
      and not (re->>'encaminhar')::boolean and e.encaminhamento = 'chegada'
      and not (rf->>'encaminhar')::boolean,
      'A ' || (ra->>'encaminhar') || ', B ' || coalesce(b.encaminhamento, '-') || ', legenda ' || (rc->>'encaminhar')
      || ', repescagem ' || (rd->>'encaminhar') || ', sombra ' || (re->>'encaminhar') || ', ambos ' || (rf->>'encaminhar'));
  exception when others then
    insert into _resultado values ('T16 encaminhamento: agrupa placeholders; legenda, repescagem e sombra', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T17 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_q text := pg_temp._telefone();
  v_f uuid; v_g uuid; v_h uuid; v_i uuid; v_j uuid;
  a1 jsonb; a2 jsonb; a3 jsonb; a4 jsonb; a5 jsonb;
begin
  begin
    v_f := pg_temp._chegada(p_forcado => true, p_legenda => 'cupom', p_phone => v_q);
    perform pg_temp._ler(v_f, 'nfce', 'alta', '{"valor_total":"15.50"}', '{"valor_total":"alta"}');
    v_g := pg_temp._chegada(p_phone => v_q);                 -- ainda na fila do telefone
    a1 := public.comprovante_reservar_aviso(v_q, false);     -- espera a fila esvaziar
    a2 := public.comprovante_reservar_aviso(v_q, true);      -- o vigia força
    a3 := public.comprovante_reservar_aviso(v_q, true);      -- já avisado: nada
    -- item que esperou 10 min ou mais sai mesmo com a fila cheia e sem forçar
    v_h := pg_temp._chegada(p_forcado => true, p_legenda => 'nota', p_phone => v_q, p_recebido => now() - interval '11 minutes');
    perform pg_temp._ler(v_h, 'nfce', 'media');
    a4 := public.comprovante_reservar_aviso(v_q, false);
    -- sombra nunca avisa; legenda-chave que nem foi guardada avisa "não guardado"
    v_i := pg_temp._chegada(p_modo => 'sombra', p_rota => 'ambos', p_phone => v_q);
    perform pg_temp._ler(v_i, 'nfce', 'alta');
    v_j := pg_temp._chegada(p_forcado => true, p_legenda => 'cupom', p_phone => v_q);
    perform public.comprovante_download_falhou(v_j, 'sem_chave');
    a5 := public.comprovante_reservar_aviso(v_q, true);
    insert into _resultado values ('T17 aviso espera a fila, respeita p_forcar e os 10 min',
      jsonb_array_length(a1->'itens') = 0 and (a1->>'esperando')::int = 1
      and jsonb_array_length(a2->'itens') = 1 and a2->'itens'->0->>'id' = v_f::text and a2->'itens'->0->>'decisao' = 'cmp'
      and a2->'itens'->0->>'valor' = '15.50' and a2->'itens'->0->>'codigo' ~ '^CMP-'
      and jsonb_array_length(a3->'itens') = 0
      and jsonb_array_length(a4->'itens') = 1 and a4->'itens'->0->>'id' = v_h::text
      and jsonb_array_length(a5->'itens') = 1 and a5->'itens'->0->>'id' = v_j::text
      and a5->'itens'->0->>'decisao' = 'nao_guardado' and a5->'itens'->0->>'erro' = 'sem_chave',
      'itens ' || jsonb_array_length(a1->'itens') || '/' || jsonb_array_length(a2->'itens') || '/'
      || jsonb_array_length(a3->'itens') || '/' || jsonb_array_length(a4->'itens') || '/' || jsonb_array_length(a5->'itens'));
  exception when others then
    insert into _resultado values ('T17 aviso espera a fila, respeita p_forcar e os 10 min', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T18 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_url constant text := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/comprovantes-whatsapp';
  v_id uuid;
  v_job uuid;
  v_outro uuid;
  v_n0 integer; v_n1 integer; v_n2 integer; v_n3 integer;
  v_corpo jsonb;
  v_headers jsonb;
begin
  begin
    v_id := pg_temp._chegada();
    perform pg_temp._guardar(v_id);
    v_job := pg_temp._job_de(v_id);
    select count(*) into v_n0 from net.http_request_queue where url = v_url;
    perform pg_temp._concluir(v_job, pg_temp._saida(pg_temp._sha_de(v_id), 'nao_documento', 'alta'));
    select count(*) into v_n1 from net.http_request_queue where url = v_url;
    select convert_from(q.body, 'UTF8')::jsonb, q.headers into v_corpo, v_headers
      from net.http_request_queue q where q.url = v_url order by q.id desc limit 1;
    update public.ai_jobs set status = 'completed' where id = v_job;      -- sem mudança real de status
    update public.ai_jobs set priority = priority where id = v_job;       -- nem toca no status
    select count(*) into v_n2 from net.http_request_queue where url = v_url;
    insert into public.ai_jobs (source, requested_by, prompt, metadata)
    values ('marineflow', pg_temp._dono(), 'teste', '{"tipo":"teste_outro"}')
    returning id into v_outro;
    update public.ai_jobs set status = 'completed', completed_at = now() where id = v_outro;
    select count(*) into v_n3 from net.http_request_queue where url = v_url;
    insert into _resultado values ('T18 gatilho só com tipo certo e mudança real de status',
      v_n1 = v_n0 + 1 and v_n2 = v_n1 and v_n3 = v_n2
      and v_corpo->>'acao' = 'entrega' and v_corpo->>'job_id' = v_job::text and v_headers ? 'x-cron-secret',
      'chamadas: +' || (v_n1 - v_n0) || ' na conclusão, +' || (v_n2 - v_n1) || ' sem mudança, +' || (v_n3 - v_n2) || ' outro tipo');
  exception when others then
    insert into _resultado values ('T18 gatilho só com tipo certo e mudança real de status', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T19 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_baixar uuid; v_dropbox uuid; v_expira uuid; v_cmp_vencido uuid; v_nao_vencido uuid; v_entregar uuid; v_reenf uuid;
  v_job_entregar uuid;
  l1 jsonb;
  l2 jsonb;
  v_texto_sobrou text;
begin
  begin
    v_baixar := pg_temp._chegada();
    update public.comprovantes set created_at = now() - interval '6 minutes' where id = v_baixar;

    v_dropbox := pg_temp._chegada(p_forcado => true, p_legenda => 'cupom');
    perform pg_temp._ler(v_dropbox, 'nfce', 'alta');
    update public.comprovantes set dropbox_proxima_em = now() - interval '1 minute' where id = v_dropbox;

    v_expira := pg_temp._chegada();
    perform pg_temp._ler(v_expira, 'nfce', 'alta', '{}', '{}', 'texto velho');
    update public.comprovantes set lido_em = now() - interval '91 days' where id = v_expira;

    -- CMP vivo com prazo de apagar vencido (não deveria existir, mas se existir não apaga)
    v_cmp_vencido := pg_temp._chegada(p_forcado => true, p_legenda => 'cupom');
    perform pg_temp._ler(v_cmp_vencido, 'nfce', 'alta');
    update public.comprovantes set arquivo_apagar_apos = now() - interval '1 minute' where id = v_cmp_vencido;
    v_nao_vencido := pg_temp._chegada();
    perform pg_temp._ler(v_nao_vencido);
    update public.comprovantes set arquivo_apagar_apos = now() - interval '1 minute' where id = v_nao_vencido;

    -- job concluído há 3 min sem entrega (o gatilho perdeu)
    v_entregar := pg_temp._chegada();
    perform pg_temp._guardar(v_entregar);
    v_job_entregar := pg_temp._job_de(v_entregar);
    perform pg_temp._concluir(v_job_entregar, pg_temp._saida(pg_temp._sha_de(v_entregar), 'nao_documento', 'alta'));
    update public.ai_jobs set completed_at = now() - interval '3 minutes' where id = v_job_entregar;

    -- prazo vencido já entregue: o vigia reenfileira
    v_reenf := pg_temp._chegada();
    perform pg_temp._guardar(v_reenf);
    perform pg_temp._falhar(pg_temp._job_de(v_reenf), 'deadline_exceeded');
    perform public.comprovante_aplicar_leitura(pg_temp._job_de(v_reenf));

    l1 := public.comprovantes_vigia_lote(50);
    l2 := public.comprovantes_vigia_lote(50);
    select leitura_texto into v_texto_sobrou from public.comprovantes where id = v_expira;

    insert into _resultado values ('T19 vigia_lote reserva baixar/dropbox e não repete',
      l1->'baixar' @> jsonb_build_array(jsonb_build_object('id', v_baixar))
      and not (l2->'baixar' @> jsonb_build_array(jsonb_build_object('id', v_baixar)))
      and l1->'dropbox' @> jsonb_build_array(jsonb_build_object('id', v_dropbox))
      and not (l2->'dropbox' @> jsonb_build_array(jsonb_build_object('id', v_dropbox)))
      and l1->'entregar' @> jsonb_build_array(jsonb_build_object('job_id', v_job_entregar))
      and l1->'reenfileirar' @> jsonb_build_array(jsonb_build_object('id', v_reenf)),
      'baixar ' || jsonb_array_length(l1->'baixar') || '→' || jsonb_array_length(l2->'baixar')
      || ', dropbox ' || jsonb_array_length(l1->'dropbox') || '→' || jsonb_array_length(l2->'dropbox')
      || ', entregar ' || jsonb_array_length(l1->'entregar') || ', reenfileirar ' || jsonb_array_length(l1->'reenfileirar'));
    insert into _resultado values ('T19b vigia expurga o texto de 90 dias e nunca apaga CMP vivo',
      (l1->>'expurgados')::int >= 1 and v_texto_sobrou is null
      and l1->'apagar' @> jsonb_build_array(jsonb_build_object('id', v_nao_vencido))
      and not (l1->'apagar' @> jsonb_build_array(jsonb_build_object('id', v_cmp_vencido))),
      'expurgados ' || (l1->>'expurgados') || ', apagar ' || jsonb_array_length(l1->'apagar'));
  exception when others then
    insert into _resultado values ('T19 vigia_lote reserva baixar/dropbox e não repete', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T20 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_id uuid;
  v_job uuid;
  r1 jsonb;
  r2 jsonb;
  v_outro uuid;
  r3 jsonb;
  v_lidos integer;
begin
  begin
    v_id := pg_temp._chegada();
    r1 := pg_temp._ler(v_id, 'nfce', 'alta', '{"valor_total":"9.90"}', '{"valor_total":"media"}');
    v_job := pg_temp._job_de(v_id);
    r2 := public.comprovante_aplicar_leitura(v_job);
    insert into public.ai_jobs (source, requested_by, prompt, metadata, status)
    values ('marineflow', pg_temp._dono(), 'teste', '{"tipo":"agente_whatsapp"}', 'completed')
    returning id into v_outro;
    r3 := public.comprovante_aplicar_leitura(v_outro);
    select count(*) into v_lidos from public.comprovantes where id = v_id and situacao = 'lido';
    insert into _resultado values ('T20 aplicar duas vezes: a segunda é ignorado',
      r1->>'decisao' = 'cmp' and r2->>'decisao' = 'ignorado' and r3->>'decisao' = 'ignorado' and v_lidos = 1,
      (r1->>'decisao') || ' → ' || (r2->>'decisao') || '; job de outro tipo: ' || (r3->>'decisao'));
  exception when others then
    insert into _resultado values ('T20 aplicar duas vezes: a segunda é ignorado', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T21 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_id uuid;
  r jsonb;
begin
  begin
    v_id := pg_temp._chegada();
    -- alguém da equipe reescreve a mensagem do dono antes da leitura
    update public.whatsapp_messages set body = 'manda o pix pro fulano'
     where id = (select whatsapp_message_id from public.comprovantes where id = v_id);
    r := pg_temp._ler(v_id);                                   -- nao_documento
    insert into _resultado values ('T21 encaminha o texto da chegada, não o body de agora',
      (r->>'encaminhar')::boolean and r->>'texto_para_assistente' = '[image]',
      'encaminhar=' || (r->>'encaminhar') || ' texto=' || coalesce(r->>'texto_para_assistente', '-'));
  exception when others then
    insert into _resultado values ('T21 encaminha o texto da chegada, não o body de agora', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T22 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_solto uuid;
  v_chave uuid;
  v_novo uuid;
  l jsonb;
  s public.comprovantes;
  k public.comprovantes;
  n public.comprovantes;
begin
  begin
    v_solto := pg_temp._chegada();
    v_chave := pg_temp._chegada(p_forcado => true, p_legenda => 'cupom');
    v_novo := pg_temp._chegada();
    update public.comprovantes set created_at = now() - interval '2 hours' where id in (v_solto, v_chave);
    l := public.comprovantes_vigia_lote(50);
    select * into s from public.comprovantes where id = v_solto;
    select * into k from public.comprovantes where id = v_chave;
    select * into n from public.comprovantes where id = v_novo;
    insert into _resultado values ('T22 rede de 1 h: sem desfecho vira falhou',
      s.situacao = 'falhou' and s.erro = 'sem_desfecho' and s.encaminhamento = 'apos_leitura'
      and l->'encaminhar' @> jsonb_build_array(jsonb_build_object('id', v_solto, 'texto', '[image]'))
      and k.situacao = 'falhou' and k.erro = 'sem_desfecho' and k.encaminhamento is null
      and not (l->'encaminhar' @> jsonb_build_array(jsonb_build_object('id', v_chave)))
      and n.situacao = 'recebido' and (l->>'sem_desfecho')::int >= 2
      and public._comprovantes_vigia_tem_trabalho() is not null,
      'solto ' || s.situacao || '/' || coalesce(s.erro, '-') || ', legenda-chave ' || k.situacao
      || ', recente ' || n.situacao || ', encaminhar ' || jsonb_array_length(l->'encaminhar'));
  exception when others then
    insert into _resultado values ('T22 rede de 1 h: sem desfecho vira falhou', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T23 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_id uuid;
  v_job uuid;
  f1 jsonb; f2 jsonb; f3 jsonb; r jsonb;
  c public.comprovantes;
  j public.ai_jobs;
begin
  begin
    v_id := pg_temp._chegada();
    perform pg_temp._guardar(v_id);
    v_job := pg_temp._job_de(v_id);
    perform pg_temp._concluir(v_job, pg_temp._saida(pg_temp._sha_de(v_id), 'nfce', 'alta', '{}', '{}', 'OCR COM CPF 123.456.789-09'));
    f1 := public.comprovante_entrega_falhou(v_job);
    f2 := public.comprovante_entrega_falhou(v_job);
    f3 := public.comprovante_entrega_falhou(v_job);
    r := public.comprovante_aplicar_leitura(v_job);
    select * into c from public.comprovantes where id = v_id;
    select * into j from public.ai_jobs where id = v_job;
    insert into _resultado values ('T23 entrega que lança desiste na 3ª e segue ao assistente',
      not (f1->>'desistiu')::boolean and (f1->>'tentativas')::int = 1 and not (f2->>'desistiu')::boolean
      and (f3->>'desistiu')::boolean and (f3->>'encaminhar')::boolean and f3->>'texto_para_assistente' = '[image]'
      and c.situacao = 'falhou' and c.erro = 'entrega_falhou' and c.numero is null
      and c.arquivo_apagar_apos = c.recebido_em + interval '7 days'
      and j.metadata ? 'entregue_em' and not (j.input->'arquivo' ? 'url') and not (j.response->'data' ? 'texto')
      and j.response::text not like '%123.456.789-09%'
      and r->>'decisao' = 'ignorado',
      'tentativas ' || (f1->>'tentativas') || '/' || (f2->>'tentativas') || '/' || (f3->>'tentativas')
      || ' desistiu=' || (f3->>'desistiu') || ' ' || c.situacao || '/' || coalesce(c.erro, '-') || '; depois ' || (r->>'decisao'));
  exception when others then
    insert into _resultado values ('T23 entrega que lança desiste na 3ª e segue ao assistente', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T24 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_q text := pg_temp._telefone();
  v_id uuid;
  a1 jsonb; a2 jsonb; a3 jsonb; f1 jsonb; f5 jsonb;
  v_espera integer;
  c public.comprovantes;
begin
  begin
    v_id := pg_temp._chegada(p_forcado => true, p_legenda => 'cupom', p_phone => v_q);
    perform pg_temp._ler(v_id, 'nfce', 'alta');
    a1 := public.comprovante_reservar_aviso(v_q, true);
    f1 := public.comprovante_aviso_falhou(array[v_id]);
    select extract(epoch from (aviso_proximo_em - now()))::int into v_espera from public.comprovantes where id = v_id;
    a2 := public.comprovante_reservar_aviso(v_q, true);           -- ainda não é a vez dele
    update public.comprovantes set aviso_proximo_em = now() - interval '1 second' where id = v_id;
    a3 := public.comprovante_reservar_aviso(v_q, true);           -- agora sai
    update public.comprovantes set aviso_tentativas = 4 where id = v_id;
    f5 := public.comprovante_aviso_falhou(array[v_id]);
    select * into c from public.comprovantes where id = v_id;
    insert into _resultado values ('T24 aviso que não saiu volta com espera; na 5ª desiste',
      jsonb_array_length(a1->'itens') = 1 and (f1->>'liberados')::int = 1 and v_espera between 290 and 300
      and jsonb_array_length(a2->'itens') = 0 and jsonb_array_length(a3->'itens') = 1
      and (f5->>'desistiu')::int = 1 and c.avisado_em is not null and c.aviso_tentativas = 5,
      'itens ' || jsonb_array_length(a1->'itens') || '/' || jsonb_array_length(a2->'itens') || '/'
      || jsonb_array_length(a3->'itens') || ' espera ' || v_espera || 's; desistiu ' || (f5->>'desistiu'));
  exception when others then
    insert into _resultado values ('T24 aviso que não saiu volta com espera; na 5ª desiste', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T25 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_nao uuid;
  v_cmp uuid;
  n public.comprovantes;
  c public.comprovantes;
begin
  begin
    v_nao := pg_temp._chegada(p_modo => 'dono', p_rota => 'ambos', p_legenda => 'olha isso');
    perform pg_temp._ler(v_nao);                                 -- nao_documento
    update public.comprovantes set nome_arquivo = 'foto.jpg', dica_da_legenda = 'isso' where id = v_nao;
    v_cmp := pg_temp._chegada(p_forcado => true, p_legenda => 'cupom');
    perform pg_temp._ler(v_cmp, 'nfce', 'alta');
    perform public.comprovante_arquivo_apagado(v_nao);
    perform public.comprovante_arquivo_apagado(v_cmp);
    select * into n from public.comprovantes where id = v_nao;
    select * into c from public.comprovantes where id = v_cmp;
    insert into _resultado values ('T25 apagar o original leva o texto do não comprovante',
      n.situacao = 'nao_comprovante' and n.arquivo_apagado_em is not null
      and n.legenda is null and n.dica_da_legenda is null and n.nome_arquivo is null and n.tipo = 'nao_documento'
      and c.situacao = 'lido' and c.legenda = 'cupom',
      'não comprovante: legenda ' || coalesce(n.legenda, 'apagada') || '; CMP: legenda ' || coalesce(c.legenda, '-'));
  exception when others then
    insert into _resultado values ('T25 apagar o original leva o texto do não comprovante', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T26 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_id uuid;
  v_msg uuid;
  m1 jsonb; m2 jsonb; r jsonb;
  c public.comprovantes;
begin
  begin
    v_id := pg_temp._chegada();
    select whatsapp_message_id into v_msg from public.comprovantes where id = v_id;
    m1 := public.comprovante_ja_encaminhado(v_msg);
    m2 := public.comprovante_ja_encaminhado(v_msg);
    r := pg_temp._ler(v_id);                                     -- nao_documento
    select * into c from public.comprovantes where id = v_id;
    insert into _resultado values ('T26 o webhook já encaminhou: o banco não repete',
      (m1->>'marcado')::boolean and not (m2->>'marcado')::boolean and not (r->>'encaminhar')::boolean
      and c.encaminhamento = 'chegada' and (public.comprovante_ja_encaminhado(gen_random_uuid())->>'marcado') = 'false',
      'marcado ' || (m1->>'marcado') || '/' || (m2->>'marcado') || '; encaminhar depois da leitura ' || (r->>'encaminhar'));
  exception when others then
    insert into _resultado values ('T26 o webhook já encaminhou: o banco não repete', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
