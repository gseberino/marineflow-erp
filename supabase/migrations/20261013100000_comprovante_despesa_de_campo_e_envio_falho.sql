-- Comprovantes (13/10/2026 — spec-ajustes-1310.md, decisões 1 e 4 do dono, "todas como recomendado"):
-- a compra de deslocamento/campo numa OS vira despesa da OS sem a pergunta "peça ou despesa?", e a pergunta
-- automática que não saiu não conta como tentativa.
--
-- 1. Combustível, alimentação de campo e pedágio/estacionamento comprados para uma OS são DESPESA DA OS (custo
--    interno, como o "despesa" de hoje) sem a pergunta "Peça ou material | Despesa da OS?". A marca fica na
--    própria categoria (financial_categories.despesa_de_campo, no padrão da "sensitive"): renomear não quebra,
--    marcar outra é dado, categoria nova nasce sem a marca (pergunta). _comprovante_tipo_na_os diz o tipo que
--    VALE (sem gravar no CMP): o dito pelo dono sempre; sem ele, 'despesa' quando a categoria (a dita, senão a
--    de sempre do fornecedor) está marcada e nada igual está lançado na OS; senão nulo (o passo pergunta). Fora
--    de OS, cliente que pagou direto, "a mesma compra" e NF-e ficam como estão. Quem decide usa a regra: o
--    próximo passo (pula o passo), o plano (cai no despesa_os de sempre) e o resumo (+ tipo_na_os_pela_categoria);
--    a consulta do assistente mostra o mesmo; o comprovante_completar trata o "peça/despesa" dito com a
--    categoria de campo (igual = já estava; diferente = o passo é forçado e respondido). Peça/material e as
--    ambíguas (Hospedagem, Frete, Ferramentas…) continuam perguntando. Nada grava sem o SIM; o dono corrige
--    antes dele pelos caminhos de sempre ("não" → "Peça ou despesa", "corrigir categoria", "corrigir os").
-- 4. comprovante_pergunta_nao_enviada (o whatsapp-send não confirmou): a volta à fila olha a tabela DEPOIS do
--    fechamento, num comando próprio — no mesmo IF do _pergunta_fechar, o not exists lia o retrato de antes,
--    achava a própria pergunta ainda aberta e o CMP ficava "perguntando" sem pergunta (em TODO envio que
--    falha). A pergunta do vigia que não saiu devolve a tentativa (perguntas_automaticas na F2, banco_perguntas
--    na F3) e a F2 espera 4 h (adiado_ate) para tentar de novo; a pergunta que o dono não viu não é a última
--    (ultima_pergunta_em volta à última que saiu). Horário, limite de 3 e espaçamento do vigia não mudam. O
--    dado de antes não é corrigido aqui (o CMP-00001 fica como está).
--
-- Funções: _comprovante_tipo_na_os (nova); _comprovante_proximo_passo, _comprovante_plano, _comprovante_resumo,
-- comprovantes_consultar, comprovante_completar e comprovante_pergunta_nao_enviada (redefinidas). As cópias de
-- corpo são as do arquivo indicado no comentário de cada uma, IGUAIS, mais só o que ele diz.
--
-- Todas security definer, search_path vazio; helpers sem grant para ninguém. Idempotente.
-- Escreve dado: marca 3 categorias (despesa_de_campo).

-- ---------------------------------------------------------------------------------------------
-- 0. A marca na categoria (DDL + DML de 3 linhas)
-- ---------------------------------------------------------------------------------------------
alter table public.financial_categories
  add column if not exists despesa_de_campo boolean not null default false;

comment on column public.financial_categories.despesa_de_campo is
  'Comprovantes (13/10/2026): gasto de deslocamento/campo. Comprado para uma OS, o comprovante vira despesa da OS '
  '(custo interno) sem a pergunta "peça ou despesa?". Marcar outra categoria é decisão do dono.';

update public.financial_categories f
   set despesa_de_campo = true
 where f.type = 'payable' and coalesce(f.active, false) and not f.despesa_de_campo
   and f.name in ('Combustível e deslocamento', 'Alimentação de campo', 'Pedágio e estacionamento');

comment on column public.comprovantes.adiado_ate is
  'F2: "pular"/"deixar para depois", ou a pergunta do vigia que não saiu (4 h) — o vigia não pergunta este CMP antes desta hora.';
comment on column public.comprovantes.perguntas_automaticas is
  'F2: perguntas do vigia sobre este CMP; a que não saiu (envio falhou) é devolvida (13/10/2026). No máximo 3.';

-- ---------------------------------------------------------------------------------------------
-- 1. O tipo na OS que vale. Decisão do dono (13/10/2026): a compra de deslocamento/campo numa OS é despesa da
--    OS sem a pergunta 'peça ou despesa?'. O tipo que vale: o dito pelo dono sempre; sem ele, 'despesa' quando
--    a categoria (a dita, senão a de sempre do fornecedor) está marcada em financial_categories.despesa_de_campo
--    e nada igual está lançado na OS. Senão nulo: o passo pergunta.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_tipo_na_os(c public.comprovantes)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cat text;
begin
  if c.tipo_na_os is not null or c.destino is distinct from 'os' or c.destino_os_id is null
     or c.quem_pagou is not distinct from 'cliente' or c.mesma_compra_de is not null
     or public._comprovante_e_nfe(c) then
    return c.tipo_na_os;
  end if;
  v_cat := coalesce(nullif(btrim(coalesce(c.categoria, '')), ''), public._comprovante_categoria_provavel(c.supplier_id));
  if v_cat is null or not exists (select 1 from public.financial_categories f
                                   where f.name = v_cat and f.type = 'payable' and coalesce(f.active, false)
                                     and f.despesa_de_campo) then
    return null;
  end if;
  -- o lançamento que já está na OS só é comprovado (a ordem do plano: o achado vale com tipo_na_os nulo)
  if public._comprovante_lancamento_na_os(c) is not null then
    return null;
  end if;
  return 'despesa';
end $$;

comment on function public._comprovante_tipo_na_os(public.comprovantes) is
  '13/10/2026: o tipo na OS que vale (peca/despesa/nulo) — o dito pelo dono; sem ele, despesa pela categoria de campo (financial_categories.despesa_de_campo) sem nada igual na OS. Não grava no CMP.';

-- ---------------------------------------------------------------------------------------------
-- 2. O próximo passo: pula o "peça ou despesa da OS?" da compra de campo
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261011202000:632-695 IGUAL + "and public._comprovante_tipo_na_os(c) is null" no passo tipo_na_os
create or replace function public._comprovante_proximo_passo(c public.comprovantes)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_nfe boolean := public._comprovante_e_nfe(c);
  v_ef jsonb;
