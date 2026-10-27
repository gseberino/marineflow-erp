-- Prova das notas do e-mail e do Pix da Agenda de Produção, Fase 4 (pacote P3): migration 20261027100300.
-- bancada: depende de 20261027100300
--
--   N0 portas: a remessa do e-mail, os passos e as internas só para service_role; a RPC do material com a assinatura nova
--      (p_aviso) para authenticated e service_role, a antiga fora; nunca anon; agenda_rascunho.tipo aceita aviso
--   N1 a remessa do e-mail: desligado = nada; idempotente; o CNPJ casa o fornecedor (o principal, com dois cadastros); sem
--      cadastro, o prazo pelo lugar do XML; dhSaiEnt vence dhEmi; modFrete 9 = o próprio despacho; velha e de outra empresa
--      ignoradas; extração antiga = sem itens; a já importada nasce chegou e ligada à OS da importação; NENHUMA OS muda
--   N2 a previsão da Kamell: seg 26/10 + 4 dias úteis = sex 30/10
--   N3 a pergunta "é material de qual serviço?": só com OS candidata, as opções em ordem (fornecedor, palavra, início), o
--      texto, perda_em, a validade, uma vez; sem candidata, nada; vai ao fechamento e de carona
--   N4 a resposta (o aviso): ambíguo e não achado perguntam e nada entra; "tudo" com a nota = as linhas do fornecedor da nota
--      ou sem fornecedor; nada muda antes do *grava*; o *grava* deixa a linha a caminho pela nota (nível B), a nota ligada e a
--      pergunta respondida; a data dita vence
--   N5 "não é de serviço": sem aviso recusa; a releitura; o *grava* deixa a nota sem serviço e a pergunta respondida
--   N6 a nota importada: a remessa chegou, a linha ligada na mão, a ação material (origem nota) com o *desfaz*, no "o que
--      mudou" do fechamento; em sombra a ação fica executada = false e a linha igual; o aviso de nota já importada = na mão
--   N7 o Pix: a pergunta (texto, a OS, perda_em), 1 por semana NO TOTAL, uma vez por Pix, a janela, o valor mínimo, a
--      categoria, a OS sem início ou que começa depois de material_inicio_dias fica de fora, o CMP com destino, a limpeza; a
--      resposta grava comprado/na mão; NENHUMA tabela de dinheiro muda
--   N8 desligado = nada (remessa, passos, pergunta, aviso)
--   N9 as cópias só acrescentam os blocos "-- FASE 4:" (agenda_rascunho_material e _agenda_aplicar_material × 20261024160600;
--      _agenda_rascunho_frase e agenda_rascunho_gravar × 20261027100100; agenda_carona e _agenda_mudancas × 20261026100500)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase4_notas_pix.sql
--   Seguro em produção: tudo termina em ROLLBACK. N1–N8 rodam só na bancada (a fixture-fase4; fora dela, PULADO); N9 só com
--   as migrations antigas como texto.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- A chamada como a ferramenta faz (o admin da fixture, pelo WhatsApp, sex 30/10).
create function pg_temp.mat(p_os text, p_itens text[], p_sit text, p_quando text, p_trecho text, p_aviso text,
                            p_forn text default null) returns jsonb language sql as $f$
  select public.agenda_rascunho_material('aa000000-0000-4000-8000-000000000001', 'whatsapp', p_os, p_itens, p_sit, p_quando,
                                         p_forn, null, false, p_trecho, date '2026-10-30', p_aviso)
$f$;
create function pg_temp.grava() returns jsonb language sql as $f$
  select public.agenda_rascunho_gravar('aa000000-0000-4000-8000-000000000001', date '2026-10-30')
$f$;
create function pg_temp.descarta() returns jsonb language sql as $f$
  select public.agenda_rascunho_descartar('aa000000-0000-4000-8000-000000000001')
$f$;

-- Fotografias: as linhas de material (sem a hora da última mudança) e as tabelas de dinheiro.
create function pg_temp.foto_material() returns text language sql stable as $f$
  select md5(coalesce(string_agg((to_jsonb(m) - 'atualizado_em')::text, '|' order by m.id), '')) from public.os_material m
$f$;
create function pg_temp.foto_dinheiro() returns text language sql stable as $f$
  select md5(concat_ws('#',
    (select string_agg(to_jsonb(x)::text, '|' order by x.id) from public.bank_transactions x),
    (select string_agg(to_jsonb(x)::text, '|' order by x.id) from public.finance_review_queue x),
    (select string_agg(to_jsonb(x)::text, '|' order by x.id) from public.payables x),
    (select string_agg(to_jsonb(x)::text, '|' order by x.id) from public.comprovantes x),
    (select string_agg(to_jsonb(x)::text, '|' order by x.id) from public.receivables x),
    (select string_agg(to_jsonb(x)::text, '|' order by x.id) from public.payments x)))
$f$;

-- Um e-mail de teste com as NF-e dadas (o que o leitor do email-imap grava).
create function pg_temp.email(p_id uuid, p_nfes jsonb) returns uuid language sql as $f$
  insert into public.email_messages (id, account_id, dedup_key, from_address, subject, received_at, has_attachments,
                                     dados_extraidos)
  values (p_id, 'd4000000-0000-4000-8000-0000000003e0', 'teste-ag4:' || p_id, 'nfe@teste-ag4.test', 'TESTE AG4',
          timestamptz '2026-10-30 08:00-03', true, jsonb_build_object('nfes', p_nfes, 'boletos', '[]'::jsonb))
  returning id
$f$;
create function pg_temp.nfe(p_chave text, p_cnpj text, p_numero text, p_data text, p_saida text, p_frete text, p_uf text,
                            p_mun text, p_para boolean default true, p_com_itens boolean default true) returns jsonb
language sql immutable as $f$
  select jsonb_build_object('anexo_indice', 0, 'chave', p_chave, 'emitente', 'EMITENTE TESTE AG4', 'emitente_cnpj', p_cnpj,
           'numero', p_numero, 'serie', '1', 'valor', 100.5, 'data', p_data, 'para_empresa', p_para)
         || case when p_com_itens then jsonb_build_object('saida', p_saida, 'mod_frete', p_frete, 'uf', p_uf, 'municipio', p_mun,
                   'itens', jsonb_build_array(jsonb_build_object('n', 1, 'descricao', 'PECA TESTE AG4', 'qtd', 1, 'un', 'UN')))
                 else '{}'::jsonb end
$f$;

-- O bloco "create or replace function public.<nome>(…)" de uma migration: o corpo (entre "as $function$" e "$function$;").
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'as $function$\n' in v) + length(E'as $function$'));
  return left(v, position(E'\n$function$;' in v));
end $f$;

