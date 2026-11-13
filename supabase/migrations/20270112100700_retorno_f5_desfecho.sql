-- Retorno rápido ao cliente, F5 (P8): o desfecho do orçamento enviado, as palavras do dono e o fechamento. Nada liga aqui.
-- Gerada por script (scripts/gerar_f5.cjs desfecho): as funções novas e a view vêm de scripts/f5_sql/p8_desfecho.sql, escritas
-- à mão; retorno_carona (a da 20261112200000, com "where id"), retorno_resumo_extra e _retorno_dito_errado são geradas do
-- corpo vigente (o do banco, achado pelo md5 do prosrc), e só os trechos marcados -- F5 são novos.
--
-- 1. _orcamento_rotulo_da_saida: "lembrete do ORÇ-00151 (Ana)", do tipo e do os_id da saída (o 1º nome do cadastro, nunca
--    telefone).
-- 2. orcamento_marcar_perdido: o orçamento (draft, sem conversão, sem agrupamento) vira rejected com motivo_perda da lista
--    fechada (sem_motivo_antigo é só da migration de dado), audit_log com o motivo antigo e o novo; o acompanhamento ativo ou
--    parado conclui (status_mudou) e as saídas agendadas dele caem; o encerrado fica encerrado (CHECK).
-- 3. orcamento_dito (C-DITO-O): *segura 151*, *solta 151*, *segura orcamentos*, *solta orcamentos* e *motivo 151 B*, só do
--    dono (is_admin_or_financial); a ordem pelo número (ORÇ-/OS-), nunca pelo nome. Nunca recebe PIN.
-- 4. orcamento_resumo_fechamento (C-FECH-O): {fixas, linhas, avisar, nao_saiu}. Fixa: amanhã sai sozinho (até 3, com
--    *segura N*). Linhas (no máximo 4): amanhã esperam o seu *sim <PIN>*; os encerramentos desde o último fechamento que podia
--    mostrá-los (a revisão não conta); o "Fechado" ou o pedido de dados que não saiu; os enviados vencidos sem desfecho. Com
--    orcamento_modo = 'desligado', só a dos vencidos. Nunca telefone nem documento. Só lê: o aviso do que não saiu vai em
--    nao_saiu ({aceite, linha}), e quem grava a marca é o 5b, depois de a tarde com a linha ir à fila.
-- 5. orcamento_avisados (C-AVISO-O): grava avisado_em e aviso_fila nos passos previstos da linha fixa; sem a linha da fila,
--    nada (o aviso vale pela entrega, e o vigia só deixa sair sozinho com a fila em sent).
-- 5b. orcamento_nao_saiu_avisados (revisão das ondas 4 a 9, achados banco-2, seguranca-1 e edge-fechamento): grava
--    resultado.nao_saiu_fechado_em (e nao_saiu_fila) nos aceites cujo aviso a tarde levou à fila; só então o aviso sai da
--    lista do cartão (_orcamento_cartao_aceites). Sem a linha da fila, nada.
-- 6. Gerados: retorno_carona (a lista da F5, _orcamento_cartao_lista, da P7, dentro de begin … exception when
--    undefined_function: até a onda 5, a carona é a da F2), retorno_resumo_extra (o "Mandei sozinho" lista a saída sozinha do
--    orçamento, com o rótulo dela) e _retorno_dito_errado (o *errado Z* de uma saída sem caso diz o nome do cliente).
-- 7. retorno_auditoria_lista, recriada à mão com as mesmas colunas e a mesma ordem: a amostra passa a ter as saídas sozinhas
--    do orçamento. O gerador confere antes o md5 do pg_get_viewdef de produção (o de 12/11). Na saída sem caso, o trecho é o
--    '(sem texto)' de _retorno_pedido_do_caso (o coalesce dela).
--
-- Com a F5 desligada (o padrão: orcamento_modo, encerrar_marca_perdido e motivo_marca_aberto desligados), a carona, o "Mandei
-- sozinho", o *errado Z* e a auditoria saem como antes (sem saída do orçamento não há o que mudar), e o fechamento só traz os
-- enviados vencidos sem desfecho (o desfecho vale mesmo sem cadência).
--
-- Sem dado. Reverter: reaplicar retorno_carona de 20261112200000_retorno_update_com_where.sql, retorno_resumo_extra e a view
-- retorno_auditoria_lista de 20261123100800_retorno_f2_resumo.sql e _retorno_dito_errado de 20261123100100_retorno_f2_palavras.sql;
-- depois, drop function das funções orcamento_* e _orcamento_* desta migration (a P5 chama orcamento_marcar_perdido dentro de
-- begin … exception when undefined_function).

-- ── 1. O rótulo da saída do orçamento ──────────────────────────────────────────────────────────────────────────────────

