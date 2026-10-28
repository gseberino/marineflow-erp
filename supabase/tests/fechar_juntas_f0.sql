-- Prova: "Fechar juntas", Fases 0 e 0b, parte do banco (migration 20261028190000_fechar_juntas_f0).
--
--   G1  coluna clients.generico (not null, padrão falso) e a migration marcou SÓ o "Cliente Final" sem
--       documento (510a1f14…, o único candidato em 28/10/2026)
--   G2  OS de cadastro genérico: _os_impedimento_para_agrupar dá a mensagem pronta, _agrupar_os_montar recusa
--       e nada muda, os_para_agrupar lista com elegivel = false e o MESMO motivo; a OS-00110 (concluída, do
--       Cliente Final de verdade) recebe a mensagem do genérico
--   G3  orçamento de cadastro genérico: _agrupar_orcamentos_montar recusa e nada muda; a porta pública
--       agrupar_orcamentos recusa ANTES de gastar o document_number_seq; orcamentos_para_agrupar mostra o motivo
--       (e, no reprovado, o impedimento_se_voltar)
--   G4  dado real: os orçamentos do Cliente Final na embarcação 4a7caf94… ficam todos inelegíveis pelo genérico
--   K1  chegada no barco: OS-00032, OS-00033 e OS-00076 (chegada registrada, aguardando cliente) passam a ser
--       recusadas no agrupar ("chegada no barco registrada")
--   N1–N4 OS com nota viva (origem direta) não é cancelada: autorizada (UPDATE direto), em processamento
--       (cancel_service_order_cascade: contas e cobranças ficam como estavam), orçamento com nota ("o
--       orçamento"), duas notas ("as notas")
--   N5  nota morta (rascunho, rejeitada, falhou, cancelada), nota manual e nota de OUTRA OS não prendem: cancela
--   N6  dado real: a OS-00060 (NF-e nº 29 e NFS-e nº 4 autorizadas) não é cancelada
--   N7  agrupar/desagrupar (OS e orçamentos) continuam funcionando: os dois cancelam OS sem nota
--   P1  privilégios: funções novas fora de anon/authenticated, _cliente_generico para o service role, gatilho
--       ligado, security definer com search_path vazio
--
-- ═══ COMO RODAR ═══ (só com OK nomeado; DEPOIS da migration aplicada — o arquivo usa a coluna e as funções dela)
--
--   npx supabase@2.111.0 db query --linked -f supabase/tests/fechar_juntas_f0.sql --output json
--   (a partir do repositório principal: o worktree não é linkado)
--
-- Seguro em produção: usuário, clientes, barcos, OS, orçamentos e notas de teste criados aqui (números
-- OS-9xxxxx/ORÇ-9xxxxx livres; notas sem chave nem provedor: nada é enviado); as agrupadas recebem números
-- fictícios (OS-T…/ORÇ-T…) passados direto aos _montar. A porta pública agrupar_orcamentos só roda no G3,
-- onde falha antes de numerar (e o G3 confere). As leituras de dado real (G1, G2, G4, K1) não gravam; o N6
-- tenta cancelar a OS-00060 e o gatilho recusa. Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ids (nome text primary key, id uuid) on commit drop;

-- ── helpers da transação (somem no rollback) ────────────────────────────────────────────────
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop')
$$;

create function pg_temp._id(p_nome text) returns uuid language sql stable as $$
  select id from _ids where nome = p_nome
$$;

-- condição verdadeira -> null; falsa ou nula -> o nome (concat_ws dos nomes = detalhe; vazio = tudo certo)
create function pg_temp._se(p_ok boolean, p_nome text) returns text language sql immutable as $$
  select case when coalesce(p_ok, false) then null else p_nome end
$$;

create function pg_temp._usuario(p_role text) returns uuid language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste fechar juntas (' || p_role || ')', 'teste-fechar-juntas-' || v_id || '@teste.invalido', p_role, true);
  return v_id;
end $$;

create function pg_temp._cliente(p_generico boolean default false) returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.clients (type, name, generico)
  values ('individual', 'Cliente Teste Fechar Juntas ' || pg_temp._letras(6), p_generico)
  returning id into v_id;
  return v_id;
end $$;

create function pg_temp._barco(p_cli uuid) returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.vessels (client_id, name) values (p_cli, 'Barco' || pg_temp._letras(8)) returning id into v_id;
  return v_id;
end $$;

create function pg_temp._numero_livre(p_prefixo text) returns text language plpgsql as $$
declare
  v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders where service_order_number = p_prefixo || v_num) loop
    v_num := v_num + 1;
  end loop;
  return p_prefixo || v_num;
