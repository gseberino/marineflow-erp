-- Retorno F1 (P8): retorno_vigia_silencio, o vigia de silêncio de ENTRADA (F0b-8), em sombra.
-- Em dia útil, na janela 09:00 + 3 h até 18:00, registra 3 h sem recebida de fora da equipe (pela hora de
-- gravação) com saída humana no período; a equipe, o grupo e a transmissão não zeram o relógio; sem saída
-- humana não registra (os dois lados quietos); fora do dia útil ou da janela só fecha os abertos; desligado
-- (ou sem a configuração) não faz nada; caiu_avisado pelo aviso whatsapp_caiu; a linha "do futuro"
-- (recebida, saída ou aviso depois do agora) não muda o resultado; nunca manda nada.
-- No fim, o REPLAY INFORMATIVO de 60 dias (a consulta r31 com as regras da função), sem falhar: os números
-- vão para _bancada.numeros -> 'replay_60d', porque a CLI não mostra raise notice.
-- Datas FUTURAS (01–06/12/2026: não há mensagem real nelas) e telefones de teste 55479000092xx. A janela do
-- silêncio é fixada no arranjo (a de produção pode mudar); o sábado só é conferido como "fora" enquanto
-- agenda_dia_util o disser (agenda_config.sabado_util, congelado, não é tocado).
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_silencio.sql
-- Termina em ROLLBACK: nada fica gravado. O arranjo inteiro é desfeito dentro do arquivo (sub-bloco que
-- termina em 'desfaz'), inclusive o fechamento de silêncios reais abertos que o passo 6 faria.
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

do $silencio$
declare
  v_f record;
  v_modo_antes text;
  v_cfg_antes jsonb;
  v_sabado_util boolean;
  v_user uuid;
  v_payee uuid;
  v_out uuid;
  v_eco uuid;
  v_tela uuid;
  v_estado_0112 text;
  v_estado_0312 text;
  v_r jsonb;
  v_r2 jsonb;
  v_s record;
  v_n int;
  v_chamadas int := 0;
  v_linhas int := 0;
  v_chegou boolean := false;
