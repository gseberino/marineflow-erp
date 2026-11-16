-- Histórico de documentos: linha antiga que só mudou o FORMATO do valor não aparece como alteração.
--
-- Achado na prova com dado real (16/11/2026, OS-00104): o formulário antigo regravava datas em outro formato de
-- texto ('2026-10-08T21:00:00+00:00' x '2026-10-08 21:00:00+00') e a linha do tempo mostrava
-- "Fim agendado: 08/10/2026 18:00 → 08/10/2026 18:00". Agora, quando o valor LEGÍVEL de antes e de depois é o mesmo,
-- o campo não entra (o evento sem nenhuma mudança visível já some da lista).
-- Recria private.historico_linha (20270121100100) com uma linha a mais; o resto é igual.
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
      -- só o formato mudou (data com T x espaço, 10 x 10.00): não é alteração
      continue when p_l.previous_value ? v_k and private.historico_valor(v_k, v_a) = private.historico_valor(v_k, v_d);
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

revoke all on function private.historico_linha(public.audit_log) from public, anon, authenticated;
