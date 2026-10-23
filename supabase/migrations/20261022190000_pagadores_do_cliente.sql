-- Pagadores do cliente (leva 8, 22/10/2026): "Pago por", quem costuma pagar por um cliente e a pergunta
-- "de quem é este pagamento?" no lugar de "cadastrar cliente" com os dados de quem pagou.
--
-- O problema (mapas de 22/10/2026, só SELECT, juntando as 3 ligações extrato ↔ conta a receber): de 93 linhas,
-- 20 (11 pares) foram pagas por um documento diferente do do cliente e 19 (13 pares) por alguém quando o cliente
-- não tem documento. A fila do Extrato não sabia disso: propunha "cadastrar cliente" com o CPF/CNPJ de quem pagou
-- (das 21 entradas que carregaram a proposta, 9 foram aprovadas, quase todas para um cliente com outro documento)
-- e o histórico de UM pagamento de terceiro já identificava o cliente em verde, sem pergunta.
--
-- Decisões do dono ("siga pelo recomendado", 22/10/2026):
--   * pagador conhecido de um cliente só existe com o SIM do dono: o administrador grava 'confirmado'; o
--     financeiro grava 'proposto' (hoje há 1 administrador ativo, que é o dono);
--   * o documento e o nome do pagador vêm da linha do banco, nunca de quem chama ("IA pensa, sistema preenche");
--   * pagador conhecido vira SUGESTÃO com motivo, nunca baixa automática (o motor fica na edge finance-review);
--   * relações: empresa_do_cliente, conjuge, parente, marina, seguradora, outro;
--   * CPF de terceiro é dado pessoal: só admin e financeiro leem (RLS), nada para anon.
--
-- O que esta migration faz (só esquema; nenhum dado nasce aqui — todo pagador nasce de um clique):
--   1. tabela public.pagadores_do_cliente, com RLS de leitura para admin/financeiro e nenhuma policy de escrita;
--   2. guardar_pagadores_do_cliente(p_itens, p_autor) — grava (admin: confirmado; financeiro: proposto), recusa
--      item a item com motivo legível e, ao confirmar, tira o cliente da regra de entrada "documento → cliente"
--      do mesmo documento (a regra continua valendo para a categoria): uma fonte só para o mesmo vínculo;
--   3. decidir_pagador_do_cliente(p_id, p_decisao, p_motivo, p_autor, p_relacao) — confirmar/reativar (só admin; ao
--      confirmar, o admin pode trocar a relação), recusar/pausar (admin; o financeiro só o PROPOSTO — o que o dono já
--      decidiu, só o dono desfaz);
--   4. recusar_pagadores_do_cliente(p_itens, p_motivo, p_autor) — "não é pagador habitual" a partir da linha do
--      banco (o par ainda não está na tabela): grava 'recusado', que não volta à lista nem vira sugestão (o motor da
--      fila lê os recusados e pausados como VETO daquele cliente para aquele documento);
--   5. pagadores_para_conferir() — a lista histórica para o dono conferir, uma linha por par cliente × pagador
--      (o 'proposto' pelo financeiro continua nela, esperando o SIM do administrador — também o que veio da fila ou do
--      assistente e não paga conta nenhuma ainda);
--   6. view public.pagamentos_com_pagador (security_invoker) — quem pagou cada pagamento, para o "Pago por" e o
--      recibo, sem o embed payments ↔ bank_transactions (2 FKs = PGRST201).
--
-- Regra de entrada ANTIGA ("documento → cliente Y") e pagador confirmado de OUTRO cliente X: a regra não é apagada
-- (é o vínculo com Y), mas deixa de decidir o cliente — o motor da fila pergunta "de quem é?" com Y e X como
-- candidatos (finance-review/identificacao.ts), e guardar/decidir avisam o dono no retorno.
--
-- Comparação de documento: as funções que já existem e o motor usa (_doc_normalizado devolve o zero que a
-- planilha comeu; _documento_contradiz compara CNPJ pela raiz de 8 dígitos e CPF inteiro).
--
-- Idempotente. Versão 20261022190000: depois da última do ramo (20261021170000). Se outra migration de versão maior
-- for aplicada antes desta, renomear antes de publicar.

-- ---------------------------------------------------------------------------------------------
-- 1. Tabela
-- ---------------------------------------------------------------------------------------------
create table if not exists public.pagadores_do_cliente (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null,
  documento text not null,
  nome text not null,
  relacao text not null,
  situacao text not null default 'proposto',
  observacao text,
  origem text,
  bank_transaction_id uuid,
  proposto_por uuid,
  proposto_em timestamptz not null default now(),
  confirmado_por uuid,
  confirmado_em timestamptz,
  decidido_motivo text,
  constraint pagadores_do_cliente_client_id_fkey
    foreign key (client_id) references public.clients(id) on delete cascade,
  constraint pagadores_do_cliente_bank_transaction_id_fkey
    foreign key (bank_transaction_id) references public.bank_transactions(id) on delete set null,
  constraint pagadores_do_cliente_proposto_por_fkey
    foreign key (proposto_por) references public.app_users(id) on delete set null,
  constraint pagadores_do_cliente_confirmado_por_fkey
    foreign key (confirmado_por) references public.app_users(id) on delete set null,
  constraint pagadores_do_cliente_documento_check check (documento ~ '^([0-9]{11}|[0-9]{14})$'),
  constraint pagadores_do_cliente_nome_check check (btrim(nome) <> ''),
  constraint pagadores_do_cliente_relacao_check
    check (relacao in ('empresa_do_cliente', 'conjuge', 'parente', 'marina', 'seguradora', 'outro')),
  constraint pagadores_do_cliente_situacao_check
    check (situacao in ('proposto', 'confirmado', 'recusado', 'pausado')),
  constraint pagadores_do_cliente_origem_check
    check (origem is null or origem in ('historico', 'fila', 'assistente')),
  -- confirmado sempre diz quando (quem pode ficar nulo se o usuário for apagado)
  constraint pagadores_do_cliente_confirmado_check check (situacao <> 'confirmado' or confirmado_em is not null),
  constraint pagadores_do_cliente_um_por_cliente unique (client_id, documento)
);

create index if not exists pagadores_do_cliente_documento_idx on public.pagadores_do_cliente (documento);

comment on table public.pagadores_do_cliente is
  'Quem costuma pagar por um cliente (empresa dele, cônjuge, parente, marina, seguradora). Nasce de uma linha do banco; '
  'só o administrador confirma (o SIM do dono). O motor da fila do Extrato SUGERE o cliente por aqui, nunca dá baixa. '
  'Escrita só pelas funções guardar_pagadores_do_cliente, decidir_pagador_do_cliente e recusar_pagadores_do_cliente.';
comment on column public.pagadores_do_cliente.documento is 'CPF (11) ou CNPJ (14) de quem pagou, só dígitos, tirado da linha do banco.';
comment on column public.pagadores_do_cliente.nome is 'Nome de quem pagou como veio do banco (preenchido pelo sistema).';
comment on column public.pagadores_do_cliente.bank_transaction_id is 'A linha do banco que prova o pagamento (a primeira guardada).';

-- ---------------------------------------------------------------------------------------------
-- 2. RLS e privilégios (revogar de anon/authenticated POR NOME: o grant padrão do Supabase não vem de PUBLIC)
-- ---------------------------------------------------------------------------------------------
alter table public.pagadores_do_cliente enable row level security;

revoke all on table public.pagadores_do_cliente from public, anon, authenticated;
grant select on table public.pagadores_do_cliente to authenticated;
grant select on table public.pagadores_do_cliente to service_role;

drop policy if exists pagadores_do_cliente_admin_financeiro_le on public.pagadores_do_cliente;
create policy pagadores_do_cliente_admin_financeiro_le on public.pagadores_do_cliente
  for select to authenticated
  using (public.is_admin_or_financial((select auth.uid())));

-- ---------------------------------------------------------------------------------------------
-- 3. Auxiliares internas (ninguém de fora executa)
-- ---------------------------------------------------------------------------------------------