-- O corpo sem os blocos "-- FASE 4: … -- FASE 4: fim" (linhas).
-- (Fase 5, P5) o corpo sem os blocos "-- FASE 5: … -- FASE 5: fim" (P5 recriou _agenda_rascunho_frase e _agenda_mudancas em 20261028100500).
create function pg_temp.sem_fase5(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 5:' and l !~ '^\s*-- FASE 5: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 5: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;
create function pg_temp.sem_fase4(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 4:' and l !~ '^\s*-- FASE 4: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 4: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- ── N0. Portas ──────────────────────────────────────────────────────────────────────────────────────────
do $n0$
declare
  v_res jsonb := '[]'::jsonb;
  c_nova constant text := 'public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date, text)';
  f text;
  v_so_service text[] := array[
    'public.material_remessas_do_email(uuid, date)', 'public._agenda_material_notas(date, timestamptz)',
    'public._agenda_material_pix(date, timestamptz)',
    'public._agenda_material_perguntar(text, text, uuid, uuid[], uuid, date, text, jsonb, timestamptz, boolean)',
    'public._agenda_aplicar_aviso(uuid, jsonb, text, text, date)', 'public._agenda_aplicar_material(uuid, uuid, jsonb, text, date)',
    'public._agenda_resolver_aviso(text, uuid, text)', 'public._agenda_pix_fonte(text, uuid)',
    'public._agenda_material_em_falta(date)', 'public._agenda_rascunho_frase(text, jsonb)',
    'public.agenda_carona(uuid, text[], text, date, timestamptz)'];
  v_leitura text[] := array[
    'public._agenda_material_modo()', 'public._agenda_fornecedor_curto(uuid)', 'public._agenda_remessa_quem(uuid, text, text)',
    'public._agenda_remessa_nota(uuid)', 'public._agenda_inicio_previsto(uuid, date)',
    'public._agenda_mudancas(date, date, boolean, boolean, timestamptz)'];
  v_ruins text := '';
begin
  v_res := pg_temp.ok(v_res, 'N0a agenda_rascunho_material: só a assinatura nova (p_aviso no fim); a de 11 argumentos saiu',
    to_regprocedure(c_nova) is not null
    and to_regprocedure('public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date)') is null
    and (select count(*) from pg_proc where proname = 'agenda_rascunho_material' and pronamespace = 'public'::regnamespace) = 1);
  v_res := pg_temp.ok(v_res, 'N0b a RPC do material: authenticated e service_role executam; anon nunca; definer com search_path',
    has_function_privilege('authenticated', c_nova, 'execute') and has_function_privilege('service_role', c_nova, 'execute')
    and not has_function_privilege('anon', c_nova, 'execute')
    and (select p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=%' from pg_proc p where p.oid = c_nova::regprocedure));
  foreach f in array v_so_service loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'N0c a remessa do e-mail, os passos notas e pix, a pergunta, o aviso e os *grava*: só service_role',
    v_ruins = '', nullif(v_ruins, ''));
  v_ruins := '';
  foreach f in array v_leitura loop
    if has_function_privilege('anon', f, 'execute') or not has_function_privilege('authenticated', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'N0d as leituras e os textos: authenticated (o painel) e service_role; nunca anon', v_ruins = '',
    nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'N0e security definer: só a remessa do e-mail e o *grava* do aviso (os passos, a pergunta e o resolvedor não)',
    (select bool_and(p.prosecdef = (p.proname in ('material_remessas_do_email', '_agenda_aplicar_aviso')))
       from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('material_remessas_do_email', '_agenda_aplicar_aviso', '_agenda_material_notas', '_agenda_material_pix',
                          '_agenda_material_perguntar', '_agenda_resolver_aviso', '_agenda_pix_fonte', '_agenda_material_em_falta',
                          '_agenda_inicio_previsto')));
  v_res := pg_temp.ok(v_res, 'N0f agenda_rascunho.tipo aceita aviso (a lista fechada ampliada)',
    (select pg_get_constraintdef(c.oid) like '%''aviso''%' from pg_constraint c
      where c.conrelid = 'public.agenda_rascunho'::regclass and c.conname = 'agenda_rascunho_tipo_check'));
  perform pg_temp.gravar(v_res);
end
$n0$;

-- ── N1 e N2. A remessa do e-mail ────────────────────────────────────────────────────────────────────────
do $n1$
declare
  v_res     jsonb := '[]'::jsonb;
  c_hoje    constant date := date '2026-10-30';
  c_e1      constant uuid := 'd4000000-0000-4000-8000-0000000003e1';
  c_e2      constant uuid := 'd4000000-0000-4000-8000-0000000003e2';
  c_kes     constant uuid := 'dd000000-0000-4000-8000-000000000002';
  c_toli    constant uuid := 'dd000000-0000-4000-8000-000000000006';
  c_ven     constant uuid := '05000000-0000-4000-8000-000000000069';
  c_kchave  constant text := '32261011222333000144550010000510381000000014';
  r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb;
  k public.material_remessas; co public.material_remessas; x public.material_remessas;
  v_foto text;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('N1 a remessa do e-mail (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');
    v_foto := pg_temp.foto_material();

    -- desligado: nada
    r1 := public.material_remessas_do_email(c_e1, c_hoje);
    v_res := pg_temp.ok(v_res, 'N1a modo_material desligado: {pulado} e nenhuma remessa',
      r1 = '{"pulado": true}'::jsonb and not exists (select 1 from public.material_remessas), r1::text);

    update public.agenda_config set modo_material = 'sombra' where id;
    r1 := public.material_remessas_do_email(c_e1, c_hoje);
    r2 := public.material_remessas_do_email(c_e2, c_hoje);
    r3 := public.material_remessas_do_email(c_e1, c_hoje);
    v_res := pg_temp.ok(v_res, 'N1b uma remessa por nota; o mesmo e-mail de novo não duplica (on conflict)',
      r1 = '{"criadas": 1, "ja_existiam": 0, "ignoradas": 0, "sem_itens": 0}'::jsonb
      and r2 ->> 'criadas' = '1' and r3 = '{"criadas": 0, "ja_existiam": 1, "ignoradas": 0, "sem_itens": 0}'::jsonb
      and (select count(*) from public.material_remessas) = 2, concat_ws(' | ', r1, r2, r3));

    select * into k from public.material_remessas where nfe_chave = c_kchave;
    v_res := pg_temp.ok(v_res, 'N1c Kamell 51038: o fornecedor pelo CNPJ (Vila Velha), outro estado, 4 dias úteis, a nota e o anexo, os itens, a caminho e sem resposta',
      k.fornecedor_id = c_kes and k.classe = 'outro_estado' and k.prazo_du = 4 and k.numero = '51038' and k.valor = 3054.44
      and k.emitente_uf = 'ES' and k.emitente_municipio = 'Vila Velha' and k.emitente_cnpj = '11222333000144' and k.mod_frete = '0'
      and k.email_message_id = c_e1 and k.email_attachment_id = 'd4000000-0000-4000-8000-0000000003a1'
      and k.itens = '[{"n": 1, "un": "UN", "qtd": 1, "descricao": "CENTRAL DE CONTROLE CERBO GX VICTRON ENERGY"}]'::jsonb
      and k.estado = 'a_caminho' and k.vinculo = 'sem_resposta' and k.os_ids = '{}' and k.respondida_em is null
      and k.fiscal_note_id is null, to_jsonb(k)::text);
    v_res := pg_temp.ok(v_res, 'N2 a previsão da Kamell: despacho seg 26/10 (a saída) + 4 dias úteis = sex 30/10',
      k.emitida_em = date '2026-10-26' and k.saida_em = date '2026-10-26' and k.despacho_em = date '2026-10-26'
      and k.previsao_ate = date '2026-10-30', concat_ws(' ', k.despacho_em, k.previsao_ate));

    select * into co from public.material_remessas where numero = '812';
    v_res := pg_temp.ok(v_res, 'N1d Correa 812, modFrete 9 (sem transporte): a previsão é o próprio despacho (qui 29/10), 0 dia útil',
      co.mod_frete = '9' and co.saida_em is null and co.despacho_em = date '2026-10-29' and co.previsao_ate = date '2026-10-29'
      and co.prazo_du = 0 and co.classe = 'entrega_local', to_jsonb(co)::text);

    -- Mais um e-mail: a saída noutro dia, a velha, a de outra empresa, a sem cadastro, a de extração antiga e o CNPJ com dois
    -- cadastros ativos.
    insert into public.suppliers (id, name, cnpj_cpf, city, state, active)
    values ('d4000000-0000-4000-8000-0000000003c1', 'KAMELL REPETIDA TESTE AG4', '11222333000144', 'Itajaí', 'SC', true);
    perform pg_temp.email('d4000000-0000-4000-8000-0000000003e3', jsonb_build_array(
      pg_temp.nfe('42261022333444000155550010000001231000000011', '22333444000155', '123', '2026-10-23', '2026-10-26', '0', 'PR', 'Curitiba'),
      pg_temp.nfe('42260922333444000155550010000001241000000012', '22333444000155', '124', '2026-09-20', '2026-09-20', '0', 'PR', 'Curitiba'),
      pg_temp.nfe('42261022333444000155550010000001251000000013', '22333444000155', '125', '2026-10-27', null, '0', 'PR', 'Curitiba', false),
      pg_temp.nfe('35261099888777000111550010000007771000000014', '99888777000111', '777', '2026-10-27', null, '0', 'SP', 'Sao Paulo'),
      pg_temp.nfe('32261011222333000144550010000510391000000015', '11.222.333/0001-44', '51039', '2026-10-28', null, null, null, null, true, false)));
    r4 := public.material_remessas_do_email('d4000000-0000-4000-8000-0000000003e3', c_hoje);
    v_res := pg_temp.ok(v_res, 'N1e a velha (antes de hoje − remessa_dias) e a de outra empresa ficam de fora; a de extração antiga entra sem itens',
      r4 = '{"criadas": 3, "ja_existiam": 0, "ignoradas": 2, "sem_itens": 1}'::jsonb
      and not exists (select 1 from public.material_remessas where numero in ('124', '125')), r4::text);
    select * into x from public.material_remessas where numero = '123';
    v_res := pg_temp.ok(v_res, 'N1f a saída (seg 26/10) vence a emissão (sex 23/10): a Toli (Curitiba/PR, 2 dias úteis) chega qua 28/10',
      x.fornecedor_id = c_toli and x.emitida_em = date '2026-10-23' and x.despacho_em = date '2026-10-26'
      and x.classe = 'distribuidor_sc_pr' and x.prazo_du = 2 and x.previsao_ate = date '2026-10-28', to_jsonb(x)::text);
    select * into x from public.material_remessas where numero = '777';
    v_res := pg_temp.ok(v_res, 'N1g sem cadastro (CNPJ que não casa): o prazo pela UF do XML (SP, outro estado): ter 27/10 + 4 dias úteis = ter 03/11 (Finados no meio)',
      x.fornecedor_id is null and x.classe = 'outro_estado' and x.prazo_du = 4 and x.emitente_uf = 'SP'
      and x.previsao_ate = date '2026-11-03' and public._agenda_remessa_nota(x.id) = 'nota 777 da Emitente (SP, sem cadastro)',
      concat_ws(' ', to_jsonb(x), public._agenda_remessa_nota(x.id)));
    select * into x from public.material_remessas where numero = '51039';
    v_res := pg_temp.ok(v_res, 'N1h o CNPJ com dois cadastros ativos: o principal (mais produtos e contas: a Kamell de Vila Velha); a extração antiga: sem itens nem saída',
      x.fornecedor_id = c_kes and x.itens = '[]'::jsonb and x.saida_em is null and x.mod_frete is null
      and x.previsao_ate = public.agenda_somar_du(date '2026-10-28', 4), to_jsonb(x)::text);

    -- A já importada pela tela, ligada à OS do Vanderlei na importação: nasce chegou e ligada.
    insert into public.fiscal_notes (id, nfe_key, nfe_number, status, confirmed_at, supplier_id)
    values ('d4000000-0000-4000-8000-0000000003f9', '42261044555666000177550010000008131000000047', '813', 'confirmed',
            timestamptz '2026-10-27 16:00-03', 'dd000000-0000-4000-8000-000000000008');
    insert into public.fiscal_note_items (fiscal_note_id, item_index, description, quantity, service_order_id)
    values ('d4000000-0000-4000-8000-0000000003f9', 1, 'PORTA FUSIVEL', 8, c_ven);
    perform pg_temp.email('d4000000-0000-4000-8000-0000000003e4', jsonb_build_array(
      pg_temp.nfe('42261044555666000177550010000008131000000047', '44555666000177', '813', '2026-10-26', null, '0', 'SC', 'Balneario Camboriu')));
    r5 := public.material_remessas_do_email('d4000000-0000-4000-8000-0000000003e4', c_hoje);
    select * into x from public.material_remessas where numero = '813';
    v_res := pg_temp.ok(v_res, 'N1i a nota já importada (fiscal_notes confirmada) nasce chegou (ter 27/10) e ligada à OS que a importação disse',
      r5 ->> 'criadas' = '1' and x.estado = 'chegou' and x.chegou_em = date '2026-10-27'
      and x.fiscal_note_id = 'd4000000-0000-4000-8000-0000000003f9' and x.vinculo = 'ligada' and x.os_ids = array[c_ven]
      and x.respondida_em is not null, to_jsonb(x)::text);

    v_res := pg_temp.ok(v_res, 'N1j nenhuma OS mudou: os_material igual, nenhuma pergunta e nenhuma ação de material',
      pg_temp.foto_material() = v_foto
      and not exists (select 1 from public.agenda_perguntas where tipo in ('nfe_vincular', 'pix_material'))
      and not exists (select 1 from public.agenda_acoes where tipo = 'material'));
    v_res := pg_temp.ok(v_res, 'N1k a remessa não se apaga',
      (select count(*) from public.material_remessas) = 6);

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$n1$;

-- ── N3 a N7. O fluxo em ligado: a pergunta, a resposta, "não é de serviço", a nota importada e o Pix ─────
do $n3$
declare
  v_res     jsonb := '[]'::jsonb;
  c_hoje    constant date := date '2026-10-30';
  c_agora   constant timestamptz := timestamptz '2026-10-30 10:00-03';
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_nel     constant uuid := '05000000-0000-4000-8000-000000000112';
  c_ven     constant uuid := '05000000-0000-4000-8000-000000000069';
  c_tx      constant uuid := 'd4000000-0000-4000-8000-0000000003b1';
  c_kchave  constant text := '32261011222333000144550010000510381000000014';
  r jsonb; rk public.material_remessas; rc public.material_remessas; q public.agenda_perguntas; qc public.agenda_perguntas;
  m public.os_material; a public.agenda_acoes;
  v_foto text; v_din text; v_rasc int; x jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('N3 a pergunta, a resposta e o Pix (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');
    update public.agenda_config set modo_material = 'ligado' where id;
    v_din := pg_temp.foto_dinheiro();
    perform public.material_remessas_do_email('d4000000-0000-4000-8000-0000000003e1', c_hoje);
    perform public.material_remessas_do_email('d4000000-0000-4000-8000-0000000003e2', c_hoje);
    select * into rk from public.material_remessas where nfe_chave = c_kchave;
    select * into rc from public.material_remessas where numero = '812';

    -- ── N3: a pergunta
    r := public._agenda_material_notas(c_hoje, c_agora);
    select * into q from public.agenda_perguntas where chave = 'nfe:' || rk.id;
    select * into qc from public.agenda_perguntas where chave = 'nfe:' || rc.id;
    v_res := pg_temp.ok(v_res, 'N3a uma pergunta por nota sem resposta com OS candidata (2), em ligado, nunca crítica',
      r = '{"chegaram": 0, "acoes": 0, "perguntas": 2, "resolvidas": 0, "modo": "ligado"}'::jsonb
      and q.tipo = 'nfe_vincular' and q.modo = 'ligado' and not q.critica and q.estado = 'aberta'
      and qc.tipo = 'nfe_vincular', r::text);
    v_res := pg_temp.ok(v_res, 'N3b o texto da Kamell: a nota, o despacho, a chegada pela previsão e as opções (fornecedor primeiro, depois o início)',
      q.texto = 'Chegou por e-mail a nota 51038 da Kamell, despachada seg 26/10: deve chegar por volta de sex 30/10. É material de qual serviço? 1) Nelson: Central de controle…; 2) Vanderlei: Kit Cabos/ Conectores/… e mais 3; 3) nenhum (estoque ou escritório). Me diga o número ou o nome.',
      q.texto);
    v_res := pg_temp.ok(v_res, 'N3c as opções: o Nelson (item da Kamell), o Vanderlei (começa ter 03/11), "nenhum"; as OS em os_ids; perda_em = o início mais cedo; vence em 7 dias',
      q.opcoes -> 0 ->> 'os' = c_nel::text and q.opcoes -> 1 ->> 'os' = c_ven::text and q.opcoes -> 2 ->> 'os' is null
      and q.opcoes -> 2 ->> 'texto' = 'nenhum (estoque ou escritório)' and jsonb_array_length(q.opcoes) = 3
      and q.os_ids = array[c_nel, c_ven] and q.service_order_id is null and q.perda_em = date '2026-11-03'
      and q.expira_em = c_agora + interval '7 days', concat_ws(' ', q.opcoes, q.os_ids, q.perda_em, q.expira_em));
    v_res := pg_temp.ok(v_res, 'N3d a Correa (modFrete 9): "sem frete (retirada na loja)"; só o Vanderlei tem como (o início) — nenhum item é da Correa nem tem palavra em comum',
      qc.texto = 'Chegou por e-mail a nota 812 da Correa, de qui 29/10, sem frete (retirada na loja). É material de qual serviço? 1) Vanderlei: Kit Cabos/ Conectores/… e mais 3; 2) nenhum (estoque ou escritório). Me diga o número ou o nome.'
      and qc.os_ids = array[c_ven], qc.texto);
    r := public._agenda_material_notas(c_hoje, c_agora + interval '15 minutes');
    v_res := pg_temp.ok(v_res, 'N3e uma vez: o tique seguinte não pergunta de novo',
      r ->> 'perguntas' = '0' and (select count(*) from public.agenda_perguntas where tipo = 'nfe_vincular') = 2, r::text);

    -- Sem OS candidata: o Vanderlei com o material na mão; uma nota nova da Correa não tem como ligar (nada em comum, ninguém
    -- começa logo) e não vira pergunta.
    begin
      update public.os_material set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = c_hoje
       where service_order_id = c_ven;
      perform pg_temp.email('d4000000-0000-4000-8000-0000000003e5', jsonb_build_array(
        pg_temp.nfe('42261044555666000177550010000008141000000050', '44555666000177', '814', '2026-10-30', null, '9', 'SC', 'Balneario Camboriu')));
      perform public.material_remessas_do_email('d4000000-0000-4000-8000-0000000003e5', c_hoje);
      r := public._agenda_material_notas(c_hoje, c_agora + interval '30 minutes');
      v_res := pg_temp.ok(v_res, 'N3f sem OS candidata, sem pergunta (a nota aparece no foco compras, P6)',
        r ->> 'perguntas' = '0'
        and not exists (select 1 from public.agenda_perguntas p join public.material_remessas x on p.chave = 'nfe:' || x.id
                         where x.numero = '814'), r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- O fechamento e a carona (o Vanderlei não tem pergunta das Fases 2–3; o Nelson tem a crítica "não cabe", que vem antes).
    x := (select l from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_hoje)) l where l ->> 'tipo' = 'pergunta' limit 1);
    v_res := pg_temp.ok(v_res, 'N3g o fechamento mostra uma das perguntas de nota (a que perde primeiro), em ligado, com as outras em *agenda pendências*',
      x ->> 'texto' like 'Agenda: Chegou por e-mail a nota %' and x ->> 'texto' like '%(e mais 1 em *agenda pendências*)'
      and x ->> 'modo' = 'ligado' and (x ->> 'pergunta_id')::uuid in (q.id, qc.id), x::text);
    -- (cada carona numa subtransação: a carona marca carona_em, e a da nota cita as duas OS)
    begin
      r := public.agenda_carona(c_admin, array['Vanderlei'], 'whatsapp', c_hoje, c_agora + interval '1 hour');
      v_res := pg_temp.ok(v_res, 'N3h de carona numa conversa sobre o Vanderlei (que está nas opções): a pergunta da nota',
        r ->> 'tipo' = 'nfe_vincular' and r ->> 'texto' like 'Aproveitando: Chegou por e-mail a nota %'
        and (r ->> 'pergunta_id')::uuid in (q.id, qc.id), r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      r := public.agenda_carona(c_admin, array['Nelson'], 'whatsapp', c_hoje, c_agora + interval '1 hour');
      v_res := pg_temp.ok(v_res, 'N3i a pergunta das Fases 2–3 vem antes (o Nelson: a crítica "não cabe")',
        r ->> 'tipo' = 'nao_cabe', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── N4: a resposta
    v_foto := pg_temp.foto_material();
    r := pg_temp.mat('Vanderlei', array['porta'], 'a_caminho', null, 'a nota é do Vanderlei', 'a nota');
    v_res := pg_temp.ok(v_res, 'N4a "a nota" com duas esperando (as duas citam o Vanderlei): a pergunta, e nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'texto' = 'Qual nota: a 51038 da Kamell ou a 812 da Correa?'
      and not exists (select 1 from public.agenda_rascunho where estado = 'aberto'), r::text);
    r := pg_temp.mat('Nelson', array['Cerbo'], 'a_caminho', null, 'a nota da Bosch é do Nelson', 'a nota da Bosch');
    v_res := pg_temp.ok(v_res, 'N4b "a nota da Bosch" (nenhuma é dela): não achei — nunca a da Kamell por eliminação',
      not (r ->> 'ok')::boolean
      and r ->> 'texto' = 'Não achei "a nota da Bosch" no que está esperando você: a nota 51038 da Kamell e a nota 812 da Correa.'
      and not exists (select 1 from public.agenda_rascunho where estado = 'aberto'), r::text);
    r := pg_temp.mat('Nelson', array['tudo'], 'a_caminho', null, 'a nota da Kamell é do Nelson', 'a nota da Kamell');
    v_res := pg_temp.ok(v_res, 'N4c "tudo" com a nota da Kamell: as linhas em falta do Nelson da Kamell ou sem fornecedor (o painel da AliExpress fica de fora)',
      r ->> 'releitura' = E'Entendi assim, confere?\n• Nelson (OS-00112): KIT Cabos Comunicação…, Central de controle… e Orion-Tr Smart 12/12-30A… a caminho pela nota 51038 da Kamell, chega por volta de sex 30/10.\nResponda *grava* ou corrija o que estiver errado.',
      r ->> 'releitura');
    perform pg_temp.descarta();
    r := pg_temp.mat('Nelson', array['Cerbo'], 'a_caminho', 'dia 3', 'a nota da Kamell é do Nelson, o Cerbo chega dia 3', 'a nota da Kamell');
    v_res := pg_temp.ok(v_res, 'N4d a data dita vence a da nota ("chega ter 03/11 (você disse)")',
      r ->> 'releitura' = E'Entendi assim, confere?\n• Nelson (OS-00112): Cerbo gx victron… a caminho pela nota 51038 da Kamell, chega ter 03/11 (você disse).\nResponda *grava* ou corrija o que estiver errado.',
      r ->> 'releitura');
    perform pg_temp.descarta();
    r := pg_temp.mat('Nelson', array['Cerbo'], 'a_caminho', null, 'a nota da Kamell é do Nelson, o Cerbo', 'a nota da Kamell');
    v_res := pg_temp.ok(v_res, 'N4e "a nota da Kamell é do Nelson, o Cerbo": a releitura diz a nota e a chegada dela',
      (r ->> 'ok')::boolean
      and r ->> 'releitura' = E'Entendi assim, confere?\n• Nelson (OS-00112): Cerbo gx victron… a caminho pela nota 51038 da Kamell, chega por volta de sex 30/10.\nResponda *grava* ou corrija o que estiver errado.',
      r ->> 'releitura');
    v_res := pg_temp.ok(v_res, 'N4f nada antes do *grava*: a linha, a nota e a pergunta como estavam (vínculo sempre pergunta)',
      pg_temp.foto_material() = v_foto
      and (select vinculo = 'sem_resposta' and os_ids = '{}' from public.material_remessas where id = rk.id)
      and (select estado = 'aberta' from public.agenda_perguntas where id = q.id));
    r := pg_temp.grava();
    select * into m from public.os_material where service_order_part_id = md5('peca:112:2')::uuid;
    v_res := pg_temp.ok(v_res, 'N4g o *grava*: o Cerbo a caminho pela nota (fonte nfe, a previsão da nota, comprado no dia da nota), a nota na linha e a evidência',
      (r ->> 'ok')::boolean and m.situacao = 'a_caminho' and m.fonte = 'nfe' and m.previsao_ate = date '2026-10-30'
      and m.previsao_fonte = 'nfe' and m.comprado_em = date '2026-10-26' and m.comprado_fonte = 'nfe' and m.remessa_id = rk.id
      and m.evidencia ->> 'vinculo_por' = 'dono' and m.evidencia ->> 'nfe_chave' = c_kchave
      and m.evidencia ->> 'email_attachment_id' = 'd4000000-0000-4000-8000-0000000003a1'
      and m.previsao_original = date '2026-10-30' and m.previsao_original_fonte = 'nfe',
      concat_ws(' | ', r ->> 'texto', to_jsonb(m) - 'historico'));
    v_res := pg_temp.ok(v_res, 'N4h a nota ficou ligada ao Nelson pelo dono e a pergunta respondida (opção 1, pelo WhatsApp, com as palavras dele)',
      (select vinculo = 'ligada' and os_ids = array[c_nel] and respondida_por = c_admin and respondida_em is not null
         from public.material_remessas where id = rk.id)
      and (select estado = 'respondida' and opcao_escolhida = 1 and respondida_via = 'whatsapp' and respondida_por = c_admin
                  and resposta = 'a nota da Kamell é do Nelson, o Cerbo'
             from public.agenda_perguntas where id = q.id));
    x := (select e from jsonb_array_elements(public.os_prontidao(c_nel, c_hoje) #> '{material,itens}') e
           where e ->> 'linha' = md5('peca:112:2')::uuid::text);
    v_res := pg_temp.ok(v_res, 'N4i na prontidão o Cerbo é nível B: "chega sex 30/10 (pela nota)"',
      x ->> 'nivel' = 'B' and x ->> 'data_texto' = 'chega sex 30/10 (pela nota)', x::text);

    -- ── N5: "não é de serviço"
    r := pg_temp.mat(null, null, 'nao_e_de_servico', null, 'não é de serviço', null);
    v_res := pg_temp.ok(v_res, 'N5a "não é de serviço" sem dizer qual: a pergunta, e nada entra',
      not (r ->> 'ok')::boolean and r ->> 'texto' = 'De qual nota, Pix ou mensagem? Diga como o fornecedor aparece ("a nota da Correa").',
      r::text);
    r := pg_temp.mat(null, null, 'nao_e_de_servico', null, 'essa nota da Correa não é de serviço', 'a nota da Correa');
    v_res := pg_temp.ok(v_res, 'N5b a releitura: "Nota 812 da Correa: não é material de serviço (estoque ou escritório). Não pergunto mais dela."',
      r ->> 'releitura' = E'Entendi assim, confere?\n• Nota 812 da Correa: não é material de serviço (estoque ou escritório). Não pergunto mais dela.\nResponda *grava* ou corrija o que estiver errado.'
      and (select tipo = 'aviso' and service_order_id is null from public.agenda_rascunho where estado = 'aberto'),
      r ->> 'releitura');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'N5c o *grava*: a nota fica sem serviço e a pergunta respondida ("nenhum"); nenhuma OS mudou',
      r ->> 'texto' = E'Gravado. Agora:\n• Nota 812 da Correa: não é material de serviço.'
      and (select vinculo = 'sem_servico' and os_ids = '{}' and respondida_em is not null from public.material_remessas where id = rc.id)
      and (select estado = 'respondida' and opcao_escolhida = 2 from public.agenda_perguntas where id = qc.id),
      r ->> 'texto');

    -- ── N7: o Pix
    r := public._agenda_material_pix(c_hoje, c_agora);
    select * into q from public.agenda_perguntas where chave = 'pix:tx:' || c_tx;
    v_res := pg_temp.ok(v_res, 'N7a o Pix de R$ 480,00 à Premel (sugerida pela fila financeira em "Peças e materiais") vira a pergunta sobre o Vanderlei (o fornecedor dele, começa ter 03/11)',
      r ->> 'perguntas' = '1'
      and q.texto = 'O Pix de R$ 480,00 à Premel (seg 26/10) é material do Vanderlei? Já está na mão?'
      and q.service_order_id = c_ven and q.os_ids = array[c_ven] and q.perda_em = date '2026-11-03' and q.modo = 'ligado'
      and not q.critica and q.expira_em = c_agora + interval '7 days', concat_ws(' | ', r, q.texto));
    r := pg_temp.mat('Vanderlei', array['tudo'], 'na_mao', null, 'o Pix da Premel é do Vanderlei, já tá aqui', 'o Pix da Premel', 'Premel');
    v_res := pg_temp.ok(v_res, 'N7b "o Pix da Premel é do Vanderlei, já tá aqui": os 4 itens na mão desde hoje (com o Pix na releitura)',
      r ->> 'releitura' = E'Entendi assim, confere?\n• Vanderlei (OS-00069): os 4 itens na mão desde hoje (Pix de R$ 480,00 à Premel, seg 26/10).\nResponda *grava* ou corrija o que estiver errado.',
      r ->> 'releitura');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'N7c o *grava*: as 4 linhas na mão (fonte pix, comprado no dia do Pix, chegou hoje, o Pix na evidência) e a pergunta respondida',
      (r ->> 'ok')::boolean
      and (select count(*) = 4 and bool_and(situacao = 'na_mao' and fonte = 'pix' and comprado_em = date '2026-10-26'
                  and comprado_fonte = 'pix' and chegou_em = c_hoje and evidencia ->> 'bank_transaction_id' = c_tx::text
                  and evidencia ->> 'vinculo_por' = 'dono')
             from public.os_material where service_order_id = c_ven)
      and (select estado = 'respondida' from public.agenda_perguntas where id = q.id), r ->> 'texto');
    v_res := pg_temp.ok(v_res, 'N7d DINHEIRO: o extrato, a fila financeira, as contas, os comprovantes, as cobranças e os pagamentos iguais (o Pix só é lido)',
      pg_temp.foto_dinheiro() = v_din);

    -- ── N6: a nota importada pela tela
    insert into public.fiscal_notes (id, nfe_key, nfe_number, status, confirmed_at, supplier_id)
    values ('d4000000-0000-4000-8000-0000000003f1', c_kchave, '51038', 'confirmed', timestamptz '2026-10-28 10:00-03',
            'dd000000-0000-4000-8000-000000000002');
    r := public._agenda_material_notas(c_hoje, timestamptz '2026-10-30 12:00-03');
    select * into a from public.agenda_acoes where tipo = 'material' and service_order_id = c_nel;
    select * into m from public.os_material where service_order_part_id = md5('peca:112:2')::uuid;
    v_res := pg_temp.ok(v_res, 'N6a a nota importada: a remessa chegou (qua 28/10) e o Cerbo ligado a ela fica na mão pela nota',
      r ->> 'chegaram' = '1' and r ->> 'acoes' = '1'
      and (select estado = 'chegou' and chegou_em = date '2026-10-28' and fiscal_note_id = 'd4000000-0000-4000-8000-0000000003f1'
             from public.material_remessas where id = rk.id)
      and m.situacao = 'na_mao' and m.fonte = 'nfe' and m.chegou_em = date '2026-10-28' and m.quantidade_na_mao = m.quantidade_necessaria,
      concat_ws(' | ', r, to_jsonb(m) - 'historico'));
    v_res := pg_temp.ok(v_res, 'N6b a ação material (origem nota) com o *desfaz*: o antes (a caminho) tirado antes da sincronização, o depois (na mão), a frase',
      a.origem = 'nota' and a.executada and a.os_ids = array[c_nel] and a.desfazivel_ate = timestamptz '2026-10-31 12:00-03'
      and a.antes -> 'linhas' -> 0 ->> 'situacao' = 'a_caminho' and a.depois -> 'linhas' -> 0 ->> 'situacao' = 'na_mao'
      and a.antes ->> 'remessa_id' = rk.id::text
      and a.texto = 'Nelson (OS-00112): a nota 51038 da Kamell entrou no estoque — Central de controle… está na mão. *desfaz OS-00112* volta como estava.',
      concat_ws(' | ', a.texto, a.desfazivel_ate, a.antes -> 'linhas' -> 0 ->> 'situacao'));
    v_res := pg_temp.ok(v_res, 'N6c a ação entra no "o que mudou" do fechamento e o *desfaz OS-00112* a acha',
      exists (select 1 from jsonb_array_elements(public._agenda_mudancas(c_hoje, c_hoje, true, true, timestamptz '2026-10-30 12:30-03')) g
               where g -> 'acao_ids' ? a.id::text and (g ->> 'desfazivel')::boolean)
      and public.agenda_acao_desfazivel('OS-00112', c_hoje, timestamptz '2026-10-30 12:30-03') ->> 'acao_id' = a.id::text);
    r := public._agenda_material_notas(c_hoje, timestamptz '2026-10-30 12:15-03');
    v_res := pg_temp.ok(v_res, 'N6d o tique seguinte não repete a chegada nem a ação',
      r ->> 'chegaram' = '0' and r ->> 'acoes' = '0' and (select count(*) from public.agenda_acoes where tipo = 'material') = 1, r::text);

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$n3$;

-- ── N6s. Em sombra: a pergunta não aparece, a nota importada só registra; o aviso de nota já importada ────────
do $n6$
declare
  v_res     jsonb := '[]'::jsonb;
  c_hoje    constant date := date '2026-10-30';
  c_agora   constant timestamptz := timestamptz '2026-10-30 10:00-03';
  c_nel     constant uuid := '05000000-0000-4000-8000-000000000112';
  c_kchave  constant text := '32261011222333000144550010000510381000000014';
  r jsonb; a public.agenda_acoes; m public.os_material; x jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('N6s a sombra (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');
    update public.agenda_config set modo_material = 'sombra' where id;
    perform public.material_remessas_do_email('d4000000-0000-4000-8000-0000000003e1', c_hoje);
    perform public.material_remessas_do_email('d4000000-0000-4000-8000-0000000003e2', c_hoje);
    r := public._agenda_material_notas(c_hoje, c_agora);
    x := (select l from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_hoje)) l
           where l ->> 'tipo' = 'pergunta' and l ->> 'texto' like 'Agenda: Chegou por e-mail%' limit 1);
    v_res := pg_temp.ok(v_res, 'N6e em sombra: as perguntas são gravadas em sombra e nunca vão ao dono (a linha do fechamento é sombra)',
      r ->> 'perguntas' = '2' and r ->> 'modo' = 'sombra'
      and (select bool_and(modo = 'sombra') from public.agenda_perguntas where tipo = 'nfe_vincular')
      and x ->> 'modo' = 'sombra'
      and public.agenda_carona('aa000000-0000-4000-8000-000000000001', array['Vanderlei'], 'whatsapp', c_hoje, c_agora) is null,
      concat_ws(' | ', r, x));

    -- O dono liga a nota pela conversa (vale em sombra: é o *grava* dele) e a tela importa.
    perform pg_temp.mat('Nelson', array['Cerbo'], 'a_caminho', null, 'a nota da Kamell é do Nelson, o Cerbo', 'a nota da Kamell');
    perform pg_temp.grava();
    insert into public.fiscal_notes (id, nfe_key, nfe_number, status, confirmed_at)
    values ('d4000000-0000-4000-8000-0000000003f1', c_kchave, '51038', 'confirmed', timestamptz '2026-10-28 10:00-03');
    r := public._agenda_material_notas(c_hoje, timestamptz '2026-10-30 12:00-03');
    select * into a from public.agenda_acoes where tipo = 'material';
    select * into m from public.os_material where service_order_part_id = md5('peca:112:2')::uuid;
    v_res := pg_temp.ok(v_res, 'N6f em sombra a nota importada: a remessa chegou, a ação fica executada = false (sem *desfaz*) e a linha NÃO muda',
      r ->> 'chegaram' = '1' and r ->> 'acoes' = '1' and not a.executada and a.desfazivel_ate is null
      and a.texto = 'Nelson (OS-00112): a nota 51038 da Kamell entrou no estoque — em teste, eu marcaria Central de controle… como na mão.'
      and a.depois -> 'linhas' -> 0 ->> 'situacao' = 'na_mao' and m.situacao = 'a_caminho' and m.fonte = 'nfe'
      and (select estado = 'chegou' from public.material_remessas where nfe_chave = c_kchave),
      concat_ws(' | ', r, a.texto, m.situacao));
    v_res := pg_temp.ok(v_res, 'N6g em sombra a ação aparece só no que a sombra teria feito (executada = false)',
      exists (select 1 from jsonb_array_elements(public._agenda_mudancas(c_hoje, c_hoje, false, false, null)) g where g -> 'acao_ids' ? a.id::text)
      and not exists (select 1 from jsonb_array_elements(public._agenda_mudancas(c_hoje, c_hoje, true, true, null)) g where g -> 'acao_ids' ? a.id::text));

    -- A nota da Correa importada antes de o dono responder: o aviso diz "na mão desde a importação".
    insert into public.fiscal_notes (id, nfe_key, nfe_number, status, confirmed_at)
    values ('d4000000-0000-4000-8000-0000000003f2', '42261044555666000177550010000008121000000023', '812', 'confirmed',
            timestamptz '2026-10-29 17:00-03');
    perform public._agenda_material_notas(c_hoje, timestamptz '2026-10-30 12:15-03');
    r := pg_temp.mat('Vanderlei', array['porta'], 'a_caminho', null, 'a nota da Correa é do Vanderlei, a porta fusível', 'a nota da Correa');
    v_res := pg_temp.ok(v_res, 'N6h a nota já importada: o aviso diz "na mão desde qui 29/10 (a nota 812 da Correa entrou no estoque)"',
      r ->> 'releitura' = E'Entendi assim, confere?\n• Vanderlei (OS-00069): Porta Fusível MIDI… na mão desde qui 29/10 (a nota 812 da Correa entrou no estoque).\nResponda *grava* ou corrija o que estiver errado.',
      r ->> 'releitura');

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$n6$;

-- ── N7. O Pix: o teto, a janela, o valor mínimo, a categoria, o início, o CMP e a limpeza ───────────────
do $n7$
declare
  v_res     jsonb := '[]'::jsonb;
  c_hoje    constant date := date '2026-10-30';
  c_agora   constant timestamptz := timestamptz '2026-10-30 10:00-03';
  c_ven     constant uuid := '05000000-0000-4000-8000-000000000069';
  c_premel  constant uuid := 'dd000000-0000-4000-8000-000000000001';
  c_tx      constant uuid := 'd4000000-0000-4000-8000-0000000003b1';
  r jsonb; r2 jsonb; v_din text; v_cat text;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('N7 o Pix (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');
    update public.agenda_config set modo_material = 'ligado' where id;
    -- Mais Pix: R$ 300,00 à Premel qua 28/10 (material); R$ 30,00 à Premel (abaixo do mínimo); R$ 500,00 à Premel ter 20/10
    -- (fora da janela de 7 dias); R$ 200,00 ao Mercado Pago em "Alimentação" (sem conta, produto nem categoria de
    -- material); R$ 3.054,44 à Kamell de Vila Velha (o item dela é do Nelson, que não tem início).
    insert into public.bank_transactions (id, transaction_date, description, amount, transaction_type, payment_method, provider, source_type)
    values ('d4000000-0000-4000-8000-0000000003b3', date '2026-10-28', 'PIX PREMEL', -300, 'debit', 'PIX', 'pluggy', 'bank'),
           ('d4000000-0000-4000-8000-0000000003b4', date '2026-10-29', 'PIX PREMEL', -30, 'debit', 'PIX', 'pluggy', 'bank'),
           ('d4000000-0000-4000-8000-0000000003b5', date '2026-10-20', 'PIX PREMEL', -500, 'debit', 'PIX', 'pluggy', 'bank'),
           ('d4000000-0000-4000-8000-0000000003b6', date '2026-10-29', 'PIX MERCADO PAGO', -200, 'debit', 'PIX', 'pluggy', 'bank'),
           ('d4000000-0000-4000-8000-0000000003b7', date '2026-10-29', 'PIX KAMELL', -3054.44, 'debit', 'PIX', 'pluggy', 'bank');
    insert into public.finance_review_queue (kind, status, bank_transaction_id, title, suggested_category, suggested_supplier_id)
    values ('create_payable', 'pending', 'd4000000-0000-4000-8000-0000000003b3', 'Pix', 'Peças e materiais', c_premel),
           ('create_payable', 'pending', 'd4000000-0000-4000-8000-0000000003b4', 'Pix', 'Peças e materiais', c_premel),
           ('create_payable', 'pending', 'd4000000-0000-4000-8000-0000000003b5', 'Pix', 'Peças e materiais', c_premel),
           ('create_payable', 'pending', 'd4000000-0000-4000-8000-0000000003b6', 'Pix', 'Alimentação', 'dd000000-0000-4000-8000-000000000007'),
           ('create_payable', 'approved', 'd4000000-0000-4000-8000-0000000003b7', 'Pix', 'Peças e materiais', 'dd000000-0000-4000-8000-000000000002');
    v_din := pg_temp.foto_dinheiro();

    -- O início depois de material_inicio_dias: em seg 26/10, com 7 dias, o Vanderlei (ter 03/11, 8 dias) fica de fora.
    update public.agenda_config set material_inicio_dias = 7 where id;
    r := public._agenda_material_pix(date '2026-10-26', timestamptz '2026-10-26 18:00-03');
    v_res := pg_temp.ok(v_res, 'N7e a OS que começa depois de material_inicio_dias não é candidata (seg 26/10, 7 dias: o Vanderlei começa ter 03/11)',
      r ->> 'perguntas' = '0' and r ->> 'candidatas' = '0', r::text);
    update public.agenda_config set material_inicio_dias = 14 where id;

    r := public._agenda_material_pix(c_hoje, c_agora);
    r2 := public._agenda_material_pix(c_hoje, c_agora + interval '15 minutes');
    v_res := pg_temp.ok(v_res, 'N7f no máximo 1 por semana NO TOTAL: de 2 Pix de material à Premel, 1 pergunta (o mais recente: R$ 300,00 de qua 28/10); o tique seguinte nada',
      r ->> 'perguntas' = '1' and r ->> 'candidatas' = '2' and (r ->> 'teto')::boolean and r2 ->> 'perguntas' = '0'
      and (select count(*) from public.agenda_perguntas where tipo = 'pix_material') = 1
      and exists (select 1 from public.agenda_perguntas where chave = 'pix:tx:d4000000-0000-4000-8000-0000000003b3'
                    and texto = 'O Pix de R$ 300,00 à Premel (qua 28/10) é material do Vanderlei? Já está na mão?'),
      concat_ws(' | ', r, r2));
    v_res := pg_temp.ok(v_res, 'N7g fora: abaixo do valor mínimo, fora da janela, sem categoria de material e a OS sem início (o Nelson, da Kamell)',
      not exists (select 1 from public.agenda_perguntas where chave in (
        'pix:tx:d4000000-0000-4000-8000-0000000003b4', 'pix:tx:d4000000-0000-4000-8000-0000000003b5',
        'pix:tx:d4000000-0000-4000-8000-0000000003b6', 'pix:tx:d4000000-0000-4000-8000-0000000003b7')));
    r := public._agenda_material_pix(date '2026-11-02', timestamptz '2026-11-02 10:00-03');
    v_res := pg_temp.ok(v_res, 'N7h na semana seguinte (seg 02/11) a outra vaga: o Pix de R$ 480,00 (ainda na janela); o de antes nunca volta',
      r ->> 'perguntas' = '1'
      and exists (select 1 from public.agenda_perguntas where chave = 'pix:tx:' || c_tx)
      and (select count(*) from public.agenda_perguntas where chave = 'pix:tx:d4000000-0000-4000-8000-0000000003b3') = 1, r::text);

    -- A limpeza: o material do Vanderlei chegou (o dono disse pela tela) — a pergunta aberta do Pix se resolve.
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-11-02'
     where service_order_id = c_ven;
    r := public._agenda_material_pix(date '2026-11-02', timestamptz '2026-11-02 10:15-03');
    v_res := pg_temp.ok(v_res, 'N7i a pergunta do Pix cuja OS não tem mais falta se resolve',
      r ->> 'resolvidas' = '2'
      and not exists (select 1 from public.agenda_perguntas where tipo = 'pix_material' and estado = 'aberta')
      and (select bool_and(resolvida_motivo = 'o material da OS não falta mais') from public.agenda_perguntas where tipo = 'pix_material'),
      r::text);
    v_res := pg_temp.ok(v_res, 'N7j DINHEIRO: os passos do Pix não mexeram em extrato, fila financeira, contas, comprovantes, cobranças nem pagamentos',
      pg_temp.foto_dinheiro() = v_din);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Revisão da Fase 4, C2 (R6): a Premel não tem produto nem conta de material — só a categoria da fila diz que o Pix é
  -- material. Com "PEÇAS E MATERIAIS" (ou "Compras de Mercadorias", como 3 da fila em produção) ele é; com "Alimentação",
  -- não. Antes, a comparação exata deixava o de maiúscula de fora.
  v_din := '';
  foreach v_cat in array array['PEÇAS E MATERIAIS', 'Compras de Mercadorias', 'Alimentação'] loop
    begin
      execute current_setting('agenda_teste.fase4');
      update public.agenda_config set modo_material = 'ligado' where id;
      update public.finance_review_queue set suggested_category = v_cat where id = 'd4000000-0000-4000-8000-0000000003b2';
      r := public._agenda_material_pix(c_hoje, c_agora);
      v_din := v_din || v_cat || '=' || coalesce(r ->> 'candidatas', '?') || '/' || coalesce(r ->> 'perguntas', '?') || ';';
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'N7k a categoria da fila sem maiúscula nem acento: "PEÇAS E MATERIAIS" e "Compras de Mercadorias" fazem do Pix da Premel material (1 candidata, 1 pergunta); "Alimentação", não',
    v_din = 'PEÇAS E MATERIAIS=1/1;Compras de Mercadorias=1/1;Alimentação=0/0;', v_din);

  -- O CMP com o destino que o dono deu: a pergunta só pergunta se está na mão; o Pix do mesmo dinheiro não pergunta de novo.
  begin
    execute current_setting('agenda_teste.fase4');
    update public.agenda_config set modo_material = 'ligado' where id;
    insert into public.comprovantes (id, numero, supplier_id, fornecedor_nome, valor, data_compra, destino, destino_os_id, situacao)
    values ('d4000000-0000-4000-8000-0000000003d1', 12, c_premel, 'PREMEL', 480.00, date '2026-10-26', 'os', c_ven, 'lido');
    r := public._agenda_material_pix(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'N7k o CMP com destino a OS: "O CMP-00012 (R$ 480,00 à Premel) é do Vanderlei, você disse. O material já está na mão?"; o Pix do mesmo dinheiro conta pelo CMP',
      r ->> 'perguntas' = '1' and r ->> 'candidatas' = '1'
      and exists (select 1 from public.agenda_perguntas where chave = 'pix:cmp:d4000000-0000-4000-8000-0000000003d1'
                    and texto = 'O CMP-00012 (R$ 480,00 à Premel) é do Vanderlei, você disse. O material já está na mão?')
      and not exists (select 1 from public.agenda_perguntas where chave = 'pix:tx:' || c_tx), r::text);
    r := pg_temp.mat('Vanderlei', array['tudo'], 'comprei', null, 'o comprovante da Premel é do Vanderlei, comprei', 'o comprovante da Premel');
    v_res := pg_temp.ok(v_res, 'N7l a resposta pelo comprovante: comprado no dia do CMP, com o comprovante na releitura',
      (r ->> 'ok')::boolean and r ->> 'releitura' like E'Entendi assim, confere?\n• Vanderlei (OS-00069): os 4 itens comprado em seg 26/10 (comprovante CMP-00012, R$ 480,00 à Premel, seg 26/10).%',
      r ->> 'releitura');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$n7$;

