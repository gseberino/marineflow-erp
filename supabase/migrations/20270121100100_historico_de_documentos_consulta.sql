-- Histórico de documentos (F2): CONSULTAR o que mudou, as versões e comparar — já em português.
--
-- Uma função só, public.documento_historico, serve a tela (linha do tempo da OS) e o assistente
-- (consultar_historico_documento). "IA pensa, sistema preenche": quem lê não monta diff nem formata
-- valor; o banco devolve rótulo em português, R$, data de Brasília e nome no lugar de uuid.
--
-- Modos:
--   alteracoes  eventos agrupados (um salvamento = um evento): quem, quando, por onde, o que mudou
--   versoes     os retratos guardados (v1, v2...) com marco, autor e total
--   ver_versao  o documento como estava numa versão
--   comparar    o que mudou entre duas versões (ou entre uma versão e o estado atual)
--
-- Quem lê: admin e financeiro (o mesmo do RLS do audit_log). Pelo service-role (assistente no WhatsApp/Max)
-- a ferramenta já confere o cargo antes de chamar.

-- ─── Rótulos ───────────────────────────────────────────────────────────────────────────────────────
create or replace function private.historico_rotulo(p_tabela text, p_coluna text)
returns text language sql immutable set search_path = public, pg_temp as $$
  select coalesce(
    (select r from (values
      ('status', 'Situação'), ('quote_status', 'Situação do orçamento'), ('invoicing_status', 'Faturamento'),
      ('payment_status', 'Pagamento'), ('priority', 'Prioridade'), ('service_type', 'Tipo de serviço'),
      ('client_id', 'Cliente'), ('vessel_id', 'Embarcação'), ('marina_id', 'Marina'),
      ('problem_description', 'Descrição do problema'), ('initial_findings', 'Constatação inicial'),
      ('diagnosis', 'Diagnóstico'), ('solution_applied', 'Solução aplicada'), ('technician_notes', 'Notas do técnico'),
      ('internal_notes', 'Notas internas'), ('customer_visible_report', 'Relatório ao cliente'), ('extra_notes', 'Observações'),
      ('hourly_rate', 'Valor da hora'), ('estimated_hours', 'Horas estimadas'), ('labor_hours_total', 'Horas totais'),
      ('labor_cost_total', 'Total de mão de obra'), ('parts_cost_total', 'Total de peças'),
      ('travel_distance_km', 'Distância (km)'), ('travel_cost_per_km', 'Valor por km'), ('travel_cost_total', 'Deslocamento'),
      ('travel_hours', 'Horas de deslocamento'), ('ferry_cost', 'Balsa'), ('travel_type', 'Tipo de deslocamento'),
      ('is_travel_billable', 'Cobrar deslocamento'), ('technician_count_for_travel', 'Técnicos no deslocamento'),
      ('subcontract_cost_total', 'Terceirizados'), ('operational_cost_total', 'Custos operacionais'),
      ('discount_amount', 'Desconto'), ('discount_pct', 'Desconto (%)'), ('discount_services_pct', 'Desconto em serviços (%)'),
      ('discount_parts_pct', 'Desconto em peças (%)'), ('tax_amount', 'Impostos'), ('grand_total', 'Total'),
      ('card_fee_amount', 'Taxa do cartão'), ('card_fee_passthrough_enabled', 'Repassar taxa do cartão'),
      ('card_installments', 'Parcelas no cartão'), ('payment_method', 'Forma de pagamento'),
      ('payment_method_preferred', 'Forma de pagamento preferida'), ('payment_conditions', 'Condições de pagamento'),
      ('payment_condition_preset_id', 'Condição de pagamento (modelo)'), ('custom_payment_installments', 'Parcelamento'),
      ('quote_validity_days', 'Validade (dias)'), ('quote_validity_date', 'Validade'),
      ('scheduled_start_at', 'Início agendado'), ('scheduled_end_at', 'Fim agendado'),
      ('check_in_at', 'Chegada'), ('check_out_at', 'Saída'), ('commission_rate', 'Comissão (%)'),
      ('commission_amount', 'Comissão'), ('commissioned_person', 'Comissionado'), ('commissioned_user_id', 'Comissionado'),
      ('customer_po_number', 'Pedido do cliente'), ('customer_buyer_name', 'Comprador do cliente'),
      ('requested_by_name', 'Solicitante'), ('requested_by_contact_id', 'Contato solicitante'),
      ('contingency_pct', 'Contingência (%)'), ('technician_instructions', 'Instruções ao técnico'),
      ('site_access', 'Acesso ao local'), ('signed_at', 'Assinado em'), ('signed_by_name', 'Assinado por'),
      ('requires_resignature', 'Pede nova assinatura'), ('resignature_requested_at', 'Nova assinatura pedida em'),
      ('converted_to_os_at', 'Convertido em OS'), ('cancelled_at', 'Cancelado em'), ('cancellation_reason', 'Motivo do cancelamento'),
      ('reopened_at', 'Reaberto em'), ('reopen_reason', 'Motivo da reabertura'), ('merged_into_id', 'Agrupado em'),
      ('orcamento_enviado_em', 'Enviado em'), ('orcamento_enviado_via', 'Enviado por'),
      ('motivo_perda', 'Motivo da perda'), ('motivo_perda_nota', 'Nota da perda'), ('delivered_at', 'Entregue em'),
      ('client_confirmed_at', 'Cliente confirmou em'), ('service_order_number', 'Número'),
      ('quantity', 'Quantidade'), ('unit_sale_snapshot', 'Preço unitário'), ('unit_cost_snapshot', 'Custo unitário'),
      ('line_total_sale', 'Total do item'), ('line_total_cost', 'Custo do item'), ('product_id', 'Produto'),
      ('serial_number', 'Número de série'), ('notes', 'Observação'), ('warranty_days', 'Garantia (dias)'),
      ('warranty_months', 'Garantia (meses)'), ('service_id', 'Serviço do catálogo'), ('name_snapshot', 'Nome'),
      ('description_snapshot', 'Descrição'), ('billing_unit_snapshot', 'Unidade'), ('unit_price_snapshot', 'Preço unitário'),
      ('line_total', 'Total do item'), ('technician_user_id', 'Técnico'), ('field_status', 'Situação na execução'),
      ('field_status_note', 'Nota da execução'), ('responsavel_payee_id', 'Responsável'), ('started_at', 'Início'),
      ('finished_at', 'Fim'), ('service_system', 'Sistema'), ('service_verb', 'Ação'), ('fiscal_verb', 'Ação na nota'),
      ('description', 'Descrição'), ('amount', 'Valor'), ('paid_amount', 'Valor pago'), ('balance_amount', 'Saldo'),
      ('due_date', 'Vencimento'), ('issue_date', 'Emissão'), ('is_deposit', 'Sinal'), ('category', 'Categoria'),
      ('expense_date', 'Data da despesa'), ('paid_by', 'Pago por'), ('billable_to_client', 'Cobrar do cliente'),
      ('user_id', 'Técnico'), ('role_in_order', 'Papel'), ('title', 'Título'), ('name', 'Nome'), ('sku', 'Código'),
      ('cost_price', 'Custo'), ('sale_price', 'Preço de venda'), ('default_price', 'Preço padrão'), ('active', 'Ativo'),
      ('phone', 'Telefone'), ('whatsapp', 'WhatsApp'), ('email', 'E-mail'), ('cpf_cnpj', 'CPF/CNPJ'),
      ('display_name', 'Nome de exibição'), ('po_number', 'Número do pedido'), ('supplier_id', 'Fornecedor'),
      ('expected_date', 'Previsão'), ('received_date', 'Recebido em'), ('total_amount', 'Total'),
      ('unit_cost', 'Custo unitário'), ('received_qty', 'Quantidade recebida'), ('value', 'Valor'),
      ('accepted_name', 'Nome de quem assinou'), ('superseded_at', 'Substituída em'), ('superseded_reason', 'Motivo da substituição')
    ) as t(c, r) where t.c = p_coluna),
    initcap(replace(p_coluna, '_', ' ')));
