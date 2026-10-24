-- Agenda de Produção, Fase 1, pacote P1: a função que semeia agenda_disponibilidade pelas diárias lançadas.
-- Spec: scratchpad agenda-pesquisa/spec-fase1.md (§3.6, §3.7, §5.2). Depende de 20261024160000 e 160100.
--
-- ═══ DDL — OK NOMEADO ═══ (uma função nova; NÃO roda aqui e não grava dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
-- O dado (a primeira semeadura) é outra migration, 20261024161000_agenda_fase1_semente_dados.sql (pacote P7),
-- que só faz "select public.agenda_disponibilidade_semear();" e pede o seu próprio OK.
--
-- POR QUE: a capacidade da equipe é um número só, medido — Σ da frequência por dia da semana de cada pessoa,
-- pelas diárias das últimas semanas (revisão §6) — e não um chute ("o Roberto vem seg–sex, o João à tarde").
-- O dono só entra quando ele disser o padrão dele (origem 'dono'); a semente nunca toca essas linhas.
--
-- O QUE FAZ agenda_disponibilidade_semear(p_hoje):
--   1. U = a última diária lançada (tipo 'diaria', fração > 0, até p_hoje). Sem nenhuma: não semeia.
--   2. Janela = as agenda_config.medicao_semanas semanas (segunda a domingo) que terminam na semana de U, contadas
--      até U. A spec dizia "até o domingo da semana de U"; aqui vai até U, porque o dia depois da última diária
--      lançada ainda não foi lançado — contar como falta puxaria a frequência para baixo. Na carteira de 23/10
--      (U = sáb 17/10) dá o mesmo: 24/08 a 17/10.
--   3. Equipe = payees ativos (prestador, diarista ou funcionário; nunca o sócio) com work_profiles vigente em
--      p_hoje e com diária nos agenda_config.equipe_recente_dias dias até U. Quem saiu sai pela regra, não pelo
--      nome: o Mickael (última diária 18/09) fica de fora.
--   4. Para cada pessoa e dia ISO de 1 a 5, desde a 1ª diária dela na janela: frequência = Σ das frações (as meias
--      do mesmo dia somam, teto 1) ÷ os dias contados. Conta o dia útil e também o feriado em que ela trabalhou
--      (a spec dizia "feriado não conta no denominador", mas a diária de feriado entra no numerador: sem contar o
--      dia, a frequência passaria de 1). É o que dá o "3 de 5 segundas" do Roberto: 07/09 (feriado, trabalhou)
--      entra, 12/10 (feriado, não trabalhou) não. Sábado nunca entra (só por exceção por data).
--   5. Uma linha por pessoa e dia com frequência >= agenda_config.frequencia_minima: dias_semana = {d}, turno nulo,
--      'disponivel', origem 'historico', nota "semente: 3 de 5 segundas (8 semanas até 17/10)".
--   6. Idempotente: a pessoa cujo conjunto novo é igual ao vigente não é tocada; a que mudou tem as linhas
--      'historico' vigentes marcadas com substituida_em (fica o rastro) antes das novas; quem saiu da equipe tem
--      as dela marcadas. NUNCA toca linhas 'dono', 'diarista' ou 'agente'.
--   Esperado na carteira de 23/10: Roberto seg 0,6 (3/5), ter 0,8333 (5/6), qua/qui/sex 1 → 4,43; João ter 0,5
--   (1,5/3), qua 0,6667, qui 0,6667, sex 0,5 → 2,33 (segunda 0 de 1: sem linha); Mickael nada. Total 6,77.
--
-- PORTAS: security definer (escreve em agenda_disponibilidade, que não tem policy de escrita); search_path fixo;
-- revoke de public, anon e authenticated; execute só para service_role.
--
-- ORDEM DE LIGAR: depois de 20261024160000 e 160100.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase1_base.sql (com a fixture, os números acima; em produção,
-- reaplicar não muda nada). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261024160200
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261024160200_agenda_fase1_semente_funcao.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024160200', 'agenda_fase1_semente_funcao');"
--
-- IDEMPOTENTE: create or replace function; revoke/grant repetidos não mudam nada.

create or replace function public.agenda_disponibilidade_semear(p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  c            public.agenda_config := public._agenda_cfg();
  v_ultima     date;
  v_ini        date;
  v_novas      jsonb;
  v_inseridas  int := 0;
  v_trocadas   int := 0;
  v_mantidas   int := 0;
  v_n          int;
  r            record;
begin
  if p_hoje is null then
    raise exception 'agenda_disponibilidade_semear: sem o dia de hoje' using errcode = '22004';
  end if;

  select max(ws.data) into v_ultima
    from public.work_shifts ws
   where ws.tipo = 'diaria' and ws.fracao > 0 and ws.data <= p_hoje;
  if v_ultima is null then
    return jsonb_build_object('semeadas', 0, 'substituidas', 0, 'mantidas', 0, 'motivo', 'sem diárias');
  end if;

  -- Segunda da 1ª semana da janela.
  v_ini := v_ultima - (extract(isodow from v_ultima)::int - 1) - 7 * (c.medicao_semanas - 1);

  with turnos as (        -- por pessoa e dia: as meias do mesmo dia somam, teto 1
    select w.payee_id, ws.data, least(sum(ws.fracao), 1) as fracao
      from public.work_shifts ws
      join public.work_profiles w on w.id = ws.work_profile_id
     where w.payee_id is not null and ws.tipo = 'diaria' and ws.fracao > 0
       and ws.data between v_ini and v_ultima
     group by 1, 2),
  equipe as (             -- quem trabalhou nos últimos equipe_recente_dias e tem cadastro de diarista vigente
    select t.payee_id, min(t.data) as primeira
      from turnos t
      join public.payees p on p.id = t.payee_id
     where p.active and p.kind in ('prestador', 'diarista', 'funcionario')
       and exists (select 1 from public.work_profiles w
                    where w.payee_id = p.id and w.vigencia_inicio <= p_hoje
                      and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje))
     group by t.payee_id
    having max(t.data) >= v_ultima - (c.equipe_recente_dias - 1)),
  dias as (
    select e.payee_id, e.primeira + g.i as dia
      from equipe e
      cross join lateral generate_series(0, v_ultima - e.primeira) g(i)),
  contagem as (           -- conta o dia útil e o feriado trabalhado; sábado e domingo fora
    select d.payee_id, extract(isodow from d.dia)::int as dow,
           count(*) filter (where t.fracao is not null or public.agenda_dia_util(d.dia)) as dias_contados,
           coalesce(sum(t.fracao), 0) as soma
      from dias d
      left join turnos t on t.payee_id = d.payee_id and t.data = d.dia
     where extract(isodow from d.dia) between 1 and 5
     group by 1, 2)
  select coalesce(jsonb_agg(jsonb_build_object(
           'payee_id', payee_id, 'dow', dow, 'soma', soma, 'dias', dias_contados,
           'frequencia', round(soma / dias_contados, 4)) order by payee_id, dow), '[]'::jsonb)
    into v_novas
    from contagem
   where dias_contados > 0 and soma / dias_contados >= c.frequencia_minima;

  for r in
    with novas as (
      select (x->>'payee_id')::uuid as payee_id,
             jsonb_agg(jsonb_build_object('dow', (x->>'dow')::int, 'frequencia', (x->>'frequencia')::numeric(5,4))
                       order by (x->>'dow')::int) as linhas
        from jsonb_array_elements(v_novas) x
       group by 1),
    vigentes as (
      select d.payee_id,
             jsonb_agg(jsonb_build_object('dow', d.dias_semana[1]::int, 'frequencia', d.frequencia)
                       order by d.dias_semana[1], d.criado_em, d.id) as linhas
        from public.agenda_disponibilidade d
       where d.origem = 'historico' and d.substituida_em is null and d.payee_id is not null
       group by 1)
    select coalesce(n.payee_id, v.payee_id) as payee_id, n.linhas as novas, v.linhas as vigentes
      from novas n
      full join vigentes v on v.payee_id = n.payee_id
  loop
    if r.novas is not distinct from r.vigentes then
      v_mantidas := v_mantidas + 1;
      continue;
    end if;
    update public.agenda_disponibilidade
       set substituida_em = now()
     where payee_id = r.payee_id and origem = 'historico' and substituida_em is null;
    get diagnostics v_n = row_count;
    v_trocadas := v_trocadas + v_n;
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, frequencia, nota)
    select r.payee_id, array[(x->>'dow')::smallint], null, 'disponivel', 'historico',
           (x->>'frequencia')::numeric(5,4),
           format('semente: %s de %s %s (%s semanas até %s)',
                  replace(trim_scale((x->>'soma')::numeric)::text, '.', ','),
                  x->>'dias',
                  (array['segunda','terça','quarta','quinta','sexta'])[(x->>'dow')::int]
                    || case when (x->>'dias')::int > 1 then 's' else '' end,
                  c.medicao_semanas,
                  to_char(v_ultima, 'DD/MM'))
      from jsonb_array_elements(v_novas) x
     where (x->>'payee_id')::uuid = r.payee_id
     order by (x->>'dow')::int;
    get diagnostics v_n = row_count;
    v_inseridas := v_inseridas + v_n;
  end loop;

  return jsonb_build_object(
    'semeadas', v_inseridas,
    'substituidas', v_trocadas,
    'mantidas', v_mantidas,
    'ultima_diaria', v_ultima,
    'janela', jsonb_build_object('de', v_ini, 'ate', v_ultima),
    'linhas', v_novas);
end;
$function$;

comment on function public.agenda_disponibilidade_semear(date) is
  'Semeia agenda_disponibilidade (origem historico) pelas diárias das últimas agenda_config.medicao_semanas semanas até a última diária lançada: uma linha por pessoa da equipe recente e dia ISO 1..5 com frequência >= frequencia_minima. Idempotente; nunca toca linhas do dono, do diarista nem do agente. Só service_role.';

revoke all on function public.agenda_disponibilidade_semear(date) from public, anon, authenticated;
grant execute on function public.agenda_disponibilidade_semear(date) to service_role;
