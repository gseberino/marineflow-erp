-- Histórico de documentos (F3): CORRIGIR — desfazer uma alteração ou voltar o orçamento/OS para uma versão.
--
-- Uma função só, public.documento_restaurar, para a tela e para o assistente (restaurar_documento, sempre com SIM).
-- Regras (decisão 2 do dono, 16/11/2026, e princípios do Business Central/Frappe):
--   * só documento ABERTO: concluída, faturada, cancelada ou agrupada é recusada (para essas, copiar para um novo);
--   * restaura só CONTEÚDO (campos digitados, peças e serviços — private.historico_restauraveis, na F2); nunca
--     situação, pagamento, faturamento, assinatura, número, link público, cliente ou embarcação;
--   * só desfaz linha gravada PELO BANCO (audit_log.pelo_banco) e do PRÓPRIO documento: linha escrita pela API pode
--     ser forjada, e linha antiga não guarda o valor de antes — essas vão para "nao_desfeito", nunca viram NULL;
--   * a linha volta com o MESMO id (o histórico e os vínculos continuam ligados); o que o CASCADE/SET NULL levou
--     junto (material da agenda, item de compra/cotação) não volta — a simulação avisa antes;
--   * o total é recalculado pela fórmula única (recalc_so_totals, MF-AUD-011), nunca copiado; se ficar abaixo do que
--     o cliente já pagou, recusa;
--   * restaurar é uma edição nova: o histórico ganha as linhas da restauração, uma linha 'restore' e um retrato
--     novo (marco "restaurado") — nada do histórico é apagado;
--   * documento assinado que muda volta a pedir assinatura (gatilhos de assinatura, F1);
--   * p_simular = true (padrão) faz tudo e DESFAZ no fim: o que a simulação mostra é exatamente o que vai acontecer;
--   * p_conferir_hash: guarda-se o hash do documento na simulação e a confirmação recusa se ele mudou no meio.

-- As colunas reais de uma tabela (para inserir de volta só o que existe).
create or replace function private.historico_colunas(p_tabela text)
returns text[] language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(array_agg(a.attname::text order by a.attnum), '{}')
    from pg_attribute a
   where a.attrelid = ('public.' || quote_ident(p_tabela))::regclass
     and a.attnum > 0 and not a.attisdropped and a.attgenerated = '';
$$;

-- Atualiza as colunas pedidas de uma linha a partir de um jsonb (tipos convertidos pelo próprio Postgres).
create or replace function private.historico_aplicar_update(p_tabela text, p_id uuid, p_valores jsonb, p_colunas text[])
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_colunas is null or cardinality(p_colunas) = 0 then
    return;
  end if;
  execute format(
    'update public.%I t set (%s) = (select %s from jsonb_populate_record(null::public.%I, $1) r) where t.id = $2',
    p_tabela,
    (select string_agg(quote_ident(c), ', ') from unnest(p_colunas) c),
    (select string_agg('r.' || quote_ident(c), ', ') from unnest(p_colunas) c),
    p_tabela)
  using p_valores, p_id;
end $$;

-- Põe de volta uma linha apagada, com o mesmo id. Devolve o motivo se não deu (vínculo que não existe mais).
create or replace function private.historico_aplicar_insert(p_tabela text, p_linha jsonb)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_cols text[];
begin
  select array_agg(c) into v_cols
    from unnest(private.historico_colunas(p_tabela)) c
   where p_linha ? c and c not in ('updated_at');
  begin
    execute format(
      'insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1) r',
      p_tabela,
      (select string_agg(quote_ident(c), ', ') from unnest(v_cols) c),
      (select string_agg('r.' || quote_ident(c), ', ') from unnest(v_cols) c),
      p_tabela)
    using p_linha;
  exception
    when foreign_key_violation then
      return 'o produto, serviço ou item a que ela se ligava não existe mais';
    when unique_violation then
      return 'já existe de novo';
  end;
  return null;
end $$;

