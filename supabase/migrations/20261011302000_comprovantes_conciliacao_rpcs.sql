-- Comprovantes F3 (11/10/2026): candidatos do extrato, ligar e explicar a linha (contrato BANCO ↔ EDGE).
--
-- Para cada CMP gravado que espera o banco, a F3 procura as linhas do extrato que podem ser dele
-- (regra por forma: Pix = valor + documento D-1..D+1; boleto = documento + valor D-1..D+2; débito =
-- só valor D-1..D+3, porque o C6 manda "DEBITO DE CARTAO" sem loja nem documento; crédito = à vista
-- ou parcela 1/n em D-1..D+5 — o cartão data a linha na compra) e dá o nível: VERDE (UMA candidata na
-- janela, e forte), AZUL (lista numerada com "0 Nenhuma destas") ou CINZA (nenhuma: espera 30 dias,
-- 45 no crédito, e vira "abandonado"). Linha dispensada da fila nunca é candidata.
-- Nome diferente NUNCA é forte e não exclui (o descritor do cartão raramente é a razão social);
-- documento de quem recebeu que contradiz exclui (o CNPJ do emitente do cupom, não: o Pix da
-- maquininha vai ao intermediador). Vínculo sempre pergunta (SIM do dono); identificação automática
-- só por documento ou nome igual — e a ligação automática só pelo que o dono já autorizou (a anotação
-- do resumo, "anoto para quando o banco trouxer", ou o lançamento que ele mesmo casou). Depois que
-- o dono aprova a linha no Extrato, a varredura só ADOTA o lançamento dele (nunca corrige categoria
-- nem OS sem SIM).
--
-- LIGAR NÃO APROVA: ligar classifica a proposta da fila do Extrato pela rota da anotação que já existe
-- (_aplicar_anotacao: fornecedor, categoria, OS, confiança 99), anexa ao lançamento que já existe
-- (corrigindo categoria/OS) ou dá baixa na conta a pagar que o CMP anexou (conciliar_lancamento, só no
-- SIM). A aprovação continua sendo do dono no Extrato.
--
--   R1 comprovantes_reavaliar_banco(origem, autor)     a varredura (o finance-review chama logo depois
--                                                       de aplicar_anotacoes_pendentes)
--   R2 comprovantes_linhas_da_conciliacao(transacoes)  as linhas ligadas a CMP e as candidatas com
--                                                       pergunta (o finance-review não as lança sozinho)
--   R3 comprovante_banco_proxima(phone, motivo, cmp)   abre a pergunta "apareceu no extrato, ligo?"
--   R4 comprovante_banco_responder(p)                  a resposta do dono a ela
--   R6 comprovantes_vigia_banco(limite)                telefones em que o vigia pode perguntar agora
--   R10 comprovante_banco_ceder(phone)                 o comprovante NOVO do dono passa na frente da
--                                                       pergunta do extrato aberta (ela fecha e volta depois)
--   extrato_da_conta (redefinida, MESMA casca: sql, invoker, search_path public, grants de hoje): a
--   contraparte da linha sem nome passa a ser a loja do CMP (bank_transactions.nome_pelo_comprovante).
--
-- Helpers internos (sem grant para ninguém): _comprovante_banco_regra, _comprovante_nomes,
-- _comprovante_nome_da_linha, _comprovante_linha_curta, _comprovante_banco_rotulo,
-- _comprovante_candidatos, _comprovante_recusar, _comprovante_indice_pendente,
-- _comprovante_efeitos_com_ligacao, _comprovante_linha_explicar, _comprovante_ligar,
-- _comprovante_desligar, _comprovantes_banco_varrer, _comprovante_banco_pode,
-- _comprovante_banco_resumo, _comprovante_banco_pergunta, _comprovante_banco_abrir.
--
-- Todas security definer, search_path vazio. Nenhuma devolve leitura, leitura_texto, wa_key nem CPF.
-- Toda rota que grava financeiro recebe o autor: as que o edge chama com o dono recebem p_autor e
-- conferem p_autor = c.dono_id e is_admin(p_autor); a varredura (sem pessoa) usa o c.dono_id de cada
-- CMP. Logs (raise warning) só com o sqlstate. Não escreve dados. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. Quem procura linha e como
-- ---------------------------------------------------------------------------------------------

-- {"regra","so_registro"} ou nulo. Procura só o CMP com valor e data confirmados, que não é "a mesma
-- compra" de outro (o principal é que procura), que não é NF-e (a conta é a da nota), pago pela
-- EMPRESA (padrão do dono: Pix, débito e crédito assumem a empresa; o resumo mostra), com forma
-- bancária ou crédito. PESSOAL com forma bancária/crédito: só registra (pendência do dono 11.1).
create or replace function public._comprovante_banco_regra(c public.comprovantes)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_forma text;
  v_regra text;
begin
  if c.id is null or c.valor_confirmado is null or c.data_confirmada is null or c.mesma_compra_de is not null
     or public._comprovante_e_nfe(c) then
    return null;
  end if;
  v_forma := case when c.destino = 'pessoal' then coalesce(c.forma_confirmada, c.forma_pagamento) else c.forma_confirmada end;
  v_regra := case v_forma when 'pix' then 'pix' when 'transferencia' then 'pix' when 'boleto' then 'boleto'
                          when 'debito' then 'debito' when 'credito' then 'credito' end;
  if v_regra is null then
    return null;
  end if;
  if c.destino = 'pessoal' then
    return jsonb_build_object('regra', v_regra, 'so_registro', true);
  end if;
  if c.destino is null or public._comprovante_efetivo(c)->>'quem' is distinct from 'empresa' then
    return null;
  end if;
  return jsonb_build_object('regra', v_regra, 'so_registro', false);
end $$;

-- Os nomes comparáveis do CMP: cadastro (nome e fantasia) + Receita (fantasia, razão e o nome gravado
-- da Receita), sem CPF. O CNPJ da HBR nunca é fornecedor.
create or replace function public._comprovante_nomes(c public.comprovantes)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct z.n) filter (where z.n <> ''), '{}'::text[])
    from (
      select public._nome_comparavel(public._comprovante_sem_cpf(y.x)) as n
        from (
          select s.name as x from public.suppliers s where s.id = public._comprovante_fornecedor_efetivo(c, null)
          union all
          select s.trade_name from public.suppliers s where s.id = public._comprovante_fornecedor_efetivo(c, null)
          union all
          select c.fornecedor_receita
          union all
          select k.nome_fantasia from public.cnpj_consultas k
           where k.encontrado and k.cnpj in (c.emitente_cnpj, c.favorecido_doc)
             and left(k.cnpj, 8) is distinct from public.raiz_do_cnpj_da_empresa()
          union all
          select k.razao_social from public.cnpj_consultas k
           where k.encontrado and k.cnpj in (c.emitente_cnpj, c.favorecido_doc)
             and left(k.cnpj, 8) is distinct from public.raiz_do_cnpj_da_empresa()
        ) y
       where y.x is not null
    ) z;
$$;

-- O nome de quem recebeu na linha: o campo próprio, a loja, o que vem depois do "|" no "Compra no
-- débito|…" do Nubank ou o que está na descrição ("Pix enviado para …"). "DEBITO DE CARTAO" = sem
-- nome. A loja que a F3 gravou (nome_pelo_comprovante) NÃO conta: é nossa, não do banco.
create or replace function public._comprovante_nome_da_linha(t public.bank_transactions)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(nullif(btrim(t.counterparty_name), ''), nullif(btrim(t.merchant_name), ''),
                  case when t.description ~* '^compra no d[eé]bito\|' then nullif(btrim(split_part(t.description, '|', 2)), '') end,
                  public._nome_da_linha(t.counterparty_name, t.description));
$$;

-- A linha como o dono a vê (LinhaCurta, sem a ação): data, valor, histórico, conta, cartão,
-- parcela, pendente no cartão e o lançamento que ela já tem.
create or replace function public._comprovante_linha_curta(p_tx uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'data', t.transaction_date,
           'valor', round(t.amount, 2)::text,
           'descricao', left(t.description, 80),
           'conta', bc.label,
           'cartao', t.source_type = 'credit_card',
           'parcela', case when t.installment_label ~ '^[0-9]+/[0-9]+$' and t.installment_label <> '1/1' then t.installment_label end,
           'pendente', coalesce(t.tx_status, '') = 'PENDING',
           'lancamento', (select jsonb_build_object('categoria', p.expense_category, 'descricao', left(p.description, 60))
                            from public.payables p
                           where p.bank_transaction_id = t.id and p.status <> 'cancelled'
                           order by p.divisao_id nulls first, p.created_at, p.id
                           limit 1))
    from public.bank_transactions t
    left join public.bank_connections bc on bc.id = t.bank_connection_id
   where t.id = p_tx;
$$;

-- O rótulo da opção no menu: "<conta> · DD/MM · <histórico até 40> · R$ 50,98" + cartão, parcela,
-- pendente e já lançada (o edge monta o mesmo texto; este é o que fica gravado na pergunta).
create or replace function public._comprovante_banco_rotulo(p_l jsonb)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select left(
    coalesce(p_l->>'conta', 'Conta') || ' · ' || to_char((p_l->>'data')::date, 'DD/MM') || ' · '
    || left(coalesce(p_l->>'descricao', ''), 40) || ' · R$ '
    || translate(to_char(coalesce((p_l->>'valor')::numeric, 0), 'FM999,999,990.00'), ',.', '.,')
    || case when coalesce((p_l->>'cartao')::boolean, false) then ' (cartão)' else '' end
    || case when p_l->>'parcela' is not null
            then ' · parcela ' || (p_l->>'parcela') || coalesce(' da compra de R$ '
                 || translate(to_char((p_l->>'total_da_compra')::numeric, 'FM999,999,990.00'), ',.', '.,'), '')
            else '' end
    || case when coalesce((p_l->>'pendente')::boolean, false) then ' · ainda pendente no cartão' else '' end
    || case when jsonb_typeof(p_l->'lancamento') = 'object'
            then ' · já lançada' || coalesce(' (' || (p_l->'lancamento'->>'categoria') || ')', '') else '' end,
    300);
$$;

-- ---------------------------------------------------------------------------------------------
-- 2. Candidatos (Avaliacao). A MESMA regra de simulacao-f3/candidatos.sql (o ensaio confere as duas
--    no PGlite com os mesmos CMPs sintéticos). Só leitura.
--    Fora: linha dispensada da fila (qualquer dismissed_kind: duplicata, "lançada em dobro",
--    mecânica do cartão…), recusada pelo dono, ligada a outro CMP não cancelado. Disputada: a linha
--    é forte para outro CMP aguardando_banco (pela última avaliação dele) → deixa de ser forte para
--    os dois.
--    Documento que contradiz só exclui quando é o de QUEM RECEBEU (o favorecido do comprovante do Pix
--    ou do boleto, ou o do comprovante "a mesma compra"): o CNPJ do emitente do cupom não é o de quem
--    recebe o Pix na maquininha (CloudWalk, Mercado Pago, Pagar.me…: 12 de 196 Pix a CNPJ, simulação
--    de 11/10/2026) — a linha de outro CNPJ fica fraca, nunca de fora.
--    Nível (regra do dono): VERDE = UMA candidata na janela, e forte; AZUL = 2 ou mais, ou uma fraca
--    (a forte, se há, vem em 1 na lista com "0 Nenhuma destas"); CINZA = nenhuma.
--    Ação "conflito": o CMP anexou uma conta a pagar em aberto e a linha já virou OUTRO lançamento —
--    nunca forte; ligar não resolve (uma das duas tem de ser cancelada no Financeiro).
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_candidatos(c public.comprovantes)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r jsonb := public._comprovante_banco_regra(c);
  v_regra text := v_r->>'regra';
  v_ate integer;
  v_raiz text := public.raiz_do_cnpj_da_empresa();
  v_fav text := c.favorecido_doc;
  v_doc14 text;
  v_recebedor boolean := false;
  v_cpf5 text;
  v_nomes text[];
  v_e2e text;
  v_conta_aberta jsonb;
  v_n integer;
  v_fortes integer;
  v_linhas jsonb;
  v_hash text;
  v_nivel text;
