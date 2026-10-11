-- Comprovantes F2 (11/10/2026): gravação depois do sim e cancelamento que desfaz cada efeito.
--
-- O plano (_comprovante_plano) decide, pela matriz 2.6.1 da spec, o que o sim do dono VAI fazer;
-- o resumo mostra exatamente esse plano e o hash dele vai na pergunta: o sim é sobre o que vai
-- acontecer de fato. A gravação (_comprovante_gravar) reaproveita SÓ rotas que já existem:
--   * despesa da OS aberta → so_expense_add (o único caminho de custo de OS que recalcula o total);
--   * OS concluída/faturada → INSERT direto não faturável, SEM recálculo (o total não muda; prova
--     no fim da função); "cobrar do cliente" fica marcado cobrar_a_parte;
--   * NF-e com XML → a OS vai pela linha da nota (fiscal_note_items.service_order_id), nunca por
--     despesa; nota que ainda não chegou → aguardando_xml (a manutenção liga quando chegar);
--   * pagamento pelo banco (Pix, débito, boleto…) da empresa → anotar_transacao (a "anotação antes do
--     banco"); se a linha já virou lançamento, ANEXA e corrige categoria/OS (corrigir_lancamento);
--   * dinheiro da empresa → lancar_no_caixa('caixa'); do bolso do sócio → lancar_no_caixa('socio')
--     (reembolso); crédito → nada (espera a fatura); técnico → só a despesa da OS (acerto = F2b);
--   * antes de criar, procura o que já foi lançado igual — do MESMO fornecedor — e anexa em vez de
--     duplicar (a despesa da OS, a anotação, a conta do Caixa, a conta a pagar em aberto);
--   * o CMP que o dono disse ser a mesma compra de outro CMP só guarda o arquivo.
-- O CNPJ da HBR nunca é documento nem fornecedor. FKs só comprovantes → outras tabelas.
--
-- DDL: service_order_expenses.cobrar_a_parte (nasce fechada ao anon, que lê por coluna).
-- Não escreve dados. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. Despesa "cobrar à parte"
-- ---------------------------------------------------------------------------------------------
alter table public.service_order_expenses
  add column if not exists cobrar_a_parte boolean not null default false;
comment on column public.service_order_expenses.cobrar_a_parte is
  'Despesa a cobrar do cliente fora do total (a OS já estava concluída/faturada quando o comprovante chegou). Fica não faturável; o Lucro por OS não a conta como custo da HBR.';
-- o anon lê service_order_expenses POR COLUNA (20261001190104): a coluna nova não entra
revoke select (cobrar_a_parte) on table public.service_order_expenses from anon;

-- ---------------------------------------------------------------------------------------------
-- 2. O documento que vai na anotação: o CNPJ de quem recebeu (Pix/boleto) ou o do emitente com
--    selo alta/média. Nunca CPF mascarado, CNPJ alfanumérico nem o CNPJ da HBR.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_documento(c public.comprovantes)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_raiz text := public.raiz_do_cnpj_da_empresa();
begin
  if c.favorecido_doc ~ '^[0-9]{14}$' and (v_raiz is null or left(c.favorecido_doc, 8) <> v_raiz) then
    return c.favorecido_doc;
  end if;
  if c.emitente_cnpj ~ '^[0-9]{14}$' and c.cnpj_confianca in ('alta', 'media')
     and (v_raiz is null or left(c.emitente_cnpj, 8) <> v_raiz) then
    return c.emitente_cnpj;
  end if;
  return null;
end $$;

-- O fornecedor do cadastro que vai às rotas (revisão de 11/10/2026). O CNPJ da HBR nunca é
-- fornecedor: o cadastro com a raiz da HBR vira nulo (a regra valia só na exibição). Na anotação, o
-- fornecedor só vai quando o cadastro não contradiz o documento (o CNPJ do Pix pode ser de uma filial
-- ou de um intermediador): o gatilho _anotacao_documento_confere recusaria TODO "sim".
create or replace function public._comprovante_fornecedor_efetivo(c public.comprovantes, p_documento text default null)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_raiz text := public.raiz_do_cnpj_da_empresa();
  v_doc text;
begin
  if c.supplier_id is null then
    return null;
  end if;
  select nullif(regexp_replace(coalesce(s.cnpj_cpf, ''), '\D', '', 'g'), '') into v_doc
    from public.suppliers s where s.id = c.supplier_id;
  if v_doc is not null and v_raiz is not null and length(v_doc) = 14 and left(v_doc, 8) = v_raiz then
    return null;
  end if;
  if p_documento is not null and v_doc is not null and v_doc <> p_documento then
    return null;
  end if;
  return c.supplier_id;
end $$;

-- O nome do fornecedor (cadastro/Receita) confere com o texto de um lançamento? O nome inteiro, ou
-- uma palavra distintiva dele (5+ letras, fora das genéricas: "posto", "comercio", "ltda"…).
create or replace function public._comprovante_nome_confere(p_nome text, p_texto text)
returns boolean
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_nome text := public._comprovante_normalizar(p_nome);
  v_texto text := ' ' || public._comprovante_normalizar(p_texto) || ' ';
begin
  if char_length(v_nome) < 4 or btrim(v_texto) = '' then
    return false;
  end if;
  if v_texto like '% ' || v_nome || ' %' then
    return true;
  end if;
  return exists (
    select 1 from unnest(regexp_split_to_array(v_nome, ' ')) t
     where char_length(t) >= 5
       and t not in ('ltda', 'comercio', 'servicos', 'servico', 'industria', 'eireli', 'posto', 'postos', 'loja', 'lojas',
                     'mercado', 'supermercado', 'distribuidora', 'materiais', 'material', 'construcao', 'nautica',
                     'nautico', 'marine', 'brasil', 'sociedade', 'empresa', 'grupo', 'comercial', 'combustiveis',
                     'combustivel', 'automotivo', 'automotiva', 'pecas', 'transportes', 'restaurante', 'farmacia')
       and v_texto like '% ' || t || ' %');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. O plano (2.6.2): o que o sim VAI fazer. Só leitura (a P5 roda nos CMPs reais).
--    CMP incompleto → {"efeitos":[],"falta":[...]} (nunca erro).
--    Revisão de 11/10/2026:
--    * a mesma compra de outro CMP (passo mesma_compra): o dono disse que é → só o arquivo
--      (efeito mesma_compra, nada na OS nem no financeiro); ainda não disse → falta;
--    * anexar exige IDENTIDADE (mesmo fornecedor do cadastro, mesmo CNPJ ou o nome dele no
--      lançamento), não só valor e data: um R$ 50,00 de outra compra não é usado; o parecido sem
--      identidade vira aviso (parecido_sem_identidade) e, no banco, "classificar no Extrato";
--    * a despesa anexada segue a resposta "cobrar ou não" (ajustar_despesa, com o "antes" para o
--      cancelar); OS faturada não muda de total: só o "cobrar à parte" ou o aviso;
--    * conta a pagar já aberta para o gasto (a da despesa da OS, lançada com "também criar conta",
--      ou uma em aberto do mesmo fornecedor e valor): anexa, não lança outra (pendência de baixa);
--    * cobrar do cliente em OS aberta com recebíveis já emitidos: aviso + pendência ajustar_recebiveis;
--    * NF-e com OS concluída/faturada e "cobrar": pendência cobrar_a_parte (não incluir_na_os).
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_plano(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_falta text[] := '{}';
  v_nfe boolean;
  v_ef jsonb;
  v_quem text;
  v_pagador uuid;
  v_cat text;
  v_os jsonb;
  v_faturada boolean;
  v_forma text;
  v_valor numeric;
  v_data date;
  v_efeitos jsonb := '[]'::jsonb;
  v_avisos text[] := '{}';
  v_pend text[] := '{}';
  v_situacao text := 'gravado';
  v_ids uuid[];
  v_parecidos integer;
  v_nota record;
  v_itens integer;
  v_q text;
  v_mesma_id uuid;
  v_mesma_codigo text;
  v_cand jsonb;
  v_raiz text := public.raiz_do_cnpj_da_empresa();
  v_docs text[];
  v_sup uuid;
  v_nome text;
  v_desp record;
  v_link_id uuid;
  v_link_status text;
  v_link_desc text;
  v_bancaria boolean;
  v_financeiro_feito boolean := false;
  v_billable_final boolean;
begin
  select * into c from public.comprovantes x where x.id = p_id;
  if not found then
    raise exception '_comprovante_plano: comprovante % não existe', p_id using errcode = '22023';
  end if;
  v_valor := c.valor_confirmado;
  v_data := c.data_confirmada;
  v_nfe := public._comprovante_e_nfe(c);
  if c.mesma_compra_de is not null then
    -- o outro foi cancelado: este volta a ser compra própria
    select y.id, y.codigo into v_mesma_id, v_mesma_codigo
      from public.comprovantes y where y.id = c.mesma_compra_de and y.situacao <> 'cancelado';
  end if;
  if v_valor is null then v_falta := v_falta || 'valor'::text; end if;
  if v_data is null then v_falta := v_falta || 'data'::text; end if;
  if c.destino is null then v_falta := v_falta || 'para_que'::text; end if;
  if c.destino = 'os' and c.destino_os_id is null then v_falta := v_falta || 'qual_os'::text; end if;
  if v_mesma_id is null and c.destino is not null and c.destino <> 'pessoal' and not coalesce(c.outra_compra, false)
     and cardinality(v_falta) = 0 and public._comprovante_mesma_compra(c) is not null then
    v_falta := v_falta || 'mesma_compra'::text;
  end if;
  if v_mesma_id is null and c.destino is not null and c.destino <> 'pessoal' and not v_nfe and c.forma_confirmada is null then
    v_falta := v_falta || 'como_pagou'::text;
  end if;
  if cardinality(v_falta) > 0 then
    return jsonb_build_object('efeitos', '[]'::jsonb, 'avisos', '[]'::jsonb, 'situacao_final', null, 'pasta', null,
                              'falta', to_jsonb(v_falta));
  end if;

  v_ef := public._comprovante_efetivo(c);
  v_quem := v_ef->>'quem';
  v_pagador := nullif(v_ef->>'pagador_id', '')::uuid;
  v_cat := v_ef->>'categoria';
  v_os := public._comprovante_os_info(c.destino_os_id);
  v_faturada := coalesce((v_os->>'faturada')::boolean, false);
  v_forma := c.forma_confirmada;
  v_bancaria := v_forma in ('pix', 'transferencia', 'debito', 'boleto', 'deposito', 'cheque');
  -- quem é o fornecedor (para anexar só o que é DESTA compra)
  select array_agg(d) into v_docs
    from unnest(array[c.emitente_cnpj, c.favorecido_doc]) d
   where d ~ '^[0-9]{14}$' and (v_raiz is null or left(d, 8) <> v_raiz);
  v_docs := coalesce(v_docs, '{}'::text[]);
  v_sup := public._comprovante_fornecedor_efetivo(c, null);
  v_nome := public._comprovante_fornecedor(c)->>'nome';

  if v_mesma_id is not null then
    -- a mesma compra de outro CMP: só o arquivo (o outro já lançou)
    v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'mesma_compra', 'cmp', v_mesma_codigo, 'cmp_id', v_mesma_id));

  elsif c.destino = 'pessoal' then
    -- L: só o arquivo em COMPROVANTES/PESSOAL
    v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'pessoal'));

  elsif v_nfe then
    -- I/J: a OS pela linha da nota; a conta é a da importação da nota
    select fn.id, fn.nfe_number into v_nota
      from public.fiscal_notes fn
     where fn.nfe_key = c.chave_acesso and fn.status = 'confirmed';
    if found then
      if c.destino = 'os' then
        select count(*) into v_itens from public.fiscal_note_items i
         where i.fiscal_note_id = v_nota.id and i.service_order_id is null;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'itens_da_nota', 'fiscal_note_id', v_nota.id, 'nfe_numero', v_nota.nfe_number,
          'os_id', c.destino_os_id, 'os_numero', v_os->>'numero', 'itens', v_itens));
      else
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'nota',
                                                                       'fiscal_note_id', v_nota.id));
      end if;
    else
      v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'aguardar_nota', 'os_id', c.destino_os_id));
      v_situacao := 'aguardando_xml';
    end if;
    -- O custo da NF-e na OS (revisão de 11/10/2026): "custo da HBR" vira despesa da OS NÃO faturável
    -- com o valor da nota — é o que o Lucro por OS desconta (nenhuma view lê a OS pela linha da nota);
    -- "cobrar" com a OS já concluída/faturada vira a despesa "cobrar à parte" (o total não muda),
    -- como no cupom. Com a OS aberta, "cobrar" = incluir as peças na OS pela tela (pendência). Se uma
    -- peça da nota já entrou como peça da OS, o custo dela já está no Lucro: não lança a despesa.
    if c.destino = 'os' and (c.cobrar_cliente is false or (c.cobrar_cliente and v_faturada)) then
      if v_nota.id is not null and exists (
           select 1 from public.fiscal_note_items i
             join public.service_order_parts sp
               on sp.service_order_id = c.destino_os_id and sp.product_id = coalesce(i.matched_product_id, i.product_id)
            where i.fiscal_note_id = v_nota.id) then
        v_avisos := v_avisos || 'pecas_da_nota_ja_na_os'::text;
      else
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'despesa_os', 'os_id', c.destino_os_id, 'os_numero', v_os->>'numero',
          'billable', false, 'cobrar_a_parte', coalesce(c.cobrar_cliente, false), 'direto', v_faturada,
          'paid_by', 'company', 'pagador_id', null, 'categoria', coalesce(v_cat, 'Peças e materiais'), 'nota', true));
      end if;
    end if;
    if c.destino = 'os' and c.cobrar_cliente then
      -- OS já concluída/faturada: o total não muda — fica a lembrança de cobrar à parte
      v_pend := v_pend || case when v_faturada then 'cobrar_a_parte' else 'incluir_na_os' end;
    end if;
    if c.destino = 'os' and v_faturada then
      v_avisos := v_avisos || 'os_faturada_total_nao_muda'::text;
    end if;

  elsif v_quem = 'cliente' then
    -- H: o cliente pagou direto
    v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'cliente_pagou'));

  else
    -- ── (1) a OS: A/B/C (e G com paid_by technician) ──────────────────────────────────────
    if c.destino = 'os' then
      -- a despesa que já está na OS com o mesmo valor e data E do mesmo fornecedor
      select count(*) into v_parecidos
        from public.service_order_expenses e
       where e.service_order_id = c.destino_os_id
         and abs(e.amount - v_valor) <= 0.01 and abs(e.expense_date - v_data) <= 1
         and not exists (select 1 from public.comprovantes y where y.so_expense_id = e.id);
      select array_agg(e.id order by e.id) into v_ids
        from public.service_order_expenses e
        left join public.suppliers s on s.id = e.supplier_id
       where e.service_order_id = c.destino_os_id
         and abs(e.amount - v_valor) <= 0.01 and abs(e.expense_date - v_data) <= 1
         and not exists (select 1 from public.comprovantes y where y.so_expense_id = e.id)
         and ((v_sup is not null and e.supplier_id = v_sup)
              or (regexp_replace(coalesce(s.cnpj_cpf, ''), '\D', '', 'g') = any (v_docs))
              or public._comprovante_nome_confere(v_nome, coalesce(e.description, '') || ' ' || coalesce(e.notes, '')));
      if coalesce(cardinality(v_ids), 0) = 1 then
        select e.id, e.amount, e.expense_date, e.description, e.billable_to_client, e.cobrar_a_parte, e.linked_payable_id
          into v_desp from public.service_order_expenses e where e.id = v_ids[1];
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'anexar_despesa', 'so_expense_id', v_desp.id, 'os_numero', v_os->>'numero',
          'valor', v_desp.amount::text, 'data', v_desp.expense_date, 'descricao', left(v_desp.description, 60),
          'billable', v_desp.billable_to_client));
        -- a despesa anexada segue o "cobrar ou não" que o dono respondeu agora
        if c.cobrar_cliente is not null and v_quem <> 'cliente' then
          if not v_faturada and v_desp.billable_to_client is distinct from c.cobrar_cliente then
            v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
              'tipo', 'ajustar_despesa', 'so_expense_id', v_desp.id, 'os_id', c.destino_os_id, 'os_numero', v_os->>'numero',
              'campo', 'billable_to_client', 'antes', v_desp.billable_to_client, 'depois', c.cobrar_cliente, 'recalcular', true));
            v_billable_final := c.cobrar_cliente;
          elsif v_faturada and not v_desp.billable_to_client and v_desp.cobrar_a_parte is distinct from c.cobrar_cliente then
            v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
              'tipo', 'ajustar_despesa', 'so_expense_id', v_desp.id, 'os_id', c.destino_os_id, 'os_numero', v_os->>'numero',
              'campo', 'cobrar_a_parte', 'antes', v_desp.cobrar_a_parte, 'depois', c.cobrar_cliente, 'recalcular', false));
          elsif v_faturada and v_desp.billable_to_client and not c.cobrar_cliente then
            v_avisos := v_avisos || 'cobranca_da_despesa_nao_muda'::text;
          end if;
        end if;
        -- a despesa já tem conta a pagar (lançada com "também criar conta"): é ela o financeiro
        if v_desp.linked_payable_id is not null then
          select p.id, p.status, p.description into v_link_id, v_link_status, v_link_desc
            from public.payables p where p.id = v_desp.linked_payable_id and p.status <> 'cancelled';
        end if;
      elsif coalesce(cardinality(v_ids), 0) > 1 then
        v_avisos := v_avisos || 'duplicado_ambiguo'::text;
        v_pend := v_pend || 'classificar_no_extrato'::text;
      else
        if v_parecidos > 0 then
          v_avisos := v_avisos || 'parecido_sem_identidade'::text;
        end if;
        v_billable_final := not v_faturada and coalesce(c.cobrar_cliente, false);
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'despesa_os', 'os_id', c.destino_os_id, 'os_numero', v_os->>'numero',
          'billable', not v_faturada and coalesce(c.cobrar_cliente, false),
          'cobrar_a_parte', v_faturada and coalesce(c.cobrar_cliente, false),
          'direto', v_faturada,
          'paid_by', case when v_quem = 'tecnico' then 'technician' else 'company' end,
          'pagador_id', case when v_quem = 'tecnico' then v_pagador end,
          'categoria', coalesce(v_cat, 'Peças e materiais')));
      end if;
      if coalesce(v_billable_final, false) and not v_faturada then
        if coalesce((v_os->>'assinada')::boolean, false) then
          v_avisos := v_avisos || 'os_assinada_pede_nova_assinatura'::text;
        end if;
        -- o total da OS sobe, mas o recebível de saldo/parcelas já emitido não (a tela faz a cascata)
        if exists (select 1 from public.receivables r
                    where r.service_order_id = c.destino_os_id and r.status <> 'cancelled' and not coalesce(r.is_deposit, false))
           or exists (select 1 from public.service_orders so
                       where so.id = c.destino_os_id and coalesce(so.payment_status, 'unpaid') <> 'unpaid') then
          v_avisos := v_avisos || 'recebiveis_nao_mudam'::text;
          v_pend := v_pend || 'ajustar_recebiveis'::text;
        end if;
      end if;
      if v_faturada then
        v_avisos := v_avisos || 'os_faturada_total_nao_muda'::text;
        if coalesce(c.cobrar_cliente, false) then
          v_pend := v_pend || 'cobrar_a_parte'::text;
        end if;
      end if;
    end if;

    -- ── (2) o financeiro ───────────────────────────────────────────────────────────────────
    -- a conta da despesa anexada (ou uma conta em aberto deste fornecedor e valor) é o financeiro:
    -- não se lança outro; fica a baixa (dinheiro) ou a classificação no Extrato (banco)
    if v_link_id is not null and v_quem in ('empresa', 'socio') then
      v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
        'tipo', 'anexar_lancamento', 'payable_id', v_link_id, 'conta', 'CONTA DA DESPESA', 'origem', 'despesa_da_os',
        'valor', v_valor::text, 'data', v_data, 'descricao', left(v_link_desc, 60), 'categoria', v_cat));
      if v_link_status in ('pending', 'overdue', 'partially_paid') then
        v_pend := v_pend || case when v_bancaria then 'classificar_no_extrato' else 'dar_baixa' end;
      end if;
      v_financeiro_feito := true;
    elsif v_quem = 'empresa' and v_forma not in ('credito', 'credito_loja', 'outro') then
      select array_agg(p.id order by p.id) into v_ids
        from public.payables p
        left join public.suppliers s on s.id = p.supplier_id
        left join public.fiscal_notes fn on fn.id = p.fiscal_note_id
       where p.status in ('pending', 'overdue', 'partially_paid') and p.bank_transaction_id is null
         and abs(p.amount - v_valor) <= 0.01
         and (abs(p.issue_date - v_data) <= 5 or abs(p.due_date - v_data) <= 5)
         and not exists (select 1 from public.comprovantes y where y.payable_id = p.id)
         and ((v_sup is not null and p.supplier_id = v_sup)
              or regexp_replace(coalesce(s.cnpj_cpf, ''), '\D', '', 'g') = any (v_docs)
              or regexp_replace(coalesce(fn.issuer_cnpj, ''), '\D', '', 'g') = any (v_docs)
              or public._comprovante_nome_confere(v_nome, coalesce(p.supplier_name, '') || ' ' || coalesce(p.description, '')));
      if coalesce(cardinality(v_ids), 0) = 1 then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'anexar_lancamento', 'payable_id', v_ids[1], 'conta', 'CONTA A PAGAR', 'origem', 'conta_em_aberto',
          'valor', (select p.amount::text from public.payables p where p.id = v_ids[1]),
          'data', (select coalesce(p.due_date, p.issue_date) from public.payables p where p.id = v_ids[1]),
          'descricao', (select left(p.description, 60) from public.payables p where p.id = v_ids[1]),
          'categoria', v_cat));
        v_pend := v_pend || case when v_bancaria then 'classificar_no_extrato' else 'dar_baixa' end;
        v_financeiro_feito := true;
      elsif coalesce(cardinality(v_ids), 0) > 1 then
        v_avisos := v_avisos || 'duplicado_ambiguo'::text;
        v_pend := v_pend || 'classificar_no_extrato'::text;
        v_financeiro_feito := true;
      end if;
    end if;

    if not v_financeiro_feito and v_quem = 'empresa' then
      if v_bancaria then
        -- A: anotar antes do banco (ou usar a anotação que já espera esse dinheiro — do mesmo fornecedor)
        select count(*) into v_parecidos
          from public.anotacoes_do_extrato a
         where a.status = 'aguardando' and a.sentido = 'debit'
           and abs(a.valor - v_valor) <= 0.01 and abs(a.data_prevista - v_data) <= 1
           and not exists (select 1 from public.comprovantes y where y.anotacao_id = a.id);
        select array_agg(a.id order by a.id) into v_ids
          from public.anotacoes_do_extrato a
          left join public.suppliers s on s.id = a.fornecedor_id
         where a.status = 'aguardando' and a.sentido = 'debit'
           and abs(a.valor - v_valor) <= 0.01 and abs(a.data_prevista - v_data) <= 1
           and not exists (select 1 from public.comprovantes y where y.anotacao_id = a.id)
           and ((v_sup is not null and a.fornecedor_id = v_sup)
                or a.documento = any (v_docs)
                or regexp_replace(coalesce(s.cnpj_cpf, ''), '\D', '', 'g') = any (v_docs)
                or public._comprovante_nome_confere(v_nome, coalesce(a.nome, '') || ' ' || coalesce(a.descricao, '')));
        if coalesce(cardinality(v_ids), 0) = 1 then
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'anexar_anotacao', 'anotacao_id', v_ids[1],
            'valor', (select a.valor::text from public.anotacoes_do_extrato a where a.id = v_ids[1]),
            'data', (select a.data_prevista from public.anotacoes_do_extrato a where a.id = v_ids[1]),
            'descricao', (select left(coalesce(nullif(btrim(a.nome), ''), a.descricao), 60) from public.anotacoes_do_extrato a where a.id = v_ids[1]),
            'categoria', (select a.categoria from public.anotacoes_do_extrato a where a.id = v_ids[1])));
        elsif coalesce(cardinality(v_ids), 0) > 1 then
          v_avisos := v_avisos || 'duplicado_ambiguo'::text;
          v_pend := v_pend || 'classificar_no_extrato'::text;
        elsif v_parecidos > 0 then
          -- uma anotação do mesmo valor e data, de outro fornecedor: não anota por cima (a rota
          -- substituiria ou cancelaria a outra); a linha do banco é classificada no Extrato
          v_avisos := v_avisos || 'parecido_sem_identidade'::text;
          v_pend := v_pend || 'classificar_no_extrato'::text;
        else
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'anotar', 'forma', v_forma, 'categoria', v_cat,
            'documento', public._comprovante_documento(c) is not null));
        end if;
      elsif v_forma = 'dinheiro' then
        -- D: saída do Caixa (ou a que já foi lançada — do mesmo fornecedor)
        select count(*) into v_parecidos
          from public.payables p
         where p.payment_method = 'cash' and p.status <> 'cancelled'
           and abs(p.amount - v_valor) <= 0.01 and abs(p.issue_date - v_data) <= 1
           and not exists (select 1 from public.comprovantes y where y.payable_id = p.id);
        select array_agg(p.id order by p.id) into v_ids
          from public.payables p
          left join public.suppliers s on s.id = p.supplier_id
         where p.payment_method = 'cash' and p.status <> 'cancelled'
           and abs(p.amount - v_valor) <= 0.01 and abs(p.issue_date - v_data) <= 1
           and not exists (select 1 from public.comprovantes y where y.payable_id = p.id)
           and ((v_sup is not null and p.supplier_id = v_sup)
                or regexp_replace(coalesce(s.cnpj_cpf, ''), '\D', '', 'g') = any (v_docs)
                or public._comprovante_nome_confere(v_nome, coalesce(p.supplier_name, '') || ' ' || coalesce(p.description, '')));
        if coalesce(cardinality(v_ids), 0) = 1 then
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'anexar_lancamento', 'payable_id', v_ids[1], 'conta', 'CAIXA', 'origem', 'anterior',
            'valor', (select p.amount::text from public.payables p where p.id = v_ids[1]),
            'data', (select p.issue_date from public.payables p where p.id = v_ids[1]),
            'descricao', (select left(p.description, 60) from public.payables p where p.id = v_ids[1]),
            'categoria', v_cat));
        elsif coalesce(cardinality(v_ids), 0) > 1 then
          v_avisos := v_avisos || 'duplicado_ambiguo'::text;
          v_pend := v_pend || 'classificar_no_extrato'::text;
        else
          if v_parecidos > 0 then
            v_avisos := v_avisos || 'parecido_sem_identidade'::text;
          end if;
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'caixa', 'categoria', v_cat));
        end if;
      else
        -- F: crédito (e crédito de loja / outro) espera a fatura
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'aguardar_fatura'));
        if v_forma in ('credito_loja', 'outro') then
          v_pend := v_pend || 'classificar_no_extrato'::text;
        end if;
      end if;

    elsif not v_financeiro_feito and v_quem = 'socio' then
      -- E: do bolso do sócio → reembolso pendente no nome dele
      if v_pagador is null then
        v_avisos := v_avisos || 'sem_socio_cadastrado'::text;
        return jsonb_build_object('efeitos', '[]'::jsonb, 'avisos', to_jsonb(v_avisos), 'situacao_final', null,
                                  'pasta', null, 'falta', jsonb_build_array('quem_pagou'));
      end if;
      select array_agg(p.id order by p.id) into v_ids
        from public.payables p
       where p.payee_id = v_pagador and p.status <> 'cancelled' and p.bank_transaction_id is null
         and p.payment_method is distinct from 'cash'
         and abs(p.amount - v_valor) <= 0.01 and abs(p.issue_date - v_data) <= 1
         and (p.supplier_id is null or v_sup is null or p.supplier_id = v_sup)
         and not exists (select 1 from public.comprovantes y where y.payable_id = p.id);
      if coalesce(cardinality(v_ids), 0) = 1 then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'anexar_lancamento', 'payable_id', v_ids[1],
          'conta', 'BOLSO ' || upper(split_part(public._comprovante_normalizar(v_ef->>'pagador_nome'), ' ', 1)),
          'origem', 'anterior',
          'valor', (select p.amount::text from public.payables p where p.id = v_ids[1]),
          'data', (select p.issue_date from public.payables p where p.id = v_ids[1]),
          'descricao', (select left(p.description, 60) from public.payables p where p.id = v_ids[1]),
          'categoria', v_cat));
      elsif coalesce(cardinality(v_ids), 0) > 1 then
        v_avisos := v_avisos || 'duplicado_ambiguo'::text;
        v_pend := v_pend || 'classificar_no_extrato'::text;
      else
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'reembolso_socio', 'socio_id', v_pagador, 'socio_nome', v_ef->>'pagador_nome', 'categoria', v_cat));
      end if;

    elsif v_quem = 'tecnico' then
      -- G: o acerto do técnico em Diárias é a F2b; por ora nada no financeiro
      v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'tecnico_f2b',
                                                                     'pagador_id', v_pagador, 'pagador_nome', v_ef->>'pagador_nome'));
      v_pend := v_pend || 'acerto_tecnico'::text;
    end if;

    -- K: estoque só pelo XML
    if c.destino = 'estoque' then
      v_pend := v_pend || 'dar_entrada'::text;
    end if;

    if v_cat is not null and not coalesce((v_ef->>'categoria_ativa')::boolean, true) then
      v_avisos := v_avisos || 'categoria_inativa'::text;
    end if;
  end if;

  -- ── (3) pendências, sem repetir, na ordem em que apareceram ─────────────────────────────
  for v_q in select q from unnest(v_pend) with ordinality as t(q, o) group by q order by min(o) loop
    v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'pendencia', 'qual', v_q));
  end loop;

  return jsonb_build_object(
    'efeitos', v_efeitos,
    'avisos', coalesce((select to_jsonb(array_agg(a order by o)) from (
                          select a, min(o) as o from unnest(v_avisos) with ordinality as t(a, o) group by a) u), '[]'::jsonb),
    'situacao_final', v_situacao,
    'pasta', case c.destino when 'os' then 'barco' when 'pessoal' then 'pessoal' else 'mes' end);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. Despesa da OS. OS aberta → so_expense_add (recalcula). Concluída/faturada → INSERT direto não
