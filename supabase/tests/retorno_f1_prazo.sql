-- Retorno F1 (P3): _retorno_prazo, o "até X" do recibo (B.4.1) linha a linha, mais _retorno_proxima_manha,
-- _retorno_x2, _retorno_quando e _retorno_hora.
-- Datas fixas de novembro de 2026, em Brasília (sem horário de verão): ter 17/11 é dia útil, sex 20/11 é
-- feriado (Consciência Negra), sáb 21/11, dom 22/11, seg 23/11. O caso 0 confere essas premissas na agenda
-- de produção (agenda_dia_util, só lida): se o dono marcar um desses dias como indisponível, o arquivo para
-- ali, dizendo a premissa que mudou, em vez de acusar o prazo.
-- A configuração do retorno é posta nos valores de nascença no começo do arranjo (meio-dia desligado,
-- promessa_faixa vazia, fora_ate nulo, janelas e momentos padrão): o resultado não depende do que estiver
-- em produção no dia da bancada. As funções do P3 não leem whatsapp_messages, retorno_saidas,
-- app_notifications, whatsapp_acompanhamentos nem avisos_do_dono: "linha do futuro" não se aplica aqui.
-- Run (só pela bancada, de madrugada): npx supabase@2.111.0 db query --linked -f supabase/tests/retorno_f1_prazo.sql
-- Termina em ROLLBACK: nada fica gravado. Sem telefone real: as chaves de teste são 00009401–00009403 (faixa
-- 55479000094xx) e a chave sintética do caso 13. Todo arranjo (retorno_config, a linha de
-- agenda_disponibilidade, os logs) é desfeito dentro do arquivo (sub-bloco que termina em 'desfaz').
begin;
create temp table if not exists _bancada (arquivo text, ok boolean, numeros jsonb, em timestamptz default clock_timestamp());

-- Confere uma resposta de _retorno_prazo: o contrato (as 10 chaves), o esperado e a coerência interna
-- (dia e hora = os de prometido_ate; ref = o dia do recibo; outro_dia; x2 = _retorno_x2; promessa depois do
-- recibo). Chamada DENTRO do arranjo, com a configuração do caso.
create or replace function pg_temp.retorno_f1_prazo_confere(p_caso text, p_pz jsonb, p_faixa text, p_fonte text,
                                                            p_prometido timestamptz, p_quando text,
                                                            p_recibo timestamptz default null)
returns void
language plpgsql as $f$
declare
  v_prom timestamptz;
  v_recibo timestamptz;
