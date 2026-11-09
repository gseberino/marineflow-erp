-- Retorno rápido ao cliente, F3 (P6): decidir as letras novas e preparar o orçamento. Gerada por script (scripts/gerar_f3.cjs decidir) a partir do corpo
-- vigente; só os trechos marcados -- F3 são novos.
--
-- 1. _retorno_decidir_letra: B (o outro parecido) e as letras de unidade. *L* reusa responder, e o update passa a limpar acao_sim. A letra D descarta as propostas vivas.
-- 2. retorno_decidir_dito: *dita* com cara de ajuste da proposta é recusado, sem gravar (7.3).
-- 3. retorno_cartao_executar: o item de orçamento entra em "orcamentos" (o SQL só decide; quem cria e manda é a ferramenta, P8), e nunca em "Vai sair".
-- 4. retorno_previa_preparar (C-PREP): as 8 regras, em ordem, a devolutiva única e os args do construtor. retorno_previa_caiu, _soltar, _orc_criado, _pdf, _ver (C-VER, STABLE: só lê), _retorno e _aplicar.
--
-- Tudo nasce desligado: sem proposta viva e sem letra nova no item, nada aqui é alcançado. Reverter: reaplicar as versões de 20261123100500 e, de retorno_vigia_cartao, a de 20261201100000; a de retorno_ver_caso_para_modelo exige o drop da assinatura com p_sessao.

-- ── 1. Auxiliares ───────────────────────────────────────────────────────────────────────────────────

-- As flags por ação: PDF de rascunho e origem ditado exigem o ditado ligado; origem historico exige a proposta ligada.
create or replace function public._retorno_previa_liberada(p_acao text, p_origem text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cfg public.retorno_config := public._retorno_cfg();
begin
  if p_acao = 'pdf' or p_origem = 'ditado' then
    return coalesce(v_cfg.previa_ditado_ligado, false);
  end if;
  if p_origem = 'historico' then
    return coalesce(v_cfg.previa_modo = 'ligado', false);
  end if;
  return false;
end;
$$;

comment on function public._retorno_previa_liberada(text, text) is
  'Retorno F3 (P6): o PDF e o ditado exigem previa_ditado_ligado; a proposta do histórico exige previa_modo = ligado. Reverter vale para o cartão vivo: o item cai aqui em vez de criar.';

revoke all on function public._retorno_previa_liberada(text, text) from public, anon, authenticated;

-- A mesma regra de compliance-guard.ts: H_INICIO = 8, H_FIM = 20, Brasília.
create or replace function public._retorno_fora_do_horario_de_envio(p_agora timestamptz)
returns boolean
language sql
immutable
set search_path = public
as $$
  select extract(hour from coalesce(p_agora, now()) at time zone 'America/Sao_Paulo') < 8
      or extract(hour from coalesce(p_agora, now()) at time zone 'America/Sao_Paulo') >= 20;
$$;

comment on function public._retorno_fora_do_horario_de_envio(timestamptz) is
  'Retorno F3 (P6): fora das 8h–20h de Brasília, o mesmo intervalo de compliance-guard.ts. A guardaDeEnvio continua em orcarEEnviar, como segunda linha.';

revoke all on function public._retorno_fora_do_horario_de_envio(timestamptz) from public, anon, authenticated;

-- A recusa do preparo: a devolutiva e o que acontece com o item. Regra 0: item fora. Regra 1 (só o dono): nada. Regras 2 a 7: item feito
-- (caminho do cartão, já decidido) cai com o motivo; item vivo em cartão vivo (ditado) remonta; a proposta segue viva, salvo cliente_final.
create or replace function public._retorno_previa_recusa(p_abertura uuid, p_previa uuid, p_item uuid, p_regra integer, p_motivo text, p_frase text, p_agora timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_i public.retorno_cartao_itens;
  v_rotulo text := coalesce(public._retorno_rotulo(p_abertura, p_agora), 'contato');
begin
  if p_item is not null then
    select * into v_i from public.retorno_cartao_itens i where i.id = p_item;
    if found then
      if p_regra = 0 then
        update public.retorno_cartao_itens i set estado = 'fora' where i.id = p_item and i.estado in ('vivo', 'feito');
      elsif p_regra between 2 and 7 then
        if v_i.estado = 'feito' then
          update public.retorno_cartao_itens i
             set estado = 'caiu', caiu_motivo = p_motivo, decidido_em = coalesce(i.decidido_em, p_agora)
           where i.id = p_item;
        elsif v_i.estado = 'vivo'
              and exists (select 1 from public.retorno_cartoes c where c.id = v_i.cartao_id and c.estado = 'vivo') then
          perform public._retorno_item_remontar(p_item, p_agora);
        end if;
      end if;
    end if;
  end if;
  if p_regra = 5 and p_previa is not null then
    update public.retorno_previa p
       set estado = 'caiu', decidida_em = p_agora, atualizada_em = p_agora
     where p.id = p_previa and p.estado = 'proposta';
  end if;
  return jsonb_build_object('ok', false, 'motivo', p_motivo, 'frase', p_frase, 'rotulo', v_rotulo);
end;
$$;

revoke all on function public._retorno_previa_recusa(uuid, uuid, uuid, integer, text, text, timestamptz) from public, anon, authenticated;

-- ── 2. O preparo (C-PREP) ──────────────────────────────────────────────────────────────────────────

create or replace function public.retorno_previa_preparar(p_previa uuid, p_item uuid, p_autor uuid, p_agora timestamptz default now(), p_so uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_pv public.retorno_previa;
  v_i public.retorno_cartao_itens;
  v_ab public.retorno_aberturas;
  v_abertura uuid;
  v_rasc jsonb;
  v_so public.service_orders;
  v_cad jsonb;
  v_cli uuid;
  v_ves uuid;
  v_unidades jsonb;
  v_fone text;
  v_quatro text;
  v_nomes text;
  v_acao text := case when p_so is not null then 'pdf' else 'orcar' end;
  v_legenda jsonb;
  v_previa_pdf uuid;
  v_origem text;
  v_items jsonb;
  v_labor jsonb;
  v_args jsonb;
  v_saida jsonb;
begin
  if p_previa is not null then
    select * into v_pv from public.retorno_previa p where p.id = p_previa;
  end if;
  if p_item is not null then
    select * into v_i from public.retorno_cartao_itens i where i.id = p_item;
  end if;
  v_abertura := coalesce(v_pv.abertura_id, v_i.abertura_id);
  select * into v_ab from public.retorno_aberturas a where a.id = v_abertura;

  -- Regra 0: a flag da ação.
  if not public._retorno_previa_liberada(v_acao, v_pv.origem) then
    return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 0, 'desligado',
      'não saiu, porque o orçamento pelo cartão foi desligado; não criei nada', v_agora);
  end if;

  -- Regra 1: só o dono. Sem mexer em nada: outro autor não pode derrubar o item de ninguém.
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 1, 'nao_e_o_dono',
      'não saiu, porque só o dono pode fazer isso; não criei nada', v_agora);
  end if;

  -- Regra 2: proposta viva e caso aberto. No ramo do rascunho, o rascunho tem de ser exatamente o que o cartão oferece.
  if v_acao = 'orcar' then
    if v_ab.id is null or v_ab.estado = 'fechada' or v_pv.id is null or v_pv.estado <> 'proposta' then
      return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 2, 'caso_fechado', 'já não está aberto; não criei nada', v_agora);
    end if;
  else
    v_rasc := public._retorno_rascunho_do_caso(v_abertura, v_agora);
    if v_ab.id is null or v_ab.estado = 'fechada' or v_rasc is null or (v_rasc ->> 'service_order_id')::uuid is distinct from p_so then
      return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 2, 'caso_fechado', 'já não está aberto; não criei nada', v_agora);
    end if;
    select * into v_so from public.service_orders so where so.id = p_so;
  end if;

  -- Regra 3: nada provisório; nenhum total zerado.
  if v_acao = 'orcar' then
    if v_pv.provisorios_n > 0 then
      select string_agg(left(l.nome, 40), ', ' order by l.ordem) into v_nomes
        from public.retorno_previa_linhas l where l.previa_id = v_pv.id and l.estado = 'provisorio';
      return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 3, 'item_provisorio',
        format('tem item a completar (%s): não criei nada. Mande *retorno* e dite o que falta', v_nomes), v_agora);
    end if;
    if v_pv.linhas_n <= 0 or v_pv.total <= 0 then
      return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 3, 'item_provisorio',
        'está sem nenhum item: dite o que entra; não criei nada', v_agora);
    end if;
  else
    if coalesce((v_rasc ->> 'total')::numeric, 0) <= 0 or (v_rasc ->> 'linhas_n')::integer <= 0 or (v_rasc ->> 'linhas_sem_preco')::integer > 0 then
      return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 3, 'rascunho_sem_valor',
        format('ficou com o rascunho %s sem valor: complete na tela; não mandei', v_rasc ->> 'numero'), v_agora);
    end if;
  end if;

  -- Regra 4: cliente e unidade definidos e ativos. No rascunho, sempre os de service_orders, nunca os do caso.
  if v_acao = 'orcar' then
    v_cad := public._retorno_cadastro_do_caso(v_abertura);
    v_cli := (v_cad ->> 'client_id')::uuid;
    if v_cli is null then
      return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 4, 'sem_cadastro',
        'ainda não tem cadastro completo: mande *retorno* quando ele responder; não criei nada', v_agora);
    end if;
    v_ves := coalesce(v_pv.vessel_id, (public._retorno_unidade_do_caso(v_abertura, v_cli, v_agora) ->> 'vessel_id')::uuid);
    if v_ves is null or not exists (select 1 from public.vessels v where v.id = v_ves and v.active and v.client_id = v_cli) then
      v_unidades := public._retorno_unidades_do_cliente(v_cli);
      if jsonb_array_length(v_unidades) >= 2 then
        return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 4, 'sem_cadastro',
          'está sem unidade escolhida: mande *retorno* e a letra; não criei nada', v_agora);
      end if;
      return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 4, 'sem_cadastro',
        'está sem unidade no cadastro: cadastre e mande *retorno*; não criei nada', v_agora);
    end if;
  else
    v_cli := v_so.client_id;
    v_ves := v_so.vessel_id;
    if not exists (select 1 from public.clients c where c.id = v_cli and c.active) then
      return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 4, 'sem_cadastro',
        'ainda não tem cadastro completo: mande *retorno* quando ele responder; não criei nada', v_agora);
    end if;
    if v_ves is null or not exists (select 1 from public.vessels v where v.id = v_ves and v.active) then
      return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 4, 'sem_cadastro',
        'está sem unidade no cadastro: cadastre e mande *retorno*; não criei nada', v_agora);
    end if;
  end if;

  -- Regra 5: Cliente Final. A proposta cai (a regra 5 de _retorno_previa_recusa).
  if exists (select 1 from public.clients c where c.id = v_cli and c.generico) then
    return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 5, 'cliente_final', 'está no Cliente Final: use o celular; não criei nada', v_agora);
  end if;

  -- Regra 6: o contato do caso. O PDF nunca vai a um número que o dono não reconhece.
  select coalesce(c.whatsapp, c.phone) into v_fone from public.clients c where c.id = v_cli;
  if public._agenda_chave_telefone(v_fone) is distinct from v_ab.chave then
    v_quatro := right(regexp_replace(coalesce(v_fone, ''), '[^0-9]', '', 'g'), 4);
    return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 6, 'contato_diferente',
      format('não saiu, porque o WhatsApp do cadastro (••%s) não é o número do caso: corrija o cadastro ou mande pelo celular; não criei nada', v_quatro), v_agora);
  end if;

  -- Regra 7: canal livre. A mesma expressão da regra 5 de _retorno_item_conferir: o ditado com cartão caído não passa pelo conferir.
  if public.canal_bloqueado(v_ab.phone_normalized) is not null
     or v_ab.nivel = 'nada'
     or exists (select 1 from public.whatsapp_leads l
                 where l.lead_tipo = 'pessoal' and public._agenda_chave_telefone(l.phone_normalized) = v_ab.chave) then
    return public._retorno_previa_recusa(v_abertura, p_previa, p_item, 7, 'canal_bloqueado',
      'pediu para não receber mensagem automática; não criei nada', v_agora);
  end if;

  -- Passou. A legenda decide nome, apresentação e a data que vai ao PDF: legenda e documento nunca calculam separado.
  if v_acao = 'pdf' then
    v_previa_pdf := p_previa;
    if v_previa_pdf is null then
      select p.id into v_previa_pdf from public.retorno_previa p
       where p.service_order_id = p_so and p.estado = 'virou_orc'
       order by p.criada_em desc, p.id
       limit 1;
    end if;
    v_legenda := public.retorno_legenda_do_orcamento(v_abertura, v_previa_pdf, v_agora, v_cli);
    return jsonb_build_object('ok', true, 'acao', 'pdf', 'previa_id', v_previa_pdf, 'abertura_id', v_abertura,
      'rotulo', public._retorno_rotulo(v_abertura, v_agora), 'chave8', v_ab.chave,
      'total', coalesce(v_so.grand_total, 0), 'numero', v_so.service_order_number,
      'validade_data', v_legenda ->> 'validade_data', 'legenda', v_legenda);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('product_id', l.product_id, 'quantity', l.quantidade, 'unit_price', l.preco, 'keyword', l.nome) order by l.ordem), '[]'::jsonb)
    into v_items
    from public.retorno_previa_linhas l
   where l.previa_id = v_pv.id and l.tipo = 'peca';
  select coalesce(jsonb_agg(jsonb_build_object('service_id', l.service_id, 'description', l.nome, 'price', l.preco, 'quantity', l.quantidade,
                                               'billing_unit', coalesce(s.billing_unit, 'unit')) order by l.ordem), '[]'::jsonb)
    into v_labor
    from public.retorno_previa_linhas l
    left join public.services s on s.id = l.service_id
   where l.previa_id = v_pv.id and l.tipo = 'servico';

  v_origem := case when v_pv.origem = 'ditado' or coalesce((v_pv.dados ->> 'ajustada_por_ditado')::boolean, false) then 'retorno_ditado' else 'retorno_previa' end;
  v_args := jsonb_build_object('client_id', v_cli, 'vessel_id', v_ves, 'title', v_pv.titulo, 'items', v_items, 'labor', v_labor,
                               'payment_conditions', v_pv.condicao_pagamento, 'origem', v_origem);

  v_legenda := public.retorno_legenda_do_orcamento(v_abertura, v_pv.id, v_agora);
  v_saida := jsonb_build_object('ok', true, 'acao', 'orcar', 'previa_id', v_pv.id, 'abertura_id', v_abertura,
    'rotulo', public._retorno_rotulo(v_abertura, v_agora), 'chave8', v_ab.chave, 'total', v_pv.total,
    'validade_data', v_legenda ->> 'validade_data', 'legenda', v_legenda, 'args', v_args);
  return v_saida;