--    faturável, sem recálculo, com a prova de que grand_total e operational_cost_total não mudaram.
--    Revisão de 11/10/2026: depois do lock da OS, confere de novo se ela foi concluída/faturada entre
--    o resumo e o sim (MFC01 = o resumo mudou; o responder mostra o novo). O fornecedor com a raiz da
--    HBR não vai à despesa.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_despesa_da_os(p_cmp uuid, p_efeito jsonb, p_autor uuid, p_descricao text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_os uuid := (p_efeito->>'os_id')::uuid;
  so record;
  v_id uuid;
  v_r jsonb;
  v_tecnico uuid;
  v_depois record;
  v_faturada boolean;
begin
  select * into c from public.comprovantes x where x.id = p_cmp;
  select s.id, s.status, s.invoicing_status, s.grand_total, s.operational_cost_total into so
    from public.service_orders s where s.id = v_os for update;
  if not found then
    raise exception 'A OS da despesa não existe mais.' using errcode = '22023';
  end if;
  if so.status in ('cancelled', 'draft') then
    raise exception 'A OS % está cancelada ou em rascunho.', p_efeito->>'os_numero' using errcode = '22023';
  end if;
  v_faturada := so.status in ('completed', 'invoiced') or coalesce(so.invoicing_status, 'not_invoiced') <> 'not_invoiced';
  if v_faturada is distinct from coalesce((p_efeito->>'direto')::boolean, false) then
    raise exception 'A OS % mudou (concluída/faturada) desde o resumo.', p_efeito->>'os_numero' using errcode = 'MFC01';
  end if;
  if p_efeito->>'paid_by' = 'technician' and p_efeito->>'pagador_id' is not null then
    select p.app_user_id into v_tecnico from public.payees p where p.id = (p_efeito->>'pagador_id')::uuid;
  end if;

  if not v_faturada then
    v_r := public.so_expense_add(v_os, p_efeito->>'categoria', p_descricao, c.valor_confirmado, c.data_confirmada,
                                 p_efeito->>'paid_by', coalesce((p_efeito->>'billable')::boolean, false),
                                 public._comprovante_fornecedor_efetivo(c, null), c.codigo);
    v_id := (v_r->>'id')::uuid;
    update public.service_order_expenses e
       set created_by = p_autor, technician_user_id = coalesce(v_tecnico, e.technician_user_id)
     where e.id = v_id;
  else
    insert into public.service_order_expenses (
      service_order_id, category, description, amount, expense_date, paid_by, billable_to_client,
      cobrar_a_parte, supplier_id, notes, created_by, technician_user_id
    ) values (
      v_os, p_efeito->>'categoria', p_descricao, c.valor_confirmado, c.data_confirmada, p_efeito->>'paid_by', false,
      coalesce((p_efeito->>'cobrar_a_parte')::boolean, false), public._comprovante_fornecedor_efetivo(c, null), c.codigo,
      p_autor, v_tecnico
    ) returning id into v_id;
    select s.grand_total, s.operational_cost_total into v_depois from public.service_orders s where s.id = v_os;
    if v_depois.grand_total is distinct from so.grand_total
       or v_depois.operational_cost_total is distinct from so.operational_cost_total then
      raise exception 'O total da OS % mudou ao lançar a despesa à parte: nada foi gravado.', p_efeito->>'os_numero';
    end if;
  end if;
  return v_id;
end $$;

-- A despesa anexada passa a seguir o "cobrar ou não" (ajustar_despesa). Faturável ↔ não faturável em
-- OS aberta recalcula (so_recalc_operational_cost, o mesmo da tela); o "cobrar à parte" de OS
-- faturada não mexe no total (prova no fim). Devolve o efeito com o "antes" para o cancelar.
create or replace function public._comprovante_ajustar_despesa(p_efeito jsonb, p_desfazer boolean default false)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id uuid := (p_efeito->>'so_expense_id')::uuid;
  v_campo text := p_efeito->>'campo';
  v_de boolean := case when p_desfazer then (p_efeito->>'depois')::boolean else (p_efeito->>'antes')::boolean end;
  v_para boolean := case when p_desfazer then (p_efeito->>'antes')::boolean else (p_efeito->>'depois')::boolean end;
  e record;
  so record;
  v_depois record;
  v_faturada boolean;
begin
  select x.id, x.service_order_id, x.billable_to_client, x.cobrar_a_parte into e
    from public.service_order_expenses x where x.id = v_id for update;
  if not found then
    return null;          -- a despesa sumiu (tirada pela tela): nada a ajustar
  end if;
  select s.id, s.status, s.invoicing_status, s.grand_total, s.operational_cost_total into so
    from public.service_orders s where s.id = e.service_order_id for update;
  v_faturada := so.status in ('completed', 'invoiced') or coalesce(so.invoicing_status, 'not_invoiced') <> 'not_invoiced';
  if v_campo = 'billable_to_client' then
    if e.billable_to_client is distinct from v_de then
      return null;        -- alguém mudou pela tela: não mexe
    end if;
    if v_faturada then
      raise exception 'A OS % já foi concluída/faturada: a cobrança da despesa não muda por aqui.', p_efeito->>'os_numero'
        using errcode = case when p_desfazer then '22023' else 'MFC01' end;
    end if;
    update public.service_order_expenses x set billable_to_client = v_para where x.id = v_id;
    perform public.so_recalc_operational_cost(e.service_order_id);
  elsif v_campo = 'cobrar_a_parte' then
    if e.cobrar_a_parte is distinct from v_de or e.billable_to_client then
      return null;
    end if;
    update public.service_order_expenses x set cobrar_a_parte = v_para where x.id = v_id;
    select s.grand_total, s.operational_cost_total into v_depois from public.service_orders s where s.id = so.id;
    if v_depois.grand_total is distinct from so.grand_total or v_depois.operational_cost_total is distinct from so.operational_cost_total then
      raise exception 'O total da OS % mudou ao marcar "cobrar à parte": nada foi gravado.', p_efeito->>'os_numero';
    end if;
  else
    raise exception '_comprovante_ajustar_despesa: campo desconhecido' using errcode = '22023';
  end if;
  return jsonb_build_object('tipo', 'ajustar_despesa', 'so_expense_id', v_id, 'os_id', e.service_order_id,
                            'campo', v_campo, 'antes', (p_efeito->>'antes')::boolean, 'depois', (p_efeito->>'depois')::boolean,
                            'recalcular', v_campo = 'billable_to_client');
end $$;

-- NF-e: as linhas da nota SEM OS passam a apontar para a OS. Devolve os item_index (não os ids): o
-- gatilho sync_fiscal_note_items reconstrói as linhas com ids novos a cada reprocessamento da nota
-- (e preserva a OS pelo item_index) — o cancelamento desfaz pelo índice.
create or replace function public._comprovante_ligar_nota(p_nota uuid, p_os uuid)
returns integer[]
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v integer[];
begin
  with u as (
    update public.fiscal_note_items i set service_order_id = p_os
     where i.fiscal_note_id = p_nota and i.service_order_id is null
    returning i.item_index
  )
  select coalesce(array_agg(u.item_index order by u.item_index), '{}') into v from u;
  return v;
end $$;

-- O lançamento anexado (já existente) recebe a categoria e a OS do CMP — só o que difere, por
-- corrigir_lancamento (a rota da tela), guardando o "antes". Mês fechado (ou recusa da rota): só
-- anexa e devolve a mensagem.
create or replace function public._comprovante_corrigir_lancamento(p_payable uuid, p_cat text, p_os uuid, p_codigo text, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_pay record;
  v_campos jsonb := '{}'::jsonb;
  v_corr jsonb := '{}'::jsonb;
  v_t text;
begin
  select p.expense_category, p.linked_service_order_id, p.issue_date, p.status into v_pay
    from public.payables p where p.id = p_payable;
  if not found or v_pay.status = 'cancelled' then
    return jsonb_build_object('corrigido', '{}'::jsonb, 'mensagem', null);
  end if;
  if p_cat is not null and v_pay.expense_category is distinct from p_cat then
    v_campos := v_campos || jsonb_build_object('expense_category', p_cat);
    v_corr := v_corr || jsonb_build_object('expense_category', jsonb_build_object('antes', v_pay.expense_category, 'depois', p_cat));
  end if;
  if p_os is not null and v_pay.linked_service_order_id is distinct from p_os then
    v_campos := v_campos || jsonb_build_object('linked_service_order_id', p_os);
    v_corr := v_corr || jsonb_build_object('linked_service_order_id',
                                           jsonb_build_object('antes', v_pay.linked_service_order_id, 'depois', p_os));
  end if;
  if v_campos = '{}'::jsonb then
    return jsonb_build_object('corrigido', '{}'::jsonb, 'mensagem', null);
  end if;
  begin
    perform public.corrigir_lancamento('payable', p_payable, v_campos, p_codigo, p_autor);
  exception when others then
    get stacked diagnostics v_t = message_text;
    return jsonb_build_object('corrigido', '{}'::jsonb,
      'mensagem', case when public.periodo_esta_fechado(v_pay.issue_date)
                       then 'o mês está fechado: só anexei'
                       else left('não corrigi o lançamento: ' || v_t, 200) end);
  end;
  return jsonb_build_object('corrigido', v_corr, 'mensagem', null);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Gravar (2.6.3). Só depois do sim, só com o hash do plano que o dono viu (MFC01 = mudou).
--    Exceção de rota desfaz tudo (quem chama, comprovante_responder, pega em subtransação).
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_gravar(p_id uuid, p_autor uuid, p_plano_hash text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_plano jsonb;
  v_ef jsonb;
  e jsonb;
  v_cat text;
  v_desc text;
  v_os uuid;
  v_r jsonb;
  v_efeitos jsonb := '[]'::jsonb;
  v_msgs text[] := '{}';
  v_pend text[] := '{}';
  v_so_expense uuid;
  v_so_criada boolean := false;
  v_anotacao uuid;
  v_payable uuid;
  v_nota uuid;
  v_aguardando timestamptz;
  v_idx integer[];
  v_corr jsonb;
  v_t text;
  v_estado text;
  v_doc text;
  v_mes date;
  v_anotou boolean;
begin
  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found then
    raise exception '_comprovante_gravar: comprovante % não existe', p_id using errcode = '22023';
  end if;
  if c.situacao <> 'aguardando_sim' then
    raise exception 'O comprovante % não está esperando o sim.', c.codigo using errcode = '22023';
  end if;
  if p_autor is null or p_autor is distinct from c.dono_id or not public.is_admin(p_autor) then
    raise exception 'Só o dono grava o comprovante.' using errcode = '42501';
  end if;
  v_plano := public._comprovante_plano(c.id);
  if v_plano ? 'falta' then
    raise exception 'Falta responder: %.', array_to_string(array(select jsonb_array_elements_text(v_plano->'falta')), ', ')
      using errcode = '22023';
  end if;
  if md5(v_plano::text) is distinct from p_plano_hash then
    raise exception 'O resumo do % mudou desde que foi mostrado.', c.codigo using errcode = 'MFC01';
  end if;

  v_ef := public._comprovante_efetivo(c);
  v_cat := v_ef->>'categoria';
  v_os := case when c.destino = 'os' then c.destino_os_id end;
  v_desc := left(c.codigo || ' · ' || public._comprovante_tipo_no_texto(c.tipo)
                 || coalesce(' · ' || (public._comprovante_fornecedor(c)->>'nome'), ''), 200);

  for e in select value from jsonb_array_elements(v_plano->'efeitos')
  loop
    case e->>'tipo'
      -- ── OS / nota ──────────────────────────────────────────────────────────────────────
      when 'despesa_os' then
        v_so_expense := public._comprovante_despesa_da_os(c.id, e, p_autor, v_desc);
        v_so_criada := true;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'despesa_os', 'so_expense_id', v_so_expense, 'os_id', e->'os_id', 'os_numero', e->'os_numero',
          'billable', e->'billable', 'cobrar_a_parte', e->'cobrar_a_parte', 'direto', e->'direto', 'paid_by', e->'paid_by'));
      when 'anexar_despesa' then
        v_so_expense := (e->>'so_expense_id')::uuid;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'anexar_despesa', 'so_expense_id', v_so_expense,
                                                                       'os_numero', e->'os_numero'));
      when 'ajustar_despesa' then
        v_r := public._comprovante_ajustar_despesa(e, false);
        if v_r is not null then
          v_efeitos := v_efeitos || jsonb_build_array(v_r || jsonb_build_object('os_numero', e->'os_numero'));
        end if;
      when 'itens_da_nota' then
        v_nota := (e->>'fiscal_note_id')::uuid;
        v_idx := public._comprovante_ligar_nota(v_nota, (e->>'os_id')::uuid);
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'itens_da_nota', 'fiscal_note_id', v_nota, 'os_id', e->'os_id', 'os_numero', e->'os_numero',
          'itens', to_jsonb(v_idx)));
      when 'aguardar_nota' then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'aguardar_nota', 'os_id', e->'os_id'));
      when 'mesma_compra' then
        v_efeitos := v_efeitos || jsonb_build_array(e);

      -- ── financeiro ─────────────────────────────────────────────────────────────────────
      when 'anotar' then
        v_doc := public._comprovante_documento(c);
        v_anotou := true;
        begin
          v_r := public.anotar_transacao('saida', c.valor_confirmado, c.data_confirmada, v_doc,
                                         null, public._comprovante_fornecedor_efetivo(c, v_doc), null, null, v_cat, v_os, v_desc, p_autor);
        exception when others then
          get stacked diagnostics v_t = message_text, v_estado = returned_sqlstate;
          -- o documento contradiz o cadastro (_anotacao_documento_confere): não anota; a linha do
          -- banco é classificada no Extrato. Qualquer outro erro desfaz tudo (o responder mostra).
          if v_estado = 'P0001' and v_t like 'O documento % não é o de %' then
            v_anotou := false;
          else
            raise;
          end if;
        end;
        if not v_anotou then
          v_pend := v_pend || 'classificar_no_extrato'::text;
          v_msgs := v_msgs || 'o documento do comprovante não é o do fornecedor no cadastro: não anotei (fica para classificar no Extrato)'::text;
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'anotacao_recusada'));
        elsif coalesce((v_r->>'ja_lancada')::boolean, false) and v_r->>'tipo' = 'payable' then
          -- A3: a linha do banco já virou lançamento → anexa e corrige só o que difere
          v_payable := (v_r->>'lancamento_id')::uuid;
          v_corr := public._comprovante_corrigir_lancamento(v_payable, v_cat, v_os, c.codigo, p_autor);
          if v_corr->>'mensagem' is not null then
            v_msgs := v_msgs || (v_corr->>'mensagem');
          end if;
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'anexar_lancamento', 'payable_id', v_payable, 'corrigido', v_corr->'corrigido', 'origem', 'anotar'));
        elsif coalesce((v_r->>'ok')::boolean, false) then
          -- A1 (a linha não chegou) ou A2 (estava na fila e saiu classificada; falta aprovar)
          v_anotacao := (v_r->>'id')::uuid;
          v_aguardando := now();
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'anotar', 'anotacao_id', v_anotacao,
            'resultado', case when coalesce((v_r->>'aplicada')::boolean, false) then 'aplicada' else 'aguardando' end));
          if coalesce((v_r->>'falta_quem')::boolean, false) or v_r ? 'outra_contraparte'
             or coalesce((v_r->>'substituidas')::integer, 0) > 0 then
            v_msgs := v_msgs || left(v_r->>'message', 300);
          end if;
        else
          -- ambígua / gêmea / disputa / já anotada: a própria rota cancelou a anotação
          v_pend := v_pend || 'classificar_no_extrato'::text;
          v_msgs := v_msgs || left(coalesce(v_r->>'message', 'a anotação não entrou'), 300);
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'anotacao_recusada'));
        end if;
      when 'anexar_anotacao' then
        v_anotacao := (e->>'anotacao_id')::uuid;
        v_aguardando := now();
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'anexar_anotacao', 'anotacao_id', v_anotacao));
      when 'caixa' then
        v_r := public.lancar_no_caixa('saida', c.valor_confirmado, v_desc, c.data_confirmada, e->>'categoria',
                                      public._comprovante_fornecedor_efetivo(c, null), null, null, v_os, 'caixa', null, p_autor);
        v_payable := (v_r->>'lancamento_id')::uuid;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'caixa', 'payable_id', v_payable));
      when 'reembolso_socio' then
        v_r := public.lancar_no_caixa('saida', c.valor_confirmado, v_desc, c.data_confirmada, e->>'categoria',
                                      public._comprovante_fornecedor_efetivo(c, null), null, null, v_os, 'socio',
                                      (e->>'socio_id')::uuid, p_autor);
        v_payable := (v_r->>'lancamento_id')::uuid;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'reembolso_socio', 'payable_id', v_payable));
      when 'anexar_lancamento' then
        -- o lançamento que já existia recebe a categoria e a OS do CMP (o "antes" fica para o cancelar)
        v_payable := (e->>'payable_id')::uuid;
        v_corr := public._comprovante_corrigir_lancamento(v_payable, e->>'categoria', v_os, c.codigo, p_autor);
        if v_corr->>'mensagem' is not null then
          v_msgs := v_msgs || (v_corr->>'mensagem');
        end if;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'anexar_lancamento', 'payable_id', v_payable, 'corrigido', v_corr->'corrigido', 'origem', e->'origem'));
      when 'aguardar_fatura' then
        v_aguardando := now();
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'aguardar_fatura'));
      when 'nada' then
        if e->>'motivo' = 'nota' then
          v_nota := (e->>'fiscal_note_id')::uuid;
        end if;
        v_efeitos := v_efeitos || jsonb_build_array(e);
      when 'pendencia' then
        v_pend := v_pend || (e->>'qual');
      else
        raise exception '_comprovante_gravar: efeito desconhecido %', e->>'tipo' using errcode = '22023';
    end case;
  end loop;

  -- a despesa da OS aponta para o lançamento (criada agora, ou anexada sem lançamento)
  if v_so_expense is not null and v_payable is not null then
    update public.service_order_expenses s set linked_payable_id = v_payable
     where s.id = v_so_expense and s.linked_payable_id is null;
    if found and not v_so_criada then
      v_efeitos := (select jsonb_agg(case when x->>'tipo' = 'anexar_despesa'
                                          then x || jsonb_build_object('ligou_lancamento', v_payable) else x end
                                     order by o)
                      from jsonb_array_elements(v_efeitos) with ordinality as t(x, o));
    end if;
  end if;

  -- pendências sem repetir, na ordem
  select coalesce(array_agg(q order by o), '{}') into v_pend
    from (select q, min(o) as o from unnest(v_pend) with ordinality as t(q, o) group by q) u;
  for v_t in select unnest(v_pend) loop
    v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'pendencia', 'qual', v_t));
  end loop;

  v_mes := date_trunc('month', c.data_confirmada)::date;
  update public.comprovantes x
     set situacao = v_plano->>'situacao_final',
         gravado_em = now(),
         gravado_por = p_autor,
         plano = v_plano,
         efeitos = v_efeitos,
         pendencias = v_pend,
         passo = null,
         quem_pagou = case when x.destino = 'pessoal' or x.mesma_compra_de is not null then x.quem_pagou else v_ef->>'quem' end,
         pagador_payee_id = coalesce(x.pagador_payee_id, nullif(v_ef->>'pagador_id', '')::uuid),
         categoria = coalesce(x.categoria, v_cat),
         so_expense_id = v_so_expense,
         anotacao_id = v_anotacao,
         payable_id = v_payable,
         fiscal_note_id = coalesce(v_nota, x.fiscal_note_id),
         aguardando_banco_desde = coalesce(v_aguardando, x.aguardando_banco_desde),
         indice_mes = v_mes,
         dropbox_pendente = 'mover',
         dropbox_mover_tentativas = 0,
         dropbox_mover_erro = null,
         -- +3 min: o edge move na hora; o vigia só pega se ele falhar
         dropbox_mover_proxima_em = now() + interval '3 minutes'
   where x.id = c.id;

  insert into public.comprovantes_indice_mensal as i (mes, pendente, proxima_em, atualizado_em)
  values (v_mes, true, now(), now())
  on conflict (mes) do update set pendente = true, proxima_em = now(), atualizado_em = now();

  -- a pasta como o dono a vê, pela MESMA regra do edge (o "gravado" diz onde o arquivo vai de fato)
  v_t := to_char(v_mes, 'YYYY-MM');
  return jsonb_build_object(
    'situacao', v_plano->>'situacao_final',
    'efeitos', v_efeitos,
    'avisos', v_plano->'avisos',
    'mensagens', to_jsonb(v_msgs),
    'mes', v_t,
    'pasta', case v_plano->>'pasta'
               when 'barco' then case when public._comprovante_usa_pasta_do_barco(public._comprovante_os_info(c.destino_os_id))
                                      then (public._comprovante_os_info(c.destino_os_id)->>'barco') || '/1- DOC''s/Compras'
                                      else 'COMPROVANTES/' || left(v_t, 4) || '/' || v_t end
               when 'pessoal' then 'COMPROVANTES/PESSOAL/' || v_t
               else 'COMPROVANTES/' || left(v_t, 4) || '/' || v_t end);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Notas que chegam (2.6.5): CMP aguardando_xml cuja chave já é uma nota confirmada → liga os