$$;

-- Colunas que o sistema calcula (não foram digitadas): a leitura marca como "recalculado".
create or replace function private.historico_calculada(p_coluna text)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_coluna = any (array['grand_total', 'labor_cost_total', 'parts_cost_total', 'labor_hours_total', 'card_fee_amount',
    'operational_cost_total', 'invoicing_status', 'payment_status', 'requires_resignature', 'resignature_requested_at',
    'balance_amount', 'paid_amount', 'commission_amount', 'orcamento_enviado_em', 'motivo_perda_em', 'quote_validity_date']);
$$;

-- Colunas que não se mostram (técnicas).
create or replace function private.historico_oculta(p_coluna text)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_coluna = any (array['id', 'created_at', 'updated_at', 'service_order_id', 'purchase_order_id', 'quote_request_id',
    'external_quote_id', 'share_token', 'created_by', 'origem_chave8', 'orcamento_enviado_chave', 'currency', 'currency_snapshot',
    'source', 'signed_document_hash', 'document_hash', 'client_signature_url', 'signature_image_url', 'signed_pdf_url',
    'ip_address', 'user_agent', 'survey_id', 'linked_payable_id', 'receipt_storage_path', 'receipt_url', 'bank_transaction_id',
    'issued_fiscal_document_id', 'invoice_id', 'cost_center_id', 'ai_operator_draft_id', 'lead_id', 'template_id', 'block_key']);
$$;

