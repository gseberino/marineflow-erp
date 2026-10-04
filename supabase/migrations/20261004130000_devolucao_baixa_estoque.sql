-- Devolução de compra autorizada tira o item do estoque (decisão do dono, 04/10/2026 — cartão
-- "devolucao-estoque": "Sim, fazer").
--
-- O QUE ACONTECIA: as 3 devoluções de compra de 28/07 (NF-e 2/22, 2/23 e 2/24 — Cerbo GX, Conversor
-- Orion e Tela GX Touch 50) foram autorizadas e não tiraram nada do estoque: o sistema não ligava o
-- item devolvido ao produto. O saldo daquelas três está certo hoje porque a contagem de 27/07 já os
-- tinha zerado; a próxima devolução de um item na prateleira deixaria o saldo acima do real.
--
-- COMO FICA: quando uma NF-e de devolução (finalidade 4) de PRODUÇÃO passa a 'authorized', cada
-- item vira uma baixa 'fiscal_note_exit' no razão, com o produto achado pela NOTA DE ENTRADA que a
-- devolução referencia — a mesma que deu entrada no estoque:
--   1) pela referência do item (det/DFeReferenciado: chave da nota de compra + nItem), que o
--      payload-builder manda em toda devolução montada a partir da nota de entrada;
--   2) sem o número do item, pelo código do fornecedor (cProd) dentro das notas referenciadas,
--      só se ele apontar para UM produto.
-- A nota ganha stock_settled_at, e é isso que liga o estorno que JÁ EXISTE: se a devolução for
-- cancelada, reverse_nfe_settlement_on_cancel repõe cada baixa com 'fiscal_note_cancel_reversal'
-- (o mesmo caminho das notas avulsas de venda).
--
-- O QUE NÃO FAZ:
--   · não mexe nas 3 devoluções de julho (já estão autorizadas; a regra só age na passagem para
--     'authorized'), nem em homologação;
--   · NUNCA impede a autorização: qualquer falha aqui é registrada em app_error_logs e a nota segue
--     (o bloco de exceção desfaz só as baixas desta nota, e stock_settled_at fica vazio);
--   · item cujo produto não foi achado não baixa nada — vai para app_error_logs com o nome, para
--     ajuste manual; saldo que fique negativo também é avisado lá (sinal de que o estoque já
--     estava errado antes da devolução).

create or replace function private.devolucao_baixa_estoque()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_chaves      text[];
  v_item        jsonb;
  v_ref_chave   text;
  v_ref_item    int;
  v_pid         uuid;
  v_qtd         numeric;
  v_baixas      jsonb := '{}'::jsonb;  -- produto -> quantidade (soma das linhas do mesmo produto)
  v_sem_produto text[] := '{}';
  v_produto     text;
  v_saldo       numeric;
  v_nota        text;
