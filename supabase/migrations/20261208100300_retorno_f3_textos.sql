-- Retorno rápido ao cliente, F3 (P4): os textos da proposta, a validade do envio e o caso que não fecha com a visita a combinar.
-- Gerada por script (scripts/gerar_f3.cjs textos) a partir do corpo vigente das funções; só os trechos marcados -- F3 são novos.
--
-- 1. _retorno_corpo_do_modelo ganha o M07 (precisa ver no local) e _retorno_tipo_curto o nome curto dele. Não entra em
--    retorno_modelo_tipos: como a M06, nunca é promovível, só sai pela letra e com PIN.
-- 2. *Precisa ver no local* não fecha o caso (rr-f1-10): _retorno_aplicar_efeitos grava visita_a_combinar_em e mantém o estado;
--    _retorno_checar_antes corta adiamento, fim do dia e urgente enquanto a visita está a combinar; retorno_vigia não fecha por silêncio,
--    por nada ou por expirar o caso com a marca. Quem tira da lista é o dono: *resolvido N*, resposta com conteúdo ou o PDF depois da visita.
-- 3. _cliente_ja_apresentada conta o PDF que saiu: a legenda com apresentação é apresentação.
-- 4. _retorno_texto_f3 tem as legendas L01 a L08; retorno_legenda_do_orcamento escolhe a variante e monta o contexto do validador
--    com as 9 chaves de ContextoDoValidador; _retorno_validade_do_envio é a data K6 (7 dias corridos do envio).
--
-- Sem dado. Tudo nasce desligado: nada aqui é chamado sem proposta, e a proposta nasce com previa_modo = 'desligado'.
-- Reverter: reaplicar as versões de retorno_vigia (20261201100000), _retorno_aplicar_efeitos e _retorno_checar_antes (20261123100600),
-- _retorno_corpo_do_modelo (20261123100300), _retorno_tipo_curto (20261123100100) e _cliente_ja_apresentada (20261116100400).

-- ── 1. Os textos das legendas (L01 a L08) ──────────────────────────────────────────────────────────

create or replace function public._retorno_texto_f3(p_tipo text, p_variante text, p_dados jsonb)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  c_dia constant text := '^(hoje|amanhã|(segunda|terça|quarta|quinta|sexta|sábado|domingo) \([0-9]{2}/[0-9]{2}\))$';
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_modelo text;
  v_texto text;
  v_campo text;
  v_valor text;
begin
  v_modelo := case p_tipo || '/' || p_variante
    when 'orcamento_pdf/padrao' then -- L01
      '{nome}, segue o orçamento {do_servico}. Ele vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.'
    when 'orcamento_pdf/padrao_apresentacao' then -- L02
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento {do_servico}, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.'
    when 'orcamento_pdf/sem_servico' then -- L03
      '{nome}, segue o orçamento que você pediu. Ele vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.'
    when 'orcamento_pdf/sem_servico_apresentacao' then -- L04
      'Oi, {nome}! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento que você pediu, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.'
    when 'orcamento_pdf/sem_nome' then -- L05
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento {do_servico}, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.'
    when 'orcamento_pdf/sem_nome_servico' then -- L06
      'Olá! Aqui é a Claudia, assistente virtual da HBR. Segue o orçamento que você pediu, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.'
    when 'orcamento_pdf/sem_nome_ja_apresentada' then -- L07
      'Segue o orçamento {do_servico}, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.'
    when 'orcamento_pdf/sem_nome_servico_ja_apresentada' then -- L08
      'Segue o orçamento que você pediu, que vale até {validade}. Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.'
  end;
  if v_modelo is null then
    raise exception 'texto F3: par desconhecido' using errcode = '22023';
  end if;

  v_texto := v_modelo;
  for v_campo in select distinct (regexp_matches(v_modelo, '\{([a-z_]+)\}', 'g'))[1] loop
    v_valor := nullif(btrim(d ->> v_campo), '');
    if v_valor is null or (v_campo = 'validade' and v_valor !~ c_dia) then
      raise exception 'texto F3: campo % ausente ou inválido', v_campo using errcode = '22023';
    end if;
    v_texto := replace(v_texto, '{' || v_campo || '}', v_valor);
  end loop;
  return v_texto;
end;
$$;

comment on function public._retorno_texto_f3(text, text, jsonb) is
  'Retorno F3 (P4): as legendas L01 a L08 do PDF do orçamento. Lista fechada de tipo/variante, modelo fixo, falta de dado = 22023. _retorno_texto_f2 não muda.';

revoke all on function public._retorno_texto_f3(text, text, jsonb) from public, anon, authenticated;

-- ── 2. A validade do envio (K6) ──────────────────────────────────────────────────────────────────────