-- Igualdade "de formulário": null e "" são o mesmo; número compara por valor.
create or replace function private.historico_igual(p_a jsonb, p_b jsonb)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_a is not distinct from p_b
      or (coalesce(p_a, 'null'::jsonb) in ('null'::jsonb, '""'::jsonb) and coalesce(p_b, 'null'::jsonb) in ('null'::jsonb, '""'::jsonb))
      or (jsonb_typeof(p_a) = 'number' and jsonb_typeof(p_b) in ('number', 'string') and (p_b #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$'
          and (p_a #>> '{}')::numeric = (p_b #>> '{}')::numeric);
$$;

-- Colunas que se restauram (conteúdo). Fora daqui: situação, pagamento, faturamento, assinatura, número, link,
-- cliente, embarcação, datas de agenda e os totais (recalculados). Usada pela consulta (o que é "desfazível") e
-- pela restauração (20270121100200).
create or replace function private.historico_restauraveis(p_tabela text)
returns text[] language sql immutable set search_path = public, pg_temp as $$
  select case p_tabela
    when 'service_orders' then array[
      'problem_description', 'initial_findings', 'diagnosis', 'solution_applied', 'technician_notes', 'internal_notes',
      'customer_visible_report', 'extra_notes', 'hourly_rate', 'estimated_hours', 'travel_distance_km', 'travel_cost_per_km',
      'technician_count_for_travel', 'travel_cost_total', 'travel_hours', 'ferry_cost', 'travel_type', 'is_travel_billable',
      'subcontract_cost_total', 'discount_amount', 'discount_services_pct', 'discount_parts_pct', 'tax_amount',
      'payment_conditions', 'payment_condition_preset_id', 'payment_method', 'payment_method_preferred', 'card_installments',
      'card_fee_passthrough_enabled', 'custom_payment_installments', 'quote_validity_days', 'quote_validity_date',
      'customer_po_number', 'customer_buyer_name', 'requested_by_name', 'contingency_pct', 'technician_instructions',
      'site_access', 'priority', 'service_type', 'commission_rate', 'commissioned_person', 'commissioned_user_id',
      'financial_notes', 'estimate_confidence']
    when 'service_order_parts' then array[
      'product_id', 'quantity', 'unit_cost_snapshot', 'unit_sale_snapshot', 'line_total_cost', 'line_total_sale',
      'discount_pct', 'discount_amount', 'notes', 'serial_number', 'warranty_days', 'warranty_months', 'service_order_service_id']
    when 'service_order_services' then array[
      'service_id', 'name_snapshot', 'description_snapshot', 'billing_unit_snapshot', 'quantity', 'unit_price_snapshot',
      'line_total', 'discount_pct', 'discount_amount', 'notes', 'technician_instructions', 'warranty_days', 'warranty_months',
      'service_system', 'service_verb', 'fiscal_verb', 'technician_user_id', 'responsavel_payee_id']
    else '{}'::text[]
  end;
$$;

-- Uma linha do histórico que dá para desfazer: gravada pelo banco (tem o valor de antes confiável), de cabeçalho,
-- peça ou serviço, e com algo de conteúdo (não só situação, total recalculado ou data de agenda).
create or replace function private.historico_desfazivel(p_l public.audit_log)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_l.pelo_banco
     and p_l.table_name in ('service_orders', 'service_order_parts', 'service_order_services')
     and case p_l.action
           when 'update' then exists (
             select 1 from jsonb_object_keys(coalesce(p_l.new_value, '{}'::jsonb)) k
              where k = any (private.historico_restauraveis(p_l.table_name))
                and coalesce(p_l.previous_value, '{}'::jsonb) ? k)
           when 'insert' then p_l.table_name <> 'service_orders'
           when 'delete' then p_l.table_name <> 'service_orders'
           else false
         end;
$$;

-- Linha antiga (antes do gatilho) que não mudou nada: o formulário gravava a foto inteira a cada salvar.
create or replace function private.historico_linha_vazia(p_l public.audit_log)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_l.action = 'update'
     and not p_l.pelo_banco
     and jsonb_typeof(p_l.new_value) = 'object'
     and not (p_l.new_value ? 'financial_changes')
     and not (p_l.new_value ? 'motivo')
     and not exists (
       select 1 from jsonb_each(p_l.new_value) e
        where e.key not in ('via', 'key', 'id', 'created_at', 'updated_at')
          and (p_l.previous_value is null or not (p_l.previous_value ? e.key)
               or not private.historico_igual(p_l.previous_value -> e.key, e.value)));
$$;

-- Valor legível: R$, %, data de Brasília, Sim/Não, situação em português e nome no lugar de uuid.
create or replace function private.historico_valor(p_coluna text, p_valor jsonb)
returns text language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_txt text;
  v_num numeric;
  v_id  uuid;
  v_nome text;
begin
  if p_valor is null or p_valor = 'null'::jsonb or p_valor = '""'::jsonb then
    return '(vazio)';
  end if;
  if jsonb_typeof(p_valor) = 'boolean' then
    return case when p_valor = 'true'::jsonb then 'Sim' else 'Não' end;
  end if;
  if jsonb_typeof(p_valor) in ('object', 'array') then
    v_txt := p_valor::text;
    return case when length(v_txt) > 200 then left(v_txt, 200) || '…' else v_txt end;
  end if;
  v_txt := p_valor #>> '{}';

  -- dinheiro
  if p_coluna = any (array['grand_total', 'labor_cost_total', 'parts_cost_total', 'travel_cost_total', 'subcontract_cost_total',
       'operational_cost_total', 'discount_amount', 'tax_amount', 'hourly_rate', 'travel_cost_per_km', 'ferry_cost',
       'card_fee_amount', 'commission_amount', 'original_quote_amount', 'unit_cost_snapshot', 'unit_sale_snapshot',
       'line_total_cost', 'line_total_sale', 'unit_price_snapshot', 'line_total', 'amount', 'paid_amount', 'balance_amount',
       'net_amount', 'total_amount', 'unit_cost', 'cost_price', 'sale_price', 'default_price', 'total_value'])
     and v_txt ~ '^-?[0-9]+(\.[0-9]+)?$' then
    v_num := v_txt::numeric;
    return 'R$ ' || translate(to_char(v_num, 'FM999G999G990D00'), ',.', '.,');
  end if;
  -- percentuais
  if (p_coluna like '%\_pct' or p_coluna in ('commission_rate', 'profit_margin', 'card_fee_percent'))
     and v_txt ~ '^-?[0-9]+(\.[0-9]+)?$' then
    return replace(trim(trailing '.' from trim(trailing '0' from v_txt::numeric::text)), '.', ',') || '%';
  end if;
  -- datas
  if v_txt ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}' or v_txt ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}' then
    begin
      return to_char(v_txt::timestamptz at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI');
    exception when others then return v_txt; end;
  end if;
  if v_txt ~ '^\d{4}-\d{2}-\d{2}$' then
    return to_char(v_txt::date, 'DD/MM/YYYY');
  end if;
  -- situações
  if p_coluna in ('status', 'quote_status', 'invoicing_status', 'payment_status', 'field_status') then
    return coalesce((select r from (values
      ('draft', 'Rascunho'), ('open', 'Aberta'), ('scheduled', 'Agendada'), ('in_progress', 'Em andamento'),
      ('awaiting_client', 'Esperando o cliente'), ('awaiting_parts', 'Esperando peças'), ('completed', 'Concluída'),
      ('invoiced', 'Faturada'), ('cancelled', 'Cancelada'), ('sent', 'Enviado'), ('approved', 'Aprovado'),
      ('rejected', 'Recusado/perdido'), ('awaiting_approval', 'Esperando aprovação'), ('awaiting_deposit', 'Esperando sinal'),
      ('not_invoiced', 'Não faturada'), ('unpaid', 'Não pago'), ('paid', 'Pago'), ('partially_paid', 'Pago em parte'),
      ('pending', 'Pendente'), ('a_fazer', 'A fazer'), ('feito', 'Feito'), ('parcial', 'Parcial'), ('nao_feito', 'Não feito')
    ) as t(c, r) where t.c = v_txt), v_txt);
  end if;
  -- uuid -> nome
  if v_txt ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_id := v_txt::uuid;
    v_nome := case
      when p_coluna = 'client_id' then (select name from public.clients where id = v_id)
      when p_coluna = 'vessel_id' then (select name from public.vessels where id = v_id)
      when p_coluna = 'product_id' then (select name from public.products where id = v_id)
      when p_coluna = 'service_id' then (select name from public.services where id = v_id)
      when p_coluna = 'merged_into_id' then (select service_order_number from public.service_orders where id = v_id)
      when p_coluna in ('technician_user_id', 'user_id', 'commissioned_user_id', 'assigned_user_id', 'approved_by')
        then (select full_name from public.app_users where id = v_id)
    end;
    return coalesce(v_nome, '(registro ' || left(v_txt, 8) || ')');
  end if;
  if length(v_txt) > 200 then
    return left(v_txt, 200) || '…';
  end if;
  return v_txt;
end $$;

-- Nome do item (peça, serviço, parcela...) a que uma linha do histórico se refere.
create or replace function private.historico_item(p_tabela text, p_registro uuid, p_antes jsonb, p_depois jsonb)
returns text language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v jsonb := coalesce(p_depois, '{}'::jsonb) || coalesce(p_antes, '{}'::jsonb);
  v_nome text;
  v_prod uuid;
begin
  if p_tabela in ('service_orders', 'purchase_orders', 'quote_requests', 'external_quotes', 'clients', 'vessels',
                  'products', 'services') then
    return 'Documento';
  end if;
  if p_tabela in ('service_order_parts', 'external_quote_parts', 'purchase_order_items', 'quote_request_items') then
    v_prod := nullif(v ->> 'product_id', '')::uuid;
    if v_prod is null and p_tabela = 'service_order_parts' then
      select product_id into v_prod from public.service_order_parts where id = p_registro;
      if v_prod is null then   -- linha já apagada: o produto está no registro de inclusão
        select nullif(l.new_value ->> 'product_id', '')::uuid into v_prod
          from public.audit_log l where l.table_name = p_tabela and l.record_id = p_registro and l.action = 'insert' limit 1;
      end if;
    end if;
    v_nome := coalesce((select name from public.products where id = v_prod), v ->> 'description', v ->> 'name');
    return 'Peça: ' || coalesce(v_nome, 'item');
  end if;
  if p_tabela in ('service_order_services', 'external_quote_services') then
    v_nome := coalesce(v ->> 'name_snapshot', v ->> 'name',
      (select name_snapshot from public.service_order_services where id = p_registro),
      (select l.new_value ->> 'name_snapshot' from public.audit_log l
        where l.table_name = p_tabela and l.record_id = p_registro and l.action = 'insert' limit 1));
    return 'Serviço: ' || coalesce(v_nome, 'item');
  end if;
  return case p_tabela
    when 'service_order_expenses'    then 'Despesa: ' || coalesce(v ->> 'description', (select description from public.service_order_expenses where id = p_registro), 'item')
    when 'service_order_technicians' then 'Técnico: ' || coalesce((select full_name from public.app_users where id = nullif(v ->> 'user_id', '')::uuid), 'técnico')
    when 'service_order_steps'       then 'Etapa: ' || coalesce(v ->> 'title', (select title from public.service_order_steps where id = p_registro), 'etapa')
    when 'service_order_signatures'  then 'Assinatura do cliente'
    when 'service_order_photos'      then 'Foto'
    when 'receivables'               then 'Parcela: ' || coalesce(v ->> 'description', (select description from public.receivables where id = p_registro), 'parcela')
    when 'app_settings'              then 'Configuração: ' || coalesce(v ->> 'key', '?')
    else p_tabela
  end;
end $$;

-- Uma linha do audit_log em português: { item, acao, mudancas: [{campo, antes, depois, calculado}] }.
create or replace function private.historico_linha(p_l public.audit_log)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_mud  jsonb := '[]'::jsonb;
  v_k    text;
  v_a    jsonb;
  v_d    jsonb;
  v_base jsonb;
  v_resumo text[] := array['quantity', 'unit_sale_snapshot', 'line_total_sale', 'unit_price_snapshot', 'line_total',
                           'discount_amount', 'amount', 'due_date', 'name', 'description', 'title', 'value', 'status'];
  v_acao text;
begin
  v_acao := case p_l.action
    when 'insert' then 'incluído' when 'delete' then 'removido' when 'update' then 'alterado'
    when 'versao' then 'versão guardada' when 'restore' then 'restaurado'
    when 'cancel' then 'cancelado' when 'reopen' then 'reaberto' when 'reversal' then 'peça retirada (estorno)'
    when 'cascade_update' then 'ajustado pelo sistema' when 'client_signature' then 'assinado pelo cliente'
    when 'whatsapp_send' then 'enviado pelo WhatsApp' when 'whatsapp_send_api' then 'enviado pelo WhatsApp'
    else replace(p_l.action, '_', ' ') end;

  if p_l.action = 'update' and p_l.previous_value is not null and p_l.new_value ? 'financial_changes' then
    -- formato antigo da tela (campos financeiros {before, after})
    for v_k, v_d in select key, value from jsonb_each(p_l.new_value -> 'financial_changes') loop
      v_mud := v_mud || jsonb_build_object('campo', private.historico_rotulo(p_l.table_name, v_k),
        'antes', private.historico_valor(v_k, v_d -> 'before'), 'depois', private.historico_valor(v_k, v_d -> 'after'),
        'calculado', private.historico_calculada(v_k));
    end loop;
  elsif p_l.action in ('update', 'cascade_update') and jsonb_typeof(p_l.new_value) = 'object' then
    for v_k, v_d in select key, value from jsonb_each(p_l.new_value) loop
      continue when private.historico_oculta(v_k) or v_k in ('via', 'motivo', 'key');
      v_a := p_l.previous_value -> v_k;
      -- linhas antigas (antes do gatilho) gravavam o formulário inteiro: só conta o que mudou de fato
      continue when p_l.previous_value is not null and (p_l.previous_value ? v_k)
        and (v_a is not distinct from v_d
             or (coalesce(v_a, 'null'::jsonb) in ('null'::jsonb, '""'::jsonb) and coalesce(v_d, 'null'::jsonb) in ('null'::jsonb, '""'::jsonb))
             or (jsonb_typeof(v_a) = 'number' and jsonb_typeof(v_d) in ('number', 'string') and v_d #>> '{}' ~ '^-?[0-9.]+$'
                 and (v_a #>> '{}')::numeric = (v_d #>> '{}')::numeric));
      v_mud := v_mud || jsonb_build_object('campo', private.historico_rotulo(p_l.table_name, v_k),
        'antes', case when p_l.previous_value ? v_k then private.historico_valor(v_k, v_a) end,
        'depois', private.historico_valor(v_k, v_d), 'calculado', private.historico_calculada(v_k));
    end loop;
    if p_l.new_value ? 'motivo' then
      v_mud := v_mud || jsonb_build_object('campo', 'Motivo', 'antes', null, 'depois', p_l.new_value ->> 'motivo', 'calculado', false);
    end if;
  elsif p_l.action in ('insert', 'delete', 'reversal') then
    v_base := coalesce(p_l.new_value, p_l.previous_value);
    if p_l.table_name not in ('service_orders', 'purchase_orders', 'quote_requests', 'external_quotes') then
      foreach v_k in array v_resumo loop
        continue when not (v_base ? v_k) or v_base -> v_k in ('null'::jsonb, '""'::jsonb);
        v_mud := v_mud || jsonb_build_object('campo', private.historico_rotulo(p_l.table_name, v_k),
          'antes', case when p_l.action <> 'insert' then private.historico_valor(v_k, v_base -> v_k) end,
          'depois', case when p_l.action = 'insert' then private.historico_valor(v_k, v_base -> v_k) end,
          'calculado', false);
      end loop;
    end if;
  elsif p_l.action like 'whatsapp_send%' then
    v_mud := jsonb_build_array(jsonb_build_object('campo', 'Envio', 'antes', null,
      'depois', concat_ws(' · ', case p_l.new_value ->> 'kind' when 'document' then 'PDF' when 'link' then 'link' else p_l.new_value ->> 'kind' end,
                          case p_l.new_value ->> 'context' when 'quote' then 'orçamento' when 'service_order' then 'OS' else p_l.new_value ->> 'context' end),
      'calculado', false));
  end if;

  return jsonb_build_object(
    'item', case when p_l.action = 'versao' then 'Versão ' || p_l.versao || coalesce(' (' || p_l.reason || ')', '')
                 else private.historico_item(p_l.table_name, p_l.record_id, p_l.previous_value, p_l.new_value) end,
    'acao', v_acao,
    'mudancas', v_mud,
    'motivo', case when p_l.action <> 'versao' then p_l.reason end,
    'desfazivel', private.historico_desfazivel(p_l),
    'registro_id', p_l.id);
end $$;

-- ─── Retrato legível (ver_versao e comparar) ─────────────────────────────────────────────────────
create or replace function private.historico_retrato_legivel(p_ret jsonb)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'numero', p_ret ->> 'numero',
    'situacao', private.historico_valor('status', p_ret -> 'cabecalho' -> 'status'),
    'situacao_do_orcamento', private.historico_valor('quote_status', p_ret -> 'cabecalho' -> 'quote_status'),
    'cliente', p_ret -> 'cliente' ->> 'nome',
    'embarcacao', p_ret -> 'embarcacao' ->> 'nome',
    'descricao', p_ret -> 'cabecalho' ->> 'problem_description',
    'relatorio_ao_cliente', p_ret -> 'cabecalho' ->> 'customer_visible_report',
    'condicoes_de_pagamento', p_ret -> 'cabecalho' ->> 'payment_conditions',
    'validade', private.historico_valor('quote_validity_date', p_ret -> 'cabecalho' -> 'quote_validity_date'),
    'pecas', coalesce((select jsonb_agg(jsonb_build_object(
        'nome', coalesce(p ->> 'produto', 'peça'), 'quantidade', (p ->> 'quantity')::numeric,
        'preco_unitario', private.historico_valor('unit_sale_snapshot', p -> 'unit_sale_snapshot'),
        'desconto', private.historico_valor('discount_amount', p -> 'discount_amount'),
        'total', private.historico_valor('line_total_sale', p -> 'line_total_sale')))
      from jsonb_array_elements(p_ret -> 'pecas') p), '[]'::jsonb),
    'servicos', coalesce((select jsonb_agg(jsonb_build_object(
        'nome', s ->> 'name_snapshot', 'quantidade', (s ->> 'quantity')::numeric,
        'preco_unitario', private.historico_valor('unit_price_snapshot', s -> 'unit_price_snapshot'),
        'desconto', private.historico_valor('discount_amount', s -> 'discount_amount'),
        'total', private.historico_valor('line_total', s -> 'line_total')))
      from jsonb_array_elements(p_ret -> 'servicos') s), '[]'::jsonb),
    'totais', jsonb_build_object(
      'mao_de_obra', private.historico_valor('labor_cost_total', p_ret -> 'cabecalho' -> 'labor_cost_total'),
      'pecas', private.historico_valor('parts_cost_total', p_ret -> 'cabecalho' -> 'parts_cost_total'),
      'deslocamento', private.historico_valor('travel_cost_total', p_ret -> 'cabecalho' -> 'travel_cost_total'),
      'desconto', private.historico_valor('discount_amount', p_ret -> 'cabecalho' -> 'discount_amount'),
      'impostos', private.historico_valor('tax_amount', p_ret -> 'cabecalho' -> 'tax_amount'),
      'total', private.historico_valor('grand_total', p_ret -> 'cabecalho' -> 'grand_total')),
    'parcelas', coalesce((select jsonb_agg(jsonb_build_object(
        'descricao', r ->> 'descricao', 'vencimento', private.historico_valor('due_date', r -> 'vencimento'),
        'valor', private.historico_valor('amount', r -> 'valor'), 'situacao', private.historico_valor('status', r -> 'situacao')))
      from jsonb_array_elements(p_ret -> 'parcelas') r), '[]'::jsonb));
$$;

-- Diferença entre dois retratos: cabeçalho, itens incluídos/removidos/alterados (padrão do Frappe).
create or replace function private.historico_comparar_retratos(p_a jsonb, p_b jsonb)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_cab   jsonb := '[]'::jsonb;
  v_inc   jsonb := '[]'::jsonb;
  v_rem   jsonb := '[]'::jsonb;
  v_alt   jsonb := '[]'::jsonb;
  v_k     text;
  v_lista text;
  v_tab   text;
  v_ia    jsonb;
  v_ib    jsonb;
  v_mud   jsonb;
  v_nome  text;
begin
  for v_k in select key from jsonb_each(coalesce(p_b -> 'cabecalho', '{}'::jsonb)) loop
    continue when private.historico_oculta(v_k) or v_k in ('reminder_sent_at');
    continue when (p_a -> 'cabecalho' -> v_k) is not distinct from (p_b -> 'cabecalho' -> v_k)
      or (coalesce(p_a -> 'cabecalho' -> v_k, 'null'::jsonb) in ('null'::jsonb, '""'::jsonb)
          and coalesce(p_b -> 'cabecalho' -> v_k, 'null'::jsonb) in ('null'::jsonb, '""'::jsonb));
    v_cab := v_cab || jsonb_build_object('campo', private.historico_rotulo('service_orders', v_k),
      'antes', private.historico_valor(v_k, p_a -> 'cabecalho' -> v_k),
      'depois', private.historico_valor(v_k, p_b -> 'cabecalho' -> v_k), 'calculado', private.historico_calculada(v_k));
  end loop;

  foreach v_lista in array array['pecas', 'servicos'] loop
    v_tab := case v_lista when 'pecas' then 'service_order_parts' else 'service_order_services' end;
    for v_ib in select x from jsonb_array_elements(coalesce(p_b -> v_lista, '[]'::jsonb)) x loop
      select y into v_ia from jsonb_array_elements(coalesce(p_a -> v_lista, '[]'::jsonb)) y where y ->> 'id' = v_ib ->> 'id';
      v_nome := case v_lista when 'pecas' then 'Peça: ' || coalesce(v_ib ->> 'produto', 'item') else 'Serviço: ' || coalesce(v_ib ->> 'name_snapshot', 'item') end;
      if v_ia is null then
        v_inc := v_inc || jsonb_build_object('item', v_nome, 'quantidade', v_ib -> 'quantity',
          'total', private.historico_valor('line_total', coalesce(v_ib -> 'line_total_sale', v_ib -> 'line_total')));
      else
        v_mud := '[]'::jsonb;
        for v_k in select key from jsonb_each(v_ib) loop
          continue when private.historico_oculta(v_k) or v_k in ('produto', 'sku', 'elapsed_minutes', 'started_at', 'finished_at');
          continue when (v_ia -> v_k) is not distinct from (v_ib -> v_k)
            or (coalesce(v_ia -> v_k, 'null'::jsonb) in ('null'::jsonb, '""'::jsonb) and coalesce(v_ib -> v_k, 'null'::jsonb) in ('null'::jsonb, '""'::jsonb));
          v_mud := v_mud || jsonb_build_object('campo', private.historico_rotulo(v_tab, v_k),
            'antes', private.historico_valor(v_k, v_ia -> v_k), 'depois', private.historico_valor(v_k, v_ib -> v_k),
            'calculado', private.historico_calculada(v_k));
        end loop;
        if jsonb_array_length(v_mud) > 0 then
          v_alt := v_alt || jsonb_build_object('item', v_nome, 'mudancas', v_mud);
        end if;
      end if;
      v_ia := null;
    end loop;
    for v_ia in select x from jsonb_array_elements(coalesce(p_a -> v_lista, '[]'::jsonb)) x loop
      if not exists (select 1 from jsonb_array_elements(coalesce(p_b -> v_lista, '[]'::jsonb)) y where y ->> 'id' = v_ia ->> 'id') then
        v_rem := v_rem || jsonb_build_object(
          'item', case v_lista when 'pecas' then 'Peça: ' || coalesce(v_ia ->> 'produto', 'item') else 'Serviço: ' || coalesce(v_ia ->> 'name_snapshot', 'item') end,
          'quantidade', v_ia -> 'quantity',
          'total', private.historico_valor('line_total', coalesce(v_ia -> 'line_total_sale', v_ia -> 'line_total')));
      end if;
    end loop;
  end loop;

  return jsonb_build_object('cabecalho', v_cab, 'itens_incluidos', v_inc, 'itens_removidos', v_rem, 'itens_alterados', v_alt,
    'sem_diferenca', jsonb_array_length(v_cab) + jsonb_array_length(v_inc) + jsonb_array_length(v_rem) + jsonb_array_length(v_alt) = 0);
end $$;

-- ─── Quem pode ler ─────────────────────────────────────────────────────────────────────────────────
create or replace function private.historico_pode_ler()
returns boolean language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_papel text;
begin
  if v_uid is not null then
    return public.is_admin_or_financial(v_uid);
  end if;
  begin
    v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
  exception when others then v_papel := 'invalido';
  end;
  return v_papel in ('', 'service_role');   -- service-role (a ferramenta já conferiu o cargo) ou o próprio banco
end $$;

-- Acha o documento pelo tipo e pela referência (uuid, número, código, nome ou chave).
create or replace function private.historico_resolver(p_tipo text, p_ref text,
  out doc_tabela text, out doc_id uuid, out rotulo text, out por_registro boolean)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_tipo text := lower(coalesce(nullif(btrim(p_tipo), ''), 'os'));
  v_ref  text := btrim(coalesce(p_ref, ''));
  v_uuid uuid;
  v_n    integer;
begin
  por_registro := false;
  if v_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_uuid := v_ref::uuid;
  end if;
  doc_tabela := case
    when v_tipo in ('os', 'orcamento', 'orçamento', 'ordem', 'ordem_de_servico', 'service_order', 'service_orders') then 'service_orders'
    when v_tipo in ('compra', 'pedido_de_compra', 'purchase_order', 'purchase_orders') then 'purchase_orders'
    when v_tipo in ('cotacao', 'cotação', 'quote_request', 'quote_requests') then 'quote_requests'
    when v_tipo in ('orcamento_externo', 'external_quote', 'external_quotes') then 'external_quotes'
    when v_tipo in ('cliente', 'clients') then 'clients'
    when v_tipo in ('embarcacao', 'embarcação', 'barco', 'vessels') then 'vessels'
    when v_tipo in ('produto', 'products') then 'products'
    when v_tipo in ('servico', 'serviço', 'services') then 'services'
    when v_tipo in ('configuracao', 'configuração', 'app_settings') then 'app_settings'
  end;
  if doc_tabela is null then
    raise exception 'Tipo de documento desconhecido: %. Use os, compra, cotacao, orcamento_externo, cliente, embarcacao, produto, servico ou configuracao.', p_tipo
      using errcode = '22023';
  end if;

  if doc_tabela = 'app_settings' then
    if not private.historico_config_relevante(v_ref) then
      raise exception 'A configuração "%" não tem histórico (só as que formam o documento).', v_ref using errcode = '22023';
    end if;
    doc_id := md5('app_settings:' || v_ref)::uuid; rotulo := 'Configuração ' || v_ref; por_registro := true;
    return;
  end if;

  if doc_tabela = 'service_orders' then
    select so.id, so.service_order_number into doc_id, rotulo from public.service_orders so
     where so.id = v_uuid
        or upper(translate(so.service_order_number, 'Çç', 'CC')) = upper(translate(v_ref, 'Çç', 'CC'));
  elsif doc_tabela = 'purchase_orders' then
    select p.id, p.po_number into doc_id, rotulo from public.purchase_orders p where p.id = v_uuid or upper(p.po_number) = upper(v_ref);
  elsif doc_tabela = 'quote_requests' then
    select q.id, q.code into doc_id, rotulo from public.quote_requests q where q.id = v_uuid or upper(q.code) = upper(v_ref);
  elsif doc_tabela = 'external_quotes' then
    select e.id, e.quote_number into doc_id, rotulo from public.external_quotes e where e.id = v_uuid or upper(e.quote_number) = upper(v_ref);
  elsif doc_tabela = 'products' then
    select count(*) into v_n from public.products p where p.id = v_uuid or upper(p.sku) = upper(v_ref) or p.name ilike v_ref;
    if v_n > 1 then
      raise exception 'Mais de um produto para "%": use o código (SKU).', v_ref using errcode = '22023';
    end if;
    select p.id, p.name into doc_id, rotulo from public.products p where p.id = v_uuid or upper(p.sku) = upper(v_ref) or p.name ilike v_ref;
  else
    execute format('select count(*) from public.%I t where t.id = $1 or t.name ilike $2', doc_tabela) into v_n using v_uuid, v_ref;
    if v_n > 1 then
      raise exception 'Mais de um registro com o nome "%": diga qual (por exemplo, pelo número do documento).', v_ref using errcode = '22023';
    end if;
    execute format('select t.id, t.name from public.%I t where t.id = $1 or t.name ilike $2', doc_tabela) into doc_id, rotulo using v_uuid, v_ref;
  end if;

  if doc_id is null and v_uuid is not null then
    -- documento excluído: o histórico continua lá
    doc_id := v_uuid; rotulo := '(excluído)';
  end if;
  if doc_id is null then
    raise exception 'Documento não encontrado: % %.', p_tipo, p_ref using errcode = 'P0002';
  end if;
end $$;

-- ─── A consulta ────────────────────────────────────────────────────────────────────────────────────
create or replace function public.documento_historico(
  p_tipo     text,
  p_ref      text,
  p_modo     text default 'alteracoes',
  p_versao   integer default null,
  p_versao_b integer default null,
  p_desde    timestamptz default null,
  p_ate      timestamptz default null,
  p_limite   integer default 20
) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_doc     record;
  v_limite  integer := least(greatest(coalesce(p_limite, 20), 1), 100);
  v_eventos jsonb;
  v_total   integer;
  v_ret_a   jsonb;
  v_ret_b   jsonb;
  v_lin     record;
begin
  if not private.historico_pode_ler() then
    raise exception 'O histórico de documentos é só para administrador e financeiro.' using errcode = '42501';
  end if;
  select * into v_doc from private.historico_resolver(p_tipo, p_ref);

  if p_modo = 'alteracoes' then
    with base as (
      select l.id, l.changed_at, l.ator_id, l.origem, l.changed_by, l.action,
             -- Um "salvamento" = mesma pessoa e canal. Linha do gatilho: transação diferente com mais de 5 s entre elas é
             -- outro salvamento (a tela grava um salvar em várias requisições quase juntas). Linha antiga: janela de 90 s.
             case when lag(l.changed_at) over w is null
                    or lag(l.ator_id) over w is distinct from l.ator_id
                    or lag(l.origem) over w is distinct from l.origem
                    or lag(l.changed_by) over w is distinct from l.changed_by
                    or l.action = 'versao' or lag(l.action) over w = 'versao'
                    or (l.xact_id is not null and lag(l.xact_id) over w is not null
                        and l.xact_id <> lag(l.xact_id) over w
                        and l.changed_at - lag(l.changed_at) over w > interval '5 seconds')
                    or l.changed_at - lag(l.changed_at) over w > interval '90 seconds'
                  then 1 else 0 end as novo
        from public.audit_log l
       where ((l.doc_tabela = v_doc.doc_tabela and l.doc_id = v_doc.doc_id)
              or (l.table_name = v_doc.doc_tabela and l.record_id = v_doc.doc_id and l.doc_id is null))
         and not private.historico_linha_vazia(l)
         and (p_desde is null or l.changed_at >= p_desde)
         and (p_ate is null or l.changed_at <= p_ate)
      window w as (order by l.changed_at, l.id)
    ), grupos as (
      select b.*, sum(b.novo) over (order by b.changed_at, b.id) as grupo from base b
    ), topo as (
      -- só os eventos que vão aparecer são formatados (há OS com centenas de linhas antigas)
      select g.grupo, min(g.changed_at) as inicio from grupos g group by g.grupo order by min(g.changed_at) desc limit v_limite
    ), linhas as (
      select g.grupo, g.changed_at, g.id, g.changed_by, g.origem, g.action, private.historico_linha(a) as l
        from grupos g
        join topo t on t.grupo = g.grupo
        join public.audit_log a on a.id = g.id
    ), evt as (
      select li.grupo,
             min(li.changed_at) as inicio,
             (array_agg(li.changed_by order by li.changed_at))[1] as quem,
             (array_agg(li.origem order by li.changed_at))[1] as origem,
             jsonb_agg(li.l order by li.changed_at, li.id)
               filter (where li.action not in ('update', 'cascade_update') or jsonb_array_length(li.l -> 'mudancas') > 0) as itens
        from linhas li
       group by li.grupo
    )
    select (select count(distinct g.grupo) from grupos g),
           coalesce(jsonb_agg(jsonb_build_object(
             'quando', to_char(e.inicio at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
             'quando_iso', e.inicio,
             'quem', coalesce(e.quem, 'sistema'),
             'por_onde', case e.origem
               when 'tela' then 'tela' when 'assistente_painel' then 'assistente (painel)'
               when 'assistente_whatsapp' then 'assistente (WhatsApp)' when 'assistente_max' then 'assistente (Claude)'
               when 'cliente_link' then 'cliente pelo link' when 'automacao' then 'automação'
               when 'restauracao' then 'restauração' when 'migracao' then 'carga inicial' when 'servidor' then 'sistema'
               when 'banco' then 'sistema' else coalesce(e.origem, 'registro antigo') end,
             'desfazivel', exists (select 1 from jsonb_array_elements(e.itens) i where (i ->> 'desfazivel')::boolean),
             'itens', e.itens) order by e.inicio desc) filter (where e.itens is not null), '[]'::jsonb)
      into v_total, v_eventos
      from evt e;

    return jsonb_build_object(
      'documento', jsonb_build_object('tipo', p_tipo, 'numero', v_doc.rotulo, 'id', v_doc.doc_id),
      'modo', 'alteracoes',
      'total_de_eventos', v_total,
      'eventos', v_eventos,
      'aviso', case when v_total > v_limite then format('Mostrando os %s eventos mais recentes de %s. Peça com "desde"/"ate" ou um limite maior para ver mais.', v_limite, v_total) end);
  end if;

  if v_doc.doc_tabela <> 'service_orders' and p_modo in ('versoes', 'ver_versao', 'comparar') then
    raise exception 'Versões existem só para orçamento/OS; para este documento use o modo alteracoes.' using errcode = '22023';
  end if;

  if p_modo = 'versoes' then
    return jsonb_build_object(
      'documento', jsonb_build_object('tipo', p_tipo, 'numero', v_doc.rotulo, 'id', v_doc.doc_id),
      'modo', 'versoes',
      'versoes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'versao', l.versao, 'marco', l.reason,
          'quando', to_char(l.changed_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
          'quando_iso', l.changed_at, 'quem', l.changed_by,
          'situacao', private.historico_valor('status', l.new_value -> 'retrato' -> 'cabecalho' -> 'status'),
          'total', private.historico_valor('grand_total', l.new_value -> 'retrato' -> 'cabecalho' -> 'grand_total'),
          'pecas', jsonb_array_length(l.new_value -> 'retrato' -> 'pecas'),
          'servicos', jsonb_array_length(l.new_value -> 'retrato' -> 'servicos')) order by l.versao desc)
          from public.audit_log l
         where l.doc_tabela = 'service_orders' and l.doc_id = v_doc.doc_id and l.action = 'versao'), '[]'::jsonb));
  end if;

  if p_modo = 'ver_versao' then
    select l.* into v_lin from public.audit_log l
     where l.doc_tabela = 'service_orders' and l.doc_id = v_doc.doc_id and l.action = 'versao'
       and (p_versao is null or l.versao = p_versao)
     order by l.versao desc limit 1;
    if v_lin.id is null then
      raise exception 'Versão % não encontrada para %.', coalesce(p_versao::text, '(última)'), v_doc.rotulo using errcode = 'P0002';
    end if;
    return jsonb_build_object(
      'documento', jsonb_build_object('tipo', p_tipo, 'numero', v_doc.rotulo, 'id', v_doc.doc_id),
      'modo', 'ver_versao', 'versao', v_lin.versao, 'marco', v_lin.reason,
      'quando', to_char(v_lin.changed_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'), 'quem', v_lin.changed_by,
      'conteudo', private.historico_retrato_legivel(v_lin.new_value -> 'retrato'));
  end if;

  if p_modo = 'comparar' then
    if p_versao is null then
      raise exception 'Para comparar, diga a versão (e, se quiser, a segunda; sem ela compara com o estado atual).' using errcode = '22023';
    end if;
    select l.new_value -> 'retrato' into v_ret_a from public.audit_log l
     where l.doc_tabela = 'service_orders' and l.doc_id = v_doc.doc_id and l.action = 'versao' and l.versao = p_versao;
    if v_ret_a is null then
      raise exception 'Versão % não encontrada para %.', p_versao, v_doc.rotulo using errcode = 'P0002';
    end if;
    if p_versao_b is null then
      v_ret_b := private.documento_retrato(v_doc.doc_id);
    else
      select l.new_value -> 'retrato' into v_ret_b from public.audit_log l
       where l.doc_tabela = 'service_orders' and l.doc_id = v_doc.doc_id and l.action = 'versao' and l.versao = p_versao_b;
      if v_ret_b is null then
        raise exception 'Versão % não encontrada para %.', p_versao_b, v_doc.rotulo using errcode = 'P0002';
      end if;
    end if;
    return jsonb_build_object(
      'documento', jsonb_build_object('tipo', p_tipo, 'numero', v_doc.rotulo, 'id', v_doc.doc_id),
      'modo', 'comparar', 'de', 'v' || p_versao, 'para', coalesce('v' || p_versao_b, 'estado atual'),
      'diferencas', private.historico_comparar_retratos(v_ret_a, v_ret_b));
  end if;

  raise exception 'Modo desconhecido: %. Use alteracoes, versoes, ver_versao ou comparar.', p_modo using errcode = '22023';
end $$;

comment on function public.documento_historico(text, text, text, integer, integer, timestamptz, timestamptz, integer) is
  'Histórico legível de um documento (orçamento/OS, compra, cotação, orçamento externo, cadastro, configuração). Só admin/financeiro.';

-- ─── Segurança ────────────────────────────────────────────────────────────────────────────────────
revoke all on function private.historico_rotulo(text, text)                 from public, anon, authenticated;
revoke all on function private.historico_calculada(text)                    from public, anon, authenticated;
revoke all on function private.historico_oculta(text)                       from public, anon, authenticated;
revoke all on function private.historico_igual(jsonb, jsonb)                from public, anon, authenticated;
revoke all on function private.historico_restauraveis(text)                 from public, anon, authenticated;
revoke all on function private.historico_desfazivel(public.audit_log)       from public, anon, authenticated;
revoke all on function private.historico_linha_vazia(public.audit_log)      from public, anon, authenticated;
revoke all on function private.historico_valor(text, jsonb)                 from public, anon, authenticated;
revoke all on function private.historico_item(text, uuid, jsonb, jsonb)     from public, anon, authenticated;
revoke all on function private.historico_linha(public.audit_log)            from public, anon, authenticated;
revoke all on function private.historico_retrato_legivel(jsonb)             from public, anon, authenticated;
revoke all on function private.historico_comparar_retratos(jsonb, jsonb)    from public, anon, authenticated;
revoke all on function private.historico_pode_ler()                         from public, anon, authenticated;
revoke all on function private.historico_resolver(text, text)               from public, anon, authenticated;

revoke all on function public.documento_historico(text, text, text, integer, integer, timestamptz, timestamptz, integer) from public, anon;
grant execute on function public.documento_historico(text, text, text, integer, integer, timestamptz, timestamptz, integer) to authenticated, service_role;
