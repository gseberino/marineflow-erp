-- Retorno rápido ao cliente, F1 (sobe em sombra na seg 16/11/2026): pegar e decidir as saídas do retorno.
-- O caso (P5) agenda as saídas; aqui o banco as pega uma a uma, confere tudo de novo no instante de mandar,
-- monta o texto fixo e reserva a saída para a edge retorno-recibos (P11), que só roda o validador e fala com
-- o whatsapp-send. Cada desfecho volta por retorno_registrar_decisao. IA pensa, sistema preenche: hora,
-- prazo, variante, modo e estado são do banco.
--
-- 1. retorno_tem_vencido(agora) → boolean (C-VENCIDO): o cron (P9) só chama a edge quando há saída de texto
--    agendada e vencida, fora de reserva. O acorde e o cadastro provisório o SQL decide sozinho (vigia, P6.2).
--    Usa o índice retorno_saidas_devidas (incidente de 17/08: nada de chamada em vão a cada minuto).
--
-- 2. _retorno_resposta_humana(caso, agora) → {respondida_em, cumprida_em, cumprida_por}: a ÚNICA fonte do
--    "o dono respondeu" (pegar e vigia). Resposta humana = _saida_e_humana (F0b) à chave, depois da abertura
--    pelas duas horas (a real e a de gravação: no lote de ressincronização a pergunta e a resposta gravam no
--    mesmo minuto) e sempre gravada até agora (ninguém olha o futuro). Cumprida = a 1ª com conteúdo (áudio,
--    documento ou mais de conteudo_min_caracteres): o "ok, já vejo" responde, mas não cumpre (A.2).
--
-- 3. _retorno_checar_antes(saída, agora) → {acao: seguir | cancelar | adiar, motivo, enviar_em}: as regras
--    de antes de mandar, na ordem da spec (caso fechado; respondida pelo dono, salvo o aviso honesto, que só
--    a resposta de conteúdo cancela; rajada; lote global; áudio do número novo; a triagem de novo; atraso de
--    gravação longo; teto de mensagens de volta). Duas regras a mais, que a spec deixa em aberto (falha
--    fecha): o adiamento que não saiu antes do "até X" e o fim do dia que passou do próprio dia são
--    cancelados (caso_vencido): "a resposta sai até as 19h" depois das 19h, ou "não conseguiu te responder
--    hoje" na manhã seguinte, seriam mentira. VOLATILE (desvio da spec, que diz STABLE): chama _retorno_triar
--    (P5), que regrava o caso e cancela saídas, e função STABLE não deve escrever.
--
-- 4. retorno_pegar(agora) → jsonb | null (C-PEGAR): até 10 voltas; cada uma pega 1 saída devida com FOR
--    UPDATE SKIP LOCKED (duas execuções nunca pegam a mesma; a trava não depende do envio, B.8.4), fora do
--    sub-bloco. Do passo 2 ao 7, cada volta roda num begin … exception próprio: a exceção desfaz só a volta,
--    marca a saída recusada/erro (com o sqlstate e a mensagem em dados.erro), vai ao app_error_logs (context
--    'retorno', action 'pegar') e a volta seguinte segue. Um item cujo dado derruba a composição nunca volta
--    à frente da fila a cada minuto (incidente de 17/08). Os passos:
--    - checar antes (acima): cancelar (com respondida_em no caso, se foi o dono) ou adiar;
--    - compor: o prazo do recibo e da saudação é gravado em dados.prazo na 1ª vez (a mensagem das 23:30 ouve
--      às 08:10 a promessa da faixa noite, "hoje até as 10h"), e o recibo fora da janela espera a manhã; a
--      variante pelas regras do P3.1 (K4 pelo modo PRETENDIDO); o texto por _retorno_texto, e falta de dado
--      (22023) = recusada/texto; o fim do dia e o URGENTE gravam antes o topo_dia do caso;
--    - modo efetivo (_retorno_modo_efetivo, P4), com o motivo da sombra em dados.sombra_motivo;
--    - canal (canal_pode_enviar, P4; simulando quando a saída vai em sombra): fora da janela e espaçamento
--      reagendam; o resto recusa com o motivo do canal. A saída LIGADA trava antes a linha de retorno_config
--      (FOR UPDATE, até o fim da transação): duas execuções simultâneas do retorno_pegar (duas rodadas da edge
--      sobrepostas, seção 7.3) passam uma de cada vez pelo espaçamento global (R1-11) e pelo teto do dia, e a
--      2ª vê a reserva da 1ª. Sem a trava, as duas leriam proximo_envio_em antes de qualquer commit e
--      reservariam duas saídas a menos de espaco_min_s uma da outra;
--    - tetos por número: recibo ou saudação de OUTRO caso nas últimas 12 h; saudação em 30 dias; no 1º
--      contato do número novo, no máximo 2 mensagens automáticas (saudação, recibo e coleta);
--    - reserva: 'enviando' (ligado) ou 'preparada' (sombra) por 2 min, com o espaçamento global sorteado
--      entre espaco_min_s e espaco_max_s (R1-11) só quando ligado;
--    - devolve o item com o contexto do validador (C-VAL) montado pelo banco: datas, horas e nome que o banco
--      pôs, os nomes curtos dos clientes do número no ambíguo, os textos do cliente (só para o eco) e os
--      trechos do modelo. Os trechos saem do próprio texto, cortado nos valores dos {campos}: um valor que
--      coincida com o texto fixo só encolhe a lista de permissão (bloqueia mais, nunca menos).
--    Desvios (falha fecha), levados à coordenação: o prazo guardado que já venceu é calculado de novo (nunca
--    promete hora passada); as palavras do dia do prazo guardado (quando, outro_dia, ref) são vistas de novo
--    do dia em que o recibo SAI, e a promessa (dia, hora, prometido_ate) não muda: o recibo composto às 21:59
--    ("amanhã até as 10h") que voltou a agendada depois das 22:00 (a reserva que venceu, o 503, o espaçamento)
--    e que o canal levou à manhã seguinte diz "hoje até as 10h", nunca "amanhã", e o validador não pegaria
--    ("amanhã" está em datas_permitidas); o recibo de número novo sem a palavra do bem não pergunta o modelo (sai
--    sem_pergunta, em vez de recusar o recibo por falta de {do_bem}); o atraso longo e o teto de volta valem
--    também para a saudação; o teto de volta conta toda saída de recibo ou saudação marcada como "de volta"
--    (atraso de gravação entre volta_min e volta_max), não só as variantes volta*.
--
-- 5. retorno_registrar_decisao(saída, estado, detalhe, agora) → {ok, estado} | {ok: false, erro} (C-DECISAO):
--    sombra (de preparada); enviada (de enviando: zera os erros seguidos e desliga o so_reativo por erros);
--    incerta (de enviando; FINAL, nunca há 2ª tentativa); recusada (de preparada ou enviando, com o motivo
--    validador | canal | provedor | equipe | texto; outro motivo vira 'erro', para a saída nunca ficar presa);
--    reagendar (de enviando, só quando a reserva do whatsapp-send não aconteceu: volta a agendada em 2 min,
--    com a MESMA chave; acima de 3 tentativas, recusada/reserva). Três erros seguidos (incerta ou provedor)
--    ligam o disjuntor (so_reativo, motivo 'erros', B.6). Estado de partida errado = {"ok": false, "erro":
--    "estado"}, sem mudar nada. Exceção = {"ok": false, "erro": sqlstate}, com log.
--    Efeitos no caso (_retorno_aplicar_efeitos) quando o estado final é sombra, enviada ou incerta (a sombra
--    simula o relógio inteiro; a incerta pode ter saído, e o aviso honesto vale): o recibo grava recibo_em e a
--    promessa (prometido_ate, fonte, faixa); a mensagem a número novo soma coleta_n; o adiamento grava
--    adiamento_em e o 2º prazo; o fim do dia, fim_do_dia_em e o caso vencido; o URGENTE, urgente_em. Os
--    efeitos rodam num sub-bloco próprio: o que falha (dados.prazo ou dados.x2 ilegíveis) vai ao app_error_logs
--    (action 'decisao') e NÃO desfaz a decisão. Sem isso a decisão voltava atrás com {"ok": false}, a saída
--    ficava preparada/enviando, o vigia a devolvia (ou a passava a incerta, com o mesmo efeito que falha) e o
--    ciclo se repetia a cada ~7 min, sem nunca chegar a um estado final (erro nunca trava a fila).
--    Desvio da spec (que diz "recibo/saudação → recibo_em, prometido_ate…"): a saudação (T19, "Em que posso
--    te ajudar?") não promete hora, então não grava promessa nem recibo_em. Assim o relógio (adiamento e fim
--    do dia) nunca avisa um prazo que ninguém ouviu, e a calibração (P9) não conta caso sem promessa.
--
-- Auxiliares internas (_retorno_*): SECURITY DEFINER com search_path, revoke de public, anon e authenticated,
-- sem grant. _retorno_log embrulha log_app_error e nunca levanta (um log que derruba o retorno seria pior
-- que não ter log). As públicas (retorno_*): SECURITY DEFINER, só o service_role.
--
-- Sem dado: só funções novas; nenhuma linha existente muda. As tabelas (P1) nascem vazias.
-- Reverter (depois das migrations seguintes da F1, que chamam estas): drop function
-- public.retorno_registrar_decisao(uuid, text, jsonb, timestamptz), public.retorno_pegar(timestamptz),
-- public._retorno_contexto_do_validador(uuid, text, jsonb, timestamptz),
-- public._retorno_checar_antes(uuid, timestamptz), public._retorno_resposta_humana(uuid, timestamptz),
-- public._retorno_aplicar_efeitos(uuid, timestamptz), public.retorno_tem_vencido(timestamptz),
-- public._retorno_log(text, text, text, jsonb).
-- Sem deploy: update public.retorno_config set modo = 'desligado' (retorno_pegar devolve nulo e o cron não
-- chama a edge) ou modo = 'sombra' (nada sai ligado).

