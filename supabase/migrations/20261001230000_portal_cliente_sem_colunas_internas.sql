-- O link público da OS (/view/<token>) deixa de entregar colunas internas ao anônimo.
--
-- Achado de 01/10/2026: o portal lia service_orders, vessels e service_order_parts com
-- select('*') como anon. O que não aparecia na tela chegava ao navegador do cliente: custo de
-- cada peça (unit_cost_snapshot, line_total_cost — a margem), comissão, notas internas, custo e
-- margem do produto, taxa de cartão do pagamento, anotações sobre o cliente.
--
-- O anon tinha SELECT na tabela inteira. Agora tem SELECT por coluna: todas MENOS as internas.
-- As políticas de RLS (só a OS do token) continuam as mesmas. Coluna criada depois nasce fechada
-- para o anon — se o portal precisar dela, liberar aqui e em colunas-publicas.ts.
--
-- A lista das internas é a mesma de supabase/functions/_shared/pdf/colunas-publicas.ts
-- (COLUNAS_INTERNAS); o teste colunas-publicas.test.ts confere as duas.
-- O portal e o PDF do portal já pedem colunas explícitas desde o commit anterior; com `*` o
-- anon passaria a receber "permission denied".

do $$
declare
  internas jsonb := '{
    "service_orders": ["internal_notes", "commission_rate", "commission_amount", "commissioned_person", "commissioned_user_id", "technician_instructions", "site_access", "estimate_confidence", "contingency_pct", "original_quote_amount", "created_by", "hourly_rate", "travel_cost_per_km"],
    "service_order_parts": ["unit_cost_snapshot", "line_total_cost"],
    "service_order_services": ["technician_instructions", "field_status", "field_status_note"],
    "products": ["cost_price", "cost_currency", "profit_margin", "commission_rate", "is_commissionable", "stock_quantity", "minimum_stock", "reserved_quantity", "location_bin", "supplier_id", "notes", "last_stock_entry_at"],
    "clients": ["notes", "communication_tone"],
    "marinas": ["billing_notes", "access_notes"],
    "vessels": ["access_notes"],
    "payments": ["card_fee_percent", "net_amount", "notes", "payable_id"],
    "receivables": ["notes", "category", "sub_category", "cost_center_id", "bank_transaction_id"],
    "service_order_expenses": ["notes", "receipt_url", "receipt_storage_path", "supplier_id", "technician_user_id", "reimbursed", "reimbursed_at", "reimbursed_payment_id", "linked_payable_id", "created_by"]
  }'::jsonb;
  t record;
  faltando text;
  liberadas text;
begin
  for t in select key as tabela, value as fechar from jsonb_each(internas) loop
    -- Nome de coluna errado aqui deixaria a coluna ABERTA em silêncio: para tudo.
    select string_agg(c, ', ') into faltando
      from jsonb_array_elements_text(t.fechar) c
     where not exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = t.tabela and column_name = c);
    if faltando is not null then
      raise exception 'Coluna inexistente em %: %', t.tabela, faltando;
    end if;

    select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into liberadas
      from information_schema.columns
     where table_schema = 'public' and table_name = t.tabela
       and column_name not in (select jsonb_array_elements_text(t.fechar));

    execute format('revoke select on public.%I from anon', t.tabela);
    execute format('grant select (%s) on public.%I to anon', liberadas, t.tabela);
  end loop;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261001230000', 'portal_cliente_sem_colunas_internas')
on conflict (version) do nothing;
