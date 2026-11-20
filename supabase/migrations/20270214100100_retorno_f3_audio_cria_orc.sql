-- Retorno rápido ao cliente, F3: decisão do dono rr-f3-2b (20/11/2026), "O áudio já cria o orçamento, e o PIN serve só para
-- mandar o PDF". Gerada por scripts/gerar_audio.cjs; o _retorno_item_montar sai do corpo vigente em produção, com 1 troca.
--
-- Antes: o áudio gravava a proposta e o *sim <PIN>* criava o ORÇ e mandava o PDF. Agora (retorno.ts, retorno_orcar_caso):
--  · quando o áudio é entendido (a pendência nasce), a proposta é gravada (retorno_previa_aplicar) e vira ORÇ em rascunho, com
--    número, pela criação que já existe (retorno_previa_preparar + montarOrcamento, o caminho do "cria sem mandar");
--  · retorno_orc_do_audio_marcar põe na proposta a marca orc_pelo_audio_em (o ato do dono, para a medida orc_sem_ato) e devolve
--    número, total e a impressão digital do ORÇ (_retorno_orc_impressao), que vai ao retrato da pendência;
--  · o cartão ao dono mostra o número; o *sim <PIN>* só manda o PDF. retorno_orc_do_audio_conferir recusa se o ORÇ mudou entre o
--    resumo e o PIN (item, preço, quantidade, cliente, unidade, título, desconto ou total), se já foi enviado, se o caso fechou,
--    se o telefone do caso mudou ou se o ditado foi desligado;
--  · áudio repetido não cria dois: com um ORÇ do áudio ainda em rascunho no caso, retorno_orc_do_audio_do_caso o devolve e o
--    resumo mostra esse mesmo ORÇ (e o construtor ainda tem a trava de rascunho recente de 12 h);
--  · *não* não manda nada; o ORÇ fica em rascunho na lista (não vai a ninguém) e o caso continua no cartão, na linha do rascunho.
-- _retorno_item_montar: a linha do rascunho (acao_sim = pdf) passa a ter a impressão digital do ORÇ no hash, não só o total.
--
-- Tudo segue desligado: sem retorno_config.previa_ditado_ligado, nada disto é alcançado (o retrato recusa e o preparo recusa).
-- Funções novas: SECURITY DEFINER, sem anon nem authenticated; as de chamar, só service_role.
-- Reverter: reaplicar _retorno_item_montar de 20261208100400 e drop function public.retorno_orc_do_audio_conferir(uuid, uuid, text,
-- text, uuid, timestamptz), public.retorno_orc_do_audio_do_caso(uuid, uuid, timestamptz), public.retorno_orc_do_audio_marcar(uuid,
-- uuid, uuid, timestamptz), public._retorno_orc_linhas(uuid), public._retorno_orc_impressao(uuid); e o retorno.ts anterior.

-- ── 1. A impressão digital e as linhas do ORÇ ─────────────────────────────────────────────────────────────────────────

