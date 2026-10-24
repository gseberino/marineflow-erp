-- Agenda de Produção, Fase 1, pacote P1: o calendário e os textos curtos, em SQL.
-- Spec: scratchpad agenda-pesquisa/spec-fase1.md (§5.1). Depende de 20261024160000 (agenda_config e
-- agenda_disponibilidade).
--
-- ═══ DDL — OK NOMEADO ═══ (só funções novas e um GRANT em _dia_curto; não grava dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: o modelo nunca calcula data. Toda data que o dono lê ou diz passa por aqui: "dia 3", "terça",
-- "semana que vem", "daqui a 2 dias úteis" viram datas no banco, e a resposta sai com _dia_curto ("ter 03/11").
--
-- O QUE MUDA:
--   1. agenda_pascoa(ano) e agenda_feriado(dia): os mesmos feriados de _shared/secretario/feriados.ts — os 9
--      nacionais fixos (com 20/11, Consciência Negra), 15/06 (aniversário de Itajaí) e a Sexta-feira Santa.
--      Carnaval, Corpus Christi e o 11/08 de SC ficam fora, como lá. A paridade é provada dia a dia, de 2026 a
--      2035 (3.652 dias), contra supabase/tests/agenda/feriados_2026_2035.json, que é gerado de feriados.ts
--      (feriados-paridade_test.ts). Mudou um lado, muda o outro na mesma leva.
--   2. _agenda_cfg(): a linha de agenda_config; lança se não existir (nunca inventa parâmetro).
--   3. agenda_dia_util(dia): não é domingo, não é sábado (salvo sabado_util), não é feriado e não há recesso
--      (agenda_disponibilidade sem pessoa, indisponível, dia inteiro, cobrindo o dia).
--   4. agenda_somar_du(dia, n) e agenda_du_entre(de, ate): dias úteis para a frente e para trás, e quantos úteis
--      há em (de, ate] — a mesma semântica de businessDaysBetween (task-automations/rules.ts), agora com
--      feriado e recesso.
--   5. agenda_data_dita(texto, hoje, sentido): o que o dono disse vira {de, ate, texto}. Hoje, amanhã, depois
--      de amanhã, ontem, anteontem; dia da semana (com "-feira", "que vem", "próxima", "passada"); "dia N" e
--      "N"; "dd/mm" e "dd/mm/aa(aa)"; "N de novembro"; faixas "entre X e Y", "de X a Y", "X a Y", "X ou Y",
--      "até X"; "daqui a N dias" (corridos); "em/daqui a N dias úteis"; "semana que vem" (seg a sex);
--      números por extenso de 1 a 31. Não entendeu → erro 22007 com a frase para o dono.
--   6. agenda_dias_da_semana_ditos(texto): "segunda a sexta", "seg, qua e sex", "terças e quintas",
--      "todo dia", "dia de semana", "sábado", "segunda a sexta menos quarta" viram os dias ISO.
--   7. Textos curtos: _agenda_lista ("A, B e C", "e mais 2"), _agenda_dias ("meio dia", "1,5 dia"),
--      _agenda_faixa_dias ("1,5 a 3 dias"), _agenda_nome_curto ("LENINE LORI BROCCA" → "Lenine").
--   8. grant execute em _dia_curto(date) a authenticated: as leituras security invoker do painel usam a data
--      curta (hoje só service_role).
--
-- PORTAS: todas com search_path fixo; revoke de public e anon; execute para authenticated e service_role (as
-- leituras são security invoker e chamam estas). Nenhuma é security definer.
--
-- O QUE NÃO MUDA: _dia_curto (só ganha o grant), feriados.ts, nenhuma tabela.
--
-- ORDEM DE LIGAR: depois de 20261024160000; antes de 20261024160200 (a semente usa agenda_dia_util).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase1_base.sql. Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261024160200
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261024160100_agenda_fase1_calendario.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024160100', 'agenda_fase1_calendario');"
--
-- IDEMPOTENTE: create or replace function; revoke/grant repetidos não mudam nada.

-- ── 1. Feriados ─────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.agenda_pascoa(p_ano integer)
 returns date
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  -- Meeus/Jones/Butcher, calendário gregoriano — o mesmo cálculo de pascoa() em feriados.ts.
  a int := p_ano % 19;
  b int := p_ano / 100;
  c int := p_ano % 100;
  d int := b / 4;
  e int := b % 4;
  f int := (b + 8) / 25;
  g int := (b - f + 1) / 3;
  h int := (19 * a + b - d - g + 15) % 30;
  i int := c / 4;
  k int := c % 4;
  l int := (32 + 2 * e + 2 * i - h - k) % 7;
  m int := (a + 11 * h + 22 * l) / 451;
begin
  if p_ano is null then return null; end if;
  return make_date(p_ano, (h + l - 7 * m + 114) / 31, ((h + l - 7 * m + 114) % 31) + 1);
end;
$function$;

comment on function public.agenda_pascoa(integer) is
  'Domingo de Páscoa do ano (Meeus/Jones/Butcher). Igual a pascoa() de _shared/secretario/feriados.ts.';

create or replace function public.agenda_feriado(p_dia date)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
begin
  if p_dia is null then return null; end if;
  -- Os fixos vêm antes da Sexta-feira Santa, como em feriadoDoDia() (feriados.ts).
  case extract(month from p_dia)::int * 100 + extract(day from p_dia)::int
    when 101  then return 'Ano-Novo';
    when 421  then return 'Tiradentes';
    when 501  then return 'Dia do Trabalho';
    when 615  then return 'aniversário de Itajaí';
    when 907  then return 'Independência';
    when 1012 then return 'Nossa Senhora Aparecida';
    when 1102 then return 'Finados';
    when 1115 then return 'Proclamação da República';
    when 1120 then return 'Consciência Negra';
    when 1225 then return 'Natal';
    else null;
  end case;
  if p_dia = public.agenda_pascoa(extract(year from p_dia)::int) - 2 then return 'Sexta-feira Santa'; end if;
  return null;
end;
$function$;

comment on function public.agenda_feriado(date) is
  'Nome do feriado do dia, ou null: os mesmos de feriadoDoDia() em _shared/secretario/feriados.ts (9 nacionais fixos com 20/11, 15/06 de Itajaí e Sexta-feira Santa; sem Carnaval, Corpus Christi e 11/08). Paridade 2026–2035 em supabase/tests/agenda/feriados_2026_2035.json.';

-- ── 2. Parâmetros e dia útil ────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_cfg()
 returns public.agenda_config
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  r public.agenda_config;
begin
  select * into r from public.agenda_config where id;
  if not found then
    raise exception 'A agenda está sem os parâmetros (agenda_config vazia ou fora do alcance deste usuário).'
      using errcode = 'P0002';
  end if;
  return r;
end;
$function$;

comment on function public._agenda_cfg() is
  'A linha de parâmetros da agenda (agenda_config). Lança se não existir: parâmetro nunca é inventado.';

create or replace function public.agenda_dia_util(p_dia date)
 returns boolean
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_dow int := extract(isodow from p_dia)::int;
begin
  if p_dia is null then return null; end if;
  if v_dow = 7 then return false; end if;
  if v_dow = 6 and not (public._agenda_cfg()).sabado_util then return false; end if;
  if public.agenda_feriado(p_dia) is not null then return false; end if;
  return not exists (
    select 1 from public.agenda_disponibilidade d
     where d.payee_id is null and d.situacao = 'indisponivel' and d.turno is null
       and d.substituida_em is null and d.periodo @> p_dia);
end;
$function$;

comment on function public.agenda_dia_util(date) is
  'Dia útil da agenda: nem domingo, nem sábado (salvo agenda_config.sabado_util), nem feriado (agenda_feriado), nem recesso (agenda_disponibilidade sem pessoa, indisponível, dia inteiro).';

create or replace function public.agenda_somar_du(p_dia date, p_n integer)
 returns date
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_dia    date := p_dia;
  v_restam int := abs(p_n);
  v_passo  int := case when p_n < 0 then -1 else 1 end;
  v_voltas int := 0;
begin
  if p_dia is null or p_n is null then return null; end if;
  if p_n = 0 then
    while not public.agenda_dia_util(v_dia) loop
      v_dia := v_dia + 1;
      v_voltas := v_voltas + 1;
      if v_voltas > 400 then
        raise exception 'agenda_somar_du: nenhum dia útil em 400 dias a partir de %', p_dia using errcode = '54000';
      end if;
    end loop;
    return v_dia;
  end if;
  while v_restam > 0 loop
    v_dia := v_dia + v_passo;
    v_voltas := v_voltas + 1;
    if v_voltas > 400 then
      raise exception 'agenda_somar_du: % dias úteis a partir de % passam de 400 dias', p_n, p_dia using errcode = '54000';
    end if;
    if public.agenda_dia_util(v_dia) then v_restam := v_restam - 1; end if;
  end loop;
  return v_dia;
end;
$function$;

comment on function public.agenda_somar_du(date, integer) is
  'n > 0: o n-ésimo dia útil DEPOIS do dia; n = 0: o próprio dia se útil, senão o próximo útil; n < 0: o n-ésimo útil ANTES. Teto de 400 dias corridos (lança).';

create or replace function public.agenda_du_entre(p_de date, p_ate date)
 returns integer
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when p_de is null or p_ate is null then null
    when p_ate >= p_de then
      (select count(*)::int from generate_series(1, p_ate - p_de) g(i) where public.agenda_dia_util(p_de + g.i))
    else
      -(select count(*)::int from generate_series(1, p_de - p_ate) g(i) where public.agenda_dia_util(p_ate + g.i))
  end;
$function$;

comment on function public.agenda_du_entre(date, date) is
  'Dias úteis em (de, ate] — aberto no começo, fechado no fim, como businessDaysBetween (rules.ts); negativo quando ate < de.';

-- ── 3. O que o dono disse → data ────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_normal(p text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  -- Minúsculo, sem acento (translate, sem depender de locale nem de extensão), "26-10"/"26.10" viram "26/10",
  -- o resto da pontuação vira espaço, espaços colapsados.
  select btrim(regexp_replace(regexp_replace(regexp_replace(
           lower(translate(coalesce(p, ''),
             'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäéèêëíìîïóòôõöúùûüçñºª',
             'aaaaaeeeeiiiiooooouuuucnaaaaaeeeeiiiiooooouuuucn')),
           '(\d)\s*[.-]\s*(\d)', '\1/\2', 'g'),
           '[^a-z0-9/ ]', ' ', 'g'),
           '\s+', ' ', 'g'));
$function$;

comment on function public._agenda_normal(text) is
  'Texto dito pelo dono, normalizado para as leituras de data: minúsculo, sem acento, pontuação vira espaço (menos a barra das datas).';

create or replace function public._agenda_preparar_data(p_texto text)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  s text := public._agenda_normal(p_texto);
  par text[];
  unidades text[] := array['um','dois','tres','quatro','cinco','seis','sete','oito','nove'];
  meses text[] := array['janeiro','fevereiro','marco','abril','maio','junho','julho','agosto','setembro',
                        'outubro','novembro','dezembro'];
  abrev text[] := array['jan','fev',null,'abr',null,'jun','jul','ago','set','out','nov',null];
  k int;
begin
  -- Por extenso (1 a 31): primeiro os compostos, depois as palavras soltas.
  for k in 1..9 loop
    s := regexp_replace(s, '\mvinte e ' || unidades[k] || '\M', (20 + k)::text, 'g');
  end loop;
  s := regexp_replace(s, '\mtrinta e um\M', '31', 'g');
  foreach par slice 1 in array array[
    ['dezesseis','16'], ['dezasseis','16'], ['dezessete','17'], ['dezassete','17'], ['dezoito','18'],
    ['dezenove','19'], ['dezanove','19'], ['onze','11'], ['doze','12'], ['treze','13'], ['quatorze','14'],
    ['catorze','14'], ['quinze','15'], ['vinte','20'], ['trinta','30'], ['dez','10'], ['primeiro','1'],
    ['um','1'], ['uma','1'], ['dois','2'], ['duas','2'], ['tres','3'], ['quatro','4'], ['cinco','5'],
    ['seis','6'], ['sete','7'], ['oito','8'], ['nove','9']]
  loop
    s := regexp_replace(s, '\m' || par[1] || '\M', par[2], 'g');
  end loop;
  -- "3 de novembro (de 2026)" → "3/11(/2026)". Sem "mar", "mai" e "dez" abreviados (mar, maio, número).
  for k in 1..12 loop
    s := regexp_replace(s, '\m(\d{1,2}) de ' || meses[k] || '\M', '\1/' || k::text, 'g');
    if abrev[k] is not null then
      s := regexp_replace(s, '\m(\d{1,2}) de ' || abrev[k] || '\M', '\1/' || k::text, 'g');
    end if;
  end loop;
  s := regexp_replace(s, '(\d{1,2}/\d{1,2}) de (\d{4})\M', '\1/\2', 'g');
  -- Expressões de várias palavras viram uma só, para os separadores de faixa (" a ", " e ") não as partirem.
  s := regexp_replace(s, '\mdepois de amanha\M', 'depoisdeamanha', 'g');
  s := regexp_replace(s, '\m(semana que vem|proxima semana|semana seguinte)\M', 'semanaquevem', 'g');
  s := regexp_replace(s, '\m(segunda|terca|quarta|quinta|sexta) feira\M', '\1', 'g');
  s := regexp_replace(s, '\m(?:daqui a |daqui |em |dentro de )?(\d{1,3}) (?:dias uteis|dia util)\M', 'du:\1', 'g');
  s := regexp_replace(s, '\m(?:daqui a |daqui |em |dentro de )(\d{1,3}) dias?\M', 'dc:\1', 'g');
  return btrim(regexp_replace(s, '\s+', ' ', 'g'));
end;
$function$;

comment on function public._agenda_preparar_data(text) is
  'Prepara o texto de data dito pelo dono: normaliza, troca número por extenso (1–31) e mês por número, e junta "depois de amanhã", "semana que vem", "N dias (úteis)" numa palavra só.';

create or replace function public._agenda_data_valida(p_ano integer, p_mes integer, p_dia integer)
 returns date
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
begin
  if p_ano is null or p_mes is null or p_dia is null then return null; end if;
  if p_ano not between 1900 and 2200 or p_mes not between 1 and 12 or p_dia not between 1 and 31 then return null; end if;
  if p_dia > extract(day from (make_date(p_ano, p_mes, 1) + interval '1 month' - interval '1 day'))::int then
    return null;
  end if;
  return make_date(p_ano, p_mes, p_dia);
end;
$function$;

comment on function public._agenda_data_valida(integer, integer, integer) is
  'make_date que devolve null em vez de erro (31/02, mês 13): a data inválida vira "não entendi".';

create or replace function public._agenda_isodow_dito(p text)
 returns integer
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p
    when 'segunda' then 1 when 'seg' then 1
    when 'terca'   then 2 when 'ter' then 2
    when 'quarta'  then 3 when 'qua' then 3
    when 'quinta'  then 4 when 'qui' then 4
    when 'sexta'   then 5 when 'sex' then 5
    when 'sabado'  then 6 when 'sab' then 6
    when 'domingo' then 7 when 'dom' then 7
  end;
$function$;

comment on function public._agenda_isodow_dito(text) is
  'Dia da semana ISO (1 = segunda … 7 = domingo) do nome já normalizado ("terca", "qui"); null se não for.';

create or replace function public._agenda_data_um(p_s text, p_hoje date, p_sentido text, p_lado boolean,
                                                  p_mes_de date, p_depois_de date)
 returns date
 language plpgsql
 stable
 set search_path to 'public'
as $function$
-- UMA data do texto já preparado. null = não entendi (quem chama decide o erro).
--   p_lado:      é um lado de faixa ("3" em "entre 3 e 5/11"): aceita número solto em qualquer posição;
--   p_mes_de:    o lado esquerdo herda mês e ano do direito ("3" de "3 a 5/11" = 03/11);
--   p_depois_de: o lado direito é o primeiro dia >= o esquerdo ("segunda a sexta").
declare
  s text := btrim(coalesce(p_s, ''));
  m text[];
  v_sentido text := p_sentido;
  v_dow int;
  v_n int;
  v_ano int;
  v_d date;
  v_fut date;
  v_pas date;
  v_base date;
  k int;
begin
  if s = '' or p_hoje is null then return null; end if;

  -- dd/mm e dd/mm/aa(aa): sem ano, o que deixa a data entre hoje − 180 e hoje + 185 (o mais perto de hoje).
  m := regexp_match(s, '(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?');
  if m is not null then
    if m[3] is not null then
      v_ano := m[3]::int;
      if v_ano < 100 then v_ano := 2000 + v_ano; end if;
      return public._agenda_data_valida(v_ano, m[2]::int, m[1]::int);
    end if;
    for v_ano in extract(year from p_hoje)::int - 1 .. extract(year from p_hoje)::int + 1 loop
      v_d := public._agenda_data_valida(v_ano, m[2]::int, m[1]::int);
      if v_d is not null and v_d between p_hoje - 180 and p_hoje + 185
         and (v_fut is null or abs(v_d - p_hoje) < abs(v_fut - p_hoje)) then
        v_fut := v_d;
      end if;
    end loop;
    return v_fut;
  end if;

  -- "daqui a N dias úteis" e "daqui a N dias" (corridos).
  m := regexp_match(s, '\mdu:(\d{1,3})\M');
  if m is not null then return public.agenda_somar_du(p_hoje, m[1]::int); end if;
  m := regexp_match(s, '\mdc:(\d{1,3})\M');
  if m is not null then return p_hoje + m[1]::int; end if;

  if s ~ '\mdepoisdeamanha\M' then return p_hoje + 2; end if;
  if s ~ '\manteontem\M' then return p_hoje - 2; end if;
  if s ~ '\mamanha\M' then return p_hoje + 1; end if;
  if s ~ '\montem\M' then return p_hoje - 1; end if;
  if s ~ '\mhoje\M' then return p_hoje; end if;

  -- Dia da semana. Abreviado ("qui") só quando é o texto inteiro: "ter" também é verbo.
  m := regexp_match(s, '\m(segunda|terca|quarta|quinta|sexta|sabado|domingo)\M');
  if m is null and s ~ '^(seg|ter|qua|qui|sex|sab|dom)$' then m := array[s]; end if;
  if m is not null then
    v_dow := public._agenda_isodow_dito(m[1]);
    if s ~ '\msemanaquevem\M' then  -- "terça da semana que vem": a terça da próxima semana ISO
      return p_hoje + (8 - extract(isodow from p_hoje)::int) + (v_dow - 1);
    end if;
    if p_depois_de is not null then
      return p_depois_de + ((v_dow - extract(isodow from p_depois_de)::int + 7) % 7);
    end if;
    if s ~ '\m(passada|passado)\M' then v_sentido := 'passado';
    elsif s ~ '\m(que vem|proxima|proximo)\M' then v_sentido := 'futuro';
    end if;
    -- Estritamente depois / antes de hoje: hoje se diz "hoje".
    v_fut := p_hoje + (((v_dow - extract(isodow from p_hoje)::int + 6) % 7) + 1);
    v_pas := p_hoje - (((extract(isodow from p_hoje)::int - v_dow + 6) % 7) + 1);
    return case v_sentido
      when 'passado' then v_pas
      when 'futuro'  then v_fut
      else case when v_fut - p_hoje <= p_hoje - v_pas then v_fut else v_pas end
    end;
  end if;

  -- "dia N"; "N" sozinho (ou, num lado de faixa, o número em qualquer posição).
  m := regexp_match(s, '\mdia (\d{1,2})\M');
  if m is null then
    if p_lado then
      m := regexp_match(s, '\m(\d{1,2})\M');
    else
      m := regexp_match(s, '^(?:(?:o|no|na|em|pro|pra|para) )?(\d{1,2})$');
    end if;
  end if;
  if m is null then return null; end if;
  v_n := m[1]::int;
  if v_n not between 1 and 31 then return null; end if;

  if p_mes_de is not null then
    v_d := public._agenda_data_valida(extract(year from p_mes_de)::int, extract(month from p_mes_de)::int, v_n);
    if v_d is null or v_d > p_mes_de then
      v_base := (p_mes_de - interval '1 month')::date;
      v_d := public._agenda_data_valida(extract(year from v_base)::int, extract(month from v_base)::int, v_n);
    end if;
    return v_d;
  end if;

  v_base := coalesce(p_depois_de, p_hoje);
  v_fut := null;
  for k in 0..12 loop                     -- o 1º dia >= a base com esse dia do mês
    v_d := (date_trunc('month', v_base::timestamp) + make_interval(months => k))::date;
    v_d := public._agenda_data_valida(extract(year from v_d)::int, extract(month from v_d)::int, v_n);
    if v_d is not null and v_d >= v_base then v_fut := v_d; exit; end if;
  end loop;
  if p_depois_de is not null then return v_fut; end if;
  v_pas := null;
  for k in 0..12 loop                     -- o último dia <= hoje com esse dia do mês
    v_d := (date_trunc('month', p_hoje::timestamp) - make_interval(months => k))::date;
    v_d := public._agenda_data_valida(extract(year from v_d)::int, extract(month from v_d)::int, v_n);
    if v_d is not null and v_d <= p_hoje then v_pas := v_d; exit; end if;
  end loop;
  return case v_sentido
    when 'passado' then v_pas
    when 'futuro'  then v_fut
    else case when v_pas is null or (v_fut is not null and v_fut - p_hoje <= p_hoje - v_pas) then v_fut else v_pas end
  end;
end;
$function$;

comment on function public._agenda_data_um(text, date, text, boolean, date, date) is
  'Uma data do texto já preparado por _agenda_preparar_data; null quando não entende. Interna de agenda_data_dita.';

create or replace function public.agenda_data_dita(p_texto text, p_hoje date, p_sentido text default 'futuro')
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  s text := public._agenda_preparar_data(p_texto);
  v_ps text;
  v_sep text;
  v_i int;
  v_esq text;
  v_dir text;
  v_de date;
  v_ate date;
  v_ref date;
  v_invertida boolean := false;
begin
  if p_sentido is null or p_sentido not in ('futuro','passado','qualquer') then
    raise exception 'agenda_data_dita: sentido "%" inválido (futuro, passado ou qualquer)', p_sentido
      using errcode = '22023';
  end if;
  if p_hoje is null then
    raise exception 'agenda_data_dita: sem o dia de hoje' using errcode = '22004';
  end if;

  if s <> '' then
    -- "semana que vem" sozinha: de segunda a sexta da próxima semana.
    if s ~ '\msemanaquevem\M' and s !~ '\m(segunda|terca|quarta|quinta|sexta|sabado|domingo)\M' then
      v_de := p_hoje + (8 - extract(isodow from p_hoje)::int);
      v_ate := v_de + 4;
    else
      -- Faixas: "entre X e Y", "X ou Y", "até Y" / "X até Y", "de X a Y" / "X a Y". O primeiro separador
      -- cujos dois lados são datas vence; senão, a data única.
      foreach v_sep in array array['entre','ou','ate','a'] loop
        v_ps := ' ' || s || ' ';
        if v_sep = 'entre' then
          v_i := strpos(v_ps, ' entre ');
          continue when v_i = 0;
          v_ps := ' ' || btrim(substr(v_ps, v_i + 7)) || ' ';
          v_i := strpos(v_ps, ' e ');
          continue when v_i = 0;
          v_esq := btrim(substr(v_ps, 1, v_i));
          v_dir := btrim(substr(v_ps, v_i + 3));
        else
          v_i := strpos(v_ps, ' ' || v_sep || ' ');
          continue when v_i = 0;
          v_esq := btrim(substr(v_ps, 1, v_i));
          v_dir := btrim(substr(v_ps, v_i + length(v_sep) + 2));
        end if;
        v_ref := public._agenda_data_um(v_dir, p_hoje, p_sentido, true, null, null);
        continue when v_ref is null;
        if v_sep = 'ate' and v_esq = '' then
          -- "até sexta": de hoje até a data dita, como ela é.
          v_de := p_hoje;
          v_ate := v_ref;
        else
          v_de := public._agenda_data_um(v_esq, p_hoje, p_sentido, true,
                    case when v_dir ~ '\d{1,2}/\d{1,2}'
                          and v_esq ~ '^(?:(?:de|do|entre|o|no) )?(?:dia )?\d{1,2}$' then v_ref end,
                    null);
          continue when v_de is null;
          -- O lado direito é o primeiro dia >= o esquerdo ("segunda a sexta", "dia 28 a dia 3").
          v_ate := public._agenda_data_um(v_dir, p_hoje, p_sentido, true, null, v_de);
        end if;
        if v_ate is not null and v_ate < v_de then v_invertida := true; end if;
        if v_ate is null or v_ate < v_de then v_de := null; v_ate := null; continue; end if;
        exit;
      end loop;
      -- "30/10 a 26/10": as duas datas existem, mas a faixa está ao contrário. Melhor perguntar do que escolher uma.
      if v_de is null and not v_invertida then
        v_de := public._agenda_data_um(s, p_hoje, p_sentido, false, null, null);
        v_ate := v_de;
      end if;
    end if;
  end if;

  if v_de is null then
    raise exception 'Não entendi a data "%". Diga como "dia 3", "03/11", "terça" ou "amanhã".', btrim(coalesce(p_texto, ''))
      using errcode = '22007';
  end if;
  return jsonb_build_object(
    'de', v_de,
    'ate', v_ate,
    'texto', case when v_de = v_ate then public._dia_curto(v_de)
                  else public._dia_curto(v_de) || ' a ' || public._dia_curto(v_ate) end);
end;
$function$;

comment on function public.agenda_data_dita(text, date, text) is
  'O que o dono disse ("dia 3", "terça", "semana que vem", "entre 3 e 5/11", "daqui a 2 dias úteis") vira {de, ate, texto} com o texto por _dia_curto. sentido futuro (padrão), passado ou qualquer. Não entendeu: erro 22007 com a frase para o dono. O modelo nunca calcula data: passa o texto dito.';

-- ── 4. Dias da semana ditos ─────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_dias_ditos_parte(p_s text)
 returns integer[]
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  dw constant text := '(segunda|terca|quarta|quinta|sexta|sabado|domingo|seg|ter|qua|qui|sex|sab|dom)';
  v_dias int[] := '{}';
  m text[];
  v_a int;
  v_b int;
begin
  if coalesce(p_s, '') = '' then return v_dias; end if;
  if p_s ~ '\m(todo dia|todos os dias|dia de semana|dias de semana|dias uteis|dia util|semana toda|semana inteira)\M' then
    v_dias := v_dias || array[1,2,3,4,5];
  end if;
  for m in select regexp_matches(p_s, '\m' || dw || ' (?:a|ate) ' || dw || '\M', 'g') loop
    v_a := public._agenda_isodow_dito(m[1]);
    v_b := public._agenda_isodow_dito(m[2]);
    loop                                   -- "sexta a segunda" dá a volta, sem o domingo
      if v_a <> 7 then v_dias := v_dias || v_a; end if;
      exit when v_a = v_b;
      v_a := v_a % 7 + 1;
    end loop;
  end loop;
  for m in select regexp_matches(p_s, '\m' || dw || '\M', 'g') loop
    v_dias := v_dias || public._agenda_isodow_dito(m[1]);
  end loop;
  return v_dias;
end;
$function$;

comment on function public._agenda_dias_ditos_parte(text) is
  'Dias ISO citados num pedaço de texto já normalizado (faixas e nomes soltos). Interna de agenda_dias_da_semana_ditos.';

create or replace function public.agenda_dias_da_semana_ditos(p_texto text)
 returns smallint[]
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  s text := public._agenda_normal(p_texto);
  v_ps text;
  v_i int := 0;
  v_tam int := 0;
  v_sep text;
  v_incl int[];
  v_excl int[] := '{}';
  v_res smallint[];
begin
  s := regexp_replace(s, '\m(segunda|terca|quarta|quinta|sexta) feira\M', '\1', 'g');
  s := regexp_replace(s, '\m(segunda|terca|quarta|quinta|sexta|sabado|domingo)s\M', '\1', 'g');
  v_ps := ' ' || s || ' ';
  foreach v_sep in array array['menos','exceto','tirando','salvo'] loop
    v_i := strpos(v_ps, ' ' || v_sep || ' ');
    if v_i > 0 then v_tam := length(v_sep); exit; end if;
  end loop;
  if v_i > 0 then
    v_incl := public._agenda_dias_ditos_parte(btrim(substr(v_ps, 1, v_i)));
    v_excl := public._agenda_dias_ditos_parte(btrim(substr(v_ps, v_i + v_tam + 2)));
  else
    v_incl := public._agenda_dias_ditos_parte(s);
  end if;
  if 7 = any (v_incl) then
    raise exception 'Domingo não entra na agenda. Diga os dias de segunda a sábado, como "segunda a sexta".'
      using errcode = '22007';
  end if;
  select array_agg(distinct d::smallint order by d::smallint) into v_res
    from unnest(v_incl) d
   where not (d = any (v_excl));
  if v_res is null then
    raise exception 'Não entendi os dias "%". Diga como "segunda a sexta", "terças e quintas" ou "seg, qua e sex".',
      btrim(coalesce(p_texto, '')) using errcode = '22007';
  end if;
  return v_res;
end;
$function$;

comment on function public.agenda_dias_da_semana_ditos(text) is
  'Dias da semana ditos ("segunda a sexta", "seg, qua e sex", "terças e quintas", "todo dia", "dia de semana", "sábado", "… menos quarta") em ISO 1..6. Domingo ou nada reconhecido: erro 22007 com a frase para o dono.';

-- ── 5. Textos curtos ────────────────────────────────────────────────────────────────────────────────────
create or replace function public._agenda_lista(p_itens text[], p_max integer default null)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v text[] := array(select x from unnest(coalesce(p_itens, '{}'::text[])) with ordinality u(x, o)
                     where nullif(btrim(x), '') is not null order by o);
  n int := cardinality(v);
  v_max int := greatest(coalesce(p_max, n), 1);
begin
  if n = 0 then return ''; end if;
  if n = 1 then return v[1]; end if;
  if n <= v_max then
    return array_to_string(v[1:n - 1], ', ') || ' e ' || v[n];
  end if;
  return array_to_string(v[1:v_max], ', ') || ' e mais ' || (n - v_max)::text;
end;
$function$;

comment on function public._agenda_lista(text[], integer) is
  '"A", "A e B", "A, B e C"; passou de p_max: "A, B, C e mais 2". Itens vazios saem.';

create or replace function public._agenda_dias(p numeric)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p is null then null
    when p = 0.5 then 'meio dia'
    when p >= 1 and p < 2 then replace(trim_scale(p)::text, '.', ',') || ' dia'
    else replace(trim_scale(p)::text, '.', ',') || ' dias'
  end;
$function$;

comment on function public._agenda_dias(numeric) is '0,5 → "meio dia"; 1 → "1 dia"; 1,5 → "1,5 dia"; 2 → "2 dias".';

create or replace function public._agenda_faixa_dias(p_de numeric, p_ate numeric)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_de is null then public._agenda_dias(p_ate)
    when p_ate is null or p_de = p_ate then public._agenda_dias(p_de)
    else case when p_de = 0.5 then 'meio dia' else replace(trim_scale(p_de)::text, '.', ',') end
         || ' a ' || public._agenda_dias(p_ate)
  end;
$function$;

comment on function public._agenda_faixa_dias(numeric, numeric) is
  '"1,5 a 3 dias", "meio dia a 1 dia"; iguais → _agenda_dias.';

create or replace function public._agenda_nome_curto(p_nome text)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_tok text := (regexp_match(coalesce(p_nome, ''), '^[[:space:]]*([^[:space:],;/()–—-]+)'))[1];
begin
  if v_tok is null then return null; end if;
  -- Sigla de até 3 letras toda maiúscula fica como está ("MP MOTOR HOMES" → "MP").
  if v_tok ~ '^[A-ZÁÀÂÃÉÊÍÓÔÕÚÇ]{1,3}$' then return v_tok; end if;
  -- Maiúscula só na 1ª letra, sem depender do locale do banco para as letras acentuadas.
  return translate(upper(left(v_tok, 1)), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ')
      || translate(lower(substr(v_tok, 2)), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ', 'áàâãäéèêëíìîïóòôõöúùûüçñ');
end;
$function$;

comment on function public._agenda_nome_curto(text) is
  'O 1º nome com inicial maiúscula ("LENINE LORI BROCCA" → "Lenine", "César – Palazzo" → "César"); sigla de até 3 letras maiúsculas fica ("MP MOTOR HOMES" → "MP").';

-- ── Portas ──────────────────────────────────────────────────────────────────────────────────────────────
revoke all on function
  public.agenda_pascoa(integer), public.agenda_feriado(date), public._agenda_cfg(), public.agenda_dia_util(date),
  public.agenda_somar_du(date, integer), public.agenda_du_entre(date, date), public._agenda_normal(text),
  public._agenda_preparar_data(text), public._agenda_data_valida(integer, integer, integer),
  public._agenda_isodow_dito(text), public._agenda_data_um(text, date, text, boolean, date, date),
  public.agenda_data_dita(text, date, text), public._agenda_dias_ditos_parte(text),
  public.agenda_dias_da_semana_ditos(text), public._agenda_lista(text[], integer), public._agenda_dias(numeric),
  public._agenda_faixa_dias(numeric, numeric), public._agenda_nome_curto(text)
  from public, anon;
grant execute on function
  public.agenda_pascoa(integer), public.agenda_feriado(date), public._agenda_cfg(), public.agenda_dia_util(date),
  public.agenda_somar_du(date, integer), public.agenda_du_entre(date, date), public._agenda_normal(text),
  public._agenda_preparar_data(text), public._agenda_data_valida(integer, integer, integer),
  public._agenda_isodow_dito(text), public._agenda_data_um(text, date, text, boolean, date, date),
  public.agenda_data_dita(text, date, text), public._agenda_dias_ditos_parte(text),
  public.agenda_dias_da_semana_ditos(text), public._agenda_lista(text[], integer), public._agenda_dias(numeric),
  public._agenda_faixa_dias(numeric, numeric), public._agenda_nome_curto(text)
  to authenticated, service_role;

-- A data curta ("ter 03/11") nas leituras security invoker do painel. Continua sem anon.
grant execute on function public._dia_curto(date) to authenticated;