begin
  if p_pz is null or jsonb_typeof(p_pz) is distinct from 'object' then
    raise exception '%: _retorno_prazo não devolveu objeto: %', p_caso, p_pz;
  end if;
  if (select array_agg(k order by k collate "C") from jsonb_object_keys(p_pz) k)
     is distinct from array['dia', 'faixa', 'fonte', 'hora', 'outro_dia', 'prometido_ate', 'quando', 'recibo_em', 'ref', 'x2'] then
    raise exception '%: fora do contrato (chaves): %', p_caso, p_pz;
  end if;
  v_prom := (p_pz ->> 'prometido_ate')::timestamptz;
  v_recibo := (p_pz ->> 'recibo_em')::timestamptz;
  if p_pz ->> 'faixa' is distinct from p_faixa or p_pz ->> 'fonte' is distinct from p_fonte
     or v_prom is distinct from p_prometido or p_pz ->> 'quando' is distinct from p_quando then
    raise exception '%: esperado faixa %, fonte %, até % (%); veio %', p_caso, p_faixa, p_fonte,
      to_char(p_prometido at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), p_quando, p_pz;
  end if;
  if p_recibo is not null and v_recibo is distinct from p_recibo then
    raise exception '%: recibo_em esperado %, veio %', p_caso,
      to_char(p_recibo at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI:SS'), p_pz ->> 'recibo_em';
  end if;
  if (p_pz ->> 'dia')::date is distinct from (v_prom at time zone 'America/Sao_Paulo')::date
     or p_pz ->> 'hora' is distinct from public._retorno_hora((v_prom at time zone 'America/Sao_Paulo')::time)
     or (p_pz ->> 'ref')::date is distinct from (v_recibo at time zone 'America/Sao_Paulo')::date
     or (p_pz ->> 'outro_dia')::boolean is distinct from ((p_pz ->> 'dia')::date > (p_pz ->> 'ref')::date)
     or p_pz ->> 'quando' is distinct from public._retorno_quando((p_pz ->> 'dia')::date, (p_pz ->> 'ref')::date)
     or (p_pz ->> 'x2')::timestamptz is distinct from public._retorno_x2(v_prom)
     or not (v_prom > v_recibo) then
    raise exception '%: resposta incoerente: %', p_caso, p_pz;
  end if;
end $f$;

-- Quantas vezes o log da calibração foi registrado NESTA transação (o upsert por impressão digital soma
-- occurrences e regrava last_seen_at = now()). Sobe a cada log, inclusive sobre uma linha antiga.
create or replace function pg_temp.retorno_f1_prazo_logs() returns bigint
language sql as $f$
  select coalesce(sum(l.occurrences), 0)::bigint from public.app_error_logs l
   where l.context = 'retorno' and l.action = 'promessa_faixa' and l.resolved_at is null and l.last_seen_at = now()
$f$;

do $prazo$
declare
  c_k1 constant text := '00009401';
  c_k2 constant text := '00009402';
  c_k3 constant text := '00009403';
  c_k_min constant text := 'otO8PF8IhYoy';   -- hashtext('otO8PF8IhYoy2026-11-18') = -2147483648 (conferido no caso 13)
  v_f record;
  v_nome text;
  v_pz jsonb;
  v_pz2 jsonb;
  v_t1 timestamptz; v_t2 timestamptz; v_t3 timestamptz; v_t4 timestamptz; v_t5 timestamptz;
  v_logs bigint;
  v_erro text;
  v_chegou boolean := false;
  v_casos int := 0;
  v_logs_calibracao int := 0;
begin
  -- ── 0. As funções e as premissas do calendário ───────────────────────────────────────────────────────────
  foreach v_nome in array array['public._retorno_prazo(timestamptz, text, boolean, boolean)',
                                'public._retorno_proxima_manha(timestamptz, text)', 'public._retorno_x2(timestamptz)',
                                'public._retorno_quando(date, date)', 'public._retorno_hora(time)']
  loop
    if to_regprocedure(v_nome) is null then
      raise exception '0: % não existe', v_nome;
    end if;
    if has_function_privilege('anon', v_nome, 'execute') or has_function_privilege('authenticated', v_nome, 'execute') then
      raise exception '0b: % aberta a anon/authenticated', v_nome;
    end if;
  end loop;
  select p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}') as config into v_f
    from pg_proc p where p.oid = to_regprocedure('public._retorno_prazo(timestamptz, text, boolean, boolean)');
  -- VOLATILE: grava o log da calibração inválida.
  if v_f.provolatile <> 'v' or not v_f.prosecdef or not ('search_path=public' = any (v_f.config)) then
    raise exception '0c: _retorno_prazo não é VOLATILE + SECURITY DEFINER com search_path = public';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = to_regprocedure('public._retorno_proxima_manha(timestamptz, text)')) <> 's'
     or (select p.provolatile from pg_proc p where p.oid = to_regprocedure('public._retorno_x2(timestamptz)')) <> 's'
     or (select p.provolatile from pg_proc p where p.oid = to_regprocedure('public._retorno_quando(date, date)')) <> 's'
     or (select p.provolatile from pg_proc p where p.oid = to_regprocedure('public._retorno_hora(time)')) <> 'i' then
    raise exception '0d: volatilidade fora da especificação (proxima_manha, x2 e quando STABLE; hora IMMUTABLE)';
  end if;
  if not exists (select 1 from public.retorno_config where id) then
    raise exception '0e: retorno_config sem a linha de configuração';
  end if;
  if extract(isodow from date '2026-11-17') <> 2
     or public.agenda_feriado('2026-11-20') is null
     or not (public.agenda_dia_util('2026-11-16') and public.agenda_dia_util('2026-11-17') and public.agenda_dia_util('2026-11-18')
             and public.agenda_dia_util('2026-11-19') and public.agenda_dia_util('2026-11-23') and public.agenda_dia_util('2026-11-24')
             and public.agenda_dia_util('2026-11-25'))
     or public.agenda_dia_util('2026-11-20') or public.agenda_dia_util('2026-11-21') or public.agenda_dia_util('2026-11-22') then
    raise exception '0f: premissa do calendário mudou (16–19 e 23–25/11 úteis; 20, 21 e 22/11 não): confira agenda_disponibilidade e agenda_config.sabado_util antes do prazo';
  end if;

  -- ── _retorno_quando e _retorno_hora ─────────────────────────────────────────────────────────────────────
  if public._retorno_quando('2026-11-17', '2026-11-17') is distinct from 'hoje'
     or public._retorno_quando('2026-11-18', '2026-11-17') is distinct from 'amanhã'
     or public._retorno_quando('2026-11-23', '2026-11-17') is distinct from 'segunda (23/11)'
     or public._retorno_quando('2026-11-21', '2026-11-17') is distinct from 'sábado (21/11)'
     or public._retorno_quando(null, '2026-11-17') is not null or public._retorno_quando('2026-11-17', null) is not null then
    raise exception 'q: _retorno_quando fora da especificação';
  end if;
  if public._retorno_hora('10:00') is distinct from '10h' or public._retorno_hora('09:00') is distinct from '9h'
     or public._retorno_hora('19:00:30') is distinct from '19h' or public._retorno_hora('10:30') is distinct from '10:30'
     or public._retorno_hora('09:05') is distinct from '09:05' or public._retorno_hora(null) is not null then
    raise exception 'h: _retorno_hora fora da especificação';
  end if;

  begin
    -- Arranjo: a configuração de nascença, para o resultado não depender do valor de produção.
    update public.retorno_config set
      cliente_resposta_direta_inicio = '07:00', cliente_resposta_direta_fim = '22:00',
      manha_recibo = '08:00', manha_recibo_folga = '09:00', manha_espalhar = '30 minutes',
      ponto_manha = '07:30', ponto_meio_dia = '12:30', ponto_fechamento = '17:30',
      promessa_manha = '10:00', promessa_meio_dia = '14:00', promessa_fechamento = '19:00',
      meio_dia_ligado = false, corte_meio_dia = '11:00', corte_tarde = '15:30',
      promessa_faixa = '{}', fora_ate = null
    where id;

    -- ── 1. ter 17/11 09:12: hoje 19h (meio-dia desligado); com o meio-dia ligado, hoje 14h ──────────────
    perform pg_temp.retorno_f1_prazo_confere('1a', public._retorno_prazo('2026-11-17 09:12-03', c_k1),
      'manha_cedo', 'fechamento', '2026-11-17 19:00-03', 'hoje', '2026-11-17 09:12-03');
    update public.retorno_config set meio_dia_ligado = true where id;
    perform pg_temp.retorno_f1_prazo_confere('1b', public._retorno_prazo('2026-11-17 09:12-03', c_k1),
      'manha_cedo', 'meio_dia', '2026-11-17 14:00-03', 'hoje', '2026-11-17 09:12-03');
    -- 10:59 ainda é manhã cedo; 11:00 já é o meio (19h), mesmo com o meio-dia ligado.
    perform pg_temp.retorno_f1_prazo_confere('1c', public._retorno_prazo('2026-11-17 10:59-03', c_k1),
      'manha_cedo', 'meio_dia', '2026-11-17 14:00-03', 'hoje');
    perform pg_temp.retorno_f1_prazo_confere('1d', public._retorno_prazo('2026-11-17 11:00-03', c_k1),
      'meio', 'fechamento', '2026-11-17 19:00-03', 'hoje');
    update public.retorno_config set meio_dia_ligado = false where id;
    -- 07:00 abre a janela: recibo na hora, hoje 19h.
    perform pg_temp.retorno_f1_prazo_confere('1e', public._retorno_prazo('2026-11-17 07:00-03', c_k1),
      'manha_cedo', 'fechamento', '2026-11-17 19:00-03', 'hoje', '2026-11-17 07:00-03');
    v_casos := v_casos + 5;

    -- ── 2. 11:00 → 19h; 15:29 → 19h; 15:30 → qua 18/11 10h, "amanhã" ─────────────────────────────────────
    perform pg_temp.retorno_f1_prazo_confere('2a', public._retorno_prazo('2026-11-17 11:00-03', c_k1),
      'meio', 'fechamento', '2026-11-17 19:00-03', 'hoje', '2026-11-17 11:00-03');
    perform pg_temp.retorno_f1_prazo_confere('2b', public._retorno_prazo('2026-11-17 15:29-03', c_k1),
      'meio', 'fechamento', '2026-11-17 19:00-03', 'hoje', '2026-11-17 15:29-03');
    v_pz := public._retorno_prazo('2026-11-17 15:30-03', c_k1);
    perform pg_temp.retorno_f1_prazo_confere('2c', v_pz,
      'tarde', 'manha', '2026-11-18 10:00-03', 'amanhã', '2026-11-17 15:30-03');
    if (v_pz -> 'outro_dia') is distinct from 'true'::jsonb then
      raise exception '2c: outro_dia não é verdadeiro na promessa de amanhã: %', v_pz;
    end if;
    -- 21:59 ainda é janela (recibo na hora); 22:00 já espera a manhã.
    perform pg_temp.retorno_f1_prazo_confere('2d', public._retorno_prazo('2026-11-17 21:59-03', c_k1),
      'tarde', 'manha', '2026-11-18 10:00-03', 'amanhã', '2026-11-17 21:59-03');
    v_pz := public._retorno_prazo('2026-11-17 22:00-03', c_k1);
    perform pg_temp.retorno_f1_prazo_confere('2e', v_pz, 'noite', 'manha', '2026-11-18 10:00-03', 'hoje');
    v_casos := v_casos + 5;

    -- ── 3. qui 19/11 16:00, véspera de feriado → seg 23/11 10h ─────────────────────────────────────────────
    perform pg_temp.retorno_f1_prazo_confere('3', public._retorno_prazo('2026-11-19 16:00-03', c_k1),
      'tarde', 'manha', '2026-11-23 10:00-03', 'segunda (23/11)', '2026-11-19 16:00-03');
    -- e no próprio feriado (sex 20/11 10:00): folga, seg 23/11 10h.
    perform pg_temp.retorno_f1_prazo_confere('3b', public._retorno_prazo('2026-11-20 10:00-03', c_k1),
      'folga', 'manha', '2026-11-23 10:00-03', 'segunda (23/11)', '2026-11-20 10:00-03');
    v_casos := v_casos + 2;

    -- ── 4. sáb 21/11 20:10 (C7): recibo na hora, seg 23/11 10h, folga, outro dia ─────────────────────────────
    v_pz := public._retorno_prazo('2026-11-21 20:10-03', c_k1);
    perform pg_temp.retorno_f1_prazo_confere('4', v_pz,
      'folga', 'manha', '2026-11-23 10:00-03', 'segunda (23/11)', '2026-11-21 20:10-03');
    if (v_pz -> 'outro_dia') is distinct from 'true'::jsonb then
      raise exception '4: outro_dia não é verdadeiro: %', v_pz;
    end if;
    v_casos := v_casos + 1;

    -- ── 5. Fora da janela: o recibo espera a manhã ──────────────────────────────────────────────────────────
    -- sáb 21/11 23:30 → recibo no domingo 22/11 entre 09:00 e 09:30; promete seg 23/11 10h, "amanhã" (dúvida 4).
    v_pz := public._retorno_prazo('2026-11-21 23:30-03', c_k1);
    perform pg_temp.retorno_f1_prazo_confere('5a', v_pz, 'noite', 'manha', '2026-11-23 10:00-03', 'amanhã');
    if not ((v_pz ->> 'recibo_em')::timestamptz >= '2026-11-22 09:00-03'
            and (v_pz ->> 'recibo_em')::timestamptz < '2026-11-22 09:30-03') then
      raise exception '5a: recibo do domingo fora de 09:00–09:30: %', v_pz ->> 'recibo_em';
    end if;
    -- ter 17/11 02:00 → recibo ter 08:00–08:30; promete ter 10h, "hoje".
    v_pz := public._retorno_prazo('2026-11-17 02:00-03', c_k1);
    perform pg_temp.retorno_f1_prazo_confere('5b', v_pz, 'noite', 'manha', '2026-11-17 10:00-03', 'hoje');
    if not ((v_pz ->> 'recibo_em')::timestamptz >= '2026-11-17 08:00-03'
            and (v_pz ->> 'recibo_em')::timestamptz < '2026-11-17 08:30-03')
       or (v_pz -> 'outro_dia') is distinct from 'false'::jsonb then
      raise exception '5b: recibo da madrugada fora de 08:00–08:30 ou em outro dia: %', v_pz;
    end if;
    -- 06:59 ainda espera a manhã do mesmo dia.
    v_pz := public._retorno_prazo('2026-11-17 06:59-03', c_k1);
    perform pg_temp.retorno_f1_prazo_confere('5c', v_pz, 'noite', 'manha', '2026-11-17 10:00-03', 'hoje');
    -- sex 20/11 (feriado) 01:00 → recibo no feriado entre 09:00 e 09:30; promete seg 23/11 10h.
    v_pz := public._retorno_prazo('2026-11-20 01:00-03', c_k1);
    perform pg_temp.retorno_f1_prazo_confere('5d', v_pz, 'noite', 'manha', '2026-11-23 10:00-03', 'segunda (23/11)');
    if not ((v_pz ->> 'recibo_em')::timestamptz >= '2026-11-20 09:00-03'
            and (v_pz ->> 'recibo_em')::timestamptz < '2026-11-20 09:30-03') then
      raise exception '5d: recibo do feriado fora de 09:00–09:30: %', v_pz ->> 'recibo_em';
    end if;
    v_casos := v_casos + 4;

    -- ── 6. _retorno_proxima_manha: estável por chave e dia, e espalha entre chaves ──────────────────────────
    v_t1 := public._retorno_proxima_manha('2026-11-17 22:10-03', c_k1);
    v_t2 := public._retorno_proxima_manha('2026-11-18 03:00-03', c_k1);     -- outra hora, o mesmo dia de recibo
    v_t3 := public._retorno_proxima_manha('2026-11-17 22:10-03', c_k2);
    v_t4 := public._retorno_proxima_manha('2026-11-17 22:10-03', c_k3);
    v_t5 := public._retorno_proxima_manha('2026-11-18 22:10-03', c_k1);     -- o dia seguinte
    if v_t1 is distinct from v_t2 then
      raise exception '6a: a mesma chave no mesmo dia deu instantes diferentes: % e %', v_t1, v_t2;
    end if;
    if v_t1 = v_t3 or v_t1 = v_t4 or v_t3 = v_t4 then
      raise exception '6b: chaves diferentes caíram no mesmo instante: % % %', v_t1, v_t3, v_t4;
    end if;
    if not (v_t1 >= '2026-11-18 08:00-03' and v_t1 < '2026-11-18 08:30-03' and v_t3 >= '2026-11-18 08:00-03'
            and v_t3 < '2026-11-18 08:30-03' and v_t4 >= '2026-11-18 08:00-03' and v_t4 < '2026-11-18 08:30-03') then
      raise exception '6c: manhã fora de 08:00–08:30 de qua 18/11: % % %', v_t1, v_t3, v_t4;
    end if;
    if not (v_t5 >= '2026-11-19 08:00-03' and v_t5 < '2026-11-19 08:30-03') then
      raise exception '6d: a manhã do dia seguinte não caiu em qui 19/11 08:00–08:30: %', v_t5;
    end if;
    -- O espalhamento é o do hash da chave e do dia: 08:00 + (|hashtext| mod 1800) s.
    if v_t1 is distinct from ('2026-11-18 08:00-03'::timestamptz
                              + make_interval(secs => (abs(hashtext(c_k1 || '2026-11-18')::bigint) % 1800)::double precision)) then
      raise exception '6e: o espalhamento não é o do hash da chave e do dia: %', v_t1;
    end if;
    -- Sem espalhar (manha_espalhar = 0): exatamente 08:00.
    update public.retorno_config set manha_espalhar = '0' where id;
    if public._retorno_proxima_manha('2026-11-17 22:10-03', c_k1) is distinct from '2026-11-18 08:00-03'::timestamptz then
      raise exception '6f: sem espalhar, a manhã não foi 08:00';
    end if;
    update public.retorno_config set manha_espalhar = '30 minutes' where id;
    v_casos := v_casos + 6;

    -- ── 7. greatest: hora real 09:00, gravada às 15:10 → 19h, nunca 14h (mesmo com o meio-dia ligado) ──────
    update public.retorno_config set meio_dia_ligado = true where id;
    perform pg_temp.retorno_f1_prazo_confere('7a',
      public._retorno_prazo(greatest('2026-11-17 09:00-03'::timestamptz, '2026-11-17 15:10-03'::timestamptz), c_k1),
      'meio', 'fechamento', '2026-11-17 19:00-03', 'hoje', '2026-11-17 15:10-03');
    -- o contraste: pela hora real sozinha, a promessa seria 14h (já vencida às 15:10).
    perform pg_temp.retorno_f1_prazo_confere('7b', public._retorno_prazo('2026-11-17 09:00-03', c_k1),
      'manha_cedo', 'meio_dia', '2026-11-17 14:00-03', 'hoje');
    update public.retorno_config set meio_dia_ligado = false where id;
    v_casos := v_casos + 2;

    -- ── 8. fora_ate ─────────────────────────────────────────────────────────────────────────────────────────
    update public.retorno_config set fora_ate = '2026-11-25' where id;
    perform pg_temp.retorno_f1_prazo_confere('8a', public._retorno_prazo('2026-11-23 10:00-03', c_k1),
      'fora_ate', 'fora_ate', '2026-11-25 10:00-03', 'quarta (25/11)', '2026-11-23 10:00-03');
    -- fora da janela: o recibo espera a manhã (ter 24/11 08:00–08:30) e a promessa segue a da volta.
    v_pz := public._retorno_prazo('2026-11-23 23:00-03', c_k1);
    perform pg_temp.retorno_f1_prazo_confere('8b', v_pz, 'fora_ate', 'fora_ate', '2026-11-25 10:00-03', 'amanhã');
    if not ((v_pz ->> 'recibo_em')::timestamptz >= '2026-11-24 08:00-03'
            and (v_pz ->> 'recibo_em')::timestamptz < '2026-11-24 08:30-03') then
      raise exception '8b: recibo fora da janela, com fora_ate, não saiu na manhã de ter 24/11: %', v_pz ->> 'recibo_em';
    end if;
    -- a pressa não fura o fora_ate (o acorde real não existe; a regra 1 vem antes).
    perform pg_temp.retorno_f1_prazo_confere('8c', public._retorno_prazo('2026-11-23 10:00-03', c_k1, true, true),
      'fora_ate', 'fora_ate', '2026-11-25 10:00-03', 'quarta (25/11)');
    -- volta num sábado: a promessa vai ao 1º dia útil a partir dele (seg 23/11).
    update public.retorno_config set fora_ate = '2026-11-21' where id;
    perform pg_temp.retorno_f1_prazo_confere('8d', public._retorno_prazo('2026-11-19 16:00-03', c_k1),
      'fora_ate', 'fora_ate', '2026-11-23 10:00-03', 'segunda (23/11)');
    -- no próprio dia da volta: antes das 10h promete hoje 10h; depois, a promessa já passou e vale a tabela.
    update public.retorno_config set fora_ate = '2026-11-17' where id;
    perform pg_temp.retorno_f1_prazo_confere('8e', public._retorno_prazo('2026-11-17 09:00-03', c_k1),
      'fora_ate', 'fora_ate', '2026-11-17 10:00-03', 'hoje');
    perform pg_temp.retorno_f1_prazo_confere('8f', public._retorno_prazo('2026-11-17 15:00-03', c_k1),
      'meio', 'fechamento', '2026-11-17 19:00-03', 'hoje');
    -- fora_ate que já passou não vale.
    update public.retorno_config set fora_ate = '2026-11-16' where id;
    perform pg_temp.retorno_f1_prazo_confere('8g', public._retorno_prazo('2026-11-17 09:12-03', c_k1),
      'manha_cedo', 'fechamento', '2026-11-17 19:00-03', 'hoje');
    update public.retorno_config set fora_ate = null where id;
    v_casos := v_casos + 7;

    -- ── 9. Dia que o dono marcou indisponível (linha sintética, payee_id nulo) = folga ───────────────────────
    begin
      insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota)
      values (null, daterange('2026-11-18', '2026-11-18', '[]'), 'indisponivel', 'dono', 'Teste F1 prazo (sintético)');
      if public.agenda_dia_util('2026-11-18') then
        raise exception '9: a linha sintética não fez de qua 18/11 um dia indisponível';
      end if;
      perform pg_temp.retorno_f1_prazo_confere('9a', public._retorno_prazo('2026-11-18 10:00-03', c_k1),
        'folga', 'manha', '2026-11-19 10:00-03', 'amanhã', '2026-11-18 10:00-03');
      -- e a véspera à tarde pula o dia indisponível: ter 17/11 16:00 → qui 19/11 10h.
      perform pg_temp.retorno_f1_prazo_confere('9b', public._retorno_prazo('2026-11-17 16:00-03', c_k1),
        'tarde', 'manha', '2026-11-19 10:00-03', 'quinta (19/11)');
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;
    if not public.agenda_dia_util('2026-11-18') then
      raise exception '9c: a linha sintética de agenda_disponibilidade não foi desfeita';
    end if;
    v_casos := v_casos + 2;

    -- ── 10. Pressa com acorde: às 10:00 → 19h acorde; às 20:30 → tabela, nunca acorde ──────────────────────
    perform pg_temp.retorno_f1_prazo_confere('10a', public._retorno_prazo('2026-11-17 10:00-03', c_k1, true, true),
      'pressa', 'acorde', '2026-11-17 19:00-03', 'hoje', '2026-11-17 10:00-03');
    perform pg_temp.retorno_f1_prazo_confere('10b', public._retorno_prazo('2026-11-17 20:30-03', c_k1, true, true),
      'tarde', 'manha', '2026-11-18 10:00-03', 'amanhã');
    -- 23:30 com pressa: espera a manhã (regra 2), nunca acorde.
    perform pg_temp.retorno_f1_prazo_confere('10c', public._retorno_prazo('2026-11-17 23:30-03', c_k1, true, true),
      'noite', 'manha', '2026-11-18 10:00-03', 'hoje');
    -- guarda: às 19:30 o "até as 19h" já passou → tabela.
    perform pg_temp.retorno_f1_prazo_confere('10d', public._retorno_prazo('2026-11-17 19:30-03', c_k1, true, true),
      'tarde', 'manha', '2026-11-18 10:00-03', 'amanhã');
    -- pressa sem o acorde saindo agora (o caso desta leva) não muda a tabela.
    perform pg_temp.retorno_f1_prazo_confere('10e', public._retorno_prazo('2026-11-17 10:00-03', c_k1, true, false),
      'manha_cedo', 'fechamento', '2026-11-17 19:00-03', 'hoje');
    -- e o padrão dos dois parâmetros é falso.
    if public._retorno_prazo('2026-11-17 10:00-03', c_k1) is distinct from public._retorno_prazo('2026-11-17 10:00-03', c_k1, false, false) then
      raise exception '10f: o padrão de p_pressa/p_acorde_agora não é falso';
    end if;
    -- sábado com pressa e acorde: folga (a regra 3 vem antes).
    perform pg_temp.retorno_f1_prazo_confere('10g', public._retorno_prazo('2026-11-21 10:00-03', c_k1, true, true),
      'folga', 'manha', '2026-11-23 10:00-03', 'segunda (23/11)');
    v_casos := v_casos + 7;

    -- ── 11. Calibração: só alonga, e só num momento ────────────────────────────────────────────────────────
    -- 11a. {"meio": {"dias": 1, "hora": "10:00"}} às 12:00 → qua 18/11 10h, sem log.
    update public.retorno_config set promessa_faixa = '{"meio": {"dias": 1, "hora": "10:00"}}' where id;
    v_logs := pg_temp.retorno_f1_prazo_logs();
    perform pg_temp.retorno_f1_prazo_confere('11a', public._retorno_prazo('2026-11-17 12:00-03', c_k1),
      'meio', 'manha', '2026-11-18 10:00-03', 'amanhã', '2026-11-17 12:00-03');
    if pg_temp.retorno_f1_prazo_logs() <> v_logs then
      raise exception '11a: a calibração válida registrou log';
    end if;
    -- a calibração é por faixa: a manhã cedo da mesma configuração segue a tabela.
    perform pg_temp.retorno_f1_prazo_confere('11a2', public._retorno_prazo('2026-11-17 09:12-03', c_k1),
      'manha_cedo', 'fechamento', '2026-11-17 19:00-03', 'hoje');
    -- 11b. {"meio": {"dias": 0, "hora": "14:00"}} com o meio-dia desligado → ignorado (19h) e um log.
    update public.retorno_config set promessa_faixa = '{"meio": {"dias": 0, "hora": "14:00"}}' where id;
    v_logs := pg_temp.retorno_f1_prazo_logs();
    perform pg_temp.retorno_f1_prazo_confere('11b', public._retorno_prazo('2026-11-17 12:00-03', c_k1),
      'meio', 'fechamento', '2026-11-17 19:00-03', 'hoje');
    if pg_temp.retorno_f1_prazo_logs() <= v_logs then
      raise exception '11b: a calibração inválida (14h sem o meio-dia) não registrou log';
    end if;
    v_logs_calibracao := v_logs_calibracao + 1;
    -- 11c. {"meio": {"dias": 0, "hora": "16:00"}} → ignorado (16h não é momento) e um log.
    update public.retorno_config set promessa_faixa = '{"meio": {"dias": 0, "hora": "16:00"}}' where id;
    v_logs := pg_temp.retorno_f1_prazo_logs();
    perform pg_temp.retorno_f1_prazo_confere('11c', public._retorno_prazo('2026-11-17 12:00-03', c_k1),
      'meio', 'fechamento', '2026-11-17 19:00-03', 'hoje');
    if pg_temp.retorno_f1_prazo_logs() <= v_logs then
      raise exception '11c: a calibração fora de um momento não registrou log';
    end if;
    v_logs_calibracao := v_logs_calibracao + 1;
    -- 11d. Encurtar nunca: a manhã cedo (tabela 19h) calibrada para 10h do mesmo dia → ignorada e log.
    update public.retorno_config set promessa_faixa = '{"manha_cedo": {"dias": 0, "hora": "10:00"}}' where id;
    v_logs := pg_temp.retorno_f1_prazo_logs();
    perform pg_temp.retorno_f1_prazo_confere('11d', public._retorno_prazo('2026-11-17 09:12-03', c_k1),
      'manha_cedo', 'fechamento', '2026-11-17 19:00-03', 'hoje');
    if pg_temp.retorno_f1_prazo_logs() <= v_logs then
      raise exception '11d: a calibração que encurtaria não registrou log';
    end if;
    v_logs_calibracao := v_logs_calibracao + 1;
    -- 11e. Com o meio-dia LIGADO, a mesma manhã cedo calibrada para 19h alonga (14h → 19h), sem log.
    update public.retorno_config set meio_dia_ligado = true,
                                     promessa_faixa = '{"manha_cedo": {"dias": 0, "hora": "19:00"}}' where id;
    v_logs := pg_temp.retorno_f1_prazo_logs();
    perform pg_temp.retorno_f1_prazo_confere('11e', public._retorno_prazo('2026-11-17 09:12-03', c_k1),
      'manha_cedo', 'fechamento', '2026-11-17 19:00-03', 'hoje');
    if pg_temp.retorno_f1_prazo_logs() <> v_logs then
      raise exception '11e: a calibração válida (14h → 19h) registrou log';
    end if;
    -- 11f. Com o meio-dia desligado, essa mesma calibração é igual à tabela: nada muda e não há log.
    update public.retorno_config set meio_dia_ligado = false where id;
    v_logs := pg_temp.retorno_f1_prazo_logs();
    perform pg_temp.retorno_f1_prazo_confere('11f', public._retorno_prazo('2026-11-17 09:12-03', c_k1),
      'manha_cedo', 'fechamento', '2026-11-17 19:00-03', 'hoje');
    if pg_temp.retorno_f1_prazo_logs() <> v_logs then
      raise exception '11f: a calibração igual à tabela registrou log';
    end if;
    -- 11g. A tarde (tabela: amanhã 10h) calibrada para 19h do mesmo dia da tabela → qua 18/11 19h.
    update public.retorno_config set promessa_faixa = '{"tarde": {"dias": 0, "hora": "19:00"}}' where id;
    perform pg_temp.retorno_f1_prazo_confere('11g', public._retorno_prazo('2026-11-17 15:30-03', c_k1),
      'tarde', 'fechamento', '2026-11-18 19:00-03', 'amanhã');
    -- 11h. A noite com "dias": 1 → o dia útil seguinte ao da tabela (qua 18/11 10h, recibo ter de manhã).
    update public.retorno_config set promessa_faixa = '{"noite": {"dias": 1, "hora": "10:00"}}' where id;
    perform pg_temp.retorno_f1_prazo_confere('11h', public._retorno_prazo('2026-11-17 02:00-03', c_k1),
      'noite', 'manha', '2026-11-18 10:00-03', 'amanhã');
    -- 11i. Valores mal formados: ignorados (vale a tabela) e registrados.
    foreach v_nome in array array['{"meio": {"dias": 2, "hora": "19:00"}}', '{"meio": {"dias": "1", "hora": "10:00"}}',
                                  '{"meio": {"dias": 1}}', '{"meio": {"dias": 1, "hora": "10h"}}', '{"meio": "amanhã"}']
    loop
      update public.retorno_config set promessa_faixa = v_nome::jsonb where id;
      v_logs := pg_temp.retorno_f1_prazo_logs();
      perform pg_temp.retorno_f1_prazo_confere('11i ' || v_nome, public._retorno_prazo('2026-11-17 12:00-03', c_k1),
        'meio', 'fechamento', '2026-11-17 19:00-03', 'hoje');
      if pg_temp.retorno_f1_prazo_logs() <= v_logs then
        raise exception '11i: o valor mal formado % não registrou log', v_nome;
      end if;
      v_logs_calibracao := v_logs_calibracao + 1;
    end loop;
    -- 11j. fora_ate não é calibrada: a calibração dela é ignorada (com log) e a promessa segue a da volta.
    update public.retorno_config set fora_ate = '2026-11-25',
                                     promessa_faixa = '{"fora_ate": {"dias": 1, "hora": "19:00"}}' where id;
    v_logs := pg_temp.retorno_f1_prazo_logs();
    perform pg_temp.retorno_f1_prazo_confere('11j', public._retorno_prazo('2026-11-23 10:00-03', c_k1),
      'fora_ate', 'fora_ate', '2026-11-25 10:00-03', 'quarta (25/11)');
    if pg_temp.retorno_f1_prazo_logs() <= v_logs then
      raise exception '11j: a calibração da faixa fora_ate não registrou log';
    end if;
    v_logs_calibracao := v_logs_calibracao + 1;
    update public.retorno_config set fora_ate = null, promessa_faixa = '{}' where id;
    -- o log da calibração é 'warn', no contexto do retorno, com a faixa e o motivo.
    if not exists (select 1 from public.app_error_logs l
                    where l.context = 'retorno' and l.action = 'promessa_faixa' and l.level = 'warn'
                      and l.last_seen_at = now() and l.details ->> 'faixa' = 'meio' and l.details ? 'motivo') then
      raise exception '11k: o log da calibração não é warn com a faixa e o motivo';
    end if;
    v_casos := v_casos + 13;

    -- ── 12. X2: 10h → 19h (meio-dia desligado) ou 14h (ligado); 14h → 19h; 19h → nulo ────────────────────────
    if public._retorno_x2('2026-11-17 10:00-03') is distinct from '2026-11-17 19:00-03'::timestamptz
       or public._retorno_x2('2026-11-17 14:00-03') is distinct from '2026-11-17 19:00-03'::timestamptz
       or public._retorno_x2('2026-11-17 19:00-03') is not null
       or public._retorno_x2(null) is not null then
      raise exception '12a: X2 com o meio-dia desligado fora da especificação';
    end if;
    update public.retorno_config set meio_dia_ligado = true where id;
    if public._retorno_x2('2026-11-17 10:00-03') is distinct from '2026-11-17 14:00-03'::timestamptz
       or public._retorno_x2('2026-11-17 14:00-03') is distinct from '2026-11-17 19:00-03'::timestamptz
       or public._retorno_x2('2026-11-17 19:00-03') is not null then
      raise exception '12b: X2 com o meio-dia ligado fora da especificação';
    end if;
    update public.retorno_config set meio_dia_ligado = false where id;
    v_casos := v_casos + 2;

    -- ── 13. Hash no limite: hashtext = -2147483648 não estoura (abs de int4 daria 22003) ────────────────────
    if hashtext(c_k_min || '2026-11-18') <> -2147483648 then
      raise exception '13: premissa: hashtext(%) não é -2147483648 neste banco', c_k_min || '2026-11-18';
    end if;
    begin
      v_t1 := public._retorno_proxima_manha('2026-11-17 23:00-03', c_k_min);
      v_pz2 := public._retorno_prazo('2026-11-17 23:00-03', c_k_min);
    exception when others then
      raise exception '13: a chave de hash mínimo derrubou a manhã (% %)', sqlstate, sqlerrm;
    end;
    -- 2147483648 mod 1800 = 848 s → 08:14:08.
    if v_t1 is distinct from '2026-11-18 08:14:08-03'::timestamptz then
      raise exception '13b: manhã da chave de hash mínimo: %', v_t1;
    end if;
    perform pg_temp.retorno_f1_prazo_confere('13c', v_pz2, 'noite', 'manha', '2026-11-18 10:00-03', 'hoje', '2026-11-18 08:14:08-03');
    v_casos := v_casos + 2;

    -- ── Falha fecha: sem a linha de configuração, o prazo sobe (55000) em vez de inventar ────────────────
    begin
      delete from public.retorno_config;
      begin
        perform public._retorno_prazo('2026-11-17 09:12-03', c_k1);
        v_erro := 'passou';
      exception when others then
        v_erro := sqlstate;
      end;
      raise exception 'desfaz' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'desfaz' then raise; end if;
    end;
    if v_erro is distinct from '55000' then
      raise exception '14: sem a linha de retorno_config o prazo não subiu 55000 (%)', v_erro;
    end if;
    if public._retorno_prazo(null, c_k1) is not null or public._retorno_proxima_manha(null, c_k1) is not null then
      raise exception '14b: hora nula não devolveu nulo';
    end if;
    -- chave nula não deixa a manhã nula (o recibo nunca fica sem hora).
    if public._retorno_proxima_manha('2026-11-17 23:00-03', null) is null then
      raise exception '14c: chave nula deixou a manhã nula';
    end if;
    v_casos := v_casos + 3;

    v_chegou := true;
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'desfaz' then raise; end if;
  end;
  if not v_chegou then
    raise exception '0g: o arranjo não chegou ao fim';
  end if;
  if exists (select 1 from public.agenda_disponibilidade where nota = 'Teste F1 prazo (sintético)') then
    raise exception '0h: o arranjo não foi desfeito';
  end if;

  insert into _bancada (arquivo, ok, numeros)
  values ('retorno_f1_prazo', true, jsonb_build_object('casos', v_casos, 'logs_calibracao', v_logs_calibracao));
end
$prazo$;

select arquivo, ok, numeros from _bancada order by em;
rollback;
