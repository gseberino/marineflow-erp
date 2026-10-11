-- Comprovantes F2 (11/10/2026): o registro único de pergunta ativa por telefone (whatsapp_perguntas).
--
-- Uma pergunta aberta por telefone (índice único parcial). Quem pergunta ao dono e espera sim/número
-- registra aqui: o fluxo de comprovantes (as perguntas dele), o assistente (proposta ou opções), os
-- lembretes de revisão, a campanha de temporada e o acompanhar-conversas. O webhook e o ai-agent
-- leem pergunta_rotear antes de decidir quem responde (3.2 da spec da F2).
--
--   1 pergunta_rotear(phone, citado)          o estado do telefone: ativa, citada, pendência viva, CMP em contexto
--   1b pergunta_interromper(phone)            o texto livre foi ao assistente com a pergunta do CMP aberta
--   2 pergunta_ocupado(phone)                 há pergunta aberta ou pendência viva? (quem pergunta adia)
--   3 pergunta_registrar_externa(p)           pendência do assistente/lembretes entra no registro (substitui a do CMP)
--   4 pergunta_marcar_enviada(id, wa)         o envio da pergunta foi confirmado (e o id do WhatsApp dele)
--   5 pergunta_encerrar_externa(phone, st)    fecha as abertas que não são de comprovante
--
-- Helpers internos (sem grant): _pendencia_viva_do_telefone, _comprovante_pergunta_saiu,
-- _comprovante_sair_da_conversa, _pergunta_limpar, _pergunta_abrir, _pergunta_fechar.
--
-- Com a conversa desligada (_comprovante_conversa_ligada() falso) nada é gravado aqui: o
-- registrar_externa devolve desligada e o ocupado olha só a pendência viva (o mesmo de hoje).
-- Todas pegam pg_advisory_xact_lock('pergunta:' || telefone) antes de olhar o telefone.
-- Não escreve dados. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- Helpers internos
-- ---------------------------------------------------------------------------------------------