end;
$$;

comment on function public.retorno_previa_preparar(uuid, uuid, uuid, timestamptz, uuid) is
  'Retorno F3 (P6, C-PREP): confere as 8 regras em ordem e devolve a devolutiva única com a legenda e, para orcar, os args do construtor; a primeira que falha devolve {ok: false, motivo, frase, rotulo}. p_so preenchido é o ramo do PDF de rascunho, em que cliente e unidade vêm de service_orders. quote_validity_days não vem daqui; a data vem da legenda.';

revoke all on function public.retorno_previa_preparar(uuid, uuid, uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.retorno_previa_preparar(uuid, uuid, uuid, timestamptz, uuid) to service_role;

-- ── 3. Os finais do orçamento ───────────────────────────────────────────────────────────────────────

create or replace function public.retorno_previa_caiu(p_previa uuid, p_item uuid, p_motivo text, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cartao uuid;
begin
  if p_item is not null then
    update public.retorno_cartao_itens i
       set estado = 'caiu', caiu_motivo = p_motivo, decidido_em = coalesce(i.decidido_em, v_agora)
     where i.id = p_item and i.estado in ('vivo', 'feito')
     returning i.cartao_id into v_cartao;
    -- Revisão da F3: o último item vivo saiu pelo ditado: o cartão não fica vivo sem nada.
    if v_cartao is not null and not public._retorno_cartao_fechar_se_vazio(v_cartao, v_agora) then
      update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = v_cartao and c.estado = 'vivo';
    end if;
  end if;
  if p_previa is not null then
    update public.retorno_previa p
       set estado = 'caiu', decidida_em = v_agora, atualizada_em = v_agora
     where p.id = p_previa and p.estado = 'proposta';
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.retorno_previa_caiu(uuid, uuid, text, timestamptz) is
  'Retorno F3 (P6, C-CAIU): o construtor recusou (rascunho recente: orc_existe): marca o item caiu com o motivo e a proposta caiu.';

revoke all on function public.retorno_previa_caiu(uuid, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_previa_caiu(uuid, uuid, text, timestamptz) to service_role;

create or replace function public.retorno_previa_soltar(p_item uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_i public.retorno_cartao_itens;
  v_vivo boolean;
begin
  select * into v_i from public.retorno_cartao_itens i where i.id = p_item for update;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  select c.estado = 'vivo' into v_vivo from public.retorno_cartoes c where c.id = v_i.cartao_id;
  if v_i.estado = 'vivo' and v_vivo then
    perform public._retorno_item_remontar(p_item, v_agora);
  elsif v_i.estado = 'feito' then
    -- O cartão já foi decidido: o caso volta no próximo *retorno*, e decidido_em fica: é o ato do dono que a P11 conta.
    update public.retorno_cartao_itens i set estado = 'fora' where i.id = p_item;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.retorno_previa_soltar(uuid, timestamptz) is
  'Retorno F3 (P6, C-SOLTAR): o orçamento não terminou. Item vivo em cartão vivo remonta; item feito vai a fora, mantendo decidido_em; outro estado: nada.';

revoke all on function public.retorno_previa_soltar(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_previa_soltar(uuid, timestamptz) to service_role;

create or replace function public.retorno_previa_orc_criado(p_previa uuid, p_so uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
begin
  update public.retorno_previa p
     set service_order_id = p_so, estado = 'virou_orc', decidida_em = coalesce(p.decidida_em, v_agora), atualizada_em = v_agora
   where p.id = p_previa and p.estado = 'proposta';
  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.retorno_previa_orc_criado(uuid, uuid, timestamptz) is
  'Retorno F3 (P6, C-ORC-LIGA): grava o ORÇ nascido na proposta (virou_orc). Idempotente.';

revoke all on function public.retorno_previa_orc_criado(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_previa_orc_criado(uuid, uuid, timestamptz) to service_role;

create or replace function public.retorno_previa_pdf(p_previa uuid, p_ok boolean, p_chave text, p_agora timestamptz default now(),
                                                     p_so uuid default null, p_abertura uuid default null, p_item uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_id uuid := p_previa;
  v_abertura uuid := p_abertura;
  v_so public.service_orders;
  v_ab public.retorno_aberturas;
  v_n integer;
  v_cartao uuid;
begin
  if not coalesce(p_ok, false) then
    return jsonb_build_object('ok', true);   -- p_ok falso não grava nada: o ORÇ volta ao cartão pela linha 1
  end if;

  if v_id is null and p_so is not null then
    select p.id into v_id from public.retorno_previa p
     where p.service_order_id = p_so and p.estado = 'virou_orc'
     order by p.criada_em desc, p.id
     limit 1;
  end if;

  if v_id is not null then
    update public.retorno_previa p
       set pdf_em = coalesce(p.pdf_em, v_agora), pdf_chave = coalesce(p_chave, p.pdf_chave), atualizada_em = v_agora
     where p.id = v_id
     returning p.abertura_id into v_abertura;
  elsif p_so is not null then
    -- PDF de rascunho sem proposta: a linha origem 'rascunho' existe para a medida e para a apresentação, e só o PDF que saiu a cria.
    select * into v_so from public.service_orders so where so.id = p_so;
    select * into v_ab from public.retorno_aberturas a where a.id = v_abertura;
    if v_so.id is not null and v_ab.id is not null then
      select (select count(*) from public.service_order_parts p where p.service_order_id = p_so)
           + (select count(*) from public.service_order_services s where s.service_order_id = p_so)
        into v_n;
      insert into public.retorno_previa (abertura_id, chave, client_id, vessel_id, origem, estado, modo, service_order_id, titulo, familias, total,
                                         linhas_n, provisorios_n, linhas_iniciais, hash, pdf_em, pdf_chave, decidida_em, criada_em, atualizada_em)
      values (v_ab.id, v_ab.chave, v_so.client_id, v_so.vessel_id, 'rascunho', 'virou_orc', 'ligado', p_so,
              left('Rascunho ' || coalesce(v_so.service_order_number, ''), 120), '{}', coalesce(v_so.grand_total, 0),
              coalesce(v_n, 0), 0, '[]', '', v_agora, p_chave, v_agora, v_agora, v_agora);
    end if;
  end if;

  if p_item is not null then
    update public.retorno_cartao_itens i
       set estado = 'feito', decidido_em = coalesce(i.decidido_em, v_agora)
     where i.id = p_item and i.estado = 'vivo'
     returning i.cartao_id into v_cartao;
    if v_cartao is not null then
      -- Revisão da F3: decide antes de refazer o texto. Era o último caso? O cartão não fica vivo sem item.
      perform public._retorno_cartao_fechar_se_vazio(v_cartao, v_agora);
      update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = v_cartao;
    end if;
  elsif v_abertura is not null then
    -- O cartão caiu antes do *sim <PIN>*: quem fecha o caso é o PDF que saiu.
    update public.retorno_aberturas a
       set cumprida_em = coalesce(a.cumprida_em, v_agora), cumprida_por = coalesce(a.cumprida_por, 'cartao'),
           estado = 'fechada', fechada_em = coalesce(a.fechada_em, v_agora), fechada_motivo = coalesce(a.fechada_motivo, 'conteudo'),
           atualizada_em = now()
     where a.id = v_abertura;
    update public.retorno_saidas s
       set estado = 'cancelada', motivo = 'caso_fechado', decidida_em = v_agora, atualizada_em = now()
     where s.abertura_id = v_abertura and s.estado = 'agendada';
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.retorno_previa_pdf(uuid, boolean, text, timestamptz, uuid, uuid, uuid) is
  'Retorno F3 (P6, C-PDF): o PDF saiu: grava pdf_em e a chave do telefone que recebeu; rascunho sem proposta ganha a linha origem rascunho. p_ok falso não grava nada. Com item vivo (ditado), item feito, cartão refeito e, se era o último item, decidido; sem item (cartão caído), fecha o caso.';

revoke all on function public.retorno_previa_pdf(uuid, boolean, text, timestamptz, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.retorno_previa_pdf(uuid, boolean, text, timestamptz, uuid, uuid, uuid) to service_role;

-- Gerado do corpo vigente (20261123100500), com o trecho -- F3: o ditado livre também não deixa o cartão vivo sem item.
create or replace function public.retorno_caso_respondido(p_item uuid, p_texto text, p_wa_id text default null, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cartao uuid;   -- F3 (revisão)
  v_r jsonb;
begin
  update public.retorno_cartao_itens i
     set texto_ditado = left(p_texto, 1000), ditado_via = 'assistente', estado = 'feito', decidido_em = v_agora
   where i.id = p_item
   returning i.cartao_id into v_cartao;
  v_r := public.retorno_item_enviado(p_item, true, p_wa_id, v_agora);
  perform public._retorno_cartao_fechar_se_vazio(v_cartao, v_agora);   -- F3 (revisão)
  return v_r;
end;
$$;

-- ── 4. A leitura e o ditado ─────────────────────────────────────────────────────────────────────────

create or replace function public.retorno_previa_ver(p_n integer, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cartao public.retorno_cartoes;
  v_status text;
  v_i public.retorno_cartao_itens;
  v_ab public.retorno_aberturas;
  v_pv public.retorno_previa;
  v_cli uuid;
  v_ves uuid;
  v_unidades jsonb;
  v_linhas jsonb;
  v_un_nome text;
  v_hash text;
  v_generico boolean := false;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('erro', 'nao_e_o_dono');
  end if;

  select c.* into v_cartao from public.retorno_cartoes c where c.estado = 'vivo' limit 1;
  if v_cartao.id is null then
    return jsonb_build_object('erro', 'sem_cartao');
  end if;
  if v_cartao.pendencia_id is not null then
    select p.status into v_status from public.ai_operator_pending_actions p where p.id = v_cartao.pendencia_id;
    if v_status in ('rejected', 'expired', 'executed', 'failed') then
      return jsonb_build_object('erro', 'sem_cartao');
    end if;
  end if;

  select i.* into v_i from public.retorno_cartao_itens i
   where i.cartao_id = v_cartao.id and i.n = p_n and i.estado = 'vivo';
  if v_i.id is null then
    return jsonb_build_object('erro', 'sem_caso');
  end if;
  select * into v_ab from public.retorno_aberturas a where a.id = v_i.abertura_id;

  select p.* into v_pv from public.retorno_previa p where p.abertura_id = v_ab.id and p.estado = 'proposta' limit 1;
  v_cli := (public._retorno_cadastro_do_caso(v_ab.id) ->> 'client_id')::uuid;
  v_ves := coalesce(v_pv.vessel_id, (public._retorno_unidade_do_caso(v_ab.id, v_cli, v_agora) ->> 'vessel_id')::uuid);
  if v_cli is not null then
    select coalesce(c.generico, false) into v_generico from public.clients c where c.id = v_cli;
  end if;
  v_unidades := public._retorno_unidades_do_cliente(v_cli);
  if jsonb_array_length(v_unidades) < 2 then
    v_unidades := '[]'::jsonb;
  end if;
  select left(v.name, 30) into v_un_nome from public.vessels v where v.id = v_ves;

  if v_pv.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'linha', l.ordem, 'tipo', l.tipo, 'product_id', l.product_id, 'service_id', l.service_id, 'nome', l.nome,
             'quantidade', l.quantidade, 'preco', l.preco, 'fonte', l.preco_fonte, 'em', l.preco_em,
             'rotulo', public._retorno_rotulo_do_preco(l.preco_fonte, l.preco_em), 'estado', l.estado, 'motivo', l.motivo) order by l.ordem), '[]'::jsonb)
      into v_linhas
      from public.retorno_previa_linhas l where l.previa_id = v_pv.id;
    v_hash := public._retorno_previa_hash_efetivo(v_pv.id, v_agora);
  else
    v_linhas := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'n', p_n, 'rotulo', public._retorno_rotulo(v_ab.id, v_agora), 'titulo', v_pv.titulo, 'total', coalesce(v_pv.total, 0), 'hash', v_hash,
    'linhas', v_linhas, 'abertura_id', v_ab.id, 'phone', v_ab.phone_normalized, 'client_id', v_cli, 'vessel_id', v_ves, 'unidade_nome', v_un_nome,
    'unidades', v_unidades, 'previa_id', v_pv.id, 'ditado_ligado', (public._retorno_cfg()).previa_ditado_ligado, 'cliente_generico', v_generico,
    'validade', public._retorno_quando(public._retorno_validade_do_envio(v_agora), (v_agora at time zone 'America/Sao_Paulo')::date));
end;
$$;

comment on function public.retorno_previa_ver(integer, uuid, timestamptz) is
  'Retorno F3 (P6, C-VER): as linhas da proposta viva do item n do cartão aberto, sem texto do cliente. STABLE: acha o item por select direto e não mexe em nada; proposta só em sombra dá previa_id nulo e linhas vazia. {erro: nao_e_o_dono | sem_cartao | sem_caso}.';

revoke all on function public.retorno_previa_ver(integer, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_previa_ver(integer, uuid, timestamptz) to service_role;

create or replace function public.retorno_previa_retrato(p_abertura uuid, p_previa uuid, p_hash text, p_phone text, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_ab public.retorno_aberturas;
  v_pv public.retorno_previa;
  v_item uuid;
  v_n integer;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'motivo', 'mudou');
  end if;
  if not coalesce((public._retorno_cfg()).previa_ditado_ligado, false) then
    return jsonb_build_object('ok', false, 'motivo', 'desligado');
  end if;
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if v_ab.id is null or v_ab.estado = 'fechada' or v_ab.phone_normalized is distinct from p_phone then
    return jsonb_build_object('ok', false, 'motivo', 'mudou');
  end if;

  if p_previa is null then
    if exists (select 1 from public.retorno_previa p where p.abertura_id = p_abertura and p.estado = 'proposta') then
      return jsonb_build_object('ok', false, 'motivo', 'mudou');
    end if;
  else
    select * into v_pv from public.retorno_previa p where p.id = p_previa;
    if v_pv.id is null or v_pv.estado <> 'proposta' or public._retorno_previa_hash_efetivo(p_previa, v_agora) is distinct from p_hash then
      return jsonb_build_object('ok', false, 'motivo', 'mudou');
    end if;
  end if;

  select i.id, i.n into v_item, v_n
    from public.retorno_cartao_itens i
    join public.retorno_cartoes c on c.id = i.cartao_id
   where i.abertura_id = p_abertura and i.estado = 'vivo' and c.estado = 'vivo'
   limit 1;
  return jsonb_build_object('ok', true, 'item_id', v_item, 'n', v_n);
end;
$$;

comment on function public.retorno_previa_retrato(uuid, uuid, text, text, uuid, timestamptz) is
  'Retorno F3 (P6, C-RETRATO): na execução do ditado, confere que o que o dono aprovou ainda vale: dono, flag, caso aberto, telefone, proposta e hash. {ok, item_id, n} (item_id nulo se o cartão já caiu) ou {ok: false, motivo: desligado | mudou}.';

revoke all on function public.retorno_previa_retrato(uuid, uuid, text, text, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_previa_retrato(uuid, uuid, text, text, uuid, timestamptz) to service_role;

create or replace function public.retorno_previa_aplicar(p_previa uuid, p_plano jsonb, p_autor uuid, p_agora timestamptz default now(), p_item uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_linhas jsonb := p_plano -> 'linhas';
  v_id uuid := p_previa;
  v_ab public.retorno_aberturas;
  v_pv public.retorno_previa;
  v_titulo text := left(coalesce(nullif(btrim(p_plano ->> 'titulo'), ''), 'Orçamento'), 120);
  v_cli uuid := (p_plano ->> 'client_id')::uuid;
  v_ves uuid := (p_plano ->> 'vessel_id')::uuid;
  v_familias text[];
  v_total numeric(14,2) := 0;
  v_n integer := 0;
  v_prov integer := 0;
  v_antigo date;
  v_hash text;
  r record;
  v_i public.retorno_cartao_itens;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    raise exception 'retorno_previa_aplicar: só o dono' using errcode = '42501';
  end if;
  if jsonb_typeof(v_linhas) is distinct from 'array' then
    raise exception 'retorno_previa_aplicar: plano sem linhas' using errcode = '22023';
  end if;

  if v_id is null then
    select * into v_ab from public.retorno_aberturas a where a.id = (p_plano ->> 'abertura_id')::uuid;
    if not found then
      raise exception 'retorno_previa_aplicar: caso inexistente' using errcode = '22023';
    end if;
    -- As famílias do caso, como o passo 6 da montagem: a legenda usa o {do_servico} delas.
    select public._retorno_familias(public._retorno_busca(
             coalesce(string_agg(w.body, ' '), '') || ' ' || coalesce(v_ab.coleta ->> 'servico', '') || ' ' || coalesce(v_ab.coleta ->> 'detalhes', '')))
      into v_familias
      from public.retorno_mensagens m
      join public.whatsapp_messages w on w.id = m.whatsapp_message_id
     where m.abertura_id = v_ab.id and m.pede_resposta and m.recebida_em <= v_agora;
    insert into public.retorno_previa (abertura_id, chave, client_id, vessel_id, origem, familias, titulo, estado, modo, hash, dados, criada_em, atualizada_em)
    values (v_ab.id, v_ab.chave, v_cli, v_ves, 'ditado', coalesce(v_familias, '{}'), v_titulo, 'proposta', 'ligado', '',
            jsonb_build_object('travada', true, 'ajustada_por_ditado', true), v_agora, v_agora)
    returning id into v_id;
  else
    select * into v_pv from public.retorno_previa p where p.id = v_id for update;
    if not found then
      raise exception 'retorno_previa_aplicar: proposta inexistente' using errcode = '22023';
    end if;
    select * into v_ab from public.retorno_aberturas a where a.id = v_pv.abertura_id;
  end if;

  -- As linhas, sem cálculo: o plano já decidiu nome, quantidade e preço de cada uma.
  delete from public.retorno_previa_linhas l where l.previa_id = v_id;
  for r in select e.valor, e.ord from jsonb_array_elements(v_linhas) with ordinality as e(valor, ord) order by e.ord loop
    v_n := v_n + 1;
    if (r.valor ->> 'preco') is not null then
      v_total := v_total + round((r.valor ->> 'quantidade')::numeric * (r.valor ->> 'preco')::numeric, 2);
    end if;
    if r.valor ->> 'estado' = 'provisorio' then
      v_prov := v_prov + 1;
    end if;
    if r.valor ->> 'em' is not null then
      v_antigo := least(coalesce(v_antigo, (r.valor ->> 'em')::date), (r.valor ->> 'em')::date);
    end if;
    insert into public.retorno_previa_linhas (previa_id, ordem, tipo, product_id, service_id, nome, quantidade, preco, preco_fonte, preco_em, estado, motivo)
    values (v_id, r.ord, r.valor ->> 'tipo', (r.valor ->> 'product_id')::uuid, (r.valor ->> 'service_id')::uuid, left(r.valor ->> 'nome', 200),
            (r.valor ->> 'quantidade')::numeric, (r.valor ->> 'preco')::numeric, r.valor ->> 'fonte', (r.valor ->> 'em')::date, r.valor ->> 'estado',
            case when r.valor ->> 'estado' = 'assumido' and nullif(btrim(r.valor ->> 'nome_pedido'), '') is not null
                 then 'pedido: ' || left(r.valor ->> 'nome_pedido', 120)
                 else r.valor ->> 'motivo' end);
  end loop;

  v_hash := public._retorno_previa_hash(v_ves, v_titulo, public._retorno_previa_linhas_json(v_id));

  update public.retorno_previa p
     set titulo = v_titulo,
         condicao_pagamento = p_plano ->> 'condicao',
         client_id = v_cli,
         vessel_id = v_ves,
         total = v_total,
         linhas_n = v_n,
         provisorios_n = v_prov,
         preco_mais_antigo = v_antigo,
         hash = v_hash,
         dados = p.dados || jsonb_build_object('travada', true, 'ajustada_por_ditado', true, 'ditada_em', v_agora),   -- ditada_em: o cartão compara com a data do rascunho
         atualizada_em = v_agora
   where p.id = v_id;

  -- A unidade dita só vale de verdade com 2 ou mais: com 1, ela já é a do caso.
  if v_ves is not null and jsonb_array_length(public._retorno_unidades_do_cliente(v_cli)) >= 2 then
    update public.retorno_aberturas a set unidade_escolhida_id = v_ves, atualizada_em = now() where a.id = v_ab.id;
  end if;

  if p_item is not null then
    select i.* into v_i from public.retorno_cartao_itens i where i.id = p_item;
    if v_i.estado = 'vivo'
       and exists (select 1 from public.retorno_cartoes c where c.id = v_i.cartao_id and c.estado = 'vivo') then
      perform public._retorno_item_remontar(p_item, v_agora);
    end if;
  end if;

  return jsonb_build_object('previa_id', v_id, 'hash', v_hash);
end;
$$;

comment on function public.retorno_previa_aplicar(uuid, jsonb, uuid, timestamptz, uuid) is
  'Retorno F3 (P6, C-APLICA): reescreve linhas e cabeçalho pelo plano aprovado. Nova: origem ditado, modo ligado, famílias do caso. Existente: origem, famílias e fonte_* não mudam. Nunca toca em linhas_iniciais; o hash é o de _retorno_previa_hash.';

revoke all on function public.retorno_previa_aplicar(uuid, jsonb, uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.retorno_previa_aplicar(uuid, jsonb, uuid, timestamptz, uuid) to service_role;

-- ── 5. Gerado do corpo vigente, com os trechos -- F3 ─────────────────────────────────────────────────

create or replace function public._retorno_decidir_letra(p_item public.retorno_cartao_itens, p_comando jsonb, p_dono uuid, p_agora timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_hoje date := (p_agora at time zone c_fuso)::date;
  v_letra text := upper(coalesce(p_comando ->> 'letra', ''));
  v_resto text := nullif(btrim(p_comando ->> 'resto'), '');
  v_op jsonb;
  v_rotulo text := public._retorno_rotulo(p_item.abertura_id, p_agora);
  v_r jsonb;
  v_item jsonb;
  v_m jsonb;
  v_nivel text;
  v_texto text;
  v_dia date;
  v_prov uuid;
  v_ves uuid;
  v_cli uuid;   -- F3 (P6)
begin
  select o into v_op from jsonb_array_elements(p_item.opcoes) o where o ->> 'letra' = v_letra limit 1;
  if v_op is null then
    return jsonb_build_object('ok', true, 'texto', format('O caso %s não tem a opção %s, e nada foi feito.', p_item.n, v_letra));
  end if;

  case v_op ->> 'acao'
    when 'chegou', 'previsao' then
      if v_op ->> 'acao' = 'previsao' and v_resto is null then
        return jsonb_build_object('ok', true, 'texto', format('Diga a previsão: *%s C dia 14*.', p_item.n));
      end if;
      if exists (select 1 from public.agenda_rascunho r where r.autor = p_dono and r.estado = 'aberto' and r.expira_em > p_agora) then
        return jsonb_build_object('ok', true, 'texto', 'Tem um rascunho aberto: mande *grava* ou *descarta* antes.');
      end if;
      if v_op ->> 'acao' = 'chegou' then
        v_r := public._retorno_material(p_dono, v_op ->> 'os', 'na_mao', null, format('cartão do retorno: %s B', p_item.n), v_hoje);
      else
        v_r := public._retorno_material(p_dono, v_op ->> 'os', 'a_caminho', v_resto,
                                        format('cartão do retorno: %s C %s', p_item.n, v_resto), v_hoje);
      end if;
      if not (v_r ->> 'ok')::boolean then
        return jsonb_build_object('ok', true, 'texto', v_r ->> 'texto');
      end if;

      if v_op ->> 'acao' = 'previsao' then
        select max(m.previsao_ate) into v_dia from public.os_material m
         where m.service_order_id = p_item.service_order_id and m.critico and m.situacao = 'a_caminho';
        perform public._retorno_item_remontar(p_item.id, p_agora);
        return jsonb_build_object('ok', true,
          'texto', format('Anotei: previsão %s. Só você vê: ao cliente não vai data.', coalesce(to_char(v_dia, 'DD/MM'), 'anotada')));
      end if;

      v_item := public._retorno_item_remontar(p_item.id, p_agora);
      v_m := public._retorno_modelo_do_caso(p_item.abertura_id, p_agora);
      select t.nivel into v_nivel from public.retorno_modelo_tipos t where t.tipo = 'modelo_peca_chegou';
      if v_m ->> 'modelo' = 'modelo_peca_chegou' and v_nivel = 'cartao' then
        return jsonb_build_object('ok', true, 'precisa_pin', true,
          'texto', format('Anotei: chegou hoje. Mando a %s: ''%s''? *sim <PIN>*', v_rotulo, v_item ->> 'texto_mostrado'));
      elsif v_m ->> 'modelo' = 'modelo_peca_chegou' and v_nivel = 'sozinho' then
        perform public._retorno_agendar_modelo(p_item.abertura_id, v_m, p_agora);
        return jsonb_build_object('ok', true, 'texto', format('Anotei: chegou hoje. Vai sair a %s.', v_rotulo));
      end if;
      return jsonb_build_object('ok', true, 'texto', 'Anotei: chegou hoje. A agenda avisa o cliente quando marcar o dia.');

    when 'responder' then
      -- F3 (P6): a letra L com o ditado desligado não vale: M07 não sai sem as letras ligadas.
      if v_op ->> 'modelo' = 'modelo_ver_no_local' and not coalesce((public._retorno_cfg()).previa_ditado_ligado, false) then
        return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', 'O orçamento pelo cartão está desligado: nada mudou.');
      end if;
      v_texto := public._retorno_texto_do_modelo(p_item.abertura_id,
        jsonb_build_object('modelo', v_op ->> 'modelo', 'os_id', v_op ->> 'os_id'), null, p_agora);
      -- F3 (P6): acao_sim = null, com previa_id intacto. Sem isso, *L* + *sim <PIN>* criaria o orçamento e mandaria o PDF.
      update public.retorno_cartao_itens i
         set texto_mostrado = v_texto, modelo_tipo = v_op ->> 'modelo', escolha = v_letra, selecionado = true, acao_sim = null
       where i.id = p_item.id;
      update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = p_item.cartao_id;
      return jsonb_build_object('ok', true, 'precisa_pin', true,
        'texto', format('Vou mandar a %s: ''%s''. *sim <PIN>* manda.', v_rotulo, v_texto));

    when 'parecido' then
      -- F3 (P6): *B* troca pelo outro parecido. p_fonte só vale com previa_modo = 'ligado' (retorno_previa_montar também barra).
      -- pin_nao_vale (revisão da F3): o PIN mandado junto da letra não vale. O dono lê as linhas novas e manda *sim <PIN>* sozinho, inclusive quando nada mudou.
      if (public._retorno_cfg()).previa_modo is distinct from 'ligado' then
        return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', 'O orçamento pelo cartão está desligado: nada mudou.');
      end if;
      v_r := public.retorno_previa_montar(p_item.abertura_id, p_agora, (v_op ->> 'os_id')::uuid);
      if v_r ->> 'acao' = 'nada' then
        return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', 'Não consegui usar esse orçamento: nada mudou.');
      end if;
      v_item := public._retorno_item_remontar(p_item.id, p_agora);
      return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', (select string_agg(l, E'\n') from jsonb_array_elements_text(v_item -> 'linhas') l));

    when 'unidade' then
      -- F3 (P6): a escolha do dono vale mais que a busca por nome; a proposta fica travada e o hash é recalculado (a rodada a mantém).
      v_cli := (public._retorno_cadastro_do_caso(p_item.abertura_id) ->> 'client_id')::uuid;
      v_ves := (v_op ->> 'vessel_id')::uuid;
      if v_cli is null or not exists (select 1 from public.vessels v where v.id = v_ves and v.active and v.client_id = v_cli) then
        return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', format('A unidade da opção %s já não vale para este cliente, e nada foi feito. Mande *retorno*.', v_letra));
      end if;
      update public.retorno_aberturas a set unidade_escolhida_id = v_ves, atualizada_em = now() where a.id = p_item.abertura_id;
      update public.retorno_previa p
         set vessel_id = v_ves,
             hash = public._retorno_previa_hash(v_ves, p.titulo, public._retorno_previa_linhas_json(p.id)),
             dados = p.dados || '{"travada": true}'::jsonb,
             atualizada_em = p_agora
       where p.abertura_id = p_item.abertura_id and p.estado in ('proposta', 'sombra');
      v_item := public._retorno_item_remontar(p_item.id, p_agora);
      return jsonb_build_object('ok', true, 'pin_nao_vale', true, 'texto', (select string_agg(l, E'\n') from jsonb_array_elements_text(v_item -> 'linhas') l));

    when 'cliente' then
      -- Vale só para este caso: não vincula o número nem regrava mensagem.
      update public.retorno_aberturas a
         set client_id = (v_op ->> 'client_id')::uuid, papel = 'cliente', atualizada_em = now()
       where a.id = p_item.abertura_id;
      v_item := public._retorno_item_remontar(p_item.id, p_agora);
      -- Revisão da F3: definido o cliente, o item pode nascer com um rascunho dele a mandar, que o dono ainda não leu.
      return jsonb_build_object('ok', true, 'pin_nao_vale', (v_item ->> 'acao_sim') is not null, 'texto', (select string_agg(l, E'\n') from jsonb_array_elements_text(v_item -> 'linhas') l));

    when 'desfaz_cadastro' then
      v_prov := (v_op ->> 'client_id')::uuid;
      select (a.new_value ->> 'vessel_id')::uuid into v_ves
        from public.audit_log a
       where a.table_name = 'clients' and a.record_id = v_prov and a.new_value ->> 'caso' = p_item.abertura_id::text
       limit 1;
      update public.clients c set active = false where c.id = v_prov;
      update public.vessels v set active = false where v.id = v_ves;
      insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
      values ('clients', v_prov, 'update', 'dono', jsonb_build_object('active', true), jsonb_build_object('active', false),
              'Cadastro provisório desfeito pelo dono no cartão do retorno');
      -- F3 (P6): sem cadastro não há proposta: as vivas caem, e _retorno_cadastro_do_caso já devolve nulo (o *sim <PIN>* não cria nada nele).
      update public.retorno_previa p set estado = 'descartada', atualizada_em = p_agora
       where p.abertura_id = p_item.abertura_id and p.estado in ('proposta', 'sombra');
      if (public._retorno_cfg()).previa_ditado_ligado or (public._retorno_cfg()).previa_modo = 'ligado' then
        perform public._retorno_item_remontar(p_item.id, p_agora);
      end if;
      return jsonb_build_object('ok', true, 'texto', 'Cadastro provisório desfeito. Nada foi apagado.');

    else
      return jsonb_build_object('ok', true, 'texto', format('O caso %s não tem a opção %s, e nada foi feito.', p_item.n, v_letra));
  end case;
end;
$$;

-- Revisão da F3: p_sessao é a sessão do turno que leu o caso (vem do servidor, nunca do modelo). O cartão vive 24 h e a sessão gira em 4 h,
-- e o erp-mcp lê a marca da sessão do job: marcar só a do cartão deixava o create_quote_from_items sem PIN no turno que já leu o cliente.
drop function if exists public.retorno_ver_caso_para_modelo(integer, uuid, timestamptz);

create or replace function public.retorno_ver_caso_para_modelo(p_n integer, p_autor uuid, p_agora timestamptz default now(), p_sessao uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_agora timestamptz := coalesce(p_agora, now());
  v_d jsonb;
  v_i public.retorno_cartao_itens;
  v_c public.retorno_cartoes;
  v_ab public.retorno_aberturas;
  v_fatos jsonb;
  v_os jsonb;
  v_f jsonb;
  v_vessel uuid;
  v_recebidas jsonb;
begin
  v_d := public.retorno_destino_do_item(p_n, p_autor, v_agora);
  if v_d ? 'erro' then
    return v_d;
  end if;
  select * into v_i from public.retorno_cartao_itens i where i.id = (v_d ->> 'item_id')::uuid;
  select * into v_c from public.retorno_cartoes c where c.id = v_i.cartao_id;
  select * into v_ab from public.retorno_aberturas a where a.id = v_i.abertura_id;

  if v_ab.papel = 'cliente' then
    begin
      v_fatos := public.retorno_fatos_do_contato(v_ab.phone_normalized, v_agora);
      if jsonb_array_length(v_fatos -> 'os') = 1 then
        v_os := v_fatos -> 'os' -> 0;
        -- A previsão nunca vai ao modelo, nem a lista de peças: só o que dá para afirmar.
        v_f := jsonb_build_object('pronto', v_os -> 'fatos' -> 'pronto' <> 'null'::jsonb,
                                  'em_servico', v_os -> 'fatos' -> 'em_servico' <> 'null'::jsonb,
                                  'peca_chegou', v_os -> 'fatos' -> 'peca_chegou' <> 'null'::jsonb,
                                  'aguarda_peca', v_os -> 'fatos' -> 'aguarda_peca' <> 'null'::jsonb,
                                  'liberado', v_os -> 'fatos' -> 'liberado' <> 'null'::jsonb);
      end if;
    exception when others then
      v_f := null;   -- sem fato, nunca "não há peça"
    end;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('hora', x.hora, 'texto', x.corpo) order by x.recebida_em, x.id), '[]'::jsonb)
    into v_recebidas
    from (select m.recebida_em, m.whatsapp_message_id as id, to_char(m.recebida_em at time zone c_fuso, 'HH24:MI') as hora, left(w.body, 500) as corpo
            from public.retorno_mensagens m
            join public.whatsapp_messages w on w.id = m.whatsapp_message_id
           where m.abertura_id = v_ab.id and m.recebida_em <= v_agora
           order by m.recebida_em desc, m.whatsapp_message_id desc
           limit 5) x;

  -- A amarração: com caso ambíguo, só a marca, porque o texto de terceiro entrou do mesmo jeito.
  -- F3 (P6): papel cliente grava sempre o client_id, e vessel_id e service_order_id só com exatamente 1 OS; no else, zera as três: client_id de outro caso não fica para trás.
  if v_ab.papel = 'cliente' then
    if v_os is not null then
      select so.vessel_id into v_vessel from public.service_orders so where so.id = (v_os ->> 'id')::uuid;
    end if;
    update public.ai_operator_sessions s
       set client_id = v_ab.client_id, vessel_id = v_vessel, service_order_id = (v_os ->> 'id')::uuid,
           metadata = coalesce(s.metadata, '{}'::jsonb) || '{"retorno_amarrada": true}'::jsonb
     where s.id = coalesce(p_sessao, v_c.sessao_id);
  else
    update public.ai_operator_sessions s
       set client_id = null, vessel_id = null, service_order_id = null,
           metadata = coalesce(s.metadata, '{}'::jsonb) || '{"retorno_amarrada": true}'::jsonb
     where s.id = coalesce(p_sessao, v_c.sessao_id);
  end if;

  return jsonb_build_object('n', p_n, 'rotulo', v_d ->> 'rotulo', 'os', v_os ->> 'numero', 'recebidas', v_recebidas, 'fatos', coalesce(v_f, '{}'::jsonb),
    'amarra', jsonb_build_object('client_id', case when v_ab.papel = 'cliente' then v_ab.client_id end, 'vessel_id', v_vessel));   -- F3 (P6): lerCaso tira antes de entregar ao modelo
end;
$$;

revoke all on function public.retorno_ver_caso_para_modelo(integer, uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.retorno_ver_caso_para_modelo(integer, uuid, timestamptz, uuid) to service_role;

create or replace function public.retorno_decidir_dito(p_comando jsonb, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cmd text := p_comando ->> 'comando';
  v_n integer := (p_comando ->> 'n')::integer;
  v_ns integer[] := case when jsonb_typeof(p_comando -> 'ns') = 'array'
                         then array(select (x)::integer from jsonb_array_elements_text(p_comando -> 'ns') x) end;
  v_vivo jsonb;
  v_cartao uuid;
  v_k integer;
  v_item public.retorno_cartao_itens;
  v_r jsonb;
  v_sel integer[];
  v_texto text;
  v_ditado text;
  v_aviso text;
  v_palavra text;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'motivo', 'nao_e_o_dono');
  end if;
  v_vivo := public.retorno_cartao_vivo(v_agora);
  if v_vivo is null then
    return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end if;
  if v_vivo ->> 'estado' = 'lista' then
    return jsonb_build_object('ok', true, 'texto', 'Esta lista é só para consulta. Mande *retorno* quando o pedido aberto terminar.');
  end if;
  v_cartao := (v_vivo ->> 'id')::uuid;

  select count(*) into v_k from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo';
  if (v_n is not null and not exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = v_n and i.estado = 'vivo'))
     or (v_ns is not null and exists (select 1 from unnest(v_ns) x
                                       where not exists (select 1 from public.retorno_cartao_itens i
                                                          where i.cartao_id = v_cartao and i.n = x and i.estado = 'vivo'))) then
    return jsonb_build_object('ok', true, 'texto', format('O cartão tem %s casos.', v_k));
  end if;
  if v_n is not null then
    select * into v_item from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.n = v_n;
  end if;

  case v_cmd
    when 'escolher' then
      v_palavra := 'letra';
      v_r := public._retorno_decidir_letra(v_item, p_comando, p_autor, v_agora);
      perform public._retorno_toque(v_palavra, v_cartao, v_item.abertura_id, v_agora);
      return v_r || jsonb_build_object('historico', jsonb_build_object('user', format('(escolheu %s no caso %s)', upper(p_comando ->> 'letra'), v_n),
                                                                       'assistant', format('(anotei a escolha do caso %s)', v_n)));

    when 'so', 'sem' then
      update public.retorno_cartao_itens i
         set selecionado = case when v_cmd = 'so' then i.n = any (v_ns) else not (i.n = any (v_ns)) end
       where i.cartao_id = v_cartao and i.estado = 'vivo';
      select array_agg(i.n::integer order by i.n) into v_sel
        from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo' and i.selecionado;
      perform public._retorno_toque(v_cmd, v_cartao, null, v_agora);
      if v_sel is null then
        return jsonb_build_object('ok', true, 'texto', 'Nada ficou selecionado. *retorno* volta ao cartão inteiro.',
          'historico', jsonb_build_object('user', format('(%s)', v_cmd), 'assistant', '(nada selecionado no cartão)'));
      end if;
      v_texto := format('Fica %s. *sim <PIN>* manda. *retorno* volta ao cartão inteiro.', public._retorno_lista_de_casos(v_sel));
      return jsonb_build_object('ok', true, 'precisa_pin', true, 'texto', v_texto,
        'historico', jsonb_build_object('user', format('(%s %s)', v_cmd, array_to_string(v_ns, ' ')), 'assistant', v_texto));

    when 'tirar' then
      update public.retorno_cartao_itens i set selecionado = false where i.cartao_id = v_cartao and i.estado = 'vivo' and i.n = any (v_ns);
      perform public._retorno_toque('tirar', v_cartao, null, v_agora);
      if not exists (select 1 from public.retorno_cartao_itens i where i.cartao_id = v_cartao and i.estado = 'vivo' and i.selecionado) then
        perform public._retorno_cartao_recusar(v_cartao, v_agora);
        return jsonb_build_object('ok', true, 'texto', 'Cartão fechado: nada foi mandado.',
          'historico', jsonb_build_object('user', '(tirou os casos do cartão)', 'assistant', 'Cartão fechado: nada foi mandado.'));
      end if;
      v_texto := case when cardinality(v_ns) = 1 then format('Tirei o %s. O relógio dele continua.', v_ns[1])
                      else format('Tirei o %s. O relógio deles continua.', array_to_string(v_ns, ' e o ')) end;
      return jsonb_build_object('ok', true, 'texto', v_texto,
        'historico', jsonb_build_object('user', format('(não %s)', array_to_string(v_ns, ' ')), 'assistant', v_texto));

    when 'ditar' then
      v_ditado := btrim(coalesce(p_comando ->> 'texto', ''));
      if v_ditado = '' then
        return jsonb_build_object('ok', true, 'texto', format('Diga o texto: *dita %s pode buscar amanhã*.', v_n));
      end if;
      -- F3 (P6, 7.3): com proposta viva, *dita* com cara de ajuste é ajuste da proposta, e *dita* mandaria o texto ao cliente.
      if v_item.previa_id is not null
         and exists (select 1 from public.retorno_previa p where p.id = v_item.previa_id and p.estado = 'proposta')
         and v_ditado ~* '^\s*(troca|tira|muda|poe|põe|coloca|aumenta|diminui|acrescenta|fica)\y' then
        return jsonb_build_object('ok', true,
          'texto', format('Isso parece ajuste da proposta, e *dita* manda o texto ao cliente. Diga sem o *dita*: ou mande *dita %s* com o texto completo ao cliente.', v_n),
          'historico', jsonb_build_object('user', format('(ditou o caso %s)', v_n), 'assistant', '(recusei o ditado: parecia ajuste da proposta)'));
      end if;
      update public.retorno_cartao_itens i
         set texto_ditado = v_ditado, ditado_via = 'dita', selecionado = true
       where i.id = v_item.id;
      update public.retorno_cartoes c set texto = public._retorno_cartao_texto(c.id, null) where c.id = v_cartao;
      perform public._retorno_toque('dita', v_cartao, v_item.abertura_id, v_agora);
      v_aviso := case when v_ditado ~* '(R\$|\yreais\y|[0-9]+[[:space:]]*mil\y)' then ' (tem valor no texto)' else '' end;
      return jsonb_build_object('ok', true, 'precisa_pin', true,
        'texto', format('Vou mandar a %s, exatamente: ''%s''.%s', public._retorno_rotulo(v_item.abertura_id, v_agora), v_ditado, v_aviso)
                 || E'\n' || format('*sim <PIN>* manda o que está no cartão · *dita %1$s …* troca · *não %1$s* tira.', v_n),
        'historico', jsonb_build_object('user', format('(ditou a resposta do caso %s)', v_n),
                                        'assistant', format('(anotei o ditado do caso %s)', v_n)));

    else
      return jsonb_build_object('ok', false, 'seguir_ao_modelo', true);
  end case;
end;
$$;

create or replace function public.retorno_cartao_executar(p_cartao uuid, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_c public.retorno_cartoes;
  v_i public.retorno_cartao_itens;
  v_ab public.retorno_aberturas;
  v_conf jsonb;
  v_frases text[] := '{}';
  v_ditados jsonb := '[]'::jsonb;
  v_rotulos text[] := '{}';
  v_n integer := 0;
  v_saida uuid;
  v_op jsonb;
  v_aviso text;
  -- F3 (P6)
  v_orcamentos jsonb := '[]'::jsonb;
  v_pv public.retorno_previa;
  v_nomes text;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'aviso', 'Só o dono executa o cartão.');
  end if;
  select * into v_c from public.retorno_cartoes c where c.id = p_cartao for update;
  if not found or v_c.estado <> 'vivo' then
    return jsonb_build_object('ok', false, 'aviso', 'Esse cartão já foi decidido.');
  end if;

  update public.retorno_cartao_itens i set estado = 'fora' where i.cartao_id = p_cartao and i.estado = 'vivo' and not i.selecionado;

  for v_i in select i.* from public.retorno_cartao_itens i where i.cartao_id = p_cartao and i.estado = 'vivo' order by i.n loop
    v_conf := public._retorno_item_conferir(v_i.id, v_agora, true);
    if not (v_conf ->> 'ok')::boolean then
      update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = v_conf ->> 'motivo', decidido_em = v_agora where i.id = v_i.id;
      v_frases := v_frases || (v_conf ->> 'texto');
      continue;
    end if;
    select * into v_ab from public.retorno_aberturas a where a.id = v_i.abertura_id;

    -- F3 (P6): o item de orçamento. O SQL só decide; quem cria e manda é a ferramenta, e a frase de cada um sai dela (não soma em "Vai sair").
    if v_i.acao_sim is not null and v_i.texto_ditado is null and v_i.modelo_tipo is null then
      select p.* into v_pv from public.retorno_previa p where p.id = v_i.previa_id;
      if not public._retorno_previa_liberada(v_i.acao_sim, v_pv.origem) then
        update public.retorno_cartao_itens i set estado = 'fora' where i.id = v_i.id;
        v_frases := v_frases || format('o %s não saiu, porque o orçamento pelo cartão foi desligado; não criei nada', v_i.n);
        continue;
      end if;
      if v_cfg.modo <> 'ligado' then
        update public.retorno_cartao_itens i set estado = 'fora' where i.id = v_i.id;
        v_frases := v_frases || 'O retorno está em teste: não mandei.'::text;
        continue;
      end if;
      if v_cfg.segura_tudo_ate is not null and v_cfg.segura_tudo_ate > v_agora then
        update public.retorno_cartao_itens i set estado = 'fora' where i.id = v_i.id;
        v_frases := v_frases || '*segura tudo* está ligado: não mandei.'::text;
        continue;
      end if;
      if v_i.acao_sim = 'orcar' and v_pv.provisorios_n > 0 then
        select string_agg(left(l.nome, 40), ', ' order by l.ordem) into v_nomes
          from public.retorno_previa_linhas l where l.previa_id = v_pv.id and l.estado = 'provisorio';
        update public.retorno_cartao_itens i set estado = 'caiu', caiu_motivo = 'item_provisorio', decidido_em = v_agora where i.id = v_i.id;
        v_frases := v_frases || format('o %s tem item a completar (%s): não criei nada. Mande *retorno* e dite o que falta', v_i.n, v_nomes);
        continue;
      end if;
      if public._retorno_fora_do_horario_de_envio(v_agora) then
        update public.retorno_cartao_itens i set estado = 'fora' where i.id = v_i.id;
        v_frases := v_frases || format('o %s: fora do horário de envio; não criei nada. Mande *retorno* a partir das 8h', v_i.n);
        continue;
      end if;
      v_orcamentos := v_orcamentos || jsonb_build_array(jsonb_build_object(
        'item_id', v_i.id, 'n', v_i.n, 'previa_id', v_i.previa_id, 'acao', v_i.acao_sim, 'service_order_id', v_i.service_order_id,
        'numero', case when v_i.acao_sim = 'pdf' then (select so.service_order_number from public.service_orders so where so.id = v_i.service_order_id) end,
        'rotulo', public._retorno_rotulo(v_ab.id, v_agora)));
      update public.retorno_cartao_itens i set estado = 'feito', decidido_em = v_agora where i.id = v_i.id;
      continue;
    end if;

    if v_i.texto_ditado is not null then
      v_ditados := v_ditados || jsonb_build_array(jsonb_build_object(
        'item_id', v_i.id, 'phone', v_ab.phone_normalized, 'texto', v_i.texto_ditado,
        'dedupe_key', 'retorno:' || v_ab.id || ':ditado:' || md5(v_i.texto_ditado)));
      v_n := v_n + 1;
      v_rotulos := v_rotulos || public._retorno_rotulo(v_ab.id, v_agora);
    elsif v_i.modelo_tipo is not null then
      if v_cfg.modo <> 'ligado' then
        v_frases := v_frases || 'O retorno está em teste: não mandei.'::text;
      elsif v_cfg.segura_tudo_ate is not null and v_cfg.segura_tudo_ate > v_agora then
        v_frases := v_frases || '*segura tudo* está ligado: não mandei.'::text;
      elsif exists (select 1 from public.retorno_saidas s
                     where s.abertura_id = v_ab.id and s.tipo like 'modelo\_%' escape '\'
                       and s.estado in ('agendada', 'preparada', 'enviando')) then
        v_frases := v_frases || format('o %s já está saindo', v_i.n);
      else
        select o into v_op from jsonb_array_elements(v_i.opcoes) o where o ->> 'letra' = v_i.escolha limit 1;
        insert into public.retorno_saidas (abertura_id, tipo, variante, origem, classe, chave, phone_normalized, client_id, modo, estado,
                                           enviar_em, dados, dedupe_key)
        values (v_ab.id, v_i.modelo_tipo, 'aprovado', 'retorno_modelo', 'resposta_imediata', v_ab.chave, v_ab.phone_normalized, v_ab.client_id,
                'ligado', 'agendada', v_agora,
                jsonb_build_object('aprovada', true, 'aprovada_em', v_agora, 'cartao_id', p_cartao, 'item_id', v_i.id,
                                   'texto_aprovado', v_i.texto_mostrado, 'hash', v_i.hash, 'os_id', v_i.service_order_id,
                                   'marca_liberado', coalesce((v_op ->> 'marca_liberado')::boolean, false)),
                'retorno:' || v_ab.id || ':modelo:' || v_i.id)
        returning id into v_saida;
        update public.retorno_cartao_itens i set saida_id = v_saida where i.id = v_i.id;
        -- F3 (P6): *precisa ver no local* aprovado tira a proposta da mesa; a marca do caso nasce quando M07 sai (P4).
        if v_i.previa_id is not null and v_i.modelo_tipo = 'modelo_ver_no_local' then
          update public.retorno_previa p
             set estado = 'ver_no_local', decidida_em = v_agora, atualizada_em = v_agora
           where p.id = v_i.previa_id and p.estado = 'proposta';
        end if;
        if coalesce((v_op ->> 'marca_liberado')::boolean, false) and v_i.service_order_id is not null then
          update public.service_orders so
             set liberado_retirada_em = v_agora, liberado_retirada_por = p_autor
           where so.id = v_i.service_order_id;
        end if;
        v_n := v_n + 1;
        v_rotulos := v_rotulos || public._retorno_rotulo(v_ab.id, v_agora);
      end if;
    else
      update public.retorno_cartao_itens i set estado = 'fora' where i.id = v_i.id;
      continue;
    end if;

    update public.retorno_cartao_itens i set estado = 'feito', decidido_em = v_agora where i.id = v_i.id;
  end loop;

  update public.retorno_cartoes c
     set estado = 'decidido', decidido_em = v_agora, decidido_por = 'sim_pin'
   where c.id = p_cartao;
  perform public._retorno_toque('sim_pin', p_cartao, null, v_agora);

  if v_n > 0 then
    v_aviso := format('Vai sair %s: %s.', v_n, array_to_string(v_rotulos, ', '));
  elsif cardinality(v_frases) = 0 and jsonb_array_length(v_orcamentos) = 0 then   -- F3 (P6): orçamento não é "nada para mandar"
    v_aviso := 'Nada para mandar neste cartão. *retorno* abre de novo: use *dita N* ou a letra antes do *sim*.';
  end if;
  v_aviso := concat_ws(' ', v_aviso, nullif(array_to_string(v_frases, ' · '), ''),
                       case when v_c.mais > 0 then format('Mais %s esperando: *retorno*.', v_c.mais) end);

  return jsonb_build_object('ok', true, 'aviso', v_aviso, 'ditados', v_ditados, 'vai_sair', v_n, 'orcamentos', v_orcamentos);   -- F3 (P6)
end;
$$;

-- ── 6. Gerado do corpo vigente (20261201100000), com o trecho -- F3 ─────────────────────────────────

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
       where s.status = 'open' and s.metadata ? 'retorno_amarrada';   -- F3 (revisão): a marca agora pode estar em outra sessão do dono, inclusive a do painel
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
