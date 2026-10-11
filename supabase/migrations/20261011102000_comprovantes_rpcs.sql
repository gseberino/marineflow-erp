-- Comprovantes F1 (11/10/2026): RPCs de chegada, leitura, aviso e vigia (contrato BANCO ↔ EDGE).
--
-- Quem chama: só a edge comprovantes-whatsapp, com a service role. Todas security definer,
-- search_path vazio, execute só para service_role. Erro de entrada = 22023; dono inválido = 42501.
-- Nenhuma RPC devolve leitura_texto. Nenhuma grava em tabela financeira.
--
--   1  comprovante_receber(p)                 linha nova (idempotente por wa_message_id)
--   2  comprovante_guardar_arquivo(id, a, url) arquivo no bucket → CMP repetido? senão job de leitura
--   3  comprovante_download_falhou(id, erro)  nova tentativa em 5 e 15 min; depois falhou
--   4  comprovante_pedir_leitura(id, url)     o ÚNICO reenfileiramento (decisão 3)
--   5  comprovante_aplicar_leitura(job)       decide cmp | nao_comprovante | cancelado | duplicado | falhou | reenfileirar
--   6  comprovante_falhou(id, erro)           falha final do lado da edge
--   7  comprovante_reservar_aviso(phone, f)   itens do aviso consolidado (modo dono)
--   8  comprovante_no_dropbox(...)            cópia gravada em _A CLASSIFICAR
--   9  comprovante_dropbox_falhou(id, erro)   backoff 5, 15, 60, 180 min; desiste na 5ª
--   10 comprovante_arquivo_apagado(id)
--   11 comprovantes_vigia_lote(limite)        manutenção + reserva do que a edge faz (+ rede de 1 h)
--   12 comprovantes_relatorio_sombra(desde)   só contagens
--   13 comprovante_entrega_falhou(job)        a entrega lançou: conta e desiste na 3ª
--   14 comprovante_aviso_falhou(ids)          o aviso não saiu: o vigia tenta de novo (5, 15, 60, 180 min)
--   15 comprovante_ja_encaminhado(mensagem)   o webhook já mandou ao assistente (prazo do receber)
--
-- Helpers internos (sem grant): _comprovante_dono, _comprovante_dados_do_arquivo,
-- _comprovante_criar_job, _comprovante_encaminhar.
-- Não escreve dados. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- Helpers internos
-- ---------------------------------------------------------------------------------------------

-- O dono: 1º admin ativo com o assistente no WhatsApp e telefone, por created_at
-- (a mesma regra de lembretes-de-revisao e de _shared/whatsapp/dono.ts).
create or replace function public._comprovante_dono()
returns table (id uuid, phone text)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.phone_normalized
    from public.app_users u
   where u.role = 'admin' and u.active and u.ai_whatsapp_enabled and u.phone_normalized is not null
   order by u.created_at asc
   limit 1;
$$;

-- Forma DadosDoArquivo (DA) do contrato: o que a edge precisa para nomear e subir no Dropbox.
create or replace function public._comprovante_dados_do_arquivo(p public.comprovantes)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'codigo', p.codigo,
    'situacao', p.situacao,
    'tipo', p.tipo,
    'valor', p.valor::text,
    'valor_confianca', p.valor_confianca,
    'data_compra', p.data_compra,
    'hora_compra', p.hora_compra,
    'recebido_em', p.recebido_em,
    'fornecedor_nome', p.fornecedor_nome,
    'arquivo_path', p.arquivo_path,
    'arquivo_mime', p.arquivo_mime);
$$;

-- Cria o job de leitura em ai_jobs (contrato v1 de entrada: sem legenda, nome de arquivo ou telefone).
create or replace function public._comprovante_criar_job(p_id uuid, p_url text, p_tentativa smallint)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_job uuid;
  v_local timestamp;
  v_min integer;
  v_iso text;
begin
  select * into c from public.comprovantes x where x.id = p_id;
  if not found or c.arquivo_path is null or c.arquivo_sha256 is null then
    raise exception 'comprovantes: linha % sem arquivo guardado', p_id using errcode = '22023';
  end if;

  -- recebido_em em ISO com o deslocamento de São Paulo (ex.: 2026-10-10T19:40:57-03:00)
  v_local := c.recebido_em at time zone 'America/Sao_Paulo';
  v_min := round(extract(epoch from (v_local - (c.recebido_em at time zone 'UTC'))) / 60)::integer;
  v_iso := to_char(v_local, 'YYYY-MM-DD"T"HH24:MI:SS')
           || case when v_min < 0 then '-' else '+' end
           || lpad((abs(v_min) / 60)::text, 2, '0') || ':' || lpad((abs(v_min) % 60)::text, 2, '0');

  insert into public.ai_jobs (
    source, requested_by, provider, model, task_profile, response_format, prompt,
    priority, timeout_seconds, max_attempts, allow_fallback, deadline_at, input, metadata
  ) values (
    'marineflow', c.dono_id, 'local-doc', 'leitor-v1', 'comprovante', 'json', 'ler_comprovante',
    case when c.origem = 'repescagem' then 10
         when c.modo = 'sombra' then 20
         when c.rota = 'ambos' then 30
         else 40 end,
    180, 2, false, now() + interval '24 hours',
    jsonb_build_object(
      'versao', 1,
      'comprovante_id', c.id,
      'modo', case when c.forcado or c.arquivo_mime in ('application/pdf', 'application/xml', 'text/xml')
                   then 'completo' else 'triagem' end,
      'arquivo', jsonb_build_object(
        'url', p_url,
        'caminho', c.arquivo_path,
        'mime_declarado', c.mime_declarado,
        'mime_real', c.arquivo_mime,
        'bytes', c.arquivo_bytes,
        'sha256', c.arquivo_sha256),
      'origem', jsonb_build_object(
        'canal', 'whatsapp',
        'tipo_whatsapp', c.tipo_whatsapp,
        'recebido_em', v_iso,
        'forcado', c.forcado)),
    jsonb_build_object('tipo', 'comprovante_leitura', 'versao', 1, 'comprovante_id', c.id, 'tentativa', p_tentativa)
  )
  returning id into v_job;
  return v_job;
end $$;

