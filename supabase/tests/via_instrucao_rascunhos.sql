-- Prova da F2 da via do técnico v2 (20/11/2026; migration 20270131100000_via_instrucao_rascunhos.sql): o assistente sugere a Instrução de
-- cada serviço, o dono aprova ou corrige, e só o aprovado vai a technician_instructions (e ao papel).
-- bancada: depende de 20270131100000
--
--   P   a forma e as portas: tabela com RLS e policy só "select to authenticated"; anon sem nada; authenticated só lê; funções privadas
--       fechadas e as 3 públicas para authenticated/service_role; gatilho E16 é o ÚLTIMO BEFORE UPDATE da linha; CHECK de
--       ai_suggestion_reviews com instrucao_tecnico; nenhum UPDATE/DELETE sem WHERE nas funções novas (pg_safeupdate)
--   C   a regra de COBRANÇA em SQL = a do TypeScript: cada caso de supabase/functions/_shared/pdf/via-cobranca-casos.ts, com o título
--       curto que o TypeScript calcula (tituloDoServico) e a resposta (ehCobranca). A guarda src/test/via-casos-no-teste-sql.test.ts
--       confere que cada caso da lista está aqui, com o mesmo título
--   O   o NÚMERO do serviço em SQL = o do TypeScript: cada caso de supabase/functions/_shared/linhas-da-os-casos.ts (CASOS_DE_ORDEM),
--       linhas gravadas com o created_at do caso (microssegundos, fração cortada, outro fuso, empate total, cobrança contada)
--   N   o núcleo, com dado sintético: pedir (reuso nasce pendente; cobrança e linha com instrução ficam fora; um job só por OS, sem
--       nome do cliente na entrada; pedir de novo não cria outro job), receber (idempotente; não confia na resposta; sem_sugestao),
--       decidir (corrigir grava o editado; E16: instrução não mexe em updated_at, quantidade mexe; o 2º canal recebe ja_decidido;
--       aprovar todas; descartar; nunca sobrescreve; R$ recusado; obsoleto quando a linha muda; documento fora de uso), uma linha em
--       ai_suggestion_reviews por decisão, job que falhou devolve as linhas, não admin = 42501, anon sem acesso
--
-- ═══ COMO RODAR ═══
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/via_instrucao_rascunhos.sql
--   Ensaio ANTES de aplicar (migration + este teste na MESMA transação, desfeita): concatenar "begin;" + a migration + este arquivo
--   sem a linha "begin;" (o rollback do fim desfaz os dois). Termina em ROLLBACK: nada fica gravado; os jobs criados aqui nunca chegam
--   ao gateway (não são vistos fora da transação).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
-- Simula a requisição do PostgREST (claims do JWT); sem papel = sem login.
create function pg_temp.req(p_sub uuid, p_papel text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    case when p_papel is null then '' else jsonb_strip_nulls(jsonb_build_object('sub', p_sub, 'role', p_papel))::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_sub::text, ''), true);
  perform set_config('request.headers', '', true);
end $f$;
-- UPDATE/DELETE sem WHERE no nível de cima (o detector da 20261112300000, resumido: sem comentários nem strings).
create function pg_temp.sem_where(p_corpo text) returns setof text language sql immutable as $f$
  with c as (
    select regexp_replace(regexp_replace(p_corpo, '--[^\n]*', '', 'g'), '''(?:[^'']|'''')*''', '''''', 'g') as corpo
  )
  select btrim(regexp_replace(m[1], '\s+', ' ', 'g'))
    from c, regexp_matches(c.corpo, '(?<![a-z0-9_.])((?:update|delete\s+from)\s+(?:only\s+)?(?!(?:set|of|on|or|loop|skip|nowait)\M)(?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*\M[^;]*)', 'gi') as m
   where m[1] !~* '\mwhere\M'
$f$;

-- ── P. A forma e as portas ───────────────────────────────────────────────────────────────────────────────────────────────────────────
do $p$
declare
  v_res jsonb := '[]'::jsonb;
  v_f   text;
  v_ruim text;
  v_ult text;
