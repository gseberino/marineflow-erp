-- Anotação que não chuta, reavaliação que pode limpar a OS (26/09/2026).
--
-- Decisões do dono de 26/09/2026: "o sistema nunca pode sugerir ou lançar alguma transação com
-- nomes diferentes" e a ligação com o serviço "deve sempre questionar". A revisão adversarial
-- achou três furos no banco:
--
-- 1. A anotação ("o Pix de 1.500 é da TSD") casava com a linha só por sentido, valor e data —
--    e, com duas candidatas, ficava com a de data mais próxima. Um Pix de R$ 1.500 para a
--    KAMELL (CNPJ reconhecido) podia virar TSD, e o da TSD ficar sem nada. Agora: o documento
--    do cadastro anotado também filtra; linha cujo fornecedor/favorecido/cliente foi provado
--    POR DOCUMENTO e é outro fica de fora; e com mais de uma candidata nada é aplicado — o
--    assistente pergunta a data exata ou o CPF/CNPJ.
-- 2. A OS dita na anotação se perdia na aprovação. Agora ela vai junto na evidência
--    (evidencia.anotacao.os_id) e a aprovação a lê da própria anotação.
-- 3. A reavaliação nunca LIMPAVA a OS sugerida (coalesce): uma OS que não vale mais seguia
--    perguntando "é desta OS?". O motor manda o valor certo (inclusive nenhum).
--
-- Segunda revisão (mesmo dia): anotação ambígua não fica esperando para ser aplicada sozinha à
-- linha que sobrar (é cancelada, com a pergunta); data DITA vale como data exata (±1 dia);
-- linha já anotada não é sobrescrita; linha com outra pessoa/empresa reconhecida (por qualquer
-- prova) ou com OUTRO nome no extrato não é tomada; e, quando nenhuma serve, a resposta diz
-- em nome de quem a transação chegou.
--
-- Terceira revisão (mesmo dia): o nome cortado só vale com o corte provado (Pix no limite de
-- ~30 letras, como no motor); anotação repetida ou de correção é recusada com o porquê (não
-- fica esperando para cair na próxima transação); duas anotações que disputam a mesma
-- transação são canceladas; matriz e filial (mesma raiz de CNPJ) são a mesma empresa.
--
-- Quarta revisão (mesmo dia): UM teste de identidade (_identidade_serve) em todos os caminhos.
-- Anotação que não diz quem (só OS ou categoria) vale só para linha sem nome e sem ninguém
-- reconhecido — a OS de um cliente não vai para o Pix de outro; numa entrada com OS, o "quem"
-- é o cliente da OS. "Já lançada" e "já anotada" só olham a transação de MESMA identidade, e
-- a correção do que foi dito nunca cai na outra linha por eliminação. A mesma coisa dita de
-- novo (mesma pessoa, valor e dias) substitui a anterior. Os cancelamentos da varredura ficam
-- com hora (cancelada_em) para o resumo das 07:30 contar.

-- ── Documento comparável ────────────────────────────────────────────────────────────────
-- Só dígitos, com o zero à esquerda que a planilha comeu (13 → 14, 10 → 11).
create or replace function public._doc_normalizado(p text)
returns text
language sql
immutable
set search_path = public
as $$
  select case length(d) when 13 then lpad(d, 14, '0') when 10 then lpad(d, 11, '0') else d end
    from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x;
$$;