-- ── 0. O log que nunca derruba ───────────────────────────────────────────────────────────────────────

create or replace function public._retorno_log(p_acao text, p_mensagem text, p_nivel text, p_detalhes jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  begin
    perform public.log_app_error('db', left(coalesce(p_mensagem, 'retorno'), 500), 'retorno', p_acao,
                                 coalesce(p_nivel, 'error'), coalesce(p_detalhes, '{}'::jsonb));
  exception when others then
    null;   -- o log falhou: o retorno segue (o item já ficou registrado na própria saída)
  end;
end;
$$;

comment on function public._retorno_log(text, text, text, jsonb) is
  'Retorno F1 (P6): log_app_error(''db'', mensagem, ''retorno'', ação, nível, detalhes) que nunca levanta.';

revoke all on function public._retorno_log(text, text, text, jsonb) from public, anon, authenticated;

-- ── 1. Há saída de texto vencida? (C-VENCIDO) ────────────────────────────────────────────────────────

create or replace function public.retorno_tem_vencido(p_agora timestamptz default now())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select c.modo <> 'desligado' from public.retorno_config c where c.id), false)
     and exists (select 1 from public.retorno_saidas s
                  where s.estado = 'agendada'
                    and s.enviar_em <= coalesce(p_agora, now())
                    and (s.processando_ate is null or s.processando_ate < coalesce(p_agora, now()))
                    and s.tipo not in ('acorde', 'cadastro_provisorio', 'fila'));