-- A pendência do assistente que ainda espera o dono (a mesma regra de pendenciaQueSegueEsperando,
-- _shared/ai/whatsapp-channel.ts): a sessão aberta do WhatsApp mais recente do telefone.
create or replace function public._pendencia_viva_do_telefone(p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s record;
  pa record;
  v_id uuid;
begin
  select x.id, x.metadata, x.last_activity_at into s
    from public.ai_operator_sessions x
   where x.channel = 'whatsapp' and x.external_thread_key = p_phone and x.status = 'open'
   order by x.last_activity_at desc
   limit 1;
  if not found then
    return null;
  end if;

  begin
    v_id := nullif(s.metadata->>'pending_confirm_action_id', '')::uuid;
  exception when others then
    v_id := null;
  end;
  if v_id is not null then
    select a.id, a.title, a.created_at into pa
      from public.ai_operator_pending_actions a
     where a.id = v_id and a.status = 'pending' and (a.expires_at is null or a.expires_at > now());
    if found then
      return jsonb_build_object('tipo', 'confirmacao', 'id', pa.id,
                                'titulo', left(coalesce(nullif(btrim(pa.title), ''), 'ação pendente'), 80),
                                'desde', pa.created_at);
    end if;
  end if;

  -- a lista de opções só segura o telefone por 4 h (o mesmo prazo das opções no registro): a sessão
  -- guarda a lista até virar, e uma lista velha não respondida não pode adiar lembretes nem perguntas
  if jsonb_typeof(s.metadata->'pending_options') = 'array' and jsonb_array_length(s.metadata->'pending_options') > 0
     and s.last_activity_at > now() - interval '4 hours' then
    return jsonb_build_object('tipo', 'opcoes', 'id', null, 'titulo', 'escolha da lista do assistente',
                              'desde', s.last_activity_at);
  end if;
  return null;
end $$;

-- O CMP da pergunta que saiu (pular, sair, expirou, substituída) volta para a fila sem perder o
-- que já foi respondido: respostas e fila_ordem ficam. O passo também, menos o "corrigir": o menu
-- do corrigir sem o resumo na frente não diz nada a quem volta horas depois (o vigia reapresenta o
-- resumo).
create or replace function public._comprovante_pergunta_saiu(p_cmp uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_phone text;
begin
  update public.comprovantes x
     set situacao = 'aguardando_vez',
         passo = case when x.passo = 'corrigir' then null else x.passo end
   where x.id = p_cmp and x.situacao in ('perguntando', 'aguardando_sim')
  returning x.phone_normalized into v_phone;
  if v_phone is null then
    select x.phone_normalized into v_phone from public.comprovantes x where x.id = p_cmp;
  end if;
  if v_phone is not null then
    insert into public.comprovantes_fila_do_telefone as f (phone_normalized, ultima_pergunta_fechada_em, atualizado_em)
    values (v_phone, now(), now())
    on conflict (phone_normalized) do update set ultima_pergunta_fechada_em = now(), atualizado_em = now();
  end if;
end $$;

-- A conversa foi desligada (comprovante_conversa = 'off' ou o fluxo saiu do modo dono): o CMP que
-- ainda não foi gravado volta a ser o da F1 ('lido', ou 'falhou' quando a leitura não veio), fora da
-- fila (fila_desde nulo) — o "lote antigo" e o "cmp N" o trazem de volta quando a conversa religar.
-- As respostas que o dono já deu ficam (entrar na fila de novo não as apaga).
create or replace function public._comprovante_sair_da_conversa(p_cmp uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.comprovantes x
     set situacao = case when x.lido_em is not null and x.erro is null then 'lido' else 'falhou' end,
         fila_desde = null,
         fila_ordem = null,
         passo = null
   where x.id = p_cmp and x.gravado_em is null
     and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
end $$;

-- Fecha uma pergunta aberta. O status final fica no CHECK (respondida, substituida, expirada,
-- cancelada). true = fechou AQUI (estava aberta); false = já estava fechada (outra transação chegou
-- antes) — quem chama só devolve o CMP à fila quando fechou de fato.
create or replace function public._pergunta_fechar(p_id uuid, p_status text, p_motivo text, p_resposta_message_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_origem text;
  v_phone text;
begin
  if p_status is null or p_status not in ('respondida', 'substituida', 'expirada', 'cancelada') then
    raise exception '_pergunta_fechar: status inválido' using errcode = '22023';
  end if;
  update public.whatsapp_perguntas w
     set status = p_status,
         motivo = left(p_motivo, 60),
         fechada_em = now(),
         resposta_message_id = coalesce(p_resposta_message_id, w.resposta_message_id)
   where w.id = p_id and w.status = 'aberta'
  returning w.origem, w.phone_normalized into v_origem, v_phone;
  if v_origem is null then
    return false;
  end if;
  -- espaçamento do vigia: conta da última pergunta de comprovante fechada
  if v_origem = 'comprovante' then
    insert into public.comprovantes_fila_do_telefone as f (phone_normalized, ultima_pergunta_fechada_em, atualizado_em)
    values (v_phone, now(), now())
    on conflict (phone_normalized) do update set ultima_pergunta_fechada_em = now(), atualizado_em = now();
  end if;
  return true;
end $$;

-- Limpeza preguiçosa do telefone (toda RPC do registro chama antes de olhar):
--   * pergunta de comprovante aberta com a conversa desligada → cancelada (conversa_desligada);
--   * vencida → expirada;
--   * confirmação cuja pendência não está mais pendente (ou venceu) → respondida;
--   * opções cuja sessão não tem mais pending_options → respondida.
-- O CMP de pergunta que sai volta para a fila (_comprovante_pergunta_saiu); com a conversa
-- desligada, sai dela (_comprovante_sair_da_conversa: volta a lido/falhou, como na F1).
create or replace function public._pergunta_limpar(p_phone text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r record;
  v_ligada boolean := public._comprovante_conversa_ligada();
begin
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || coalesce(p_phone, ''), 0));
  for r in
    select w.id, w.origem, w.tipo, w.referencia_id, w.expira_em
      from public.whatsapp_perguntas w
     where w.phone_normalized = p_phone and w.status = 'aberta'
  loop
    if r.origem = 'comprovante' and not v_ligada then
      -- desligada: o CMP sai da conversa e volta a ser o da F1 (lido/falhou, fora da fila)
      if public._pergunta_fechar(r.id, 'cancelada', 'conversa_desligada', null) then
        perform public._comprovante_sair_da_conversa(r.referencia_id);
      end if;
    elsif r.expira_em <= now() then
      if public._pergunta_fechar(r.id, 'expirada', null, null) and r.origem = 'comprovante' then
        perform public._comprovante_pergunta_saiu(r.referencia_id);
      end if;
    elsif r.tipo = 'confirmacao' and not exists (
      select 1 from public.ai_operator_pending_actions a
       where a.id = r.referencia_id and a.status = 'pending' and (a.expires_at is null or a.expires_at > now())) then
      perform public._pergunta_fechar(r.id, 'respondida', null, null);
    elsif r.tipo = 'opcoes' and not exists (
      select 1 from public.ai_operator_sessions s
       where s.id = r.referencia_id and s.status = 'open'
         and jsonb_typeof(s.metadata->'pending_options') = 'array'
         and jsonb_array_length(s.metadata->'pending_options') > 0) then
      perform public._pergunta_fechar(r.id, 'respondida', null, null);
    end if;
  end loop;
end $$;

-- Abre uma pergunta de comprovante (uso interno). Entrada {phone, origem, tipo, referencia_id,
-- referencia_codigo, passo, opcoes, dados, expira_em}. A aberta da MESMA referência é fechada
-- (respondida) e segue; outra aberta ou pendência viva → {"ok":false,"ocupado_por":{...}}.
create or replace function public._pergunta_abrir(p jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_phone text := p->>'phone';
  v_ref uuid;
  v_id uuid := gen_random_uuid();
  v_aberta record;
  v_pend jsonb;
  v_expira timestamptz;
begin
  if v_phone is null or v_phone !~ '^[0-9]{10,15}$' then
    raise exception '_pergunta_abrir: telefone inválido' using errcode = '22023';
  end if;
  begin
    v_ref := (p->>'referencia_id')::uuid;
    v_expira := coalesce((p->>'expira_em')::timestamptz, now() + interval '2 hours');
  exception when others then
    raise exception '_pergunta_abrir: referência ou prazo malformado' using errcode = '22023';
  end;
  if v_ref is null then
    raise exception '_pergunta_abrir: referência obrigatória' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || v_phone, 0));
  perform public._pergunta_limpar(v_phone);

  select w.id, w.origem, w.referencia_id, w.referencia_codigo, w.aberta_em into v_aberta
    from public.whatsapp_perguntas w
   where w.phone_normalized = v_phone and w.status = 'aberta';
  if found then
    if v_aberta.referencia_id = v_ref and v_aberta.origem = coalesce(p->>'origem', 'comprovante') then
      perform public._pergunta_fechar(v_aberta.id, 'respondida', null, null);
    else
      return jsonb_build_object('ok', false, 'ocupado_por', jsonb_build_object(
        'origem', v_aberta.origem, 'titulo', v_aberta.referencia_codigo, 'desde', v_aberta.aberta_em));
    end if;
  end if;

  v_pend := public._pendencia_viva_do_telefone(v_phone);
  if v_pend is not null then
    return jsonb_build_object('ok', false, 'ocupado_por', jsonb_build_object(
      'origem', 'assistente', 'titulo', v_pend->>'titulo', 'desde', v_pend->'desde'));
  end if;

  insert into public.whatsapp_perguntas (
    id, phone_normalized, origem, tipo, referencia_id, referencia_codigo, passo, opcoes, dados,
    dedupe_key, expira_em
  ) values (
    v_id, v_phone, coalesce(p->>'origem', 'comprovante'), coalesce(p->>'tipo', 'pergunta'), v_ref,
    left(p->>'referencia_codigo', 80), left(p->>'passo', 40),
    coalesce(case when jsonb_typeof(p->'opcoes') = 'array' then p->'opcoes' end, '[]'::jsonb),
    coalesce(case when jsonb_typeof(p->'dados') = 'object' then p->'dados' end, '{}'::jsonb),
    'cmp:p:' || v_id, v_expira
  );
  return jsonb_build_object('ok', true, 'id', v_id, 'dedupe_key', 'cmp:p:' || v_id);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1. pergunta_rotear: o que o webhook e o ai-agent leem antes de decidir quem responde
--    Além da ativa, da citada, da pendência viva e do CMP em contexto (revisão de 11/10/2026):
--    * ativa.interrompida_em / ativa.enviada_em: o dono falou com o assistente DEPOIS da pergunta do
--      CMP (o "sim" seguinte pode ser para o assistente); quando o envio da pergunta foi confirmado;
--    * citada: acha também os REENVIOS da pergunta (wa_message_ids), não só o primeiro envio;
--    * citado_cmp: a mensagem citada é a FOTO/arquivo de um CMP (comprovantes.wa_message_id);
--    * cmp_substituido: a pergunta do CMP que a ativa (do assistente/lembrete) acabou de substituir,
--      aberta a menos de 2 min dela — um "1"/"sim" agora é empate, não aprovação;
--    * ultima_do_cmp: sem pergunta aberta, a última de comprovante fechada há menos de 24 h
--      (expirou, foi substituída ou não saiu), do CMP ainda não gravado — a resposta atrasada vai a ela;
--    * cmp_chegando: o CMP que o dono acabou de mandar (até 2 min) e que ainda não foi perguntado —
--      o texto solto logo depois da foto ("é do Brisa") é dica dele, não conversa com o assistente.
-- ---------------------------------------------------------------------------------------------
create or replace function public.pergunta_rotear(p_phone text, p_citado text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_dono_phone text;
  v_eh_dono boolean;
  v_citado text := nullif(btrim(coalesce(p_citado, '')), '');
  v_ativa record;
  v_citada record;
  v_cmp record;
  v_sub record;
  v_ult record;
  v_chegando record;
  v_foto record;
  j_ativa jsonb;
  j_citada jsonb;
  j_cmp jsonb;
  j_sub jsonb;
  j_ult jsonb;
  j_chegando jsonb;
  j_foto jsonb;
begin
  if p_phone is null or p_phone !~ '^[0-9]{10,15}$' then
    raise exception 'pergunta_rotear: telefone inválido' using errcode = '22023';
  end if;
  select d.phone into v_dono_phone from public._comprovante_dono() d;
  v_eh_dono := v_dono_phone is not null and v_dono_phone = p_phone;
  -- desligada ou não é o dono: nada mais é lido (o despacho de hoje)
  if not v_eh_dono or not public._comprovante_conversa_ligada() then
    return jsonb_build_object('conversa', false, 'dono', v_eh_dono);
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || p_phone, 0));
  perform public._pergunta_limpar(p_phone);

  select w.id, w.origem, w.tipo, w.referencia_id, w.referencia_codigo, w.passo, w.opcoes, w.wa_message_id, w.aberta_em,
         w.enviada_em, w.dados->>'interrompida_em' as interrompida_em
    into v_ativa
    from public.whatsapp_perguntas w
   where w.phone_normalized = p_phone and w.status = 'aberta';
  if v_ativa.id is not null then
    j_ativa := jsonb_build_object('id', v_ativa.id, 'origem', v_ativa.origem, 'tipo', v_ativa.tipo,
      'referencia_id', v_ativa.referencia_id, 'referencia_codigo', v_ativa.referencia_codigo,
      'passo', v_ativa.passo, 'opcoes', v_ativa.opcoes, 'wa_message_id', v_ativa.wa_message_id,
      'aberta_em', v_ativa.aberta_em, 'enviada_em', v_ativa.enviada_em, 'interrompida_em', v_ativa.interrompida_em);
  end if;

  if v_citado is not null then
    select w.id, w.origem, w.tipo, w.referencia_id, w.referencia_codigo, w.status, w.passo into v_citada
      from public.whatsapp_perguntas w
     where w.phone_normalized = p_phone
       and (w.wa_message_id = v_citado or v_citado = any (w.wa_message_ids))
       and w.aberta_em > now() - interval '48 hours'
     order by w.aberta_em desc
     limit 1;
    if v_citada.id is not null then
      j_citada := jsonb_build_object('id', v_citada.id, 'origem', v_citada.origem, 'tipo', v_citada.tipo,
        'referencia_id', v_citada.referencia_id, 'referencia_codigo', v_citada.referencia_codigo,
        'status', v_citada.status, 'passo', v_citada.passo);
    else
      -- citou a foto/o arquivo de um comprovante (não uma pergunta)
      select x.id, x.codigo, x.situacao, x.gravado_em into v_foto
        from public.comprovantes x
       where x.phone_normalized = p_phone and x.wa_message_id = v_citado and x.numero is not null
       order by x.recebido_em desc
       limit 1;
      if v_foto.id is not null then
        j_foto := jsonb_build_object('id', v_foto.id, 'codigo', v_foto.codigo, 'situacao', v_foto.situacao,
                                     'gravado', v_foto.gravado_em is not null);
      end if;
    end if;
  end if;

  -- o CMP em contexto: o da pergunta ativa; senão o último gravado ou perguntado há 30 min
  if v_ativa.id is not null and v_ativa.origem = 'comprovante' then
    select x.id, x.codigo, x.situacao, x.gravado_em into v_cmp from public.comprovantes x where x.id = v_ativa.referencia_id;
  else
    select x.id, x.codigo, x.situacao, x.gravado_em into v_cmp
      from public.comprovantes x
     where x.phone_normalized = p_phone and x.numero is not null and x.situacao <> 'cancelado'
       and (x.gravado_em > now() - interval '30 minutes' or x.ultima_pergunta_em > now() - interval '30 minutes')
     order by greatest(coalesce(x.gravado_em, '-infinity'::timestamptz), coalesce(x.ultima_pergunta_em, '-infinity'::timestamptz)) desc
     limit 1;
  end if;
  if v_cmp.id is not null then
    j_cmp := jsonb_build_object('id', v_cmp.id, 'codigo', v_cmp.codigo, 'situacao', v_cmp.situacao,
                                'gravado', v_cmp.gravado_em is not null);
  end if;

  -- a pergunta do CMP que a ativa (de outra origem) acabou de substituir: empate se < 2 min entre elas
  if v_ativa.id is not null and v_ativa.origem <> 'comprovante' then
    select w.id, w.referencia_id, w.referencia_codigo, w.passo, w.aberta_em into v_sub
      from public.whatsapp_perguntas w
      join public.comprovantes x on x.id = w.referencia_id
     where w.phone_normalized = p_phone and w.origem = 'comprovante' and w.status = 'substituida'
       and w.motivo like 'substituida_por:%'
       and w.fechada_em between v_ativa.aberta_em - interval '5 seconds' and v_ativa.aberta_em + interval '5 seconds'
       and abs(extract(epoch from (v_ativa.aberta_em - w.aberta_em))) < 120
       and x.gravado_em is null and x.situacao <> 'cancelado'
     order by w.fechada_em desc
     limit 1;
    if v_sub.id is not null then
      j_sub := jsonb_build_object('id', v_sub.id, 'referencia_id', v_sub.referencia_id,
                                  'referencia_codigo', v_sub.referencia_codigo, 'passo', v_sub.passo, 'aberta_em', v_sub.aberta_em);
    end if;
  end if;

  -- sem pergunta aberta: a última de comprovante, fechada há menos de 24 h sem ser respondida
  if v_ativa.id is null then
    select w.id, w.referencia_id, w.referencia_codigo, w.passo, w.opcoes, w.status, w.motivo, w.fechada_em,
           w.dados ? 'interrompida_em' as interrompida, x.gravado_em, x.situacao as cmp_situacao
      into v_ult
      from public.whatsapp_perguntas w
      join public.comprovantes x on x.id = w.referencia_id
     where w.phone_normalized = p_phone and w.origem = 'comprovante'
     order by w.aberta_em desc
     limit 1;
    if v_ult.id is not null
       and (v_ult.status in ('expirada', 'substituida') or (v_ult.status = 'cancelada' and v_ult.motivo = 'nao_enviada'))
       and v_ult.fechada_em > now() - interval '24 hours'
       and not v_ult.interrompida
       and v_ult.gravado_em is null and v_ult.cmp_situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
       and v_ult.passo is distinct from 'confirmar' then
      j_ult := jsonb_build_object('id', v_ult.id, 'referencia_id', v_ult.referencia_id,
                                  'referencia_codigo', v_ult.referencia_codigo, 'passo', v_ult.passo,
                                  'opcoes', v_ult.opcoes, 'fechada_em', v_ult.fechada_em);
    end if;
  end if;

  -- o comprovante que acabou de chegar (até 2 min) e ainda não foi perguntado
  select x.id, x.codigo into v_chegando
    from public.comprovantes x
   where x.phone_normalized = p_phone and x.modo = 'dono' and x.recebido_em > now() - interval '2 minutes'
     and x.gravado_em is null and x.situacao <> 'cancelado' and x.ultima_pergunta_em is null
     and x.id is distinct from (case when v_ativa.origem = 'comprovante' then v_ativa.referencia_id end)
   order by x.recebido_em desc
   limit 1;
  if v_chegando.id is not null then
    j_chegando := jsonb_build_object('id', v_chegando.id, 'codigo', v_chegando.codigo);
  end if;

  return jsonb_build_object(
    'conversa', true,
    'dono', true,
    'ativa', j_ativa,
    'citada', j_citada,
    'citado_cmp', j_foto,
    'pendencia', public._pendencia_viva_do_telefone(p_phone),
    'cmp_em_contexto', j_cmp,
    'cmp_substituido', j_sub,
    'ultima_do_cmp', j_ult,
    'cmp_chegando', j_chegando);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 1b. pergunta_interromper (revisão de 11/10/2026): o texto livre do dono foi ao ASSISTENTE com a
--     pergunta de um CMP aberta. Marca a pergunta (dados.interrompida_em): o "sim"/número seguinte,
--     sem citar, pode ser a resposta a uma pergunta informal do assistente — não vale para o CMP sem
--     que a pergunta seja reapresentada. true = marcou.
-- ---------------------------------------------------------------------------------------------
create or replace function public.pergunta_interromper(p_phone text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_dono_phone text;
  v_n integer;
begin
  if p_phone is null or p_phone !~ '^[0-9]{10,15}$' then
    raise exception 'pergunta_interromper: telefone inválido' using errcode = '22023';
  end if;
  select d.phone into v_dono_phone from public._comprovante_dono() d;
  if v_dono_phone is distinct from p_phone or not public._comprovante_conversa_ligada() then
    return false;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || p_phone, 0));
  update public.whatsapp_perguntas w
     set dados = w.dados || jsonb_build_object('interrompida_em', now())
   where w.phone_normalized = p_phone and w.status = 'aberta' and w.origem = 'comprovante'
     and not (w.dados ? 'interrompida_em');
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. pergunta_ocupado: quem quer perguntar ao dono (lembretes, acompanhar-conversas) adia se sim
-- ---------------------------------------------------------------------------------------------
create or replace function public.pergunta_ocupado(p_phone text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_aberta record;
  v_pend jsonb;
begin
  if p_phone is null or p_phone !~ '^[0-9]{10,15}$' then
    raise exception 'pergunta_ocupado: telefone inválido' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || p_phone, 0));

  if public._comprovante_conversa_ligada() then
    perform public._pergunta_limpar(p_phone);
    select w.origem, w.referencia_codigo, w.aberta_em into v_aberta
      from public.whatsapp_perguntas w
     where w.phone_normalized = p_phone and w.status = 'aberta';
    if found then
      return jsonb_build_object('ocupado', true, 'por', jsonb_build_object(
        'origem', v_aberta.origem, 'titulo', v_aberta.referencia_codigo, 'desde', v_aberta.aberta_em));
    end if;
  end if;

  -- desligada: só a pendência viva (exatamente o que lembretes e acompanhar olham hoje)
  v_pend := public._pendencia_viva_do_telefone(p_phone);
  if v_pend is not null then
    return jsonb_build_object('ocupado', true, 'por', jsonb_build_object(
      'origem', 'assistente', 'titulo', v_pend->>'titulo', 'desde', v_pend->'desde'));
  end if;
  return jsonb_build_object('ocupado', false, 'por', null);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. pergunta_registrar_externa: a pendência do assistente/lembretes entra no registro.
