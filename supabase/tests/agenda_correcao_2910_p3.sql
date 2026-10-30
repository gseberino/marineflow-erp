-- Prova da correção de 29/10 da Agenda de Produção, pacote P3 (migration 20261030100200): o motor.
-- bancada: depende de 20261030100200
--
-- Os defeitos (auditoria de 29/10):
--   (a) a reserva do Lenine nunca viraria compromisso: no encaixe, a própria reserva ocupava o teto de 100% da semana do João
--       (4 de 4 meios-dias), e a promoção dava "sem encaixe";
--   (b) o resumo da publicação dizia "1 serviço marcado" quando era só a reserva;
--   (c) as perguntas feitas em teste (modo sombra) ficavam abertas quando o modo virava ligado, e a lista parecia ter a mesma
--       pergunta duas vezes;
--   (d) "quais dias você fica em campo?" nunca nascia: o dono sem nenhuma disponibilidade, e a OS que precisava dele saía
--       antes por outro motivo.
--
-- O cenário de HOJE é a fixture-2310.sql que a bancada sempre carrega (a carteira de 23/10, sem nenhuma resposta do dono, a
-- equipe pela semente das diárias: o João com teto de 3 meios-dias de compromisso e 4 com a reserva por semana, o dono sem os
-- dias em campo) com os modos ligados e a vigia de qui 29/10 às 16:30: ela publica o que produção publicou (só a reserva do
-- Lenine, 12 meios-dias, João e Roberto, 2 pessoas por meio-dia). Por cima dela:
--   H  hoje: o resumo e o título da semana ("1 reservado (Lenine), nada marcado firme, 10 de fora"), o "Publiquei a semana de
--      …" da aplicação, do *o que mudou* e do fechamento; a pergunta dos seus dias em campo nasce UMA vez, não crítica, com
--      a validade, e não volta depois de vencer
--   R  a promoção: o dono responde a peça e os dias do Lenine (classe 2) → com o encaixe de ANTES, sem encaixe (o defeito);
--      com a correção, a vigia promove a reserva a compromisso (qui 05, sex 06 de manhã, ter 10 e qua 11 de manhã, João e
--      Roberto; você abre e fecha), a reserva sai como promovida e os tetos do João ficam em 3 de 3; a reserva de OUTRA OS
--      continua contando (1 meio-dia do João na semana de 09/11: cabe; 2: não cabe); a OS nova de 1 dia com o João não pega o
--      João na semana da reserva do Lenine
--   S  as perguntas de teste: a aberta em sombra cujo modo está ligado fecha como resolvida (o motivo claro), a ligada de
--      mesma chave fica; a de um modo ainda em sombra fica; o modo de cada um dos tipos da lista fechada
--   D  a pergunta dos seus dias em campo: com o seu padrão, nada; com uma exceção disponível, nada; sem OS que precise de você,
--      nada; feita em teste e depois ligada (a de teste fecha, a de verdade nasce)
--   N  o que NÃO muda: sem reserva no que entra, a agenda_propor é a de antes, byte a byte (a definição de antes rodada como
--      pg_temp); com reserva, só o resumo, o título e o texto mudam; fora de ligado, nada muda
-- Sempre (com ou sem as fixtures):
--   K  as cópias: as 4 recriadas só acrescentam os blocos "-- CORREÇÃO 29/10 (P3):" (× a migration de onde cada uma veio)
--   P  portas: a nova só o service_role; o motor só o service_role; as peças da vigia, ninguém de fora
--   C  o parâmetro novo: 7 dias na linha; o CHECK recusa 0 e 31 dias e aceita 30
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_correcao_2910_p3.sql
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
create function pg_temp.vigiar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_vigiar(p_dia, (p_dia + p_hora::time) at time zone 'America/Sao_Paulo')
$f$;
create function pg_temp.agora(p_dia date, p_hora text) returns void language sql as $f$
  select set_config('agenda.agora', ((p_dia + p_hora::time) at time zone 'America/Sao_Paulo')::text, true)
$f$;
-- O dono responde a peça (não tem nada a comprar) e os dias (3) do Lenine: a OS passa à classe 2.
create function pg_temp.lenine_respondido() returns void language sql as $f$
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, material_conferido_em, trecho, atualizado_por)
  values ('05000000-0000-4000-8000-000000000074', 3, 'dono', timestamptz '2026-10-29 17:00-03', timestamptz '2026-10-29 17:00-03',
          'não tem peça a comprar, leva 3 dias', 'aa000000-0000-4000-8000-000000000001')
  on conflict (service_order_id) do update
    set dias = excluded.dias, estimativa_fonte = excluded.estimativa_fonte, estimativa_em = excluded.estimativa_em,
        material_conferido_em = excluded.material_conferido_em