begin
  if NEW.request_payload->>'purpose' is distinct from '4'
     or NEW.environment is distinct from 'producao'
     or NEW.status is distinct from 'authorized'
     or NEW.stock_settled_at is not null then
    return NEW;
  end if;
  if TG_OP = 'UPDATE' and OLD.status is not distinct from 'authorized' then
    return NEW;
  end if;

  v_nota := 'NF-e ' || coalesce(NEW.series::text, '') || '/' || coalesce(NEW.number::text, '');

  begin
    -- As notas de entrada referenciadas no nível da nota (as duas grafias que o payload já usou).
    select array_agg(distinct k) into v_chaves
      from (
        select regexp_replace(coalesce(r->>'access_key', ''), '\D', '', 'g') as k
          from jsonb_array_elements(coalesce(NEW.request_payload->'referenced_documents', '[]'::jsonb)) r
        union
        select regexp_replace(coalesce(r #>> '{}', ''), '\D', '', 'g')
          from jsonb_array_elements(coalesce(NEW.request_payload->'referenced_access_keys', '[]'::jsonb)) r
      ) x
     where length(k) = 44;

    for v_item in select * from jsonb_array_elements(coalesce(NEW.request_payload->'items', '[]'::jsonb)) loop
      v_qtd := coalesce(nullif(v_item->>'quantity', '')::numeric, 0);
      continue when v_qtd <= 0;

      v_pid := null;
      v_ref_chave := regexp_replace(coalesce(v_item->'referenced_document'->>'access_key', ''), '\D', '', 'g');
      v_ref_item := nullif(v_item->'referenced_document'->>'item', '')::int;

      -- 1) A referência do item: nota de entrada + número do item nela.
      if length(v_ref_chave) = 44 and v_ref_item is not null then
        select coalesce(fni.product_id, fni.matched_product_id) into v_pid
          from fiscal_notes fn
          join fiscal_note_items fni on fni.fiscal_note_id = fn.id
         where fn.nfe_key = v_ref_chave
           and fni.item_index = v_ref_item
         limit 1;
      end if;

      -- 2) O código do fornecedor dentro das notas referenciadas, se apontar para um produto só.
      if v_pid is null and coalesce(v_item->>'code', '') <> '' then
        select (array_agg(distinct coalesce(fni.product_id, fni.matched_product_id)))[1] into v_pid
          from fiscal_notes fn
          join fiscal_note_items fni on fni.fiscal_note_id = fn.id
         where fn.nfe_key = any (
                 coalesce(v_chaves, '{}'::text[])
                 || case when length(v_ref_chave) = 44 then array[v_ref_chave] else '{}'::text[] end)
           and coalesce(fni.c_prod, fni.sku_supplier) = v_item->>'code'
           and coalesce(fni.product_id, fni.matched_product_id) is not null
        having count(distinct coalesce(fni.product_id, fni.matched_product_id)) = 1;
      end if;

      if v_pid is null then
        v_sem_produto := v_sem_produto || coalesce(nullif(v_item->>'name', ''), v_item->>'code', '(sem nome)');
      else
        v_baixas := jsonb_set(v_baixas, array[v_pid::text],
                              to_jsonb(coalesce((v_baixas->>v_pid::text)::numeric, 0) + v_qtd));
      end if;
    end loop;

    for v_produto in select jsonb_object_keys(v_baixas) loop
      insert into inventory_movements
        (product_id, movement_type, quantity_delta, reference_type, reference_id, notes, adjusted_by)
      values
        (v_produto::uuid, 'fiscal_note_exit', -((v_baixas->>v_produto)::numeric),
         'issued_fiscal_document', NEW.id,
         'Devolução ao fornecedor — ' || v_nota, 'sistema');

      select coalesce(sum(quantity_delta), 0) into v_saldo
        from inventory_movements where product_id = v_produto::uuid;
      if v_saldo < 0 then
        perform public.log_app_error(
          'db', 'Devolução deixou o saldo do produto negativo: o estoque já estava abaixo do real antes dela.',
          'devolucao_baixa_estoque', v_nota, 'warn',
          jsonb_build_object('documento', NEW.id, 'produto', v_produto, 'saldo', v_saldo));
      end if;
    end loop;

    if array_length(v_sem_produto, 1) > 0 then
      perform public.log_app_error(
        'db', 'Devolução autorizada com item sem produto ligado: o estoque desse item não foi baixado (ajuste manual).',
        'devolucao_baixa_estoque', v_nota, 'warn',
        jsonb_build_object('documento', NEW.id, 'itens', to_jsonb(v_sem_produto)));
    end if;

    if v_baixas <> '{}'::jsonb then
      NEW.stock_settled_at := now();
    end if;
  exception when others then
    -- A autorização da nota nunca depende desta baixa.
    begin
      perform public.log_app_error(
        'db', 'Falha ao baixar o estoque da devolução: ' || sqlerrm,
        'devolucao_baixa_estoque', v_nota, 'error',
        jsonb_build_object('documento', NEW.id, 'sqlstate', sqlstate));
    exception when others then
      null;
    end;
  end;

  return NEW;
end;
$function$;

revoke all on function private.devolucao_baixa_estoque() from public, anon, authenticated;

drop trigger if exists trg_devolucao_baixa_estoque on public.issued_fiscal_documents;
create trigger trg_devolucao_baixa_estoque
  before insert or update of status on public.issued_fiscal_documents
  for each row execute function private.devolucao_baixa_estoque();

comment on function private.devolucao_baixa_estoque() is
  'Devolução de compra (finNFe 4) de produção autorizada: baixa fiscal_note_exit por item, produto achado pela nota de entrada referenciada (chave + nItem; senão cProd único). Marca stock_settled_at, o que liga o estorno de reverse_nfe_settlement_on_cancel. Nunca bloqueia a autorização: falha vai para app_error_logs. 04/10/2026.';