--    Toda aberta vira substituida (a do CMP volta para a fila sem perder o que já foi respondido).
--    Desligada: não grava nada ({"id":null,"desligada":true}).
-- ---------------------------------------------------------------------------------------------
create or replace function public.pergunta_registrar_externa(p jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_phone text;
  v_origem text;
  v_tipo text;
  v_ref uuid;
  v_titulo text;
  v_dono_phone text;
  v_expira timestamptz;
  v_id uuid;
  v_subst jsonb;
  r record;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'pergunta_registrar_externa: a entrada precisa ser um objeto' using errcode = '22023';
  end if;
  v_phone := p->>'phone';
  v_origem := p->>'origem';
  v_tipo := p->>'tipo';
  v_titulo := left(nullif(btrim(coalesce(p->>'titulo', '')), ''), 80);
  begin
    v_ref := (p->>'referencia_id')::uuid;
  exception when others then
    raise exception 'pergunta_registrar_externa: referencia_id malformado' using errcode = '22023';
  end;
  if v_phone is null or v_phone !~ '^[0-9]{10,15}$' then
    raise exception 'pergunta_registrar_externa: telefone inválido' using errcode = '22023';
  end if;
  if v_origem is null or v_origem not in ('assistente', 'lembrete_revisao', 'campanha_temporada', 'acompanhar_conversa') then
    raise exception 'pergunta_registrar_externa: origem inválida' using errcode = '22023';
  end if;
  if v_tipo is null or v_tipo not in ('confirmacao', 'opcoes') then
    raise exception 'pergunta_registrar_externa: tipo inválido' using errcode = '22023';
  end if;
  if v_ref is null then
    raise exception 'pergunta_registrar_externa: referencia_id obrigatório' using errcode = '22023';
  end if;

  select d.phone into v_dono_phone from public._comprovante_dono() d;
  if not public._comprovante_conversa_ligada() or v_dono_phone is distinct from v_phone then
    return jsonb_build_object('id', null, 'desligada', true);
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || v_phone, 0));
  perform public._pergunta_limpar(v_phone);

  -- a mesma pendência registrada de novo: fica a que já está (idempotente)
  select w.id into v_id from public.whatsapp_perguntas w
   where w.phone_normalized = v_phone and w.status = 'aberta' and w.origem = v_origem and w.referencia_id = v_ref;
  if v_id is not null then
    return jsonb_build_object('id', v_id, 'substituiu', null);
  end if;

  for r in
    select w.id, w.origem, w.referencia_id, w.referencia_codigo
      from public.whatsapp_perguntas w
     where w.phone_normalized = v_phone and w.status = 'aberta'
  loop
    perform public._pergunta_fechar(r.id, 'substituida', 'substituida_por:' || v_origem, null);
    if r.origem = 'comprovante' then
      perform public._comprovante_pergunta_saiu(r.referencia_id);
    end if;
    v_subst := jsonb_build_object('origem', r.origem, 'referencia_codigo', r.referencia_codigo);
  end loop;

  if v_tipo = 'confirmacao' then
    select a.expires_at into v_expira from public.ai_operator_pending_actions a where a.id = v_ref;
    v_expira := coalesce(v_expira, now() + interval '24 hours');
  else
    v_expira := now() + interval '4 hours';
  end if;

  insert into public.whatsapp_perguntas (phone_normalized, origem, tipo, referencia_id, referencia_codigo, expira_em)
  values (v_phone, v_origem, v_tipo, v_ref, coalesce(v_titulo, case when v_tipo = 'opcoes' then 'escolha da lista do assistente' else 'ação pendente' end), v_expira)
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'substituiu', v_subst);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. pergunta_marcar_enviada: o whatsapp-send confirmou o envio da pergunta (só se ainda aberta).
--    Grava enviada_em (a primeira confirmação, mesmo sem o id do WhatsApp — resposta mais velha que
--    isto não é resposta a esta pergunta) e acrescenta o id em wa_message_ids (o reenvio também é
--    citável; até 20). wa_message_id fica sendo o do primeiro envio.
-- ---------------------------------------------------------------------------------------------
create or replace function public.pergunta_marcar_enviada(p_id uuid, p_wa_message_id text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_phone text;
  v_wa text := nullif(btrim(coalesce(p_wa_message_id, '')), '');
begin
  if v_wa is not null and char_length(v_wa) > 128 then
    raise exception 'pergunta_marcar_enviada: id do WhatsApp inválido' using errcode = '22023';
  end if;
  select w.phone_normalized into v_phone from public.whatsapp_perguntas w where w.id = p_id;
  if v_phone is null then
    return;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || v_phone, 0));
  update public.whatsapp_perguntas w
     set enviada_em = coalesce(w.enviada_em, now()),
         wa_message_id = coalesce(w.wa_message_id, v_wa),
         wa_message_ids = case when v_wa is null or v_wa = any (w.wa_message_ids) or cardinality(w.wa_message_ids) >= 20
                               then w.wa_message_ids else w.wa_message_ids || v_wa end
   where w.id = p_id and w.status = 'aberta';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. pergunta_encerrar_externa: fecha as abertas que não são de comprovante