begin
  if v_r is null then
    return null;
  end if;
  -- a janela da busca (data da linha). O cartão data a linha na compra (a parcela 1/n também): D+5
  -- basta; os 45 dias do crédito são só a espera antes do abandono (o atraso de importação do Nubank)
  v_ate := case v_regra when 'pix' then 1 when 'boleto' then 2 when 'debito' then 3 else 5 end;
  -- o comprovante do Pix guardado como "a mesma compra" deste (o cupom) traz o documento de quem recebeu
  if v_fav is null then
    select y.favorecido_doc into v_fav from public.comprovantes y
     where y.mesma_compra_de = c.id and y.situacao <> 'cancelado'
       and (y.favorecido_doc ~ '^[0-9]{14}$' or y.favorecido_doc ~ '^\*\*\*\.\*\*\*\.[0-9]{3}-[0-9]{2}$')
     order by y.numero
     limit 1;
  end if;
  if v_fav ~ '^[0-9]{14}$' and (v_raiz is null or left(v_fav, 8) <> v_raiz) then
    v_doc14 := v_fav;
    v_recebedor := true;
  else
    -- o CNPJ do emitente (cupom): identifica quando bate, nunca exclui
    v_doc14 := public._comprovante_documento(c);
  end if;
  if v_fav ~ '^\*\*\*\.\*\*\*\.[0-9]{3}-[0-9]{2}$' then
    v_cpf5 := regexp_replace(v_fav, '\D', '', 'g');
  end if;
  v_nomes := public._comprovante_nomes(c);
  if jsonb_typeof(c.leitura) = 'object' and jsonb_typeof(c.leitura->'campos') = 'object' then
    v_e2e := nullif(btrim(c.leitura->'campos'->>'e2e'), '');
  end if;
  -- a conta a pagar em aberto que a F2 anexou: a ação vira "casar"
  select jsonb_build_object('descricao', left(p.description, 60), 'valor', round(p.amount, 2)::text) into v_conta_aberta
    from public.payables p
   where p.id = c.payable_id and p.status in ('pending', 'overdue', 'partially_paid') and p.bank_transaction_id is null;

  with linhas as (
    select t.id, t.transaction_date, t.amount, t.description, t.source_type, t.payment_method, t.installment_label,
           t.tx_status, t.pix_end_to_end_id, bc.label as conta,
           nullif(regexp_replace(coalesce(t.counterparty_document, ''), '\D', '', 'g'), '') as doc,
           public._comprovante_nome_da_linha(t) as nome_linha
      from public.bank_transactions t
      left join public.bank_connections bc on bc.id = t.bank_connection_id
     where t.transaction_type = 'debit'
       -- dispensada da fila (transferência, duplicata, estorno, parcela, "lançada em dobro", mecânica do
       -- cartão…) não é compra de ninguém
       and t.dismissed_kind is null
       and coalesce(t.source_type, 'bank') in ('bank', 'credit_card')
       and t.source_type = case when v_regra = 'credito' then 'credit_card' else 'bank' end
       and t.transaction_date between c.data_confirmada - 1 and c.data_confirmada + v_ate
       and not (t.id = any (c.banco_recusados))
       and not exists (select 1 from public.comprovantes y
                        where y.bank_transaction_id = t.id and y.id <> c.id and y.situacao <> 'cancelado')
  ), cand as (
    select l.*,
           (l.transaction_date - c.data_confirmada) as dias,
           case when l.installment_label ~ '^[0-9]+/[0-9]+$' then split_part(l.installment_label, '/', 2)::int end as n_parcelas,
           case when v_doc14 is not null and length(l.doc) = 14 and left(l.doc, 8) = left(v_doc14, 8) then 'documento'
                when v_cpf5 is not null and length(l.doc) = 11 and right(l.doc, 5) = v_cpf5 then 'cpf_parcial'
                when l.doc is null then 'linha_sem_documento'
                when v_doc14 is null and v_cpf5 is null then 'cmp_sem_documento'
                else 'outro_documento' end as prova_doc,
           case when l.nome_linha is null then 'sem_nome'
                when exists (select 1 from unnest(v_nomes) nm
                              where nm = public._nome_comparavel(l.nome_linha)
                                 or (length(public._nome_comparavel(l.nome_linha)) >= 20
                                     and nm like public._nome_comparavel(l.nome_linha) || '%'))
                  then 'nome_igual'
                else 'nome_diferente' end as prova_nome,
           coalesce(v_e2e is not null and l.pix_end_to_end_id = v_e2e, false) as e2e
      from linhas l
     -- documento de QUEM RECEBEU que contradiz exclui (CNPJ: outra raiz; CPF parcial: outros 5
     -- dígitos). O CNPJ do emitente do cupom nunca exclui (o Pix da maquininha vai ao intermediador).
     where not (length(coalesce(l.doc, '')) >= 11 and (
                (v_recebedor and (length(l.doc) <> 14 or left(l.doc, 8) <> left(v_doc14, 8)))
             or (v_cpf5 is not null and (length(l.doc) <> 11 or right(l.doc, 5) <> v_cpf5))))
       -- valor exato; no crédito também a parcela 1/n cujo n × valor dá o total (1 centavo por parcela)
       and ((abs(l.amount - c.valor_confirmado) < 0.005
             and (v_regra <> 'credito' or l.installment_label is null or l.installment_label = '1/1'))
            or (v_regra = 'credito' and l.installment_label ~ '^1/([2-9]|[1-9][0-9])$'
                and abs(l.amount * split_part(l.installment_label, '/', 2)::int - c.valor_confirmado)
                    <= 0.01 * split_part(l.installment_label, '/', 2)::int))
       -- o tipo de linha que cada forma produz
       and case v_regra
             when 'pix' then l.payment_method = 'PIX' or l.description ~* '(^|\s)(pix|transf\w*|ted)(\s|$)'
                             or (v_doc14 is not null and length(l.doc) = 14 and left(l.doc, 8) = left(v_doc14, 8))
             when 'boleto' then l.payment_method = 'BOLETO' or l.description ~* 'boleto'
                             or (v_doc14 is not null and length(l.doc) = 14 and left(l.doc, 8) = left(v_doc14, 8))
             when 'debito' then l.payment_method is distinct from 'PIX' and l.payment_method is distinct from 'BOLETO'
                             and l.description !~* '(^|\s)(pix|ted|doc|transf\w*|tributos|darf|juros|iof|tarifa|cdb|aplica\w*|resgate|encargos|estorno)(\s|$)|pgto fat|pagamento de fatura'
             else true end
  ), forca as (
    select k.*,
           lc.lanc,
           (case v_regra
              when 'pix' then k.prova_doc = 'documento'
              when 'boleto' then k.prova_doc = 'documento'
              when 'debito' then k.prova_nome in ('sem_nome', 'nome_igual')
              else k.prova_nome = 'nome_igual' and coalesce(k.n_parcelas, 1) = 1 and k.dias between -1 and 3 end
            or k.e2e) as bruto,
           exists (select 1 from public.comprovantes y
                    cross join lateral jsonb_array_elements(y.banco_candidatos) e
                    where y.id <> c.id and y.situacao = 'aguardando_banco' and not y.banco_so_registro
                      and e->>'id' = k.id::text
                      and (coalesce((e->>'forte')::boolean, false) or coalesce(e->'motivos', '[]'::jsonb) ? 'disputada')) as disputada,
           -- a conta em aberto do CMP + a linha já lançada em outro registro: o mesmo gasto duas vezes
           (lc.lanc is not null and v_conta_aberta is not null) as conflito
      from cand k
      left join lateral (
        select jsonb_build_object('categoria', p.expense_category, 'descricao', left(p.description, 60)) as lanc
          from public.payables p
         where p.bank_transaction_id = k.id and p.status <> 'cancelled'
         order by p.divisao_id nulls first, p.created_at, p.id
         limit 1) lc on true
  ), ordenada as (
    select f.*, (f.bruto and not f.disputada and not f.conflito) as e_forte,
           row_number() over (order by (f.bruto and not f.disputada and not f.conflito) desc, abs(f.dias), f.id) as ordem
      from forca f
  ), com_acao as (
    select o.*,
           case when o.conflito then 'conflito'
                when o.lanc is not null then 'anexar'
                when v_conta_aberta is not null then 'casar'
                when exists (select 1 from public.finance_review_queue q
                              where q.bank_transaction_id = o.id and q.status = 'pending') then 'classificar'
                else 'aguardar' end as acao
      from ordenada o
  )
  select count(*)::integer,
         (count(*) filter (where z.e_forte))::integer,
         coalesce(jsonb_agg(jsonb_build_object(
             'n', z.ordem,
             'id', z.id,
             'data', z.transaction_date,
             'valor', round(z.amount, 2)::text,
             'descricao', left(z.description, 80),
             'nome', z.nome_linha,
             'conta', z.conta,
             'cartao', z.source_type = 'credit_card',
             'parcela', case when coalesce(z.n_parcelas, 1) > 1 then z.installment_label end,
             'total_da_compra', case when coalesce(z.n_parcelas, 1) > 1 then c.valor_confirmado::text end,
             'pendente', coalesce(z.tx_status, '') = 'PENDING',
             'acao', z.acao,
             'lancamento', z.lanc,
             'conta_aberta', case when z.acao in ('casar', 'conflito') then v_conta_aberta end,
             'motivos', to_jsonb(array_remove(array[
                          case when coalesce(z.n_parcelas, 1) > 1 then 'parcela_1_de_' || z.n_parcelas else 'valor_exato' end,
                          case when z.prova_doc in ('documento', 'cpf_parcial', 'outro_documento') then z.prova_doc end,
                          z.prova_nome,
                          'dias:' || z.dias,
                          case when z.e2e then 'e2e' end,
                          case when z.disputada then 'disputada' end], null)),
             'forte', z.e_forte) order by z.ordem) filter (where z.ordem <= 3), '[]'::jsonb),
         md5(coalesce(string_agg(z.id::text || ':' || z.acao, ',' order by z.ordem) filter (where z.ordem <= 3), '')
             || '|' || greatest(count(*) - 3, 0))
    into v_n, v_fortes, v_linhas, v_hash
    from com_acao z;

  -- verde = UMA candidata na janela, e forte (regra do dono): com outra do mesmo valor, mesmo fraca
  -- (débito com o descritor cortado, Pix sem documento), o dono vê as duas na lista azul
  v_nivel := case when v_n = 0 then 'cinza' when v_n = 1 and v_fortes = 1 then 'verde' else 'azul' end;
  return jsonb_build_object('regra', v_regra, 'so_registro', coalesce((v_r->>'so_registro')::boolean, false),
                            'nivel', v_nivel, 'linhas', v_linhas, 'mais', greatest(v_n - 3, 0), 'hash', v_hash);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. Pequenos helpers
-- ---------------------------------------------------------------------------------------------

-- as linhas que o dono recusou: sem repetir, na ordem, as 50 últimas
create or replace function public._comprovante_recusar(p_atual uuid[], p_novas uuid[])
returns uuid[]
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce((select array_agg(u.id order by u.o)
                     from (select x.id, min(x.o) as o
                             from unnest(coalesce(p_atual, '{}'::uuid[]) || coalesce(p_novas, '{}'::uuid[])) with ordinality as x(id, o)
                            where x.id is not null
                            group by x.id
                            order by min(x.o) desc
                            limit 50) u), '{}'::uuid[]);
$$;

-- o índice do mês do CMP volta a ficar pendente (a situação mudou)
create or replace function public._comprovante_indice_pendente(p_mes date)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into public.comprovantes_indice_mensal as i (mes, pendente, proxima_em, atualizado_em)
  select date_trunc('month', p_mes)::date, true, now(), now() where p_mes is not null
  on conflict (mes) do update set pendente = true, proxima_em = now(), atualizado_em = now();
$$;

-- o efeito ligar_linha entra no lugar do anterior da MESMA linha (ainda ligado) ou no fim
create or replace function public._comprovante_efeitos_com_ligacao(p_efeitos jsonb, p_efeito jsonb)
returns jsonb
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when exists (select 1 from jsonb_array_elements(coalesce(p_efeitos, '[]'::jsonb)) e
                  where e->>'tipo' = 'ligar_linha' and e->>'bank_transaction_id' = p_efeito->>'bank_transaction_id'
                    and not e ? 'desligado_em')
      then (select jsonb_agg(case when e->>'tipo' = 'ligar_linha' and e->>'bank_transaction_id' = p_efeito->>'bank_transaction_id'
                                       and not e ? 'desligado_em'
                                  then p_efeito else e end order by o)
              from jsonb_array_elements(p_efeitos) with ordinality as t(e, o))
    else coalesce(p_efeitos, '[]'::jsonb) || jsonb_build_array(p_efeito) end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 4. Explicar a linha ligada (2.5), idempotente. Não escreve em comprovantes (quem chama escreve).