$$;

comment on function public.retorno_tem_vencido(timestamptz) is
  'Retorno F1 (C-VENCIDO): há saída de texto agendada e vencida, fora de reserva, com o retorno ligado ou em sombra? O cron só chama a edge retorno-recibos quando sim. Acorde e cadastro provisório o vigia decide no SQL.';

revoke all on function public.retorno_tem_vencido(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_tem_vencido(timestamptz) to service_role;

-- ── 2. O dono respondeu? ─────────────────────────────────────────────────────────────────────────────

create or replace function public._retorno_resposta_humana(p_abertura uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_min integer := coalesce((public._retorno_cfg()).conteudo_min_caracteres, 15);
  v_ab public.retorno_aberturas;
  v_resp timestamptz;
  v_cump timestamptz;
  v_raw jsonb;
  v_tem_conteudo boolean;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found then
    return jsonb_build_object('respondida_em', null, 'cumprida_em', null, 'cumprida_por', null);
  end if;

  -- As saídas humanas à chave depois da abertura, pelas duas horas (a real OU a de gravação), gravadas até
  -- agora. A margem de 10 min em occurred_at só deixa o índice das enviadas por chave cortar a busca: as duas
  -- condições implicam gravação depois da abertura (a gravação nunca vem antes do envio).
  select min(h.real),
         (array_agg(h.real order by h.real, h.occurred_at, h.id) filter (where h.conteudo))[1],
         (array_agg(h.raw_payload order by h.real, h.occurred_at, h.id) filter (where h.conteudo))[1],
         coalesce(bool_or(h.conteudo), false)
    into v_resp, v_cump, v_raw, v_tem_conteudo
    from (select public._retorno_hora_real(o) as real, o.occurred_at, o.id, o.raw_payload,
                 (o.message_type in ('audio', 'document') or length(btrim(coalesce(o.body, ''))) > v_min) as conteudo
            from public.whatsapp_messages o
           where public._agenda_chave_telefone(o.phone_normalized) = v_ab.chave
             and o.direction = 'outbound'
             and o.occurred_at <= v_agora
             and o.occurred_at > least(v_ab.aberta_em, v_ab.gravada_em) - interval '10 minutes'
             and (public._retorno_hora_real(o) > v_ab.aberta_em or o.occurred_at > v_ab.gravada_em)
             and coalesce(o.saida_humana, public._saida_e_humana(o.direction, o.raw_payload, o.sent_by))) h;

  return jsonb_build_object(
    'respondida_em', v_resp,
    'cumprida_em', case when v_tem_conteudo then v_cump end,
    'cumprida_por', case
      when not v_tem_conteudo then null
      when v_raw is null or jsonb_typeof(v_raw) <> 'object' then 'tela'                    -- a caixa do app
      when v_raw ->> 'via' = 'whatsapp-send' and v_raw ->> 'origem' = 'assistente' then 'assistente'
      when v_raw ->> 'origem' = 'tela' then 'tela'
      else 'celular'
    end);
end;
$$;

comment on function public._retorno_resposta_humana(uuid, timestamptz) is
  'Retorno F1 (P6): {respondida_em (1ª saída humana à chave depois da abertura, pela hora real ou pela de gravação), cumprida_em (a 1ª com conteúdo: áudio, documento ou mais de conteudo_min_caracteres), cumprida_por (assistente, tela ou celular)}, só com mensagens gravadas até p_agora. Única fonte do "o dono respondeu".';

revoke all on function public._retorno_resposta_humana(uuid, timestamptz) from public, anon, authenticated;

-- ── 3. Antes de mandar ───────────────────────────────────────────────────────────────────────────────

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
  if v_s.tipo not in ('adiamento', 'fim_do_dia') and v_rh ->> 'respondida_em' is not null then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'respondida_pelo_dono', 'enviar_em', null, 'resposta', v_rh);
  end if;
  if v_s.tipo in ('adiamento', 'fim_do_dia') and v_rh ->> 'cumprida_em' is not null then
    return jsonb_build_object('acao', 'cancelar', 'motivo', 'respondida_pelo_dono', 'enviar_em', null, 'resposta', v_rh);
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

  -- 10.
  return jsonb_build_object('acao', 'seguir', 'motivo', null, 'enviar_em', null);
end;
$$;

comment on function public._retorno_checar_antes(uuid, timestamptz) is
  'Retorno F1 (P6): antes de mandar, {acao: seguir|cancelar|adiar, motivo, enviar_em}: caso_fechado, caso_vencido (adiamento depois do até X, fim do dia fora do dia), respondida_pelo_dono (o aviso honesto só pela resposta de conteúdo), rajada, lote_global, aguarda_transcricao, nivel_nada (pela triagem de novo), atraso_longo, teto_volta. VOLATILE: chama _retorno_triar.';

revoke all on function public._retorno_checar_antes(uuid, timestamptz) from public, anon, authenticated;

-- ── 4. Os efeitos de uma saída decidida no caso ──────────────────────────────────────────────────────

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
end;
$$;

comment on function public._retorno_aplicar_efeitos(uuid, timestamptz) is
  'Retorno F1 (P6): os efeitos de uma saída sombra/enviada/incerta no caso: recibo → recibo_em e a promessa de dados.prazo; mensagem a número novo → coleta_n + 1; adiamento → adiamento_em e segundo_prazo; fim do dia → fim_do_dia_em e vencida; URGENTE → urgente_em. A saudação não promete hora (não grava promessa).';

revoke all on function public._retorno_aplicar_efeitos(uuid, timestamptz) from public, anon, authenticated;

-- ── 5. O contexto do validador (C-VAL) ───────────────────────────────────────────────────────────────

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
      select unnest(array[d ->> 'quando', d ->> 'quando_lista', d ->> 'dia_msg', v_fala]) as x
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
                               d ->> 'de_quando', d ->> 'dia_msg', d ->> 'hora_msg', d ->> 'do_bem', v_fala]) as x
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
    'marcas', jsonb_build_object('tem_proposta', false, 'tem_topo', v_ab.topo_dia is not null,
                                 'cliente_ouviu', false, 'conferida', false));