create or replace function public._retorno_validade_do_envio(p_agora timestamptz)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select ((coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date + (public._retorno_cfg()).validade_orcamento_dias)::date;
$$;

comment on function public._retorno_validade_do_envio(timestamptz) is
  'Retorno F3 (P4, K6): 7 dias corridos contados do envio, na data de Brasília. É a data que vai no PDF e na legenda: nenhum dos dois calcula separado.';

revoke all on function public._retorno_validade_do_envio(timestamptz) from public, anon, authenticated;

-- ── 3. A legenda do PDF e o contexto do validador ────────────────────────────────────────────────────

create or replace function public.retorno_legenda_do_orcamento(p_abertura uuid, p_previa uuid default null, p_agora timestamptz default now(),
                                                               p_client uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_sep constant text := chr(31);
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (v_agora at time zone c_fuso)::date;
  v_ab public.retorno_aberturas;
  v_cliente uuid;
  v_nome text;
  v_ja_apresentada boolean;
  v_familias text[];
  v_do_servico text;
  v_validade_data date;
  v_validade text;
  v_ddmm text;
  v_variante text;
  v_texto text;
  v_corte text;
  v_valor text;
  v_trechos text[];
  v_cliente_diz jsonb;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found then
    raise exception 'legenda: caso inexistente' using errcode = '22023';
  end if;

  -- No ramo do rascunho, quem vale é o cliente de service_orders; senão o cadastro do caso, que cobre o número novo provisório.
  v_cliente := coalesce(p_client, (public._retorno_cadastro_do_caso(p_abertura) ->> 'client_id')::uuid);
  v_nome := public._retorno_nome(v_cliente);
  v_ja_apresentada := public._cliente_ja_apresentada(v_cliente, v_ab.chave, v_hoje);

  if p_previa is not null then
    select p.familias into v_familias from public.retorno_previa p where p.id = p_previa;
    v_do_servico := public._retorno_familia_rotulo(coalesce(v_familias, '{}'::text[])) ->> 'do_servico';
  end if;

  v_validade_data := public._retorno_validade_do_envio(v_agora);
  v_validade := public._retorno_quando(v_validade_data, v_hoje);
  v_ddmm := (regexp_match(coalesce(v_validade, ''), '[0-9]{2}/[0-9]{2}'))[1];

  v_variante := case
    when v_nome is not null and v_do_servico is not null then case when v_ja_apresentada then 'padrao' else 'padrao_apresentacao' end
    when v_nome is not null then case when v_ja_apresentada then 'sem_servico' else 'sem_servico_apresentacao' end
    when v_do_servico is not null then case when v_ja_apresentada then 'sem_nome_ja_apresentada' else 'sem_nome' end
    else case when v_ja_apresentada then 'sem_nome_servico_ja_apresentada' else 'sem_nome_servico' end
  end;

  v_texto := public._retorno_texto_f3('orcamento_pdf', v_variante,
    jsonb_build_object('nome', v_nome, 'do_servico', v_do_servico, 'validade', v_validade));

  -- Os trechos do modelo: o texto cortado nos valores dos {campos}, o maior primeiro (como em _retorno_contexto_do_validador).
  v_corte := v_texto;
  for v_valor in
    select x from unnest(array[v_nome, v_validade, v_do_servico]) as x
     where x is not null and btrim(x) <> ''
     order by char_length(x) desc, x
  loop
    v_corte := replace(v_corte, v_valor, c_sep);
  end loop;
  v_trechos := array(select p from unnest(string_to_array(v_corte, c_sep)) as p where btrim(p) <> '');

  -- Os corpos das recebidas do caso, gravadas até agora (só para o eco; nunca entram no texto).
  select coalesce(jsonb_agg(w.body order by rm.recebida_em, rm.whatsapp_message_id), '[]'::jsonb) into v_cliente_diz
    from public.retorno_mensagens rm
    join public.whatsapp_messages w on w.id = rm.whatsapp_message_id
   where rm.abertura_id = v_ab.id
     and w.occurred_at <= v_agora
     and w.body is not null;

  return jsonb_build_object(
    'texto', v_texto,
    'validade_data', v_validade_data,
    'contexto', jsonb_build_object(
      'audiencia', 'cliente',
      'datas_permitidas', to_jsonb(array_remove(array[v_validade, v_ddmm], null)),
      'horas_permitidas', '[]'::jsonb,
      'nome_permitido', v_nome,
      'nomes_de_outros', '[]'::jsonb,   -- papel cliente_ambiguo não gera proposta nem rascunho
      'os_permitidas', '[]'::jsonb,     -- a legenda não cita ORÇ
      'textos_do_cliente', v_cliente_diz,
      'trechos_do_modelo', to_jsonb(coalesce(v_trechos, '{}'::text[])),
      'marcas', jsonb_build_object('tem_proposta', true, 'tem_topo', false, 'cliente_ouviu', false, 'conferida', false)));
end;
$$;

comment on function public.retorno_legenda_do_orcamento(uuid, uuid, timestamptz, uuid) is
  'Retorno F3 (P4, C-LEG): {texto, contexto, validade_data} da legenda do PDF. contexto traz as 9 chaves de ContextoDoValidador. p_previa nulo usa as variantes sem serviço; p_client decide nome e apresentação no ramo do rascunho. validade_data é a data que vai ao ORÇ.';

revoke all on function public.retorno_legenda_do_orcamento(uuid, uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.retorno_legenda_do_orcamento(uuid, uuid, timestamptz, uuid) to service_role;

-- ── 4. Gerado do corpo vigente, com os trechos -- F3 ──────────────────────────────────────────────────

create or replace function public._retorno_corpo_do_modelo(p_tipo text, p_dados jsonb)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_no_bem text := nullif(btrim(d ->> 'no_bem'), '');
  v_dia text := nullif(btrim(d ->> 'dia_peca'), '');
begin
  case p_tipo
    when 'modelo_aguarda_peca' then
      if v_no_bem is null then raise exception 'modelo: falta no_bem' using errcode = '22023'; end if;
      return format('o serviço %s está aguardando a chegada de uma peça. %s', v_no_bem,
                    case when coalesce((d ->> 'te_aviso')::boolean, false) then 'Assim que ela chegar, aviso você por aqui.'
                         else 'Assim que ela chegar, o Gustavo avisa você.' end);
    when 'modelo_peca_chegou' then
      if v_dia is null or v_dia !~ '^[0-9]{2}/[0-9]{2}$' then raise exception 'modelo: falta dia_peca' using errcode = '22023'; end if;
      return case when d ->> 'intencao' = 'status'
                  then format('a peça do serviço chegou no dia %s. Agora o Gustavo vai marcar o dia do serviço.', v_dia)
                  else format('a peça chegou sim, no dia %s. Agora o Gustavo vai marcar o dia do serviço.', v_dia) end;
    when 'modelo_pronto' then
      if v_no_bem is null then raise exception 'modelo: falta no_bem' using errcode = '22023'; end if;
      return format('o serviço %s está pronto. Qual o melhor dia para você buscar? O Gustavo combina o horário por aqui.', v_no_bem);
    when 'modelo_em_servico' then
      if v_no_bem is null then raise exception 'modelo: falta no_bem' using errcode = '22023'; end if;
      return format('o serviço %s está em andamento hoje. O Gustavo passa as novidades por aqui.', v_no_bem);
    when 'modelo_liberado' then
      return 'pode sim: o serviço está liberado para retirada. É só combinar o horário com o Gustavo por aqui.';
    when 'modelo_retirada_nao' then
      return 'ainda não dá para retirar, porque o serviço não terminou. O Gustavo chama você para combinar.';
    when 'modelo_ver_no_local' then   -- F3 (M07): como a M06, nunca é promovível; só sai pela letra e com PIN
      return 'para passar o valor certo, o Gustavo precisa ver o serviço no local. Ele combina o melhor dia com você por aqui.';
    else
      raise exception 'modelo: tipo desconhecido' using errcode = '22023';
  end case;
end;
$$;

comment on function public._retorno_corpo_do_modelo(text, jsonb) is
  'Retorno F2 (P6) e F3 (P4): o corpo M01 a M07, começando em minúscula: a abertura decide a maiúscula. Falta de dado = 22023.';

create or replace function public._retorno_tipo_curto(p_tipo text)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_tipo
    when 'modelo_aguarda_peca' then 'aguardando peça'
    when 'modelo_peca_chegou' then 'peça chegou'
    when 'modelo_pronto' then 'pronto'
    when 'modelo_em_servico' then 'em serviço'
    when 'modelo_liberado' then 'liberado'
    when 'modelo_retirada_nao' then 'retirada ainda não'
    when 'modelo_ver_no_local' then 'ver no local'   -- F3
  end;
$$;

create or replace function public._retorno_checar_antes(p_saida uuid, p_agora timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  c_decididas constant text[] := array['sombra', 'preparada', 'enviando', 'enviada', 'incerta'];
  v_cfg public.retorno_config := public._retorno_cfg();
  v_agora timestamptz := coalesce(p_agora, now());
  v_s public.retorno_saidas;
  v_ab public.retorno_aberturas;
  v_rh jsonb;
  v_ultima timestamptz;
  v_audio timestamptz;
  v_t jsonb;
  v_n integer;
  v_depois timestamptz;   -- F2
  v_mod text;             -- F2
  v_m jsonb;              -- F2
begin
  -- Sem a linha de configuração: espera (falha fecha, sem perder a saída).
  if v_cfg.id is null then
    return jsonb_build_object('acao', 'adiar', 'motivo', 'sem_config', 'enviar_em', v_agora + interval '2 minutes');
  end if;

  select * into v_s from public.retorno_saidas s where s.id = p_saida;
  if not found then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'erro', 'enviar_em', null);
  end if;
  select * into v_ab from public.retorno_aberturas a where a.id = v_s.abertura_id;

  -- 1. Caso fechado (ou saída sem caso).
  if not found or v_ab.estado = 'fechada' then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'caso_fechado', 'enviar_em', null);
  end if;

  -- F2: a saída que esperou o *segura tudo*: quem escreveu há mais de 12 h fica com o dono. Um "recebi" de 20 h atrás seria pior que nada.
  if coalesce((v_s.dados ->> 'segurada')::boolean, false) and v_ab.ultima_em < v_agora - v_cfg.recibo_intervalo then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'segura_tudo', 'enviar_em', null);
  end if;

  -- 1b. O aviso honesto fora do tempo dele (desvio, falha fecha): o adiamento só vale antes do "até X", e o
  --     fim do dia só no próprio dia.
  if v_s.tipo = 'adiamento' and v_ab.prometido_ate is not null and v_agora >= v_ab.prometido_ate then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'caso_vencido', 'enviar_em', null);
  end if;
  if v_s.tipo = 'fim_do_dia' and coalesce(v_s.dados ->> 'dia', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
     and (v_agora at time zone c_fuso)::date > (v_s.dados ->> 'dia')::date then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'caso_vencido', 'enviar_em', null);
  end if;

  -- F3 (P4): com a visita a combinar, nada automático fala de prazo (rr-f1-10). O recibo de mensagem nova do cliente segue normal.
  if v_ab.visita_a_combinar_em is not null and v_s.tipo in ('adiamento', 'fim_do_dia', 'urgente') then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'visita_a_combinar', 'enviar_em', null);
  end if;

  -- 2 e 3. O dono respondeu. O "ok, já vejo" cancela o recibo e os outros, mas não o aviso honesto (adiamento
  --        e fim do dia): esses só a resposta de conteúdo cancela (A.2).
  v_rh := public._retorno_resposta_humana(v_ab.id, v_agora);
  -- F2: modelo aprovado no cartão: só a resposta humana DEPOIS da aprovação cancela. Quem aprovou já sabia do "ok, já vejo" anterior.
  --     respondida_em é a PRIMEIRA saída humana, e por isso esta conta é à parte.
  if v_s.tipo like 'modelo\_%' escape '\' and coalesce((v_s.dados ->> 'aprovada')::boolean, false) then
    v_depois := public._retorno_resposta_depois(v_ab.id, (v_s.dados ->> 'aprovada_em')::timestamptz, v_agora);
    if v_depois is not null then
      return jsonb_build_object('acao', 'cancelar', 'motivo', 'respondida_pelo_dono', 'enviar_em', null,
                                'resposta', v_rh || jsonb_build_object('respondida_em', v_depois));
    end if;
  elsif v_s.tipo not in ('adiamento', 'fim_do_dia') and v_rh ->> 'respondida_em' is not null then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'respondida_pelo_dono', 'enviar_em', null, 'resposta', v_rh);
  end if;
  if v_s.tipo in ('adiamento', 'fim_do_dia') and v_rh ->> 'cumprida_em' is not null then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'respondida_pelo_dono', 'enviar_em', null, 'resposta', v_rh);
  end if;

  -- F2: aprovada há mais de 30 min na fila: o fato pode ter envelhecido. M06 não sai de fato: fica de fora.
  if coalesce((v_s.dados ->> 'aprovada')::boolean, false) and v_s.tipo not in ('modelo_retirada_nao', 'modelo_ver_no_local')   /* F3 */
     and (v_s.dados ->> 'aprovada_em')::timestamptz < v_agora - interval '30 minutes'
     and public._retorno_modelo_do_caso(v_ab.id, v_agora) ->> 'modelo' is distinct from v_s.tipo then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'fato_mudou', 'enviar_em', null);
  end if;

  -- 4. A rajada continua: recebida nova da chave há menos de carencia_min (gravada até agora).
  select max(w.occurred_at) into v_ultima
    from public.whatsapp_messages w
   where public._agenda_chave_telefone(w.phone_normalized) = v_s.chave
     and w.direction = 'inbound'
     and w.occurred_at <= v_agora
     and w.occurred_at > v_agora - make_interval(mins => v_cfg.carencia_min);
  if v_ultima is not null then
    return jsonb_build_object('acao', 'adiar', 'motivo', 'rajada',
                              'enviar_em', v_ultima + make_interval(mins => v_cfg.carencia_min));
  end if;

  -- 5. Lote global (a Evolution regravando ao voltar de queda): algum minuto da janela com lote_linhas_por_min
  --    ou mais linhas gravadas.
  if exists (select 1 from public.whatsapp_messages w
              where w.occurred_at > v_agora - make_interval(mins => v_cfg.lote_janela_min)
                and w.occurred_at <= v_agora
              group by date_trunc('minute', w.occurred_at)
             having count(*) >= v_cfg.lote_linhas_por_min) then
    return jsonb_build_object('acao', 'adiar', 'motivo', 'lote_global', 'enviar_em', v_agora + interval '2 minutes');
  end if;

  -- 6. O número novo que mandou áudio há pouco espera a transcrição (o cliente identificado não espera).
  if v_ab.papel = 'numero_novo' then
    select max(rm.gravada_em) into v_audio
      from public.retorno_mensagens rm
     where rm.abertura_id = v_ab.id
       and rm.audio_pendente
       and rm.gravada_em <= v_agora
       and rm.gravada_em > v_agora - make_interval(mins => v_cfg.audio_espera_min);
    if v_audio is not null then
      return jsonb_build_object('acao', 'adiar', 'motivo', 'aguarda_transcricao',
                                'enviar_em', v_audio + make_interval(mins => v_cfg.audio_espera_min));
    end if;
  end if;

  -- 7. A triagem de novo (P5): vendedor que apareceu, a agenda que consumiu, a promessa do dono que chegou…
  --    A confirmação do PARAR é de um caso 'nada' por construção: só segue com o motivo 'parar'.
  v_t := public._retorno_triar(v_ab.id, v_agora);
  select * into v_s from public.retorno_saidas s where s.id = p_saida;
  if v_s.estado <> 'agendada' then
    -- a própria triagem a cancelou (o caso virou 'nada' ou a saudação foi substituída)
    return jsonb_build_object('acao', 'cancelar', 'motivo', coalesce(v_s.motivo, 'nivel_nada'), 'enviar_em', null);
  end if;
  if v_t ->> 'nivel' = 'nada' and not (v_s.tipo = 'parar' and v_t ->> 'motivo' = 'parar') then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'nivel_nada', 'enviar_em', null);
  end if;
  if v_s.enviar_em > v_agora then
    -- a triagem empurrou o recibo (mensagem nova da rajada que o webhook acabou de ler)
    return jsonb_build_object('acao', 'adiar', 'motivo', 'rajada', 'enviar_em', v_s.enviar_em);
  end if;

  -- 8 e 9. O recibo (e a saudação) de mensagem gravada com atraso: mais de volta_max vai a "Para conferir"
  --        (P9); entre volta_min e volta_max, no máximo volta_por_volta_max textos de volta em 2 h.
  if v_s.tipo = any (c_recibos) or v_s.tipo = 'saudacao_numero_novo' then
    if v_ab.atraso_gravacao > v_cfg.volta_max then
      return jsonb_build_object('acao', 'cancelar', 'motivo', 'atraso_longo', 'enviar_em', null);
    end if;
    if v_ab.atraso_gravacao >= v_cfg.volta_min then
      select count(*) into v_n
        from public.retorno_saidas o
       where o.emissor = 'retorno'
         and o.id <> v_s.id
         and (coalesce((o.dados ->> 'volta')::boolean, false) or coalesce(o.variante, '') like 'volta%')
         and o.estado = any (c_decididas)
         and o.decidida_em > v_agora - interval '2 hours'
         and o.decidida_em <= v_agora;
      if v_n >= v_cfg.volta_por_volta_max then
        return jsonb_build_object('acao', 'cancelar', 'motivo', 'teto_volta', 'enviar_em', null);
      end if;
    end if;
  end if;

  -- F2: quem responde é o modelo promovido, e o recibo espera. O validador roda na edge, depois do retorno_pegar: cancelar o
  --     recibo aqui deixaria o cliente sem palavra se o modelo fosse recusado.
  if v_s.tipo = 'recibo_cliente' then
    select m.estado into v_mod from public.retorno_saidas m
     where m.abertura_id = v_ab.id and m.tipo like 'modelo\_%' escape '\'
     order by m.criada_em desc limit 1;
    if v_mod in ('agendada', 'preparada', 'enviando') then
      return jsonb_build_object('acao', 'adiar', 'motivo', 'aguarda_modelo', 'enviar_em', v_agora + interval '1 minute');
    elsif v_mod is null then
      v_m := public._retorno_modelo_do_caso(v_ab.id, v_agora);
      if v_m ->> 'modelo' is not null and public._retorno_tipo_sozinho(v_m ->> 'modelo', v_agora) then
        perform public._retorno_agendar_modelo(v_ab.id, v_m, v_agora);
        return jsonb_build_object('acao', 'adiar', 'motivo', 'aguarda_modelo', 'enviar_em', v_agora + interval '2 minutes');
      end if;
    end if;
    -- recusada, cancelada ou sombra: o recibo segue, sem nova tentativa. enviada/incerta: o caso fechou e a regra 1 já cancelou.
  end if;

  -- 10.
  return jsonb_build_object('acao', 'seguir', 'motivo', null, 'enviar_em', null);
