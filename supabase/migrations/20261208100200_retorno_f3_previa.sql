-- Retorno rápido ao cliente, F3 (P3): montar a proposta.
--
-- A proposta nasce do orçamento parecido mais recente, com o último preço de cada linha e a data dele, e nunca é OS: o ORÇ só
-- nasce no ato do dono (F3, P6 e P7). Preço de orçamento não aprovado aparece como *orçado, não aprovado*, nunca como praticado.
-- O preço nunca é o do parecido: cada linha é reprecificada aqui. Zero é ausência de preço.
--
-- 1. Cadastro e unidade do caso: _retorno_cadastro_do_caso, _retorno_unidades_do_cliente, _retorno_unidade_do_caso (palavra
--    inteira, nunca nome parcial, unidade com nome igual ao tipo não identifica) e _retorno_rascunho_do_caso.
-- 2. Preço e nome: _retorno_nome_limpo (nome de linha da fonte que tem dado de outro cliente vira "Serviço a descrever"),
--    _retorno_preco_da_peca, _retorno_preco_do_servico (aprovado primeiro, nunca o não aprovado como praticado) e
--    _retorno_rotulo_do_preco, o único lugar que escreve a palavra do preço.
-- 3. retorno_previa_precos: expõe as funções de preço ao TypeScript (C-PRECO).
-- 4. Hash único: _retorno_previa_hash; _retorno_previa_hash_efetivo vale o que o dono está vendo no cartão.
-- 5. retorno_previa_montar (C-MONTAR) e retorno_previa_rodada (C-RODADA). Tudo nasce desligado: previa_modo = 'desligado'.
--
-- Sem dado; nada toca em cliente, unidade ou orçamento. Reverter: drop das funções; as tabelas da P1 ficam.

-- ── 1. Cadastro e unidade ───────────────────────────────────────────────────────────────────────────

create or replace function public._retorno_cadastro_do_caso(p_abertura uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ab public.retorno_aberturas;
  v_cliente uuid;
  v_vessel uuid;
  v_audit jsonb;
  v_prov boolean := false;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found then
    return null;
  end if;

  if v_ab.papel = 'cliente' and v_ab.client_id is not null then
    v_cliente := v_ab.client_id;
  else
    -- Número novo: o vínculo fica só no audit_log do cadastro provisório (A-1, _retorno_item_montar lê do mesmo jeito).
    select a.record_id, a.new_value into v_cliente, v_audit
      from public.audit_log a
     where a.table_name = 'clients' and a.new_value ->> 'caso' = p_abertura::text
     limit 1;
    if v_cliente is null then
      return null;
    end if;
    v_vessel := (v_audit ->> 'vessel_id')::uuid;
  end if;

  -- Só cadastro ativo: a letra D desativa cliente e unidade, e aí o caso volta a não ter cadastro.
  select coalesce(c.provisorio, false) into v_prov from public.clients c where c.id = v_cliente and c.active;
  if not found then
    return null;
  end if;
  if v_vessel is not null and not exists (select 1 from public.vessels v where v.id = v_vessel and v.active) then
    v_vessel := null;
  end if;

  return jsonb_build_object('client_id', v_cliente, 'vessel_id', v_vessel, 'provisorio', v_prov);
end;
$$;

comment on function public._retorno_cadastro_do_caso(uuid) is
  'Retorno F3 (P3): {client_id, vessel_id, provisorio} do caso. Papel cliente: retorno_aberturas.client_id; senão o audit_log do cadastro provisório. Só devolve cadastro ativo; nulo quando não há.';

revoke all on function public._retorno_cadastro_do_caso(uuid) from public, anon, authenticated;

create or replace function public._retorno_unidades_do_cliente(p_client uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('numero', x.n, 'vessel_id', x.id, 'nome', left(x.name, 30)) order by x.n), '[]'::jsonb)
    from (select v.id, v.name, row_number() over (order by v.name, v.id) as n
            from public.vessels v
           where v.client_id = p_client and v.active) x;
$$;

comment on function public._retorno_unidades_do_cliente(uuid) is
  'Retorno F3 (P3): unidades ativas numeradas por nome. É a única numeração: as letras C, F, G e H do cartão e o campo unidade do ditado apontam para esta lista.';

revoke all on function public._retorno_unidades_do_cliente(uuid) from public, anon, authenticated;

