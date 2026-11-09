-- Retorno rápido ao cliente, F2 (P10): as saídas dos modelos, com as funções da F1 e só os trechos marcados "-- F2:".
--
-- Os corpos abaixo são os da F1 (20261116100500 e 20261116100700), mais os trechos -- F2:. Nada mais muda.
--
-- O que entra:
-- - o modelo aprovado sai como o dono viu, sem recompor; o sozinho confere o fato de novo;
-- - o recibo fica de reserva: com o modelo promovido, o recibo espera, e só cai quando o modelo sai. Modelo recusado, o recibo sai,
--   e o cliente nunca fica sem palavra;
-- - *segura tudo* não queima a saída: ela espera, e na volta quem escreveu há mais de 12 h fica com o dono;
-- - as variantes T29 a T35 só com variantes_ligadas: com a chave desligada, o texto ao cliente é o da F1;
-- - o modelo enviado cumpre e fecha o caso; a aprovação do tipo conta só na saída enviada, porque o que o validador recusou não
--   ensina nada.
--
-- Com cartao_ligado, variantes_ligadas e os tipos desligados, nada muda ao cliente. A bancada confere isso com o replay.
--
-- Reverter: voltar as 5 funções da F1 com os corpos das migrations de origem. Sem deploy: tipos em 'desligado' e variantes_ligadas = false.

create or replace function public._retorno_tipo_sozinho(p_tipo text, p_agora timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select t.nivel = 'sozinho' and (t.promocao_suspensa_ate is null or t.promocao_suspensa_ate <= p_agora)
                     from public.retorno_modelo_tipos t where t.tipo = p_tipo), false);
$$;

comment on function public._retorno_tipo_sozinho(text, timestamptz) is
  'Retorno F2 (P10.2): o tipo está em sozinho e a promoção não está suspensa.';