begin
  if c.valor_confirmado is null then
    return 'valor';
  end if;
  if c.destino is null then
    return 'para_que';
  end if;
  if c.destino = 'os' and c.destino_os_id is null then
    return 'qual_os';
  end if;
  if c.destino = 'pessoal' then
    -- quem pagou: da conta/cartão da empresa (gasto pessoal do sócio) ou do bolso (só o arquivo)
    if c.quem_pagou is null then
      return 'quem_pagou';
    elsif c.quem_pagou = 'empresa' and c.forma_confirmada is null then
      return 'como_pagou';
    end if;
    return 'confirmar';
  end if;
  -- a mesma compra de outro CMP: o dono disse que é → só o arquivo (nada mais a perguntar);
  -- ainda não disse (e não disse que é outra) → pergunta
  if c.mesma_compra_de is not null then
    return 'confirmar';
  end if;
  if not coalesce(c.outra_compra, false) and public._comprovante_mesma_compra(c) is not null then
    return 'mesma_compra';
  end if;
  if c.forma_confirmada is null and not v_nfe then
    return 'como_pagou';
  end if;
  if not v_nfe and c.quem_pagou is null and c.forma_confirmada = 'dinheiro' then
    return 'quem_pagou';
  end if;
  v_ef := public._comprovante_efetivo(c);
  -- sócio sem cadastro (desativado depois da resposta): pergunta de novo
  if v_ef->>'quem' = 'socio' and v_ef->>'pagador_id' is null then
    return 'quem_pagou';
  end if;
  if v_ef->>'quem' = 'tecnico' and c.pagador_payee_id is null and v_ef->>'pagador_id' is null
     and jsonb_array_length(public._comprovante_tecnicos()) >= 2 then
    return 'qual_tecnico';
  end if;
  -- OS: o lançamento que já está nela só é comprovado; sem ele, "peça ou despesa da OS?" — menos a compra de
  -- deslocamento/campo, que já é despesa da OS pela categoria (decisão do dono, 13/10/2026)
  if c.destino = 'os' and c.tipo_na_os is null and v_ef->>'quem' <> 'cliente'
     and public._comprovante_lancamento_na_os(c) is null
     and public._comprovante_tipo_na_os(c) is null then
    return 'tipo_na_os';
  end if;
  if not v_nfe and v_ef->>'quem' <> 'cliente'
     and ((c.destino in ('empresa', 'os') and v_ef->>'categoria' is null)
          or not coalesce((v_ef->>'categoria_ativa')::boolean, true)) then
    return 'categoria';
  end if;
  return 'confirmar';
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. O plano: usa o tipo que vale (sem "falta tipo_na_os"; cai no despesa_os de sempre)
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261011303000:59-639 IGUAL + "c.tipo_na_os := public._comprovante_tipo_na_os(c);" logo depois do
-- "não existe"
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
  -- ajustes do dono (11/10/2026)
  v_na_os jsonb;
  v_extra jsonb;
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
  -- decisão do dono (13/10/2026): a compra de deslocamento/campo numa OS é despesa da OS sem perguntar — o
  -- plano usa o tipo que vale (o dito, senão o da categoria)
  c.tipo_na_os := public._comprovante_tipo_na_os(c);
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
  -- PESSOAL (ajustes do dono, 11/10/2026): quem pagou — da conta/cartão da EMPRESA vira gasto pessoal do
  -- sócio (e então importa como foi pago); do bolso ou do cartão pessoal, só o arquivo
  if c.destino = 'pessoal' and c.quem_pagou is null then
    v_falta := v_falta || 'quem_pagou'::text;
  end if;
  if v_mesma_id is null and c.destino is not null and (c.destino <> 'pessoal' or c.quem_pagou = 'empresa')
     and not v_nfe and c.forma_confirmada is null then
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
  -- OS (ajustes do dono, 11/10/2026): o lançamento que já está na OS só é comprovado; sem ele, o dono diz
  -- se é peça ou despesa da OS (a despesa precisa de categoria; a da NF-e fica com a de peças)
  if c.destino = 'os' and v_mesma_id is null and v_quem is distinct from 'cliente' then
    v_na_os := public._comprovante_lancamento_na_os(c);
    if c.tipo_na_os is null and v_na_os is null then
      v_falta := v_falta || 'tipo_na_os'::text;
    elsif c.tipo_na_os = 'despesa' and v_cat is null and not v_nfe then
      v_falta := v_falta || 'categoria'::text;
    end if;
    if cardinality(v_falta) > 0 then
      return jsonb_build_object('efeitos', '[]'::jsonb, 'avisos', '[]'::jsonb, 'situacao_final', null, 'pasta', null,
                                'falta', to_jsonb(v_falta));
    end if;
  end if;
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
  if v_regra is not null then
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

  elsif c.destino = 'pessoal' and v_quem is distinct from 'empresa' then
    -- L: do bolso ou do cartão pessoal do sócio — só o arquivo em COMPROVANTES/PESSOAL. O PESSOAL que a
    -- conta ou o cartão da EMPRESA pagou segue o bloco geral (sem OS), como gasto pessoal do sócio:
    -- "Gasto Pessoal Sócio - Descontar PL", com o sócio de favorecido (a rotina do pró-labore desconta)
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
    -- O custo da NF-e na OS (ajustes do dono, 11/10/2026): a nota nunca é cobrada do cliente por aqui.
    -- O lançamento que já está na OS só é comprovado; "peça" = as peças entram pela tela da OS
    -- (pendência); "despesa" = custo interno da OS com o valor da nota (fora de qualquer documento do
    -- cliente; o Lucro por OS desconta) — exceto se uma peça da nota já entrou como peça da OS (o custo
    -- dela já está no Lucro).
    if c.destino = 'os' then
      if c.tipo_na_os is null and v_na_os->>'tipo' = 'despesa' then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'anexar_despesa', 'so_expense_id', (v_na_os->>'id')::uuid, 'os_numero', v_os->>'numero',
          'valor', v_na_os->>'valor', 'data', v_na_os->'data', 'descricao', v_na_os->>'descricao',
          'categoria', v_na_os->>'categoria', 'billable',
          (select e.billable_to_client from public.service_order_expenses e where e.id = (v_na_os->>'id')::uuid)));
      elsif c.tipo_na_os is null and v_na_os->>'tipo' = 'peca' then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'anexar_peca', 'so_part_id', (v_na_os->>'id')::uuid, 'os_numero', v_os->>'numero',
          'produto', v_na_os->>'produto', 'valor', v_na_os->>'valor'));
      elsif c.tipo_na_os is null and v_na_os ? 'ambiguo' then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'comprovar_na_os', 'os_id', c.destino_os_id, 'os_numero', v_os->>'numero', 'motivo', 'ambiguo',
          'n', (v_na_os->>'ambiguo')::integer));
        v_avisos := v_avisos || 'varios_na_os'::text;
      elsif c.tipo_na_os = 'peca' then
        v_pend := v_pend || 'incluir_na_os'::text;
      elsif c.tipo_na_os = 'despesa' then
        if v_nota.id is not null and exists (
             select 1 from public.fiscal_note_items i
               join public.service_order_parts sp
                 on sp.service_order_id = c.destino_os_id and sp.product_id = coalesce(i.matched_product_id, i.product_id)
              where i.fiscal_note_id = v_nota.id) then
          v_avisos := v_avisos || 'pecas_da_nota_ja_na_os'::text;
        else
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'despesa_os', 'os_id', c.destino_os_id, 'os_numero', v_os->>'numero',
            'categoria', coalesce(v_cat, 'Peças e materiais'), 'paid_by', 'company', 'pagador_id', null, 'nota', true));
        end if;
      end if;
    end if;

  elsif v_quem = 'cliente' then
    -- H: o cliente pagou direto
    v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object('tipo', 'nada', 'motivo', 'cliente_pagou'));

  else
    -- ── (1) a OS (ajustes do dono, 11/10/2026): o comprovante nunca é cobrado do cliente ─────
    --   o lançamento que já está na OS (despesa ou peça, lançado à mão ou pelo assistente) só é
    --   comprovado: anexa, nada nele muda; dois ou mais iguais: só a prova, sem escolher (aviso). Sem
    --   nenhum, o dono disse: peça → só a prova (a peça entra pela OS: pendência de lançá-la, não lança
    --   custo para não contar duas vezes); despesa → custo INTERNO da OS (não faturável, origem = o CMP,
    --   em qualquer status da OS: o total não muda; fora dos documentos do cliente; entra no Lucro por OS).
    if c.destino = 'os' then
      if c.tipo_na_os is null and v_na_os->>'tipo' = 'despesa' then
        select e.id, e.amount, e.expense_date, e.description, e.billable_to_client, e.linked_payable_id, e.category
          into v_desp from public.service_order_expenses e where e.id = (v_na_os->>'id')::uuid;
        v_desp_anexada := v_desp.id;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'anexar_despesa', 'so_expense_id', v_desp.id, 'os_numero', v_os->>'numero',
          'valor', v_desp.amount::text, 'data', v_desp.expense_date, 'descricao', left(v_desp.description, 60),
          'categoria', v_desp.category, 'billable', v_desp.billable_to_client));
        -- a despesa já tem conta a pagar (lançada com "também criar conta"): é ela o financeiro
        if v_desp.linked_payable_id is not null then
          select p.id, p.status, p.description, p.bank_transaction_id into v_link_id, v_link_status, v_link_desc, v_link_tx
            from public.payables p where p.id = v_desp.linked_payable_id and p.status <> 'cancelled';
        end if;
      elsif c.tipo_na_os is null and v_na_os->>'tipo' = 'peca' then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'anexar_peca', 'so_part_id', (v_na_os->>'id')::uuid, 'os_numero', v_os->>'numero',
          'produto', v_na_os->>'produto', 'valor', v_na_os->>'valor'));
      elsif c.tipo_na_os is null and v_na_os ? 'ambiguo' then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'comprovar_na_os', 'os_id', c.destino_os_id, 'os_numero', v_os->>'numero', 'motivo', 'ambiguo',
          'n', (v_na_os->>'ambiguo')::integer));
        v_avisos := v_avisos || 'varios_na_os'::text;
      elsif c.tipo_na_os = 'peca' then
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'comprovar_na_os', 'os_id', c.destino_os_id, 'os_numero', v_os->>'numero', 'motivo', 'peca'));
        v_pend := v_pend || 'incluir_na_os'::text;
      else
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'despesa_os', 'os_id', c.destino_os_id, 'os_numero', v_os->>'numero', 'categoria', v_cat,
          'paid_by', case when v_quem = 'tecnico' then 'technician' else 'company' end,
          'pagador_id', case when v_quem = 'tecnico' then v_pagador end));
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
      -- a conta a pagar EM ABERTO deste fornecedor e valor (os critérios do ramo da empresa, em qualquer
      -- forma): o sócio pagou do bolso a conta que a empresa ainda deve? Reembolsar o sócio contaria o
      -- gasto duas vezes (a conta do fornecedor + a conta ao sócio) e o fornecedor seguiria "a pagar".
      -- Não lança reembolso: anexa a conta (só uma), deixa "dar baixa" e o aviso — quem pagou essa conta
      -- (e o reembolso dele) o dono resolve pela tela. Vale também para a troca de quem pagou (regra E).
      select array_agg(p.id order by p.id) into v_ids
        from public.payables p
        left join public.suppliers s on s.id = p.supplier_id
        left join public.fiscal_notes fn on fn.id = p.fiscal_note_id
       where p.status in ('pending', 'overdue', 'partially_paid') and p.bank_transaction_id is null
         and p.payee_id is distinct from v_pagador
         and abs(p.amount - v_valor) <= 0.01
         and (abs(p.issue_date - v_data) <= 5 or abs(p.due_date - v_data) <= 5)
         and not exists (select 1 from public.comprovantes y where y.payable_id = p.id)
         and ((v_sup is not null and p.supplier_id = v_sup)
              or regexp_replace(coalesce(s.cnpj_cpf, ''), '\D', '', 'g') = any (v_docs)
              or regexp_replace(coalesce(fn.issuer_cnpj, ''), '\D', '', 'g') = any (v_docs)
              or public._comprovante_nome_confere(v_nome, coalesce(p.supplier_name, '') || ' ' || coalesce(p.description, '')));
      if coalesce(cardinality(v_ids), 0) > 0 then
        if cardinality(v_ids) = 1 then
          v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
            'tipo', 'anexar_lancamento', 'payable_id', v_ids[1], 'conta', 'CONTA A PAGAR', 'origem', 'conta_em_aberto',
            'valor', (select p.amount::text from public.payables p where p.id = v_ids[1]),
            'data', (select coalesce(p.due_date, p.issue_date) from public.payables p where p.id = v_ids[1]),
            'descricao', (select left(p.description, 60) from public.payables p where p.id = v_ids[1]),
            'categoria', v_cat));
        end if;
        v_avisos := v_avisos || 'conta_aberta_paga_pelo_socio'::text;
        v_pend := v_pend || 'dar_baixa'::text;
        v_ids := null;
      else
        select array_agg(p.id order by p.id) into v_ids
          from public.payables p
         where p.payee_id = v_pagador and p.status <> 'cancelled' and p.bank_transaction_id is null
           and p.payment_method is distinct from 'cash'
           and abs(p.amount - v_valor) <= 0.01 and abs(p.issue_date - v_data) <= 1
           and (p.supplier_id is null or v_sup is null or p.supplier_id = v_sup)
           and not exists (select 1 from public.comprovantes y where y.payable_id = p.id);
      end if;
      if 'conta_aberta_paga_pelo_socio' = any (v_avisos) then
        null;
      elsif coalesce(cardinality(v_ids), 0) = 1 then
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
        -- resposta 6 do dono: o "extra" da diária é o almoço (quando o técnico traz o próprio); a
        -- alimentação paga por ele num dia em que já tem o extra avisa no resumo (não bloqueia: o dono decide)
        if v_cat = 'Alimentação de campo' then
          select jsonb_build_object('valor', round(ws.extras, 2)::text, 'data', ws.data) into v_extra
            from public.work_shifts ws
            join public.work_profiles wp on wp.id = ws.work_profile_id
           where wp.payee_id = v_pagador and ws.data = v_data and ws.fracao is not null and ws.extras > 0
           order by ws.extras desc, ws.id
           limit 1;
          if v_extra is not null then
            v_avisos := v_avisos || 'almoco_ja_no_extra'::text;
          end if;
        end if;
        v_efeitos := v_efeitos || jsonb_build_array(jsonb_build_object(
          'tipo', 'reembolso_tecnico', 'favorecido_id', v_pagador, 'favorecido_nome', v_ef->>'pagador_nome',
          'valor', v_valor::text, 'data', public._comprovante_reembolso_data(v_pagador, v_data),
          'categoria', v_cat, 'os_id', case when c.destino = 'os' then c.destino_os_id end,
          'extra_do_dia', v_extra));
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

  -- ── resposta 8 do dono (11/10/2026): o lançamento que já existe só ganha o que está vazio (OS,
  --    categoria); a categoria que ele já tem vai no efeito e, se difere da do CMP, o resumo avisa ──
  v_efeitos := (select coalesce(jsonb_agg(case when e->>'tipo' = 'anexar_lancamento'
                                               then e || jsonb_build_object('categoria_atual',
                                                      (select p.expense_category from public.payables p where p.id = (e->>'payable_id')::uuid))
                                               else e end order by o), '[]'::jsonb)
                  from jsonb_array_elements(v_efeitos) with ordinality as t(e, o));
  if v_cat is not null and exists (
       select 1 from jsonb_array_elements(v_efeitos) e
        where nullif(btrim(coalesce(case when e->>'tipo' = 'anexar_lancamento' then e->>'categoria_atual'
                                         when e->>'tipo' = 'ligar_linha' then e->'linha'->'lancamento'->>'categoria' end, '')), '')
              is not null
          and lower(case when e->>'tipo' = 'anexar_lancamento' then e->>'categoria_atual'
                         else e->'linha'->'lancamento'->>'categoria' end) <> lower(v_cat)) then
    v_avisos := v_avisos || 'categoria_existente_diferente'::text;
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
-- 4. CmpResumo: 'tipo_na_os' = o que vale; + 'tipo_na_os_pela_categoria'
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261012100000:448-505 IGUAL + v_tipo, 'tipo_na_os' = v_tipo e 'tipo_na_os_pela_categoria' logo depois
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
  v_tipo text := public._comprovante_tipo_na_os(c);
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
    -- o tipo que vale (13/10/2026): o dito, senão 'despesa' pela categoria de campo; e se veio da categoria
    'tipo_na_os', v_tipo,
    'tipo_na_os_pela_categoria', c.tipo_na_os is null and v_tipo is not null,
    -- o lançamento que já está na OS (só comprova): {"tipo","id","valor","data","descricao","categoria"|"produto"}
    -- ou {"ambiguo":n}
    'na_os', public._comprovante_lancamento_na_os(c),
    'quem_pagou', v_ef->>'quem',
    'pagador_nome', v_ef->>'pagador_nome',
    'categoria', v_ef->>'categoria',
    'observacao', public._comprovante_obs_sem_cpf(c.observacao),
    'mesma_compra', case when c.mesma_compra_de is not null
                         then (select jsonb_build_object('codigo', y.codigo) from public.comprovantes y where y.id = c.mesma_compra_de) end,
    'pendencias', to_jsonb(c.pendencias),
    'gravado_em', c.gravado_em,
    'banco', public._comprovante_banco_resumo(c));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. comprovantes_consultar (a leitura do assistente): 'tipo_na_os' = o que vale
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261012100000:511-578 IGUAL + 'tipo_na_os', public._comprovante_tipo_na_os(f)
create or replace function public.comprovantes_consultar(p jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_autor uuid;
  v_numero integer;
  v_situacao text;
  v_desde date;
  v_ate date;
  v_os uuid;
  v_valor numeric;
  v_itens jsonb;
  v_total integer;
  v_vazio constant jsonb := jsonb_build_object('itens', '[]'::jsonb, 'total', 0);
begin
  begin
    v_autor := coalesce((select auth.uid()), nullif(p->>'autor', '')::uuid);
    v_numero := coalesce(nullif(p->>'numero', '')::integer,
                         nullif(substring(coalesce(p->>'codigo', '') from '([0-9]+)$'), '')::integer);
    v_situacao := nullif(p->>'situacao', '');
    v_desde := nullif(p->>'desde', '')::date;
    v_ate := nullif(p->>'ate', '')::date;
    v_os := nullif(p->>'os_id', '')::uuid;
    v_valor := nullif(p->>'valor', '')::numeric;
  exception when others then
    return v_vazio;
  end;
  if v_autor is null or not public.is_admin(v_autor) then
    return v_vazio;
  end if;

  with filtrados as (
    select x.id, x.numero
      from public.comprovantes x
     where x.numero is not null and x.modo = 'dono'
       and (v_numero is null or x.numero = v_numero)
       and (v_situacao is null or x.situacao = v_situacao)
       and (v_desde is null or coalesce(x.data_confirmada, x.data_compra, (x.recebido_em at time zone 'America/Sao_Paulo')::date) >= v_desde)
       and (v_ate is null or coalesce(x.data_confirmada, x.data_compra, (x.recebido_em at time zone 'America/Sao_Paulo')::date) <= v_ate)
       and (v_os is null or x.destino_os_id = v_os)
       and (v_valor is null or abs(coalesce(x.valor_confirmado, x.valor) - v_valor) <= 0.01)
  )
  select (select count(*) from filtrados),
         coalesce((select jsonb_agg(jsonb_build_object(
             'codigo', f.codigo,
             'situacao', f.situacao,
             'tipo', f.tipo,
             'valor', coalesce(f.valor_confirmado, f.valor)::text,
             'data', coalesce(f.data_confirmada, f.data_compra),
             'fornecedor', public._comprovante_fornecedor(f)->>'nome',
             'destino', f.destino,
             'os_numero', (select so.service_order_number from public.service_orders so where so.id = f.destino_os_id),
             'tipo_na_os', public._comprovante_tipo_na_os(f),
             'quem_pagou', f.quem_pagou,
             'observacao', public._comprovante_obs_sem_cpf(f.observacao),
             'forma', coalesce(f.forma_confirmada, f.forma_pagamento),
             'pendencias', to_jsonb(f.pendencias),
             'gravado_em', f.gravado_em,
             'dropbox_caminho', f.dropbox_caminho) order by f.numero desc)
            from (select y.id from filtrados y order by y.numero desc limit 20) ids
            join public.comprovantes f on f.id = ids.id), '[]'::jsonb)
    into v_total, v_itens;
  return jsonb_build_object('itens', v_itens, 'total', v_total);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. comprovante_completar: o "peça ou despesa" dito com a categoria de campo (passo 3d)
-- ---------------------------------------------------------------------------------------------
-- corpo de 20261012100000:1277-1635 IGUAL + v_tipo_cat e o passo 3d (depois do 3c, ainda no bloco tudo-ou-nada)
create or replace function public.comprovante_completar(p jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_dono record;
  c public.comprovantes;
  v_phone text;
  v_autor uuid;
  v_num integer;
  v_valor text;
  v_data date;
  v_os integer;
  v_destino text;
  v_tipo_na_os text;
  v_cat text;
  v_forma text;
  v_quem text;
  v_tecnico text;
  v_obs text;
  v_texto text;
  v_destino_antes text;
  v_campo text;
  v_payload jsonb;
  v_r jsonb;
  v_res text;
  v_chamou integer := 0;
  v_aplicados text[] := '{}';
  v_ja text[] := '{}';
  v_itens jsonb := '[]'::jsonb;
  v_pergunta jsonb;
  v_ocupado boolean := false;
  v_ocupado_por text;
  v_recusado jsonb;
  v_parou text;
  v_desconhecido text;
  v_passo text;
  v_interp jsonb;
  v_campo_resp text;
  v_respondidos text[] := '{}';
  v_volta integer := 0;
  v_nome text;
  v_pedidos text[];
  v_ignorados text[];
  v_tipo_cat text;
begin
  -- ── 1. a entrada (malformada = 22023, como as RPCs vizinhas; a edge já conferiu) ─────────────
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'comprovante_completar: a entrada precisa ser um objeto' using errcode = '22023';
  end if;
  v_phone := p->>'phone';
  if v_phone is null or v_phone !~ '^[0-9]{10,15}$' then
    raise exception 'comprovante_completar: telefone inválido' using errcode = '22023';
  end if;
  begin
    v_autor := (p->>'autor')::uuid;
    v_num := (p->>'cmp')::integer;
    v_os := nullif(p->>'os', '')::integer;
  exception when others then
    raise exception 'comprovante_completar: autor, número do CMP ou da OS malformado' using errcode = '22023';
  end;
  if v_autor is null or v_num is null or v_num not between 1 and 999999 then
    raise exception 'comprovante_completar: autor ou número do CMP malformado' using errcode = '22023';
  end if;
  if v_os is not null and v_os not between 1 and 999999 then
    raise exception 'comprovante_completar: número da OS fora da faixa' using errcode = '22023';
  end if;

  v_valor := nullif(p->>'valor', '');
  if v_valor is not null
     and (case when v_valor !~ '^[0-9]{1,10}\.[0-9]{2}$' then true
               else v_valor::numeric <= 0 or v_valor::numeric > 999999.99 end) then
    raise exception 'comprovante_completar: valor malformado' using errcode = '22023';
  end if;

  v_texto := nullif(p->>'data', '');
  if v_texto is not null then
    if v_texto !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'comprovante_completar: data ilegível' using errcode = '22023';
    end if;
    begin
      v_data := v_texto::date;
    exception when others then
      raise exception 'comprovante_completar: data ilegível' using errcode = '22023';
    end;
  end if;

  v_destino := nullif(p->>'destino', '');
  v_tipo_na_os := nullif(p->>'tipo_na_os', '');
  v_forma := nullif(p->>'forma', '');
  v_quem := nullif(p->>'quem_pagou', '');
  if (v_destino is not null and v_destino not in ('os', 'estoque', 'insumo', 'empresa', 'pessoal'))
     or (v_tipo_na_os is not null and v_tipo_na_os not in ('peca', 'despesa'))
     or (v_forma is not null and v_forma not in ('pix', 'debito', 'credito', 'dinheiro', 'boleto', 'transferencia'))
     or (v_quem is not null and v_quem not in ('empresa', 'socio', 'tecnico', 'cliente')) then
    raise exception 'comprovante_completar: valor fora da lista' using errcode = '22023';
  end if;
  -- a OS dita é o destino "os": outro destino junto não combina
  if v_os is not null then
    if v_destino is not null and v_destino <> 'os' then
      raise exception 'comprovante_completar: OS com outro destino' using errcode = '22023';
    end if;
    v_destino := 'os';
  end if;

  -- os textos: uma linha, espaços juntos (vazio = nulo)
  v_cat := nullif(btrim(regexp_replace(coalesce(p->>'categoria', ''), '[[:space:]]+', ' ', 'g')), '');
  v_tecnico := nullif(btrim(regexp_replace(coalesce(p->>'tecnico', ''), '[[:space:]]+', ' ', 'g')), '');
  v_obs := nullif(btrim(regexp_replace(coalesce(p->>'observacao', ''), '[[:space:]]+', ' ', 'g')), '');
  if char_length(v_cat) > 100 or char_length(v_tecnico) > 60 or char_length(v_obs) > 200 then
    raise exception 'comprovante_completar: texto longo demais' using errcode = '22023';
  end if;

  -- o que veio, na ordem (os "ignorados" saem daqui: uma fonte só)
  v_pedidos := array_remove(array[
    case when v_cat is not null then 'categoria' end,
    case when v_os is not null then 'os' end,
    case when v_destino in ('estoque', 'insumo', 'empresa', 'pessoal') then 'para' end,
    case when v_valor is not null then 'valor' end,
    case when v_data is not null then 'data' end,
    case when v_forma is not null then 'forma' end,
    case when v_obs is not null then 'obs' end,
    case when v_quem is not null then 'quem_pagou' end,
    case when v_tecnico is not null then 'tecnico' end,
    case when v_tipo_na_os is not null then 'tipo_na_os' end]::text[], null);

  -- ── 2. as recusas antes de escrever ────────────────────────────────────────────────────────
  if not public._comprovante_conversa_ligada() then
    return jsonb_build_object('resultado', 'desligada');
  end if;
  select d.id, d.phone into v_dono from public._comprovante_dono() d;
  if v_dono.id is distinct from v_autor or v_dono.phone is distinct from v_phone then
    return jsonb_build_object('resultado', 'nao_e_o_dono');
  end if;
  -- a trava do telefone e a linha do CMP ficam do lado de FORA do bloco: o bloco desfeito não as solta
  -- (as RPCs de dentro pegam a mesma trava de novo; a trava de transação é reentrante)
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || v_phone, 0));
  select * into c from public.comprovantes x where x.numero = v_num and x.phone_normalized = v_phone for update;
  if not found or c.modo is distinct from 'dono' then
    return jsonb_build_object('resultado', 'nao_existe');
  end if;
  -- cancelado antes de gravado: um CMP gravado e depois cancelado é "cancelado"
  if c.situacao = 'cancelado' then
    return jsonb_build_object('resultado', 'ja_cancelado', 'codigo', c.codigo);
  end if;
  if c.gravado_em is not null then
    return jsonb_build_object('resultado', 'ja_gravado', 'codigo', c.codigo);
  end if;
  -- ainda sendo lido (na_fila) ou fora da conversa: o reabrir, sem achar ESTE CMP, perguntaria o primeiro
  -- da fila — e o que o dono disse deste responderia o passo de outro
  if c.situacao not in ('lido', 'falhou', 'aguardando_vez', 'perguntando', 'aguardando_sim') then
    return jsonb_build_object('resultado', 'fora_da_conversa', 'codigo', c.codigo);
  end if;
  -- valor diferente do lido (e do já confirmado) exige o porquê: o do pedido ou o já guardado no CMP
  if v_valor is not null and c.valor is not null and abs(v_valor::numeric - c.valor) > 0.01
     and not (c.valor_confirmado is not null and abs(v_valor::numeric - c.valor_confirmado) <= 0.01)
     and v_obs is null and c.observacao is null then
    return jsonb_build_object('resultado', 'observacao_obrigatoria', 'codigo', c.codigo, 'valor_lido', c.valor::text);
  end if;
  if v_data is not null and v_data > (now() at time zone 'America/Sao_Paulo')::date then
    return jsonb_build_object('resultado', 'data_futura', 'codigo', c.codigo);
  end if;
  v_destino_antes := c.destino;

  -- ── 3. tudo ou nada ────────────────────────────────────────────────────────────────────────
  begin
    -- 3a. as correções pelo comando, na ordem fixa (campo igual ao do CMP não vai: nem versão nem
    --     pergunta à toa)
    foreach v_campo in array array['categoria', 'os', 'para', 'valor', 'data', 'forma', 'obs'] loop
      v_payload := null;
      case v_campo
        when 'categoria' then
          if v_cat is not null then
            if public._comprovante_normalizar(v_cat) = public._comprovante_normalizar(c.categoria) then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('categoria', v_cat);
            end if;
          end if;
        when 'os' then
          if v_os is not null then
            v_payload := jsonb_build_object('numero', v_os);
          end if;
        when 'para' then
          if v_destino in ('estoque', 'insumo', 'empresa', 'pessoal') then
            if v_destino = c.destino then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('destino', v_destino);
            end if;
          end if;
        when 'valor' then
          if v_valor is not null then
            if c.valor_confirmado is not null and abs(v_valor::numeric - c.valor_confirmado) <= 0.001 then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('valor', v_valor);
            end if;
          end if;
        when 'data' then
          if v_data is not null then
            if v_data = c.data_confirmada then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('data', to_char(v_data, 'YYYY-MM-DD'));
            end if;
          end if;
        when 'forma' then
          if v_forma is not null then
            if v_forma = c.forma_confirmada then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('forma', v_forma);
            end if;
          end if;
        when 'obs' then
          if v_obs is not null then
            if v_obs = c.observacao then
              v_ja := array_append(v_ja, v_campo);
            else
              v_payload := jsonb_build_object('observacao', v_obs);
            end if;
          end if;
      end case;
      continue when v_payload is null;
      v_chamou := v_chamou + 1;
      v_r := public.comprovante_comando(jsonb_build_object('phone', v_phone, 'message_id', null, 'comando', 'corrigir',
                                                           'cmp', v_num, 'campo', v_campo) || v_payload);
      v_res := v_r->>'resultado';
      if v_res = 'pergunta' then
        v_aplicados := array_append(v_aplicados, v_campo);
        v_itens := v_itens || jsonb_build_array(
          jsonb_build_object('campo', v_campo, 'valor', v_r->'corrigido'->>'valor')
          || case when v_campo = 'valor' then jsonb_build_object('lido', c.valor::text) else '{}'::jsonb end);
        -- a pergunta "não perguntou" vem como JSON null (não SQL null)
        v_pergunta := nullif(v_r->'pergunta', 'null'::jsonb);
        v_ocupado := v_pergunta is null and coalesce(v_r->>'motivo' = 'ocupado', false);
        v_ocupado_por := case when v_pergunta is null then v_r->'ocupado_por'->>'titulo' end;
      elsif v_res = 'invalida' then
        v_recusado := jsonb_build_object('campo', v_campo, 'motivo', v_r->>'motivo', 'passo', null);
        raise exception 'comprovante_completar: recusado' using errcode = 'MFC02';
      else
        -- ja_gravado, ja_cancelado, nao_existe, sem_cmp, desligada: só numa corrida com o próprio dono
        v_parou := coalesce(v_res, 'desconhecido');
        raise exception 'comprovante_completar: parou' using errcode = 'MFC02';
      end if;
    end loop;

    -- 3b. nenhuma correção (tudo igual, ou só passos sem comando): a pergunta do CMP, como o *cmp N* abre
    if v_chamou = 0 then
      v_r := public.comprovante_comando(jsonb_build_object('phone', v_phone, 'message_id', null, 'comando', 'cmp',
                                                           'numero', v_num));
      v_res := v_r->>'resultado';
      if v_res = 'pergunta' then
        v_pergunta := nullif(v_r->'pergunta', 'null'::jsonb);
        v_ocupado := v_pergunta is null and coalesce(v_r->>'motivo' = 'ocupado', false);
        v_ocupado_por := case when v_pergunta is null then v_r->'ocupado_por'->>'titulo' end;
      elsif v_res in ('nao_existe', 'desligada') then
        v_parou := v_res;
        raise exception 'comprovante_completar: parou' using errcode = 'MFC02';
      end if;
    end if;

    -- 3c. os passos sem comando: no máximo 4 voltas; só a pergunta DESTE CMP (o que o dono disse dele
    --     nunca responde o passo de outro); cada passo uma vez; nunca o confirmar nem o mesma_compra
    while v_volta < 4 loop
      v_volta := v_volta + 1;
      exit when v_pergunta is null or (v_pergunta->'cmp'->>'id') is distinct from c.id::text;
      v_passo := v_pergunta->>'passo';
      exit when v_passo = any (v_respondidos);
      v_interp := null;
      v_campo_resp := null;
      if v_passo = 'quem_pagou' and v_quem is not null then
        v_interp := jsonb_build_object('tipo', 'palavra', 'valor', v_quem);
        v_campo_resp := 'quem_pagou';
      elsif v_passo = 'qual_tecnico' and v_tecnico is not null then
        v_interp := jsonb_build_object('tipo', 'nome', 'texto', v_tecnico);
        v_campo_resp := 'tecnico';
      elsif v_passo = 'tipo_na_os' and v_tipo_na_os is not null then
        v_interp := jsonb_build_object('tipo', 'palavra', 'valor', v_tipo_na_os);
        v_campo_resp := 'tipo_na_os';
      elsif v_passo = 'como_pagou' and v_forma is not null then
        v_interp := jsonb_build_object('tipo', 'palavra', 'valor', v_forma);
        v_campo_resp := 'forma';
      elsif v_passo = 'qual_os' and v_os is not null then
        v_interp := jsonb_build_object('tipo', 'os', 'numero', v_os);
        v_campo_resp := 'os';
      end if;
      exit when v_interp is null;
      v_respondidos := array_append(v_respondidos, v_passo);
      v_r := public.comprovante_responder(jsonb_build_object('pergunta_id', v_pergunta->>'pergunta_id', 'message_id', null,
                                                             'interpretacao', v_interp, 'versao', null));
      v_res := v_r->>'resultado';
      if v_res in ('proximo', 'resumo') then
        if not (v_campo_resp = any (v_aplicados)) then
          v_aplicados := array_append(v_aplicados, v_campo_resp);
        end if;
        if v_passo = 'qual_tecnico' then
          -- o nome do técnico vai no item "quem pagou" (o que veio do pedido, ou um novo)
          v_nome := coalesce(v_r->'cmp'->>'pagador_nome', v_tecnico);
          if exists (select 1 from jsonb_array_elements(v_itens) i where i->>'campo' = 'quem_pagou') then
            select jsonb_agg(case when i->>'campo' = 'quem_pagou' then i || jsonb_build_object('nome', v_nome) else i end
                             order by o)
              into v_itens
              from jsonb_array_elements(v_itens) with ordinality as t(i, o);
          else
            v_itens := v_itens || jsonb_build_array(jsonb_build_object('campo', 'quem_pagou', 'valor', 'tecnico', 'nome', v_nome));
          end if;
        elsif v_passo = 'quem_pagou' then
          v_itens := v_itens || jsonb_build_array(jsonb_build_object('campo', 'quem_pagou', 'valor', v_quem));
        elsif v_passo = 'tipo_na_os' then
          v_itens := v_itens || jsonb_build_array(jsonb_build_object('campo', 'tipo_na_os', 'valor', v_tipo_na_os));
        elsif v_passo = 'como_pagou' then
          v_itens := v_itens || jsonb_build_array(jsonb_build_object('campo', 'forma', 'valor', v_forma));
        elsif v_passo = 'qual_os' then
          v_itens := v_itens || jsonb_build_array(jsonb_build_object('campo', 'os', 'valor',
                       coalesce(v_r->'cmp'->'os'->>'numero', 'OS-' || lpad(v_os::text, 5, '0'))));
        end if;
        v_pergunta := nullif(v_r->'proxima', 'null'::jsonb);
        v_ocupado := v_pergunta is null and coalesce(v_r->>'motivo' = 'ocupado', false);
        v_ocupado_por := case when v_pergunta is null then v_r->'ocupado_por'->>'titulo' end;
      elsif v_res = 'invalida' then
        v_recusado := jsonb_build_object('campo', v_campo_resp, 'motivo', v_r->>'motivo', 'passo', v_passo);
        raise exception 'comprovante_completar: recusado' using errcode = 'MFC02';
      elsif v_res = 'ignorada' then
        v_parou := case v_r->>'motivo' when 'cancelado' then 'ja_cancelado' when 'desligada' then 'desligada'
                                        else 'ja_gravado' end;
        raise exception 'comprovante_completar: parou' using errcode = 'MFC02';
      else
        -- resultado que o completar não conhece: para aqui (o que já foi feito fica)
        v_desconhecido := coalesce(v_res, 'nulo');
        exit;
      end if;
    end loop;

    -- 3d. (13/10/2026) peça ou despesa DITA pelo dono quando a categoria de campo pulou o passo: o dito vale.
    --     O mesmo que a categoria já diz = já estava (nada muda). Diferente ("é peça", e a categoria é a do
    --     combustível) = a volta do "corrigir → Peça ou despesa": o passo é forçado e respondido. Só com a
    --     pergunta DESTE CMP na mão; telefone ocupado = o passo forçado espera e o fluxo pergunta depois.
    if v_tipo_na_os is not null and not ('tipo_na_os' = any (v_respondidos)) and v_desconhecido is null then
      select * into c from public.comprovantes x where x.id = c.id;
      v_tipo_cat := case when c.destino = 'os' and c.destino_os_id is not null and c.tipo_na_os is null
                         then public._comprovante_tipo_na_os(c) end;
      if v_tipo_cat = v_tipo_na_os then
        v_ja := array_append(v_ja, 'tipo_na_os');
      elsif v_tipo_cat is not null and v_pergunta is not null and (v_pergunta->'cmp'->>'id') = c.id::text then
        update public.comprovantes x set passo = 'tipo_na_os' where x.id = c.id;
        v_r := public._comprovante_proxima(v_phone, 'reabrir', c.id, null);
        if coalesce((v_r->>'perguntou')::boolean, false) then
          v_r := public.comprovante_responder(jsonb_build_object('pergunta_id', v_r->>'pergunta_id', 'message_id', null,
                   'interpretacao', jsonb_build_object('tipo', 'palavra', 'valor', v_tipo_na_os), 'versao', null));
          v_res := v_r->>'resultado';
          if v_res in ('proximo', 'resumo') then
            v_aplicados := array_append(v_aplicados, 'tipo_na_os');
            v_itens := v_itens || jsonb_build_array(jsonb_build_object('campo', 'tipo_na_os', 'valor', v_tipo_na_os));
            v_pergunta := nullif(v_r->'proxima', 'null'::jsonb);
            v_ocupado := v_pergunta is null and coalesce(v_r->>'motivo' = 'ocupado', false);
            v_ocupado_por := case when v_pergunta is null then v_r->'ocupado_por'->>'titulo' end;
          elsif v_res = 'invalida' then
            v_recusado := jsonb_build_object('campo', 'tipo_na_os', 'motivo', v_r->>'motivo', 'passo', 'tipo_na_os');
            raise exception 'comprovante_completar: recusado' using errcode = 'MFC02';
          else
            v_parou := case v_r->>'motivo' when 'cancelado' then 'ja_cancelado' when 'desligada' then 'desligada'
                                            else 'ja_gravado' end;
            raise exception 'comprovante_completar: parou' using errcode = 'MFC02';
          end if;
        else
          v_pergunta := null;
          v_ocupado := coalesce(v_r->>'motivo' = 'ocupado', false);
          v_ocupado_por := v_r->'ocupado_por'->>'titulo';
        end if;
      elsif v_tipo_cat is not null and not exists (select 1 from public.whatsapp_perguntas y
                                                    where y.referencia_id = c.id and y.status = 'aberta'
                                                      and y.origem = 'comprovante') then
        -- (revisão de 13/10/2026) sem a pergunta DESTE CMP na mão (o telefone já estava ocupado por uma
        -- pendência do assistente): o passo forçado espera e o fluxo pergunta "peça ou despesa?" na vez dele.
        -- Sem isso a categoria pularia o passo e o "peça" dito se perderia (o "ignorado" promete a pergunta).
        update public.comprovantes x set passo = 'tipo_na_os' where x.id = c.id;
      end if;
    end if;
  exception when sqlstate 'MFC02' then
    -- o bloco foi desfeito inteiro (correções, perguntas abertas e fechadas): a pergunta de antes segue
    -- aberta. As variáveis guardam o que foi visto (só o banco volta).
    v_ignorados := array_remove(v_pedidos, v_recusado->>'campo');
    return jsonb_build_object('resultado', coalesce(v_parou, 'recusado'), 'id', c.id, 'codigo', c.codigo,
      'valor_lido', c.valor::text, 'aplicados', '[]'::jsonb, 'ja_estava', to_jsonb(v_ja),
      'ignorados', to_jsonb(v_ignorados), 'itens', '[]'::jsonb, 'recusado', v_recusado, 'pergunta', null,
      'ocupado', false, 'ocupado_por', null, 'desconhecido', null);
  end;

  -- ── 4. o que veio e não foi usado (o passo não chegou, ou parou antes) ──────────────────────
  select coalesce(array_agg(x order by o), '{}'::text[]) into v_ignorados
    from unnest(v_pedidos) with ordinality as t(x, o)
   where not (x = any (v_aplicados)) and not (x = any (v_ja));
  -- "foi para uma OS" sem dizer qual: o menu do "para quê" já lista as OS
  if v_destino = 'os' and v_os is null and v_destino_antes is distinct from 'os' then
    v_ignorados := array_append(v_ignorados, 'destino');
  end if;
  return jsonb_build_object('resultado', 'ok', 'id', c.id, 'codigo', c.codigo, 'valor_lido', c.valor::text,
    'aplicados', to_jsonb(v_aplicados), 'ja_estava', to_jsonb(v_ja), 'ignorados', to_jsonb(v_ignorados),
    'itens', v_itens, 'recusado', null, 'pergunta', v_pergunta, 'ocupado', v_ocupado,
    'ocupado_por', v_ocupado_por, 'desconhecido', v_desconhecido);