$f$;
-- O encaixe do Lenine pela agenda_propor (escopo 'os', sem gravar), como a vigia pede a promoção: "dia pessoa turno, …" do
-- que entra (só os turnos) e o motivo de fora.
create function pg_temp.lenine_sim() returns text language sql as $f$
  select coalesce((select string_agg(format('%s %s %s', a ->> 'dia', a ->> 'nome', a ->> 'turno'), ', '
                                     order by a ->> 'dia', a ->> 'turno', a ->> 'nome')
                     from jsonb_array_elements(r -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
                    where i ->> 'op' = 'criar' and a ->> 'presenca' = 'turno'), '-')
         || ' | fora: ' || coalesce((select string_agg(f ->> 'motivo', ', ') from jsonb_array_elements(r -> 'fora') f), '-')
    from (select public.agenda_propor('os', null, null, array['05000000-0000-4000-8000-000000000074'::uuid], '{}'::jsonb, false,
                                      'motor', null, date '2026-10-29', timestamptz '2026-10-29 17:10-03') as r) x
$f$;
-- Uma pergunta como a agenda grava (para o cenário das perguntas de teste).
create function pg_temp.pergunta(p_tipo text, p_chave text, p_modo text, p_em timestamptz) returns uuid language sql as $f$
  insert into public.agenda_perguntas (tipo, chave, texto, modo, criada_em)
  values (p_tipo, p_chave, 'Pergunta de ' || p_tipo || ' (' || p_modo || ').', p_modo, p_em)
  returning id
$f$;
-- Uma consulta como um papel: o texto que volta ou "erro <sqlstate>: <mensagem>".
create function pg_temp.como(p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  return v;
end $f$;

-- O corpo (entre as duas marcas $…$) e a função inteira (do "create or replace" ao fecho) de p_nome na migration p_mig.
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
-- As linhas fora dos blocos "-- CORREÇÃO 29/10 (P3): … -- CORREÇÃO 29/10 (P3): fim".
create function pg_temp.sem_blocos(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and ltrim(l) like '-- CORREÇÃO 29/10 (P3):%' and ltrim(l) not like '-- CORREÇÃO 29/10 (P3): fim%' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro then
      if ltrim(l) like '-- CORREÇÃO 29/10 (P3): fim%' then v_dentro := false; end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;

-- A definição de ANTES de agenda_propor (20261029100900), rodada como pg_temp: a régua do que não muda. Ela chama o
-- _agenda_encaixar de agora, que sem res_propria (a de antes não passa) é o de antes.
do $antes$
declare
  v_c6 text := coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '');
begin
  if v_c6 = '' then return; end if;
  execute replace(pg_temp.inteira(v_c6, 'agenda_propor'), 'create or replace function public.agenda_propor(',
                  'create function pg_temp.propor_antes(');
end
$antes$;

-- ── Os cenários ─────────────────────────────────────────────────────────────────────────────────────────
do $cenarios$
declare
  v_fix   boolean := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '') <> ''
                     and coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '') <> ''
                     and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000003')
                     and exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000074');
  c_hoje   constant date := date '2026-10-29';
  c_admin  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_dono   constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_joao   constant uuid := 'bb000000-0000-4000-8000-000000000003';
  c_lenine constant uuid := '05000000-0000-4000-8000-000000000074';
  c_titulo constant text := 'Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme';
  c_reserva constant text := 'Reserva Lenine (OS-00074): qui 05 a ter 10/11, João os 3 dias, Roberto os 3 dias — se você disser até qua 04/11 se tem peça a comprar.';
  c_pergunta constant text := 'Não sei em que dias você fica em campo, e Rodrigo (OS-00096), Robson (ORÇ-00083), MP (ORÇ-00095) e mais 8 '
                              || 'precisam de você. Quais dias da semana você vai? Por exemplo: "fico em campo de segunda a sexta".';
  c_motivo constant text := 'era do teste: com a agenda ligada, vale só a pergunta de verdade';
  c_promovido constant text := '2026-11-05 João manha, 2026-11-05 Roberto manha, 2026-11-05 João tarde, 2026-11-05 Roberto tarde, '
                               || '2026-11-06 João manha, 2026-11-06 Roberto manha, 2026-11-10 João manha, 2026-11-10 Roberto manha, '
                               || '2026-11-10 João tarde, 2026-11-10 Roberto tarde, 2026-11-11 João manha, 2026-11-11 Roberto manha | fora: -';
  v_res   jsonb := '[]'::jsonb;
  r       jsonb;
  x       jsonb;
  v_t     text;
  v_t2    text;
  v_x1    text;
  v_x2    text;
  v_id    uuid;
  v_q     record;
  v_ids   uuid[];
  v_os    uuid;