begin
  -- ── 0. A função, a view, o cron e o terreno ─────────────────────────────────────────────────────────
  select p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config into v_f
    from pg_proc p where p.oid = to_regprocedure('public.retorno_vigia_silencio(timestamptz)');
  if not found then
    raise exception '0: retorno_vigia_silencio não existe';
  end if;
  if v_f.provolatile <> 'v' or not v_f.prosecdef or not ('search_path=public' = any (v_f.config)) then
    raise exception '0b: retorno_vigia_silencio não é VOLATILE + SECURITY DEFINER com search_path = public';
  end if;
  if has_function_privilege('anon', 'public.retorno_vigia_silencio(timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.retorno_vigia_silencio(timestamptz)', 'execute')
     or not has_function_privilege('service_role', 'public.retorno_vigia_silencio(timestamptz)', 'execute') then
    raise exception '0c: retorno_vigia_silencio não é só do service_role';
  end if;
  if to_regclass('public.retorno_silencios_comparados') is null then
    raise exception '0d: a view retorno_silencios_comparados não existe';
  end if;
  if not exists (select 1 from pg_class c, unnest(coalesce(c.reloptions, '{}')) o
                  where c.oid = 'public.retorno_silencios_comparados'::regclass and o ~* '^security_invoker=(on|true|yes|1)$')
     or has_table_privilege('anon', 'public.retorno_silencios_comparados', 'select')
     or has_table_privilege('authenticated', 'public.retorno_silencios_comparados', 'select')
     or not has_table_privilege('service_role', 'public.retorno_silencios_comparados', 'select')
     or has_table_privilege('service_role', 'public.retorno_silencios_comparados', 'insert, update, delete') then
    raise exception '0d: retorno_silencios_comparados sem security_invoker, aberta além do service_role ou com escrita';
  end if;
  if not exists (select 1 from cron.job j
                  where j.jobname = 'retorno-silencio' and j.schedule = '*/15 12-21 * * 1-5' and j.active
                    and position('public.retorno_vigia_silencio(now())' in j.command) > 0
                    and position('http' in j.command) = 0) then
    raise exception '0e: o cron retorno-silencio não está a cada 15 min, seg–sex, 12–21 UTC, pura SQL';
  end if;
  if not (public.agenda_dia_util('2026-12-01') and public.agenda_dia_util('2026-12-02')
          and public.agenda_dia_util('2026-12-03') and public.agenda_dia_util('2026-12-04'))
     or public.agenda_dia_util('2026-12-06') then
    raise exception '0f: 01–04/12/2026 deixaram de ser dias úteis (agenda_disponibilidade?) ou o domingo virou útil: troque as datas do teste';
  end if;
  v_sabado_util := public.agenda_dia_util('2026-12-05');
  if exists (select 1 from (select public._agenda_chave_telefone(u.phone_normalized) as k from public.app_users u
                            union all select public._agenda_chave_telefone(u.phone) from public.app_users u
                            union all select public._agenda_chave_telefone(p.phone) from public.payees p) e
              where e.k like '000092%')
     or exists (select 1 from public.whatsapp_messages m
                 where m.phone_normalized like '55479000092%' or m.phone_normalized like '%900009201@g.us'
                    or (m.occurred_at >= '2026-12-01 00:00-03' and m.occurred_at < '2026-12-07 00:00-03'))
     or exists (select 1 from public.retorno_silencios s where s.dia between '2026-12-01' and '2026-12-06')
     or exists (select 1 from public.app_notifications n
                 where n.created_at >= '2026-12-01 00:00-03' and n.created_at < '2026-12-07 00:00-03') then
    raise exception '0g: há equipe na faixa 55479000092xx, ou mensagem, silêncio ou aviso em 01–06/12/2026 (sobra de teste ou dado real)';
  end if;
  select to_jsonb(c) - 'atualizado_em', c.silencio_modo into v_cfg_antes, v_modo_antes from public.retorno_config c where c.id;
  if not found then
    raise exception '0h: retorno_config sem a linha de configuração';
  end if;
  select u.id into v_user from public.app_users u where u.active order by u.created_at limit 1;
  if v_user is null then
    raise exception '0i: nenhum app_users ativo para o aviso sintético e o sent_by';
  end if;
  -- O estado da conexão que a função deve gravar: o de hoje, se começou até a hora da detecção.
  select c.estado into v_estado_0112 from public.whatsapp_conexao_vigia c where c.desde <= '2026-12-01 13:10-03' order by c.id limit 1;
  select c.estado into v_estado_0312 from public.whatsapp_conexao_vigia c where c.desde <= '2026-12-03 13:15-03' order by c.id limit 1;

  begin
    -- A janela do teste: 09:00–18:00, 3 h (a de produção pode ter mudado).
    update public.retorno_config
       set silencio_modo = 'sombra', silencio_inicio = '09:00', silencio_fim = '18:00', silencio_horas = '3 hours'
     where id;

    -- Equipe sintética (a função usa todas as linhas de payees, ativas ou não).
    insert into public.payees (name, phone) values ('Teste F1 silêncio equipe', '(47) 90000-9203') returning id into v_payee;

    -- Tudo é gravado ANTES das chamadas: cada chamada só pode enxergar o que tem hora <= agora.
    -- ter 01/12: recebida de fora 10:00; saída automática 11:00 (não conta); grupo 11:30, transmissão 11:45 e
    -- equipe 12:00 (não zeram o relógio); saída humana 12:30 (raw_payload nulo); aviso de queda 13:15 e
    -- recebida de fora 13:20 (as duas "do futuro" para a chamada das 13:10).
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at)
    values ('inbound', '5547900009201', 'text', 'Bom dia, o barco fica pronto quando?', 'received', '{"data": {}}', '2026-12-01 10:00-03'),
           ('outbound', '5547900009201', 'text', 'Lembrete automático do teste', 'sent', '{"via": "whatsapp-send", "origem": "sistema"}', '2026-12-01 11:00-03'),
           ('inbound', '120363900009201@g.us', 'text', 'mensagem do grupo', 'received', '{"data": {}}', '2026-12-01 11:30-03'),
           ('inbound', '5547900009203', 'text', 'da equipe', 'received', '{"data": {}}', '2026-12-01 12:00-03'),
           ('inbound', '5547900009202', 'text', 'Voltei a escrever', 'received', '{"data": {}}', '2026-12-01 13:20-03');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at, is_broadcast)
    values ('inbound', '5547900009207', 'text', 'transmissão', 'received', '{"data": {}}', '2026-12-01 11:45-03', true);
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, occurred_at)
    values ('outbound', '5547900009201', 'text', 'Já vejo', 'sent', '2026-12-01 12:30-03')
    returning id into v_out;
    if (select m.saida_humana from public.whatsapp_messages m where m.id = v_out) is distinct from true then
      raise exception '0j: a saída com raw_payload nulo não ganhou saida_humana = true (o gatilho da F0b não está no banco?)';
    end if;
    insert into public.app_notifications (user_id, type, title, created_at)
    values (v_user, 'whatsapp_caiu', 'Teste F1 silêncio (futuro)', '2026-12-01 13:15-03');

    -- qua 02/12: recebida de fora 10:00 e só saída automática 12:30 (os dois lados quietos).
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at)
    values ('inbound', '5547900009204', 'text', 'Bom dia', 'received', '{"data": {}}', '2026-12-02 10:00-03'),
           ('outbound', '5547900009204', 'text', 'Lembrete automático do teste', 'sent', '{"via": "whatsapp-send", "origem": "sistema"}', '2026-12-02 12:30-03');

    -- qui 03/12: recebida de fora 10:00; aviso de queda 10:20; eco do celular 11:00 com saida_humana nula
    -- (como as gravadas antes de 06/11: a função cai em _saida_e_humana).
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at)
    values ('inbound', '5547900009205', 'text', 'Oi, alguma novidade?', 'received', '{"data": {}}', '2026-12-03 10:00-03');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at)
    values ('outbound', '5547900009205', 'text', 'Vejo e te falo', 'sent', '{"data": {"key": {"fromMe": true}}}', '2026-12-03 11:00-03')
    returning id into v_eco;
    update public.whatsapp_messages set saida_humana = null where id = v_eco;
    insert into public.app_notifications (user_id, type, title, created_at)
    values (v_user, 'whatsapp_caiu', 'Teste F1 silêncio', '2026-12-03 10:20-03');

    -- sex 04/12: nenhuma recebida; aviso de queda 08:20 (antes de 09:00 − 30 min); saída pela tela 09:30.
    insert into public.app_notifications (user_id, type, title, created_at)
    values (v_user, 'whatsapp_caiu', 'Teste F1 silêncio (cedo)', '2026-12-04 08:20-03');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at, sent_by)
    values ('outbound', '5547900009205', 'text', 'Passo aí amanhã', 'sent', '{"via": "whatsapp-send", "origem": "tela"}', '2026-12-04 09:30-03', v_user)
    returning id into v_tela;
    if (select m.saida_humana from public.whatsapp_messages m where m.id = v_tela) is distinct from true then
      raise exception '0j: a saída pela tela com sent_by não ganhou saida_humana = true';
    end if;

    -- sáb 05/12 e dom 06/12: recebida de fora 10:00 e saída humana 12:30 (seria silêncio num dia útil).
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, raw_payload, occurred_at)
    values ('inbound', '5547900009206', 'text', 'Bom dia, sábado', 'received', '{"data": {}}', '2026-12-05 10:00-03'),
           ('inbound', '5547900009208', 'text', 'Bom dia, domingo', 'received', '{"data": {}}', '2026-12-06 10:00-03');
    insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, delivery_status, occurred_at)
    values ('outbound', '5547900009206', 'text', 'Segunda eu vejo', 'sent', '2026-12-05 12:30-03'),
           ('outbound', '5547900009208', 'text', 'Segunda eu vejo', 'sent', '2026-12-06 12:30-03');

    -- ── 1c. 01/12 12:40: 2h40 desde as 10:00 — ainda normal. O grupo, a transmissão e a equipe não
    --        mudaram o desde; a saída automática das 11:00 não conta.
    v_r := public.retorno_vigia_silencio('2026-12-01 12:40-03'); v_chamadas := v_chamadas + 1;
    if v_r ->> 'acao' is distinct from 'normal' or (v_r ->> 'desde')::timestamptz is distinct from '2026-12-01 10:00-03'::timestamptz
       or (v_r ->> 'saidas_humanas')::int is distinct from 1 then
      raise exception '1c: 01/12 12:40 devia ser normal, desde 10:00, 1 saída humana: %', v_r;
    end if;
    if exists (select 1 from public.retorno_silencios s where s.dia = '2026-12-01') then
      raise exception '1c: 2h40 de silêncio já registrou';
    end if;

    -- ── 5. Desligado: nada (nem registra, nem fecha). Sem a configuração: também desligado.
    update public.retorno_config set silencio_modo = 'desligado' where id;
    v_r := public.retorno_vigia_silencio('2026-12-01 13:10-03'); v_chamadas := v_chamadas + 1;
    if v_r is distinct from '{"acao": "desligado"}'::jsonb then
      raise exception '5: desligado devolveu %', v_r;
    end if;
    if exists (select 1 from public.retorno_silencios s where s.dia = '2026-12-01') then
      raise exception '5: desligado registrou silêncio';
    end if;
    begin
      delete from public.retorno_config;
      v_r2 := public.retorno_vigia_silencio('2026-12-01 13:10-03'); v_chamadas := v_chamadas + 1;
      v_n := (select count(*) from public.retorno_silencios s where s.dia = '2026-12-01');
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;
    if v_r2 is distinct from '{"acao": "desligado"}'::jsonb or v_n <> 0 then
      raise exception '5b: sem a configuração devolveu % (% linhas)', v_r2, v_n;
    end if;
    update public.retorno_config set silencio_modo = 'sombra' where id;

    -- ── 1. 01/12 13:10: 3h10 desde as 10:00, com saída humana às 12:30 → 1 linha, desde 10:00.
    --    2. a recebida da equipe às 12:00 não zerou o relógio (nem o grupo, nem a transmissão).
    --    A recebida das 13:20 e o aviso das 13:15 são "do futuro": não fecham nem marcam caiu_avisado.
    v_r := public.retorno_vigia_silencio('2026-12-01 13:10-03'); v_chamadas := v_chamadas + 1;
    if v_r ->> 'acao' is distinct from 'silencio' or (v_r ->> 'desde')::timestamptz is distinct from '2026-12-01 10:00-03'::timestamptz
       or (v_r ->> 'saidas_humanas')::int is distinct from 1 then
      raise exception '1: 01/12 13:10 devia ser silêncio desde 10:00 com 1 saída humana: %', v_r;
    end if;
    select count(*) into v_n from public.retorno_silencios s where s.dia = '2026-12-01';
    if v_n <> 1 then
      raise exception '1: 01/12 com % linhas de silêncio (esperada 1)', v_n;
    end if;
    select * into v_s from public.retorno_silencios s where s.dia = '2026-12-01';
    if v_s.desde is distinct from '2026-12-01 10:00-03'::timestamptz then
      raise exception '2: a recebida da equipe, do grupo ou da transmissão zerou o relógio (desde = %)', v_s.desde;
    end if;
    if v_s.detectado_em is distinct from '2026-12-01 13:10-03'::timestamptz or v_s.voltou_em is not null
       or v_s.saidas_humanas is distinct from 1::smallint or v_s.caiu_avisado is distinct from false
       or v_s.modo is distinct from 'sombra' or v_s.conexao_estado is distinct from v_estado_0112 then
      raise exception '1: linha de 01/12 errada (a linha do futuro mudou o resultado?): %', to_jsonb(v_s);
    end if;
    v_r := public.retorno_vigia_silencio('2026-12-01 13:10-03'); v_chamadas := v_chamadas + 1;
    select count(*) into v_n from public.retorno_silencios s where s.dia = '2026-12-01';
    if v_r ->> 'acao' is distinct from 'silencio' or v_n <> 1 then
      raise exception '1b: a 2ª chamada das 13:10 devolveu % e deixou % linhas (esperada 1)', v_r, v_n;
    end if;

    -- ── 5c. Desligado não fecha o aberto.
    update public.retorno_config set silencio_modo = 'desligado' where id;
    v_r := public.retorno_vigia_silencio('2026-12-01 13:30-03'); v_chamadas := v_chamadas + 1;
    if v_r is distinct from '{"acao": "desligado"}'::jsonb
       or (select s.voltou_em from public.retorno_silencios s where s.dia = '2026-12-01') is not null then
      raise exception '5c: desligado fechou o silêncio ou devolveu %', v_r;
    end if;
    update public.retorno_config set silencio_modo = 'sombra' where id;

    -- ── 3. A recebida de fora das 13:20 → às 13:30, voltou_em = 13:20 (e a entrada está viva: normal).
    v_r := public.retorno_vigia_silencio('2026-12-01 13:30-03'); v_chamadas := v_chamadas + 1;
    if v_r ->> 'acao' is distinct from 'normal' or (v_r ->> 'desde')::timestamptz is distinct from '2026-12-01 13:20-03'::timestamptz
       or coalesce((v_r ->> 'voltaram')::int, 0) < 1 then
      raise exception '3: 01/12 13:30 devia ser normal desde 13:20, fechando o aberto: %', v_r;
    end if;
    select count(*) into v_n from public.retorno_silencios s where s.dia = '2026-12-01';
    if v_n <> 1 or (select s.voltou_em from public.retorno_silencios s where s.dia = '2026-12-01')
                   is distinct from '2026-12-01 13:20-03'::timestamptz then
      raise exception '3: voltou_em não ficou 13:20 (% linhas)', v_n;
    end if;

    -- ── 4. Fora da janela (08:30, 18:30) e sem saída humana no período (02/12): nada.
    v_r := public.retorno_vigia_silencio('2026-12-02 08:30-03'); v_chamadas := v_chamadas + 1;
    if v_r ->> 'acao' is distinct from 'fora' or v_r ? 'desde' then
      raise exception '4: 02/12 08:30 devia ser fora: %', v_r;
    end if;
    v_r := public.retorno_vigia_silencio('2026-12-02 13:10-03'); v_chamadas := v_chamadas + 1;
    if v_r ->> 'acao' is distinct from 'normal' or (v_r ->> 'saidas_humanas')::int is distinct from 0
       or (v_r ->> 'desde')::timestamptz is distinct from '2026-12-02 10:00-03'::timestamptz then
      raise exception '4: 02/12 13:10 sem saída humana devia ser normal com 0 saídas humanas: %', v_r;
    end if;
    v_r := public.retorno_vigia_silencio('2026-12-02 18:00-03'); v_chamadas := v_chamadas + 1;
    if v_r ->> 'acao' is distinct from 'normal' then
      raise exception '4: 02/12 18:00 (fim da janela, inclusive) devia ser normal: %', v_r;
    end if;
    v_r := public.retorno_vigia_silencio('2026-12-02 18:30-03'); v_chamadas := v_chamadas + 1;
    if v_r ->> 'acao' is distinct from 'fora' then
      raise exception '4: 02/12 18:30 devia ser fora: %', v_r;
    end if;
    if exists (select 1 from public.retorno_silencios s where s.dia = '2026-12-02') then
      raise exception '4: 02/12 sem saída humana registrou silêncio';
    end if;

    -- ── 6. caiu_avisado: aviso whatsapp_caiu às 10:20 (03/12), e a saída humana pela regra da origem
    --       (saida_humana nula, eco do celular).
    v_r := public.retorno_vigia_silencio('2026-12-03 13:15-03'); v_chamadas := v_chamadas + 1;
    if v_r ->> 'acao' is distinct from 'silencio' or (v_r ->> 'desde')::timestamptz is distinct from '2026-12-03 10:00-03'::timestamptz
       or (v_r ->> 'saidas_humanas')::int is distinct from 1 then
      raise exception '6: 03/12 13:15 devia ser silêncio desde 10:00 com 1 saída humana (o eco com saida_humana nula): %', v_r;
    end if;
    select * into v_s from public.retorno_silencios s where s.dia = '2026-12-03';
    if not found or v_s.caiu_avisado is distinct from true or v_s.conexao_estado is distinct from v_estado_0312 then
      raise exception '6: caiu_avisado não ficou verdadeiro com o aviso das 10:20: %', to_jsonb(v_s);
    end if;

    -- ── 4b. 04/12 sem recebida: 11:59 é fora (antes de 09:00 + 3 h); 12:00 é silêncio desde 09:00
    --        (o início do dia), com o aviso das 08:20 fora do limite de desde − 30 min.
    v_r := public.retorno_vigia_silencio('2026-12-04 11:59-03'); v_chamadas := v_chamadas + 1;
    if v_r ->> 'acao' is distinct from 'fora' then
      raise exception '4b: 04/12 11:59 devia ser fora: %', v_r;
    end if;
    v_r := public.retorno_vigia_silencio('2026-12-04 12:00-03'); v_chamadas := v_chamadas + 1;
    if v_r ->> 'acao' is distinct from 'silencio' or (v_r ->> 'desde')::timestamptz is distinct from '2026-12-04 09:00-03'::timestamptz
       or (v_r ->> 'saidas_humanas')::int is distinct from 1 then
      raise exception '4b: 04/12 12:00 devia ser silêncio desde 09:00 com 1 saída humana: %', v_r;
    end if;
    select * into v_s from public.retorno_silencios s where s.dia = '2026-12-04';
    if not found or v_s.caiu_avisado is distinct from false or v_s.voltou_em is not null then
      raise exception '4b: o aviso das 08:20 marcou caiu_avisado ou o silêncio já voltou: %', to_jsonb(v_s);
    end if;

    -- ── 4c. Sábado (enquanto não for dia útil) e domingo: fora, sem linha. Mesmo fora, o passo 6 fecha
    --        os abertos de 03/12 e 04/12 pela recebida de sábado às 10:00.
    v_r := public.retorno_vigia_silencio('2026-12-05 13:10-03'); v_chamadas := v_chamadas + 1;
    if not v_sabado_util and (v_r ->> 'acao' is distinct from 'fora'
                              or exists (select 1 from public.retorno_silencios s where s.dia = '2026-12-05')) then
      raise exception '4c: sábado 05/12 devia ser fora, sem linha: %', v_r;
    end if;
    if coalesce((v_r ->> 'voltaram')::int, 0) < 2
       or exists (select 1 from public.retorno_silencios s
                   where s.dia in ('2026-12-03', '2026-12-04') and s.voltou_em is distinct from '2026-12-05 10:00-03'::timestamptz) then
      raise exception '4c: a chamada de sábado não fechou 03/12 e 04/12 pela recebida das 10:00: %', v_r;
    end if;
    v_r := public.retorno_vigia_silencio('2026-12-06 13:10-03'); v_chamadas := v_chamadas + 1;
    if v_r ->> 'acao' is distinct from 'fora' or exists (select 1 from public.retorno_silencios s where s.dia = '2026-12-06') then
      raise exception '4c: domingo 06/12 devia ser fora, sem linha: %', v_r;
    end if;

    -- ── 7. A view: caiu_no_periodo (desde − 30 min até a volta) e a duração.
    --    01/12: o aviso das 13:15 caiu no período (caiu_avisado continua falso: veio depois da detecção).
    for v_s in
      select c.dia, c.caiu_avisado, c.caiu_no_periodo, c.duracao from public.retorno_silencios_comparados c
       where c.dia between '2026-12-01' and '2026-12-04' order by c.dia
    loop
      v_linhas := v_linhas + 1;
      if (v_s.dia = '2026-12-01' and (v_s.caiu_no_periodo is distinct from true or v_s.caiu_avisado is distinct from false
                                      or v_s.duracao is distinct from interval '3 hours 20 minutes'))
         or (v_s.dia = '2026-12-03' and (v_s.caiu_no_periodo is distinct from true or v_s.duracao is distinct from interval '48 hours'))
         or (v_s.dia = '2026-12-04' and (v_s.caiu_no_periodo is distinct from false or v_s.duracao is distinct from interval '25 hours'))
         or v_s.dia not in ('2026-12-01', '2026-12-03', '2026-12-04') then
        raise exception '7: retorno_silencios_comparados errada em %: %', v_s.dia, to_jsonb(v_s);
      end if;
    end loop;
    if v_linhas <> 3 then
      raise exception '7: a view mostrou % silêncios de teste (esperados 3: 01, 03 e 04/12)', v_linhas;
    end if;

    -- ── 8. Nunca manda nada.
    if exists (select 1 from public.whatsapp_send_queue q where q.phone_normalized like '55479000092%') then
      raise exception '8: o vigia de silêncio pôs mensagem na fila';
    end if;

    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if not v_chegou then
    raise exception '0k: o arranjo não chegou ao fim';
  end if;
  if exists (select 1 from public.retorno_silencios s where s.dia between '2026-12-01' and '2026-12-06')
     or exists (select 1 from public.whatsapp_messages m
                 where m.phone_normalized like '55479000092%' or m.phone_normalized like '%900009201@g.us')
     or exists (select 1 from public.app_notifications n where n.title like 'Teste F1 silêncio%')
     or exists (select 1 from public.payees p where p.id = v_payee)
     or (select to_jsonb(c) - 'atualizado_em' from public.retorno_config c where c.id) is distinct from v_cfg_antes then
    raise exception '0l: o arranjo não foi desfeito';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_silencio', true,
          jsonb_build_object('chamadas', v_chamadas, 'silencios_na_view', v_linhas, 'sabado_util', v_sabado_util,
                             'modo_de_hoje', v_modo_antes));