create or replace function public._retorno_unidade_do_caso(p_abertura uuid, p_client uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ab public.retorno_aberturas;
  v_unidades jsonb;
  v_n integer;
  v_casaram uuid[];
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;

  -- A escolha do dono vence, se a unidade segue ativa e é do cliente.
  if v_ab.unidade_escolhida_id is not null and p_client is not null
     and exists (select 1 from public.vessels v where v.id = v_ab.unidade_escolhida_id and v.active and v.client_id = p_client) then
    return jsonb_build_object('vessel_id', v_ab.unidade_escolhida_id, 'origem', 'dono');
  end if;

  v_unidades := public._retorno_unidades_do_cliente(p_client);
  v_n := jsonb_array_length(v_unidades);
  if v_n = 0 then
    return jsonb_build_object('vessel_id', null, 'motivo', 'sem_unidade', 'unidades', '[]'::jsonb);
  end if;
  if v_n = 1 then
    return jsonb_build_object('vessel_id', v_unidades -> 0 -> 'vessel_id', 'origem', 'unica');
  end if;

  -- 2 ou mais: o nome inteiro, como palavra inteira, em alguma mensagem do caso. _retorno_busca só deixa letra, número e espaço,
  -- então não há curinga, e "Brisa" não casa em "Brisamar". Nome igual ao tipo, vazio ou com menos de 3 letras não identifica.
  select coalesce(array_agg(distinct v.id), '{}'::uuid[]) into v_casaram
    from public.vessels v
    join jsonb_array_elements(v_unidades) u on (u ->> 'vessel_id')::uuid = v.id
   where public._retorno_busca(v.name) <> ''
     and public._retorno_busca(v.name) <> public._retorno_busca(v.asset_type)
     and char_length(public._retorno_busca(v.name)) >= 3
     and exists (select 1
                   from public.retorno_mensagens m
                   join public.whatsapp_messages w on w.id = m.whatsapp_message_id
                  where m.abertura_id = p_abertura
                    and m.recebida_em <= p_agora
                    and ' ' || public._retorno_busca(w.body) || ' ' like '% ' || public._retorno_busca(v.name) || ' %');

  if cardinality(v_casaram) = 1 then
    return jsonb_build_object('vessel_id', v_casaram[1], 'origem', 'mensagem');
  end if;
  return jsonb_build_object('vessel_id', null, 'unidades', v_unidades);
end;
$$;

comment on function public._retorno_unidade_do_caso(uuid, uuid, timestamptz) is
  'Retorno F3 (P3): a unidade do caso: {vessel_id, origem} (dono, unica, mensagem) ou {vessel_id: null, unidades, motivo}. O cartão pergunta ao dono quando ela não fica definida. Nome diferente nunca casa.';

revoke all on function public._retorno_unidade_do_caso(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_rascunho_do_caso(p_abertura uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ab public.retorno_aberturas;
  v_cliente uuid;
  v_vessel uuid;
  v_so public.service_orders;
  v_n_pecas integer;
  v_n_serv integer;
  v_sem_preco integer;
  v_unidade text;
begin
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found then
    return null;
  end if;
  v_cliente := (public._retorno_cadastro_do_caso(p_abertura) ->> 'client_id')::uuid;
  if v_cliente is null then
    return null;
  end if;
  v_vessel := (public._retorno_unidade_do_caso(p_abertura, v_cliente, p_agora) ->> 'vessel_id')::uuid;

  select so.* into v_so
    from public.service_orders so
   where so.client_id = v_cliente
     and so.status = 'draft'
     and so.quote_status = 'draft'
     and so.merged_into_id is null
     and so.created_at >= v_ab.aberta_em - interval '14 days'
     and so.created_at <= p_agora
     and (v_vessel is null or so.vessel_id = v_vessel)
   order by (so.origem_chave8 is not distinct from v_ab.chave) desc, so.created_at desc, so.id
   limit 1;
  if not found then
    return null;
  end if;

  select count(*), count(*) filter (where p.unit_sale_snapshot <= 0) into v_n_pecas, v_sem_preco
    from public.service_order_parts p where p.service_order_id = v_so.id;
  select count(*), count(*) filter (where s.unit_price_snapshot <= 0) + v_sem_preco into v_n_serv, v_sem_preco
    from public.service_order_services s where s.service_order_id = v_so.id;
  select v.name into v_unidade from public.vessels v where v.id = v_so.vessel_id;

  return jsonb_build_object(
    'service_order_id', v_so.id,
    'numero', v_so.service_order_number,
    'criado_em', v_so.created_at,
    'unidade', v_unidade,
    'total', coalesce(v_so.grand_total, 0),
    'linhas_n', v_n_pecas + v_n_serv,
    'linhas_sem_preco', v_sem_preco);
end;
$$;

comment on function public._retorno_rascunho_do_caso(uuid, timestamptz) is
  'Retorno F3 (P3): o rascunho exato que o cartão oferece, ou nulo. Cliente por _retorno_cadastro_do_caso; com unidade definida no caso, só a mesma unidade; origem_chave8 igual à chave do caso vem primeiro, depois o mais novo.';

revoke all on function public._retorno_rascunho_do_caso(uuid, timestamptz) from public, anon, authenticated;

-- ── 2. Nome e preço ─────────────────────────────────────────────────────────────────────────────────

create or replace function public._retorno_nome_limpo(p_nome text, p_fonte_client uuid, p_fonte_vessel uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_b text;
  v_palavras text[] := '{}';
  v_p text;
begin
  if p_nome is null or btrim(p_nome) = '' then
    return null;
  end if;

  -- Telefone, CPF, CNPJ, e-mail e placa: as regex de _shared/retorno/mascara.ts (\y no lugar do \b).
  if p_nome ~ '[[:alnum:]._%+-]+@[[:alnum:]-]+(\.[[:alnum:]-]+)+'
     or p_nome ~ '\y\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\y'
     or p_nome ~ '\y\d{3}\.?\d{3}\.?\d{3}-?\d{2}\y'
     or p_nome ~ '(\+?55[\s.-]?)?(\(?\d{2}\)?[\s.-]?)?\y9?\d{4}[\s.-]?\d{4}\y'
     or p_nome ~* '\y[A-Z]{3}-?\d[A-Z0-9]\d{2}\y' then
    return null;
  end if;

  -- Palavra do nome ou do display_name do cliente da fonte, ou do nome da unidade da fonte, inteira, em qualquer lugar do texto.
  -- "lancha" sozinha não identifica (nome igual a uma palavra de bem), e número sozinho também não.
  v_b := ' ' || public._retorno_busca(p_nome) || ' ';
  select coalesce(array_agg(distinct x.w), '{}'::text[]) into v_palavras
    from (select unnest(string_to_array(public._retorno_busca(coalesce(c.name, '') || ' ' || coalesce(c.display_name, '')), ' ')) as w
            from public.clients c where c.id = p_fonte_client
          union all
          select unnest(string_to_array(public._retorno_busca(v.name), ' '))
            from public.vessels v where v.id = p_fonte_vessel) x
   where char_length(x.w) >= 3
     and x.w !~ '^[0-9]+$'
     and x.w not in ('dos', 'das', 'de', 'do', 'da')
     and public._retorno_classe_do_bem(x.w) is null;

  foreach v_p in array v_palavras loop
    if v_b like '% ' || v_p || ' %' then
      return null;
    end if;
  end loop;

  return p_nome;
end;
$$;

comment on function public._retorno_nome_limpo(text, uuid, uuid) is
  'Retorno F3 (P3): o nome da linha, ou nulo se ele tem nome do cliente ou da unidade da fonte, telefone, CPF, CNPJ, e-mail ou placa. Linha de orçamento antigo vai ao PDF de outro cliente.';

revoke all on function public._retorno_nome_limpo(text, uuid, uuid) from public, anon, authenticated;

create or replace function public._retorno_preco_da_peca(p_product uuid, p_client uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_r record;
  v_catalogo numeric;
begin
  select x.preco, x.fonte, x.em into v_r
    from (select p.unit_sale_snapshot as preco, p.created_at, p.id,
                 to_char(p.created_at at time zone 'America/Sao_Paulo', 'YYYY-MM-DD') as em,
                 case when public._retorno_os_aprovada(so.status, so.quote_status) and so.client_id = p_client then 'praticado_cliente'
                      when public._retorno_os_aprovada(so.status, so.quote_status) then 'praticado_outro'
                      when so.client_id = p_client then 'orcado_cliente'
                      else 'orcado_outro' end as fonte,
                 case when public._retorno_os_aprovada(so.status, so.quote_status) and so.client_id = p_client then 1
                      when public._retorno_os_aprovada(so.status, so.quote_status) then 2
                      when so.client_id = p_client then 3
                      else 4 end as prioridade
            from public.service_order_parts p
            join public.service_orders so on so.id = p.service_order_id
           where p.product_id = p_product
             and p.unit_sale_snapshot > 0
             and p.created_at <= p_agora
             and so.status <> 'cancelled') x
   order by x.prioridade, x.created_at desc, x.id
   limit 1;
  if found then
    return jsonb_build_object('preco', v_r.preco, 'fonte', v_r.fonte, 'em', v_r.em);
  end if;

  select pr.sale_price into v_catalogo from public.products pr where pr.id = p_product;
  if v_catalogo is not null and v_catalogo > 0 then
    return jsonb_build_object('preco', v_catalogo, 'fonte', 'catalogo', 'em', null);
  end if;
  return jsonb_build_object('preco', null, 'fonte', 'sem_preco', 'em', null);
end;
$$;

comment on function public._retorno_preco_da_peca(uuid, uuid, timestamptz) is
  'Retorno F3 (P3): {preco, fonte, em} da peça até p_agora: aprovado a este cliente, aprovado a outro, orçado a este, orçado a outro, catálogo, sem_preco. Zero é ausência. Nunca confunde orçado com praticado.';

revoke all on function public._retorno_preco_da_peca(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_preco_do_servico(p_service uuid, p_nome text, p_client uuid, p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_r record;
  v_busca text := public._retorno_busca(p_nome);
  v_catalogo numeric;
begin
  select x.preco, x.fonte, x.em into v_r
    from (select s.unit_price_snapshot as preco, coalesce(s.created_at, so.created_at) as quando, s.id,
                 to_char(coalesce(s.created_at, so.created_at) at time zone 'America/Sao_Paulo', 'YYYY-MM-DD') as em,
                 case when public._retorno_os_aprovada(so.status, so.quote_status) and so.client_id = p_client then 'praticado_cliente'
                      when public._retorno_os_aprovada(so.status, so.quote_status) then 'praticado_outro'
                      when so.client_id = p_client then 'orcado_cliente'
                      else 'orcado_outro' end as fonte,
                 case when public._retorno_os_aprovada(so.status, so.quote_status) and so.client_id = p_client then 1
                      when public._retorno_os_aprovada(so.status, so.quote_status) then 2
                      when so.client_id = p_client then 3
                      else 4 end as prioridade
            from public.service_order_services s
            join public.service_orders so on so.id = s.service_order_id
           where s.unit_price_snapshot > 0
             and so.status <> 'cancelled'
             and coalesce(s.created_at, so.created_at) <= p_agora
             and case when p_service is not null then s.service_id = p_service
                      else v_busca <> '' and public._retorno_busca(s.name_snapshot) = v_busca end) x
   order by x.prioridade, x.quando desc, x.id
   limit 1;
  if found then
    return jsonb_build_object('preco', v_r.preco, 'fonte', v_r.fonte, 'em', v_r.em);
  end if;

  if p_service is not null then
    select sv.default_price into v_catalogo from public.services sv where sv.id = p_service;
    if v_catalogo is not null and v_catalogo > 0 then
      return jsonb_build_object('preco', v_catalogo, 'fonte', 'catalogo', 'em', null);
    end if;
  end if;
  return jsonb_build_object('preco', null, 'fonte', 'sem_preco', 'em', null);
end;
$$;

comment on function public._retorno_preco_do_servico(uuid, text, uuid, timestamptz) is
  'Retorno F3 (P3): {preco, fonte, em} do serviço até p_agora, na ordem da peça. Liga por service_id quando há; senão, por nome normalizado igual. Sem histórico: catálogo; senão sem_preco.';

revoke all on function public._retorno_preco_do_servico(uuid, text, uuid, timestamptz) from public, anon, authenticated;

create or replace function public._retorno_rotulo_do_preco(p_fonte text, p_em date, p_curto boolean default false)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_d text := to_char(p_em, 'DD/MM/YY');
begin
  return case p_fonte
    when 'praticado_cliente' then case when p_curto then v_d else 'praticado em ' || v_d end
    when 'praticado_outro' then case when p_curto then 'outro cliente ' || v_d else 'praticado a outro cliente em ' || v_d end
    when 'orcado_cliente' then case when p_curto then 'orçado ' || v_d else 'orçado em ' || v_d || ' (não aprovado)' end
    when 'orcado_outro' then case when p_curto then 'orçado a outro ' || v_d else 'orçado a outro cliente em ' || v_d || ' (não aprovado)' end
    when 'catalogo' then case when p_curto then 'catálogo' else 'preço de catálogo, sem data' end
    when 'dito' then case when p_curto then 'dito' else 'você disse' end
    when 'sem_preco' then 'sem preço'
  end;
end;
$$;

comment on function public._retorno_rotulo_do_preco(text, date, boolean) is
  'Retorno F3 (P3): o único lugar que escreve a palavra do preço. O TypeScript recebe pronto e nunca escreve "praticado".';

revoke all on function public._retorno_rotulo_do_preco(text, date, boolean) from public, anon, authenticated;

create or replace function public.retorno_previa_precos(p_client uuid, p_itens jsonb, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_itens jsonb := coalesce(p_itens, '[]'::jsonb);
  v_agora timestamptz := coalesce(p_agora, now());
  v_saida jsonb := '[]'::jsonb;
  r record;
  v_tipo text;
  v_p jsonb;
begin
  if jsonb_typeof(v_itens) <> 'array' or jsonb_array_length(v_itens) > 40 then
    raise exception 'retorno_previa_precos: no máximo 40 itens' using errcode = '22023';
  end if;

  for r in
    select t.valor, t.ord
      from jsonb_array_elements(v_itens) with ordinality as t(valor, ord)
     order by t.ord
  loop
    v_tipo := r.valor ->> 'tipo';
    if v_tipo is null or v_tipo not in ('peca', 'servico') then
      raise exception 'retorno_previa_precos: tipo inválido: %', v_tipo using errcode = '22023';
    end if;
    if v_tipo = 'peca' then
      if r.valor ->> 'product_id' is null then
        v_p := jsonb_build_object('preco', null, 'fonte', 'sem_preco', 'em', null);
      else
        v_p := public._retorno_preco_da_peca((r.valor ->> 'product_id')::uuid, p_client, v_agora);
      end if;
    else
      if r.valor ->> 'service_id' is null and nullif(btrim(r.valor ->> 'nome'), '') is null then
        v_p := jsonb_build_object('preco', null, 'fonte', 'sem_preco', 'em', null);
      else
        v_p := public._retorno_preco_do_servico((r.valor ->> 'service_id')::uuid, r.valor ->> 'nome', p_client, v_agora);
      end if;
    end if;
    v_saida := v_saida || jsonb_build_array(jsonb_build_object(
      'chave', r.valor ->> 'chave',
      'preco', v_p -> 'preco',
      'fonte', v_p ->> 'fonte',
      'em', v_p -> 'em',
      'rotulo', public._retorno_rotulo_do_preco(v_p ->> 'fonte', (v_p ->> 'em')::date)));
  end loop;
  return v_saida;
end;
$$;

comment on function public.retorno_previa_precos(uuid, jsonb, timestamptz) is
  'Retorno F3 (P3, C-PRECO): o preço de cada linha para o TypeScript, com fonte, data e rótulo, na mesma ordem e com a mesma chave. Até 40 itens. Só lê. preco nunca vem zero.';

revoke all on function public.retorno_previa_precos(uuid, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_previa_precos(uuid, jsonb, timestamptz) to service_role;

-- ── 3. Dinheiro, quantidade e hash ──────────────────────────────────────────────────────────────────

create or replace function public._retorno_brl(p numeric)
returns text
language sql
immutable
set search_path = public
as $$
  select regexp_replace(translate(to_char(p, 'FM999G999G999G990D00'), ',.', '.,'), ',00$', '');
$$;

comment on function public._retorno_brl(numeric) is
  'Retorno F3 (P3): valor em R$ sem o símbolo. Inteiro sai sem centavos (1.320); com centavos, sempre duas casas (1.320,50). Preço unitário nunca é arredondado para inteiro.';

revoke all on function public._retorno_brl(numeric) from public, anon, authenticated;

create or replace function public._retorno_qtd(p numeric)
returns text
language sql
immutable
set search_path = public
as $$
  select replace(trim_scale(p)::text, '.', ',');
$$;

comment on function public._retorno_qtd(numeric) is
  'Retorno F3 (P3): quantidade sem zeros à direita e com vírgula (1, 1,5, 2,25).';

revoke all on function public._retorno_qtd(numeric) from public, anon, authenticated;

create or replace function public._retorno_previa_hash(p_vessel uuid, p_titulo text, p_linhas jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select md5(concat_ws('|', p_vessel, p_titulo,
    (select string_agg(concat_ws(':', l ->> 'ordem', coalesce(l ->> 'product_id', l ->> 'service_id', l ->> 'nome'),
                                 trim_scale((l ->> 'quantidade')::numeric), trim_scale((l ->> 'preco')::numeric), l ->> 'estado'),
                       '|' order by (l ->> 'ordem')::integer)
       from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) l)));
$$;

comment on function public._retorno_previa_hash(uuid, text, jsonb) is
  'Retorno F3 (P3): a única fórmula do hash da proposta, sobre vessel_id, título e as linhas em ordem. 2 e 2.000 dão o mesmo hash.';

revoke all on function public._retorno_previa_hash(uuid, text, jsonb) from public, anon, authenticated;

create or replace function public._retorno_previa_linhas_json(p_previa uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('ordem', l.ordem, 'product_id', l.product_id, 'service_id', l.service_id, 'nome', l.nome,
                                               'quantidade', l.quantidade, 'preco', l.preco, 'estado', l.estado) order by l.ordem), '[]'::jsonb)
    from public.retorno_previa_linhas l
   where l.previa_id = p_previa;
$$;

comment on function public._retorno_previa_linhas_json(uuid) is
  'Retorno F3 (P3): as linhas gravadas no formato do _retorno_previa_hash.';

revoke all on function public._retorno_previa_linhas_json(uuid) from public, anon, authenticated;

create or replace function public._retorno_previa_hash_efetivo(p_previa uuid, p_agora timestamptz)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_p public.retorno_previa;
  v_cliente uuid;
  v_vessel uuid;
begin
  select * into v_p from public.retorno_previa p where p.id = p_previa;
  if not found then
    return null;
  end if;
  -- O mesmo cliente que o cartão usa: em número novo, a proposta nasce sem client_id, e a rodada só grava depois.
  v_cliente := coalesce(v_p.client_id, (public._retorno_cadastro_do_caso(v_p.abertura_id) ->> 'client_id')::uuid);
  v_vessel := coalesce(v_p.vessel_id, (public._retorno_unidade_do_caso(v_p.abertura_id, v_cliente, p_agora) ->> 'vessel_id')::uuid);
  return public._retorno_previa_hash(v_vessel, v_p.titulo, public._retorno_previa_linhas_json(p_previa));
end;
$$;

comment on function public._retorno_previa_hash_efetivo(uuid, timestamptz) is
  'Retorno F3 (P3): o hash que o dono vê: com vessel_id nulo e unidade já definida, usa a unidade. Assim a rodada gravar o vessel_id não muda o que o dono aprovou.';

revoke all on function public._retorno_previa_hash_efetivo(uuid, timestamptz) from public, anon, authenticated;

-- ── 4. Montar ───────────────────────────────────────────────────────────────────────────────────────

create or replace function public.retorno_previa_montar(p_abertura uuid, p_agora timestamptz default now(), p_fonte uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_ab public.retorno_aberturas;
  v_int text;
  v_cad jsonb;
  v_cliente uuid;
  v_familias text[];
  v_un jsonb;
  v_vessel uuid;
  v_unidades jsonb;
  v_classe text;
  v_bem text;
  v_n_classes integer;
  v_alguma_nula boolean;
  v_par record;
  v_fonte_client uuid;
  v_fonte_vessel uuid;
  r record;
  v_ordem integer := 0;
  v_nome text;
  v_limpo text;
  v_p jsonb;
  v_preco numeric;
  v_fonte_preco text;
  v_em date;
  v_estado_linha text;
  v_motivo text;
  v_linhas jsonb := '[]'::jsonb;
  v_iniciais jsonb := '[]'::jsonb;
  v_total numeric(14,2) := 0;
  v_prov integer := 0;
  v_antigo date;
  v_titulo text;
  v_hash text;
  v_estado_vivo text;
  v_viva public.retorno_previa;
  v_alternativas jsonb;
  v_id uuid;
begin
  -- 1. A chave geral e a trava do caso. p_fonte só vale em 'ligado'.
  if v_cfg.previa_modo = 'desligado' or (p_fonte is not null and v_cfg.previa_modo <> 'ligado') then
    return jsonb_build_object('acao', 'nada', 'motivo', 'desligado');
  end if;
  perform pg_advisory_xact_lock(hashtext('retorno:previa:' || p_abertura));

  -- 2. Caso vivo, papel, áudio, visita.
  select * into v_ab from public.retorno_aberturas a where a.id = p_abertura;
  if not found or v_ab.estado not in ('aberta', 'vencida') or v_ab.cumprida_em is not null then
    return jsonb_build_object('acao', 'nada', 'motivo', 'caso_fechado');
  end if;
  if v_ab.papel not in ('cliente', 'numero_novo') then
    return jsonb_build_object('acao', 'nada', 'motivo', 'papel');
  end if;
  if exists (select 1 from public.retorno_mensagens m
              where m.abertura_id = p_abertura and m.audio_pendente and m.recebida_em <= v_agora) then
    return jsonb_build_object('acao', 'nada', 'motivo', 'aguarda_transcricao');
  end if;
  if v_ab.visita_a_combinar_em is not null
     or exists (select 1 from public.retorno_previa p where p.abertura_id = p_abertura and p.estado = 'ver_no_local') then
    return jsonb_build_object('acao', 'nada', 'motivo', 'visita_a_combinar');
  end if;

  -- 3. Intenção.
  v_int := public._retorno_intencao_do_caso(p_abertura, v_agora);
  if v_int is null or v_int not in ('orcamento', 'adicional') then
    return jsonb_build_object('acao', 'nada', 'motivo', 'intencao');
  end if;

  -- 4. Cadastro.
  v_cad := public._retorno_cadastro_do_caso(p_abertura);
  v_cliente := (v_cad ->> 'client_id')::uuid;
  if v_cliente is not null and exists (select 1 from public.clients c where c.id = v_cliente and c.generico) then
    return jsonb_build_object('acao', 'nada', 'motivo', 'cliente_final');
  end if;
  if v_cliente is null and v_ab.papel = 'cliente' then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_cliente');
  end if;

  -- 5. Rascunho do caso: o cartão oferece o PDF dele.
  if public._retorno_rascunho_do_caso(p_abertura, v_agora) is not null then
    return jsonb_build_object('acao', 'nada', 'motivo', 'ja_tem_orcamento');
  end if;

  -- 6. Famílias do caso: as mensagens que pedem resposta e o que o número novo disse (servico e detalhes da coleta).
  select public._retorno_familias(public._retorno_busca(
           coalesce(string_agg(w.body, ' '), '') || ' ' || coalesce(v_ab.coleta ->> 'servico', '') || ' ' || coalesce(v_ab.coleta ->> 'detalhes', '')))
    into v_familias
    from public.retorno_mensagens m
    join public.whatsapp_messages w on w.id = m.whatsapp_message_id
   where m.abertura_id = p_abertura and m.pede_resposta and m.recebida_em <= v_agora;
  if v_familias is null or cardinality(v_familias) = 0 then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_familia');
  end if;

  -- 7. Classe e unidade.
  v_un := public._retorno_unidade_do_caso(p_abertura, v_cliente, v_agora);
  v_vessel := (v_un ->> 'vessel_id')::uuid;
  v_unidades := '[]'::jsonb;
  if v_vessel is not null then
    select public._retorno_classe_do_bem(v.asset_type) into v_classe from public.vessels v where v.id = v_vessel;
  elsif jsonb_array_length(coalesce(v_un -> 'unidades', '[]'::jsonb)) > 0 then
    v_unidades := v_un -> 'unidades';
    select count(distinct public._retorno_classe_do_bem(v.asset_type)),
           bool_or(public._retorno_classe_do_bem(v.asset_type) is null),
           min(public._retorno_classe_do_bem(v.asset_type))
      into v_n_classes, v_alguma_nula, v_classe
      from jsonb_array_elements(v_unidades) u
      join public.vessels v on v.id = (u ->> 'vessel_id')::uuid;
    if coalesce(v_alguma_nula, true) or v_n_classes <> 1 then
      return jsonb_build_object('acao', 'nada', 'motivo', 'unidades_mistas');
    end if;
  else
    -- 0 unidades: a classe sai do que o cliente disse. Sem unidade no cadastro, nunca se cria unidade aqui.
    select s.palavra into v_bem
      from (select public._retorno_sinais(w.body) ->> 'bem_palavra' as palavra, m.recebida_em, m.whatsapp_message_id
              from public.retorno_mensagens m
              join public.whatsapp_messages w on w.id = m.whatsapp_message_id
             where m.abertura_id = p_abertura and m.recebida_em <= v_agora) s
     where s.palavra is not null
     order by s.recebida_em desc, s.whatsapp_message_id
     limit 1;
    v_classe := public._retorno_classe_do_bem(coalesce(v_bem, v_ab.coleta ->> 'tipo'));
  end if;
  if v_classe is null then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_classe');
  end if;

  -- 8. O parecido. O que nasceu depois da abertura do caso não serve.
  if p_fonte is null then
    select * into v_par
      from public.retorno_parecidos(v_familias, v_classe, v_cliente, v_vessel, v_ab.aberta_em, v_agora, 2)
     limit 1;
  else
    select * into v_par
      from public.retorno_parecidos(v_familias, v_classe, v_cliente, v_vessel, v_ab.aberta_em, v_agora, 20) p
     where p.os_id = p_fonte;
  end if;
  if not found then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_parecido');
  end if;
  select so.client_id, so.vessel_id into v_fonte_client, v_fonte_vessel from public.service_orders so where so.id = v_par.os_id;

  -- 9 e 10. As linhas em memória: peças antes, depois serviços; dentro do grupo por created_at e id da fonte.
  for r in
    select x.* from (
      select 1 as grupo, p.created_at as momento, p.id as linha_id, 'peca'::text as tipo, p.product_id, null::uuid as service_id,
             pr.name::text as nome_cat, pr.active as ativo, p.quantity as qtd, null::text as nome_fonte
        from public.service_order_parts p
        join public.products pr on pr.id = p.product_id
       where p.service_order_id = v_par.os_id
      union all
      select 2, s.created_at, s.id, 'servico', null::uuid, s.service_id, sv.name, coalesce(sv.active, true), s.quantity, s.name_snapshot
        from public.service_order_services s
        left join public.services sv on sv.id = s.service_id
       where s.service_order_id = v_par.os_id
    ) x
    order by x.grupo, x.momento nulls last, x.linha_id
  loop
    if r.qtd is null or r.qtd <= 0 then
      continue;   -- retorno_previa_linhas exige quantidade > 0: linha sem quantidade não entra
    end if;
    v_ordem := v_ordem + 1;
    v_estado_linha := 'ok';
    v_motivo := null;
    v_preco := null;
    v_fonte_preco := 'sem_preco';
    v_em := null;
    v_p := null;

    if r.tipo = 'peca' then
      v_nome := left(r.nome_cat, 200);
      if not r.ativo then
        v_estado_linha := 'provisorio';
        v_motivo := 'inativo';
      else
        v_p := public._retorno_preco_da_peca(r.product_id, v_cliente, v_agora);
      end if;
    elsif r.service_id is not null then
      -- O nome de catálogo pode ter nascido de uma mão de obra ditada (ai_servico_pendente_catalogo): passa pela mesma limpeza da linha livre.
      if public._retorno_nome_limpo(r.nome_cat, v_fonte_client, v_fonte_vessel) is null then
        v_nome := 'Serviço a descrever';
        v_estado_linha := 'provisorio';
        v_motivo := 'nome_com_dado_de_outro';
      else
        v_nome := left(r.nome_cat, 200);
        if not r.ativo then
          v_estado_linha := 'provisorio';
          v_motivo := 'inativo';
        else
          v_p := public._retorno_preco_do_servico(r.service_id, r.nome_cat, v_cliente, v_agora);
        end if;
      end if;
    else
      v_limpo := public._retorno_nome_limpo(r.nome_fonte, v_fonte_client, v_fonte_vessel);
      if v_limpo is null then
        v_nome := 'Serviço a descrever';
        v_estado_linha := 'provisorio';
        v_motivo := 'nome_com_dado_de_outro';
      else
        v_nome := left(v_limpo, 200);
        v_p := public._retorno_preco_do_servico(null, v_limpo, v_cliente, v_agora);
      end if;
    end if;

    if v_p is not null then
      v_preco := (v_p ->> 'preco')::numeric;
      v_fonte_preco := v_p ->> 'fonte';
      v_em := (v_p ->> 'em')::date;
      if v_preco is null or v_fonte_preco = 'sem_preco' then
        v_preco := null;
        v_fonte_preco := 'sem_preco';
        v_em := null;
        v_estado_linha := 'provisorio';
        v_motivo := 'sem_preco';
      end if;
    end if;

    if v_preco is not null then
      v_total := v_total + round(r.qtd * v_preco, 2);
    end if;
    if v_estado_linha = 'provisorio' then
      v_prov := v_prov + 1;
    end if;
    v_antigo := case when v_em is not null then least(coalesce(v_antigo, v_em), v_em) else v_antigo end;

    v_linhas := v_linhas || jsonb_build_array(jsonb_build_object(
      'ordem', v_ordem, 'tipo', r.tipo, 'product_id', r.product_id, 'service_id', r.service_id, 'nome', v_nome,
      'quantidade', r.qtd, 'preco', v_preco, 'preco_fonte', v_fonte_preco, 'preco_em', v_em, 'estado', v_estado_linha, 'motivo', v_motivo));
    v_iniciais := v_iniciais || jsonb_build_array(jsonb_build_object(
      'tipo', r.tipo, 'product_id', r.product_id, 'service_id', r.service_id, 'nome', v_nome, 'quantidade', r.qtd, 'preco', v_preco));
  end loop;

  if v_ordem = 0 then
    return jsonb_build_object('acao', 'nada', 'motivo', 'sem_parecido');
  end if;

  v_titulo := public._retorno_familia_rotulo(v_familias) ->> 'titulo';
  v_hash := public._retorno_previa_hash(v_vessel, v_titulo, v_linhas);

  -- 11. A viva do estado que este modo governa.
  v_estado_vivo := case when v_cfg.previa_modo = 'sombra' then 'sombra' else 'proposta' end;
  select * into v_viva from public.retorno_previa p where p.abertura_id = p_abertura and p.estado = v_estado_vivo for update;
  if found then
    -- O cliente que apareceu entra sem mexer no hash: a comparação da P11 procura o ORÇ pelo cliente.
    if v_viva.client_id is null and v_cliente is not null then
      update public.retorno_previa p set client_id = v_cliente where p.id = v_viva.id;
    end if;
    if p_fonte is null and v_viva.vessel_id is null and v_vessel is not null then
      update public.retorno_previa p
         set vessel_id = v_vessel,
             hash = public._retorno_previa_hash(v_vessel, v_viva.titulo, public._retorno_previa_linhas_json(v_viva.id)),
             atualizada_em = v_agora
       where p.id = v_viva.id;
      return jsonb_build_object('acao', 'mantida', 'previa_id', v_viva.id);
    end if;
    if p_fonte is null and coalesce((v_viva.dados ->> 'travada')::boolean, false) then
      update public.retorno_previa p set atualizada_em = v_agora where p.id = v_viva.id;
      return jsonb_build_object('acao', 'mantida', 'previa_id', v_viva.id);
    end if;
    if v_viva.hash = v_hash then
      update public.retorno_previa p set atualizada_em = v_agora where p.id = v_viva.id;
      return jsonb_build_object('acao', 'mantida', 'previa_id', v_viva.id);
    end if;
    update public.retorno_previa p set estado = 'descartada', atualizada_em = v_agora where p.id = v_viva.id;
  end if;

  -- 12. Nova proposta. As alternativas são os outros parecidos: depois de *B*, volta o original.
  select coalesce(jsonb_agg(jsonb_build_object('os_id', x.os_id, 'numero', x.numero, 'em', x.criada_em) order by x.ord), '[]'::jsonb)
    into v_alternativas
    from public.retorno_parecidos(v_familias, v_classe, v_cliente, v_vessel, v_ab.aberta_em, v_agora, 2)
         with ordinality as x(os_id, numero, criada_em, mesma_unidade, mesmo_cliente, familia_igual, aprovado, linhas_n, ord)
   where x.os_id <> v_par.os_id;

  insert into public.retorno_previa (abertura_id, chave, client_id, vessel_id, origem, fonte_os_id, fonte_numero, fonte_em, familias, titulo,
                                     estado, modo, total, linhas_n, provisorios_n, preco_mais_antigo, linhas_iniciais, hash, dados, criada_em, atualizada_em)
  values (p_abertura, v_ab.chave, v_cliente, v_vessel, 'historico', v_par.os_id, v_par.numero, v_par.criada_em, v_familias, v_titulo,
          v_estado_vivo, v_cfg.previa_modo, v_total, v_ordem, v_prov, v_antigo, v_iniciais, v_hash,
          jsonb_build_object('alternativas', v_alternativas, 'unidades', v_unidades, 'motivo', v_un ->> 'motivo',
                             'forte', v_par.mesmo_cliente and v_par.familia_igual, 'fonte_aprovada', v_par.aprovado,
                             'travada', p_fonte is not null),
          v_agora, v_agora)
  returning id into v_id;

  insert into public.retorno_previa_linhas (previa_id, ordem, tipo, product_id, service_id, nome, quantidade, preco, preco_fonte, preco_em, estado, motivo)
  select v_id, (l ->> 'ordem')::smallint, l ->> 'tipo', (l ->> 'product_id')::uuid, (l ->> 'service_id')::uuid, l ->> 'nome',
         (l ->> 'quantidade')::numeric, (l ->> 'preco')::numeric, l ->> 'preco_fonte', (l ->> 'preco_em')::date, l ->> 'estado', l ->> 'motivo'
    from jsonb_array_elements(v_linhas) l;

  return jsonb_build_object('acao', 'criada', 'previa_id', v_id);
end;
$$;

comment on function public.retorno_previa_montar(uuid, timestamptz, uuid) is
  'Retorno F3 (P3, C-MONTAR): monta a proposta do caso a partir do orçamento parecido. {acao: criada, mantida ou nada, previa_id?, motivo?}. p_fonte força o parecido (letra B) e só vale em ligado. Nunca cria OS nem cadastro.';

revoke all on function public.retorno_previa_montar(uuid, timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.retorno_previa_montar(uuid, timestamptz, uuid) to service_role;

create or replace function public.retorno_previa_rodada(p_agora timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_estado text;
  r record;
  v_res jsonb;
  v_casos integer := 0;
  v_criadas integer := 0;
  v_mantidas integer := 0;
  v_erros integer := 0;
begin
  if v_cfg.previa_modo = 'desligado' then
    return jsonb_build_object('casos', 0, 'criadas', 0, 'mantidas', 0, 'erros', 0);
  end if;
  v_estado := case when v_cfg.previa_modo = 'sombra' then 'sombra' else 'proposta' end;

  for r in
    select a.id
      from public.retorno_aberturas a
     where a.estado in ('aberta', 'vencida')
       and a.cumprida_em is null
       and a.papel in ('cliente', 'numero_novo')
       and a.visita_a_combinar_em is null
       and not exists (select 1 from public.retorno_previa v where v.abertura_id = a.id and v.estado = 'ver_no_local')
       and (not exists (select 1 from public.retorno_previa v where v.abertura_id = a.id and v.estado = v_estado)
            or exists (select 1 from public.retorno_previa v where v.abertura_id = a.id and v.estado = v_estado
                        and (v.atualizada_em < a.ultima_em or v.vessel_id is null)))
     order by a.ultima_em desc, a.id
     limit 20
  loop
    v_casos := v_casos + 1;
    begin
      v_res := public.retorno_previa_montar(r.id, v_agora);
      if v_res ->> 'acao' = 'criada' then
        v_criadas := v_criadas + 1;
      elsif v_res ->> 'acao' = 'mantida' then
        v_mantidas := v_mantidas + 1;
      end if;
    exception when others then
      v_erros := v_erros + 1;
      perform public._retorno_log('previa_rodada', 'retorno_previa_rodada: ' || sqlerrm, 'error', jsonb_build_object('abertura_id', r.id));
    end;
  end loop;

  -- As vivas de caso que fechou saem de cena.
  update public.retorno_previa p
     set estado = 'descartada', atualizada_em = v_agora
    from public.retorno_aberturas a
   where a.id = p.abertura_id and a.estado = 'fechada' and p.estado in ('sombra', 'proposta');

  return jsonb_build_object('casos', v_casos, 'criadas', v_criadas, 'mantidas', v_mantidas, 'erros', v_erros);
end;
$$;

comment on function public.retorno_previa_rodada(timestamptz) is
  'Retorno F3 (P3, C-RODADA): até 20 casos vivos sem proposta do estado do modo, com mensagem nova ou com proposta sem unidade. Erro num caso vira log e o próximo segue. Fecha as propostas vivas de caso fechado. Nunca passa p_fonte.';

revoke all on function public.retorno_previa_rodada(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_previa_rodada(timestamptz) to service_role;