revoke all on function public._retorno_tipo_sozinho(text, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_agendar_modelo(p_abertura uuid, p_modelo jsonb, p_agora timestamptz)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ab public.retorno_aberturas;
  v_id uuid;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  insert into public.retorno_saidas (abertura_id, tipo, origem, classe, chave, phone_normalized, client_id, modo, estado, enviar_em, dados, dedupe_key)
  values (v_ab.id, p_modelo ->> 'modelo', 'retorno_modelo', 'resposta_imediata', v_ab.chave, v_ab.phone_normalized, v_ab.client_id, v_ab.modo,
          'agendada', p_agora,
          jsonb_build_object('os_id', p_modelo ->> 'os_id', 'fato', p_modelo -> 'fato', 'intencao', p_modelo ->> 'intencao', 'sozinho', true),
          'retorno:' || v_ab.id || ':modelo:sozinho')
  on conflict (dedupe_key) do nothing
  returning id into v_id;
  return v_id;
end;
$$;

comment on function public._retorno_agendar_modelo(uuid, jsonb, timestamptz) is
  'Retorno F2 (P10.2): cria a saída do modelo promovido, agendada para agora. Uma por caso, pela dedupe_key.';

revoke all on function public._retorno_agendar_modelo(uuid, jsonb, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_variante_f2(p_abertura uuid, p_agora timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_int text;
begin
  if public._retorno_tem_orcamento(p_abertura, p_agora) then
    return 'orcamento';
  end if;
  v_int := public._retorno_intencao_do_caso(p_abertura, p_agora);
  return case v_int when 'retirada' then 'retirada' when 'adicional' then 'adicional' when 'quando_pronto' then 'vou_confirmar' end;
end;
$$;

comment on function public._retorno_variante_f2(uuid, timestamptz) is
  'Retorno F2 (P10.1): a variante de recibo pela intenção do caso: orcamento, retirada, adicional, vou_confirmar ou null, nessa ordem.';

revoke all on function public._retorno_variante_f2(uuid, timestamptz) from public, anon, authenticated;

-- A letra do "Mandei sozinho" é gravada no envio, não calculada: depois do fechamento, uma conta refeita não acharia a mesma saída.
create or replace function public._retorno_gravar_letra(p_saida uuid, p_em timestamptz, p_envios integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_letras constant text[] := array['Z', 'Y', 'X', 'W', 'V'];
  v_cfg public.retorno_config := public._retorno_cfg();
  v_dia date := (p_em at time zone c_fuso)::date;
  v_i integer;
  v_letra text;
begin
  if (p_em at time zone c_fuso)::time >= v_cfg.ponto_fechamento then
    v_dia := v_dia + 1;
  end if;
  for v_i in 1 .. 10 loop
    exit when public._retorno_dia_de_tarde(v_dia);
    v_dia := v_dia + 1;
  end loop;
  select l into v_letra
    from unnest(c_letras) with ordinality as x(l, ord)
   where not exists (select 1 from public.retorno_saidas s where s.letra_dia = v_dia and s.letra = x.l)
   order by x.ord
   limit 1;
  update public.retorno_saidas s
     set letra = v_letra, letra_dia = case when v_letra is not null then v_dia end,
         dados = s.dados || case when p_envios % v_cfg.auditoria_cada = 1 then '{"auditoria": true}'::jsonb else '{}'::jsonb end,
         atualizada_em = now()
   where s.id = p_saida;
end;
$$;

comment on function public._retorno_gravar_letra(uuid, timestamptz, integer) is
  'Retorno F2 (P13.4): grava a letra do "Mandei sozinho" no envio, no próximo dia de tarde. Passou da 5ª, fica sem letra. Marca a amostra de auditoria.';

revoke all on function public._retorno_gravar_letra(uuid, timestamptz, integer) from public, anon, authenticated;

create or replace function public._retorno_contar_aprovacao(p_tipo text, p_agora timestamptz)
returns void
language sql
security definer
set search_path = public
as $$
  update public.retorno_modelo_tipos t
     set aprovados_dias = case when ((p_agora at time zone 'America/Sao_Paulo')::date) = any (t.aprovados_dias) then t.aprovados_dias
                               else t.aprovados_dias || ((p_agora at time zone 'America/Sao_Paulo')::date) end,
         aprovados_usos = t.aprovados_usos + 1,
         atualizado_em = now()
   where t.tipo = p_tipo;
$$;

comment on function public._retorno_contar_aprovacao(text, timestamptz) is
  'Retorno F2 (P13.2): soma a aprovação do tipo: o dia entra uma vez, o uso sempre. Só com a saída enviada.';

revoke all on function public._retorno_contar_aprovacao(text, timestamptz) from public, anon, authenticated;

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
  if coalesce((v_s.dados ->> 'aprovada')::boolean, false) and v_s.tipo <> 'modelo_retirada_nao'
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

revoke all on function public._retorno_checar_antes(uuid, timestamptz) from public, anon, authenticated;

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

revoke all on function public._retorno_aplicar_efeitos(uuid, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_contexto_do_validador(p_saida uuid, p_texto text, p_dados jsonb,
                                                                  p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_sep constant text := chr(31);
  v_s public.retorno_saidas;
  v_ab public.retorno_aberturas;
  d jsonb := case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end;
  v_texto text := coalesce(p_texto, '');
  v_corte text;
  v_valor text;
  v_datas text[];
  v_horas text[];
  v_trechos text[];
  v_outros text[] := '{}';
  v_cliente jsonb;
  v_fala text := public._retorno_quando_fala(d ->> 'quando', d ->> 'hora');   -- VOZ-2: é valor do banco, como {quando}
begin
  select * into v_s from public.retorno_saidas s where s.id = p_saida;
  select * into v_ab from public.retorno_aberturas a where a.id = v_s.abertura_id;

  -- As datas e dias que o banco pôs, a dd/mm de dentro deles, e "hoje", "amanhã" e "ontem" quando estão no
  -- texto (o texto é modelo fixo + valores do banco: o T22 tem "hoje" no modelo; "de ontem à noite" é valor).
  v_datas := array(
    select distinct x from (
      select unnest(array[d ->> 'quando', d ->> 'quando_lista', d ->> 'dia_msg', v_fala, d ->> 'dia_peca']) as x   -- F2: dia_peca
      union all
      select (regexp_match(y, '[0-9]{2}/[0-9]{2}'))[1]
        from unnest(array[d ->> 'quando', d ->> 'quando_lista', d ->> 'dia_msg']) as y
      union all
      select w from unnest(array['hoje', 'amanhã', 'ontem']) as w where strpos(v_texto, w) > 0
    ) z where x is not null and x <> '' order by x);
  v_horas := array(select distinct x from unnest(array[d ->> 'hora', d ->> 'hora_msg']) as x
                    where x is not null and x <> '' order by x);

  -- Os trechos do modelo: o texto cortado nos valores dos {campos} (o maior valor primeiro). Valor que
  -- coincide com o texto fixo só encolhe a lista (bloqueia mais).
  v_corte := v_texto;
  for v_valor in
    select x from unnest(array[d ->> 'nome', d ->> 'quando', d ->> 'hora', d ->> 'quando_lista', d ->> 'cumprimento',
                               d ->> 'de_quando', d ->> 'dia_msg', d ->> 'hora_msg', d ->> 'do_bem', v_fala,
                               d ->> 'dia_peca']) as x   -- F2: dia_peca. {no_bem} fica de fora de propósito: é do modelo, e cortá-lo viraria eco
     where x is not null and btrim(x) <> ''
     order by char_length(x) desc, x
  loop
    v_corte := replace(v_corte, v_valor, c_sep);
  end loop;
  v_trechos := array(select p from unnest(string_to_array(v_corte, c_sep)) as p where btrim(p) <> '');

  -- No ambíguo, os nomes curtos dos clientes do número (nenhum pode aparecer no texto).
  if v_ab.papel = 'cliente_ambiguo' then
    v_outros := array(select distinct public._agenda_nome_curto(coalesce(nullif(btrim(c.display_name), ''), c.name))
                        from public.clients c
                       where c.id = any (v_ab.clientes));
    v_outros := array(select x from unnest(v_outros) as x where x is not null and btrim(x) <> '' order by x);
  end if;

  -- Os corpos das recebidas do caso, gravadas até agora (só para o eco; nunca entram no texto).
  select coalesce(jsonb_agg(w.body order by rm.recebida_em, rm.whatsapp_message_id), '[]'::jsonb) into v_cliente
    from public.retorno_mensagens rm
    join public.whatsapp_messages w on w.id = rm.whatsapp_message_id
   where rm.abertura_id = v_ab.id
     and w.occurred_at <= coalesce(p_agora, now())
     and w.body is not null;

  return jsonb_build_object(
    'audiencia', 'cliente',
    'datas_permitidas', to_jsonb(coalesce(v_datas, '{}'::text[])),
    'horas_permitidas', to_jsonb(coalesce(v_horas, '{}'::text[])),
    'nome_permitido', nullif(btrim(d ->> 'nome'), ''),
    'nomes_de_outros', to_jsonb(coalesce(v_outros, '{}'::text[])),
    'os_permitidas', '[]'::jsonb,                     -- nenhum texto da F1 cita OS
    'textos_do_cliente', coalesce(v_cliente, '[]'::jsonb),
    'trechos_do_modelo', to_jsonb(coalesce(v_trechos, '{}'::text[])),
    -- F2: tem_proposta vem do banco
    'marcas', jsonb_build_object('tem_proposta', public._retorno_tem_orcamento(v_ab.id, coalesce(p_agora, now())), 'tem_topo', v_ab.topo_dia is not null,
                                 'cliente_ouviu', false, 'conferida', false));
end;
$$;

revoke all on function public._retorno_contexto_do_validador(uuid, text, jsonb, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_modo_efetivo(p_saida uuid, p_variante text, p_prazo jsonb, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  v_cfg public.retorno_config := public._retorno_cfg();
  v_agora timestamptz := coalesce(p_agora, now());
  v_tipo text;
  v_caso uuid;
  v_nivel text;
begin
  -- 1. O modo geral (sem a linha de configuração = desligado: sombra).
  if v_cfg.id is null or v_cfg.modo is distinct from 'ligado' then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'modo');
  end if;

  select s.tipo, s.abertura_id into v_tipo, v_caso from public.retorno_saidas s where s.id = p_saida;
  if not found then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'sem_saida');
  end if;

  -- 2. "Segura tudo" até uma hora que ainda não chegou.
  if v_cfg.segura_tudo_ate is not null and v_cfg.segura_tudo_ate > v_agora then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'segura_tudo');
  end if;

  -- F2: modelo com fato. Aprovado no cartão, liga. Sozinho, só com o tipo promovido. segura_tudo já barrou acima.
  if v_tipo like 'modelo\_%' escape '\' then
    if coalesce((select (s.dados ->> 'aprovada')::boolean from public.retorno_saidas s where s.id = p_saida), false)
       or public._retorno_tipo_sozinho(v_tipo, v_agora) then
      return jsonb_build_object('modo', 'ligado', 'motivo', null);
    end if;
    return jsonb_build_object('modo', 'sombra', 'motivo', 'modelo_nao_promovido');
  end if;

  -- 3. O tipo ligado (urgente, acorde e fila nunca estão na lista).
  if not coalesce(v_tipo = any (v_cfg.tipos_ligados), false) then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'tipo_desligado');
  end if;

  -- O parar só passa pelas regras 1–3: não depende de recibo.
  if v_tipo = 'parar' then
    return jsonb_build_object('modo', 'ligado', 'motivo', null);
  end if;

  -- 4. O modelo oferece URGENTE, e o URGENTE não liga. Sem a variante, o recibo e o adiamento podem ser os
  --    que oferecem: na dúvida, sombra.
  if (public._retorno_oferece_urgente(v_tipo, p_variante)
      or (p_variante is null and v_tipo in ('recibo_cliente', 'adiamento')))
     and not ('urgente' = any (v_cfg.tipos_ligados)) then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'urgente_desligado');
  end if;

  -- 5. "Segura recibos": recibo, saudação e coleta.
  if v_cfg.segura_recibos and (v_tipo = any (c_recibos) or v_tipo in ('saudacao_numero_novo', 'coleta_numero_novo')) then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'segura_recibos');
  end if;

  -- 6. A passagem só liga com o acorde real. Escapa só o aviso honesto (adiamento, fim do dia) de uma
  --    promessa que o cliente já ouviu: o recibo do caso enviado ou incerto, decidido até agora. O caso pode
  --    ter virado passagem depois do recibo (insistência, reclamação), e calar às 19h seria pior.
  select a.nivel into v_nivel from public.retorno_aberturas a where a.id = v_caso;
  if not found then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'sem_caso');
  end if;
  if v_nivel = 'passagem' and not ('acorde' = any (v_cfg.tipos_ligados))
     and not (v_tipo in ('adiamento', 'fim_do_dia')
              and exists (select 1 from public.retorno_saidas r
                           where r.abertura_id = v_caso
                             and r.emissor = 'retorno'
                             and r.tipo = any (c_recibos)
                             and r.estado in ('enviada', 'incerta')
                             and r.decidida_em <= v_agora)) then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'passagem_sem_acorde');
  end if;

  -- 7. O recibo só liga se o resto do caso também puder ligar: o adiamento que viria (com X2) e o fim do dia.
  if v_tipo = any (c_recibos) then
    if p_prazo is null or jsonb_typeof(p_prazo) is distinct from 'object' or not (p_prazo ? 'x2')
       or not (v_cfg.tipos_ligados @> array['adiamento', 'fim_do_dia']::text[])
       or (p_prazo ->> 'x2' is not null
           and (public._retorno_oferece_urgente('adiamento', 'com_nome') or public._retorno_oferece_urgente('adiamento', 'sem_nome'))
           and not ('urgente' = any (v_cfg.tipos_ligados))) then
      return jsonb_build_object('modo', 'sombra', 'motivo', 'caso_sem_aviso');
    end if;
  end if;

  -- 8. O aviso só liga se o cliente ouviu (ou pode ter ouvido) o recibo ou a saudação deste caso.
  if v_tipo in ('adiamento', 'fim_do_dia', 'coleta_numero_novo', 'urgente', 'cadastro_provisorio')
     and not exists (select 1 from public.retorno_saidas r
                      where r.abertura_id = v_caso
                        and r.emissor = 'retorno'
                        and (r.tipo = any (c_recibos) or r.tipo = 'saudacao_numero_novo')
                        and r.estado in ('enviada', 'incerta')
                        and r.decidida_em <= v_agora) then
    return jsonb_build_object('modo', 'sombra', 'motivo', 'caso_em_sombra');
  end if;

  -- 9.
  return jsonb_build_object('modo', 'ligado', 'motivo', null);