-- ── N8. Desligado = nada ────────────────────────────────────────────────────────────────────────────────
do $n8$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-30';
  r jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('N8 desligado (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');
    update public.agenda_config set modo_material = 'desligado' where id;
    v_res := pg_temp.ok(v_res, 'N8a desligado: a remessa, os passos notas e pix pulam; a pergunta não grava',
      public.material_remessas_do_email('d4000000-0000-4000-8000-0000000003e1', c_hoje) = '{"pulado": true}'::jsonb
      and public._agenda_material_notas(c_hoje, now()) = '{"pulado": true}'::jsonb
      and public._agenda_material_pix(c_hoje, now()) = '{"pulado": true}'::jsonb
      and not public._agenda_material_perguntar('nfe_vincular', 'nfe:teste-ag4', null, null, null, null, 'TESTE AG4 pergunta', '[]', now())
      and not exists (select 1 from public.material_remessas) and not exists (select 1 from public.agenda_perguntas where tipo = 'nfe_vincular'));
    r := pg_temp.mat('Nelson', array['Cerbo'], 'a_caminho', null, 'a nota da Kamell é do Nelson', 'a nota da Kamell');
    v_res := pg_temp.ok(v_res, 'N8b desligado: o aviso não acha nada ("Não tenho nota, Pix nem mensagem de fornecedor esperando você agora.")',
      not (r ->> 'ok')::boolean and r ->> 'texto' = 'Não tenho nota, Pix nem mensagem de fornecedor esperando você agora.', r::text);
    r := pg_temp.mat('Nelson', array['painel'], 'na_mao', null, 'o painel chegou', null);
    v_res := pg_temp.ok(v_res, 'N8c sem o aviso, material_informar é o da Fase 1 (a mesma releitura)',
      r ->> 'releitura' = E'Entendi assim, confere?\n• Nelson (OS-00112): Painel Touch de… na mão (desde hoje).\nResponda *grava* ou corrija o que estiver errado.',
      r ->> 'releitura');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$n8$;

