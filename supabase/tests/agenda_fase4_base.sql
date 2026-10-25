-- Prova da base da Agenda de Produção, Fase 4 (pacote P1): os parâmetros e os modos novos, o prazo dito por fornecedor, o
-- vínculo de linha da OC, as 3 tabelas do material, o original da previsão, o prazo do fornecedor numa fonte só, a
-- prontidão que o usa e o rascunho do fornecedor (migrations 20261027100000 e 20261027100100).
-- bancada: depende de 20261027100100
--
--   B1 colunas, DEFAULTs e CHECKs (agenda_config, suppliers, purchase_order_items, os_material, as 3 tabelas, as listas
--      fechadas ampliadas); os registros não se apagam e só mudam no estado
--   B2 RLS e privilégios das 3 tabelas e das funções (anon nada; o técnico 42501 no rascunho e nada nas tabelas)
--   B3 as chaves de modalidade são as de agenda_config.prazo_classe_du (+ importacao)
--   B4 o gatilho do original em todos os caminhos de escrita (insert com previsão, update, troca de previsão, volta a
--      faltar, compra nova, a escrita das Fases 1–3 sem a fonte, a sincronização pela OC)
--   B5 _agenda_prazo_do_fornecedor: dono > cadastro repetido > nome > cidade com U+FFFD > UF > sem lugar (a Kamell de Vila
--      Velha principal e a de Itajaí sem classe; a inativa vale como a ativa), e o lugar tolerante
--   B6 _agenda_chegada_estimada: dias úteis com Finados (02/11) e Consciência Negra (20/11); importado em corridos; classe
--      nula
--   B7 os_prontidao com o prazo dito (Premel balcão → "se comprar hoje" = hoje), o importado e a cópia que só muda nos
--      blocos "-- FASE 4:" (contra a 20261025100200)
--   B8 o rascunho do fornecedor (número não dito recusa; ambíguo pergunta; o lugar desfaz a ambiguidade; mesmo_que copia;
--      corridos convertidos; o *grava* aplica e resolve as perguntas de cadastro) e as cópias de agenda_rascunho_gravar e
--      _agenda_rascunho_frase
--   B9 a view das OCs vivas com oc_viva_dias (59 dias abate, 61 não)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase4_base.sql
--   Seguro em produção: as linhas de teste ("TESTE AG4") só são inseridas; termina em ROLLBACK. B5–B8 rodam só na bancada
--   (a fixture-fase4; fora dela, PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Executa um comando e diz que porta o recusou: o nome do CHECK, do índice único ou da FK; 'aceitou' quando entrou (e
-- desfaz); 'erro <estado>: <mensagem>' para o resto.
create function pg_temp.recusa(p_sql text) returns text language plpgsql as $f$
declare
  v_nome text; v_estado text; v_msg text;
begin
  begin
    execute p_sql;
    raise exception using errcode = 'P0001', message = '__aceitou__';
  exception when others then
    get stacked diagnostics v_nome = constraint_name, v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg = '__aceitou__' then return 'aceitou'; end if;
    if v_estado in ('23514', '23505', '23503', '23502', '23P01') then return coalesce(nullif(v_nome, ''), v_estado); end if;
    return 'erro ' || v_estado || ': ' || v_msg;
  end;
end $f$;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou 'erro <estado>: <mensagem>'.
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- O corpo (entre "as $function$" e "$function$;") de uma função numa migration.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'as $function$\n' in v) + length(E'as $function$'));
  return left(v, position(E'\n$function$;' in v));
end $f$;

-- O corpo de agora sem os blocos "-- FASE 4: … -- FASE 4: fim" (linhas).
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