end;
$$;

revoke all on function public._retorno_modo_efetivo(uuid, text, jsonb, timestamptz) from public, anon, authenticated;

create or replace function public.retorno_pegar(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_recibos constant text[] := array['recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo'];
  c_contam constant text[] := array['sombra', 'preparada', 'enviando', 'enviada', 'incerta'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_cfg public.retorno_config;
  v_volta integer;
  v_s public.retorno_saidas;
  v_ab public.retorno_aberturas;
  v_ch jsonb;
  v_pz jsonb;
  v_pd jsonb;
  v_desde timestamptz;
  v_dados jsonb;
  v_campos jsonb;
  v_nome text;
  v_var text;
  v_texto text;
  v_modo jsonb;
  v_ligado boolean;
  v_canal jsonb;
  v_pretendido boolean;
  v_ouviu boolean;
  v_volta_atraso boolean;
  v_topo date;
  v_do_bem text;
  v_apos_saudacao boolean;
  v_ctx jsonb;
  v_m jsonb;           -- F2
  v_f2 boolean;        -- F2
  v_alt text;          -- F2
begin
  v_cfg := public._retorno_cfg();
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return null;
  end if;

  for v_volta in 1 .. 10 loop
    -- 1. Uma saída devida, fora de reserva, que só a edge decide. Duas execuções nunca pegam a mesma.
    select * into v_s
      from public.retorno_saidas s
     where s.estado = 'agendada'
       and s.enviar_em <= v_agora
       and (s.processando_ate is null or s.processando_ate < v_agora)
       and s.tipo not in ('acorde', 'cadastro_provisorio', 'fila')
     order by s.enviar_em, s.id
     limit 1
     for update skip locked;
    if not found then
      return null;
    end if;

    begin
      -- 2. Conferir de novo, agora.
      v_ch := public._retorno_checar_antes(v_s.id, v_agora);
      if v_ch ->> 'acao' = 'cancelar' then
        update public.retorno_saidas s
           set estado = 'cancelada', motivo = v_ch ->> 'motivo', decidida_em = v_agora, processando_ate = null,
               atualizada_em = now()
         where s.id = v_s.id and s.estado = 'agendada';
        if v_ch ->> 'motivo' = 'respondida_pelo_dono' then
          update public.retorno_aberturas a
             set respondida_em = coalesce(a.respondida_em, (v_ch -> 'resposta' ->> 'respondida_em')::timestamptz),
                 atualizada_em = now()
           where a.id = v_s.abertura_id;
        end if;
        continue;
      elsif v_ch ->> 'acao' = 'adiar' then
        update public.retorno_saidas s
           set enviar_em = (v_ch ->> 'enviar_em')::timestamptz,
               dados = s.dados || jsonb_build_object('adiada', jsonb_build_object('motivo', v_ch ->> 'motivo', 'em', v_agora)),
               atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;

      -- A triagem pode ter mexido na saída (o risco que apareceu) e no caso: lê de novo.
      select * into v_s from public.retorno_saidas s where s.id = v_s.id;
      select * into v_ab from public.retorno_aberturas a where a.id = v_s.abertura_id;

      -- 3. Compor.
      v_dados := v_s.dados;
      v_nome := case when v_ab.papel = 'cliente' then public._retorno_nome(v_ab.client_id) end;
      v_pretendido := v_cfg.modo = 'ligado' and v_s.tipo = any (v_cfg.tipos_ligados);
      v_pz := null;
      v_campos := '{}'::jsonb;
      v_topo := null;
      v_m := null;       -- F2
      v_f2 := false;     -- F2

      if v_s.tipo = any (c_recibos) or v_s.tipo = 'saudacao_numero_novo' then
        -- O prazo é do banco, gravado na 1ª composição (a mensagem da noite guarda a promessa da faixa noite).
        -- O guardado que já venceu é calculado de novo: nunca promete hora passada.
        if jsonb_typeof(v_dados -> 'prazo') = 'object' then
          v_pz := v_dados -> 'prazo';
          if (v_pz ->> 'prometido_ate')::timestamptz <= v_agora then
            v_pz := null;
          end if;
        end if;
        if v_pz is null then
          v_pz := public._retorno_prazo(greatest(v_ab.aberta_em, v_agora), v_ab.chave,
                                        coalesce((v_ab.sinais ->> 'pressa')::boolean, false), false);
        end if;
        v_dados := v_dados || jsonb_build_object('prazo', v_pz);
        -- Fora da janela K3: o recibo espera a manhã (com o prazo guardado).
        if (v_pz ->> 'recibo_em')::timestamptz > v_agora then
          update public.retorno_saidas s
             set enviar_em = (v_pz ->> 'recibo_em')::timestamptz, dados = v_dados, atualizada_em = now()
           where s.id = v_s.id;
          continue;
        end if;
        -- O recibo sai agora: "hoje", "amanhã" e o outro dia são vistos de HOJE, não do dia em que o prazo foi
        -- guardado (o composto às 21:59, "amanhã até as 10h", que o canal levou à manhã seguinte diz "hoje até
        -- as 10h"). A promessa (dia, hora, prometido_ate) não muda. No prazo recém-calculado nada muda: ref já
        -- é hoje.
        v_pz := v_pz || jsonb_build_object('ref', v_hoje,
                                           'quando', public._retorno_quando((v_pz ->> 'dia')::date, v_hoje),
                                           'outro_dia', (v_pz ->> 'dia')::date > v_hoje);
        v_dados := v_dados || jsonb_build_object('prazo', v_pz);
        v_volta_atraso := v_ab.atraso_gravacao >= v_cfg.volta_min and v_ab.atraso_gravacao <= v_cfg.volta_max;
        if v_s.tipo = 'saudacao_numero_novo' then
          -- a saudação (T19) não promete hora: só o cumprimento entra nos dados (e no contexto do validador)
          v_campos := jsonb_build_object('cumprimento', public._retorno_cumprimento(v_agora), 'volta', v_volta_atraso);
        else
          v_campos := jsonb_build_object('cumprimento', public._retorno_cumprimento(v_agora),
                                         'quando', v_pz ->> 'quando', 'hora', v_pz ->> 'hora',
                                         'volta', v_volta_atraso,
                                         'risco', coalesce((v_dados ->> 'risco')::boolean, false));
        end if;
      end if;

      if v_s.tipo = 'recibo_cliente' then
        if v_pz ->> 'fonte' = 'fora_ate' then
          v_var := 'fora_ate';
        elsif v_pz ->> 'faixa' = 'noite' then
          v_var := case when v_pz ->> 'quando' = 'hoje' then 'manha' else 'manha_outro_dia' end;
          -- {de_quando}: a 1ª mensagem entre 00:00 e 06:59 do mesmo dia do recibo é "desta madrugada"
          v_campos := v_campos || jsonb_build_object('de_quando',
            case when (v_ab.aberta_em at time zone c_fuso)::date = v_hoje
                      and (v_ab.aberta_em at time zone c_fuso)::time < time '07:00'
                 then 'desta madrugada' else 'de ontem à noite' end);
        elsif v_volta_atraso then
          -- a queda avisada pelo vigia da conexão entre 30 min antes da mensagem e a gravação dela (R1-03)
          v_var := case when exists (select 1 from public.app_notifications n
                                      where n.type = 'whatsapp_caiu'
                                        and n.created_at >= v_ab.aberta_em - interval '30 minutes'
                                        and n.created_at <= v_ab.gravada_em
                                        and n.created_at <= v_agora)
                        then 'volta_queda' else 'volta' end;
          v_campos := v_campos || jsonb_build_object(
            'dia_msg', public._agenda_cliente_dia((v_ab.aberta_em at time zone c_fuso)::date),
            'hora_msg', to_char(v_ab.aberta_em at time zone c_fuso, 'HH24:MI'));
        elsif coalesce((v_pz ->> 'outro_dia')::boolean, false) then
          v_var := 'outro_dia';
        else
          v_var := 'padrao';
        end if;
        if v_nome is null then
          v_var := case v_var when 'outro_dia' then 'outro_dia_sem_nome'
                              when 'manha' then 'manha_sem_nome'
                              when 'manha_outro_dia' then 'manha_sem_nome'
                              when 'fora_ate' then 'fora_ate_sem_nome'
                              else 'sem_nome' end;
        elsif v_var in ('padrao', 'outro_dia', 'manha', 'manha_outro_dia', 'fora_ate', 'volta', 'volta_queda') then
          -- VOZ-1 e VOZ-6: a Claudia se apresenta só se ninguém (retorno ou agenda) falou com este cliente.
          -- Em sombra, a sombra do retorno também conta, para a simulação sair como sairia ligada.
          v_ouviu := public._cliente_ja_apresentada(v_ab.client_id, v_s.chave, v_hoje)
                     or (not v_pretendido
                         and exists (select 1 from public.retorno_saidas o
                                      where o.chave = v_s.chave
                                        and o.id <> v_s.id
                                        and o.emissor = 'retorno'
                                        and o.tipo not in ('acorde', 'cadastro_provisorio', 'fila')
                                        and o.decidida_em > v_agora - v_cfg.apresentacao_intervalo
                                        and o.decidida_em <= v_agora
                                        and o.estado = 'sombra'));
          if not v_ouviu then
            v_var := v_var || '_apresentacao';
          end if;
        end if;

      elsif v_s.tipo = 'recibo_ambiguo' then
        v_var := 'padrao';

      elsif v_s.tipo = 'recibo_numero_novo' then
        v_apos_saudacao := coalesce((v_dados ->> 'apos_saudacao')::boolean, false)
                           or exists (select 1 from public.retorno_saidas o
                                       where o.abertura_id = v_s.abertura_id
                                         and o.tipo = 'saudacao_numero_novo'
                                         and o.estado in ('sombra', 'enviada', 'incerta')
                                         and o.decidida_em <= v_agora);
        if v_apos_saudacao then
          v_var := 'sem_pergunta';     -- no máximo 2 mensagens automáticas no 1º contato (R1-23)
        else
          -- O pedido das 24 h do número (a mesma janela da triagem): a necessidade dita e o bem.
          select min(public._retorno_hora_real(w)) into v_desde
            from public.whatsapp_messages w
           where public._agenda_chave_telefone(w.phone_normalized) = v_s.chave
             and w.direction = 'inbound'
             and w.occurred_at <= v_agora
             and w.occurred_at >= v_agora - interval '24 hours'
             and public._retorno_hora_real(w) >= v_agora - interval '24 hours';
          v_pd := case when v_desde is not null
                       then public._retorno_pedido_de_servico(v_s.chave, v_desde, v_agora, null) end;
          v_do_bem := public._retorno_do_bem(coalesce(v_pd ->> 'bem_palavra', v_ab.sinais ->> 'bem_palavra'));
          if coalesce((v_pd ->> 'servico_generico')::boolean, false) then
            v_var := 'pergunta_necessidade';
          elsif coalesce(v_pd ->> 'ano', v_ab.sinais ->> 'ano') is null and v_do_bem is not null then
            v_var := 'pergunta_modelo';
            v_campos := v_campos || jsonb_build_object('do_bem', v_do_bem);
          else
            v_var := 'sem_pergunta';   -- sem a palavra do bem não há como perguntar o modelo
          end if;
        end if;

      elsif v_s.tipo = 'saudacao_numero_novo' then
        v_var := 'padrao';

      elsif v_s.tipo = 'coleta_numero_novo' then
        v_var := 'nome';

      elsif v_s.tipo = 'adiamento' then
        v_var := case when v_nome is null then 'sem_nome' else 'com_nome' end;
        v_campos := jsonb_build_object('hora', v_dados ->> 'hora');

      elsif v_s.tipo in ('fim_do_dia', 'urgente') then
        -- A marca de topo vem antes do texto: é o que torna verdadeiro "o primeiro da lista dele … cedo".
        v_topo := public.agenda_somar_du(v_hoje + 1, 0);
        update public.retorno_aberturas a
           set topo_dia = case when a.topo_dia is null or a.topo_dia < v_hoje then v_topo
                               else least(a.topo_dia, v_topo) end,
               atualizada_em = now()
         where a.id = v_s.abertura_id
         returning * into v_ab;
        v_campos := jsonb_build_object('quando_lista', public._retorno_quando(v_topo, v_hoje));
        if v_s.tipo = 'fim_do_dia' then
          v_var := case when v_nome is null then 'sem_nome' else 'com_nome' end;
        else
          v_var := case when v_nome is null then 'sem_acorde_sem_nome' else 'sem_acorde' end;
        end if;

      elsif v_s.tipo = 'parar' then
        v_var := case when v_nome is null then 'sem_nome' else 'com_nome' end;

      -- F2: modelo com fato. O aprovado sai como o dono viu, sem recompor (a trava por hash). O sozinho confere o fato de novo.
      elsif v_s.tipo like 'modelo\_%' escape '\' then
        if v_dados ? 'texto_aprovado' then
          v_var := 'aprovado';
        else
          v_m := public._retorno_modelo_do_caso(v_ab.id, v_agora);
          if v_m ->> 'modelo' is distinct from v_s.tipo then
            update public.retorno_saidas s
               set estado = 'recusada', motivo = 'fato_mudou', decidida_em = v_agora, processando_ate = null, atualizada_em = now()
             where s.id = v_s.id;
            continue;
          end if;
          if exists (select 1 from public.retorno_saidas o
                      where o.abertura_id = v_s.abertura_id
                        and o.tipo in ('recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo', 'saudacao_numero_novo')
                        and o.estado in ('enviada', 'incerta')
                        and o.decidida_em <= v_agora) then
            v_var := case when v_nome is null then 'apos_recibo_sem_nome' else 'apos_recibo' end;
          elsif v_nome is null then
            v_var := 'sem_nome';
          else
            -- VOZ-1 e VOZ-6: a Claudia se apresenta só se ninguém falou com este cliente
            v_ouviu := public._cliente_ja_apresentada(v_ab.client_id, v_s.chave, v_hoje);
            v_var := case when v_ouviu then 'padrao' else 'padrao_apresentacao' end;
          end if;
        end if;

      else
        v_var := null;   -- tipo desconhecido: o _retorno_texto recusa (22023)
      end if;

      -- F2: as variantes novas só com a chave ligada: com ela desligada, o texto ao cliente é o da F1.
      if v_cfg.variantes_ligadas then
        if v_s.tipo = 'recibo_cliente' and v_var = 'padrao' and not coalesce((v_pz ->> 'outro_dia')::boolean, false) then
          v_alt := public._retorno_variante_f2(v_ab.id, v_agora);
          if v_alt is not null then
            v_var := v_alt;
            v_f2 := true;
          end if;
        elsif v_s.tipo = 'adiamento' and public._retorno_tem_orcamento(v_ab.id, v_agora) then
          v_var := case when v_nome is null then 'orcamento_sem_nome' else 'orcamento' end;
          v_f2 := true;
        elsif v_s.tipo = 'coleta_numero_novo' and public._retorno_tem_orcamento(v_ab.id, v_agora) then
          v_var := 'nome_orcamento';
          v_f2 := true;
        end if;
      end if;

      if v_nome is not null then
        v_campos := v_campos || jsonb_build_object('nome', v_nome);
      end if;
      v_dados := v_dados || jsonb_strip_nulls(v_campos);

      begin
        -- F2: o modelo tem o texto dele; o resto, o da F1 ou a variante nova.
        if v_s.tipo like 'modelo\_%' escape '\' then
          v_texto := coalesce(v_dados ->> 'texto_aprovado', public._retorno_texto_do_modelo(v_ab.id, v_m, v_var, v_agora));
        elsif v_f2 then
          v_texto := public._retorno_texto_f2(v_s.tipo, v_var, v_dados);
        else
          v_texto := public._retorno_texto(v_s.tipo, v_var, v_dados);
        end if;
      exception when sqlstate '22023' then
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'texto', variante = left(v_var, 40), decidida_em = v_agora,
               processando_ate = null, dados = v_dados || jsonb_build_object('texto_erro', left(sqlerrm, 200)),
               atualizada_em = now()
         where s.id = v_s.id;
        perform public._retorno_log('pegar', 'retorno_pegar: ' || sqlerrm, 'error',
                                    jsonb_build_object('saida', v_s.id, 'sqlstate', '22023'));
        continue;
      end;

      -- F2: o dia da peça entra no contexto do validador.
      if v_s.tipo = 'modelo_peca_chegou' then
        v_dados := v_dados || jsonb_strip_nulls(jsonb_build_object('dia_peca', (regexp_match(v_texto, '[0-9]{2}/[0-9]{2}'))[1]));
      end if;

      -- 4. O modo efetivo (P4): o grupo do caso, o URGENTE, a passagem sem acorde e o caso em sombra.
      v_modo := public._retorno_modo_efetivo(v_s.id, v_var, v_dados -> 'prazo', v_agora);
      v_ligado := v_modo ->> 'modo' = 'ligado';
      -- F2: *segura tudo* não queima a saída: ela espera a hora do segura, e *solta tudo* a traz de volta.
      if v_modo ->> 'motivo' = 'segura_tudo' then
        update public.retorno_saidas s
           set enviar_em = v_cfg.segura_tudo_ate, dados = s.dados || jsonb_build_object('segurada', true), atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;
      if v_ligado then
        v_dados := v_dados - 'sombra_motivo';
      else
        v_dados := v_dados || jsonb_build_object('sombra_motivo', coalesce(v_modo ->> 'motivo', 'modo'));
      end if;

      -- 5. O canal (P4), simulando quando a saída vai em sombra. Ligada, trava antes a linha de configuração
      --    (até o fim da transação): a 2ª execução simultânea espera aqui e o canal dela já vê o
      --    proximo_envio_em e o teto do dia da 1ª (R1-11).
      if v_ligado then
        perform 1 from public.retorno_config c where c.id for update;
      end if;
      v_canal := public.canal_pode_enviar(v_s.phone_normalized, v_s.classe, v_s.origem, v_agora, not v_ligado, v_s.tipo);
      -- F2: o envio aprovado pelo dono conta, mas pode passar do teto do dia. Bloqueio, opt-out, pessoal e cliente final nunca passam.
      if not coalesce((v_canal ->> 'pode')::boolean, false)
         and not (v_canal ->> 'motivo' = 'teto_dia' and coalesce((v_dados ->> 'aprovada')::boolean, false)) then
        if v_canal ->> 'motivo' in ('fora_da_janela', 'espacamento')
           and (v_canal ->> 'enviar_em')::timestamptz > v_agora then
          update public.retorno_saidas s
             set enviar_em = (v_canal ->> 'enviar_em')::timestamptz,
                 dados = s.dados || jsonb_strip_nulls(jsonb_build_object('prazo', v_dados -> 'prazo')),
                 atualizada_em = now()
           where s.id = v_s.id;
          continue;
        end if;
        update public.retorno_saidas s
           set estado = 'recusada', motivo = coalesce(v_canal ->> 'motivo', 'canal'), variante = left(v_var, 40),
               texto = v_texto, dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;

      -- 6. Os tetos por número (contam sombra, preparada, enviando, enviada e incerta decididas até agora).
      if v_s.tipo = any (c_recibos) or v_s.tipo = 'saudacao_numero_novo' then
        -- recibo ou saudação de OUTRO caso nas últimas 12 h (a saudação e o recibo do mesmo caso são o par do
        -- 1º contato, J.10)
        if exists (select 1 from public.retorno_saidas o
                    where o.chave = v_s.chave
                      and o.id <> v_s.id
                      and o.emissor = 'retorno'
                      and (o.tipo = any (c_recibos) or o.tipo = 'saudacao_numero_novo')
                      and o.abertura_id is distinct from v_s.abertura_id
                      and o.estado = any (c_contam)
                      and o.decidida_em <= v_agora
                      and o.decidida_em > v_agora - v_cfg.recibo_intervalo) then
          update public.retorno_saidas s
             set estado = 'recusada', motivo = 'teto_numero', variante = left(v_var, 40), texto = v_texto,
                 dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
           where s.id = v_s.id;
          continue;
        end if;
      end if;
      if v_s.tipo = 'saudacao_numero_novo'
         and exists (select 1 from public.retorno_saidas o
                      where o.chave = v_s.chave
                        and o.id <> v_s.id
                        and o.tipo = 'saudacao_numero_novo'
                        and o.estado = any (c_contam)
                        and o.decidida_em <= v_agora
                        and o.decidida_em > v_agora - v_cfg.saudacao_intervalo) then
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'teto_saudacao', variante = left(v_var, 40), texto = v_texto,
               dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;
      if v_s.tipo = 'coleta_numero_novo'
         and (select count(*) from public.retorno_saidas o
               where o.abertura_id = v_s.abertura_id
                 and o.id <> v_s.id
                 and o.tipo in ('saudacao_numero_novo', 'recibo_numero_novo', 'coleta_numero_novo')
                 and o.estado = any (c_contam)
                 and o.decidida_em <= v_agora) >= v_cfg.coleta_max then
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'teto_coleta', variante = left(v_var, 40), texto = v_texto,
               dados = v_dados, decidida_em = v_agora, processando_ate = null, atualizada_em = now()
         where s.id = v_s.id;
        continue;
      end if;

      -- 7. A reserva.
      update public.retorno_saidas s
         set estado = case when v_ligado then 'enviando' else 'preparada' end,
             texto = v_texto, dados = v_dados, variante = left(v_var, 40), decidida_em = v_agora,
             processando_ate = v_agora + interval '2 minutes',
             modo = case when v_ligado then 'ligado' else 'sombra' end,
             atualizada_em = now()
       where s.id = v_s.id
       returning * into v_s;
      if v_ligado then
        -- o espaçamento global entre saídas automáticas, sorteado (R1-11)
        update public.retorno_config c
           set proximo_envio_em = v_agora + make_interval(secs => (c.espaco_min_s
                                    + floor(random() * (c.espaco_max_s - c.espaco_min_s + 1)))::double precision)
         where c.id;
      end if;

      -- 8. O item, com o contexto do validador montado pelo banco.
      v_ctx := public._retorno_contexto_do_validador(v_s.id, v_texto, v_dados, v_agora);
      return jsonb_build_object(
        'saida_id', v_s.id,
        'tentativa', v_s.tentativa,
        'dedupe_key', v_s.dedupe_key,
        'tipo', v_s.tipo,
        'variante', v_s.variante,
        'origem', v_s.origem,
        'classe', v_s.classe,
        'modo', v_s.modo,
        'phone', v_s.phone_normalized,
        'texto', v_s.texto,
        'validador', v_ctx);
    exception when others then
      -- Erro num item nunca trava a fila: a volta é desfeita, a saída vira recusada/erro e a próxima segue.
      update public.retorno_saidas s
         set estado = 'recusada', motivo = 'erro', decidida_em = v_agora, processando_ate = null,
             dados = s.dados || jsonb_build_object('erro', jsonb_build_object('sqlstate', sqlstate,
                                                                               'mensagem', left(sqlerrm, 200))),
             atualizada_em = now()
       where s.id = v_s.id;
      perform public._retorno_log('pegar', 'retorno_pegar: ' || sqlerrm, 'error',
                                  jsonb_build_object('saida', v_s.id, 'sqlstate', sqlstate));
    end;
  end loop;
  return null;
end;
$$;

revoke all on function public.retorno_pegar(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_pegar(timestamptz) to service_role;