end $$;

-- OS já convertida (p_status <> 'draft') ou orçamento em aberto (p_status = 'draft'), com 1 serviço (2 h × R$ 150)
create function pg_temp._os(p_cli uuid, p_ves uuid, p_status text default 'approved', p_quote_status text default null)
returns uuid language plpgsql as $$
declare
  v_os uuid;
begin
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, converted_to_os_at, created_at)
  values (pg_temp._numero_livre(case when p_status = 'draft' then 'ORÇ-' else 'OS-' end), p_cli, p_ves, p_status,
          coalesce(p_quote_status, case when p_status = 'draft' then 'draft' else 'approved' end),
          case when p_status = 'draft' then null else now() end, clock_timestamp())
  returning id into v_os;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, discount_pct, discount_amount)
  values (v_os, 'Serviço de teste', 'hour', 2, 150, 300, 0, 0);
  perform public.recalc_so_totals(v_os);
  return v_os;
end $$;

create function pg_temp._nota(p_os uuid, p_tipo text, p_status text, p_numero integer default null,
                              p_origem text default 'service_order')
returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  insert into public.issued_fiscal_documents (document_type, origin_type, origin_id, client_id, status, number)
  values (p_tipo, p_origem, p_os, (select client_id from public.service_orders where id = p_os), p_status, p_numero)
  returning id into v_id;
  return v_id;
end $$;