-- O que se perde ao tirar uma linha: o CASCADE/SET NULL leva junto material da agenda, item de compra e de cotação.
create or replace function private.historico_dependencias(p_tabela text, p_id uuid)
returns text language sql stable security definer set search_path = public, pg_temp as $$
  select nullif(concat_ws(', ',
    case when exists (select 1 from public.os_material m
                       where (p_tabela = 'service_order_parts' and m.service_order_part_id = p_id)
                          or (p_tabela = 'service_order_services' and m.service_order_service_id = p_id))
         then 'planejamento de material da agenda' end,
    case when exists (select 1 from public.purchase_order_items i
                       where (p_tabela = 'service_order_parts' and i.service_order_part_id = p_id)
                          or (p_tabela = 'service_order_services' and i.service_order_service_id = p_id))
         then 'item de pedido de compra' end,
    case when exists (select 1 from public.quote_request_items i
                       where (p_tabela = 'service_order_parts' and i.service_order_part_id = p_id)
                          or (p_tabela = 'service_order_services' and i.service_order_service_id = p_id))
         then 'item de cotação' end), '');
$$;

create or replace function public.documento_restaurar(
  p_ref           text,
  p_versao        integer default null,
  p_eventos       uuid[]  default null,
  p_motivo        text    default null,
  p_simular       boolean default true,
  p_conferir_hash text    default null,
  p_autor         uuid    default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid     uuid := auth.uid();
  v_papel   text;
  v_ator    uuid;
  v_doc     record;
  v_so      public.service_orders;
  v_antes   jsonb;
  v_depois  jsonb;
  v_alvo    jsonb;
  v_hash    text;
  v_conf    jsonb := '[]'::jsonb;
  v_avisos  jsonb := '[]'::jsonb;
  v_cols    text[];
  v_lista   text;
  v_tab     text;
  v_item    jsonb;
  v_atual   jsonb;
  v_ev      public.audit_log;
  v_k       text;
  v_nome    text;
  v_dep     text;
  v_falha   text;
  v_id      uuid;
  v_pago    numeric;
  v_total   numeric;
  v_versao  integer;
  v_desc    text;
  v_res     jsonb;
  v_simulou boolean := false;
begin
  -- quem
  if v_uid is not null then
    if not public.is_admin_or_financial(v_uid) then
      raise exception 'Só administrador e financeiro restauram documento.' using errcode = '42501';
    end if;
    v_ator := v_uid;
  else
    begin
      v_papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
    exception when others then v_papel := 'invalido';
    end;
    if v_papel not in ('', 'service_role') or p_autor is null or not public.is_admin_or_financial(p_autor) then
      raise exception 'Só administrador e financeiro restauram documento.' using errcode = '42501';
    end if;
    v_ator := p_autor;
  end if;

  if (p_versao is null) = (p_eventos is null or cardinality(p_eventos) = 0) then
    raise exception 'Diga UMA coisa: a versão para voltar (p_versao) OU as alterações a desfazer (p_eventos).' using errcode = '22023';
  end if;

  select * into v_doc from private.historico_resolver('os', p_ref);
  select * into v_so from public.service_orders where id = v_doc.doc_id for update;
  if v_so.id is null then
    raise exception 'Documento não encontrado: %.', p_ref using errcode = 'P0002';
  end if;
  if v_so.status in ('completed', 'invoiced', 'cancelled') or v_so.invoicing_status = 'invoiced' or v_so.merged_into_id is not null then
    raise exception '% está %: só documento em aberto pode ser restaurado. Para usar o conteúdo antigo, copie a versão para um documento novo.',
      v_so.service_order_number,
      case when v_so.merged_into_id is not null then 'agrupado' else private.historico_valor('status', to_jsonb(v_so.status)) end
      using errcode = 'P0001';
  end if;

  v_antes := private.documento_retrato(v_so.id);
  v_hash  := md5(v_antes::text);
  if p_conferir_hash is not null and p_conferir_hash <> v_hash then
    raise exception '% mudou depois do pedido de restauração. Consulte de novo antes de restaurar.', v_so.service_order_number
      using errcode = 'P0001';
  end if;

  if p_versao is not null then
    select l.new_value -> 'retrato' into v_alvo from public.audit_log l
     where l.doc_tabela = 'service_orders' and l.doc_id = v_so.id and l.action = 'versao' and l.versao = p_versao
       and l.pelo_banco;
    if v_alvo is null then
      raise exception 'Versão % não encontrada para %.', p_versao, v_so.service_order_number using errcode = 'P0002';
    end if;
    v_desc := 'versão ' || p_versao;
  else
    if exists (select 1 from unnest(p_eventos) e
                where not exists (select 1 from public.audit_log l where l.id = e and l.doc_tabela = 'service_orders' and l.doc_id = v_so.id)) then
      raise exception 'Alguma das alterações informadas não é de %.', v_so.service_order_number using errcode = '22023';
    end if;
    v_desc := cardinality(p_eventos) || ' alteração(ões)';
  end if;

  begin
    perform set_config('marineflow.historico_origem', 'restauracao', true);
    perform set_config('marineflow.historico_ator', v_ator::text, true);
    perform set_config('marineflow.historico_motivo',
      left('Restaurado (' || v_desc || ')' || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), 500), true);

    if p_versao is not null then
      -- 1. cabeçalho
      select array_agg(c) into v_cols from unnest(private.historico_restauraveis('service_orders')) c
       where (v_alvo -> 'cabecalho') ? c and not private.historico_igual(v_alvo -> 'cabecalho' -> c, to_jsonb(v_so) -> c);
      perform private.historico_aplicar_update('service_orders', v_so.id, v_alvo -> 'cabecalho', v_cols);

      -- 2. linhas: serviços antes das peças (a peça pode apontar para o serviço)
      foreach v_lista in array array['servicos', 'pecas'] loop
        v_tab := case v_lista when 'pecas' then 'service_order_parts' else 'service_order_services' end;
        for v_item in select x - array['produto', 'sku'] from jsonb_array_elements(coalesce(v_alvo -> v_lista, '[]'::jsonb)) x loop
          v_atual := null;
          execute format('select to_jsonb(t) from public.%I t where t.id = $1', v_tab) into v_atual using (v_item ->> 'id')::uuid;
          if v_atual is null then
            v_falha := private.historico_aplicar_insert(v_tab, v_item || jsonb_build_object('service_order_id', v_so.id));
            if v_falha is not null then
              v_conf := v_conf || jsonb_build_object('item', private.historico_item(v_tab, (v_item ->> 'id')::uuid, null, v_item),
                'motivo', 'não voltou: ' || v_falha);
            end if;
          elsif v_atual ->> 'service_order_id' = v_so.id::text then
            select array_agg(c) into v_cols from unnest(private.historico_restauraveis(v_tab)) c
             where v_item ? c and not private.historico_igual(v_item -> c, v_atual -> c);
            perform private.historico_aplicar_update(v_tab, (v_item ->> 'id')::uuid, v_item, v_cols);
          else
            v_conf := v_conf || jsonb_build_object('item', private.historico_item(v_tab, (v_item ->> 'id')::uuid, null, v_item),
              'motivo', 'hoje pertence a outro documento');
          end if;
        end loop;
      end loop;

      -- 3. o que não existia na versão sai (peças antes dos serviços), avisando o que vai junto
      for v_tab, v_lista in select * from (values ('service_order_parts', 'pecas'), ('service_order_services', 'servicos')) as t(a, b) loop
        for v_id in execute format(
            'select t.id from public.%I t where t.service_order_id = $1
              and not exists (select 1 from jsonb_array_elements($2) x where (x ->> ''id'')::uuid = t.id)', v_tab)
          using v_so.id, coalesce(v_alvo -> v_lista, '[]'::jsonb)
        loop
          v_dep := private.historico_dependencias(v_tab, v_id);
          if v_dep is not null then
            v_avisos := v_avisos || jsonb_build_object('item', private.historico_item(v_tab, v_id, null, null),
              'aviso', 'sai do documento e leva junto: ' || v_dep || ' (isso não volta numa restauração futura)');
          end if;
          execute format('delete from public.%I t where t.id = $1', v_tab) using v_id;
        end loop;
      end loop;
    else
      -- desfazer: do mais novo para o mais velho; só volta o que ainda está como a alteração deixou
      for v_ev in
        select l.* from public.audit_log l where l.id = any (p_eventos) order by l.changed_at desc, l.id desc
      loop
        v_nome := case when v_ev.action = 'versao' then 'Versão ' || v_ev.versao
                       else private.historico_item(v_ev.table_name, v_ev.record_id, v_ev.previous_value, v_ev.new_value) end;
        if not private.historico_desfazivel(v_ev) then
          v_conf := v_conf || jsonb_build_object('item', v_nome, 'motivo',
            case when not v_ev.pelo_banco then 'registro antigo ou manual: não guarda o valor de antes'
                 else 'esse tipo de registro não se desfaz (situação, total recalculado, envio, versão...)' end);
          continue;
        end if;
        v_atual := null;
        execute format('select to_jsonb(t) from public.%I t where t.id = $1', v_ev.table_name) into v_atual using v_ev.record_id;
        -- a linha tem de ser deste documento (hoje e no registro)
        if v_atual is not null and v_ev.table_name <> 'service_orders' and v_atual ->> 'service_order_id' <> v_so.id::text then
          v_conf := v_conf || jsonb_build_object('item', v_nome, 'motivo', 'hoje pertence a outro documento');
          continue;
        end if;
        if v_ev.table_name = 'service_orders' and v_ev.record_id <> v_so.id then
          v_conf := v_conf || jsonb_build_object('item', v_nome, 'motivo', 'é de outro documento');
          continue;
        end if;

        if v_ev.action = 'update' then
          if v_atual is null then
            v_conf := v_conf || jsonb_build_object('item', v_nome, 'motivo', 'o item foi removido depois');
            continue;
          end if;
          v_cols := '{}';
          for v_k in select key from jsonb_each(v_ev.new_value) loop
            continue when not (v_k = any (private.historico_restauraveis(v_ev.table_name)));
            if not (coalesce(v_ev.previous_value, '{}'::jsonb) ? v_k) then
              v_conf := v_conf || jsonb_build_object('item', v_nome, 'campo', private.historico_rotulo(v_ev.table_name, v_k),
                'motivo', 'o registro não guarda o valor de antes');
            elsif private.historico_igual(v_atual -> v_k, v_ev.new_value -> v_k) then
              v_cols := v_cols || v_k;
            elsif not private.historico_igual(v_atual -> v_k, v_ev.previous_value -> v_k) then
              v_conf := v_conf || jsonb_build_object('item', v_nome, 'campo', private.historico_rotulo(v_ev.table_name, v_k),
                'motivo', 'foi alterado de novo depois; ficou como está');
            end if;
          end loop;
          perform private.historico_aplicar_update(v_ev.table_name, v_ev.record_id, v_ev.previous_value, v_cols);
        elsif v_ev.action = 'insert' then
          if v_atual is null then
            continue;   -- já não existe: nada a desfazer
          end if;
          if exists (select 1 from unnest(private.historico_restauraveis(v_ev.table_name)) c
                      where v_ev.new_value ? c and not private.historico_igual(v_atual -> c, v_ev.new_value -> c)) then
            v_conf := v_conf || jsonb_build_object('item', v_nome, 'motivo', 'foi alterado depois de incluído; ficou como está');
            continue;
          end if;
          v_dep := private.historico_dependencias(v_ev.table_name, v_ev.record_id);
          if v_dep is not null then
            v_avisos := v_avisos || jsonb_build_object('item', v_nome,
              'aviso', 'sai do documento e leva junto: ' || v_dep || ' (isso não volta numa restauração futura)');
          end if;
          execute format('delete from public.%I t where t.id = $1', v_ev.table_name) using v_ev.record_id;
        else  -- delete: volta com o mesmo id
          if v_atual is not null then
            continue;   -- já voltou
          end if;
          if coalesce(v_ev.previous_value ->> 'service_order_id', '') <> v_so.id::text then
            v_conf := v_conf || jsonb_build_object('item', v_nome, 'motivo', 'era de outro documento');
            continue;
          end if;
          v_falha := private.historico_aplicar_insert(v_ev.table_name, v_ev.previous_value);
          if v_falha is not null then
            v_conf := v_conf || jsonb_build_object('item', v_nome, 'motivo', 'não voltou: ' || v_falha);
          end if;
        end if;
      end loop;
    end if;

    -- total pela fórmula única; não pode ficar abaixo do que o cliente já pagou
    perform public.recalc_so_totals(v_so.id);
    select grand_total into v_total from public.service_orders where id = v_so.id;
    select coalesce(sum(r.paid_amount), 0) into v_pago from public.receivables r
     where r.service_order_id = v_so.id and r.status <> 'cancelled';
    if v_total < v_pago - 0.005 then
      raise exception 'Restaurar deixaria o total (%) abaixo do que o cliente já pagou (%).',
        private.historico_valor('grand_total', to_jsonb(v_total)), private.historico_valor('grand_total', to_jsonb(v_pago))
        using errcode = 'P0001';
    end if;

    v_depois := private.documento_retrato(v_so.id);
    v_res := jsonb_build_object(
      'documento', v_so.service_order_number,
      'documento_id', v_so.id,
      'o_que_muda', private.historico_comparar_retratos(v_antes, v_depois),
      'nao_desfeito', v_conf,
      'avisos', v_avisos,
      'total_antes', private.historico_valor('grand_total', v_antes -> 'cabecalho' -> 'grand_total'),
      'total_depois', private.historico_valor('grand_total', v_depois -> 'cabecalho' -> 'grand_total'),
      'pede_nova_assinatura', v_so.signed_at is not null and (select requires_resignature from public.service_orders where id = v_so.id),
      'hash_do_documento', v_hash);

    if p_simular then
      v_simulou := true;
      raise exception using errcode = 'MF001', message = 'simulação';
    end if;

    if (v_res -> 'o_que_muda' ->> 'sem_diferenca')::boolean then
      return v_res || jsonb_build_object('simulacao', false, 'restaurado', false, 'mensagem', 'Nada a mudar: o documento já está assim.');
    end if;

    v_versao := private.documento_versionar(v_so.id, 'restaurado');
    perform set_config('marineflow.historico_interno', 'on', true);
    insert into public.audit_log (table_name, record_id, action, changed_by, new_value, reason, doc_tabela, doc_id, ator_id, origem, pelo_banco)
    values ('service_orders', v_so.id, 'restore', coalesce(private.historico_nome(v_ator), 'restauração'),
            jsonb_build_object('de', v_desc, 'versao_nova', v_versao, 'eventos', to_jsonb(p_eventos), 'versao_alvo', p_versao,
                               'nao_desfeito', v_conf, 'avisos', v_avisos),
            nullif(btrim(p_motivo), ''), 'service_orders', v_so.id, v_ator, 'restauracao', true);
    perform set_config('marineflow.historico_interno', '', true);
  exception when sqlstate 'MF001' then
    null;   -- simulação: tudo desfeito; v_res guarda o que aconteceria
  end;

  if v_simulou then
    return v_res || jsonb_build_object('simulacao', true, 'restaurado', false,
      'mensagem', case when (v_res -> 'o_que_muda' ->> 'sem_diferenca')::boolean then 'Nada a mudar: o documento já está assim.' end);
  end if;
  return v_res || jsonb_build_object('simulacao', false, 'restaurado', true, 'versao_nova', v_versao);
end $$;

comment on function public.documento_restaurar(text, integer, uuid[], text, boolean, text, uuid) is
  'Desfaz alterações (p_eventos) ou volta para uma versão (p_versao) de um orçamento/OS em aberto. p_simular=true só mostra o que mudaria.';

revoke all on function private.historico_colunas(text)                        from public, anon, authenticated;
revoke all on function private.historico_aplicar_update(text, uuid, jsonb, text[]) from public, anon, authenticated;
revoke all on function private.historico_aplicar_insert(text, jsonb)           from public, anon, authenticated;
revoke all on function private.historico_dependencias(text, uuid)             from public, anon, authenticated;

revoke all on function public.documento_restaurar(text, integer, uuid[], text, boolean, text, uuid) from public, anon;
grant execute on function public.documento_restaurar(text, integer, uuid[], text, boolean, text, uuid) to authenticated, service_role;