-- Os dois têm documento e NÃO são a mesma pessoa/empresa. CNPJ compara a raiz (filiais).
create or replace function public._documento_contradiz(a text, b text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select case
    when length(x) < 11 or length(y) < 11 then false
    when length(x) <> length(y) then true
    when length(x) = 14 then left(x, 8) <> left(y, 8)
    else x <> y
  end
  from (select public._doc_normalizado(a) as x, public._doc_normalizado(b) as y) z;
$$;

-- ── Data dita = data exata ──────────────────────────────────────────────────────────────
alter table public.anotacoes_do_extrato add column if not exists data_exata boolean not null default false;
-- Por que a anotação foi cancelada sem ser aplicada (ambígua na hora, ou quando as transações chegaram).
alter table public.anotacoes_do_extrato add column if not exists motivo_cancelamento text;

-- ── Nome comparável (como o limparNome do motor) ─────────────────────────────────────────
-- Sem anotação entre parênteses, sem acento, caixa alta, sem pontuação e sem sufixo societário.
create or replace function public._nome_comparavel(p text)
returns text
language sql
immutable
set search_path = public
as $$
  select btrim(regexp_replace(regexp_replace(regexp_replace(
           upper(translate(regexp_replace(coalesce(p, ''), '\([^)]*\)', ' ', 'g'),
             'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
             'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN')),
           '[^A-Z0-9 ]', ' ', 'g'),
           '\m(LTDA|ME|EPP|EIRELI|SA|S A|CIA)\M', ' ', 'g'),
           '\s+', ' ', 'g'));
$$;

-- O nome de quem recebeu/pagou na linha: o campo próprio, ou o que está na descrição
-- ("Pix enviado para JOSE CARLOS ABEL").
create or replace function public._nome_da_linha(p_nome text, p_descricao text)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(btrim(coalesce(nullif(btrim(coalesce(p_nome, '')), ''),
    substring(coalesce(p_descricao, '') from '(?i)^(?:pix|ted|doc|transf\w*)\s+(?:enviad[oa]|recebid[oa]|realizad[oa])\s+(?:para|de|por)\s+(.{3,})$'),
    '')), '');
$$;

-- ── Mesma empresa: matriz e filiais (mesma raiz de CNPJ) ─────────────────────────────────
create or replace function public._mesma_empresa(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select length(public._doc_normalizado(s1.cnpj_cpf)) = 14
       and left(public._doc_normalizado(s1.cnpj_cpf), 8) = left(public._doc_normalizado(s2.cnpj_cpf), 8)
      from public.suppliers s1, public.suppliers s2
     where s1.id = p_a and s2.id = p_b), false);
$$;

-- ── Quando a anotação foi cancelada: o resumo das 07:30 conta as que a VARREDURA cancelou ──
alter table public.anotacoes_do_extrato add column if not exists cancelada_em timestamptz;

-- ── Quem a anotação diz ─────────────────────────────────────────────────────────────────
-- A pessoa/empresa dita — e, numa ENTRADA com OS sem cliente dito, o cliente da OS: "o Pix de
-- 800 é da OS-60" diz, sem dizer, que o dinheiro veio do cliente da OS-60.
create or replace function public._quem_da_anotacao(p_anotacao uuid)
returns table (q_fornecedor uuid, q_favorecido uuid, q_cliente uuid, q_doc text, q_nomes text[], q_diz_quem boolean)
language sql
stable
security definer
set search_path = public
as $$
  select an.fornecedor_id, an.favorecido_id, cli.id,
         public._doc_normalizado(coalesce(an.documento, f.cnpj_cpf, pe.document, cli.cpf_cnpj)),
         array_remove(array[public._nome_comparavel(f.name), public._nome_comparavel(f.trade_name),
                            public._nome_comparavel(pe.name), public._nome_comparavel(cli.name)], ''),
         (an.fornecedor_id is not null or an.favorecido_id is not null or cli.id is not null)
    from public.anotacoes_do_extrato an
    left join public.suppliers f on f.id = an.fornecedor_id
    left join public.payees pe on pe.id = an.favorecido_id
    left join public.service_orders so on so.id = an.os_id and an.sentido = 'credit' and an.cliente_id is null
    left join public.clients cli on cli.id = coalesce(an.cliente_id, so.client_id)
   where an.id = p_anotacao;
$$;