create function pg_temp._erro_sql(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

create function pg_temp._retrato(p_ids uuid[]) returns text language sql stable as $$
  select string_agg(concat_ws('/', so.id, so.status, coalesce(so.quote_status, '-'), coalesce(so.share_token::text, '-'),
                              coalesce(so.merged_into_id::text, '-'), coalesce(so.grand_total::text, '-'),
                              coalesce(so.cancelled_at::text, '-'), coalesce(so.payment_status, '-')),
                    ' | ' order by so.id)
    from public.service_orders so where so.id = any(p_ids)
$$;

insert into _ids values ('admin', pg_temp._usuario('admin'));

-- ═══ G cadastro genérico ═══════════════════════════════════════════════════════════════════════
do $$
declare
  v_falhas text;
begin
  v_falhas := concat_ws(', ',
    pg_temp._se(exists (select 1 from information_schema.columns
                         where table_schema = 'public' and table_name = 'clients' and column_name = 'generico'
                           and data_type = 'boolean' and is_nullable = 'NO' and column_default = 'false'), 'coluna'),
    pg_temp._se((select count(*) from public.clients where generico) = 1, 'só um genérico (' ||
                (select count(*) from public.clients where generico) || ')'),
    pg_temp._se(exists (select 1 from public.clients c where c.id = '510a1f14-202a-49f0-855c-3358758cfb5f' and c.generico
                          and c.name = 'Cliente Final' and nullif(btrim(coalesce(c.cpf_cnpj, '')), '') is null), 'Cliente Final marcado'));
  insert into _resultado values ('G1 clients.generico not null default false; só o "Cliente Final" sem documento marcado',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas end);
exception when others then
  insert into _resultado values ('G1 clients.generico not null default false; só o "Cliente Final" sem documento marcado',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_cli uuid; v_ves uuid; a uuid; b uuid; v_msg text; v_erro text; v_antes text; v_numero text := 'OS-T' || upper(pg_temp._letras(6));
  r jsonb; v_falhas text; v_real text;
begin
  v_cli := pg_temp._cliente(true);
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._os(v_cli, v_ves);
  b := pg_temp._os(v_cli, v_ves);
  v_msg := public._os_impedimento_para_agrupar(a);
  v_antes := pg_temp._retrato(array[a, b]);
  v_erro := pg_temp._erro_sql(format('select public._agrupar_os_montar(%L::uuid[], null, %L, %L::uuid, null)',
                                     array[a, b], v_numero, pg_temp._id('admin')));
  r := public.os_para_agrupar(v_ves, null, pg_temp._id('admin'), null);
  select public._os_impedimento_para_agrupar(so.id) into v_real
    from public.service_orders so where so.service_order_number = 'OS-00110';
  v_falhas := concat_ws(', ',
    pg_temp._se(v_msg = format('O cadastro %s é genérico, sem CPF/CNPJ: a %s não entra em agrupamento. Passe a OS para o cadastro do cliente de verdade antes de agrupar.',
                               (select name from public.clients where id = v_cli),
                               (select service_order_number from public.service_orders where id = a)), 'mensagem'),
    pg_temp._se(v_erro like '22023 O cadastro % é genérico, sem CPF/CNPJ: a %', 'montar recusa'),
    pg_temp._se(pg_temp._retrato(array[a, b]) = v_antes
                and not exists (select 1 from public.service_orders where service_order_number = v_numero), 'nada mudou'),
    pg_temp._se((select count(*) from jsonb_array_elements(r -> 'os') e
                  where (e ->> 'id')::uuid in (a, b) and not (e ->> 'elegivel')::boolean
                    and e ->> 'motivo' = public._os_impedimento_para_agrupar((e ->> 'id')::uuid)) = 2, 'os_para_agrupar'),
    pg_temp._se(v_real like 'O cadastro Cliente Final é genérico, sem CPF/CNPJ: a OS-00110 não entra em agrupamento.%', 'OS-00110 real'));
  insert into _resultado values ('G2 OS de cadastro genérico: mensagem pronta, _agrupar_os_montar recusa e nada muda, os_para_agrupar com o mesmo motivo, OS-00110 real',
    v_falhas = '', case when v_falhas = '' then v_msg else 'falhou: ' || v_falhas || ' | ' || coalesce(v_erro, 'AGRUPOU')
                        || ' | real: ' || coalesce(v_real, 'null') end);
exception when others then
  insert into _resultado values ('G2 OS de cadastro genérico: mensagem pronta, _agrupar_os_montar recusa e nada muda, os_para_agrupar com o mesmo motivo, OS-00110 real',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_cli uuid; v_ves uuid; a uuid; b uuid; c uuid; v_erro text; v_erro_porta text; v_antes text;
  v_numero text := 'ORÇ-T' || upper(pg_temp._letras(6)); v_lv1 bigint; v_lv2 bigint; v_ic1 boolean; v_ic2 boolean;
  r jsonb; v_falhas text; v_nome text;
begin
  v_cli := pg_temp._cliente(true);
  select name into v_nome from public.clients where id = v_cli;
  v_ves := pg_temp._barco(v_cli);
  a := pg_temp._os(v_cli, v_ves, 'draft');
  b := pg_temp._os(v_cli, v_ves, 'draft');
  c := pg_temp._os(v_cli, v_ves, 'draft', 'rejected');
  v_antes := pg_temp._retrato(array[a, b]);
  v_erro := pg_temp._erro_sql(format('select public._agrupar_orcamentos_montar(%L::uuid[], null, %L, %L::uuid, null)',
                                     array[a, b], v_numero, pg_temp._id('admin')));
  -- porta pública sem sessão: vale p_autor; recusa antes de numerar
  select last_value, is_called into v_lv1, v_ic1 from public.document_number_seq;
  v_erro_porta := pg_temp._erro_sql(format('select public.agrupar_orcamentos(%L::uuid[], null, null, %L::uuid)',
                                           array[a, b], pg_temp._id('admin')));
  select last_value, is_called into v_lv2, v_ic2 from public.document_number_seq;
  r := public.orcamentos_para_agrupar(v_ves, null, pg_temp._id('admin'), null);
  v_falhas := concat_ws(', ',
    pg_temp._se(v_erro = format('22023 O cadastro %s é genérico, sem CPF/CNPJ: o %s não entra em agrupamento. Passe o orçamento para o cadastro do cliente de verdade antes de agrupar.',
                                v_nome, (select service_order_number from public.service_orders where id = a)), 'montar recusa'),
    pg_temp._se(pg_temp._retrato(array[a, b]) = v_antes
                and not exists (select 1 from public.service_orders where service_order_number = v_numero), 'nada mudou'),
    pg_temp._se(v_erro_porta like '22023 O cadastro % é genérico%' and v_lv1 = v_lv2 and v_ic1 = v_ic2
                and pg_temp._retrato(array[a, b]) = v_antes, 'porta pública sem gastar número'),
    pg_temp._se((select count(*) from jsonb_array_elements(r -> 'orcamentos') e
                  where (e ->> 'id')::uuid in (a, b) and not (e ->> 'elegivel')::boolean
                    and e ->> 'motivo' = format('o cadastro %s é genérico, sem CPF/CNPJ: não entra em agrupamento', v_nome)) = 2,
                'orcamentos_para_agrupar'),
    pg_temp._se(exists (select 1 from jsonb_array_elements(r -> 'orcamentos') e
                         where (e ->> 'id')::uuid = c and e ->> 'motivo' = 'reprovado pelo cliente (desistência)'
                           and e ->> 'impedimento_se_voltar' like 'o cadastro % é genérico%'), 'reprovado'));
  insert into _resultado values ('G3 orçamento de cadastro genérico: _montar e a porta recusam (sem gastar número), nada muda, leitura com o motivo',
    v_falhas = '', case when v_falhas = '' then v_erro else 'falhou: ' || v_falhas || ' | ' || coalesce(v_erro, 'AGRUPOU')
                        || ' | porta: ' || coalesce(v_erro_porta, 'AGRUPOU') end);
exception when others then
  insert into _resultado values ('G3 orçamento de cadastro genérico: _montar e a porta recusam (sem gastar número), nada muda, leitura com o motivo',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  r jsonb; v_qtd integer; v_ruins integer;
begin
  r := public.orcamentos_para_agrupar('4a7caf94-5e7f-4e38-af11-35db24f9f41a'::uuid, '510a1f14-202a-49f0-855c-3358758cfb5f'::uuid,
                                      pg_temp._id('admin'), null);
  select count(*),
         count(*) filter (where (e ->> 'elegivel')::boolean
                             or not (coalesce(e ->> 'motivo', '') like 'o cadastro Cliente Final é genérico%'
                                     or coalesce(e ->> 'impedimento_se_voltar', '') like 'o cadastro Cliente Final é genérico%'))
    into v_qtd, v_ruins
    from jsonb_array_elements(r -> 'orcamentos') e;
  insert into _resultado values ('G4 dado real: orçamentos do Cliente Final (embarcação 4a7caf94…) inelegíveis pelo genérico',
    v_qtd > 0 and v_ruins = 0, v_qtd || ' orçamentos, ' || v_ruins || ' fora da regra');
exception when others then
  insert into _resultado values ('G4 dado real: orçamentos do Cliente Final (embarcação 4a7caf94…) inelegíveis pelo genérico',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ K chegada no barco (dado real) ═══════════════════════════════════════════════════════════
do $$
declare
  v_det text; v_ok integer;
begin
  select string_agg(so.service_order_number || ': ' || coalesce(public._os_impedimento_para_agrupar(so.id), 'ELEGÍVEL'), ' | '
                    order by so.service_order_number),
         count(*) filter (where public._os_impedimento_para_agrupar(so.id) like '% já começou a ser executada (%chegada no barco registrada%')
    into v_det, v_ok
    from public.service_orders so where so.service_order_number in ('OS-00032', 'OS-00033', 'OS-00076');
  insert into _resultado values ('K1 dado real: OS-00032, OS-00033 e OS-00076 recusadas pela chegada no barco registrada',
    v_ok = 3, coalesce(v_det, 'nenhuma encontrada'));
exception when others then
  insert into _resultado values ('K1 dado real: OS-00032, OS-00033 e OS-00076 recusadas pela chegada no barco registrada',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ N nota viva não deixa cancelar ═══════════════════════════════════════════════════════════
do $$
declare
  v_cli uuid; v_ves uuid; a uuid; b uuid; c uuid; d uuid; v_num_a text; v_num_c text; v_num_d text;
  e1 text; e2 text; e3 text; e4 text; v_rec uuid; v_cob uuid; v_falhas text;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);

  -- N1 concluída com NFS-e autorizada: UPDATE direto recusa, com a mensagem exata
  a := pg_temp._os(v_cli, v_ves, 'completed');
  select service_order_number into v_num_a from public.service_orders where id = a;
  perform pg_temp._nota(a, 'nfse', 'authorized', 77);
  e1 := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'cancelled', a));
  insert into _resultado values ('N1 OS com NFS-e autorizada: cancelar por UPDATE direto recusa com a mensagem pronta',
    e1 = format('22023 A %s tem a NFS-e nº 77 autorizada: cancele a nota antes de cancelar a OS (o cancelamento da nota tem prazo).', v_num_a)
    and exists (select 1 from public.service_orders where id = a and status = 'completed' and cancelled_at is null),
    coalesce(e1, 'CANCELOU'));

  -- N2 em processamento, pela cascata: recusa e as contas/cobranças ficam como estavam
  b := pg_temp._os(v_cli, v_ves, 'completed');
  perform pg_temp._nota(b, 'nfse', 'processing');
  insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, balance_amount, status)
  values (v_cli, b, 'Teste fechar juntas: saldo', current_date, current_date + 10, 300, 300, 'pending') returning id into v_rec;
  insert into public.collections (service_order_id, receivable_id, client_id, amount, due_date, status)
  values (b, v_rec, v_cli, 300, current_date + 10, 'pending') returning id into v_cob;
  e2 := pg_temp._erro_sql(format('select public.cancel_service_order_cascade(%L::uuid, %L)', b, 'teste'));
  insert into _resultado values ('N2 OS com NFS-e em processamento: a cascata recusa e conta/cobrança ficam pendentes',
    e2 like '22023 A OS-% tem a NFS-e em processamento: espere a nota terminar de processar e, se sair autorizada, cancele-a antes de cancelar a OS.'
    and exists (select 1 from public.service_orders where id = b and status = 'completed')
    and exists (select 1 from public.receivables where id = v_rec and status = 'pending' and balance_amount = 300)
    and exists (select 1 from public.collections where id = v_cob and status = 'pending'),
    coalesce(e2, 'CANCELOU'));

  -- N3 orçamento (ainda rascunho) com nota autorizada (o caso do ORÇ-00109): "o orçamento"
  c := pg_temp._os(v_cli, v_ves, 'draft');
  select service_order_number into v_num_c from public.service_orders where id = c;
  perform pg_temp._nota(c, 'nfse', 'authorized', 6);
  e3 := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'cancelled', c));
  insert into _resultado values ('N3 orçamento com NFS-e autorizada: cancelar recusa ("antes de cancelar o orçamento")',
    e3 = format('22023 O %s tem a NFS-e nº 6 autorizada: cancele a nota antes de cancelar o orçamento (o cancelamento da nota tem prazo).', v_num_c)
    and exists (select 1 from public.service_orders where id = c and status = 'draft'),
    coalesce(e3, 'CANCELOU'));

  -- N4 duas notas: as duas na mensagem, no plural
  d := pg_temp._os(v_cli, v_ves, 'invoiced');
  select service_order_number into v_num_d from public.service_orders where id = d;
  perform pg_temp._nota(d, 'nfe', 'authorized', 29);
  perform pg_temp._nota(d, 'nfse', 'authorized', 4);
  e4 := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'cancelled', d));
  insert into _resultado values ('N4 duas notas autorizadas: as duas na mensagem ("cancele as notas")',
    e4 like '22023 A ' || v_num_d || ' tem a %, a %: cancele as notas antes de cancelar a OS (o cancelamento da nota tem prazo).'
    and strpos(e4, 'NF-e nº 29 autorizada') > 0 and strpos(e4, 'NFS-e nº 4 autorizada') > 0
    and exists (select 1 from public.service_orders where id = d and status = 'invoiced'),
    coalesce(e4, 'CANCELOU'));