-- Encaminhar ao assistente (seção 3.4): só o banco decide e reserva, na mesma transação de quem chama
-- (que já segura a linha com for update e já gravou a situação nova).
--   * só modo dono, rota comprovante, origem webhook, uma vez;
--   * só nao_comprovante, cancelado por tela_erro/recebimento, ou falhou sem legenda-chave;
--   * sem legenda (placeholder): no máximo um por telefone a cada 120 s; os demais ficam
--     'dispensado_agrupado' (um lote de 20 fotos não vira 20 turnos do assistente).
-- O texto sai das colunas da PRÓPRIA linha, gravadas na chegada (a mesma regra do body do
-- webhook: legenda; senão o nome do arquivo no documento; senão "[image]"/"[document]"). Nunca
-- relê whatsapp_messages.body: o encaminhamento pode vir horas depois (decisão 3) e a equipe
-- consegue reescrever aquela linha — o assistente receberia, como se fosse do dono, um texto
-- escolhido por outra pessoa.
create or replace function public._comprovante_encaminhar(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_texto text;
  nao constant jsonb := jsonb_build_object('encaminhar', false, 'texto', null);
begin
  select * into c from public.comprovantes x where x.id = p_id;
  if not found
     or c.modo <> 'dono' or c.rota <> 'comprovante' or c.origem <> 'webhook'
     or c.encaminhado_ao_assistente_em is not null or c.encaminhamento is not null
     or not (c.situacao = 'nao_comprovante'
             or (c.situacao = 'cancelado' and c.motivo_cancelamento in ('leitura_tela_erro', 'leitura_recebimento'))
             or (c.situacao = 'falhou' and not c.forcado)) then
    return nao;
  end if;

  -- o mesmo texto que o webhook mandaria hoje, montado do que a linha guardou na chegada
  v_texto := left(coalesce(c.legenda,
                           case when c.tipo_whatsapp = 'document' then c.nome_arquivo end,
                           '[' || c.tipo_whatsapp || ']'), 4000);

  if c.legenda is null then
    perform pg_advisory_xact_lock(hashtextextended('comprovante:encaminhar:' || c.phone_normalized, 0));
    if exists (
      select 1 from public.comprovantes x
       where x.phone_normalized = c.phone_normalized
         and x.id <> c.id
         and x.legenda is null
         and x.encaminhamento = 'apos_leitura'
         and x.encaminhado_ao_assistente_em > now() - interval '120 seconds'
    ) then
      update public.comprovantes x set encaminhamento = 'dispensado_agrupado' where x.id = c.id;
      return nao;
    end if;
  end if;

  update public.comprovantes x
     set encaminhado_ao_assistente_em = now(), encaminhamento = 'apos_leitura'
   where x.id = c.id;
  return jsonb_build_object('encaminhar', true, 'texto', v_texto);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. comprovante_receber
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_receber(p jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  k text;
  v_message_id uuid;
  v_dono uuid;
  v_recebido timestamptz;
  v_wa text;
  v_phone text;
  v_modo text;
  v_rota text;
  v_origem text;
  v_tipo text;
  v_forcado boolean;
  v_id uuid;
  v_situacao text;
  v_novo boolean := false;
  v_key jsonb;
  v_jid text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'comprovante_receber: a entrada precisa ser um objeto' using errcode = '22023';
  end if;
  foreach k in array array['message_id', 'wa_message_id', 'phone_normalized', 'dono_id', 'modo', 'rota', 'origem',
                           'tipo_whatsapp', 'forcado', 'legenda', 'dica_da_legenda', 'nome_arquivo',
                           'mime_declarado', 'recebido_em'] loop
    if not (p ? k) then
      raise exception 'comprovante_receber: falta o campo %', k using errcode = '22023';
    end if;
  end loop;

  begin
    v_message_id := (p->>'message_id')::uuid;
    v_dono := (p->>'dono_id')::uuid;
    v_recebido := (p->>'recebido_em')::timestamptz;
  exception when others then
    raise exception 'comprovante_receber: message_id, dono_id ou recebido_em malformado' using errcode = '22023';
  end;
  v_wa := p->>'wa_message_id';
  v_phone := p->>'phone_normalized';
  v_modo := p->>'modo';
  v_rota := p->>'rota';
  v_origem := p->>'origem';
  v_tipo := p->>'tipo_whatsapp';

  if v_message_id is null or v_dono is null or v_recebido is null then
    raise exception 'comprovante_receber: message_id, dono_id e recebido_em são obrigatórios' using errcode = '22023';
  end if;
  if v_wa is null or char_length(v_wa) not between 1 and 128 then
    raise exception 'comprovante_receber: wa_message_id inválido' using errcode = '22023';
  end if;
  if v_phone is null or v_phone !~ '^[0-9]{10,15}$' then
    raise exception 'comprovante_receber: phone_normalized inválido' using errcode = '22023';
  end if;
  if v_modo is null or v_modo not in ('sombra', 'dono') then
    raise exception 'comprovante_receber: modo inválido' using errcode = '22023';
  end if;
  if v_rota is null or v_rota not in ('comprovante', 'ambos') then
    raise exception 'comprovante_receber: rota inválida' using errcode = '22023';
  end if;
  if v_origem is null or v_origem not in ('webhook', 'repescagem') then
    raise exception 'comprovante_receber: origem inválida' using errcode = '22023';
  end if;
  -- a repescagem nunca foi ao assistente na chegada: entra sempre na rota comprovante
  if v_origem = 'repescagem' and v_rota <> 'comprovante' then
    raise exception 'comprovante_receber: repescagem só na rota comprovante' using errcode = '22023';
  end if;
  if v_tipo is null or v_tipo not in ('image', 'document') then
    raise exception 'comprovante_receber: tipo_whatsapp inválido' using errcode = '22023';
  end if;
  if jsonb_typeof(p->'forcado') is distinct from 'boolean' then
    raise exception 'comprovante_receber: forcado precisa ser booleano' using errcode = '22023';
  end if;
  v_forcado := (p->>'forcado')::boolean;

  -- o dono é UM só (o mesmo de _shared/whatsapp/dono.ts): outro admin não abre linha aqui
  if not public.is_admin(v_dono) or v_dono is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception 'comprovante_receber: dono inválido' using errcode = '42501';
  end if;

  -- defesa em profundidade (a edge já confere): a mensagem existe, foi RECEBIDA, é deste telefone e
  -- tem este wa_message_id
  if not exists (
    select 1 from public.whatsapp_messages m
     where m.id = v_message_id and m.direction = 'inbound'
       and m.phone_normalized = v_phone and m.wa_message_id = v_wa
  ) then
    raise exception 'comprovante_receber: a mensagem não confere' using errcode = '22023';
  end if;

  -- a key da Evolution (opcional; sem ela o download falha com sem_chave): do próprio telefone,
  -- recebida (fromMe falso) e com o mesmo id. Guarda só as chaves que o download usa.
  v_key := p->'wa_key';
  if v_key is not null and jsonb_typeof(v_key) <> 'null' then
    v_jid := v_key->>'remoteJid';
    if v_jid like '%@lid' then
      v_jid := coalesce(nullif(v_key->>'senderPn', ''), nullif(v_key->>'remoteJidAlt', ''), v_jid);
    end if;
    if jsonb_typeof(v_key) <> 'object' or v_key->>'id' is distinct from v_wa
       or coalesce(v_key->>'fromMe', 'false') = 'true'
       or v_jid is null
       or right(regexp_replace(split_part(v_jid, '@', 1), '[^0-9]', '', 'g'), 8) <> right(v_phone, 8) then
      raise exception 'comprovante_receber: a key da mensagem não é deste telefone' using errcode = '22023';
    end if;
    v_key := jsonb_strip_nulls(jsonb_build_object(
      'id', v_wa,
      'remoteJid', left(v_key->>'remoteJid', 128),
      'fromMe', false,
      'senderPn', left(nullif(v_key->>'senderPn', ''), 128),
      'remoteJidAlt', left(nullif(v_key->>'remoteJidAlt', ''), 128)));
  else
    v_key := null;
  end if;

  insert into public.comprovantes (
    whatsapp_message_id, wa_message_id, wa_key, phone_normalized, dono_id, modo, rota, origem, tipo_whatsapp,
    forcado, legenda, dica_da_legenda, nome_arquivo, mime_declarado, recebido_em,
    encaminhado_ao_assistente_em, encaminhamento
  ) values (
    v_message_id, v_wa, v_key, v_phone, v_dono, v_modo, v_rota, v_origem, v_tipo,
    v_forcado,
    left(nullif(btrim(p->>'legenda'), ''), 1024),
    left(nullif(btrim(p->>'dica_da_legenda'), ''), 1024),
    left(nullif(btrim(p->>'nome_arquivo'), ''), 255),
    left(nullif(btrim(p->>'mime_declarado'), ''), 100),
    v_recebido,
    -- rota 'ambos': a mensagem foi ao assistente na chegada (decisão 2)
    case when v_rota = 'ambos' then now() end,
    case when v_rota = 'ambos' then 'chegada' end
  )
  on conflict (wa_message_id) do nothing
  returning id, situacao into v_id, v_situacao;

  if v_id is null then
    select x.id, x.situacao into v_id, v_situacao from public.comprovantes x where x.wa_message_id = v_wa;
  else
    v_novo := true;
  end if;

  return jsonb_build_object('id', v_id, 'novo', v_novo, 'situacao', v_situacao);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. comprovante_guardar_arquivo
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_guardar_arquivo(p_id uuid, p_arquivo jsonb, p_url text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_dup public.comprovantes;
  v_path text;
  v_mime text;
  v_bytes integer;
  v_sha text;
  v_job uuid;
  v_decisao text;
  v_apagar boolean := false;
begin
  if p_id is null then
    raise exception 'comprovante_guardar_arquivo: id obrigatório' using errcode = '22023';
  end if;
  if p_url is null or left(p_url, 8) <> 'https://'
     or position('/storage/v1/object/sign/comprovantes/' in p_url) = 0 then
    raise exception 'comprovante_guardar_arquivo: URL assinada inválida' using errcode = '22023';
  end if;
  if p_arquivo is null or jsonb_typeof(p_arquivo) <> 'object' then
    raise exception 'comprovante_guardar_arquivo: arquivo precisa ser um objeto' using errcode = '22023';
  end if;
  v_path := p_arquivo->>'path';
  v_mime := p_arquivo->>'mime_real';
  v_sha := lower(p_arquivo->>'sha256');
  begin
    v_bytes := (p_arquivo->>'bytes')::integer;
  exception when others then
    raise exception 'comprovante_guardar_arquivo: bytes malformado' using errcode = '22023';
  end;
  -- um objeto por linha: o caminho tem de ser AAAA/MM/<este id>.<ext>
  if v_path is null or v_path !~ '^[0-9]{4}/[0-9]{2}/[0-9a-f-]{36}\.(jpg|png|webp|heic|pdf|xml)$'
     or split_part(split_part(v_path, '/', 3), '.', 1) <> p_id::text then
    raise exception 'comprovante_guardar_arquivo: caminho inválido' using errcode = '22023';
  end if;
  if v_mime is null or v_mime not in ('image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
                                      'application/pdf', 'application/xml', 'text/xml') then
    raise exception 'comprovante_guardar_arquivo: mime_real inválido' using errcode = '22023';
  end if;
  if v_bytes is null or v_bytes not between 1 and 15728640 then
    raise exception 'comprovante_guardar_arquivo: tamanho inválido' using errcode = '22023';
  end if;
  if v_sha is null or v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'comprovante_guardar_arquivo: sha256 inválido' using errcode = '22023';
  end if;

  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found then
    raise exception 'comprovante_guardar_arquivo: comprovante % não existe', p_id using errcode = '22023';
  end if;
  if c.situacao <> 'recebido' or c.arquivo_path is not null then
    return jsonb_build_object('id', c.id, 'situacao', c.situacao, 'ja_guardado', true);
  end if;

  -- dois arquivos iguais chegando juntos: um decide de cada vez
  perform pg_advisory_xact_lock(hashtextextended(v_sha, 0));

  update public.comprovantes x
     set arquivo_path = v_path, arquivo_mime = v_mime, arquivo_bytes = v_bytes, arquivo_sha256 = v_sha,
         download_proxima_em = null
   where x.id = p_id
  returning * into c;

  select * into v_dup from public.comprovantes x
   where x.arquivo_sha256 = v_sha and x.id <> p_id and x.numero is not null and x.situacao <> 'cancelado'
   order by x.numero
   limit 1;

  if found then
    -- os mesmos bytes já são um CMP vivo: cancela, sem job; o objeto deste pode sair na hora
    update public.comprovantes x
       set situacao = 'cancelado', motivo_cancelamento = 'arquivo_repetido', duplicado_de = v_dup.id,
           arquivo_apagar_apos = now()
     where x.id = p_id
    returning * into c;
    v_decisao := 'duplicado';
    v_apagar := true;
  else
    -- legenda-chave: o dono afirmou que é comprovante, o número nasce na chegada (decisão 4)
    if c.forcado and c.numero is null then
      update public.comprovantes x set numero = public._comprovante_proximo_numero()
       where x.id = p_id
      returning * into c;
    end if;
    v_job := public._comprovante_criar_job(p_id, p_url, 1::smallint);
    update public.comprovantes x set situacao = 'na_fila', job_id = v_job, leituras = 1
     where x.id = p_id
    returning * into c;
    v_decisao := 'na_fila';
  end if;

  return jsonb_build_object(
    'id', c.id,
    'decisao', v_decisao,
    'situacao', c.situacao,
    'codigo', c.codigo,
    'job_id', v_job,
    'duplicado', case when v_decisao = 'duplicado' then
                   jsonb_build_object('codigo', v_dup.codigo, 'data_compra', v_dup.data_compra, 'valor', v_dup.valor::text)
                 end,
    'modo', c.modo,
    'rota', c.rota,
    'forcado', c.forcado,
    'phone_normalized', c.phone_normalized,
    'wa_message_id', c.wa_message_id,
    'apagar_arquivo_agora', v_apagar);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. comprovante_download_falhou
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_download_falhou(p_id uuid, p_erro text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_n smallint;
  v_final boolean := false;
  v_erro text;
  v_prox timestamptz;
  v_enc jsonb := jsonb_build_object('encaminhar', false, 'texto', null);
  v_ignorado boolean := false;
begin
  if p_erro is null or p_erro not in ('midia_indisponivel', 'evolution_fora', 'upload_falhou', 'sem_chave') then
    raise exception 'comprovante_download_falhou: erro desconhecido' using errcode = '22023';
  end if;
  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found then
    raise exception 'comprovante_download_falhou: comprovante % não existe', p_id using errcode = '22023';
  end if;

  if c.situacao <> 'recebido' then
    -- outro caminho (vigia/webhook) já decidiu esta linha: não mexe
    v_ignorado := true;
    v_final := c.situacao = 'falhou';
  else
    v_n := c.download_tentativas + 1;
    if p_erro = 'sem_chave' then
      v_final := true; v_erro := 'sem_chave';             -- payload sem data.key: não adianta tentar de novo
    elsif c.origem = 'repescagem' then
      v_final := true; v_erro := 'midia_expirada';        -- mídia antiga: uma tentativa só
    elsif v_n >= 3 then
      v_final := true; v_erro := 'midia_indisponivel';
    else
      v_prox := now() + case when v_n = 1 then interval '5 minutes' else interval '15 minutes' end;
    end if;

    update public.comprovantes x
       set download_tentativas = v_n,
           download_proxima_em = v_prox,
           situacao = case when v_final then 'falhou' else x.situacao end,
           erro = case when v_final then v_erro else x.erro end
     where x.id = p_id
    returning * into c;

    if v_final and not c.forcado then
      v_enc := public._comprovante_encaminhar(c.id);
    end if;
  end if;

  return jsonb_build_object(
    'id', c.id,
    'final', v_final,
    'proxima_em', v_prox,
    'situacao', c.situacao,
    'encaminhar', coalesce((v_enc->>'encaminhar')::boolean, false),
    'texto_para_assistente', v_enc->>'texto',
    'modo', c.modo,
    'forcado', c.forcado,
    'phone_normalized', c.phone_normalized,
    'wa_message_id', c.wa_message_id,
    'dono_id', c.dono_id,
    'ignorado', v_ignorado);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. comprovante_pedir_leitura (o único reenfileiramento, decisão 3)
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_pedir_leitura(p_id uuid, p_url text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  j public.ai_jobs;
  v_job uuid;
begin
  if p_url is null or left(p_url, 8) <> 'https://'
     or position('/storage/v1/object/sign/comprovantes/' in p_url) = 0 then
    raise exception 'comprovante_pedir_leitura: URL assinada inválida' using errcode = '22023';
  end if;
  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found then
    return jsonb_build_object('id', p_id, 'ok', false, 'motivo', 'nao_encontrado');
  end if;
  if c.situacao <> 'na_fila' then
    return jsonb_build_object('id', c.id, 'ok', false, 'motivo', 'situacao_' || c.situacao);
  end if;
  if c.reenfileirado then
    return jsonb_build_object('id', c.id, 'ok', false, 'motivo', 'ja_reenfileirado');
  end if;
  if c.arquivo_apagado_em is not null then
    return jsonb_build_object('id', c.id, 'ok', false, 'motivo', 'arquivo_apagado');
  end if;
  select * into j from public.ai_jobs x where x.id = c.job_id;
  if not found or j.status <> 'failed' then
    return jsonb_build_object('id', c.id, 'ok', false, 'motivo', 'job_nao_falhou');
  end if;
  if j.error_code is null or j.error_code not in ('deadline_exceeded', 'input_unavailable') then
    return jsonb_build_object('id', c.id, 'ok', false, 'motivo', 'erro_nao_reenfileiravel');
  end if;

  v_job := public._comprovante_criar_job(c.id, p_url, 2::smallint);
  update public.comprovantes x
     set job_id = v_job, reenfileirado = true, leituras = x.leituras + 1
   where x.id = c.id;
  return jsonb_build_object('id', c.id, 'ok', true, 'job_id', v_job);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. comprovante_aplicar_leitura
--    Idempotente pela marca metadata.entregue_em do job. Nunca deixa o texto do OCR em ai_jobs.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_aplicar_leitura(p_job_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  j public.ai_jobs;
  c public.comprovantes;
  v_dup public.comprovantes;
  v_cid uuid;
  d jsonb;
  v_decisao text;
  v_erro text;
  v_enc jsonb := jsonb_build_object('encaminhar', false, 'texto', null);
  v_subir boolean := false;
  v_valida boolean := false;
  v_tipo text;
  v_conf text;
  v_campos jsonb;
  v_confs jsonb;
  v_s text;
  v_alertas text[] := '{}';
  v_valor numeric(12,2);
  v_valor_conf text;
  v_data date;
  v_data_conf text;
  v_hora time;
  v_hora_conf text;
  v_pag text;
  v_cnpj text;
  v_cnpj_conf text;
  v_chave text;
  v_fav text;
  v_linha text;
  v_leitura jsonb;
  v_curta jsonb;
  v_texto text;
  v_versao_leitor text;
  v_sup_n integer;
  v_sup_id uuid;
  v_sup_nome text;
  v_numero integer;
  v_resumo jsonb;
begin
  if p_job_id is null then
    raise exception 'comprovante_aplicar_leitura: job obrigatório' using errcode = '22023';
  end if;

  select * into j from public.ai_jobs x where x.id = p_job_id for update;
  if not found or j.metadata->>'tipo' is distinct from 'comprovante_leitura'
     or j.status not in ('completed', 'failed', 'cancelled') then
    return jsonb_build_object('decisao', 'ignorado', 'job_id', p_job_id);
  end if;
  begin
    v_cid := (j.metadata->>'comprovante_id')::uuid;
  exception when others then
    v_cid := null;
  end;
  select * into c from public.comprovantes x where x.id = v_cid for update;
  if not found or j.metadata ? 'entregue_em' or c.job_id is distinct from p_job_id or c.situacao <> 'na_fila' then
    return jsonb_build_object('decisao', 'ignorado', 'job_id', p_job_id, 'id', c.id);
  end if;

  -- marca de entrega + a URL assinada sai do job (ela vale 24 h para quem a tiver). Não toca status.
  update public.ai_jobs x
     set metadata = x.metadata || jsonb_build_object('entregue_em', now()),
         input = case when x.input is null then null else x.input #- '{arquivo,url}' end
   where x.id = p_job_id;

  -- ── job que não concluiu ────────────────────────────────────────────────────────────────
  if j.status <> 'completed' then
    if j.error_code in ('deadline_exceeded', 'input_unavailable') and not c.reenfileirado
       and c.arquivo_apagado_em is null then
      v_decisao := 'reenfileirar';      -- nada muda na linha: o vigia pede a leitura de novo, uma vez
    else
      v_erro := left(coalesce(nullif(j.error_code, ''), j.status), 300);
    end if;
  else
    -- ── job concluído: confere o contrato v1 ──────────────────────────────────────────────
    d := j.response->'data';
    if d is null or jsonb_typeof(d) <> 'object' or d->>'versao' is distinct from '1'
       or jsonb_typeof(d->'classificacao') is distinct from 'object'
       or coalesce(d->'classificacao'->>'tipo', '') not in (
            'nfce', 'nfe_danfe', 'nfe_xml', 'nfse', 'cupom_nao_fiscal', 'pix', 'boleto_pago', 'boleto', 'cartao',
            'fatura', 'guia', 'recibo', 'agendado', 'recebimento', 'tela_erro', 'pedido', 'outro', 'nao_documento')
       or coalesce(d->'classificacao'->>'confianca', '') not in ('alta', 'media', 'baixa') then
      v_erro := 'saida_invalida';
    elsif lower(d->'arquivo'->>'sha256') is distinct from c.arquivo_sha256 then
      v_erro := 'sha_divergente';
    else
      v_valida := true;
    end if;

    if not v_valida then
      -- saída fora do contrato: o job guarda só a parte sem texto, mascarada (para diagnóstico)
      update public.ai_jobs x
         set response = jsonb_build_object(
               'format', coalesce(j.response->>'format', 'json'),
               'text', v_erro,
               'data', case when jsonb_typeof(d) = 'object'
                            then public._comprovante_mascarar_cpf((d #- '{texto}')::text)::jsonb end)
       where x.id = p_job_id;
    end if;
  end if;

  -- ── falha: CMP sem leitura sobe como "A LER"; sem número, segue ao assistente ────────────
  if v_erro is not null then
    update public.comprovantes x
       set situacao = 'falhou',
           erro = v_erro,
           -- +3 min: a entrega sobe na hora; o vigia só pega se ela falhar (sem upload em dobro)
           dropbox_proxima_em = case when x.numero is not null then now() + interval '3 minutes' else x.dropbox_proxima_em end,
           arquivo_apagar_apos = case when x.numero is null then x.recebido_em + interval '7 days' else x.arquivo_apagar_apos end
     where x.id = c.id
    returning * into c;
    if c.numero is null then
      v_enc := public._comprovante_encaminhar(c.id);
    else
      v_subir := true;
    end if;
    v_decisao := 'falhou';
  end if;

  -- ── leitura válida ────────────────────────────────────────────────────────────────────────
  if v_valida then
    v_tipo := d->'classificacao'->>'tipo';
    v_conf := d->'classificacao'->>'confianca';
    v_versao_leitor := left(d->'leitor'->>'versao', 64);
    v_campos := case when jsonb_typeof(d->'campos') = 'object' then d->'campos' else '{}'::jsonb end;
    v_confs := case when jsonb_typeof(d->'confianca_dos_campos') = 'object' then d->'confianca_dos_campos' else '{}'::jsonb end;
    if jsonb_typeof(d->'alertas') = 'array' then
      select coalesce(array_agg(left(public._comprovante_mascarar_cpf(a), 64)), '{}') into v_alertas
        from (select jsonb_array_elements_text(d->'alertas') as a limit 32) s
       where a is not null and a <> '';
    end if;

    -- campos: formato errado vira vazio + alerta (nunca derruba a entrega)
    v_s := v_campos->>'valor_total';
    if v_s is not null then
      if v_s ~ '^[0-9]{1,10}\.[0-9]{2}$' and v_s::numeric > 0 then
        v_valor := v_s::numeric;
        v_valor_conf := coalesce(nullif(v_confs->>'valor_total', ''), 'baixa');
      else
        v_alertas := v_alertas || 'campo_descartado:valor_total'::text;
      end if;
    end if;
    v_s := v_campos->>'data';
    if v_s is not null then
      begin
        if v_s !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
          raise exception 'data' using errcode = '22007';
        end if;
        v_data := v_s::date;
        v_data_conf := coalesce(nullif(v_confs->>'data', ''), 'baixa');
      exception when others then
        v_data := null;
        v_alertas := v_alertas || 'campo_descartado:data'::text;
      end;
      -- defesa: data depois do dia da chegada (São Paulo) não existe
      if v_data is not null and v_data > (c.recebido_em at time zone 'America/Sao_Paulo')::date then
        v_data := null;
        v_data_conf := null;
        v_alertas := v_alertas || 'data_futura'::text;
      end if;
    end if;
    v_s := v_campos->>'hora';
    if v_s is not null then
      if v_s ~ '^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$' then
        v_hora := v_s::time;
        v_hora_conf := coalesce(nullif(v_confs->>'hora', ''), 'baixa');
      else
        v_alertas := v_alertas || 'campo_descartado:hora'::text;
      end if;
    end if;
    v_s := v_campos->>'pagamento';
    if v_s is not null then
      if v_s in ('dinheiro', 'cheque', 'credito', 'debito', 'credito_loja', 'boleto', 'deposito', 'pix', 'transferencia', 'outro') then
        v_pag := v_s;
      else
        v_alertas := v_alertas || 'campo_descartado:pagamento'::text;
      end if;
    end if;
    v_s := upper(v_campos->>'emitente_cnpj');
    if v_s is not null then
      if v_s ~ '^[0-9A-Z]{12}[0-9]{2}$' then
        v_cnpj := v_s;
        v_cnpj_conf := coalesce(nullif(v_confs->>'emitente_cnpj', ''), 'baixa');
      else
        v_alertas := v_alertas || 'campo_descartado:emitente_cnpj'::text;
      end if;
    end if;
    v_s := upper(v_campos->>'chave44');
    if v_s is not null then
      if v_s ~ '^[0-9]{6}[0-9A-Z]{12}[0-9]{26}$' then
        v_chave := v_s;
      else
        v_alertas := v_alertas || 'campo_descartado:chave44'::text;
      end if;
    end if;
    v_s := v_campos->>'favorecido_doc';
    if v_s is not null then
      if upper(v_s) ~ '^[0-9A-Z]{12}[0-9]{2}$' then
        v_fav := upper(v_s);
      elsif v_s ~ '^\*\*\*\.\*\*\*\.[0-9]{3}-[0-9]{2}$' then
        v_fav := v_s;
      else
        v_alertas := v_alertas || 'campo_descartado:favorecido_doc'::text;   -- inclusive CPF sem máscara
      end if;
    end if;
    v_s := v_campos->>'linha_digitavel';
    if v_s is not null then
      if v_s ~ '^[0-9]{44,48}$' then
        v_linha := v_s;
      else
        v_alertas := v_alertas || 'campo_descartado:linha_digitavel'::text;
      end if;
    end if;
    -- confiança desconhecida vira 'baixa'
    if v_valor_conf not in ('alta', 'media', 'baixa') then v_valor_conf := 'baixa'; end if;
    if v_data_conf not in ('alta', 'media', 'baixa') then v_data_conf := 'baixa'; end if;
    if v_hora_conf not in ('alta', 'media', 'baixa') then v_hora_conf := 'baixa'; end if;
    if v_cnpj_conf not in ('alta', 'media', 'baixa') then v_cnpj_conf := 'baixa'; end if;

    -- a leitura curta (sem campos): o que fica do que não vira CMP
    v_curta := public._comprovante_mascarar_cpf(jsonb_build_object(
      'versao', 1,
      'leitor', d->'leitor',
      'arquivo', jsonb_build_object('mime_real', d->'arquivo'->'mime_real', 'paginas', d->'arquivo'->'paginas'),
      'classificacao', d->'classificacao',
      'alertas', to_jsonb(v_alertas),
      'tempo_total_ms', d->'tempo_total_ms')::text)::jsonb;
    if octet_length(v_curta::text) > 204800 then
      v_curta := jsonb_build_object('versao', 1, 'classificacao',
                   jsonb_build_object('tipo', v_tipo, 'confianca', v_conf), 'alertas', to_jsonb(v_alertas));
    end if;

    -- os mesmos bytes viraram CMP depois que este foi guardado (corrida entre dois iguais sem legenda)
    perform pg_advisory_xact_lock(hashtextextended(c.arquivo_sha256, 0));
    select * into v_dup from public.comprovantes x
     where x.arquivo_sha256 = c.arquivo_sha256 and x.id <> c.id and x.numero is not null and x.situacao <> 'cancelado'
     order by x.numero limit 1;
    if found then
      update public.comprovantes x
         set situacao = 'cancelado', motivo_cancelamento = 'arquivo_repetido', duplicado_de = v_dup.id,
             tipo = v_tipo, confianca = v_conf, alertas = v_alertas, leitor_versao = v_versao_leitor,
             lido_em = now(), leitura = v_curta, arquivo_apagar_apos = now()
       where x.id = c.id
      returning * into c;
      v_decisao := 'duplicado';
      v_leitura := v_curta;
    end if;

    -- 2. chave repetida: CMP vivo com a mesma chave → cancelado (o número já nascido fica queimado)
    if v_decisao is null and v_chave is not null then
      perform pg_advisory_xact_lock(hashtextextended('comprovante:chave:' || v_chave, 0));
      select * into v_dup from public.comprovantes x
       where x.chave_acesso = v_chave and x.id <> c.id and x.numero is not null and x.situacao <> 'cancelado'
       order by x.numero limit 1;
      if found then
        update public.comprovantes x
           set situacao = 'cancelado', motivo_cancelamento = 'chave_repetida', duplicado_de = v_dup.id,
               tipo = v_tipo, confianca = v_conf, alertas = v_alertas, leitor_versao = v_versao_leitor,
               chave_acesso = v_chave, lido_em = now(), leitura = v_curta,
               arquivo_apagar_apos = x.recebido_em + interval '7 days'
         where x.id = c.id
        returning * into c;
        v_decisao := 'duplicado';
        v_leitura := v_curta;
      end if;
    end if;

    -- 3. legenda-chave + tela de erro ou Pix recebido: cancelado com motivo, segue ao assistente
    if v_decisao is null and c.forcado and v_tipo in ('tela_erro', 'recebimento') then
      update public.comprovantes x
         set situacao = 'cancelado',
             motivo_cancelamento = case when v_tipo = 'tela_erro' then 'leitura_tela_erro' else 'leitura_recebimento' end,
             tipo = v_tipo, confianca = v_conf, alertas = v_alertas, leitor_versao = v_versao_leitor,
             lido_em = now(), leitura = v_curta, arquivo_apagar_apos = x.recebido_em + interval '7 days'
       where x.id = c.id
      returning * into c;
      v_enc := public._comprovante_encaminhar(c.id);
      v_decisao := 'cancelado';
      v_leitura := v_curta;
    end if;

    -- 4. não é compra: fica só a classificação (decisão 13); original por 7 dias
    if v_decisao is null and not public._comprovante_e_compra(v_tipo, v_conf, c.forcado) then
      update public.comprovantes x
         set situacao = 'nao_comprovante',
             tipo = v_tipo, confianca = v_conf, alertas = v_alertas, leitor_versao = v_versao_leitor,
             lido_em = now(), leitura = v_curta, arquivo_apagar_apos = x.recebido_em + interval '7 days'
       where x.id = c.id
      returning * into c;
      v_enc := public._comprovante_encaminhar(c.id);
      v_decisao := 'nao_comprovante';
      v_leitura := v_curta;
    end if;

    -- 5. é compra: vira CMP
    if v_decisao is null then
      v_leitura := public._comprovante_mascarar_cpf((d #- '{texto}')::text)::jsonb;
      if octet_length(v_leitura::text) > 204800 then
        v_alertas := v_alertas || 'leitura_reduzida'::text;
        v_leitura := v_curta || jsonb_build_object('campos', public._comprovante_mascarar_cpf(v_campos::text)::jsonb);
        if octet_length(v_leitura::text) > 204800 then
          v_leitura := v_curta;
        end if;
      end if;
      v_texto := left(nullif(d->'texto'->>'conteudo', ''), 30000);

      -- fornecedor só do cadastro, pelo CNPJ comparando só dígitos/letras (decisão 14)
      if v_cnpj is not null then
        select count(*) into v_sup_n from public.suppliers s
         where regexp_replace(upper(coalesce(s.cnpj_cpf, '')), '[^0-9A-Z]', '', 'g') = v_cnpj;
        if v_sup_n = 1 then
          select s.id, left(coalesce(nullif(btrim(s.trade_name), ''), s.name), 200) into v_sup_id, v_sup_nome
            from public.suppliers s
           where regexp_replace(upper(coalesce(s.cnpj_cpf, '')), '[^0-9A-Z]', '', 'g') = v_cnpj;
        elsif v_sup_n > 1 then
          v_alertas := v_alertas || 'fornecedor_ambiguo'::text;
        end if;
      end if;

      if c.numero is null then
        v_numero := public._comprovante_proximo_numero();
      else
        v_numero := c.numero;
      end if;

      update public.comprovantes x
         set numero = v_numero,
             situacao = 'lido',
             tipo = v_tipo, confianca = v_conf, leitor_versao = v_versao_leitor, lido_em = now(),
             valor = v_valor, valor_confianca = v_valor_conf,
             data_compra = v_data, data_confianca = v_data_conf,
             hora_compra = v_hora, hora_confianca = v_hora_conf,
             forma_pagamento = v_pag,
             emitente_cnpj = v_cnpj, cnpj_confianca = v_cnpj_conf,
             chave_acesso = v_chave, favorecido_doc = v_fav, linha_digitavel = v_linha,
             supplier_id = v_sup_id, fornecedor_nome = v_sup_nome,
             leitura = v_leitura, leitura_texto = v_texto,
             dropbox_proxima_em = now() + interval '3 minutes'
       where x.id = c.id
      returning * into c;
      v_decisao := 'cmp';
      v_subir := true;
    end if;

    -- alertas sem repetição, na ordem em que apareceram
    update public.comprovantes x
       set alertas = (select coalesce(array_agg(a order by o), '{}')
                        from (select a, min(o) as o from unnest(v_alertas) with ordinality as t(a, o) group by a) u)
     where x.id = c.id
    returning * into c;

    -- 6. o job fica só com o que foi gravado (sem o texto do OCR)
    update public.ai_jobs x
       set response = jsonb_build_object('format', 'json', 'text', v_tipo || ' ' || v_conf, 'data', v_leitura)
     where x.id = p_job_id;

    v_resumo := jsonb_build_object(
      'tipo', c.tipo,
      'confianca', c.confianca,
      'valor', c.valor::text,
      'valor_confianca', c.valor_confianca,
      'data_compra', c.data_compra,
      'hora_compra', c.hora_compra,
      'fornecedor_nome', c.fornecedor_nome,
      'emitente_cnpj', c.emitente_cnpj,
      'cnpj_confianca', c.cnpj_confianca,
      'forma_pagamento', c.forma_pagamento,
      'alertas', to_jsonb(c.alertas));
  end if;

  return jsonb_build_object(
    'id', c.id,
    'decisao', v_decisao,
    'situacao', c.situacao,
    'codigo', c.codigo,
    'modo', c.modo,
    'rota', c.rota,
    'forcado', c.forcado,
    'phone_normalized', c.phone_normalized,
    'wa_message_id', c.wa_message_id,
    'dono_id', c.dono_id,
    'encaminhar', coalesce((v_enc->>'encaminhar')::boolean, false),
    'texto_para_assistente', v_enc->>'texto',
    'subir_dropbox', v_subir,
    'apagar_arquivo_agora', false,
    'arquivo', case when v_subir then public._comprovante_dados_do_arquivo(c) end,
    'resumo', v_resumo);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. comprovante_falhou (falha final do lado da edge, antes de guardar o arquivo)
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_falhou(p_id uuid, p_erro text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_enc jsonb := jsonb_build_object('encaminhar', false, 'texto', null);
  v_ignorado boolean := false;
begin
  if p_erro is null or p_erro not in ('formato_nao_suportado', 'arquivo_grande', 'sem_midia', 'dono_divergente') then
    raise exception 'comprovante_falhou: erro desconhecido' using errcode = '22023';
  end if;
  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found then
    raise exception 'comprovante_falhou: comprovante % não existe', p_id using errcode = '22023';
  end if;

  if c.situacao <> 'recebido' then
    v_ignorado := true;
  else
    update public.comprovantes x
       set situacao = 'falhou', erro = p_erro, download_proxima_em = null
     where x.id = p_id
    returning * into c;
    if not c.forcado then
      v_enc := public._comprovante_encaminhar(c.id);
    end if;
  end if;

  return jsonb_build_object(
    'id', c.id,
    'final', c.situacao = 'falhou',
    'proxima_em', null,
    'situacao', c.situacao,
    'encaminhar', coalesce((v_enc->>'encaminhar')::boolean, false),
    'texto_para_assistente', v_enc->>'texto',
    'modo', c.modo,
    'forcado', c.forcado,
    'phone_normalized', c.phone_normalized,
    'wa_message_id', c.wa_message_id,
    'dono_id', c.dono_id,
    'ignorado', v_ignorado);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. comprovante_reservar_aviso (modo dono): espera a fila do telefone esvaziar, ou 10 min
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_reservar_aviso(p_phone text, p_forcar boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_esperando integer;
  v_mais_antigo timestamptz;
  v_itens jsonb;
begin
  if p_phone is null or p_phone !~ '^[0-9]{10,15}$' then
    raise exception 'comprovante_reservar_aviso: telefone inválido' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('comprovante:aviso:' || p_phone, 0));

  select count(*) into v_esperando
    from public.comprovantes x
   where x.phone_normalized = p_phone and x.modo = 'dono' and x.situacao in ('recebido', 'na_fila');

  -- aviso que já falhou espera a vez dele (aviso_proximo_em, ver comprovante_aviso_falhou)
  select min(x.recebido_em) into v_mais_antigo
    from public.comprovantes x
   where x.phone_normalized = p_phone and x.modo = 'dono' and x.avisado_em is null
     and (x.aviso_proximo_em is null or x.aviso_proximo_em <= now())
     and ((x.situacao in ('lido', 'falhou') and x.numero is not null)
          or (x.situacao = 'cancelado' and x.motivo_cancelamento in ('arquivo_repetido', 'chave_repetida'))
          or (x.situacao = 'falhou' and x.forcado and x.numero is null));

  if v_mais_antigo is null
     or (v_esperando > 0 and not coalesce(p_forcar, false) and v_mais_antigo > now() - interval '10 minutes') then
    return jsonb_build_object('esperando', v_esperando, 'itens', '[]'::jsonb);
  end if;

  with alvo as (
    select x.id
      from public.comprovantes x
     where x.phone_normalized = p_phone and x.modo = 'dono' and x.avisado_em is null
       and (x.aviso_proximo_em is null or x.aviso_proximo_em <= now())
       and ((x.situacao in ('lido', 'falhou') and x.numero is not null)
            or (x.situacao = 'cancelado' and x.motivo_cancelamento in ('arquivo_repetido', 'chave_repetida'))
            or (x.situacao = 'falhou' and x.forcado and x.numero is null))
     for update
  ), marcados as (
    update public.comprovantes x set avisado_em = now()
      from alvo
     where x.id = alvo.id
    returning x.id, x.codigo, x.numero, x.situacao, x.tipo, x.valor, x.valor_confianca, x.data_compra,
              x.fornecedor_nome, x.emitente_cnpj, x.cnpj_confianca, x.recebido_em, x.erro, x.duplicado_de
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id,
           'codigo', m.codigo,
           'decisao', case when m.numero is not null and m.situacao = 'lido' then 'cmp'
                           when m.numero is not null and m.situacao = 'falhou' then 'cmp_sem_leitura'
                           when m.situacao = 'cancelado' then 'duplicado'
                           else 'nao_guardado' end,
           'tipo', m.tipo,
           'valor', m.valor::text,
           'valor_confianca', m.valor_confianca,
           'data_compra', m.data_compra,
           'fornecedor_nome', m.fornecedor_nome,
           'emitente_cnpj', m.emitente_cnpj,
           'cnpj_confianca', m.cnpj_confianca,
           'recebido_em', m.recebido_em,
           'erro', m.erro,
           'duplicado', case when m.situacao = 'cancelado' and o.id is not null then
                          jsonb_build_object('codigo', o.codigo, 'data_compra', o.data_compra, 'valor', o.valor::text)
                        end
         ) order by m.recebido_em, m.id), '[]'::jsonb)
    into v_itens
    from marcados m
    left join public.comprovantes o on o.id = m.duplicado_de;

  return jsonb_build_object('esperando', v_esperando, 'itens', v_itens);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. comprovante_no_dropbox
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_no_dropbox(p_id uuid, p_dropbox_id text, p_caminho text, p_rev text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_dropbox_id is null or p_dropbox_id !~ '^id:[A-Za-z0-9_-]+$' then
    raise exception 'comprovante_no_dropbox: id do Dropbox inválido' using errcode = '22023';
  end if;
  update public.comprovantes x
     set dropbox_id = p_dropbox_id,
         dropbox_caminho = left(p_caminho, 1000),
         dropbox_rev = left(p_rev, 100),
         dropbox_erro = null,
         dropbox_proxima_em = null
   where x.id = p_id;
  if not found then
    raise exception 'comprovante_no_dropbox: comprovante % não existe', p_id using errcode = '22023';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. comprovante_dropbox_falhou: próxima em 5, 15, 60 e 180 min; na 5ª desiste
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_dropbox_falhou(p_id uuid, p_erro text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_n smallint;
  v_prox timestamptz;
begin
  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found then
    raise exception 'comprovante_dropbox_falhou: comprovante % não existe', p_id using errcode = '22023';
  end if;
  if c.dropbox_id is not null then
    -- já subiu (outra tentativa venceu): não conta falha
    return jsonb_build_object('tentativas', c.dropbox_tentativas, 'proxima_em', null, 'desistiu', false);
  end if;
  v_n := c.dropbox_tentativas + 1;
  v_prox := case v_n
              when 1 then now() + interval '5 minutes'
              when 2 then now() + interval '15 minutes'
              when 3 then now() + interval '60 minutes'
              when 4 then now() + interval '180 minutes'
              else null end;
  update public.comprovantes x
     set dropbox_tentativas = v_n,
         dropbox_proxima_em = v_prox,
         dropbox_erro = left(coalesce(nullif(p_erro, ''), 'erro'), 300)
   where x.id = p_id;
  return jsonb_build_object('tentativas', v_n, 'proxima_em', v_prox, 'desistiu', v_prox is null);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. comprovante_arquivo_apagado (arquivo_path fica como histórico)
--     Do que não é CMP vivo (não comprovante, falha sem número, cancelado) sai também o texto do
--     dono — legenda, dica e nome do arquivo (decisão 13: fica só a classificação). O
--     encaminhamento ao assistente já usou esse texto na decisão, dias antes.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_arquivo_apagado(p_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.comprovantes x
     set arquivo_apagado_em = coalesce(x.arquivo_apagado_em, now()),
         legenda = case when x.numero is null or x.situacao = 'cancelado' then null else x.legenda end,
         dica_da_legenda = case when x.numero is null or x.situacao = 'cancelado' then null else x.dica_da_legenda end,
         nome_arquivo = case when x.numero is null or x.situacao = 'cancelado' then null else x.nome_arquivo end
   where x.id = p_id;
  if not found then
    raise exception 'comprovante_arquivo_apagado: comprovante % não existe', p_id using errcode = '22023';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 11. comprovantes_vigia_lote: a manutenção que é só banco + reserva do resto (com prazo, para
--     dois vigias seguidos não pegarem o mesmo item)
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_vigia_lote(p_limite integer default 10)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lim integer := least(greatest(coalesce(p_limite, 10), 1), 50);
  v_expurgados integer;
  v_baixar jsonb;
  v_entregar jsonb;
  v_reenfileirar jsonb;
  v_dropbox jsonb;
  v_apagar jsonb;
  v_avisar jsonb;
  v_encaminhar jsonb := '[]'::jsonb;
  v_sem_desfecho integer := 0;
  v_enc jsonb;
  v_linha record;
  c public.comprovantes;
begin
  -- texto do OCR some aos 90 dias (decisão 11); o pg_cron também faz isto sem depender da edge
  update public.comprovantes x set leitura_texto = null
   where x.leitura_texto is not null and x.lido_em < now() - interval '90 days';
  get diagnostics v_expurgados = row_count;

  -- rede de segurança: linha que ficou "recebido" por 1 h não teve desfecho (exceção inesperada na
  -- edge, isolate derrubado no download, erro do banco depois do upload). Vira falhou e segue o
  -- caminho de toda falha: sem legenda-chave, encaminha ao assistente (decisão 3); com ela, aviso.
  -- As 3 tentativas normais de download (agora, +5 e +15 min) cabem com folga nessa 1 h.
  for v_linha in
    select x.id from public.comprovantes x
     where x.situacao = 'recebido' and x.created_at < now() - interval '1 hour'
     order by x.created_at
     limit v_lim
     for update skip locked
  loop
    update public.comprovantes x
       set situacao = 'falhou', erro = 'sem_desfecho', download_proxima_em = null
     where x.id = v_linha.id
    returning * into c;
    v_sem_desfecho := v_sem_desfecho + 1;
    if not c.forcado then
      v_enc := public._comprovante_encaminhar(c.id);
      if coalesce((v_enc->>'encaminhar')::boolean, false) then
        v_encaminhar := v_encaminhar || jsonb_build_array(jsonb_build_object(
          'id', c.id, 'phone_normalized', c.phone_normalized, 'dono_id', c.dono_id, 'texto', v_enc->>'texto'));
      end if;
    end if;
  end loop;

  -- baixar: a edge recebe a key guardada na chegada (nunca relê o raw_payload) e o telefone da linha
  with alvo as (
    select x.id from public.comprovantes x
     where x.situacao = 'recebido' and x.arquivo_path is null
       and (x.download_proxima_em <= now()
            or (x.download_proxima_em is null and x.created_at < now() - interval '5 minutes'))
     order by x.created_at
     limit v_lim
     for update skip locked
  ), reservados as (
    update public.comprovantes x set download_proxima_em = now() + interval '10 minutes'
      from alvo where x.id = alvo.id
    returning x.id, x.whatsapp_message_id, x.wa_message_id, x.wa_key, x.phone_normalized, x.recebido_em, x.created_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', r2.id, 'message_id', r2.whatsapp_message_id,
                                               'wa_message_id', r2.wa_message_id, 'wa_key', r2.wa_key,
                                               'phone_normalized', r2.phone_normalized,
                                               'recebido_em', r2.recebido_em) order by r2.created_at), '[]'::jsonb)
    into v_baixar
    from reservados r2;

  -- entregar (o gatilho perdeu, ou a entrega falhou: comprovante_entrega_falhou conta e desiste na 3ª)
  select coalesce(jsonb_agg(jsonb_build_object('job_id', e.id) order by e.quando), '[]'::jsonb)
    into v_entregar
    from (select j.id, coalesce(j.completed_at, j.updated_at) as quando
            from public.comprovantes x
            join public.ai_jobs j on j.id = x.job_id
           where x.situacao = 'na_fila'
             and j.status in ('completed', 'failed', 'cancelled')
             and coalesce(j.completed_at, j.updated_at) < now() - interval '2 minutes'
             and not (j.metadata ? 'entregue_em')
           order by 2
           limit v_lim) e;

  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'arquivo_path', r.arquivo_path) order by r.recebido_em), '[]'::jsonb)
    into v_reenfileirar
    from (select x.id, x.arquivo_path, x.recebido_em
            from public.comprovantes x
            join public.ai_jobs j on j.id = x.job_id
           where x.situacao = 'na_fila' and not x.reenfileirado and x.arquivo_apagado_em is null
             and j.status = 'failed' and j.error_code in ('deadline_exceeded', 'input_unavailable')
             and j.metadata ? 'entregue_em'
           order by x.recebido_em
           limit v_lim) r;

  with alvo as (
    select x.id from public.comprovantes x
     where x.numero is not null and x.dropbox_id is null and x.situacao in ('lido', 'falhou')
       and x.dropbox_tentativas < 5 and x.dropbox_proxima_em <= now()
     order by x.dropbox_proxima_em
     limit v_lim
     for update skip locked
  ), reservados as (
    update public.comprovantes x set dropbox_proxima_em = now() + interval '10 minutes'
      from alvo where x.id = alvo.id
    returning x as linha
  )
  select coalesce(jsonb_agg(public._comprovante_dados_do_arquivo(r.linha) order by (r.linha).numero), '[]'::jsonb)
    into v_dropbox
    from reservados r;

  -- nunca o original de um CMP vivo (decisão 4: CMP não apaga na F1)
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'arquivo_path', a.arquivo_path) order by a.arquivo_apagar_apos), '[]'::jsonb)
    into v_apagar
    from (select x.id, x.arquivo_path, x.arquivo_apagar_apos
            from public.comprovantes x
           where x.arquivo_apagar_apos <= now() and x.arquivo_apagado_em is null and x.arquivo_path is not null
             and not (x.numero is not null and x.situacao <> 'cancelado')
           order by x.arquivo_apagar_apos
           limit v_lim) a;

  select coalesce(jsonb_agg(t.phone_normalized order by t.mais_antigo), '[]'::jsonb)
    into v_avisar
    from (select x.phone_normalized, min(x.recebido_em) as mais_antigo
            from public.comprovantes x
           where x.modo = 'dono' and x.avisado_em is null
             and (x.aviso_proximo_em is null or x.aviso_proximo_em <= now())
             and ((x.situacao in ('lido', 'falhou') and x.numero is not null)
                  or (x.situacao = 'cancelado' and x.motivo_cancelamento in ('arquivo_repetido', 'chave_repetida'))
                  or (x.situacao = 'falhou' and x.forcado and x.numero is null))
           group by x.phone_normalized
          having min(x.recebido_em) <= now() - interval '10 minutes'
           order by 2
           limit v_lim) t;

  return jsonb_build_object(
    'expurgados', v_expurgados,
    'sem_desfecho', v_sem_desfecho,
    'encaminhar', v_encaminhar,
    'baixar', v_baixar,
    'entregar', v_entregar,
    'reenfileirar', v_reenfileirar,
    'dropbox', v_dropbox,
    'apagar', v_apagar,
    'avisar', v_avisar);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 13. comprovante_entrega_falhou: comprovante_aplicar_leitura lançou (a transação dela desfaz tudo,
--     inclusive a marca entregue_em, e o job voltaria ao vigia a cada 2 min para sempre). A edge
--     chama esta, em transação própria, a cada falha real. Na 3ª desiste: falhou 'entrega_falhou' —
--     com número, CMP "A LER" (Dropbox pelo vigia e aviso); sem número, segue ao assistente
--     (decisão 3) e o original fica 7 dias. O job perde a URL assinada e o texto do OCR.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_entrega_falhou(p_job_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  j public.ai_jobs;
  c public.comprovantes;
  v_cid uuid;
  v_n integer;
  v_enc jsonb := jsonb_build_object('encaminhar', false, 'texto', null);
begin
  select * into j from public.ai_jobs x where x.id = p_job_id for update;
  if not found or j.metadata->>'tipo' is distinct from 'comprovante_leitura' or j.metadata ? 'entregue_em' then
    return jsonb_build_object('job_id', p_job_id, 'ignorado', true, 'desistiu', false, 'encaminhar', false);
  end if;
  begin
    v_cid := (j.metadata->>'comprovante_id')::uuid;
  exception when others then
    v_cid := null;
  end;
  select * into c from public.comprovantes x where x.id = v_cid for update;
  if not found or c.job_id is distinct from p_job_id or c.situacao <> 'na_fila' then
    return jsonb_build_object('job_id', p_job_id, 'ignorado', true, 'desistiu', false, 'encaminhar', false);
  end if;

  v_n := coalesce((j.metadata->>'entrega_tentativas')::integer, 0) + 1;
  if v_n < 3 then
    update public.ai_jobs x set metadata = x.metadata || jsonb_build_object('entrega_tentativas', v_n)
     where x.id = p_job_id;
    return jsonb_build_object('job_id', p_job_id, 'id', c.id, 'tentativas', v_n, 'desistiu', false, 'encaminhar', false);
  end if;

  update public.ai_jobs x
     set metadata = x.metadata || jsonb_build_object('entrega_tentativas', v_n, 'entregue_em', now(), 'entrega_desistida', true),
         input = case when x.input is null then null else x.input #- '{arquivo,url}' end,
         response = case when jsonb_typeof(x.response->'data') = 'object'
                         then jsonb_set(x.response, '{data}', (x.response->'data') #- '{texto}')
                         else x.response end
   where x.id = p_job_id;
  update public.comprovantes x
     set situacao = 'falhou', erro = 'entrega_falhou',
         dropbox_proxima_em = case when x.numero is not null then now() else x.dropbox_proxima_em end,
         arquivo_apagar_apos = case when x.numero is null then x.recebido_em + interval '7 days' else x.arquivo_apagar_apos end
   where x.id = c.id
  returning * into c;
  if c.numero is null then
    v_enc := public._comprovante_encaminhar(c.id);
  end if;

  return jsonb_build_object(
    'job_id', p_job_id,
    'id', c.id,
    'tentativas', v_n,
    'desistiu', true,
    'situacao', c.situacao,
    'codigo', c.codigo,
    'modo', c.modo,
    'phone_normalized', c.phone_normalized,
    'wa_message_id', c.wa_message_id,
    'dono_id', c.dono_id,
    'encaminhar', coalesce((v_enc->>'encaminhar')::boolean, false),
    'texto_para_assistente', v_enc->>'texto');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 14. comprovante_aviso_falhou: o whatsapp-send não confirmou o aviso. Desfaz a reserva para o vigia
--     tentar de novo em 5, 15, 60 e 180 min (no lugar do whatsapp_send_queue, que qualquer logado
--     lê e edita antes do envio). Na 5ª falha desiste (o item fica avisado, sem aviso).
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_aviso_falhou(p_ids uuid[])
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_liberados integer := 0;
  v_desistiu integer := 0;
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return jsonb_build_object('liberados', 0, 'desistiu', 0);
  end if;
  with alvo as (
    select x.id, x.aviso_tentativas + 1 as n
      from public.comprovantes x
     where x.id = any (p_ids) and x.avisado_em is not null
     for update
  ), feito as (
    update public.comprovantes x
       set aviso_tentativas = least(alvo.n, 32767),
           avisado_em = case when alvo.n < 5 then null else x.avisado_em end,
           aviso_proximo_em = case alvo.n
                                when 1 then now() + interval '5 minutes'
                                when 2 then now() + interval '15 minutes'
                                when 3 then now() + interval '60 minutes'
                                when 4 then now() + interval '180 minutes'
                                else null end
      from alvo
     where x.id = alvo.id
    returning alvo.n
  )
  select count(*) filter (where n < 5), count(*) filter (where n >= 5) into v_liberados, v_desistiu from feito;
  return jsonb_build_object('liberados', v_liberados, 'desistiu', v_desistiu);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 15. comprovante_ja_encaminhado: o whatsapp-webhook desistiu de esperar o receber (prazo) e mandou a
--     mensagem ao assistente pelo despacho de hoje. Se a linha existir, marca o encaminhamento da
--     chegada: _comprovante_encaminhar não repete (o dono não recebe duas respostas). Idempotente.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_ja_encaminhado(p_message_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  update public.comprovantes x
     set encaminhado_ao_assistente_em = now(), encaminhamento = 'chegada'
   where x.whatsapp_message_id = p_message_id
     and x.encaminhado_ao_assistente_em is null and x.encaminhamento is null;
  get diagnostics v_n = row_count;
  return jsonb_build_object('marcado', v_n > 0);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 12. comprovantes_relatorio_sombra: só contagens (nenhum valor, nome, CNPJ ou texto)
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_relatorio_sombra(p_desde timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_dono record;
  v_desde timestamptz := coalesce(p_desde, now() - interval '7 days');
  v_midias integer;
  v_com_linha integer;
begin
  select * into v_dono from public._comprovante_dono();
  if v_dono.id is null then
    return jsonb_build_object('desde', v_desde, 'sem_dono', true);
  end if;

  select count(*), count(*) filter (where exists (select 1 from public.comprovantes x where x.wa_message_id = m.wa_message_id))
    into v_midias, v_com_linha
    from public.whatsapp_messages m
   where m.direction = 'inbound' and m.phone_normalized = v_dono.phone and m.occurred_at >= v_desde
     and (m.message_type in ('image', 'document')
          or coalesce(m.raw_payload #> '{data,message}', '{}'::jsonb) ? 'documentWithCaptionMessage');

  return jsonb_build_object(
    'desde', v_desde,
    'midias_do_dono', v_midias,
    'com_linha', v_com_linha,
    'sem_linha', v_midias - v_com_linha,
    'por_situacao', coalesce((select jsonb_object_agg(s.situacao, s.n) from (
        select x.situacao, count(*) as n from public.comprovantes x where x.recebido_em >= v_desde group by x.situacao) s), '{}'::jsonb),
    'por_tipo', coalesce((select jsonb_object_agg(s.tipo, s.n) from (
        select coalesce(x.tipo, 'sem_tipo') as tipo, count(*) as n from public.comprovantes x
         where x.recebido_em >= v_desde group by 1) s), '{}'::jsonb),
    'cmps_por_selo_do_valor', coalesce((select jsonb_object_agg(s.selo, s.n) from (
        select coalesce(x.valor_confianca, 'sem_valor') as selo, count(*) as n from public.comprovantes x
         where x.recebido_em >= v_desde and x.numero is not null and x.situacao <> 'cancelado' group by 1) s), '{}'::jsonb),
    'recebido_ate_lido_ms', (select jsonb_build_object(
        'n', count(*),
        'p50', round(percentile_cont(0.5) within group (order by extract(epoch from (x.lido_em - x.recebido_em)) * 1000)),
        'p95', round(percentile_cont(0.95) within group (order by extract(epoch from (x.lido_em - x.recebido_em)) * 1000)))
        from public.comprovantes x where x.recebido_em >= v_desde and x.lido_em is not null),
    'falhas_por_erro', coalesce((select jsonb_object_agg(s.erro, s.n) from (
        select x.erro, count(*) as n from public.comprovantes x
         where x.recebido_em >= v_desde and x.situacao = 'falhou' group by x.erro) s), '{}'::jsonb),
    'dropbox', (select jsonb_build_object(
        'ok', count(*) filter (where x.dropbox_id is not null),
        'pendente', count(*) filter (where x.dropbox_id is null and x.dropbox_tentativas < 5),
        'desistiu', count(*) filter (where x.dropbox_id is null and x.dropbox_tentativas >= 5))
        from public.comprovantes x
       where x.recebido_em >= v_desde and x.numero is not null and x.situacao in ('lido', 'falhou')),
    'encaminhamentos', coalesce((select jsonb_object_agg(s.enc, s.n) from (
        select x.encaminhamento as enc, count(*) as n from public.comprovantes x
         where x.recebido_em >= v_desde and x.encaminhamento is not null group by 1) s), '{}'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------
-- Privilégios (revogar de anon/authenticated POR ASSINATURA; execute só para service_role)
-- ---------------------------------------------------------------------------------------------
revoke all on function public._comprovante_dono() from public, anon, authenticated;
revoke all on function public._comprovante_dados_do_arquivo(public.comprovantes) from public, anon, authenticated;
revoke all on function public._comprovante_criar_job(uuid, text, smallint) from public, anon, authenticated;
revoke all on function public._comprovante_encaminhar(uuid) from public, anon, authenticated;

revoke all on function public.comprovante_receber(jsonb) from public, anon, authenticated;
revoke all on function public.comprovante_guardar_arquivo(uuid, jsonb, text) from public, anon, authenticated;
revoke all on function public.comprovante_download_falhou(uuid, text) from public, anon, authenticated;
revoke all on function public.comprovante_pedir_leitura(uuid, text) from public, anon, authenticated;
revoke all on function public.comprovante_aplicar_leitura(uuid) from public, anon, authenticated;
revoke all on function public.comprovante_falhou(uuid, text) from public, anon, authenticated;
revoke all on function public.comprovante_reservar_aviso(text, boolean) from public, anon, authenticated;
revoke all on function public.comprovante_no_dropbox(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.comprovante_dropbox_falhou(uuid, text) from public, anon, authenticated;
revoke all on function public.comprovante_arquivo_apagado(uuid) from public, anon, authenticated;
revoke all on function public.comprovantes_vigia_lote(integer) from public, anon, authenticated;
revoke all on function public.comprovantes_relatorio_sombra(timestamptz) from public, anon, authenticated;
revoke all on function public.comprovante_entrega_falhou(uuid) from public, anon, authenticated;
revoke all on function public.comprovante_aviso_falhou(uuid[]) from public, anon, authenticated;
revoke all on function public.comprovante_ja_encaminhado(uuid) from public, anon, authenticated;

grant execute on function public.comprovante_entrega_falhou(uuid) to service_role;
grant execute on function public.comprovante_aviso_falhou(uuid[]) to service_role;
grant execute on function public.comprovante_ja_encaminhado(uuid) to service_role;
grant execute on function public.comprovante_receber(jsonb) to service_role;
grant execute on function public.comprovante_guardar_arquivo(uuid, jsonb, text) to service_role;
grant execute on function public.comprovante_download_falhou(uuid, text) to service_role;
grant execute on function public.comprovante_pedir_leitura(uuid, text) to service_role;
grant execute on function public.comprovante_aplicar_leitura(uuid) to service_role;
grant execute on function public.comprovante_falhou(uuid, text) to service_role;
grant execute on function public.comprovante_reservar_aviso(text, boolean) to service_role;
grant execute on function public.comprovante_no_dropbox(uuid, text, text, text) to service_role;
grant execute on function public.comprovante_dropbox_falhou(uuid, text) to service_role;
grant execute on function public.comprovante_arquivo_apagado(uuid) to service_role;
grant execute on function public.comprovantes_vigia_lote(integer) to service_role;
grant execute on function public.comprovantes_relatorio_sombra(timestamptz) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: anon/authenticated sem execute em nenhuma; service_role com execute nas 15 RPCs.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
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
    'public._comprovante_dono()',
    'public._comprovante_dados_do_arquivo(public.comprovantes)',
    'public._comprovante_criar_job(uuid, text, smallint)',
    'public._comprovante_encaminhar(uuid)'];
begin
  foreach v_f in array v_rpcs || v_helpers loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função dos comprovantes exposta para anon/authenticated: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs loop
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011102000', 'comprovantes_rpcs')
on conflict do nothing;
