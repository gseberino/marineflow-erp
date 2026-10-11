-- Comprovantes F3 (11/10/2026): gravação e cancelamento da F3 (linha do extrato, débito, reembolso do
-- técnico, nota que chega).
--
-- Redefine (create or replace, corpo da F2 de 20261011202000/20261011203000 IGUAL + só o diff da spec
-- da F3, 3.5):
--   * _comprovante_plano: a avaliação do extrato entra no plano. VERDE → efeito ligar_linha (o SIM do
--     resumo grava e liga); débito deixa de anotar (o "DEBITO DE CARTAO" do C6 chega sem documento: a
--     anotação com o CNPJ da loja nunca casaria — defeito da F2) e espera a linha pela pergunta
--     (aguardar_banco); Pix/boleto com CNPJ e cinza seguem anotando (o SIM do resumo já autorizava
--     "anoto para quando o banco trouxer"); crédito ≠ verde espera a fatura em aguardando_banco; conta a
--     pagar em aberto + forma bancária espera o banco (e casa no SIM se a linha é verde); técnico com
--     diária → reembolso_tecnico nas Diárias (F2b; sem diária, a pendência da F2 com o aviso
--     tecnico_fora_das_diarias); conta em aberto + linha já lançada em outro registro = conflito (não liga;
--     aviso conta_aberta_e_linha_lancada); cupom pago no Pix sem o CNPJ de quem recebeu espera a linha
--     (aguardar_banco; a anotação com o CNPJ da loja nunca casaria); NF-e só com a nota CONFIRMADA (a
--     pendente ainda não tem as linhas: o gatilho sync_fiscal_note_items as cria na confirmação);
--   * _comprovante_gravar: os efeitos ligar_linha, aguardar_banco e reembolso_tecnico (a despesa da OS
--     paga pelo técnico fica "reembolsada pelas Diárias": some da aba Reembolsos, que pagaria o mesmo
--     gasto de novo); guarda a avaliação do plano e devolve "banco":{"nivel","perguntar"};
--   * comprovante_cancelar: desfaz a ligação (a linha volta para a fila do Extrato) e o reembolso (e a
--     despesa da OS volta a "a reembolsar"); bloqueia a linha cujo lançamento não é o que existia ao
--     ligar (o dono aprovou depois) ou casada, reembolso em acerto fechado;
--     a anotação aplicada só bloqueia quando a linha dela já tem lançamento;
--   * _comprovante_mesma_compra: os estados da F3 entram na procura;
--   * _comprovante_resumo: + "banco" (BancoNoResumo);
--   * _comprovante_aplicar_notas_chegadas: o miolo vira _comprovante_nota_aplicar (helper); só a nota
--     confirmada fecha o CMP (a pendente não tem linhas e pode ser desistida);
--   * comprovantes_pendentes: + CMP com pergunta do extrato a fazer e a NF-e que chegou por e-mail.
-- Nova:
--   R5 comprovante_nota_chegou(nota)   a nota CONFIRMADA fecha o CMP que a esperava (para a confirmação
--                                      chamar; hoje quem fecha é o cron, até 2 min depois — o
--                                      process-nfe-xml grava a nota pendente, sem linhas).
--
-- Todas security definer, search_path vazio; helpers sem grant para ninguém. Não escreve dados.
-- Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. O plano: corpo da F2 IGUAL + (F3) a avaliação do extrato antes do financeiro da empresa:
--    (a) a anexação da F2 fica; conta em aberto + forma bancária ou cartão espera o banco e, verde, casa
--        no SIM (a linha verde já lançada em outro registro = conflito: não liga, avisa);
--    (b) verde → ligar_linha (sem anotar/aguardar_fatura); (c) anexar_anotacao da F2; (d) Pix/boleto/
--    transferência com o CNPJ de quem recebeu e cinza → anotar; (e) sem esse CNPJ (o cupom pago no Pix),
--    débito e Pix/boleto azul → aguardar_banco;
--    (f) dinheiro → F2; (g) crédito ≠ verde → aguardar_fatura em aguardando_banco. Técnico com diária →
--    reembolso_tecnico (F2b; a diária vale na data da compra e hoje). NF-e só com a nota confirmada.
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
  -- F3
  v_link_tx uuid;
  v_regra jsonb;
  v_busca boolean := false;
  v_av jsonb;
  v_nivel text;
  v_linha jsonb;
  v_casar jsonb;
  v_diaria boolean;
  v_desp_anexada uuid;
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
  -- F3: a avaliação do extrato (só quem procura linha: a empresa pagou por forma bancária ou crédito)
  v_regra := public._comprovante_banco_regra(c);
  if v_regra is not null and not coalesce((v_regra->>'so_registro')::boolean, false) then
    v_busca := true;
    v_av := public._comprovante_candidatos(c);
    v_nivel := v_av->>'nivel';
    if v_nivel = 'verde' then
      select l into v_linha from jsonb_array_elements(v_av->'linhas') l where (l->>'forte')::boolean limit 1;
    end if;
  end if;

  if v_mesma_id is not null then
    -- a mesma compra de outro CMP: só o arquivo (o outro já lançou)
    v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'mesma_compra', 'cmp', v_mesma_codigo, 'cmp_id', v_mesma_id));

  elsif c.destino = 'pessoal' then
    -- L: só o arquivo em COMPROVANTES/PESSOAL
    v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'pessoal'));

  elsif v_nfe then
    -- I/J: a OS pela linha da nota; a conta é a da importação da nota. Só a nota CONFIRMADA: a pendente
    -- (prévia da importação) ainda não tem linhas — o gatilho sync_fiscal_note_items só as cria quando
    -- confirmed_at é preenchido — e pode ser desistida; o CMP espera o XML e o cron o fecha na confirmação.
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
        v_desp_anexada := v_desp.id;
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
          select p.id, p.status, p.description, p.bank_transaction_id into v_link_id, v_link_status, v_link_desc, v_link_tx
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
        -- F3 (a): a conta em aberto paga por forma bancária OU NO CARTÃO espera a linha (casa no SIM);
        -- no cartão, a pendência é a da linha (a baixa vem pela compra na fatura, não à mão)
        if v_busca and v_quem = 'empresa' and v_link_tx is null and v_av->>'regra' in ('pix', 'boleto', 'debito', 'credito') then
          v_casar := jsonb_build_object('descricao', left(v_link_desc, 60),
                                        'valor', (select round(p.amount, 2)::text from public.payables p where p.id = v_link_id));
          v_pend := v_pend || 'classificar_no_extrato'::text;
        else
          v_pend := v_pend || case when v_bancaria then 'classificar_no_extrato' else 'dar_baixa' end;
        end if;
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
        -- F3 (a): a conta em aberto paga por forma bancária espera a linha do banco (casa no SIM)
        if v_busca and v_av->>'regra' in ('pix', 'boleto', 'debito') then
          v_casar := (select jsonb_build_object('descricao', left(p.description, 60), 'valor', round(p.amount, 2)::text)
                        from public.payables p where p.id = v_ids[1]);
        end if;
      elsif coalesce(cardinality(v_ids), 0) > 1 then
        v_avisos := v_avisos || 'duplicado_ambiguo'::text;
        v_pend := v_pend || 'classificar_no_extrato'::text;
        v_financeiro_feito := true;
      end if;
    end if;

    -- F3 (a): conta em aberto + forma bancária ou cartão: espera o banco; com a linha verde, o SIM casa.
    --   A linha verde que JÁ virou outro lançamento é conflito (o mesmo gasto duas vezes: a conta em
    --   aberto + o lançamento da linha): não liga; o aviso diz e a pergunta do extrato lista a linha com
    --   "cancele uma das duas" (a ação "conflito" nunca é verde).
    if v_casar is not null then
      v_situacao := 'aguardando_banco';
      if v_nivel = 'verde' and v_linha is not null and v_linha->>'acao' = 'anexar' then
        v_avisos := v_avisos || 'conta_aberta_e_linha_lancada'::text;
      elsif v_nivel = 'verde' and v_linha is not null then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'ligar_linha', 'bank_transaction_id', v_linha->>'id', 'nivel', 'verde', 'acao', 'casar',
          'linha', jsonb_build_object('data', v_linha->'data', 'valor', v_linha->'valor', 'descricao', v_linha->'descricao',
                                      'conta', v_linha->'conta', 'cartao', v_linha->'cartao', 'acao', 'casar',
                                      'lancamento', v_linha->'lancamento', 'conta_aberta', v_casar)));
        v_situacao := 'conciliado';
      end if;
    end if;

    if not v_financeiro_feito and v_quem = 'empresa' and v_busca and v_nivel = 'verde' and v_linha is not null then
      -- F3 (b): a linha forte única: o SIM grava e liga (nada de anotar nem de esperar a fatura)
      v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
        'tipo', 'ligar_linha', 'bank_transaction_id', v_linha->>'id', 'nivel', 'verde', 'acao', v_linha->>'acao',
        'linha', jsonb_build_object('data', v_linha->'data', 'valor', v_linha->'valor', 'descricao', v_linha->'descricao',
                                    'conta', v_linha->'conta', 'cartao', v_linha->'cartao', 'acao', v_linha->'acao',
                                    'lancamento', v_linha->'lancamento', 'conta_aberta', null)));
      v_situacao := 'conciliado';
    elsif not v_financeiro_feito and v_quem = 'empresa' then
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
          -- F3 (c): a anotação anexada traz a linha (a varredura liga quando ela for aplicada)
          if v_busca then
            v_situacao := 'aguardando_banco';
          end if;
        elsif coalesce(cardinality(v_ids), 0) > 1 then
          v_avisos := v_avisos || 'duplicado_ambiguo'::text;
          v_pend := v_pend || 'classificar_no_extrato'::text;
        elsif v_busca and (v_forma = 'debito' or v_nivel = 'azul'
                           or c.favorecido_doc is null or public._comprovante_documento(c) is distinct from c.favorecido_doc) then
          -- F3 (e): débito (o C6 manda "DEBITO DE CARTAO" sem documento: a anotação com o CNPJ da
          -- loja nunca casaria), Pix/boleto sem o CNPJ de QUEM RECEBEU (o cupom pago no Pix traz só o
          -- CNPJ do emitente, e o Pix da maquininha vai ao intermediador: a anotação com o CNPJ da loja
          -- também nunca casaria) ou com linhas parecidas: espera a linha e pergunta
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'aguardar_banco', 'regra', v_av->>'regra', 'nivel', v_nivel));
          v_situacao := 'aguardando_banco';
        elsif v_parecidos > 0 then
          -- uma anotação do mesmo valor e data, de outro fornecedor: não anota por cima (a rota
          -- substituiria ou cancelaria a outra); a linha do banco é classificada no Extrato
          v_avisos := v_avisos || 'parecido_sem_identidade'::text;
          v_pend := v_pend || 'classificar_no_extrato'::text;
        else
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'anotar', 'forma', v_forma, 'categoria', v_cat,
            'documento', public._comprovante_documento(c) is not null));
          -- F3 (d): Pix/boleto com CNPJ e cinza: a anotação liga quando o banco trouxer
          if v_busca then
            v_situacao := 'aguardando_banco';
          end if;
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
        -- F3 (g): crédito ≠ verde espera a compra no cartão (pergunta quando aparecer)
        if v_forma = 'credito' and v_busca then
          v_situacao := 'aguardando_banco';
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
      -- F2b: técnico com diária → o reembolso entra na conta corrente dele (no próximo acerto). A diária
      -- tem de valer na data da compra E hoje (o perfil mais recente que começou até a data e não
      -- terminou antes dela, o critério da conta corrente): quem passou para mensal ou empreitada não
      -- tem mais acerto de Diárias — o reembolso ficaria numa conta que ninguém acerta.
      v_diaria := v_pagador is not null
        and exists (select 1 from public.payees pe where pe.id = v_pagador and pe.active)
        and (select wp.modo_pagamento from public.work_profiles wp
              where wp.payee_id = v_pagador and wp.vigencia_inicio <= v_data
                and (wp.vigencia_fim is null or wp.vigencia_fim >= v_data)
              order by wp.vigencia_inicio desc, wp.id desc
              limit 1) is not distinct from 'diaria'
        and (select wp.modo_pagamento from public.work_profiles wp
              where wp.payee_id = v_pagador and wp.vigencia_inicio <= public._hoje_brt()
                and (wp.vigencia_fim is null or wp.vigencia_fim >= public._hoje_brt())
              order by wp.vigencia_inicio desc, wp.id desc
              limit 1) is not distinct from 'diaria';
      if v_diaria and v_desp_anexada is not null
         and exists (select 1 from public.service_order_expenses s
                      where s.id = v_desp_anexada and s.paid_by = 'technician' and coalesce(s.reimbursed, false)) then
        -- a despesa anexada já foi reembolsada a ele (aba Financeiro › Reembolsos): outro crédito nas
        -- Diárias pagaria o mesmo gasto duas vezes
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'ja_reembolsado',
                                                                       'pagador_id', v_pagador, 'pagador_nome', v_ef->>'pagador_nome'));
        v_avisos := v_avisos || 'despesa_ja_reembolsada'::text;
      elsif v_diaria then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'reembolso_tecnico', 'favorecido_id', v_pagador, 'favorecido_nome', v_ef->>'pagador_nome',
          'valor', v_valor::text, 'data', public._comprovante_reembolso_data(v_pagador, v_data),
          'categoria', v_cat, 'os_id', case when c.destino = 'os' then c.destino_os_id end));
      else
        -- G: o técnico sem diária vigente fica fora das Diárias: nada no financeiro, a pendência da F2
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'tecnico_f2b',
                                                                       'pagador_id', v_pagador, 'pagador_nome', v_ef->>'pagador_nome'));
        v_pend := v_pend || 'acerto_tecnico'::text;
        v_avisos := v_avisos || 'tecnico_fora_das_diarias'::text;
      end if;
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
-- 2. Gravar: corpo da F2 IGUAL + (F3) ligar_linha (explica a linha; casa a conta em aberto),
--    aguardar_banco, reembolso_tecnico (F2b; a trava de acerto fechado desfaz tudo, como qualquer rota);
--    guarda a avaliação do plano e devolve "banco":{"nivel","perguntar"}.
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
  -- F3
  v_regra jsonb;
  v_av jsonb;
  v_situacao text;
  v_lig jsonb;
  v_ligada uuid;
  v_explicada boolean := false;
  v_lig_pend text;
  v_reembolso uuid;
  v_desp_reemb uuid;
  v_avisos_f3 text[] := '{}';
  v_perguntar boolean;
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
  -- F3: a avaliação do extrato que o plano mostrou (fica guardada no CMP; o PESSOAL só registra)
  v_regra := public._comprovante_banco_regra(c);
  if v_regra is not null then
    v_av := public._comprovante_candidatos(c);
  end if;
  v_situacao := v_plano->>'situacao_final';

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

      -- ── F3 ─────────────────────────────────────────────────────────────────────────────
      when 'ligar_linha' then
        -- o que já foi gravado neste sim (a conta anexada, a despesa) vale para explicar a linha
        c.payable_id := coalesce(v_payable, c.payable_id);
        c.anotacao_id := coalesce(v_anotacao, c.anotacao_id);
        c.so_expense_id := coalesce(v_so_expense, c.so_expense_id);
        v_lig := public._comprovante_linha_explicar(c, (e->>'bank_transaction_id')::uuid, p_autor, true);
        if v_lig->>'_erro' is not null or jsonb_typeof(v_lig->'_conflito') = 'object' then
          -- a baixa da conta foi recusada (mês fechado…), ou a linha já virou OUTRO lançamento com a
          -- conta do CMP em aberto (conflito): não liga; espera o banco e pergunta depois
          if v_lig->>'_erro' is not null then
            v_msgs := v_msgs || left('não dei baixa na conta a pagar: ' || (v_lig->>'_erro'), 300);
          else
            v_avisos_f3 := v_avisos_f3 || 'conta_aberta_e_linha_lancada'::text;
          end if;
          v_aguardando := now();
          v_situacao := 'aguardando_banco';
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'aguardar_banco', 'regra', v_av->>'regra', 'nivel', 'verde'));
        else
          v_ligada := (e->>'bank_transaction_id')::uuid;
          v_explicada := coalesce((v_lig->>'_explicada')::boolean, false);
          v_lig_pend := v_lig->>'_pendencia';
          v_payable := coalesce((v_lig->>'payable_id')::uuid, v_payable);
          v_anotacao := coalesce(v_anotacao, (v_lig->>'anotacao_id')::uuid);
          if v_lig_pend is not null then
            v_pend := v_pend || v_lig_pend;
          end if;
          if v_lig->>'_aviso' is not null then
            v_avisos_f3 := v_avisos_f3 || (v_lig->>'_aviso');
          end if;
          v_msgs := v_msgs || array(select jsonb_array_elements_text(coalesce(v_lig->'mensagens', '[]'::jsonb)));
          v_efeitos := v_efeitos || jsonb_build_array((v_lig - '_explicada' - '_pendencia' - '_aviso' - '_erro' - '_aplicou' - '_conflito')
                                                      || jsonb_build_object('origem', 'gravacao', 'nivel', 'verde',
                                                                            'como', coalesce(v_lig->>'como', 'classificou')));
        end if;
      when 'aguardar_banco' then
        v_aguardando := now();
        v_efeitos := v_efeitos || jsonb_build_array(e);
      when 'reembolso_tecnico' then
        insert into public.diarias_reembolsos (favorecido_id, data, valor, descricao, origem, origem_codigo, os_id, categoria, criado_por)
        values ((e->>'favorecido_id')::uuid, (e->>'data')::date, c.valor_confirmado,
                left('Reembolso ' || c.codigo || coalesce(' · ' || (public._comprovante_fornecedor(c)->>'nome'), '')
                     || case when (e->>'data')::date <> c.data_confirmada
                             then ' (compra de ' || to_char(c.data_confirmada, 'DD/MM') || ')' else '' end, 200),
                'comprovante', c.codigo, nullif(e->>'os_id', '')::uuid, left(e->>'categoria', 100), p_autor)
        returning id into v_reembolso;
        -- a despesa da OS paga pelo técnico (criada agora ou anexada) é devolvida pelas Diárias: fica
        -- "reembolsada" para a aba Financeiro › Reembolsos não cobrar o mesmo gasto outra vez (pagar
        -- por lá e depois o acerto pagava duas vezes). O cancelamento volta ao "a reembolsar".
        v_desp_reemb := null;
        if v_so_expense is not null then
          update public.service_order_expenses s
             set reimbursed = true, reimbursed_at = now()
           where s.id = v_so_expense and s.paid_by = 'technician' and not coalesce(s.reimbursed, false)
          returning s.id into v_desp_reemb;
        end if;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'reembolso_tecnico', 'reembolso_id', v_reembolso, 'favorecido_id', e->'favorecido_id',
          'favorecido_nome', e->'favorecido_nome', 'data', e->'data', 'valor', e->'valor',
          'despesa_reembolsada', v_desp_reemb));
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

  -- F3: a linha ligada e explicada não precisa mais ser classificada no Extrato
  if v_ligada is not null and v_explicada and v_lig_pend is null then
    v_pend := array_remove(v_pend, 'classificar_no_extrato');
  end if;

  -- pendências sem repetir, na ordem
  select coalesce(array_agg(q order by o), '{}') into v_pend
    from (select q, min(o) as o from unnest(v_pend) with ordinality as t(q, o) group by q) u;
  for v_t in select unnest(v_pend) loop
    v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'pendencia', 'qual', v_t));
  end loop;

  -- F3: a pergunta do extrato a fazer (o edge pergunta logo depois de gravar)
  v_perguntar := v_ligada is null and v_situacao = 'aguardando_banco' and v_av is not null
                 and not coalesce((v_av->>'so_registro')::boolean, false) and v_av->>'nivel' in ('verde', 'azul');

  v_mes := date_trunc('month', c.data_confirmada)::date;
  update public.comprovantes x
     set situacao = v_situacao,
         bank_transaction_id = v_ligada,
         conciliacao = case when v_ligada is not null then 'verde' else v_av->>'nivel' end,
         conciliado_em = case when v_ligada is not null then now() end,
         linha_explicada_em = case when v_ligada is not null and v_explicada then now() end,
         reembolso_id = v_reembolso,
         banco_regra = v_regra->>'regra',
         banco_so_registro = coalesce((v_regra->>'so_registro')::boolean, false),
         banco_candidatos = coalesce(v_av->'linhas', '[]'::jsonb),
         banco_hash = v_av->>'hash',
         banco_avaliado_em = case when v_av is not null then now() end,
         banco_perguntar = v_perguntar,
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
         aguardando_banco_desde = case when v_situacao = 'aguardando_banco' then coalesce(v_aguardando, now())
                                       else coalesce(v_aguardando, x.aguardando_banco_desde) end,
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
    'situacao', v_situacao,
    'efeitos', v_efeitos,
    'avisos', coalesce(v_plano->'avisos', '[]'::jsonb) || to_jsonb(v_avisos_f3),
    'mensagens', to_jsonb(v_msgs),
    'mes', v_t,
    'pasta', case v_plano->>'pasta'
               when 'barco' then case when public._comprovante_usa_pasta_do_barco(public._comprovante_os_info(c.destino_os_id))
                                      then (public._comprovante_os_info(c.destino_os_id)->>'barco') || '/1- DOC''s/Compras'
                                      else 'COMPROVANTES/' || left(v_t, 4) || '/' || v_t end
               when 'pessoal' then 'COMPROVANTES/PESSOAL/' || v_t
               else 'COMPROVANTES/' || left(v_t, 4) || '/' || v_t end,
    'banco', jsonb_build_object('nivel', case when v_ligada is not null then 'verde' else v_av->>'nivel' end,
                                'perguntar', v_perguntar));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. Notas que chegam: o miolo do laço da F2 vira _comprovante_nota_aplicar (o mesmo para a
--    manutenção do cron e para a R5). Só a nota
--    CONFIRMADA conta: a pendente ainda não tem as linhas (o gatilho sync_fiscal_note_items as cria na
--    confirmação) — fechar o CMP com ela deixava a OS sem os itens e o CMP preso a uma nota desistida.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_nota_aplicar(p_cmp uuid, p_nota uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r record;
  v_idx integer[] := '{}';
  v_novo jsonb := '[]'::jsonb;
begin
  select x.id, x.codigo, x.situacao, x.destino, x.destino_os_id, x.indice_mes into r
    from public.comprovantes x where x.id = p_cmp;
  if not found or r.situacao <> 'aguardando_xml' then
    return null;
  end if;
  if r.destino = 'os' and r.destino_os_id is not null then
    v_idx := public._comprovante_ligar_nota(p_nota, r.destino_os_id);
    v_novo := jsonb_build_array(jsonb_build_object('tipo', 'itens_da_nota', 'fiscal_note_id', p_nota,
                                                   'os_id', r.destino_os_id, 'itens', to_jsonb(v_idx)));
  end if;
  update public.comprovantes x
     set situacao = 'gravado', fiscal_note_id = p_nota, efeitos = x.efeitos || v_novo, nota_no_email_em = null
   where x.id = r.id;
  if r.indice_mes is not null then
    insert into public.comprovantes_indice_mensal as i (mes, pendente, proxima_em, atualizado_em)
    values (r.indice_mes, true, now(), now())
    on conflict (mes) do update set pendente = true, proxima_em = now(), atualizado_em = now();
  end if;
  return jsonb_build_object('codigo', r.codigo, 'itens', coalesce(cardinality(v_idx), 0),
                            'os_numero', (select so.service_order_number from public.service_orders so where so.id = r.destino_os_id));
end $$;

create or replace function public._comprovante_aplicar_notas_chegadas()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r record;
  v_n integer := 0;
begin
  for r in
    select x.id, fn.id as nota
      from public.comprovantes x
      join public.fiscal_notes fn on fn.nfe_key = x.chave_acesso and fn.status = 'confirmed'
     where x.situacao = 'aguardando_xml'
     order by x.numero
     for update of x skip locked
  loop
    if public._comprovante_nota_aplicar(r.id, r.nota) is not null then
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $$;

-- R5. comprovante_nota_chegou: a nota foi CONFIRMADA (Entrada de Mercadoria): fecha na hora o CMP que a
--     esperava. Nota inexistente, pendente, cancelada ou com erro → nada. Ninguém a chama hoje (a
--     confirmação é o confirm_nfe_import da tela; o cron fecha em até 2 min): fica para a confirmação.
create or replace function public.comprovante_nota_chegou(p_fiscal_note_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_nota record;
  r record;
  v_r jsonb;
  v_fechados jsonb := '[]'::jsonb;
begin
  select fn.id, fn.nfe_key, fn.status into v_nota from public.fiscal_notes fn where fn.id = p_fiscal_note_id;
  if not found or v_nota.status <> 'confirmed' or v_nota.nfe_key is null then
    return jsonb_build_object('fechados', '[]'::jsonb);
  end if;
  for r in
    select x.id from public.comprovantes x
     where x.situacao = 'aguardando_xml' and x.chave_acesso = v_nota.nfe_key
     order by x.numero
     for update of x skip locked
  loop
    v_r := public._comprovante_nota_aplicar(r.id, v_nota.id);
    if v_r is not null then
      v_fechados := v_fechados || jsonb_build_array(v_r);
    end if;
  end loop;
  return jsonb_build_object('fechados', v_fechados);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4. comprovante_cancelar: corpo da F2 IGUAL + (F3) bloqueios: linha ligada que virou lançamento depois
--    da ligação (linha_lancada) ou casada (linha_casada), anexada com correção em mês fechado
--    (mes_fechado), reembolso em acerto fechado (reembolso_acertado); a anotação aplicada só bloqueia
--    quando a linha dela já tem lançamento. Desfaz: ligar_linha → _comprovante_desligar (a linha volta
--    para a fila do Extrato), reembolso_tecnico → cancelado, anotação aplicada sem lançamento → a
--    proposta volta para o motor; aguardar_banco → nada. banco_perguntar = false.
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
  -- F3
  v_anot_tx uuid;
  v_lanc record;
  v_reemb record;
  v_acerto integer;
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
        select a.status, a.bank_transaction_id into v_status, v_anot_tx
          from public.anotacoes_do_extrato a where a.id = (e->>'anotacao_id')::uuid for update;
        -- F3: só bloqueia quando a linha da anotação já virou lançamento (sem ele, o cancelamento desfaz)
        if v_status = 'aplicada'
           and exists (select 1 from public.payables p where p.bank_transaction_id = v_anot_tx and p.status <> 'cancelled') then
          v_bloq := v_bloq || jsonb_build_array(jsonb_build_object('efeito', 'anotar', 'motivo', 'anotacao_aplicada',
            'como_destravar', 'a linha do banco já recebeu a classificação; corrija pelo Extrato'));
        end if;
      when 'ligar_linha' then
        -- F3: a linha ligada virou lançamento depois da ligação (o dono aprovou no Extrato: a varredura só
        -- ADOTOU o lançamento dele, lancado_depois) ou foi casada: desfaz-se pelo Extrato. Só o lançamento
        -- que já existia quando o CMP ligou (anexado no SIM) se desfaz por aqui.
        if not e ? 'desligado_em' then
          select p.id, p.status, p.issue_date into v_lanc from public.payables p
           where p.bank_transaction_id = (e->>'bank_transaction_id')::uuid and p.status <> 'cancelled'
           order by p.divisao_id nulls first, p.created_at, p.id
           limit 1;
          if v_lanc.id is not null then
            if e->>'como' = 'anexou' and (e->>'payable_id')::uuid = v_lanc.id
               and not coalesce((e->>'lancado_depois')::boolean, false) then
              if coalesce(e->'corrigido', '{}'::jsonb) <> '{}'::jsonb and v_lanc.issue_date is not null
                 and public.periodo_esta_fechado(v_lanc.issue_date) then
                v_bloq := v_bloq || jsonb_build_array(jsonb_build_object('efeito', 'ligar_linha', 'motivo', 'mes_fechado',
                  'como_destravar', 'reabra o mês em Financeiro › Fechamento e cancele de novo'));
              end if;
            else
              v_bloq := v_bloq || jsonb_build_array(jsonb_build_object('efeito', 'ligar_linha',
                'motivo', case when e->>'como' = 'casou' then 'linha_casada' else 'linha_lancada' end,
                'como_destravar', 'a linha do banco de ' || coalesce(to_char((e->'linha'->>'data')::date, 'DD/MM'), '?')
                                  || ' já virou lançamento: desfaça pelo Extrato e cancele de novo'));
            end if;
          end if;
        end if;
      when 'reembolso_tecnico' then
        -- F2b: o reembolso dentro de um acerto já fechado não sai
        v_acerto := null;
        select r.data, r.favorecido_id, r.status into v_reemb
          from public.diarias_reembolsos r where r.id = (e->>'reembolso_id')::uuid;
        if v_reemb.status = 'ativo' then
          select a.numero into v_acerto from public.acertos_diarias a
           where a.favorecido_id = v_reemb.favorecido_id and a.status = 'fechado' and v_reemb.data between a.de and a.ate
           order by a.ate desc limit 1;
          if v_acerto is not null then
            v_bloq := v_bloq || jsonb_build_array(jsonb_build_object('efeito', 'reembolso_tecnico', 'motivo', 'reembolso_acertado',
              'como_destravar', 'reabra o acerto nº ' || lpad(v_acerto::text, 4, '0') || ' em Financeiro › Diárias e cancele de novo'));
          end if;
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
            -- F3: aplicada e a linha ainda sem lançamento: a proposta volta para o motor (como no desligar)
            select a.bank_transaction_id into v_anot_tx from public.anotacoes_do_extrato a where a.id = (e->>'anotacao_id')::uuid;
            if exists (select 1 from public.payables p where p.bank_transaction_id = v_anot_tx and p.status <> 'cancelled') then
              raise exception 'a anotação do % foi aplicada pelo Extrato durante o cancelamento', c.codigo;
            end if;
            update public.finance_review_queue q
               set evidencia = coalesce(q.evidencia, '{}'::jsonb) - 'anotacao' - 'motor',
                   suggested_service_order_id = null,
                   confidence = least(q.confidence, 50),
                   reasoning = left(c.codigo || ' desligado: o motor reclassifica na próxima rodada. · ' || coalesce(q.reasoning, ''), 2000),
                   updated_at = now()
             where q.bank_transaction_id = v_anot_tx and q.status = 'pending'
               and q.evidencia->'anotacao'->>'id' = e->>'anotacao_id';
            update public.anotacoes_do_extrato a
               set status = 'cancelada', cancelada_em = now(), motivo_cancelamento = v_texto
             where a.id = (e->>'anotacao_id')::uuid and a.status = 'aplicada';
            v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', 'anotar', 'anotacao_id', e->'anotacao_id'));
          end if;
        when 'ligar_linha' then
          -- F3: a linha volta para a fila do Extrato (a proposta perde a classificação do CMP)
          if not e ? 'desligado_em'
             and exists (select 1 from public.comprovantes x
                          where x.id = c.id and x.bank_transaction_id = (e->>'bank_transaction_id')::uuid) then
            perform public._comprovante_desligar(c.id, 'cancelado: ' || v_motivo, p_autor, false);
            v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', 'ligar_linha', 'bank_transaction_id', e->'bank_transaction_id'));
          end if;
        when 'reembolso_tecnico' then
          -- F2b: o crédito sai da conta corrente do técnico (a trava recusa se o acerto fechou no meio)
          update public.diarias_reembolsos r
             set status = 'cancelado', cancelado_em = now(), cancelado_por = p_autor, motivo_cancelamento = v_texto
           where r.id = (e->>'reembolso_id')::uuid and r.status = 'ativo';
          if found then
            v_desf := v_desf || jsonb_build_array(jsonb_build_object('tipo', 'reembolso_tecnico', 'reembolso_id', e->'reembolso_id'));
          end if;
          -- a despesa da OS volta a "a reembolsar" (só a que este CMP marcou e nenhum pagamento reembolsou
          -- depois); a criada por este CMP sai em seguida, no despesa_os
          if e->>'despesa_reembolsada' is not null then
            update public.service_order_expenses s
               set reimbursed = false, reimbursed_at = null
             where s.id = (e->>'despesa_reembolsada')::uuid and s.reimbursed and s.reimbursed_payment_id is null;
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
          null;    -- aguardar_nota, aguardar_fatura, aguardar_banco, mesma_compra, nada, pendencia_resolvida: nada a desfazer
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
         banco_perguntar = false,
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
-- 5. A mesma compra: corpo da F2 IGUAL + os estados da F3 (aguardando_banco, conciliado, abandonado) na
--    procura do outro CMP da mesma compra.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_mesma_compra(c public.comprovantes)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r record;
  v_raiz text := public.raiz_do_cnpj_da_empresa();
  v_docs text[];
begin
  if c.valor_confirmado is null or c.data_confirmada is null or c.destino is null or c.destino = 'pessoal' then
    return null;
  end if;
  select array_agg(d) into v_docs
    from unnest(array[c.emitente_cnpj, c.favorecido_doc]) d
   where d ~ '^[0-9]{14}$' and (v_raiz is null or left(d, 8) <> v_raiz);
  select y.id, y.codigo, y.numero, y.valor_confirmado, y.data_confirmada into r
    from public.comprovantes y
   where y.id <> c.id and y.phone_normalized = c.phone_normalized and y.numero is not null
     and y.situacao in ('gravado', 'aguardando_xml', 'aguardando_sim', 'aguardando_banco', 'conciliado', 'abandonado')
     and y.mesma_compra_de is null and y.destino is distinct from 'pessoal'
     and abs(y.valor_confirmado - c.valor_confirmado) <= 0.01
     and abs(y.data_confirmada - c.data_confirmada) <= 1
     and ((c.destino = 'os' and y.destino_os_id = c.destino_os_id)
          or (c.supplier_id is not null and y.supplier_id = c.supplier_id)
          or (coalesce(cardinality(v_docs), 0) > 0 and (y.emitente_cnpj = any (v_docs) or y.favorecido_doc = any (v_docs))))
   order by y.gravado_em desc nulls last, y.numero desc
   limit 1;
  if r.id is null then
    return null;
  end if;
  return jsonb_build_object('id', r.id, 'codigo', r.codigo, 'numero', r.numero,
                            'valor', r.valor_confirmado::text, 'data', r.data_confirmada);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. CmpResumo: corpo da F2 IGUAL + "banco" (BancoNoResumo) no fim.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_resumo(c public.comprovantes)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_forn jsonb := public._comprovante_fornecedor(c);
  v_ef jsonb := public._comprovante_efetivo(c);
  v_os jsonb := public._comprovante_os_info(c.destino_os_id);
  v_raiz text := public.raiz_do_cnpj_da_empresa();
begin
  return jsonb_build_object(
    'id', c.id,
    'codigo', c.codigo,
    'numero', c.numero,
    'situacao', c.situacao,
    'tipo', c.tipo,
    'valor', c.valor_confirmado::text,
    'valor_lido', c.valor::text,
    'valor_confianca', c.valor_confianca,
    'data', coalesce(c.data_confirmada, c.data_compra),
    -- de onde veio a data: lida do documento, o dia do envio (a leitura não trouxe) ou dita pelo dono
    'data_origem', case when c.data_compra is not null and coalesce(c.data_confirmada, c.data_compra) = c.data_compra then 'leitura'
                        when c.data_compra is null
                             and coalesce(c.data_confirmada, (c.recebido_em at time zone 'America/Sao_Paulo')::date)
                                 = (c.recebido_em at time zone 'America/Sao_Paulo')::date then 'envio'
                        else 'dono' end,
    -- quando chegou (o cabeçalho do CMP sem leitura diz "foto das 10h41 de 11/10")
    'recebido_em', c.recebido_em,
    'hora', c.hora_compra::text,
    'forma', c.forma_confirmada,
    'fornecedor', v_forn->>'nome',
    'fornecedor_origem', v_forn->>'origem',
    'cnpj', case when c.emitente_cnpj is not null and (v_raiz is null or left(c.emitente_cnpj, 8) <> v_raiz)
                 then c.emitente_cnpj end,
    'cnpj_confianca', c.cnpj_confianca,
    'destino', c.destino,
    'os', case when v_os is null then null
               else jsonb_build_object('id', v_os->'id', 'numero', v_os->'numero', 'barco', v_os->'barco',
                                       'cliente', v_os->'cliente', 'status', v_os->'status',
                                       'faturada', v_os->'faturada', 'assinada', v_os->'assinada',
                                       'pasta_registrada', v_os->'pasta_registrada') end,
    'cobrar_cliente', c.cobrar_cliente,
    'quem_pagou', v_ef->>'quem',
    'pagador_nome', v_ef->>'pagador_nome',
    'categoria', v_ef->>'categoria',
    'mesma_compra', case when c.mesma_compra_de is not null
                         then (select jsonb_build_object('codigo', y.codigo) from public.comprovantes y where y.id = c.mesma_compra_de) end,
    'pendencias', to_jsonb(c.pendencias),
    'gravado_em', c.gravado_em,
    'banco', public._comprovante_banco_resumo(c));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. comprovantes_pendentes: corpo da F2 IGUAL + o CMP com a pergunta do extrato a fazer ("banco":"perguntar")
--    e a NF-e que chegou por e-mail ("nota_no_email":true), mesmo antes dos 5 dias.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_pendentes(p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_dono record;
  v_abertos jsonb;
  v_antigos integer;
begin
  select d.id, d.phone into v_dono from public._comprovante_dono() d;
  if p_phone is null or v_dono.phone is distinct from p_phone then
    return jsonb_build_object('abertos', '[]'::jsonb, 'total', 0, 'antigos', 0);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', x.codigo,
           'numero', x.numero,
           'data', coalesce(x.data_confirmada, x.data_compra),
           'valor', coalesce(x.valor_confirmado, x.valor)::text,
           'fornecedor', public._comprovante_fornecedor(x)->>'nome',
           'situacao', x.situacao,
           'falta', case when x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
                         then coalesce(nullif(x.passo, 'confirmar'), public._comprovante_proximo_passo(x)) end,
           'pendencias', to_jsonb(x.pendencias),
           'banco', case when x.banco_perguntar and x.situacao in ('aguardando_banco', 'abandonado') then 'perguntar' end,
           'nota_no_email', x.situacao = 'aguardando_xml' and x.nota_no_email_em is not null) order by x.numero), '[]'::jsonb)
    into v_abertos
    from public.comprovantes x
   where x.phone_normalized = p_phone and x.numero is not null
     and (x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
          or (x.gravado_em is not null and x.situacao <> 'cancelado' and cardinality(x.pendencias) > 0)
          or (x.situacao = 'aguardando_xml' and x.gravado_em <= now() - interval '5 days')
          or (x.situacao in ('aguardando_banco', 'abandonado') and x.banco_perguntar and not x.banco_so_registro)
          or (x.situacao = 'aguardando_xml' and x.nota_no_email_em is not null));
  select count(*) into v_antigos from public.comprovantes x
   where x.phone_normalized = p_phone and x.dono_id = v_dono.id and x.modo = 'dono' and x.numero is not null
     and x.situacao in ('lido', 'falhou') and x.fila_desde is null and x.gravado_em is null;
  return jsonb_build_object('abertos', v_abertos, 'total', jsonb_array_length(v_abertos), 'antigos', v_antigos);