--    itens à OS e fica gravado. Igualdade de chave (a conciliação fina com o extrato é a F3).
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_aplicar_notas_chegadas()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r record;
  v_idx integer[];
  v_novo jsonb;
  v_n integer := 0;
begin
  for r in
    select x.id, x.destino, x.destino_os_id, x.indice_mes, fn.id as nota
      from public.comprovantes x
      join public.fiscal_notes fn on fn.nfe_key = x.chave_acesso and fn.status = 'confirmed'
     where x.situacao = 'aguardando_xml'
     order by x.numero
     for update of x skip locked
  loop
    v_novo := '[]'::jsonb;
    if r.destino = 'os' and r.destino_os_id is not null then
      v_idx := public._comprovante_ligar_nota(r.nota, r.destino_os_id);
      v_novo := jsonb_build_array(jsonb_build_object('tipo', 'itens_da_nota', 'fiscal_note_id', r.nota,
                                                     'os_id', r.destino_os_id, 'itens', to_jsonb(v_idx)));
    end if;
    update public.comprovantes x
       set situacao = 'gravado', fiscal_note_id = r.nota, efeitos = x.efeitos || v_novo
     where x.id = r.id;
    if r.indice_mes is not null then
      insert into public.comprovantes_indice_mensal as i (mes, pendente, proxima_em, atualizado_em)
      values (r.indice_mes, true, now(), now())
      on conflict (mes) do update set pendente = true, proxima_em = now(), atualizado_em = now();
    end if;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. comprovante_cancelar (2.6.6): primeiro confere TODOS os bloqueios; com qualquer um, nada