end;
$$;

create or replace function public._retorno_aplicar_efeitos(p_saida uuid, p_agora timestamptz)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  v_s public.retorno_saidas;
  v_em timestamptz;
  v_pz jsonb;
  v_sozinho boolean;   -- F2
  v_envios integer;    -- F2
begin
  select * into v_s from public.retorno_saidas s where s.id = p_saida;
  if not found or v_s.abertura_id is null or v_s.estado not in ('sombra', 'enviada', 'incerta') then
    return;
  end if;
  v_em := coalesce(v_s.decidida_em, p_agora, now());
  v_pz := case when jsonb_typeof(v_s.dados -> 'prazo') = 'object' then v_s.dados -> 'prazo' end;

  update public.retorno_aberturas a
     set recibo_em = case when v_s.tipo = any (c_recibos) then v_em else a.recibo_em end,
         prometido_ate = case when v_s.tipo = any (c_recibos) then (v_pz ->> 'prometido_ate')::timestamptz
                              else a.prometido_ate end,
         prometido_fonte = case when v_s.tipo = any (c_recibos) then v_pz ->> 'fonte' else a.prometido_fonte end,
         faixa = case when v_s.tipo = any (c_recibos) then v_pz ->> 'faixa' else a.faixa end,
         -- as mensagens automáticas do 1º contato do número novo (saudação, recibo e coleta; J.10)
         coleta_n = case when a.papel = 'numero_novo'
                              and v_s.tipo in ('saudacao_numero_novo', 'recibo_numero_novo', 'coleta_numero_novo')
                         then least(a.coleta_n + 1, 2) else a.coleta_n end,
         adiamento_em = case when v_s.tipo = 'adiamento' then v_em else a.adiamento_em end,
         segundo_prazo = case when v_s.tipo = 'adiamento'
                              then coalesce((v_s.dados ->> 'x2')::timestamptz, public._retorno_x2(a.prometido_ate))
                              else a.segundo_prazo end,
         fim_do_dia_em = case when v_s.tipo = 'fim_do_dia' then v_em else a.fim_do_dia_em end,
         estado = case when v_s.tipo = 'fim_do_dia' and a.estado = 'aberta' then 'vencida' else a.estado end,
         urgente_em = case when v_s.tipo = 'urgente' then v_em else a.urgente_em end,
         atualizada_em = now()
   where a.id = v_s.abertura_id;

  -- F3 (P4): *precisa ver no local* não fecha (rr-f1-10): grava a marca, e o caso fica na lista até o dono resolver. As agendadas
  --          caem, porque a régua automática não fala de prazo com a visita a combinar.
  if v_s.tipo = 'modelo_ver_no_local' and v_s.estado in ('enviada', 'incerta') then
    update public.retorno_aberturas a
       set recibo_em = coalesce(a.recibo_em, v_em), visita_a_combinar_em = coalesce(a.visita_a_combinar_em, v_em), atualizada_em = now()
     where a.id = v_s.abertura_id;
    update public.retorno_saidas o
       set estado = 'cancelada', motivo = 'visita_a_combinar', decidida_em = v_em, atualizada_em = now()
     where o.abertura_id = v_s.abertura_id and o.estado = 'agendada' and o.id <> v_s.id;
    return;
  end if;

  -- F2: o modelo com fato é o conteúdo: cumpre e fecha o caso, e as agendadas caem junto, inclusive o recibo de reserva.
  if v_s.tipo like 'modelo\_%' escape '\' and v_s.estado in ('enviada', 'incerta') then
    v_sozinho := coalesce((v_s.dados ->> 'sozinho')::boolean, false);
    update public.retorno_aberturas a
       set recibo_em = coalesce(a.recibo_em, v_em), cumprida_em = coalesce(a.cumprida_em, v_em),
           cumprida_por = coalesce(a.cumprida_por, case when v_sozinho then 'modelo' else 'cartao' end),
           estado = 'fechada', fechada_em = coalesce(a.fechada_em, v_em), fechada_motivo = coalesce(a.fechada_motivo, 'conteudo'),
           atualizada_em = now()
     where a.id = v_s.abertura_id;
    update public.retorno_saidas o
       set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_em, atualizada_em = now()
     where o.abertura_id = v_s.abertura_id and o.estado = 'agendada' and o.id <> v_s.id;
    if v_sozinho then
      update public.retorno_modelo_tipos t
         set envios_sozinho = t.envios_sozinho + 1, atualizado_em = now()
       where t.tipo = v_s.tipo
       returning t.envios_sozinho into v_envios;
      perform public._retorno_gravar_letra(v_s.id, v_em, v_envios);
    elsif v_s.estado = 'enviada' and coalesce((v_s.dados ->> 'aprovada')::boolean, false) then
      perform public._retorno_contar_aprovacao(v_s.tipo, v_em);
    end if;
  end if;