begin
  if not v_fix then
    insert into _resultado values ('H–N cenários da correção P3', true,
      'PULADO: sem as fixtures (fixture-2310, mig_motor_fase2 e mig_correcao_calculo_fase6): rode pela bancada');
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);

  -- ── H. Hoje: a vigia de qui 29/10 às 16:30 com tudo ligado ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(c_hoje, '16:30');
    perform pg_temp.agora(c_hoje, '17:40');
    v_res := pg_temp.igual(v_res, 'H0 a vigia publica o que produção publicou: só a reserva do Lenine (12 meios-dias, João e Roberto)',
      (select count(*) filter (where a.tipo = 'reserva' and a.service_order_id = c_lenine)::text || '/' || count(*)::text
         from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada')), '12/12');
    select p.textos into x from public.agenda_propostas p where p.escopo = 'semana' and p.estado = 'aplicada';
    v_res := pg_temp.igual(v_res, 'H1 (b) o resumo separa o reservado do marcado: "1 reservado (Lenine), nada marcado firme, 10 de fora" (era "1 serviço marcado")',
      x ->> 'resumo', 'Semana de 03 a 06/11 (seg 02 é Finados): 1 reservado (Lenine), nada marcado firme, 10 de fora.');
    v_res := pg_temp.igual(v_res, 'H2 (b) o título da semana diz quantos: "— 1 reservado, nada marcado firme"', x ->> 'titulo', c_titulo);
    v_res := pg_temp.igual(v_res, 'H3 (b) a aplicação: "Publiquei a semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme: Reserva Lenine …"',
      r #>> '{contagens,publicacao,texto}',
      'Publiquei a s' || substr(c_titulo, 2) || ': ' || c_reserva || ' *desfaz semana* volta como estava.');
    v_t := public.agenda_ver(c_admin, null, null, 'mudancas', null, null, false, c_hoje) ->> 'texto';
    v_res := pg_temp.igual(v_res, 'H4 (b) *o que mudou*: a mesma linha, com o título que diz que nada está marcado firme',
      v_t, 'O que mudei sozinho na agenda desde ontem:' || E'\n' || '• Publiquei a s' || substr(c_titulo, 2) || ': ' || c_reserva
           || ' *desfaz semana* volta como estava.');
    v_t := (select y ->> 'texto' from jsonb_array_elements(public.agenda_textos_do_fechamento(c_hoje, null) -> 'linhas') y
             where y ->> 'tipo' = 'semana');
    v_res := pg_temp.ok(v_res, 'H5 (b) o fechamento das 17:30: "Agenda: publiquei a semana de … — 1 reservado, nada marcado firme: reserva para Lenine …"',
      v_t like 'Agenda: publiquei a s' || substr(c_titulo, 2) || ': reserva para Lenine (%', v_t);
    -- (d) a pergunta dos seus dias em campo nasce UMA vez
    select q.* into v_q from public.agenda_perguntas q where q.tipo = 'padrao_do_dono';
    v_res := pg_temp.igual(v_res, 'H6 (d) sem nenhuma disponibilidade sua e com 11 OS que precisam de você, a vigia pergunta os seus dias em campo (a que precisa de você o tempo todo primeiro)',
      v_q.texto, c_pergunta);
    v_res := pg_temp.ok(v_res, 'H7 (d) uma vez (padrao_do_dono:sem_dias), ligada, não crítica, com as 11 OS e a validade de 7 dias (padrao_do_dono_validade)',
      v_q.chave = 'padrao_do_dono:sem_dias' and v_q.modo = 'ligado' and not v_q.critica and v_q.estado = 'aberta'
      and cardinality(v_q.os_ids) = 11 and cardinality(v_q.os_ids) = (select count(*) from public.os_carteira(c_hoje))
      and v_q.expira_em = timestamptz '2026-11-05 16:30-03'
      and (r #>> '{contagens,padrao_do_dono,criada}')::boolean and r #>> '{contagens,padrao_do_dono,motivo}' = 'sem os seus dias em campo',
      to_jsonb(v_q)::text);
    r := pg_temp.vigiar(c_hoje, '16:45');
    v_res := pg_temp.ok(v_res, 'H8 (d) a vigia seguinte não pergunta de novo ("já perguntei")',
      (select count(*) from public.agenda_perguntas where tipo = 'padrao_do_dono') = 1
      and r #>> '{contagens,padrao_do_dono,motivo}' = 'já perguntei os seus dias em campo', (r -> 'contagens' -> 'padrao_do_dono')::text);
    r := pg_temp.vigiar(date '2026-11-06', '09:00');
    v_res := pg_temp.ok(v_res, 'H9 (d) sem resposta, ela vence (sex 06/11) e não volta',
      (select count(*) from public.agenda_perguntas where tipo = 'padrao_do_dono') = 1
      and (select estado from public.agenda_perguntas where chave = 'padrao_do_dono:sem_dias') = 'vencida'
      and not (r #>> '{contagens,padrao_do_dono,criada}')::boolean, (r -> 'contagens' -> 'padrao_do_dono')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── R. A promoção da reserva (o João com 3 de compromisso e 4 com a reserva na semana; 2 pessoas por meio-dia) ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(c_hoje, '16:30');
    perform pg_temp.lenine_respondido();
    v_res := pg_temp.ok(v_res, 'R1 o dono respondeu a peça e os dias: o Lenine é classe 2 (pronto, sem condição), e a reserva continua lá',
      (public._agenda_classe_agora(c_lenine, c_hoje) ->> 'classe')::int = 2
      and (select count(*) from public.agenda_alocacoes where service_order_id = c_lenine and tipo = 'reserva' and estado = 'publicada') = 12,
      public._agenda_classe_agora(c_lenine, c_hoje) ->> 'classe');
    -- o encaixe de ANTES (a migration do motor da Fase 2) no lugar, numa subtransação desfeita: o defeito
    v_t := null;
    begin
      execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase2'), '_agenda_encaixar');
      v_t := pg_temp.lenine_sim();
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_res := pg_temp.igual(v_res, 'R2 (a) com o encaixe de antes, a promoção não cabe: a própria reserva ocupa o teto de 100% do João (o defeito)',
      v_t, '- | fora: sem_encaixe');
    v_res := pg_temp.igual(v_res, 'R3 (a) com a correção, cabe: qui 05, sex 06 de manhã, ter 10 e qua 11 de manhã, João e Roberto (2 por meio-dia)',
      pg_temp.lenine_sim(), c_promovido);
    -- a vigia promove de verdade
    r := pg_temp.vigiar(c_hoje, '17:15');
    v_res := pg_temp.igual(v_res, 'R4 (a) a vigia das 17:15 promove a reserva: o compromisso no lugar, você abre e fecha, *desfaz Lenine*',
      r #>> '{contagens,reservas,texto}',
      'Mudei: Lenine (OS-00074): qui 05, sex 06, ter 10 e qua 11/11, você abre e fecha, João os 4 dias, Roberto os 4 dias; '
      || 'Lenine (OS-00074): a reserva vira compromisso. *desfaz Lenine* volta como estava.');
    v_res := pg_temp.ok(v_res, 'R5 (a) as 12 alocações da reserva saem como promovidas; 12 turnos de compromisso + a abertura e o fechamento; uma ação promover_reserva; a OS agendada',
      (select count(*) from public.agenda_alocacoes where service_order_id = c_lenine and tipo = 'reserva'
          and estado = 'cancelada' and cancelada_motivo = 'promovida') = 12
      and (select count(*) from public.agenda_alocacoes where service_order_id = c_lenine and tipo <> 'reserva' and estado in ('publicada', 'fixada')
             and presenca = 'turno') = 12
      and (select string_agg(a.dia || ' ' || a.presenca, ', ' order by a.dia) from public.agenda_alocacoes a
            where a.service_order_id = c_lenine and a.payee_id = c_dono and a.estado in ('publicada', 'fixada'))
          = '2026-11-05 abertura, 2026-11-11 fechamento'
      and (select count(*) from public.agenda_acoes where service_order_id = c_lenine and tipo = 'promover_reserva' and executada) = 1
      and (select status from public.service_orders where id = c_lenine) = 'scheduled'
      and (r #>> '{contagens,reservas,promovidas}')::int = 1, (r -> 'contagens' -> 'reservas')::text);
    v_res := pg_temp.igual(v_res, 'R6 (a) o João fica no teto de compromisso nas duas semanas (3 de 3), sem reserva sobrando',
      (select string_agg(format('%s:%s', w, n), ' ' order by w)
         from (select to_char(a.dia - (extract(isodow from a.dia)::int - 1), 'DD/MM') as w, count(*) as n
                 from public.agenda_alocacoes a
                where a.payee_id = c_joao and a.estado in ('publicada', 'fixada') and a.presenca = 'turno'
                group by 1) s)
      || ' | reservas vigentes: ' || (select count(*) from public.agenda_alocacoes where tipo = 'reserva' and estado in ('publicada', 'fixada'))::text,
      '02/11:3 09/11:3 | reservas vigentes: 0');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- a reserva de OUTRA OS continua contando (o Vanderlei com a reserva de 1 e depois 2 meios-dias do João na semana de 09/11)
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(c_hoje, '16:30');
    perform pg_temp.lenine_respondido();
    v_os := (select id from public.service_orders where service_order_number = 'OS-00069');
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, reserva_de, publicada_em)
    values (v_os, c_joao, date '2026-11-12', 'manha', 'turno', 'reserva', 'publicada', 'motor', 'teto', now());
    v_x1 := pg_temp.lenine_sim();
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, reserva_de, publicada_em)
    values (v_os, c_joao, date '2026-11-12', 'tarde', 'turno', 'reserva', 'publicada', 'motor', 'teto', now());
    v_x2 := pg_temp.lenine_sim();
    v_res := pg_temp.igual(v_res, 'R7 (a) com a reserva de outra OS em 1 meio-dia do João na semana de 09/11 (4 − 1 = 3 de lugar), a promoção ainda cabe',
      v_x1, c_promovido);
    v_res := pg_temp.igual(v_res, 'R8 (a) com 2 meios-dias (4 − 2 = 2, e o Lenine precisa de 3 do João nessa semana), não cabe: a reserva da outra conta',
      v_x2, '- | fora: sem_encaixe');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- a reserva do Lenine conta para as outras OS: um serviço de 1 dia com o João não pega o João na semana dela
  begin
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(c_hoje, '16:30');
    insert into public.clients (id, type, name) values ('c4000000-0000-4000-8000-000000000903', 'individual', 'Daniel');
    insert into public.vessels (id, client_id, name, asset_type)
    values ('f4000000-0000-4000-8000-000000000903', 'c4000000-0000-4000-8000-000000000903', 'Lancha D', 'Lancha');
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                       created_at, updated_at, converted_to_os_at, grand_total)
    values ('05000000-0000-4000-8000-000000000903', 'OS-00903', 'c4000000-0000-4000-8000-000000000903', 'f4000000-0000-4000-8000-000000000903',
            'approved', 'approved', 'repair', timestamptz '2026-10-28 12:00-03', timestamptz '2026-10-28 12:00-03',
            timestamptz '2026-10-28 12:00-03', 1000);
    insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                               unit_price_snapshot, line_total, created_at)
    values (md5('p3:servico:903')::uuid, '05000000-0000-4000-8000-000000000903', '5e000000-0000-4000-8000-000000000003',
            'Revisão do sistema elétrico', 'unit', 1, 1000, 1000, timestamptz '2026-10-28 12:00-03');
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em,
                                        trecho, atualizado_por)
    values ('05000000-0000-4000-8000-000000000903', 1, 'dono', timestamptz '2026-10-28 18:00-03', 'abre_e_fecha',
            timestamptz '2026-10-28 18:00-03', 'um dia com o João, eu abro e fecho', c_admin);
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos)
    values ('05000000-0000-4000-8000-000000000903', c_joao, 'dia');
    r := public.agenda_propor('os', null, null, array['05000000-0000-4000-8000-000000000903'::uuid], '{}'::jsonb, false, 'motor', null,
                              c_hoje, (c_hoje + time '17:40') at time zone 'America/Sao_Paulo');
    v_res := pg_temp.igual(v_res, 'R9 (a) a reserva do Lenine conta para outra OS: 1 dia com o João vai para ter 03/11 com o Roberto (a semana do João está na reserva)',
      (select string_agg(format('%s %s %s', a ->> 'dia', a ->> 'nome', a ->> 'turno'), ', ' order by a ->> 'dia', a ->> 'turno', a ->> 'nome')
         from jsonb_array_elements(r -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
        where i ->> 'op' = 'criar' and a ->> 'presenca' = 'turno'),
      '2026-11-03 Roberto manha, 2026-11-03 Roberto tarde');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── S. As perguntas de teste (modo sombra) ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    update public.agenda_config set modo_material = 'ligado', modo_cliente = 'sombra' where id;
    -- o que produção tinha às 17:10 de 29/10: as duas de material de 28/10 em teste (17:45) e de novo ligadas (20:15)
    v_ids := array[
      pg_temp.pergunta('fornecedor_cadastro', 'fornecedor_cadastro:695df7dd-7588-4f91-a89c-b468dcbc342a', 'sombra', timestamptz '2026-10-28 17:45-03'),
      pg_temp.pergunta('fornecedores_prazo', 'fornecedores_prazo', 'sombra', timestamptz '2026-10-28 17:45-03'),
      pg_temp.pergunta('fornecedor_cadastro', 'fornecedor_cadastro:695df7dd-7588-4f91-a89c-b468dcbc342a', 'ligado', timestamptz '2026-10-28 20:15-03'),
      pg_temp.pergunta('fornecedores_prazo', 'fornecedores_prazo', 'ligado', timestamptz '2026-10-28 20:15-03'),
      -- o chegou? que a conversa do fornecedor abre é do material (ligado); a do cliente em teste continua em teste
      pg_temp.pergunta('chegou', 'chegou:fornecedor:695df7dd-7588-4f91-a89c-b468dcbc342b:2026-10-30', 'sombra', timestamptz '2026-10-28 17:45-03'),
      pg_temp.pergunta('cliente_resposta', 'cliente_resposta:p3-teste', 'sombra', timestamptz '2026-10-28 17:45-03')];
    r := pg_temp.vigiar(c_hoje, '10:00');
    v_res := pg_temp.igual(v_res, 'S1 (c) as de teste cujo modo está ligado fecham como resolvidas, com o motivo; as ligadas ficam; a do cliente (ainda em teste) fica',
      (select string_agg(format('%s %s %s %s', q.tipo, q.modo, q.estado, coalesce(q.resolvida_motivo, '-')), ' | ' order by k)
         from unnest(v_ids) with ordinality u(id, k) join public.agenda_perguntas q on q.id = u.id),
      'fornecedor_cadastro sombra resolvida ' || c_motivo || ' | fornecedores_prazo sombra resolvida ' || c_motivo
      || ' | fornecedor_cadastro ligado aberta - | fornecedores_prazo ligado aberta -'
      || ' | chegou sombra resolvida ' || c_motivo || ' | cliente_resposta sombra aberta -');
    v_res := pg_temp.ok(v_res, 'S2 (c) a lista para de parecer duplicada: uma aberta por chave; a limpeza conta as 3 em resolvidas',
      not exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' group by q.chave having count(*) > 1)
      and (r #>> '{contagens,limpeza,resolvidas}')::int >= 3, (r -> 'contagens' -> 'limpeza')::text);
    -- com o material de volta em teste, a de teste nova fica aberta
    update public.agenda_config set modo_material = 'sombra' where id;
    v_id := pg_temp.pergunta('fornecedores_prazo', 'fornecedores_prazo', 'sombra', timestamptz '2026-10-29 10:05-03');
    r := pg_temp.vigiar(c_hoje, '10:15');
    v_res := pg_temp.ok(v_res, 'S3 (c) com o modo do material em teste, a pergunta de teste não fecha',
      (select estado from public.agenda_perguntas where id = v_id) = 'aberta', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- o modo de cada tipo da lista fechada (um tipo novo sem modo reprova aqui)
  select string_agg(t, ', ' order by t) into v_t
    from (select unnest(regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g')) as t
            from pg_constraint c where c.conname = 'agenda_perguntas_tipo_check') x
   where public._agenda_modo_da_pergunta(x.t, x.t || ':x') is null;
  v_res := pg_temp.ok(v_res, 'S4 (c) todo tipo de pergunta da lista fechada (26) tem o modo de quem a faz',
    v_t is null and (select count(*) from (select unnest(regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g'))
                                             from pg_constraint c where c.conname = 'agenda_perguntas_tipo_check') y) = 26, v_t);
  v_res := pg_temp.igual(v_res, 'S5 (c) o modo de cada grupo: crítica do plano, vigia, chegou? do fornecedor, material, diária, equipe, cliente, aprendizado',
    (select string_agg(public._agenda_modo_da_pergunta(t, c), ',' order by o)
       from unnest(array['nao_cabe', 'material_conferir', 'chegou', 'chegou', 'fornecedores_prazo', 'diaria', 'concluir', 'cliente_aviso', 'aprendizado'],
                   array['x', 'x', 'chegou:abc:2026-10-30', 'chegou:fornecedor:abc:2026-10-30', 'x', 'x', 'x', 'x', 'x'])
            with ordinality u(t, c, o)),
    (select concat_ws(',', modo_proposta, modo_vigia, modo_vigia, modo_material, modo_material, modo_diaria, modo_equipe, modo_cliente, modo_aprendizado)
       from public.agenda_config where id));

  -- ── D. A pergunta dos seus dias em campo ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, trecho)
    values (c_dono, '{1,2,3,4,5}', 'disponivel', 'dono', 'fico em campo de segunda a sexta');
    r := pg_temp.vigiar(c_hoje, '10:00');
    v_res := pg_temp.ok(v_res, 'D1 (d) com o seu padrão de dias, nenhuma pergunta ("você tem padrão")',
      r #>> '{contagens,padrao_do_dono,motivo}' = 'você tem padrão' and not exists (select 1 from public.agenda_perguntas where tipo = 'padrao_do_dono'),
      (r -> 'contagens' -> 'padrao_do_dono')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, trecho)
    values (c_dono, daterange(date '2026-11-05', date '2026-11-06', '[]'), 'disponivel', 'dono', 'quinta e sexta eu vou');
    r := pg_temp.vigiar(c_hoje, '10:00');
    v_res := pg_temp.ok(v_res, 'D2 (d) com um dia seu em campo dito (uma exceção disponível), nenhuma pergunta nova',
      r #>> '{contagens,padrao_do_dono,motivo}' = 'nada ficou fora por isso' and not exists (select 1 from public.agenda_perguntas where tipo = 'padrao_do_dono'),
      (r -> 'contagens' -> 'padrao_do_dono')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    insert into public.os_planejamento (service_order_id, dono_presenca)
    select k.service_order_id, 'nunca' from public.os_carteira(c_hoje) k
    on conflict (service_order_id) do update set dono_presenca = 'nunca';
    r := pg_temp.vigiar(c_hoje, '10:00');
    v_res := pg_temp.ok(v_res, 'D3 (d) sem nenhuma OS que precise de você (todas "sem você"), nenhuma pergunta',
      r #>> '{contagens,padrao_do_dono,motivo}' = 'nada ficou fora por isso' and not exists (select 1 from public.agenda_perguntas where tipo = 'padrao_do_dono'),
      (r -> 'contagens' -> 'padrao_do_dono')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- feita em teste; depois de ligar, a de teste fecha e a de verdade nasce (uma vez em cada modo)
    perform pg_temp.modos('sombra', 'sombra');
    r := pg_temp.vigiar(c_hoje, '10:00');
    v_t := (select string_agg(modo || ' ' || estado, ', ' order by criada_em) from public.agenda_perguntas where tipo = 'padrao_do_dono');
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(c_hoje, '10:15');
    v_t2 := (select string_agg(modo || ' ' || estado || coalesce(' (' || resolvida_motivo || ')', ''), ', ' order by criada_em)
               from public.agenda_perguntas where tipo = 'padrao_do_dono');
    v_res := pg_temp.igual(v_res, 'D4 (c, d) em teste a pergunta nasce em teste; ligada, a de teste fecha e a de verdade nasce',
      v_t || ' → ' || v_t2, 'sombra aberta → sombra resolvida (' || c_motivo || '), ligado aberta');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── N. O que NÃO muda ──
  begin
    perform pg_temp.modos('ligado', 'ligado');
    -- sem reserva no que entra (o Lenine e o Giancarlo, que ficaria com a vaga da reserva, tirados): a agenda_propor é a de
    -- antes, byte a byte
    x := jsonb_build_object('tirar', jsonb_build_array(c_lenine, (select id from public.service_orders where service_order_number = 'OS-00100')));
    r := public.agenda_propor('semana', null, null, null, x, false, 'motor', null, c_hoje, (c_hoje + time '16:00') at time zone 'America/Sao_Paulo');
    x := pg_temp.propor_antes('semana', null, null, null, x, false, 'motor', null, c_hoje, (c_hoje + time '16:00') at time zone 'America/Sao_Paulo');
    v_res := pg_temp.ok(v_res, 'N1 sem reserva no que entra, a semana é a de antes, byte a byte (o resumo "N serviços marcados" de sempre)',
      r = x and not exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'tipo' = 'reserva'),
      md5(r::text) || ' × ' || md5(x::text) || ' | ' || (r #>> '{textos,resumo}'));
    -- com a reserva do Lenine: só o resumo, o título e o texto mudam (o encaixe, as reservas, o que fica de fora e a carga, iguais)
    r := public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, c_hoje,
                              (c_hoje + time '16:00') at time zone 'America/Sao_Paulo');
    x := pg_temp.propor_antes('semana', null, null, null, '{}'::jsonb, false, 'motor', null, c_hoje,
                              (c_hoje + time '16:00') at time zone 'America/Sao_Paulo');
    v_res := pg_temp.ok(v_res, 'N2 com reserva, só o resumo, o título e o texto mudam; o de antes dizia "1 serviço marcado"',
      (r - 'texto') #- '{textos,resumo}' #- '{textos,titulo}' = (x - 'texto') #- '{textos,resumo}' #- '{textos,titulo}'
      and x #>> '{textos,resumo}' = 'Semana de 03 a 06/11 (seg 02 é Finados): 1 serviço marcado, 10 de fora.'
      and r #>> '{textos,titulo}' = c_titulo
      and r ->> 'texto' = replace(x ->> 'texto', 'Semana de 03 a 06/11 (seg 02 é Finados)' || E'\n', c_titulo || E'\n'),
      (r -> 'textos')::text);
    -- fora de ligado: a semana (com a reserva do Lenine que entra) é a de antes, byte a byte
    perform pg_temp.modos('sombra', 'sombra');
    r := public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, c_hoje,
                              (c_hoje + time '16:00') at time zone 'America/Sao_Paulo');
    x := pg_temp.propor_antes('semana', null, null, null, '{}'::jsonb, false, 'motor', null, c_hoje,
                              (c_hoje + time '16:00') at time zone 'America/Sao_Paulo');
    v_res := pg_temp.ok(v_res, 'N3 em teste (sombra), a semana com a reserva é a de antes, byte a byte (o resumo e o título só mudam em ligado)',
      r = x and exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'tipo' = 'reserva'),
      md5(r::text) || ' × ' || md5(x::text));
    -- a promoção (escopo os): o título continua "Mudanças na agenda" e o resumo é o de antes (nada reservado entra)
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(c_hoje, '16:30');
    perform pg_temp.lenine_respondido();
    r := public.agenda_propor('os', null, null, array[c_lenine], '{}'::jsonb, false, 'motor', null, c_hoje, timestamptz '2026-10-29 17:10-03');
    v_res := pg_temp.ok(v_res, 'N4 a promoção (escopo os, o que entra é compromisso): título e resumo os de antes ("Mudanças na agenda: 1 serviço marcado, 0 de fora.")',
      r #>> '{textos,titulo}' = 'Mudanças na agenda' and r #>> '{textos,resumo}' = 'Mudanças na agenda: 1 serviço marcado, 0 de fora.',
      (r -> 'textos')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$cenarios$;

-- ── K. As cópias ─────────────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  v_m2 text := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '');
  v_c2 text := coalesce(current_setting('agenda_teste.mig_conferencia_fase2', true), '');
  v_d4 text := coalesce(current_setting('agenda_teste.mig_detector_fase4', true), '');
  v_c6 text := coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '');
  f record;
  v_fonte text;
  v_novo text;
begin
  if v_m2 = '' or v_c2 = '' or v_d4 = '' or v_c6 = '' then
    insert into _resultado values ('K0 as cópias só acrescentam os blocos "-- CORREÇÃO 29/10 (P3):"', true,
      'PULADO: sem agenda_teste.mig_motor_fase2/mig_conferencia_fase2/mig_detector_fase4/mig_correcao_calculo_fase6 (rode pela bancada)');
    return;
  end if;
  for f in select * from (values
      ('agenda_propor', 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', v_c6, '20261029100900', 3),
      ('_agenda_encaixar', 'public._agenda_encaixar(jsonb, jsonb, jsonb)', v_m2, '20261025100200', 2),
      ('_agenda_vigia_limpeza', 'public._agenda_vigia_limpeza(date, timestamptz)', v_d4, '20261027100400', 1),
      ('_agenda_vigia_padrao_do_dono', 'public._agenda_vigia_padrao_do_dono(date, timestamptz)', v_c2, '20261025100300', 2))
      as x(nome, sig, mig, versao, blocos) loop
    v_fonte := pg_temp.corpo(f.mig, f.nome);
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    insert into _resultado values (
      format('K1 %s: sem os blocos "-- CORREÇÃO 29/10 (P3):", é o corpo de %s (com %s blocos)', f.nome, f.versao, f.blocos),
      v_fonte is not null and pg_temp.sem_blocos(v_novo) = v_fonte
      and (select count(*) from regexp_matches(v_novo, '-- CORREÇÃO 29/10 \(P3\): fim', 'g')) = f.blocos,
      format('fonte %s × novo sem blocos %s caracteres', length(v_fonte), length(pg_temp.sem_blocos(v_novo))));
  end loop;
end
$copia$;

-- ── P. Portas (sempre) ───────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'P1 a nova (o modo de cada pergunta) é peça da vigia: só o service_role; invoker, STABLE, search_path fixo',
       not has_function_privilege('anon', 'public._agenda_modo_da_pergunta(text, text)', 'execute')
       and not has_function_privilege('authenticated', 'public._agenda_modo_da_pergunta(text, text)', 'execute')
       and has_function_privilege('service_role', 'public._agenda_modo_da_pergunta(text, text)', 'execute')
       and not p.prosecdef and p.provolatile = 's' and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%',
       null
  from pg_proc p where p.oid = 'public._agenda_modo_da_pergunta(text, text)'::regprocedure;
with f(sig) as (values
  ('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)'),
  ('public._agenda_encaixar(jsonb, jsonb, jsonb)'))
insert into _resultado
select 'P2 o motor recriado continua só do service_role (nem anon nem authenticated)',
       bool_and(not has_function_privilege('anon', sig, 'execute') and not has_function_privilege('authenticated', sig, 'execute')
                and has_function_privilege('service_role', sig, 'execute')), null
  from f;
with f(sig) as (values ('public._agenda_vigia_limpeza(date, timestamptz)'), ('public._agenda_vigia_padrao_do_dono(date, timestamptz)'))
insert into _resultado
select 'P3 as peças da vigia recriadas continuam sem ninguém de fora (só a agenda_vigiar, definer, as chama)',
       bool_and(not has_function_privilege('anon', sig, 'execute') and not has_function_privilege('authenticated', sig, 'execute')
                and not has_function_privilege('service_role', sig, 'execute')), null
  from f;

-- ── C. O parâmetro novo (sempre) ─────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'C1 padrao_do_dono_validade: 7 dias na linha, NOT NULL com DEFAULT',
       c.padrao_do_dono_validade = interval '7 days'
       and (select a.attnotnull and a.atthasdef from pg_attribute a
             where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'padrao_do_dono_validade'),
       c.padrao_do_dono_validade::text
  from public.agenda_config c where c.id;
do $c2$
declare
  v_0 text;
  v_31 text;
  v_30 text := 'aceitou';
begin
  begin
    update public.agenda_config set padrao_do_dono_validade = interval '0 days' where id;
    v_0 := 'aceitou';
  exception when check_violation then
    get stacked diagnostics v_0 = constraint_name;
  end;
  begin
    update public.agenda_config set padrao_do_dono_validade = interval '31 days' where id;
    v_31 := 'aceitou';
  exception when check_violation then
    get stacked diagnostics v_31 = constraint_name;
  end;
  begin
    update public.agenda_config set padrao_do_dono_validade = interval '30 days' where id;
    raise exception 'desfaz' using errcode = 'P0099';
  exception
    when check_violation then v_30 := 'recusou';
    when sqlstate 'P0099' then null;
  end;
  insert into _resultado values ('C2 o CHECK agenda_config_padrao_do_dono_validade_check recusa 0 e 31 dias e aceita 30',
    v_0 = 'agenda_config_padrao_do_dono_validade_check' and v_31 = 'agenda_config_padrao_do_dono_validade_check' and v_30 = 'aceitou',
    format('0: %s, 31: %s, 30: %s', v_0, v_31, v_30));
end
$c2$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