--    muda. Depois desfaz cada efeito (do último para o primeiro), queima o número e manda o
--    arquivo para _CANCELADOS. O original no bucket não é apagado.
--    Revisão de 11/10/2026: o lock do telefone vem ANTES do da linha (a mesma ordem do responder);
--    a anotação é travada na conferência (aplicada no meio = recusa tudo); a despesa não faturável de
--    OS já concluída/faturada sai sem recálculo (o total não muda, com prova); a faturável de OS
--    aberta não sai se o total ficar abaixo do que o cliente já pagou; os itens da nota voltam pelo
--    item_index (o reprocessamento da nota troca os ids).
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_cancelar(p_id uuid, p_motivo text, p_autor uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_phone text;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_texto text;
  v_bloq jsonb := '[]'::jsonb;
  v_desf jsonb := '[]'::jsonb;
  v_avisos text[] := '{}';
  v_copias text[];
  e jsonb;
  v_os jsonb;
  v_status text;
  v_pay record;
  v_atual jsonb;
  v_campos jsonb;
  v_desp record;
  v_so record;
  v_pago numeric;
  k text;
  v_anexou_anotacao boolean := false;
  v_anexou_lancamento boolean := false;
  v_t text;
  v_mes date;
  v_pid uuid;
  v_n integer;
begin
  if v_motivo is null or char_length(regexp_replace(v_motivo, '[^[:alpha:]]', '', 'g')) < 3 or char_length(v_motivo) > 300 then
    raise exception 'comprovante_cancelar: diga o motivo (3 letras ou mais, até 300)' using errcode = '22023';
  end if;
  if p_autor is null or not public.is_admin(p_autor) then
    raise exception 'Só o administrador cancela comprovante.' using errcode = '42501';
  end if;
  select x.phone_normalized into v_phone from public.comprovantes x where x.id = p_id;
  if v_phone is not null then
    perform pg_advisory_xact_lock(hashtextextended('pergunta:' || v_phone, 0));
  end if;
  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found or c.numero is null then
    raise exception 'comprovante_cancelar: comprovante % não existe', p_id using errcode = '22023';
  end if;
  if c.situacao = 'cancelado' then
    return jsonb_build_object('ok', false, 'codigo', c.codigo, 'bloqueios', jsonb_build_array(jsonb_build_object(
      'efeito', 'cmp', 'motivo', 'ja_cancelado', 'como_destravar', null)));
  end if;
  v_texto := left(c.codigo || ' cancelado: ' || v_motivo, 300);

  -- ── 1. bloqueios ────────────────────────────────────────────────────────────────────────
  for e in select value from jsonb_array_elements(c.efeitos) loop
    case e->>'tipo'
      when 'despesa_os' then
        select s.id, s.amount, s.billable_to_client into v_desp
          from public.service_order_expenses s where s.id = (e->>'so_expense_id')::uuid;
        if v_desp.id is not null and not coalesce((e->>'direto')::boolean, false) and v_desp.billable_to_client then
          v_os := public._comprovante_os_info((e->>'os_id')::uuid);
          if coalesce((v_os->>'faturada')::boolean, false) then
            v_bloq := v_bloq || jsonb_build_array(jsonb_build_object('efeito', 'despesa_os', 'motivo', 'os_faturada',
              'como_destravar', 'a ' || (v_os->>'numero') || ' já foi faturada: tire a despesa pela tela da OS e cancele de novo'));
          else
            -- o total não pode ficar abaixo do que o cliente já pagou (a tela confere o mesmo)
            select so.grand_total into v_so from public.service_orders so where so.id = (e->>'os_id')::uuid;
            select coalesce(sum(r.paid_amount), 0) into v_pago
              from public.receivables r where r.service_order_id = (e->>'os_id')::uuid and r.status <> 'cancelled';
            if coalesce(v_so.grand_total, 0) - v_desp.amount < v_pago - 0.005 then
              v_bloq := v_bloq || jsonb_build_array(jsonb_build_object('efeito', 'despesa_os', 'motivo', 'abaixo_do_pago',
                'como_destravar', 'sem a despesa, o total da ' || coalesce(v_os->>'numero', 'OS') || ' fica abaixo do que o cliente já pagou: ajuste pela tela da OS'));
            end if;
          end if;
        end if;
      when 'ajustar_despesa' then
        if coalesce((e->>'recalcular')::boolean, false)
           and exists (select 1 from public.service_order_expenses s where s.id = (e->>'so_expense_id')::uuid) then
          v_os := public._comprovante_os_info((e->>'os_id')::uuid);
          if coalesce((v_os->>'faturada')::boolean, false) then
            v_bloq := v_bloq || jsonb_build_array(jsonb_build_object('efeito', 'ajustar_despesa', 'motivo', 'os_faturada',
              'como_destravar', 'a ' || (v_os->>'numero') || ' já foi faturada: a cobrança da despesa só muda pela tela da OS'));
          end if;
        end if;
      when 'anotar' then
        select a.status into v_status from public.anotacoes_do_extrato a where a.id = (e->>'anotacao_id')::uuid for update;
        if v_status = 'aplicada' then
          v_bloq := v_bloq || jsonb_build_array(jsonb_build_object('efeito', 'anotar', 'motivo', 'anotacao_aplicada',
            'como_destravar', 'a linha do banco já recebeu a classificação; corrija pelo Extrato'));
        end if;
      when 'anexar_lancamento' then
        select p.status, p.issue_date into v_pay from public.payables p where p.id = (e->>'payable_id')::uuid;
        if coalesce(e->'corrigido', '{}'::jsonb) <> '{}'::jsonb and v_pay.status is distinct from 'cancelled'
           and v_pay.issue_date is not null and public.periodo_esta_fechado(v_pay.issue_date) then
          v_bloq := v_bloq || jsonb_build_array(jsonb_build_object('efeito', 'anexar_lancamento', 'motivo', 'mes_fechado',
            'como_destravar', 'reabra o mês em Financeiro › Fechamento e cancele de novo'));
        end if;
      when 'caixa', 'reembolso_socio' then
        select p.status, p.issue_date, p.paid_amount into v_pay from public.payables p where p.id = (e->>'payable_id')::uuid;
        if v_pay.status is distinct from 'cancelled' then
          if e->>'tipo' = 'reembolso_socio' and coalesce(v_pay.paid_amount, 0) > 0 then
            v_bloq := v_bloq || jsonb_build_array(jsonb_build_object('efeito', 'reembolso_socio', 'motivo', 'reembolso_pago',
              'como_destravar', 'o reembolso já foi pago: desfaça o pagamento pela tela e cancele de novo'));
          end if;
          if v_pay.issue_date is not null and public.periodo_esta_fechado(v_pay.issue_date) then
            v_bloq := v_bloq || jsonb_build_array(jsonb_build_object('efeito', e->>'tipo', 'motivo', 'mes_fechado',
              'como_destravar', 'reabra o mês em Financeiro › Fechamento e cancele de novo'));
          end if;
        end if;
      else
        null;
    end case;
  end loop;
  if jsonb_array_length(v_bloq) > 0 then
    return jsonb_build_object('ok', false, 'codigo', c.codigo, 'bloqueios', v_bloq);
  end if;

  -- ── 2. desfaz, do último efeito para o primeiro (rota que falhar desfaz tudo) ────────────
  begin
    for e in select t.x from jsonb_array_elements(c.efeitos) with ordinality as t(x, o) order by t.o desc loop
      case e->>'tipo'
        when 'pendencia' then
          v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', 'pendencia', 'qual', e->'qual'));
        when 'caixa', 'reembolso_socio' then
          v_pid := (e->>'payable_id')::uuid;
          if exists (select 1 from public.payables p where p.id = v_pid and p.status <> 'cancelled') then
            perform public.cancelar_lancamento('payable', v_pid, v_texto, p_autor);
            v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', e->>'tipo', 'payable_id', v_pid));
          end if;
        when 'anexar_lancamento' then
          v_anexou_lancamento := true;
          v_pid := (e->>'payable_id')::uuid;
          v_campos := '{}'::jsonb;
          select to_jsonb(p) into v_atual from public.payables p where p.id = v_pid;
          if v_atual is not null and v_atual->>'status' <> 'cancelled' then
            for k in select jsonb_object_keys(coalesce(e->'corrigido', '{}'::jsonb)) loop
              if coalesce(v_atual->k, 'null'::jsonb) = coalesce(e->'corrigido'->k->'depois', 'null'::jsonb) then
                v_campos := v_campos || jsonb_build_object(k, e->'corrigido'->k->'antes');
              end if;
            end loop;
            if v_campos <> '{}'::jsonb then
              perform public.corrigir_lancamento('payable', v_pid, v_campos, v_texto, p_autor);
            end if;
          end if;
          v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', 'anexar_lancamento', 'payable_id', v_pid,
                                                                   'voltou', v_campos));
        when 'anexar_anotacao' then
          v_anexou_anotacao := true;
          v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', 'anexar_anotacao', 'anotacao_id', e->'anotacao_id'));
        when 'anotar' then
          update public.anotacoes_do_extrato a
             set status = 'cancelada', cancelada_em = now(), motivo_cancelamento = v_texto
           where a.id = (e->>'anotacao_id')::uuid and a.status = 'aguardando';
          if found then
            v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', 'anotar', 'anotacao_id', e->'anotacao_id'));
          elsif exists (select 1 from public.anotacoes_do_extrato a where a.id = (e->>'anotacao_id')::uuid and a.status = 'aplicada') then
            raise exception 'a anotação do % foi aplicada pelo Extrato durante o cancelamento', c.codigo;
          end if;
        when 'itens_da_nota' then
          update public.fiscal_note_items i set service_order_id = null
           where i.fiscal_note_id = (e->>'fiscal_note_id')::uuid
             and i.item_index in (select (jsonb_array_elements_text(coalesce(e->'itens', '[]'::jsonb)))::integer)
             and i.service_order_id = (e->>'os_id')::uuid;
          get diagnostics v_n = row_count;
          if v_n = 0 and jsonb_array_length(coalesce(e->'itens', '[]'::jsonb)) > 0
             and exists (select 1 from public.fiscal_note_items i
                          where i.fiscal_note_id = (e->>'fiscal_note_id')::uuid and i.service_order_id = (e->>'os_id')::uuid) then
            -- a nota foi reimportada com outra numeração dos itens: não adivinha
            raise exception 'os itens da nota mudaram desde o %: desligue-os da OS pela tela da nota', c.codigo;
          end if;
          v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', 'itens_da_nota', 'fiscal_note_id', e->'fiscal_note_id'));
        when 'anexar_despesa' then
          if e ? 'ligou_lancamento' then
            update public.service_order_expenses s set linked_payable_id = null
             where s.id = (e->>'so_expense_id')::uuid and s.linked_payable_id = (e->>'ligou_lancamento')::uuid;
          end if;
          v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', 'anexar_despesa', 'so_expense_id', e->'so_expense_id'));
        when 'ajustar_despesa' then
          if public._comprovante_ajustar_despesa(e, true) is not null then
            v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', 'ajustar_despesa', 'so_expense_id', e->'so_expense_id'));
          end if;
        when 'despesa_os' then
          select s.id, s.billable_to_client into v_desp from public.service_order_expenses s where s.id = (e->>'so_expense_id')::uuid;
          if v_desp.id is not null then
            v_os := public._comprovante_os_info((e->>'os_id')::uuid);
            if coalesce((e->>'direto')::boolean, false)
               or (not v_desp.billable_to_client and coalesce((v_os->>'faturada')::boolean, false)) then
              -- não faturável (e a OS fechada): sai sem recálculo — o total não muda (prova)
              select so.grand_total, so.operational_cost_total into v_so
                from public.service_orders so where so.id = (e->>'os_id')::uuid for update;
              delete from public.service_order_expenses s where s.id = v_desp.id;
              if exists (select 1 from public.service_orders so
                          where so.id = (e->>'os_id')::uuid
                            and (so.grand_total is distinct from v_so.grand_total
                                 or so.operational_cost_total is distinct from v_so.operational_cost_total)) then
                raise exception 'o total da % mudaria ao tirar a despesa', coalesce(v_os->>'numero', 'OS');
              end if;
            else
              perform public.so_expense_remove(v_desp.id);
              if v_desp.billable_to_client and coalesce((v_os->>'assinada')::boolean, false) then
                v_avisos := v_avisos || 'os_assinada_pede_nova_assinatura'::text;
              end if;
            end if;
            v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', 'despesa_os', 'os_id', e->'os_id'));
          end if;
        else
          null;    -- aguardar_nota, aguardar_fatura, mesma_compra, nada, pendencia_resolvida: nada a desfazer
      end case;
    end loop;
  exception when others then
    get stacked diagnostics v_t = message_text;
    return jsonb_build_object('ok', false, 'codigo', c.codigo, 'bloqueios', jsonb_build_array(jsonb_build_object(
      'efeito', 'rota', 'motivo', 'erro_da_rota', 'como_destravar', left(v_t, 200))));
  end;

  -- ── 3. o CMP: número queimado, arquivo para _CANCELADOS, índice do mês refeito ───────────
  v_mes := coalesce(c.indice_mes,
                    date_trunc('month', coalesce(c.data_confirmada, c.data_compra,
                                                 (c.recebido_em at time zone 'America/Sao_Paulo')::date))::date);
  update public.comprovantes x
     set situacao = 'cancelado',
         motivo_cancelamento = 'dono_cancelou',
         cancelado_em = now(),
         cancelado_por = p_autor,
         cancelamento_texto = v_motivo,
         pendencias = '{}',
         passo = null,
         so_expense_id = null,
         anotacao_id = case when v_anexou_anotacao then null else x.anotacao_id end,
         payable_id = case when v_anexou_lancamento then null else x.payable_id end,
         indice_mes = v_mes,
         dropbox_pendente = 'cancelar',
         dropbox_mover_tentativas = 0,
         dropbox_mover_erro = null,
         dropbox_mover_proxima_em = now() + interval '3 minutes'
   where x.id = c.id;
  for v_pid in
    select w.id from public.whatsapp_perguntas w
     where w.phone_normalized = c.phone_normalized and w.status = 'aberta' and w.origem = 'comprovante' and w.referencia_id = c.id
  loop
    perform public._pergunta_fechar(v_pid, 'cancelada', 'cmp_cancelado', null);
  end loop;
  insert into public.comprovantes_indice_mensal as i (mes, pendente, proxima_em, atualizado_em)
  values (v_mes, true, now(), now())
  on conflict (mes) do update set pendente = true, proxima_em = now(), atualizado_em = now();

  -- os CMPs guardados como "a mesma compra" deste continuam (só arquivo): o dono fica sabendo
  select array_agg(y.codigo order by y.numero) into v_copias
    from public.comprovantes y where y.mesma_compra_de = c.id and y.situacao <> 'cancelado';
  if coalesce(cardinality(v_copias), 0) > 0 then
    v_avisos := v_avisos || 'outros_da_mesma_compra'::text;
  end if;

  return jsonb_build_object('ok', true, 'codigo', c.codigo, 'desfeitos', v_desf,
    'avisos', coalesce((select to_jsonb(array_agg(distinct a)) from unnest(v_avisos) a), '[]'::jsonb),
    'mesma_compra', to_jsonb(coalesce(v_copias, '{}'::text[])));
