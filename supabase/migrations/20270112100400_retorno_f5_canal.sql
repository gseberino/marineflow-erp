-- Retorno rápido ao cliente, F5 (P5): o canal e as saídas do orçamento. Nada liga aqui.
-- Gerada por script (scripts/gerar_f5.cjs canal): as funções novas vêm de scripts/f5_sql/p5_canal.sql, escritas à mão;
-- _retorno_janela, canal_pode_enviar, retorno_pegar, retorno_saida_autorizada e retorno_registrar_decisao são geradas do
-- corpo vigente (o do banco, achado pelo md5 do prosrc), e só os trechos marcados -- F5 são novos.
--
-- 1. _orcamento_modo_efetivo: 'ligado' só com o retorno e o orçamento ligados, a saída nascida ligada (chave sem ':sombra'
--    e, na cadência, o acompanhamento ligado) e mais uma condição por tipo (cadência: nivel sozinho ou dados.por = 'sim';
--    "Fechado": aceite_modo cartao; dados da nota: aceite_modo cartao e dados_nota_ligado). O resto, 'sombra'.
-- 2. _orcamento_checar_antes: a conferência do orcamento_pegar, agora (C-PARAR de novo e o passo à espera desta saída na
--    cadência; o aceite decidido e o dono calado no "Fechado" e nos dados; só na cadência: *segura orcamentos*, a agenda
--    hoje, outra voz do retorno hoje e outra comercial hoje).
-- 3. _orcamento_aplicar_efeitos: o desfecho da saída no passo (tabela de-para da P5.1), a aprovação e a letra do "Mandei
--    sozinho", o encerramento (e o perdido com encerrar_marca_perdido, só com a saída enviada), o "Fechado" (caso cumprido,
--    saida_fechado_id) e os dados da nota (esperando); o que não saiu marca resultado.saida_nao_saiu. Idempotente pela marca
--    dados.efeitos_f5. Quem chama: retorno_registrar_decisao (T-DEC-2), orcamento_pegar (as recusas antes de preparar) e o
--    bloco 8 do orcamento_vigia (a saída que o retorno_vigia decidiu sozinho).
-- 4. _orcamento_pegar_fechar: fecha a saída agendada (recusada ou cancelada) e aplica os efeitos.
-- 5. orcamento_pegar (C-PEGAR-O): a fila do orçamento, no molde do retorno_pegar (até 5 por chamada, cada uma no seu bloco):
--    conferir, o texto (o aprovado no cartão, ou o modelo do banco), o modo efetivo antes do canal (em sombra o canal
--    simula), o canal com a origem retorno_orcamento, a reserva ('enviando' ligada, 'preparada' em sombra, com ':sombra' na
--    chave) e o item com o contexto do validador. Fora da janela com abertura até o prazo: remarca; sem ela: o passo cai.
-- 6. orcamento_saida_autorizada (C-AUT-O): a última trava, no instante do envio (chamada por retorno_saida_autorizada).
-- 7. Gerados: _retorno_janela (a classe comercial), canal_pode_enviar (comercial só com a origem do orçamento, no teto das
--    iniciadas, e só a quem já escreveu), retorno_pegar (não pega o emissor orcamento: risco A-8), retorno_saida_autorizada e
--    retorno_registrar_decisao (o orçamento).
--
-- Com a F5 desligada (orcamento_modo = 'desligado', o padrão), a classe comercial continua classe_nao_suportada no canal e
-- fora da janela, e nenhuma saída do orçamento nasce (o vigia e o aceite estão desligados). As saídas do orçamento que
-- existirem só passam pelo orcamento_pegar.
--
-- Sem dado. Reverter: reaplicar _retorno_janela, canal_pode_enviar, retorno_pegar, retorno_saida_autorizada e
-- retorno_registrar_decisao de 20270105100400_retorno_f4_canal.sql; depois, drop function das funções orcamento_* e
-- _orcamento_* desta migration (o orcamento_vigia da P3 pula o bloco 8 sem _orcamento_aplicar_efeitos).

-- ── 1. O modo efetivo da saída do orçamento ────────────────────────────────────────────────────────────────────────────