--    Devolve o efeito ligar_linha (origem/nivel ficam com quem chama) + chaves internas com "_"
--    (_explicada, _pendencia, _aviso, _erro, _aplicou) que quem chama tira antes de gravar.
--    p_casar: só no SIM/escolha/gravação (nunca na varredura).
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_linha_explicar(c public.comprovantes, p_tx uuid, p_autor uuid, p_casar boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  t record;
  v_pay record;
  v_cmp_pay record;
  v_prop record;
  v_ef jsonb := public._comprovante_efetivo(c);
  v_cat text := v_ef->>'categoria';
  v_os uuid := case when c.destino = 'os' then c.destino_os_id end;
  v_forn text := public._comprovante_fornecedor(c)->>'nome';
  v_anots uuid[];
  v_como text := 'aguardando';
  v_payable uuid;
  v_anot uuid;
  v_anot_criada boolean := false;
  v_aplicou boolean := false;
  v_proposta uuid;
  v_corr jsonb := '{}'::jsonb;
  v_msgs text[] := '{}';
  v_explicada boolean := false;
  v_pend text;
  v_aviso text;
  v_erro text;
  v_ligou_despesa boolean := false;
  v_lancado_depois boolean := false;
  v_conflito jsonb;
  v_t text;
begin
  select x.id, x.transaction_date, x.counterparty_name, x.merchant_name, x.description, x.nome_pelo_comprovante
    into t from public.bank_transactions x where x.id = p_tx for update;
  if not found then
    raise exception 'A linha do extrato não existe mais.' using errcode = '22023';
  end if;
  -- as anotações deste CMP: a da F2 e as que a F3 criou/usou nas ligações
  select array_agg(distinct a) into v_anots
    from (select c.anotacao_id as a
          union all
          select (e->>'anotacao_id')::uuid from jsonb_array_elements(c.efeitos) e
           where e->>'tipo' in ('ligar_linha', 'anotar', 'anexar_anotacao') and e->>'anotacao_id' is not null) s
   where a is not null;
  v_anots := coalesce(v_anots, '{}'::uuid[]);

  select p.id, p.status into v_pay from public.payables p
   where p.bank_transaction_id = p_tx and p.status <> 'cancelled'
   order by p.divisao_id nulls first, p.created_at, p.id
   limit 1;
  select p.id, p.status, p.bank_transaction_id into v_cmp_pay from public.payables p where p.id = c.payable_id;

  if v_pay.id is not null then
    -- 1. a linha já virou lançamento
    if v_pay.id = c.payable_id then
      -- é o lançamento do próprio CMP (anexado na F2, ou a conta dele que ganhou a linha)
      v_como := 'anexou';
      v_payable := v_pay.id;
      v_explicada := true;
    elsif v_cmp_pay.id is null or v_cmp_pay.status = 'cancelled' then
      v_payable := v_pay.id;
      if p_casar then
        -- anexa no SIM do dono (a pergunta mostrou "uso o lançamento que já existe dela e corrijo
        -- para …"): o lançamento recebe a categoria e a OS do CMP (só o que difere; o "antes" fica)
        v_corr := public._comprovante_corrigir_lancamento(v_pay.id, v_cat, v_os, c.codigo, p_autor);
        if v_corr->>'mensagem' is not null then
          v_msgs := v_msgs || (v_corr->>'mensagem');
        end if;
        v_corr := coalesce(v_corr->'corrigido', '{}'::jsonb);
        v_como := 'anexou';
      else
        -- varredura: a linha que o CMP ligou foi APROVADA pelo dono no Extrato (ou lançada por
        -- outro caminho) depois da ligação. Só adota o lançamento: a categoria e a OS que o dono
        -- escolheu ao aprovar ficam (nada é corrigido sem SIM). O "como" de antes fica (quem chama
        -- não o troca) e lancado_depois marca que o lançamento NÃO é o que existia ao ligar: o
        -- cancelamento do CMP recusa (desfaz-se pelo Extrato).
        v_como := null;
        v_lancado_depois := true;
      end if;
      if c.so_expense_id is not null then
        update public.service_order_expenses s set linked_payable_id = v_pay.id
         where s.id = c.so_expense_id and s.linked_payable_id is null;
        v_ligou_despesa := found;
      end if;
      update public.anotacoes_do_extrato a
         set status = 'cancelada', cancelada_em = now(), motivo_cancelamento = c.codigo || ': a linha do banco já foi lançada'
       where a.id = any (v_anots) and a.status = 'aguardando';
      v_explicada := true;
    elsif v_cmp_pay.status in ('pending', 'overdue', 'partially_paid') and v_cmp_pay.bank_transaction_id is null then
      -- o CMP anexou uma conta a pagar EM ABERTO e a linha já virou OUTRO lançamento: o mesmo gasto
      -- contado duas vezes. Não liga (quem chama recusa): o dono cancela uma das duas no Financeiro.
      v_conflito := jsonb_build_object('conta_aberta_id', v_cmp_pay.id, 'lancamento_id', v_pay.id);
      v_pend := 'classificar_no_extrato';
      v_aviso := 'conta_aberta_e_linha_lancada';
    else
      -- o CMP já tem OUTRO lançamento (pago por outra linha ou no Caixa): não mexe; o dono confere no Extrato
      v_pend := 'classificar_no_extrato';
      v_aviso := 'linha_lancada_em_outro';
      v_explicada := true;
    end if;

  elsif v_cmp_pay.id is not null and v_cmp_pay.status in ('pending', 'overdue', 'partially_paid')
        and v_cmp_pay.bank_transaction_id is null then
    -- 2. o CMP tem conta a pagar em aberto (anexada pela F2): casa — só no SIM do dono
    if p_casar then
      begin
        perform public.conciliar_lancamento('payable', c.payable_id, p_tx, p_autor);
        update public.finance_review_queue q
           set status = 'superseded', decision_note = 'Casada com a conta do ' || c.codigo, decided_at = now(), updated_at = now()
         where q.bank_transaction_id = p_tx and q.status = 'pending';
        v_como := 'casou';
        v_payable := c.payable_id;
        v_explicada := true;
      exception when others then
        get stacked diagnostics v_t = message_text;
        v_erro := left(v_t, 200);
      end;
    end if;

  else
    -- 3. a linha tem proposta pendente na fila do Extrato
    select q.id, q.kind, q.evidencia into v_prop from public.finance_review_queue q
     where q.bank_transaction_id = p_tx and q.status = 'pending'
     order by q.created_at desc, q.id
     limit 1;
    if v_prop.id is not null then
      v_proposta := v_prop.id;
      if v_prop.kind <> 'create_payable' then
        -- transferência, anomalia...: o dono decide no Extrato
        v_pend := 'classificar_no_extrato';
        v_explicada := true;
      elsif coalesce(v_prop.evidencia, '{}'::jsonb) ? 'anotacao' then
        if (v_prop.evidencia->'anotacao'->>'id')::uuid = any (v_anots) then
          v_como := 'classificou';
          v_anot := (v_prop.evidencia->'anotacao'->>'id')::uuid;
        else
          -- outra anotação (do dono, pela tela/assistente) já classificou: não passa por cima
          v_pend := 'classificar_no_extrato';
        end if;
        v_explicada := true;
      else
        -- a anotação da F2 que ainda espera, ou uma nova (documento nulo: a linha é a escolhida)
        select a.id into v_anot from public.anotacoes_do_extrato a
         where a.id = any (v_anots) and a.status = 'aguardando'
         order by a.criada_em limit 1;
        if v_anot is null then
          insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, documento, fornecedor_id,
                                                   categoria, os_id, descricao, criada_por)
          values ('debit', c.valor_confirmado, c.data_confirmada, true, null, public._comprovante_fornecedor_efetivo(c, null),
                  v_cat, v_os,
                  left(c.codigo || ' · ' || public._comprovante_tipo_no_texto(c.tipo) || coalesce(' · ' || v_forn, ''), 200),
                  p_autor)
          returning id into v_anot;
          v_anot_criada := true;
        end if;
        perform public._aplicar_anotacao(v_anot, v_prop.id);
        v_aplicou := true;
        v_como := 'classificou';
        v_explicada := true;
      end if;
    end if;
    -- 4. sem proposta (cartão PENDING, ou o finance-review não rodou): a varredura tenta de novo
  end if;

  -- 5. a linha sem nome mostra a loja do CMP no Extrato (só se ainda não tem; nunca no conflito, que não liga)
  if v_erro is null and v_conflito is null and nullif(btrim(coalesce(t.counterparty_name, '')), '') is null
     and nullif(btrim(coalesce(t.merchant_name, '')), '') is null
     and public._nome_da_linha(t.counterparty_name, t.description) is null and t.nome_pelo_comprovante is null then
    update public.bank_transactions x
       set nome_pelo_comprovante = left(coalesce(v_forn, public._comprovante_tipo_no_texto(c.tipo)) || ' · ' || c.codigo, 160)
     where x.id = p_tx and x.nome_pelo_comprovante is null;
  end if;

  return jsonb_build_object(
    'tipo', 'ligar_linha', 'bank_transaction_id', p_tx, 'origem', null, 'nivel', null, 'em', now(),
    'como', v_como, 'proposta_id', v_proposta, 'anotacao_id', v_anot, 'anotacao_criada', v_anot_criada,
    'payable_id', v_payable, 'corrigido', v_corr, 'mensagens', to_jsonb(v_msgs),
    'linha', public._comprovante_linha_curta(p_tx), 'ligou_despesa', v_ligou_despesa,
    'lancado_depois', v_lancado_depois,
    '_explicada', v_explicada, '_pendencia', v_pend, '_aviso', v_aviso, '_erro', v_erro, '_aplicou', v_aplicou,
    '_conflito', v_conflito);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. Ligar o CMP a uma linha. Trava o telefone e o CMP; confere que a linha ainda é candidata
--    (exceto pela anotação/lançamento, que o dono já autorizou) e que nenhum outro CMP a tem.
--    Erro da explicação no SIM (a baixa recusada: mês fechado…) levanta: quem chama desfaz tudo.
--    {"ligado":true,"efeito","explicada","aviso"} ou {"ligado":false,"motivo"}.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_ligar(p_cmp uuid, p_tx uuid, p_origem text, p_nivel text, p_autor uuid, p_casar boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_phone text;
  v_av jsonb;
  v_lig jsonb;
  v_efeito jsonb;
  v_explicada boolean;
  v_pend text[];
  v_novos jsonb := '[]'::jsonb;
  v_w uuid;
begin
  if p_origem is null or p_origem not in ('gravacao', 'sim', 'escolha', 'anotacao', 'lancamento')
     or p_nivel is null or p_nivel not in ('verde', 'azul') or p_tx is null then
    raise exception '_comprovante_ligar: entrada inválida' using errcode = '22023';
  end if;
  select x.phone_normalized into v_phone from public.comprovantes x where x.id = p_cmp;
  if v_phone is not null then
    perform pg_advisory_xact_lock(hashtextextended('pergunta:' || v_phone, 0));
  end if;
  select * into c from public.comprovantes x where x.id = p_cmp for update;
  if not found then
    raise exception '_comprovante_ligar: comprovante % não existe', p_cmp using errcode = '22023';
  end if;
  if p_autor is null or p_autor is distinct from c.dono_id or not public.is_admin(p_autor) then
    raise exception 'Só o dono liga o comprovante ao extrato.' using errcode = '42501';
  end if;
  if c.situacao = 'cancelado' then
    return jsonb_build_object('ligado', false, 'motivo', 'cancelado');
  end if;
  if c.bank_transaction_id is not null then
    return jsonb_build_object('ligado', false, 'motivo', case when c.bank_transaction_id = p_tx then 'ja_ligado' else 'ja_ligado_a_outra' end);
  end if;
  if c.banco_so_registro then
    return jsonb_build_object('ligado', false, 'motivo', 'so_registro');
  end if;
  if c.situacao not in ('aguardando_banco', 'abandonado') then
    return jsonb_build_object('ligado', false, 'motivo', 'situacao');
  end if;
  if exists (select 1 from public.comprovantes y
              where y.bank_transaction_id = p_tx and y.id <> c.id and y.situacao <> 'cancelado') then
    if p_origem in ('anotacao', 'lancamento') and not ('classificar_no_extrato' = any (c.pendencias)) then
      update public.comprovantes x set pendencias = x.pendencias || 'classificar_no_extrato'::text where x.id = c.id;
    end if;
    return jsonb_build_object('ligado', false, 'motivo', 'linha_de_outro_cmp');
  end if;
  if p_origem not in ('anotacao', 'lancamento') then
    v_av := public._comprovante_candidatos(c);
    if v_av is null or not exists (select 1 from jsonb_array_elements(v_av->'linhas') l where l->>'id' = p_tx::text) then
      return jsonb_build_object('ligado', false, 'motivo', 'linha_nao_serve');
    end if;
  end if;

  v_lig := public._comprovante_linha_explicar(c, p_tx, p_autor, p_casar);
  if v_lig->>'_erro' is not null then
    raise exception 'Não dei baixa na conta a pagar: %', v_lig->>'_erro' using errcode = 'P0001';
  end if;
  if jsonb_typeof(v_lig->'_conflito') = 'object' then
    -- a conta em aberto do CMP + a linha já lançada em outro registro: ligar contaria o gasto duas
    -- vezes. Nada muda; o dono cancela uma das duas no Financeiro (a pergunta segue aberta).
    return jsonb_build_object('ligado', false, 'motivo', 'conflito', 'aviso', v_lig->>'_aviso',
                              'conta_aberta_id', v_lig->'_conflito'->'conta_aberta_id',
                              'lancamento_id', v_lig->'_conflito'->'lancamento_id');
  end if;
  v_explicada := coalesce((v_lig->>'_explicada')::boolean, false);
  -- ligação nova pela anotação do resumo cuja linha o dono já aprovou: a anotação do CMP a
  -- classificou antes da aprovação (o lançamento é do dono: lancado_depois)
  v_efeito := (v_lig - '_explicada' - '_pendencia' - '_aviso' - '_erro' - '_aplicou' - '_conflito')
              || jsonb_build_object('origem', p_origem, 'nivel', p_nivel, 'como', coalesce(v_lig->>'como', 'classificou'));

  v_pend := c.pendencias;
  if v_lig->>'_pendencia' is not null and not ((v_lig->>'_pendencia') = any (v_pend)) then
    v_pend := v_pend || (v_lig->>'_pendencia');
  elsif v_explicada and v_lig->>'_pendencia' is null and 'classificar_no_extrato' = any (v_pend) then
    v_pend := array_remove(v_pend, 'classificar_no_extrato');
    v_novos := jsonb_build_array(jsonb_build_object('tipo', 'pendencia_resolvida', 'qual', 'classificar_no_extrato', 'em', now()));
  end if;

  update public.comprovantes x
     set bank_transaction_id = p_tx,
         situacao = 'conciliado',
         conciliacao = p_nivel,
         conciliado_em = now(),
         linha_explicada_em = case when v_explicada then now() end,
         payable_id = coalesce((v_lig->>'payable_id')::uuid, x.payable_id),
         anotacao_id = coalesce(x.anotacao_id, (v_lig->>'anotacao_id')::uuid),
         efeitos = public._comprovante_efeitos_com_ligacao(x.efeitos, v_efeito) || v_novos,
         pendencias = v_pend,
         banco_perguntar = false
   where x.id = c.id;
  perform public._comprovante_indice_pendente(coalesce(c.indice_mes, c.data_confirmada));

  -- a pergunta da F3 aberta deste CMP fecha (respondida no SIM/escolha; substituída nos outros)
  for v_w in
    select w.id from public.whatsapp_perguntas w
     where w.referencia_id = c.id and w.status = 'aberta' and w.origem = 'comprovante' and w.passo = 'banco'
  loop
    perform public._pergunta_fechar(v_w, case when p_origem in ('sim', 'escolha') then 'respondida' else 'substituida' end,
                                    case when p_origem in ('sim', 'escolha') then null else 'ligado' end, null);
  end loop;

  return jsonb_build_object('ligado', true, 'efeito', v_efeito, 'explicada', v_explicada,
                            'aviso', v_lig->>'_aviso', 'aplicou', coalesce((v_lig->>'_aplicou')::boolean, false));
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. Desligar: só sem lançamento na linha (o lançamento que a própria ligação anexou volta à
--    categoria/OS de antes). A proposta da linha volta para o motor (sem a anotação do CMP; o
--    reclassificar diário refaz), as anotações do CMP são canceladas, a loja gravada na linha sai e o
--    CMP volta a esperar o banco. p_recusar = a linha entra em banco_recusados.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_desligar(p_cmp uuid, p_motivo text, p_autor uuid, p_recusar boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_tx uuid;
  v_ef jsonb;
  v_pay record;
  v_data date;
  v_anots uuid[];
  v_campos jsonb := '{}'::jsonb;
  v_atual jsonb;
  k text;
  v_anexou boolean := false;
  v_motivo text := left(coalesce(nullif(btrim(p_motivo), ''), 'sem motivo'), 200);
begin
  select * into c from public.comprovantes x where x.id = p_cmp for update;
  if not found then
    raise exception '_comprovante_desligar: comprovante % não existe', p_cmp using errcode = '22023';
  end if;
  if c.bank_transaction_id is null then
    return jsonb_build_object('desligado', false, 'motivo', 'sem_linha');
  end if;
  v_tx := c.bank_transaction_id;
  select e into v_ef from jsonb_array_elements(c.efeitos) with ordinality as t(e, o)
   where e->>'tipo' = 'ligar_linha' and e->>'bank_transaction_id' = v_tx::text and not e ? 'desligado_em'
   order by o desc limit 1;
  select x.transaction_date into v_data from public.bank_transactions x where x.id = v_tx;

  select p.id, p.status into v_pay from public.payables p
   where p.bank_transaction_id = v_tx and p.status <> 'cancelled'
   order by p.divisao_id nulls first, p.created_at, p.id
   limit 1;
  if v_pay.id is not null then
    -- só o lançamento que JÁ existia quando o CMP ligou (anexado no SIM) se desliga por aqui; o que
    -- nasceu depois (o dono aprovou a linha no Extrato: lancado_depois) desfaz-se pelo Extrato
    if not (v_ef->>'como' = 'anexou' and (v_ef->>'payable_id')::uuid = v_pay.id
            and not coalesce((v_ef->>'lancado_depois')::boolean, false)) then
      raise exception 'A linha do banco de % já virou lançamento: desfaça pelo Extrato.', to_char(v_data, 'DD/MM')
        using errcode = '22023';
    end if;
    -- o lançamento que a ligação anexou volta a categoria/OS de antes (regra do anexar_lancamento da F2)
    v_anexou := true;
    select to_jsonb(p) into v_atual from public.payables p where p.id = v_pay.id;
    for k in select jsonb_object_keys(coalesce(v_ef->'corrigido', '{}'::jsonb)) loop
      if coalesce(v_atual->k, 'null'::jsonb) = coalesce(v_ef->'corrigido'->k->'depois', 'null'::jsonb) then
        v_campos := v_campos || jsonb_build_object(k, v_ef->'corrigido'->k->'antes');
      end if;
    end loop;
    if v_campos <> '{}'::jsonb then
      perform public.corrigir_lancamento('payable', v_pay.id, v_campos, left(c.codigo || ' desligado: ' || v_motivo, 300), p_autor);
    end if;
    if coalesce((v_ef->>'ligou_despesa')::boolean, false) and c.so_expense_id is not null then
      update public.service_order_expenses s set linked_payable_id = null
       where s.id = c.so_expense_id and s.linked_payable_id = v_pay.id;
    end if;
  end if;

  select array_agg(distinct a) into v_anots
    from (select c.anotacao_id as a
          union all
          select (e->>'anotacao_id')::uuid from jsonb_array_elements(c.efeitos) e
           where e->>'tipo' in ('ligar_linha', 'anotar', 'anexar_anotacao') and e->>'anotacao_id' is not null) s
   where a is not null;
  v_anots := coalesce(v_anots, '{}'::uuid[]);

  -- a proposta da linha volta para o motor (o reclassificar diário refaz a linha: o motor mudou)
  update public.finance_review_queue q
     set evidencia = coalesce(q.evidencia, '{}'::jsonb) - 'anotacao' - 'motor',
         suggested_service_order_id = null,
         confidence = least(q.confidence, 50),
         reasoning = left(c.codigo || ' desligado: o motor reclassifica na próxima rodada. · ' || coalesce(q.reasoning, ''), 2000),
         updated_at = now()
   where q.bank_transaction_id = v_tx and q.status = 'pending'
     and (q.evidencia->'anotacao'->>'id') is not null
     and (q.evidencia->'anotacao'->>'id')::uuid = any (v_anots);
  update public.anotacoes_do_extrato a
     set status = 'cancelada', cancelada_em = now(), motivo_cancelamento = left(c.codigo || ' desligado: ' || v_motivo, 300)
   where a.id = any (v_anots) and a.status in ('aguardando', 'aplicada');
  update public.bank_transactions x set nome_pelo_comprovante = null
   where x.id = v_tx and x.nome_pelo_comprovante like '%' || c.codigo || '%';

  update public.comprovantes x
     set bank_transaction_id = null,
         conciliado_em = null,
         linha_explicada_em = null,
         conciliacao = null,
         situacao = case when x.situacao = 'cancelado' then x.situacao else 'aguardando_banco' end,
         aguardando_banco_desde = now(),
         banco_recusados = case when p_recusar then public._comprovante_recusar(x.banco_recusados, array[v_tx]) else x.banco_recusados end,
         anotacao_id = case when x.anotacao_id = any (v_anots) then null else x.anotacao_id end,
         payable_id = case when v_anexou and x.payable_id = v_pay.id then null else x.payable_id end,
         efeitos = coalesce((select jsonb_agg(case when e->>'tipo' = 'ligar_linha' and e->>'bank_transaction_id' = v_tx::text
                                                        and not e ? 'desligado_em'
                                                   then e || jsonb_build_object('desligado_em', now(), 'desligado_motivo', v_motivo)
                                                   else e end order by o)
                               from jsonb_array_elements(x.efeitos) with ordinality as t(e, o)), '[]'::jsonb),
         banco_avaliado_em = null,
         banco_hash = null,
         banco_perguntar = false
   where x.id = c.id;
  perform public._comprovante_indice_pendente(coalesce(c.indice_mes, c.data_confirmada));
  return jsonb_build_object('desligado', true, 'bank_transaction_id', v_tx, 'motivo', v_motivo);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. A pergunta da F3: pode perguntar agora? (a fila da F2 vem primeiro)
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_banco_pode(p_phone text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v text := public._comprovante_vigia_pode(p_phone);
begin
  if v is null then
    return 'fila_da_f2';          -- a F2 pergunta antes
  elsif v in ('fila_vazia', 'limite_de_tentativas') then
    return null;
  end if;
  return v;
end $$;

-- BancoNoResumo (CmpResumo.banco) ou nulo (CMP que não procura linha ou ainda não gravado)
create or replace function public._comprovante_banco_resumo(c public.comprovantes)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_estado text;
  v_desde date;
  v_ate date;
  v_ef jsonb;
  v_linha jsonb;
begin
  if c.id is null or c.gravado_em is null or c.situacao = 'cancelado'
     or (c.banco_regra is null and c.bank_transaction_id is null) then
    return null;
  end if;
  v_desde := (c.aguardando_banco_desde at time zone 'America/Sao_Paulo')::date;
  v_ate := v_desde + case when c.banco_regra = 'credito' then 45 else 30 end;
  if c.banco_so_registro then
    v_estado := 'so_registro';
  elsif c.bank_transaction_id is not null then
    v_estado := 'ligado';
    select e into v_ef from jsonb_array_elements(c.efeitos) with ordinality as t(e, o)
     where e->>'tipo' = 'ligar_linha' and e->>'bank_transaction_id' = c.bank_transaction_id::text and not e ? 'desligado_em'
     order by o desc limit 1;
    select jsonb_build_object('data', l->'data', 'valor', l->'valor', 'descricao', l->'descricao', 'conta', l->'conta',
                              'como', coalesce(v_ef->>'como', 'aguardando'))
      into v_linha
      from (select public._comprovante_linha_curta(c.bank_transaction_id) as l) s;
  elsif c.situacao = 'abandonado' then
    v_estado := 'abandonado';
  elsif exists (select 1 from public.whatsapp_perguntas w
                 where w.referencia_id = c.id and w.status = 'aberta' and w.origem = 'comprovante' and w.passo = 'banco') then
    v_estado := 'pergunta_aberta';
  elsif c.banco_perguntar then
    v_estado := 'perguntar';
  elsif c.situacao = 'aguardando_banco' then
    v_estado := 'esperando';
  else
    return null;
  end if;
  return jsonb_build_object(
    'estado', v_estado,
    'nivel', c.conciliacao,
    'desde', case when v_estado in ('esperando', 'perguntar', 'pergunta_aberta', 'abandonado') then v_desde end,
    'ate', case when v_estado in ('esperando', 'perguntar', 'pergunta_aberta') then v_ate end,
    'linha', v_linha,
    'candidatos', jsonb_array_length(c.banco_candidatos));
end $$;

-- PerguntaDoBancoF3: o que o edge precisa para mandar a pergunta
create or replace function public._comprovante_banco_pergunta(c public.comprovantes, p_pergunta_id uuid, p_avaliacao jsonb, p_motivo text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  w record;
begin
  select x.id, x.dedupe_key, x.opcoes into w from public.whatsapp_perguntas x where x.id = p_pergunta_id;
  if not found then
    raise exception '_comprovante_banco_pergunta: pergunta % não existe', p_pergunta_id using errcode = '22023';
  end if;
  return jsonb_build_object(
    'pergunta_id', w.id,
    'dedupe_key', w.dedupe_key,
    'cmp', public._comprovante_resumo(c),
    'passo', 'banco',
    'opcoes', w.opcoes,
    'retomada', coalesce(p_motivo, '') = 'vigia' and c.banco_ultima_pergunta_em is not null,
    'banco', p_avaliacao);
end $$;

-- Abre a pergunta da F3 de UM CMP (quem chama já decidiu que pode): recalcula e guarda a avaliação;
-- cinza = não pergunta. {"perguntou":true, ...PerguntaDoBancoF3} ou {"perguntou":false,"motivo"}.
create or replace function public._comprovante_banco_abrir(p_cmp uuid, p_motivo text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_av jsonb;
  v_opcoes jsonb;
  v_txs jsonb;
  v_abriu jsonb;
  v_pergunta jsonb;
begin
  select * into c from public.comprovantes x where x.id = p_cmp for update;
  if not found then
    raise exception '_comprovante_banco_abrir: comprovante % não existe', p_cmp using errcode = '22023';
  end if;
  v_av := public._comprovante_candidatos(c);
  update public.comprovantes x
     set banco_candidatos = coalesce(v_av->'linhas', '[]'::jsonb),
         banco_hash = v_av->>'hash',
         banco_avaliado_em = now(),
         conciliacao = coalesce(v_av->>'nivel', x.conciliacao),
         banco_perguntar = coalesce(v_av->>'nivel', 'cinza') <> 'cinza'
   where x.id = c.id;
  if v_av is null or v_av->>'nivel' = 'cinza' then
    return jsonb_build_object('perguntou', false, 'motivo', 'cinza');
  end if;
  if v_av->>'nivel' = 'verde' then
    select jsonb_build_array(jsonb_build_object('n', 1, 'rotulo', public._comprovante_banco_rotulo(l), 'valor', 'tx:' || (l->>'id'))),
           jsonb_build_array(l->>'id')
      into v_opcoes, v_txs
      from jsonb_array_elements(v_av->'linhas') l
     where (l->>'forte')::boolean
     limit 1;
  else
    select jsonb_agg(jsonb_build_object('n', (l->>'n')::integer, 'rotulo', public._comprovante_banco_rotulo(l), 'valor', 'tx:' || (l->>'id'))
                     order by (l->>'n')::integer)
             || jsonb_build_array(jsonb_build_object('n', 0, 'rotulo', 'Nenhuma destas', 'valor', 'nenhum')),
           jsonb_agg(l->>'id' order by (l->>'n')::integer)
      into v_opcoes, v_txs
      from jsonb_array_elements(v_av->'linhas') l;
  end if;
  v_abriu := public._pergunta_abrir(jsonb_build_object(
    'phone', c.phone_normalized, 'origem', 'comprovante', 'tipo', 'pergunta', 'referencia_id', c.id,
    'referencia_codigo', c.codigo, 'passo', 'banco', 'opcoes', v_opcoes,
    'dados', jsonb_build_object('nivel', v_av->>'nivel', 'hash', v_av->>'hash', 'regra', v_av->>'regra', 'tx', v_txs,
                                'motivo', left(coalesce(p_motivo, ''), 30)),
    'expira_em', now() + interval '2 hours'));
  if not coalesce((v_abriu->>'ok')::boolean, false) then
    return jsonb_build_object('perguntou', false, 'motivo', 'ocupado', 'ocupado_por', v_abriu->'ocupado_por');
  end if;
  select * into c from public.comprovantes x where x.id = c.id;
  v_pergunta := public._comprovante_banco_pergunta(c, (v_abriu->>'id')::uuid, v_av, p_motivo);
  update public.comprovantes x
     set banco_ultima_pergunta_em = now(),
         banco_perguntas = x.banco_perguntas + case when p_motivo = 'vigia' then 1 else 0 end
   where x.id = c.id;
  return jsonb_build_object('perguntou', true) || v_pergunta;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. A varredura (2.7). Trava 'comprovantes:banco' SEM ESPERAR: ocupada (o finance-review e o cron ao
--    mesmo tempo), pula os passos 1-6 e devolve só as reservadas — esperar a trava invertia a ordem
--    com a do telefone ('pergunta:', que a manutenção pega antes) e podia dar deadlock.
--    Roda a cada 2 min (cron) e em cada finance-review: só GRAVA quando algo mudou (nada de versão
--    nova de linha nem trava de linha do banco à toa — lição do incidente de I/O de 17/08):
--      1 re-valida as ligadas cuja linha ainda não virou lançamento (só lê; desliga quando mudou);
--      2 liga pela anotação aplicada / pelo lançamento do CMP que ganhou linha;
--      3 explica as ligadas: só quando a linha tem proposta pendente ou lançamento (a compra PENDING
--        do cartão espera ~13 dias sem nenhum dos dois) e só grava o que mudou; depois da aprovação
--        do dono, ADOTA o lançamento dele (nunca corrige categoria nem OS sem SIM);
--      4 reavalia as candidatas de quem espera (só lê) e grava só quando a lista, o nível ou o hash
--        mudaram (até p_limite gravações por rodada; as outras ficam para a próxima);
--      5 abandona; 6 notas que chegaram e as que só chegaram no e-mail.
--    Cada parte (e cada CMP) no seu bloco: falha numa vira aviso (só o sqlstate) e não desfaz as outras.
--    Devolve Varredura.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovantes_banco_varrer(p_limite integer, p_motivo text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r record;
  c public.comprovantes;
  v_lim integer := case when p_limite is null then null else greatest(p_limite, 1) end;
  v_conversa boolean := public._comprovante_conversa_ligada();
  v_manutencao boolean := coalesce(p_motivo, '') = 'manutencao';
  v_av jsonb;
  v_l jsonb;
  v_ant jsonb;
  v_novo jsonb;
  v_pend text[];
  v_novos jsonb;
  v_mudou boolean;
  v_mudou_lista boolean;
  v_explicada boolean;
  v_payable uuid;
  v_w uuid;
  v_t record;
  v_gravados integer := 0;
  n_avaliados integer := 0;
  n_ligados integer := 0;
  n_explicadas integer := 0;
  n_desligados integer := 0;
  n_verdes integer := 0;
  n_azuis integer := 0;
  n_cinzas integer := 0;
  n_abandonados integer := 0;
  n_so_registro integer := 0;
  n_notas integer := 0;
  n_classificadas integer := 0;
  v_perguntar jsonb := '[]'::jsonb;
  v_reservadas jsonb := '[]'::jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('comprovantes:banco', 0)) then
    -- a outra varredura já está fazendo isto agora: só as reservadas (o finance-review precisa delas)
    if not v_manutencao then
      select coalesce(jsonb_agg(distinct l->>'bank_transaction_id'), '[]'::jsonb) into v_reservadas
        from jsonb_array_elements(public.comprovantes_linhas_da_conciliacao(null)->'linhas') l;
    end if;
    return jsonb_build_object(
      'avaliados', 0, 'ligados', 0, 'explicadas', 0, 'desligados', 0, 'verdes', 0, 'azuis', 0, 'cinzas', 0,
      'abandonados', 0, 'so_registro', 0, 'notas', 0, 'perguntar', '[]'::jsonb, 'reservadas', v_reservadas,
      'classificadas', 0, 'ocupada', true);
  end if;

  -- ── 1. re-valida os ligados (só os de linha ainda sem lançamento: os outros não mudam mais) ──
  for r in
    select x.id, x.bank_transaction_id, x.valor_confirmado, x.dono_id, x.so_expense_id
      from public.comprovantes x
     where x.situacao = 'conciliado'
       and (x.bank_transaction_id is null
            or not exists (select 1 from public.payables p
                            where p.bank_transaction_id = x.bank_transaction_id and p.status <> 'cancelled'))
     order by x.numero
  loop
    begin
      if r.bank_transaction_id is null then
        -- a linha sumiu (a FK pôs nulo): o CMP volta a esperar o banco
        update public.comprovantes x
           set situacao = 'aguardando_banco', aguardando_banco_desde = now(), conciliado_em = null, linha_explicada_em = null,
               conciliacao = null, banco_avaliado_em = null, banco_hash = null,
               efeitos = coalesce((select jsonb_agg(case when e->>'tipo' = 'ligar_linha' and not e ? 'desligado_em'
                                                         then e || jsonb_build_object('desligado_em', now(), 'desligado_motivo', 'linha_sumiu')
                                                         else e end order by o)
                                     from jsonb_array_elements(x.efeitos) with ordinality as t(e, o)), '[]'::jsonb)
         where x.id = r.id;
        n_desligados := n_desligados + 1;
        continue;
      end if;
      select t.transaction_type, t.amount, t.installment_label, t.dismissed_kind into v_t
        from public.bank_transactions t where t.id = r.bank_transaction_id;
      if v_t.dismissed_kind is not null then
        -- o dono dispensou a linha no Extrato (duplicata, "lançada em dobro", estorno…): não é a compra
        -- deste CMP. Desliga sem recusar (dispensada nunca volta como candidata). Estornada: a compra
        -- foi desfeita no banco — a despesa da OS lançada pelo CMP fica para o dono decidir.
        perform public._comprovante_desligar(r.id, 'linha_dispensada', r.dono_id, false);
        if v_t.dismissed_kind = 'estornada' and r.so_expense_id is not null then
          update public.comprovantes x
             set pendencias = x.pendencias || 'conferir_estorno'::text
           where x.id = r.id and not ('conferir_estorno' = any (x.pendencias));
        end if;
        n_desligados := n_desligados + 1;
      elsif v_t.transaction_type <> 'debit'
            -- coalesce: sem parcela, a comparação não pode virar nulo (o "not" de nulo nunca desliga)
            or not (abs(v_t.amount - r.valor_confirmado) < 0.005
                    or (coalesce(v_t.installment_label, '') ~ '^1/([2-9]|[1-9][0-9])$'
                        and abs(v_t.amount * split_part(v_t.installment_label, '/', 2)::int - r.valor_confirmado)
                            <= 0.01 * split_part(v_t.installment_label, '/', 2)::int)) then
        perform public._comprovante_desligar(r.id, 'linha_mudou', r.dono_id, false);
        n_desligados := n_desligados + 1;
      elsif exists (select 1 from public.finance_review_queue q
                     where q.bank_transaction_id = r.bank_transaction_id and q.status = 'rejected')
            and not exists (select 1 from public.finance_review_queue q
                             where q.bank_transaction_id = r.bank_transaction_id and q.status = 'pending') then
        -- o dono recusou a proposta da linha no Extrato: não é desta compra
        perform public._comprovante_desligar(r.id, 'recusada_no_extrato', r.dono_id, true);
        n_desligados := n_desligados + 1;
      end if;
    exception when others then
      raise warning 'comprovantes: re-validar a ligação falhou: %', sqlstate;
    end;
  end loop;

  -- ── 2. liga pela anotação aplicada / pelo lançamento que ganhou linha (sem pergunta) ──────
  for r in
    select x.id, x.dono_id, a.bank_transaction_id as tx_anot, p.bank_transaction_id as tx_pay
      from public.comprovantes x
      left join public.anotacoes_do_extrato a
        on a.id = x.anotacao_id and a.status = 'aplicada' and a.bank_transaction_id is not null
      left join public.payables p
        on p.id = x.payable_id and p.status <> 'cancelled' and p.bank_transaction_id is not null
     where x.situacao in ('aguardando_banco', 'abandonado') and not x.banco_so_registro and x.bank_transaction_id is null
       and (a.id is not null or p.id is not null)
       -- a linha de outro CMP já deixou a pendência: não tenta de novo a cada rodada
       and not ('classificar_no_extrato' = any (x.pendencias)
                and exists (select 1 from public.comprovantes y
                             where y.bank_transaction_id = coalesce(p.bank_transaction_id, a.bank_transaction_id)
                               and y.id <> x.id and y.situacao <> 'cancelado'))
     order by x.numero
  loop
    begin
      v_l := public._comprovante_ligar(r.id, coalesce(r.tx_pay, r.tx_anot),
                                       case when r.tx_pay is not null then 'lancamento' else 'anotacao' end,
                                       'verde', r.dono_id, false);
      if coalesce((v_l->>'ligado')::boolean, false) then
        n_ligados := n_ligados + 1;
        if coalesce((v_l->>'explicada')::boolean, false) then n_explicadas := n_explicadas + 1; end if;
        if coalesce((v_l->>'aplicou')::boolean, false) then n_classificadas := n_classificadas + 1; end if;
      end if;
    exception when others then
      raise warning 'comprovantes: ligar pela anotação falhou: %', sqlstate;
    end;
  end loop;

  -- ── 3. explica as ligadas ainda sem explicação (ou cuja linha ganhou lançamento) ──────────
  for r in
    select x.id
      from public.comprovantes x
     where x.situacao = 'conciliado' and x.bank_transaction_id is not null
       and ((x.linha_explicada_em is null
             -- pré-checagem sem travar nada: só há o que explicar com proposta pendente ou lançamento
             and (exists (select 1 from public.finance_review_queue q
                           where q.bank_transaction_id = x.bank_transaction_id and q.status = 'pending')
                  or exists (select 1 from public.payables p
                              where p.bank_transaction_id = x.bank_transaction_id and p.status <> 'cancelled')))
            or (exists (select 1 from public.payables p
                         where p.bank_transaction_id = x.bank_transaction_id and p.status <> 'cancelled')
                and not exists (select 1 from public.payables p where p.id = x.payable_id and p.status <> 'cancelled')))
     order by x.numero
  loop
    begin
      select * into c from public.comprovantes x where x.id = r.id for update;
      v_l := public._comprovante_linha_explicar(c, c.bank_transaction_id, c.dono_id, false);
      select e into v_ant from jsonb_array_elements(c.efeitos) with ordinality as t(e, o)
       where e->>'tipo' = 'ligar_linha' and e->>'bank_transaction_id' = c.bank_transaction_id::text and not e ? 'desligado_em'
       order by o desc limit 1;
      -- o efeito novo por cima do anterior: origem, nível, quando ligou e o "como" ficam (o "como" só
      -- sai de "aguardando" para o que a explicação fez); o que veio vazio (nulo, falso, {} ou []) não
      -- apaga o de antes — o "corrigido" do SIM (o "antes" do cancelamento) nunca se perde
      select coalesce(v_ant, '{}'::jsonb) || coalesce(jsonb_object_agg(k.key, k.value), '{}'::jsonb) into v_novo
        from jsonb_each(v_l - '_explicada' - '_pendencia' - '_aviso' - '_erro' - '_aplicou' - '_conflito'
                            - 'origem' - 'nivel' - 'em' - 'como') k
       where k.value not in ('null'::jsonb, 'false'::jsonb, '{}'::jsonb, '[]'::jsonb);
      if v_l->>'como' is not null and coalesce(v_ant->>'como', 'aguardando') = 'aguardando' then
        v_novo := v_novo || jsonb_build_object('como', v_l->>'como');
      end if;
      v_explicada := coalesce((v_l->>'_explicada')::boolean, false);
      v_payable := coalesce((v_l->>'payable_id')::uuid, c.payable_id);
      v_pend := c.pendencias;
      v_novos := '[]'::jsonb;
      if v_l->>'_pendencia' is not null and not ((v_l->>'_pendencia') = any (v_pend)) then
        v_pend := v_pend || (v_l->>'_pendencia');
      elsif v_explicada and v_l->>'_pendencia' is null and 'classificar_no_extrato' = any (v_pend) then
        v_pend := array_remove(v_pend, 'classificar_no_extrato');
        v_novos := jsonb_build_array(jsonb_build_object('tipo', 'pendencia_resolvida', 'qual', 'classificar_no_extrato', 'em', now()));
      end if;
      -- só grava quando algo mudou
      if v_novo is distinct from coalesce(v_ant, '{}'::jsonb) or v_pend is distinct from c.pendencias
         or (v_explicada and c.linha_explicada_em is null) or v_payable is distinct from c.payable_id
         or (c.anotacao_id is null and v_l->>'anotacao_id' is not null) then
        update public.comprovantes x
           set linha_explicada_em = case when v_explicada then coalesce(x.linha_explicada_em, now()) else x.linha_explicada_em end,
               payable_id = v_payable,
               anotacao_id = coalesce(x.anotacao_id, (v_l->>'anotacao_id')::uuid),
               efeitos = public._comprovante_efeitos_com_ligacao(x.efeitos, v_novo) || v_novos,
               pendencias = v_pend
         where x.id = c.id;
      end if;
      if v_explicada and c.linha_explicada_em is null then
        n_explicadas := n_explicadas + 1;
      end if;
      if coalesce((v_l->>'_aplicou')::boolean, false) then
        n_classificadas := n_classificadas + 1;
      end if;
    exception when others then
      raise warning 'comprovantes: explicar a linha falhou: %', sqlstate;
    end;
  end loop;

  -- ── 4. candidatas de quem espera (e o registro do PESSOAL, até 30 dias): lê sempre, grava só a mudança ──
  for c in
    select x.*
      from public.comprovantes x
     where x.numero is not null and x.bank_transaction_id is null and x.banco_regra is not null
       and ((x.situacao = 'aguardando_banco' and not x.banco_so_registro)
            or (x.banco_so_registro and x.situacao <> 'cancelado' and x.gravado_em > now() - interval '30 days'))
       -- só quem pode ter candidata: nunca avaliado, a conversa ligou depois (hash nulo), já tinha
       -- candidata, ou há linha de saída do mesmo valor na janela (o cartão: também a parcela 1/n)
       and (x.banco_avaliado_em is null
            or (v_conversa and x.banco_hash is null and not x.banco_so_registro)
            or jsonb_array_length(x.banco_candidatos) > 0
            or exists (select 1 from public.bank_transactions t
                        where t.transaction_type = 'debit'
                          and t.transaction_date between x.data_confirmada - 1
                                                     and x.data_confirmada + case x.banco_regra when 'pix' then 1 when 'boleto' then 2
                                                                                                when 'debito' then 3 else 5 end
                          and (abs(t.amount - x.valor_confirmado) < 0.005
                               or (x.banco_regra = 'credito' and coalesce(t.installment_label, '') ~ '^1/'))))
     order by x.banco_avaliado_em nulls first, x.numero
  loop
    begin
      v_av := public._comprovante_candidatos(c);
      if v_av is null then
        if c.banco_perguntar or c.banco_avaliado_em is null then
          update public.comprovantes x set banco_perguntar = false, banco_avaliado_em = now() where x.id = c.id;
        end if;
        continue;
      end if;
      n_avaliados := n_avaliados + 1;
      if c.banco_so_registro then
        n_so_registro := n_so_registro + 1;
      elsif v_av->>'nivel' = 'verde' then
        n_verdes := n_verdes + 1;
      elsif v_av->>'nivel' = 'azul' then
        n_azuis := n_azuis + 1;
      else
        n_cinzas := n_cinzas + 1;
      end if;
      -- a pergunta muda quando o hash (com a conversa ligada) ou o nível mudam; a lista guardada, quando
      -- qualquer candidata mudou (ação, pendente, disputa…)
      v_mudou := (v_conversa and c.banco_hash is distinct from v_av->>'hash') or c.conciliacao is distinct from v_av->>'nivel';
      v_mudou_lista := c.banco_candidatos is distinct from coalesce(v_av->'linhas', '[]'::jsonb);
      if c.banco_avaliado_em is not null and not v_mudou and not v_mudou_lista then
        continue;
      end if;
      if v_lim is not null and v_gravados >= v_lim then
        continue;    -- o resto grava na próxima rodada
      end if;
      perform 1 from public.comprovantes x where x.id = c.id for update;
      update public.comprovantes x
         set banco_candidatos = coalesce(v_av->'linhas', '[]'::jsonb),
             -- sem conversa ligada só registra: o hash fica nulo para a pergunta sair quando ela ligar
             banco_hash = case when v_conversa then v_av->>'hash' end,
             banco_avaliado_em = now(),
             conciliacao = v_av->>'nivel',
             banco_perguntar = case when c.banco_so_registro or not v_conversa or v_av->>'nivel' = 'cinza' then false
                                    when v_mudou then true
                                    else x.banco_perguntar end
       where x.id = c.id and x.bank_transaction_id is null and x.situacao = c.situacao;
      v_gravados := v_gravados + 1;
      if v_mudou and not c.banco_so_registro then
        for v_w in
          select w.id from public.whatsapp_perguntas w
           where w.referencia_id = c.id and w.status = 'aberta' and w.origem = 'comprovante' and w.passo = 'banco'
        loop
          perform public._pergunta_fechar(v_w, 'substituida', 'linhas_mudaram', null);
        end loop;
      end if;
    exception when others then
      raise warning 'comprovantes: avaliar candidatas falhou: %', sqlstate;
    end;
  end loop;

  -- ── 5. abandono: 30 dias (45 no crédito) esperando ──────────────────────────────────────
  for r in
    select x.id, x.indice_mes, x.data_confirmada
      from public.comprovantes x
     where x.situacao = 'aguardando_banco'
       and x.aguardando_banco_desde < now() - case when x.banco_regra = 'credito' then interval '45 days' else interval '30 days' end
     order by x.numero
  loop
    begin
      update public.comprovantes x
         set situacao = 'abandonado',
             banco_perguntar = false,
             pendencias = case when 'classificar_no_extrato' = any (x.pendencias) then x.pendencias
                               else x.pendencias || 'classificar_no_extrato'::text end
       where x.id = r.id;
      for v_w in
        select w.id from public.whatsapp_perguntas w
         where w.referencia_id = r.id and w.status = 'aberta' and w.origem = 'comprovante' and w.passo = 'banco'
      loop
        perform public._pergunta_fechar(v_w, 'cancelada', 'abandonado', null);
      end loop;
      perform public._comprovante_indice_pendente(coalesce(r.indice_mes, r.data_confirmada));
      n_abandonados := n_abandonados + 1;
    exception when others then
      raise warning 'comprovantes: abandonar falhou: %', sqlstate;
    end;
  end loop;

  -- ── 6. NF-e: as notas que chegaram e as que só chegaram no e-mail ───────────────────────
  begin
    n_notas := public._comprovante_aplicar_notas_chegadas();
    -- o e-mail da nota chega perto da compra: só os recebidos desde uma semana antes dela (a tabela
    -- de e-mails cresce centenas de linhas por dia)
    update public.comprovantes x set nota_no_email_em = now()
     where x.situacao = 'aguardando_xml' and x.nota_no_email_em is null and x.chave_acesso is not null
       and not exists (select 1 from public.fiscal_notes fn
                        where fn.nfe_key = x.chave_acesso and fn.status in ('pending', 'confirmed'))
       and exists (select 1 from public.email_messages m
                    cross join lateral jsonb_array_elements(case when jsonb_typeof(m.dados_extraidos->'nfes') = 'array'
                                                                 then m.dados_extraidos->'nfes' else '[]'::jsonb end) n
                    where m.received_at >= coalesce(x.data_confirmada, (x.gravado_em at time zone 'America/Sao_Paulo')::date) - 7
                      and jsonb_typeof(n) = 'object' and n->>'chave' = x.chave_acesso);
  exception when others then
    raise warning 'comprovantes: notas que chegaram falhou: %', sqlstate;
  end;

  -- ── quem o vigia pode perguntar e as linhas reservadas (a manutenção do cron não usa: não calcula) ──
  if not v_manutencao then
    select coalesce(jsonb_agg(t.phone order by t.phone), '[]'::jsonb) into v_perguntar
      from (select distinct x.phone_normalized as phone
              from public.comprovantes x
             where x.banco_perguntar and x.situacao = 'aguardando_banco' and not x.banco_so_registro and x.banco_perguntas < 3
               and (x.banco_ultima_pergunta_em is null or x.banco_ultima_pergunta_em <= now() - interval '4 hours')) t
     where public._comprovante_banco_pode(t.phone) is null;
    select coalesce(jsonb_agg(distinct l->>'bank_transaction_id'), '[]'::jsonb) into v_reservadas
      from jsonb_array_elements(public.comprovantes_linhas_da_conciliacao(null)->'linhas') l;
  end if;

  return jsonb_build_object(
    'avaliados', n_avaliados, 'ligados', n_ligados, 'explicadas', n_explicadas, 'desligados', n_desligados,
    'verdes', n_verdes, 'azuis', n_azuis, 'cinzas', n_cinzas, 'abandonados', n_abandonados, 'so_registro', n_so_registro,
    'notas', n_notas, 'perguntar', v_perguntar, 'reservadas', v_reservadas, 'classificadas', n_classificadas,
    'ocupada', false);
end $$;

-- ---------------------------------------------------------------------------------------------
-- R1. comprovantes_reavaliar_banco: a varredura inteira (o finance-review chama logo depois de
--     aplicar_anotacoes_pendentes). A varredura grava como o dono de cada CMP; p_autor, quando vem,
--     só é conferido (admin ou financeiro).
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_reavaliar_banco(p_origem text default 'finance_review', p_autor uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_origem is null or p_origem !~ '^[a-z_]{1,30}$' then
    raise exception 'comprovantes_reavaliar_banco: origem inválida' using errcode = '22023';
  end if;
  if p_autor is not null and not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro reavalia os comprovantes.' using errcode = '42501';
  end if;
  return public._comprovantes_banco_varrer(null, p_origem);
end $$;

-- ---------------------------------------------------------------------------------------------
-- R2. comprovantes_linhas_da_conciliacao: as linhas que o finance-review não lança sozinho e as
--     anotações dos CMPs.
--       ligada    = ligada a CMP não cancelado e ainda SEM lançamento (a que já virou lançamento não
--                   pode mais ser lançada sozinha: devolvê-la só cresceria a lista para sempre);
--       candidata = só a FORTE de um CMP com pergunta pendente/aberta (nunca o PESSOAL). As fracas de
--                   um azul (pedágio de R$ 5,70, outra compra do mesmo valor) seguem o motor: reservá-las
--                   travava compras de outros até o dono responder ou o CMP ser abandonado.
--     conta_aberta_id = a conta a pagar em aberto que o CMP anexou (case pela Conciliação, não lance
--     outra); na candidata, o aprovar diz "pode ser a do CMP" (não "é").
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_linhas_da_conciliacao(p_transacoes uuid[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_linhas jsonb;
  v_anots jsonb;
begin
  with base as (
    select x.bank_transaction_id as tx, x.codigo, 'ligada'::text as papel,
           case when p.id is not null then p.id end as conta_aberta_id, 0 as prioridade, x.numero
      from public.comprovantes x
      left join public.payables p
        on p.id = x.payable_id and p.status in ('pending', 'overdue', 'partially_paid') and p.bank_transaction_id is null
     where x.bank_transaction_id is not null and x.situacao <> 'cancelado'
       and not exists (select 1 from public.payables l
                        where l.bank_transaction_id = x.bank_transaction_id and l.status <> 'cancelled')
    union all
    select (e->>'id')::uuid, x.codigo, 'candidata'::text,
           case when p.id is not null then p.id end, 1, x.numero
      from public.comprovantes x
      cross join lateral jsonb_array_elements(x.banco_candidatos) e
      left join public.payables p
        on p.id = x.payable_id and p.status in ('pending', 'overdue', 'partially_paid') and p.bank_transaction_id is null
     where x.situacao in ('aguardando_banco', 'abandonado') and not x.banco_so_registro
       and coalesce((e->>'forte')::boolean, false)
       and (x.banco_perguntar
            or exists (select 1 from public.whatsapp_perguntas w
                        where w.referencia_id = x.id and w.status = 'aberta' and w.origem = 'comprovante' and w.passo = 'banco'))
  ), uma as (
    select distinct on (b.tx) b.* from base b
     where b.tx is not null and (p_transacoes is null or b.tx = any (p_transacoes))
     order by b.tx, b.prioridade, b.numero
  )
  select coalesce(jsonb_agg(jsonb_build_object('bank_transaction_id', u.tx, 'codigo', u.codigo, 'papel', u.papel,
                                               'conta_aberta_id', u.conta_aberta_id) order by u.numero, u.tx), '[]'::jsonb)
    into v_linhas
    from uma u;

  select coalesce(jsonb_agg(distinct a.id), '[]'::jsonb) into v_anots
    from (select x.anotacao_id as id from public.comprovantes x
           where x.anotacao_id is not null and x.situacao <> 'cancelado'
          union all
          select (e->>'anotacao_id')::uuid from public.comprovantes x
           cross join lateral jsonb_array_elements(x.efeitos) e
           where x.situacao <> 'cancelado' and e->>'tipo' in ('ligar_linha', 'anotar', 'anexar_anotacao')
             and e->>'anotacao_id' is not null) a;

  return jsonb_build_object('linhas', v_linhas, 'anotacoes', v_anots);
end $$;

-- ---------------------------------------------------------------------------------------------
-- R3. comprovante_banco_proxima: abre a pergunta "apareceu no extrato, ligo?".
--     vigia = só com _comprovante_banco_pode (horário, espaçamento, F2 primeiro) e o CMP mais antigo
--     dentro do limite (3) e do espaçamento (4 h); os outros motivos são ação do dono ou continuação.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_banco_proxima(p_phone text, p_motivo text, p_cmp uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_pode text;
  v_cmp uuid := p_cmp;
  r record;
begin
  if p_motivo is null or p_motivo not in ('vigia', 'depois_de_gravar', 'pendentes', 'cmp', 'reabrir') then
    raise exception 'comprovante_banco_proxima: motivo inválido' using errcode = '22023';
  end if;
  if p_phone is null or p_phone !~ '^[0-9]{10,15}$' then
    raise exception 'comprovante_banco_proxima: telefone inválido' using errcode = '22023';
  end if;
  if not public._comprovante_conversa_ligada()
     or p_phone is distinct from (select d.phone from public._comprovante_dono() d) then
    return jsonb_build_object('perguntou', false, 'motivo', 'desligada');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || p_phone, 0));
  perform public._pergunta_limpar(p_phone);

  if p_motivo = 'vigia' then
    v_pode := public._comprovante_banco_pode(p_phone);
    if v_pode is not null then
      return jsonb_build_object('perguntou', false, 'motivo', v_pode);
    end if;
    select x.id into v_cmp from public.comprovantes x
     where x.phone_normalized = p_phone and x.banco_perguntar and x.situacao = 'aguardando_banco' and not x.banco_so_registro
       and x.banco_perguntas < 3
       and (x.banco_ultima_pergunta_em is null or x.banco_ultima_pergunta_em <= now() - interval '4 hours')
     order by x.gravado_em, x.numero
     limit 1;
  elsif v_cmp is not null then
    select x.id, x.phone_normalized, x.situacao, x.banco_so_registro into r from public.comprovantes x where x.id = v_cmp;
    if not found or r.phone_normalized <> p_phone or r.situacao not in ('aguardando_banco', 'abandonado') or r.banco_so_registro then
      return jsonb_build_object('perguntou', false, 'motivo', 'nao_pergunta');
    end if;
  else
    select x.id into v_cmp from public.comprovantes x
     where x.phone_normalized = p_phone and x.banco_perguntar and x.situacao in ('aguardando_banco', 'abandonado')
       and not x.banco_so_registro
     order by x.gravado_em, x.numero
     limit 1;
  end if;
  if v_cmp is null then
    return jsonb_build_object('perguntou', false, 'motivo', 'fila_vazia');
  end if;
  return public._comprovante_banco_abrir(v_cmp, p_motivo);
end $$;

-- ---------------------------------------------------------------------------------------------
-- R4. comprovante_banco_responder: a resposta do dono à pergunta da F3. Só vale a resposta mandada
--     DEPOIS de a pergunta chegar a ele; as linhas mudaram (hash/nível) = "mudou" e a pergunta nova.
--     Verde: sim liga, não recusa a linha, número/ok não liga. Azul: N liga a N-ésima, 0/não recusa
--     todas as listadas, sim/ok pede o número. Erro da rota = nao_ligado, nada muda.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_banco_responder(p jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  w record;
  c public.comprovantes;
  v_pid uuid;
  v_msg uuid;
  v_autor uuid;
  v_quando timestamptz;
  v_interp jsonb;
  v_tipo text;
  v_n integer;
  v_av jsonb;
  v_nivel text;
  v_txs uuid[];
  v_tx uuid;
  v_l jsonb;
  v_t text;
  v_prox jsonb;
  v_ate date;
  v_recusar uuid[];
begin
  if p is null or jsonb_typeof(p) <> 'object' or jsonb_typeof(p->'interpretacao') is distinct from 'object' then
    raise exception 'comprovante_banco_responder: entrada inválida' using errcode = '22023';
  end if;
  begin
    v_pid := (p->>'pergunta_id')::uuid;
    v_msg := nullif(p->>'message_id', '')::uuid;
    v_autor := nullif(p->>'autor', '')::uuid;
  exception when others then
    raise exception 'comprovante_banco_responder: pergunta_id, message_id ou autor malformado' using errcode = '22023';
  end;
  v_interp := p->'interpretacao';
  v_tipo := v_interp->>'tipo';
  if v_tipo is null or v_tipo not in ('opcao', 'sim', 'nao', 'ok') then
    raise exception 'comprovante_banco_responder: interpretação desconhecida' using errcode = '22023';
  end if;

  select x.id, x.phone_normalized, x.origem, x.passo, x.referencia_id into w
    from public.whatsapp_perguntas x where x.id = v_pid;
  if not found or w.origem <> 'comprovante' or w.passo is distinct from 'banco' then
    raise exception 'comprovante_banco_responder: pergunta % não é da linha do extrato', v_pid using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || w.phone_normalized, 0));
  select * into c from public.comprovantes x where x.id = w.referencia_id for update;
  if v_autor is null or v_autor is distinct from c.dono_id or not public.is_admin(v_autor) then
    raise exception 'Só o dono responde sobre o comprovante.' using errcode = '42501';
  end if;
  v_ate := (c.aguardando_banco_desde at time zone 'America/Sao_Paulo')::date + case when c.banco_regra = 'credito' then 45 else 30 end;
  if c.situacao = 'cancelado' or c.bank_transaction_id is not null then
    return jsonb_build_object('resultado', 'ignorada', 'cmp', public._comprovante_resumo(c), 'ligacao', null, 'proxima', null,
                              'motivo', case when c.situacao = 'cancelado' then 'cancelado' else 'ja_ligado' end, 'ate', null);
  end if;
  if not public._comprovante_conversa_ligada() then
    return jsonb_build_object('resultado', 'ignorada', 'cmp', public._comprovante_resumo(c), 'ligacao', null, 'proxima', null,
                              'motivo', 'desligada', 'ate', null);
  end if;
  if v_msg is not null then
    select m.occurred_at into v_quando from public.whatsapp_messages m where m.id = v_msg;
    if not found then
      v_msg := null;
    end if;
  end if;

  perform public._pergunta_limpar(w.phone_normalized);
  select x.id, x.phone_normalized, x.referencia_id, x.status, x.opcoes, x.dados, x.aberta_em, x.enviada_em into w
    from public.whatsapp_perguntas x where x.id = v_pid;

  -- a pergunta já fechou (venceu, foi substituída): mostra a de agora
  if w.status <> 'aberta' then
    v_prox := case when c.situacao in ('aguardando_banco', 'abandonado') and not c.banco_so_registro
                   then public._comprovante_banco_abrir(c.id, 'reabrir') end;
    select * into c from public.comprovantes x where x.id = c.id;
    return jsonb_build_object('resultado', 'invalida', 'cmp', public._comprovante_resumo(c), 'ligacao', null,
      'proxima', case when coalesce((v_prox->>'perguntou')::boolean, false) then v_prox - 'perguntou' end,
      'motivo', 'pergunta_fechada', 'ate', v_ate);
  end if;

  v_av := public._comprovante_candidatos(c);
  -- só vale o que o dono mandou depois de a pergunta chegar a ele
  if v_msg is null or w.enviada_em is null
     or v_quando < greatest(w.aberta_em + interval '2 seconds', w.enviada_em - interval '2 seconds') then
    return jsonb_build_object('resultado', 'invalida', 'cmp', public._comprovante_resumo(c), 'ligacao', null,
      'proxima', public._comprovante_banco_pergunta(c, w.id, v_av, 'reabrir'),
      'motivo', 'resposta_anterior_a_pergunta', 'ate', v_ate);
  end if;

  -- as linhas mudaram desde a pergunta: a pergunta nova (ou nada, se ficou cinza)
  if v_av is null or v_av->>'hash' is distinct from w.dados->>'hash' or v_av->>'nivel' is distinct from w.dados->>'nivel' then
    perform public._pergunta_fechar(w.id, 'substituida', 'linhas_mudaram', v_msg);
    v_prox := case when v_av is not null then public._comprovante_banco_abrir(c.id, 'reabrir') end;
    select * into c from public.comprovantes x where x.id = c.id;
    return jsonb_build_object('resultado', 'mudou', 'cmp', public._comprovante_resumo(c), 'ligacao', null,
      'proxima', case when coalesce((v_prox->>'perguntou')::boolean, false) then v_prox - 'perguntou' end,
      'motivo', 'linhas_mudaram', 'ate', v_ate);
  end if;

  v_nivel := w.dados->>'nivel';
  select coalesce(array_agg(x::uuid order by o), '{}'::uuid[]) into v_txs
    from jsonb_array_elements_text(coalesce(w.dados->'tx', '[]'::jsonb)) with ordinality as t(x, o);

  if v_nivel = 'verde' then
    if v_tipo = 'sim' then
      v_tx := v_txs[1];
    elsif v_tipo = 'nao' then
      v_recusar := v_txs[1:1];
    else
      -- número ou "ok" nunca ligam no verde: a pergunta continua
      return jsonb_build_object('resultado', 'ok_nao_aprova', 'cmp', public._comprovante_resumo(c), 'ligacao', null,
        'proxima', public._comprovante_banco_pergunta(c, w.id, v_av, 'reabrir'), 'motivo', null, 'ate', v_ate);
    end if;
  else
    if v_tipo = 'opcao' then
      begin
        v_n := (v_interp->>'n')::integer;
      exception when others then
        v_n := null;
      end;
      if v_n = 0 then
        v_recusar := v_txs;
      elsif v_n between 1 and cardinality(v_txs) then
        v_tx := v_txs[v_n];
      else
        return jsonb_build_object('resultado', 'invalida', 'cmp', public._comprovante_resumo(c), 'ligacao', null,
          'proxima', public._comprovante_banco_pergunta(c, w.id, v_av, 'reabrir'), 'motivo', 'opcao_fora', 'ate', v_ate);
      end if;
    elsif v_tipo = 'nao' then
      v_recusar := v_txs;
    else
      return jsonb_build_object('resultado', 'invalida', 'cmp', public._comprovante_resumo(c), 'ligacao', null,
        'proxima', public._comprovante_banco_pergunta(c, w.id, v_av, 'reabrir'), 'motivo', 'pede_numero', 'ate', v_ate);
    end if;
  end if;

  if v_tx is not null then
    begin
      v_l := public._comprovante_ligar(c.id, v_tx, case when v_nivel = 'verde' then 'sim' else 'escolha' end,
                                       v_nivel, v_autor, true);
      if not coalesce((v_l->>'ligado')::boolean, false) then
        raise exception 'nao_ligado:%', coalesce(v_l->>'motivo', 'linha_nao_serve');
      end if;
    exception when others then
      get stacked diagnostics v_t = message_text;
      select * into c from public.comprovantes x where x.id = c.id;
      return jsonb_build_object('resultado', 'nao_ligado', 'cmp', public._comprovante_resumo(c), 'ligacao', null, 'proxima', null,
                                'motivo', left(regexp_replace(v_t, '^nao_ligado:', ''), 200), 'ate', v_ate);
    end;
    update public.whatsapp_perguntas x set resposta_message_id = coalesce(x.resposta_message_id, v_msg) where x.id = w.id;
    select * into c from public.comprovantes x where x.id = c.id;
    return jsonb_build_object('resultado', 'ligado', 'cmp', public._comprovante_resumo(c), 'ligacao', v_l->'efeito',
                              'proxima', null, 'motivo', v_l->>'aviso', 'ate', null);
  end if;

  -- recusou: as linhas não voltam; a próxima avaliação procura outras
  update public.comprovantes x
     set banco_recusados = public._comprovante_recusar(x.banco_recusados, v_recusar),
         banco_perguntar = false,
         banco_hash = null,
         banco_avaliado_em = null
   where x.id = c.id;
  perform public._pergunta_fechar(w.id, 'respondida', null, v_msg);
  select * into c from public.comprovantes x where x.id = c.id;
  return jsonb_build_object('resultado', 'recusado', 'cmp', public._comprovante_resumo(c), 'ligacao', null, 'proxima', null,
                            'motivo', case when v_nivel = 'verde' then 'nao_e_essa' else 'nenhuma' end, 'ate', v_ate);
end $$;

-- ---------------------------------------------------------------------------------------------
-- R6. comprovantes_vigia_banco: telefones em que o vigia pode perguntar a F3 agora
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_vigia_banco(p_limite integer default 5)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  select coalesce(jsonb_agg(t.phone order by t.phone), '[]'::jsonb) into v
    from (select distinct x.phone_normalized as phone
            from public.comprovantes x
           where x.banco_perguntar and x.situacao = 'aguardando_banco' and not x.banco_so_registro and x.banco_perguntas < 3
             and (x.banco_ultima_pergunta_em is null or x.banco_ultima_pergunta_em <= now() - interval '4 hours')
           order by 1
           limit least(greatest(coalesce(p_limite, 5), 1), 50)) t
   where public._comprovante_banco_pode(t.phone) is null;
  return jsonb_build_object('perguntar', v);
end $$;

-- ---------------------------------------------------------------------------------------------
-- R10. comprovante_banco_ceder: chegou comprovante NOVO do dono e a pergunta aberta do telefone é a
--      do extrato (aberta pelo vigia, vale 2 h): ela cede a vez — fecha como "substituida" e a F2
--      pergunta o comprovante novo na hora (antes, ele ficava "na fila / ocupado com CMP-…" até a
--      pergunta do extrato fechar). O CMP continua com banco_perguntar: o vigia volta a ela depois
--      (horário, 4 h, limite de 3). Só a pergunta do extrato cede; a da F2 e a pendência do
--      assistente, não. {"cedeu":bool,"codigo"}.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_banco_ceder(p_phone text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  w record;
begin
  if p_phone is null or p_phone !~ '^[0-9]{10,15}$' then
    raise exception 'comprovante_banco_ceder: telefone inválido' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || p_phone, 0));
  select x.id, x.referencia_codigo into w
    from public.whatsapp_perguntas x
   where x.phone_normalized = p_phone and x.status = 'aberta' and x.origem = 'comprovante' and x.passo = 'banco'
   order by x.aberta_em desc
   limit 1;
  if not found then
    return jsonb_build_object('cedeu', false, 'codigo', null);
  end if;
  perform public._pergunta_fechar(w.id, 'substituida', 'cmp_novo', null);
  return jsonb_build_object('cedeu', true, 'codigo', w.referencia_codigo);
end $$;

-- ---------------------------------------------------------------------------------------------
-- extrato_da_conta: corpo de 20260928100000 IGUAL + a contraparte da linha sem nome = a loja do CMP
-- (bank_transactions.nome_pelo_comprovante; a view bank_transactions_situacao não tem a coluna).
-- A casca de hoje: sql, stable, invoker, search_path public, grants authenticated e service_role.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "public"."extrato_da_conta"("p_conexao" "uuid", "p_de" "date", "p_ate" "date") RETURNS TABLE("id" "uuid", "data" "date", "descricao" "text", "contraparte" "text", "documento" "text", "tipo" "text", "valor" numeric, "saldo_apos" numeric, "situacao" "text", "pendente" boolean, "lancamento_tipo" "text", "lancamento_id" "uuid", "lancamento_descricao" "text", "categoria" "text", "quem" "text", "tipo_fora" "text", "motivo_fora" "text", "proposta_id" "uuid")
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  with base as (
    select c.saldo_base from public.bank_connections c where c.id = p_conexao
  ),
  mov as (
    select t.*,
           (coalesce(t.tx_status, '') <> 'PENDING' and coalesce(t.dismissed_kind, '') not in ('duplicata', 'estornada')) as conta_no_saldo,
           case when t.transaction_type = 'credit' then t.amount else -t.amount end as com_sinal
      from public.bank_transactions_situacao t
     where t.bank_connection_id = p_conexao
       and coalesce(t.source_type, 'bank') in ('bank', 'cash')
  ),
  acumulado as (
    select m.*,
           sum(case when m.conta_no_saldo then m.com_sinal else 0 end)
             over (order by m.transaction_date, m.created_at, m.id rows unbounded preceding) as soma_ate_aqui
      from mov m
  )
  select a.id, a.transaction_date, a.description,
         coalesce(a.counterparty_name, a.merchant_name,
                  (select x.nome_pelo_comprovante from public.bank_transactions x where x.id = a.id)),
         a.counterparty_document, a.transaction_type,
         a.com_sinal,
         case when (select saldo_base from base) is null then null
              else round((select saldo_base from base) + a.soma_ate_aqui, 2) end,
         a.situacao, coalesce(a.tx_status, '') = 'PENDING',
         case when p.id is not null then 'payable' when r.id is not null then 'receivable' end,
         coalesce(p.id, r.id),
         coalesce(p.description, r.description),
         coalesce(p.expense_category, r.category),
         coalesce(s.name, pe.name, cl.name, p.supplier_name),
         a.dismissed_kind, a.dismissed_reason,
         q.id
    from acumulado a
    -- Uma linha do extrato é UMA linha aqui, mesmo com o Pix dividido em partes (pró-labore +
    -- retirada de sócio, 28/09/2026): mostra o lançamento principal e as categorias das partes.
    left join lateral (
      select p0.id, p0.description, p0.supplier_id, p0.payee_id, p0.supplier_name,
             (select string_agg(x.expense_category, ' + ' order by x.divisao_id nulls first, x.created_at, x.id)
                from public.payables x
               where x.bank_transaction_id = a.id and x.status <> 'cancelled') as expense_category
        from public.payables p0
       where p0.bank_transaction_id = a.id and p0.status <> 'cancelled'
       order by p0.divisao_id nulls first, p0.created_at, p0.id
       limit 1
    ) p on true
    left join public.receivables r on r.bank_transaction_id = a.id and r.status <> 'cancelled'
    left join public.suppliers s on s.id = p.supplier_id
    left join public.payees pe on pe.id = p.payee_id
    left join public.clients cl on cl.id = r.client_id
    left join lateral (
      select fq.id from public.finance_review_queue fq
       where fq.bank_transaction_id = a.id and fq.status = 'pending'
       order by fq.created_at desc limit 1
    ) q on true
   where a.transaction_date between p_de and p_ate
   order by a.transaction_date desc, a.created_at desc, a.id desc;
$$;

revoke all on function public.extrato_da_conta(uuid, date, date) from public, anon;
grant execute on function public.extrato_da_conta(uuid, date, date) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Privilégios (revogar de anon/authenticated POR ASSINATURA; helpers sem grant para ninguém)
-- ---------------------------------------------------------------------------------------------
revoke all on function public._comprovante_banco_regra(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_nomes(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_nome_da_linha(public.bank_transactions) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_linha_curta(uuid) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_banco_rotulo(jsonb) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_candidatos(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_recusar(uuid[], uuid[]) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_indice_pendente(date) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_efeitos_com_ligacao(jsonb, jsonb) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_linha_explicar(public.comprovantes, uuid, uuid, boolean) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_ligar(uuid, uuid, text, text, uuid, boolean) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_desligar(uuid, text, uuid, boolean) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_banco_pode(text) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_banco_resumo(public.comprovantes) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_banco_pergunta(public.comprovantes, uuid, jsonb, text) from public, anon, authenticated, service_role;
revoke all on function public._comprovante_banco_abrir(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public._comprovantes_banco_varrer(integer, text) from public, anon, authenticated, service_role;

revoke all on function public.comprovantes_reavaliar_banco(text, uuid) from public, anon, authenticated;
revoke all on function public.comprovantes_linhas_da_conciliacao(uuid[]) from public, anon, authenticated;
revoke all on function public.comprovante_banco_proxima(text, text, uuid) from public, anon, authenticated;
revoke all on function public.comprovante_banco_responder(jsonb) from public, anon, authenticated;
revoke all on function public.comprovantes_vigia_banco(integer) from public, anon, authenticated;
revoke all on function public.comprovante_banco_ceder(text) from public, anon, authenticated;
grant execute on function public.comprovantes_reavaliar_banco(text, uuid) to service_role;
grant execute on function public.comprovantes_linhas_da_conciliacao(uuid[]) to service_role;
grant execute on function public.comprovante_banco_proxima(text, text, uuid) to service_role;
grant execute on function public.comprovante_banco_responder(jsonb) to service_role;
grant execute on function public.comprovantes_vigia_banco(integer) to service_role;
grant execute on function public.comprovante_banco_ceder(text) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: R1-R4 e R6 só service_role; helpers sem grant; extrato_da_conta com os grants de hoje; as
-- rotas que a F3 reaproveita (anotação, conciliação) com assinatura e grants iguais.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
  v_rpcs text[] := array[
    'public.comprovantes_reavaliar_banco(text, uuid)',
    'public.comprovantes_linhas_da_conciliacao(uuid[])',
    'public.comprovante_banco_proxima(text, text, uuid)',
    'public.comprovante_banco_responder(jsonb)',
    'public.comprovantes_vigia_banco(integer)',
    'public.comprovante_banco_ceder(text)'];
  v_helpers text[] := array[
    'public._comprovante_banco_regra(public.comprovantes)',
    'public._comprovante_nomes(public.comprovantes)',
    'public._comprovante_nome_da_linha(public.bank_transactions)',
    'public._comprovante_linha_curta(uuid)',
    'public._comprovante_banco_rotulo(jsonb)',
    'public._comprovante_candidatos(public.comprovantes)',
    'public._comprovante_recusar(uuid[], uuid[])',
    'public._comprovante_indice_pendente(date)',
    'public._comprovante_efeitos_com_ligacao(jsonb, jsonb)',
    'public._comprovante_linha_explicar(public.comprovantes, uuid, uuid, boolean)',
    'public._comprovante_ligar(uuid, uuid, text, text, uuid, boolean)',
    'public._comprovante_desligar(uuid, text, uuid, boolean)',
    'public._comprovante_banco_pode(text)',
    'public._comprovante_banco_resumo(public.comprovantes)',
    'public._comprovante_banco_pergunta(public.comprovantes, uuid, jsonb, text)',
    'public._comprovante_banco_abrir(uuid, text)',
    'public._comprovantes_banco_varrer(integer, text)'];
begin
  foreach v_f in array v_rpcs || v_helpers loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função da conciliação dos comprovantes exposta para anon/authenticated: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs loop
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  foreach v_f in array v_helpers loop
    if has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'helper interno da conciliação alcançável pela service_role: %', v_f;
    end if;
  end loop;
  -- extrato_da_conta: a casca e os grants de hoje
  if has_function_privilege('anon', 'public.extrato_da_conta(uuid, date, date)', 'execute')
     or not has_function_privilege('authenticated', 'public.extrato_da_conta(uuid, date, date)', 'execute')
     or not has_function_privilege('service_role', 'public.extrato_da_conta(uuid, date, date)', 'execute') then
    raise exception 'extrato_da_conta com grants diferentes dos de hoje';
  end if;
  if (select prosecdef from pg_proc where oid = 'public.extrato_da_conta(uuid, date, date)'::regprocedure)
     or (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang
          where p.oid = 'public.extrato_da_conta(uuid, date, date)'::regprocedure) <> 'sql' then
    raise exception 'extrato_da_conta mudou de casca (deve seguir sql e invoker)';
  end if;
  -- as rotas que a F3 reaproveita: assinatura e grants iguais
  if to_regprocedure('public._aplicar_anotacao(uuid, uuid)') is null
     or to_regprocedure('public.conciliar_lancamento(text, uuid, uuid, uuid)') is null
     or to_regprocedure('public.aplicar_anotacoes_pendentes()') is null then
    raise exception 'uma rota que a F3 reaproveita mudou de assinatura';
  end if;
  if has_function_privilege('anon', 'public._aplicar_anotacao(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public._aplicar_anotacao(uuid, uuid)', 'execute')
     or not has_function_privilege('service_role', 'public._aplicar_anotacao(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.aplicar_anotacoes_pendentes()', 'execute')
     or has_function_privilege('authenticated', 'public.aplicar_anotacoes_pendentes()', 'execute')
     or not has_function_privilege('service_role', 'public.aplicar_anotacoes_pendentes()', 'execute')
     or has_function_privilege('anon', 'public.conciliar_lancamento(text, uuid, uuid, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.conciliar_lancamento(text, uuid, uuid, uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.conciliar_lancamento(text, uuid, uuid, uuid)', 'execute') then
    raise exception 'grants das rotas da anotação/conciliação mudaram';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011302000', 'comprovantes_conciliacao_rpcs')
on conflict do nothing;