-- ── N9. As cópias: fora dos blocos "-- FASE 4:", iguais às da migration de onde vieram ─────────────────
do $n9$
declare
  v_f1 text := current_setting('agenda_teste.mig_rascunho_fase1', true);
  v_p1 text := current_setting('agenda_teste.mig_fornecedores_fase4', true);
  v_f3 text := current_setting('agenda_teste.mig_acompanhamento_fase3', true);
  v_ruins text := '';
  f record;
begin
  if coalesce(v_f1, '') = '' or coalesce(v_p1, '') = '' or coalesce(v_f3, '') = '' then
    insert into _resultado values ('N9 as cópias só acrescentam os blocos "-- FASE 4:"', true,
      'PULADO: sem agenda_teste.mig_rascunho_fase1/mig_fornecedores_fase4/mig_acompanhamento_fase3 (rode pela bancada)');
    return;
  end if;
  for f in select * from (values
      ('agenda_rascunho_material', 'public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date, text)', v_f1),
      ('_agenda_aplicar_material', 'public._agenda_aplicar_material(uuid, uuid, jsonb, text, date)', v_f1),
      ('_agenda_rascunho_frase', 'public._agenda_rascunho_frase(text, jsonb)', v_p1),
      ('agenda_rascunho_gravar', 'public.agenda_rascunho_gravar(uuid, date)', v_p1),
      ('agenda_carona', 'public.agenda_carona(uuid, text[], text, date, timestamptz)', v_f3),
      ('_agenda_mudancas', 'public._agenda_mudancas(date, date, boolean, boolean, timestamptz)', v_f3)) as x(nome, sig, mig) loop
    if pg_temp.sem_fase4(pg_temp.corpo(f.mig, f.nome))
         -- (Fase 5, P5) _agenda_rascunho_frase e _agenda_mudancas recriadas de novo em 20261028100500: os blocos da Fase 5
         -- saem antes (o L8 do agenda_fase5_leituras.sql confere as cópias da Fase 5)
         is distinct from pg_temp.sem_fase4(array_to_string(pg_temp.sem_fase5(
                            (select p.prosrc from pg_proc p where p.oid = f.sig::regprocedure)), E'\n'))
       or (select p.prosrc from pg_proc p where p.oid = f.sig::regprocedure) !~ '-- FASE 4: \(P3\)|-- FASE 4: o aviso|-- FASE 4: "não é de serviço"|-- FASE 4: o que o aviso|-- FASE 4: \(P3\) sem pergunta'
    then
      v_ruins := v_ruins || f.nome || ' ';
    end if;
  end loop;
  insert into _resultado values ('N9 as 6 cópias só acrescentam os blocos "-- FASE 4:" (e têm o bloco do P3)', v_ruins = '',
    nullif(v_ruins, ''));
end
$n9$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
