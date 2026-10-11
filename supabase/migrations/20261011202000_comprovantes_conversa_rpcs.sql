-- Comprovantes F2 (11/10/2026): a conversa com o dono (contrato BANCO ↔ EDGE da F2).
--
-- Cada CMP lido entra na fila do telefone do dono; o sistema pergunta um passo de cada vez (menus
-- numerados, o código CMP em toda mensagem), mostra o resumo do que VAI fazer e só grava depois do
-- sim (a gravação mora em 20261011203000). O edge interpreta o texto (Interpretacao, 2.3 da spec);
-- o banco valida contra o passo aberto. "ok" nunca aprova; o sim só vale para a versão que o dono viu.
--
--   6  comprovante_conversa_entrar(ids)            CMPs lidos entram na fila (pré-preenche pela legenda)
--   7  comprovante_proxima_pergunta(phone, m, cmp)  abre a próxima pergunta (vigia: horário, pausa, espaçamento)
--   8  comprovante_pergunta_nao_enviada(id)        o envio não confirmou: a pergunta volta para a fila
--   9  comprovante_responder(p)                    aplica a resposta ao passo; no sim, grava
--   10 comprovante_comando(p)                      cmp N, pular, sair, lote antigo, cancelar, feito, corrigir
--   11 comprovantes_pendentes(phone)               lista do "pendentes"
--   12 comprovante_cnpj_cache(cnpj, dados)         grava a consulta da BrasilAPI e o nome nos CMPs
--   13 comprovantes_cnpj_a_consultar(ids, limite)  CNPJs sem cache válido
--   14 comprovantes_consultar(p)                   leitura do assistente (admin; authenticated + service_role)
--   15 comprovantes_parecidos(valor, data, os, a)  CMPs parecidos com um lançamento (as travas do assistente)
--
-- Helpers internos (sem grant): _comprovante_normalizar, _comprovante_tipo_no_texto, _comprovante_e_nfe,
-- _comprovante_os_info, _comprovante_os_por_numero, _comprovante_ler_dica, _comprovante_menu_para_que,
-- _comprovante_categoria_provavel, _comprovante_socio, _comprovante_tecnicos, _comprovante_efetivo,
-- _comprovante_fornecedor, _comprovante_proximo_passo, _comprovante_resumo, _comprovante_opcoes_do_passo,
-- _comprovante_montar_pergunta, _comprovante_entrar_na_fila, _comprovante_abrir_pergunta,
-- _comprovante_vigia_pode, _comprovante_cmp_da_vigia, _comprovante_proxima.
--
-- Todas security definer, search_path vazio, execute só para service_role (14 e 15 também para
-- authenticated, com checagem de admin dentro). Nenhuma devolve leitura, leitura_texto nem wa_key.
-- Nenhum log com texto do dono, valor, CNPJ ou nome. Não escreve dados. Idempotente.

-- ---------------------------------------------------------------------------------------------
-- Helpers puros
-- ---------------------------------------------------------------------------------------------

-- minúsculas, sem acento, tudo que não é letra/número vira um espaço
create or replace function public._comprovante_normalizar(p text)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select btrim(regexp_replace(
    lower(translate(coalesce(p, ''),
      'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
      'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN')),
    '[^a-z0-9]+', ' ', 'g'));
$$;

-- O nome sem CPF (revisão de 11/10/2026): na Receita, a razão social do MEI costuma trazer o CPF do
-- titular ("FULANO DA SILVA 12345678900") ou o CNPJ básico na frente ("12.345.678 FULANO DA SILVA").
-- Esse nome vai para o arquivo no Dropbox, para o _INDICE do mês, para a descrição do lançamento e
-- para o WhatsApp: tira o CPF solto (com ou sem pontuação) e o prefixo de 8 dígitos. Vazio = nulo.
create or replace function public._comprovante_sem_cpf(p text)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select nullif(btrim(regexp_replace(
    regexp_replace(
      regexp_replace(' ' || coalesce(p, '') || ' ', '\s\d{3}\.?\d{3}\.?\d{3}-?\d{2}(?=\s)', ' ', 'g'),
      '^\s*\d{2}\.?\d{3}\.?\d{3}\s+', ''),
    '\s+', ' ', 'g')), '');
$$;

-- o tipo como o dono lê (o TIPO_NO_AVISO da F1, _shared/comprovantes/nucleo.ts)
create or replace function public._comprovante_tipo_no_texto(p_tipo text)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select case p_tipo
    when 'nfce' then 'cupom NFC-e'
    when 'nfe_danfe' then 'nota fiscal (DANFE)'
    when 'nfe_xml' then 'XML de nota fiscal'
    when 'nfse' then 'nota fiscal de serviço'
    when 'cupom_nao_fiscal' then 'cupom não fiscal'
    when 'pix' then 'comprovante de Pix'
    when 'boleto_pago' then 'comprovante de boleto pago'
    when 'boleto' then 'boleto'
    when 'cartao' then 'via de cartão'
    when 'fatura' then 'fatura'
    when 'guia' then 'guia'
    when 'recibo' then 'recibo'
    when 'agendado' then 'pagamento agendado'
    when 'pedido' then 'pedido'
    else 'documento' end;
$$;

-- doc NF-e (modelo 55 com chave): a OS vai pela linha da nota, nunca por despesa da OS
create or replace function public._comprovante_e_nfe(c public.comprovantes)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(c.tipo in ('nfe_xml', 'nfe_danfe') and c.chave_acesso is not null
                  and substr(c.chave_acesso, 21, 2) = '55', false);
$$;

-- ---------------------------------------------------------------------------------------------
-- OS
-- ---------------------------------------------------------------------------------------------