end;
$$;

create or replace function public.retorno_vigia(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  c_faixas constant text[] := array['manha_cedo', 'meio', 'tarde', 'noite', 'folga', 'pressa'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_local timestamp := coalesce(p_agora, now()) at time zone 'America/Sao_Paulo';
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_diario boolean;
  v_cfg public.retorno_config;
  v_erros integer[] := '{}';
  r record;
  e record;
  v_estado text;
  v_desde timestamptz;
  v_disjuntor text;
  v_n_audio integer := 0;
  v_n_resp integer := 0;
  v_n_conteudo integer := 0;
  v_n_silencio integer := 0;
  v_n_nada integer := 0;
  v_n_expirou integer := 0;
  v_n_acorde integer := 0;
  v_n_adiamento integer := 0;
  v_n_fim integer := 0;
  v_n_vencida integer := 0;
  v_n_decididas integer := 0;
  v_n_incertas integer := 0;
  v_n_presas integer := 0;
  v_n_arquivados integer := 0;
  v_n_retencao integer := 0;
  v_n_k integer;
  v_rebaixados text[] := '{}';
  v_alongadas text[] := '{}';
  v_ids uuid[];
  v_rh jsonb;
  v_cump timestamptz;
  v_x timestamptz;
  v_x2 timestamptz;
  v_a timestamptz;
  v_fim timestamptz;
  v_quando timestamptz;
  v_fila integer;
  v_modo jsonb;
  v_cad jsonb;
  v_eco timestamptz;
  v_tirar text[];
  v_novos text[];
  v_atual jsonb;
  v_prox jsonb;
  v_hora_atual time;
  v_dias_atual integer;
  v_abrir jsonb;
  v_k_acorde integer;
  v_k_adiamento integer;
  v_k_fim integer;
begin
  -- 1. Sem a linha de configuração ou desligado: nada roda.
  v_cfg := public._retorno_cfg();
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return jsonb_build_object('ok', true, 'rodou', false,
                              'motivo', case when v_cfg.id is null then 'sem_config' else 'desligado' end);
  end if;
  v_diario := v_local::time >= time '04:00' and v_local::time < time '04:01';

  -- 2. O disjuntor pela conexão, nos dois sentidos (todo estado diferente de 'open' é fora).
  begin
    select c.estado, c.desde into v_estado, v_desde
      from public.whatsapp_conexao_vigia c order by c.id limit 1;
    if v_estado is not null then
      if v_estado <> 'open' and v_desde <= v_agora - interval '10 minutes' and not v_cfg.so_reativo then
        update public.retorno_config c
           set so_reativo = true, so_reativo_motivo = 'conexao', so_reativo_desde = v_agora
         where c.id;
        v_disjuntor := 'ligou';
        perform public._retorno_log('disjuntor', 'retorno: so_reativo ligado pela conexão do WhatsApp', 'warn',
                                    jsonb_build_object('estado', v_estado, 'desde', v_desde));
      elsif v_cfg.so_reativo and v_cfg.so_reativo_motivo = 'conexao'
            and v_estado = 'open' and v_desde <= v_agora - interval '10 minutes' then
        update public.retorno_config c
           set so_reativo = false, so_reativo_motivo = null, so_reativo_desde = null
         where c.id;
        v_disjuntor := 'desligou';
        perform public._retorno_log('disjuntor', 'retorno: so_reativo desligado (a conexão voltou)', 'warn',
                                    jsonb_build_object('desde', v_desde));
      end if;
    end if;
  exception when others then
    v_erros := v_erros || 2;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 2, 'sqlstate', sqlstate));
  end;

  -- 3. O áudio transcrito: o corpo mudou, a triagem roda de novo (retorno_abrir nunca levanta). Conta só a
  --    reavaliação com ok; a linha que continua com o hash antigo sai do filtro, com log (nada volta a cada
  --    minuto por 24 h).
  begin
    for r in
      select rm.whatsapp_message_id as msg, rm.consumida, md5(coalesce(w.body, '')) as hash
        from public.retorno_mensagens rm
        join public.whatsapp_messages w on w.id = rm.whatsapp_message_id
       where rm.audio_pendente
         and rm.recebida_em > v_agora - v_cfg.audio_reavaliar_max
         and rm.recebida_em <= v_agora
         and w.occurred_at <= v_agora
         and md5(coalesce(w.body, '')) <> rm.corpo_hash
       order by rm.recebida_em, rm.whatsapp_message_id
       limit 200
    loop
      begin
        v_abrir := public.retorno_abrir(r.msg, r.consumida, v_agora);
        if coalesce((v_abrir ->> 'ok')::boolean, false) then
          v_n_audio := v_n_audio + 1;
        end if;
        -- ok = false desfaz tudo (o hash fica o antigo); a mensagem ignorada também não o regrava
        update public.retorno_mensagens rm
           set audio_pendente = false
         where rm.whatsapp_message_id = r.msg
           and rm.audio_pendente
           and rm.corpo_hash is distinct from r.hash;
        if found then
          perform public._retorno_log('vigia', 'retorno_vigia: áudio transcrito que o retorno_abrir não reavaliou', 'error',
                                      jsonb_build_object('passo', 3, 'mensagem', r.msg, 'ok', v_abrir -> 'ok',
                                                         'acao', v_abrir ->> 'acao'));
        end if;
      exception when others then
        perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error',
                                    jsonb_build_object('passo', 3, 'mensagem', r.msg, 'sqlstate', sqlstate));
      end;
    end loop;
  exception when others then
    v_erros := v_erros || 3;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 3, 'sqlstate', sqlstate));
  end;

  -- 4. As respostas humanas dos casos vivos; com conteúdo, o caso fecha e as agendadas dele caem.
  begin
    for r in
      select a.id, a.respondida_em
        from public.retorno_aberturas a
       where a.estado in ('aberta', 'vencida')
         and a.cumprida_em is null
         and a.gravada_em <= v_agora
       order by a.aberta_em, a.id
       for update skip locked
    loop
      v_rh := public._retorno_resposta_humana(r.id, v_agora);
      if v_rh ->> 'respondida_em' is null then
        continue;
      end if;
      v_cump := (v_rh ->> 'cumprida_em')::timestamptz;
      if r.respondida_em is null or v_cump is not null then
        update public.retorno_aberturas a
           set respondida_em = coalesce(a.respondida_em, (v_rh ->> 'respondida_em')::timestamptz),
               cumprida_em = v_cump,
               cumprida_por = case when v_cump is not null then v_rh ->> 'cumprida_por' end,
               estado = case when v_cump is not null then 'fechada' else a.estado end,
               fechada_em = case when v_cump is not null then v_agora else a.fechada_em end,
               fechada_motivo = case when v_cump is not null then 'conteudo' else a.fechada_motivo end,
               atualizada_em = now()
         where a.id = r.id;
        v_n_resp := v_n_resp + 1;
      end if;
      if v_cump is not null then
        v_n_conteudo := v_n_conteudo + 1;
        update public.retorno_saidas s
           set estado = 'cancelada', motivo = 'respondida_pelo_dono', decidida_em = v_agora, atualizada_em = now()
         where s.id in (select x.id from public.retorno_saidas x
                         where x.abertura_id = r.id and x.estado = 'agendada'
                         for update skip locked);
      end if;
    end loop;
  exception when others then
    v_erros := v_erros || 4;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 4, 'sqlstate', sqlstate));
  end;

  -- 5. Fechar: silêncio (sem promessa ouvida), nada parado e o caso que expirou. As agendadas caem.
  begin
    -- silêncio: o dono respondeu sem conteúdo, ninguém prometeu hora, e o número não escreveu mais por 4 h
    with fechar as (
      select a.id from public.retorno_aberturas a
       where a.estado in ('aberta', 'vencida')
         and a.gravada_em <= v_agora
         and a.respondida_em is not null
         and a.cumprida_em is null
         and a.prometido_ate is null
         and a.respondida_em + v_cfg.caso_fecha_silencio <= v_agora
         and a.visita_a_combinar_em is null   -- F3 (P4): a visita a combinar só sai pelo dono (rr-f1-10)
         and not exists (select 1 from public.whatsapp_messages w
                          where public._agenda_chave_telefone(w.phone_normalized) = a.chave
                            and w.direction = 'inbound'
                            and w.occurred_at <= v_agora
                            and w.occurred_at > a.respondida_em - interval '10 minutes'
                            and public._retorno_hora_real(w) > a.respondida_em)
       for update skip locked
    )
    update public.retorno_aberturas a
       set estado = 'fechada', fechada_em = v_agora, fechada_motivo = 'silencio', atualizada_em = now()
      from fechar f
     where a.id = f.id;
    get diagnostics v_n_silencio = row_count;

    -- nada parado: nenhuma mensagem (de nenhum lado) há 4 h; a promessa do dono fica no relógio até vencer
    with fechar as (
      select a.id from public.retorno_aberturas a
       where a.estado in ('aberta', 'vencida')
         and a.gravada_em <= v_agora
         and a.nivel = 'nada'
         and a.motivo is distinct from 'promessa_do_dono'
         and a.visita_a_combinar_em is null   -- F3 (P4)
         and greatest(a.ultima_gravada_em,
                      coalesce((select max(w.occurred_at) from public.whatsapp_messages w
                                 where public._agenda_chave_telefone(w.phone_normalized) = a.chave
                                   and w.direction = 'inbound' and w.occurred_at <= v_agora), a.ultima_gravada_em),
                      coalesce((select max(w.occurred_at) from public.whatsapp_messages w
                                 where public._agenda_chave_telefone(w.phone_normalized) = a.chave
                                   and w.direction = 'outbound' and w.occurred_at <= v_agora), a.ultima_gravada_em))
             + v_cfg.caso_fecha_silencio <= v_agora
       for update skip locked
    )
    update public.retorno_aberturas a
       set estado = 'fechada', fechada_em = v_agora, fechada_motivo = 'nada', atualizada_em = now()
      from fechar f
     where a.id = f.id;
    get diagnostics v_n_nada = row_count;

    -- expirou: expira_dias_uteis completos sem recebida do número, e sem a manhã de topo por vir. Nulo (o padrão,
    -- cartão F1-10 de 08/11/2026) = nunca: o caso fica na lista até o dono resolver
    with fechar as (
      select a.id from public.retorno_aberturas a
       where v_cfg.expira_dias_uteis is not null
         and a.estado in ('aberta', 'vencida')
         and a.visita_a_combinar_em is null   -- F3 (P4)
         and a.gravada_em <= v_agora
         and v_hoje > public.agenda_somar_du((a.ultima_em at time zone c_fuso)::date, v_cfg.expira_dias_uteis)
         and (a.topo_dia is null or a.topo_dia < v_hoje)
         and not exists (select 1 from public.whatsapp_messages w
                          where public._agenda_chave_telefone(w.phone_normalized) = a.chave
                            and w.direction = 'inbound'
                            and w.occurred_at <= v_agora
                            and w.occurred_at > a.ultima_em - interval '10 minutes'
                            and public._retorno_hora_real(w) > a.ultima_em)
       for update skip locked
    )
    update public.retorno_aberturas a
       set estado = 'fechada', fechada_em = v_agora, fechada_motivo = 'expirou', atualizada_em = now()
      from fechar f
     where a.id = f.id;
    get diagnostics v_n_expirou = row_count;

    -- as agendadas dos casos fechados agora caem (a mensagem seguinte abre caso novo)
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_agora, atualizada_em = now()
     where s.id in (select x.id from public.retorno_saidas x
                      join public.retorno_aberturas a on a.id = x.abertura_id
                     where x.estado = 'agendada'
                       and a.estado = 'fechada'
                       and a.fechada_em = v_agora
                       and a.fechada_motivo in ('silencio', 'nada', 'expirou')
                     for update of x skip locked);
  exception when others then
    v_erros := v_erros || 5;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 5, 'sqlstate', sqlstate));
  end;

  -- 6. O relógio dos casos abertos com recibo e promessa, sem conteúdo (E.4).
  begin
    for r in
      select a.id, a.chave, a.phone_normalized, a.client_id, a.modo, a.recibo_em, a.prometido_ate,
             a.adiamento_em, a.segundo_prazo
        from public.retorno_aberturas a
       where a.estado = 'aberta'
         and a.nivel in ('recibo', 'passagem')
         and a.recibo_em is not null
         and a.prometido_ate is not null
         and a.cumprida_em is null
         and a.recibo_em <= v_agora
         and a.prometido_fonte is distinct from 'dono'      -- a promessa do dono não ganha adiamento
       order by a.prometido_ate, a.recibo_em, a.id
    loop
      -- cada caso no seu sub-bloco: o erro de um (um X2 ou uma hora ilegível) vai ao log e os outros seguem
      begin
        v_k_acorde := 0;
        v_k_adiamento := 0;
        v_k_fim := 0;
        v_x := r.prometido_ate;
        v_x2 := public._retorno_x2(v_x);
        v_a := v_x - v_cfg.adiamento_antes;

        -- o acorde do relógio, uma hora antes de X
        if v_agora >= v_x - v_cfg.acorde_antes and v_agora < v_x then
          insert into public.retorno_saidas (abertura_id, tipo, variante, chave, phone_normalized, client_id, modo,
                                             estado, enviar_em, dados, dedupe_key)
          values (r.id, 'acorde', 'relogio', r.chave, r.phone_normalized, r.client_id, r.modo, 'agendada',
                  v_x - v_cfg.acorde_antes, jsonb_build_object('por', 'relogio', 'x', v_x),
                  'retorno:' || r.id || ':acorde:relogio')
          on conflict (dedupe_key) do nothing;
          get diagnostics v_k_acorde = row_count;
        end if;

        -- o adiamento, com X2, em X − 30; os casos do mesmo X em fila, 1 min entre eles, nunca depois de X − 1
        if v_x2 is not null and r.recibo_em <= v_a and v_agora >= v_a and v_agora < v_x
           and not exists (select 1 from public.retorno_saidas s where s.dedupe_key = 'retorno:' || r.id || ':adiamento') then
          select count(*) into v_fila
            from public.retorno_saidas s
            join public.retorno_aberturas b on b.id = s.abertura_id
           where s.tipo = 'adiamento' and b.prometido_ate = v_x;
          v_quando := least(v_a + make_interval(mins => v_fila), v_x - interval '1 minute');
          insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                             estado, enviar_em, dados, dedupe_key)
          values (r.id, 'adiamento', 'retorno_adiamento', 'resposta_atrasada', r.chave, r.phone_normalized, r.client_id,
                  r.modo, 'agendada', v_quando,
                  jsonb_build_object('hora', public._retorno_hora((v_x2 at time zone c_fuso)::time),
                                     'x', v_x, 'x2', v_x2, 'fila', v_fila),
                  'retorno:' || r.id || ':adiamento')
          on conflict (dedupe_key) do nothing;
          get diagnostics v_k_adiamento = row_count;
        end if;

        -- o fim do dia: sem X2, em X − 30 (sem 2ª hora); com X2 e o adiamento decidido, em X2; o recibo decidido
        -- depois de X − 30 vai direto ao fim do dia em X. Só no próprio dia. Desvio (§3): com X2, o adiamento que
        -- não vai ser ouvido (recusado; ainda agendado em X, que o retorno_pegar cancela por caso_vencido; ou que
        -- nem nasceu) também dá o fim do dia em X. Fora: o decidido (o fim do dia é em X2), o que está saindo e o
        -- cancelado porque o dono respondeu, o caso fechou ou a triagem deu nada.
        v_fim := case
          when r.recibo_em > v_a then v_x
          when v_x2 is null then v_a
          when r.adiamento_em is not null and r.segundo_prazo is not null then r.segundo_prazo
          when r.adiamento_em is null and v_agora >= v_x
               and not exists (select 1 from public.retorno_saidas s
                                where s.dedupe_key = 'retorno:' || r.id || ':adiamento'
                                  and (s.estado in ('preparada', 'enviando', 'sombra', 'enviada', 'incerta')
                                       or (s.estado = 'cancelada'
                                           and s.motivo in ('respondida_pelo_dono', 'caso_fechado', 'nivel_nada'))))
            then v_x
        end;
        if v_fim is not null and v_agora >= v_fim
           and (v_agora at time zone c_fuso)::date = (v_fim at time zone c_fuso)::date then
          insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo,
                                             estado, enviar_em, dados, dedupe_key)
          values (r.id, 'fim_do_dia', 'retorno_adiamento', 'resposta_atrasada', r.chave, r.phone_normalized, r.client_id,
                  r.modo, 'agendada', v_fim,
                  jsonb_build_object('x', v_x, 'x2', v_x2, 'dia', (v_fim at time zone c_fuso)::date),
                  'retorno:' || r.id || ':fim_do_dia')
          on conflict (dedupe_key) do nothing;
          get diagnostics v_k_fim = row_count;
        end if;

        -- só conta o que ficou gravado (o sub-bloco que falha desfaz os inserts dele)
        v_n_acorde := v_n_acorde + v_k_acorde;
        v_n_adiamento := v_n_adiamento + v_k_adiamento;
        v_n_fim := v_n_fim + v_k_fim;
      exception when others then
        perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error',
                                    jsonb_build_object('passo', 6, 'caso', r.id, 'sqlstate', sqlstate));
      end;
    end loop;

    -- o caso aberto cujo prazo final passou sem conteúdo vira vencido (inclusive o da promessa do dono); não
    -- enquanto o adiamento dele está saindo (preparada/enviando): recusado depois de X, ele ainda dá o fim do dia
    -- em X no minuto seguinte (o caso vencido sai do relógio)
    update public.retorno_aberturas a
       set estado = 'vencida', atualizada_em = now()
     where a.id in (select b.id from public.retorno_aberturas b
                     where b.estado = 'aberta'
                       and b.gravada_em <= v_agora
                       and b.prometido_ate is not null
                       and b.cumprida_em is null
                       and coalesce(b.segundo_prazo, b.prometido_ate) < v_agora
                       and not exists (select 1 from public.retorno_saidas s
                                        where s.abertura_id = b.id
                                          and s.tipo = 'adiamento'
                                          and s.estado in ('preparada', 'enviando'))
                     for update skip locked);
    get diagnostics v_n_vencida = row_count;
  exception when others then
    v_erros := v_erros || 6;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 6, 'sqlstate', sqlstate));
  end;

  -- 7. O acorde e o cadastro provisório, decididos no SQL. Exceção num item = recusada/erro, e o próximo segue.
  begin
    for r in
      select s.id, s.tipo, s.abertura_id
        from public.retorno_saidas s
       where s.estado = 'agendada'
         and s.tipo in ('acorde', 'cadastro_provisorio')
         and s.enviar_em <= v_agora
         -- F2 (P14): com o acorde real ligado, quem trata é o retorno_vigia_cartao; aqui viraria sombra antes.
         and not (s.tipo = 'acorde' and v_cfg.modo = 'ligado' and 'acorde' = any (v_cfg.tipos_ligados))
       order by s.enviar_em, s.id
       limit 100
       for update skip locked
    loop
      begin
        if not exists (select 1 from public.retorno_aberturas a where a.id = r.abertura_id and a.estado <> 'fechada') then
          update public.retorno_saidas s
             set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_agora, atualizada_em = now()
           where s.id = r.id;
        elsif r.tipo = 'acorde' then
          -- nesta leva o acorde nunca é ligado: é o "eu teria acordado o Gustavo"
          update public.retorno_saidas s
             set estado = 'sombra', modo = 'sombra', decidida_em = v_agora,
                 dados = s.dados || public._retorno_acorde_simulado(v_agora), atualizada_em = now()
           where s.id = r.id;
        else
          v_modo := public._retorno_modo_efetivo(r.id, null, null, v_agora);
          v_cad := public.retorno_cadastro_provisorio(r.abertura_id, v_modo ->> 'modo' = 'ligado');
          if v_cad ->> 'acao' = 'criaria' then
            update public.retorno_saidas s
               set estado = 'sombra', modo = 'sombra', decidida_em = v_agora,
                   dados = s.dados || jsonb_build_object('cadastro', v_cad,
                                                         'sombra_motivo', coalesce(v_modo ->> 'motivo', 'modo')),
                   atualizada_em = now()
             where s.id = r.id;
          elsif v_cad ->> 'acao' = 'criado' then
            update public.retorno_saidas s
               set estado = 'enviada', modo = 'ligado', decidida_em = v_agora, enviada_em = v_agora,
                   dados = s.dados || jsonb_build_object('cadastro', v_cad), atualizada_em = now()
             where s.id = r.id;
          elsif v_cad ->> 'acao' = 'perguntar' then
            update public.retorno_saidas s
               set estado = 'recusada', motivo = 'duplicado_pergunta', decidida_em = v_agora,
                   dados = s.dados || jsonb_build_object('duplicados', v_cad -> 'duplicados'), atualizada_em = now()
             where s.id = r.id;
          else
            update public.retorno_saidas s
               set estado = 'cancelada', motivo = 'sem_nome', decidida_em = v_agora,
                   dados = s.dados || jsonb_build_object('cadastro', v_cad), atualizada_em = now()
             where s.id = r.id;
          end if;
        end if;
        v_n_decididas := v_n_decididas + 1;
      exception when others then
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'erro', decidida_em = v_agora,
               dados = s.dados || jsonb_build_object('erro', jsonb_build_object('sqlstate', sqlstate,
                                                                                 'mensagem', left(sqlerrm, 200))),
               atualizada_em = now()
         where s.id = r.id;
        perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error',
                                    jsonb_build_object('passo', 7, 'saida', r.id, 'sqlstate', sqlstate));
      end;
    end loop;
  exception when others then
    v_erros := v_erros || 7;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 7, 'sqlstate', sqlstate));
  end;

  -- 8. As incertas: só conferir na conversa, por 30 min. Nunca há reenvio.
  begin
    for r in
      select s.id, s.chave, s.texto, s.decidida_em
        from public.retorno_saidas s
       where s.estado = 'incerta'
         and s.emissor = 'retorno'
         and s.texto is not null
         and s.decidida_em >= v_agora - v_cfg.incerta_conferir_ate
         and s.decidida_em <= v_agora - interval '10 minutes'
       for update skip locked
    loop
      begin
        select min(w.occurred_at) into v_eco
          from public.whatsapp_messages w
         where public._agenda_chave_telefone(w.phone_normalized) = r.chave
           and w.direction = 'outbound'
           and w.occurred_at >= r.decidida_em
           and w.occurred_at <= v_agora
           and w.body = r.texto;
        if v_eco is not null then
          update public.retorno_saidas s
             set estado = 'enviada', enviada_em = v_eco,
                 dados = s.dados || jsonb_build_object('conferida_na_conversa', v_agora), atualizada_em = now()
           where s.id = r.id;
          v_n_incertas := v_n_incertas + 1;
        end if;
      exception when others then
        perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error',
                                    jsonb_build_object('passo', 8, 'saida', r.id, 'sqlstate', sqlstate));
      end;
    end loop;
  exception when others then
    v_erros := v_erros || 8;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 8, 'sqlstate', sqlstate));
  end;

  -- 9. Os itens presos, um a um (o erro de um não desfaz os outros):
  --    - preparada (nada saiu): na 1ª vez volta a agendada, atrás das que já venceram; na 2ª, recusada/erro;
  --    - enviando vira incerta (pode ter saído), com os efeitos; o efeito que falha não desfaz a incerta.
  begin
    for r in
      select s.id, s.estado,
             case when coalesce(s.dados ->> 'presas', '') ~ '^[0-9]{1,4}$' then (s.dados ->> 'presas')::integer
                  else 0 end as presas
        from public.retorno_saidas s
       where s.estado in ('preparada', 'enviando') and s.processando_ate < v_agora - interval '5 minutes'
       order by s.processando_ate, s.id
       for update skip locked
    loop
      begin
        if r.estado = 'preparada' and r.presas >= 1 then
          -- a edge falhou duas vezes no mesmo item: nunca volta à frente da fila a cada ~7 min (17/08)
          update public.retorno_saidas s
             set estado = 'recusada', motivo = 'erro', decidida_em = v_agora, processando_ate = null,
                 dados = s.dados || jsonb_build_object('presa', v_agora, 'presas', r.presas + 1), atualizada_em = now()
           where s.id = r.id;
          perform public._retorno_log('vigia', 'retorno_vigia: saída presa de novo na reserva, recusada', 'error',
                                      jsonb_build_object('passo', 9, 'saida', r.id, 'presas', r.presas + 1));
        elsif r.estado = 'preparada' then
          update public.retorno_saidas s
             set estado = 'agendada', processando_ate = null, decidida_em = null,
                 enviar_em = greatest(s.enviar_em, v_agora),
                 dados = s.dados || jsonb_build_object('presa', v_agora, 'presas', r.presas + 1), atualizada_em = now()
           where s.id = r.id;
        else
          update public.retorno_saidas s
             set estado = 'incerta', processando_ate = null,
                 dados = s.dados || jsonb_build_object('presa', v_agora), atualizada_em = now()
           where s.id = r.id;
          begin
            perform public._retorno_aplicar_efeitos(r.id, v_agora);
          exception when others then
            perform public._retorno_log('vigia', 'retorno_vigia: efeitos da saída presa: ' || sqlerrm, 'error',
                                        jsonb_build_object('passo', 9, 'saida', r.id, 'sqlstate', sqlstate));
          end;
        end if;
        v_n_presas := v_n_presas + 1;
      exception when others then
        perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error',
                                    jsonb_build_object('passo', 9, 'saida', r.id, 'sqlstate', sqlstate));
      end;
    end loop;
  exception when others then
    v_erros := v_erros || 9;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 9, 'sqlstate', sqlstate));
  end;

  -- 10. O rebaixamento automático (E.6), com o grupo do P1.1. Só o sinal das últimas 24 h.
  begin
    v_cfg := public._retorno_cfg();
    if cardinality(v_cfg.tipos_ligados) > 0 then
      v_tirar := '{}';
      for e in
        -- opt-out até 48 h depois de uma enviada do tipo à mesma chave
        select s.tipo, s.id as saida, 'opt_out' as motivo
          from public.retorno_saidas s
         where s.emissor = 'retorno'
           and s.estado = 'enviada'
           and s.tipo = any (v_cfg.tipos_ligados)
           and s.tipo not in ('acorde', 'urgente')   -- F2 (P14): um vai ao dono, o outro é pedido do próprio cliente
           and s.enviada_em > v_agora - interval '72 hours'
           and exists (select 1 from public.whatsapp_blocked_numbers b
                        where b.tipo = 'opt_out'
                          and public._agenda_chave_telefone(b.phone_normalized) = s.chave
                          and b.created_at > s.enviada_em
                          and b.created_at <= s.enviada_em + interval '48 hours'
                          and b.created_at <= v_agora
                          and b.created_at > v_agora - interval '24 hours')
        union all
        -- reclamação até 24 h depois
        select s.tipo, s.id, 'reclamacao'
          from public.retorno_saidas s
         where s.emissor = 'retorno'
           and s.estado = 'enviada'
           and s.tipo = any (v_cfg.tipos_ligados)
           and s.tipo not in ('acorde', 'urgente')   -- F2 (P14): reclamar depois de "avisei o Gustavo" é natural
           and s.enviada_em > v_agora - interval '48 hours'
           and exists (select 1 from public.whatsapp_messages w
                        where public._agenda_chave_telefone(w.phone_normalized) = s.chave
                          and w.direction = 'inbound'
                          and w.occurred_at > s.enviada_em
                          and w.occurred_at <= s.enviada_em + interval '24 hours'
                          and w.occurred_at <= v_agora
                          and w.occurred_at > v_agora - interval '24 hours'
                          and coalesce((public._retorno_sinais(w.body) ->> 'reclamacao')::boolean, false))
        union all
        -- 3 ou mais recusas do validador do tipo na última hora
        select s.tipo, (array_agg(s.id order by s.decidida_em desc))[1], 'validador'
          from public.retorno_saidas s
         where s.emissor = 'retorno'
           and s.estado = 'recusada'
           and s.motivo = 'validador'
           and s.tipo = any (v_cfg.tipos_ligados)
           and s.decidida_em > v_agora - interval '1 hour'
           and s.decidida_em <= v_agora
         group by s.tipo
        having count(*) >= 3
      loop
        v_tirar := v_tirar || e.tipo;
        perform public._retorno_log('rebaixamento', 'retorno: tipo rebaixado da lista de ligados', 'warn',
                                    jsonb_build_object('tipo', e.tipo, 'saida', e.saida, 'motivo', e.motivo));
      end loop;
      if cardinality(v_tirar) > 0 then
        -- os que dependem do tipo saem junto: sem adiamento ou fim do dia, nenhum recibo; sem o recibo de
        -- número novo, nem coleta; sem a coleta, nem cadastro
        -- F2 (P14): urgente e acorde são um grupo só (retorno_config_grupo_acorde), e o meio-dia depende deles.
        if v_tirar && array['urgente', 'acorde']::text[] then
          v_tirar := v_tirar || array['urgente', 'acorde']::text[];
        end if;
        if v_tirar && array['adiamento', 'fim_do_dia']::text[] then
          v_tirar := v_tirar || c_recibos;
        end if;
        if 'recibo_numero_novo' = any (v_tirar) then
          v_tirar := v_tirar || 'coleta_numero_novo'::text;
        end if;
        if 'coleta_numero_novo' = any (v_tirar) then
          v_tirar := v_tirar || 'cadastro_provisorio'::text;
        end if;
        v_novos := array(select t from unnest(v_cfg.tipos_ligados) with ordinality as x(t, n)
                          where not (t = any (v_tirar)) order by n);
        if v_novos is distinct from v_cfg.tipos_ligados then
          update public.retorno_config c
             set tipos_ligados = v_novos,
                 meio_dia_ligado = case when 'urgente' = any (v_cfg.tipos_ligados) and not ('urgente' = any (v_novos))
                                        then false else c.meio_dia_ligado end,   -- F2 (P14): um update só, pelos checks
                 atualizado_em = now()
           where c.id;
          v_rebaixados := array(select t from unnest(v_cfg.tipos_ligados) as t where not (t = any (v_novos)));
        end if;
      end if;
    end if;
  exception when others then
    v_erros := v_erros || 10;
    perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 10, 'sqlstate', sqlstate));
  end;

  -- 11–13. Uma vez por dia, no minuto das 04:00 de Brasília.
  if v_diario then
    -- 11. Arquivar o cadastro provisório sem uso (nunca apaga).
    begin
      update public.clients c
         set active = false
       where c.provisorio
         and c.origem = 'retorno'
         and c.active
         and c.created_at < v_agora - v_cfg.cadastro_arquivar_apos
         and not exists (select 1 from public.service_orders o where o.client_id = c.id);
      get diagnostics v_n_arquivados = row_count;
    exception when others then
      v_erros := v_erros || 11;
      perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 11, 'sqlstate', sqlstate));
    end;

    -- 12. A retenção da coleta que não virou cadastro (J.12).
    begin
      update public.retorno_aberturas a
         set coleta = null, atualizada_em = now()
       where a.papel = 'numero_novo'
         and a.coleta is not null
         and a.aberta_em < v_agora - v_cfg.coleta_retencao
         and not exists (select 1 from public.clients c
                          where not c.generico
                            and a.chave in (public._agenda_chave_telefone(c.whatsapp), public._agenda_chave_telefone(c.phone)));
      get diagnostics v_n_k = row_count;
      v_n_retencao := v_n_k;
      update public.whatsapp_leads l
         set coleta = null
       where l.coleta is not null
         and l.status <> 'converted'
         and l.linked_client_id is null
         and l.last_inbound_at < v_agora - v_cfg.coleta_retencao;
      get diagnostics v_n_k = row_count;
      v_n_retencao := v_n_retencao + v_n_k;
    exception when others then
      v_erros := v_erros || 12;
      perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 12, 'sqlstate', sqlstate));
    end;

    -- 13. O alongamento da promessa por faixa (B.4.1), só ligado. Nunca encurta.
    begin
      v_cfg := public._retorno_cfg();
      if v_cfg.modo = 'ligado' then
        for r in
          select a.faixa, count(*)::integer as casos,
                 count(*) filter (where a.cumprida_em is not null and a.cumprida_em <= a.prometido_ate)::integer as no_prazo
            from public.retorno_aberturas a
           where a.faixa = any (c_faixas)
             and a.prometido_ate is not null
             and a.prometido_ate <= v_agora
             and exists (select 1 from public.retorno_saidas s
                          where s.abertura_id = a.id
                            and s.tipo = any (c_recibos)
                            and s.estado = 'enviada'
                            and s.enviada_em > v_agora - v_cfg.alongar_janela
                            and s.enviada_em <= v_agora
                            and s.enviada_em > coalesce((select max(l.em) from public.retorno_alongamentos l
                                                          where l.faixa = a.faixa and l.em <= v_agora),
                                                         '-infinity'::timestamptz))
           group by a.faixa
           order by a.faixa
        loop
          if r.casos < v_cfg.alongar_minimo_casos or r.no_prazo::numeric / r.casos >= v_cfg.alongar_meta then
            continue;
          end if;
          -- a promessa atual da faixa: a calibrada, se legível; senão a da tabela do P3
          v_atual := v_cfg.promessa_faixa -> r.faixa;
          if jsonb_typeof(v_atual) is distinct from 'object'
             or coalesce(v_atual -> 'dias' not in ('0'::jsonb, '1'::jsonb), true)
             or coalesce(v_atual ->> 'hora', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
            v_atual := jsonb_build_object('dias', 0, 'hora', to_char(case
              when r.faixa = 'manha_cedo' and v_cfg.meio_dia_ligado then v_cfg.promessa_meio_dia
              when r.faixa in ('manha_cedo', 'meio', 'pressa') then v_cfg.promessa_fechamento
              else v_cfg.promessa_manha end, 'HH24:MI'));
          end if;
          v_hora_atual := (v_atual ->> 'hora')::time;
          v_dias_atual := (v_atual ->> 'dias')::integer;
          -- o próximo momento: 14h → 19h do mesmo dia; 19h → 10h do próximo dia útil; 10h → 19h do mesmo dia
          v_prox := case
            when v_hora_atual = v_cfg.promessa_meio_dia or v_hora_atual = v_cfg.promessa_manha
              then jsonb_build_object('dias', v_dias_atual, 'hora', to_char(v_cfg.promessa_fechamento, 'HH24:MI'))
            when v_hora_atual = v_cfg.promessa_fechamento and v_dias_atual = 0
              then jsonb_build_object('dias', 1, 'hora', to_char(v_cfg.promessa_manha, 'HH24:MI'))
          end;
          if v_prox is null then
            continue;      -- já no último momento que a calibração aceita
          end if;
          update public.retorno_config c
             set promessa_faixa = c.promessa_faixa || jsonb_build_object(r.faixa, v_prox), atualizado_em = now()
           where c.id
           returning * into v_cfg;
          insert into public.retorno_alongamentos (faixa, de, para, casos, pct, em)
          values (r.faixa, v_atual, v_prox, least(r.casos, 32767), round(r.no_prazo::numeric / r.casos, 4), v_agora);
          v_alongadas := v_alongadas || r.faixa;
          perform public._retorno_log('alongamento', 'retorno: promessa da faixa alongada', 'warn',
                                      jsonb_build_object('faixa', r.faixa, 'de', v_atual, 'para', v_prox,
                                                         'casos', r.casos, 'no_prazo', r.no_prazo));
        end loop;
      end if;
    exception when others then
      v_erros := v_erros || 13;
      perform public._retorno_log('vigia', 'retorno_vigia: ' || sqlerrm, 'error', jsonb_build_object('passo', 13, 'sqlstate', sqlstate));
    end;
  end if;

  -- 14. As contagens.
  return jsonb_build_object(
    'ok', cardinality(v_erros) = 0,
    'rodou', true,
    'erros', to_jsonb(v_erros),
    'disjuntor', v_disjuntor,
    'audios', v_n_audio,
    'respondidas', v_n_resp,
    'fechadas', jsonb_build_object('conteudo', v_n_conteudo, 'silencio', v_n_silencio, 'nada', v_n_nada,
                                   'expirou', v_n_expirou),
    'relogio', jsonb_build_object('acordes', v_n_acorde, 'adiamentos', v_n_adiamento, 'fins_do_dia', v_n_fim,
                                  'vencidas', v_n_vencida),
    'decididas', v_n_decididas,
    'incertas_conferidas', v_n_incertas,
    'presas', v_n_presas,
    'rebaixados', to_jsonb(v_rebaixados),
    'diario', v_diario,
    'arquivados', v_n_arquivados,
    'retencao', v_n_retencao,
    'alongadas', to_jsonb(v_alongadas));
end;
$$;

create or replace function public._cliente_ja_apresentada(p_client_id uuid, p_chave text, p_hoje date)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with j as (
    select (p_hoje::timestamp at time zone 'America/Sao_Paulo')
             - coalesce((public._retorno_cfg()).apresentacao_intervalo, interval '365 days') as desde,
           ((p_hoje + 1)::timestamp at time zone 'America/Sao_Paulo') as ate
  )
  select exists (select 1 from public.agenda_cliente_mensagens m, j
                  where p_client_id is not null
                    and m.client_id = p_client_id
                    and m.enviada_em > j.desde and m.enviada_em < j.ate)
      or exists (select 1 from public.retorno_saidas s, j
                  where s.emissor = 'retorno'
                    and s.estado = 'enviada'
                    and s.tipo not in ('acorde', 'cadastro_provisorio', 'fila')
                    and (s.client_id = p_client_id or s.chave = p_chave)
                    and s.enviada_em > j.desde and s.enviada_em < j.ate)
      -- F3 (P4): a legenda com apresentação conta como apresentação; o PDF não passa por retorno_saidas nem por agenda_cliente_mensagens.
      or exists (select 1 from public.retorno_previa p, j
                  where p.pdf_em > j.desde and p.pdf_em < j.ate
                    and (p.client_id = p_client_id or p.chave = p_chave));
$$;