end $$;

-- ---------------------------------------------------------------------------------------------
-- Privilégios (revogar de anon/authenticated POR ASSINATURA; helpers sem grant para ninguém)
-- ---------------------------------------------------------------------------------------------
revoke all on function public._comprovante_plano(uuid) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_gravar(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_nota_aplicar(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_aplicar_notas_chegadas() from public, anon, authenticated, service_role;
revoke all on function public._comprovante_mesma_compra(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_resumo(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public.comprovante_cancelar(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.comprovante_nota_chegou(uuid) from public, anon, authenticated;
revoke all on function public.comprovantes_pendentes(text) from public, anon, authenticated;
grant execute on function public.comprovante_cancelar(uuid, text, uuid) to service_role;
grant execute on function public.comprovante_nota_chegou(uuid) to service_role;
grant execute on function public.comprovantes_pendentes(text) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
  v_rpcs text[] := array[
    'public.comprovante_cancelar(uuid, text, uuid)',
    'public.comprovante_nota_chegou(uuid)',
    'public.comprovantes_pendentes(text)'];
  v_helpers text[] := array[
    'public._comprovante_plano(uuid)',
    'public._comprovante_gravar(uuid, uuid, text)',
    'public._comprovante_nota_aplicar(uuid, uuid)',
    'public._comprovante_aplicar_notas_chegadas()',
    'public._comprovante_mesma_compra(public.comprovantes)',
    'public._comprovante_resumo(public.comprovantes)'];
  v_def text;
begin
  foreach v_f in array v_rpcs || v_helpers loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função da gravação da F3 exposta para anon/authenticated: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs loop
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  foreach v_f in array v_helpers loop
    if has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'helper interno da gravação alcançável pela service_role: %', v_f;
    end if;
  end loop;
  -- a gravação conhece os efeitos novos (efeito desconhecido levanta erro e nada é gravado)
  v_def := pg_get_functiondef('public._comprovante_gravar(uuid, uuid, text)'::regprocedure);
  if position('''ligar_linha''' in v_def) = 0 or position('''aguardar_banco''' in v_def) = 0
     or position('''reembolso_tecnico''' in v_def) = 0 then
    raise exception 'a gravação não conhece ligar_linha/aguardar_banco/reembolso_tecnico';
  end if;
  v_def := pg_get_functiondef('public.comprovante_cancelar(uuid, text, uuid)'::regprocedure);
  if position('_comprovante_desligar' in v_def) = 0 or position('reembolso_acertado' in v_def) = 0 then
    raise exception 'o cancelamento não desfaz a ligação nem confere o acerto do reembolso';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011303000', 'comprovantes_gravacao_f3')
on conflict do nothing;