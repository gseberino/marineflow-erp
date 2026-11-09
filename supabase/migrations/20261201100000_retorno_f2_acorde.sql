-- Retorno rápido ao cliente, F2 (P14): o acorde real. Pacote 2. Gerada por script a partir do corpo vigente das funções.
--
-- O cliente responde "urgente", a passagem pede o dono ou o prazo vence em 1 hora: o Gustavo é acordado de verdade, pelo portão
-- de avisos_do_dono (no máximo 2 por dia, das 08:00 às 20:00, o mesmo assunto não acorda duas vezes).
--
-- Sem o update de ligar (P14.2), nada muda: o acorde segue simulado em sombra. Todo trecho novo exige modo = 'ligado' e 'acorde'
-- em tipos_ligados.
--
-- Desvios da spec, registrados: a chave da passagem leva o dia (F1-10: o caso fica aberto até o dono resolver, e a reclamação de
-- outro dia precisa poder acordar); com o cartão desligado o A01 vai pela fila, senão aguarda_cartao ficaria para sempre; T24a
-- para o cliente sem nome; _retorno_acordar_agora para o urgente e a pressa, que não têm saída acorde própria na F1.
--
-- Reverter: update public.retorno_config set tipos_ligados = array(select t from unnest(tipos_ligados) t where t not in ('urgente', 'acorde')),
-- meio_dia_ligado = false where id; e reaplicar as versões de retorno_vigia, retorno_vigia_cartao, _retorno_cartao_devido e retorno_pegar
-- das migrations 20261116100800, 20261123100900, 20261123100700 e 20261123100600.

-- O aviso ao dono de um caso. O texto (A01) não tem nada do cliente: vai para avisos_do_dono, que a manhã lê.
create or replace function public._retorno_acordar(p_abertura uuid, p_variante text, p_agora timestamptz, p_por text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_ab public.retorno_aberturas;
  v_phone text;
  v_motivo text;
  v_prazo text := '';
  v_chave text;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'caso');
  end if;
  select d.phone into v_phone from public._comprovante_dono() d;

  v_motivo := case
    when p_variante = 'venceu' then 'venceu ontem'
    when p_variante = 'urgente' then 'urgente'
    when p_variante = 'pressa' then 'pressa'
    when p_variante = 'relogio' then 'o prazo vence em 1 hora'
    when p_por = 'risco' then 'risco'
    when p_por = 'lgpd' then 'pedido de dados (LGPD)'
    when p_por = 'reclamacao' then 'reclamação'
    when p_por = 'quer_dono' then 'quer falar com você'
    when p_por = 'vencida' then 'escreveu de novo depois de vencer'
    else '2ª insistência'
  end;
  if v_ab.prometido_ate is not null then
    v_prazo := ', prometi até ' || public._retorno_hora((v_ab.prometido_ate at time zone c_fuso)::time);
  end if;

  -- A passagem leva o dia: com o caso aberto até o dono resolver (F1-10), a reclamação de outro dia precisa poder acordar.
  v_chave := 'retorno:' || p_abertura || ':' || p_variante
             || case when p_variante = 'passagem' then ':' || (p_agora at time zone c_fuso)::date else '' end;

  return public.aviso_registrar(jsonb_build_object(
    'phone', v_phone,
    'modo', public._retorno_modo_da_voz(),
    'fonte', 'cliente',
    'chave', v_chave,
    'assunto', 'contato:' || v_ab.phone_normalized,   -- o mesmo do "me acorde se": a mesma reclamação não acorda duas vezes
    'destino', 'acorde',
    'texto', format('%s: %s%s. *retorno* abre o cartão.', public._retorno_rotulo(p_abertura, p_agora), v_motivo, v_prazo),
    'dados', jsonb_build_object('abertura', p_abertura, 'variante', p_variante),
    'agora', p_agora));
end;
$$;

comment on function public._retorno_acordar(uuid, text, timestamptz, text) is
  'Retorno F2 (P14): registra o aviso do caso pelo portão de avisos_do_dono (A01, sem texto do cliente; o assunto é o do "me acorde se"). Devolve o resultado de aviso_registrar.';