-- ---------------------------------------------------------------------------------------------
create or replace function public.pergunta_encerrar_externa(p_phone text, p_status text)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r record;
  v_n integer := 0;
begin
  if p_phone is null or p_phone !~ '^[0-9]{10,15}$' then
    raise exception 'pergunta_encerrar_externa: telefone inválido' using errcode = '22023';
  end if;
  if p_status is null or p_status not in ('respondida', 'cancelada') then
    raise exception 'pergunta_encerrar_externa: status inválido' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || p_phone, 0));
  for r in
    select w.id from public.whatsapp_perguntas w
     where w.phone_normalized = p_phone and w.status = 'aberta' and w.origem <> 'comprovante'
  loop
    perform public._pergunta_fechar(r.id, p_status, null, null);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Privilégios (revogar de anon/authenticated POR ASSINATURA; execute só para service_role)
-- ---------------------------------------------------------------------------------------------
revoke all on function public._pendencia_viva_do_telefone(text) from public, anon, authenticated;
revoke all on function public._comprovante_pergunta_saiu(uuid) from public, anon, authenticated;
revoke all on function public._comprovante_sair_da_conversa(uuid) from public, anon, authenticated;
revoke all on function public._pergunta_fechar(uuid, text, text, uuid) from public, anon, authenticated;
revoke all on function public._pergunta_limpar(text) from public, anon, authenticated;
revoke all on function public._pergunta_abrir(jsonb) from public, anon, authenticated;
revoke all on function public._pendencia_viva_do_telefone(text) from service_role;
revoke all on function public._comprovante_pergunta_saiu(uuid) from service_role;
revoke all on function public._comprovante_sair_da_conversa(uuid) from service_role;
revoke all on function public._pergunta_fechar(uuid, text, text, uuid) from service_role;
revoke all on function public._pergunta_limpar(text) from service_role;
revoke all on function public._pergunta_abrir(jsonb) from service_role;

