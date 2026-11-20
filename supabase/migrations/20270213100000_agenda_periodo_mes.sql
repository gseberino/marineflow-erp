-- Agenda de Produção: o atalho "agenda do mês" (decisão do dono, 20/11/2026: "Sim, criar"). Só UMA função recriada; nenhuma tabela, dado,
-- cron, grant ou tela muda.
--
-- O problema: "agenda da semana" funciona, mas "agenda do mês", "este mês" (dito ao assistente, que passa o período como o dono disse) caíam
-- em agenda_data_dita e voltavam "Não entendi a data "este mes"". Conferido em produção (20/11, só leitura): agenda_data_dita('este mes', …)
-- lança 22007; agenda_semana(hoje, fim do mês, hoje) e agenda_semana(01/12, 31/12, hoje) já respondem (755 letras): faltava só o período.
--
-- O conserto: _agenda_periodo entende o mês, ANTES de cair em agenda_data_dita (que continua igual para o resto):
--   · "mes", "este mes", "esse mes", "neste mes", "nesse mes", "o mes", "do mes", "deste mes", "desse mes", "mes todo", "o mes todo",
--     "ate o fim do mes", "fim do mes"                        → de HOJE até o último dia do mês (no último dia do mês, só hoje: a rota dia)
--   · "proximo mes", "mes que vem", "o mes que vem", "o proximo mes", "do mes que vem", "do proximo mes", "mes seguinte"
--                                                             → do dia 1 ao último dia do mês que vem
-- O "hoje" é o p_hoje de quem chama (agenda_ver recebe _hoje_brt(): o calendário de Brasília), como a semana. Nada do que antes era
-- entendido muda de resposta: as frases novas antes lançavam 22007.
--
-- A RECRIADA parte do corpo VIGENTE em produção (pg_get_functiondef de 20/11 = 20261024160500_agenda_fase1_leituras.sql:201, única
-- definição no repositório); tirado o bloco "-- AGENDA DO MÊS (20/11): … fim", é a origem byte a byte (o teste confere).
-- Prova: supabase/tests/agenda_periodo_mes.sql (begin/rollback; na bancada e em produção depois de aplicar).
--
-- DESFAZER: rodar de novo a definição de _agenda_periodo de 20261024160500_agenda_fase1_leituras.sql (create or replace + comment).
-- IDEMPOTENTE: só create or replace e comment. Os grants da função (authenticated, service_role; anon não) ficam como estão.

create or replace function public._agenda_periodo(p_periodo text, p_hoje date)
 returns table (de date, ate date)
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v   text := btrim(replace(public._agenda_normal(p_periodo), '_', ' '));
  seg date := p_hoje - (extract(isodow from p_hoje)::int - 1);
  d   jsonb;
begin
  if coalesce(v, '') = '' then
    de := null; ate := null;
  elsif v = 'hoje' then
    de := p_hoje; ate := p_hoje;
  elsif v in ('amanha', 'pra amanha', 'de amanha') then
    de := p_hoje + 1; ate := p_hoje + 1;
  elsif v in ('semana', 'esta semana', 'essa semana', 'nesta semana', 'nessa semana', 'a semana', 'da semana') then
    de := seg; ate := seg + 5;
  elsif v in ('proxima semana', 'semana que vem', 'a semana que vem', 'a proxima semana', 'da semana que vem',
              'da proxima semana', 'semana seguinte') then
    de := seg + 7; ate := seg + 12;
  -- AGENDA DO MÊS (20/11): de hoje ao fim do mês; o mês que vem inteiro
  elsif v in ('mes', 'este mes', 'esse mes', 'neste mes', 'nesse mes', 'o mes', 'do mes', 'deste mes', 'desse mes', 'mes todo',
              'o mes todo', 'ate o fim do mes', 'fim do mes') then
    de := p_hoje; ate := (date_trunc('month', p_hoje::timestamp) + interval '1 month - 1 day')::date;
  elsif v in ('proximo mes', 'mes que vem', 'o mes que vem', 'o proximo mes', 'do mes que vem', 'do proximo mes', 'mes seguinte') then
    de := (date_trunc('month', p_hoje::timestamp) + interval '1 month')::date;
    ate := (date_trunc('month', p_hoje::timestamp) + interval '2 months - 1 day')::date;
  -- AGENDA DO MÊS (20/11): fim
  else
    d := public.agenda_data_dita(p_periodo, p_hoje, 'futuro');
    de := (d ->> 'de')::date; ate := (d ->> 'ate')::date;
  end if;
  return next;
end;
$function$;

comment on function public._agenda_periodo(text, date) is 'Agenda de Produção (Fase 1, P4; mês em 20/11/2026): o período pedido — hoje, amanha, semana (seg–sáb desta), proxima_semana (seg–sáb da que vem), mes (de hoje ao fim do mês), proximo_mes (o mês que vem inteiro) ou o que o dono disse por agenda_data_dita (futuro). Vazio = (null, null). Data incompreensível lança 22007 com a frase ao dono.';