-- ── B1. Colunas, DEFAULTs e CHECKs ──────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B1a agenda_config: os 3 modos nascem desligado na linha e o DEFAULT da coluna é sombra; os 24 parâmetros com o valor da spec (e o detector_modelo_max da C1, 5)',
       c.modo_material = 'desligado' and c.modo_detector = 'desligado' and c.modo_fornecedor = 'desligado'
       and (select count(*) from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = 'public.agenda_config'::regclass
               and a.attname in ('modo_material', 'modo_detector', 'modo_fornecedor')
               and pg_get_expr(d.adbin, d.adrelid) like '''sombra''%') = 3
       and c.oc_viva_dias = 60 and c.remessa_dias = 30 and c.material_inicio_dias = 14
       and c.material_pergunta_validade = interval '7 days' and c.nfe_opcoes_max = 3 and c.pix_janela_dias = 7
       and c.pix_valor_minimo = 50 and c.pix_perguntas_semana_max = 1
       and c.pix_categorias = array['Peças e materiais', 'Compras de mercadorias', 'Materiais e Insumos Operacionais']
       and c.prazo_longo_du = 10 and c.detector_janela_horas = 48 and c.detector_lote_max = 100
       and c.detector_precisao_minima = 0.70 and c.detector_minimo_julgados = 5 and c.detector_tolerancia_du = 1
       and c.detector_modelo_max = 5
       and c.fornecedor_janela_inicio = time '08:00' and c.fornecedor_janela_fim = time '18:00' and not c.fornecedor_sabado
       and c.fornecedor_dia_max = 1 and c.fornecedor_semana_max = 2 and c.fornecedor_total_dia_max = 5
       and c.fornecedor_conversa_dias = 90 and c.fornecedores_principais_max = 15
       -- os prazos por classe continuam só na Fase 1 (nenhum prazo novo)
       and c.prazo_classe_du = '{"balcao":0,"entrega_local":1,"distribuidor_sc_pr":2,"outro_estado":4,"marketplace":3}'::jsonb
       and c.importacao_dias = 20,
       to_jsonb(c)::text
  from public.agenda_config c;

create temp table _casos (grupo text, nome text, sql text, espera text) on commit drop;
insert into _casos values
  ('config', 'modo_material', $q$update public.agenda_config set modo_material = 'x'$q$, 'agenda_config_modo_material_check'),
  ('config', 'modo_detector', $q$update public.agenda_config set modo_detector = 'x'$q$, 'agenda_config_modo_detector_check'),
  ('config', 'modo_fornecedor', $q$update public.agenda_config set modo_fornecedor = 'x'$q$, 'agenda_config_modo_fornecedor_check'),
  ('config', 'oc_viva_dias 13', $q$update public.agenda_config set oc_viva_dias = 13$q$, 'agenda_config_oc_viva_dias_check'),
  ('config', 'remessa_dias 121', $q$update public.agenda_config set remessa_dias = 121$q$, 'agenda_config_remessa_dias_check'),
  ('config', 'material_inicio_dias 6', $q$update public.agenda_config set material_inicio_dias = 6$q$, 'agenda_config_material_inicio_dias_check'),
  ('config', 'material_pergunta_validade 15 dias', $q$update public.agenda_config set material_pergunta_validade = '15 days'$q$, 'agenda_config_material_pergunta_validade_check'),
  ('config', 'nfe_opcoes_max 0', $q$update public.agenda_config set nfe_opcoes_max = 0$q$, 'agenda_config_nfe_opcoes_max_check'),
  ('config', 'pix_janela_dias 31', $q$update public.agenda_config set pix_janela_dias = 31$q$, 'agenda_config_pix_janela_dias_check'),
  ('config', 'pix_valor_minimo 1001', $q$update public.agenda_config set pix_valor_minimo = 1001$q$, 'agenda_config_pix_valor_minimo_check'),
  ('config', 'pix_perguntas_semana_max 6', $q$update public.agenda_config set pix_perguntas_semana_max = 6$q$, 'agenda_config_pix_perguntas_semana_max_check'),
  ('config', 'pix_categorias vazia', $q$update public.agenda_config set pix_categorias = '{}'$q$, 'agenda_config_pix_categorias_check'),
  ('config', 'prazo_longo_du 4', $q$update public.agenda_config set prazo_longo_du = 4$q$, 'agenda_config_prazo_longo_du_check'),
  ('config', 'detector_janela_horas 97', $q$update public.agenda_config set detector_janela_horas = 97$q$, 'agenda_config_detector_janela_horas_check'),
  ('config', 'detector_lote_max 9', $q$update public.agenda_config set detector_lote_max = 9$q$, 'agenda_config_detector_lote_max_check'),
  ('config', 'detector_precisao_minima 0,96', $q$update public.agenda_config set detector_precisao_minima = 0.96$q$, 'agenda_config_detector_precisao_minima_check'),
  ('config', 'detector_minimo_julgados 2', $q$update public.agenda_config set detector_minimo_julgados = 2$q$, 'agenda_config_detector_minimo_julgados_check'),
  ('config', 'detector_tolerancia_du 4', $q$update public.agenda_config set detector_tolerancia_du = 4$q$, 'agenda_config_detector_tolerancia_du_check'),
  ('config', 'detector_modelo_max 21', $q$update public.agenda_config set detector_modelo_max = 21$q$, 'agenda_config_detector_modelo_max_check'),
  ('config', 'fornecedor_janela_inicio 06:59', $q$update public.agenda_config set fornecedor_janela_inicio = '06:59'$q$, 'agenda_config_fornecedor_janela_inicio_check'),
  ('config', 'fornecedor_janela_fim 19:01', $q$update public.agenda_config set fornecedor_janela_fim = '19:01'$q$, 'agenda_config_fornecedor_janela_fim_check'),
  ('config', 'fornecedor_dia_max 3', $q$update public.agenda_config set fornecedor_dia_max = 3$q$, 'agenda_config_fornecedor_dia_max_check'),
  ('config', 'fornecedor_semana_max 0', $q$update public.agenda_config set fornecedor_semana_max = 0$q$, 'agenda_config_fornecedor_semana_max_check'),
  ('config', 'fornecedor_total_dia_max 21', $q$update public.agenda_config set fornecedor_total_dia_max = 21$q$, 'agenda_config_fornecedor_total_dia_max_check'),
  ('config', 'fornecedor_conversa_dias 366', $q$update public.agenda_config set fornecedor_conversa_dias = 366$q$, 'agenda_config_fornecedor_conversa_dias_check'),
  ('config', 'fornecedores_principais_max 31', $q$update public.agenda_config set fornecedores_principais_max = 31$q$, 'agenda_config_fornecedores_principais_max_check'),
  ('config', 'limites que entram (14, 180, 0, 1000, 07:00, 19:00, 0 dias de conversa)',
   $q$update public.agenda_config set oc_viva_dias = 180, pix_valor_minimo = 1000, pix_perguntas_semana_max = 0,
        fornecedor_janela_inicio = '07:00', fornecedor_janela_fim = '19:00', fornecedor_conversa_dias = 0$q$, 'aceitou'),
  -- suppliers (a Premel da fixture de 23/10)
  ('fornecedor', 'modalidade fora da lista', $q$update public.suppliers set modalidade = 'loja', prazo_fonte = 'dono' where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'suppliers_modalidade_check'),
  ('fornecedor', 'fonte sem modalidade', $q$update public.suppliers set prazo_fonte = 'dono' where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'suppliers_prazo_coerente'),
  ('fornecedor', 'modalidade sem fonte', $q$update public.suppliers set modalidade = 'balcao' where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'suppliers_prazo_coerente'),
  ('fornecedor', 'prazo sem modalidade (a correção sobre a spec)', $q$update public.suppliers set prazo_dias_uteis = 3 where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'suppliers_prazo_coerente'),
  ('fornecedor', 'corridos sem modalidade', $q$update public.suppliers set prazo_dias_corridos = 20 where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'suppliers_prazo_coerente'),
  ('fornecedor', 'importado com dias úteis', $q$update public.suppliers set modalidade = 'importacao', prazo_fonte = 'dono', prazo_dias_uteis = 3 where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'suppliers_prazo_coerente'),
  ('fornecedor', 'outro estado com corridos', $q$update public.suppliers set modalidade = 'outro_estado', prazo_fonte = 'dono', prazo_dias_corridos = 10 where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'suppliers_prazo_coerente'),
  ('fornecedor', '61 dias úteis', $q$update public.suppliers set modalidade = 'outro_estado', prazo_fonte = 'dono', prazo_dias_uteis = 61 where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'suppliers_prazo_coerente'),
  ('fornecedor', '0 dia corrido', $q$update public.suppliers set modalidade = 'importacao', prazo_fonte = 'dono', prazo_dias_corridos = 0 where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'suppliers_prazo_coerente'),
  ('fornecedor', 'fonte fora da lista', $q$update public.suppliers set modalidade = 'balcao', prazo_fonte = 'chute' where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'suppliers_prazo_fonte_check'),
  ('fornecedor', 'trecho de 301', $q$update public.suppliers set prazo_trecho = repeat('x', 301) where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'suppliers_prazo_trecho_check'),
  ('fornecedor', 'outro estado, 4 dias, o dono', $q$update public.suppliers set modalidade = 'outro_estado', prazo_fonte = 'dono', prazo_dias_uteis = 4 where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'aceitou'),
  ('fornecedor', 'importado, 30 corridos, medido', $q$update public.suppliers set modalidade = 'importacao', prazo_fonte = 'medido', prazo_dias_corridos = 30 where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'aceitou'),
  ('fornecedor', 'balcão, 0 dia, o dono', $q$update public.suppliers set modalidade = 'balcao', prazo_fonte = 'dono', prazo_dias_uteis = 0 where id = 'dd000000-0000-4000-8000-000000000001'$q$, 'aceitou'),
  -- a linha da OC (OC-00004 da fixture de 23/10)
  ('oc', 'os dois vínculos de linha', $q$update public.purchase_order_items set service_order_part_id = md5('peca:112:1')::uuid, service_order_service_id = (select s.id from public.service_order_services s order by s.id limit 1) where id = '71000000-0000-4000-8000-000000000001'$q$, 'poi_um_vinculo_de_linha'),
  ('oc', 'um vínculo de linha', $q$update public.purchase_order_items set service_order_service_id = (select s.id from public.service_order_services s order by s.id limit 1) where id = '71000000-0000-4000-8000-000000000001'$q$, 'aceitou'),
  ('oc', 'peça que não existe', $q$update public.purchase_order_items set service_order_part_id = 'd4000000-0000-4000-8000-0000000000ff' where id = '71000000-0000-4000-8000-000000000001'$q$, 'purchase_order_items_service_order_part_id_fkey'),
  -- os_material (a linha de teste d4…d1)
  ('material', 'comprado_fonte fora da lista', $q$update public.os_material set comprado_fonte = 'x' where id = 'd4000000-0000-4000-8000-0000000000d1'$q$, 'os_material_comprado_fonte_check'),
  ('material', 'fonte do original fora da lista', $q$update public.os_material set previsao_original = '2026-11-01', previsao_original_fonte = 'x' where id = 'd4000000-0000-4000-8000-0000000000d1'$q$, 'os_material_previsao_original_fonte_check'),
  ('material', 'fonte do original sem o original', $q$update public.os_material set previsao_original_fonte = 'dono' where id = 'd4000000-0000-4000-8000-0000000000d1'$q$, 'os_material_original_coerente'),
  ('material', 'remessa que não existe', $q$update public.os_material set remessa_id = 'd4000000-0000-4000-8000-0000000000ff' where id = 'd4000000-0000-4000-8000-0000000000d1'$q$, 'os_material_remessa_id_fkey'),
  -- material_remessas (a de teste d4…a1)
  ('remessa', 'chave que não tem 44 dígitos', $q$insert into public.material_remessas (nfe_chave, emitida_em) values ('123', '2026-10-26')$q$, 'material_remessas_nfe_chave_check'),
  ('remessa', 'chave repetida', $q$insert into public.material_remessas (nfe_chave, emitida_em) values (repeat('4', 44), '2026-10-26')$q$, 'material_remessas_nfe_chave_key'),
  ('remessa', 'CNPJ torto', $q$insert into public.material_remessas (nfe_chave, emitida_em, emitente_cnpj) values (repeat('5', 44), '2026-10-26', '12.345')$q$, 'material_remessas_emitente_cnpj_check'),
  ('remessa', 'UF minúscula', $q$insert into public.material_remessas (nfe_chave, emitida_em, emitente_uf) values (repeat('5', 44), '2026-10-26', 'sc')$q$, 'material_remessas_emitente_uf_check'),
  ('remessa', 'frete de dois dígitos', $q$insert into public.material_remessas (nfe_chave, emitida_em, mod_frete) values (repeat('5', 44), '2026-10-26', '10')$q$, 'material_remessas_mod_frete_check'),
  ('remessa', '41 itens', $q$insert into public.material_remessas (nfe_chave, emitida_em, itens) values (repeat('5', 44), '2026-10-26', (select jsonb_agg(jsonb_build_object('n', g)) from generate_series(1, 41) g))$q$, 'material_remessas_itens_check'),
  ('remessa', 'sem emissão', $q$insert into public.material_remessas (nfe_chave) values (repeat('5', 44))$q$, '23502'),
  ('remessa', 'estado fora da lista', $q$update public.material_remessas set estado = 'x' where id = 'd4000000-0000-4000-8000-0000000000a1'$q$, 'material_remessas_estado_check'),
  ('remessa', 'vínculo fora da lista', $q$update public.material_remessas set vinculo = 'x' where id = 'd4000000-0000-4000-8000-0000000000a1'$q$, 'material_remessas_vinculo_check'),
  ('remessa', 'chegou sem o dia', $q$update public.material_remessas set estado = 'chegou' where id = 'd4000000-0000-4000-8000-0000000000a1'$q$, 'remessa_chegou_tem_data'),
  ('remessa', 'ligada sem OS', $q$update public.material_remessas set vinculo = 'ligada', respondida_em = now() where id = 'd4000000-0000-4000-8000-0000000000a1'$q$, 'remessa_ligada_tem_os'),
  ('remessa', 'respondida sem a hora', $q$update public.material_remessas set vinculo = 'sem_servico' where id = 'd4000000-0000-4000-8000-0000000000a1'$q$, 'remessa_resposta_coerente'),
  ('remessa', '21 entradas no histórico', $q$update public.material_remessas set historico = (select jsonb_agg(jsonb_build_object('n', g)) from generate_series(1, 21) g) where id = 'd4000000-0000-4000-8000-0000000000a1'$q$, 'material_remessas_historico_check'),
  ('remessa', 'ligada ao Nelson, respondida', $q$update public.material_remessas set vinculo = 'ligada', os_ids = array['05000000-0000-4000-8000-000000000112'::uuid], respondida_em = now() where id = 'd4000000-0000-4000-8000-0000000000a1'$q$, 'aceitou'),
  ('remessa', 'a chave não muda', $q$update public.material_remessas set nfe_chave = repeat('6', 44) where id = 'd4000000-0000-4000-8000-0000000000a1'$q$, 'erro P0001: A nota registrada não muda: só o estado, o vínculo, a resposta, a chegada e o prazo.'),
  ('remessa', 'não se apaga', $q$delete from public.material_remessas where id = 'd4000000-0000-4000-8000-0000000000a1'$q$, 'erro P0001: O registro da agenda não se apaga.'),
  -- material_sinais (a mensagem de teste d4…b1)
  ('sinal', 'direção fora da lista', $q$insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo) values ('d4000000-0000-4000-8000-0000000000b1', 'x', now(), '2026-10-13', 'chegada', 'Já foi coletado', 'sombra')$q$, 'material_sinais_direcao_check'),
  ('sinal', 'tipo fora da lista', $q$insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo) values ('d4000000-0000-4000-8000-0000000000b1', 'recebida', now(), '2026-10-13', 'x', 'Já foi coletado', 'sombra')$q$, 'material_sinais_tipo_check'),
  ('sinal', 'trecho de 2', $q$insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo) values ('d4000000-0000-4000-8000-0000000000b1', 'recebida', now(), '2026-10-13', 'chegada', 'ok', 'sombra')$q$, 'material_sinais_trecho_check'),
  ('sinal', 'expressão de 61', $q$insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo, expressao) values ('d4000000-0000-4000-8000-0000000000b1', 'recebida', now(), '2026-10-13', 'chegada', 'Já foi coletado', 'sombra', repeat('x', 61))$q$, 'material_sinais_expressao_check'),
  ('sinal', 'modo desligado', $q$insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo) values ('d4000000-0000-4000-8000-0000000000b1', 'recebida', now(), '2026-10-13', 'chegada', 'Já foi coletado', 'desligado')$q$, 'material_sinais_modo_check'),
  ('sinal', 'casou por fora da lista', $q$insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo, casou_por) values ('d4000000-0000-4000-8000-0000000000b1', 'recebida', now(), '2026-10-13', 'chegada', 'Já foi coletado', 'sombra', 'chute')$q$, 'material_sinais_casou_por_check'),
  ('sinal', 'confiança 1,5', $q$insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo, modelo_confianca) values ('d4000000-0000-4000-8000-0000000000b1', 'recebida', now(), '2026-10-13', 'chegada', 'Já foi coletado', 'sombra', 1.5)$q$, 'material_sinais_modelo_confianca_check'),
  ('sinal', 'faixa ao contrário', $q$insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo, data_de, data_ate) values ('d4000000-0000-4000-8000-0000000000b1', 'recebida', now(), '2026-10-13', 'chegada', 'Já foi coletado', 'sombra', '2026-10-15', '2026-10-14')$q$, 'sinal_faixa_coerente'),
  ('sinal', 'julgado sem a hora', $q$insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo, julgamento) values ('d4000000-0000-4000-8000-0000000000b1', 'recebida', now(), '2026-10-13', 'chegada', 'Já foi coletado', 'sombra', 'certo')$q$, 'sinal_julgado_coerente'),
  ('sinal', 'julgamento fora da lista', $q$insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo, julgamento, julgado_em) values ('d4000000-0000-4000-8000-0000000000b1', 'recebida', now(), '2026-10-13', 'chegada', 'Já foi coletado', 'sombra', 'talvez', now())$q$, 'material_sinais_julgamento_check'),
  ('sinal', 'a mesma mensagem e tipo', $q$insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo) values ('d4000000-0000-4000-8000-0000000000b1', 'recebida', now(), '2026-10-13', 'chegada', 'Já foi coletado', 'sombra')$q$, 'material_sinais_whatsapp_message_id_tipo_key'),
  ('sinal', 'o trecho não muda', $q$update public.material_sinais set trecho = 'outra coisa' where whatsapp_message_id = 'd4000000-0000-4000-8000-0000000000b1'$q$, 'erro P0001: O sinal registrado não muda: só o estado, o que faria, o vínculo e o julgamento.'),
  ('sinal', 'o julgamento muda', $q$update public.material_sinais set julgamento = 'certo', julgado_em = now(), julgado_por = 'fato' where whatsapp_message_id = 'd4000000-0000-4000-8000-0000000000b1'$q$, 'aceitou'),
  ('sinal', 'não se apaga', $q$delete from public.material_sinais where whatsapp_message_id = 'd4000000-0000-4000-8000-0000000000b1'$q$, 'erro P0001: O registro da agenda não se apaga.'),
  -- agenda_fornecedor_mensagens (a de teste d4…c1)
  ('mensagem', 'tipo fora da lista', $q$insert into public.agenda_fornecedor_mensagens (fornecedor_id, tipo, terco, modo, texto, enviar_em, dedupe_key) values ('dd000000-0000-4000-8000-000000000002', 'cobrar', 1, 'sombra', 'Olá! Sobre o pedido…', now(), 'x1')$q$, 'agenda_fornecedor_mensagens_tipo_check'),
  ('mensagem', 'terço 3', $q$insert into public.agenda_fornecedor_mensagens (fornecedor_id, tipo, terco, modo, texto, enviar_em, dedupe_key) values ('dd000000-0000-4000-8000-000000000002', 'confirmar_prazo', 3, 'sombra', 'Olá! Sobre o pedido…', now(), 'x2')$q$, 'agenda_fornecedor_mensagens_terco_check'),
  ('mensagem', 'modo desligado', $q$insert into public.agenda_fornecedor_mensagens (fornecedor_id, tipo, terco, modo, texto, enviar_em, dedupe_key) values ('dd000000-0000-4000-8000-000000000002', 'confirmar_prazo', 1, 'desligado', 'Olá! Sobre o pedido…', now(), 'x3')$q$, 'agenda_fornecedor_mensagens_modo_check'),
  ('mensagem', 'texto de 2', $q$insert into public.agenda_fornecedor_mensagens (fornecedor_id, tipo, terco, modo, texto, enviar_em, dedupe_key) values ('dd000000-0000-4000-8000-000000000002', 'confirmar_prazo', 1, 'sombra', 'oi', now(), 'x4')$q$, 'agenda_fornecedor_mensagens_texto_check'),
  ('mensagem', 'recusada sem motivo', $q$insert into public.agenda_fornecedor_mensagens (fornecedor_id, tipo, terco, modo, texto, enviar_em, dedupe_key, estado) values ('dd000000-0000-4000-8000-000000000002', 'confirmar_prazo', 1, 'sombra', 'Olá! Sobre o pedido…', now(), 'x5', 'recusada')$q$, 'fornecedor_recusa_coerente'),
  ('mensagem', 'motivo fora da lista', $q$insert into public.agenda_fornecedor_mensagens (fornecedor_id, tipo, terco, modo, texto, enviar_em, dedupe_key, estado, recusa_motivo) values ('dd000000-0000-4000-8000-000000000002', 'confirmar_prazo', 1, 'sombra', 'Olá! Sobre o pedido…', now(), 'x6', 'recusada', 'chuva')$q$, 'agenda_fornecedor_mensagens_recusa_motivo_check'),
  ('mensagem', 'a mesma chave', $q$insert into public.agenda_fornecedor_mensagens (fornecedor_id, tipo, terco, modo, texto, enviar_em, dedupe_key) values ('dd000000-0000-4000-8000-000000000002', 'confirmar_prazo', 2, 'sombra', 'Olá! Sobre o pedido…', now(), 'agenda-fornecedor:teste:1:sombra')$q$, 'agenda_fornecedor_mensagens_dedupe_key_key'),
  ('mensagem', 'fornecedor que não existe', $q$insert into public.agenda_fornecedor_mensagens (fornecedor_id, tipo, terco, modo, texto, enviar_em, dedupe_key) values ('d4000000-0000-4000-8000-0000000000ff', 'confirmar_prazo', 1, 'sombra', 'Olá! Sobre o pedido…', now(), 'x7')$q$, 'agenda_fornecedor_mensagens_fornecedor_id_fkey'),
  ('mensagem', 'o texto não muda', $q$update public.agenda_fornecedor_mensagens set texto = 'outra mensagem' where id = 'd4000000-0000-4000-8000-0000000000c1'$q$, 'erro P0001: A mensagem ao fornecedor registrada não muda: só o estado, a recusa e a fila.'),
  ('mensagem', 'enfileirada com a fila', $q$update public.agenda_fornecedor_mensagens set estado = 'enfileirada', fila_id = gen_random_uuid() where id = 'd4000000-0000-4000-8000-0000000000c1'$q$, 'aceitou'),
  ('mensagem', 'não se apaga', $q$delete from public.agenda_fornecedor_mensagens where id = 'd4000000-0000-4000-8000-0000000000c1'$q$, 'erro P0001: O registro da agenda não se apaga.'),
  -- as listas fechadas ampliadas
  ('lista', 'pergunta nfe_vincular entra', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('nfe_vincular', 'nfe_vincular:teste', 'É material de qual serviço?', 'sombra')$q$, 'aceitou'),
  ('lista', 'pergunta fornecedores_prazo entra', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('fornecedores_prazo', 'fornecedores_prazo', 'Como você compra dos principais?', 'sombra')$q$, 'aceitou'),
  ('lista', 'pergunta de tipo que não existe', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('cotacao', 'cotacao:teste', 'Qual cotação?', 'sombra')$q$, 'agenda_perguntas_tipo_check'),
  ('lista', 'rascunho de tipo que não existe', $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, expira_em) values ('aa000000-0000-4000-8000-000000000001', 'whatsapp', 'compra', 'compra:x', '{}', 'x', now() + interval '1 hour')$q$, 'agenda_rascunho_tipo_check'),
  ('lista', 'rascunho fornecedor entra', $q$insert into public.agenda_rascunho (autor, canal, tipo, chave, dados, texto, expira_em) values ('aa000000-0000-4000-8000-000000000001', 'whatsapp', 'fornecedor', 'fornecedor:x', '{}', 'x', now() + interval '1 hour')$q$, 'aceitou'),
  ('lista', 'rodada material entra', $q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('material', '2026-10-30', now(), 'sombra', 'sombra')$q$, 'aceitou'),
  ('lista', 'rodada de rotina que não existe', $q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('cotacao', '2026-10-30', now(), 'sombra', 'sombra')$q$, 'agenda_vigia_rodadas_rotina_check');

-- As linhas de teste que os casos acima mexem.
insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria)
values ('d4000000-0000-4000-8000-0000000000d1', '05000000-0000-4000-8000-000000000069', 'dono', 'TESTE AG4 linha', 1);
insert into public.material_remessas (id, nfe_chave, emitida_em, emitente, numero)
values ('d4000000-0000-4000-8000-0000000000a1', repeat('4', 44), '2026-10-26', 'TESTE AG4', '1');
insert into public.whatsapp_messages (id, direction, phone_normalized, body)
values ('d4000000-0000-4000-8000-0000000000b1', 'inbound', '5547900000201', 'Já foi coletado');
insert into public.material_sinais (whatsapp_message_id, direcao, ocorreu_em, dia, tipo, trecho, modo)
values ('d4000000-0000-4000-8000-0000000000b1', 'recebida', timestamptz '2026-10-13 17:19-03', '2026-10-13', 'chegada',
        'Já foi coletado', 'sombra');
insert into public.agenda_fornecedor_mensagens (id, fornecedor_id, tipo, terco, modo, texto, enviar_em, dedupe_key)
values ('d4000000-0000-4000-8000-0000000000c1', 'dd000000-0000-4000-8000-000000000002', 'confirmar_prazo', 1, 'sombra',
        'Olá! Aqui é o Gustavo, da HBR Marine. Sobre o pedido de painel (pedido de 15/10): a entrega continua prevista para qua 04/11? Obrigado!',
        timestamptz '2026-10-22 09:00-03', 'agenda-fornecedor:teste:1:sombra');

insert into _resultado
select format('B1 %s: %s', k.grupo, k.nome), r = k.espera, r
  from _casos k, lateral (select pg_temp.recusa(k.sql) as r) x;

insert into _resultado
select 'B1z todo CHECK novo de agenda_config tem caso (nenhum ficou sem prova)',
       bool_and(exists (select 1 from _casos k where k.espera = c.conname)),
       string_agg(c.conname, ', ') filter (where not exists (select 1 from _casos k where k.espera = c.conname))
  from pg_constraint c
 where c.conrelid = 'public.agenda_config'::regclass and c.contype = 'c'
   and c.conname ~ '^agenda_config_(modo_material|modo_detector|modo_fornecedor|oc_viva|remessa|material_|nfe_|pix_|prazo_longo|detector_|fornecedor)';

insert into _resultado
select 'B1y a remessa: o despacho é a saída, senão a emissão; nasce a caminho e sem resposta',
       (select despacho_em = date '2026-10-26' and estado = 'a_caminho' and vinculo = 'sem_resposta' and os_ids = '{}'
          from public.material_remessas where id = 'd4000000-0000-4000-8000-0000000000a1')
       and pg_temp.recusa($q$insert into public.material_remessas (nfe_chave, emitida_em, saida_em) values (repeat('7', 44), '2026-10-26', '2026-10-27')$q$) = 'aceitou',
       null;

insert into _resultado
select 'B1x a view das OCs vivas termina com as duas colunas de vínculo de linha; a coluna gerada critica não ganhou tipo novo',
       (select array_agg(a.attname::text order by a.attnum desc) from pg_attribute a
         where a.attrelid = 'public.v_oc_itens_a_caminho'::regclass and a.attnum > 0)[1:2]
         = array['service_order_service_id', 'service_order_part_id']
       and (select pg_get_expr(d.adbin, d.adrelid) from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica') !~ 'nfe_vincular|fornecedor'
       and pg_get_constraintdef((select oid from pg_constraint where conname = 'agenda_acoes_tipo_check'
                                   and conrelid = 'public.agenda_acoes'::regclass)) ~ '''material''.*''fornecedor'''
       and pg_get_constraintdef((select oid from pg_constraint where conname = 'agenda_acoes_origem_check'
                                   and conrelid = 'public.agenda_acoes'::regclass)) ~ '''fornecedor''.*''nota''',
       null;

-- ── B2. RLS e privilégios ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B2a as 3 tabelas: RLS ligada e uma policy só, de leitura, TO authenticated',
       bool_and(c.relrowsecurity)
       and bool_and((select count(*) from pg_policy p where p.polrelid = c.oid) = 1)
       and bool_and((select bool_and(p.polcmd = 'r' and p.polroles = array[(select oid from pg_roles where rolname = 'authenticated')])
                       from pg_policy p where p.polrelid = c.oid)),
       string_agg(c.relname, ', ')
  from pg_class c
 where c.oid in ('public.material_remessas'::regclass, 'public.material_sinais'::regclass, 'public.agenda_fornecedor_mensagens'::regclass);

insert into _resultado
select 'B2b anon sem privilégio nenhum; authenticated só lê; service_role escreve',
       bool_and(not has_table_privilege('anon', t, 'select') and not has_table_privilege('anon', t, 'insert')
                and not has_table_privilege('anon', t, 'update') and not has_table_privilege('anon', t, 'delete'))
       and bool_and(has_table_privilege('authenticated', t, 'select') and not has_table_privilege('authenticated', t, 'insert')
                    and not has_table_privilege('authenticated', t, 'update') and not has_table_privilege('authenticated', t, 'delete'))
       and bool_and(has_table_privilege('service_role', t, 'insert') and has_table_privilege('service_role', t, 'update')),
       null
  from unnest(array['public.material_remessas', 'public.material_sinais', 'public.agenda_fornecedor_mensagens']) t;

create temp table _funcoes_f4 (f text primary key, quem text) on commit drop;
insert into _funcoes_f4 values
  ('public._agenda_lugar_normal(text)', 'leitura'), ('public._agenda_lugar_casa(text, text)', 'leitura'),
  ('public._agenda_classe_por_lugar(text, text)', 'leitura'), ('public._agenda_lugar_texto(text, text)', 'leitura'),
  ('public._agenda_classe_pelo_nome(text)', 'leitura'), ('public._agenda_nome_de_grupo(text)', 'leitura'),
  ('public._agenda_classe_texto(text, integer, integer)', 'leitura'), ('public._agenda_prazo_do_fornecedor(uuid)', 'leitura'),
  ('public._agenda_chegada_pela_classe(text, integer, integer, date)', 'leitura'),
  ('public._agenda_chegada_estimada(uuid, date)', 'leitura'), ('public._agenda_classe_do_fornecedor(uuid)', 'leitura'),
  ('public.os_prontidao(uuid, date)', 'leitura'),
  ('public.agenda_rascunho_fornecedor(uuid, text, text, text, numeric, text, text, text, date)', 'rpc'),
  ('public.agenda_rascunho_gravar(uuid, date)', 'rpc'),
  ('public._agenda_aplicar_fornecedor(uuid, jsonb, text, date)', 'interna'), ('public._agenda_fornecedor_dito(text)', 'interna'),
  ('public._agenda_rascunho_frase(text, jsonb)', 'interna'),
  ('public._os_material_previsao_original()', 'gatilho'), ('public._material_remessas_so_muda()', 'gatilho'),
  ('public._material_sinais_so_muda()', 'gatilho'), ('public._agenda_fornecedor_mensagens_so_muda()', 'gatilho');

insert into _resultado
select 'B2c funções: anon nada; authenticated as leituras e as RPCs (nem as internas nem os gatilhos); service_role as leituras, as RPCs e as internas',
       bool_and(not has_function_privilege('anon', f, 'execute'))
       and bool_and(has_function_privilege('authenticated', f, 'execute') = (quem in ('leitura', 'rpc')))
       and bool_and(has_function_privilege('service_role', f, 'execute') or quem = 'gatilho'),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f, 'execute')
                                      or has_function_privilege('authenticated', f, 'execute') <> (quem in ('leitura', 'rpc'))
                                      or not (has_function_privilege('service_role', f, 'execute') or quem = 'gatilho'))
  from _funcoes_f4;

insert into _resultado
select 'B2d security definer só o rascunho, o *grava* e o gatilho do original; leituras STABLE/IMMUTABLE; search_path fixo em todas',
       bool_and(p.prosecdef = (p.oid in ('public.agenda_rascunho_fornecedor(uuid, text, text, text, numeric, text, text, text, date)'::regprocedure,
                                         'public._agenda_aplicar_fornecedor(uuid, jsonb, text, date)'::regprocedure,
                                         'public.agenda_rascunho_gravar(uuid, date)'::regprocedure,
                                         'public._os_material_previsao_original()'::regprocedure)))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and bool_and(p.provolatile in ('s', 'i') or k.quem <> 'leitura'),
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ')
  from _funcoes_f4 k join pg_proc p on p.oid = k.f::regprocedure;

insert into _resultado
select 'B2e o técnico: o rascunho do fornecedor recusa 42501 e as tabelas voltam vazias; anon não lê',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
         $q$select public.agenda_rascunho_fornecedor(null, 'whatsapp', 'Premel', 'balcao', null, null, null, 'a Premel eu pego no balcão')::text$q$)
         = 'erro 42501: Só o administrador mexe na agenda.'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select (select count(*) from public.material_remessas) + (select count(*) from public.material_sinais)
                       + (select count(*) from public.agenda_fornecedor_mensagens)$q$) = '0'
       and pg_temp.como(null, 'anon', $q$select count(*)::text from public.material_remessas$q$) like 'erro 42501%'
       and pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated',
             $q$select count(*)::text from public.material_remessas$q$) = '1',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
         $q$select public.agenda_rascunho_fornecedor(null, 'whatsapp', 'Premel', 'balcao', null, null, null, 'a Premel eu pego no balcão')::text$q$);

-- ── B3. As modalidades são as chaves de prazo_classe_du (+ importacao) ───────────────────────────────────
insert into _resultado
select 'B3 as modalidades do CHECK de suppliers, menos importacao, são exatamente as chaves de agenda_config.prazo_classe_du',
       (select array_agg(m order by m) from (
          select (regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g'))[1] as m
            from pg_constraint c where c.conname = 'suppliers_modalidade_check' and c.conrelid = 'public.suppliers'::regclass) x
         where m <> 'importacao')
       = (select array_agg(k order by k) from jsonb_object_keys((select prazo_classe_du from public.agenda_config)) k),
       (select string_agg(k, ', ') from jsonb_object_keys((select prazo_classe_du from public.agenda_config)) k);

-- ── B4. O original da previsão em todos os caminhos de escrita ──────────────────────────────────────────
do $b4$
declare
  v_res jsonb := '[]'::jsonb;
  c_lin constant uuid := 'd4000000-0000-4000-8000-0000000000d2';
  m public.os_material;
begin
  begin
    -- insert com previsão (o fornecedor disse), num dia fixo
    perform set_config('agenda.hoje', '2026-10-30', true);
    insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, situacao, fonte,
                                    previsao_ate, previsao_fonte)
    values (c_lin, '05000000-0000-4000-8000-000000000069', 'dono', 'TESTE AG4 compressor', 1, 'a_caminho', 'fornecedor',
            date '2026-11-05', 'fornecedor');
    select * into m from public.os_material where id = c_lin;
    v_res := pg_temp.ok(v_res, 'B4a insert com previsão: o original é a previsão, com a fonte e o dia de quem escreveu',
      m.previsao_original = date '2026-11-05' and m.previsao_original_fonte = 'fornecedor' and m.previsao_original_em = date '2026-10-30',
      to_jsonb(m)::text);

    -- troca de previsão (e a escrita que tenta mudar o original): o original fica
    perform set_config('agenda.hoje', '2026-11-02', true);
    update public.os_material set previsao_ate = date '2026-11-10', previsao_fonte = 'dono',
                                  previsao_original = date '2026-12-01', previsao_original_fonte = 'oc', previsao_original_em = null
     where id = c_lin;
    select * into m from public.os_material where id = c_lin;
    v_res := pg_temp.ok(v_res, 'B4b a previsão muda, o original não (nem quando a escrita tenta trocá-lo)',
      m.previsao_ate = date '2026-11-10' and m.previsao_original = date '2026-11-05' and m.previsao_original_fonte = 'fornecedor'
      and m.previsao_original_em = date '2026-10-30', to_jsonb(m)::text);

    -- volta a faltar (a OC cancelada, a quantidade que subiu): o original fica
    update public.os_material set situacao = 'falta', fonte = null, previsao_ate = null, previsao_fonte = null where id = c_lin;
    select * into m from public.os_material where id = c_lin;
    v_res := pg_temp.ok(v_res, 'B4c a linha volta a faltar: o original fica (como a Fase 1 já fazia)',
      m.situacao = 'falta' and m.previsao_original = date '2026-11-05' and m.previsao_original_fonte = 'fornecedor', to_jsonb(m)::text);

    -- a compra nova: o original de antes vai ao histórico (antes da entrada desta mudança) e vale o novo
    perform set_config('agenda.hoje', '2026-11-03', true);
    update public.os_material
       set situacao = 'a_caminho', fonte = 'nfe', previsao_ate = date '2026-11-12', previsao_fonte = 'nfe',
           historico = public._os_material_historico(historico, '{"nota": "pela nota 51038"}'::jsonb)
     where id = c_lin;
    select * into m from public.os_material where id = c_lin;
    v_res := pg_temp.ok(v_res, 'B4d compra nova depois de faltar: original novo (nota, 03/11) e o de antes no histórico, antes do evento',
      m.previsao_original = date '2026-11-12' and m.previsao_original_fonte = 'nfe' and m.previsao_original_em = date '2026-11-03'
      and m.historico -> -1 ->> 'nota' = 'pela nota 51038'
      and m.historico -> -2 = '{"em": "2026-11-03", "de": "original", "valor": "2026-11-05", "fonte": "fornecedor"}'::jsonb,
      m.historico::text);

    -- a escrita das Fases 1–3 (o original escrito junto, sem a fonte; ou a linha que já faltava com o original)
    insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao, fonte, previsao_ate,
                                    previsao_original, previsao_fonte)
    values ('05000000-0000-4000-8000-000000000069', 'dono', 'TESTE AG4 painel', 1, 'a_caminho', 'dono', date '2026-11-03',
            date '2026-11-03', 'dono')
    returning * into m;
    v_res := pg_temp.ok(v_res, 'B4e o original escrito sem a fonte (rascunho da Fase 1) ganha a da previsão e o dia',
      m.previsao_original_fonte = 'dono' and m.previsao_original_em = date '2026-11-03', to_jsonb(m)::text);
    insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao, previsao_original)
    values ('05000000-0000-4000-8000-000000000069', 'dono', 'TESTE AG4 cabo', 1, 'falta', date '2026-11-03')
    returning * into m;
    v_res := pg_temp.ok(v_res, 'B4f o original sem previsão nem fato informado: a fonte é a OC (a única que o sistema grava sozinho)',
      m.previsao_original_fonte = 'oc', to_jsonb(m)::text);

    -- a sincronização: a OC-00004 com data prevista cria a linha a caminho, e o original é o da OC
    perform set_config('agenda.hoje', '2026-10-16', true);
    update public.purchase_orders set expected_date = date '2026-10-20' where id = '70000000-0000-4000-8000-000000000004';
    perform public.os_material_sincronizar('05000000-0000-4000-8000-000000000104', date '2026-10-16');
    select * into m from public.os_material where purchase_order_item_id = '71000000-0000-4000-8000-000000000001';
    v_res := pg_temp.ok(v_res, 'B4g pela sincronização (OC com data): a caminho, o original é o da OC, com a fonte oc',
      m.situacao = 'a_caminho' and m.previsao_original = date '2026-10-20' and m.previsao_original_fonte = 'oc'
      and m.previsao_original_em = date '2026-10-16', to_jsonb(m)::text);

    perform set_config('agenda.hoje', '', true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b4$;

-- ── B5–B8. Com a carteira de sex 30/10 (fixture-fase4) ───────────────────────────────────────────────────
do $b5$
declare
  v_res jsonb := '[]'::jsonb;
  c_premel  constant uuid := 'dd000000-0000-4000-8000-000000000001';
  c_kes     constant uuid := 'dd000000-0000-4000-8000-000000000002';
  c_ksc     constant uuid := 'dd000000-0000-4000-8000-000000000003';
  c_mateus  constant uuid := 'dd000000-0000-4000-8000-000000000004';
  c_ali     constant uuid := 'dd000000-0000-4000-8000-000000000005';
  c_toli    constant uuid := 'dd000000-0000-4000-8000-000000000006';
  c_mp      constant uuid := 'dd000000-0000-4000-8000-000000000007';
  c_correa  constant uuid := 'dd000000-0000-4000-8000-000000000008';
  j jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('B5 o prazo do fornecedor (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');

    -- o lugar tolerante
    v_res := pg_temp.ok(v_res, 'B5a o caractere quebrado vale uma letra: "Itaja�" e "ITAJA�" casam Itajaí; "Balne�rio Cambori�" casa; "S�o Paulo" não',
      public._agenda_lugar_casa('Itaja' || chr(65533), 'Itajaí') and public._agenda_lugar_casa('ITAJA' || chr(65533), 'Itajaí')
      and public._agenda_lugar_casa('Itajai', 'Itajaí') and public._agenda_lugar_casa('BALNEARIO CAMBORIU', 'Balneário Camboriú')
      and public._agenda_lugar_casa('Balne' || chr(65533) || 'rio Cambori' || chr(65533), 'Balneário Camboriú')
      and not public._agenda_lugar_casa('S' || chr(65533) || 'o Paulo', 'Itajaí')
      and not public._agenda_lugar_casa('S' || chr(65533) || 'o Paulo', 'Penha')
      and not public._agenda_lugar_casa('Itajaí Mirim', 'Itajaí') and not public._agenda_lugar_casa(null, 'Itajaí')
      and public._agenda_lugar_normal('Itaja' || chr(65533)) = 'itaja' || chr(65533));
    v_res := pg_temp.ok(v_res, 'B5b a classe pelo lugar: local, SC/PR (sigla, extenso e quebrado), outra UF, nada',
      public._agenda_classe_por_lugar('Itaja' || chr(65533), 'SC') = 'entrega_local'
      and public._agenda_classe_por_lugar('Curitiba', 'PR') = 'distribuidor_sc_pr'
      and public._agenda_classe_por_lugar('Joinville', 'Santa Catarina') = 'distribuidor_sc_pr'
      and public._agenda_classe_por_lugar('Londrina', 'Paran' || chr(65533)) = 'distribuidor_sc_pr'
      and public._agenda_classe_por_lugar('S' || chr(65533) || 'o Paulo', 'SP') = 'outro_estado'
      and public._agenda_classe_por_lugar(null, null) is null and public._agenda_classe_por_lugar('', '') is null);
    v_res := pg_temp.ok(v_res, 'B5c o lugar para o dono ler: a grafia dos municípios locais, a inicial maiúscula, a UF em sigla',
      public._agenda_lugar_texto('Itaja' || chr(65533), 'SC') = 'Itajaí/SC'
      and public._agenda_lugar_texto('CURITIBA', 'PR') = 'Curitiba/PR'
      and public._agenda_lugar_texto('BALNEARIO CAMBORIU', 'SC') = 'Balneário Camboriú/SC'
      and public._agenda_lugar_texto('Vila Velha', 'ES') = 'Vila Velha/ES'
      and public._agenda_lugar_texto('Joinville', 'Santa Catarina') = 'Joinville/SC'
      and public._agenda_lugar_texto(null, null) is null);

    -- a fonte única, regra por regra
    j := public._agenda_prazo_do_fornecedor(c_premel);
    v_res := pg_temp.ok(v_res, 'B5d Premel ("Itaja�"/SC): entrega local, 1 dia útil, pela cidade (era distribuidor SC/PR na Fase 1)',
      j = '{"classe": "entrega_local", "du": 1, "corridos": null, "fonte": "cidade", "duvida": null, "principal_id": null,
            "texto": "entrega local, 1 dia útil (pela cidade, chute meu)"}'::jsonb, j::text);
    j := public._agenda_prazo_do_fornecedor(c_kes);
    v_res := pg_temp.ok(v_res, 'B5e Kamell de Vila Velha (CNPJ, o produto): a principal do cadastro repetido — outro estado, 4 dias úteis, com a dúvida',
      j ->> 'classe' = 'outro_estado' and (j ->> 'du')::int = 4 and j ->> 'fonte' = 'cidade' and j ->> 'duvida' = 'duplicado'
      and j ->> 'principal_id' = c_kes::text and j ->> 'texto' = 'outro estado, 4 dias úteis (pela cidade, chute meu)', j::text);
    j := public._agenda_prazo_do_fornecedor(c_ksc);
    v_res := pg_temp.ok(v_res, 'B5f Kamell de Itajaí (ativa, sem CNPJ): sem classe até o dono dizer, apontando a principal',
      j ->> 'classe' is null and j ->> 'duvida' = 'duplicado' and j ->> 'principal_id' = c_kes::text and j ->> 'texto' is null
      and public._agenda_classe_do_fornecedor(c_ksc) is null and public._agenda_classe_do_fornecedor(c_kes) = 'outro_estado', j::text);
    j := public._agenda_prazo_do_fornecedor(c_ali);
    v_res := pg_temp.ok(v_res, 'B5g AliExpress: importado pelo nome, 20 dias corridos, sem dias úteis',
      j = '{"classe": "importacao", "du": null, "corridos": 20, "fonte": "nome", "duvida": null, "principal_id": null,
            "texto": "importado, 20 dias corridos (pelo nome)"}'::jsonb, j::text);
    j := public._agenda_prazo_do_fornecedor(c_mp);
    v_res := pg_temp.ok(v_res, 'B5h Mercado Pago (Osasco/SP): compra pela internet pelo nome, antes da UF',
      j ->> 'classe' = 'marketplace' and (j ->> 'du')::int = 3 and j ->> 'fonte' = 'nome', j::text);
    j := public._agenda_prazo_do_fornecedor(c_toli);
    v_res := pg_temp.ok(v_res, 'B5i Toli (Curitiba/PR): transportadora de SC/PR, 2 dias úteis',
      j ->> 'texto' = 'transportadora de SC/PR, 2 dias úteis (pela cidade, chute meu)' and (j ->> 'du')::int = 2, j::text);
    v_res := pg_temp.ok(v_res, 'B5j Correa ("BALNEARIO CAMBORIU"): entrega local; Mateus (sem cidade e sem UF): sem lugar; nulo e inexistente: vazio',
      public._agenda_prazo_do_fornecedor(c_correa) ->> 'classe' = 'entrega_local'
      and public._agenda_prazo_do_fornecedor(c_mateus) ->> 'classe' is null
      and public._agenda_prazo_do_fornecedor(c_mateus) ->> 'duvida' = 'sem_lugar'
      and public._agenda_prazo_do_fornecedor(null) = '{"classe": null, "du": null, "corridos": null, "fonte": null, "duvida": null, "principal_id": null, "texto": null}'::jsonb
      and public._agenda_prazo_do_fornecedor('d4000000-0000-4000-8000-0000000000ff') ->> 'classe' is null);

    -- dois cadastros do mesmo nome e a mesma classe: sem dúvida (a Coremma de Blumenau e a de Itajaí)
    insert into public.suppliers (id, name, city, state, active) values
      ('d4000000-0000-4000-8000-000000000e01', 'COREMMA LTDA', 'Blumenau', 'SC', true),
      ('d4000000-0000-4000-8000-000000000e02', 'Coremma Ltda', 'Itajai', 'SC', true);
    v_res := pg_temp.ok(v_res, 'B5k cadastro repetido com a mesma classe (Coremma de Blumenau e de Itajaí): os dois valem, sem dúvida',
      (public._agenda_prazo_do_fornecedor('d4000000-0000-4000-8000-000000000e01') ->> 'duvida') is null
      and public._agenda_prazo_do_fornecedor('d4000000-0000-4000-8000-000000000e02') ->> 'classe' = 'entrega_local');

    -- o que o dono disse vale primeiro
    update public.suppliers set modalidade = 'outro_estado', prazo_dias_uteis = 5, prazo_fonte = 'dono' where id = c_kes;
    j := public._agenda_prazo_do_fornecedor(c_kes);
    v_res := pg_temp.ok(v_res, 'B5l o dono disse (Kamell de Vila Velha, 5 dias úteis): vale antes de tudo, sem dúvida',
      j = '{"classe": "outro_estado", "du": 5, "corridos": null, "fonte": "dono", "duvida": null, "principal_id": null,
            "texto": "outro estado, 5 dias úteis (você disse)"}'::jsonb, j::text);
    update public.suppliers set modalidade = 'importacao', prazo_dias_uteis = null, prazo_dias_corridos = null, prazo_fonte = 'dono'
     where id = c_ali;
    v_res := pg_temp.ok(v_res, 'B5m importado dito sem os dias: os corridos de agenda_config',
      (public._agenda_prazo_do_fornecedor(c_ali) ->> 'corridos')::int = 20
      and public._agenda_prazo_do_fornecedor(c_ali) ->> 'fonte' = 'dono');

    -- em produção a Kamell de Itajaí já está INATIVA: ela vale como a de Vila Velha, sem dúvida nas duas
    update public.suppliers set modalidade = null, prazo_dias_uteis = null, prazo_fonte = null where id = c_kes;
    update public.suppliers set active = false where id = c_ksc;
    j := public._agenda_prazo_do_fornecedor(c_ksc);
    v_res := pg_temp.ok(v_res, 'B5n a Kamell de Itajaí inativa (produção, 25/10): vale como a de Vila Velha (4 dias úteis), apontando-a; a de Vila Velha sem dúvida',
      j ->> 'classe' = 'outro_estado' and (j ->> 'du')::int = 4 and j ->> 'principal_id' = c_kes::text and (j ->> 'duvida') is null
      and (public._agenda_prazo_do_fornecedor(c_kes) ->> 'duvida') is null
      and (public._agenda_prazo_do_fornecedor(c_kes) ->> 'principal_id') is null, j::text);
    update public.suppliers set active = true where id = c_ksc;

    -- ── B6. A chegada estimada ──
    v_res := pg_temp.ok(v_res, 'B6a dias úteis: Premel (1) de qui 29/10 → sex 30/10, de sex 30/10 → ter 03/11 (Finados); Kamell (4) de qui 29/10 → qui 05/11',
      public._agenda_chegada_estimada(c_premel, date '2026-10-29') = date '2026-10-30'
      and public._agenda_chegada_estimada(c_premel, date '2026-10-30') = date '2026-11-03'
      and public._agenda_chegada_estimada(c_kes, date '2026-10-29') = date '2026-11-05');
    v_res := pg_temp.ok(v_res, 'B6b Consciência Negra: Toli (2) de qua 18/11 → seg 23/11',
      public._agenda_chegada_estimada(c_toli, date '2026-11-18') = date '2026-11-23');
    v_res := pg_temp.ok(v_res, 'B6c importado: 20 corridos de qui 15/10 → qua 04/11; de ter 13/10 → 02/11 (Finados) vira ter 03/11',
      public._agenda_chegada_estimada(c_ali, date '2026-10-15') = date '2026-11-04'
      and public._agenda_chegada_estimada(c_ali, date '2026-10-13') = date '2026-11-03');
    v_res := pg_temp.ok(v_res, 'B6d classe nula (Mateus, a Kamell de Itajaí ativa, sem fornecedor) = sem data; pela classe, a mesma conta',
      public._agenda_chegada_estimada(c_mateus, date '2026-10-29') is null
      and public._agenda_chegada_estimada(c_ksc, date '2026-10-29') is null
      and public._agenda_chegada_estimada(null, date '2026-10-29') is null
      and public._agenda_chegada_pela_classe('outro_estado', 4, null, date '2026-10-29') = date '2026-11-05'
      and public._agenda_chegada_pela_classe('importacao', null, null, date '2026-10-15') = date '2026-11-04'
      and public._agenda_chegada_pela_classe('balcao', 0, null, date '2026-10-31') = date '2026-11-03'
      and public._agenda_chegada_pela_classe(null, 3, null, date '2026-10-29') is null
      and public._agenda_chegada_pela_classe('entrega_local', 1, null, null) is null);

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b5$;

-- ── B7. A prontidão com o prazo do fornecedor ───────────────────────────────────────────────────────────
do $b7$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje   constant date := date '2026-10-30';
  c_premel constant uuid := 'dd000000-0000-4000-8000-000000000001';
  c_ali    constant uuid := 'dd000000-0000-4000-8000-000000000005';
  c_ven    constant uuid := '05000000-0000-4000-8000-000000000069';
  c_nelson constant uuid := '05000000-0000-4000-8000-000000000112';
  r jsonb; x jsonb; v_cab uuid; v_corpo text; v_a text[] := '{}'; v_b text[]; l text; v_achadas text[] := '{}';
  v_esp date;
  v_trocadas text[] := array[
    '    select q.*, public._agenda_classe_do_fornecedor(q.forn_id) as classe',
    '    select q.*, public._agenda_prazo_da_classe(q.classe) as prazo',
    $l$             when q.prazo is not null then 'D'$l$,
    $l$             when q.sit in ('comprado', 'a_caminho') and q.prazo is not null then$l$,
    '               public.agenda_somar_du(coalesce(q.comprado_em, p_hoje), q.prazo)',
    $l$             when q.sit = 'falta' and q.prazo is not null then$l$,
    '               -- "Se comprar hoje" (ou no dia combinado): calculado, nunca gravado.',
    '               public.agenda_somar_du(greatest(coalesce(q.compra_prevista_em, p_hoje), p_hoje), q.prazo)',
    $l$           case when q.sit = 'falta' and q.prazo is not null and q.compra_prevista_em is null then$l$,
    '             public.agenda_somar_du(v_est_sm, -(c.folga_material_du + q.prazo)) end as compre_ate,',
    $l$                            public._dia_curto(public.agenda_somar_du(p_hoje, (v_compra ->> 'prazo_du')::int)))$l$];
begin
  -- A cópia: fora dos blocos "-- FASE 4:", linha a linha a da Fase 2 (sem as linhas que os blocos trocaram).
  if coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '') = '' then
    insert into _resultado values ('B7z a cópia de os_prontidao só muda nos blocos "-- FASE 4:"', true,
      'PULADO: sem agenda_teste.mig_motor_fase2 (rode pela bancada)');
  else
    v_corpo := pg_temp.corpo(current_setting('agenda_teste.mig_motor_fase2'), 'os_prontidao');
    foreach l in array string_to_array(v_corpo, E'\n') loop
      if l = any (v_trocadas) and not (l = any (v_achadas)) then
        v_achadas := v_achadas || l;
        continue;
      end if;
      v_a := v_a || l;
    end loop;
    v_b := pg_temp.sem_fase4((select p.prosrc from pg_proc p where p.oid = 'public.os_prontidao(uuid, date)'::regprocedure));
    -- Os 8 blocos do P1 e o 9º do P2 (20261027100200: a OC recebida ligada ao texto livre não conta duas vezes; só
    -- acréscimo, sem linha trocada).
    insert into _resultado values ('B7z a cópia de os_prontidao só muda nos 9 blocos "-- FASE 4:" (fora deles, linha a linha a de 20261025100200)',
      v_a = v_b and cardinality(v_achadas) = cardinality(v_trocadas)
      and (select count(*) from regexp_matches((select p.prosrc from pg_proc p where p.oid = 'public.os_prontidao(uuid, date)'::regprocedure),
                                               '-- FASE 4: fim', 'g')) = 9,
      format('linhas Fase 2 %s, cópia sem os blocos %s, trocadas achadas %s de %s; 1ª diferente: %s', cardinality(v_a),
             cardinality(v_b), cardinality(v_achadas), cardinality(v_trocadas),
             (select coalesce(min(i)::text, '-') from generate_series(1, greatest(cardinality(v_a), cardinality(v_b))) i
               where v_a[i] is distinct from v_b[i])));
  end if;

  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('B7 a prontidão com o prazo do fornecedor (fixture-fase4)', true,
      'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');
    -- O material do Vanderlei de volta a faltar, informado pelo dono, da Premel e sem compra combinada.
    update public.os_material
       set situacao = 'falta', quantidade_na_mao = 0, chegou_em = null, compra_prevista_em = null, fonte = 'dono',
           fornecedor_id = c_premel
     where service_order_id = c_ven;
    v_cab := (select m.service_order_part_id from public.os_material m
               where m.service_order_id = c_ven and m.service_order_part_id is not null order by m.service_order_part_id limit 1);

    r := public.os_prontidao(c_ven, c_hoje);
    x := (select e from jsonb_array_elements(r #> '{material,itens}') e where e ->> 'linha' = v_cab::text);
    v_res := pg_temp.ok(v_res, 'B7a Premel pela cidade quebrada: entrega local, D, "se comprar hoje" chega ter 03/11 (1 dia útil, Finados no meio), com o prazo_texto',
      x ->> 'nivel' = 'D' and x ->> 'classe' = 'entrega_local' and (x ->> 'prazo_du')::int = 1 and x ->> 'data' = '2026-11-03'
      and x ->> 'data_texto' = 'se comprar hoje, chega por volta de ter 03/11'
      and x ->> 'prazo_texto' = 'entrega local, 1 dia útil (pela cidade, chute meu)' and (x ->> 'duvida') is null
      and (x ->> 'corridos') is null, x::text);

    update public.suppliers set modalidade = 'balcao', prazo_fonte = 'dono' where id = c_premel;
    r := public.os_prontidao(c_ven, c_hoje);
    x := (select e from jsonb_array_elements(r #> '{material,itens}') e where e ->> 'linha' = v_cab::text);
    v_res := pg_temp.ok(v_res, 'B7b Premel no balcão (o dono disse): "se comprar hoje" = hoje (sex 30/10), 0 dia útil',
      x ->> 'nivel' = 'D' and x ->> 'classe' = 'balcao' and (x ->> 'prazo_du')::int = 0 and x ->> 'data' = c_hoje::text
      and x ->> 'data_texto' = 'se comprar hoje, chega por volta de sex 30/10'
      and x ->> 'prazo_texto' = 'balcão, na mão no mesmo dia (você disse)', x::text);

    -- Um item da AliExpress (importado): D em corridos, "compre até" no último dia útil que ainda chega a tempo.
    update public.os_material set fornecedor_id = c_ali where service_order_part_id = v_cab;
    r := public.os_prontidao(c_ven, c_hoje);
    x := (select e from jsonb_array_elements(r #> '{material,itens}') e where e ->> 'linha' = v_cab::text);
    v_esp := public.agenda_somar_du(public.agenda_somar_du((r ->> 'est_sem_material')::date,
                                                           -(select folga_material_du from public.agenda_config)) - 20 + 1, -1);
    v_res := pg_temp.ok(v_res, 'B7c AliExpress: D com 20 dias corridos (sex 30/10 + 20 = qui 19/11), compre até pelo início em corridos, a restrição com texto',
      x ->> 'nivel' = 'D' and x ->> 'classe' = 'importacao' and (x ->> 'prazo_du') is null and (x ->> 'corridos')::int = 20
      and x ->> 'data' = '2026-11-19' and x ->> 'data_texto' = 'se comprar hoje, chega por volta de qui 19/11'
      and x ->> 'compre_ate' = v_esp::text
      and not exists (select 1 from jsonb_array_elements(r -> 'restricoes') e where e ->> 'texto' is null),
      x::text || ' | esperado compre até ' || coalesce(v_esp::text, '-') || ' | ' || (r -> 'restricoes')::text);

    -- O painel do Nelson: comprado na AliExpress com a data dita (C), o prazo do fornecedor no item.
    r := public.os_prontidao(c_nelson, c_hoje);
    x := (select e from jsonb_array_elements(r #> '{material,itens}') e where e ->> 'linha' = md5('peca:112:4')::uuid::text);
    v_res := pg_temp.ok(v_res, 'B7d o painel do Nelson: C "chega qua 04/11 (você disse)", da AliExpress (importado)',
      x ->> 'nivel' = 'C' and x ->> 'data_texto' = 'chega qua 04/11 (você disse)' and x ->> 'classe' = 'importacao'
      and x ->> 'fornecedor' = 'Aliexpress', x::text);

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b7$;

-- ── B8. O rascunho do fornecedor e o *grava* ────────────────────────────────────────────────────────────
do $b8$
declare
  v_res jsonb := '[]'::jsonb;
  c_admin  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_hoje   constant date := date '2026-10-30';
  c_premel constant uuid := 'dd000000-0000-4000-8000-000000000001';
  c_kes    constant uuid := 'dd000000-0000-4000-8000-000000000002';
  c_ksc    constant uuid := 'dd000000-0000-4000-8000-000000000003';
  c_mateus constant uuid := 'dd000000-0000-4000-8000-000000000004';
  c_toli   constant uuid := 'dd000000-0000-4000-8000-000000000006';
  r jsonb; g jsonb; s public.suppliers;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('B8 o rascunho do fornecedor (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');

    r := public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Premel', 'balcao', null, null, null,
                                           'a Premel eu pego no balcão, sai na hora', c_hoje);
    v_res := pg_temp.ok(v_res, 'B8a "a Premel eu pego no balcão": a releitura e NADA no cadastro',
      (r ->> 'ok')::boolean
      and r ->> 'releitura' = E'Entendi assim, confere?\n• Premel (Itajaí/SC): balcão, na mão no mesmo dia (você disse).\nResponda *grava* ou corrija o que estiver errado.'
      and (select modalidade is null and prazo_fonte is null from public.suppliers where id = c_premel), r::text);

    r := public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Toli', null, 7, 'uteis', null, 'a Toli chega rápido', c_hoje);
    v_res := pg_temp.ok(v_res, 'B8b o número que o dono não disse recusa (nada entra)',
      not (r ->> 'ok')::boolean and r ->> 'texto' = 'Não achei "7" no que você disse; me diga de novo.'
      and not exists (select 1 from public.agenda_rascunho x where x.chave = 'fornecedor:' || c_toli), r::text);

    r := public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Kamell', 'outro_estado', 4, 'uteis', null,
                                           'a Kamell chega em 4 dias úteis depois que sai', c_hoje);
    v_res := pg_temp.ok(v_res, 'B8c "a Kamell" com dois cadastros: a pergunta com a cidade de cada um',
      not (r ->> 'ok')::boolean and r ->> 'pergunta' = 'Qual Kamell: Kamell (Vila Velha/ES) ou Kamell (Itajaí/SC)?', r::text);

    r := public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Bosch', 'balcao', null, null, null, 'a Bosch eu pego no balcão', c_hoje);
    v_res := pg_temp.ok(v_res, 'B8d fornecedor que não está no cadastro: recusa (o cadastro é pela tela)',
      not (r ->> 'ok')::boolean
      and r ->> 'texto' = 'Não achei a Bosch nos fornecedores. Cadastre na tela de fornecedores e me diga de novo.', r::text);

    r := public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Kamell de Itajaí', null, null, null, 'Kamell de Vila Velha',
                                           'a Kamell de Itajaí é a mesma de Vila Velha', c_hoje);
    v_res := pg_temp.ok(v_res, 'B8e "é a mesma" sem o prazo da outra (nem dito, nem gravado): pede como ela entrega',
      not (r ->> 'ok')::boolean and r ->> 'texto' = 'Me diga também como a Kamell entrega.', r::text);

    r := public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Kamell (Vila Velha/ES)', 'outro_estado', 4, 'uteis', null,
                                           'a de Vila Velha chega em 4 dias úteis depois que sai', c_hoje);
    v_res := pg_temp.ok(v_res, 'B8f a resposta da pergunta ("Kamell (Vila Velha/ES)") acha a de Vila Velha: outro estado, 4 dias úteis depois do despacho',
      (r ->> 'ok')::boolean and r ->> 'item' = 'Kamell (Vila Velha/ES): outro estado, 4 dias úteis depois do despacho (você disse)'
      and (public._agenda_fornecedor_dito('a Kamell de Vila Velha') ->> 'id') = c_kes::text
      and (public._agenda_fornecedor_dito('Kamell de SC') ->> 'id') = c_ksc::text
      and public._agenda_fornecedor_dito('Kamell de Recife') ->> 'status' = 'ambiguo'
      and public._agenda_fornecedor_dito('Premel de Curitiba') ->> 'status' = 'novo'
      and (public._agenda_fornecedor_dito('Premel') ->> 'id') = c_premel::text, r::text);

    r := public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Kamell de Itajaí', null, null, null, 'Kamell de Vila Velha',
                                           'a Kamell de Itajaí é a mesma de Vila Velha', c_hoje);
    v_res := pg_temp.ok(v_res, 'B8g "a de Itajaí é a mesma de Vila Velha": copia o prazo dito da outra e diz como tirar o cadastro repetido',
      (r ->> 'ok')::boolean
      and r ->> 'item' = 'Kamell (Itajaí/SC): é a mesma Kamell de Vila Velha — conto 4 dias úteis para as duas. Para tirar o cadastro repetido, desative a de Itajaí na tela de fornecedores',
      r::text);

    r := public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Toli', null, 5, 'corridos', null, 'a Toli chega em 5 dias', c_hoje);
    v_res := pg_temp.ok(v_res, 'B8h "a Toli chega em 5 dias" (corridos, não importado): conta os dias úteis do intervalo (Finados no meio: 2)',
      (r ->> 'ok')::boolean and r ->> 'item' = 'Toli (Curitiba/PR): 5 dias (conto 2 dias úteis) (você disse)', r::text);

    r := public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Mateus', 'entrega_local', 1, 'uteis', null,
                                           'o Mateus entrega em 1 dia', c_hoje);
    v_res := pg_temp.ok(v_res, 'B8i o Mateus (sem cidade): entrega local, 1 dia útil, e o aviso da cidade em branco',
      (r ->> 'ok')::boolean
      and r ->> 'item' = 'Mateus: entrega local, 1 dia útil (você disse). A cidade continua em branco no cadastro', r::text);

    r := public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Kamell (Vila Velha/ES)', 'outro_estado', null, null, 'Toli',
                                           'é a mesma da Toli', c_hoje);
    v_res := pg_temp.ok(v_res, 'B8j "é a mesma" junto de modalidade: uma coisa de cada vez',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'mesmo_que_e_prazo', r::text);

    -- A releitura do lote inteiro, na ordem em que o dono falou.
    v_res := pg_temp.ok(v_res, 'B8k a releitura do lote: uma linha por fornecedor, na ordem',
      public.agenda_rascunho_ler(c_admin, c_hoje) ->> 'texto' = E'Entendi assim, confere?\n'
        || E'• Premel (Itajaí/SC): balcão, na mão no mesmo dia (você disse).\n'
        || E'• Kamell (Vila Velha/ES): outro estado, 4 dias úteis depois do despacho (você disse).\n'
        || E'• Kamell (Itajaí/SC): é a mesma Kamell de Vila Velha — conto 4 dias úteis para as duas. Para tirar o cadastro repetido, desative a de Itajaí na tela de fornecedores.\n'
        || E'• Toli (Curitiba/PR): 5 dias (conto 2 dias úteis) (você disse).\n'
        || E'• Mateus: entrega local, 1 dia útil (você disse). A cidade continua em branco no cadastro.\n'
        || 'Responda *grava* ou corrija o que estiver errado.',
      public.agenda_rascunho_ler(c_admin, c_hoje) ->> 'texto');

    -- O *grava*: o cadastro passa a dizer, e as perguntas de cadastro se resolvem. Vale com a agenda automática em teste.
    insert into public.agenda_perguntas (tipo, chave, texto, modo) values
      ('fornecedor_cadastro', 'fornecedor_cadastro:' || c_ksc, 'A Kamell está cadastrada duas vezes… A de Itajaí é a mesma?', 'sombra'),
      ('fornecedores_prazo', 'fornecedores_prazo', 'Para eu prever quando chega o material, me diga como você compra…', 'sombra');
    update public.agenda_config set modo_proposta = 'sombra';
    g := public.agenda_rascunho_gravar(c_admin, c_hoje);
    v_res := pg_temp.ok(v_res, 'B8l o *grava* (com a agenda automática em teste): 5 gravados, "Gravado. Agora:" com uma linha por fornecedor',
      (g ->> 'ok')::boolean and (g ->> 'gravados')::int = 5
      and g ->> 'texto' = E'Gravado. Agora:\n'
        || E'• Premel: balcão, na mão no mesmo dia (você disse).\n'
        || E'• Kamell: outro estado, 4 dias úteis depois do despacho (você disse).\n'
        || E'• Kamell: a mesma de Vila Velha, outro estado, 4 dias úteis (você disse).\n'
        || E'• Toli: 5 dias (conto 2 dias úteis) (você disse).\n'
        || '• Mateus: entrega local, 1 dia útil (você disse).',
      g::text);
    v_res := pg_temp.ok(v_res, 'B8m o cadastro: o que o dono disse, com a fonte, o dia e o trecho; a de Itajaí com o prazo da de Vila Velha',
      (select modalidade = 'balcao' and prazo_dias_uteis is null and prazo_fonte = 'dono' and prazo_informado_em is not null
              and prazo_trecho = 'a Premel eu pego no balcão, sai na hora' from public.suppliers where id = c_premel)
      and (select modalidade = 'outro_estado' and prazo_dias_uteis = 4 from public.suppliers where id = c_kes)
      and (select modalidade = 'outro_estado' and prazo_dias_uteis = 4 and prazo_fonte = 'dono' from public.suppliers where id = c_ksc)
      and (select modalidade = 'distribuidor_sc_pr' and prazo_dias_uteis = 2 from public.suppliers where id = c_toli)
      and (select modalidade = 'entrega_local' and prazo_dias_uteis = 1 and city is null from public.suppliers where id = c_mateus),
      (select string_agg(concat_ws(':', name, modalidade, prazo_dias_uteis), ' | ') from public.suppliers
        where id in (c_premel, c_kes, c_ksc, c_toli, c_mateus)));
    v_res := pg_temp.ok(v_res, 'B8n as perguntas de cadastro se resolvem ("você disse como compra da …"); o prazo passa a ser o do dono',
      (select estado = 'resolvida' and resolvida_motivo = 'você disse como compra da Kamell'
         from public.agenda_perguntas where chave = 'fornecedor_cadastro:' || c_ksc)
      and (select estado = 'resolvida' and resolvida_motivo like 'você disse como compra da %'
             from public.agenda_perguntas where chave = 'fornecedores_prazo')
      and public._agenda_prazo_do_fornecedor(c_premel) ->> 'texto' = 'balcão, na mão no mesmo dia (você disse)'
      and public._agenda_prazo_do_fornecedor(c_ksc) ->> 'classe' = 'outro_estado'
      and (public._agenda_prazo_do_fornecedor(c_ksc) ->> 'duvida') is null, null);

    -- A agenda desligada: nada entra.
    update public.agenda_config set modo_leitura = 'desligado';
    r := public.agenda_rascunho_fornecedor(c_admin, 'whatsapp', 'Premel', 'balcao', null, null, null, 'a Premel no balcão', c_hoje);
    v_res := pg_temp.ok(v_res, 'B8o com a agenda de produção desligada, o rascunho recusa',
      not (r ->> 'ok')::boolean and r ->> 'texto' = 'A agenda de produção está desligada agora: não anotei nada.', r::text);

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b8$;

-- As cópias de agenda_rascunho_gravar (de 20261026100200) e _agenda_rascunho_frase (de 20261025100400): fora dos blocos
-- "-- FASE 4:", iguais (os blocos só acrescentam).
do $copias$
declare
  v_caminhos text := current_setting('agenda_teste.mig_caminhos_fase3', true);
  v_rascunho text := current_setting('agenda_teste.mig_rascunho_fase2', true);
begin
  if coalesce(v_caminhos, '') = '' or coalesce(v_rascunho, '') = '' then
    insert into _resultado values ('B8z as cópias de agenda_rascunho_gravar e _agenda_rascunho_frase', true,
      'PULADO: sem agenda_teste.mig_caminhos_fase3/mig_rascunho_fase2 (rode pela bancada)');
    return;
  end if;
  insert into _resultado values ('B8z as cópias de agenda_rascunho_gravar e _agenda_rascunho_frase só acrescentam o bloco "-- FASE 4:"',
    string_to_array(pg_temp.corpo(v_caminhos, 'agenda_rascunho_gravar'), E'\n')
      = pg_temp.sem_fase4((select prosrc from pg_proc where oid = 'public.agenda_rascunho_gravar(uuid, date)'::regprocedure))
    and string_to_array(pg_temp.corpo(v_rascunho, '_agenda_rascunho_frase'), E'\n')
      = pg_temp.sem_fase4((select prosrc from pg_proc where oid = 'public._agenda_rascunho_frase(text, jsonb)'::regprocedure))
    and (select prosrc from pg_proc where oid = 'public.agenda_rascunho_gravar(uuid, date)'::regprocedure) ~ '-- FASE 4: fim'
    and (select prosrc from pg_proc where oid = 'public._agenda_rascunho_frase(text, jsonb)'::regprocedure) ~ '-- FASE 4: fim',
    null);
end
$copias$;

-- ── B9. A view das OCs vivas com agenda_config.oc_viva_dias ─────────────────────────────────────────────
do $b9$
declare
  v_res jsonb := '[]'::jsonb;
begin
  begin
    insert into public.products (id, name, stock_quantity, cost_price, sale_price)
    values ('d4000000-0000-4000-8000-0000000000f1', 'TESTE AG4 produto', 0, 10, 20);
    insert into public.purchase_orders (id, po_number, status, created_at, updated_at) values
      ('d4000000-0000-4000-8000-0000000000f2', 'OC-TESTE-AG4-59', 'sent', now() - interval '59 days', now()),
      ('d4000000-0000-4000-8000-0000000000f3', 'OC-TESTE-AG4-61', 'sent', now() - interval '61 days', now());
    insert into public.purchase_order_items (id, purchase_order_id, product_id, description, quantity, unit_cost, received_qty) values
      ('d4000000-0000-4000-8000-0000000000f4', 'd4000000-0000-4000-8000-0000000000f2', 'd4000000-0000-4000-8000-0000000000f1', 'x', 1, 10, 0),
      ('d4000000-0000-4000-8000-0000000000f5', 'd4000000-0000-4000-8000-0000000000f3', 'd4000000-0000-4000-8000-0000000000f1', 'x', 1, 10, 0);
    v_res := pg_temp.ok(v_res, 'B9a OC de 59 dias abate a falta; a de 61 não (oc_viva_dias = 60)',
      (select conta_como_ja_pedido from public.v_oc_itens_a_caminho where purchase_order_item_id = 'd4000000-0000-4000-8000-0000000000f4')
      and not (select conta_como_ja_pedido from public.v_oc_itens_a_caminho where purchase_order_item_id = 'd4000000-0000-4000-8000-0000000000f5'));
    update public.agenda_config set oc_viva_dias = 30;
    v_res := pg_temp.ok(v_res, 'B9b com oc_viva_dias = 30, nem a de 59 abate: o número mora em agenda_config',
      not (select conta_como_ja_pedido from public.v_oc_itens_a_caminho where purchase_order_item_id = 'd4000000-0000-4000-8000-0000000000f4'));
    update public.purchase_order_items set service_order_part_id = md5('peca:112:2')::uuid where id = 'd4000000-0000-4000-8000-0000000000f4';
    v_res := pg_temp.ok(v_res, 'B9c a view mostra o vínculo de linha da OC',
      (select service_order_part_id = md5('peca:112:2')::uuid and service_order_service_id is null
         from public.v_oc_itens_a_caminho where purchase_order_item_id = 'd4000000-0000-4000-8000-0000000000f4'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b9$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