revoke all on function public.pergunta_rotear(text, text) from public, anon, authenticated;
revoke all on function public.pergunta_interromper(text) from public, anon, authenticated;
revoke all on function public.pergunta_ocupado(text) from public, anon, authenticated;
revoke all on function public.pergunta_registrar_externa(jsonb) from public, anon, authenticated;
revoke all on function public.pergunta_marcar_enviada(uuid, text) from public, anon, authenticated;
revoke all on function public.pergunta_encerrar_externa(text, text) from public, anon, authenticated;

grant execute on function public.pergunta_rotear(text, text) to service_role;
grant execute on function public.pergunta_interromper(text) to service_role;
grant execute on function public.pergunta_ocupado(text) to service_role;
grant execute on function public.pergunta_registrar_externa(jsonb) to service_role;
grant execute on function public.pergunta_marcar_enviada(uuid, text) to service_role;
grant execute on function public.pergunta_encerrar_externa(text, text) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: as 6 RPCs só para service_role; os 6 helpers para ninguém além do dono da função.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
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
    'public._pergunta_abrir(jsonb)'];
begin
  foreach v_f in array v_rpcs || v_helpers loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função do registro de perguntas exposta para anon/authenticated: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs loop
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  foreach v_f in array v_helpers loop
    if has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'helper interno do registro alcançável pela service_role: %', v_f;
    end if;
  end loop;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011201000', 'whatsapp_perguntas_rpcs')
on conflict do nothing;
