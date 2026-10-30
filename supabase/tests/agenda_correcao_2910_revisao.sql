-- Prova da correção de 29/10 da Agenda de Produção, revisão do lote (migration 20261030100500): os achados da revisão de
-- P1 a P5.
-- bancada: depende de 20261030100500
--
-- Os achados (revisão de 30/10) e o que cada bloco prova. O cenário de HOJE é a fixture-2310.sql que a bancada sempre
-- carrega, com os modos ligados, o dono no WhatsApp e a vigia de qui 29/10 às 16:30 (a publicação da reserva do Lenine):
--   D  (achado 1) o *desfaz* que o aviso promete vale desde que ele sai: o prazo vai a "agora + 24 h" já no enfileirar (o
--      conferir ainda o leva à hora do envio); a mudança de sábado 20:00 contada na segunda 09:30 se desfaz às 09:35, antes
--      do tique seguinte (antes: "Não tenho mudança minha no Vanderlei para desfazer agora."); o 1º aviso depois do deploy
--      conta a publicação já vencida e o *desfaz semana* vale; o aviso que não sai devolve as mudanças e o prazo fica
--   O  (achado 2) o aprendizado do mesmo instante sai numa ordem fixa (fator, presença, folga, atraso e prazo do
--      fornecedor), não pelo id aleatório: a frase do *desfaz aprendizado* na 1ª linha, o "Aprendi com as OS concluídas"
--      no *o que mudou* (o R10g de agenda_fase6_rodada.sql) e duas rodadas iguais dão o mesmo texto (fixture-fase6)
--   L  (achado 3) a linha curta do livre no sábado e no domingo: "de qua 04 a sex 06/11, …; na semana de 09/11, …" (o mesmo
--      rótulo do *livre*); na quinta, como antes
--   S  (achado 4) "(é 1 diária de equipe)" e "(é meia diária de equipe)", em ligado e fora dele; 2 diárias como antes
--   E  (achado 5) a equipe de produção de 30/10 (o dono tirou Roberto, João e Mickael; o Alex, sem a diária cadastrada):
--      a vigia cancela a reserva do Lenine, a pergunta "Guardei lugar a partir de qui 05/11" resolve ("a reserva saiu"),
--      nasce UMA vez na semana a pergunta da equipe sem dias, com o nome do Alex e o que fazer, e o fechamento a mostra; na
--      semana seguinte a velha vence e nasce a nova; com a diária do Alex cadastrada, ela resolve; com a equipe da fixture,
--      nada; com a vigia desligada, o passo não roda.
--      AJUSTADO em 30/10 pela correção da equipe (20261030100600): com a regra nova, quem o dono declara é da equipe, e o
--      Alex declarado pelo dono (como em produção) conta — a pergunta não nasceria. Aqui o Alex entra com os dias só
--      anotados pelo assistente (origem agente), o caso em que ele fica de fora, e o texto é o novo (pergunta os dias, não a
--      diária). O cenário de produção com o Alex declarado pelo dono está em agenda_correcao_2910_equipe.sql.
--   F  (achado 6) o aviso espera o fechamento: de segunda a sexta, de 17:25 a 18:00, nem as peças nem a 1ª trava avisam; a
--      corrida das 17:30 (o fechamento lê, o aviso do mesmo minuto, o fechamento registra) dá UMA mensagem; antes, depois, e
--      no sábado, o aviso sai
--   Q  (achado 7) a pergunta sai uma vez por dia: o fechamento não repete a que o aviso de hoje levou (enviado ou na fila),
--      mas mostra a do aviso que não saiu; o aviso não leva perguntas se alguma delas já saiu hoje no fechamento, e no dia
--      seguinte leva
--   N  o que NÃO muda: o fechamento sem aviso no dia, as peças fora da pausa e o *o que mudou* sem aprendizado são os de
--      antes, byte a byte (as definições de antes rodadas como pg_temp)
-- Sempre (com ou sem as fixtures):
--   K  as cópias: as 9 recriadas só mudam nos blocos "-- CORREÇÃO 29/10 (revisão):" (a linha trocada volta do "-- antes:")
--   P  portas: as 3 novas, ninguém de fora; as recriadas com as portas de antes
--   C  os parâmetros novos (17:25, 18:00) e os CHECKs; o tipo novo na lista fechada e o modo dele
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_correcao_2910_revisao.sql
--   Sem as fixtures (produção) os cenários saem PULADO e só K, P e C rodam. Os cenários mexem em linhas só dentro de
--   subtransações desfeitas na hora; termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.igual(p_res jsonb, p_nome text, p_visto text, p_esperado text) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, p_visto is not distinct from p_esperado,
           case when p_visto is distinct from p_esperado then 'veio: ' || coalesce(p_visto, '(null)') end))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.modos(p_proposta text, p_vigia text) returns void language sql as $f$
  update public.agenda_config set modo_proposta = p_proposta, modo_vigia = p_vigia, modo_leitura = 'ligado' where id
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.vigiar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_vigiar(p_dia, pg_temp.em(p_dia, p_hora))
$f$;
-- O dono com o assistente no WhatsApp (o 1º admin ativo; a regra de donoDoWhatsApp).
create function pg_temp.dono() returns void language sql as $f$
  update public.app_users set ai_whatsapp_enabled = true, phone_normalized = '5547900000210'
   where id = 'aa000000-0000-4000-8000-000000000001'