-- A01 pela fila, com o molde de linhaDoAcordeNaFila. Limpa aguarda_cartao: o minuto seguinte não repete.
create or replace function public._retorno_a01_na_fila(p_aviso uuid, p_agora timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_a public.avisos_do_dono;
  v_minutos numeric;
begin
  update public.retorno_saidas s
     set dados = s.dados - 'aguarda_cartao', atualizada_em = now()
   where s.tipo = 'acorde' and s.dados ->> 'aviso_id' = p_aviso::text and s.dados ? 'aguarda_cartao';

  select * into v_a from public.avisos_do_dono a where a.id = p_aviso;
  if not found then
    return;
  end if;
  v_minutos := extract(epoch from ((((p_agora at time zone c_fuso)::date + time '20:00') at time zone c_fuso) - p_agora)) / 60;
  begin
    insert into public.whatsapp_send_queue (phone_normalized, message, source, priority, max_attempts, dedupe_key, source_ref_id)
    values (v_a.phone_normalized, v_a.texto, 'me_acorde', 1, greatest(1, floor((v_minutos - 5) / 10)::integer + 1),
            'aviso:' || p_aviso, p_aviso)
    on conflict (dedupe_key) do nothing;
  exception when others then
    perform public.aviso_reabrir(jsonb_build_object('id', p_aviso, 'agora', p_agora));
    perform public._retorno_log('acorde', 'retorno_a01_na_fila: ' || sqlerrm, 'error',
                                jsonb_build_object('aviso', p_aviso, 'sqlstate', sqlstate));
  end;
end;
$$;

comment on function public._retorno_a01_na_fila(uuid, timestamptz) is
  'Retorno F2 (P14): põe o A01 na fila (source me_acorde, prioridade 1, dedupe aviso:<id>) e limpa aguarda_cartao. Falha no insert reabre o aviso.';

-- Aplica à saída acorde o que o portão decidiu.
create or replace function public._retorno_acorde_aplicar(p_saida uuid, p_av jsonb, p_agora timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg public.retorno_config := public._retorno_cfg();
  v_decisao text := p_av ->> 'decisao';
  v_aviso uuid := (p_av ->> 'id')::uuid;
  v_cartao boolean := coalesce((p_av ->> 'cartao')::boolean, false) and v_cfg.cartao_ligado;
begin
  if coalesce((p_av ->> 'ok')::boolean, false) and v_decisao = 'acordar' then
    update public.retorno_saidas s
       set estado = 'enviada', modo = 'ligado', decidida_em = p_agora, enviada_em = p_agora,
           dados = s.dados || jsonb_build_object('aviso_id', v_aviso)
                   || case when v_cartao then '{"aguarda_cartao": true}'::jsonb else '{}'::jsonb end,
           atualizada_em = now()
     where s.id = p_saida;
    if not v_cartao then
      perform public._retorno_a01_na_fila(v_aviso, p_agora);
    end if;
  elsif coalesce((p_av ->> 'ok')::boolean, false) and v_decisao = 'guardar' then
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'guardado_no_portao', decidida_em = p_agora,
           dados = s.dados || jsonb_build_object('aviso_id', v_aviso), atualizada_em = now()
     where s.id = p_saida;
  elsif coalesce((p_av ->> 'ok')::boolean, false) and v_decisao = 'repetido' then
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'acorde_repetido', decidida_em = p_agora, atualizada_em = now()
     where s.id = p_saida;
  else
    update public.retorno_saidas s
       set estado = 'recusada', motivo = 'erro', decidida_em = p_agora,
           dados = s.dados || jsonb_build_object('aviso', p_av), atualizada_em = now()
     where s.id = p_saida;
  end if;
end;
$$;

comment on function public._retorno_acorde_aplicar(uuid, jsonb, timestamptz) is
  'Retorno F2 (P14): acordar = enviada, com aguarda_cartao (das 09:30 em diante, cartão ligado) ou A01 na fila; guardar = cancelada/guardado_no_portao; repetido = cancelada/acorde_repetido; o resto = recusada/erro.';

-- O acorde que sai junto com a resposta ao cliente (urgente e pressa). Devolve se o Gustavo foi avisado de fato.
create or replace function public._retorno_acordar_agora(p_abertura uuid, p_variante text, p_agora timestamptz)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_saida uuid;
  v_av jsonb;
begin
  insert into public.retorno_saidas (abertura_id, tipo, variante, chave, phone_normalized, client_id, modo,
                                     estado, enviar_em, dados, dedupe_key)
  select a.id, 'acorde', p_variante, a.chave, a.phone_normalized, a.client_id, a.modo, 'agendada', p_agora,
         jsonb_build_object('por', p_variante), 'retorno:' || a.id || ':acorde:' || p_variante
    from public.retorno_aberturas a where a.id = p_abertura
  on conflict (dedupe_key) do nothing
  returning id into v_saida;

  v_av := public._retorno_acordar(p_abertura, p_variante, p_agora, p_variante);
  if v_saida is not null then
    perform public._retorno_acorde_aplicar(v_saida, v_av, p_agora);
  end if;
  -- A saída que voltou à fila e foi composta de novo: o aviso de antes vale.
  return coalesce((v_av ->> 'ok')::boolean, false)
         and (v_av ->> 'decisao' = 'acordar' or (v_av ->> 'decisao' = 'repetido' and v_av ->> 'antes' = 'acordar'));
end;
$$;

comment on function public._retorno_acordar_agora(uuid, text, timestamptz) is
  'Retorno F2 (P14): registra e aplica o acorde de urgente e pressa, que o retorno_pegar precisa saber na hora ("Avisei o Gustavo" só se avisou).';

revoke all on function public._retorno_acordar(uuid, text, timestamptz, text) from public, anon, authenticated;
revoke all on function public._retorno_a01_na_fila(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public._retorno_acorde_aplicar(uuid, jsonb, timestamptz) from public, anon, authenticated;
revoke all on function public._retorno_acordar_agora(uuid, text, timestamptz) from public, anon, authenticated;

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

create or replace function public.retorno_vigia_cartao(p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (v_agora at time zone c_fuso)::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_vivo jsonb;
  v_cartao uuid;
  r record;
  v_conf jsonb;
  v_caidos integer := 0;
  v_promovidos integer := 0;
  v_rebaixados integer := 0;
  v_avisos integer := 0;
  v_dono uuid;
  v_phone text;
  v_motivo text;
  v_rotulo text;
  v_edit integer;
  v_tot integer;
  v_hora time := (v_agora at time zone c_fuso)::time;   -- F2 (P14)
  v_a public.retorno_saidas;                            -- F2 (P14)
  v_acordes integer := 0;                               -- F2 (P14)
begin
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return jsonb_build_object('rodou', false);
  end if;
  select d.id, d.phone into v_dono, v_phone from public._comprovante_dono() d;

  -- 1 e 2. Queda e validade.
  begin
    v_vivo := public.retorno_cartao_vivo(v_agora);
    if v_vivo ->> 'estado' = 'vivo' then
      v_cartao := (v_vivo ->> 'id')::uuid;
      if (select c.expira_em from public.retorno_cartoes c where c.id = v_cartao) < v_agora then
        perform public._retorno_cartao_encerrar(v_cartao, 'expirou', 'expired', 'cartao_expirou', v_agora);
      else
        for r in select i.id from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo' loop
          v_conf := public._retorno_item_conferir(r.id, v_agora, false);
          if not (v_conf ->> 'ok')::boolean then
            update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = v_conf ->> 'motivo', decidido_em = v_agora where i.id = r.id;
            v_caidos := v_caidos + 1;
          end if;
        end loop;
        if not exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo') then
          perform public._retorno_cartao_encerrar(v_cartao, 'caiu', 'rejected', 'cartao_caiu', v_agora);
        elsif v_caidos > 0 then
          update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = v_cartao;
        end if;
      end if;
    end if;
  exception when others then
    perform public._retorno_vigia_log('queda', sqlstate);
  end;

  -- 3. Amarração: sem cartão vivo, a sessão do dono solta o caso.
  begin
    if not exists (select 1 from public.retorno_cartoes c where c.estado = 'vivo') then
      update public.ai_operator_sessions s
         set client_id = null, vessel_id = null, service_order_id = null, metadata = s.metadata - 'retorno_amarrada'
       where s.channel = 'whatsapp' and s.external_thread_key = v_phone and s.status = 'open' and s.metadata ? 'retorno_amarrada';
    end if;
  exception when others then
    perform public._retorno_vigia_log('amarracao', sqlstate);
  end;

  -- 4. Promoção.
  begin
    for r in select t.* from public.retorno_modelo_tipos t where t.nivel = 'cartao' loop
      continue when r.promocao_suspensa_ate is not null and r.promocao_suspensa_ate > v_agora;
      if r.regua = 'dias' then
        continue when cardinality(r.aprovados_dias) < v_cfg.modelo_dias_aprovacao;
        continue when v_hoje <= (select max(d) from unnest(r.aprovados_dias) d);
      else
        continue when r.aprovados_usos < v_cfg.modelo_usos_liberado;
      end if;
      -- sem queixa nem pedido de parar desde a 1ª aprovação do período
      continue when exists (
        select 1
          from public.retorno_saidas s
          join public.retorno_mensagens m on m.chave = s.chave and m.recebida_em > s.decidida_em
                                         and m.recebida_em <= s.decidida_em + interval '24 hours'
         where s.tipo = r.tipo and s.estado = 'enviada' and s.decidida_em <= v_agora
           and coalesce((m.sinais ->> 'reclamacao')::boolean, false));
      continue when exists (
        select 1
          from public.retorno_saidas s
          join public.whatsapp_blocked_numbers b on public._agenda_chave_telefone(b.phone_normalized) = s.chave
         where s.tipo = r.tipo and s.estado = 'enviada' and b.tipo = 'opt_out'
           and b.created_at > s.decidida_em and b.created_at <= s.decidida_em + interval '48 hours');
      -- nos últimos 10 itens do tipo, editados até rebaixa_edicao_pct
      select count(*), count(*) filter (where x.texto_ditado is not null) into v_tot, v_edit
        from (select i.texto_ditado
                from public.retorno_cartao_itens i
                join public.retorno_cartoes c on c.id = i.cartao_id
               where i.modelo_tipo = r.tipo and i.estado in ('feito', 'fora')
               order by c.criado_em desc
               limit 10) x;
      continue when v_tot > 0 and v_edit::numeric / v_tot > v_cfg.rebaixa_edicao_pct;

      update public.retorno_modelo_tipos t
         set nivel = 'sozinho', promovido_em = v_agora, atualizado_em = now()
       where t.tipo = r.tipo;
      v_promovidos := v_promovidos + 1;
    end loop;
  exception when others then
    perform public._retorno_vigia_log('promocao', sqlstate);
  end;

  -- 5. Fadiga: as últimas fadiga_vezes aprovações, todas rápidas, nas últimas 24 h.
  begin
    if (select count(*) from (select t.rapido from public.retorno_toques t
                               where t.palavra = 'sim_pin' and t.em > v_agora - interval '24 hours' and t.em <= v_agora
                               order by t.em desc limit v_cfg.fadiga_vezes) x where x.rapido) >= v_cfg.fadiga_vezes then
      update public.retorno_modelo_tipos t
         set promocao_suspensa_ate = v_agora + v_cfg.fadiga_suspende, atualizado_em = now()
       where (t.promocao_suspensa_ate is null or t.promocao_suspensa_ate <= v_agora)
         and t.tipo in (select i.modelo_tipo
                          from public.retorno_toques q
                          join public.retorno_cartao_itens i on i.cartao_id = q.cartao_id
                         where q.palavra = 'sim_pin' and q.rapido and q.em > v_agora - interval '24 hours' and q.em <= v_agora
                           and i.modelo_tipo is not null);
    end if;
  exception when others then
    perform public._retorno_vigia_log('fadiga', sqlstate);
  end;

  -- 6. Rebaixamento: queixa até 24 h depois, opt-out até 48 h, ou 3 recusas do validador na última hora.
  begin
    for r in select t.tipo, t.promovido_em from public.retorno_modelo_tipos t where t.nivel = 'sozinho' loop
      v_motivo := null;
      if exists (select 1
                   from public.retorno_saidas s
                   join public.retorno_mensagens m on m.chave = s.chave and m.recebida_em > s.decidida_em
                                                  and m.recebida_em <= s.decidida_em + interval '24 hours' and m.recebida_em <= v_agora
                  where s.tipo = r.tipo and s.estado = 'enviada' and s.decidida_em > coalesce(r.promovido_em, v_agora - interval '30 days')
                    and coalesce((m.sinais ->> 'reclamacao')::boolean, false)) then
        v_motivo := 'queixa';
      elsif exists (select 1
                      from public.retorno_saidas s
                      join public.whatsapp_blocked_numbers b on public._agenda_chave_telefone(b.phone_normalized) = s.chave
                     where s.tipo = r.tipo and s.estado = 'enviada' and b.tipo = 'opt_out'
                       and s.decidida_em > coalesce(r.promovido_em, v_agora - interval '30 days')
                       and b.created_at > s.decidida_em and b.created_at <= s.decidida_em + interval '48 hours' and b.created_at <= v_agora) then
        v_motivo := 'opt_out';
      elsif (select count(*) from public.retorno_saidas s
              where s.tipo = r.tipo and s.estado = 'recusada' and s.motivo = 'validador'
                and s.decidida_em > v_agora - interval '1 hour' and s.decidida_em <= v_agora) >= 3 then
        v_motivo := 'validador';
      end if;
      if v_motivo is not null and public._retorno_rebaixar(r.tipo, v_motivo, v_agora) then
        v_rebaixados := v_rebaixados + 1;
      end if;
    end loop;
  exception when others then
    perform public._retorno_vigia_log('rebaixamento', sqlstate);
  end;

  -- 7. Saída aprovada que foi recusada: o dono vê na mensagem fixa seguinte, sem gastar acorde e sem texto do cliente.
  begin
    for r in
      select s.id, s.abertura_id, s.phone_normalized, s.motivo
        from public.retorno_saidas s
       where s.estado = 'recusada' and coalesce((s.dados ->> 'aprovada')::boolean, false) and not s.dados ? 'avisada'
    loop
      v_rotulo := public._retorno_rotulo(r.abertura_id, v_agora);
      perform public.aviso_registrar(jsonb_build_object(
        'phone', v_phone, 'modo', public._retorno_modo_da_voz(), 'fonte', 'cliente',
        'chave', 'retorno:recusa:' || r.id, 'assunto', 'contato:' || r.phone_normalized, 'destino', 'proxima_fixa',
        'texto', format('Não saiu a mensagem para %s: %s. Responda pelo celular.', v_rotulo,
                        case r.motivo when 'validador' then 'o texto não passou na conferência'
                                      when 'fato_mudou' then 'o fato mudou'
                                      else 'o canal recusou' end),
        'agora', v_agora));
      update public.retorno_saidas s set dados = s.dados || '{"avisada": true}'::jsonb, atualizada_em = now() where s.id = r.id;
      v_avisos := v_avisos + 1;
    end loop;
  exception when others then
    perform public._retorno_vigia_log('recusa', sqlstate);
  end;

  -- F2 (P14): 8 e 9. O acorde real, 1 por minuto; os outros ficam para o minuto seguinte.
  begin
    if v_cfg.modo = 'ligado' and 'acorde' = any (v_cfg.tipos_ligados) then
      -- 9. A 1ª prioridade da manhã: quem ficou para hoje e ainda não teve resposta.
      if public.agenda_dia_util(v_hoje) and v_hora >= time '08:00' and v_hora < time '20:00' then
        insert into public.retorno_saidas (abertura_id, tipo, variante, chave, phone_normalized, client_id, modo,
                                           estado, enviar_em, dados, dedupe_key)
        select a.id, 'acorde', 'venceu', a.chave, a.phone_normalized, a.client_id, a.modo, 'agendada', v_agora,
               jsonb_build_object('por', 'venceu'), 'retorno:' || a.id || ':acorde:venceu'
          from public.retorno_aberturas a
         where a.topo_dia = v_hoje and a.cumprida_em is null and a.estado in ('aberta', 'vencida')
        on conflict (dedupe_key) do nothing;
      end if;

      select s.* into v_a
        from public.retorno_saidas s
       where s.tipo = 'acorde' and s.estado = 'agendada' and s.enviar_em <= v_agora
       order by case s.variante when 'venceu' then 0 when 'passagem' then 1 when 'relogio' then 2 else 3 end, s.enviar_em, s.id
       limit 1
       for update skip locked;
      if found then
        if not exists (select 1 from public.retorno_aberturas a where a.id = v_a.abertura_id and a.estado <> 'fechada') then
          update public.retorno_saidas s
             set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_agora, atualizada_em = now()
           where s.id = v_a.id;
        else
          perform public._retorno_acorde_aplicar(v_a.id,
            public._retorno_acordar(v_a.abertura_id, v_a.variante, v_agora, v_a.dados ->> 'por'), v_agora);
          v_acordes := 1;
        end if;
      end if;
    end if;
  exception when others then
    perform public._retorno_vigia_log('acorde', sqlstate);
  end;

  return jsonb_build_object('rodou', true, 'caidos', v_caidos, 'promovidos', v_promovidos, 'rebaixados', v_rebaixados, 'avisos', v_avisos,
                            'acordes', v_acordes);
end;
$$;

create or replace function public._retorno_cartao_devido(p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_hoje date := (p_agora at time zone c_fuso)::date;
  v_hora time := (p_agora at time zone c_fuso)::time;
  v_aviso text;   -- F2 (P14)
begin
  -- F2 (P14): o acorde que espera o cartão vem antes do meio-dia.
  if v_cfg.id is not null and v_cfg.modo = 'ligado' and v_cfg.cartao_ligado and 'acorde' = any (v_cfg.tipos_ligados) then
    select s.dados ->> 'aviso_id' into v_aviso
      from public.retorno_saidas s
     where s.tipo = 'acorde' and s.estado = 'enviada' and coalesce((s.dados ->> 'aguarda_cartao')::boolean, false)
     order by s.decidida_em, s.id
     limit 1;
    if v_aviso is not null then
      return jsonb_build_object('gatilho', 'acorde', 'aviso_id', v_aviso);
    end if;
  end if;
  if v_cfg.id is null or v_cfg.modo = 'desligado' or not v_cfg.meio_dia_ligado or not v_cfg.cartao_ligado then
    return null;
  end if;
  if not public.agenda_dia_util(v_hoje) or v_hora < v_cfg.ponto_meio_dia or v_hora >= v_cfg.promessa_meio_dia then
    return null;
  end if;
  if not exists (select 1 from public.retorno_aberturas a
                  where a.prometido_fonte = 'meio_dia'
                    and (a.prometido_ate at time zone c_fuso)::date = v_hoje
                    and a.cumprida_em is null
                    and a.estado in ('aberta', 'vencida')) then
    return null;
  end if;
  if exists (select 1 from public.retorno_cartoes c where c.gatilho = 'meio_dia' and c.dia = v_hoje and c.estado <> 'falhou') then
    return null;
  end if;
  if (select count(*) from public.retorno_cartoes c where c.gatilho = 'meio_dia' and c.dia = v_hoje and c.estado = 'falhou') >= v_cfg.cartao_tentativas then
    return null;
  end if;
  return jsonb_build_object('gatilho', 'meio_dia');
end;
$$;

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
  v_acorde boolean;    -- F2 (P14)
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
      v_acorde := false; -- F2 (P14)

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
          -- F2 (P14): a pressa, com vaga de acorde, sai junto com o recibo e promete o fechamento de hoje. Sem vaga, a faixa normal.
          if coalesce((v_ab.sinais ->> 'pressa')::boolean, false)
             and v_s.tipo <> 'saudacao_numero_novo'
             and v_cfg.modo = 'ligado' and 'acorde' = any (v_cfg.tipos_ligados)
             and (v_agora at time zone c_fuso)::time >= time '08:00' and (v_agora at time zone c_fuso)::time < time '20:00' then
            v_acorde := public._retorno_acordar_agora(v_ab.id, 'pressa', v_agora);
          end if;
          v_pz := public._retorno_prazo(greatest(v_ab.aberta_em, v_agora), v_ab.chave,
                                        coalesce((v_ab.sinais ->> 'pressa')::boolean, false), v_acorde);
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
          -- F2 (P14): o banco sabe qual das duas é verdade. "Avisei" só com o aviso de fato registrado.
          if v_cfg.modo = 'ligado' and 'acorde' = any (v_cfg.tipos_ligados)
             and public._retorno_acordar_agora(v_ab.id, 'urgente', v_agora) then
            v_var := case when v_nome is null then 'acorde_sem_nome' else 'acorde' end;
          end if;
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