create or replace function public._orcamento_rotulo_da_saida(p_saida uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_s public.retorno_saidas;
  v_numero text;
begin
  select * into v_s from public.retorno_saidas s where s.id = p_saida;
  if not found then
    return 'orçamento';
  end if;
  select so.service_order_number into v_numero
    from public.service_orders so
   where so.id = (case when coalesce(v_s.dados ->> 'os_id', '') ~ c_uuid then (v_s.dados ->> 'os_id')::uuid end);
  return format('%s do %s (%s)',
                (case v_s.tipo when 'orc_lembrete' then 'lembrete'
                               when 'orc_vespera' then 'véspera'
                               when 'orc_encerramento' then 'encerramento'
                               when 'orc_fechado' then '''Fechado'''
                               when 'orc_dados_nota' then 'pedido de dados'
                               else 'aviso' end),
                coalesce(v_numero, 'orçamento'),
                coalesce(public._retorno_nome(v_s.client_id), 'cliente sem nome'));
end;
$$;

comment on function public._orcamento_rotulo_da_saida(uuid) is
  'Retorno F5 (P8.1): o rótulo da saída do orçamento para o dono ("lembrete do ORÇ-00151 (Ana)"): o passo pelo tipo, o número do dados.os_id e o 1º nome do cadastro (_retorno_nome). Nunca telefone nem documento.';

revoke all on function public._orcamento_rotulo_da_saida(uuid) from public, anon, authenticated;

-- ── 2. Perdido, com motivo ─────────────────────────────────────────────────────────────────────────────────────────────

create or replace function public.orcamento_marcar_perdido(p_os uuid, p_motivo text, p_por text, p_autor uuid,
                                                           p_nota text default null, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_motivos constant text[] := array['sumiu', 'fechou_com_outro', 'desistiu', 'preco', 'prazo', 'outro'];
  c_por constant text[] := array['tela', 'assistente', 'dono', 'cadencia'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_nota text := nullif(btrim(coalesce(p_nota, '')), '');
  v_so record;
  v_acomps uuid[];
begin
  -- sem_motivo_antigo só pela migration de dado (P9): por aqui, recusa.
  if p_motivo is null or not (p_motivo = any (c_motivos)) then
    return jsonb_build_object('ok', false, 'motivo', 'motivo');
  end if;
  if p_por is null or not (p_por = any (c_por)) then
    return jsonb_build_object('ok', false, 'motivo', 'por');
  end if;
  select so.id, so.service_order_number, so.status, so.quote_status, so.converted_to_os_at, so.merged_into_id, so.motivo_perda,
         so.motivo_perda_por
    into v_so
    from public.service_orders so
   where so.id = p_os
     for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sem_ordem');
  end if;
  if v_so.converted_to_os_at is not null or v_so.status is distinct from 'draft' then
    return jsonb_build_object('ok', false, 'motivo', 'convertida', 'numero', v_so.service_order_number);
  end if;
  if v_so.merged_into_id is not null then
    return jsonb_build_object('ok', false, 'motivo', 'agrupada', 'numero', v_so.service_order_number);
  end if;

  update public.service_orders so
     set quote_status = 'rejected', motivo_perda = p_motivo, motivo_perda_em = v_agora, motivo_perda_por = p_por,
         motivo_perda_nota = left(v_nota, 200)
   where so.id = p_os and so.status = 'draft' and so.converted_to_os_at is null and so.merged_into_id is null;
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('service_orders', p_os, 'update', coalesce(p_autor::text, 'retorno-f5'),
          jsonb_build_object('quote_status', v_so.quote_status, 'motivo_perda', v_so.motivo_perda, 'motivo_perda_por', v_so.motivo_perda_por),
          jsonb_build_object('quote_status', 'rejected', 'motivo_perda', p_motivo, 'motivo_perda_por', p_por),
          'Orçamento perdido: ' || p_motivo || ' (' || p_por || ')');

  -- O acompanhamento ativo ou parado conclui, e o que esperava dele cai. O encerrado fica encerrado, com o encerramento que
  -- tinha (CHECK (estado = 'encerrado') = (encerramento is not null)); o concluido também não muda (troca de motivo).
  select coalesce(array_agg(a.id), '{}'::uuid[]) into v_acomps
    from public.orcamento_acompanhamentos a
   where a.service_order_id = p_os and a.estado in ('ativo', 'parado');
  if cardinality(v_acomps) > 0 then
    update public.orcamento_acompanhamentos a
       set estado = 'concluido', parou_por = 'status_mudou', parou_em = v_agora, atualizado_em = now()
     where a.id = any (v_acomps) and a.estado in ('ativo', 'parado');
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'status_mudou', decidida_em = v_agora, processando_ate = null, atualizada_em = now()
     where s.emissor = 'orcamento' and s.estado = 'agendada'
       and s.dados ->> 'acompanhamento_id' = any (array(select x::text from unnest(v_acomps) as x));
    update public.orcamento_passos p
       set estado = 'cancelado'
     where p.acompanhamento_id = any (v_acomps)
       and (p.estado in ('previsto', 'aguarda_sim')
            or (p.estado = 'agendado'
                and exists (select 1 from public.retorno_saidas s where s.id = p.saida_id and s.estado = 'cancelada')));
  end if;

  return jsonb_build_object('ok', true, 'numero', v_so.service_order_number, 'motivo', p_motivo, 'antes', v_so.motivo_perda);
end;
$$;

comment on function public.orcamento_marcar_perdido(uuid, text, text, uuid, text, timestamptz) is
  'Retorno F5 (P8.1, 3.4): o orçamento (status draft, sem conversão, sem agrupamento; qualquer quote_status, inclusive rejected para trocar o motivo) vira rejected com motivo_perda (sumiu, fechou_com_outro, desistiu, preco, prazo, outro; sem_motivo_antigo recusa), motivo_perda_em, motivo_perda_por (tela, assistente, dono, cadencia) e a nota; audit_log com o antes e o depois. O acompanhamento ativo ou parado vai a concluido (status_mudou), os passos previstos/à espera e a saída agendada dele caem; o encerrado e o concluido não mudam. {ok, numero, motivo, antes} ou {ok: false, motivo: motivo | por | sem_ordem | convertida | agrupada}.';

revoke all on function public.orcamento_marcar_perdido(uuid, text, text, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_marcar_perdido(uuid, text, text, uuid, text, timestamptz) to service_role;

-- ── 3. As palavras do dono (C-DITO-O) ──────────────────────────────────────────────────────────────────────────────────

create or replace function public.orcamento_dito(p_comando jsonb, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_erro constant text := 'Não consegui agora; tente pela tela.';
  c_dias constant text[] := array['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_c jsonb := (case when jsonb_typeof(p_comando) = 'object' then p_comando else '{}'::jsonb end);
  v_cmd text;
  v_n text;
  v_orc text;
  v_os record;
  v_num text;
  v_curto text;
  v_nome text;
  v_a public.orcamento_acompanhamentos;
  v_p public.orcamento_passos;
  v_cfg public.retorno_config;
  v_palavra text;
  v_motivo text;
  v_r jsonb;
  v_valor text;
begin
  if p_autor is null or not coalesce(public.is_admin_or_financial(p_autor), false) then
    return jsonb_build_object('ok', false, 'motivo', 'nao_e_o_dono');
  end if;
  begin
    v_cmd := v_c ->> 'comando';
    if v_cmd = 'segura_todos' then
      update public.retorno_config set orcamento_segura = true where id;
      return jsonb_build_object('ok', true, 'texto', 'Segurei todos os lembretes de orçamento. Para voltar: *solta orcamentos*.');
    end if;
    if v_cmd = 'solta_todos' then
      update public.retorno_config set orcamento_segura = false where id;
      return jsonb_build_object('ok', true, 'texto', 'Os lembretes de orçamento voltaram.');
    end if;
    if v_cmd is null or v_cmd not in ('segura', 'solta', 'motivo') then
      return jsonb_build_object('ok', false, 'motivo', 'comando', 'texto', c_erro);
    end if;

    -- O número acha UMA ordem, por ORÇ-nnnnn ou OS-nnnnn (a conversão troca só o prefixo); nunca pelo nome.
    v_n := substring(coalesce(v_c ->> 'numero', '') from '^[0-9]{1,8}$');
    if v_n is null then
      return jsonb_build_object('ok', false, 'motivo', 'numero', 'texto', c_erro);
    end if;
    v_n := coalesce(nullif(ltrim(v_n, '0'), ''), '0');
    v_num := (case when char_length(v_n) >= 5 then v_n else lpad(v_n, 5, '0') end);
    v_orc := 'ORÇ-' || v_num;
    select so.id, so.service_order_number, so.status, so.quote_status, so.converted_to_os_at, so.merged_into_id, so.client_id,
           so.grand_total
      into v_os
      from public.service_orders so
     where so.service_order_number in (v_orc, 'OS-' || v_num)
     order by (so.service_order_number = v_orc) desc, so.created_at desc, so.id
     limit 1;
    if not found then
      return jsonb_build_object('ok', true, 'texto', format('Não achei o %s.', v_orc));
    end if;
    v_curto := v_n;
    v_nome := coalesce(public._retorno_nome(v_os.client_id), 'sem nome');

    -- *segura 151*: o acompanhamento para (segurado); o que esperava cai, e a saída agendada também.
    if v_cmd = 'segura' then
      select * into v_a
        from public.orcamento_acompanhamentos a
       where a.service_order_id = v_os.id and a.estado in ('ativo', 'parado')
         for update;
      if not found then
        return jsonb_build_object('ok', true, 'texto', format('O %s não tem lembrete previsto.', v_os.service_order_number));
      end if;
      update public.orcamento_acompanhamentos a
         set estado = 'parado', parou_por = 'segurado', parou_em = v_agora, atualizado_em = now()
       where a.id = v_a.id;
      update public.retorno_saidas s
         set estado = 'cancelada', motivo = 'segurado', decidida_em = v_agora, processando_ate = null, atualizada_em = now()
       where s.emissor = 'orcamento' and s.estado = 'agendada' and s.dados ->> 'acompanhamento_id' = v_a.id::text;
      update public.orcamento_passos p
         set estado = 'cancelado', motivo = 'segurado'
       where p.acompanhamento_id = v_a.id
         and (p.estado in ('previsto', 'aguarda_sim')
              or (p.estado = 'agendado'
                  and exists (select 1 from public.retorno_saidas s where s.id = p.saida_id and s.estado = 'cancelada')));
      return jsonb_build_object('ok', true, 'texto',
        format('Segurei os lembretes do %s (%s). Para voltar: *solta %s*.', v_os.service_order_number, v_nome, v_curto));
    end if;

    -- *solta 151*: só o segurado volta. O passo de dia já passado fica pulado/segurado; os de hoje em diante voltam a previsto,
    -- sem o aviso de antes (avisado_em e aviso_fila nulos: o aviso era de quando estava segurado).
    if v_cmd = 'solta' then
      select * into v_a
        from public.orcamento_acompanhamentos a
       where a.service_order_id = v_os.id and a.estado = 'parado' and a.parou_por = 'segurado'
         for update;
      if not found then
        return jsonb_build_object('ok', true, 'texto', format('Os lembretes do %s não estavam segurados.', v_os.service_order_number));
      end if;
      update public.orcamento_acompanhamentos a
         set estado = 'ativo', parou_por = null, parou_em = null, parou_msg_id = null, atualizado_em = now()
       where a.id = v_a.id;
      update public.orcamento_passos p
         set estado = (case when p.dia < v_hoje then 'pulado' else 'previsto' end),
             motivo = (case when p.dia < v_hoje then 'segurado' end),
             avisado_em = null, aviso_fila = null
       where p.acompanhamento_id = v_a.id and p.estado = 'cancelado' and p.motivo = 'segurado';
      select * into v_p
        from public.orcamento_passos p
       where p.acompanhamento_id = v_a.id and p.estado = 'previsto'
       order by p.dia, p.id
       limit 1;
      if not found then
        return jsonb_build_object('ok', true, 'texto', format('Os lembretes do %s voltaram.', v_os.service_order_number));
      end if;
      return jsonb_build_object('ok', true, 'texto',
        format('Os lembretes do %s voltaram. Próximo: %s, %s %s.', v_os.service_order_number,
               (case v_p.passo when 'lembrete' then 'lembrete' when 'vespera' then 'véspera' else 'encerramento' end),
               c_dias[extract(isodow from v_p.dia)::integer], to_char(v_p.dia, 'DD/MM')));
    end if;

    -- *motivo 151 B* (ou a palavra no lugar da letra: preco, prazo, desistiu, sumiu, outro, outra empresa).
    v_palavra := public._retorno_busca(coalesce(v_c ->> 'letra', v_c ->> 'palavra', ''));
    v_motivo := (case
      when v_palavra in ('a', 'sumiu') then 'sumiu'
      when v_palavra in ('b', 'fechou com outro', 'fechou_com_outro', 'outra empresa', 'fechei com outro') then 'fechou_com_outro'
      when v_palavra in ('c', 'desistiu') then 'desistiu'
      when v_palavra in ('d', 'preco') then 'preco'
      when v_palavra in ('f', 'prazo') then 'prazo'
      when v_palavra in ('g', 'outro') then 'outro'
    end);
    if v_motivo is null then
      return jsonb_build_object('ok', false, 'motivo', 'letra', 'texto', c_erro);
    end if;
    if v_os.converted_to_os_at is not null or v_os.status is distinct from 'draft' then
      return jsonb_build_object('ok', true, 'texto', format('O %s já virou %s: não há o que marcar.', v_orc, v_os.service_order_number));
    end if;
    if v_os.merged_into_id is not null then
      return jsonb_build_object('ok', true, 'texto', format('O %s foi agrupado em outro orçamento: não há o que marcar.', v_os.service_order_number));
    end if;
    -- Orçamento aberto: só com motivo_marca_aberto (dúvida 8; o padrão é não marcar).
    if v_os.quote_status is distinct from 'rejected' then
      v_cfg := public._retorno_cfg();
      if not coalesce(v_cfg.motivo_marca_aberto, false) then
        return jsonb_build_object('ok', true, 'texto',
          format('O %s ainda está aberto: para marcar como perdido, use a tela ou o assistente. Depois disso, *motivo %s B* troca o motivo.',
                 v_os.service_order_number, v_curto));
      end if;
    end if;
    v_r := public.orcamento_marcar_perdido(v_os.id, v_motivo, 'dono', p_autor, null, v_agora);
    if not coalesce((v_r ->> 'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'motivo', coalesce(v_r ->> 'motivo', 'erro'), 'texto', c_erro);
    end if;
    v_valor := (case when v_os.grand_total is null then null
                     else regexp_replace('R$ ' || translate(to_char(round(v_os.grand_total, 2), 'FM999,999,999,990.00'), ',.', '.,'),
                                         ',00$', '') end);
    return jsonb_build_object('ok', true, 'texto',
      format('%s (%s%s) marcado como perdido: %s. Para reabrir, use a tela.', v_os.service_order_number, v_nome,
             coalesce(', ' || v_valor, ''),
             (case v_motivo when 'sumiu' then 'sumiu' when 'fechou_com_outro' then 'fechou com outro' when 'desistiu' then 'desistiu'
                            when 'preco' then 'preço' when 'prazo' then 'prazo' else 'outro' end)));
  exception when others then
    perform public._retorno_log('orcamento_dito', 'orcamento_dito: ' || sqlerrm, 'error',
                                jsonb_build_object('comando', v_cmd, 'sqlstate', sqlstate));
    return jsonb_build_object('ok', false, 'texto', c_erro);
  end;
end;
$$;

comment on function public.orcamento_dito(jsonb, uuid, timestamptz) is
  'Retorno F5 (P8.1, C-DITO-O): as palavras do dono sobre o orçamento, só de is_admin_or_financial (senão {ok: false, motivo: nao_e_o_dono}). segura {numero}: acompanhamento parado/segurado, passos à espera cancelados (motivo segurado), saída agendada cancelada/segurado. solta {numero}: o segurado volta a ativo; passos de dia passado pulado/segurado, os outros previsto sem aviso. segura_todos/solta_todos: retorno_config.orcamento_segura (where id). motivo {numero, letra} (A sumiu, B fechou com outro, C desistiu, D preço, F prazo, G outro, ou a palavra): rejected troca o motivo; aberto só com motivo_marca_aberto. A ordem pelo número (ORÇ-nnnnn ou OS-nnnnn), nunca pelo nome. {ok, texto}; erro: {ok: false, texto: "Não consegui agora; tente pela tela."}. Nunca recebe PIN.';

revoke all on function public.orcamento_dito(jsonb, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_dito(jsonb, uuid, timestamptz) to service_role;

-- ── 4. O fechamento do dono (C-FECH-O) ─────────────────────────────────────────────────────────────────────────────────

-- "Amanhã" é o próximo dia comercial (_orcamento_dia_util_mais). Os encerramentos contam desde o último fechamento que podia
-- mostrá-los: a revisão da semana e a do mês não mostram as linhas do orçamento (P10.2) e não contam (revisão das ondas 4 a 9,
-- achado seguranca-1); o de outro dia diz o dia ("Encerrado seg 16/11"). O aviso do "Fechado" que não saiu volta em nao_saiu,
-- com a linha exata; esta função não grava nada: a marca resultado.nao_saiu_fechado_em é de orcamento_nao_saiu_avisados,
-- depois de a tarde com a linha ir à fila (antes, a marca era gravada aqui, e a linha que a tarde descartava sumia do cartão).
create or replace function public.orcamento_resumo_fechamento(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_dias constant text[] := array['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
  c_legenda constant text := '(B fechou com outro · C desistiu · D preço · F prazo · G outro)';
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (coalesce(p_agora, now()) at time zone 'America/Sao_Paulo')::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_amanha date;
  v_desde timestamptz;
  v_fixas text[] := '{}'::text[];
  v_avisar uuid[] := '{}'::uuid[];
  v_itens text[] := '{}'::text[];
  v_meio text[] := '{}'::text[];
  v_meio_aceite uuid[] := '{}'::uuid[];
  v_linhas text[] := '{}'::text[];
  v_linha2 text;
  v_linha4 text;
  v_linha text;
  v_nao_saiu jsonb := '[]'::jsonb;
  v_desde_enc timestamptz;
  v_quando text;
  v_n integer := 0;
  v_k integer := 0;
  v_m integer := 0;
  v_ate date;
  v_r record;
  v_cauda text;
  v_lugar integer;
  v_venc text[];
  v_venc_n integer;
begin
  if v_cfg.id is null then
    return jsonb_build_object('fixas', '[]'::jsonb, 'linhas', '[]'::jsonb, 'avisar', '[]'::jsonb, 'nao_saiu', '[]'::jsonb);
  end if;
  v_desde := public._retorno_fechamento_anterior(v_agora);
  -- Os encerramentos: desde a última tarde de turno 'fechamento' que foi à fila (resumo_tarde.enviado) nos últimos 10 dias. A
  -- revisão (da semana, do mês) e a tarde calada não mostram as linhas do orçamento; sem nenhum fechamento enviado, o anterior
  -- de sempre. Num dia comum, é o mesmo instante de v_desde.
  v_desde_enc := least(v_desde, coalesce((select (max(t.dia) + v_cfg.ponto_fechamento) at time zone c_fuso
                                            from public.resumo_tarde t
                                           where t.turno = 'fechamento' and t.enviado and t.dia < v_hoje
                                             and t.dia >= v_hoje - 10), v_desde));

  if v_cfg.orcamento_modo is distinct from 'desligado' then
    v_amanha := public._orcamento_dia_util_mais(v_hoje, 1);

    -- 1 e 2. Amanhã: o que sai sozinho (fixa, até 3) e o que espera o *sim* no cartão. Com *segura orcamentos*, nada anda.
    if not coalesce(v_cfg.orcamento_segura, false) then
      for v_r in
        select p.id, p.passo, so.service_order_number as numero, public._retorno_nome(a.client_id) as nome
          from public.orcamento_passos p
          join public.orcamento_acompanhamentos a on a.id = p.acompanhamento_id
          join public.retorno_modelo_tipos t on t.tipo = p.tipo
          join public.service_orders so on so.id = a.service_order_id
         where p.estado = 'previsto' and p.dia = v_amanha and a.estado = 'ativo' and a.modo = 'ligado' and t.nivel = 'sozinho'
         order by so.service_order_number, p.id
      loop
        v_n := v_n + 1;
        if v_n <= 3 then
          v_itens := v_itens || format('%s do %s (%s) · *segura %s*',
                                       (case v_r.passo when 'lembrete' then 'o lembrete' when 'vespera' then 'o aviso de véspera'
                                                       else 'o encerramento' end),
                                       v_r.numero, coalesce(v_r.nome, 'sem nome'),
                                       coalesce(nullif(ltrim(substring(v_r.numero from '[0-9]+$'), '0'), ''), '0'));
          v_avisar := v_avisar || v_r.id;
        end if;
      end loop;
      if v_n > 0 then
        v_fixas := array[format('Orçamentos: amanhã %s %s%s', (case when v_n = 1 then 'sai sozinho' else 'saem sozinhos' end),
                                array_to_string(v_itens, '; '),
                                (case when v_n > 3 then format(' e mais %s', v_n - 3) else '' end))];
      end if;

      select count(*) into v_k
        from public.orcamento_passos p
        join public.orcamento_acompanhamentos a on a.id = p.acompanhamento_id
        join public.retorno_modelo_tipos t on t.tipo = p.tipo
       where p.estado = 'previsto' and p.dia = v_amanha and a.estado = 'ativo' and a.modo = 'ligado' and t.nivel = 'cartao';
      v_k := v_k + greatest(v_n - 3, 0);
      select count(*), min(p.ate) into v_m, v_ate
        from public.orcamento_passos p
        join public.orcamento_acompanhamentos a on a.id = p.acompanhamento_id
       where p.estado = 'aguarda_sim' and a.estado = 'ativo' and p.ate > v_hoje;
      if v_k > 0 then
        v_linha2 := format('Orçamentos: amanhã %s', (case when v_k = 1 then '1 lembrete espera o seu *sim <PIN>* no *retorno*'
                                                          else v_k || ' lembretes esperam o seu *sim <PIN>* no *retorno*' end))
                    || (case when v_m > 0
                             then format(' · %s de hoje ainda %s, até %s %s', v_m, (case when v_m = 1 then 'espera' else 'esperam' end),
                                         c_dias[extract(isodow from v_ate)::integer], to_char(v_ate, 'DD/MM'))
                             else '' end);
      elsif v_m > 0 then
        v_linha2 := format('Orçamentos: %s de hoje ainda %s o seu *sim <PIN>* no *retorno*, até %s %s', v_m,
                           (case when v_m = 1 then 'espera' else 'esperam' end),
                           c_dias[extract(isodow from v_ate)::integer], to_char(v_ate, 'DD/MM'));
      end if;
    end if;

    -- 3. Os encerramentos desde o último fechamento que podia mostrá-los (v_desde_enc; só do acompanhamento ligado: a sombra não
    --    fala com o dono). A hora do encerramento é a da saída dele; sem saída, o fim do prazo do passo (sem o *sim*) ou o dia
    --    seguinte ao prazo. O de outro dia diz o dia no lugar do "hoje".
    for v_r in
      select x.*
        from (select a.encerramento, so.service_order_number as numero, so.status, so.converted_to_os_at, so.quote_status,
                     so.motivo_perda, public._retorno_nome(a.client_id) as nome, e.motivo as passo_motivo,
                     coalesce(es.enviada_em, es.decidida_em,
                              (case when e.motivo = 'sem_sim' then (e.ate + v_cfg.cadencia_fim) at time zone c_fuso
                                    when e.motivo is not null then (e.ate + 1)::timestamp at time zone c_fuso end),
                              a.atualizado_em) as quando
                from public.orcamento_acompanhamentos a
                join public.service_orders so on so.id = a.service_order_id
                left join public.orcamento_passos e on e.acompanhamento_id = a.id and e.passo = 'encerramento'
                left join public.retorno_saidas es on es.id = e.saida_id
               where a.estado = 'encerrado' and a.modo = 'ligado' and a.encerramento in ('enviado', 'sem_mensagem')) x
       where x.quando > v_desde_enc and x.quando <= v_agora
         and x.status = 'draft' and x.converted_to_os_at is null
       order by x.quando, x.numero
    loop
      v_cauda := (case when coalesce(v_cfg.motivo_marca_aberto, false)
                       then format(' · *motivo %s A* marca como perdido (sumiu)',
                                   coalesce(nullif(ltrim(substring(v_r.numero from '[0-9]+$'), '0'), ''), '0'))
                       else ' · para marcar como perdido, use a tela ou o assistente' end);
      v_quando := (case when (v_r.quando at time zone c_fuso)::date = v_hoje then 'hoje'
                        else c_dias[extract(isodow from (v_r.quando at time zone c_fuso))::integer] || ' '
                             || to_char(v_r.quando at time zone c_fuso, 'DD/MM') end);
      if v_r.quote_status = 'rejected' then
        v_meio := v_meio || format('Encerrado %s: %s (%s), perdido (%s) · troque com *motivo %s B* %s', v_quando, v_r.numero,
                                   coalesce(v_r.nome, 'sem nome'),
                                   (case v_r.motivo_perda when 'fechou_com_outro' then 'fechou com outro' when 'preco' then 'preço'
                                                          else coalesce(v_r.motivo_perda, 'sem motivo') end),
                                   coalesce(nullif(ltrim(substring(v_r.numero from '[0-9]+$'), '0'), ''), '0'), c_legenda);
      elsif v_r.encerramento = 'enviado' then
        v_meio := v_meio || (format('Encerrado %s sem resposta: %s (%s)', v_quando, v_r.numero, coalesce(v_r.nome, 'sem nome'))
                             || v_cauda);
      else
        v_meio := v_meio || (format('Encerrado sem mensagem (não saiu: %s): %s (%s)',
                                    (case v_r.passo_motivo when 'sem_sim' then 'sem o seu sim'
                                                           when 'agenda_hoje' then 'a agenda falou com o cliente no dia'
                                                           when 'outra_voz_hoje' then 'outra mensagem ao cliente no dia'
                                                           when 'comercial_hoje' then 'outro lembrete ao cliente no dia'
                                                           when 'teto_iniciadas' then 'o teto do dia'
                                                           when 'fora_da_janela' then 'fora do horário'
                                                           when 'segurado' then 'segurado'
                                                           when 'validador' then 'o conferidor barrou o texto'
                                                           when 'sem_conversa' then 'o cliente nunca escreveu'
                                                           else 'o canal barrou' end),
                                    v_r.numero, coalesce(v_r.nome, 'sem nome')) || v_cauda);
      end if;
      v_meio_aceite := array_append(v_meio_aceite, null::uuid);
    end loop;

    -- 3b. O "Fechado" ou o pedido de dados que não saiu (P5.1), uma vez.
    for v_r in
      select a.id, a.resultado, so.service_order_number as numero, public._retorno_nome(a.client_id) as nome
        from public.orcamento_aceites a
        left join public.service_orders so on so.id = a.service_order_id
       where a.estado in ('com_sinal', 'sem_sinal')
         and a.resultado ? 'saida_nao_saiu' and not (a.resultado ? 'nao_saiu_fechado_em')
         and a.criado_em <= v_agora
       order by coalesce(a.decidido_em, a.criado_em), so.service_order_number, a.id
    loop
      v_meio := v_meio || (case
        when v_r.resultado ->> 'saida_nao_saiu' = 'incerta'
          then format('O ''Fechado'' do %s (%s) pode não ter saído: confira a conversa', coalesce(v_r.numero, 'orçamento'),
                      coalesce(v_r.nome, 'sem nome'))
        when v_r.resultado ->> 'saida_nao_saiu_tipo' = 'orc_dados_nota'
          then format('O pedido de dados da nota do %s (%s) não saiu: responda você', coalesce(v_r.numero, 'orçamento'),
                      coalesce(v_r.nome, 'sem nome'))
        else format('O ''Fechado'' do %s (%s) não saiu: responda você', coalesce(v_r.numero, 'orçamento'), coalesce(v_r.nome, 'sem nome'))
      end);
      v_meio_aceite := array_append(v_meio_aceite, v_r.id);
    end loop;
  end if;

  -- 4. Enviados vencidos sem desfecho (vale mesmo com a F5 desligada: é o desfecho). Enviado = ao menos um envio em
  --    orcamento_envios, a qualquer número, menos o do parceiro; vencido = o último dia da validade há mais de 1 dia útil.
  select coalesce(array_agg(y.numero order by y.numero), '{}'::text[]), count(*)
    into v_venc, v_venc_n
    from (select so.service_order_number as numero
            from public.service_orders so
           where exists (select 1 from public.orcamento_envios e where e.service_order_id = so.id and e.em <= v_agora)
             and so.status = 'draft' and so.converted_to_os_at is null and so.merged_into_id is null
             and (so.quote_status is null or so.quote_status not in ('awaiting_deposit', 'approved', 'rejected'))
             and not coalesce(so.client_id = any (coalesce(v_cfg.clientes_parceiros, '{}'::uuid[])), false)
             and not exists (select 1 from public.orcamento_aceites ac
                              where ac.service_order_id = so.id and ac.estado in ('com_sinal', 'sem_sinal'))
             and not exists (select 1 from public.orcamento_acompanhamentos a
                              where a.service_order_id = so.id and a.estado = 'ativo')
             and public._orcamento_dia_util_mais(public._orcamento_ultimo_dia(so.id), 1) < v_hoje) y;
  if v_venc_n > 0 then
    v_linha4 := format('Enviados vencidos sem desfecho: %s (%s%s)', v_venc_n, array_to_string(v_venc[1:5], ', '),
                       (case when v_venc_n > 5 then format(' e mais %s', v_venc_n - 5) else '' end))
                || (case when coalesce(v_cfg.motivo_marca_aberto, false)
                         then format(' · *motivo %s A* marca como perdido (sumiu)',
                                     (case when v_venc_n = 1
                                           then coalesce(nullif(ltrim(substring(v_venc[1] from '[0-9]+$'), '0'), ''), '0')
                                           else '<número>' end))
                         else ' · para marcar como perdido, use a tela ou o assistente' end);
  end if;

  -- No máximo 4 linhas: a de amanhã, os encerramentos e os avisos (o que não couber vira "e mais N" e fica para o próximo)
  -- e a dos vencidos, que sempre entra.
  v_lugar := 4 - (case when v_linha2 is null then 0 else 1 end) - (case when v_linha4 is null then 0 else 1 end);
  if v_linha2 is not null then
    v_linhas := v_linhas || v_linha2;
  end if;
  for v_i in 1 .. least(coalesce(cardinality(v_meio), 0), v_lugar) loop
    v_linha := v_meio[v_i]
               || (case when v_i = v_lugar and cardinality(v_meio) > v_lugar
                        then format(' (e mais %s)', cardinality(v_meio) - v_lugar) else '' end);
    v_linhas := v_linhas || v_linha;
    -- O aviso do que não saiu: o aceite e a linha exata. A marca é de orcamento_nao_saiu_avisados, depois de a tarde com
    -- esta linha ir à fila; até lá, o aviso fica na lista do cartão (_orcamento_cartao_aceites) e volta no próximo fechamento.
    if v_meio_aceite[v_i] is not null then
      v_nao_saiu := v_nao_saiu || jsonb_build_array(jsonb_build_object('aceite', v_meio_aceite[v_i], 'linha', v_linha));
    end if;
  end loop;
  if v_linha4 is not null then
    v_linhas := v_linhas || v_linha4;
  end if;

  return jsonb_build_object('fixas', to_jsonb(v_fixas), 'linhas', to_jsonb(v_linhas), 'avisar', to_jsonb(v_avisar),
                            'nao_saiu', v_nao_saiu);
end;
$$;

comment on function public.orcamento_resumo_fechamento(timestamptz) is
  'Retorno F5 (P8.1, C-FECH-O): {fixas, linhas, avisar, nao_saiu}. Só lê. fixas: "Orçamentos: amanhã sai sozinho o lembrete do ORÇ-00151 (Ana) · *segura 151*" (até 3, "e mais N"; os passos citados vão em avisar). linhas (no máximo 4): amanhã N esperam o seu *sim <PIN>* (e os de hoje que ainda esperam); os encerramentos desde a última tarde de turno fechamento que foi à fila (a revisão não conta; o de outro dia diz o dia), perdido com *motivo N B* e a legenda, sem resposta, sem mensagem com a razão, e *motivo N A* só com motivo_marca_aberto; o "Fechado" ou o pedido de dados que não saiu ou pode não ter saído; os enviados vencidos sem desfecho. nao_saiu: [{aceite, linha}] dos avisos que entraram em linhas, para orcamento_nao_saiu_avisados depois do envio. orcamento_modo desligado: só a dos vencidos. 1º nome do cadastro, nunca telefone nem documento.';

revoke all on function public.orcamento_resumo_fechamento(timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_resumo_fechamento(timestamptz) to service_role;

-- ── 5. O aviso da véspera entregue (C-AVISO-O) ─────────────────────────────────────────────────────────────────────────

create or replace function public.orcamento_avisados(p_passos uuid[], p_fila uuid, p_agora timestamptz default now())
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_n integer := 0;
begin
  -- Sem a linha da fila não há como saber se o fechamento chegou: nada é gravado.
  if p_fila is null or p_passos is null or coalesce(cardinality(p_passos), 0) = 0 then
    return 0;
  end if;
  update public.orcamento_passos p
     set avisado_em = coalesce(p_agora, now()), aviso_fila = p_fila
   where p.id = any (p_passos) and p.estado = 'previsto';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

comment on function public.orcamento_avisados(uuid[], uuid, timestamptz) is
  'Retorno F5 (P8.1, C-AVISO-O): depois de o fechamento com a linha fixa ir à fila, grava avisado_em = p_agora e aviso_fila = p_fila nos passos previstos de p_passos. p_fila nulo: 0, nada gravado. Devolve quantos marcou. Só a service_role.';

revoke all on function public.orcamento_avisados(uuid[], uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_avisados(uuid[], uuid, timestamptz) to service_role;

-- ── 5b. O aviso do que não saiu, mostrado (revisão das ondas 4 a 9: banco-2, seguranca-1, edge-fechamento) ─────────────────

-- O aviso do "Fechado" (ou do pedido de dados) que não saiu sai da lista do cartão só depois de a tarde com a linha dele ir à
-- fila: a edge chama com os aceites cujas linhas o texto enviado tem, e com o id da linha da fila da tarde. A tarde que
-- descartou a linha (revisão, corte das extras, tentativa que falhou) não chama, e o aviso continua no cartão e no próximo
-- fechamento.
create or replace function public.orcamento_nao_saiu_avisados(p_aceites uuid[], p_fila uuid, p_agora timestamptz default now())
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_n integer := 0;
begin
  -- Sem a linha da fila não há como saber se o fechamento chegou: nada é gravado.
  if p_fila is null or p_aceites is null or coalesce(cardinality(p_aceites), 0) = 0 then
    return 0;
  end if;
  update public.orcamento_aceites a
     set resultado = a.resultado || jsonb_build_object('nao_saiu_fechado_em', coalesce(p_agora, now()), 'nao_saiu_fila', p_fila)
   where a.id = any (p_aceites) and a.estado in ('com_sinal', 'sem_sinal')
     and a.resultado ? 'saida_nao_saiu' and not (a.resultado ? 'nao_saiu_fechado_em');
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

comment on function public.orcamento_nao_saiu_avisados(uuid[], uuid, timestamptz) is
  'Retorno F5 (P8.1, revisão das ondas 4 a 9): depois de o fechamento com a linha do "Fechado" (ou do pedido de dados) que não saiu ir à fila, grava resultado.nao_saiu_fechado_em = p_agora e nao_saiu_fila = p_fila nos aceites com_sinal/sem_sinal de p_aceites que têm saida_nao_saiu e ainda não têm a marca; o aviso sai da lista do cartão. p_fila nulo: 0, nada gravado. Devolve quantos marcou. Só a service_role.';

revoke all on function public.orcamento_nao_saiu_avisados(uuid[], uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.orcamento_nao_saiu_avisados(uuid[], uuid, timestamptz) to service_role;

-- ── 6. Gerado do corpo vigente, com os trechos -- F5 ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.retorno_carona(p_autor uuid, p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_vivo jsonb;
  v_n integer;
  v_caso uuid;
  v_rotulo text;
  v_prazo text;
  v_texto text;
  v_f5_rotulo text;   -- F5 (P8)
begin
  if v_cfg.id is null or not v_cfg.carona_ligada or v_cfg.modo = 'desligado' then
    return null;
  end if;
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return null;
  end if;
  if v_cfg.carona_em is not null and v_cfg.carona_em > v_agora - v_cfg.carona_intervalo then
    return null;
  end if;

  v_vivo := public.retorno_cartao_vivo(v_agora);
  if v_vivo ->> 'estado' = 'vivo' then
    v_n := jsonb_array_length(v_vivo -> 'itens');
    if v_n = 0 then
      return null;
    end if;
    v_texto := format('Retorno: cartão aberto, %s %s · *retorno*', v_n, case when v_n = 1 then 'caso' else 'casos' end);
  else
    -- F5 (P8): a lista da F5 (casos da F2, aceites e passos à espera do sim). O 1º da lista dá o rótulo; sem caso, o do orçamento.
    begin
      select count(*), (array_agg(c.abertura_id order by c.ordem))[1], (array_agg(c.rotulo order by c.ordem))[1]
        into v_n, v_caso, v_f5_rotulo
        from public._orcamento_cartao_lista(v_agora, null) c;
      if v_n > 0 and v_caso is null then
        update public.retorno_config set carona_em = v_agora where id;
        return jsonb_build_object('texto', format('Retorno: %s esperando (%s) · *retorno*', v_n, v_f5_rotulo));
      end if;
    exception when undefined_function then
      select count(*), (array_agg(c.abertura_id))[1] into v_n, v_caso from public._retorno_cartao_casos(v_agora, null) c;
    end;
    if v_n = 0 then
      return null;
    end if;
    v_rotulo := public._retorno_rotulo(v_caso, v_agora);
    v_prazo := public._retorno_prazo_curto(v_caso, v_agora);
    v_texto := case
      when v_prazo like 'prometi até %' then
        format('Retorno: %s esperando (%s, prometido até %s) · *retorno*', v_n, v_rotulo, substr(v_prazo, char_length('prometi até ') + 1))
      else
        format('Retorno: %s esperando (%s, desde %s) · *retorno*', v_n, v_rotulo,
               (select to_char(a.aberta_em at time zone 'America/Sao_Paulo', 'HH24:MI') from public.retorno_aberturas a where a.id = v_caso))
    end;
  end if;

  update public.retorno_config set carona_em = v_agora where id;
  return jsonb_build_object('texto', v_texto);
end;
$function$;
revoke all on function public.retorno_carona(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_carona(uuid, timestamptz) to service_role;

create or replace function public.retorno_resumo_extra(p_turno text, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_letras constant text[] := array['Z', 'Y', 'X', 'W', 'V'];
  v_agora timestamptz := coalesce(p_agora, now());
  v_hoje date := (v_agora at time zone c_fuso)::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_desde timestamptz;
  v_mandei jsonb;
  v_total integer;
  v_seg date;
  v_semana jsonb;
begin
  if v_cfg.id is null then
    return null;
  end if;
  v_desde := public._retorno_fechamento_anterior(v_agora);

  if p_turno = 'manha' then
    return jsonb_build_object('palavra', v_cfg.cartao_ligado,
      'contatos', jsonb_build_object(
        'vendedores', (select count(*) from public.retorno_aberturas a
                        where a.nivel = 'nada' and a.motivo = 'vendedor' and a.aberta_em > v_desde and a.aberta_em <= v_agora),
        'conhecidos', (select count(*) from public.retorno_aberturas a
                        where a.nivel = 'nada' and a.motivo = 'contato_conhecido' and a.aberta_em > v_desde and a.aberta_em <= v_agora)));
  end if;

  select count(*) into v_total
    from public.retorno_saidas s
   where (s.tipo like 'modelo\_%' escape '\' or s.emissor = 'orcamento')   -- F5 (P8): a cadência sozinha também
     and coalesce((s.dados ->> 'sozinho')::boolean, false)
     and s.estado in ('enviada', 'incerta') and s.decidida_em > v_desde and s.decidida_em <= v_agora;

  select coalesce(jsonb_agg(x.o order by x.ord), '[]'::jsonb) into v_mandei
    from (select l.ord, jsonb_build_object('letra', s.letra, 'rotulo', case when s.emissor = 'orcamento' then public._orcamento_rotulo_da_saida(s.id) else public._retorno_rotulo(s.abertura_id, v_agora) end,   -- F5 (P8)
                                           'tipo_curto', public._retorno_tipo_curto(s.tipo), 'saida_id', s.id) as o
            from public.retorno_saidas s
            join unnest(c_letras) with ordinality as l(letra, ord) on l.letra = s.letra
           where (s.tipo like 'modelo\_%' escape '\' or s.emissor = 'orcamento')   -- F5 (P8)
             and coalesce((s.dados ->> 'sozinho')::boolean, false)
             and s.estado in ('enviada', 'incerta') and s.decidida_em > v_desde and s.decidida_em <= v_agora
           order by l.ord
           limit 3) x;

  -- Só na sexta útil, como as alongadas da F1.
  if extract(isodow from v_hoje) = 5 and public._retorno_dia_de_tarde(v_hoje) then
    v_seg := v_hoje - 4;
    select jsonb_build_object(
             'recibos', count(*) filter (where s.id is not null),
             'recibo_12min', count(*) filter (where s.id is not null and s.decidida_em - a.aberta_em <= interval '12 minutes'),
             'hora_casos', count(*) filter (where a.prometido_ate is not null and a.recibo_em is not null),
             'hora_cumprida', count(*) filter (where a.prometido_ate is not null and a.recibo_em is not null
                                                 and a.cumprida_em <= coalesce(a.segundo_prazo, a.prometido_ate)),
             'vencida_sem_aviso', count(*) filter (where a.estado = 'vencida' and a.adiamento_em is null and a.fim_do_dia_em is null),
             'insistencia', count(*) filter (where a.insistencias > 0),
             'toques', (select count(*) from public.retorno_toques t where (t.em at time zone c_fuso)::date between v_seg and v_hoje),
             'dias_uteis', (select count(*) from generate_series(v_seg, v_hoje, interval '1 day') d where public.agenda_dia_util(d::date)))
      into v_semana
      from public.retorno_aberturas a
      left join lateral (select o.id, o.decidida_em from public.retorno_saidas o
                          where o.abertura_id = a.id and o.tipo in ('recibo_cliente', 'recibo_ambiguo', 'recibo_numero_novo')
                            and o.estado in ('enviada', 'incerta')
                          order by o.decidida_em limit 1) s on true
     where (a.aberta_em at time zone c_fuso)::date between v_seg and v_hoje
       and a.aberta_em <= v_agora
       and a.nivel in ('recibo', 'passagem');
  end if;

  return jsonb_build_object(
    'palavra', v_cfg.cartao_ligado,
    'mandei', v_mandei,
    'mandei_mais', greatest(0, v_total - jsonb_array_length(v_mandei)),
    'promovidos', (select coalesce(jsonb_agg(public._retorno_tipo_curto(t.tipo) order by t.tipo), '[]'::jsonb)
                     from public.retorno_modelo_tipos t where t.promovido_em > v_desde and t.promovido_em <= v_agora and t.nivel = 'sozinho'),
    'rebaixados', (select coalesce(jsonb_agg(jsonb_build_object('tipo_curto', public._retorno_tipo_curto(t.tipo), 'motivo', t.rebaixado_motivo) order by t.tipo), '[]'::jsonb)
                     from public.retorno_modelo_tipos t where t.rebaixado_em > v_desde and t.rebaixado_em <= v_agora),
    'suspensos', (select coalesce(jsonb_agg(public._retorno_tipo_curto(t.tipo) order by t.tipo), '[]'::jsonb)
                    from public.retorno_modelo_tipos t
                   where t.promocao_suspensa_ate > v_agora and t.promocao_suspensa_ate - v_cfg.fadiga_suspende > v_desde),
    'semana', v_semana);
end;
$$;
revoke all on function public.retorno_resumo_extra(text, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_resumo_extra(text, timestamptz) to service_role;

create or replace function public._retorno_dito_errado(p_letra text, p_agora timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_hoje date := (p_agora at time zone c_fuso)::date;
  v_cfg public.retorno_config := public._retorno_cfg();
  v_s public.retorno_saidas;
  v_dia date;
  v_limite timestamptz;
  v_i integer;
begin
  select s.* into v_s
    from public.retorno_saidas s
   where s.letra = p_letra
     and s.letra_dia <= v_hoje
     and not s.dados ? 'errado_em'
   order by s.letra_dia desc, s.decidida_em desc nulls last, s.id
   limit 1;
  if found then
    v_dia := v_s.letra_dia;
    for v_i in 1 .. 10 loop
      v_dia := v_dia + 1;
      exit when public._retorno_dia_de_tarde(v_dia);
    end loop;
    v_limite := (v_dia + v_cfg.ponto_fechamento) at time zone c_fuso;
  end if;
  if not found or p_agora >= v_limite then
    return jsonb_build_object('ok', true, 'texto', format('Não achei a letra %s no último "Mandei sozinho".', p_letra));
  end if;

  perform public._retorno_rebaixar(v_s.tipo, 'errado', p_agora);
  update public.retorno_saidas s
     set dados = s.dados || jsonb_build_object('errado_em', p_agora), atualizada_em = now()
   where s.id = v_s.id;
  perform public._retorno_toque('errado', null, v_s.abertura_id, p_agora);

  return jsonb_build_object('ok', true,
    'texto', format('Anotei: ''%s'' voltou ao cartão e não sai mais sozinho. Se quiser corrigir com %s, responda pelo celular.',
                    public._retorno_tipo_curto(v_s.tipo),
                    -- F5 (P8): a saída do orçamento não tem caso; o rótulo é o do cliente, como o _retorno_rotulo dá no caso de cliente.
                    case when v_s.abertura_id is null and v_s.emissor = 'orcamento'
                         then coalesce(public._retorno_nome(v_s.client_id), 'cliente sem nome')
                         else public._retorno_rotulo(v_s.abertura_id, p_agora) end));
end;
$$;
revoke all on function public._retorno_dito_errado(text, timestamptz) from public, anon, authenticated;

-- ── 7. A amostra da auditoria (recriada à mão, mesmas colunas e mesma ordem) ───────────────────────────────────────────

create or replace view public.retorno_auditoria_lista with (security_invoker = on) as
select s.enviada_em, s.tipo, s.texto,
       case when s.emissor = 'orcamento' then public._orcamento_rotulo_da_saida(s.id)
            else public._retorno_rotulo(s.abertura_id, null) end as rotulo,
       public._retorno_pedido_do_caso(s.abertura_id, coalesce(s.enviada_em, s.decidida_em)) as trecho,
       s.dados -> 'fato' as fato, s.dados -> 'fato' ->> 'fonte' as fonte, s.dados ->> 'errado_em' as errado_em
  from public.retorno_saidas s
 where (s.tipo like 'modelo\_%' escape '\' or s.emissor = 'orcamento')   -- F5 (P8)
   and coalesce((s.dados ->> 'sozinho')::boolean, false)
   and s.estado in ('enviada', 'incerta')
   and (coalesce((s.dados ->> 'auditoria')::boolean, false) or s.letra is null or s.letra in ('W', 'V'));

comment on view public.retorno_auditoria_lista is
  'Retorno F2 (P12.1) e F5 (P8.1): a amostra de 1 em auditoria_cada por tipo e o que passou de 3 no dia, também das saídas sozinhas do orçamento (com o rótulo do orçamento). Tem a pergunta do cliente: nunca sai pelo WhatsApp.';

revoke all on public.retorno_auditoria_lista from public, anon, authenticated;
grant select on public.retorno_auditoria_lista to service_role;