-- ── Esta linha pode ser a transação desta anotação? (identidade) ────────────────────────
-- UMA regra para todos os caminhos (candidatas, já lançada, já anotada, varredura):
--   · o documento DITO tem de ser o da linha; o do cadastro não pode ser contradito;
--   · a anotação diz QUEM: a linha não pode ter outra parte reconhecida (por qualquer prova),
--     nem OUTRO nome no extrato (vale o mesmo nome, o mesmo documento, ou o nome cortado
--     provado — Pix no limite de ~30 letras, como no motor);
--   · a anotação NÃO diz quem (só OS ou categoria): só linha sem ninguém reconhecido e sem
--     nome no extrato ("DEBITO DE CARTAO", "TRANSF ENVIADA PIX"). Pix com nome exige que a
--     pessoa diga para quem foi — senão a OS de um cliente iria para o dinheiro de outro
--     (quarta revisão de 26/09/2026; decisões P1 e P2 do dono).
create or replace function public._identidade_serve(
  p_anotacao uuid, p_tx uuid, p_fornecedor uuid, p_favorecido uuid, p_cliente uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select (an.documento is null or public._doc_normalizado(t.counterparty_document) = public._doc_normalizado(an.documento))
       and not public._documento_contradiz(t.counterparty_document, qd.q_doc)
       and case
         when not qd.q_diz_quem then
           p_fornecedor is null and p_favorecido is null and p_cliente is null
           and public._nome_da_linha(t.counterparty_name, t.description) is null
         else
           (case when qd.q_fornecedor is null then p_fornecedor is null
                 else p_fornecedor is null or p_fornecedor = qd.q_fornecedor
                      or public._mesma_empresa(p_fornecedor, qd.q_fornecedor) end)
           and coalesce(p_favorecido, qd.q_favorecido) is not distinct from qd.q_favorecido
           and coalesce(p_cliente, qd.q_cliente) is not distinct from qd.q_cliente
           and (
             public._nome_da_linha(t.counterparty_name, t.description) is null
             -- Documento dos dois lados, sem contradição (mesmo CPF, ou mesma raiz de CNPJ).
             or (length(qd.q_doc) >= 11 and length(public._doc_normalizado(t.counterparty_document)) >= 11)
             or exists (
               select 1 from unnest(qd.q_nomes) n
                where n = public._nome_comparavel(public._nome_da_linha(t.counterparty_name, t.description))
                   or (length(btrim(public._nome_da_linha(t.counterparty_name, t.description))) >= 29
                       and length(public._nome_comparavel(public._nome_da_linha(t.counterparty_name, t.description))) >= 25
                       and n like public._nome_comparavel(public._nome_da_linha(t.counterparty_name, t.description)) || '%')))
       end
      from public.anotacoes_do_extrato an
      cross join lateral public._quem_da_anotacao(an.id) qd
      join public.bank_transactions t on t.id = p_tx
     where an.id = p_anotacao), false);
$$;

-- ── Candidatas de uma anotação ──────────────────────────────────────────────────────────
-- Mesmo sentido, valor ao centavo, a janela (data DITA: ±1 dia; sem data: -3/+7) e a
-- identidade. Linha já anotada fica de fora — salvo para PERGUNTAR se ela é "a mesma".
create or replace function public._candidatas_da_anotacao(p_anotacao uuid, p_incluir_anotadas boolean default false)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select q.id
    from public.anotacoes_do_extrato a
    join public.bank_transactions t on t.transaction_type = a.sentido
     and abs(t.amount - a.valor) < 0.01
     and t.transaction_date between a.data_prevista - case when a.data_exata then 1 else 3 end
                                and a.data_prevista + case when a.data_exata then 1 else 7 end
    join public.finance_review_queue q on q.bank_transaction_id = t.id and q.status = 'pending'
     and q.kind = case when a.sentido = 'debit' then 'create_payable' else 'create_receivable' end
   where a.id = p_anotacao
     and (p_incluir_anotadas or not (coalesce(q.evidencia, '{}'::jsonb) ? 'anotacao'))
     and public._identidade_serve(a.id, t.id, q.suggested_supplier_id, q.suggested_payee_id, q.suggested_client_id);
$$;

-- Na janela há uma linha JÁ ANOTADA que poderia ser esta (mesma identidade)? Então esta é
-- repetição ou correção do que foi dito — nunca se aplica à OUTRA linha por eliminação.
create or replace function public._janela_tem_linha_anotada(p_anotacao uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public._candidatas_da_anotacao(p_anotacao, true) c
      join public.finance_review_queue q on q.id = c
     where coalesce(q.evidencia, '{}'::jsonb) ? 'anotacao');
$$;