end $$;

-- ---------------------------------------------------------------------------------------------
-- Privilégios (revogar de anon/authenticated POR ASSINATURA; helpers sem grant para ninguém)
-- ---------------------------------------------------------------------------------------------
revoke all on function public._comprovante_documento(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_fornecedor_efetivo(public.comprovantes, text) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_nome_confere(text, text) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_plano(uuid) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_despesa_da_os(uuid, jsonb, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_ajustar_despesa(jsonb, boolean) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_ligar_nota(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_corrigir_lancamento(uuid, text, uuid, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_gravar(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_aplicar_notas_chegadas() from public, anon, authenticated, service_role;
revoke all on function public.comprovante_cancelar(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.comprovante_cancelar(uuid, text, uuid) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
  v_helpers text[] := array[
    'public._comprovante_documento(public.comprovantes)',
    'public._comprovante_fornecedor_efetivo(public.comprovantes, text)',
    'public._comprovante_nome_confere(text, text)',
    'public._comprovante_plano(uuid)',
    'public._comprovante_despesa_da_os(uuid, jsonb, uuid, text)',
    'public._comprovante_ajustar_despesa(jsonb, boolean)',
    'public._comprovante_ligar_nota(uuid, uuid)',
    'public._comprovante_corrigir_lancamento(uuid, text, uuid, text, uuid)',
    'public._comprovante_gravar(uuid, uuid, text)',
    'public._comprovante_aplicar_notas_chegadas()'];
begin
  if has_function_privilege('anon', 'public.comprovante_cancelar(uuid, text, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.comprovante_cancelar(uuid, text, uuid)', 'execute') then
    raise exception 'comprovante_cancelar exposta para anon/authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.comprovante_cancelar(uuid, text, uuid)', 'execute') then
    raise exception 'a edge (service_role) não alcança comprovante_cancelar';
  end if;
  foreach v_f in array v_helpers loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute')
       or has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'helper da gravação dos comprovantes exposto: %', v_f;
    end if;
  end loop;
  if has_column_privilege('anon', 'public.service_order_expenses', 'cobrar_a_parte', 'select') then
    raise exception 'cobrar_a_parte aberta para o anon (o link público mostraria a lembrança de cobrança)';
  end if;
  -- as rotas da despesa da OS continuam como estavam (assinatura, invoker e grants)
  if to_regprocedure('public.so_expense_add(uuid, text, text, numeric, date, text, boolean, uuid, text)') is null
     or to_regprocedure('public.so_expense_remove(uuid)') is null then
    raise exception 'so_expense_add/so_expense_remove mudaram de assinatura';
  end if;
  if (select prosecdef from pg_proc where oid = 'public.so_expense_add(uuid, text, text, numeric, date, text, boolean, uuid, text)'::regprocedure)
     or (select prosecdef from pg_proc where oid = 'public.so_expense_remove(uuid)'::regprocedure) then
    raise exception 'so_expense_add/so_expense_remove viraram security definer';
  end if;
  if has_function_privilege('anon', 'public.so_expense_add(uuid, text, text, numeric, date, text, boolean, uuid, text)', 'execute')
     or has_function_privilege('anon', 'public.so_expense_remove(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.so_expense_add(uuid, text, text, numeric, date, text, boolean, uuid, text)', 'execute')
     or not has_function_privilege('service_role', 'public.so_expense_remove(uuid)', 'execute') then
    raise exception 'grants de so_expense_add/so_expense_remove mudaram';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011203000', 'comprovantes_gravacao')
on conflict do nothing;