$f$;
-- O texto como o montador (_shared/agenda/aviso-do-gestor.ts) o junta quando cabe no teto (o mesmo de agenda_correcao_2910_p4.sql).
create function pg_temp.montar(p jsonb) returns text language sql immutable as $f$
  select (p ->> 'cabecalho')
         || (select string_agg(E'\n• ' || (m ->> 'texto'), '' order by o) from jsonb_array_elements(p -> 'mudancas') with ordinality t(m, o))
         || coalesce(E'\n' || (p ->> 'fora'), '') || coalesce(E'\n' || (p ->> 'rodape'), '')
         || coalesce(E'\n\n' || (p #>> '{perguntas,texto}'), '')
$f$;
create function pg_temp.ids(p jsonb) returns uuid[] language sql immutable as $f$
  select array(select x::uuid from jsonb_array_elements(p -> 'mudancas') m, jsonb_array_elements_text(m -> 'acao_ids') x)
$f$;
create function pg_temp.pids(p jsonb) returns uuid[] language sql immutable as $f$
  select array(select x::uuid from jsonb_array_elements_text(case when jsonb_typeof(p -> 'perguntas') = 'object'
                                                                  then p #> '{perguntas,pergunta_ids}' else '[]'::jsonb end) x)
$f$;
-- Um tique do aviso como o task-automations faz: as peças e, quando é para avisar, o enfileirar com o texto montado.
create function pg_temp.avisar(p_dia date, p_hora text) returns jsonb language plpgsql as $f$
declare
  p jsonb := public.agenda_aviso_pecas(p_dia, pg_temp.em(p_dia, p_hora));
begin
  if not coalesce((p ->> 'avisar')::boolean, false) then
    return p || jsonb_build_object('enfileirou', false);
  end if;
  return public.agenda_aviso_enfileirar(pg_temp.montar(p), pg_temp.ids(p), pg_temp.pids(p), jsonb_typeof(p -> 'perguntas') = 'object',
                                        p_dia, pg_temp.em(p_dia, p_hora))
         || jsonb_build_object('pecas', p);
end $f$;
-- A fila mandou (o worker): as linhas agenda-dono pendentes saem na hora dada.
create function pg_temp.saiu(p_dia date, p_hora text) returns void language sql as $f$
  update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(p_dia, p_hora), attempts = attempts + 1
   where source = 'agenda-dono' and status = 'pending'
$f$;
-- Uma mudança da vigia (remanejo) gravada como o motor grava: executada, desfazível pelo prazo da agenda.
create function pg_temp.mover(p_em timestamptz) returns uuid language sql as $f$
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, texto, desfazivel_ate)
  select p_em, (p_em at time zone 'America/Sao_Paulo')::date, true, 'vigia', 'mover', so.id, array[so.id],
         'Vanderlei (OS-00069): de qua 04/11 para qui 05/11.', p_em + (select c.desfazer_validade from public.agenda_config c where c.id)
    from public.service_orders so where so.service_order_number = 'OS-00069'
  returning id
$f$;
-- As linhas do fechamento como o secretário as registra depois de enviar ({pergunta_id, acao_ids} de cada uma).
create function pg_temp.registrar_fechamento(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_fechamento_registrar(p_dia,
           (select coalesce(jsonb_agg(jsonb_build_object('pergunta_id', l -> 'pergunta_id', 'acao_ids', l -> 'acao_ids')), '[]'::jsonb)
              from jsonb_array_elements(public.agenda_textos_do_fechamento(p_dia, null) -> 'linhas') l),
           'fechamento', pg_temp.em(p_dia, p_hora))
$f$;
-- As perguntas de fato que o fechamento mostraria (linha e: tipo pergunta, ligado).
create function pg_temp.perguntas_do_fechamento(p_dia date) returns uuid[] language sql stable as $f$
  select array(select (l ->> 'pergunta_id')::uuid from jsonb_array_elements(public._agenda_linhas_do_fechamento(p_dia)) l
                where l ->> 'tipo' = 'pergunta' and l ->> 'modo' = 'ligado' and l ->> 'pergunta_id' is not null)
$f$;
-- O erro de um comando: 'ok' ou o sqlstate.
create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
begin
  begin
    execute p_sql;
    raise exception 'desfaz' using errcode = 'P0098';
  exception
    when sqlstate 'P0098' then return 'ok';
    when others then return sqlstate;
  end;
end $f$;
-- O corpo de uma função numa migration (entre o "as $function$" e o fecho) e a definição inteira.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
  v_i int := position('create or replace function public.' || p_nome || '(' in v);
  v_tag text;
begin
  if v_i = 0 then return null; end if;
  v := substr(v, v_i);
  v_tag := substring(v from E'\nas (\\$[a-z_]*\\$)\n');
  v := substr(v, position(E'\nas ' || v_tag in v) + length(E'\nas ' || v_tag));
  return left(v, position(v_tag in v) - 1);
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- As linhas fora dos blocos "-- CORREÇÃO 29/10 (revisão): … fim"; a linha que um bloco trocou ("-- antes: <a linha>") volta.
create function pg_temp.sem_revisao(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and l ~ '^\s*-- CORREÇÃO 29/10 \(revisão\):' and l !~ '^\s*-- CORREÇÃO 29/10 \(revisão\): fim' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro then
      if l ~ '^\s*-- CORREÇÃO 29/10 \(revisão\): fim' then
        v_dentro := false;
      elsif l ~ '^\s*-- antes: ' then
        v_fora := v_fora || regexp_replace(l, '^(\s*)-- antes: ', '\1');
      end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;

-- As definições de ANTES rodadas como pg_temp (a régua do que não muda): _agenda_linhas_do_fechamento (20261028100500),
-- agenda_aviso_pecas (20261030100300) e _agenda_mudancas (20261029100950).
do $antes$
declare
  v_f5 text := coalesce(current_setting('agenda_teste.mig_leituras_fase5', true), '');
  v_p4 text := coalesce(current_setting('agenda_teste.mig_correcao_aviso', true), '');
  v_c6 text := coalesce(current_setting('agenda_teste.mig_correcao_textos_fase6', true), '');
begin
  if v_f5 = '' or v_p4 = '' or v_c6 = '' then return; end if;
  execute replace(pg_temp.inteira(v_f5, '_agenda_linhas_do_fechamento'),
                  'create or replace function public._agenda_linhas_do_fechamento(', 'create function pg_temp.linhas_antes(');
  execute replace(pg_temp.inteira(v_p4, 'agenda_aviso_pecas'),
                  'create or replace function public.agenda_aviso_pecas(', 'create function pg_temp.pecas_antes(');
  execute replace(pg_temp.inteira(v_c6, '_agenda_mudancas'),
                  'create or replace function public._agenda_mudancas(', 'create function pg_temp.mudancas_antes(');
end
$antes$;

-- ── Os cenários de hoje (fixture-2310) ─────────────────────────────────────────────────────────────────────
do $hoje$
declare
  v_fix   boolean := exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000074')
                     and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002')
                     and to_regprocedure('pg_temp.linhas_antes(date)') is not null;
  c_qui   constant date := date '2026-10-29';
  c_sex   constant date := date '2026-10-30';
  c_sab   constant date := date '2026-10-31';
  c_dom   constant date := date '2026-11-01';
  c_seg   constant date := date '2026-11-02';
  c_dono  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_len   constant uuid := '05000000-0000-4000-8000-000000000074';
  c_alex  constant uuid := 'bb000000-0000-4000-8000-0000000000a1';
  c_linha_qui constant text := 'Livre de verdade: na semana de 03/11, Roberto 1 dia e meio, João nada; na de 09/11, Roberto 3 dias, João 1 dia.';
  c_linha_sab constant text := 'Livre de verdade: de qua 04 a sex 06/11, Roberto 1 dia, João nada; na semana de 09/11, Roberto 3 dias, João 1 dia.';
  -- (AJUSTADO em 30/10 pela correção da equipe: o texto novo, que pergunta os dias e não a diária)
  c_equipe constant text := 'Não consigo marcar nenhum dos 11 serviços que esperam: ninguém da equipe tem dias na agenda. Alex tem dias na agenda, mas não está na equipe. Se for, me diga em que dias vem. Por exemplo: "Alex vem de segunda a sexta".';
  v_res   jsonb := '[]'::jsonb;
  r       jsonb;
  e       jsonb;
  p       jsonb;
  p2      jsonb;
  d       jsonb;
  v_t     text;
  v_t2    text;
  v_pub   uuid[];
  v_pids  uuid[];
  v_id    uuid;
  v_ate   timestamptz;
  q       public.agenda_perguntas;
begin
  if not v_fix then
    insert into _resultado values ('D0..Q0 os cenários de hoje (fixture-2310)', true, 'PULADO: sem a fixture-2310 (rode pela bancada)');
    return;
  end if;

  -- ── D. (achado 1) o *desfaz* que o aviso promete vale desde que ele sai ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_qui, '16:30');
    v_pub := array(select a.id from public.agenda_acoes a where a.tipo = 'publicar' and a.executada order by a.id);
    v_ate := (select max(a.desfazivel_ate) from public.agenda_acoes a where a.id = any (v_pub));
    e := pg_temp.avisar(c_qui, '16:45');
    v_res := pg_temp.ok(v_res, 'D1 o enfileirar já leva o prazo do *desfaz semana* a qui 16:45 + 24 h (era o da publicação, sex 16:30)',
      (e ->> 'enfileirou')::boolean and cardinality(v_pub) > 0 and v_ate = pg_temp.em(c_sex, '16:30')
      and not exists (select 1 from public.agenda_acoes a where a.id = any (v_pub)
                       and (a.desfazivel_ate is distinct from pg_temp.em(c_sex, '16:45') or a.contada_via is distinct from 'aviso')),
      e::text);
    perform pg_temp.saiu(c_qui, '16:50');
    perform public.agenda_aviso_conferir(pg_temp.em(c_qui, '17:00'));
    v_res := pg_temp.ok(v_res, 'D2 o conferir ainda leva o prazo à hora do envio + 24 h (sex 16:50)',
      not exists (select 1 from public.agenda_acoes a where a.id = any (v_pub) and a.desfazivel_ate is distinct from pg_temp.em(c_sex, '16:50')),
      (select string_agg(a.desfazivel_ate::text, ', ') from public.agenda_acoes a where a.id = any (v_pub)));
    -- sábado 20:00 (fora da janela): a vigia remaneja o Vanderlei, desfazível até dom 20:00
    v_id := pg_temp.mover(pg_temp.em(c_sab, '20:00'));
    perform set_config('agenda.hoje', c_seg::text, true);
    e := pg_temp.avisar(c_seg, '09:30');
    v_res := pg_temp.ok(v_res, 'D3 seg 09:30: o aviso promete *desfaz Vanderlei* (o prazo de sábado venceu dom 20:00) e o prazo já vai a ter 03/11 09:30',
      (e ->> 'enfileirou')::boolean
      and e #>> '{pecas,mudancas,0,texto}' = 'Vanderlei (OS-00069): de qua 04/11 para qui 05/11. *desfaz Vanderlei* volta como estava.'
      and (select a.desfazivel_ate from public.agenda_acoes a where a.id = v_id) = pg_temp.em(date '2026-11-03', '09:30'),
      e::text);
    perform pg_temp.saiu(c_seg, '09:31');
    d := public.agenda_acao_desfazivel('Vanderlei', c_seg, pg_temp.em(c_seg, '09:35'));
    v_res := pg_temp.ok(v_res, 'D4 o dono responde *desfaz Vanderlei* às 09:35, antes do tique seguinte: acha a mudança (antes: "Não tenho mudança minha no Vanderlei para desfazer agora.")',
      d ->> 'status' = 'ok' and (d ->> 'acao_id')::uuid = v_id, d::text);
    perform public.agenda_aviso_conferir(pg_temp.em(c_seg, '09:45'));
    v_res := pg_temp.ok(v_res, 'D5 o conferir das 09:45 leva o prazo à hora do envio + 24 h (ter 03/11 09:31)',
      (select a.desfazivel_ate from public.agenda_acoes a where a.id = v_id) = pg_temp.em(date '2026-11-03', '09:31'),
      (select a.desfazivel_ate::text from public.agenda_acoes a where a.id = v_id));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- o 1º aviso depois do deploy: a publicação de qui 29/10 (prazo sex 16:30) contada só no sábado
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_qui, '16:30');
    v_pub := array(select a.id from public.agenda_acoes a where a.tipo = 'publicar' and a.executada order by a.id);
    perform set_config('agenda.hoje', c_sab::text, true);
    e := pg_temp.avisar(c_sab, '09:30');
    perform pg_temp.saiu(c_sab, '09:31');
    d := public.agenda_acao_desfazivel('semana', c_sab, pg_temp.em(c_sab, '09:35'));
    v_res := pg_temp.ok(v_res, 'D6 o 1º aviso conta no sábado a publicação de quinta (o prazo tinha vencido sex 16:30): *desfaz semana* às 09:35 acha a semana',
      (e ->> 'enfileirou')::boolean and d ->> 'status' = 'ok'
      and (select array_agg(x::uuid order by x::uuid) from jsonb_array_elements_text(d -> 'acao_ids') x) = v_pub,
      e::text || ' | ' || d::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- o aviso que não sai: as mudanças voltam a "por contar" e o prazo fica (o próximo aviso as conta dentro dele)
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_qui, '16:30');
    v_pub := array(select a.id from public.agenda_acoes a where a.tipo = 'publicar' and a.executada order by a.id);
    e := pg_temp.avisar(c_qui, '16:45');
    update public.whatsapp_send_queue set status = 'failed', failed_reason = 'teste' where source = 'agenda-dono';
    r := public.agenda_aviso_conferir(pg_temp.em(c_qui, '17:00'));
    p := public.agenda_aviso_pecas(c_sex, pg_temp.em(c_sex, '09:30'));
    v_res := pg_temp.ok(v_res, 'D7 o aviso que a fila não mandou devolve as mudanças (por contar), o prazo fica em sex 16:45 e o aviso de sex 09:30 as conta de novo',
      (r ->> 'devolvidas')::int = cardinality(v_pub)
      and not exists (select 1 from public.agenda_acoes a where a.id = any (v_pub)
                       and (a.contada_em is not null or a.desfazivel_ate is distinct from pg_temp.em(c_sex, '16:45')))
      and (p ->> 'avisar')::boolean and pg_temp.ids(p) @> v_pub,
      r::text || ' | ' || p::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── L. (achado 3) a linha curta do livre ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(c_qui, '16:30');
    v_t := public.agenda_livre_de_verdade(c_sab, pg_temp.em(c_sab, '10:00')) ->> 'texto';
    v_res := pg_temp.igual(v_res, 'L1 sáb 31/10: a 1ª semana que conta começa na quarta e sai com o rótulo do *livre* (não "na semana de 04/11")',
      v_t, c_linha_sab);
    v_res := pg_temp.igual(v_res, 'L2 dom 01/11: a mesma linha',
      public.agenda_livre_de_verdade(c_dom, pg_temp.em(c_dom, '10:00')) ->> 'texto', c_linha_sab);
    perform set_config('agenda.hoje', c_sab::text, true);
    v_t := public.agenda_ver(null, 'semana', null, null, null, null, false, c_sab) ->> 'texto';
    v_t2 := public.agenda_ver(null, null, null, 'livre', null, null, false, c_sab) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'L3 *agenda* de sábado traz a linha nova uma vez; o *livre* diz a mesma semana ("• De qua 04 a sex 06/11: Roberto 1 dia, João nada.")',
      v_t like '%' || E'\n' || c_linha_sab || E'\n' || '%' and v_t not like '%na semana de 04/11%'
      and v_t2 like '%' || E'\n' || '• De qua 04 a sex 06/11: Roberto 1 dia, João nada.' || E'\n' || '%', v_t || ' || ' || v_t2);
    v_res := pg_temp.igual(v_res, 'L4 qui 29/10 (a 1ª semana inteira): a linha de antes',
      public.agenda_livre_de_verdade(c_qui, pg_temp.em(c_qui, '17:00')) ->> 'texto', c_linha_qui);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── S. (achado 4) a concordância da conta do serviço novo ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(c_qui, '16:30');
    v_res := pg_temp.ok(v_res, 'S1 1 dia com o Roberto: "(é 1 diária de equipe)"',
      public.agenda_simular(1, '["Roberto"]'::jsonb, null, c_dono, c_qui) ->> 'texto'
        like 'Um serviço de 1 dia com Roberto (é 1 diária de equipe): pelo plano de agora, cabe em %', null);
    v_res := pg_temp.ok(v_res, 'S2 meio dia com o João: "(é meia diária de equipe)"',
      public.agenda_simular(0.5, '["João"]'::jsonb, null, c_dono, c_qui) ->> 'texto'
        like 'Um serviço de meio dia com João (é meia diária de equipe): pelo plano de agora, cabe em %', null);
    v_res := pg_temp.ok(v_res, 'S3 2 dias com o Roberto: "(são 2 diárias de equipe)", como antes',
      public.agenda_simular(2, '["Roberto"]'::jsonb, null, c_dono, c_qui) ->> 'texto'
        like 'Um serviço de 2 dias com Roberto (são 2 diárias de equipe): %', null);
    perform pg_temp.modos('sombra', 'sombra');
    v_t := public.agenda_simular(0.5, '["João"]'::jsonb, null, c_dono, c_qui) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'S4 fora de ligado (a projeção da Fase 1) também: "(é meia diária de equipe)"',
      v_t like 'Um serviço de meio dia com João (é meia diária de equipe): no fim da fila, %', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── E. (achado 5) a equipe sem dias ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(c_qui, '16:30');
    v_res := pg_temp.ok(v_res, 'E0 com a equipe da fixture (Roberto e João com os dias da semente), nada: "a equipe tem dias"',
      r #>> '{contagens,equipe_sem_dias,motivo}' = 'a equipe tem dias'
      and not exists (select 1 from public.agenda_perguntas x where x.tipo = 'equipe_sem_dias'), (r -> 'contagens' -> 'equipe_sem_dias')::text);
    select x.* into q from public.agenda_perguntas x where x.chave = 'material_conferir:' || c_len and x.estado = 'aberta';
    r := pg_temp.vigiar(c_qui, '16:45');
    v_res := pg_temp.ok(v_res, 'E1 com a reserva do Lenine de pé, a pergunta "Guardei lugar a partir de qui 05/11" continua aberta',
      q.id is not null and q.texto like '%Guardei lugar a partir de qui 05/11%'
      and (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'aberta', q.texto);
    -- produção, 29/10 21:11 (00:11 UTC de 30/10): "os três saíram" (Roberto, João, Mickael) — e o Alex sem a diária
    -- cadastrada (work_profiles). AJUSTADO em 30/10 pela correção da equipe: os dias do Alex só anotados pelo assistente
    -- (origem agente; declarados pelo dono, como em produção, ele conta e nada aqui nasce: agenda_correcao_2910_equipe.sql)
    update public.agenda_disponibilidade set substituida_em = pg_temp.em(c_qui, '21:11')
     where substituida_em is null and payee_id in ('bb000000-0000-4000-8000-000000000002', 'bb000000-0000-4000-8000-000000000003',
                                                   'bb000000-0000-4000-8000-000000000004');
    insert into public.payees (id, name, kind, active) values (c_alex, 'Alex Gonçalves Machado', 'prestador', true);
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho)
    values (c_alex, '{1,2,3,4,5}', null, 'disponivel', 'agente', 'anotado pelo assistente', null);
    r := pg_temp.vigiar(c_sex, '00:15');
    v_res := pg_temp.ok(v_res, 'E2 00:15: a vigia cancela a reserva do Lenine (como em produção) e pergunta da equipe sem dias, com o Alex pelo nome',
      exists (select 1 from public.agenda_acoes a where a.executada and a.tipo = 'cancelar' and a.service_order_id = c_len
               and a.texto = 'Lenine (OS-00074): sai qui 05, sex 06 e ter 10/11 — quem ia não está mais livre.')
      and r -> 'contagens' -> 'equipe_sem_dias' = '{"criada": true, "motivo": "ninguém da equipe tem dias", "servicos": 11, "sem_diaria": ["Alex"]}'::jsonb,
      (r -> 'contagens' -> 'equipe_sem_dias')::text);
    select x.* into q from public.agenda_perguntas x where x.tipo = 'equipe_sem_dias';
    v_res := pg_temp.igual(v_res, 'E3 a pergunta: o texto (o que fazer, sem jargão)', q.texto, c_equipe);
    v_res := pg_temp.ok(v_res, 'E4 a pergunta: uma por semana (equipe_sem_dias:2026-10-26), de verdade (ligado), não crítica, perde no dia do plano (qui 05/11) e vence na segunda (02/11 00:00)',
      q.chave = 'equipe_sem_dias:2026-10-26' and q.modo = 'ligado' and not q.critica and q.estado = 'aberta'
      and q.perda_em = date '2026-11-05' and q.expira_em = pg_temp.em(c_seg, '00:00'), to_jsonb(q)::text);
    r := pg_temp.vigiar(c_sex, '00:30');
    v_res := pg_temp.ok(v_res, 'E5 00:30: a pergunta do Lenine resolve ("a reserva saiu…"), a dos seus dias continua, e a da equipe não se repete',
      (select x.estado || ' | ' || x.resolvida_motivo from public.agenda_perguntas x where x.chave = 'material_conferir:' || c_len)
        = 'resolvida | a reserva saiu: o lugar que eu tinha guardado não existe mais'
      and exists (select 1 from public.agenda_perguntas x where x.chave = 'padrao_do_dono:sem_dias' and x.estado = 'aberta')
      and (select count(*) from public.agenda_perguntas x where x.tipo = 'equipe_sem_dias') = 1
      and r #>> '{contagens,equipe_sem_dias,motivo}' = 'já perguntei nesta semana',
      (select string_agg(x.chave || '=' || x.estado, ', ') from public.agenda_perguntas x));
    v_t := (select string_agg(l ->> 'texto', E'\n') from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_sex)) l
             where l ->> 'modo' = 'ligado');
    v_res := pg_temp.ok(v_res, 'E6 o fechamento de sex 30/10 mostra a pergunta da equipe e não diz mais "Guardei lugar"',
      v_t like '%Agenda: ' || c_equipe || '%' and v_t not like '%Guardei lugar%', v_t);
    -- a semana seguinte, a equipe ainda sem dias: a da semana passada vence, e nasce a desta
    r := pg_temp.vigiar(c_seg, '08:00');
    v_res := pg_temp.ok(v_res, 'E7 seg 02/11: a da semana passada vence e nasce a desta semana (equipe_sem_dias:2026-11-02)',
      (select x.estado from public.agenda_perguntas x where x.chave = 'equipe_sem_dias:2026-10-26') = 'vencida'
      and (select x.estado from public.agenda_perguntas x where x.chave = 'equipe_sem_dias:2026-11-02') = 'aberta',
      (select string_agg(x.chave || '=' || x.estado, ', ') from public.agenda_perguntas x where x.tipo = 'equipe_sem_dias'));
    -- o dono cadastra a diária do Alex ("cadastre o Alex, diária de 200")
    insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio)
    values (c_alex, 'diarista', 'diaria', 200, c_sex);
    r := pg_temp.vigiar(c_seg, '08:15');
    v_res := pg_temp.ok(v_res, 'E8 com a diária do Alex cadastrada, a pergunta resolve ("alguém da equipe voltou a ter dias na agenda") e não volta',
      (select x.estado || ' | ' || x.resolvida_motivo from public.agenda_perguntas x where x.chave = 'equipe_sem_dias:2026-11-02')
        = 'resolvida | alguém da equipe voltou a ter dias na agenda'
      and r #>> '{contagens,equipe_sem_dias,motivo}' in ('a equipe tem dias', 'já perguntei nesta semana'),
      (r -> 'contagens' -> 'equipe_sem_dias')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'desligado');
    r := pg_temp.vigiar(c_qui, '16:30');
    v_res := pg_temp.ok(v_res, 'E9 com a vigia desligada o passo não roda (nem na contagem, nem no tempo)',
      not (r -> 'contagens' ? 'equipe_sem_dias')
      and not ((select x.contagens -> 'ms' from public.agenda_vigia_rodadas x
                 where x.p_agora = pg_temp.em(c_qui, '16:30') order by x.rodou_em desc limit 1) ? 'equipe_sem_dias'),
      (r -> 'contagens')::text);
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(c_qui, '16:45');
    v_res := pg_temp.ok(v_res, 'E10 com a vigia ligada, o tempo do passo entra em contagens.ms',
      (select jsonb_typeof(x.contagens -> 'ms' -> 'equipe_sem_dias') from public.agenda_vigia_rodadas x
        where x.p_agora = pg_temp.em(c_qui, '16:45') order by x.rodou_em desc limit 1) = 'number', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── F. (achado 6) o aviso espera o fechamento ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_qui, '16:30');
    v_pub := array(select a.id from public.agenda_acoes a where a.tipo = 'publicar' and a.executada order by a.id);
    v_res := pg_temp.igual(v_res, 'F1 a pausa: de seg a sex, de 17:25 (inclusive) a 18:00 (aberto), em Brasília; nunca no sábado nem no domingo',
      (select string_agg(public._agenda_aviso_espera_o_fechamento(pg_temp.em(x.d, x.h))::text, ',' order by x.o)
         from (values (1, c_qui, '17:24:59'), (2, c_qui, '17:25'), (3, c_qui, '17:59:59'), (4, c_qui, '18:00'),
                      (5, c_seg, '17:30'), (6, c_sex, '17:50'), (7, c_sab, '17:30'), (8, c_dom, '17:30')) x(o, d, h)),
      'false,true,true,false,true,true,false,false');
    p := public.agenda_aviso_pecas(c_qui, pg_temp.em(c_qui, '17:30'));
    e := public.agenda_aviso_enfileirar('Agenda — o que eu mudei sozinho:' || E'\n• teste', v_pub, '{}', false, c_qui, pg_temp.em(c_qui, '17:30'));
    v_res := pg_temp.ok(v_res, 'F2 às 17:30 nem as peças nem a 1ª trava avisam (motivo fechamento) e nada é gravado',
      p = '{"avisar": false, "motivo": "fechamento", "pendentes": 1}'::jsonb
      and e = '{"enfileirou": false, "motivo": "fechamento"}'::jsonb
      and not exists (select 1 from public.agenda_dono_avisos) and not exists (select 1 from public.whatsapp_send_queue w where w.source = 'agenda-dono')
      and not exists (select 1 from public.agenda_acoes a where a.id = any (v_pub) and a.contada_em is not null),
      p::text || ' | ' || e::text);
    v_res := pg_temp.ok(v_res, 'F3 fora da pausa o aviso sai: qui 17:24, qui 18:00 e sáb 17:30',
      (public.agenda_aviso_pecas(c_qui, pg_temp.em(c_qui, '17:24')) ->> 'avisar')::boolean
      and (public.agenda_aviso_pecas(c_qui, pg_temp.em(c_qui, '18:00')) ->> 'avisar')::boolean
      and (public.agenda_aviso_pecas(c_sab, pg_temp.em(c_sab, '17:30')) ->> 'avisar')::boolean, null);
    -- a corrida das 17:30: o fechamento lê, o aviso do mesmo minuto espera, o fechamento registra o que mostrou
    v_t := (select string_agg(l ->> 'texto', E'\n') from jsonb_array_elements(public.agenda_textos_do_fechamento(c_qui, null) -> 'linhas') l
             where l ->> 'tipo' = 'semana');
    e := pg_temp.avisar(c_qui, '17:30');
    r := pg_temp.registrar_fechamento(c_qui, '17:30:15');
    p := public.agenda_aviso_pecas(c_qui, pg_temp.em(c_qui, '18:00'));
    v_res := pg_temp.ok(v_res, 'F4 a corrida das 17:30 dá UMA mensagem: o fechamento conta a semana, o aviso das 17:30 esperou e o das 18:00 não tem nada novo',
      v_t like 'Agenda: publiquei a semana de 03 a 06/11 (seg 02 é Finados)%' and not (e ->> 'enfileirou')::boolean
      and (r ->> 'acoes')::int = cardinality(v_pub) and p = '{"avisar": false, "motivo": "nada_mudou"}'::jsonb
      and not exists (select 1 from public.whatsapp_send_queue w where w.source = 'agenda-dono'),
      v_t || ' | ' || e::text || ' | ' || r::text || ' | ' || p::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── Q. (achado 7) a pergunta sai uma vez por dia ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_qui, '16:30');
    e := pg_temp.avisar(c_qui, '16:45');
    v_pids := pg_temp.pids(e -> 'pecas');
    perform pg_temp.saiu(c_qui, '16:50');
    perform public.agenda_aviso_conferir(pg_temp.em(c_qui, '17:00'));
    v_res := pg_temp.ok(v_res, 'Q1 o aviso das 16:45 levou as perguntas (saiu 16:50): o fechamento das 17:30 não as repete (elas ainda caberiam: mostradas 1 vez de 2)',
      cardinality(v_pids) > 0 and not (pg_temp.perguntas_do_fechamento(c_qui) && v_pids)
      and not exists (select 1 from public.agenda_perguntas x where x.id = any (v_pids) and (x.mostrada_vezes <> 1 or x.estado <> 'aberta')),
      v_pids::text || ' × ' || pg_temp.perguntas_do_fechamento(c_qui)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_qui, '16:30');
    e := pg_temp.avisar(c_qui, '16:45');
    v_pids := pg_temp.pids(e -> 'pecas');
    v_res := pg_temp.ok(v_res, 'Q2 com o aviso ainda na fila, o fechamento também não as repete',
      cardinality(v_pids) > 0 and not (pg_temp.perguntas_do_fechamento(c_qui) && v_pids), null);
    update public.whatsapp_send_queue set status = 'failed', failed_reason = 'teste' where source = 'agenda-dono';
    perform public.agenda_aviso_conferir(pg_temp.em(c_qui, '17:00'));
    v_res := pg_temp.ok(v_res, 'Q3 o aviso que não saiu não conta: o fechamento mostra a pergunta dele',
      pg_temp.perguntas_do_fechamento(c_qui) && v_pids, pg_temp.perguntas_do_fechamento(c_qui)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_qui, '16:30');
    v_pids := pg_temp.perguntas_do_fechamento(c_qui);
    -- sem o fechamento (a régua): o aviso das 18:00 levaria as perguntas
    p2 := public.agenda_aviso_pecas(c_qui, pg_temp.em(c_qui, '18:00'));
    r := pg_temp.registrar_fechamento(c_qui, '17:30:15');
    v_id := pg_temp.mover(pg_temp.em(c_qui, '17:45'));
    p := public.agenda_aviso_pecas(c_qui, pg_temp.em(c_qui, '18:00'));
    v_res := pg_temp.ok(v_res, 'Q4 o fechamento das 17:30 mostrou a pergunta do Lenine: o aviso das 18:00 conta o remanejo e deixa as perguntas para amanhã (sem o fechamento, levaria)',
      cardinality(v_pids) = 1 and pg_temp.pids(p2) && v_pids and jsonb_typeof(p2 -> 'perguntas') = 'object'
      and (p ->> 'avisar')::boolean and p -> 'perguntas' = 'null'::jsonb
      and pg_temp.ids(p) = array[v_id],
      p::text);
    v_id := pg_temp.mover(pg_temp.em(c_sex, '09:00'));
    perform set_config('agenda.hoje', c_sex::text, true);
    p := public.agenda_aviso_pecas(c_sex, pg_temp.em(c_sex, '09:30'));
    v_res := pg_temp.ok(v_res, 'Q5 no dia seguinte o 1º aviso leva as perguntas de novo',
      (p ->> 'avisar')::boolean and jsonb_typeof(p -> 'perguntas') = 'object' and pg_temp.pids(p) && v_pids, p::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── N. O que não muda ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.dono();
    perform pg_temp.vigiar(c_qui, '16:30');
    v_res := pg_temp.ok(v_res, 'N1 sem aviso no dia, as linhas do fechamento são as de antes, byte a byte (ligado)',
      public._agenda_linhas_do_fechamento(c_qui) = pg_temp.linhas_antes(c_qui), null);
    v_res := pg_temp.ok(v_res, 'N2 fora da pausa e sem pergunta mostrada hoje, as peças do aviso são as de antes, byte a byte (qui 16:45)',
      public.agenda_aviso_pecas(c_qui, pg_temp.em(c_qui, '16:45')) = pg_temp.pecas_antes(c_qui, pg_temp.em(c_qui, '16:45')), null);
    v_res := pg_temp.ok(v_res, 'N3 sem aprendizado, o *o que mudou* é o de antes, byte a byte',
      public._agenda_mudancas(c_qui - 6, c_qui, true, true, null) = pg_temp.mudancas_antes(c_qui - 6, c_qui, true, true, null)
      and public._agenda_mudancas(c_qui - 6, c_qui, true, false, pg_temp.em(c_qui, '17:00'))
          = pg_temp.mudancas_antes(c_qui - 6, c_qui, true, false, pg_temp.em(c_qui, '17:00')), null);
    perform pg_temp.modos('sombra', 'sombra');
    perform pg_temp.vigiar(c_qui, '16:45');
    v_res := pg_temp.ok(v_res, 'N4 em sombra, as linhas do fechamento são as de antes, byte a byte',
      public._agenda_linhas_do_fechamento(c_qui) = pg_temp.linhas_antes(c_qui), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$hoje$;

-- ── O. (achado 2) a ordem fixa do aprendizado (fixture-fase6: o cenário do R10g de agenda_fase6_rodada.sql) ──
do $ordem$
declare
  c_dono constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v_res  jsonb := '[]'::jsonb;
  v_m    jsonb;
  v_ord  text;
  v_f    text;
  v_txt  text[] := '{}';
  k      int;
begin
  if coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('O0 a ordem do aprendizado (fixture-fase6)', true, 'PULADO: sem agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  for k in 1 .. 2 loop
    begin
      execute current_setting('agenda_teste.fase6');
      update public.agenda_config set modo_aprendizado = 'sombra', aprendizado_ligados = '{}' where id;
      perform public.agenda_aprender(date '2026-10-29', pg_temp.em(date '2026-10-29', '16:05'));
      update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = '{fator,presenca,fornecedor,aviso_cliente}' where id;
      perform public.agenda_aprender(date '2026-10-30', pg_temp.em(date '2026-10-30', '16:05'));
      v_m := public._agenda_mudancas(date '2026-10-30', date '2026-10-30', true, true, pg_temp.em(date '2026-10-30', '17:30'));
      select string_agg(a.antes ->> 'item', ',' order by t.o) into v_ord
        from jsonb_array_elements(v_m) with ordinality t(g, o)
        join public.agenda_acoes a on a.id = (t.g -> 'acao_ids' ->> 0)::uuid and a.tipo = 'aprendizado';
      v_f := public.agenda_ver(c_dono, null, null, 'mudancas', null, null, false, date '2026-10-30') ->> 'texto';
      if k = 1 then
        v_res := pg_temp.igual(v_res, 'O1 o aprendizado do mesmo instante sai na ordem fixa: fator, presença, folga, atraso e prazo do fornecedor',
          v_ord, 'fator,presenca,aviso_folga,fornecedor_atraso,fornecedor_prazo');
        v_res := pg_temp.ok(v_res, 'O2 a frase do *desfaz aprendizado* vem UMA vez, na 1ª linha do aprendizado (a do fator)',
          (select t.g -> 'itens' ->> 0 from jsonb_array_elements(v_m) with ordinality t(g, o)
            join public.agenda_acoes a on a.id = (t.g -> 'acao_ids' ->> 0)::uuid and a.antes ->> 'item' = 'fator')
            like '%*desfaz aprendizado* volta tudo; *desfaz aprendizado fator* volta só essa.'
          and (length(v_m::text) - length(replace(v_m::text, '*desfaz aprendizado* volta tudo', ''))) / length('*desfaz aprendizado* volta tudo') = 1,
          v_m::text);
        v_res := pg_temp.ok(v_res, 'O3 o *o que mudou* traz o "Aprendi com as OS concluídas" (o R10g de agenda_fase6_rodada.sql, que falhava às vezes)',
          v_f like '%Aprendi com as OS concluídas%', v_f);
      end if;
      v_txt := v_txt || v_f;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'O4 duas rodadas do zero (outros ids) dão o mesmo *o que mudou*, letra a letra',
    cardinality(v_txt) = 2 and v_txt[1] = v_txt[2], array_to_string(v_txt, ' ≠ '));
  perform pg_temp.gravar(v_res);
end
$ordem$;

-- ── K. As cópias (sempre que as migrations de origem vierem como texto) ─────────────────────────────────────
do $copia$
declare
  f record;
  v_fonte text;
  v_novo text;
  v_mig text;
begin
  for f in select * from (values
      ('agenda_aviso_enfileirar', 'public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz)', 'mig_correcao_aviso', '20261030100300', 2),
      ('agenda_aviso_pecas', 'public.agenda_aviso_pecas(date, timestamptz)', 'mig_correcao_aviso', '20261030100300', 2),
      ('_agenda_linhas_do_fechamento', 'public._agenda_linhas_do_fechamento(date)', 'mig_leituras_fase5', '20261028100500', 2),
      ('_agenda_mudancas', 'public._agenda_mudancas(date, date, boolean, boolean, timestamptz)', 'mig_correcao_textos_fase6', '20261029100950', 4),
      ('agenda_livre_de_verdade', 'public.agenda_livre_de_verdade(date, timestamptz)', 'mig_correcao_livre', '20261030100100', 2),
      ('agenda_simular', 'public.agenda_simular(numeric, jsonb, text, uuid, date)', 'mig_correcao_livre', '20261030100100', 1),
      ('_agenda_modo_da_pergunta', 'public._agenda_modo_da_pergunta(text, text)', 'mig_correcao_motor', '20261030100200', 1),
      ('_agenda_vigia_limpeza', 'public._agenda_vigia_limpeza(date, timestamptz)', 'mig_correcao_motor', '20261030100200', 1),
      ('agenda_vigiar', 'public.agenda_vigiar(date, timestamptz)', 'mig_correcao_desempenho', '20261030100400', 1))
      as x(nome, sig, mig, versao, blocos) loop
    v_mig := coalesce(current_setting('agenda_teste.' || f.mig, true), '');
    if v_mig = '' then
      insert into _resultado values (format('K1 %s: a cópia', f.nome), true,
        format('PULADO: sem agenda_teste.%s (rode pela bancada)', f.mig));
      continue;
    end if;
    v_fonte := pg_temp.corpo(v_mig, f.nome);
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    insert into _resultado values (
      format('K1 %s: sem os blocos "-- CORREÇÃO 29/10 (revisão):" (e com a linha trocada de volta), é o corpo de %s (com %s blocos)',
             f.nome, f.versao, f.blocos),
      v_fonte is not null and pg_temp.sem_revisao(v_novo) = v_fonte
      and (select count(*) from regexp_matches(v_novo, '-- CORREÇÃO 29/10 \(revisão\): fim', 'g')) = f.blocos,
      format('fonte %s × novo sem blocos %s caracteres; blocos %s', length(v_fonte), length(pg_temp.sem_revisao(v_novo)),
             (select count(*) from regexp_matches(v_novo, '-- CORREÇÃO 29/10 \(revisão\): fim', 'g'))));
  end loop;
end
$copia$;

-- ── P. Portas (sempre) ───────────────────────────────────────────────────────────────────────────────────
with f(sig) as (values ('public._agenda_aviso_espera_o_fechamento(timestamptz)'), ('public._agenda_equipe_tem_dias(date)'),
                       ('public._agenda_vigia_equipe_sem_dias(date, timestamptz)'))
insert into _resultado
select 'P1 as 3 novas são peças de dentro: ninguém de fora (nem anon, nem authenticated, nem service_role); invoker, search_path fixo',
       bool_and(not has_function_privilege('anon', f.sig, 'execute') and not has_function_privilege('authenticated', f.sig, 'execute')
                and not has_function_privilege('service_role', f.sig, 'execute')
                and not p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'), null
  from f join pg_proc p on p.oid = f.sig::regprocedure;
with f(sig) as (values ('public.agenda_aviso_pecas(date, timestamptz)'),
                       ('public.agenda_aviso_enfileirar(text, uuid[], uuid[], boolean, date, timestamptz)'),
                       ('public.agenda_vigiar(date, timestamptz)'), ('public._agenda_modo_da_pergunta(text, text)'))
insert into _resultado
select 'P2 as recriadas do motor e do aviso continuam só do service_role',
       bool_and(not has_function_privilege('anon', sig, 'execute') and not has_function_privilege('authenticated', sig, 'execute')
                and has_function_privilege('service_role', sig, 'execute')), null
  from f;
insert into _resultado
select 'P3 a limpeza da vigia continua sem ninguém de fora (só a agenda_vigiar, definer, a chama)',
       not has_function_privilege('anon', 'public._agenda_vigia_limpeza(date, timestamptz)', 'execute')
       and not has_function_privilege('authenticated', 'public._agenda_vigia_limpeza(date, timestamptz)', 'execute')
       and not has_function_privilege('service_role', 'public._agenda_vigia_limpeza(date, timestamptz)', 'execute'), null;
with f(sig) as (values ('public._agenda_linhas_do_fechamento(date)'), ('public._agenda_mudancas(date, date, boolean, boolean, timestamptz)'),
                       ('public.agenda_livre_de_verdade(date, timestamptz)'), ('public.agenda_simular(numeric, jsonb, text, uuid, date)'))
insert into _resultado
select 'P4 as leituras recriadas continuam fechadas para anon', bool_and(not has_function_privilege('anon', sig, 'execute')), null
  from f;

-- ── C. Os parâmetros novos, os CHECKs e o tipo novo (sempre) ──────────────────────────────────────────────
insert into _resultado
select 'C1 a pausa do aviso durante o fechamento: 17:25 a 18:00 na linha; NOT NULL com DEFAULT',
       c.gestor_aviso_pausa_inicio = time '17:25' and c.gestor_aviso_pausa_fim = time '18:00'
       and (select bool_and(a.attnotnull and a.atthasdef) from pg_attribute a
             where a.attrelid = 'public.agenda_config'::regclass and a.attname like 'gestor_aviso_pausa_%' and not a.attisdropped
             having count(*) = 2),
       format('%s a %s', c.gestor_aviso_pausa_inicio, c.gestor_aviso_pausa_fim)
  from public.agenda_config c where c.id;
insert into _resultado
select 'C2 os CHECKs recusam o início antes de 16:00, o fim depois de 20:00 e o fim antes do início; aceitam 16:00 a 20:00',
       pg_temp.erro_de('update public.agenda_config set gestor_aviso_pausa_inicio = ''15:59'' where id') = '23514'
       and pg_temp.erro_de('update public.agenda_config set gestor_aviso_pausa_fim = ''20:01'' where id') = '23514'
       and pg_temp.erro_de('update public.agenda_config set gestor_aviso_pausa_inicio = ''17:50'', gestor_aviso_pausa_fim = ''17:40'' where id') = '23514'
       and pg_temp.erro_de('update public.agenda_config set gestor_aviso_pausa_inicio = ''16:00'', gestor_aviso_pausa_fim = ''20:00'' where id') = 'ok',
       null;
insert into _resultado
select 'C3 a lista fechada dos tipos de pergunta: as 26 de antes e equipe_sem_dias (27); "outro" é recusado',
       (select count(*) from (select unnest(regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g'))
                                from pg_constraint c where c.conname = 'agenda_perguntas_tipo_check') y) = 27
       and pg_get_constraintdef((select c.oid from pg_constraint c where c.conname = 'agenda_perguntas_tipo_check')) like '%''equipe_sem_dias''%'
       and pg_temp.erro_de($q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('outro', 'outro:t', 'Pergunta?', 'sombra')$q$) = '23514',
       null;
insert into _resultado
select 'C4 a equipe sem dias é da vigia (o modo de quem a faz)',
       public._agenda_modo_da_pergunta('equipe_sem_dias', 'equipe_sem_dias:2026-10-26') = c.modo_vigia, null
  from public.agenda_config c where c.id;

select teste, ok, detalhe from _resultado order by teste;

rollback;