end
$silencio$;

-- Replay informativo, 60 dias até ontem: a consulta r31 com as regras da função (dia útil por
-- agenda_dia_util, janela e horas da configuração, hora de gravação, equipe por chave de todas as linhas,
-- sem grupo e sem transmissão, saída humana pela origem). Cada buraco >= silencio_horas entre 2 pontos do
-- dia (silencio_inicio, as recebidas de fora da equipe, silencio_fim) com saída humana dentro é um alarme;
-- ele "teve whatsapp_caiu" com aviso entre o início − 30 min e a volta (ou início + horas + 6 h).
-- Só lê dado real: na bancada, os testes anteriores da mesma transação deixam mensagens com occurred_at
-- relativo a now() (o retorno_f0b_esperando grava recebidas de 1 a 20 dias atrás, sem desfazer), que
-- partiriam buracos reais ou mudariam a volta. Por isso rec e env só leem linha gravada ANTES desta
-- transação (created_at < now(); o padrão da coluna é now() e nenhum teste o preenche) e fora da faixa de
-- teste 5547900009xxx (seção 7.1). Nunca falha a bancada: um erro vai para os números como {"erro", "mensagem"}.
do $silencio_replay$
declare
  v_rep jsonb;
begin
  begin
    with cfg as (
      select coalesce(c.silencio_inicio, time '09:00') as ini, coalesce(c.silencio_fim, time '18:00') as fim,
             coalesce(c.silencio_horas, interval '3 hours') as horas
        from (select 1) x left join public.retorno_config c on c.id
    ),
    periodo as (
      select public._hoje_brt() - 60 as de, public._hoje_brt() - 1 as ate,
             ((public._hoje_brt() - 60)::timestamp at time zone 'America/Sao_Paulo') as de_ts
    ),
    eq as (
      select distinct z.k
        from (select public._agenda_chave_telefone(u.phone_normalized) as k from public.app_users u
              union all select public._agenda_chave_telefone(u.phone) from public.app_users u
              union all select public._agenda_chave_telefone(p.phone) from public.payees p) z
       where z.k is not null
    ),
    dias as (
      select g::date as d
        from periodo, generate_series(periodo.de::timestamp, periodo.ate::timestamp, interval '1 day') g
       where public.agenda_dia_util(g::date)
    ),
    rec as (
      select m.occurred_at as t
        from public.whatsapp_messages m, periodo
       where m.direction = 'inbound' and m.occurred_at >= periodo.de_ts
         and m.created_at < now() and m.phone_normalized !~ '^5547900009'
         and m.phone_normalized !~ '@' and not coalesce(m.is_broadcast, false)
         and not exists (select 1 from eq where eq.k = public._agenda_chave_telefone(m.phone_normalized))
    ),
    env as (
      select m.occurred_at as t
        from public.whatsapp_messages m, periodo
       where m.direction = 'outbound' and m.occurred_at >= periodo.de_ts
         and m.created_at < now() and m.phone_normalized !~ '^5547900009'
         and coalesce(m.saida_humana, public._saida_e_humana(m.direction, m.raw_payload, m.sent_by))
    ),
    pontos as (
      select dias.d, (dias.d + cfg.ini) at time zone 'America/Sao_Paulo' as t from dias, cfg
      union all
      select dias.d, (dias.d + cfg.fim) at time zone 'America/Sao_Paulo' from dias, cfg
      union all
      select dias.d, rec.t
        from rec join dias on dias.d = (rec.t at time zone 'America/Sao_Paulo')::date, cfg
       where (rec.t at time zone 'America/Sao_Paulo')::time between cfg.ini and cfg.fim
    ),
    buracos as (
      select p.d, p.t as ini, lead(p.t) over (partition by p.d order by p.t) as fim from pontos p
    ),
    alarmes as (
      select b.d, b.ini, b.fim, (select min(r.t) from rec r where r.t > b.ini) as voltou
        from buracos b, cfg
       where b.fim - b.ini >= cfg.horas
         and exists (select 1 from env e where e.t > b.ini and e.t < b.fim)
    ),
    caiu as (
      select n.created_at as t
        from public.app_notifications n, periodo
       where n.type = 'whatsapp_caiu' and n.created_at >= periodo.de_ts - interval '1 day'
    ),
    alarmes_c as (
      select a.d, a.ini, a.voltou,
             exists (select 1 from caiu c
                      where c.t >= a.ini - interval '30 minutes'
                        and c.t <= coalesce(a.voltou, a.ini + cfg.horas + interval '6 hours')) as caiu_no_periodo
        from alarmes a, cfg
    )
    select jsonb_build_object(
             'de', (select periodo.de from periodo),
             'ate', (select periodo.ate from periodo),
             'dias_uteis', (select count(*) from dias),
             'dias_com_alarme', (select count(distinct a.d) from alarmes_c a),
             'alarmes', (select count(*) from alarmes_c a),
             'dias_com_alarme_e_caiu', (select count(distinct a.d) from alarmes_c a where a.caiu_no_periodo),
             'alarmes_com_caiu', (select count(*) from alarmes_c a where a.caiu_no_periodo),
             'dias_uteis_com_caiu', (select count(*) from dias
                                      where exists (select 1 from caiu c where (c.t at time zone 'America/Sao_Paulo')::date = dias.d)),
             'dias_com_caiu_sem_alarme', (select count(*) from dias
                                           where exists (select 1 from caiu c where (c.t at time zone 'America/Sao_Paulo')::date = dias.d)
                                             and not exists (select 1 from alarmes_c a where a.d = dias.d)),
             'maior_alarme_h', (select round((max(extract(epoch from (coalesce(a.voltou, now()) - a.ini))) / 3600)::numeric, 1)
                                  from alarmes_c a))
      into v_rep;
  exception when others then
    v_rep := jsonb_build_object('erro', sqlstate, 'mensagem', left(sqlerrm, 300));
  end;
  update _bancada set numeros = coalesce(numeros, '{}'::jsonb) || jsonb_build_object('replay_60d', v_rep)
   where arquivo = 'retorno_f1_silencio';
end
$silencio_replay$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