exception when others then
  insert into _resultado values ('N1–N4 nota viva', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_cli uuid; v_ves uuid; a uuid; b uuid; c uuid; e1 text; e2 text; e3 text;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  -- notas mortas na própria OS + nota manual autorizada apontando para ela + nota viva de OUTRA OS
  a := pg_temp._os(v_cli, v_ves, 'completed');
  b := pg_temp._os(v_cli, v_ves, 'completed');
  perform pg_temp._nota(a, 'nfse', 'draft');
  perform pg_temp._nota(a, 'nfse', 'rejected', 10);
  perform pg_temp._nota(a, 'nfse', 'failed');
  perform pg_temp._nota(a, 'nfse', 'cancelled', 11);
  perform pg_temp._nota(a, 'nfe', 'cancelled', 12);
  perform pg_temp._nota(a, 'nfe', 'authorized', 13, 'manual');
  perform pg_temp._nota(b, 'nfse', 'authorized', 14);
  e1 := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'cancelled', a));
  -- OS comum sem nota: a cascata segue cancelando
  c := pg_temp._os(v_cli, v_ves, 'approved');
  e2 := pg_temp._erro_sql(format('select public.cancel_service_order_cascade(%L::uuid, %L)', c, 'teste'));
  -- a OS da nota viva (b) é que fica presa
  e3 :=pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'cancelled', b));
  insert into _resultado values ('N5 nota morta, manual ou de outra OS não prende (cancela); OS sem nota cancela pela cascata; a outra OS prende',
    e1 is null and e2 is null and strpos(coalesce(e3, ''), 'NFS-e nº 14 autorizada') > 0
    and exists (select 1 from public.service_orders where id = a and status = 'cancelled')
    and exists (select 1 from public.service_orders where id = c and status = 'cancelled')
    and exists (select 1 from public.service_orders where id = b and status = 'completed'),
    'mortas: ' || coalesce(e1, 'cancelou') || ' | sem nota: ' || coalesce(e2, 'cancelou') || ' | outra OS: ' || coalesce(e3, 'CANCELOU'));