end;
$$;

comment on function public._retorno_contexto_do_validador(uuid, text, jsonb, timestamptz) is
  'Retorno F1 (P6, C-VAL): o contexto do validador que o banco monta para uma saída composta: datas e horas que o banco pôs, nome permitido, nomes dos clientes do número no ambíguo, textos do cliente (eco), trechos do modelo (o texto cortado nos valores) e as marcas (tem_topo pelo topo_dia do caso).';

revoke all on function public._retorno_contexto_do_validador(uuid, text, jsonb, timestamptz) from public, anon, authenticated;

-- ── 6. Pegar (C-PEGAR) ───────────────────────────────────────────────────────────────────────────────

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

      else
        v_var := null;   -- tipo desconhecido: o _retorno_texto recusa (22023)
      end if;

      if v_nome is not null then
        v_campos := v_campos || jsonb_build_object('nome', v_nome);
      end if;
      v_dados := v_dados || jsonb_strip_nulls(v_campos);

      begin
        v_texto := public._retorno_texto(v_s.tipo, v_var, v_dados);
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

      -- 4. O modo efetivo (P4): o grupo do caso, o URGENTE, a passagem sem acorde e o caso em sombra.
      v_modo := public._retorno_modo_efetivo(v_s.id, v_var, v_dados -> 'prazo', v_agora);
      v_ligado := v_modo ->> 'modo' = 'ligado';
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
      if not coalesce((v_canal ->> 'pode')::boolean, false) then
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