-- Raízes do CNPJ da própria HBR: app_settings.cnpj (o que a fila usa para "transferência entre contas") e o
-- cadastro fiscal. Dinheiro da própria empresa nunca é "pagador de cliente".
create or replace function public._raizes_do_cnpj_da_hbr()
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_remove(array[
    (select case when length(public._doc_normalizado(s.value)) = 14 then left(public._doc_normalizado(s.value), 8) end
       from public.app_settings s where s.key = 'cnpj'),
    public.raiz_do_cnpj_da_empresa()
  ], null), '{}'::text[]);
$$;

-- Ao confirmar um pagador, a regra de entrada "documento → cliente" do mesmo documento e do mesmo cliente deixa de
-- apontar o cliente (continua valendo para a categoria). Sem isto haveria duas fontes para o mesmo vínculo, e a
-- regra (uma por documento) escolheria um cliente em silêncio quando marina ou seguradora paga por vários.
create or replace function public._pagador_consolidar_regras(p_client_id uuid, p_documento text)
returns uuid[]
language sql
volatile
security definer
set search_path = public
as $$
  with alvo as (
    update public.finance_rules fr
       set set_client_id = null
     where fr.match_type = 'document'
       and fr.direction = 'credit'
       and fr.set_client_id = p_client_id
       and length(public._doc_normalizado(fr.match_value)) >= 11
       and not public._documento_contradiz(fr.match_value, p_documento)
    returning fr.id
  )
  select coalesce(array_agg(id order by id), '{}'::uuid[]) from alvo;
$$;