create or replace function public._retorno_orc_impressao(p_so uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select md5(concat_ws('|',
           so.id, so.client_id, so.vessel_id, so.problem_description, so.payment_conditions, so.discount_amount, so.grand_total,
           (select string_agg(concat_ws(':', p.product_id, p.quantity, p.unit_sale_snapshot, p.discount_pct, p.discount_amount), ','
                              order by p.created_at, p.id)
              from public.service_order_parts p where p.service_order_id = so.id),
           (select string_agg(concat_ws(':', s.service_id, s.name_snapshot, s.description_snapshot, s.quantity, s.unit_price_snapshot,
                                        s.discount_pct, s.discount_amount), ',' order by s.created_at, s.id)
              from public.service_order_services s where s.service_order_id = so.id)))
    from public.service_orders so
   where so.id = p_so;
$$;

comment on function public._retorno_orc_impressao(uuid) is
  'Retorno F3 (rr-f3-2b): a impressão digital do orçamento que o dono viu: cliente, unidade, título, condição, desconto, total e cada peça e serviço (item, quantidade, preço, desconto). Fica de fora a validade (o envio a grava) e o status (conferido à parte). Nulo sem ORÇ.';

revoke all on function public._retorno_orc_impressao(uuid) from public, anon, authenticated;

create or replace function public._retorno_orc_linhas(p_so uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(x.l order by x.em, x.id), '[]'::jsonb)
    from (select p.created_at as em, p.id,
                 jsonb_build_object('nome', left(coalesce(pr.name, 'Peça'), 80), 'quantidade', p.quantity, 'preco', p.unit_sale_snapshot) as l
            from public.service_order_parts p
            left join public.products pr on pr.id = p.product_id
           where p.service_order_id = p_so
          union all
          select s.created_at, s.id,
                 jsonb_build_object('nome', left(coalesce(nullif(btrim(s.name_snapshot), ''), nullif(btrim(s.description_snapshot), ''), 'Serviço'), 80),
                                    'quantidade', s.quantity, 'preco', s.unit_price_snapshot)
            from public.service_order_services s
           where s.service_order_id = p_so) x;
$$;

comment on function public._retorno_orc_linhas(uuid) is
  'Retorno F3 (rr-f3-2b): as linhas do ORÇ como estão (nome, quantidade, preço), na ordem de criação, para o resumo do dono quando o áudio repetido acha o ORÇ que já existe.';

revoke all on function public._retorno_orc_linhas(uuid) from public, anon, authenticated;

-- ── 2. A marca do áudio, o ORÇ do caso e a conferência no PIN ─────────────────────────────────────────────────────────

create or replace function public.retorno_orc_do_audio_marcar(p_previa uuid, p_so uuid, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_so public.service_orders;
  v_n integer;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return jsonb_build_object('ok', false, 'motivo', 'nao_e_o_dono');
  end if;
  update public.retorno_previa p
     set dados = case when p.dados ? 'orc_pelo_audio_em' then p.dados
                      else p.dados || jsonb_build_object('orc_pelo_audio_em', v_agora) end,
         atualizada_em = v_agora
   where p.id = p_previa and p.service_order_id = p_so and p.estado = 'virou_orc';
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'motivo', 'sem_proposta');
  end if;
  select * into v_so from public.service_orders so where so.id = p_so;
  return jsonb_build_object('ok', true, 'service_order_id', v_so.id, 'numero', v_so.service_order_number,
                            'total', coalesce(v_so.grand_total, 0), 'impressao', public._retorno_orc_impressao(p_so),
                            'linhas', public._retorno_orc_linhas(p_so));
end;
$$;

comment on function public.retorno_orc_do_audio_marcar(uuid, uuid, uuid, timestamptz) is
  'Retorno F3 (rr-f3-2b): o áudio do dono criou o ORÇ desta proposta (virou_orc, service_order_id = p_so). Grava dados.orc_pelo_audio_em (o ato do dono, para orc_sem_ato; a 1ª vez fica) e devolve {ok, service_order_id, numero, total, impressao, linhas}. Só o dono.';

revoke all on function public.retorno_orc_do_audio_marcar(uuid, uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_orc_do_audio_marcar(uuid, uuid, uuid, timestamptz) to service_role;

create or replace function public.retorno_orc_do_audio_do_caso(p_abertura uuid, p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pv public.retorno_previa;
  v_so public.service_orders;
begin
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return null;
  end if;
  select p.* into v_pv
    from public.retorno_previa p
    join public.service_orders so on so.id = p.service_order_id
   where p.abertura_id = p_abertura
     and p.estado = 'virou_orc'
     and p.dados ? 'orc_pelo_audio_em'
     and p.pdf_em is null
     and so.status = 'draft' and so.quote_status = 'draft' and so.merged_into_id is null
     and so.created_at <= coalesce(p_agora, now())
   order by p.criada_em desc, p.id
   limit 1;
  if v_pv.id is null then
    return null;
  end if;
  select * into v_so from public.service_orders so where so.id = v_pv.service_order_id;
  return jsonb_build_object('previa_id', v_pv.id, 'service_order_id', v_so.id, 'numero', v_so.service_order_number,
                            'total', coalesce(v_so.grand_total, 0), 'impressao', public._retorno_orc_impressao(v_so.id),
                            'linhas', public._retorno_orc_linhas(v_so.id));
end;
$$;

comment on function public.retorno_orc_do_audio_do_caso(uuid, uuid, timestamptz) is
  'Retorno F3 (rr-f3-2b): o ORÇ que um áudio do dono já criou neste caso e que ainda está em rascunho, sem PDF: {previa_id, service_order_id, numero, total, impressao, linhas}; senão nulo. É o que impede o áudio repetido de criar outro. STABLE: só lê.';

revoke all on function public.retorno_orc_do_audio_do_caso(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_orc_do_audio_do_caso(uuid, uuid, timestamptz) to service_role;

create or replace function public.retorno_orc_do_audio_conferir(p_abertura uuid, p_so uuid, p_impressao text, p_phone text, p_autor uuid,
                                                                 p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ab public.retorno_aberturas;
  v_so public.service_orders;
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
  select * into v_so from public.service_orders so where so.id = p_so;
  if v_so.id is null then
    return jsonb_build_object('ok', false, 'motivo', 'mudou');
  end if;
  if v_so.quote_status is distinct from 'draft'
     or exists (select 1 from public.retorno_previa p where p.service_order_id = p_so and p.pdf_em is not null) then
    return jsonb_build_object('ok', false, 'motivo', 'enviado');
  end if;
  if v_so.status is distinct from 'draft' or v_so.merged_into_id is not null
     or public._retorno_orc_impressao(p_so) is distinct from p_impressao then
    return jsonb_build_object('ok', false, 'motivo', 'mudou');
  end if;

  select i.id, i.n into v_item, v_n
    from public.retorno_cartao_itens i
    join public.retorno_cartoes c on c.id = i.cartao_id
   where i.abertura_id = p_abertura and i.estado = 'vivo' and c.estado = 'vivo'
   limit 1;
  return jsonb_build_object('ok', true, 'item_id', v_item, 'n', v_n, 'numero', v_so.service_order_number);
end;
$$;

comment on function public.retorno_orc_do_audio_conferir(uuid, uuid, text, text, uuid, timestamptz) is
  'Retorno F3 (rr-f3-2b): no *sim <PIN>* do ditado, que agora só manda o PDF, confere que o ORÇ é o que o dono viu no resumo: dono, ditado ligado, caso aberto, telefone, ORÇ em rascunho, não juntado e com a mesma impressão digital. {ok, item_id, n, numero} (item nulo se o cartão já caiu) ou {ok: false, motivo: desligado | enviado | mudou}. STABLE: só lê.';

revoke all on function public.retorno_orc_do_audio_conferir(uuid, uuid, text, text, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_orc_do_audio_conferir(uuid, uuid, text, text, uuid, timestamptz) to service_role;

-- ── 3. Gerado do corpo vigente (pg_get_functiondef), com o trecho rr-f3-2b ─────────────────────────────────────────────

create or replace function public._retorno_item_montar(p_abertura uuid, p_n smallint, p_agora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  c_letras constant text[] := array['A', 'B', 'C', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'P', 'Q', 'R', 'T', 'U'];
  v_ab public.retorno_aberturas;
  v_rotulo text;
  v_fatos jsonb;
  v_os jsonb;
  v_f jsonb;
  v_m jsonb;
  v_nivel text;
  v_int text;
  v_tipo text;
  v_modelo text;
  v_texto text;
  v_opcoes jsonb := '[]'::jsonb;
  v_frases text[] := '{}';
  v_fato_txt text;
  v_linhas jsonb;
  v_k integer;
  v_clientes uuid[];
  v_c uuid;
  v_i integer := 0;
  v_numero text;
  v_retrato jsonb := '{}'::jsonb;
  v_prov uuid;
  -- F3 (P5)
  v_cfg public.retorno_config := public._retorno_cfg();
  v_hoje date;
  v_pv public.retorno_previa;
  v_cad jsonb;
  v_cli uuid;
  v_unidades jsonb;
  v_vessel uuid;
  v_vessel_nome text;
  v_rasc jsonb;
  v_ato boolean;
  v_int_ok boolean;
  v_ditada_depois boolean := false;
  v_acao text;
  v_previa uuid;
  v_so_f3 uuid;
  v_so_total text;
  v_hash_f3 text;
  v_f3_linhas text[] := '{}';
  v_pedacos text[] := '{}';
  v_nomes_un text[] := '{}';
  v_n_cat integer;
  v_n_dito integer;
  v_nome_cat text;
  v_nome_velho text;
  v_c20 text;
  v_precos text;
  v_partes text[];
  v_confira text;
  v_alt jsonb;
  v_sem_preco text[];
  v_n_desc integer;
  v_inativos text[];
  r record;
  i integer;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  v_rotulo := public._retorno_rotulo(p_abertura, p_agora);
  v_k := public._retorno_automaticas_hoje(v_ab.chave, p_agora);
  v_int := public._retorno_intencao_do_caso(p_abertura, p_agora);

  begin
    if v_ab.papel = 'cliente' then
      v_fatos := public.retorno_fatos_do_contato(v_ab.phone_normalized, p_agora);
    end if;
  exception when others then
    v_fatos := null;   -- sem fato, nunca "não há peça"
  end;
  if v_fatos is not null and jsonb_array_length(v_fatos -> 'os') = 1 then
    v_os := v_fatos -> 'os' -> 0;
    v_f := v_os -> 'fatos';
    v_numero := v_os ->> 'numero';
  end if;

  v_m := public._retorno_modelo_do_caso(p_abertura, p_agora);
  if v_m ->> 'modelo' is not null then
    select t.nivel into v_nivel from public.retorno_modelo_tipos t where t.tipo = v_m ->> 'modelo';
  end if;

  if v_ab.papel = 'cliente_ambiguo' then
    v_tipo := 'ambiguo';
    v_clientes := case when cardinality(v_ab.clientes) > 0 then v_ab.clientes
                       else array(select (e)::uuid from jsonb_array_elements_text(coalesce(v_ab.quem -> 'clientes', '[]'::jsonb)) e) end;
    foreach v_c in array v_clientes loop
      v_i := v_i + 1;
      exit when v_i > cardinality(c_letras);
      v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object(
        'letra', c_letras[v_i], 'acao', 'cliente', 'client_id', v_c, 'rotulo', coalesce(public._retorno_nome(v_c), 'sem nome')));
      v_frases := v_frases || format('*%s %s* = %s', p_n, c_letras[v_i], coalesce(public._retorno_nome(v_c), 'sem nome'));
    end loop;
  elsif v_ab.papel = 'numero_novo' then
    v_tipo := 'numero_novo';
    select a.record_id into v_prov
      from public.audit_log a
     where a.table_name = 'clients' and a.new_value ->> 'caso' = p_abertura::text
     limit 1;
    if v_prov is not null then
      v_opcoes := jsonb_build_array(jsonb_build_object('letra', 'D', 'acao', 'desfaz_cadastro', 'client_id', v_prov, 'rotulo', 'desfaz o cadastro'));
      v_frases := array[format('*%s D* = desfaz o cadastro', p_n)];
    end if;
  elsif v_m ->> 'modelo' is not null and v_nivel in ('cartao', 'sozinho') then
    v_tipo := 'modelo';
    v_modelo := v_m ->> 'modelo';
    v_texto := public._retorno_texto_do_modelo(p_abertura, v_m, null, p_agora);
    v_retrato := jsonb_build_object('fato', v_m -> 'fato', 'intencao', v_m ->> 'intencao');
    if v_modelo = 'modelo_aguarda_peca' then
      v_opcoes := jsonb_build_array(
        jsonb_build_object('letra', 'B', 'acao', 'chegou', 'os', v_numero, 'rotulo', 'a peça chegou'),
        jsonb_build_object('letra', 'C', 'acao', 'previsao', 'os', v_numero, 'rotulo', 'dite a previsão'));
      v_frases := array[format('*%s B* = %s', p_n, case when jsonb_array_length(v_f -> 'aguarda_peca' -> 'linhas') > 1 then 'chegou tudo' else 'a peça chegou' end),
                        format('*%s C* = dite a previsão', p_n)];
    end if;
  elsif (v_f is not null and v_f -> 'aguarda_peca' <> 'null'::jsonb)
        or (v_int = 'peca' and (v_f is null or v_f -> 'peca_chegou' = 'null'::jsonb)) then
    v_tipo := 'peca_sem_registro';
    if v_numero is not null then
      v_opcoes := jsonb_build_array(
        jsonb_build_object('letra', 'B', 'acao', 'chegou', 'os', v_numero, 'rotulo', 'a peça chegou'),
        jsonb_build_object('letra', 'C', 'acao', 'previsao', 'os', v_numero, 'rotulo', 'dite a previsão'));
      v_frases := array[format('*%s B* = %s', p_n,
                               case when v_f is not null and v_f -> 'aguarda_peca' <> 'null'::jsonb
                                         and jsonb_array_length(v_f -> 'aguarda_peca' -> 'linhas') > 1
                                    then 'chegou tudo' else 'a peça chegou' end),
                        format('*%s C* = dite a previsão', p_n)];
    end if;
  elsif v_f is not null and v_f -> 'concluida_sem_palavra' <> 'null'::jsonb then
    v_tipo := 'pronto_sem_palavra';
  elsif v_int = 'retirada' then
    v_tipo := 'retirada';
    v_opcoes := jsonb_build_array(
      jsonb_build_object('letra', 'A', 'acao', 'responder', 'modelo', 'modelo_liberado', 'marca_liberado', true, 'rotulo', 'pode retirar', 'os_id', v_os ->> 'id'),
      jsonb_build_object('letra', 'B', 'acao', 'responder', 'modelo', 'modelo_retirada_nao', 'rotulo', 'ainda não dá', 'os_id', v_os ->> 'id'));
    v_frases := array[format('*%s A* = pode retirar', p_n), format('*%s B* = ainda não dá', p_n)];
  elsif v_int = 'orcamento' then
    v_tipo := 'orcamento';
  elsif v_int = 'adicional' then
    v_tipo := 'adicional';
  else
    v_tipo := 'livre';
  end if;

  -- F3 (P5): a proposta no cartão. Só em vigor com previa_ditado_ligado = true ou previa_modo = 'ligado'; com as duas desligadas, o
  -- item é byte a byte o da F2. previa_modo = 'ligado' exige previa_ditado_ligado (check da P1): aqui as duas valem juntas.
  if v_cfg.previa_ditado_ligado or v_cfg.previa_modo = 'ligado' then
    v_hoje := (p_agora at time zone c_fuso)::date;
    select p.* into v_pv from public.retorno_previa p where p.abertura_id = p_abertura and p.estado = 'proposta' limit 1;
    v_cad := public._retorno_cadastro_do_caso(p_abertura);
    v_cli := (v_cad ->> 'client_id')::uuid;
    v_unidades := public._retorno_unidades_do_cliente(v_cli);
    v_vessel := coalesce(v_pv.vessel_id, (public._retorno_unidade_do_caso(p_abertura, v_cli, p_agora) ->> 'vessel_id')::uuid);
    v_rasc := public._retorno_rascunho_do_caso(p_abertura, p_agora);
    v_ato := (v_pv.id is not null and (v_pv.origem = 'ditado' or coalesce((v_pv.dados ->> 'ajustada_por_ditado')::boolean, false)))
             or (v_rasc is not null
                 and exists (select 1 from public.service_orders so
                              where so.id = (v_rasc ->> 'service_order_id')::uuid and so.origem_chave8 = v_ab.chave));
    v_int_ok := coalesce(v_int in ('orcamento', 'adicional'), false);

    if public._retorno_visita_em_aberto(p_abertura, p_agora) then
      -- Linha 0, em qualquer tipo: só lembra da visita. Não mexe nas opções da F2.
      v_f3_linhas := array[format('   Visita a combinar desde %s. *resolvido %s* tira da lista.',
                                  to_char(v_ab.visita_a_combinar_em at time zone c_fuso, 'DD/MM'), p_n)];
    elsif v_ato or (v_tipo in ('orcamento', 'adicional', 'numero_novo') and v_int_ok) then
      -- O ato do dono vale mais que a intenção adivinhada: nenhum modelo nem letra da F2 sobra neste caso.
      v_modelo := null;
      v_texto := null;
      v_retrato := '{}'::jsonb;
      if v_tipo <> 'numero_novo' then
        v_opcoes := '[]'::jsonb;
        v_frases := '{}';
      end if;
      v_vessel_nome := (select left(v.name, 30) from public.vessels v where v.id = v_vessel);

      -- A proposta ditada depois do rascunho é o ato mais novo do dono: ela vence a linha 1, senão o *sim <PIN>* mandaria o PDF velho.
      -- O rascunho feito depois do ditado segue vencendo. O que nasceu do próprio caso nem cai aqui: a proposta dele já está em virou_orc, fora de v_pv.
      v_ditada_depois := v_rasc is not null and v_pv.id is not null
                         and (v_pv.origem = 'ditado' or coalesce((v_pv.dados ->> 'ajustada_por_ditado')::boolean, false))
                         and (v_rasc ->> 'criado_em')::timestamptz < coalesce((v_pv.dados ->> 'ditada_em')::timestamptz, v_pv.criada_em);

      if v_rasc is not null and not v_ditada_depois then
        -- Linhas 1 e 1b: o rascunho exato que está na mesa, com número, data e unidade à vista.
        v_so_f3 := (v_rasc ->> 'service_order_id')::uuid;
        v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'L', 'acao', 'responder', 'modelo', 'modelo_ver_no_local', 'os_id', null, 'rotulo', 'precisa ver no local'));
        if coalesce((v_rasc ->> 'total')::numeric, 0) > 0 and (v_rasc ->> 'linhas_n')::integer > 0 and (v_rasc ->> 'linhas_sem_preco')::integer = 0 then
          v_acao := 'pdf';
          -- rr-f3-2b (20/11/2026): o *sim <PIN>* do rascunho vale sobre o orçamento inteiro, não só o total: item, preço,
          -- quantidade, cliente, unidade e título entram na impressão digital.
          v_so_total := (v_rasc ->> 'total') || ':' || coalesce(public._retorno_orc_impressao(v_so_f3), '');
          v_f3_linhas := array[format('   Rascunho %s de %s%s: %s · R$ %s · vale até %s se sair hoje',
            v_rasc ->> 'numero',
            to_char((v_rasc ->> 'criado_em')::timestamptz at time zone c_fuso, 'DD/MM'),
            case when v_rasc ->> 'unidade' is not null then ' · ' || left(v_rasc ->> 'unidade', 30) else '' end,
            case when (v_rasc ->> 'linhas_n')::integer = 1 then '1 item' else (v_rasc ->> 'linhas_n') || ' itens' end,
            public._retorno_brl((v_rasc ->> 'total')::numeric),
            public._retorno_quando(public._retorno_validade_do_envio(p_agora), v_hoje))];
        else
          v_f3_linhas := array[format('   Rascunho %s de %s está sem valor: complete na tela. *%s L* precisa ver no local.',
            v_rasc ->> 'numero', to_char((v_rasc ->> 'criado_em')::timestamptz at time zone c_fuso, 'DD/MM'), p_n)];
        end if;

      elsif v_pv.id is not null then
        -- Linhas 2 a 5b: a proposta viva.
        v_previa := v_pv.id;
        v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'L', 'acao', 'responder', 'modelo', 'modelo_ver_no_local', 'os_id', null, 'rotulo', 'precisa ver no local'));

        select count(*) filter (where l.preco_fonte = 'catalogo'),
               count(*) filter (where l.preco_fonte = 'dito'),
               (array_agg(left(l.nome, 40) order by l.ordem) filter (where l.preco_fonte = 'catalogo'))[1],
               (array_agg(left(l.nome, 40) order by l.preco_em, l.ordem) filter (where l.preco_em is not null))[1]
          into v_n_cat, v_n_dito, v_nome_cat, v_nome_velho
          from public.retorno_previa_linhas l where l.previa_id = v_pv.id;

        if v_pv.origem = 'ditado' then
          v_c20 := format('   Proposta ditada%s: %s · R$ %s · %s %s %s por você',
            case when v_vessel_nome is not null then ' · ' || v_vessel_nome else '' end,
            case when v_pv.linhas_n = 1 then '1 item' else v_pv.linhas_n || ' itens' end,
            public._retorno_brl(v_pv.total),
            v_n_dito,
            case when v_n_dito = 1 then 'preço' else 'preços' end,
            case when v_n_dito = 1 then 'dito' else 'ditos' end);
        else
          if v_pv.linhas_n > 0 and v_n_cat = v_pv.linhas_n then
            v_precos := 'preços de catálogo, sem data';
          elsif v_pv.linhas_n > 0 and v_n_dito = v_pv.linhas_n then
            v_precos := 'preços ditados por você';
          else
            v_partes := '{}';
            if v_pv.preco_mais_antigo is not null then
              v_partes := v_partes || ('preços de ' || public._retorno_mes_aa(v_pv.preco_mais_antigo));
            end if;
            if v_n_cat > 0 then
              v_partes := v_partes || format('%s de catálogo, sem data', v_n_cat);
            end if;
            if v_n_dito > 0 then
              v_partes := v_partes || format('%s %s por você', v_n_dito, case when v_n_dito = 1 then 'dito' else 'ditos' end);
            end if;
            v_precos := array_to_string(v_partes, ' e ');
          end if;
          v_confira := case
            when v_pv.preco_mais_antigo is not null and v_pv.preco_mais_antigo < (v_hoje - v_cfg.previa_preco_velho)::date then v_nome_velho
            when v_n_cat > 0 then v_nome_cat
          end;
          v_c20 := format('   Proposta com base no %s%s%s: %s · R$ %s%s%s',
            v_pv.fonte_numero,
            case when not coalesce((v_pv.dados ->> 'fonte_aprovada')::boolean, false) then ' (não aprovado)' else '' end,
            case when v_vessel_nome is not null then ' · ' || v_vessel_nome else '' end,
            case when v_pv.linhas_n = 1 then '1 item' else v_pv.linhas_n || ' itens' end,
            public._retorno_brl(v_pv.total),
            case when coalesce(v_precos, '') <> '' then ' · ' || v_precos else '' end,
            case when v_confira is not null then ': confira o preço de ' || v_confira else '' end);
        end if;
        v_f3_linhas := array[v_c20];

        if v_vessel is not null then
          -- Linhas 2, 2b e 3: a proposta com unidade definida.
          v_acao := 'orcar';
          v_hash_f3 := public._retorno_previa_hash_efetivo(v_pv.id, p_agora);
          v_alt := v_pv.dados -> 'alternativas' -> 0;
          if v_alt is not null and v_alt ->> 'os_id' is not null then
            v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'B', 'acao', 'parecido', 'os_id', v_alt ->> 'os_id', 'numero', v_alt ->> 'numero', 'rotulo', 'usa o ' || (v_alt ->> 'numero')));
            v_pedacos := v_pedacos || format('*%s B* usa o %s', p_n, v_alt ->> 'numero');
          end if;

          if v_pv.provisorios_n > 0 then
            -- Linha 3: o que falta completar aparece aqui, e o *sim <PIN>* não cria nada enquanto faltar (P6).
            select coalesce(array_agg(left(l.nome, 40) order by l.ordem) filter (where l.estado = 'provisorio' and l.motivo in ('sem_preco', 'preco_invalido')), '{}'),
                   count(*) filter (where l.estado = 'provisorio' and l.motivo = 'nome_com_dado_de_outro'),
                   coalesce(array_agg(left(l.nome, 40) order by l.ordem) filter (where l.estado = 'provisorio' and l.motivo = 'inativo'), '{}')
              into v_sem_preco, v_n_desc, v_inativos
              from public.retorno_previa_linhas l where l.previa_id = v_pv.id;
            if cardinality(v_sem_preco) > 0 then
              v_f3_linhas := v_f3_linhas || format('   Falta preço em %s: %s. Dite o valor antes do *sim*.',
                                                   cardinality(v_sem_preco), array_to_string(v_sem_preco[1:2], ', '));
            end if;
            if v_n_desc > 0 then
              v_f3_linhas := v_f3_linhas || format('   Falta descrever %s %s: diga o que é cada um antes do *sim*.',
                                                   v_n_desc, case when v_n_desc = 1 then 'serviço' else 'serviços' end);
            end if;
            if cardinality(v_inativos) > 0 then
              v_f3_linhas := v_f3_linhas || format('   Fora de linha no cadastro: %s. Troque ou tire antes do *sim*.', array_to_string(v_inativos[1:2], ', '));
            end if;
          elsif v_pv.origem <> 'ditado' and not coalesce((v_pv.dados ->> 'forte')::boolean, false) then
            -- Linha 2b: fora de mesmo cliente com família idêntica, o dono lê as linhas antes do PIN. O corte pelo teto de 3.500 é de _retorno_cartao_texto.
            for r in select l.* from public.retorno_previa_linhas l where l.previa_id = v_pv.id order by l.ordem limit v_cfg.previa_max_linhas loop
              v_f3_linhas := v_f3_linhas || format('   · %s · %s × R$ %s · %s', left(r.nome, 40), public._retorno_qtd(r.quantidade),
                                                   public._retorno_brl(r.preco), public._retorno_rotulo_do_preco(r.preco_fonte, r.preco_em, true));
            end loop;
          end if;
        elsif jsonb_array_length(v_unidades) >= 2 then
          -- Linha 4: 2 ou mais unidades e nenhuma definida.
          for i in 1 .. least(jsonb_array_length(v_unidades), 4) loop
            v_nomes_un := v_nomes_un || format('*%s %s* %s', p_n, (array['C', 'F', 'G', 'H'])[i], v_unidades -> (i - 1) ->> 'nome');
            v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', (array['C', 'F', 'G', 'H'])[i], 'acao', 'unidade',
              'vessel_id', v_unidades -> (i - 1) ->> 'vessel_id', 'rotulo', v_unidades -> (i - 1) ->> 'nome'));
          end loop;
          v_f3_linhas := v_f3_linhas || ('   Qual unidade? ' || array_to_string(v_nomes_un, ' · '));
        elsif v_cli is not null then
          -- Linha 5: cliente no cadastro, inclusive provisório, sem unidade.
          v_f3_linhas := v_f3_linhas || format('   Falta cadastrar a unidade: diga o nome e o tipo (*cadastra a lancha Brisa no %s*) ou crie no app, e mande *retorno*.', p_n);
        else
          -- Linha 5b: número novo sem cadastro.
          v_f3_linhas := v_f3_linhas || '   Cadastro incompleto: o orçamento só sai depois que ele responder.'::text;
        end if;

        -- C23: só o que existe. *ver N* só com proposta viva.
        v_pedacos := v_pedacos || format('*%s L* precisa ver no local', p_n);
        v_pedacos := v_pedacos || format('*ver %s* mostra os itens', p_n);
        v_f3_linhas := v_f3_linhas || ('   ' || array_to_string(v_pedacos, ' · '));

      elsif v_int_ok then
        -- Linhas 6a a 6d: sem proposta viva (sem parecido, ou proposta só em sombra). Nunca diz "sem parecido".
        v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', 'L', 'acao', 'responder', 'modelo', 'modelo_ver_no_local', 'os_id', null, 'rotulo', 'precisa ver no local'));
        if v_cli is null then
          v_f3_linhas := array[format('   Cadastro incompleto: o orçamento aparece aqui quando ele responder. *%s L* precisa ver no local.', p_n)];
        elsif v_vessel is not null then
          v_f3_linhas := array[format('   Dite o orçamento em áudio. *%s L* precisa ver no local.', p_n)];
        elsif jsonb_array_length(v_unidades) >= 2 then
          for i in 1 .. least(jsonb_array_length(v_unidades), 4) loop
            v_nomes_un := v_nomes_un || format('*%s %s* %s', p_n, (array['C', 'F', 'G', 'H'])[i], v_unidades -> (i - 1) ->> 'nome');
            v_opcoes := v_opcoes || jsonb_build_array(jsonb_build_object('letra', (array['C', 'F', 'G', 'H'])[i], 'acao', 'unidade',
              'vessel_id', v_unidades -> (i - 1) ->> 'vessel_id', 'rotulo', v_unidades -> (i - 1) ->> 'nome'));
          end loop;
          v_f3_linhas := array[format('   Qual unidade? %s. Depois dite o orçamento em áudio. *%s L* precisa ver no local.', array_to_string(v_nomes_un, ' · '), p_n)];
        else
          v_f3_linhas := array[format('   Falta cadastrar a unidade: diga o nome e o tipo (*cadastra a lancha Brisa no %s*) ou crie no app, e mande *retorno*.', p_n),
                               format('   *%s L* precisa ver no local', p_n)];
        end if;
      end if;
    end if;
  end if;

  v_linhas := jsonb_build_array(format('%s. %s%s%s · %s · %s · %s', p_n, v_rotulo,
    case when v_numero is not null then ' · ' || v_numero else '' end,
    case when v_os ->> 'bem' is not null then ' · ' || (v_os ->> 'bem') else '' end,
    to_char(v_ab.aberta_em at time zone c_fuso, 'HH24:MI'),
    public._retorno_prazo_curto(p_abertura, p_agora),
    public._retorno_pedido_do_caso(p_abertura, p_agora)));

  v_fato_txt := public._retorno_fato_texto(v_f, v_tipo = 'retirada', (v_os ->> 'id')::uuid, v_rotulo, p_agora);
  if v_fato_txt is not null then
    v_linhas := v_linhas || jsonb_build_array('   O que sei: ' || v_fato_txt);
  end if;
  if v_modelo is not null then
    v_linhas := v_linhas || jsonb_build_array(format('   Modelo: ''%s''', v_texto));
  end if;
  if cardinality(v_frases) > 0 then
    v_linhas := v_linhas || jsonb_build_array('   ' || array_to_string(v_frases, ' · '));
  end if;
  -- F3 (P5): as linhas da proposta vêm depois das frases da F2 (a letra D do número novo fica) e antes do "Ele já recebeu".
  if cardinality(v_f3_linhas) > 0 then
    v_linhas := v_linhas || to_jsonb(v_f3_linhas);
  end if;
  if v_k >= 1 then
    v_linhas := v_linhas || jsonb_build_array(format('   Ele já recebeu %s automáticas hoje.', v_k));
  end if;

  return jsonb_build_object(
    'tipo_item', v_tipo, 'modelo_tipo', v_modelo, 'service_order_id', coalesce(v_so_f3::text, v_os ->> 'id'), 'texto_mostrado', v_texto,
    'opcoes', v_opcoes, 'fatos', v_retrato, 'linhas', v_linhas,
    'previa_id', v_previa, 'acao_sim', v_acao,   -- F3 (P5)
    -- F3 (P5): com acao_sim, o hash inclui a proposta (efetiva) ou o total do rascunho, e v_k sai: um adiamento automático com o cartão aberto não dá fato_mudou.
    'hash', md5(concat_ws('|', v_ab.phone_normalized, v_modelo, v_texto, v_retrato::text,
                          case when v_acao is null then v_k end, v_hash_f3, v_so_total)));
end;
$$;

revoke all on function public._retorno_item_montar(uuid, smallint, timestamptz) from public, anon, authenticated;

insert into supabase_migrations.schema_migrations (version, name) values ('20270214100100','retorno_f3_audio_cria_orc');