begin
  v_res := pg_temp.ok(v_res, 'P1 tabela com RLS', (select c.relrowsecurity from pg_class c where c.oid = 'public.via_instrucao_rascunhos'::regclass));
  v_res := pg_temp.ok(v_res, 'P2 anon não alcança a tabela',
    not (has_table_privilege('anon', 'public.via_instrucao_rascunhos', 'select') or has_table_privilege('anon', 'public.via_instrucao_rascunhos', 'insert')
         or has_table_privilege('anon', 'public.via_instrucao_rascunhos', 'update') or has_table_privilege('anon', 'public.via_instrucao_rascunhos', 'delete')));
  v_res := pg_temp.ok(v_res, 'P3 authenticated só lê',
    has_table_privilege('authenticated', 'public.via_instrucao_rascunhos', 'select')
    and not (has_table_privilege('authenticated', 'public.via_instrucao_rascunhos', 'insert')
             or has_table_privilege('authenticated', 'public.via_instrucao_rascunhos', 'update')
             or has_table_privilege('authenticated', 'public.via_instrucao_rascunhos', 'delete')));
  v_res := pg_temp.ok(v_res, 'P4 uma policy só, select to authenticated',
    (select count(*) = 1 and bool_and(p.roles = array['authenticated']::name[] and p.cmd = 'SELECT')
       from pg_policies p where p.schemaname = 'public' and p.tablename = 'via_instrucao_rascunhos'),
    (select string_agg(p.policyname || ' ' || p.cmd || ' ' || p.roles::text, '; ') from pg_policies p
      where p.schemaname = 'public' and p.tablename = 'via_instrucao_rascunhos'));

  v_ruim := null;
  foreach v_f in array array['public.via_instrucao_pedir(uuid, text, uuid[], uuid, boolean)', 'public.via_instrucao_pendentes(uuid, uuid)',
                             'public.via_instrucao_decidir(jsonb, text, uuid, uuid)'] loop
    if has_function_privilege('anon', v_f, 'execute') or not has_function_privilege('authenticated', v_f, 'execute')
       or not has_function_privilege('service_role', v_f, 'execute')
       or not (select p.prosecdef from pg_proc p where p.oid = to_regprocedure(v_f)) then
      v_ruim := concat_ws(', ', v_ruim, v_f);
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'P5 as 3 públicas: definer, authenticated e service_role, sem anon', v_ruim is null, v_ruim);

  select string_agg(p.oid::regprocedure::text, ', ') into v_ruim
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and (p.proname like '\_via\_%' or p.proname = '_linha_instrucao_mantem_updated_at')
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));
  v_res := pg_temp.ok(v_res, 'P6 funções privadas fechadas para anon e authenticated', v_ruim is null, v_ruim);
  v_res := pg_temp.ok(v_res, 'P6b as 19 privadas existem',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private' and (p.proname like '\_via\_%' or p.proname = '_linha_instrucao_mantem_updated_at')) = 19);

  select t.tgname into v_ult from pg_trigger t
   where t.tgrelid = 'public.service_order_services'::regclass and not t.tgisinternal
     and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16   -- BEFORE, UPDATE
   order by t.tgname desc limit 1;
  v_res := pg_temp.ok(v_res, 'P7 E16 é o último BEFORE UPDATE da linha (roda depois do set_updated_at)',
    v_ult = 'trg_zz_instrucao_mantem_updated_at', v_ult);

  v_res := pg_temp.ok(v_res, 'P8 ai_suggestion_reviews aceita instrucao_tecnico (e mantém os 7 de antes)',
    (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'ai_suggestion_reviews_suggestion_type_check')
      ~ 'instrucao_tecnico' and
    (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'ai_suggestion_reviews_suggestion_type_check')
      ~ 'survey_question.*step.*duration.*material.*quote_line.*step_template.*step_block');

  select string_agg(p.proname || ': ' || w, ' | ') into v_ruim
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
         lateral pg_temp.sem_where(p.prosrc) w
   where (n.nspname = 'private' and p.proname like '\_via\_%') or (n.nspname = 'public' and p.proname like 'via\_instrucao\_%');
  v_res := pg_temp.ok(v_res, 'P9 nenhum UPDATE/DELETE sem WHERE nas funções novas', v_ruim is null, v_ruim);

  perform pg_temp.gravar(v_res);
end
$p$;

-- ── C. Cobrança: SQL = TypeScript (via-cobranca-casos.ts; título = tituloDoServico do TS) ─────────────────────────────────────────────
insert into _resultado
select 'C ' || x.caso,
       private._via_titulo_curto(x.nome) = x.titulo and private._via_eh_cobranca(x.nome) = x.cobranca,
       format('%s → sql "%s" %s | ts "%s" %s', x.nome, private._via_titulo_curto(x.nome), private._via_eh_cobranca(x.nome), x.titulo, x.cobranca)
  from (values
    ($c$insumos no fim do título, com parêntese de detalhe$c$, $n$Termorretráteis e insumos (abraçadeiras, terminais e fita)$n$, $t$Termorretráteis e insumos (abraçadeiras, terminais e fita)$t$, true),
    ($c$"Insumos" no começo, em caixa alta e baixa, com barra$c$, $n$Insumos Elétricos / terminais, fusíveis e conectores$n$, $t$Insumos Elétricos / terminais, fusíveis e conectores$t$, true),
    ($c$frete DEPOIS do travessão é detalhe do serviço: fica$c$, $n$Retirada e reinstalação do carregador TM41 — inclui frete de ida e volta ao fornecedor$n$, $t$Retirada e reinstalação do carregador TM41$t$, false),
    ($c$frete em CAIXA ALTA (palavra inteira, sem acento e em minúsculas na comparação)$c$, $n$FRETE EQUIPAMENTO$n$, $t$FRETE EQUIPAMENTO$t$, true),
    ($c$deslocamento sozinho no título$c$, $n$Deslocamento técnico$n$, $t$Deslocamento técnico$t$, true),
    ($c$insumos no fim de um título longo em caixa alta (falso positivo aceito: era OS cancelada)$c$, $n$LEVANTAMENTO E DIMENSIONAMENTO DE PROTEÇÃO TÉRMICA DO CHICOTE E INSUMOS$n$, $t$LEVANTAMENTO E DIMENSIONAMENTO DE PROTEÇÃO TÉRMICA DO CHICOTE E INSUMOS$t$, true),
    ($c$"Transporte" não é palavra da regra: fica (pergunta antiga ao dono, sem resposta)$c$, $n$Transporte$n$, $t$Transporte$t$, false),
    ($c$insumo no singular também conta$c$, $n$Insumo de vedação$n$, $t$Insumo de vedação$t$, true),
    ($c$palavra só começando igual não conta ("fretado", "deslocamentos" de peça não são a palavra inteira)$c$, $n$Ajuste do banco fretado e deslocamentos do trilho$n$, $t$Ajuste do banco fretado e deslocamentos do trilho$t$, false),
    ($c$serviço comum: fica$c$, $n$Instalação de inversor 3000 W$n$, $t$Instalação de inversor 3000 W$t$, false),
    ($c$"Mão de obra —" na frente sai antes de olhar o título (limparRuido)$c$, $n$Mão de obra — deslocamento até a marina$n$, $t$Deslocamento até a marina$t$, true),
    ($c$preço no nome sai antes de olhar o título; o frete continua sendo o título$c$, $n$Frete (R$ 150,00)$n$, $t$Frete$t$, true),
    ($c$nome vazio vira "Serviço": não é cobrança$c$, $n$$n$, $t$Serviço$t$, false)
  ) as x(caso, nome, titulo, cobranca);

-- ── O. Número do serviço: SQL = TypeScript (CASOS_DE_ORDEM de linhas-da-os-casos.ts; o 4º campo é o número esperado) ───────────────
create temp table _casos_de_ordem (caso integer, id uuid, criado text, numero integer) on commit drop;
insert into _casos_de_ordem values
    (1, '00000000-0000-4000-8000-000000000001', '2026-11-16T18:01:02.123457+00:00', 2),
    (1, '00000000-0000-4000-8000-000000000002', '2026-11-16T18:01:02.123456+00:00', 1),
    (2, '00000000-0000-4000-8000-000000000001', '2026-11-16T18:01:00.13+00:00', 5),
    (2, '00000000-0000-4000-8000-000000000002', '2026-11-16T18:01:00.1201+00:00', 4),
    (2, '00000000-0000-4000-8000-000000000003', '2026-11-16T18:01:00.12+00:00', 3),
    (2, '00000000-0000-4000-8000-000000000004', '2026-11-16T18:00:59.000001+00:00', 2),
    (2, '00000000-0000-4000-8000-000000000005', '2026-11-16T18:00:59+00:00', 1),
    (3, 'c0000000-0000-4000-8000-000000000000', '2026-11-14T04:25:59.5+00:00', 3),
    (3, '0a000000-0000-4000-8000-000000000000', '2026-11-14T04:25:59.5+00:00', 1),
    (3, '9f000000-0000-4000-8000-000000000000', '2026-11-14T04:25:59.5+00:00', 2),
    (4, '00000000-0000-4000-8000-000000000009', '2026-11-16 15:01:02.5-03', 2),
    (4, '00000000-0000-4000-8000-000000000008', '2026-11-16T18:01:02.5+00:00', 1),
    (5, '00000000-0000-4000-8000-000000000003', '2026-11-16T18:01:03+00:00', 3),
    (5, '00000000-0000-4000-8000-000000000002', '2026-11-16T18:01:02+00:00', 2),
    (5, '00000000-0000-4000-8000-000000000001', '2026-11-16T18:01:01+00:00', 1);

do $o$
declare
  v_res   jsonb := '[]'::jsonb;
  v_barco uuid := (select id from public.vessels where client_id is not null order by created_at, id limit 1);
  v_cli   uuid := (select client_id from public.vessels where id = (select id from public.vessels where client_id is not null order by created_at, id limit 1));
  v_caso  integer;
  v_os    uuid;
  v_dif   text;
begin
  for v_caso in select distinct c.caso from _casos_de_ordem c order by 1 loop
    begin
      insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
      values (v_cli, v_barco, 'ORÇ-TESTE-F2-O' || v_caso, 'draft', 'draft') returning id into v_os;
      -- na ordem FÍSICA do caso (a do arquivo)
      insert into public.service_order_services (id, service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot,
                                                 line_total, created_at)
      select c.id, v_os, 'TESTE F2 — ordem ' || c.numero, 'unit', 1, 0, 0, c.criado::timestamptz
        from _casos_de_ordem c where c.caso = v_caso order by c.ctid;
      select string_agg(format('%s: sql %s, ts %s', c.id, n.numero, c.numero), '; ') into v_dif
        from _casos_de_ordem c
        left join private._via_linhas_numeradas(v_os) n on n.linha_id = c.id
       where c.caso = v_caso and n.numero is distinct from c.numero;
      v_res := pg_temp.ok(v_res, 'O caso ' || v_caso || ' de CASOS_DE_ORDEM', v_dif is null, v_dif);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
  end loop;
  perform pg_temp.gravar(v_res);
end
$o$;

-- ── N. O núcleo ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
do $n$
declare
  v_res    jsonb := '[]'::jsonb;
  -- o dono: o job precisa de requested_by em auth.users (o gateway só roda claude-local para ele)
  v_admin  uuid := (select id from public.app_users where role = 'admin' and active order by created_at, id limit 1);
  v_tec    uuid := gen_random_uuid();
  v_barco  uuid := (select id from public.vessels where client_id is not null order by created_at, id limit 1);
  v_cli    uuid;
  v_nome_cli text;
  v_os  uuid; v_osb uuid; v_osc uuid;
  t0    timestamptz := '2026-11-20 12:00:00+00';
  l_tem uuid; l_cob uuid; l_reuso uuid; l_ia uuid; l_cita uuid; l_novo uuid; l_obs uuid; l_desc uuid; l_fal uuid; l_c uuid;
  v_job uuid; v_job2 uuid;
  j     public.ai_jobs;
  r     jsonb; r2 jsonb;
  v_n   integer;
  v_txt text;
  v_upd timestamptz;
  v_id_ia uuid; v_id_reuso uuid; v_id_novo uuid; v_id_obs uuid; v_id_desc uuid; v_id_c uuid;
  v_msg text;
  v_rev integer;
begin
  if v_admin is null or v_barco is null then
    raise exception 'FALHOU: sem admin ativo ou sem barco cadastrado para montar o teste';
  end if;
  select client_id into v_cli from public.vessels where id = v_barco;
  select name into v_nome_cli from public.clients where id = v_cli;
  insert into public.app_users (id, full_name, email, role, active)
  values (v_tec, 'Teste F2 (técnico)', 'teste-f2-' || v_tec || '@teste.invalido', 'technician', true);

  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status, problem_description)
  values (v_cli, v_barco, 'ORÇ-TESTE-F2-A', 'draft', 'draft', 'Antena de TV sem sinal e quadro de popa desarmando.') returning id into v_os;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cli, v_barco, 'ORÇ-TESTE-F2-B', 'draft', 'draft') returning id into v_osb;

  -- a fonte do reuso (outra OS, instrução aprovada) e uma fonte que cita "serviço 3" (o reuso pula)
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total,
                                             technician_instructions, created_at)
  values (v_osb, 'TESTE F2 — revisão do quadro de popa', 'unit', 1, 0, 0,
          'Remoção da tampa do quadro, reaperto dos bornes, troca dos fusíveis queimados e teste de cada circuito.', t0),
         (v_osb, 'TESTE F2 — troca da bomba de porão', 'unit', 1, 0, 0,
          'Remoção da bomba antiga e instalação da nova; a fiação é o serviço 3; teste de acionamento.', t0 + interval '1 ms');

  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total,
                                             technician_instructions, created_at, updated_at)
  values (v_os, 'TESTE F2 — ligação do inversor', 'unit', 1, 0, 0, 'Instrução já gravada pelo dono para este serviço.', t0 + interval '1 ms', t0)
  returning id into l_tem;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at, updated_at)
  values (v_os, 'Deslocamento técnico', 'visit', 1, 0, 0, t0 + interval '2 ms', t0) returning id into l_cob;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at, updated_at)
  values (v_os, 'TESTE F2 — revisão do quadro de popa', 'unit', 1, 0, 0, t0 + interval '3 ms', t0) returning id into l_reuso;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at, updated_at)
  values (v_os, 'TESTE F2 — instalação da antena de TV', 'unit', 1, 0, 0, t0 + interval '4 ms', '2026-01-01 00:00:00+00') returning id into l_ia;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at, updated_at)
  values (v_os, 'TESTE F2 — troca da bomba de porão', 'unit', 1, 0, 0, t0 + interval '5 ms', t0) returning id into l_cita;

  -- N1 pedir pela tela (login do admin)
  perform pg_temp.req(v_admin, 'authenticated');
  r := public.via_instrucao_pedir(v_os);
  v_job := (r ->> 'job_id')::uuid;
  v_res := pg_temp.ok(v_res, 'N1 pedir: 1 reuso, 2 ao assistente num job novo, 1 com instrução e 1 cobrança ficam fora',
    (r ->> 'reusadas')::int = 1 and (r ->> 'pedidas')::int = 2 and (r ->> 'ja_tem')::int = 1 and (r ->> 'cobranca')::int = 1
    and (r ->> 'job_novo')::boolean and v_job is not null, r::text);
  select * into j from public.ai_jobs x where x.id = v_job;
  v_res := pg_temp.ok(v_res, 'N1b o job: do admin, claude-local/sonnet/json_schema, sem reserva, prioridade 40, prazo 30 min',
    j.requested_by = v_admin and j.provider = 'claude-local' and j.model = 'sonnet' and j.response_format = 'json_schema'
    and j.task_profile = 'text' and not j.allow_fallback and j.priority = 40 and j.timeout_seconds = 90 and j.max_attempts = 2
    and j.deadline_at = now() + interval '30 minutes' and j.json_schema is not null and j.status = 'pending',
    format('%s %s %s %s %s', j.requested_by = v_admin, j.provider, j.model, j.priority, j.deadline_at));
  v_res := pg_temp.ok(v_res, 'N1c metadata: tipo, OS, as 2 linhas e a base de cada uma',
    j.metadata ->> 'tipo' = 'instrucao_rascunho' and j.metadata ->> 'service_order_id' = v_os::text
    and j.metadata -> 'linhas' @> to_jsonb(array[l_ia, l_cita]) and jsonb_array_length(j.metadata -> 'linhas') = 2
    and j.metadata -> 'bases' ? l_ia::text and j.metadata ->> 'pedido_via' = 'tela', j.metadata::text);
  v_res := pg_temp.ok(v_res, 'N1d entrada: as 5 linhas na ordem do papel, cobrança com pedir falso, pedido do cliente, sem o nome do cliente',
    jsonb_array_length(j.input -> 'servicos') = 5
    and (select string_agg(e ->> 'numero', ',' order by o) from jsonb_array_elements(j.input -> 'servicos') with ordinality t(e, o)) = '1,2,3,4,5'
    and (select (e ->> 'pedir')::boolean = false and (e ->> 'cobranca')::boolean from jsonb_array_elements(j.input -> 'servicos') e
          where e ->> 'linha_id' = l_cob::text)
    and (select (e ->> 'pedir')::boolean from jsonb_array_elements(j.input -> 'servicos') e where e ->> 'linha_id' = l_ia::text)
    and j.input -> 'os' ->> 'pedido_do_cliente' like 'Antena de TV%'
    and (v_nome_cli is null or position(v_nome_cli in j.input::text) = 0),
    left(j.input::text, 400));

  -- N2 pedir de novo: o mesmo job, nenhum outro
  r2 := public.via_instrucao_pedir(v_os);
  v_res := pg_temp.ok(v_res, 'N2 pedir de novo não cria outro job (espera o aberto)',
    (r2 ->> 'job_id')::uuid = v_job and not (r2 ->> 'job_novo')::boolean and (r2 ->> 'esperando_job')::int = 2
    and (select count(*) from public.ai_jobs x where x.metadata ->> 'service_order_id' = v_os::text) = 1, r2::text);

  -- N3 a tela antes do assistente responder: só o reuso, com o rótulo da fonte e o número do papel
  r := public.via_instrucao_pendentes(v_os);
  select (e ->> 'id')::uuid into v_id_reuso from jsonb_array_elements(r -> 'pendentes') e where e ->> 'linha_id' = l_reuso::text;
  v_res := pg_temp.ok(v_res, 'N3 pendentes: o reuso (serviço 3, "igual à do ORÇ-TESTE-F2-B · serviço 1"), 2 elegíveis, job na fila',
    jsonb_array_length(r -> 'pendentes') = 1 and (r -> 'pendentes' -> 0 ->> 'numero')::int = 3
    and r -> 'pendentes' -> 0 ->> 'origem' = 'reuso' and r -> 'pendentes' -> 0 ->> 'fonte_rotulo' = 'igual à do ORÇ-TESTE-F2-B · serviço 1'
    and r -> 'pendentes' -> 0 ->> 'texto' like 'Remoção da tampa do quadro%'
    and (r ->> 'elegiveis')::int = 2 and r -> 'job' ->> 'status' = 'pending' and (r ->> 'em_uso')::boolean, r::text);

  -- N4 o assistente responde (o gateway grava assim): 1 texto (com quebra de linha), 1 "sem sugestão", 1 linha não pedida, 1 lixo
  update public.ai_jobs x
     set status = 'completed', completed_at = now(), model_used = 'claude-sonnet-teste',
         response = jsonb_build_object('format', 'json_schema', 'data', jsonb_build_object('itens', jsonb_build_array(
           jsonb_build_object('linha_id', l_ia, 'texto', E'Fixação do suporte da antena, passagem e ligação do cabo coaxial,\n sintonia dos canais e teste de imagem.', 'motivo_sem', null),
           jsonb_build_object('linha_id', l_cita, 'texto', null, 'motivo_sem', 'o nome já traz as etapas'),
           jsonb_build_object('linha_id', l_tem, 'texto', 'Texto para uma linha que não foi pedida ao assistente.', 'motivo_sem', null),
           jsonb_build_object('linha_id', 'nao-e-uuid', 'texto', 'Qualquer coisa com mais de dez letras.', 'motivo_sem', null))))
   where x.id = v_job;
  r := public.via_instrucao_pendentes(v_os);
  select (e ->> 'id')::uuid, e ->> 'texto' into v_id_ia, v_txt from jsonb_array_elements(r -> 'pendentes') e where e ->> 'linha_id' = l_ia::text;
  select * into j from public.ai_jobs x where x.id = v_job;
  v_res := pg_temp.ok(v_res, 'N4 receber: 1 sugestão (uma linha só), 1 sem_sugestao, 2 recusadas; 0 elegíveis; nada na linha',
    jsonb_array_length(r -> 'pendentes') = 2 and v_txt = 'Fixação do suporte da antena, passagem e ligação do cabo coaxial, sintonia dos canais e teste de imagem.'
    and (r ->> 'elegiveis')::int = 0 and j.metadata ? 'entregue_em' and (j.metadata ->> 'recebidos')::int = 1
    and (j.metadata ->> 'recusados')::int = 2 and (j.metadata ->> 'sem_sugestao')::int = 1
    and exists (select 1 from public.via_instrucao_rascunhos x where x.linha_id = l_cita and x.estado = 'sem_sugestao' and x.texto is null
                and x.motivo_fim = 'o nome já traz as etapas')
    and (select technician_instructions from public.service_order_services where id = l_ia) is null, r::text || ' | ' || j.metadata::text);
  v_n := private._via_instrucao_receber(v_job);
  v_res := pg_temp.ok(v_res, 'N4b receber de novo não faz nada (entregue_em)',
    v_n = 0 and (select count(*) from public.via_instrucao_rascunhos x where x.service_order_id = v_os) = 3, v_n::text);
  r := public.via_instrucao_pedir(v_os);
  v_res := pg_temp.ok(v_res, 'N4c pedir de novo: nada a pedir (2 pendentes, 1 sem sugestão), nenhum job',
    r -> 'job_id' = 'null'::jsonb and (r ->> 'pendentes')::int = 2 and (r ->> 'sem_sugestao')::int = 1, r::text);

  -- N5 corrigir pela tela: grava o editado; E16: updated_at da linha fica; histórico e aprendizado registram
  v_upd := (select updated_at from public.service_order_services where id = l_ia);
  r := public.via_instrucao_decidir(jsonb_build_array(jsonb_build_object('id', v_id_ia, 'acao', 'aprovar',
         'texto', 'Fixação do suporte da antena, ligação do cabo coaxial e teste de imagem em todas as TVs.')), 'tela');
  v_res := pg_temp.ok(v_res, 'N5 corrigir: a linha recebe o texto editado, a sugestão fica corrigida (tela, admin)',
    r -> 'itens' -> 0 ->> 'resultado' = 'corrigido' and (r -> 'itens' -> 0 ->> 'numero')::int = 4
    and (select technician_instructions from public.service_order_services where id = l_ia)
        = 'Fixação do suporte da antena, ligação do cabo coaxial e teste de imagem em todas as TVs.'
    and exists (select 1 from public.via_instrucao_rascunhos x where x.id = v_id_ia and x.estado = 'corrigido' and x.decidido_via = 'tela'
                and x.decidido_por = v_admin), r::text);
  v_res := pg_temp.ok(v_res, 'N5b E16: aprovar instrução NÃO mexe em updated_at da linha',
    (select updated_at from public.service_order_services where id = l_ia) = v_upd and v_upd = '2026-01-01 00:00:00+00',
    (select updated_at::text from public.service_order_services where id = l_ia));
  v_res := pg_temp.ok(v_res, 'N5c ai_suggestion_reviews: edited, sugerido × aprovado, modelo e versão do pedido',
    exists (select 1 from public.ai_suggestion_reviews x where x.suggestion_type = 'instrucao_tecnico' and x.target_id = l_ia
            and x.verdict = 'edited' and x.target_table = 'service_order_services' and x.reviewer_id = v_admin
            and x.suggested ->> 'texto' = v_txt and x.approved ->> 'texto' like 'Fixação do suporte da antena, ligação%'
            and x.ai_model = 'claude-sonnet-teste' and x.prompt_version = 'instrucao_rascunho/1'));

  -- N6 o 2º canal (WhatsApp, service_role com p_autor) recebe ja_decidido, sem erro e sem gravar
  perform pg_temp.req(null, 'service_role');
  r := public.via_instrucao_decidir(jsonb_build_array(jsonb_build_object('id', v_id_ia, 'acao', 'aprovar')), 'whatsapp', v_admin);
  v_res := pg_temp.ok(v_res, 'N6 o 2º canal: ja_decidido (corrigido pela tela), nada muda',
    r -> 'itens' -> 0 ->> 'resultado' = 'ja_decidido' and r -> 'itens' -> 0 ->> 'estado' = 'corrigido'
    and r -> 'itens' -> 0 ->> 'decidido_via' = 'tela'
    and (select count(*) from public.ai_suggestion_reviews x where x.target_id = l_ia) = 1, r::text);
  begin
    perform public.via_instrucao_pendentes(v_os, null);
    v_msg := 'passou';
  exception when insufficient_privilege then v_msg := '42501';
  end;
  v_res := pg_temp.ok(v_res, 'N6b service_role sem p_autor admin = 42501', v_msg = '42501', v_msg);

  -- N7 aprovar todas (p_itens nulo + OS): o reuso, com o texto sugerido
  perform pg_temp.req(v_admin, 'authenticated');
  r := public.via_instrucao_decidir(null, 'tela', null, v_os);
  v_res := pg_temp.ok(v_res, 'N7 aprovar todas: o reuso aprovado (accepted), a linha com o texto da fonte',
    (r -> 'totais' ->> 'aprovado')::int = 1 and jsonb_array_length(r -> 'itens') = 1
    and (select technician_instructions from public.service_order_services where id = l_reuso) like 'Remoção da tampa do quadro%'
    and exists (select 1 from public.ai_suggestion_reviews x where x.target_id = l_reuso and x.verdict = 'accepted' and x.prompt_version = 'reuso'),
    r::text);

  -- N8 E16 ao contrário: mudar a quantidade sobe updated_at
  update public.service_order_services set quantity = 2 where id = l_ia;
  v_res := pg_temp.ok(v_res, 'N8 E16: quantidade muda, updated_at sobe',
    (select updated_at from public.service_order_services where id = l_ia) = now());

  -- sugestões postas à mão (o banco; a tabela só deixa o postgres/service_role escrever) para os casos de decisão
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (v_os, 'TESTE F2 — troca do fusível do guincho', 'unit', 1, 0, 0, t0 + interval '6 ms') returning id into l_novo;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (v_os, 'TESTE F2 — revisão da luz de navegação', 'unit', 1, 0, 0, t0 + interval '7 ms') returning id into l_obs;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (v_os, 'TESTE F2 — ajuste do piloto automático', 'unit', 1, 0, 0, t0 + interval '8 ms') returning id into l_desc;
  insert into public.via_instrucao_rascunhos (linha_id, service_order_id, texto, origem, base, pedido_via, pedido_por)
  select s.id, v_os, 'Remoção do fusível queimado, troca pelo novo, conferência do cabo e teste do guincho.', 'ia',
         private._via_instrucao_base(s.name_snapshot, s.description_snapshot, s.notes), 'tela', v_admin
    from public.service_order_services s where s.id = l_novo returning id into v_id_novo;
  insert into public.via_instrucao_rascunhos (linha_id, service_order_id, texto, origem, base, pedido_via, pedido_por)
  select s.id, v_os, 'Remoção das lâmpadas, limpeza dos contatos, troca do que estiver ruim e teste das luzes.', 'ia',
         private._via_instrucao_base(s.name_snapshot, s.description_snapshot, s.notes), 'tela', v_admin
    from public.service_order_services s where s.id = l_obs returning id into v_id_obs;
  insert into public.via_instrucao_rascunhos (linha_id, service_order_id, texto, origem, base, pedido_via, pedido_por)
  select s.id, v_os, 'Conferência dos parâmetros do piloto, ajuste do ganho e teste de rumo em navegação.', 'ia',
         private._via_instrucao_base(s.name_snapshot, s.description_snapshot, s.notes), 'tela', v_admin
    from public.service_order_services s where s.id = l_desc returning id into v_id_desc;

  -- N9 "R$" recusado (nada grava); depois, o dono digitou no campo: aprovar não sobrescreve
  begin
    perform public.via_instrucao_decidir(jsonb_build_array(jsonb_build_object('id', v_id_novo, 'acao', 'aprovar',
              'texto', 'Troca do fusível e cobrança de R$ 50,00 no fim do serviço.')), 'tela');
    v_msg := 'passou';
  exception when sqlstate '22023' then v_msg := '22023';
  end;
  v_res := pg_temp.ok(v_res, 'N9 texto com R$ recusado (22023), a linha continua sem instrução',
    v_msg = '22023' and (select technician_instructions from public.service_order_services where id = l_novo) is null, v_msg);
  update public.service_order_services set technician_instructions = 'Texto escrito à mão pelo dono no campo.' where id = l_novo;
  r := public.via_instrucao_decidir(jsonb_build_array(jsonb_build_object('id', v_id_novo, 'acao', 'aprovar')), 'tela');
  v_res := pg_temp.ok(v_res, 'N9b nunca sobrescreve: a sugestão vira substituida, fica o texto do dono, nenhum veredito',
    r -> 'itens' -> 0 ->> 'resultado' = 'substituido'
    and (select technician_instructions from public.service_order_services where id = l_novo) = 'Texto escrito à mão pelo dono no campo.'
    and not exists (select 1 from public.ai_suggestion_reviews x where x.target_id = l_novo), r::text);

  -- N10 a linha mudou depois da sugestão: obsoleta, e a linha volta a ser elegível
  update public.service_order_services set name_snapshot = 'TESTE F2 — revisão das luzes de navegação e de fundeio' where id = l_obs;
  r := public.via_instrucao_pendentes(v_os);
  v_res := pg_temp.ok(v_res, 'N10 linha mudou: a sugestão fica obsoleta e some da tela',
    exists (select 1 from public.via_instrucao_rascunhos x where x.id = v_id_obs and x.estado = 'obsoleto'
            and x.motivo_fim = 'o serviço mudou depois da sugestão' and x.decidido_via = 'sistema')
    and not exists (select 1 from jsonb_array_elements(r -> 'pendentes') e where e ->> 'id' = v_id_obs::text), r::text);

  -- N11 descartar: nada na linha, veredito rejected
  r := public.via_instrucao_decidir(jsonb_build_array(jsonb_build_object('id', v_id_desc, 'acao', 'descartar')), 'tela');
  v_res := pg_temp.ok(v_res, 'N11 descartar: rejected, aprovado nulo, a linha sem instrução',
    r -> 'itens' -> 0 ->> 'resultado' = 'descartado'
    and (select technician_instructions from public.service_order_services where id = l_desc) is null
    and exists (select 1 from public.ai_suggestion_reviews x where x.target_id = l_desc and x.verdict = 'rejected' and x.approved is null),
    r::text);

  -- N12 a tabela recusa quebra de linha e texto curto (CHECK); ação desconhecida recusada
  begin
    insert into public.via_instrucao_rascunhos (linha_id, service_order_id, texto, origem, base, pedido_via)
    values (l_desc, v_os, E'Duas\nlinhas de instrução não cabem.', 'ia', md5('x'), 'tela');
    v_msg := 'passou';
  exception when check_violation then v_msg := 'check';
  end;
  v_res := pg_temp.ok(v_res, 'N12 quebra de linha recusada pela tabela', v_msg = 'check', v_msg);
  begin
    perform public.via_instrucao_decidir(jsonb_build_array(jsonb_build_object('id', v_id_desc, 'acao', 'apagar')), 'tela');
    v_msg := 'passou';
  exception when sqlstate '22023' then v_msg := '22023';
  end;
  v_res := pg_temp.ok(v_res, 'N12b ação desconhecida = 22023', v_msg = '22023', v_msg);

  -- N13 uma linha em ai_suggestion_reviews por DECISÃO (corrigido, aprovado, descartado); ja_decidido/substituido/obsoleto não contam
  select count(*) into v_rev from public.ai_suggestion_reviews x
   where x.suggestion_type = 'instrucao_tecnico' and x.target_id in (l_tem, l_cob, l_reuso, l_ia, l_cita, l_novo, l_obs, l_desc);
  v_res := pg_temp.ok(v_res, 'N13 3 vereditos para 3 decisões', v_rev = 3, v_rev::text);

  -- N14 documento fora de uso (orçamento recusado): a pendente não aparece nem é aprovável; pedir recusa
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cli, v_barco, 'ORÇ-TESTE-F2-C', 'draft', 'draft') returning id into v_osc;
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total)
  values (v_osc, 'TESTE F2 — troca do carregador', 'unit', 1, 0, 0) returning id into l_c;
  insert into public.via_instrucao_rascunhos (linha_id, service_order_id, texto, origem, base, pedido_via, pedido_por)
  select s.id, v_osc, 'Remoção do carregador antigo, instalação do novo, ligação e teste de carga.', 'ia',
         private._via_instrucao_base(s.name_snapshot, s.description_snapshot, s.notes), 'tela', v_admin
    from public.service_order_services s where s.id = l_c returning id into v_id_c;
  update public.service_orders set quote_status = 'rejected', motivo_perda = 'desistiu', motivo_perda_em = now(), motivo_perda_por = 'tela'
   where id = v_osc;   -- orçamento recusado: fora de uso (E8)
  r := public.via_instrucao_decidir(jsonb_build_array(jsonb_build_object('id', v_id_c, 'acao', 'aprovar')), 'tela');
  v_res := pg_temp.ok(v_res, 'N14 orçamento recusado: decidir devolve fora_de_uso e fecha como obsoleto; a linha fica sem instrução',
    r -> 'itens' -> 0 ->> 'resultado' = 'fora_de_uso'
    and exists (select 1 from public.via_instrucao_rascunhos x where x.id = v_id_c and x.estado = 'obsoleto' and x.motivo_fim = 'documento fora de uso')
    and (select technician_instructions from public.service_order_services where id = l_c) is null, r::text);
  r := public.via_instrucao_pendentes(v_osc);
  v_res := pg_temp.ok(v_res, 'N14b pendentes do orçamento recusado: em_uso falso, nada pendente, 0 elegíveis',
    not (r ->> 'em_uso')::boolean and jsonb_array_length(r -> 'pendentes') = 0 and (r ->> 'elegiveis')::int = 0, r::text);
  begin
    perform public.via_instrucao_pedir(v_osc);
    v_msg := 'passou';
  exception when sqlstate '22023' then v_msg := '22023';
  end;
  v_res := pg_temp.ok(v_res, 'N14c pedir num orçamento recusado = 22023', v_msg = '22023', v_msg);

  -- N15 o job que falha devolve as linhas (elegíveis de novo, nenhuma sugestão)
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (v_os, 'TESTE F2 — instalação do sonar', 'unit', 1, 0, 0, t0 + interval '9 ms') returning id into l_fal;
  r := public.via_instrucao_pedir(v_os, 'tela', array[l_fal]);
  v_job2 := (r ->> 'job_id')::uuid;
  -- (20/11) na mesma transação os dois jobs nascem no mesmo now(): o 2º passa 1 ms à frente para "o mais recente" não cair no desempate por id
  update public.ai_jobs x set status = 'failed', completed_at = now(), error_code = 'timeout', error = 'teste',
         created_at = x.created_at + interval '1 ms' where x.id = v_job2;
  r := public.via_instrucao_pendentes(v_os);
  v_res := pg_temp.ok(v_res, 'N15 job que falhou: entregue sem sugestão, a tela mostra a falha, a linha volta a ser elegível',
    (r ->> 'job_novo') is null and v_job2 is not null and v_job2 <> v_job
    and (select metadata ? 'entregue_em' from public.ai_jobs where id = v_job2)
    and r -> 'job' ->> 'id' = v_job2::text and r -> 'job' ->> 'error_code' = 'timeout'
    and not exists (select 1 from public.via_instrucao_rascunhos x where x.linha_id = l_fal)
    and (r ->> 'elegiveis')::int >= 1, r::text);

  -- N16 quem não é admin: 42501 nas 3
  perform pg_temp.req(v_tec, 'authenticated');
  v_msg := '';
  begin perform public.via_instrucao_pedir(v_os); v_msg := v_msg || 'pedir passou '; exception when insufficient_privilege then null; end;
  begin perform public.via_instrucao_pendentes(v_os); v_msg := v_msg || 'pendentes passou '; exception when insufficient_privilege then null; end;
  begin perform public.via_instrucao_decidir(null, 'tela', null, v_os); v_msg := v_msg || 'decidir passou'; exception when insufficient_privilege then null; end;
  v_res := pg_temp.ok(v_res, 'N16 técnico logado: 42501 em pedir, pendentes e decidir', v_msg = '', v_msg);

  -- N17 pela RLS, com o papel de verdade: o técnico não lê, o admin lê; anon nem a tabela nem as funções
  set local role authenticated;
  select count(*) into v_n from public.via_instrucao_rascunhos x where x.service_order_id = v_os;
  reset role;
  v_res := pg_temp.ok(v_res, 'N17 técnico (authenticated) não lê nenhuma sugestão', v_n = 0, v_n::text);
  perform pg_temp.req(v_admin, 'authenticated');
  set local role authenticated;
  select count(*) into v_n from public.via_instrucao_rascunhos x where x.service_order_id = v_os;
  reset role;
  v_res := pg_temp.ok(v_res, 'N17b admin (authenticated) lê', v_n > 0, v_n::text);
  perform pg_temp.req(null, 'anon');
  v_msg := '';
  set local role anon;
  begin perform count(*) from public.via_instrucao_rascunhos; v_msg := v_msg || 'leu '; exception when insufficient_privilege then null; end;
  begin perform public.via_instrucao_pendentes(v_os); v_msg := v_msg || 'executou'; exception when insufficient_privilege then null; end;
  reset role;
  v_res := pg_temp.ok(v_res, 'N17c anon: sem a tabela e sem as funções', v_msg = '', v_msg);

  perform pg_temp.gravar(v_res);
end
$n$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