-- A regra de entrada ATIVA "este documento é do cliente Y" de um cliente DIFERENTE do pagador que se guarda (CNPJ pela
-- raiz, como a consolidação). Ela não é apagada — é o vínculo com Y —, mas deixa de decidir o cliente: o motor da fila
-- pergunta "de quem é?" com Y e os clientes do pagador (identificacao.ts). Quem guarda é avisado. Nulo = nenhuma.
create or replace function public._pagador_regra_de_outro_cliente(p_client_id uuid, p_documento text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('finance_rule_id', fr.id, 'client_id', fr.set_client_id, 'cliente', c.name)
    from public.finance_rules fr
    join public.clients c on c.id = fr.set_client_id
   where fr.match_type = 'document'
     and fr.direction = 'credit'
     and fr.status = 'active'
     and fr.set_client_id is not null
     and fr.set_client_id <> p_client_id
     and length(public._doc_normalizado(fr.match_value)) >= 11
     and not public._documento_contradiz(fr.match_value, p_documento)
   order by fr.id
   limit 1;
$$;

revoke all on function public._raizes_do_cnpj_da_hbr() from public, anon, authenticated;
revoke all on function public._pagador_consolidar_regras(uuid, text) from public, anon, authenticated;
revoke all on function public._pagador_regra_de_outro_cliente(uuid, text) from public, anon, authenticated;
grant execute on function public._raizes_do_cnpj_da_hbr() to service_role;
grant execute on function public._pagador_consolidar_regras(uuid, text) to service_role;
grant execute on function public._pagador_regra_de_outro_cliente(uuid, text) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 4. guardar_pagadores_do_cliente
-- ---------------------------------------------------------------------------------------------
-- p_itens: [{client_id, bank_transaction_id, relacao, observacao?, origem?}], no máximo 50.
-- O documento e o nome NÃO vêm de quem chama: saem da linha do banco. Cada item recusado volta com o motivo; os
-- outros são gravados. Autor: auth.uid() na tela; p_autor só quando a chamada vem por service-role (assistente).
create or replace function public.guardar_pagadores_do_cliente(p_itens jsonb, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_admin boolean;
  v_raizes text[] := public._raizes_do_cnpj_da_hbr();
  v_item jsonb;
  v_i integer := 0;
  v_cliente public.clients%rowtype;
  t public.bank_transactions%rowtype;
  v_atual public.pagadores_do_cliente%rowtype;
  v_existe boolean;
  v_doc text;
  v_nome text;
  v_relacao text;
  v_obs text;
  v_origem text;
  v_outro text;
  v_ligada boolean;
  v_na_fila boolean;
  v_motivo text;
  v_situacao text;
  v_id uuid;
  v_regras uuid[];
  v_todas_regras uuid[] := '{}';
  v_gravados jsonb := '[]'::jsonb;
  v_recusados jsonb := '[]'::jsonb;
  v_conflito jsonb;
  v_avisos jsonb := '[]'::jsonb;
  v_n integer;
  v_nr integer;
  v_msg text;
begin
  if v_autor is null then
    raise exception 'Diga quem está guardando: entre no sistema (ou o assistente informa o autor).' using errcode = '42501';
  end if;
  v_admin := public.is_admin(v_autor);

  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Escolha ao menos um pagador para guardar.';
  end if;
  if jsonb_array_length(p_itens) > 50 then
    raise exception 'No máximo 50 pagadores de uma vez (vieram %).', jsonb_array_length(p_itens);
  end if;

  for v_item in select e.value from jsonb_array_elements(p_itens) e loop
    v_i := v_i + 1;
    v_motivo := null;
    v_ligada := false;
    v_na_fila := false;

    -- O pedido
    if jsonb_typeof(v_item) <> 'object'
       or coalesce(v_item ->> 'client_id', '') !~ c_uuid
       or coalesce(v_item ->> 'bank_transaction_id', '') !~ c_uuid then
      v_motivo := 'Falta o cliente ou a linha do extrato.';
    end if;
    v_relacao := btrim(coalesce(v_item ->> 'relacao', ''));
    if v_motivo is null and v_relacao not in ('empresa_do_cliente', 'conjuge', 'parente', 'marina', 'seguradora', 'outro') then
      v_motivo := 'Diga quem é o pagador para o cliente: empresa do cliente, cônjuge, parente, marina, seguradora ou outro.';
    end if;
    v_origem := nullif(btrim(coalesce(v_item ->> 'origem', '')), '');
    if v_motivo is null and v_origem is not null and v_origem not in ('historico', 'fila', 'assistente') then
      v_motivo := 'Origem desconhecida (use historico, fila ou assistente).';
    end if;
    v_obs := left(nullif(btrim(coalesce(v_item ->> 'observacao', '')), ''), 500);

    -- O cliente
    if v_motivo is null then
      select * into v_cliente from public.clients where id = (v_item ->> 'client_id')::uuid;
      if not found then
        v_motivo := 'Cliente não encontrado.';
      elsif not v_cliente.active then
        v_motivo := format('O cliente %s está inativo.', v_cliente.name);
      end if;
    end if;

    -- A linha do banco: o documento e o nome saem daqui
    if v_motivo is null then
      select * into t from public.bank_transactions where id = (v_item ->> 'bank_transaction_id')::uuid;
      if not found then
        v_motivo := 'Linha do extrato não encontrada.';
      elsif t.transaction_type <> 'credit' then
        v_motivo := 'Só uma entrada do banco mostra quem pagou por um cliente.';
      end if;
    end if;
    if v_motivo is null then
      v_doc := public._doc_normalizado(t.counterparty_document);
      if v_doc !~ '^([0-9]{11}|[0-9]{14})$' then
        v_motivo := 'O banco não informou o CPF/CNPJ de quem pagou nesta linha.';
      end if;
    end if;

    -- Quem pagou não pode ser o próprio cliente, a própria HBR nem outro cliente
    if v_motivo is null then
      if length(public._doc_normalizado(v_cliente.cpf_cnpj)) >= 11
         and not public._documento_contradiz(v_doc, v_cliente.cpf_cnpj) then
        v_motivo := format('Quem pagou é o próprio cliente %s (mesmo documento): não precisa guardar.', v_cliente.name);
      elsif length(v_doc) = 14 and left(v_doc, 8) = any (v_raizes) then
        v_motivo := 'É o CNPJ da própria HBR (dinheiro entre contas), não alguém pagando por um cliente.';
      end if;
    end if;
    if v_motivo is null then
      v_outro := null;
      select c.name into v_outro
        from public.clients c
       where c.id <> v_cliente.id and c.active
         and length(public._doc_normalizado(c.cpf_cnpj)) >= 11
         and not public._documento_contradiz(v_doc, c.cpf_cnpj)
       order by c.created_at
       limit 1;
      if v_outro is not null then
        v_motivo := format('Este CPF/CNPJ é do cliente %s: possível cadastro duplicado. Confira os dois cadastros antes de guardar.', v_outro);
      end if;
    end if;

    -- A prova: a linha paga uma conta deste cliente (as 3 ligações) ou está esperando na fila do Extrato
    if v_motivo is null then
      v_ligada := exists (
        select 1
          from public.receivables r
         where r.client_id = v_cliente.id
           and r.status <> 'cancelled'
           and (r.bank_transaction_id = t.id
                or exists (select 1 from public.payments p
                            where p.receivable_id = r.id
                              and p.status is distinct from 'cancelled'
                              and (p.bank_transaction_id = t.id or p.id = t.reconciled_payment_id))));
      v_na_fila := exists (
        select 1 from public.finance_review_queue q
         where q.bank_transaction_id = t.id and q.status = 'pending' and q.kind = 'create_receivable');
      if not v_ligada and not v_na_fila then
        v_motivo := format('Esta entrada não paga uma conta de %s nem está esperando na fila do Extrato.', v_cliente.name);
      end if;
    end if;

    if v_motivo is null then
      v_nome := coalesce(
        nullif(btrim(t.counterparty_name), ''),
        nullif(btrim(substring(coalesce(t.description, '')
          from '(?i)^(?:pix|ted|doc|transf\S*)\s+recebid[oa]\s+(?:de|por)\s+(.{3,})$')), ''),
        'Sem nome no extrato');

      -- O par já guardado: o mesmo documento ou, no CNPJ, a mesma raiz (matriz e filial são uma empresa só, como na
      -- lista para conferir e no motor).
      select * into v_atual from public.pagadores_do_cliente pc
       where pc.client_id = v_cliente.id
         and (pc.documento = v_doc or (length(pc.documento) = 14 and length(v_doc) = 14 and left(pc.documento, 8) = left(v_doc, 8)))
       order by (pc.documento = v_doc) desc, pc.proposto_em
       limit 1
       for update;
      v_existe := found;

      if v_existe and not v_admin then
        -- Só o administrador desfaz o que já foi decidido (o SIM do dono, a recusa, a pausa).
        if v_atual.situacao = 'recusado' then
          v_motivo := format('%s foi recusado como pagador de %s; só o administrador traz de volta.', v_atual.nome, v_cliente.name);
        elsif v_atual.situacao = 'pausado' then
          v_motivo := format('%s está pausado como pagador de %s; só o administrador reativa.', v_atual.nome, v_cliente.name);
        elsif v_atual.situacao = 'confirmado' then
          v_motivo := format('%s já é pagador confirmado de %s.', v_atual.nome, v_cliente.name);
        end if;
      end if;
    end if;

    if v_motivo is not null then
      v_recusados := v_recusados || jsonb_build_object(
        'indice', v_i,
        'client_id', v_item ->> 'client_id',
        'bank_transaction_id', v_item ->> 'bank_transaction_id',
        'motivo', v_motivo);
      continue;
    end if;

    v_situacao := case when v_admin then 'confirmado' else 'proposto' end;
    if v_existe then
      update public.pagadores_do_cliente
         set relacao = v_relacao,
             observacao = coalesce(v_obs, observacao),
             bank_transaction_id = coalesce(bank_transaction_id, t.id),
             situacao = v_situacao,
             -- quem confirmou e quando: o primeiro SIM vale ("guardado por você em dd/mm")
             confirmado_por = case when v_admin and situacao <> 'confirmado' then v_autor else confirmado_por end,
             confirmado_em = case when v_admin and situacao <> 'confirmado' then now() else confirmado_em end,
             decidido_motivo = case when v_admin then null else decidido_motivo end
       where id = v_atual.id
      returning id into v_id;
    else
      insert into public.pagadores_do_cliente (
        client_id, documento, nome, relacao, situacao, observacao, origem, bank_transaction_id,
        proposto_por, proposto_em, confirmado_por, confirmado_em)
      values (
        v_cliente.id, v_doc, v_nome, v_relacao, v_situacao, v_obs,
        coalesce(v_origem, case when v_ligada then 'historico' else 'fila' end), t.id,
        v_autor, now(), case when v_admin then v_autor end, case when v_admin then now() end)
      on conflict on constraint pagadores_do_cliente_um_por_cliente do nothing
      returning id into v_id;
      if v_id is null then
        v_recusados := v_recusados || jsonb_build_object(
          'indice', v_i, 'client_id', v_cliente.id, 'bank_transaction_id', t.id,
          'motivo', 'Outra pessoa acabou de guardar este pagador. Atualize a tela.');
        continue;
      end if;
    end if;

    v_regras := '{}';
    if v_situacao = 'confirmado' then
      v_regras := public._pagador_consolidar_regras(v_cliente.id, v_doc);
      v_todas_regras := v_todas_regras || v_regras;
    end if;

    -- Regra antiga do mesmo documento apontando OUTRO cliente: fica como está (é o vínculo com ele), e o dono é avisado
    -- de que as entradas deste pagador passam a perguntar de quem é.
    v_conflito := public._pagador_regra_de_outro_cliente(v_cliente.id, v_doc);
    if v_conflito is not null then
      v_avisos := v_avisos || to_jsonb(case when v_situacao = 'confirmado'
        then format('Atenção: uma regra antiga diz que este CPF/CNPJ é do cliente %s; as entradas de %s passam a perguntar de quem é (escolha o cliente em cada uma).',
                    v_conflito ->> 'cliente', v_nome)
        else format('Atenção: uma regra antiga diz que este CPF/CNPJ é do cliente %s; quando o administrador confirmar, as entradas de %s passam a perguntar de quem é.',
                    v_conflito ->> 'cliente', v_nome)
        end);
    end if;

    insert into public.reconciliation_log (acao, autor, bank_transaction_id, finance_rule_id, detalhe, antes, depois)
    values (
      'guardou_pagador_do_cliente', v_autor, t.id, coalesce(v_regras[1], (v_conflito ->> 'finance_rule_id')::uuid),
      left(format('%s guardado como pagador de %s (%s, %s)', v_nome, v_cliente.name, v_relacao, v_situacao), 300),
      case when v_existe then jsonb_build_object('situacao', v_atual.situacao, 'relacao', v_atual.relacao) end,
      jsonb_build_object('pagador_id', v_id, 'client_id', v_cliente.id, 'situacao', v_situacao, 'relacao', v_relacao,
                         'origem', coalesce(v_origem, case when v_ligada then 'historico' else 'fila' end),
                         'regras_consolidadas', to_jsonb(v_regras),
                         'regra_em_conflito', v_conflito));

    v_gravados := v_gravados || jsonb_build_object(
      'id', v_id, 'client_id', v_cliente.id, 'cliente', v_cliente.name, 'nome', v_nome,
      'relacao', v_relacao, 'situacao', v_situacao, 'ja_existia', v_existe,
      'situacao_anterior', case when v_existe then v_atual.situacao end,
      'regras_consolidadas', to_jsonb(v_regras), 'regra_de_outro_cliente', v_conflito);
  end loop;

  v_n := jsonb_array_length(v_gravados);
  v_nr := jsonb_array_length(v_recusados);
  v_msg := case
    when v_n = 0 then 'Nenhum pagador guardado.'
    when v_admin and v_n = 1 then '1 pagador guardado e confirmado.'
    when v_admin then format('%s pagadores guardados e confirmados.', v_n)
    when v_n = 1 then '1 pagador proposto: falta o SIM do administrador.'
    else format('%s pagadores propostos: falta o SIM do administrador.', v_n)
  end
  || case when v_nr = 1 then ' 1 não foi guardado: ' || (v_recusados -> 0 ->> 'motivo')
          when v_nr > 1 then format(' %s não foram guardados (veja o motivo de cada um).', v_nr)
          else '' end
  || case when cardinality(v_todas_regras) = 1 then ' A regra de entrada deste documento deixou de apontar o cliente (continua valendo para a categoria).'
          when cardinality(v_todas_regras) > 1 then format(' %s regras de entrada deixaram de apontar o cliente (continuam valendo para a categoria).', cardinality(v_todas_regras))
          else '' end
  || case when jsonb_array_length(v_avisos) = 1 then ' ' || (v_avisos ->> 0)
          when jsonb_array_length(v_avisos) > 1 then format(' Atenção: %s regras antigas dizem que estes documentos são de outro cliente (veja os avisos).', jsonb_array_length(v_avisos))
          else '' end;

  return jsonb_build_object(
    'ok', v_n > 0,
    'gravados', v_gravados,
    'recusados', v_recusados,
    'regras_consolidadas', to_jsonb(v_todas_regras),
    'avisos', v_avisos,
    'message', v_msg);
end;
$$;

comment on function public.guardar_pagadores_do_cliente(jsonb, uuid) is
  'Guarda quem paga por um cliente a partir de linhas do banco. Admin grava confirmado (o SIM do dono); financeiro, proposto. '
  'Avisa (avisos) quando uma regra antiga de entrada do mesmo documento aponta outro cliente.';

-- ---------------------------------------------------------------------------------------------
-- 5. decidir_pagador_do_cliente
-- ---------------------------------------------------------------------------------------------
-- confirmar/reativar: só o administrador (é o SIM do dono). recusar/pausar: o administrador, ou o financeiro quando o
-- pagador ainda está PROPOSTO — o que o dono já decidiu (confirmado, pausado) só o dono desfaz, como no guardar e no
-- recusar_pagadores_do_cliente (decisão do dono, 23/10/2026: "pelo recomendado").
-- p_relacao (opcional, só no 'confirmar'): o administrador troca a relação que o financeiro propôs ao dar o SIM
-- (decisão do dono, 23/10/2026).
-- O parâmetro novo muda a assinatura: a de 4 argumentos sai antes (com as duas, a chamada por nome ficaria ambígua).
drop function if exists public.decidir_pagador_do_cliente(uuid, text, text, uuid);
create or replace function public.decidir_pagador_do_cliente(
  p_id uuid,
  p_decisao text,
  p_motivo text default null,
  p_autor uuid default null,
  p_relacao text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_admin boolean;
  v public.pagadores_do_cliente%rowtype;
  v_cliente public.clients%rowtype;
  v_decisao text := lower(btrim(coalesce(p_decisao, '')));
  v_motivo text := left(nullif(btrim(coalesce(p_motivo, '')), ''), 500);
  v_relacao text := nullif(btrim(coalesce(p_relacao, '')), '');
  v_relacao_final text;
  v_para text;
  v_outro text;
  v_regras uuid[] := '{}';
  v_conflito jsonb;
  v_msg text;
  v_rotulo text;
begin
  if v_autor is null then
    raise exception 'Diga quem está decidindo: entre no sistema (ou o assistente informa o autor).' using errcode = '42501';
  end if;
  if v_decisao not in ('confirmar', 'reativar', 'recusar', 'pausar') then
    raise exception 'Decisão desconhecida: use confirmar, reativar, recusar ou pausar.';
  end if;
  v_admin := public.is_admin(v_autor);
  if v_decisao in ('confirmar', 'reativar') and not v_admin then
    raise exception 'Só o administrador confirma ou reativa quem paga por um cliente (é o SIM do dono).' using errcode = '42501';
  end if;
  if v_relacao is not null then
    if v_decisao <> 'confirmar' then
      raise exception 'A relação só muda ao confirmar um pagador proposto.';
    end if;
    if v_relacao not in ('empresa_do_cliente', 'conjuge', 'parente', 'marina', 'seguradora', 'outro') then
      raise exception 'Relação desconhecida: use empresa do cliente, cônjuge, parente, marina, seguradora ou outro.';
    end if;
  end if;

  select * into v from public.pagadores_do_cliente where id = p_id for update;
  if not found then
    raise exception 'Pagador não encontrado.';
  end if;
  select * into v_cliente from public.clients where id = v.client_id;
  v_rotulo := case v.situacao when 'proposto' then 'proposto' when 'confirmado' then 'confirmado'
                              when 'recusado' then 'recusado' else 'pausado' end;

  if v_decisao = 'confirmar' and v.situacao <> 'proposto' then
    raise exception 'Só um pagador proposto é confirmado; este está %.', v_rotulo;
  elsif v_decisao = 'reativar' and v.situacao not in ('pausado', 'recusado') then
    raise exception 'Só um pagador pausado ou recusado é reativado; este está %.', v_rotulo;
  elsif v_decisao = 'pausar' and v.situacao not in ('proposto', 'confirmado') then
    raise exception 'Este pagador já está %.', v_rotulo;
  elsif v_decisao = 'recusar' and v.situacao = 'recusado' then
    raise exception 'Este pagador já está recusado.';
  end if;

  -- O financeiro recusa ou pausa só o proposto: o confirmado é o SIM do dono, e o pausado só o dono reativa.
  if v_decisao in ('recusar', 'pausar') and v.situacao <> 'proposto' and not v_admin then
    if v.situacao = 'confirmado' then
      raise exception '% é pagador confirmado de %: só o administrador recusa ou pausa (é o SIM do dono).', v.nome, v_cliente.name
        using errcode = '42501';
    end if;
    raise exception '% está % como pagador de %: só o administrador muda (o financeiro recusa ou pausa só o proposto).',
      v.nome, v_rotulo, v_cliente.name using errcode = '42501';
  end if;

  v_para := case v_decisao when 'confirmar' then 'confirmado' when 'reativar' then 'confirmado'
                           when 'recusar' then 'recusado' else 'pausado' end;
  v_relacao_final := case when v_decisao = 'confirmar' then coalesce(v_relacao, v.relacao) else v.relacao end;

  if v_para = 'confirmado' then
    if not coalesce(v_cliente.active, false) then
      raise exception 'O cliente % está inativo: reative o cliente antes.', v_cliente.name;
    end if;
    -- O cadastro pode ter mudado desde que o pagador foi proposto.
    if length(public._doc_normalizado(v_cliente.cpf_cnpj)) >= 11
       and not public._documento_contradiz(v.documento, v_cliente.cpf_cnpj) then
      raise exception 'Este documento agora é o do próprio cliente %: não é mais preciso guardar o pagador.', v_cliente.name;
    end if;
    select c.name into v_outro
      from public.clients c
     where c.id <> v.client_id and c.active
       and length(public._doc_normalizado(c.cpf_cnpj)) >= 11
       and not public._documento_contradiz(v.documento, c.cpf_cnpj)
     order by c.created_at
     limit 1;
    if v_outro is not null then
      raise exception 'Este CPF/CNPJ é do cliente %: possível cadastro duplicado. Confira os dois cadastros antes.', v_outro;
    end if;
  end if;

  update public.pagadores_do_cliente
     set situacao = v_para,
         relacao = v_relacao_final,
         confirmado_por = case when v_para = 'confirmado' then v_autor else confirmado_por end,
         confirmado_em = case when v_para = 'confirmado' then now() else confirmado_em end,
         decidido_motivo = case when v_para = 'confirmado' then null else coalesce(v_motivo, decidido_motivo) end
   where id = v.id;

  if v_para = 'confirmado' then
    v_regras := public._pagador_consolidar_regras(v.client_id, v.documento);
    -- Regra antiga do mesmo documento apontando OUTRO cliente: fica (é o vínculo com ele), e o dono é avisado.
    v_conflito := public._pagador_regra_de_outro_cliente(v.client_id, v.documento);
  end if;

  -- recusar e pausar: o motor da fila lê o recusado e o pausado como VETO daquele cliente para aquele documento
  -- (nem pagador conhecido, nem histórico, nem nome idêntico o sugerem — finance-review/identificacao.ts).
  v_msg := case v_decisao
    when 'confirmar' then format('%s confirmado como pagador de %s', v.nome, v_cliente.name)
      || case when v_relacao_final is distinct from v.relacao
              then format(' (relação trocada para %s).',
                          case v_relacao_final when 'empresa_do_cliente' then 'empresa do cliente' when 'conjuge' then 'cônjuge'
                                               else v_relacao_final end)
              else '.' end
    when 'reativar' then format('%s voltou a ser pagador de %s.', v.nome, v_cliente.name)
    when 'recusar' then format('%s recusado como pagador de %s: não volta a ser sugerido.', v.nome, v_cliente.name)
    else format('%s pausado como pagador de %s: deixa de ser sugerido até o administrador reativar.', v.nome, v_cliente.name)
  end
  || case when cardinality(v_regras) > 0
          then ' A regra de entrada deste documento deixou de apontar o cliente (continua valendo para a categoria).'
          else '' end
  || case when v_conflito is not null
          then format(' Atenção: uma regra antiga diz que este CPF/CNPJ é do cliente %s; as entradas de %s passam a perguntar de quem é (escolha o cliente em cada uma).',
                      v_conflito ->> 'cliente', v.nome)
          else '' end;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, finance_rule_id, detalhe, antes, depois)
  values (
    'decidiu_pagador_do_cliente', v_autor, v.bank_transaction_id, coalesce(v_regras[1], (v_conflito ->> 'finance_rule_id')::uuid),
    left(coalesce(v_motivo || ' · ', '') || v_msg, 300),
    jsonb_build_object('situacao', v.situacao, 'relacao', v.relacao),
    jsonb_build_object('pagador_id', v.id, 'client_id', v.client_id, 'decisao', v_decisao, 'situacao', v_para,
                       'relacao', v_relacao_final,
                       'regras_consolidadas', to_jsonb(v_regras), 'regra_em_conflito', v_conflito));

  return jsonb_build_object('ok', true, 'id', v.id, 'situacao', v_para, 'relacao', v_relacao_final,
                            'regras_consolidadas', to_jsonb(v_regras),
                            'regra_de_outro_cliente', v_conflito, 'message', v_msg);
end;
$$;

comment on function public.decidir_pagador_do_cliente(uuid, text, text, uuid, text) is
  'confirmar/reativar (só administrador; ao confirmar, p_relacao troca a relação proposta) ou recusar/pausar '
  '(administrador; o financeiro só o proposto) um pagador do cliente.';

-- ---------------------------------------------------------------------------------------------
-- 6. recusar_pagadores_do_cliente — "não é pagador habitual", a partir da linha do banco
-- ---------------------------------------------------------------------------------------------
-- Para o par que ainda NÃO está na tabela (a lista para conferir, a fila do Extrato): decidir_pagador_do_cliente
-- só age sobre quem já foi guardado, e guardar grava proposto/confirmado (no admin, ainda consolida a regra).
-- p_itens: [{client_id, bank_transaction_id, relacao?, origem?}], de 1 a 50. O documento e o nome saem da linha do
-- banco, como no guardar. Aceita o documento de OUTRO cliente (o possível cadastro duplicado também precisa sair da
-- lista). Nunca mexe em regra. O financeiro não desfaz o que o administrador decidiu (o confirmado é o SIM do dono; o
-- pausado só o dono reativa) — a mesma trava do decidir_pagador_do_cliente.
-- Mesmo formato de retorno de guardar: {ok, gravados, recusados, regras_consolidadas (sempre vazio), avisos, message}.
create or replace function public.recusar_pagadores_do_cliente(
  p_itens jsonb,
  p_motivo text default null,
  p_autor uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_admin boolean;
  v_raizes text[] := public._raizes_do_cnpj_da_hbr();
  v_motivo_da_recusa text := left(coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), 'Não é pagador habitual'), 500);
  v_item jsonb;
  v_i integer := 0;
  v_cliente public.clients%rowtype;
  t public.bank_transactions%rowtype;
  v_atual public.pagadores_do_cliente%rowtype;
  v_existe boolean;
  v_doc text;
  v_nome text;
  v_relacao text;
  v_origem text;
  v_ligada boolean;
  v_na_fila boolean;
  v_motivo text;
  v_id uuid;
  v_gravados jsonb := '[]'::jsonb;
  v_recusados jsonb := '[]'::jsonb;
  v_n integer;
  v_nr integer;
  v_msg text;
begin
  if v_autor is null then
    raise exception 'Diga quem está recusando: entre no sistema (ou o assistente informa o autor).' using errcode = '42501';
  end if;
  if not public.is_admin_or_financial(v_autor) then
    raise exception 'Só administrador ou financeiro recusa quem paga por um cliente.' using errcode = '42501';
  end if;
  v_admin := public.is_admin(v_autor);

  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Escolha ao menos um pagador para recusar.';
  end if;
  if jsonb_array_length(p_itens) > 50 then
    raise exception 'No máximo 50 pagadores de uma vez (vieram %).', jsonb_array_length(p_itens);
  end if;

  for v_item in select e.value from jsonb_array_elements(p_itens) e loop
    v_i := v_i + 1;
    v_motivo := null;
    v_existe := false;
    v_ligada := false;
    v_na_fila := false;

    -- O pedido (a relação não importa para recusar: a coluna é obrigatória, então 'outro' quando não vem)
    if jsonb_typeof(v_item) <> 'object'
       or coalesce(v_item ->> 'client_id', '') !~ c_uuid
       or coalesce(v_item ->> 'bank_transaction_id', '') !~ c_uuid then
      v_motivo := 'Falta o cliente ou a linha do extrato.';
    end if;
    v_relacao := btrim(coalesce(v_item ->> 'relacao', ''));
    if v_relacao not in ('empresa_do_cliente', 'conjuge', 'parente', 'marina', 'seguradora', 'outro') then
      v_relacao := 'outro';
    end if;
    v_origem := nullif(btrim(coalesce(v_item ->> 'origem', '')), '');
    if v_origem is not null and v_origem not in ('historico', 'fila', 'assistente') then
      v_origem := null;
    end if;

    -- O cliente (inativo também: recusar não sugere nada)
    if v_motivo is null then
      select * into v_cliente from public.clients where id = (v_item ->> 'client_id')::uuid;
      if not found then
        v_motivo := 'Cliente não encontrado.';
      end if;
    end if;

    -- A linha do banco: o documento e o nome saem daqui
    if v_motivo is null then
      select * into t from public.bank_transactions where id = (v_item ->> 'bank_transaction_id')::uuid;
      if not found then
        v_motivo := 'Linha do extrato não encontrada.';
      elsif t.transaction_type <> 'credit' then
        v_motivo := 'Só uma entrada do banco mostra quem pagou por um cliente.';
      end if;
    end if;
    if v_motivo is null then
      v_doc := public._doc_normalizado(t.counterparty_document);
      if v_doc !~ '^([0-9]{11}|[0-9]{14})$' then
        v_motivo := 'O banco não informou o CPF/CNPJ de quem pagou nesta linha.';
      end if;
    end if;

    -- O próprio cliente e a própria HBR não são "pagador": não há o que recusar. Documento de OUTRO cliente é aceito.
    if v_motivo is null then
      if length(public._doc_normalizado(v_cliente.cpf_cnpj)) >= 11
         and not public._documento_contradiz(v_doc, v_cliente.cpf_cnpj) then
        v_motivo := format('Quem pagou é o próprio cliente %s (mesmo documento): não há pagador para recusar.', v_cliente.name);
      elsif length(v_doc) = 14 and left(v_doc, 8) = any (v_raizes) then
        v_motivo := 'É o CNPJ da própria HBR (dinheiro entre contas), não alguém pagando por um cliente.';
      end if;
    end if;

    -- A prova, como no guardar: a linha paga uma conta deste cliente (as 3 ligações) ou espera na fila do Extrato
    if v_motivo is null then
      v_ligada := exists (
        select 1
          from public.receivables r
         where r.client_id = v_cliente.id
           and r.status <> 'cancelled'
           and (r.bank_transaction_id = t.id
                or exists (select 1 from public.payments p
                            where p.receivable_id = r.id
                              and p.status is distinct from 'cancelled'
                              and (p.bank_transaction_id = t.id or p.id = t.reconciled_payment_id))));
      v_na_fila := exists (
        select 1 from public.finance_review_queue q
         where q.bank_transaction_id = t.id and q.status = 'pending' and q.kind = 'create_receivable');
      if not v_ligada and not v_na_fila then
        v_motivo := format('Esta entrada não paga uma conta de %s nem está esperando na fila do Extrato.', v_cliente.name);
      end if;
    end if;

    if v_motivo is null then
      v_nome := coalesce(
        nullif(btrim(t.counterparty_name), ''),
        nullif(btrim(substring(coalesce(t.description, '')
          from '(?i)^(?:pix|ted|doc|transf\S*)\s+recebid[oa]\s+(?:de|por)\s+(.{3,})$')), ''),
        'Sem nome no extrato');

      select * into v_atual from public.pagadores_do_cliente pc
       where pc.client_id = v_cliente.id
         and (pc.documento = v_doc or (length(pc.documento) = 14 and length(v_doc) = 14 and left(pc.documento, 8) = left(v_doc, 8)))
       order by (pc.documento = v_doc) desc, pc.proposto_em
       limit 1
       for update;
      v_existe := found;

      if v_existe and v_atual.situacao = 'confirmado' and not v_admin then
        v_motivo := format('%s é pagador confirmado de %s; só o administrador recusa.', v_atual.nome, v_cliente.name);
      elsif v_existe and v_atual.situacao = 'pausado' and not v_admin then
        v_motivo := format('%s está pausado como pagador de %s; só o administrador muda.', v_atual.nome, v_cliente.name);
      end if;
    end if;

    if v_motivo is not null then
      v_recusados := v_recusados || jsonb_build_object(
        'indice', v_i,
        'client_id', v_item ->> 'client_id',
        'bank_transaction_id', v_item ->> 'bank_transaction_id',
        'motivo', v_motivo);
      continue;
    end if;

    -- Já recusado: nada muda (nem a trilha) — o pedido repetido não é erro.
    if v_existe and v_atual.situacao = 'recusado' then
      v_gravados := v_gravados || jsonb_build_object(
        'id', v_atual.id, 'client_id', v_cliente.id, 'cliente', v_cliente.name, 'nome', v_atual.nome,
        'relacao', v_atual.relacao, 'situacao', 'recusado', 'ja_existia', true, 'situacao_anterior', 'recusado',
        'regras_consolidadas', '[]'::jsonb);
      continue;
    end if;

    if v_existe then
      update public.pagadores_do_cliente
         set situacao = 'recusado',
             decidido_motivo = v_motivo_da_recusa
       where id = v_atual.id
      returning id into v_id;
    else
      insert into public.pagadores_do_cliente (
        client_id, documento, nome, relacao, situacao, origem, bank_transaction_id,
        proposto_por, proposto_em, decidido_motivo)
      values (
        v_cliente.id, v_doc, v_nome, v_relacao, 'recusado',
        coalesce(v_origem, case when v_ligada then 'historico' else 'fila' end), t.id,
        v_autor, now(), v_motivo_da_recusa)
      on conflict on constraint pagadores_do_cliente_um_por_cliente do nothing
      returning id into v_id;
      if v_id is null then
        v_recusados := v_recusados || jsonb_build_object(
          'indice', v_i, 'client_id', v_cliente.id, 'bank_transaction_id', t.id,
          'motivo', 'Outra pessoa acabou de guardar este pagador. Atualize a tela.');
        continue;
      end if;
    end if;

    insert into public.reconciliation_log (acao, autor, bank_transaction_id, detalhe, antes, depois)
    values (
      'recusou_pagador_do_cliente', v_autor, t.id,
      left(format('%s recusado como pagador de %s: %s', coalesce(v_atual.nome, v_nome), v_cliente.name, v_motivo_da_recusa), 300),
      case when v_existe then jsonb_build_object('situacao', v_atual.situacao, 'relacao', v_atual.relacao) end,
      jsonb_build_object('pagador_id', v_id, 'client_id', v_cliente.id, 'situacao', 'recusado',
                         'motivo', v_motivo_da_recusa,
                         'origem', case when v_existe then v_atual.origem
                                        else coalesce(v_origem, case when v_ligada then 'historico' else 'fila' end) end));

    v_gravados := v_gravados || jsonb_build_object(
      'id', v_id, 'client_id', v_cliente.id, 'cliente', v_cliente.name,
      'nome', case when v_existe then v_atual.nome else v_nome end,
      'relacao', case when v_existe then v_atual.relacao else v_relacao end,
      'situacao', 'recusado', 'ja_existia', v_existe,
      'situacao_anterior', case when v_existe then v_atual.situacao end,
      'regras_consolidadas', '[]'::jsonb);
  end loop;

  v_n := jsonb_array_length(v_gravados);
  v_nr := jsonb_array_length(v_recusados);
  v_msg := case
    when v_n = 0 then 'Nenhum pagador recusado.'
    when v_n = 1 then '1 pagador recusado: não volta a ser sugerido nem à lista para conferir.'
    else format('%s pagadores recusados: não voltam a ser sugeridos nem à lista para conferir.', v_n)
  end
  || case when v_nr = 1 then ' 1 não foi recusado: ' || (v_recusados -> 0 ->> 'motivo')
          when v_nr > 1 then format(' %s não foram recusados (veja o motivo de cada um).', v_nr)
          else '' end;

  return jsonb_build_object(
    'ok', v_n > 0,
    'gravados', v_gravados,
    'recusados', v_recusados,
    'regras_consolidadas', '[]'::jsonb,
    'avisos', '[]'::jsonb,
    'message', v_msg);
end;
$$;

comment on function public.recusar_pagadores_do_cliente(jsonb, text, uuid) is
  '"Não é pagador habitual": grava o par cliente × quem pagou (da linha do banco) como recusado. Admin ou financeiro; '
  'o financeiro não desfaz um confirmado nem um pausado. Nunca mexe em regra.';

-- ---------------------------------------------------------------------------------------------
-- 7. pagadores_para_conferir — a lista histórica para o dono conferir
-- ---------------------------------------------------------------------------------------------
-- Uma linha por par (cliente ativo, documento de quem pagou; CNPJ pela raiz) das 3 ligações extrato ↔ conta a
-- receber: payments.bank_transaction_id, bank_transactions.reconciled_payment_id e receivables.bank_transaction_id.
-- Fica de fora: par já decidido na tabela (confirmado, recusado ou pausado: recusado não volta), documento do próprio
-- cliente e o CNPJ da HBR. O par PROPOSTO pelo financeiro continua, com pagador_id/situacao/relacao_proposta/quem e
-- quando propôs: é onde o administrador dá o SIM (sem isto o trabalho do financeiro sumia de todas as listas).
-- O proposto que NÃO sai das ligações (guardado pela fila do Extrato ou pelo assistente enquanto a linha esperava — e
-- que continua esperando, foi aprovada para outro cliente, recusada ou ignorada) entra por um union all, montado da
-- própria tabela: vezes 1, a linha que ele guardou (total e data), o mesmo grupo e os mesmos avisos (sem
-- ligacao_duvidosa, que é das ligações). Cliente ativo, sem o documento do próprio cliente nem o CNPJ da HBR.
-- aviso (o item sai do lote e é decidido um a um), na ordem de prioridade:
--   documento_de_outro_cliente — o documento é de outro cliente ativo (possível cadastro duplicado);
--   ligacao_duvidosa           — a ÚNICA ligação do par é bank_transactions.reconciled_payment_id, e esse pagamento
--                                já tem OUTRA linha do banco (a MUNDO DOCE COLOMBO 9d5f1352 → pagamento eb43573b, que é
--                                da linha cfc6043d): provavelmente a conciliação errada, não um pagador;
--   pagou_para_varios_clientes — o mesmo documento (CNPJ pela raiz) aparece em mais de um cliente (nas ligações ou num
--                                proposto).
-- "Nome idêntico" é conferido na tela, com o normalizeText do motor (uma normalização só).
-- security invoker: a RLS de quem chama vale (bank_transactions e a tabela nova só para admin e financeiro; o nome
-- de quem propôs só sai para o administrador ou para o próprio autor — RLS de app_users).
-- drop antes: o returns table mudou (create or replace não troca o tipo de retorno); os grants voltam na seção 9.
drop function if exists public.pagadores_para_conferir();
create function public.pagadores_para_conferir()
returns table (
  client_id uuid,
  cliente_nome text,
  cliente_tem_documento boolean,
  pagador_documento text,
  pagador_nome text,
  tipo_documento text,
  vezes integer,
  total numeric,
  primeira date,
  ultima date,
  bank_transaction_ids uuid[],
  grupo text,
  aviso text,
  pagador_id uuid,
  situacao text,
  relacao_proposta text,
  proposto_por_nome text,
  proposto_em timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  with ligacoes as (
    -- duvidosa: só a conciliação liga a linha à conta, e o pagamento já tem OUTRA linha do banco
    select r.client_id, r.bank_transaction_id as bt_id, false as duvidosa
      from public.receivables r
     where r.bank_transaction_id is not null and r.status <> 'cancelled'
    union all
    select r.client_id, p.bank_transaction_id, false
      from public.payments p
      join public.receivables r on r.id = p.receivable_id
     where p.bank_transaction_id is not null and p.status is distinct from 'cancelled' and r.status <> 'cancelled'
    union all
    select r.client_id, b.id,
           coalesce(p.bank_transaction_id <> b.id, false)
           or exists (select 1 from public.bank_transactions b2 where b2.reconciled_payment_id = p.id and b2.id <> b.id)
      from public.bank_transactions b
      join public.payments p on p.id = b.reconciled_payment_id
      join public.receivables r on r.id = p.receivable_id
     where p.status is distinct from 'cancelled' and r.status <> 'cancelled'
  ),
  -- uma linha por (cliente, linha do banco): duvidosa só quando TODA ligação dela é duvidosa
  linhas as (
    select l.client_id, l.bt_id, bool_and(l.duvidosa) as duvidosa
      from ligacoes l
     group by l.client_id, l.bt_id
  ),
  hbr as (
    select array_remove(array[
      (select case when length(public._doc_normalizado(s.value)) = 14 then left(public._doc_normalizado(s.value), 8) end
         from public.app_settings s where s.key = 'cnpj'),
      public.raiz_do_cnpj_da_empresa()
    ], null) as raizes
  ),
  de_terceiro as (
    select l.client_id,
           c.name as cliente_nome,
           length(public._doc_normalizado(c.cpf_cnpj)) >= 11 as cliente_tem_documento,
           b.id as bt_id,
           public._doc_normalizado(b.counterparty_document) as doc,
           nullif(btrim(b.counterparty_name), '') as nome,
           b.amount,
           b.transaction_date,
           l.duvidosa,
           case when length(public._doc_normalizado(b.counterparty_document)) = 14
                then 'raiz:' || left(public._doc_normalizado(b.counterparty_document), 8)
                else public._doc_normalizado(b.counterparty_document) end as chave
      from linhas l
      join public.bank_transactions b on b.id = l.bt_id
      join public.clients c on c.id = l.client_id and c.active
     cross join hbr
     where b.transaction_type = 'credit'
       and public._doc_normalizado(b.counterparty_document) ~ '^([0-9]{11}|[0-9]{14})$'
       -- o próprio cliente (CNPJ pela raiz)
       and not (length(public._doc_normalizado(c.cpf_cnpj)) >= 11
                and not public._documento_contradiz(b.counterparty_document, c.cpf_cnpj))
       -- dinheiro da própria HBR
       and not (length(public._doc_normalizado(b.counterparty_document)) = 14
                and left(public._doc_normalizado(b.counterparty_document), 8) = any (hbr.raizes))
  ),
  pares as (
    select d.client_id,
           d.chave,
           min(d.cliente_nome) as cliente_nome,
           bool_or(d.cliente_tem_documento) as cliente_tem_documento,
           (array_agg(d.doc order by d.transaction_date desc, d.bt_id))[1] as doc,
           (array_agg(d.nome order by d.transaction_date desc, d.bt_id) filter (where d.nome is not null))[1] as nome,
           count(distinct d.bt_id)::integer as vezes,
           sum(d.amount) as total,
           min(d.transaction_date) as primeira,
           max(d.transaction_date) as ultima,
           array_agg(distinct d.bt_id) as bank_transaction_ids,
           -- a única ligação do par é duvidosa (toda linha dele só se liga pela conciliação torta)
           bool_and(d.duvidosa) as duvidosa
      from de_terceiro d
     group by d.client_id, d.chave
  ),
  -- O PROPOSTO que não casa com nenhum par das ligações (mesmo cliente e mesmo documento; CNPJ pela raiz): veio da fila
  -- do Extrato ou do assistente. Cliente ativo; o documento do próprio cliente e o CNPJ da HBR ficam de fora, como nos
  -- pares. A linha do banco é a que ele guardou (pode ter sido apagada: aí sem linha, valor zero e a data da proposta).
  soltos as (
    select pc.id as pagador_id,
           pc.client_id,
           c.name as cliente_nome,
           length(public._doc_normalizado(c.cpf_cnpj)) >= 11 as cliente_tem_documento,
           pc.documento as doc,
           pc.nome,
           pc.relacao,
           pc.proposto_por,
           pc.proposto_em,
           pc.bank_transaction_id,
           b.amount,
           b.transaction_date,
           case when length(pc.documento) = 14 then 'raiz:' || left(pc.documento, 8) else pc.documento end as chave
      from public.pagadores_do_cliente pc
      join public.clients c on c.id = pc.client_id
      left join public.bank_transactions b on b.id = pc.bank_transaction_id
     cross join hbr
     where pc.situacao = 'proposto'
       and c.active
       and not (length(public._doc_normalizado(c.cpf_cnpj)) >= 11
                and not public._documento_contradiz(pc.documento, c.cpf_cnpj))
       and not (length(pc.documento) = 14 and left(pc.documento, 8) = any (hbr.raizes))
       and not exists (
         select 1 from pares p
          where p.client_id = pc.client_id
            and p.chave = case when length(pc.documento) = 14 then 'raiz:' || left(pc.documento, 8) else pc.documento end)
  ),
  -- quantos clientes cada documento (CNPJ pela raiz) já pagou: nas ligações e nos propostos soltos
  clientes_por_chave as (
    select x.chave, count(distinct x.client_id) as clientes
      from (select d.chave, d.client_id from de_terceiro d
            union all
            select s.chave, s.client_id from soltos s) x
     group by x.chave
  ),
  da_lista as (
    select p.client_id,
           p.cliente_nome,
           p.cliente_tem_documento,
           p.doc as pagador_documento,
           p.nome as pagador_nome,
           case when length(p.doc) = 14 then 'CNPJ' else 'CPF' end as tipo_documento,
           p.vezes,
           p.total,
           p.primeira,
           p.ultima,
           p.bank_transaction_ids,
           case when p.cliente_tem_documento then 'documento_diferente' else 'cliente_sem_documento' end as grupo,
           case
             when exists (select 1 from public.clients c2
                           where c2.id <> p.client_id and c2.active
                             and length(public._doc_normalizado(c2.cpf_cnpj)) >= 11
                             and not public._documento_contradiz(p.doc, c2.cpf_cnpj))
               then 'documento_de_outro_cliente'
             when p.duvidosa then 'ligacao_duvidosa'
             when k.clientes > 1 then 'pagou_para_varios_clientes'
           end as aviso,
           prop.id as pagador_id,
           case when prop.id is not null then 'proposto' end as situacao,
           prop.relacao as relacao_proposta,
           u.full_name as proposto_por_nome,
           prop.proposto_em
      from pares p
      join clientes_por_chave k on k.chave = p.chave
      -- o proposto do mesmo par (mesmo documento ou, no CNPJ, a mesma raiz), esperando o SIM do administrador
      left join lateral (
        select pc.id, pc.relacao, pc.proposto_por, pc.proposto_em
          from public.pagadores_do_cliente pc
         where pc.client_id = p.client_id
           and pc.situacao = 'proposto'
           and (pc.documento = p.doc
                or (length(pc.documento) = 14 and length(p.doc) = 14 and left(pc.documento, 8) = left(p.doc, 8)))
         order by (pc.documento = p.doc) desc, pc.proposto_em
         limit 1
      ) prop on true
      left join public.app_users u on u.id = prop.proposto_por
     where not exists (
       select 1 from public.pagadores_do_cliente pc
        where pc.client_id = p.client_id
          and pc.situacao in ('confirmado', 'recusado', 'pausado')
          and (pc.documento = p.doc
               or (length(pc.documento) = 14 and length(p.doc) = 14 and left(pc.documento, 8) = left(p.doc, 8))))
    union all
    select s.client_id,
           s.cliente_nome,
           s.cliente_tem_documento,
           s.doc,
           s.nome,
           case when length(s.doc) = 14 then 'CNPJ' else 'CPF' end,
           1,
           coalesce(s.amount, 0),
           coalesce(s.transaction_date, s.proposto_em::date),
           coalesce(s.transaction_date, s.proposto_em::date),
           case when s.bank_transaction_id is null then '{}'::uuid[] else array[s.bank_transaction_id] end,
           case when s.cliente_tem_documento then 'documento_diferente' else 'cliente_sem_documento' end,
           case
             when exists (select 1 from public.clients c2
                           where c2.id <> s.client_id and c2.active
                             and length(public._doc_normalizado(c2.cpf_cnpj)) >= 11
                             and not public._documento_contradiz(s.doc, c2.cpf_cnpj))
               then 'documento_de_outro_cliente'
             when k.clientes > 1 then 'pagou_para_varios_clientes'
           end,
           s.pagador_id,
           'proposto',
           s.relacao,
           u.full_name,
           s.proposto_em
      from soltos s
      join clientes_por_chave k on k.chave = s.chave
      left join public.app_users u on u.id = s.proposto_por
  )
  select l.client_id, l.cliente_nome, l.cliente_tem_documento, l.pagador_documento, l.pagador_nome, l.tipo_documento,
         l.vezes, l.total, l.primeira, l.ultima, l.bank_transaction_ids, l.grupo, l.aviso, l.pagador_id, l.situacao,
         l.relacao_proposta, l.proposto_por_nome, l.proposto_em
    from da_lista l
   order by case when l.cliente_tem_documento then 0 else 1 end, l.total desc, l.client_id, l.pagador_documento;
$$;

comment on function public.pagadores_para_conferir() is
  'Pares cliente × quem pagou (documento diferente ou cliente sem documento) ainda sem decisão (o proposto pelo '
  'financeiro continua, esperando o SIM do administrador — também o que veio da fila ou do assistente e não está nas '
  'ligações), com o aviso que tira o par do lote.';

-- ---------------------------------------------------------------------------------------------
-- 8. View pagamentos_com_pagador — o "Pago por" de cada pagamento
-- ---------------------------------------------------------------------------------------------
-- A linha do banco do pagamento: payments.bank_transaction_id; senão a linha com reconciled_payment_id = o
-- pagamento; senão receivables.bank_transaction_id — esta só quando nenhum OUTRO pagamento da mesma conta já está
-- ligado a ela (pagamento em dinheiro de uma conta paga em parte por Pix não herda o pagador do Pix).
-- situacao:
--   cliente     — o documento de quem pagou é o do cliente (CNPJ pela raiz);
--   terceiro    — pagador confirmado do cliente, ou os dois documentos existem e são diferentes;
--   indefinido  — o cliente não tem documento e não há pagador confirmado ("nome diferente nunca identifica");
--   sem_dado    — sem linha do banco, ou o banco não disse quem pagou.
-- security_invoker: quem não lê bank_transactions (técnico, vendedor) vê o pagamento sem pagador.
create or replace view public.pagamentos_com_pagador
with (security_invoker = on) as
select p.id as payment_id,
       p.receivable_id,
       r.client_id,
       b.id as bank_transaction_id,
       nullif(btrim(b.counterparty_name), '') as pagador_nome,
       nullif(public._doc_normalizado(b.counterparty_document), '') as pagador_documento,
       pc.relacao,
       case
         when b.id is null then 'sem_dado'
         when length(public._doc_normalizado(b.counterparty_document)) >= 11
              and length(public._doc_normalizado(c.cpf_cnpj)) >= 11
              and not public._documento_contradiz(b.counterparty_document, c.cpf_cnpj) then 'cliente'
         when pc.relacao is not null then 'terceiro'
         when length(public._doc_normalizado(b.counterparty_document)) >= 11
              and length(public._doc_normalizado(c.cpf_cnpj)) >= 11 then 'terceiro'
         when length(public._doc_normalizado(c.cpf_cnpj)) < 11
              and (length(public._doc_normalizado(b.counterparty_document)) >= 11
                   or nullif(btrim(b.counterparty_name), '') is not null) then 'indefinido'
         else 'sem_dado'
       end as situacao
  from public.payments p
  join public.receivables r on r.id = p.receivable_id
  left join public.clients c on c.id = r.client_id
  left join lateral (
    select coalesce(
      p.bank_transaction_id,
      (select b1.id from public.bank_transactions b1 where b1.reconciled_payment_id = p.id order by b1.id limit 1),
      case when r.bank_transaction_id is not null
             and not exists (
               select 1 from public.payments p2
                where p2.receivable_id = r.id and p2.id <> p.id
                  and (p2.bank_transaction_id = r.bank_transaction_id
                       or exists (select 1 from public.bank_transactions b2
                                   where b2.id = r.bank_transaction_id and b2.reconciled_payment_id = p2.id)))
           then r.bank_transaction_id end
    ) as bt_id
  ) linha on true
  left join public.bank_transactions b on b.id = linha.bt_id
  left join lateral (
    select x.relacao
      from public.pagadores_do_cliente x
     where x.client_id = r.client_id
       and x.situacao = 'confirmado'
       and length(public._doc_normalizado(b.counterparty_document)) >= 11
       and not public._documento_contradiz(x.documento, b.counterparty_document)
     order by (x.documento = public._doc_normalizado(b.counterparty_document)) desc, x.confirmado_em
     limit 1
  ) pc on true;

comment on view public.pagamentos_com_pagador is
  'Quem pagou cada pagamento de conta a receber (pela linha do banco) e se foi o cliente, um terceiro ou indefinido.';

revoke all on public.pagamentos_com_pagador from public, anon, authenticated;
grant select on public.pagamentos_com_pagador to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 9. Privilégios das funções públicas (revogar de anon POR NOME)
-- ---------------------------------------------------------------------------------------------
revoke all on function public.guardar_pagadores_do_cliente(jsonb, uuid) from public, anon;
revoke all on function public.decidir_pagador_do_cliente(uuid, text, text, uuid, text) from public, anon;
revoke all on function public.recusar_pagadores_do_cliente(jsonb, text, uuid) from public, anon;
revoke all on function public.pagadores_para_conferir() from public, anon;
grant execute on function public.guardar_pagadores_do_cliente(jsonb, uuid) to authenticated, service_role;
grant execute on function public.decidir_pagador_do_cliente(uuid, text, text, uuid, text) to authenticated, service_role;
grant execute on function public.recusar_pagadores_do_cliente(jsonb, text, uuid) to authenticated, service_role;
grant execute on function public.pagadores_para_conferir() to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- 10. Prova, dentro da própria migration: anon não lê nem executa; as internas ficam fechadas
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_f text;
begin
  foreach v_f in array array[
    'public.guardar_pagadores_do_cliente(jsonb, uuid)',
    'public.decidir_pagador_do_cliente(uuid, text, text, uuid, text)',
    'public.recusar_pagadores_do_cliente(jsonb, text, uuid)',
    'public.pagadores_para_conferir()'
  ] loop
    if has_function_privilege('anon', v_f, 'execute') then
      raise exception '% continua executável por anon', v_f;
    end if;
    if not has_function_privilege('authenticated', v_f, 'execute') or not has_function_privilege('service_role', v_f, 'execute') then
      raise exception '% sem execute para authenticated/service_role', v_f;
    end if;
  end loop;
  foreach v_f in array array['public._raizes_do_cnpj_da_hbr()', 'public._pagador_consolidar_regras(uuid, text)',
                             'public._pagador_regra_de_outro_cliente(uuid, text)'] loop
    if has_function_privilege('anon', v_f, 'execute') or has_function_privilege('authenticated', v_f, 'execute') then
      raise exception '% não pode ser executável de fora', v_f;
    end if;
  end loop;
  if has_table_privilege('anon', 'public.pagadores_do_cliente', 'select')
     or has_table_privilege('anon', 'public.pagamentos_com_pagador', 'select') then
    raise exception 'anon lê pagadores_do_cliente ou pagamentos_com_pagador';
  end if;
  if has_table_privilege('authenticated', 'public.pagadores_do_cliente', 'insert')
     or has_table_privilege('authenticated', 'public.pagadores_do_cliente', 'update')
     or has_table_privilege('authenticated', 'public.pagadores_do_cliente', 'delete') then
    raise exception 'authenticated escreve direto em pagadores_do_cliente (a escrita é só pelas funções)';
  end if;
  if not exists (select 1 from pg_class where oid = 'public.pagamentos_com_pagador'::regclass
                  and 'security_invoker=on' = any (coalesce(reloptions, '{}'))) then
    raise exception 'pagamentos_com_pagador sem security_invoker=on';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.pagadores_do_cliente'::regclass) then
    raise exception 'pagadores_do_cliente sem RLS';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261022190000', 'pagadores_do_cliente')
on conflict do nothing;