-- Outra anotação ESPERANDO o mesmo dinheiro que não se separa desta quando chegar: mesmo
-- sentido e valor, janelas que se cruzam, documentos que não se contradizem, e ao menos uma
-- das duas sem dizer quem. (Quem diferente se separa pelo nome no extrato; quem IGUAL é a
-- mesma coisa dita de novo — _anotacoes_repetidas_esperando.)
create or replace function public._anotacoes_gemeas_esperando(p_anotacao uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select b.id
    from public.anotacoes_do_extrato a
    cross join lateral public._quem_da_anotacao(a.id) qa
    join public.anotacoes_do_extrato b
      on b.id <> a.id and b.status = 'aguardando'
     and b.sentido = a.sentido and abs(b.valor - a.valor) < 0.01
     and b.data_prevista - case when b.data_exata then 1 else 3 end <= a.data_prevista + case when a.data_exata then 1 else 7 end
     and a.data_prevista - case when a.data_exata then 1 else 3 end <= b.data_prevista + case when b.data_exata then 1 else 7 end
    cross join lateral public._quem_da_anotacao(b.id) qb
   where a.id = p_anotacao
     and not public._documento_contradiz(qa.q_doc, qb.q_doc)
     and not (qa.q_diz_quem and qb.q_diz_quem);
$$;

-- Outra anotação ESPERANDO com a MESMA pessoa/empresa, mesmo valor e dias que se cruzam: é a
-- mesma coisa dita de novo (em geral, agora com o CPF/CNPJ). A nova substitui a anterior —
-- cancelar as duas e pedir o documento de novo seria um laço.
create or replace function public._anotacoes_repetidas_esperando(p_anotacao uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select b.id
    from public.anotacoes_do_extrato a
    cross join lateral public._quem_da_anotacao(a.id) qa
    join public.anotacoes_do_extrato b
      on b.id <> a.id and b.status = 'aguardando'
     and b.sentido = a.sentido and abs(b.valor - a.valor) < 0.01
     and b.data_prevista - case when b.data_exata then 1 else 3 end <= a.data_prevista + case when a.data_exata then 1 else 7 end
     and a.data_prevista - case when a.data_exata then 1 else 3 end <= b.data_prevista + case when b.data_exata then 1 else 7 end
    cross join lateral public._quem_da_anotacao(b.id) qb
   where a.id = p_anotacao
     and qa.q_diz_quem and qb.q_diz_quem
     and not public._documento_contradiz(qa.q_doc, qb.q_doc)
     and (qa.q_fornecedor is not distinct from qb.q_fornecedor or public._mesma_empresa(qa.q_fornecedor, qb.q_fornecedor))
     and qa.q_favorecido is not distinct from qb.q_favorecido
     and qa.q_cliente is not distinct from qb.q_cliente;
$$;

-- Outras anotações ESPERANDO que querem a mesma transação desta: qual é de qual é pergunta.
create or replace function public._anotacoes_em_disputa(p_anotacao uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select b.id
    from public.anotacoes_do_extrato b
   where b.status = 'aguardando' and b.id <> p_anotacao
     and exists (select 1 from public._candidatas_da_anotacao(b.id) cb
                  where cb in (select ca from public._candidatas_da_anotacao(p_anotacao) ca));
$$;

-- A transação desta anotação: só quando é UMA. Duas de mesmo valor na janela é pergunta.
create or replace function public._proposta_da_anotacao(p_anotacao uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select case when count(*) = 1 then (array_agg(c))[1] end
    from public._candidatas_da_anotacao(p_anotacao) c;
$$;

-- ── Aplicar: a OS dita vai junto na evidência; numa entrada, o cliente é o da OS ─────────
create or replace function public._aplicar_anotacao(p_anotacao uuid, p_proposta uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  a public.anotacoes_do_extrato%rowtype;
  v_dre text;
  v_cliente_da_os uuid;
begin
  select * into a from public.anotacoes_do_extrato where id = p_anotacao;
  if a.categoria is not null then
    select dre_group into v_dre from public.financial_categories where name = a.categoria and active limit 1;
  end if;
  if a.sentido = 'credit' and a.os_id is not null then
    select client_id into v_cliente_da_os from public.service_orders where id = a.os_id;
  end if;
  update public.finance_review_queue q set
    suggested_supplier_id = coalesce(a.fornecedor_id, q.suggested_supplier_id),
    suggested_payee_id = coalesce(a.favorecido_id, q.suggested_payee_id),
    suggested_client_id = coalesce(a.cliente_id, v_cliente_da_os, q.suggested_client_id),
    suggested_service_order_id = coalesce(a.os_id, q.suggested_service_order_id),
    suggested_category = coalesce(a.categoria, q.suggested_category),
    dre_group = coalesce(v_dre, q.dre_group),
    suggested_description = coalesce(a.descricao, q.suggested_description),
    confidence = 99,
    reasoning = left('Anotado por você em ' || to_char(a.criada_em at time zone 'America/Sao_Paulo', 'DD/MM')
                     || coalesce(': ' || a.descricao, '') || ' · ' || coalesce(q.reasoning, ''), 2000),
    evidencia = coalesce(q.evidencia, '{}'::jsonb) - 'cadastrar'
                || jsonb_build_object('anotacao', jsonb_strip_nulls(jsonb_build_object('id', a.id, 'os_id', a.os_id))),
    updated_at = now()
  where q.id = p_proposta and q.status = 'pending';
  update public.anotacoes_do_extrato
     set status = 'aplicada', aplicada_em = now(),
         bank_transaction_id = (select bank_transaction_id from public.finance_review_queue where id = p_proposta)
   where id = p_anotacao;
end;
$$;

-- ── Anotar ──────────────────────────────────────────────────────────────────────────────
create or replace function public.anotar_transacao(
  p_sentido text,                 -- 'saida' | 'entrada'
  p_valor numeric,
  p_data date default null,
  p_documento text default null,
  p_nome text default null,
  p_fornecedor_id uuid default null,
  p_favorecido_id uuid default null,
  p_cliente_id uuid default null,
  p_categoria text default null,
  p_os_id uuid default null,
  p_descricao text default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_id uuid;
  v_proposta uuid;
  v_candidatas integer;
  v_outros text;
  v_diz_quem boolean;
  v_doc text := nullif(regexp_replace(coalesce(p_documento, ''), '\D', '', 'g'), '');
  v_valor text := translate(to_char(p_valor, 'FM999,999,990.00'), ',.', '.,');
  v_lancada record;
  v_substituidas integer := 0;
  v_aviso text := '';
begin
  if p_sentido not in ('saida', 'entrada') then raise exception 'Sentido inválido: % (saida ou entrada).', p_sentido; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'O valor precisa ser maior que zero.'; end if;
  if v_doc is not null and length(v_doc) not in (11, 14) then raise exception 'CPF tem 11 dígitos e CNPJ tem 14.'; end if;
  if p_categoria is null and p_fornecedor_id is null and p_favorecido_id is null and p_cliente_id is null and p_os_id is null then
    raise exception 'Diga o que classificar: fornecedor, favorecido, cliente, categoria ou OS.';
  end if;

  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, data_exata, documento, nome, fornecedor_id, favorecido_id,
                                           cliente_id, categoria, os_id, descricao, criada_por)
  values (case when p_sentido = 'saida' then 'debit' else 'credit' end, round(p_valor, 2), coalesce(p_data, public._hoje_brt()),
          p_data is not null,
          v_doc, nullif(btrim(coalesce(p_nome, '')), ''), p_fornecedor_id, p_favorecido_id, p_cliente_id,
          nullif(btrim(coalesce(p_categoria, '')), ''), p_os_id, nullif(btrim(coalesce(p_descricao, '')), ''), v_autor)
  returning id into v_id;
  select q_diz_quem into v_diz_quem from public._quem_da_anotacao(v_id);

  -- 0. A mesma coisa dita de novo (mesma pessoa, valor e dias): a nova substitui a anterior.
  update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
         motivo_cancelamento = 'substituída por uma anotação nova igual (mesma pessoa, valor e dias)'
   where id in (select public._anotacoes_repetidas_esperando(v_id));
  get diagnostics v_substituidas = row_count;
  if v_substituidas > 0 then
    v_aviso := 'Troquei a anotação anterior igual (mesma pessoa e valor) por esta. Se eram dois pagamentos diferentes, '
      || 'classifique pela tela quando chegarem. ';
  end if;

  -- 1. Uma linha que PODE ser esta já foi anotada: é repetição ou correção do que foi dito.
  --    Troca se faz pela tela — e nunca na outra linha, por eliminação.
  if public._janela_tem_linha_anotada(v_id) then
    update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
           motivo_cancelamento = 'a transação já tinha uma anotação; troca se faz pela tela'
     where id = v_id;
    return jsonb_build_object('ok', false, 'id', v_id, 'aplicada', false, 'ja_anotada', true,
      'message', format('A transação de R$ %s desses dias já foi anotada antes. Para trocar o que foi dito, '
        || 'corrija a linha pela tela do Extrato.', v_valor));
  end if;

  -- 2. Já chegou do banco e está na fila? Aplica agora — se for UMA transação só, e se nenhuma
  --    outra anotação sua estiver esperando essa mesma transação.
  v_proposta := public._proposta_da_anotacao(v_id);
  if v_proposta is not null and exists (select 1 from public._anotacoes_em_disputa(v_id)) then
    update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
           motivo_cancelamento = 'outra anotação esperava a mesma transação; qual é de qual é pergunta'
     where id = v_id or id in (select public._anotacoes_em_disputa(v_id));
    return jsonb_build_object('ok', false, 'id', v_id, 'aplicada', false, 'disputa', true,
      'message', format('Já havia outra anotação sua esperando uma transação de R$ %s nesses dias. Para não trocar uma '
        || 'pela outra, não apliquei nenhuma das duas: classifique pela tela ou me diga o CPF/CNPJ de cada uma.', v_valor));
  end if;
  if v_proposta is not null then
    perform public._aplicar_anotacao(v_id, v_proposta);
    return jsonb_build_object('ok', true, 'id', v_id, 'aplicada', true, 'proposta_id', v_proposta, 'substituidas', v_substituidas,
      'message', v_aviso || 'A transação já tinha chegado do banco: a linha do Extrato foi classificada como você disse. Falta aprovar.');
  end if;

  -- 3. Mais de uma serve: pergunta, e não fica esperando para cair na que sobrar.
  select count(*) into v_candidatas from public._candidatas_da_anotacao(v_id);
  if v_candidatas > 1 then
    update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
           motivo_cancelamento = format('%s transações do mesmo valor nesses dias', v_candidatas)
     where id = v_id;
    return jsonb_build_object('ok', false, 'id', v_id, 'aplicada', false, 'ambigua', true, 'candidatas', v_candidatas,
      'message', format('Há %s transações de R$ %s nesses dias na fila do Extrato. Não anotei para não errar: '
        || 'diga o dia exato ou o CPF/CNPJ de quem recebeu e eu anoto de novo — ou classifique pela tela.', v_candidatas, v_valor));
  end if;

  -- 4. Já chegou E já virou lançamento — e é ESTA (mesma identidade)? Então é correção.
  select coalesce(p.id, r.id) id, case when p.id is not null then 'payable' else 'receivable' end tipo into v_lancada
    from public.anotacoes_do_extrato a
    join public.bank_transactions t on t.transaction_type = a.sentido
     and abs(t.amount - a.valor) < 0.01
     and t.transaction_date between a.data_prevista - case when a.data_exata then 1 else 3 end
                                and a.data_prevista + case when a.data_exata then 1 else 7 end
    left join public.payables p on p.bank_transaction_id = t.id and p.status <> 'cancelled'
    left join public.receivables r on r.bank_transaction_id = t.id and r.status <> 'cancelled'
   where a.id = v_id
     and coalesce(p.id, r.id) is not null
     and public._identidade_serve(v_id, t.id, p.supplier_id, p.payee_id, r.client_id)
   limit 1;
  if v_lancada.id is not null then
    update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(), motivo_cancelamento = 'a transação já foi lançada'
     where id = v_id;
    return jsonb_build_object('ok', false, 'ja_lancada', true, 'lancamento_id', v_lancada.id, 'tipo', v_lancada.tipo,
      'message', 'Essa transação já chegou e já foi lançada. Para mudar fornecedor ou categoria, corrija o lançamento.');
  end if;

  -- 5. Outra anotação sua já espera o mesmo dinheiro sem nada que as separe: são DOIS
  --    pagamentos iguais, e quando chegarem não haverá como saber qual é qual. As duas saem.
  if exists (select 1 from public._anotacoes_gemeas_esperando(v_id)) then
    update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
           motivo_cancelamento = 'duas anotações do mesmo valor nos mesmos dias; diga de novo com o CPF/CNPJ de cada uma'
     where id = v_id or id in (select public._anotacoes_gemeas_esperando(v_id));
    return jsonb_build_object('ok', false, 'id', v_id, 'aplicada', false, 'gemea', true,
      'message', format('Já havia outra anotação sua esperando uma transação de R$ %s nesses dias. Para eu saber qual é '
        || 'qual quando chegarem, cancelei as duas: me diga de novo, com o CPF/CNPJ de quem recebeu cada uma '
        || '(ou classifique pela tela quando chegarem).', v_valor));
  end if;

  -- 6. A transação desses dias que está na fila é de outro: dizer em nome de quem (o cadastro
  --    reconhecido, ou o nome do extrato — nunca o texto genérico do banco).
  select string_agg(distinct coalesce(sf.name, pe.name, cl.name, public._nome_da_linha(t.counterparty_name, t.description)), '; ')
    into v_outros
    from public.anotacoes_do_extrato a
    join public.bank_transactions t on t.transaction_type = a.sentido
     and abs(t.amount - a.valor) < 0.01
     and t.transaction_date between a.data_prevista - case when a.data_exata then 1 else 3 end
                                and a.data_prevista + case when a.data_exata then 1 else 7 end
    join public.finance_review_queue q on q.bank_transaction_id = t.id and q.status = 'pending'
    left join public.suppliers sf on sf.id = q.suggested_supplier_id
    left join public.payees pe on pe.id = q.suggested_payee_id
    left join public.clients cl on cl.id = q.suggested_client_id
   where a.id = v_id;
  if v_outros is not null and not v_diz_quem then
    return jsonb_build_object('ok', true, 'id', v_id, 'aplicada', false, 'outra_contraparte', v_outros, 'falta_quem', true,
      'message', format('Chegou uma transação de R$ %s nesses dias de/para %s. Como você não disse para quem foi, não mexi '
        || 'nela: se é essa, me diga de novo com o nome (ex.: "o Pix de %s do %s é …"). Se não é, deixei anotado para quando a outra chegar.',
        v_valor, left(v_outros, 80), v_valor, split_part(v_outros, ';', 1)));
  end if;
  if v_outros is not null then
    return jsonb_build_object('ok', true, 'id', v_id, 'aplicada', false, 'outra_contraparte', v_outros, 'substituidas', v_substituidas,
      'message', v_aviso || format('A transação de R$ %s desses dias que está na fila é de outro (%s), então não mexi nela. '
        || 'Deixei anotado: quando a que você disse chegar do banco, entra classificada. Se for aquela mesma, classifique pela tela.',
        v_valor, left(v_outros, 120)));
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'aplicada', false, 'substituidas', v_substituidas,
    'message', v_aviso || 'Anotado. Quando a transação chegar do banco, ela já entra classificada.');
end;
$$;

-- ── Varredura diária: anotação que ficou ambígua é cancelada, nunca aplicada por eliminação ──
-- A anotação feita ANTES de a transação chegar espera. Se chegam duas do mesmo valor, qual é
-- a certa é pergunta — e, se uma delas sair da fila, a outra não pode receber o que foi dito
-- só por ter sobrado. O motivo e a hora ficam gravados: o resumo das 07:30 conta essas.
create or replace function public.aplicar_anotacoes_pendentes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  v_proposta uuid;
  v_candidatas integer;
  v_n integer := 0;
begin
  for a in select id from public.anotacoes_do_extrato where status = 'aguardando' order by criada_em loop
    -- Já cancelada nesta mesma varredura (por disputa com outra): pula.
    if (select status from public.anotacoes_do_extrato where id = a.id) <> 'aguardando' then continue; end if;
    select count(*) into v_candidatas from public._candidatas_da_anotacao(a.id);
    if v_candidatas > 1 then
      update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
             motivo_cancelamento = format('chegaram %s transações do mesmo valor; diga qual pela tela ou anote de novo com o CPF/CNPJ', v_candidatas)
       where id = a.id;
      continue;
    end if;
    -- Na janela já há uma linha ANOTADA que podia ser esta (mesma identidade): pode ter sido
    -- dita para aquela mesma transação. Aplicar na que sobrou seria escolher por eliminação.
    if v_candidatas = 1 and public._janela_tem_linha_anotada(a.id) then
      update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
             motivo_cancelamento = 'uma transação desse valor nesses dias já tinha outra anotação; diga qual é pela tela'
       where id = a.id;
      continue;
    end if;
    -- Outra anotação esperando quer a mesma transação: não se escolhe por ordem de chegada.
    if v_candidatas = 1 and exists (select 1 from public._anotacoes_em_disputa(a.id)) then
      update public.anotacoes_do_extrato set status = 'cancelada', cancelada_em = now(),
             motivo_cancelamento = 'duas anotações esperavam a mesma transação; diga qual é qual pela tela'
       where id = a.id or id in (select public._anotacoes_em_disputa(a.id));
      continue;
    end if;
    v_proposta := public._proposta_da_anotacao(a.id);
    if v_proposta is not null then
      perform public._aplicar_anotacao(a.id, v_proposta);
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$$;

-- ── Reavaliação: a OS sugerida é a do motor de agora (inclusive nenhuma) ────────────────
create or replace function public.aplicar_reavaliacao_da_fila(p_linhas jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer;
begin
  update public.finance_review_queue q set
    suggested_category = coalesce(l.suggested_category, q.suggested_category),
    dre_group = coalesce(l.dre_group, q.dre_group),
    suggested_supplier_id = l.suggested_supplier_id,
    suggested_payee_id = l.suggested_payee_id,
    suggested_client_id = l.suggested_client_id,
    -- O motor manda o valor certo: a OS da OC (preservada por ele) ou a do vínculo — ou
    -- nenhuma. O coalesce antigo deixava para sempre uma pergunta "é desta OS?" que não valia.
    suggested_service_order_id = l.suggested_service_order_id,
    applied_rule_id = l.applied_rule_id,
    confidence = coalesce(l.confidence, q.confidence),
    reasoning = coalesce(l.reasoning, q.reasoning),
    evidencia = l.evidencia,
    vinculo_sugerido = l.vinculo_sugerido,
    updated_at = now()
  from jsonb_to_recordset(p_linhas) as l(
    id uuid, suggested_category text, dre_group text, suggested_supplier_id uuid,
    suggested_payee_id uuid, suggested_client_id uuid, suggested_service_order_id uuid,
    applied_rule_id uuid, confidence integer, reasoning text, evidencia jsonb, vinculo_sugerido jsonb)
  where q.id = l.id and q.status = 'pending';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- ── Quem executa ────────────────────────────────────────────────────────────────────────
revoke all on function public._mesma_empresa(uuid, uuid) from public, anon, authenticated;
grant execute on function public._mesma_empresa(uuid, uuid) to service_role;
revoke all on function public._anotacoes_repetidas_esperando(uuid) from public, anon, authenticated;
grant execute on function public._anotacoes_repetidas_esperando(uuid) to service_role;
revoke all on function public._anotacoes_gemeas_esperando(uuid) from public, anon, authenticated;
grant execute on function public._anotacoes_gemeas_esperando(uuid) to service_role;
revoke all on function public._janela_tem_linha_anotada(uuid) from public, anon, authenticated;
grant execute on function public._janela_tem_linha_anotada(uuid) to service_role;
revoke all on function public._anotacoes_em_disputa(uuid) from public, anon, authenticated;
grant execute on function public._anotacoes_em_disputa(uuid) to service_role;
revoke all on function public._nome_comparavel(text) from public, anon;
revoke all on function public._nome_da_linha(text, text) from public, anon;
grant execute on function public._nome_comparavel(text) to authenticated, service_role;
grant execute on function public._nome_da_linha(text, text) to authenticated, service_role;
revoke all on function public._doc_normalizado(text) from public, anon;
revoke all on function public._documento_contradiz(text, text) from public, anon;
revoke all on function public._candidatas_da_anotacao(uuid, boolean) from public, anon, authenticated;
revoke all on function public._quem_da_anotacao(uuid) from public, anon, authenticated;
revoke all on function public._identidade_serve(uuid, uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public._proposta_da_anotacao(uuid) from public, anon, authenticated;
revoke all on function public._aplicar_anotacao(uuid, uuid) from public, anon, authenticated;
revoke all on function public.anotar_transacao(text, numeric, date, text, text, uuid, uuid, uuid, text, uuid, text, uuid) from public, anon;
revoke all on function public.aplicar_reavaliacao_da_fila(jsonb) from public, anon, authenticated;
revoke all on function public.aplicar_anotacoes_pendentes() from public, anon, authenticated;
grant execute on function public.aplicar_anotacoes_pendentes() to service_role;
grant execute on function public._doc_normalizado(text) to authenticated, service_role;
grant execute on function public._documento_contradiz(text, text) to authenticated, service_role;
grant execute on function public._candidatas_da_anotacao(uuid, boolean) to service_role;
grant execute on function public._quem_da_anotacao(uuid) to service_role;
grant execute on function public._identidade_serve(uuid, uuid, uuid, uuid, uuid) to service_role;
grant execute on function public._proposta_da_anotacao(uuid) to service_role;
grant execute on function public._aplicar_anotacao(uuid, uuid) to service_role;
grant execute on function public.anotar_transacao(text, numeric, date, text, text, uuid, uuid, uuid, text, uuid, text, uuid) to authenticated, service_role;
grant execute on function public.aplicar_reavaliacao_da_fila(jsonb) to service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260926220000', 'anotacao_pergunta_e_reavaliacao')
on conflict do nothing;