create or replace function public._orcamento_modo_efetivo(p_saida uuid, p_agora timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  c_cadencia constant text[] := array['orc_lembrete', 'orc_vespera', 'orc_encerramento'];
  v_cfg public.retorno_config := public._retorno_cfg();
  v_s public.retorno_saidas;
  v_acomp text;
  v_nivel text;
begin
  if v_cfg.id is null then
    return 'sombra';
  end if;
  select * into v_s from public.retorno_saidas s where s.id = p_saida;
  if not found or v_s.emissor is distinct from 'orcamento' then
    return 'sombra';
  end if;
  if v_cfg.modo is distinct from 'ligado' or v_cfg.orcamento_modo is distinct from 'ligado' then
    return 'sombra';
  end if;
  -- A saída que nasceu em sombra (a chave com ':sombra') nunca vai ao cliente: a chave real fica livre para quando ligar.
  if v_s.modo is distinct from 'ligado' or v_s.dedupe_key ~ ':sombra$' then
    return 'sombra';
  end if;
  if v_s.tipo = any (c_cadencia) then
    select a.modo into v_acomp
      from public.orcamento_acompanhamentos a
     where a.id = (case when coalesce(v_s.dados ->> 'acompanhamento_id', '') ~ c_uuid then (v_s.dados ->> 'acompanhamento_id')::uuid end);
    if v_acomp is distinct from 'ligado' then
      return 'sombra';
    end if;
    select t.nivel into v_nivel from public.retorno_modelo_tipos t where t.tipo = v_s.tipo;
    if v_nivel = 'sozinho' or v_s.dados ->> 'por' = 'sim' then
      return 'ligado';
    end if;
    return 'sombra';
  end if;
  if v_s.tipo = 'orc_fechado' then
    return (case when v_cfg.aceite_modo = 'cartao' then 'ligado' else 'sombra' end);
  end if;
  if v_s.tipo = 'orc_dados_nota' then
    return (case when v_cfg.aceite_modo = 'cartao' and coalesce(v_cfg.dados_nota_ligado, false) then 'ligado' else 'sombra' end);
  end if;
  return 'sombra';
end;
$$;

comment on function public._orcamento_modo_efetivo(uuid, timestamptz) is
  'Retorno F5 (P5.1): ''ligado'' ou ''sombra'' da saída do orçamento. Ligado só com retorno_config.modo e orcamento_modo ligados, a saída nascida ligada (modo ligado, chave sem :sombra) e: na cadência, o acompanhamento ligado e nivel sozinho ou dados.por = sim; no orc_fechado, aceite_modo cartao; no orc_dados_nota, aceite_modo cartao e dados_nota_ligado. O resto, sombra.';

revoke all on function public._orcamento_modo_efetivo(uuid, timestamptz) from public, anon, authenticated;

-- ── 2. A conferência do orcamento_pegar ────────────────────────────────────────────────────────────────────────────────

-- {"pode": true} ou {"pode": false, "motivo", "estado": 'cancelada', "passo": 'cancelado' | 'pulado' | nulo}. O passo diz o
-- que a tabela de-para da P5.1 faz com o passo da cadência: a parada o cancela, a conferência o pula, e a saída que não é
-- mais a do passo (o refeito) não mexe nele.
create or replace function public._orcamento_checar_antes(p_saida uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  c_cadencia constant text[] := array['orc_lembrete', 'orc_vespera', 'orc_encerramento'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_desde timestamptz;
  v_ate timestamptz;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_s public.retorno_saidas;
  v_a public.orcamento_acompanhamentos;
  v_p public.orcamento_passos;
  v_ac public.orcamento_aceites;
  v_m jsonb;
begin
  select * into v_s from public.retorno_saidas s where s.id = p_saida;
  if not found or v_s.emissor is distinct from 'orcamento' then
    return jsonb_build_object('pode', false, 'motivo', 'erro', 'estado', 'cancelada', 'passo', null);
  end if;
  v_desde := v_hoje::timestamp at time zone c_fuso;
  v_ate := (v_hoje + 1)::timestamp at time zone c_fuso;

  if v_s.tipo = any (c_cadencia) then
    -- 0. A F5 desligada (ou sem a linha de configuração): a cadência não sai.
    if v_cfg.id is null or v_cfg.orcamento_modo is null or v_cfg.orcamento_modo = 'desligado' then
      return jsonb_build_object('pode', false, 'motivo', 'orcamento_desligado', 'estado', 'cancelada', 'passo', 'pulado');
    end if;
    -- 1. O acompanhamento ainda ativo (C-PARAR de novo, agora) e o passo à espera desta saída.
    select * into v_a
      from public.orcamento_acompanhamentos a
     where a.id = (case when coalesce(v_s.dados ->> 'acompanhamento_id', '') ~ c_uuid then (v_s.dados ->> 'acompanhamento_id')::uuid end);
    if not found then
      return jsonb_build_object('pode', false, 'motivo', 'erro', 'estado', 'cancelada', 'passo', 'cancelado');
    end if;
    v_m := public._orcamento_parar_motivo(v_a.id, v_agora);
    if v_m is not null then
      return jsonb_build_object('pode', false, 'motivo', coalesce(v_m ->> 'motivo', 'erro'), 'estado', 'cancelada', 'passo', 'cancelado');
    end if;
    if v_a.estado is distinct from 'ativo' then
      return jsonb_build_object('pode', false, 'motivo', coalesce(v_a.parou_por, 'status_mudou'), 'estado', 'cancelada', 'passo', 'cancelado');
    end if;
    select * into v_p
      from public.orcamento_passos p
     where p.id = (case when coalesce(v_s.dados ->> 'passo_id', '') ~ c_uuid then (v_s.dados ->> 'passo_id')::uuid end);
    if not found or v_p.saida_id is distinct from v_s.id or v_p.estado is distinct from 'agendado' then
      return jsonb_build_object('pode', false, 'motivo', 'substituida', 'estado', 'cancelada', 'passo', null);
    end if;

    -- 2. Só na cadência (o "Fechado" e os dados respondem ao cliente e foram aprovados com *sim <PIN>*).
    if coalesce(v_cfg.orcamento_segura, false) then
      return jsonb_build_object('pode', false, 'motivo', 'segurado', 'estado', 'cancelada', 'passo', 'pulado');
    end if;
    -- A agenda falou ou vai falar com este cliente hoje.
    if exists (select 1 from public.agenda_cliente_mensagens m
                where m.client_id = v_s.client_id
                  and m.criada_em <= v_agora
                  and ((m.enviada_em >= v_desde and m.enviada_em < v_ate and m.enviada_em <= v_agora)
                       or (m.estado in ('aguardando_dono', 'enfileirada') and m.enviar_em >= v_desde and m.enviar_em < v_ate)
                       or (m.estado = 'registrada' and m.modo = 'ligado' and m.enviar_em >= v_desde and m.enviar_em < v_ate))) then
      return jsonb_build_object('pode', false, 'motivo', 'agenda_hoje', 'estado', 'cancelada', 'passo', 'pulado');
    end if;
    -- Outra voz do retorno falou ou vai falar com a chave hoje: o aviso da F4 ou o modelo da F2/F3.
    if exists (select 1 from public.retorno_saidas o
                where o.chave = v_s.chave and o.id <> v_s.id
                  and (o.classe = 'aviso' or o.origem = 'retorno_modelo')
                  and o.criada_em <= v_agora
                  and ((o.estado in ('enviada', 'incerta', 'enviando')
                        and coalesce(o.enviada_em, o.decidida_em) >= v_desde and coalesce(o.enviada_em, o.decidida_em) <= v_agora)
                       or (o.estado = 'agendada' and o.enviar_em >= v_desde and o.enviar_em < v_ate))) then
      return jsonb_build_object('pode', false, 'motivo', 'outra_voz_hoje', 'estado', 'cancelada', 'passo', 'pulado');
    end if;
    -- Outra comercial já foi à mesma chave hoje.
    if exists (select 1 from public.retorno_saidas o
                where o.chave = v_s.chave and o.id <> v_s.id and o.classe = 'comercial'
                  and o.estado in ('enviada', 'incerta', 'enviando')
                  and coalesce(o.enviada_em, o.decidida_em) >= v_desde and coalesce(o.enviada_em, o.decidida_em) <= v_agora) then
      return jsonb_build_object('pode', false, 'motivo', 'comercial_hoje', 'estado', 'cancelada', 'passo', 'pulado');
    end if;
    return jsonb_build_object('pode', true);
  end if;

  if v_s.tipo in ('orc_fechado', 'orc_dados_nota') then
    -- O aceite segue decidido, e o dono não escreveu à chave depois da decisão (com ou sem caso: a chave do aceite).
    select * into v_ac
      from public.orcamento_aceites a
     where a.id = (case when coalesce(v_s.dados ->> 'aceite_id', '') ~ c_uuid then (v_s.dados ->> 'aceite_id')::uuid end);
    if not found or v_ac.estado not in ('com_sinal', 'sem_sinal') then
      return jsonb_build_object('pode', false, 'motivo', 'aceite_mudou', 'estado', 'cancelada', 'passo', null);
    end if;
    if exists (select 1 from public.whatsapp_messages o
                where o.direction = 'outbound'
                  and public._agenda_chave_telefone(o.phone_normalized) = v_ac.chave
                  and o.occurred_at > coalesce(v_ac.decidido_em, v_ac.criado_em) - interval '1 day'
                  and o.occurred_at <= v_agora
                  and coalesce(o.hora_real, o.occurred_at) > coalesce(v_ac.decidido_em, v_ac.criado_em)
                  and coalesce(o.hora_real, o.occurred_at) <= v_agora
                  and coalesce(o.saida_humana, public._saida_e_humana(o.direction, o.raw_payload, o.sent_by))) then
      return jsonb_build_object('pode', false, 'motivo', 'aceite_mudou', 'estado', 'cancelada', 'passo', null);
    end if;
    return jsonb_build_object('pode', true);
  end if;

  return jsonb_build_object('pode', false, 'motivo', 'erro', 'estado', 'cancelada', 'passo', null);
end;
$$;

comment on function public._orcamento_checar_antes(uuid, timestamptz) is
  'Retorno F5 (P5.1): a conferência do orcamento_pegar, agora. Cadência: orcamento_modo fora de desligado (senão orcamento_desligado), o acompanhamento ativo (_orcamento_parar_motivo de novo: o motivo da parada), o passo agendado com esta saída (senão substituida), e só nela: orcamento_segura (segurado), a agenda hoje (agenda_hoje), o aviso da F4 ou o modelo da F2/F3 à chave hoje (outra_voz_hoje), outra comercial enviada hoje (comercial_hoje). "Fechado" e dados: o aceite com_sinal ou sem_sinal e nenhuma saída humana à chave depois da decisão (senão aceite_mudou). {pode, motivo, estado, passo}.';

revoke all on function public._orcamento_checar_antes(uuid, timestamptz) from public, anon, authenticated;

-- ── 3. Os efeitos da saída do orçamento ────────────────────────────────────────────────────────────────────────────────

-- A tabela de-para da P5.1, do lado do passo: enviada ou incerta → enviado (nunca se repete); sombra → sombra; recusada →
-- pulado com o motivo; cancelada → o que a conferência disse (dados.passo_estado) ou, sem isso, cancelado nas paradas e pulado
-- no resto. O motivo do passo é o da saída, se estiver na lista do passo; senão 'canal'. Só o passo cuja saída é esta e que
-- ainda está agendado muda (o refeito, ou o que o vigia já cancelou, fica como está).
create or replace function public._orcamento_aplicar_efeitos(p_saida uuid, p_agora timestamptz)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  c_cadencia constant text[] := array['orc_lembrete', 'orc_vespera', 'orc_encerramento'];
  c_paradas constant text[] := array['cliente_escreveu', 'encerrou', 'parar', 'opt_out', 'dono_falou', 'segurado', 'status_mudou',
                                     'validade_mudou', 'erro'];
  c_do_passo constant text[] := array['sem_sim', 'agenda_hoje', 'outra_voz_hoje', 'comercial_hoje', 'segurado', 'orcamento_desligado',
                                      'teto_iniciadas', 'sem_conversa', 'so_reativo', 'segura_tudo', 'pessoal', 'equipe', 'opt_out',
                                      'bloqueado', 'classe_nao_suportada', 'provedor', 'fora_da_janela', 'espacamento', 'texto',
                                      'sem_nome', 'validador', 'canal', 'parou', 'erro', 'tirado'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_s public.retorno_saidas;
  v_p public.orcamento_passos;
  v_a public.orcamento_acompanhamentos;
  v_ac public.orcamento_aceites;
  v_motivo text;
  v_por text;
  v_estado_passo text;
  v_em timestamptz;
  v_envios integer;
begin
  select * into v_s from public.retorno_saidas s where s.id = p_saida for update;
  if not found or v_s.emissor is distinct from 'orcamento' or v_s.estado in ('agendada', 'preparada', 'enviando')
     or v_s.dados ? 'efeitos_f5' then
    return;
  end if;
  v_motivo := coalesce(v_s.motivo, 'erro');
  v_por := v_s.dados ->> 'por';
  v_em := coalesce(v_s.enviada_em, v_s.decidida_em, v_agora);

  if v_s.tipo = any (c_cadencia) then
    -- O passo.
    select * into v_p
      from public.orcamento_passos p
     where p.id = (case when coalesce(v_s.dados ->> 'passo_id', '') ~ c_uuid then (v_s.dados ->> 'passo_id')::uuid end)
     for update;
    if found and v_p.saida_id = v_s.id and v_p.estado = 'agendado' then
      v_estado_passo := (case when v_s.estado in ('enviada', 'incerta') then 'enviado'
                              when v_s.estado = 'sombra' then 'sombra'
                              when v_s.estado = 'recusada' then 'pulado'
                              when v_s.dados ->> 'passo_estado' in ('pulado', 'cancelado') then v_s.dados ->> 'passo_estado'
                              when v_motivo = any (c_paradas) then 'cancelado'
                              else 'pulado' end);
      update public.orcamento_passos p
         set estado = v_estado_passo,
             motivo = (case when v_estado_passo = 'pulado' then (case when v_motivo = any (c_do_passo) then v_motivo else 'canal' end)
                            else p.motivo end)
       where p.id = v_p.id and p.estado = 'agendado';
    end if;

    -- A aprovação conta só com a saída enviada (como na F2); o sozinho ganha a letra do "Mandei sozinho" (Z a V).
    if v_s.estado = 'enviada' and v_por = 'sim' then
      perform public._retorno_contar_aprovacao(v_s.tipo, v_em);
    end if;
    if v_s.estado in ('enviada', 'incerta') and v_por = 'sozinho' then
      update public.retorno_modelo_tipos t
         set envios_sozinho = t.envios_sozinho + 1, atualizado_em = now()
       where t.tipo = v_s.tipo
       returning t.envios_sozinho into v_envios;
      perform public._retorno_gravar_letra(v_s.id, v_em, v_envios);
    end if;

    -- O encerramento que saiu (ou que pode ter saído, ou a sombra dele) encerra o acompanhamento; só o enviado marca perdido,
    -- e só com encerrar_marca_perdido (dúvida 1). A incerta nunca marca perdido (pode não ter saído).
    if v_s.tipo = 'orc_encerramento' and v_s.estado in ('enviada', 'incerta', 'sombra') then
      update public.orcamento_acompanhamentos a
         set estado = 'encerrado', encerramento = (case when v_s.estado = 'sombra' then 'sombra' else 'enviado' end),
             desfecho_proposto = coalesce(a.desfecho_proposto, 'sumiu'), atualizado_em = now()
       where a.id = (case when coalesce(v_s.dados ->> 'acompanhamento_id', '') ~ c_uuid then (v_s.dados ->> 'acompanhamento_id')::uuid end)
         and a.estado in ('ativo', 'parado')
       returning * into v_a;
      if found and v_s.estado = 'enviada' and coalesce(v_cfg.encerrar_marca_perdido, false) then
        begin
          perform public.orcamento_marcar_perdido(v_a.service_order_id, 'sumiu', 'cadencia', null, null, v_agora);
        exception when undefined_function then
          perform public._retorno_log('orcamento_efeitos', 'orcamento_marcar_perdido ausente: o encerramento não marcou perdido', 'warn',
                                      jsonb_build_object('saida', v_s.id));
        end;
      end if;
    end if;

  elsif v_s.tipo in ('orc_fechado', 'orc_dados_nota') then
    select * into v_ac
      from public.orcamento_aceites a
     where a.id = (case when coalesce(v_s.dados ->> 'aceite_id', '') ~ c_uuid then (v_s.dados ->> 'aceite_id')::uuid end)
     for update;
    if found then
      if v_s.tipo = 'orc_fechado' and v_s.estado in ('enviada', 'incerta') then
        -- O "Fechado" saiu (ou pode ter saído): o caso do aceite, quando há, fica cumprido.
        update public.orcamento_aceites a
           set saida_fechado_id = v_s.id,
               resultado = (case when v_s.estado = 'incerta' and not (a.resultado ? 'saida_nao_saiu')
                                 then a.resultado || jsonb_build_object('saida_nao_saiu', 'incerta', 'saida_nao_saiu_tipo', v_s.tipo)
                                 else a.resultado end)
         where a.id = v_ac.id;
        if v_ac.abertura_id is not null then
          update public.retorno_aberturas a
             set cumprida_em = v_agora, cumprida_por = 'cartao', atualizada_em = now()
           where a.id = v_ac.abertura_id and a.cumprida_em is null;
        end if;
      elsif v_s.tipo = 'orc_dados_nota' and v_s.estado in ('enviada', 'incerta') then
        -- O pedido saiu (ou pode ter saído): o detector espera a resposta. Em sombra, mede-se só o pedido.
        update public.orcamento_aceites a
           set dados_estado = 'esperando', saida_dados_id = v_s.id
         where a.id = v_ac.id and a.dados_estado is null;
      elsif v_s.tipo = 'orc_dados_nota' and v_s.estado = 'cancelada' and v_s.motivo = 'fato_mudou' then
        -- Nada mais a pedir (o cadastro foi completado antes de sair): não é falha.
        update public.orcamento_aceites a set dados_estado = 'nada' where a.id = v_ac.id and a.dados_estado is null;
      elsif v_s.estado in ('recusada', 'cancelada') then
        -- Não saiu: o aceite (já decidido) volta uma vez ao cartão e aparece no fechamento.
        update public.orcamento_aceites a
           set resultado = a.resultado || jsonb_build_object('saida_nao_saiu', v_motivo, 'saida_nao_saiu_tipo', v_s.tipo)
         where a.id = v_ac.id and not (a.resultado ? 'saida_nao_saiu');
      end if;
    end if;
  end if;

  update public.retorno_saidas s
     set dados = s.dados || jsonb_build_object('efeitos_f5', v_agora), atualizada_em = now()
   where s.id = v_s.id;
end;
$$;

comment on function public._orcamento_aplicar_efeitos(uuid, timestamptz) is
  'Retorno F5 (P5.1): os efeitos da saída do orçamento decidida (nada em agendada, preparada e enviando; idempotente pela marca dados.efeitos_f5). Passo agendado desta saída: enviada/incerta → enviado, sombra → sombra, recusada → pulado, cancelada → dados.passo_estado ou (paradas) cancelado ou pulado; motivo da lista do passo ou canal. Enviada com por = sim → _retorno_contar_aprovacao; enviada/incerta com por = sozinho → envios_sozinho e _retorno_gravar_letra. Encerramento enviado/incerto/sombra → acompanhamento encerrado (enviado ou sombra, sumiu proposto); só enviado e encerrar_marca_perdido → orcamento_marcar_perdido(sumiu, cadencia). orc_fechado enviado/incerto → saida_fechado_id e o caso cumprido (cartao); incerto → saida_nao_saiu = incerta. orc_dados_nota enviado/incerto → dados_estado esperando; cancelado por fato_mudou → nada. Fechado ou dados recusados/cancelados → resultado.saida_nao_saiu = motivo (e saida_nao_saiu_tipo).';

revoke all on function public._orcamento_aplicar_efeitos(uuid, timestamptz) from public, anon, authenticated;

-- ── 4. Fechar a saída antes de preparar ────────────────────────────────────────────────────────────────────────────────

-- O retorno_registrar_decisao só aceita recusada em saída preparada ou enviando: a agendada que cai na conferência, no texto
-- ou no canal é fechada aqui (como o retorno_pegar faz), e os efeitos rodam na hora. Efeito que falha vai ao log, e o bloco 8
-- do vigia tenta de novo (a marca efeitos_f5 só entra quando ele roda inteiro).
create or replace function public._orcamento_pegar_fechar(p_saida uuid, p_estado text, p_motivo text, p_dados jsonb, p_agora timestamptz)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if p_estado is null or p_estado not in ('recusada', 'cancelada') then
    raise exception using errcode = '22023', message = '_orcamento_pegar_fechar: estado fora da lista (recusada, cancelada)';
  end if;
  update public.retorno_saidas s
     set estado = p_estado, motivo = coalesce(p_motivo, 'erro'), decidida_em = p_agora, processando_ate = null,
         dados = s.dados || (case when jsonb_typeof(p_dados) = 'object' then p_dados else '{}'::jsonb end),
         atualizada_em = now()
   where s.id = p_saida and s.estado = 'agendada';
  if found then
    begin
      perform public._orcamento_aplicar_efeitos(p_saida, p_agora);
    exception when others then
      perform public._retorno_log('orcamento_pegar', 'efeitos: ' || sqlerrm, 'error',
                                  jsonb_build_object('saida', p_saida, 'sqlstate', sqlstate));
    end;
  end if;
end;
$$;

comment on function public._orcamento_pegar_fechar(uuid, text, text, jsonb, timestamptz) is
  'Retorno F5 (P5.1): fecha a saída do orçamento ainda agendada (recusada ou cancelada) com o motivo, a hora da decisão e os dados, e roda _orcamento_aplicar_efeitos (o efeito que falha vai ao log).';

revoke all on function public._orcamento_pegar_fechar(uuid, text, text, jsonb, timestamptz) from public, anon, authenticated;

-- ── 5. A fila do orçamento (C-PEGAR-O) ─────────────────────────────────────────────────────────────────────────────────

-- Até 5 voltas, cada uma com 1 saída devida do emissor 'orcamento', FOR UPDATE SKIP LOCKED, na ordem enviar_em, id; cada
-- volta no seu begin … exception (o item que dá exceção vira recusada/erro, vai ao log e o próximo segue). Nenhuma saída fica
-- agendada com enviar_em no passado depois de uma chamada: ou sai, ou cai, ou é remarcada para depois de agora.
create or replace function public.orcamento_pegar(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  c_cadencia constant text[] := array['orc_lembrete', 'orc_vespera', 'orc_encerramento'];
  c_canal constant text[] := array['teto_iniciadas', 'sem_conversa', 'so_reativo', 'segura_tudo', 'pessoal', 'equipe', 'opt_out',
                                   'bloqueado', 'classe_nao_suportada', 'provedor'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_cfg public.retorno_config;
  v_volta integer;
  v_s public.retorno_saidas;
  v_ch jsonb;
  v_os uuid;
  v_validade date;
  v_ate date;
  v_dia date;
  v_k integer;
  v_dados jsonb;
  v_var text;
  v_texto text;
  v_ligado boolean;
  v_canal jsonb;
  v_motivo text;
  v_em timestamptz;
  v_ctx jsonb;
begin
  v_cfg := public._retorno_cfg();
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return null;
  end if;

  for v_volta in 1 .. 5 loop
    select * into v_s
      from public.retorno_saidas s
     where s.emissor = 'orcamento'
       and s.estado = 'agendada'
       and s.enviar_em <= v_agora
       and (s.processando_ate is null or s.processando_ate < v_agora)
     order by s.enviar_em, s.id
     limit 1
     for update skip locked;
    if not found then
      return null;
    end if;

    begin
      -- 1. Conferir de novo, agora.
      v_ch := public._orcamento_checar_antes(v_s.id, v_agora);
      if not coalesce((v_ch ->> 'pode')::boolean, false) then
        perform public._orcamento_pegar_fechar(v_s.id, coalesce(v_ch ->> 'estado', 'cancelada'), coalesce(v_ch ->> 'motivo', 'erro'),
                                               jsonb_strip_nulls(jsonb_build_object('passo_estado', v_ch ->> 'passo')), v_agora);
        continue;
      end if;

      -- 2. O texto: o aprovado no cartão (dados.por = sim, a cadência), ou o modelo do banco. Os campos vêm do banco.
      v_os := (case when coalesce(v_s.dados ->> 'os_id', '') ~ c_uuid then (v_s.dados ->> 'os_id')::uuid end);
      v_dados := v_s.dados || jsonb_strip_nulls(jsonb_build_object('nome', public._retorno_nome(v_s.client_id),
                                                                   'do_servico', public._orcamento_do_servico(v_os)));
      if v_s.tipo = 'orc_vespera' then
        select a.validade_ate into v_validade
          from public.orcamento_acompanhamentos a
         where a.id = (case when coalesce(v_s.dados ->> 'acompanhamento_id', '') ~ c_uuid then (v_s.dados ->> 'acompanhamento_id')::uuid end);
        v_dados := v_dados || jsonb_strip_nulls(jsonb_build_object('validade', public._orcamento_validade_texto(v_validade, v_hoje)));
      end if;
      if v_s.tipo = 'orc_dados_nota' then
        -- O que falta agora (o cadastro pode ter sido completado depois do *sim*): nada a pedir = a saída cai sem falha.
        v_dados := v_dados || jsonb_build_object('faltas', to_jsonb(coalesce(public._orcamento_faltas_para_nota(v_s.client_id), '{}'::text[])));
      end if;

      if v_s.tipo = any (c_cadencia) and v_s.dados ->> 'por' = 'sim' then
        v_var := 'aprovado';
        v_texto := nullif(btrim(coalesce(v_s.dados ->> 'texto_aprovado', '')), '');
        if v_texto is null then
          perform public._orcamento_pegar_fechar(v_s.id, 'recusada', 'texto', jsonb_build_object('texto_erro', 'sem o texto aprovado'), v_agora);
          continue;
        end if;
      else
        v_var := public._orcamento_variante(v_s.tipo, v_os, v_s.client_id, v_s.chave, v_hoje, v_dados);
        if v_var = 'sem_nome' then
          perform public._orcamento_pegar_fechar(v_s.id, 'recusada', 'sem_nome', jsonb_build_object('variante', 'sem_nome'), v_agora);
          continue;
        end if;
        if v_var is null then
          perform public._orcamento_pegar_fechar(v_s.id, 'cancelada', 'fato_mudou', jsonb_build_object('faltas', v_dados -> 'faltas'), v_agora);
          continue;
        end if;
        begin
          v_texto := public._orcamento_texto(v_s.tipo, v_var, v_dados);
        exception when sqlstate '22023' then
          perform public._orcamento_pegar_fechar(v_s.id, 'recusada', 'texto',
                                                 jsonb_build_object('variante', left(v_var, 40), 'texto_erro', left(sqlerrm, 200)), v_agora);
          continue;
        end;
      end if;

      -- 3. O modo efetivo, antes do canal: em sombra o canal simula (não conta a saída que não vai sair, nem espera).
      v_ligado := public._orcamento_modo_efetivo(v_s.id, v_agora) = 'ligado';

      -- 4. O canal. Ligada, trava antes a linha de configuração (a 2ª execução simultânea vê o espaçamento e o teto da 1ª).
      if v_ligado then
        perform 1 from public.retorno_config c where c.id for update;
      end if;
      v_canal := public.canal_pode_enviar(v_s.phone_normalized, v_s.classe, 'retorno_orcamento', v_agora, not v_ligado, v_s.tipo);
      if not coalesce((v_canal ->> 'pode')::boolean, false) then
        v_motivo := coalesce(v_canal ->> 'motivo', 'canal');
        v_em := nullif(v_canal ->> 'enviar_em', '')::timestamptz;
        if v_motivo in ('fora_da_janela', 'espacamento') then
          if v_s.tipo = any (c_cadencia) then
            select p.ate into v_ate
              from public.orcamento_passos p
             where p.id = (case when coalesce(v_s.dados ->> 'passo_id', '') ~ c_uuid then (v_s.dados ->> 'passo_id')::uuid end);
            -- Sem abertura hoje: o cadencia_hora do próximo dia comercial, se ainda cabe no prazo do passo.
            if v_em is null and v_ate is not null then
              v_dia := v_hoje + 1;
              v_k := 0;
              while v_dia <= v_ate and v_k < 60 loop
                v_k := v_k + 1;
                if extract(isodow from v_dia) between 1 and 5 and coalesce(public.agenda_dia_util(v_dia), false) then
                  v_em := (v_dia + v_cfg.cadencia_hora) at time zone c_fuso;
                  exit;
                end if;
                v_dia := v_dia + 1;
              end loop;
            end if;
            if v_em is not null and v_em > v_agora and v_ate is not null and (v_em at time zone c_fuso)::date <= v_ate then
              update public.retorno_saidas s
                 set enviar_em = v_em,
                     dados = s.dados || jsonb_build_object('adiada', jsonb_build_object('motivo', v_motivo, 'em', v_agora)),
                     atualizada_em = now()
               where s.id = v_s.id;
              continue;
            end if;
            perform public._orcamento_pegar_fechar(v_s.id, 'cancelada', v_motivo, jsonb_build_object('passo_estado', 'pulado'), v_agora);
            continue;
          end if;
          -- O "Fechado" e os dados (resposta_imediata): a abertura que o canal devolveu (a manhã seguinte, fora das 07–22).
          if v_em is not null and v_em > v_agora then
            update public.retorno_saidas s
               set enviar_em = v_em,
                   dados = s.dados || jsonb_build_object('adiada', jsonb_build_object('motivo', v_motivo, 'em', v_agora)),
                   atualizada_em = now()
             where s.id = v_s.id;
            continue;
          end if;
          perform public._orcamento_pegar_fechar(v_s.id, 'cancelada', v_motivo, null, v_agora);
          continue;
        end if;
        perform public._orcamento_pegar_fechar(v_s.id, 'recusada', (case when v_motivo = any (c_canal) then v_motivo else 'canal' end),
                                               jsonb_build_object('variante', left(v_var, 40), 'canal', v_motivo), v_agora);
        continue;
      end if;

      -- 5. A reserva: ligada sai 'enviando' (o que orcamento_saida_autorizada e retorno_registrar_decisao exigem para enviada
      --    e incerta); em sombra, 'preparada', e a chave ganha ':sombra' (a real fica livre).
      update public.retorno_saidas s
         set estado = (case when v_ligado then 'enviando' else 'preparada' end),
             texto = v_texto, dados = v_dados, variante = left(v_var, 40), decidida_em = v_agora,
             processando_ate = v_agora + interval '2 minutes',
             modo = (case when v_ligado then 'ligado' else 'sombra' end),
             dedupe_key = (case when v_ligado or s.dedupe_key like '%:sombra' then s.dedupe_key else s.dedupe_key || ':sombra' end),
             atualizada_em = now()
       where s.id = v_s.id
       returning * into v_s;
      if v_ligado then
        -- o espaçamento global entre saídas automáticas, sorteado (o mesmo do retorno_pegar)
        update public.retorno_config c
           set proximo_envio_em = v_agora + make_interval(secs => (c.espaco_min_s
                                    + floor(random() * (c.espaco_max_s - c.espaco_min_s + 1)))::double precision)
         where c.id;
      end if;

      -- 6. O item, no formato do retorno_pegar, com o contexto do validador montado pelo banco.
      v_ctx := public._orcamento_contexto_do_validador(v_s.id, v_texto, v_dados, v_agora);
      return jsonb_build_object(
        'saida_id', v_s.id,
        'tentativa', v_s.tentativa,
        'dedupe_key', v_s.dedupe_key,
        'tipo', v_s.tipo,
        'variante', v_s.variante,
        'origem', 'retorno_orcamento',
        'classe', v_s.classe,
        'modo', v_s.modo,
        'phone', v_s.phone_normalized,
        'texto', v_s.texto,
        'validador', v_ctx);
    exception when others then
      -- Erro num item nunca trava a fila: a volta é desfeita, a saída vira recusada/erro e a próxima segue.
      update public.retorno_saidas s
         set estado = 'recusada', motivo = 'erro', decidida_em = v_agora, processando_ate = null,
             dados = s.dados || jsonb_build_object('erro', jsonb_build_object('sqlstate', sqlstate, 'mensagem', left(sqlerrm, 200))),
             atualizada_em = now()
       where s.id = v_s.id and s.estado = 'agendada';
      perform public._retorno_log('orcamento_pegar', 'orcamento_pegar: ' || sqlerrm, 'error',
                                  jsonb_build_object('saida', v_s.id, 'sqlstate', sqlstate));
      begin
        perform public._orcamento_aplicar_efeitos(v_s.id, v_agora);
      exception when others then
        perform public._retorno_log('orcamento_pegar', 'efeitos: ' || sqlerrm, 'error',
                                    jsonb_build_object('saida', v_s.id, 'sqlstate', sqlstate));
      end;
    end;
  end loop;
  return null;
end;
$$;

comment on function public.orcamento_pegar(timestamptz) is
  'Retorno F5 (P5.1, C-PEGAR-O): até 5 saídas do emissor orcamento por chamada, agendadas e devidas, FOR UPDATE SKIP LOCKED, na ordem enviar_em, id. _orcamento_checar_antes; o texto (dados.texto_aprovado com por = sim; senão _orcamento_texto da variante, com nome, do_servico, validade e faltas do banco; sem_nome, texto, ou nada a pedir nos dados = fato_mudou); o modo efetivo antes do canal; canal_pode_enviar(classe da saída, retorno_orcamento, p_simular = not ligado), com a trava da configuração quando ligada; fora_da_janela/espacamento com abertura até o prazo do passo (ou, no Fechado e nos dados, com enviar_em) remarca, sem ela cai; os outros motivos do canal recusam (fora da lista: canal). A reserva: enviando (ligada) ou preparada (sombra, com :sombra na chave), processando_ate = agora + 2 min, e o espaçamento global quando ligada. Devolve o item no formato de retorno_pegar (origem retorno_orcamento, validador de _orcamento_contexto_do_validador) ou nulo. Retorno desligado: nulo.';

revoke all on function public.orcamento_pegar(timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_pegar(timestamptz) to service_role;

-- ── 6. A última trava (C-AUT-O) ────────────────────────────────────────────────────────────────────────────────────────

create or replace function public.orcamento_saida_autorizada(p_saida uuid, p_fone text, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  c_cadencia constant text[] := array['orc_lembrete', 'orc_vespera', 'orc_encerramento'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_s public.retorno_saidas;
  v_a public.orcamento_acompanhamentos;
  v_m jsonb;
  v_quote text;
  v_aceite text;
  v_bloqueio text;
  v_janela jsonb;
begin
  begin
    select * into v_s from public.retorno_saidas s where s.id = p_saida;
    if not found then
      return jsonb_build_object('pode', false, 'motivo', 'sem_saida');
    end if;
    if v_s.emissor is distinct from 'orcamento' then
      return jsonb_build_object('pode', false, 'motivo', 'emissor');
    end if;
    -- A reserva do orcamento_pegar: enviando, ligada e de pé.
    if v_s.estado is distinct from 'enviando' then
      return jsonb_build_object('pode', false, 'motivo', 'estado');
    end if;
    if v_s.modo is distinct from 'ligado' then
      return jsonb_build_object('pode', false, 'motivo', 'saida_em_sombra');
    end if;
    if v_s.processando_ate is null or v_s.processando_ate <= v_agora then
      return jsonb_build_object('pode', false, 'motivo', 'reserva_vencida');
    end if;
    -- O destino é o telefone da saída (8 dígitos e o mesmo DDD).
    if not coalesce(public._mesmo_telefone(p_fone, v_s.phone_normalized), false) then
      return jsonb_build_object('pode', false, 'motivo', 'telefone');
    end if;
    if public._orcamento_modo_efetivo(v_s.id, v_agora) is distinct from 'ligado' then
      return jsonb_build_object('pode', false, 'motivo', 'modo');
    end if;
    if v_s.tipo = any (c_cadencia) then
      -- A cadência: o acompanhamento segue ativo e o funil segue aberto.
      select * into v_a
        from public.orcamento_acompanhamentos a
       where a.id = (case when coalesce(v_s.dados ->> 'acompanhamento_id', '') ~ c_uuid then (v_s.dados ->> 'acompanhamento_id')::uuid end);
      if not found then
        return jsonb_build_object('pode', false, 'motivo', 'erro');
      end if;
      v_m := public._orcamento_parar_motivo(v_a.id, v_agora);
      if v_m is not null then
        return jsonb_build_object('pode', false, 'motivo', coalesce(v_m ->> 'motivo', 'erro'));
      end if;
      if v_a.estado is distinct from 'ativo' then
        return jsonb_build_object('pode', false, 'motivo', coalesce(v_a.parou_por, 'status_mudou'));
      end if;
      select so.quote_status into v_quote from public.service_orders so where so.id = v_a.service_order_id;
      if v_quote is null or v_quote not in ('sent', 'awaiting_approval') then
        return jsonb_build_object('pode', false, 'motivo', 'status_mudou');
      end if;
    elsif v_s.tipo in ('orc_fechado', 'orc_dados_nota') then
      select a.estado into v_aceite
        from public.orcamento_aceites a
       where a.id = (case when coalesce(v_s.dados ->> 'aceite_id', '') ~ c_uuid then (v_s.dados ->> 'aceite_id')::uuid end);
      if v_aceite is null or v_aceite not in ('com_sinal', 'sem_sinal') then
        return jsonb_build_object('pode', false, 'motivo', 'aceite_mudou');
      end if;
    else
      return jsonb_build_object('pode', false, 'motivo', 'erro');
    end if;
    -- O bloqueio (o PARAR, o opt-out, o cliente final).
    v_bloqueio := public.canal_bloqueado(p_fone);
    if v_bloqueio is not null then
      return jsonb_build_object('pode', false, 'motivo', v_bloqueio);
    end if;
    -- A janela da classe.
    v_janela := public._retorno_janela(v_s.classe, v_agora, v_s.chave);
    if not coalesce((v_janela ->> 'dentro')::boolean, false) then
      return jsonb_build_object('pode', false, 'motivo', 'fora_da_janela');
    end if;
    return jsonb_build_object('pode', true, 'motivo', null);
  exception when others then
    -- Na dúvida, não manda.
    return jsonb_build_object('pode', false, 'motivo', 'erro');
  end;
end;
$$;

comment on function public.orcamento_saida_autorizada(uuid, text, timestamptz) is
  'Retorno F5 (P5.1, C-AUT-O): a última trava da saída do orçamento, no instante do envio (chamada por retorno_saida_autorizada). Nesta ordem: enviando (estado), ligada (saida_em_sombra), a reserva de pé (reserva_vencida), o telefone da saída (telefone), o modo efetivo ligado (modo); na cadência o acompanhamento ativo e o funil em sent/awaiting_approval (o motivo da parada), no Fechado e nos dados o aceite decidido (aceite_mudou); canal_bloqueado; a janela da classe (fora_da_janela). {pode, motivo}; erro: {pode: false, motivo: erro}.';

revoke all on function public.orcamento_saida_autorizada(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_saida_autorizada(uuid, text, timestamptz) to service_role;

-- ── 7. Gerado do corpo vigente, com os trechos -- F5 ────────────────────────────────────────────────────────────────────

create or replace function public._retorno_janela(p_classe text, p_agora timestamptz, p_chave text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_local timestamp;
  v_t time;
  v_d date;
  v_dia date;
  v_fim time;
begin
  -- Sem a linha de configuração, sem hora ou classe que a janela não conhece: fora, sem próxima abertura.
  if v_cfg.id is null or p_agora is null
     or p_classe is null or p_classe not in ('resposta_imediata', 'resposta_atrasada', 'aviso', 'resumo_parceiro', 'comercial')   -- F5 (P5)
     -- F4 (P5): as duas classes do parceiro só existem com a F4 fora de 'desligado'; desligada, a janela é a de antes.
     or (p_classe in ('aviso', 'resumo_parceiro') and v_cfg.parceiro_modo = 'desligado')
     -- F5 (P5): a classe comercial (a cadência do orçamento) só existe com a F5 fora de 'desligado'.
     or (p_classe = 'comercial' and v_cfg.orcamento_modo = 'desligado') then
    return jsonb_build_object('dentro', false, 'enviar_em', null);
  end if;

  v_local := p_agora at time zone c_fuso;
  v_t := v_local::time;
  v_d := v_local::date;

  if p_classe = 'resposta_imediata' then
    -- K3: todo dia, inclusive domingo e feriado; o fim é exclusivo (22:00 já está fora).
    if v_t >= v_cfg.cliente_resposta_direta_inicio and v_t < v_cfg.cliente_resposta_direta_fim then
      return jsonb_build_object('dentro', true, 'enviar_em', null);
    end if;
    return jsonb_build_object('dentro', false, 'enviar_em', public._retorno_proxima_manha(p_agora, p_chave));
  end if;

  -- F4 (P5): resumo_parceiro (o painel): seg–sex em dia útil, de painel_hora a painel_janela_fim (o fim é exclusivo).
  -- Fora: painel_hora de hoje, se ainda não passou; senão nulo, e o painel do dia cai (nunca vale amanhã).
  if p_classe = 'resumo_parceiro' then
    if extract(isodow from v_d) between 1 and 5 and public.agenda_dia_util(v_d) then
      if v_t >= v_cfg.painel_hora and v_t < v_cfg.painel_janela_fim then
        return jsonb_build_object('dentro', true, 'enviar_em', null);
      end if;
      if v_t < v_cfg.painel_hora then
        return jsonb_build_object('dentro', false, 'enviar_em', (v_d + v_cfg.painel_hora) at time zone c_fuso);
      end if;
    end if;
    return jsonb_build_object('dentro', false, 'enviar_em', null);
  end if;

  -- F5 (P5): comercial: seg–sex em dia útil, de cadencia_inicio a cadencia_fim (o fim é exclusivo). Fora: cadencia_inicio de hoje,
  -- se ainda não passou e hoje é comercial; senão nulo (quem olha o próximo dia é o passo, pelo ate dele: P3.1).
  if p_classe = 'comercial' then
    if extract(isodow from v_d) between 1 and 5 and public.agenda_dia_util(v_d) then
      if v_t >= v_cfg.cadencia_inicio and v_t < v_cfg.cadencia_fim then
        return jsonb_build_object('dentro', true, 'enviar_em', null);
      end if;
      if v_t < v_cfg.cadencia_inicio then
        return jsonb_build_object('dentro', false, 'enviar_em', (v_d + v_cfg.cadencia_inicio) at time zone c_fuso);
      end if;
    end if;
    return jsonb_build_object('dentro', false, 'enviar_em', null);
  end if;

  -- F4 (P5): aviso (o aviso ao cliente, o eco, a ativação e o repassar) tem a janela da resposta_atrasada, abaixo.
  -- resposta_atrasada: o fim da janela do dia (nulo no domingo e no feriado).
  v_fim := case
    when extract(isodow from v_d) = 7 or public.agenda_feriado(v_d) is not null then null
    when extract(isodow from v_d) = 6 then v_cfg.atrasada_sabado_fim
    else v_cfg.atrasada_fim
  end;
  if v_fim is not null and v_t >= v_cfg.atrasada_inicio and v_t < v_fim then
    return jsonb_build_object('dentro', true, 'enviar_em', null);
  end if;

  -- A próxima abertura: hoje, se ainda não deu atrasada_inicio e hoje é permitido; senão o próximo dia
  -- que não é domingo nem feriado (até 7 dias à frente).
  for i in 0 .. 7 loop
    v_dia := v_d + i;
    if extract(isodow from v_dia) <> 7 and public.agenda_feriado(v_dia) is null
       and (i > 0 or v_t < v_cfg.atrasada_inicio) then
      return jsonb_build_object('dentro', false, 'enviar_em', (v_dia + v_cfg.atrasada_inicio) at time zone c_fuso);
    end if;
  end loop;
  return jsonb_build_object('dentro', false, 'enviar_em', null);
end;
$$;
revoke all on function public._retorno_janela(text, timestamptz, text) from public, anon, authenticated;

create or replace function public.canal_pode_enviar(p_fone text, p_classe text, p_origem text,
                                                    p_agora timestamptz default now(),
                                                    p_simular boolean default false,
                                                    p_tipo text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_agora timestamptz := coalesce(p_agora, now());
  v_simular boolean := coalesce(p_simular, false);
  v_chave text := public._agenda_chave_telefone(p_fone);
  v_bloqueio text;
  v_janela jsonb;
  v_desde timestamptz;
  v_n bigint;
begin
  -- 1. Sem a linha de configuração, ou o retorno desligado: nada sai.
  if v_cfg.id is null or v_cfg.modo = 'desligado' then
    return jsonb_build_object('pode', false, 'motivo', 'sem_config', 'enviar_em', null);
  end if;

  -- 2. Só as duas classes de resposta (as do pedido 7 nunca passam aqui).
  --    F4 (P5): aviso e resumo_parceiro passam só com a origem do parceiro (retorno_parceiro, retorno_aviso) e com a F4
  --    fora de 'desligado'; sem isso continuam classe_nao_suportada, como na F1.
  if p_classe is null or p_classe not in ('resposta_imediata', 'resposta_atrasada', 'aviso', 'resumo_parceiro', 'comercial')   -- F5 (P5)
     or (p_classe in ('aviso', 'resumo_parceiro')
         and (v_cfg.parceiro_modo = 'desligado' or p_origem is null or p_origem not in ('retorno_parceiro', 'retorno_aviso')))
     -- F5 (P5): comercial só com a origem do orçamento e a F5 fora de 'desligado'.
     or (p_classe = 'comercial' and (v_cfg.orcamento_modo = 'desligado' or p_origem is distinct from 'retorno_orcamento')) then
    return jsonb_build_object('pode', false, 'motivo', 'classe_nao_suportada', 'enviar_em', null);
  end if;

  -- 3. Sem os 8 dígitos não há a quem mandar.
  if v_chave is null then
    return jsonb_build_object('pode', false, 'motivo', 'sem_numero', 'enviar_em', null);
  end if;

  -- 4. A equipe, pelo mesmo telefone (8 dígitos e o mesmo DDD, como em quem_escreve).
  if exists (select 1 from public.app_users u
              where u.active and (public._mesmo_telefone(p_fone, u.phone_normalized) or public._mesmo_telefone(p_fone, u.phone)))
     or exists (select 1 from public.payees p where p.active and public._mesmo_telefone(p_fone, p.phone)) then
    return jsonb_build_object('pode', false, 'motivo', 'equipe', 'enviar_em', null);
  end if;

  -- 5. Bloqueio da F0a. O parar só sai confirmando o opt-out recém-gravado (e nunca sem ele).
  v_bloqueio := public.canal_bloqueado(p_fone);
  if p_tipo = 'parar' then
    if not coalesce(public._retorno_parar_permitido(v_chave, v_agora), false) then
      return jsonb_build_object('pode', false, 'motivo', coalesce(v_bloqueio, 'canal'), 'enviar_em', null);
    end if;
  elsif v_bloqueio is not null then
    return jsonb_build_object('pode', false, 'motivo', v_bloqueio, 'enviar_em', null);
  end if;

  -- 6. O número que o dono marcou como pessoal.
  if exists (select 1 from public.whatsapp_leads l
              where l.lead_tipo = 'pessoal' and public._agenda_chave_telefone(l.phone_normalized) = v_chave) then
    return jsonb_build_object('pode', false, 'motivo', 'pessoal', 'enviar_em', null);
  end if;

  -- 7. "Segura tudo".
  if v_cfg.segura_tudo_ate is not null and v_cfg.segura_tudo_ate > v_agora then
    return jsonb_build_object('pode', false, 'motivo', 'segura_tudo', 'enviar_em', null);
  end if;

  -- 8. Disjuntor: só sai a resposta imediata a quem escreveu.
  if v_cfg.so_reativo and p_classe <> 'resposta_imediata' then
    return jsonb_build_object('pode', false, 'motivo', 'so_reativo', 'enviar_em', null);
  end if;

  -- 9. A janela da classe.
  v_janela := public._retorno_janela(p_classe, v_agora, v_chave);
  if not coalesce((v_janela ->> 'dentro')::boolean, false) then
    return jsonb_build_object('pode', false, 'motivo', 'fora_da_janela', 'enviar_em', v_janela -> 'enviar_em');
  end if;

  -- 10. O teto da HBR: as respostas decididas desde 00:00 de Brasília até agora.
  v_desde := ((v_agora at time zone c_fuso)::date)::timestamp at time zone c_fuso;
  -- F4 (P5): teto das iniciadas pela HBR (12 por dia): aviso e painel desta tabela, mais o que a agenda já mandou hoje.
  if p_classe in ('aviso', 'resumo_parceiro', 'comercial') then   -- F5 (P5): a cadência conta no teto das iniciadas
    select (select count(*) from public.retorno_saidas s
             where s.classe in ('aviso', 'resumo_parceiro', 'comercial') and s.decidida_em >= v_desde and s.decidida_em <= v_agora
               and (s.estado in ('enviada', 'incerta', 'enviando') or (v_simular and s.estado in ('sombra', 'preparada'))))
         + (select count(*) from public.agenda_cliente_mensagens m where m.enviada_em >= v_desde and m.enviada_em <= v_agora)
      into v_n;
    if v_n >= v_cfg.iniciadas_dia_max then
      -- O aviso espera o dia seguinte; o painel do dia não vale amanhã.
      return jsonb_build_object('pode', false, 'motivo', 'teto_iniciadas', 'enviar_em',
        (case when p_classe = 'aviso'
              then public._retorno_janela('aviso', (((v_agora at time zone c_fuso)::date + 1)::timestamp at time zone c_fuso), v_chave) -> 'enviar_em'
         end));
    end if;
  end if;
  -- F4 (P5): o teto das respostas vale só para resposta_imediata e resposta_atrasada: aviso e painel obedecem só ao das
  -- iniciadas, e nunca caem em teto_dia. A resposta ao parceiro (resposta_imediata) conta aqui, como qualquer resposta.
  if p_classe in ('resposta_imediata', 'resposta_atrasada') then
    select count(*) into v_n
      from public.retorno_saidas s
     where s.classe in ('resposta_imediata', 'resposta_atrasada')
       and s.decidida_em >= v_desde
       and s.decidida_em <= v_agora
       and (s.estado in ('enviada', 'incerta', 'enviando')
            or (v_simular and s.estado in ('sombra', 'preparada')));
    if v_n >= v_cfg.respostas_dia_max then
      return jsonb_build_object('pode', false, 'motivo', 'teto_dia', 'enviar_em', null);
    end if;
  end if;

  -- F5 (P5): a cadência só fala com quem já escreveu: ao menos uma recebida da chave em cadencia_conversa.
  if p_classe = 'comercial'
     and not exists (select 1 from public.whatsapp_messages w
                      where public._agenda_chave_telefone(w.phone_normalized) = v_chave and w.direction = 'inbound'
                        and w.occurred_at <= v_agora and w.occurred_at > v_agora - v_cfg.cadencia_conversa) then
    return jsonb_build_object('pode', false, 'motivo', 'sem_conversa', 'enviar_em', null);
  end if;

  -- 11. O espaçamento global entre saídas automáticas (a simulação não reserva, então não espera).
  if not v_simular and v_cfg.proximo_envio_em is not null and v_cfg.proximo_envio_em > v_agora then
    return jsonb_build_object('pode', false, 'motivo', 'espacamento', 'enviar_em', v_cfg.proximo_envio_em);
  end if;

  -- 12.
  return jsonb_build_object('pode', true, 'motivo', null, 'enviar_em', null);
end;
$$;
revoke all on function public.canal_pode_enviar(text, text, text, timestamptz, boolean, text) from public, anon, authenticated;
grant execute on function public.canal_pode_enviar(text, text, text, timestamptz, boolean, text) to service_role;

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
       and s.emissor not in ('parceiro', 'orcamento')   -- F4 (P5) e F5 (P5): as saídas do parceiro e do orçamento têm o pegar delas
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
revoke all on function public.retorno_pegar(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_pegar(timestamptz) to service_role;

create or replace function public.retorno_saida_autorizada(p_saida uuid, p_fone text, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_s public.retorno_saidas;
  v_modo jsonb;
  v_bloqueio text;
  v_janela jsonb;
begin
  begin
    select * into v_s from public.retorno_saidas s where s.id = p_saida;
    if not found then
      return jsonb_build_object('pode', false, 'motivo', 'sem_saida');
    end if;
    -- F4 (P5): a saída do parceiro tem a última trava dela (veto, 24 h, o vínculo e o número conferidos de novo).
    if v_s.emissor = 'parceiro' then
      return public.parceiro_saida_autorizada(p_saida, p_fone, v_agora);
    end if;
    -- F5 (P5): a saída do orçamento tem a última trava dela (orcamento_saida_autorizada).
    if v_s.emissor = 'orcamento' then
      return public.orcamento_saida_autorizada(p_saida, p_fone, v_agora);
    end if;
    -- A saída reservada pelo retorno_pegar: do retorno, enviando, ligada e dentro da reserva.
    if v_s.emissor is distinct from 'retorno' then
      return jsonb_build_object('pode', false, 'motivo', 'emissor');
    end if;
    if v_s.estado is distinct from 'enviando' then
      return jsonb_build_object('pode', false, 'motivo', 'estado');
    end if;
    if v_s.modo is distinct from 'ligado' then
      return jsonb_build_object('pode', false, 'motivo', 'saida_em_sombra');
    end if;
    if v_s.processando_ate is null or v_s.processando_ate <= v_agora then
      return jsonb_build_object('pode', false, 'motivo', 'reserva_vencida');
    end if;
    -- O destino é o telefone da saída (8 dígitos e o mesmo DDD).
    if not coalesce(public._mesmo_telefone(p_fone, v_s.phone_normalized), false) then
      return jsonb_build_object('pode', false, 'motivo', 'telefone');
    end if;
    -- As mesmas regras do retorno_pegar, de novo agora.
    v_modo := public._retorno_modo_efetivo(v_s.id, v_s.variante, v_s.dados -> 'prazo', v_agora);
    if v_modo ->> 'modo' is distinct from 'ligado' then
      return jsonb_build_object('pode', false, 'motivo', coalesce(v_modo ->> 'motivo', 'modo'));
    end if;
    -- O bloqueio; a única exceção é a confirmação do PARAR (a própria saída, enviando, não conta).
    v_bloqueio := public.canal_bloqueado(p_fone);
    if v_s.tipo = 'parar' then
      if not coalesce(public._retorno_parar_permitido(v_s.chave, v_agora, v_s.id), false) then
        return jsonb_build_object('pode', false, 'motivo', coalesce(v_bloqueio, 'canal'));
      end if;
    elsif v_bloqueio is not null then
      return jsonb_build_object('pode', false, 'motivo', v_bloqueio);
    end if;
    -- A janela da classe.
    v_janela := public._retorno_janela(v_s.classe, v_agora, v_s.chave);
    if not coalesce((v_janela ->> 'dentro')::boolean, false) then
      return jsonb_build_object('pode', false, 'motivo',
        case when v_s.classe in ('resposta_imediata', 'resposta_atrasada') then 'fora_da_janela' else 'classe_nao_suportada' end);
    end if;
    return jsonb_build_object('pode', true, 'motivo', null);
  exception when others then
    -- Na dúvida, não manda.
    return jsonb_build_object('pode', false, 'motivo', 'erro');
  end;
end;
$$;
revoke all on function public.retorno_saida_autorizada(uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_saida_autorizada(uuid, text, timestamptz) to service_role;

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
    if v_s.emissor is null or v_s.emissor not in ('retorno', 'parceiro', 'orcamento')   -- F4 (P5) e F5 (P5): também a saída do parceiro e a do orçamento
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

    -- F4 (P5): os efeitos do parceiro (aviso, painel, apresentação, coleta_n), em toda decisão de saída do parceiro, num
    -- sub-bloco próprio: o efeito que falha vai ao log e não desfaz a decisão.
    if v_s.emissor = 'parceiro' then
      begin
        perform public._parceiro_aplicar_efeitos(v_s.id, v_agora);
      exception when others then
        perform public._retorno_log('decisao', 'retorno_registrar_decisao: efeitos do parceiro: ' || sqlerrm, 'error',
                                    jsonb_build_object('saida', v_s.id, 'estado', v_final, 'sqlstate', sqlstate));
      end;
    end if;

    -- F5 (P5): os efeitos do orçamento (passo, acompanhamento, aceite), em toda decisão de saída do orçamento, num sub-bloco
    -- próprio: o efeito que falha vai ao log e não desfaz a decisão. _orcamento_aplicar_efeitos é idempotente (dados.efeitos_f5).
    if v_s.emissor = 'orcamento' then
      begin
        perform public._orcamento_aplicar_efeitos(v_s.id, v_agora);
      exception when others then
        perform public._retorno_log('decisao', 'retorno_registrar_decisao: efeitos do orçamento: ' || sqlerrm, 'error',
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
revoke all on function public.retorno_registrar_decisao(uuid, text, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_registrar_decisao(uuid, text, jsonb, timestamptz) to service_role;
