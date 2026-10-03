-- Orçamento técnico com IA (03/10/2026): o admin descreve o serviço em texto livre, o banco monta o
-- pacote de dados (catálogo inteiro + histórico + regras de preço), um job vai para a fila ai_jobs
-- (HBR AI Gateway, Claude pela assinatura do dono) e a proposta volta como JSON validado por schema.
-- Virar orçamento de verdade é outro passo, por clique do admin (ai_orcamento_tecnico_criar_rascunho).
--
-- Testado antes com o pedido real de 22/07 (2 orçamentos LiFePO4): contas fechadas, nenhum custo fora
-- dos dados, provisórios marcados. O teste usava um filtro por palavra-chave; aqui vai o catálogo inteiro
-- (525 produtos ≈ 94 kB compactos), porque cada pedido fala de uma coisa e o filtro errava fácil.

-- ---------------------------------------------------------------------------------------------
-- Pacote de dados: o que o assistente buscaria com dezenas de chamadas de ferramenta.
-- ---------------------------------------------------------------------------------------------
create or replace function public.ai_orcamento_tecnico_pacote()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with produtos as (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'produto_id', p.id, 'nome', p.name, 'sku', p.sku, 'marca', p.brand,
      'categoria', coalesce(pc.name, p.category), 'unidade', p.unit,
      'custo_cadastro', nullif(p.cost_price, 0), 'venda_cadastro', nullif(p.sale_price, 0),
      'cadastro_atualizado_em', to_char(p.updated_at, 'YYYY-MM-DD'),
      'fornecedor', s.name,
      'ultimo_custo_nf', (select jsonb_build_object('valor', h.new_cost, 'data', to_char(h.created_at, 'YYYY-MM-DD'))
                            from public.product_price_history h
                           where h.product_id = p.id and h.new_cost > 0 order by h.created_at desc limit 1),
      'ultima_compra_oc', (select jsonb_build_object('valor', i.unit_cost, 'data', to_char(i.created_at, 'YYYY-MM-DD'))
                             from public.purchase_order_items i
                            where i.product_id = p.id and i.unit_cost > 0 order by i.created_at desc limit 1),
      'ultimo_orcamento', (select jsonb_strip_nulls(jsonb_build_object('numero', so.service_order_number,
                                    'custo', nullif(sp.unit_cost_snapshot, 0), 'venda', nullif(sp.unit_sale_snapshot, 0),
                                    'data', to_char(sp.created_at, 'YYYY-MM-DD')))
                             from public.service_order_parts sp
                             join public.service_orders so on so.id = sp.service_order_id
                            where sp.product_id = p.id order by sp.created_at desc limit 1)
    )) order by p.name) as v
      from public.products p
      left join public.suppliers s on s.id = p.supplier_id
      left join public.product_categories pc on pc.id = p.product_category_id
     where p.active
  ),
  servicos as (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'servico_id', sv.id, 'nome', sv.name, 'descricao', nullif(left(sv.description, 140), ''),
      'categoria', sv.category, 'unidade_cobranca', sv.billing_unit,
      'preco_padrao', nullif(sv.default_price, 0), 'minutos_padrao', sv.standard_minutes
    )) order by sv.name) as v
      from public.services sv
     where sv.active
  ),
  recentes as (
    select so.* from public.service_orders so
     where exists (select 1 from public.service_order_parts sp where sp.service_order_id = so.id)
     order by so.created_at desc limit 12
  ),
  orcamentos as (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'numero', so.service_order_number, 'data', to_char(so.created_at, 'YYYY-MM-DD'),
      'status', coalesce(so.quote_status, so.status), 'total_geral', so.grand_total,
      'descricao', nullif(left(so.problem_description, 200), ''),
      'pecas', (select jsonb_agg(jsonb_build_object('item', p.name, 'qtd', sp.quantity,
                                                    'custo_unit', sp.unit_cost_snapshot, 'venda_unit', sp.unit_sale_snapshot)
                                 order by sp.created_at)
                  from public.service_order_parts sp join public.products p on p.id = sp.product_id
                 where sp.service_order_id = so.id),
      'servicos', (select jsonb_agg(jsonb_build_object('servico', ss.name_snapshot, 'qtd', ss.quantity,
                                                       'unidade', ss.billing_unit_snapshot, 'preco_unit', ss.unit_price_snapshot)
                                    order by ss.created_at)
                     from public.service_order_services ss where ss.service_order_id = so.id)
    )) order by so.created_at desc) as v
      from recentes so
  ),
  margem as (
    select jsonb_build_object(
      'markup_mediano', round((percentile_cont(0.5) within group (order by sp.unit_sale_snapshot / sp.unit_cost_snapshot))::numeric, 3),
      'markup_p25', round((percentile_cont(0.25) within group (order by sp.unit_sale_snapshot / sp.unit_cost_snapshot))::numeric, 3),
      'markup_p75', round((percentile_cont(0.75) within group (order by sp.unit_sale_snapshot / sp.unit_cost_snapshot))::numeric, 3),
      'linhas_consideradas', count(*),
      'periodo', 'orçamentos e OS dos últimos 12 meses'
    ) as v
      from public.service_order_parts sp
     where sp.unit_cost_snapshot > 0 and sp.unit_sale_snapshot > 0
       and sp.created_at > now() - interval '12 months'
  )
  select jsonb_build_object(
    'data_de_referencia', to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'),
    'configuracoes_de_preco', (select jsonb_object_agg(key, value) from public.app_settings
                                where key in ('default_profit_margin', 'default_hourly_rate', 'simples_aliquota', 'default_commission_rate')),
    'margem_praticada', (select v from margem),
    'margem_por_categoria', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                                'categoria', c.name, 'margem_pct', c.default_profit_margin,
                                'comissao_pct', c.default_commission_rate, 'comissionavel', c.is_commissionable)) order by c.name)
                               from public.product_categories c where c.active),
    'produtos', coalesce((select v from produtos), '[]'::jsonb),
    'servicos', coalesce((select v from servicos), '[]'::jsonb),
    'orcamentos_recentes', coalesce((select v from orcamentos), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------------------------------
-- Pedido: só o admin (ai_job_submit confere de novo). Regras e schema ficam AQUI, não no app.
-- ---------------------------------------------------------------------------------------------
create or replace function public.ai_orcamento_tecnico_solicitar(p_pedido text, p_modelo text default 'opus')
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_admin(v_uid) then
    raise exception 'Só o administrador pode pedir orçamento técnico com IA' using errcode = '42501';
  end if;
  if p_pedido is null or char_length(btrim(p_pedido)) < 15 then
    raise exception 'Descreva o serviço com mais detalhes (mínimo de 15 caracteres)' using errcode = '22023';
  end if;
  if coalesce(p_modelo, 'opus') not in ('haiku', 'sonnet', 'opus') then
    raise exception 'Modelo inválido: use sonnet ou opus' using errcode = '22023';
  end if;

  return public.ai_job_submit(
    p_prompt => btrim(p_pedido),
    p_model => coalesce(p_modelo, 'opus'),
    p_system_prompt =>
      'Você é o orçamentista técnico sênior da HBR Systems (sistemas elétricos e eletrônicos de embarcações e motorhomes). '
      || 'Monte o(s) orçamento(s) pedido(s) usando o pacote <dados_de_entrada> (catálogo de produtos e serviços, histórico de custos, orçamentos recentes e regras de preço). Regras inegociáveis: '
      || '(1) use SOMENTE valores presentes nos dados; em cada item cite a origem exata (cadastro, NF, ordem de compra ou número do orçamento) e a data. '
      || '(2) Item do catálogo leva o produto_id ou servico_id EXATAMENTE como está nos dados; item que não está no catálogo leva id null e provisorio=true. '
      || '(3) Custo ou venda ausente não é zero: sem valor exato, use o item mais semelhante, estime com coerência e marque provisorio=true com a observação "Valor provisório — aguardando cotação do fornecedor". '
      || '(4) Siga exatamente o que o pedido incluir ou excluir; não misture itens nem valores entre orçamentos diferentes. '
      || '(5) As contas precisam fechar: total_venda = quantidade × preco_venda_unitario, e o resumo soma os itens. O preco_venda_unitario é o preço FINAL da linha: o sistema não soma imposto nem comissão por cima. '
      || '(6) Margem: se o pedido não definir, use a margem praticada (markup_mediano) e explique; se o preço de venda do cadastro for bem menor que o resultado, aponte isso em perguntas_pendentes. '
      || '(7) Dimensione com critério técnico (bitolas, proteções, normas) e registre as premissas. '
      || '(8) O que faltar para fechar o orçamento vai em perguntas_pendentes — nunca invente. Responda em português do Brasil.',
    p_input => public.ai_orcamento_tecnico_pacote(),
    p_response_format => 'json_schema',
    p_json_schema => jsonb_build_object(
      'type', 'object', 'additionalProperties', false,
      'required', jsonb_build_array('premissas_tecnicas', 'margem_adotada', 'orcamentos', 'perguntas_pendentes'),
      'properties', jsonb_build_object(
        'premissas_tecnicas', jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string')),
        'margem_adotada', jsonb_build_object('type', 'object', 'additionalProperties', false,
          'required', jsonb_build_array('criterio', 'markup'),
          'properties', jsonb_build_object('criterio', jsonb_build_object('type', 'string'), 'markup', jsonb_build_object('type', 'number'))),
        'perguntas_pendentes', jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string')),
        'orcamentos', jsonb_build_object('type', 'array', 'minItems', 1, 'maxItems', 4, 'items', jsonb_build_object(
          'type', 'object', 'additionalProperties', false,
          'required', jsonb_build_array('titulo', 'itens', 'resumo', 'observacoes_valores_provisorios'),
          'properties', jsonb_build_object(
            'titulo', jsonb_build_object('type', 'string'),
            'observacoes_valores_provisorios', jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string')),
            'resumo', jsonb_build_object('type', 'object', 'additionalProperties', false,
              'required', jsonb_build_array('custo_estimado', 'margem_aplicada_pct', 'total_materiais_e_equipamentos', 'total_mao_de_obra', 'total_geral'),
              'properties', jsonb_build_object(
                'custo_estimado', jsonb_build_object('type', 'number'),
                'margem_aplicada_pct', jsonb_build_object('type', 'number'),
                'total_materiais_e_equipamentos', jsonb_build_object('type', 'number'),
                'total_mao_de_obra', jsonb_build_object('type', 'number'),
                'total_geral', jsonb_build_object('type', 'number'))),
            'itens', jsonb_build_object('type', 'array', 'items', jsonb_build_object(
              'type', 'object', 'additionalProperties', false,
              'required', jsonb_build_array('tipo', 'descricao', 'produto_id', 'servico_id', 'quantidade', 'unidade',
                                            'custo_unitario', 'origem_do_custo', 'data_do_custo', 'provisorio',
                                            'preco_venda_unitario', 'total_venda'),
              'properties', jsonb_build_object(
                'tipo', jsonb_build_object('type', 'string', 'enum', jsonb_build_array('equipamento', 'material', 'mao_de_obra')),
                'descricao', jsonb_build_object('type', 'string'),
                'produto_id', jsonb_build_object('type', jsonb_build_array('string', 'null')),
                'servico_id', jsonb_build_object('type', jsonb_build_array('string', 'null')),
                'quantidade', jsonb_build_object('type', 'number'),
                'unidade', jsonb_build_object('type', 'string'),
                'custo_unitario', jsonb_build_object('type', 'number'),
                'origem_do_custo', jsonb_build_object('type', 'string'),
                'data_do_custo', jsonb_build_object('type', jsonb_build_array('string', 'null')),
                'provisorio', jsonb_build_object('type', 'boolean'),
                'preco_venda_unitario', jsonb_build_object('type', 'number'),
                'total_venda', jsonb_build_object('type', 'number'))))))))),
    p_timeout_seconds => 900,
    p_max_attempts => 2,
    p_metadata => jsonb_build_object('tipo', 'orcamento_tecnico', 'versao', 1)
  );
end $$;

-- ---------------------------------------------------------------------------------------------
-- Proposta → rascunho de orçamento (ORÇ, status draft), por clique do admin.
-- "IA pensa, sistema preenche": a IA deu itens, quantidades e preços; número, status, validade,
-- totais e vínculos quem preenche é o banco. O conteúdo vem do ai_jobs (gravado pelo gateway),
-- nunca do navegador.
-- ---------------------------------------------------------------------------------------------

-- Montagem separada da numeração: dá para testar com número fictício numa transação desfeita
-- sem consumir o document_number_seq (buraco na numeração dos ORÇ).
create or replace function public._ai_orcamento_tecnico_montar(
  p_job_id uuid,
  p_indice integer,
  p_client_id uuid,
  p_vessel_id uuid,
  p_numero text,
  p_uid uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  j public.ai_jobs;
  v_orc jsonb;
  v_ja uuid;
  v_so uuid;
  v_validade integer;
  v_notas text;
  it jsonb;
  sv public.services;
  v_qtd numeric;
  v_custo numeric;
  v_venda numeric;
  v_prov boolean;
  v_desc text;
  v_nota text;
  v_prod uuid;
  n_pecas integer := 0;
  n_servicos integer := 0;
  n_pendentes integer := 0;
begin
  select * into j from public.ai_jobs x where x.id = p_job_id for update;
  if not found or j.metadata->>'tipo' is distinct from 'orcamento_tecnico' then
    raise exception 'Pedido de orçamento técnico não encontrado' using errcode = 'P0002';
  end if;
  if j.status <> 'completed' then
    raise exception 'A proposta ainda não está pronta (status %)', j.status using errcode = '22023';
  end if;
  v_orc := j.response->'data'->'orcamentos'->coalesce(p_indice, -1);
  if v_orc is null or jsonb_typeof(v_orc->'itens') is distinct from 'array' then
    raise exception 'O orçamento % não existe nesta proposta', coalesce(p_indice, -1) + 1 using errcode = '22023';
  end if;

  -- O mesmo orçamento da proposta não vira dois rascunhos (duplo clique, aba repetida).
  v_ja := nullif(j.metadata->'rascunhos'->>(p_indice::text), '')::uuid;
  if v_ja is not null and exists (select 1 from public.service_orders so where so.id = v_ja) then
    return jsonb_build_object('service_order_id', v_ja, 'ja_existia', true,
      'numero', (select so.service_order_number from public.service_orders so where so.id = v_ja));
  end if;

  if p_numero is null then
    raise exception 'Número do orçamento ausente' using errcode = '22023';
  end if;
  if not exists (select 1 from public.vessels v where v.id = p_vessel_id and v.client_id = p_client_id) then
    raise exception 'O ativo escolhido não pertence a este cliente' using errcode = '22023';
  end if;

  -- Validade: a configuração da empresa (mesma fonte do formulário e do assistente).
  select case when s.value ~ '^\s*\d{1,3}\s*$' and btrim(s.value)::int between 1 and 365 then btrim(s.value)::int end
    into v_validade from public.app_settings s where s.key = 'quote_validity_days';

  v_notas := left(concat_ws(E'\n',
    'Gerado pelo Orçamento técnico com IA em ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
      || coalesce(' (modelo ' || j.model_used || ')', '') || '. Revise antes de enviar ao cliente.',
    'Pedido: ' || left(j.prompt, 600),
    case when jsonb_array_length(coalesce(v_orc->'observacoes_valores_provisorios', '[]'::jsonb)) > 0 then
      E'\nValores provisórios:\n- ' || (select string_agg(x, E'\n- ') from jsonb_array_elements_text(v_orc->'observacoes_valores_provisorios') x) end,
    case when jsonb_array_length(coalesce(j.response->'data'->'perguntas_pendentes', '[]'::jsonb)) > 0 then
      E'\nPerguntas pendentes:\n- ' || (select string_agg(x, E'\n- ') from jsonb_array_elements_text(j.response->'data'->'perguntas_pendentes') x) end,
    case when jsonb_array_length(coalesce(j.response->'data'->'premissas_tecnicas', '[]'::jsonb)) > 0 then
      E'\nPremissas técnicas:\n- ' || (select string_agg(x, E'\n- ') from jsonb_array_elements_text(j.response->'data'->'premissas_tecnicas') x) end
  ), 12000);

  insert into public.service_orders (
    client_id, vessel_id, service_order_number, status, quote_status,
    problem_description, internal_notes, quote_validity_days, created_by
  ) values (
    p_client_id, p_vessel_id, p_numero, 'draft', 'draft',
    left(coalesce(nullif(btrim(v_orc->>'titulo'), ''), 'Orçamento técnico'), 500), v_notas,
    coalesce(v_validade, 15), p_uid
  )
  returning id into v_so;

  for it in select value from jsonb_array_elements(v_orc->'itens') loop
    v_qtd := greatest(coalesce((it->>'quantidade')::numeric, 1), 0.001);
    v_custo := greatest(coalesce((it->>'custo_unitario')::numeric, 0), 0);
    v_venda := greatest(coalesce((it->>'preco_venda_unitario')::numeric, 0), 0);
    v_prov := coalesce((it->>'provisorio')::boolean, false);
    v_desc := left(coalesce(nullif(btrim(it->>'descricao'), ''), 'Item sem descrição'), 300);
    v_nota := left('IA: ' || coalesce(nullif(it->>'origem_do_custo', ''), 'sem origem informada')
                   || coalesce(' (' || nullif(it->>'data_do_custo', '') || ')', '')
                   || case when v_prov then ' — Valor provisório — aguardando cotação do fornecedor' else '' end, 1000);

    -- O id só vale se existir de fato: o modelo pode errar um uuid.
    v_prod := null;
    sv := null;
    if it->>'produto_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select p.id into v_prod from public.products p where p.id = (it->>'produto_id')::uuid;
    end if;
    if v_prod is null and it->>'servico_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select * into sv from public.services s where s.id = (it->>'servico_id')::uuid;
    end if;

    if v_prod is null and sv.id is null and coalesce(it->>'tipo', '') <> 'mao_de_obra' then
      -- Peça sem cadastro: PRODUTO PENDENTE, como o assistente já faz (item físico mora em Peças).
      -- Reaproveita o de mesmo nome para não encher o catálogo de duplicatas.
      select p.id into v_prod from public.products p
       where p.name ilike replace(replace(replace(v_desc, '\', '\\'), '%', '\%'), '_', '\_')
       limit 1;
      if v_prod is null then
        insert into public.products (name, sale_price, unit, notes)
        values (v_desc, round(v_venda, 2), 'UN',
                'Criado pelo Orçamento técnico com IA. Confirmar preço, unidade e NCM.')
        returning id into v_prod;
        n_pendentes := n_pendentes + 1;
      end if;
      v_nota := left(v_nota || ' — produto cadastrado pelo orçamento: completar o cadastro', 1000);
    end if;

    if v_prod is not null then
      insert into public.service_order_parts (
        service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, currency_snapshot,
        line_total_cost, line_total_sale, notes, source
      ) values (
        v_so, v_prod, v_qtd, round(v_custo, 2), round(v_venda, 2), 'BRL',
        round(v_custo * v_qtd, 2), round(v_venda * v_qtd, 2), v_nota, 'ai'
      );
      n_pecas := n_pecas + 1;
    else
      insert into public.service_order_services (
        service_order_id, service_id, name_snapshot, description_snapshot, billing_unit_snapshot,
        quantity, unit_price_snapshot, line_total, notes
      ) values (
        v_so, sv.id, coalesce(sv.name, v_desc), sv.description,
        coalesce(sv.billing_unit, 'unit'), v_qtd, round(v_venda, 2), round(v_venda * v_qtd, 2), v_nota
      );
      n_servicos := n_servicos + 1;
    end if;
  end loop;

  perform public.recalc_so_totals(v_so);

  update public.ai_jobs x
     set metadata = x.metadata || jsonb_build_object('rascunhos',
           coalesce(x.metadata->'rascunhos', '{}'::jsonb) || jsonb_build_object(p_indice::text, v_so))
   where x.id = p_job_id;

  return jsonb_build_object(
    'service_order_id', v_so, 'numero', p_numero, 'ja_existia', false,
    'pecas', n_pecas, 'servicos', n_servicos, 'produtos_pendentes_criados', n_pendentes,
    'total_geral', (select so.grand_total from public.service_orders so where so.id = v_so));
end $$;

create or replace function public.ai_orcamento_tecnico_criar_rascunho(
  p_job_id uuid,
  p_indice integer,
  p_client_id uuid,
  p_vessel_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_ja uuid;
begin
  if v_uid is null or not public.is_admin(v_uid) then
    raise exception 'Só o administrador pode criar rascunho a partir da IA' using errcode = '42501';
  end if;
  -- Já criado: devolve o existente sem gastar número.
  select nullif(x.metadata->'rascunhos'->>(p_indice::text), '')::uuid into v_ja
    from public.ai_jobs x where x.id = p_job_id;
  if v_ja is not null and exists (select 1 from public.service_orders so where so.id = v_ja) then
    return public._ai_orcamento_tecnico_montar(p_job_id, p_indice, p_client_id, p_vessel_id, null, v_uid);
  end if;
  return public._ai_orcamento_tecnico_montar(
    p_job_id, p_indice, p_client_id, p_vessel_id,
    'ORÇ-' || lpad(public.next_document_number()::text, 5, '0'), v_uid);
end $$;

-- ---------------------------------------------------------------------------------------------
-- Privilégios: só o que o app chama fica aberto a authenticated (e as funções ainda exigem admin).
-- ---------------------------------------------------------------------------------------------
revoke all on function public.ai_orcamento_tecnico_pacote() from public, anon, authenticated;
revoke all on function public.ai_orcamento_tecnico_solicitar(text, text) from public, anon, authenticated;
revoke all on function public._ai_orcamento_tecnico_montar(uuid, integer, uuid, uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.ai_orcamento_tecnico_criar_rascunho(uuid, integer, uuid, uuid) from public, anon, authenticated;
grant execute on function public.ai_orcamento_tecnico_pacote() to service_role;
grant execute on function public._ai_orcamento_tecnico_montar(uuid, integer, uuid, uuid, text, uuid) to service_role;
grant execute on function public.ai_orcamento_tecnico_solicitar(text, text) to authenticated, service_role;
grant execute on function public.ai_orcamento_tecnico_criar_rascunho(uuid, integer, uuid, uuid) to authenticated, service_role;

do $$
begin
  if has_function_privilege('anon', 'public.ai_orcamento_tecnico_solicitar(text, text)', 'execute')
     or has_function_privilege('anon', 'public.ai_orcamento_tecnico_criar_rascunho(uuid, integer, uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.ai_orcamento_tecnico_pacote()', 'execute')
     or has_function_privilege('authenticated', 'public.ai_orcamento_tecnico_pacote()', 'execute')
     or has_function_privilege('authenticated', 'public._ai_orcamento_tecnico_montar(uuid, integer, uuid, uuid, text, uuid)', 'execute') then
    raise exception 'função do orçamento técnico com IA exposta além do previsto';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261003213000', 'orcamento_tecnico_ia')
on conflict do nothing;