end $$;

comment on function public.comprovante_completar(jsonb) is
  'B (12/10/2026): o que o dono disse em conversa, pelo assistente (ação completar da edge), numa transação só: '
  'recusas antes de escrever; depois comprovante_comando (categoria, os, para, valor, data, forma, obs) e '
  'comprovante_responder (passos sem comando, message_id nulo) num bloco que desfaz tudo na primeira recusa '
  '(MFC02). Devolve a última pergunta para a edge mandar. Nunca grava no financeiro. 13/10/2026: peça '
  'ou despesa dita com a categoria de campo — igual = já estava; diferente = o passo é forçado e respondido '
  '(telefone ocupado: forçado, pergunta na vez dele).';

-- ---------------------------------------------------------------------------------------------
-- 7. comprovante_pergunta_nao_enviada: o whatsapp-send não confirmou. A pergunta fecha (cancelada,
--    nao_enviada) e o CMP volta para a fila. 13/10/2026 (decisão do dono): a pergunta automática que não saiu
--    não é tentativa — a do vigia devolve perguntas_automaticas (F2) ou banco_perguntas (F3) e a F2 espera
--    4 h (adiado_ate) para tentar de novo; a pergunta que o dono não viu não é a última (ultima_pergunta_em
--    volta à última que saiu). A volta à fila olha a tabela DEPOIS do fechamento, num comando próprio: no
--    mesmo IF do _pergunta_fechar, o not exists usava o retrato de antes dele, achava a própria pergunta
--    ainda aberta e o CMP ficava "perguntando" sem pergunta (CMP-00001, 13/10 08:00).
--    (corpo novo; o de antes é 20261011202000:1391-1413)
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_pergunta_nao_enviada(p_pergunta_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  w record;
  v_vigia boolean;
begin
  select x.phone_normalized, x.origem into w
    from public.whatsapp_perguntas x where x.id = p_pergunta_id;
  if not found or w.origem <> 'comprovante' then
    return;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || w.phone_normalized, 0));
  -- relê DEPOIS da trava: se outra transação já a fechou (o "cmp 124" no meio), nada aqui
  select x.id, x.referencia_id, x.status, x.passo, x.enviada_em, x.dados->>'motivo' as motivo into w
    from public.whatsapp_perguntas x where x.id = p_pergunta_id;
  if w.status is distinct from 'aberta' or not public._pergunta_fechar(w.id, 'cancelada', 'nao_enviada', null) then
    return;
  end if;
  -- a volta à fila num comando próprio: já vê a pergunta fechada logo acima
  if not exists (select 1 from public.whatsapp_perguntas y
                  where y.referencia_id = w.referencia_id and y.status = 'aberta' and y.origem = 'comprovante') then
    perform public._comprovante_pergunta_saiu(w.referencia_id);
  end if;
  -- a do vigia que não saiu não é tentativa (a que já tinha saído — enviada_em — conta)
  v_vigia := w.motivo = 'vigia' and w.enviada_em is null;
  if w.passo in ('banco', 'banco_quem') then
    if v_vigia then
      update public.comprovantes x set banco_perguntas = greatest(x.banco_perguntas - 1, 0) where x.id = w.referencia_id;
    end if;
  else
    update public.comprovantes x
       set ultima_pergunta_em = (select max(y.aberta_em) from public.whatsapp_perguntas y
                                  where y.referencia_id = x.id and y.origem = 'comprovante' and y.enviada_em is not null
                                    and y.passo is distinct from 'banco' and y.passo is distinct from 'banco_quem'),
           perguntas_automaticas = case when v_vigia then greatest(x.perguntas_automaticas - 1, 0)
                                        else x.perguntas_automaticas end,
           adiado_ate = case when v_vigia then greatest(coalesce(x.adiado_ate, now()), now() + interval '4 hours')
                             else x.adiado_ate end
     where x.id = w.referencia_id and x.gravado_em is null;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. Privilégios (revogar POR ASSINATURA; helpers sem grant para ninguém; RPCs só service_role; a leitura do
--    assistente também authenticated, como em 20261012100000). O create or replace mantém a ACL; aqui ela é
--    reafirmada.
-- ---------------------------------------------------------------------------------------------
revoke all on function public._comprovante_tipo_na_os(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_proximo_passo(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_plano(uuid) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_resumo(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public.comprovantes_consultar(jsonb) from public, anon, authenticated;
revoke all on function public.comprovante_completar(jsonb) from public, anon, authenticated;
revoke all on function public.comprovante_pergunta_nao_enviada(uuid) from public, anon, authenticated;
grant execute on function public.comprovantes_consultar(jsonb) to authenticated, service_role;
grant execute on function public.comprovante_completar(jsonb) to service_role;
grant execute on function public.comprovante_pergunta_nao_enviada(uuid) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 9. Prova: a coluna, as três categorias marcadas, as portas fechadas, a regra nos três que decidem e nos
--    dois que mostram, e a volta à fila fora do IF do fechamento.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
  v_rpcs text[] := array[
    'public.comprovante_completar(jsonb)',
    'public.comprovante_pergunta_nao_enviada(uuid)'];
  v_leituras text[] := array[
    'public.comprovantes_consultar(jsonb)'];
  v_helpers text[] := array[
    'public._comprovante_tipo_na_os(public.comprovantes)',
    'public._comprovante_proximo_passo(public.comprovantes)',
    'public._comprovante_plano(uuid)',
    'public._comprovante_resumo(public.comprovantes)'];
  v_falta text;
  v_src text;
begin
  if not exists (select 1 from information_schema.columns k
                  where k.table_schema = 'public' and k.table_name = 'financial_categories'
                    and k.column_name = 'despesa_de_campo' and k.is_nullable = 'NO' and k.column_default = 'false') then
    raise exception 'financial_categories.despesa_de_campo não é boolean not null default false';
  end if;
  select string_agg(n, ', ' order by n) into v_falta
    from unnest(array['Combustível e deslocamento', 'Alimentação de campo', 'Pedágio e estacionamento']) as n
   where not exists (select 1 from public.financial_categories f
                      where f.name = n and f.type = 'payable' and coalesce(f.active, false) and f.despesa_de_campo);
  if v_falta is not null then
    raise exception 'categoria de campo sem a marca: %', v_falta;
  end if;

  foreach v_f in array v_rpcs || v_leituras || v_helpers loop
    if has_function_privilege('anon', v_f, 'execute') then
      raise exception 'função dos comprovantes exposta para anon: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs || v_helpers loop
    if has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função dos comprovantes exposta para authenticated: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs || v_leituras loop
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  foreach v_f in array v_leituras loop
    if not has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'o painel (authenticated) não alcança %', v_f;
    end if;
  end loop;
  foreach v_f in array v_helpers loop
    if has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'helper interno dos comprovantes alcançável pela service_role: %', v_f;
    end if;
  end loop;

  -- a regra entra nos três que decidem e nos dois que mostram
  foreach v_f in array array[
    'public._comprovante_proximo_passo(public.comprovantes)',
    'public._comprovante_plano(uuid)',
    'public._comprovante_resumo(public.comprovantes)',
    'public.comprovantes_consultar(jsonb)',
    'public.comprovante_completar(jsonb)'] loop
    select p.prosrc into v_src from pg_proc p where p.oid = v_f::regprocedure;
    if position('_comprovante_tipo_na_os(' in v_src) = 0 then
      raise exception '% não usa _comprovante_tipo_na_os', v_f;
    end if;
  end loop;
  -- a volta à fila não fica no mesmo IF do fechamento, e a tentativa que não saiu é devolvida (F2 e F3)
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.comprovante_pergunta_nao_enviada(uuid)'::regprocedure;
  if v_src ~* '_pergunta_fechar\([^;]*\)\s*and\s+not\s+exists' then
    raise exception 'comprovante_pergunta_nao_enviada ainda olha a fila no mesmo IF do _pergunta_fechar';
  end if;
  if position('perguntas_automaticas' in v_src) = 0 or position('banco_perguntas' in v_src) = 0 then
    raise exception 'comprovante_pergunta_nao_enviada não devolve a tentativa (perguntas_automaticas/banco_perguntas)';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261013100000', 'comprovante_despesa_de_campo_e_envio_falho')
on conflict do nothing;