exception when others then
  insert into _resultado values ('N5 nota morta, manual ou de outra OS não prende (cancela); OS sem nota cancela pela cascata; a outra OS prende',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_id uuid; v_status text; e1 text;
begin
  select id, status into v_id, v_status from public.service_orders where service_order_number = 'OS-00060';
  e1 := pg_temp._erro_sql(format('update public.service_orders set status = %L where id = %L', 'cancelled', v_id));
  insert into _resultado values ('N6 dado real: a OS-00060 (NF-e nº 29 e NFS-e nº 4 autorizadas) não é cancelada',
    v_id is not null and strpos(coalesce(e1, ''), 'NF-e nº 29 autorizada') > 0 and strpos(coalesce(e1, ''), 'NFS-e nº 4 autorizada') > 0
    and (select status from public.service_orders where id = v_id) = v_status,
    coalesce(e1, 'CANCELOU'));
exception when others then
  insert into _resultado values ('N6 dado real: a OS-00060 (NF-e nº 29 e NFS-e nº 4 autorizadas) não é cancelada',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_cli uuid; v_ves uuid; v uuid[]; o uuid[]; r jsonb; v_g uuid; v_go uuid; v_falhas text;
begin
  v_cli := pg_temp._cliente();
  v_ves := pg_temp._barco(v_cli);
  -- OS: agrupar (cancela as originais) e desagrupar (cancela a agrupada)
  v := array[pg_temp._os(v_cli, v_ves), pg_temp._os(v_cli, v_ves)];
  r := public._agrupar_os_montar(v, null, 'OS-T' || upper(pg_temp._letras(6)), pg_temp._id('admin'), null);
  v_g := (r ->> 'service_order_id')::uuid;
  v_falhas := concat_ws(', ',
    pg_temp._se((select count(*) from public.service_orders where id = any(v) and status = 'cancelled' and merged_into_id = v_g) = 2,
                'agrupar OS cancelou as originais'));
  perform public._desagrupar_os_desfazer(v_g, pg_temp._id('admin'));
  v_falhas := concat_ws(', ', nullif(v_falhas, ''),
    pg_temp._se(exists (select 1 from public.service_orders where id = v_g and status = 'cancelled')
                and (select count(*) from public.service_orders where id = any(v) and status = 'approved' and merged_into_id is null) = 2,
                'desagrupar OS'));
  -- Orçamentos: idem
  o := array[pg_temp._os(v_cli, v_ves, 'draft'), pg_temp._os(v_cli, v_ves, 'draft')];
  v_go := (public._agrupar_orcamentos_montar(o, null, 'ORÇ-T' || upper(pg_temp._letras(6)), pg_temp._id('admin'), null)
           ->> 'service_order_id')::uuid;
  v_falhas := concat_ws(', ', nullif(v_falhas, ''),
    pg_temp._se(v_go is not null
                and (select count(*) from public.service_orders where id = any(o) and status = 'cancelled' and merged_into_id = v_go) = 2,
                'agrupar orçamentos'));
  perform public._desagrupar_orcamentos_desfazer(v_go, pg_temp._id('admin'));
  v_falhas := concat_ws(', ', nullif(v_falhas, ''),
    pg_temp._se(exists (select 1 from public.service_orders where id = v_go and status = 'cancelled')
                and (select count(*) from public.service_orders where id = any(o) and status = 'draft' and merged_into_id is null) = 2,
                'desagrupar orçamentos'));
  insert into _resultado values ('N7 agrupar/desagrupar OS e orçamentos seguem funcionando com o gatilho da nota viva',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas end);
exception when others then
  insert into _resultado values ('N7 agrupar/desagrupar OS e orçamentos seguem funcionando com o gatilho da nota viva',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ P privilégios ═══════════════════════════════════════════════════════════════════════════
do $$
declare
  v_falhas text;
begin
  v_falhas := concat_ws(', ',
    pg_temp._se(not has_function_privilege('anon', 'public._cliente_generico(uuid)', 'execute'), 'anon _cliente_generico'),
    pg_temp._se(not has_function_privilege('authenticated', 'public._cliente_generico(uuid)', 'execute'), 'logado _cliente_generico'),
    pg_temp._se(has_function_privilege('service_role', 'public._cliente_generico(uuid)', 'execute'), 'service_role sem _cliente_generico'),
    pg_temp._se(not has_function_privilege('anon', 'public._os_nota_viva_nao_cancela()', 'execute'), 'anon gatilho'),
    pg_temp._se(not has_function_privilege('authenticated', 'public._os_nota_viva_nao_cancela()', 'execute'), 'logado gatilho'),
    pg_temp._se(not has_function_privilege('authenticated', 'public._os_execucao_iniciada(uuid)', 'execute'), 'logado _os_execucao_iniciada'),
    pg_temp._se(not has_function_privilege('authenticated', 'public._os_impedimento_para_agrupar(uuid)', 'execute'), 'logado _os_impedimento'),
    pg_temp._se(not has_function_privilege('authenticated', 'public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric)', 'execute'), 'logado _montar orçamentos'),
    pg_temp._se(has_function_privilege('authenticated', 'public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[])', 'execute')
                and not has_function_privilege('anon', 'public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[])', 'execute'), 'leitura de orçamentos'),
    pg_temp._se(exists (select 1 from pg_trigger t where t.tgrelid = 'public.service_orders'::regclass
                         and t.tgname = 'trg_os_nota_viva_nao_cancela' and t.tgenabled = 'O'), 'gatilho ligado'),
    pg_temp._se((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
                   from pg_proc p
                  where p.oid in ('public._cliente_generico(uuid)'::regprocedure, 'public._os_nota_viva_nao_cancela()'::regprocedure,
                                  'public._os_execucao_iniciada(uuid)'::regprocedure, 'public._os_impedimento_para_agrupar(uuid)'::regprocedure,
                                  'public._agrupar_orcamentos_montar(uuid[], uuid, text, uuid, numeric)'::regprocedure,
                                  'public.orcamentos_para_agrupar(uuid, uuid, uuid, uuid[])'::regprocedure)), 'security definer + search_path'));
  insert into _resultado values ('P1 privilégios: funções novas fora de anon/authenticated, gatilho ligado, search_path vazio',
    v_falhas = '', case when v_falhas = '' then 'ok' else 'falhou: ' || v_falhas end);
exception when others then
  insert into _resultado values ('P1 privilégios: funções novas fora de anon/authenticated, gatilho ligado, search_path vazio',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