comment on function public.retorno_pegar(timestamptz) is
  'Retorno F1 (C-PEGAR): até 10 voltas; cada uma pega 1 saída de texto devida (FOR UPDATE SKIP LOCKED), confere de novo (_retorno_checar_antes), compõe (prazo, variante, texto fixo), decide o modo efetivo e o canal, aplica os tetos por número e reserva (preparada na sombra, enviando ligada). Devolve {saida_id, tentativa, dedupe_key, tipo, variante, origem, classe, modo, phone, texto, validador} ou nulo. Exceção num item = recusada/erro + app_error_logs, e a volta seguinte segue.';

revoke all on function public.retorno_pegar(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_pegar(timestamptz) to service_role;

-- ── 7. Registrar a decisão (C-DECISAO) ───────────────────────────────────────────────────────────────

create or replace function public.retorno_registrar_decisao(p_saida uuid, p_estado text, p_detalhe jsonb default '{}',
                                                            p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_motivos constant text[] := array['validador', 'canal', 'provedor', 'equipe', 'texto'];
  v_agora timestamptz := coalesce(p_agora, now());
  d jsonb := case when jsonb_typeof(p_detalhe) = 'object' then p_detalhe else '{}'::jsonb end;
  v_s public.retorno_saidas;
  v_cfg public.retorno_config;
  v_final text;
  v_motivo text;
  v_erro boolean := false;
  v_envio jsonb;
begin
  begin
    select * into v_s from public.retorno_saidas s where s.id = p_saida for update;
    if not found then
      return jsonb_build_object('ok', false, 'erro', 'sem_saida');
    end if;
    if v_s.emissor is distinct from 'retorno'
       or p_estado is null
       or (p_estado = 'sombra' and v_s.estado <> 'preparada')
       or (p_estado in ('enviada', 'incerta', 'reagendar') and v_s.estado <> 'enviando')
       or (p_estado = 'recusada' and v_s.estado not in ('preparada', 'enviando')) then
      return jsonb_build_object('ok', false, 'erro', 'estado');
    end if;
    -- o que a edge viu do envio, só códigos (nunca texto do cliente)
    v_envio := jsonb_strip_nulls(jsonb_build_object('http_status', d -> 'http_status', 'codigo', left(d ->> 'codigo', 64),
                                                    'em', v_agora));

    if p_estado = 'sombra' then
      v_final := 'sombra';
      update public.retorno_saidas s
         set estado = 'sombra', validador = nullif(d -> 'validador', 'null'::jsonb), processando_ate = null,
             atualizada_em = now()
       where s.id = v_s.id;

    elsif p_estado = 'enviada' then
      v_final := 'enviada';
      update public.retorno_saidas s
         set estado = 'enviada', enviada_em = v_agora, provider_message_id = left(d ->> 'provider_message_id', 200),
             validador = nullif(d -> 'validador', 'null'::jsonb), processando_ate = null,
             dados = s.dados || jsonb_build_object('envio', v_envio), atualizada_em = now()
       where s.id = v_s.id;
      -- uma enviada zera os erros e desliga o disjuntor por erros (o da conexão é do vigia)
      update public.retorno_config c
         set erros_seguidos = 0,
             so_reativo = case when c.so_reativo_motivo = 'erros' then false else c.so_reativo end,
             so_reativo_desde = case when c.so_reativo_motivo = 'erros' then null else c.so_reativo_desde end,
             so_reativo_motivo = case when c.so_reativo_motivo = 'erros' then null else c.so_reativo_motivo end
       where c.id;

    elsif p_estado = 'incerta' then
      -- FINAL: pode ter saído, e nunca há 2ª tentativa (o vigia só confere a conversa por 30 min).
      v_final := 'incerta';
      v_erro := true;
      update public.retorno_saidas s
         set estado = 'incerta', validador = nullif(d -> 'validador', 'null'::jsonb), processando_ate = null,
             dados = s.dados || jsonb_build_object('envio', v_envio), atualizada_em = now()
       where s.id = v_s.id;

    elsif p_estado = 'recusada' then
      v_final := 'recusada';
      v_motivo := case when d ->> 'motivo' = any (c_motivos) then d ->> 'motivo' else 'erro' end;
      v_erro := v_motivo = 'provedor';
      update public.retorno_saidas s
         set estado = 'recusada', motivo = v_motivo, processando_ate = null,
             validador = case when v_motivo = 'validador'
                              then jsonb_strip_nulls(jsonb_build_object(
                                     'ok', false,
                                     'regras', case when jsonb_typeof(d -> 'regras') = 'array' then d -> 'regras'
                                                    else '[]'::jsonb end,
                                     'codigo', left(d ->> 'codigo', 64)))
                              else nullif(d -> 'validador', 'null'::jsonb) end,
             dados = s.dados || jsonb_build_object('envio', v_envio)
                     || case when v_motivo = 'erro' and d ? 'motivo'
                             then jsonb_build_object('motivo_recebido', left(d ->> 'motivo', 64)) else '{}'::jsonb end,
             atualizada_em = now()
       where s.id = v_s.id;

    elsif p_estado = 'reagendar' then
      -- Só o 503 (a reserva do whatsapp-send não aconteceu): volta com a MESMA chave; acima de 3, recusa.
      if v_s.tentativa >= 3 then
        v_final := 'recusada';
        update public.retorno_saidas s
           set estado = 'recusada', motivo = 'reserva', processando_ate = null,
               dados = s.dados || jsonb_build_object('envio', v_envio), atualizada_em = now()
         where s.id = v_s.id;
      else
        v_final := 'agendada';
        update public.retorno_saidas s
           set estado = 'agendada', enviar_em = v_agora + interval '2 minutes', tentativa = s.tentativa + 1,
               processando_ate = null, decidida_em = null,
               dados = s.dados || jsonb_build_object('envio', v_envio), atualizada_em = now()
         where s.id = v_s.id;
      end if;

    else
      return jsonb_build_object('ok', false, 'erro', 'estado');
    end if;

    -- O disjuntor por erros (B.6): três erros seguidos do envio (incerta ou provedor) → só resposta imediata.
    if v_erro then
      update public.retorno_config c
         set erros_seguidos = least(c.erros_seguidos + 1, 32767)
       where c.id
       returning * into v_cfg;
      if v_cfg.erros_seguidos >= 3 and not v_cfg.so_reativo then
        update public.retorno_config c
           set so_reativo = true, so_reativo_motivo = 'erros', so_reativo_desde = v_agora
         where c.id;
        perform public._retorno_log('disjuntor', 'retorno: so_reativo ligado por erros seguidos do envio', 'warn',
                                    jsonb_build_object('erros_seguidos', v_cfg.erros_seguidos, 'saida', v_s.id));
      end if;
    end if;

    -- Os efeitos no caso (a sombra simula o relógio inteiro; a incerta pode ter saído), num sub-bloco próprio:
    -- o efeito que falha vai ao log e não desfaz a decisão (a saída nunca fica presa voltando à fila).
    if v_final in ('sombra', 'enviada', 'incerta') then
      begin
        perform public._retorno_aplicar_efeitos(v_s.id, v_agora);
      exception when others then
        perform public._retorno_log('decisao', 'retorno_registrar_decisao: efeitos no caso: ' || sqlerrm, 'error',
                                    jsonb_build_object('saida', v_s.id, 'estado', v_final, 'sqlstate', sqlstate));
      end;
    end if;

    return jsonb_build_object('ok', true, 'estado', v_final);
  exception when others then
    perform public._retorno_log('decisao', 'retorno_registrar_decisao: ' || sqlerrm, 'error',
                                jsonb_build_object('saida', p_saida, 'estado', p_estado, 'sqlstate', sqlstate));
    return jsonb_build_object('ok', false, 'erro', sqlstate);
  end;
end;
$$;

comment on function public.retorno_registrar_decisao(uuid, text, jsonb, timestamptz) is
  'Retorno F1 (C-DECISAO): sombra (de preparada), enviada (de enviando; zera os erros e desliga o so_reativo por erros), incerta (de enviando; final), recusada (de preparada ou enviando; motivo validador|canal|provedor|equipe|texto, senão erro), reagendar (de enviando, só o 503: agendada em 2 min, mesma chave; acima de 3 tentativas, recusada/reserva). 3 erros seguidos ligam o so_reativo. Efeitos no caso nos finais sombra/enviada/incerta (o efeito que falha vai ao log e não desfaz a decisão). Estado de partida errado = {"ok": false, "erro": "estado"}.';

revoke all on function public.retorno_registrar_decisao(uuid, text, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_registrar_decisao(uuid, text, jsonb, timestamptz) to service_role;