-- O que a conversa precisa saber de uma OS. faturada = concluída/faturada (o total não muda mais);
-- assinada = assinada pelo cliente e ainda não faturada (incluir no total pede nova assinatura).
create or replace function public._comprovante_os_info(p_os uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r record;
  v_faturada boolean;
begin
  if p_os is null then
    return null;
  end if;
  select so.id, so.service_order_number, so.status, so.invoicing_status, so.signed_at, so.vessel_id, so.client_id,
         nullif(btrim(v.name), '') as barco,
         coalesce(nullif(btrim(cl.display_name), ''), nullif(btrim(cl.name), '')) as cliente
    into r
    from public.service_orders so
    left join public.vessels v on v.id = so.vessel_id
    left join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
  if not found then
    return null;
  end if;
  v_faturada := r.status in ('completed', 'invoiced') or coalesce(r.invoicing_status, 'not_invoiced') <> 'not_invoiced';
  return jsonb_build_object(
    'id', r.id,
    'numero', r.service_order_number,
    'barco', r.barco,
    'cliente', r.cliente,
    'status', r.status,
    'faturada', v_faturada,
    'assinada', r.signed_at is not null and not v_faturada,
    'pasta_registrada', exists (select 1 from public.pastas_dropbox p
                                 where p.vessel_id = r.vessel_id and p.situacao = 'vinculada'),
    'vessel_id', r.vessel_id,
    'client_id', r.client_id,
    'aberta', r.status in ('open', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client', 'approved'));
end $$;

-- "os 112" → a OS. Devolve {"id"} ou {"motivo":"os_nao_existe|os_cancelada|os_rascunho"}.
create or replace function public._comprovante_os_por_numero(p_numero integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r record;
begin
  if p_numero is null or p_numero <= 0 then
    return jsonb_build_object('motivo', 'os_nao_existe');
  end if;
  select so.id, so.status into r
    from public.service_orders so
   where substring(so.service_order_number from '([0-9]+)$')::integer = p_numero
   order by (so.status in ('cancelled', 'draft')), so.created_at desc
   limit 1;
  if not found then
    return jsonb_build_object('motivo', 'os_nao_existe');
  elsif r.status = 'cancelled' then
    return jsonb_build_object('motivo', 'os_cancelada');
  elsif r.status = 'draft' then
    return jsonb_build_object('motivo', 'os_rascunho');
  end if;
  return jsonb_build_object('id', r.id);
end $$;

-- ---------------------------------------------------------------------------------------------
-- O que a legenda já diz (nunca adivinha "quem pagou" por texto livre)
--   * 1ª palavra da legenda: empresa/adm → empresa; estoque, insumo, pessoal → o próprio;
--   * "os 112" na dica ou na legenda → a OS (se existe e não é cancelada/rascunho);
--   * sem número: o nome (≥ 4 letras, palavra inteira) de EXATAMENTE um barco ativo com
--     EXATAMENTE uma OS aberta → essa OS.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_ler_dica(p_legenda text, p_dica text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_leg text := public._comprovante_normalizar(p_legenda);
  v_texto text := btrim(public._comprovante_normalizar(p_dica) || ' ' || public._comprovante_normalizar(p_legenda));
  v_primeira text;
  v_num text;
  v_os jsonb;
  v_barcos uuid[];
  v_oss uuid[];
begin
  if v_texto = '' then
    return '{}'::jsonb;
  end if;
  v_primeira := split_part(v_leg, ' ', 1);
  if v_primeira in ('empresa', 'adm') then
    return jsonb_build_object('destino', 'empresa');
  elsif v_primeira in ('estoque', 'insumo') then
    return jsonb_build_object('destino', v_primeira);
  elsif v_primeira = 'pessoal' and array_length(regexp_split_to_array(v_leg, ' '), 1) <= 2 then
    -- só a legenda curta ("pessoal", "pessoal gasolina"): "Pessoal almoçou no Brisa" é coloquial e
    -- a compra é da OS — com texto a mais, segue para o número da OS e o nome do barco (e pergunta)
    return jsonb_build_object('destino', 'pessoal');
  end if;

  v_num := (regexp_match(v_texto, '(^|\s)os\s*0*([0-9]{1,6})'))[2];
  if v_num is not null then
    v_os := public._comprovante_os_por_numero(v_num::integer);
    if v_os ? 'id' then
      return jsonb_build_object('destino', 'os', 'os_id', v_os->>'id', 'os_numero', v_num::integer);
    end if;
    return '{}'::jsonb;
  end if;

  -- o nome de EXATAMENTE um barco ativo (palavra inteira, ≥ 4 letras) com EXATAMENTE uma OS aberta
  select array_agg(v.id) into v_barcos
    from public.vessels v
   where v.active
     and char_length(regexp_replace(public._comprovante_normalizar(v.name), '[^a-z]', '', 'g')) >= 4
     and (' ' || v_texto || ' ') like ('% ' || public._comprovante_normalizar(v.name) || ' %');
  if coalesce(cardinality(v_barcos), 0) = 1 then
    select array_agg(so.id) into v_oss
      from public.service_orders so
     where so.vessel_id = v_barcos[1]
       and so.status in ('open', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client', 'approved');
    if coalesce(cardinality(v_oss), 0) = 1 then
      return jsonb_build_object('destino', 'os', 'os_id', v_oss[1]);
    end if;
  end if;
  return '{}'::jsonb;
end $$;

-- Menu "para quê": até 5 OS sem repetir (a da dica; abertas cujo barco aparece na dica; abertas
-- por atualização; concluídas/faturadas dos últimos 30 dias) e depois os fixos.
create or replace function public._comprovante_menu_para_que(c public.comprovantes)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_texto text := btrim(public._comprovante_normalizar(c.dica_da_legenda) || ' ' || public._comprovante_normalizar(c.legenda));
  v_dica_os uuid := nullif(public._comprovante_ler_dica(c.legenda, c.dica_da_legenda)->>'os_id', '')::uuid;
  v_os jsonb;
  v_n integer := 0;
  v_menu jsonb := '[]'::jsonb;
  r record;
begin
  for r in
    with candidatas as (
      select so.id, 1 as prioridade, so.updated_at as quando
        from public.service_orders so where so.id = v_dica_os
      union all
      select so.id, 2, so.updated_at
        from public.service_orders so
        join public.vessels v on v.id = so.vessel_id
       where v_texto <> ''
         and so.status in ('open', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client', 'approved')
         and char_length(regexp_replace(public._comprovante_normalizar(v.name), '[^a-z]', '', 'g')) >= 4
         and (' ' || v_texto || ' ') like ('% ' || public._comprovante_normalizar(v.name) || ' %')
      union all
      select so.id, 3, so.updated_at
        from public.service_orders so
       where so.status in ('open', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client', 'approved')
      union all
      select so.id, 4, coalesce(so.check_out_at, so.updated_at)
        from public.service_orders so
       where so.status in ('completed', 'invoiced')
         and coalesce(so.check_out_at, so.updated_at) >= now() - interval '30 days'
    ), uma as (
      select distinct on (id) id, prioridade, quando from candidatas order by id, prioridade, quando desc
    ), fechada as (
      -- um lugar fica para a OS concluída/faturada mais recente (com 5 abertas, ela sumiria do menu)
      select id from uma where prioridade = 4 order by quando desc, id limit 1
    ), as_outras as (
      select id, prioridade, quando from uma where id not in (select f.id from fechada f)
       order by prioridade, quando desc, id
       limit (5 - (select count(*) from fechada))
    )
    select t.id from (
      select o.id, o.prioridade, o.quando from as_outras o
      union all
      select u.id, u.prioridade, u.quando from uma u join fechada f on f.id = u.id
    ) t
    order by t.prioridade, t.quando desc, t.id
  loop
    v_os := public._comprovante_os_info(r.id);
    v_n := v_n + 1;
    v_menu := v_menu || jsonb_build_array(jsonb_build_object(
      'n', v_n,
      'rotulo', (v_os->>'numero') || ' · ' || coalesce(v_os->>'barco', v_os->>'cliente', 'sem barco')
                || case when v_os->>'status' = 'invoiced' or (v_os->>'faturada')::boolean and v_os->>'status' <> 'completed'
                          then ' (faturada)'
                        when v_os->>'status' = 'completed' then ' (concluída)'
                        else '' end,
      'valor', 'os:' || r.id));
  end loop;
  return v_menu || jsonb_build_array(
    jsonb_build_object('n', v_n + 1, 'rotulo', 'Estoque', 'valor', 'estoque'),
    jsonb_build_object('n', v_n + 2, 'rotulo', 'Insumo', 'valor', 'insumo'),
    jsonb_build_object('n', v_n + 3, 'rotulo', 'Empresa (sem OS)', 'valor', 'empresa'),
    jsonb_build_object('n', v_n + 4, 'rotulo', 'Pessoal', 'valor', 'pessoal'));
end $$;

-- ---------------------------------------------------------------------------------------------
-- Categoria, sócio, técnicos
-- ---------------------------------------------------------------------------------------------

-- A categoria de sempre do fornecedor: ≥ 2 lançamentos e ≥ 60% dos dos últimos 365 dias, ativa.
create or replace function public._comprovante_categoria_provavel(p_supplier uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cat text;
begin
  if p_supplier is null then
    return null;
  end if;
  with base as (
    select p.expense_category as cat
      from public.payables p
     where p.supplier_id = p_supplier and p.status <> 'cancelled'
       and p.issue_date >= (now() at time zone 'America/Sao_Paulo')::date - 365
  ), contagem as (
    select cat, count(*) as n, sum(count(*)) over () as total from base group by cat
  )
  select k.cat into v_cat
    from contagem k
   where k.cat is not null and k.n >= 2 and k.n >= 0.6 * k.total
     and exists (select 1 from public.financial_categories f
                  where f.name = k.cat and f.type = 'payable' and coalesce(f.active, false))
   order by k.n desc
   limit 1;
  return v_cat;
end $$;

-- O sócio que pagou do bolso: o favorecido ligado ao usuário do dono; senão o ÚNICO sócio ativo.
create or replace function public._comprovante_socio(p_dono uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v uuid;
  v_n integer;
begin
  select p.id into v from public.payees p where p.active and p.app_user_id = p_dono
   order by (p.kind = 'socio') desc, p.created_at limit 1;
  if v is not null then
    return v;
  end if;
  select count(*), min(p.id::text)::uuid into v_n, v from public.payees p where p.active and p.kind = 'socio';
  return case when v_n = 1 then v end;
end $$;

-- Técnicos para o menu: favorecidos ativos com perfil de trabalho vigente, por nome, até 6.
create or replace function public._comprovante_tecnicos()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('n', t.n, 'rotulo', t.name, 'valor', 'payee:' || t.id) order by t.n), '[]'::jsonb)
    into v
    from (select p.id, p.name, row_number() over (order by p.name, p.id) as n
            from public.payees p
           where p.active
             and exists (select 1 from public.work_profiles wp
                          where wp.payee_id = p.id
                            and (wp.vigencia_fim is null
                                 or wp.vigencia_fim >= (now() at time zone 'America/Sao_Paulo')::date))
           order by p.name, p.id
           limit 6) t;
  return v;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Os valores que valem (o que o dono respondeu, ou o padrão que o resumo mostra):
--   quem = o respondido; sem resposta = empresa (o resumo diz "se não foi a empresa: corrigir quem");
--   pagador = o respondido; sócio sem resposta = _comprovante_socio; técnico único = ele;
--   categoria = a respondida; senão os → provável ou "Peças e materiais"; estoque → "Compras de
--   mercadorias"; insumo → "Materiais e Insumos Operacionais"; empresa → provável; pessoal → nenhuma.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_efetivo(c public.comprovantes)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_quem text;
  v_pagador uuid := c.pagador_payee_id;
  v_cat text := nullif(btrim(coalesce(c.categoria, '')), '');
  v_tecnicos jsonb;
  v_ativa boolean := true;
begin
  v_quem := case when c.destino is null or c.destino = 'pessoal' then c.quem_pagou
                 else coalesce(c.quem_pagou, 'empresa') end;
  if v_pagador is null and v_quem = 'socio' then
    v_pagador := public._comprovante_socio(c.dono_id);
  elsif v_pagador is null and v_quem = 'tecnico' then
    v_tecnicos := public._comprovante_tecnicos();
    if jsonb_array_length(v_tecnicos) = 1 then
      v_pagador := substr(v_tecnicos->0->>'valor', 7)::uuid;
    end if;
  end if;
  if v_cat is null then
    v_cat := case c.destino
               when 'os' then coalesce(public._comprovante_categoria_provavel(c.supplier_id), 'Peças e materiais')
               when 'estoque' then 'Compras de mercadorias'
               when 'insumo' then 'Materiais e Insumos Operacionais'
               when 'empresa' then public._comprovante_categoria_provavel(c.supplier_id)
               else null end;
  end if;
  if v_cat is not null then
    v_ativa := exists (select 1 from public.financial_categories f
                        where lower(f.name) = lower(v_cat) and f.type = 'payable' and coalesce(f.active, false));
  end if;
  return jsonb_build_object(
    'quem', v_quem,
    'pagador_id', v_pagador,
    'pagador_nome', (select p.name from public.payees p where p.id = v_pagador),
    'categoria', v_cat,
    'categoria_ativa', v_ativa);
end $$;

-- O fornecedor que aparece: do cadastro, senão da Receita (BrasilAPI, cache); nunca do OCR.
-- O CNPJ da HBR nunca é fornecedor.
create or replace function public._comprovante_fornecedor(c public.comprovantes)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_raiz text := public.raiz_do_cnpj_da_empresa();
  v_nome text;
begin
  if c.emitente_cnpj is not null and v_raiz is not null and left(c.emitente_cnpj, 8) = v_raiz then
    return jsonb_build_object('nome', null, 'origem', null);
  end if;
  -- o CPF do MEI nunca sai daqui (defesa: o cache e fornecedor_receita já gravam sem ele)
  if c.supplier_id is not null and public._comprovante_sem_cpf(c.fornecedor_nome) is not null then
    return jsonb_build_object('nome', public._comprovante_sem_cpf(c.fornecedor_nome), 'origem', 'cadastro');
  end if;
  if public._comprovante_sem_cpf(c.fornecedor_receita) is not null then
    return jsonb_build_object('nome', public._comprovante_sem_cpf(c.fornecedor_receita), 'origem', 'receita');
  end if;
  if c.emitente_cnpj ~ '^[0-9]{14}$' then
    select coalesce(public._comprovante_sem_cpf(k.nome_fantasia), public._comprovante_sem_cpf(k.razao_social)) into v_nome
      from public.cnpj_consultas k
     where k.cnpj = c.emitente_cnpj and k.encontrado and k.consultado_em > now() - interval '90 days';
    if v_nome is not null then
      return jsonb_build_object('nome', v_nome, 'origem', 'receita');
    end if;
  end if;
  return jsonb_build_object('nome', null, 'origem', null);
end $$;

-- ---------------------------------------------------------------------------------------------
-- A mesma compra em outro CMP (revisão de 11/10/2026). O cupom (NFC-e) e o print do Pix (ou o
-- recibo) da MESMA compra viram dois CMPs (a F1 só pega arquivo idêntico ou a mesma chave): o
-- segundo lançaria outra despesa na OS, outra saída do Caixa ou outra anotação. Outro CMP do dono
-- já gravado (ou esperando o sim), que não é ele mesmo "a mesma compra" de outro, com o valor a
-- ±0,01, a data a ±1 dia e a mesma OS, o mesmo fornecedor do cadastro ou o mesmo CNPJ (emitente ou
-- favorecido, cruzados: o Pix traz o CNPJ de quem recebeu). O dono decide (passo mesma_compra).
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
     and y.situacao in ('gravado', 'aguardando_xml', 'aguardando_sim')
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
-- O próximo passo, na ordem fixa (no máximo 3 perguntas no caso comum)
-- ---------------------------------------------------------------------------------------------
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
  if c.destino = 'os' and c.cobrar_cliente is null and v_ef->>'quem' <> 'cliente' then
    return 'cobrar';        -- sempre: caso a caso, sem padrão
  end if;
  if not v_nfe and v_ef->>'quem' <> 'cliente'
     and ((c.destino = 'empresa' and v_ef->>'categoria' is null)
          or not coalesce((v_ef->>'categoria_ativa')::boolean, true)) then
    return 'categoria';
  end if;
  return 'confirmar';
end $$;

-- ---------------------------------------------------------------------------------------------
-- CmpResumo (2.3): nunca leitura, texto do OCR, legenda nem CPF
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
    'gravado_em', c.gravado_em);
end $$;

-- As opções de cada passo (o que o dono vê e o que o número dele quer dizer).
create or replace function public._comprovante_opcoes_do_passo(c public.comprovantes, p_passo text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_os jsonb;
  v_cats jsonb;
  v_mesma jsonb;
  v_nfe boolean := public._comprovante_e_nfe(c);
  v_padrao text;
  v_itens text[] := '{}';
  v_valores text[] := '{}';
  v_menu jsonb := '[]'::jsonb;
  i integer;
begin
  case p_passo
    when 'para_que' then
      return public._comprovante_menu_para_que(c);
    when 'mesma_compra' then
      v_mesma := public._comprovante_mesma_compra(c);
      return jsonb_build_array(
        jsonb_build_object('n', 1, 'rotulo',
          'Sim, é a mesma compra do ' || coalesce(v_mesma->>'codigo', 'outro comprovante') || ': só guardar o arquivo',
          'valor', 'mesma'),
        jsonb_build_object('n', 2, 'rotulo', 'Não, é outra compra', 'valor', 'outra'));
    when 'como_pagou' then
      return jsonb_build_array(
        jsonb_build_object('n', 1, 'rotulo', 'Pix', 'valor', 'pix'),
        jsonb_build_object('n', 2, 'rotulo', 'Débito', 'valor', 'debito'),
        jsonb_build_object('n', 3, 'rotulo', 'Crédito', 'valor', 'credito'),
        jsonb_build_object('n', 4, 'rotulo', 'Dinheiro', 'valor', 'dinheiro'),
        jsonb_build_object('n', 5, 'rotulo', 'Boleto', 'valor', 'boleto'),
        jsonb_build_object('n', 6, 'rotulo', 'Transferência', 'valor', 'transferencia'));
    when 'quem_pagou' then
      -- "do Caixa" só é verdade no dinheiro (depois de "corrigir quem" no Pix/débito, é a conta da empresa)
      return jsonb_build_array(
        jsonb_build_object('n', 1, 'rotulo',
          case when c.forma_confirmada = 'dinheiro' then 'A empresa (dinheiro do Caixa)' else 'A empresa (conta da empresa)' end,
          'valor', 'empresa'),
        jsonb_build_object('n', 2, 'rotulo', 'Eu, do meu bolso (fica como reembolso para você)', 'valor', 'socio'),
        jsonb_build_object('n', 3, 'rotulo', 'Um técnico', 'valor', 'tecnico'))
        || case when c.destino = 'os'
                then jsonb_build_array(jsonb_build_object('n', 4, 'rotulo', 'O cliente pagou direto', 'valor', 'cliente'))
                else '[]'::jsonb end;
    when 'qual_tecnico' then
      return public._comprovante_tecnicos();
    when 'cobrar' then
      v_os := public._comprovante_os_info(c.destino_os_id);
      if coalesce((v_os->>'faturada')::boolean, false) then
        return jsonb_build_array(
          jsonb_build_object('n', 1, 'rotulo', 'Cobrar à parte (fica a lembrança de cobrar)', 'valor', 'cobrar'),
          jsonb_build_object('n', 2, 'rotulo', 'Custo da HBR', 'valor', 'custo'));
      end if;
      return jsonb_build_array(
        jsonb_build_object('n', 1, 'rotulo',
          case when coalesce((v_os->>'assinada')::boolean, false)
               then 'Cobrar do cliente (muda o total e a OS vai pedir nova assinatura)'
               else 'Cobrar do cliente (entra no total da OS)' end, 'valor', 'cobrar'),
        jsonb_build_object('n', 2, 'rotulo', 'Custo da HBR (não entra no total)', 'valor', 'custo'));
    when 'categoria' then
      -- a categoria padrão do destino vem primeiro (na OS, "Peças e materiais" não estava no menu)
      v_padrao := case c.destino
                    when 'os' then 'Peças e materiais'
                    when 'estoque' then 'Compras de mercadorias'
                    when 'insumo' then 'Materiais e Insumos Operacionais'
                    else null end;
      select coalesce(jsonb_agg(jsonb_build_object('n', t.n, 'rotulo', t.nome, 'valor', t.nome) order by t.n), '[]'::jsonb)
        into v_cats
        from (select x.nome, row_number() over (order by x.ordem) as n
                from unnest(array[v_padrao, 'Combustível e deslocamento', 'Alimentação de campo', 'Pedágio e estacionamento',
                                  'Ferramentas e equipamentos', 'Manutenção de veículo', 'Material de escritório',
                                  'Hospedagem e Hotelaria', 'Outras despesas']) with ordinality as x(nome, ordem)
               where x.nome is not null
                 and exists (select 1 from public.financial_categories f
                              where f.name = x.nome and f.type = 'payable' and coalesce(f.active, false))) t;
      return v_cats;
    when 'corrigir' then
      -- por contexto: "Cobrar" só em OS; "Como foi pago", "Quem pagou" e "Categoria" fora da NF-e
      -- (a conta é a da nota) e do pessoal (nada no financeiro)
      v_itens := array['Valor', 'Data', 'Para quê'];
      v_valores := array['valor', 'data', 'para_que'];
      if not v_nfe and c.destino is distinct from 'pessoal' then
        v_itens := v_itens || array['Como foi pago', 'Quem pagou'];
        v_valores := v_valores || array['como_pagou', 'quem_pagou'];
      end if;
      if c.destino = 'os' then
        v_itens := v_itens || 'Cobrar ou não'::text;
        v_valores := v_valores || 'cobrar'::text;
      end if;
      if not v_nfe and c.destino is distinct from 'pessoal' then
        v_itens := v_itens || 'Categoria'::text;
        v_valores := v_valores || 'categoria'::text;
      end if;
      v_itens := v_itens || array['Cancelar este comprovante', 'Deixar para depois'];
      v_valores := v_valores || array['cancelar', 'depois'];
      for i in 1 .. cardinality(v_itens) loop
        v_menu := v_menu || jsonb_build_array(jsonb_build_object('n', i, 'rotulo', v_itens[i], 'valor', v_valores[i]));
      end loop;
      return v_menu;
    else
      return '[]'::jsonb;
  end case;
end $$;

-- ---------------------------------------------------------------------------------------------
-- PerguntaDoBanco (2.3): o que o edge precisa para montar a mensagem da pergunta aberta
-- ---------------------------------------------------------------------------------------------
-- A pasta do barco vale para o CMP de OS com barco e cliente, cliente que não é genérico
-- ("Cliente Final", "Teste…") e pasta registrada — ou a pasta-base configurada para criar uma nova.
-- A MESMA regra do usaPastaDoBarco (_shared/comprovantes/destino.ts): o resumo e o "gravado" dizem a
-- pasta onde o arquivo vai de fato.
create or replace function public._comprovante_usa_pasta_do_barco(p_os jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cliente text := public._comprovante_normalizar(p_os->>'cliente');
  v_base text;
begin
  if p_os is null or p_os->>'vessel_id' is null or p_os->>'client_id' is null or p_os->>'barco' is null then
    return false;
  end if;
  if v_cliente = 'cliente final' or v_cliente like 'cliente final %' or v_cliente like 'teste%' then
    return false;
  end if;
  if coalesce((p_os->>'pasta_registrada')::boolean, false) then
    return true;
  end if;
  select nullif(btrim(regexp_replace(btrim(s.value::text), '^"(.*)"$', '\1')), '') into v_base
    from public.app_settings s where s.key = 'dropbox_pasta_base';
  return v_base is not null;
exception when others then
  return false;
end $$;

create or replace function public._comprovante_montar_pergunta(c public.comprovantes, p_pergunta_id uuid, p_motivo text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  w record;
  v_lote jsonb;
  v_codigos text[];
  v_antigos integer := 0;
  v_avisos text[] := '{}';
  v_os jsonb := public._comprovante_os_info(c.destino_os_id);
  v_plano jsonb;
  v_pasta text;
  v_mesma jsonb;
  v_mes text := to_char(coalesce(c.data_confirmada, c.data_compra, (c.recebido_em at time zone 'America/Sao_Paulo')::date), 'YYYY-MM');
begin
  select x.id, x.dedupe_key, x.passo, x.opcoes, x.dados into w from public.whatsapp_perguntas x where x.id = p_pergunta_id;
  if not found then
    raise exception '_comprovante_montar_pergunta: pergunta % não existe', p_pergunta_id using errcode = '22023';
  end if;

  -- primeira do lote: os que entraram na fila nos últimos 30 min e nunca foram perguntados; os
  -- antigos que já estavam na fila vão à parte ("há também 3 antigos na fila")
  if p_motivo in ('abertura', 'lote_antigo') and c.ultima_pergunta_em is null then
    select array_agg(x.codigo order by x.numero) into v_codigos
      from public.comprovantes x
     where x.phone_normalized = c.phone_normalized
       and (x.id = c.id
            or (x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
                and x.fila_desde > now() - interval '30 minutes' and x.ultima_pergunta_em is null));
    if p_motivo = 'lote_antigo' then
      select array_agg(x.codigo order by x.numero) into v_codigos
        from public.comprovantes x
       where x.phone_normalized = c.phone_normalized
         and (x.id = c.id or (x.situacao = 'aguardando_vez' and x.fila_desde > now() - interval '30 minutes'
                              and x.ultima_pergunta_em is null));
    end if;
    select count(*) into v_antigos
      from public.comprovantes x
     where x.phone_normalized = c.phone_normalized and x.id <> c.id
       and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
       and not (x.codigo = any (coalesce(v_codigos, '{}'::text[])));
    v_lote := jsonb_build_object('n', coalesce(cardinality(v_codigos), 0), 'codigos', to_jsonb(coalesce(v_codigos, '{}'::text[])),
                                 'antigos', v_antigos);
  end if;

  if c.valor_confianca = 'media' and c.valor_confirmado is not distinct from c.valor then
    v_avisos := v_avisos || 'valor_incerto'::text;
  end if;
  if coalesce((v_os->>'faturada')::boolean, false) then
    v_avisos := v_avisos || 'os_faturada_total_nao_muda'::text;
  elsif coalesce((v_os->>'assinada')::boolean, false) and (w.passo = 'cobrar' or c.cobrar_cliente) then
    v_avisos := v_avisos || 'os_assinada_pede_nova_assinatura'::text;
  end if;

  if w.passo = 'mesma_compra' then
    v_mesma := public._comprovante_mesma_compra(c) - 'id';
  end if;

  if w.passo = 'confirmar' then
    v_plano := public._comprovante_plano(c.id);
    v_pasta := case v_plano->>'pasta'
                 when 'barco' then case when public._comprovante_usa_pasta_do_barco(v_os)
                                        then (v_os->>'barco') || '/1- DOC''s/Compras'
                                        else 'COMPROVANTES/' || left(v_mes, 4) || '/' || v_mes end
                 when 'pessoal' then 'COMPROVANTES/PESSOAL/' || v_mes
                 when 'mes' then 'COMPROVANTES/' || left(v_mes, 4) || '/' || v_mes
                 else null end;
  end if;

  return jsonb_build_object(
    'pergunta_id', w.id,
    'dedupe_key', w.dedupe_key,
    'cmp', public._comprovante_resumo(c),
    'passo', w.passo,
    'opcoes', w.opcoes,
    'posicao', coalesce((w.dados->>'posicao')::integer, 1),
    'total', coalesce((w.dados->>'total')::integer, 1),
    'primeira_do_lote', case when coalesce((v_lote->>'n')::integer, 0) > 0 then v_lote end,
    'retomada', c.ultima_pergunta_em is not null,
    -- o passo veio do "corrigir" (o dono disse que o dado estava errado): "Qual o valor certo?"
    'forcado', coalesce((w.dados->>'forcado')::boolean, false),
    'mesma_compra', v_mesma,
    'avisos', to_jsonb(v_avisos),
    'plano', v_plano,
    'versao', case when w.passo = 'confirmar' then (w.dados->>'versao')::integer end,
    'pasta', v_pasta);
end $$;

-- ---------------------------------------------------------------------------------------------
-- Entrar na fila (regra da RPC 6): CMP do modo dono, lido ou "A LER" (falhou com número), nunca
-- gravado nem na fila. Pré-preenche o que a leitura e a legenda já dizem — sem apagar o que o dono
-- já respondeu (o CMP que saiu da conversa quando ela foi desligada volta com as respostas).
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovante_entrar_na_fila(p_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_dica jsonb;
  v_receita text;
begin
  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found or c.numero is null or c.modo <> 'dono' or c.situacao not in ('lido', 'falhou')
     or c.gravado_em is not null or c.fila_desde is not null then
    return false;
  end if;
  v_dica := public._comprovante_ler_dica(c.legenda, c.dica_da_legenda);
  if c.supplier_id is null and c.emitente_cnpj ~ '^[0-9]{14}$' then
    select coalesce(public._comprovante_sem_cpf(k.nome_fantasia), public._comprovante_sem_cpf(k.razao_social)) into v_receita
      from public.cnpj_consultas k
     where k.cnpj = c.emitente_cnpj and k.encontrado and k.consultado_em > now() - interval '90 days';
  end if;
  update public.comprovantes x
     set situacao = 'aguardando_vez',
         fila_desde = now(),
         fila_ordem = clock_timestamp(),
         valor_confirmado = coalesce(x.valor_confirmado, case when x.valor_confianca in ('alta', 'media') then x.valor end),
         data_confirmada = coalesce(x.data_confirmada, x.data_compra, (x.recebido_em at time zone 'America/Sao_Paulo')::date),
         forma_confirmada = coalesce(x.forma_confirmada, x.forma_pagamento),
         destino = coalesce(x.destino, v_dica->>'destino'),
         destino_os_id = coalesce(x.destino_os_id, nullif(v_dica->>'os_id', '')::uuid),
         fornecedor_receita = coalesce(x.fornecedor_receita, left(v_receita, 200))
   where x.id = p_id;
  return true;
end $$;

-- Abre a pergunta do passo atual de um CMP (sem as regras do vigia: quem chama já decidiu).
-- {"ok":true,"pergunta":PerguntaDoBanco} ou {"ok":false,"ocupado_por":{...}}.
-- p_motivo 'corrigir' = o dono escolheu o campo no menu do corrigir (a pergunta sai "forcada": no
-- valor, "Qual o valor certo?", e o "sim" não vale como "mantém o lido").
-- A posição ("2 de 4") é contada no LOTE (o que entrou na fila nos últimos 30 min) quando o CMP é
-- dele; os antigos da fila não inflam o "de N" de quem acabou de mandar 4 fotos.
create or replace function public._comprovante_abrir_pergunta(p_id uuid, p_motivo text, p_opcoes jsonb default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_depois public.comprovantes;
  v_passo text;
  v_opcoes jsonb;
  v_dados jsonb;
  v_abriu jsonb;
  v_conversa integer;
  v_resolvidos integer;
  v_lote integer;
  v_lote_resolvidos integer;
  v_pergunta jsonb;
begin
  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found then
    raise exception '_comprovante_abrir_pergunta: comprovante % não existe', p_id using errcode = '22023';
  end if;
  -- o confirmar é sempre recalculado (o caso pode ter mudado); os outros passos forçados ficam
  v_passo := case when c.passo is null or c.passo = 'confirmar' then public._comprovante_proximo_passo(c) else c.passo end;
  v_opcoes := coalesce(p_opcoes, public._comprovante_opcoes_do_passo(c, v_passo));

  select count(*) into v_conversa from public.comprovantes x
   where x.phone_normalized = c.phone_normalized and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
  select count(*) into v_resolvidos from public.comprovantes x
   where x.phone_normalized = c.phone_normalized and x.fila_desde is not null and x.id <> c.id
     and (x.gravado_em > now() - interval '30 minutes' or x.cancelado_em > now() - interval '30 minutes');
  select count(*) filter (where x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
                                or x.gravado_em > now() - interval '30 minutes' or x.cancelado_em > now() - interval '30 minutes'),
         count(*) filter (where x.id <> c.id
                                and (x.gravado_em > now() - interval '30 minutes' or x.cancelado_em > now() - interval '30 minutes'))
    into v_lote, v_lote_resolvidos
    from public.comprovantes x
   where x.phone_normalized = c.phone_normalized and x.fila_desde > now() - interval '30 minutes';
  if c.fila_desde > now() - interval '30 minutes' then
    v_dados := jsonb_build_object('versao', c.resumo_versao, 'posicao', v_lote_resolvidos + 1,
                                  'total', greatest(v_lote, v_lote_resolvidos + 1));
  else
    v_dados := jsonb_build_object('versao', c.resumo_versao, 'posicao', v_resolvidos + 1,
                                  'total', v_resolvidos + greatest(v_conversa, 1));
  end if;
  v_dados := v_dados || jsonb_build_object('motivo', left(p_motivo, 30), 'forcado', p_motivo = 'corrigir');
  if v_passo = 'confirmar' then
    v_dados := v_dados || jsonb_build_object('plano_hash', md5(public._comprovante_plano(c.id)::text));
  end if;

  v_abriu := public._pergunta_abrir(jsonb_build_object(
    'phone', c.phone_normalized, 'origem', 'comprovante', 'tipo', 'pergunta', 'referencia_id', c.id,
    'referencia_codigo', c.codigo, 'passo', v_passo, 'opcoes', v_opcoes, 'dados', v_dados,
    'expira_em', now() + interval '2 hours'));
  if not coalesce((v_abriu->>'ok')::boolean, false) then
    return v_abriu;
  end if;

  update public.comprovantes x
     set situacao = case when v_passo = 'confirmar' then 'aguardando_sim' else 'perguntando' end,
         passo = v_passo,
         ultima_pergunta_em = now(),
         adiado_ate = null,
         perguntas_automaticas = x.perguntas_automaticas + case when p_motivo = 'vigia' then 1 else 0 end
   where x.id = c.id
  returning * into v_depois;
  -- a pergunta mostra o CMP como ficou; "retomada" e o lote olham a pergunta ANTERIOR a esta
  v_depois.ultima_pergunta_em := c.ultima_pergunta_em;
  v_pergunta := public._comprovante_montar_pergunta(v_depois, (v_abriu->>'id')::uuid, p_motivo);
  return jsonb_build_object('ok', true, 'pergunta', v_pergunta);
end $$;

-- O texto/áudio do dono há menos de 2 min (conversa em andamento), sem contar o que virou dica de
-- um CMP (a frase solta logo depois da foto: comprovante_acrescentar_dica).
create or replace function public._comprovante_conversa_em_andamento(p_phone text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.whatsapp_messages m
     where m.phone_normalized = p_phone and m.direction = 'inbound'
       and m.message_type in ('text', 'audio') and m.occurred_at > now() - interval '2 minutes'
       and not exists (select 1 from public.comprovantes y
                        where y.phone_normalized = p_phone and y.recebido_em > now() - interval '1 day'
                          and m.id = any (y.mensagens_de_dica)));
$$;

-- O vigia pode perguntar a este telefone agora? null = pode; senão o motivo. Só leitura (a guarda
-- do cron usa a mesma regra): conversa ligada e do dono, sem pausa, de 08:00 a 20:00 de São Paulo
-- de segunda a sábado, sem texto/áudio do dono nos últimos 2 min, sem pergunta aberta nem
-- pendência viva, e um CMP da fila dentro do espaçamento (4 h), do limite (3 perguntas automáticas)
-- e fora do adiamento do "pular"/"deixar para depois" (adiado_ate).
create or replace function public._comprovante_vigia_pode(p_phone text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_agora timestamp := now() at time zone 'America/Sao_Paulo';
  v_fila record;
begin
  if not public._comprovante_conversa_ligada()
     or p_phone is distinct from (select d.phone from public._comprovante_dono() d) then
    return 'desligada';
  end if;
  select f.pausada_ate, f.ultima_pergunta_fechada_em into v_fila
    from public.comprovantes_fila_do_telefone f where f.phone_normalized = p_phone;
  if v_fila.pausada_ate > now() then
    return 'pausada';
  end if;
  if extract(isodow from v_agora) = 7 or v_agora::time < time '08:00' or v_agora::time >= time '20:00' then
    return 'fora_do_horario';
  end if;
  if public._comprovante_conversa_em_andamento(p_phone) then
    return 'conversa_em_andamento';
  end if;
  if exists (select 1 from public.whatsapp_perguntas w
              where w.phone_normalized = p_phone and w.status = 'aberta' and w.expira_em > now()
                and (w.tipo = 'pergunta'
                     or (w.tipo = 'confirmacao' and exists (
                           select 1 from public.ai_operator_pending_actions a
                            where a.id = w.referencia_id and a.status = 'pending'
                              and (a.expires_at is null or a.expires_at > now())))
                     or (w.tipo = 'opcoes' and exists (
                           select 1 from public.ai_operator_sessions s
                            where s.id = w.referencia_id and s.status = 'open'
                              and jsonb_typeof(s.metadata->'pending_options') = 'array'
                              and jsonb_array_length(s.metadata->'pending_options') > 0))))
     or public._pendencia_viva_do_telefone(p_phone) is not null then
    return 'ocupado';
  end if;
  if exists (select 1 from public.comprovantes x
              where x.phone_normalized = p_phone and x.situacao = 'aguardando_vez' and x.perguntas_automaticas < 3
                and (x.adiado_ate is null or x.adiado_ate <= now())
                and (x.perguntas_automaticas = 0 or v_fila.ultima_pergunta_fechada_em is null
                     or v_fila.ultima_pergunta_fechada_em <= now() - interval '4 hours')) then
    return null;
  end if;
  if exists (select 1 from public.comprovantes x where x.phone_normalized = p_phone and x.situacao = 'aguardando_vez') then
    return 'limite_de_tentativas';
  end if;
  return 'fila_vazia';
end $$;

-- O CMP que o vigia pergunta: o primeiro da fila dentro do espaçamento, do limite e do adiamento.
create or replace function public._comprovante_cmp_da_vigia(p_phone text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v uuid;
  v_fechada timestamptz;
begin
  select f.ultima_pergunta_fechada_em into v_fechada from public.comprovantes_fila_do_telefone f where f.phone_normalized = p_phone;
  select x.id into v from public.comprovantes x
   where x.phone_normalized = p_phone and x.situacao = 'aguardando_vez' and x.perguntas_automaticas < 3
     and (x.adiado_ate is null or x.adiado_ate <= now())
     and (x.perguntas_automaticas = 0 or v_fechada is null or v_fechada <= now() - interval '4 hours')
   order by x.fila_ordem, x.numero
   limit 1;
  return v;
end $$;

-- O miolo da RPC 7 (com p_excluir: o "pular" não pergunta de novo o que acabou de pular).
--   abertura: o dono acabou de mandar o comprovante — ação dele: limpa a pausa do "sair"; só espera a
--     conversa em andamento (texto/áudio há menos de 2 min que não virou dica);
--   retomar: a pendência do assistente que tinha tirado a pergunta do CMP foi respondida — reabre
--     AQUELE CMP (o da pergunta substituída nas últimas 24 h), respeitando a pausa;
--   os outros motivos (ação do dono) limpam a pausa e ignoram horário e espaçamento.
-- Sem perguntar, devolve o código do CMP que ficou na fila (o edge avisa numa linha).
create or replace function public._comprovante_proxima(p_phone text, p_motivo text, p_cmp uuid, p_excluir uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_fila integer;
  v_motivo text;
  v_cmp uuid := p_cmp;
  v_aberta record;
  c record;
  v_r jsonb;
begin
  if p_motivo is null or p_motivo not in ('abertura', 'vigia', 'depois_de_gravar', 'pendentes', 'cmp', 'lote_antigo',
                                          'pular', 'reabrir', 'retomar') then
    raise exception 'comprovante_proxima_pergunta: motivo inválido' using errcode = '22023';
  end if;
  if p_phone is null or p_phone !~ '^[0-9]{10,15}$' then
    raise exception 'comprovante_proxima_pergunta: telefone inválido' using errcode = '22023';
  end if;
  if not public._comprovante_conversa_ligada()
     or p_phone is distinct from (select d.phone from public._comprovante_dono() d) then
    return jsonb_build_object('perguntou', false, 'motivo', 'desligada', 'fila', 0);
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || p_phone, 0));
  perform public._pergunta_limpar(p_phone);

  if p_motivo in ('abertura', 'vigia', 'retomar') then
    if p_motivo = 'vigia' then
      v_motivo := public._comprovante_vigia_pode(p_phone);
    elsif p_motivo = 'retomar' then
      if exists (select 1 from public.comprovantes_fila_do_telefone f
                  where f.phone_normalized = p_phone and f.pausada_ate > now()) then
        v_motivo := 'pausada';
      end if;
    else
      -- abertura: um comprovante novo é ação do dono (a pausa do "sair" acaba)
      update public.comprovantes_fila_do_telefone f set pausada_ate = null, atualizado_em = now()
       where f.phone_normalized = p_phone and f.pausada_ate is not null;
      if public._comprovante_conversa_em_andamento(p_phone) then
        v_motivo := 'conversa_em_andamento';
      end if;
    end if;
    if v_motivo = 'ocupado' then
      v_motivo := null;      -- quem diz "ocupado" (com o porquê) é o _pergunta_abrir, abaixo
    end if;
    if v_motivo is not null then
      select count(*) into v_fila from public.comprovantes x
       where x.phone_normalized = p_phone and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
      return jsonb_build_object('perguntou', false, 'motivo', v_motivo, 'fila', v_fila,
                                'codigo', (select x.codigo from public.comprovantes x where x.id = v_cmp));
    end if;
    if p_motivo = 'vigia' and v_cmp is null then
      v_cmp := public._comprovante_cmp_da_vigia(p_phone);
    elsif p_motivo = 'retomar' and v_cmp is null then
      -- o CMP cuja pergunta a pendência do assistente/lembrete substituiu
      select w.referencia_id into v_cmp
        from public.whatsapp_perguntas w
        join public.comprovantes x on x.id = w.referencia_id
       where w.phone_normalized = p_phone and w.origem = 'comprovante' and w.status = 'substituida'
         and w.motivo like 'substituida_por:%' and w.fechada_em > now() - interval '24 hours'
         and x.situacao = 'aguardando_vez'
       order by w.fechada_em desc
       limit 1;
      if v_cmp is null then
        select count(*) into v_fila from public.comprovantes x
         where x.phone_normalized = p_phone and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
        return jsonb_build_object('perguntou', false, 'motivo', 'fila_vazia', 'fila', v_fila);
      end if;
    end if;
  else
    -- ação do dono: limpa a pausa, ignora horário e espaçamento
    update public.comprovantes_fila_do_telefone f set pausada_ate = null, atualizado_em = now()
     where f.phone_normalized = p_phone and f.pausada_ate is not null;
  end if;

  if v_cmp is not null then
    select x.id, x.situacao, x.gravado_em, x.phone_normalized into c from public.comprovantes x where x.id = v_cmp;
    if not found or c.phone_normalized <> p_phone or c.gravado_em is not null or c.situacao = 'cancelado' then
      v_cmp := null;
    elsif c.situacao in ('lido', 'falhou') then
      if not public._comprovante_entrar_na_fila(v_cmp) then
        v_cmp := null;
      end if;
    elsif c.situacao not in ('aguardando_vez', 'perguntando', 'aguardando_sim') then
      v_cmp := null;
    end if;
  elsif p_motivo not in ('abertura', 'vigia', 'retomar') then
    -- pedido do dono sem CMP: a pergunta de comprovante aberta é refeita (pendentes, lote...)
    select w.referencia_id into v_aberta from public.whatsapp_perguntas w
     where w.phone_normalized = p_phone and w.status = 'aberta' and w.origem = 'comprovante';
    v_cmp := v_aberta.referencia_id;
  end if;
  if v_cmp is null and p_motivo not in ('vigia', 'retomar') then
    select x.id into v_cmp from public.comprovantes x
     where x.phone_normalized = p_phone and x.situacao = 'aguardando_vez' and x.id is distinct from p_excluir
     order by x.fila_ordem, x.numero
     limit 1;
  end if;

  select count(*) into v_fila from public.comprovantes x
   where x.phone_normalized = p_phone and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
  if v_cmp is null then
    return jsonb_build_object('perguntou', false,
      'motivo', case when p_motivo = 'vigia' and v_fila > 0 then 'limite_de_tentativas' else 'fila_vazia' end,
      'fila', v_fila);
  end if;

  v_r := public._comprovante_abrir_pergunta(v_cmp, p_motivo, null);
  if not coalesce((v_r->>'ok')::boolean, false) then
    return jsonb_build_object('perguntou', false, 'motivo', 'ocupado', 'ocupado_por', v_r->'ocupado_por', 'fila', v_fila,
                              'codigo', (select x.codigo from public.comprovantes x where x.id = v_cmp));
  end if;
  return jsonb_build_object('perguntou', true) || (v_r->'pergunta');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 6. comprovante_conversa_entrar
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_conversa_entrar(p_ids uuid[])
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_entraram jsonb := '[]'::jsonb;
  v_phone text := (select d.phone from public._comprovante_dono() d);
  v_fila integer;
begin
  if not public._comprovante_conversa_ligada() or p_ids is null then
    return jsonb_build_object('entraram', '[]'::jsonb, 'fila', 0);
  end if;
  for v_id in
    select x.id from public.comprovantes x where x.id = any (p_ids) order by x.numero nulls last, x.recebido_em
  loop
    if public._comprovante_entrar_na_fila(v_id) then
      v_entraram := v_entraram || jsonb_build_array(jsonb_build_object(
        'id', v_id, 'codigo', (select x.codigo from public.comprovantes x where x.id = v_id)));
    end if;
  end loop;
  select count(*) into v_fila from public.comprovantes x
   where x.phone_normalized = v_phone and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
  return jsonb_build_object('entraram', v_entraram, 'fila', v_fila);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 7. comprovante_proxima_pergunta
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_proxima_pergunta(p_phone text, p_motivo text, p_cmp uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return public._comprovante_proxima(p_phone, p_motivo, p_cmp, null);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 8. comprovante_pergunta_nao_enviada: o whatsapp-send não confirmou; o CMP volta para a fila
--    (relê a pergunta DEPOIS do lock: se outra transação já a fechou — o "cmp 124" no meio —, o CMP
--    não volta para a fila com uma pergunta nova dele aberta)
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
begin
  select x.phone_normalized, x.origem into w
    from public.whatsapp_perguntas x where x.id = p_pergunta_id;
  if not found or w.origem <> 'comprovante' then
    return;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || w.phone_normalized, 0));
  select x.id, x.referencia_id, x.status into w from public.whatsapp_perguntas x where x.id = p_pergunta_id;
  if w.status = 'aberta' and public._pergunta_fechar(w.id, 'cancelada', 'nao_enviada', null)
     and not exists (select 1 from public.whatsapp_perguntas y
                      where y.referencia_id = w.referencia_id and y.status = 'aberta' and y.origem = 'comprovante') then
    perform public._comprovante_pergunta_saiu(w.referencia_id);
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 9. comprovante_responder: a resposta ao passo da pergunta (ou, citada, ao passo dela)
--    Revisão de 11/10/2026: a resposta só vale para a pergunta que o dono VIU. Mensagem mais velha
--    que o envio da pergunta (o "1" repetido que chegou depois de o primeiro abrir a próxima; o
--    "sim" digitado antes de o vigia mandar o resumo) não é aplicada: a pergunta é reapresentada
--    (motivo resposta_anterior_a_pergunta). No confirmar, sem a mensagem (ou sem o envio
--    confirmado), também não.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_responder(p jsonb)
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
  v_quando timestamptz;
  v_interp jsonb;
  v_tipo text;
  v_passo text;
  v_aberta boolean;
  v_versao integer;
  v_val text;
  v_n integer;
  v_os jsonb;
  v_ids uuid[];
  v_abertas uuid[];
  v_tokens text[];
  v_motivo text;
  v_resultado text;
  v_mudou boolean := false;
  v_override jsonb;
  v_forcar_passo text;
  v_abriu jsonb;
  v_prox jsonb;
  v_grav jsonb;
  v_hash text;
  v_t text;
  v_estado text;
  v_mesma jsonb;
  -- o que muda
  n_valor numeric(12,2);
  n_data date;
  n_destino text;
  n_os uuid;
  n_forma text;
  n_quem text;
  n_pagador uuid;
  n_cobrar boolean;
  n_categoria text;
  n_mesma uuid;
  n_outra boolean;
  n_adiado timestamptz;
begin
  if p is null or jsonb_typeof(p) <> 'object' or jsonb_typeof(p->'interpretacao') is distinct from 'object' then
    raise exception 'comprovante_responder: entrada inválida' using errcode = '22023';
  end if;
  begin
    v_pid := (p->>'pergunta_id')::uuid;
    v_msg := nullif(p->>'message_id', '')::uuid;
    v_versao := nullif(p->>'versao', '')::integer;
  exception when others then
    raise exception 'comprovante_responder: pergunta_id, message_id ou versao malformado' using errcode = '22023';
  end;
  v_interp := p->'interpretacao';
  v_tipo := v_interp->>'tipo';
  if v_tipo is null or v_tipo not in ('opcao', 'sim', 'nao', 'ok', 'valor', 'data', 'os', 'palavra', 'nome') then
    raise exception 'comprovante_responder: interpretação desconhecida' using errcode = '22023';
  end if;

  select x.id, x.phone_normalized, x.origem, x.referencia_id into w from public.whatsapp_perguntas x where x.id = v_pid;
  if not found or w.origem <> 'comprovante' then
    raise exception 'comprovante_responder: pergunta % não é de comprovante', v_pid using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || w.phone_normalized, 0));
  select * into c from public.comprovantes x where x.id = w.referencia_id for update;
  if v_msg is not null then
    select m.occurred_at into v_quando from public.whatsapp_messages m where m.id = v_msg;
    if not found then
      v_msg := null;
    end if;
  end if;

  if c.gravado_em is not null or c.situacao = 'cancelado' then
    return jsonb_build_object('resultado', 'ignorada', 'cmp', public._comprovante_resumo(c), 'proxima', null,
                              'gravacao', null, 'motivo', case when c.situacao = 'cancelado' then 'cancelado' else 'ja_gravado' end);
  end if;
  if not public._comprovante_conversa_ligada() then
    return jsonb_build_object('resultado', 'ignorada', 'cmp', public._comprovante_resumo(c), 'proxima', null,
                              'gravacao', null, 'motivo', 'desligada');
  end if;

  perform public._pergunta_limpar(w.phone_normalized);
  select x.id, x.phone_normalized, x.referencia_id, x.status, x.passo, x.opcoes, x.dados, x.aberta_em, x.enviada_em into w
    from public.whatsapp_perguntas x where x.id = v_pid;
  v_aberta := w.status = 'aberta';
  v_passo := w.passo;
  select * into c from public.comprovantes x where x.id = c.id;

  -- a resposta é a esta pergunta? (só vale o que o dono mandou depois de a pergunta chegar a ele)
  if v_aberta and ((v_msg is not null and (w.enviada_em is null
                                            or v_quando < greatest(w.aberta_em + interval '2 seconds',
                                                                   w.enviada_em - interval '2 seconds')))
                   or (v_msg is null and v_passo = 'confirmar' and v_tipo = 'sim')) then
    return jsonb_build_object('resultado', 'invalida', 'cmp', public._comprovante_resumo(c),
      'proxima', public._comprovante_montar_pergunta(c, w.id, 'reabrir'),
      'gravacao', null, 'motivo', 'resposta_anterior_a_pergunta');
  end if;

  n_valor := c.valor_confirmado; n_data := c.data_confirmada; n_destino := c.destino; n_os := c.destino_os_id;
  n_forma := c.forma_confirmada; n_quem := c.quem_pagou; n_pagador := c.pagador_payee_id;
  n_cobrar := c.cobrar_cliente; n_categoria := c.categoria; n_mesma := c.mesma_compra_de; n_outra := c.outra_compra;
  n_adiado := c.adiado_ate;

  -- o valor da opção escolhida (do que o dono VIU nesta pergunta)
  if v_tipo = 'opcao' then
    begin
      v_n := (v_interp->>'n')::integer;
    exception when others then
      v_n := null;
    end;
    select o->>'valor' into v_val from jsonb_array_elements(w.opcoes) o where (o->>'n')::integer = v_n limit 1;
  elsif v_tipo = 'palavra' then
    v_val := v_interp->>'valor';
  end if;

  -- ══ confirmar ═══════════════════════════════════════════════════════════════════════════
  if v_passo = 'confirmar' then
    if v_tipo = 'ok' then
      return jsonb_build_object('resultado', 'ok_nao_aprova', 'cmp', public._comprovante_resumo(c), 'proxima', null,
                                'gravacao', null, 'motivo', null);
    elsif v_tipo = 'nao' then
      v_forcar_passo := 'corrigir';
      v_resultado := 'corrigir';
    elsif v_tipo = 'sim' then
      if not v_aberta then
        -- sim a um resumo que já fechou não aprova: mostra o resumo de novo
        v_forcar_passo := null;
        v_resultado := 'resumo';
        v_motivo := 'pergunta_fechada';
      elsif coalesce(v_versao, (w.dados->>'versao')::integer) is distinct from (w.dados->>'versao')::integer
            or (w.dados->>'versao')::integer is distinct from c.resumo_versao then
        v_resultado := 'resumo';
        v_motivo := 'versao_mudou';
      else
        v_hash := w.dados->>'plano_hash';
        begin
          v_grav := public._comprovante_gravar(c.id, c.dono_id, v_hash);
        exception
          when sqlstate 'MFC01' then
            v_resultado := 'resumo';
            v_motivo := 'versao_mudou';
          when others then
            get stacked diagnostics v_t = message_text, v_estado = returned_sqlstate;
            -- o motivo vai ao edge, que o traduz para o dono (nunca a mensagem crua do Postgres) e
            -- registra só o código do erro
            return jsonb_build_object('resultado', 'nao_gravado', 'cmp', public._comprovante_resumo(c), 'proxima', null,
                                      'gravacao', null, 'motivo', left(v_t, 200), 'codigo_erro', v_estado);
        end;
        if v_grav is not null then
          perform public._pergunta_fechar(w.id, 'respondida', null, v_msg);
          v_prox := public._comprovante_proxima(w.phone_normalized, 'depois_de_gravar', null, null);
          select * into c from public.comprovantes x where x.id = c.id;
          return jsonb_build_object('resultado', 'gravado', 'cmp', public._comprovante_resumo(c),
            'proxima', case when coalesce((v_prox->>'perguntou')::boolean, false) then v_prox - 'perguntou' end,
            'gravacao', v_grav, 'motivo', null);
        end if;
      end if;
    else
      return jsonb_build_object('resultado', 'invalida', 'cmp', public._comprovante_resumo(c),
        'proxima', case when v_aberta then public._comprovante_montar_pergunta(c, w.id, 'reabrir') end,
        'gravacao', null, 'motivo', 'so_sim_ou_nao');
    end if;

    -- resumo de novo (versão mudou / pergunta fechada) ou o menu do corrigir
    if v_aberta then
      perform public._pergunta_fechar(w.id, case when v_resultado = 'corrigir' then 'respondida' else 'substituida' end,
                                      v_motivo, v_msg);
    end if;
    update public.comprovantes x set passo = v_forcar_passo where x.id = c.id;
    v_abriu := public._comprovante_abrir_pergunta(c.id, 'reabrir', null);
    select * into c from public.comprovantes x where x.id = c.id;
    if not coalesce((v_abriu->>'ok')::boolean, false) then
      perform public._comprovante_pergunta_saiu(c.id);
      return jsonb_build_object('resultado', 'proximo', 'cmp', public._comprovante_resumo(c), 'proxima', null,
                                'gravacao', null, 'motivo', 'ocupado', 'ocupado_por', v_abriu->'ocupado_por');
    end if;
    return jsonb_build_object('resultado', v_resultado, 'cmp', public._comprovante_resumo(c),
                              'proxima', v_abriu->'pergunta', 'gravacao', null, 'motivo', v_motivo);
  end if;

  -- ══ os passos de dado ═══════════════════════════════════════════════════════════════════
  case v_passo
    when 'valor' then
      if v_tipo = 'valor' and coalesce(v_interp->>'valor', '') ~ '^[0-9]{1,10}\.[0-9]{2}$'
         and (v_interp->>'valor')::numeric > 0 and (v_interp->>'valor')::numeric <= 999999.99 then
        n_valor := (v_interp->>'valor')::numeric;
      elsif v_tipo = 'sim' and c.valor is not null and not coalesce((w.dados->>'forcado')::boolean, false) then
        -- "sim" = mantém o lido; no valor vindo do corrigir o dono acabou de dizer que está errado
        n_valor := c.valor;
      elsif v_tipo in ('sim', 'nao') then
        v_motivo := 'qual_o_valor';
      else
        v_motivo := case when v_tipo = 'valor' then 'valor_invalido' else 'resposta_nao_serve' end;
      end if;

    when 'para_que', 'qual_os' then
      if v_tipo = 'opcao' and v_val is null then
        v_motivo := 'opcao_fora';
      elsif (v_tipo = 'opcao' and v_val like 'os:%') then
        v_os := public._comprovante_os_info(substr(v_val, 4)::uuid);
        if v_os is null then v_motivo := 'os_nao_existe';
        elsif v_os->>'status' = 'cancelled' then v_motivo := 'os_cancelada';
        elsif v_os->>'status' = 'draft' then v_motivo := 'os_rascunho';
        else n_destino := 'os'; n_os := substr(v_val, 4)::uuid;
        end if;
      elsif v_passo = 'para_que' and v_tipo in ('opcao', 'palavra') and v_val in ('estoque', 'insumo', 'empresa', 'pessoal') then
        n_destino := v_val; n_os := null;
      elsif v_passo = 'para_que' and v_tipo = 'palavra' and v_val = 'os' then
        n_destino := 'os'; n_os := null;
      elsif v_tipo = 'os' then
        begin
          v_n := (v_interp->>'numero')::integer;
        exception when others then
          v_n := null;
        end;
        v_os := public._comprovante_os_por_numero(v_n);
        if v_os ? 'id' then
          n_destino := 'os'; n_os := (v_os->>'id')::uuid;
        else
          v_motivo := v_os->>'motivo';
        end if;
      elsif v_tipo = 'nome' then
        -- o nome do barco ou do cliente: as palavras do texto (sem enchimento) inteiras no nome, ou o
        -- nome inteiro do barco dentro do texto ("do brisa", "brisa mar" acham "Brisa do Mar"). OS
        -- abertas e as concluídas/faturadas dos últimos 60 dias; uma aberta só = ela; nenhuma aberta e
        -- uma fechada só = ela; mais de uma = repergunta só com elas.
        v_t := public._comprovante_normalizar(v_interp->>'texto');
        select array_agg(t) into v_tokens
          from unnest(regexp_split_to_array(v_t, ' ')) t
         where char_length(t) >= 3
           and t not in ('barco', 'cliente', 'para', 'pro', 'pra', 'dos', 'das', 'que', 'esse', 'essa', 'este', 'esta',
                         'compra', 'gasto', 'nota', 'cupom', 'aquele', 'aquela', 'lancha', 'veleiro', 'embarcacao');
        if coalesce(cardinality(v_tokens), 0) > 0 then
          with alvos as (
            select so.id, so.status, so.updated_at,
                   ' ' || public._comprovante_normalizar(v.name) || ' ' as nb,
                   ' ' || public._comprovante_normalizar(coalesce(cl.display_name, cl.name)) || ' ' as nc
              from public.service_orders so
              left join public.vessels v on v.id = so.vessel_id
              left join public.clients cl on cl.id = so.client_id
             where so.status in ('open', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client', 'approved')
                or (so.status in ('completed', 'invoiced') and coalesce(so.check_out_at, so.updated_at) >= now() - interval '60 days')
          ), achadas as (
            select a.id, a.status from alvos a
             where (select bool_and(a.nb like '% ' || t || ' %' or a.nc like '% ' || t || ' %') from unnest(v_tokens) t)
                or (char_length(btrim(a.nb)) >= 4 and (' ' || v_t || ' ') like '%' || a.nb || '%')
          )
          select array_agg(distinct a.id),
                 array_agg(distinct a.id) filter (where a.status in ('open', 'scheduled', 'in_progress', 'awaiting_parts',
                                                                     'awaiting_client', 'approved'))
            into v_ids, v_abertas
            from achadas a;
        end if;
        if coalesce(cardinality(v_abertas), 0) = 1 then
          n_destino := 'os'; n_os := v_abertas[1];
        elsif coalesce(cardinality(v_abertas), 0) = 0 and coalesce(cardinality(v_ids), 0) = 1 then
          n_destino := 'os'; n_os := v_ids[1];
        elsif coalesce(cardinality(v_ids), 0) > 1 then
          -- repergunta só com elas (as fechadas com o rótulo)
          n_destino := 'os'; n_os := null;
          v_forcar_passo := 'qual_os';
          select jsonb_agg(jsonb_build_object('n', t.n, 'rotulo', t.rotulo, 'valor', 'os:' || t.id) order by t.n)
            into v_override
            from (select so.id,
                         row_number() over (order by (so.status in ('completed', 'invoiced')), so.updated_at desc, so.id) as n,
                         so.service_order_number || ' · ' || coalesce(nullif(btrim(v.name), ''), cl.display_name, cl.name, 'sem barco')
                         || case when so.status = 'invoiced' or coalesce(so.invoicing_status, 'not_invoiced') <> 'not_invoiced'
                                 then ' (faturada)'
                                 when so.status = 'completed' then ' (concluída)' else '' end as rotulo
                    from public.service_orders so
                    left join public.vessels v on v.id = so.vessel_id
                    left join public.clients cl on cl.id = so.client_id
                   where so.id = any (v_ids)
                   order by (so.status in ('completed', 'invoiced')), so.updated_at desc, so.id
                   limit 8) t;
        else
          v_motivo := 'nome_nao_achado';
        end if;
      else
        v_motivo := 'resposta_nao_serve';
      end if;
      if v_motivo is null and n_os is distinct from c.destino_os_id then
        n_cobrar := null;            -- outra OS: cobrar ou não se decide de novo
      end if;
      if v_motivo is null and n_destino is distinct from 'os' then
        n_os := null; n_cobrar := null;
      end if;

    when 'mesma_compra' then
      if (v_tipo in ('opcao', 'palavra') and v_val = 'mesma') or v_tipo = 'sim' then
        v_mesma := public._comprovante_mesma_compra(c);
        -- o outro CMP sumiu (cancelado no meio): segue como compra própria
        n_mesma := nullif(v_mesma->>'id', '')::uuid;
        n_outra := case when n_mesma is null then true else null end;
      elsif (v_tipo in ('opcao', 'palavra') and v_val = 'outra') or v_tipo = 'nao' then
        n_mesma := null;
        n_outra := true;
      else
        v_motivo := case when v_tipo = 'opcao' then 'opcao_fora' else 'resposta_nao_serve' end;
      end if;

    when 'como_pagou' then
      if v_tipo in ('opcao', 'palavra') and v_val in ('pix', 'debito', 'credito', 'dinheiro', 'boleto', 'transferencia') then
        n_forma := v_val;
      else
        v_motivo := case when v_tipo = 'opcao' then 'opcao_fora' else 'resposta_nao_serve' end;
      end if;

    when 'quem_pagou' then
      if v_tipo in ('opcao', 'palavra') and v_val in ('empresa', 'socio', 'tecnico')
         or (v_tipo in ('opcao', 'palavra') and v_val = 'cliente' and c.destino = 'os') then
        n_quem := v_val;
        n_pagador := null;
        if v_val = 'socio' then
          n_pagador := public._comprovante_socio(c.dono_id);
          if n_pagador is null then
            v_motivo := 'sem_socio_cadastrado';
          end if;
        end if;
      else
        v_motivo := case when v_tipo = 'opcao' then 'opcao_fora' else 'resposta_nao_serve' end;
      end if;

    when 'qual_tecnico' then
      if v_tipo = 'opcao' and v_val like 'payee:%' then
        n_pagador := substr(v_val, 7)::uuid;
      elsif v_tipo = 'nome' then
        v_t := public._comprovante_normalizar(v_interp->>'texto');
        select array_agg(substr(o->>'valor', 7)::uuid) into v_ids
          from jsonb_array_elements(public._comprovante_tecnicos()) o
         where char_length(v_t) >= 3
           and (' ' || public._comprovante_normalizar(o->>'rotulo') || ' ') like ('% ' || v_t || ' %');
        if coalesce(cardinality(v_ids), 0) = 1 then
          n_pagador := v_ids[1];
        else
          v_motivo := 'nome_nao_achado';
        end if;
      else
        v_motivo := case when v_tipo = 'opcao' then 'opcao_fora' else 'resposta_nao_serve' end;
      end if;

    when 'cobrar' then
      if (v_tipo in ('opcao', 'palavra') and v_val = 'cobrar') or v_tipo = 'sim' then
        n_cobrar := true;
      elsif (v_tipo in ('opcao', 'palavra') and v_val = 'custo') or v_tipo = 'nao' then
        n_cobrar := false;
      else
        v_motivo := case when v_tipo = 'opcao' then 'opcao_fora' else 'resposta_nao_serve' end;
      end if;

    when 'categoria' then
      if v_tipo = 'opcao' and v_val is not null then
        n_categoria := v_val;
      elsif v_tipo = 'nome' then
        v_t := public._comprovante_normalizar(v_interp->>'texto');
        select (array_agg(f.name order by f.name))[1], count(*) into n_categoria, v_n
          from public.financial_categories f
         where f.type = 'payable' and coalesce(f.active, false) and char_length(v_t) >= 3
           and public._comprovante_normalizar(f.name) = v_t;
        if v_n <> 1 then
          select (array_agg(f.name order by f.name))[1], count(*) into n_categoria, v_n
            from public.financial_categories f
           where f.type = 'payable' and coalesce(f.active, false) and char_length(v_t) >= 3
             and (' ' || public._comprovante_normalizar(f.name) || ' ') like ('% ' || v_t || ' %');
        end if;
        if v_n <> 1 then
          n_categoria := c.categoria;
          v_motivo := 'categoria_nao_achada';
        end if;
      else
        v_motivo := case when v_tipo = 'opcao' then 'opcao_fora' else 'resposta_nao_serve' end;
      end if;

    when 'data' then
      if v_tipo = 'data' and coalesce(v_interp->>'data', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        begin
          n_data := (v_interp->>'data')::date;
        exception when others then
          n_data := c.data_confirmada;
          v_motivo := 'data_invalida';
        end;
        if v_motivo is null and n_data > (now() at time zone 'America/Sao_Paulo')::date then
          n_data := c.data_confirmada;
          v_motivo := 'data_futura';
        end if;
      else
        v_motivo := 'resposta_nao_serve';
      end if;

    when 'corrigir' then
      if v_tipo <> 'opcao' or v_val is null then
        v_motivo := case when v_tipo = 'opcao' then 'opcao_fora' else 'resposta_nao_serve' end;
      elsif v_val = 'cancelar' then
        return jsonb_build_object('resultado', 'corrigir', 'cmp', public._comprovante_resumo(c), 'proxima', null,
                                  'gravacao', null, 'motivo', 'cancelar_pede_motivo');
      elsif v_val = 'depois' then
        if v_aberta then
          perform public._pergunta_fechar(w.id, 'cancelada', 'pular', v_msg);
        end if;
        -- para o fim da fila, e o vigia só volta a ele daqui a 4 h
        update public.comprovantes x set fila_ordem = clock_timestamp(), adiado_ate = now() + interval '4 hours'
         where x.id = c.id;
        perform public._comprovante_pergunta_saiu(c.id);
        v_prox := public._comprovante_proxima(w.phone_normalized, 'pular', null, c.id);
        select * into c from public.comprovantes x where x.id = c.id;
        return jsonb_build_object('resultado', 'proximo', 'cmp', public._comprovante_resumo(c),
          'proxima', case when coalesce((v_prox->>'perguntou')::boolean, false) then v_prox - 'perguntou' end,
          'gravacao', null, 'motivo', 'depois');
      elsif v_val = 'cobrar' and c.destino is distinct from 'os' then
        v_motivo := 'opcao_fora';
      else
        v_forcar_passo := v_val;
        case v_val
          when 'valor' then n_valor := null;
          when 'para_que' then n_destino := null; n_os := null; n_cobrar := null;
          when 'como_pagou' then n_forma := null;
          when 'quem_pagou' then n_quem := null; n_pagador := null;
          when 'cobrar' then n_cobrar := null;
          when 'categoria' then n_categoria := null;
          else null;
        end case;
      end if;

    else
      v_motivo := 'passo_desconhecido';
  end case;

  if v_motivo is not null then
    return jsonb_build_object('resultado', 'invalida', 'cmp', public._comprovante_resumo(c),
      'proxima', case when v_aberta then public._comprovante_montar_pergunta(c, w.id, 'reabrir') end,
      'gravacao', null, 'motivo', v_motivo);
  end if;

  -- mudou o que identifica a compra (valor, data, destino, OS): "é a mesma compra do CMP-…?" vale de novo
  if v_passo <> 'mesma_compra'
     and (n_valor is distinct from c.valor_confirmado or n_data is distinct from c.data_confirmada
          or n_destino is distinct from c.destino or n_os is distinct from c.destino_os_id) then
    n_mesma := null;
    n_outra := null;
  end if;

  v_mudou := n_valor is distinct from c.valor_confirmado or n_data is distinct from c.data_confirmada
             or n_destino is distinct from c.destino or n_os is distinct from c.destino_os_id
             or n_forma is distinct from c.forma_confirmada or n_quem is distinct from c.quem_pagou
             or n_pagador is distinct from c.pagador_payee_id or n_cobrar is distinct from c.cobrar_cliente
             or n_categoria is distinct from c.categoria or n_mesma is distinct from c.mesma_compra_de
             or n_outra is distinct from c.outra_compra;
  update public.comprovantes x
     set valor_confirmado = n_valor, data_confirmada = n_data, destino = n_destino, destino_os_id = n_os,
         forma_confirmada = n_forma, quem_pagou = n_quem, pagador_payee_id = n_pagador,
         cobrar_cliente = n_cobrar, categoria = n_categoria, mesma_compra_de = n_mesma, outra_compra = n_outra,
         passo = v_forcar_passo,
         resumo_versao = x.resumo_versao + case when v_mudou then 1 else 0 end
   where x.id = c.id;

  if v_aberta then
    perform public._pergunta_fechar(w.id, 'respondida', null, v_msg);
  end if;
  v_abriu := public._comprovante_abrir_pergunta(c.id, case when v_passo = 'corrigir' then 'corrigir' else 'reabrir' end, v_override);
  select * into c from public.comprovantes x where x.id = c.id;
  if not coalesce((v_abriu->>'ok')::boolean, false) then
    -- o telefone está ocupado (outra pergunta ou pendência do assistente): o CMP espera a vez
    perform public._comprovante_pergunta_saiu(c.id);
    select * into c from public.comprovantes x where x.id = c.id;
    return jsonb_build_object('resultado', 'proximo', 'cmp', public._comprovante_resumo(c), 'proxima', null,
                              'gravacao', null, 'motivo', 'ocupado', 'ocupado_por', v_abriu->'ocupado_por');
  end if;
  return jsonb_build_object(
    'resultado', case when v_passo = 'corrigir' then 'proximo'
                      when v_abriu->'pergunta'->>'passo' = 'confirmar' then 'resumo'
                      else 'proximo' end,
    'cmp', public._comprovante_resumo(c), 'proxima', v_abriu->'pergunta', 'gravacao', null, 'motivo', null);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 10. comprovante_comando
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_comando(p jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_phone text;
  v_cmd text;
  v_dono record;
  v_aberta record;
  c public.comprovantes;
  v_num integer;
  v_r jsonb;
  v_prox jsonb;
  v_fila integer;
  v_entraram jsonb := '[]'::jsonb;
  v_id uuid;
  v_restam integer;
  v_motivo text;
  v_canc jsonb;
  v_resolvidas text[];
  v_campo text;
  v_valor text;
  v_os jsonb;
  v_data date;
  v_alvo uuid;
  v_cmp_num integer;
  v_gravado_codigo text;
  v_corrigido jsonb;
  v_cat text;
  v_n integer;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'comprovante_comando: a entrada precisa ser um objeto' using errcode = '22023';
  end if;
  v_phone := p->>'phone';
  v_cmd := p->>'comando';
  if v_phone is null or v_phone !~ '^[0-9]{10,15}$' then
    raise exception 'comprovante_comando: telefone inválido' using errcode = '22023';
  end if;
  if v_cmd is null or v_cmd not in ('cmp', 'pular', 'sair', 'lote_antigo', 'cancelar', 'feito', 'corrigir') then
    raise exception 'comprovante_comando: comando desconhecido' using errcode = '22023';
  end if;
  select d.id, d.phone into v_dono from public._comprovante_dono() d;
  if not public._comprovante_conversa_ligada() or v_dono.phone is distinct from v_phone then
    return jsonb_build_object('resultado', 'desligada');
  end if;
  begin
    v_num := nullif(p->>'numero', '')::integer;
  exception when others then
    raise exception 'comprovante_comando: número malformado' using errcode = '22023';
  end;

  perform pg_advisory_xact_lock(hashtextextended('pergunta:' || v_phone, 0));
  perform public._pergunta_limpar(v_phone);
  select w.id, w.referencia_id, w.dados into v_aberta from public.whatsapp_perguntas w
   where w.phone_normalized = v_phone and w.status = 'aberta' and w.origem = 'comprovante';

  if v_cmd in ('cmp', 'cancelar', 'feito') then
    select * into c from public.comprovantes x where x.numero = v_num and x.phone_normalized = v_phone;
    if not found then
      if v_cmd = 'cancelar' and char_length(regexp_replace(coalesce(p->>'motivo', ''), '[^[:alpha:]]', '', 'g')) < 3 then
        return jsonb_build_object('resultado', 'motivo_obrigatorio');
      end if;
      return jsonb_build_object('resultado', 'nao_existe');
    end if;
  end if;

  -- ── cmp N ────────────────────────────────────────────────────────────────────────────────
  if v_cmd = 'cmp' then
    if c.gravado_em is not null or c.situacao = 'cancelado'
       or not (c.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
               or (c.situacao in ('lido', 'falhou') and c.modo = 'dono' and c.fila_desde is null)) then
      return jsonb_build_object('resultado', 'cartao', 'cmp', public._comprovante_resumo(c), 'efeitos', c.efeitos);
    end if;
    if v_aberta.id is not null and v_aberta.referencia_id <> c.id then
      perform public._pergunta_fechar(v_aberta.id, 'substituida', 'cmp', null);
      perform public._comprovante_pergunta_saiu(v_aberta.referencia_id);
      -- o anterior volta à FRENTE da fila
      update public.comprovantes x
         set fila_ordem = coalesce((select min(y.fila_ordem) from public.comprovantes y
                                     where y.phone_normalized = v_phone and y.situacao = 'aguardando_vez'), now())
                          - interval '1 second'
       where x.id = v_aberta.referencia_id;
    end if;
    v_r := public._comprovante_proxima(v_phone, 'cmp', c.id, null);
    return jsonb_build_object('resultado', 'pergunta',
      'pergunta', case when coalesce((v_r->>'perguntou')::boolean, false) then v_r - 'perguntou' end,
      'motivo', case when not coalesce((v_r->>'perguntou')::boolean, false) then v_r->>'motivo' end,
      'ocupado_por', v_r->'ocupado_por');
  end if;

  -- ── pular ────────────────────────────────────────────────────────────────────────────────
  if v_cmd = 'pular' then
    if v_aberta.id is null then
      select count(*) into v_fila from public.comprovantes x
       where x.phone_normalized = v_phone and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
      return jsonb_build_object('resultado', 'pulado', 'codigo', null, 'pergunta', null, 'fila', v_fila);
    end if;
    perform public._pergunta_fechar(v_aberta.id, 'cancelada', 'pular', null);
    -- para o fim da fila, e o vigia só volta a ele daqui a 4 h (senão o "fica para depois" virava
    -- "Ainda falta conferir…" dois minutos depois)
    update public.comprovantes x set fila_ordem = clock_timestamp(), adiado_ate = now() + interval '4 hours'
     where x.id = v_aberta.referencia_id;
    perform public._comprovante_pergunta_saiu(v_aberta.referencia_id);
    v_r := public._comprovante_proxima(v_phone, 'pular', null, v_aberta.referencia_id);
    select count(*) into v_fila from public.comprovantes x
     where x.phone_normalized = v_phone and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
    return jsonb_build_object('resultado', 'pulado',
      'codigo', (select x.codigo from public.comprovantes x where x.id = v_aberta.referencia_id),
      'pergunta', case when coalesce((v_r->>'perguntou')::boolean, false) then v_r - 'perguntou' end,
      'fila', v_fila);
  end if;

  -- ── sair ─────────────────────────────────────────────────────────────────────────────────
  if v_cmd = 'sair' then
    if v_aberta.id is not null then
      perform public._pergunta_fechar(v_aberta.id, 'cancelada', 'sair', null);
      perform public._comprovante_pergunta_saiu(v_aberta.referencia_id);
    end if;
    insert into public.comprovantes_fila_do_telefone as f (phone_normalized, pausada_ate, atualizado_em)
    values (v_phone, now() + interval '12 hours', now())
    on conflict (phone_normalized) do update set pausada_ate = now() + interval '12 hours', atualizado_em = now();
    select count(*) into v_fila from public.comprovantes x
     where x.phone_normalized = v_phone and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim');
    -- o primeiro da fila: o "para continuar antes: *cmp N*"
    return jsonb_build_object('resultado', 'pausado', 'fila', v_fila,
      'codigo', (select x.codigo from public.comprovantes x
                  where x.phone_normalized = v_phone and x.situacao = 'aguardando_vez'
                  order by x.fila_ordem, x.numero limit 1));
  end if;

  -- ── lote antigo ──────────────────────────────────────────────────────────────────────────
  if v_cmd = 'lote_antigo' then
    for v_id in
      select x.id from public.comprovantes x
       where x.phone_normalized = v_phone and x.dono_id = v_dono.id and x.modo = 'dono' and x.numero is not null
         and x.situacao in ('lido', 'falhou') and x.fila_desde is null and x.gravado_em is null
       order by x.recebido_em, x.numero
       limit 20
    loop
      if public._comprovante_entrar_na_fila(v_id) then
        v_entraram := v_entraram || jsonb_build_array(jsonb_build_object(
          'id', v_id, 'codigo', (select x.codigo from public.comprovantes x where x.id = v_id)));
      end if;
    end loop;
    select count(*) into v_restam from public.comprovantes x
     where x.phone_normalized = v_phone and x.dono_id = v_dono.id and x.modo = 'dono' and x.numero is not null
       and x.situacao in ('lido', 'falhou') and x.fila_desde is null and x.gravado_em is null;
    if jsonb_array_length(v_entraram) > 0 then
      v_r := public._comprovante_proxima(v_phone, 'lote_antigo', null, null);
    end if;
    return jsonb_build_object('resultado', 'lote', 'entraram', v_entraram, 'restam', v_restam,
      'pergunta', case when coalesce((v_r->>'perguntou')::boolean, false) then v_r - 'perguntou' end);
  end if;

  -- ── cancelar cmp N motivo ────────────────────────────────────────────────────────────────
  if v_cmd = 'cancelar' then
    v_motivo := nullif(btrim(coalesce(p->>'motivo', '')), '');
    if v_motivo is null or char_length(regexp_replace(v_motivo, '[^[:alpha:]]', '', 'g')) < 3 then
      return jsonb_build_object('resultado', 'motivo_obrigatorio', 'codigo', c.codigo);
    end if;
    v_canc := public.comprovante_cancelar(c.id, left(v_motivo, 300), v_dono.id);
    if not coalesce((v_canc->>'ok')::boolean, false) then
      return jsonb_build_object('resultado', 'cancelamento_recusado', 'cancelamento', v_canc, 'pergunta', null);
    end if;
    if v_aberta.id is not null and v_aberta.referencia_id = c.id then
      v_r := public._comprovante_proxima(v_phone, 'depois_de_gravar', null, null);
    end if;
    return jsonb_build_object('resultado', 'cancelado', 'cancelamento', v_canc,
      'pergunta', case when coalesce((v_r->>'perguntou')::boolean, false) then v_r - 'perguntou' end);
  end if;

  -- ── feito cmp N ──────────────────────────────────────────────────────────────────────────
  if v_cmd = 'feito' then
    v_resolvidas := c.pendencias;
    if cardinality(v_resolvidas) > 0 then
      update public.comprovantes x
         set pendencias = '{}',
             efeitos = x.efeitos || coalesce((select jsonb_agg(jsonb_build_object('tipo', 'pendencia_resolvida', 'qual', q, 'em', now()))
                                                from unnest(v_resolvidas) q), '[]'::jsonb)
       where x.id = c.id;
      update public.comprovantes_indice_mensal i set pendente = true, proxima_em = now(), atualizado_em = now()
       where i.mes = coalesce(c.indice_mes, date_trunc('month', coalesce(c.data_confirmada, c.data_compra, (c.recebido_em at time zone 'America/Sao_Paulo')::date))::date);
    end if;
    return jsonb_build_object('resultado', 'feito', 'codigo', c.codigo, 'resolvidas', to_jsonb(v_resolvidas));
  end if;

  -- ── corrigir <campo> ─────────────────────────────────────────────────────────────────────
  -- O alvo: o CMP dito ("corrigir cmp 124 valor 70"); senão o da pergunta aberta; senão o CMP em
  -- contexto. Logo depois de um "gravado… Próximo:", "corrigir valor 70" sem dizer o CMP é ambíguo
  -- (o gravado ou o próximo?): pergunta qual (resultado qual_cmp), nada muda.
  v_campo := p->>'campo';
  if v_campo is null or v_campo not in ('valor', 'data', 'forma', 'os', 'quem', 'para', 'categoria') then
    raise exception 'comprovante_comando: campo do corrigir desconhecido' using errcode = '22023';
  end if;
  begin
    v_cmp_num := nullif(p->>'cmp', '')::integer;
  exception when others then
    raise exception 'comprovante_comando: número do CMP malformado' using errcode = '22023';
  end;
  if v_cmp_num is not null then
    select x.id into v_alvo from public.comprovantes x where x.numero = v_cmp_num and x.phone_normalized = v_phone;
    if v_alvo is null then
      return jsonb_build_object('resultado', 'nao_existe');
    end if;
  else
    v_alvo := v_aberta.referencia_id;
    if v_aberta.id is not null and v_aberta.dados->>'motivo' = 'depois_de_gravar' then
      select x.codigo into v_gravado_codigo
        from public.comprovantes x
       where x.phone_normalized = v_phone and x.id <> v_aberta.referencia_id and x.gravado_em > now() - interval '2 minutes'
         and x.situacao <> 'cancelado'
       order by x.gravado_em desc
       limit 1;
      if v_gravado_codigo is not null then
        return jsonb_build_object('resultado', 'qual_cmp', 'gravado', v_gravado_codigo,
                                  'aberto', (select x.codigo from public.comprovantes x where x.id = v_aberta.referencia_id));
      end if;
    end if;
  end if;
  if v_alvo is null then
    select x.id into v_alvo
      from public.comprovantes x
     where x.phone_normalized = v_phone and x.numero is not null and x.situacao <> 'cancelado'
       and (x.gravado_em > now() - interval '30 minutes' or x.ultima_pergunta_em > now() - interval '30 minutes')
     order by greatest(coalesce(x.gravado_em, '-infinity'::timestamptz), coalesce(x.ultima_pergunta_em, '-infinity'::timestamptz)) desc
     limit 1;
  end if;
  if v_alvo is null then
    return jsonb_build_object('resultado', 'sem_cmp');
  end if;
  select * into c from public.comprovantes x where x.id = v_alvo for update;
  if c.gravado_em is not null then
    return jsonb_build_object('resultado', 'ja_gravado', 'codigo', c.codigo);
  end if;
  if c.situacao = 'cancelado' then
    return jsonb_build_object('resultado', 'ja_cancelado', 'codigo', c.codigo);
  end if;
  if c.situacao in ('lido', 'falhou') and not public._comprovante_entrar_na_fila(c.id) then
    return jsonb_build_object('resultado', 'sem_cmp');
  end if;

  case v_campo
    when 'valor' then
      v_valor := p->>'valor';
      if v_valor is null or v_valor !~ '^[0-9]{1,10}\.[0-9]{2}$' or v_valor::numeric <= 0 or v_valor::numeric > 999999.99 then
        return jsonb_build_object('resultado', 'invalida', 'codigo', c.codigo, 'motivo', 'valor_invalido');
      end if;
      update public.comprovantes x set valor_confirmado = v_valor::numeric, passo = null, resumo_versao = x.resumo_versao + 1,
                                      mesma_compra_de = null, outra_compra = null
       where x.id = c.id;
      v_corrigido := jsonb_build_object('campo', 'valor', 'valor', v_valor);
    when 'data' then
      begin
        v_data := (p->>'data')::date;
      exception when others then
        v_data := null;
      end;
      if v_data is null or v_data > (now() at time zone 'America/Sao_Paulo')::date then
        return jsonb_build_object('resultado', 'invalida', 'codigo', c.codigo, 'motivo', 'data_invalida');
      end if;
      update public.comprovantes x set data_confirmada = v_data, passo = null, resumo_versao = x.resumo_versao + 1,
                                      mesma_compra_de = null, outra_compra = null
       where x.id = c.id;
      v_corrigido := jsonb_build_object('campo', 'data', 'valor', v_data);
    when 'forma' then
      v_valor := p->>'forma';
      if v_valor is null or v_valor not in ('pix', 'debito', 'credito', 'dinheiro', 'boleto', 'transferencia') then
        return jsonb_build_object('resultado', 'invalida', 'codigo', c.codigo, 'motivo', 'forma_invalida');
      end if;
      update public.comprovantes x
         set forma_confirmada = v_valor, passo = null, resumo_versao = x.resumo_versao + 1,
             -- quem pagou só se pergunta no dinheiro: trocar a forma refaz a pergunta
             quem_pagou = case when v_valor = 'dinheiro' or x.forma_confirmada = 'dinheiro' then null else x.quem_pagou end,
             pagador_payee_id = case when v_valor = 'dinheiro' or x.forma_confirmada = 'dinheiro' then null else x.pagador_payee_id end
       where x.id = c.id;
      v_corrigido := jsonb_build_object('campo', 'forma', 'valor', v_valor);
    when 'os' then
      v_os := public._comprovante_os_por_numero(v_num);
      if not (v_os ? 'id') then
        return jsonb_build_object('resultado', 'invalida', 'codigo', c.codigo, 'motivo', v_os->>'motivo');
      end if;
      update public.comprovantes x
         set destino = 'os', destino_os_id = (v_os->>'id')::uuid,
             cobrar_cliente = case when x.destino_os_id = (v_os->>'id')::uuid then x.cobrar_cliente end,
             mesma_compra_de = null, outra_compra = null,
             passo = null, resumo_versao = x.resumo_versao + 1
       where x.id = c.id;
      v_corrigido := jsonb_build_object('campo', 'os', 'valor',
                                        (select so.service_order_number from public.service_orders so where so.id = (v_os->>'id')::uuid));
    when 'quem' then
      update public.comprovantes x set quem_pagou = null, pagador_payee_id = null, passo = 'quem_pagou',
                                      resumo_versao = x.resumo_versao + 1 where x.id = c.id;
    when 'para' then
      v_valor := p->>'destino';
      if v_valor in ('estoque', 'insumo', 'empresa', 'pessoal') then
        -- "corrigir para estoque": o destino dito, sem o menu
        update public.comprovantes x set destino = v_valor, destino_os_id = null, cobrar_cliente = null, passo = null,
                                        mesma_compra_de = null, outra_compra = null,
                                        resumo_versao = x.resumo_versao + 1 where x.id = c.id;
        v_corrigido := jsonb_build_object('campo', 'para', 'valor', v_valor);
      else
        update public.comprovantes x set destino = null, destino_os_id = null, cobrar_cliente = null, passo = 'para_que',
                                        mesma_compra_de = null, outra_compra = null,
                                        resumo_versao = x.resumo_versao + 1 where x.id = c.id;
      end if;
    when 'categoria' then
      v_valor := public._comprovante_normalizar(p->>'categoria');
      if coalesce(v_valor, '') = '' then
        -- sem o nome: o menu de categorias
        update public.comprovantes x set categoria = null, passo = 'categoria', resumo_versao = x.resumo_versao + 1
         where x.id = c.id;
      else
        select (array_agg(f.name order by f.name))[1], count(*) into v_cat, v_n
          from public.financial_categories f
         where f.type = 'payable' and coalesce(f.active, false) and public._comprovante_normalizar(f.name) = v_valor;
        if v_n <> 1 then
          select (array_agg(f.name order by f.name))[1], count(*) into v_cat, v_n
            from public.financial_categories f
           where f.type = 'payable' and coalesce(f.active, false) and char_length(v_valor) >= 3
             and (' ' || public._comprovante_normalizar(f.name) || ' ') like ('% ' || v_valor || ' %');
        end if;
        if v_n <> 1 then
          return jsonb_build_object('resultado', 'invalida', 'codigo', c.codigo, 'motivo', 'categoria_nao_achada');
        end if;
        update public.comprovantes x set categoria = v_cat, passo = null, resumo_versao = x.resumo_versao + 1
         where x.id = c.id;
        v_corrigido := jsonb_build_object('campo', 'categoria', 'valor', v_cat);
      end if;
  end case;

  if v_aberta.id is not null then
    if public._pergunta_fechar(v_aberta.id, 'substituida', 'corrigir', null) and v_aberta.referencia_id <> c.id then
      perform public._comprovante_pergunta_saiu(v_aberta.referencia_id);
    end if;
  end if;
  v_r := public._comprovante_proxima(v_phone, 'reabrir', c.id, null);
  return jsonb_build_object('resultado', 'pergunta', 'codigo', c.codigo, 'corrigido', v_corrigido,
    'pergunta', case when coalesce((v_r->>'perguntou')::boolean, false) then v_r - 'perguntou' end,
    'motivo', case when not coalesce((v_r->>'perguntou')::boolean, false) then v_r->>'motivo' end);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 11. comprovantes_pendentes: o que o "pendentes" lista (antes das pendências gerais)
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
           'pendencias', to_jsonb(x.pendencias)) order by x.numero), '[]'::jsonb)
    into v_abertos
    from public.comprovantes x
   where x.phone_normalized = p_phone and x.numero is not null
     and (x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
          or (x.gravado_em is not null and x.situacao <> 'cancelado' and cardinality(x.pendencias) > 0)
          or (x.situacao = 'aguardando_xml' and x.gravado_em <= now() - interval '5 days'));
  select count(*) into v_antigos from public.comprovantes x
   where x.phone_normalized = p_phone and x.dono_id = v_dono.id and x.modo = 'dono' and x.numero is not null
     and x.situacao in ('lido', 'falhou') and x.fila_desde is null and x.gravado_em is null;
  return jsonb_build_object('abertos', v_abertos, 'total', jsonb_array_length(v_abertos), 'antigos', v_antigos);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 12. comprovante_cnpj_cache: a consulta da BrasilAPI (dado público). Raiz da HBR = nada.
--     O nome é gravado SEM CPF (MEI: a razão social traz o CPF do titular; _comprovante_sem_cpf).
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_cnpj_cache(p_cnpj text, p_dados jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_encontrado boolean;
  v_razao text;
  v_fantasia text;
  v_nome text;
begin
  if p_cnpj is null or p_cnpj !~ '^[0-9]{14}$' then
    raise exception 'comprovante_cnpj_cache: CNPJ inválido' using errcode = '22023';
  end if;
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' or jsonb_typeof(p_dados->'encontrado') is distinct from 'boolean' then
    raise exception 'comprovante_cnpj_cache: dados inválidos' using errcode = '22023';
  end if;
  if left(p_cnpj, 8) = public.raiz_do_cnpj_da_empresa() then
    return;
  end if;
  v_encontrado := (p_dados->>'encontrado')::boolean;
  v_razao := case when v_encontrado then left(public._comprovante_sem_cpf(p_dados->>'razao_social'), 200) end;
  v_fantasia := case when v_encontrado then left(public._comprovante_sem_cpf(p_dados->>'nome_fantasia'), 200) end;
  insert into public.cnpj_consultas as k (cnpj, encontrado, razao_social, nome_fantasia, situacao_cadastral, consultado_em)
  values (p_cnpj, v_encontrado, v_razao, v_fantasia,
          case when v_encontrado then left(nullif(btrim(p_dados->>'situacao_cadastral'), ''), 60) end,
          now())
  on conflict (cnpj) do update
    set encontrado = excluded.encontrado, razao_social = excluded.razao_social, nome_fantasia = excluded.nome_fantasia,
        situacao_cadastral = excluded.situacao_cadastral, consultado_em = excluded.consultado_em;
  if v_encontrado then
    v_nome := coalesce(v_fantasia, v_razao);
    if v_nome is not null then
      update public.comprovantes x set fornecedor_receita = v_nome
       where x.emitente_cnpj = p_cnpj and x.supplier_id is null and x.fornecedor_receita is distinct from v_nome;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 13. comprovantes_cnpj_a_consultar: CNPJs de fornecedor sem cadastro e sem cache válido
--     Só com a conversa ligada (desligada, a F2 não chama a BrasilAPI). Sem p_ids (o vigia): só de
--     CMP na conversa recebido nas últimas 24 h — a mesma regra da guarda do cron (com a BrasilAPI
--     fora do ar, nada é gravado no cache e a consulta não pode se repetir para sempre).
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_cnpj_a_consultar(p_ids uuid[] default null, p_limite integer default 3)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
  v_raiz text := public.raiz_do_cnpj_da_empresa();
begin
  if not public._comprovante_conversa_ligada() then
    return '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(t.cnpj order by t.quando desc), '[]'::jsonb) into v
    from (select x.emitente_cnpj as cnpj, max(x.recebido_em) as quando
            from public.comprovantes x
           where x.numero is not null and x.situacao <> 'cancelado' and x.modo = 'dono'
             and x.emitente_cnpj ~ '^[0-9]{14}$' and x.cnpj_confianca in ('alta', 'media') and x.supplier_id is null
             and (v_raiz is null or left(x.emitente_cnpj, 8) <> v_raiz)
             and (case when p_ids is null
                       then x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim')
                            and x.recebido_em > now() - interval '24 hours'
                       else x.id = any (p_ids) end)
             and not exists (select 1 from public.cnpj_consultas k
                              where k.cnpj = x.emitente_cnpj
                                and k.consultado_em > now() - case when k.encontrado then interval '90 days' else interval '7 days' end)
           group by x.emitente_cnpj
           order by 2 desc
           limit least(greatest(coalesce(p_limite, 3), 1), 20)) t;
  return v;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 14. comprovantes_consultar: a leitura do assistente (consultar_comprovantes). Só admin; para quem
--     não é, resposta vazia (nunca erro). Só os CMPs do modo dono (os de "sombra" o dono nem conhece).
--     Nunca leitura, texto do OCR, legenda, wa_key nem CPF.
-- ---------------------------------------------------------------------------------------------
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
             'cobrar_cliente', f.cobrar_cliente,
             'quem_pagou', f.quem_pagou,
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
-- 15. comprovantes_parecidos: CMPs com o mesmo valor (±0,01) e data (±1 dia) de um lançamento que
--     o assistente vai fazer — as travas contra lançar em dobro. Sem data: recebidos nos últimos
--     3 dias. Com OS: gravados só da mesma OS; abertos da mesma OS ou ainda sem OS. Só admin (os
--     detalhes: código, valor, data, fornecedor). Só CMPs do modo dono. "abertos" só com a conversa
--     LIGADA (desligada, o dono não tem como completar um CMP: *cmp N* não faz nada) e só os que a
--     conversa completaria (na fila, na pergunta ou ainda não conferidos).
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_parecidos(p_valor numeric, p_data date, p_os uuid, p_autor uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_autor uuid := coalesce((select auth.uid()), p_autor);
  v_abertos jsonb := '[]'::jsonb;
  v_gravados jsonb;
begin
  if v_autor is null or not public.is_admin(v_autor) or p_valor is null then
    return jsonb_build_object('abertos', '[]'::jsonb, 'gravados', '[]'::jsonb);
  end if;
  if public._comprovante_conversa_ligada() then
    select coalesce(jsonb_agg(jsonb_build_object(
             'codigo', x.codigo, 'numero', x.numero, 'valor', coalesce(x.valor_confirmado, x.valor)::text,
             'data', coalesce(x.data_confirmada, x.data_compra), 'fornecedor', public._comprovante_fornecedor(x)->>'nome')
             order by x.numero), '[]'::jsonb)
      into v_abertos
      from public.comprovantes x
     where x.numero is not null and x.modo = 'dono' and x.gravado_em is null
       and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim', 'lido', 'falhou')
       and abs(coalesce(x.valor_confirmado, x.valor) - p_valor) <= 0.01
       and (case when p_data is null then x.recebido_em > now() - interval '3 days'
                 else abs(coalesce(x.data_confirmada, x.data_compra, (x.recebido_em at time zone 'America/Sao_Paulo')::date) - p_data) <= 1 end)
       and (p_os is null or x.destino_os_id is null or x.destino_os_id = p_os);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', x.codigo, 'numero', x.numero, 'valor', coalesce(x.valor_confirmado, x.valor)::text,
           'data', coalesce(x.data_confirmada, x.data_compra), 'os_id', x.destino_os_id,
           'efeitos', coalesce((select jsonb_agg(distinct e->>'tipo') from jsonb_array_elements(x.efeitos) e
                                 where e->>'tipo' not in ('pendencia', 'pendencia_resolvida')), '[]'::jsonb))
           order by x.numero), '[]'::jsonb)
    into v_gravados
    from public.comprovantes x
   where x.numero is not null and x.modo = 'dono' and x.situacao <> 'cancelado' and x.gravado_em is not null
     and abs(coalesce(x.valor_confirmado, x.valor) - p_valor) <= 0.01
     and (case when p_data is null then x.recebido_em > now() - interval '3 days'
               else abs(coalesce(x.data_confirmada, x.data_compra) - p_data) <= 1 end)
     and (p_os is null or x.destino_os_id = p_os);
  return jsonb_build_object('abertos', v_abertos, 'gravados', v_gravados);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 15b. comprovantes_ja_lancados (revisão de 11/10/2026): a trava contra o dobro para QUEM lança
--      (admin ou financeiro), sem mostrar nada do comprovante do dono — só se já há um CMP gravado
--      com um destes efeitos (ja_lancado) e se há um CMP aberto do mesmo valor (aberto; só com a
--      conversa ligada). Nunca código, valor nem fornecedor ("só o dono vê comprovante").
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovantes_ja_lancados(p_valor numeric, p_data date, p_os uuid, p_efeitos text[], p_autor uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_autor uuid := coalesce((select auth.uid()), p_autor);
  v_ja boolean := false;
  v_aberto boolean := false;
begin
  if v_autor is null or not public.is_admin_or_financial(v_autor) or p_valor is null then
    return jsonb_build_object('ja_lancado', false, 'aberto', false);
  end if;
  select exists (
    select 1 from public.comprovantes x
     where x.numero is not null and x.modo = 'dono' and x.situacao <> 'cancelado' and x.gravado_em is not null
       and abs(coalesce(x.valor_confirmado, x.valor) - p_valor) <= 0.01
       and (case when p_data is null then x.recebido_em > now() - interval '3 days'
                 else abs(coalesce(x.data_confirmada, x.data_compra) - p_data) <= 1 end)
       and (p_os is null or x.destino_os_id = p_os)
       and exists (select 1 from jsonb_array_elements(x.efeitos) e where e->>'tipo' = any (coalesce(p_efeitos, '{}'::text[]))))
    into v_ja;
  if public._comprovante_conversa_ligada() then
    select exists (
      select 1 from public.comprovantes x
       where x.numero is not null and x.modo = 'dono' and x.gravado_em is null
         and x.situacao in ('aguardando_vez', 'perguntando', 'aguardando_sim', 'lido', 'falhou')
         and abs(coalesce(x.valor_confirmado, x.valor) - p_valor) <= 0.01
         and (case when p_data is null then x.recebido_em > now() - interval '3 days'
                   else abs(coalesce(x.data_confirmada, x.data_compra, (x.recebido_em at time zone 'America/Sao_Paulo')::date) - p_data) <= 1 end)
         and (p_os is null or x.destino_os_id is null or x.destino_os_id = p_os))
      into v_aberto;
  end if;
  return jsonb_build_object('ja_lancado', v_ja, 'aberto', v_aberto);
end $$;

-- ---------------------------------------------------------------------------------------------
-- 15c. comprovante_acrescentar_dica (revisão de 11/10/2026): o dono manda a foto e, em seguida, um
--      texto solto ("essa é da OS do Brisa", "gasolina do Brisa"). O texto vira dica DESTE CMP (o que
--      chegou há até 2 min e ainda não foi perguntado) e não vai ao assistente. Na fila e sem destino,
--      a dica já pré-preenche (como a legenda). A mensagem fica marcada: não conta como "conversa em
--      andamento" para a abertura. Devolve {"ok","codigo","destino"}.
-- ---------------------------------------------------------------------------------------------
create or replace function public.comprovante_acrescentar_dica(p_id uuid, p_texto text, p_message_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c public.comprovantes;
  v_texto text := left(nullif(btrim(coalesce(p_texto, '')), ''), 500);
  v_dica jsonb;
begin
  if v_texto is null then
    raise exception 'comprovante_acrescentar_dica: texto vazio' using errcode = '22023';
  end if;
  select * into c from public.comprovantes x where x.id = p_id for update;
  if not found or c.modo <> 'dono' or c.gravado_em is not null or c.situacao = 'cancelado'
     or c.phone_normalized is distinct from (select d.phone from public._comprovante_dono() d)
     or not public._comprovante_conversa_ligada() then
    return jsonb_build_object('ok', false, 'codigo', c.codigo);
  end if;
  update public.comprovantes x
     set dica_da_legenda = left(btrim(coalesce(x.dica_da_legenda || ' ', '') || v_texto), 1024),
         mensagens_de_dica = case when p_message_id is null or p_message_id = any (x.mensagens_de_dica)
                                       or cardinality(x.mensagens_de_dica) >= 20
                                  then x.mensagens_de_dica else x.mensagens_de_dica || p_message_id end
   where x.id = c.id
  returning * into c;
  if c.situacao = 'aguardando_vez' and c.destino is null then
    v_dica := public._comprovante_ler_dica(c.legenda, c.dica_da_legenda);
    update public.comprovantes x
       set destino = coalesce(x.destino, v_dica->>'destino'),
           destino_os_id = coalesce(x.destino_os_id, nullif(v_dica->>'os_id', '')::uuid),
           resumo_versao = x.resumo_versao + case when v_dica ? 'destino' then 1 else 0 end
     where x.id = c.id
    returning * into c;
  end if;
  return jsonb_build_object('ok', true, 'codigo', c.codigo, 'destino', c.destino);
end $$;

-- ---------------------------------------------------------------------------------------------
-- Privilégios (revogar de anon/authenticated POR ASSINATURA; helpers sem grant para ninguém)
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
begin
  foreach v_f in array array[
    'public._comprovante_normalizar(text)',
    'public._comprovante_sem_cpf(text)',
    'public._comprovante_tipo_no_texto(text)',
    'public._comprovante_e_nfe(public.comprovantes)',
    'public._comprovante_os_info(uuid)',
    'public._comprovante_os_por_numero(integer)',
    'public._comprovante_ler_dica(text, text)',
    'public._comprovante_menu_para_que(public.comprovantes)',
    'public._comprovante_categoria_provavel(uuid)',
    'public._comprovante_socio(uuid)',
    'public._comprovante_tecnicos()',
    'public._comprovante_efetivo(public.comprovantes)',
    'public._comprovante_fornecedor(public.comprovantes)',
    'public._comprovante_mesma_compra(public.comprovantes)',
    'public._comprovante_proximo_passo(public.comprovantes)',
    'public._comprovante_resumo(public.comprovantes)',
    'public._comprovante_opcoes_do_passo(public.comprovantes, text)',
    'public._comprovante_usa_pasta_do_barco(jsonb)',
    'public._comprovante_montar_pergunta(public.comprovantes, uuid, text)',
    'public._comprovante_entrar_na_fila(uuid)',
    'public._comprovante_abrir_pergunta(uuid, text, jsonb)',
    'public._comprovante_conversa_em_andamento(text)',
    'public._comprovante_vigia_pode(text)',
    'public._comprovante_cmp_da_vigia(text)',
    'public._comprovante_proxima(text, text, uuid, uuid)']
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_f);
  end loop;
end $$;

revoke all on function public._comprovante_normalizar(text) from public, anon, authenticated;
revoke all on function public._comprovante_sem_cpf(text) from public, anon, authenticated;
revoke all on function public._comprovante_tipo_no_texto(text) from public, anon, authenticated;
revoke all on function public._comprovante_e_nfe(public.comprovantes) from public, anon, authenticated;
revoke all on function public._comprovante_os_info(uuid) from public, anon, authenticated;
revoke all on function public._comprovante_os_por_numero(integer) from public, anon, authenticated;
revoke all on function public._comprovante_ler_dica(text, text) from public, anon, authenticated;
revoke all on function public._comprovante_menu_para_que(public.comprovantes) from public, anon, authenticated;
revoke all on function public._comprovante_categoria_provavel(uuid) from public, anon, authenticated;
revoke all on function public._comprovante_socio(uuid) from public, anon, authenticated;
revoke all on function public._comprovante_tecnicos() from public, anon, authenticated;
revoke all on function public._comprovante_efetivo(public.comprovantes) from public, anon, authenticated;
revoke all on function public._comprovante_fornecedor(public.comprovantes) from public, anon, authenticated;
revoke all on function public._comprovante_mesma_compra(public.comprovantes) from public, anon, authenticated;
revoke all on function public._comprovante_proximo_passo(public.comprovantes) from public, anon, authenticated;
revoke all on function public._comprovante_resumo(public.comprovantes) from public, anon, authenticated;
revoke all on function public._comprovante_opcoes_do_passo(public.comprovantes, text) from public, anon, authenticated;
revoke all on function public._comprovante_usa_pasta_do_barco(jsonb) from public, anon, authenticated;
revoke all on function public._comprovante_montar_pergunta(public.comprovantes, uuid, text) from public, anon, authenticated;
revoke all on function public._comprovante_entrar_na_fila(uuid) from public, anon, authenticated;
revoke all on function public._comprovante_abrir_pergunta(uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public._comprovante_conversa_em_andamento(text) from public, anon, authenticated;
revoke all on function public._comprovante_vigia_pode(text) from public, anon, authenticated;
revoke all on function public._comprovante_cmp_da_vigia(text) from public, anon, authenticated;
revoke all on function public._comprovante_proxima(text, text, uuid, uuid) from public, anon, authenticated;

revoke all on function public.comprovante_conversa_entrar(uuid[]) from public, anon, authenticated;
revoke all on function public.comprovante_proxima_pergunta(text, text, uuid) from public, anon, authenticated;
revoke all on function public.comprovante_pergunta_nao_enviada(uuid) from public, anon, authenticated;
revoke all on function public.comprovante_responder(jsonb) from public, anon, authenticated;
revoke all on function public.comprovante_comando(jsonb) from public, anon, authenticated;
revoke all on function public.comprovantes_pendentes(text) from public, anon, authenticated;
revoke all on function public.comprovante_cnpj_cache(text, jsonb) from public, anon, authenticated;
revoke all on function public.comprovantes_cnpj_a_consultar(uuid[], integer) from public, anon, authenticated;
revoke all on function public.comprovante_acrescentar_dica(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.comprovantes_consultar(jsonb) from public, anon, authenticated;
revoke all on function public.comprovantes_parecidos(numeric, date, uuid, uuid) from public, anon, authenticated;
revoke all on function public.comprovantes_ja_lancados(numeric, date, uuid, text[], uuid) from public, anon, authenticated;

grant execute on function public.comprovante_conversa_entrar(uuid[]) to service_role;
grant execute on function public.comprovante_proxima_pergunta(text, text, uuid) to service_role;
grant execute on function public.comprovante_pergunta_nao_enviada(uuid) to service_role;
grant execute on function public.comprovante_responder(jsonb) to service_role;
grant execute on function public.comprovante_comando(jsonb) to service_role;
grant execute on function public.comprovantes_pendentes(text) to service_role;
grant execute on function public.comprovante_cnpj_cache(text, jsonb) to service_role;
grant execute on function public.comprovantes_cnpj_a_consultar(uuid[], integer) to service_role;
grant execute on function public.comprovante_acrescentar_dica(uuid, text, uuid) to service_role;
-- as leituras do assistente: o painel (authenticated) e o WhatsApp (service_role); o cargo é conferido dentro
grant execute on function public.comprovantes_consultar(jsonb) to authenticated, service_role;
grant execute on function public.comprovantes_parecidos(numeric, date, uuid, uuid) to authenticated, service_role;
grant execute on function public.comprovantes_ja_lancados(numeric, date, uuid, text[], uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: RPCs 6-13 e 15c só service_role; 14, 15 e 15b sem anon, com authenticated e service_role;
-- helpers sem grant.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
  v_rpcs text[] := array[
    'public.comprovante_conversa_entrar(uuid[])',
    'public.comprovante_proxima_pergunta(text, text, uuid)',
    'public.comprovante_pergunta_nao_enviada(uuid)',
    'public.comprovante_responder(jsonb)',
    'public.comprovante_comando(jsonb)',
    'public.comprovantes_pendentes(text)',
    'public.comprovante_cnpj_cache(text, jsonb)',
    'public.comprovantes_cnpj_a_consultar(uuid[], integer)',
    'public.comprovante_acrescentar_dica(uuid, text, uuid)'];
  v_leituras text[] := array[
    'public.comprovantes_consultar(jsonb)',
    'public.comprovantes_parecidos(numeric, date, uuid, uuid)',
    'public.comprovantes_ja_lancados(numeric, date, uuid, text[], uuid)'];
  v_helpers text[] := array[
    'public._comprovante_normalizar(text)',
    'public._comprovante_sem_cpf(text)',
    'public._comprovante_tipo_no_texto(text)',
    'public._comprovante_e_nfe(public.comprovantes)',
    'public._comprovante_os_info(uuid)',
    'public._comprovante_os_por_numero(integer)',
    'public._comprovante_ler_dica(text, text)',
    'public._comprovante_menu_para_que(public.comprovantes)',
    'public._comprovante_categoria_provavel(uuid)',
    'public._comprovante_socio(uuid)',
    'public._comprovante_tecnicos()',
    'public._comprovante_efetivo(public.comprovantes)',
    'public._comprovante_fornecedor(public.comprovantes)',
    'public._comprovante_mesma_compra(public.comprovantes)',
    'public._comprovante_proximo_passo(public.comprovantes)',
    'public._comprovante_resumo(public.comprovantes)',
    'public._comprovante_opcoes_do_passo(public.comprovantes, text)',
    'public._comprovante_usa_pasta_do_barco(jsonb)',
    'public._comprovante_montar_pergunta(public.comprovantes, uuid, text)',
    'public._comprovante_entrar_na_fila(uuid)',
    'public._comprovante_abrir_pergunta(uuid, text, jsonb)',
    'public._comprovante_conversa_em_andamento(text)',
    'public._comprovante_vigia_pode(text)',
    'public._comprovante_cmp_da_vigia(text)',
    'public._comprovante_proxima(text, text, uuid, uuid)'];
begin
  foreach v_f in array v_rpcs || v_helpers loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
      raise exception 'função da conversa dos comprovantes exposta para anon/authenticated: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_rpcs loop
    if not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'a edge (service_role) não alcança %', v_f;
    end if;
  end loop;
  foreach v_f in array v_leituras loop
    if has_function_privilege('anon', v_f, 'execute') then
      raise exception 'leitura do assistente exposta para anon: %', v_f;
    end if;
    if not has_function_privilege('authenticated', v_f, 'execute') or not has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'leitura do assistente sem authenticated/service_role: %', v_f;
    end if;
  end loop;
  foreach v_f in array v_helpers loop
    if has_function_privilege('service_role', v_f, 'execute') then
      raise exception 'helper interno da conversa alcançável pela service_role: %', v_f;
    end if;
  end loop;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011202000', 'comprovantes_conversa_rpcs')
on conflict do nothing;
