-- Agenda de Produção, Fase 3 ("A execução: equipe, diária, conclusão e telas"), pacote P6: o acompanhamento — o PPC da
-- semana, as linhas novas do fechamento das 17:30, os focos novos da agenda_ver, a carona e o "livre de verdade" pela
-- simulação do motor.
-- Spec: scratchpad agenda-pesquisa/spec-fase3.md (§9, §11, §13.3, §13.5; §3.3 d17–d19). Decisões do dono 23/10
-- (Autonomia; Rotina com a equipe; Comissão). Depende das Fases 1 e 2 inteiras e de 20261026100000..100400 (tabelas, a
-- conclusão, os caminhos, a rotina da equipe e a diária, a comissão).
--
-- ═══ DDL — OK NOMEADO ═══ (funções novas e recriadas; nenhuma tabela, nenhum gatilho, nenhum dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: com a equipe e a diária andando sozinhas (P4) e a conclusão pela porta (P2/P3), o dono precisa ver o que a
-- agenda fez sem ganhar mensagem nova: tudo vai no fechamento das 17:30 que ele já recebe (as linhas da agenda
-- disputam as MESMAS vagas de REGRAS.maxManha do secretário, sem tipo novo em resumo_itens e sem letras), na conversa
-- (agenda_ver) e, no máximo uma vez por OS por semana, de carona numa resposta do assistente.
--
-- O QUE MUDA:
--   1. agenda_ppc(p_semana, p_hoje): a semana medida (PPC) — por (OS, dia) com compromisso publicado antes do dia
--      começar: cumprido, não cumprido (o 1º motivo da lista fechada LCI) ou sem conferência (fora da conta, listado);
--      ppc = cumpridos ÷ (cumpridos + não cumpridos). O texto da conversa e a linha do fechamento (uma só).
--   2. agenda_livre_de_verdade(p_hoje, p_agora): com modo_proposta 'ligado', a simulação do motor (agenda_propor
--      'replano' com p_persistir = false, toda a carteira) diz quando a equipe fica livre "só com o que está pronto" e
--      "se as compras saírem"; fora de 'ligado' {fonte: projecao} e quem chama usa a frase da Fase 1.
--   3. _agenda_linhas_do_fechamento recriada (corpo de 20261025100500, mudanças marcadas -- FASE 3:): a pergunta crítica
--      da diária vira a linha diaria (pelo modo_diaria); a linha dia ganha o que a equipe confirmou, a diária que a
--      agenda lançou, quem falta confirmar e o último dia da OS; as linhas conclusao (o que o gestor concluiu pela
--      palavra do técnico), ppc (o último dia útil da semana) e comissao (o 1º dia útil do mês).
--   4. agenda_ver recriada (corpo de 20261025100500, -- FASE 3:): focos ppc, diarias, marcos, comissao e equipe; o foco
--      livre e a frase do livre da semana pela simulação em 'ligado'.
--   5. agenda_carona(p_autor, p_os, p_canal, p_hoje, p_agora): no fim de uma resposta do assistente ao dono sobre UMA OS,
--      no máximo uma pergunta aberta dela ("Aproveitando: …"), uma vez por OS a cada carona_por_os_dias.
--   6. ai_job_registrar_os(p_job_id, p_os): o erp-mcp guarda no job do Claude Max as OS que as ferramentas do turno
--      tocaram, para a carona sair também no caminho do Max (o WhatsApp do dono vai por ele).
--   7. _agenda_mudancas recriada (corpo de 20261025100500): ações gravadas na mesma transação têm o mesmo criada_em
--      (now()); o desempate era o id (aleatório) e o G10 de agenda_fase2_leituras.sql falhava cerca de 1 vez em 15. Agora
--      a ordem é criada_em, OS, id (o motor publica por OS).
--   Auxiliares: _agenda_titulo_da_semana, _agenda_texto_do_dia, _agenda_dia_da_equipe, _agenda_mes_dito,
--   _agenda_ver_ppc, _agenda_ver_diarias, _agenda_ver_marcos, _agenda_ver_comissao, _agenda_ver_equipe.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase3_acompanhamento.sql):
--   · A linha dia: o começo continua o texto da conferência da vigia ("Agenda de hoje: Vanderlei (OS-00069) — você abre,
--     Roberto o dia todo; Flávio (OS-00104) — você, João à tarde."), que os testes da Fase 2 fixam; o que a Fase 3
--     acrescenta vem depois ("O Roberto confirmou o dia todo e lancei a diária dele (R$ 180,00). Foi isso para o João?
--     *dia feito* lança a meia diária dele, ou conte o que mudou."). Sem nada da equipe, da diária ou do último dia, o
--     texto fica byte a byte o de antes. Com a conferência já respondida (todos confirmaram), a linha sai só quando há o
--     que contar (a diária lançada pela agenda, o último dia da OS).
--   · A perda da linha diaria: não há no banco a data em que o acerto fecha (o dono fecha quando quer: o de outubro foi
--     de 29/09 a 17/10, fechado seg 19/10). Sobe de 50 para 80 quando a pergunta tem 2 dias úteis ou mais sem resposta.
--   · A linha conclusao diz *desfaz OS-00069* (o número): a OS concluída sai da carteira e o nome não acha mais (é a
--     dica que as palavras do P3 já dão, NOVO-agenda-25).
--   · O "Sem conferência" da linha do PPC usa *dia feito dd/mm*: a palavra aceita o dia por dd/mm ou pelo nome inteiro
--     ("quarta"), não "qua".
--   · O "livre de verdade": o "melhor" conta também as reservas acima da carga e no pátio (é serviço pronto que a equipe
--     vai fazer, só passou dos 80%); o "realista" soma as reservas condicionadas (classe 3). A carteira inteira (fora
--     orçamento) vai à simulação e o próprio motor separa as classes; o que fica sem encaixe no horizonte aparece com
--     os nomes.
--   · A carona recebe as OS como o turno as citou (número, nome ou id: p_os text[]) e as resolve aqui, por
--     agenda_resolver_os (o TS não resolve nada). Ref ambígua = nenhuma carona.
--   · A carona no caminho do Claude Max: o job não guardava os argumentos das ferramentas (só os nomes); daí o
--     ai_job_registrar_os, chamado pelo erp-mcp.
--
-- O QUE NÃO MUDA: nenhuma tabela, nenhum gatilho, nenhum dado; nada é mandado a ninguém (a carona vai junto de uma
-- resposta que o dono pediu). Com modo_equipe e modo_diaria em 'desligado' e sem PPC/comissão no dia, o fechamento sai
-- byte a byte o da Fase 2 (agenda_fase2_leituras.sql continua passando; o helper dele ignora as linhas novas ppc e
-- comissao, provadas aqui). A comissão continua só a conta: nada é pago.
--
-- ORDEM DE LIGAR: depois de 20261026100400; antes do ai-daily-briefing (o secretário passa a aceitar os tipos novos de
-- linha), do ai-agent (a carona) e do erp-mcp (as OS do turno do Max).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase3_acompanhamento.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261026100500
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261026100500_agenda_fase3_acompanhamento.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261026100500', 'agenda_fase3_acompanhamento');"
--
-- IDEMPOTENTE: só create or replace function, revoke/grant e comment.

-- ── 0. O que a agenda mudou sozinha: a ordem de gravação (o G10 instável da Fase 2) ─────────────────────────
-- Corpo de 20261025100500 copiado; as mudanças estão marcadas "-- FASE 3:".
create or replace function public._agenda_mudancas(p_de date, p_ate date, p_executada boolean, p_fechamento boolean,
                                                   p_agora timestamptz default null)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with
  b as (
    select a.id, a.tipo, a.service_order_id as os, a.dia, a.proposta_id, a.texto, a.criada_em as em,
           a.desfazivel_ate is not null and a.desfeita_em is null and (p_agora is null or a.desfazivel_ate >= p_agora) as desfazivel,
           a.desfeita_em is not null as desfeita,
           coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) as nome, so.service_order_number as numero
      from public.agenda_acoes a
      left join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.dia between p_de and p_ate and a.executada = p_executada
       and a.tipo not in ('resultado', 'desfazer', 'fixar')
       and (a.origem in ('motor', 'vigia') or (not p_fechamento and a.origem = 'conferencia'))
       and (not p_fechamento or (a.contada_em is null and a.desfeita_em is null))
  ),
  dono as (
    select b.*, coalesce(case when b.tipo = 'publicar' then 'p:' || b.proposta_id end, 'a:' || b.id) as grupo, false as junto
      from b where b.tipo <> 'status'
  ),
  st as (
    -- FASE 3: a mesma ordem (criada_em, OS, id) para achar o grupo
    select s.*, coalesce((select d.grupo from dono d where d.os = s.os and d.dia = s.dia order by d.em, d.os, d.id limit 1),
                         'a:' || s.id) as grupo
      from b s where s.tipo = 'status'
  ),
  todos as (
    select d.* from dono d
    union all
    select s.id, s.tipo, s.os, s.dia, s.proposta_id, s.texto, s.em, s.desfazivel, s.desfeita, s.nome, s.numero, s.grupo,
           s.grupo <> 'a:' || s.id
      from st s
  ),
  g as (
    -- FASE 3: dentro do grupo, a ordem de gravação é criada_em, OS, id (o que entra na mesma transação tem o mesmo
    -- criada_em e o id é aleatório: o G10 de agenda_fase2_leituras.sql falhava cerca de 1 vez em 15)
    select t.grupo,
           case when t.grupo like 'p:%' then 'publicacao' else 'acao' end as tipo,
           min(t.proposta_id::text) filter (where t.tipo = 'publicar') as proposta_id,
           jsonb_agg(t.id order by t.em, t.os nulls last, t.id) as acao_ids,
           coalesce(jsonb_agg(t.texto order by t.em, t.os nulls last, t.id) filter (where not t.junto), '[]'::jsonb) as itens,
           min(t.os::text) filter (where not t.junto) as os,
           min(t.nome) filter (where not t.junto) as nome,
           min(t.numero) filter (where not t.junto) as numero,
           coalesce(bool_or(t.desfazivel) filter (where not t.junto), false) as desfazivel,
           coalesce(bool_and(t.desfeita) filter (where not t.junto), false) as desfeita,
           min(t.em) as em, min(t.os::text) as desempate_os, min(t.id::text) as desempate
      from todos t
     group by t.grupo
  )
  select coalesce(jsonb_agg(jsonb_build_object('grupo', g.grupo, 'tipo', g.tipo, 'proposta_id', g.proposta_id,
                                               'acao_ids', g.acao_ids, 'itens', g.itens, 'os', g.os, 'nome', g.nome,
                                               'numero', g.numero, 'desfazivel', g.desfazivel, 'desfeita', g.desfeita,
                                               'em', g.em)
                            -- FASE 3: entre os grupos, a mesma ordem (criada_em, OS, id)
                            order by g.em, g.desempate_os nulls last, g.desempate), '[]'::jsonb)
    from g;
$function$;

comment on function public._agenda_mudancas(date, date, boolean, boolean, timestamptz) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a ordem de gravação criada_em, OS, id): o que a agenda mudou sozinha (motor e vigia; fora do fechamento também o replano da conferência) com agenda_acoes.dia em [p_de, p_ate], em grupos — a publicação da semana (as ações publicar da mesma proposta) e cada outra ação; o status que acompanha a publicação ou o replano da mesma OS no mesmo dia vai no grupo dela. p_executada false = o que a sombra teria feito; p_fechamento = só o não contado e não desfeito, só motor e vigia. [{grupo, tipo, proposta_id, acao_ids, itens, os, nome, numero, desfazivel, desfeita, em}].';

-- ── 1. O PPC da semana ──────────────────────────────────────────────────────────────────────────────────

-- "Semana de 03 a 06/11 (seg 02 é Finados)": os dias úteis da semana ISO de p_seg (a régua do título do motor; com mês
-- diferente nas pontas, "Semana de 28/09 a 02/10").
create or replace function public._agenda_titulo_da_semana(p_seg date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select format('Semana de %s a %s',
                to_char(x.d0, case when extract(month from x.d0) = extract(month from x.d1) then 'DD' else 'DD/MM' end),
                to_char(x.d1, 'DD/MM'))
         || coalesce(' (' || nullif(array_to_string(array(
              select format('%s é %s', public._agenda_dia_sem_mes(g::date), public.agenda_feriado(g::date))
                from generate_series(p_seg, p_seg + 4, interval '1 day') g
               where public.agenda_feriado(g::date) is not null order by g), ', '), '') || ')', '')
    from (select coalesce(min(g::date), p_seg) as d0, coalesce(max(g::date), p_seg + 4) as d1
            from generate_series(p_seg, p_seg + 5, interval '1 day') g
           where public.agenda_dia_util(g::date)) x;
$function$;

comment on function public._agenda_titulo_da_semana(date) is
  'Agenda de Produção (Fase 3, P6): o título da semana ISO de p_seg pelos dias úteis dela, com os feriados de dia útil: "Semana de 03 a 06/11 (seg 02 é Finados)".';

-- A semana medida: o PPC (Percent Plan Complete) por (OS, dia) de compromisso.
create or replace function public.agenda_ppc(p_semana date default null, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_ref   date := coalesce(p_semana, p_hoje);
  v_seg   date;
  v_de    date;
  v_ult   date;
  v_ate   date;
  v_tit   text;
  v_dono  uuid := public._agenda_dono(null);
  v_pares jsonb;
  v_comp  int;
  v_cump  int;
  v_nao   jsonb;
  v_sem   jsonb;
  v_mot   jsonb;
  v_den   int;
  v_ppc   numeric;
  v_cab   text;
  v_num   text;
  v_l     text[];
  v_lin   text;
  v_dias  text[];
begin
  if p_hoje is null then
    raise exception 'agenda_ppc: sem o dia de hoje' using errcode = '22004';
  end if;
  v_seg := v_ref - (extract(isodow from v_ref)::int - 1);
  select min(g::date), max(g::date) into v_de, v_ult
    from generate_series(v_seg, v_seg + 5, interval '1 day') g where public.agenda_dia_util(g::date);
  v_de := coalesce(v_de, v_seg);
  v_ult := coalesce(v_ult, v_seg + 4);
  v_ate := least(v_ult, p_hoje);
  v_tit := public._agenda_titulo_da_semana(v_seg);

  -- Os pares (OS, dia): as alocações vigentes de compromisso (sem reserva) do dia que já chegou, publicadas antes de o
  -- dia começar (o compromisso existia antes do 1º turno: a alocação criada no próprio dia, depois do início, não conta).
  -- O dia da publicação é o p_hoje da ação que a criou (agenda_acoes.dia; o relógio do banco não entra na conta); sem
  -- ação, o dia de publicada_em em Brasília. No mesmo dia, vale a hora: antes do 1º turno conta.
  with a0 as (
    select al.service_order_id as os, al.dia, al.resultado, al.motivo, al.payee_id, lower(al.periodo) as ini, al.publicada_em,
           coalesce((select min(x.dia) from public.agenda_acoes x where x.executada and al.id = any (x.alocacoes_criadas)),
                    (al.publicada_em at time zone 'America/Sao_Paulo')::date) as dia_pub
      from public.agenda_alocacoes al
     where al.estado in ('publicada', 'fixada')
       and al.tipo in ('execucao', 'diagnostico', 'comissionamento', 'entrega')
       and al.dia between v_seg and v_ate
  ),
  a as (
    select a0.* from a0
     where a0.dia_pub < a0.dia
        or (a0.dia_pub = a0.dia and a0.publicada_em < lower(public.agenda_periodo(a0.dia, 'manha', 'turno')))
  ),
  p as (
    select a.os, a.dia,
           bool_and(a.resultado = 'cumprido') as cumprido,
           bool_or(a.resultado in ('parcial', 'nao_cumprido')) as falhou,
           (array_agg(a.motivo order by a.ini, a.payee_id) filter (where a.resultado in ('parcial', 'nao_cumprido')))[1] as motivo,
           array_agg(distinct a.payee_id) as pessoas
      from a group by a.os, a.dia
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'os', p.os, 'dia', p.dia, 'numero', so.service_order_number,
           'nome', coalesce(public._agenda_nome_curto(cl.name), so.service_order_number),
           'situacao', case when p.falhou then 'nao_cumprido' when p.cumprido then 'cumprido' else 'sem_conferencia' end,
           'motivo', p.motivo,
           'pessoas', public._agenda_lista(array(
              select case when x = v_dono then 'você' else coalesce(public._agenda_nome_curto(py.name), '?') end
                from unnest(p.pessoas) x left join public.payees py on py.id = x
               order by x is distinct from v_dono, py.name), null))
           order by p.dia, so.service_order_number collate "C", p.os), '[]'::jsonb)
    into v_pares
    from p
    join public.service_orders so on so.id = p.os
    left join public.clients cl on cl.id = so.client_id;

  v_comp := jsonb_array_length(v_pares);
  v_cump := (select count(*) from jsonb_array_elements(v_pares) e where e ->> 'situacao' = 'cumprido');
  select coalesce(jsonb_agg(jsonb_build_object('os', e -> 'os', 'numero', e -> 'numero', 'nome', e -> 'nome', 'dia', e -> 'dia',
                                               'motivo', e -> 'motivo',
                                               'motivo_texto', public._agenda_motivo_texto(e ->> 'motivo')) order by o), '[]'::jsonb)
    into v_nao from jsonb_array_elements(v_pares) with ordinality t(e, o) where e ->> 'situacao' = 'nao_cumprido';
  select coalesce(jsonb_agg(jsonb_build_object('os', e -> 'os', 'nome', e -> 'nome', 'dia', e -> 'dia', 'pessoas', e -> 'pessoas')
                            order by o), '[]'::jsonb)
    into v_sem from jsonb_array_elements(v_pares) with ordinality t(e, o) where e ->> 'situacao' = 'sem_conferencia';
  select coalesce(jsonb_object_agg(m.motivo, m.n), '{}'::jsonb) into v_mot
    from (select e ->> 'motivo' as motivo, count(*) as n from jsonb_array_elements(v_nao) e
           where e ->> 'motivo' is not null group by 1) m;
  v_den := v_cump + jsonb_array_length(v_nao);
  v_ppc := case when v_den > 0 then round(v_cump::numeric / v_den, 4) end;

  -- O texto (conversa) e a linha (fechamento).
  v_cab := v_tit || case when p_hoje < v_ult then ' até ' || public._dia_curto(p_hoje) else '' end || ': ';
  if v_comp = 0 then
    v_l := array[v_cab || 'nada publicado na agenda para medir.'];
    v_lin := null;
  else
    v_num := case when v_den = 0
                  then format('%s, nenhum conferido ainda', public._agenda_plural(v_comp, 'dia de serviço', 'dias de serviço'))
                  else format('%s de %s %s (%s%%', v_cump, public._agenda_plural(v_den, 'dia de serviço', 'dias de serviço'),
                              case when v_cump = 1 then 'cumprido' else 'cumpridos' end,
                              public._agenda_num(round(v_ppc * 100), 0)) end;
    v_l := array[v_cab || v_num
                 || case when v_den > 0 then format('; a meta é %s%%)', public._agenda_num(round(cf.ppc_meta * 100), 0)) else '' end || '.'];
    v_lin := v_cab || v_num || case when v_den > 0 then ')' else '' end || '.';
    if jsonb_array_length(v_nao) > 0 then
      v_l := v_l || ('Não cumprido: ' || public._agenda_lista(array(
                       select format('%s %s — %s', e ->> 'nome', public._dia_curto((e ->> 'dia')::date), e ->> 'motivo_texto')
                         from jsonb_array_elements(v_nao) with ordinality t(e, o) order by o), 5) || '.');
      v_lin := v_lin || ' Não cumprido: ' || public._agenda_lista(array(
                 select format('%s %s (%s)', e ->> 'nome', public._dia_curto((e ->> 'dia')::date), e ->> 'motivo_texto')
                   from jsonb_array_elements(v_nao) with ordinality t(e, o) order by o), 3) || '.';
    end if;
    if jsonb_array_length(v_sem) > 0 then
      -- por dia: "ter 03/11 (Vanderlei: você e Roberto; Flávio: você e João)"
      v_l := v_l || ('Sem conferência: ' || public._agenda_lista(array(
                       select format('%s (%s)', public._dia_curto(d.dia), d.oss)
                         from (select (e ->> 'dia')::date as dia,
                                      string_agg(format('%s: %s', e ->> 'nome', e ->> 'pessoas'), '; ' order by o) as oss
                                 from jsonb_array_elements(v_sem) with ordinality t(e, o) group by 1) d
                        order by d.dia), 5) || '.');
      v_dias := array(select to_char(x.dia, 'DD/MM')
                        from (select distinct (e ->> 'dia')::date as dia from jsonb_array_elements(v_sem) e) x order by x.dia);
      v_lin := v_lin || ' Sem conferência: ' || public._agenda_lista(array(
                 select format('%s (%s)', public._dia_curto(d.dia), d.oss)
                   from (select (e ->> 'dia')::date as dia, public._agenda_lista(array_agg(e ->> 'nome' order by o), null) as oss
                           from jsonb_array_elements(v_sem) with ordinality t(e, o) group by 1) d
                  order by d.dia), 3)
               || format(' — *dia feito %s* confirma%s.', v_dias[1], case when cardinality(v_dias) > 1 then ' (um dia por vez)' else '' end);
    end if;
  end if;

  return jsonb_build_object(
    'semana', jsonb_build_object('de', v_de, 'ate', v_ult), 'ate', v_ate, 'ultimo_dia_util', p_hoje = v_ult,
    'compromissos', v_comp, 'cumpridos', v_cump, 'nao_cumpridos', v_nao, 'sem_conferencia', v_sem,
    'ppc', v_ppc, 'meta', cf.ppc_meta, 'motivos', v_mot,
    'texto', public._agenda_juntar(v_l, cf.texto_max), 'linha', v_lin);
end;
$function$;

comment on function public.agenda_ppc(date, date) is
  'Agenda de Produção (Fase 3, P6): o PPC da semana ISO de p_semana (sem ele, a de p_hoje), até p_hoje. Unidade: (OS, dia) com alocação vigente de compromisso (execucao, diagnostico, comissionamento, entrega; sem reserva) publicada antes do 1º turno do dia. cumprido = todas cumpridas; não cumprido = alguma parcial ou não cumprida (o 1º motivo pela ordem dos turnos, código LCI); sem conferência = o resto (sem resultado ou sem_registro): fora da conta e listado. ppc = cumpridos ÷ (cumpridos + não cumpridos); sem denominador, null. {semana{de, ate}, ate, ultimo_dia_util, compromissos, cumpridos, nao_cumpridos[{os, numero, nome, dia, motivo, motivo_texto}], sem_conferencia[{os, nome, dia, pessoas}], ppc, meta (ppc_meta), motivos{código: n}, texto (conversa), linha (fechamento: "Semana de 03 a 06/11 (seg 02 é Finados): 4 de 5 dias de serviço cumpridos (80%). Não cumprido: … Sem conferência: … — *dia feito 06/11* confirma.")}.';

-- ── 1b. A pergunta da diária em texto (o fechamento e a agenda_ver decisoes dizem igual) ──────────────────

-- 'O Roberto respondeu "fiquei só de manhã" e o plano de ter 03/11 era o dia todo no Vanderlei (OS-00069). 1) meia
-- diária no Vanderlei (OS-00069) (R$ 90,00), como o Roberto disse; 2) …; 3) não lançar. Recomendo a 1: é o que o
-- Roberto respondeu às 17:12. *diária Roberto meia* · *diária Roberto inteira* · *diária Roberto não*.' — a pergunta, as
-- opções, a recomendação e as palavras que respondem (só as que a palavra *diária <nome> …* sabe fazer).
create or replace function public._agenda_texto_da_diaria(p_pergunta uuid)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select q.texto || ' '
         || (select string_agg(format('%s) %s', e ->> 'n', e ->> 'texto'), '; ' order by (e ->> 'n')::int)
               from jsonb_array_elements(q.opcoes) e) || '. '
         || coalesce(q.recomendacao_texto || ' ', '')
         || coalesce(nullif(array_to_string(array(
              select format('*diária %s %s*', n.nome,
                            case when e -> 'efeito' -> 'diaria' = 'null'::jsonb then 'não'
                                 when e #>> '{efeito,diaria,jornada}' = 'meio' then 'meia' else 'inteira' end)
                from jsonb_array_elements(q.opcoes) with ordinality t(e, o)
               where n.nome is not null
                 and (e -> 'efeito' -> 'diaria' = 'null'::jsonb or e #>> '{efeito,diaria,jornada}' in ('meio', 'inteiro'))
               order by o), ' · '), '') || '.', 'Me responda aqui.')
    from public.agenda_perguntas q
    left join lateral (select public._agenda_nome_curto(py.name) as nome from public.payees py where py.id = q.payee_id) n on true
   where q.id = p_pergunta;
$function$;

comment on function public._agenda_texto_da_diaria(uuid) is
  'Agenda de Produção (Fase 3, P6): a pergunta da diária em texto — a pergunta, "1) …; 2) …; 3) …", a recomendação e as palavras que respondem (*diária Roberto meia* · *diária Roberto inteira* · *diária Roberto não*; só as opções que a palavra sabe fazer; sem nenhuma, "Me responda aqui."). O fechamento (linha diaria) e a agenda_ver (foco decisoes) dizem igual.';

-- ── 2. "Livre de verdade" pela simulação do motor ──────────────────────────────────────────────────────────

-- A segunda-feira da semana seguinte à de um dia (o 1º dia da semana em que a equipe fica livre).
create or replace function public._agenda_segunda_seguinte(p_dia date)
 returns date
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when p_dia is null then null else p_dia - (extract(isodow from p_dia)::int - 1) + 7 end;
$function$;

comment on function public._agenda_segunda_seguinte(date) is
  'Agenda de Produção (Fase 3, P6): a segunda-feira da semana seguinte à de p_dia.';

create or replace function public.agenda_livre_de_verdade(p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config := public._agenda_cfg();
  v_uid    uuid := auth.uid();
  v_os     uuid[];
  r        jsonb;
  v_t0     timestamptz := clock_timestamp();
  v_canc   uuid[];
  v_vig    date;
  v_sim    date;
  v_res    date;
  v_hor    date;
  v_comp   date;
  v_melhor date;
  v_real   date;
  v_sem    jsonb;
  v_dec    jsonb;
  v_txt    text;
  v_msg    text;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_livre_de_verdade: sem o dia ou a hora de agora' using errcode = '22004';
  end if;
  -- Quem vê: com login, só administrador e financeiro; sem login, o service_role (o assistente pelo WhatsApp).
  if v_uid is not null and not public.is_admin_or_financial(v_uid) then
    raise exception 'A agenda de produção é com o administrador.' using errcode = '42501';
  end if;
  -- O publicado só existe em 'ligado': fora disso, quem chama usa a projeção da Fase 1 (fila ÷ capacidade).
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('fonte', 'projecao', 'motivo', 'a agenda automática não está ligada');
  end if;

  -- A carteira inteira (fora orçamento) vai à simulação; o próprio motor separa as classes (1 e 2 compromisso, 3 só
  -- reserva condicionada, 4 fora) e respeita o congelado. Sem persistir: nada é gravado (o teste prova).
  v_os := array(select k.service_order_id from public.os_carteira(p_hoje) k where not k.eh_orcamento
                 order by k.numero, k.service_order_id);
  if cardinality(v_os) > 0 then
    begin
      r := public.agenda_propor('replano', null, null, v_os, '{}'::jsonb, false, 'motor', null, p_hoje, p_agora);
    exception when others then
      get stacked diagnostics v_msg = message_text;
      return jsonb_build_object('fonte', 'projecao', 'motivo', 'a simulação falhou', 'erro', left(v_msg, 300));
    end;
  end if;

  -- O vigente que fica (sem o que a simulação cancela), o compromisso simulado e a reserva condicionada simulada.
  v_canc := array(select (a ->> 'alocacao_id')::uuid
                    from jsonb_array_elements(coalesce(r -> 'itens', '[]'::jsonb)) i,
                         jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) a
                   where i ->> 'op' = 'cancelar' and a ->> 'alocacao_id' is not null);
  select max(a.dia) into v_vig from public.agenda_alocacoes a
   where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje and not (a.id = any (v_canc));
  -- o "melhor": o compromisso e também as reservas acima da carga e no pátio (serviço pronto que só passou dos 80%)
  select max((i ->> 'ate')::date) into v_sim from jsonb_array_elements(coalesce(r -> 'itens', '[]'::jsonb)) i
   where i ->> 'op' = 'criar' and not coalesce((i ->> 'espera')::boolean, false)
     and coalesce(i ->> 'reserva_de', '') <> 'condicionada';
  select max((i ->> 'ate')::date) into v_res from jsonb_array_elements(coalesce(r -> 'itens', '[]'::jsonb)) i
   where i ->> 'op' = 'criar' and i ->> 'reserva_de' = 'condicionada';
  v_hor := (r #>> '{periodo,ate}')::date;
  select coalesce(jsonb_agg(jsonb_build_object('os', f -> 'os', 'numero', f -> 'numero',
                                               'nome', coalesce(f ->> 'cliente_curto', f ->> 'numero'), 'motivo', f -> 'motivo')
                            order by o), '[]'::jsonb)
    into v_sem
    from jsonb_array_elements(coalesce(r -> 'fora', '[]'::jsonb)) with ordinality t(f, o)
   where f ->> 'motivo' in ('sem_encaixe', 'fixar_nao_cabe', 'padrao_do_dono');
  -- a que não cabe até a data do cliente espera a decisão do dono (a pergunta crítica): fica fora da conta, com o nome
  select coalesce(jsonb_agg(jsonb_build_object('os', f -> 'os', 'numero', f -> 'numero',
                                               'nome', coalesce(f ->> 'cliente_curto', f ->> 'numero')) order by o), '[]'::jsonb)
    into v_dec
    from jsonb_array_elements(coalesce(r -> 'fora', '[]'::jsonb)) with ordinality t(f, o)
   where f ->> 'motivo' = 'nao_cabe';

  v_comp := greatest(v_vig, v_sim);
  v_melhor := public._agenda_segunda_seguinte(v_comp);
  v_real := case when v_res is not null and (v_comp is null or v_res > v_comp) then public._agenda_segunda_seguinte(v_res)
                 else v_melhor end;
  v_txt := 'Livre de verdade (pela simulação da agenda): '
    || case
         when v_melhor is null and v_real is null then 'não tem serviço pronto para marcar: a equipe já está livre.'
         when v_melhor is null
           then format('só com o que está pronto, a equipe já está livre; se as compras saírem, a partir da semana de %s.',
                       to_char(v_real, 'DD/MM'))
         when v_real is distinct from v_melhor
           then format('só com o que está pronto, a partir da semana de %s; se as compras saírem, a partir de %s.',
                       to_char(v_melhor, 'DD/MM'), to_char(v_real, 'DD/MM'))
         else format('a partir da semana de %s.', to_char(v_melhor, 'DD/MM')) end
    || case when jsonb_array_length(v_sem) > 0
            then format(' Sem encaixe até %s: %s.', public._dia_curto(v_hor),
                        public._agenda_lista(array(select e ->> 'nome' from jsonb_array_elements(v_sem) with ordinality t(e, o)
                                                    order by o), 3))
            else '' end
    || case when jsonb_array_length(v_dec) > 0
            then format(' Fora da conta, esperando a sua decisão: %s.',
                        public._agenda_lista(array(select e ->> 'nome' from jsonb_array_elements(v_dec) with ordinality t(e, o)
                                                    order by o), 3))
            else '' end
    || ' É simulação: não muda nada.';
  return jsonb_build_object('fonte', 'simulacao', 'melhor', v_melhor, 'realista', v_real, 'sem_encaixe', v_sem,
                            'esperando_voce', v_dec,
                            'depois', case when jsonb_array_length(v_sem) > 0 then v_hor end, 'horizonte', v_hor,
                            'texto', v_txt,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$function$;

comment on function public.agenda_livre_de_verdade(date, timestamptz) is
  'Agenda de Produção (Fase 3, P6): "quando a gente fica livre de verdade?" pela simulação do motor — só com modo_proposta ligado (fora disso {fonte: projecao}: quem chama usa a frase da Fase 1). agenda_propor(replano, toda a carteira fora orçamento, p_persistir = false): nada é gravado. melhor = a segunda-feira seguinte ao último meio-dia de compromisso (o vigente que fica + o simulado, com as reservas acima da carga e no pátio); realista = a segunda seguinte à última reserva condicionada simulada (classe 3, como se a condição se cumprisse); sem_encaixe = o que não coube no horizonte (depois = o fim dele), com os nomes; esperando_voce = o que não cabe até a data do cliente (a decisão crítica), fora da conta. {fonte, melhor, realista, sem_encaixe, esperando_voce, depois, horizonte, texto ("Livre de verdade (pela simulação da agenda): só com o que está pronto, a partir da semana de 09/11; se as compras saírem, a partir de 16/11. É simulação: não muda nada."), ms}. A simulação que falha = {fonte: projecao, erro}. STABLE, definer (o motor é só do service_role); administrador e financeiro com login, ou o service_role.';

-- ── 3. As linhas do fechamento das 17:30 ─────────────────────────────────────────────────────────────────

-- "Agenda de hoje: Vanderlei (OS-00069) — você abre, Roberto o dia todo; Flávio (OS-00104) — você, João à tarde." — o
-- começo do texto da conferência da vigia (20261025100300, _agenda_vigia_conferencia), para o dia que não tem a
-- pergunta aberta (todos confirmaram) e ainda tem o que contar. null = hoje não tem plano.
create or replace function public._agenda_texto_do_dia(p_hoje date)
 returns text
 language sql
 stable
 set search_path to 'public'
as $function$
  select 'Agenda de hoje: ' || string_agg(q.txt, '; ' order by q.ini, q.numero collate "C") || '.'
    from (select public._agenda_rotulo_da_os(a.service_order_id) || ' — '
                 || public._agenda_pessoas_texto(jsonb_agg(jsonb_build_object('payee_id', a.payee_id,
                                                   'nome', public._agenda_nome_curto(py.name), 'dia', a.dia, 'turno', a.turno,
                                                   'presenca', a.presenca)), public._agenda_dono(null)) as txt,
                 min(lower(a.periodo)) as ini, min(so.service_order_number) as numero
            from public.agenda_alocacoes a
            join public.payees py on py.id = a.payee_id
            join public.service_orders so on so.id = a.service_order_id
           where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_hoje
           group by a.service_order_id) q
  having count(*) > 0;
$function$;

comment on function public._agenda_texto_do_dia(date) is
  'Agenda de Produção (Fase 3, P6): "Agenda de hoje: <OS — quem vai; …>." — o começo do texto da conferência da vigia (a mesma frase), para a linha dia do fechamento quando a conferência já foi respondida. null = sem plano hoje.';

-- O que a linha dia do fechamento conta da equipe e da diária de hoje, e o último dia da OS:
--   lig       as frases que valem (pelos modos ligados agora): "O Roberto confirmou o dia todo e lancei a diária dele
--             (R$ 180,00).", "O Roberto ainda não respondeu como foi; quando responder, eu lanço a diária.";
--   som       as frases da sombra (o que diria): "Em teste: o Roberto confirmou o dia todo; eu lançaria a diária dele (…).";
--   ids       as ações diaria que a linha conta (ficam contadas quando o fechamento sai);
--   pendentes os diaristas do plano sem confirmação nenhuma (sem telefone ou fora da rotina): [{nome, meios}];
--   aguardando quantos receberam o "como foi hoje?" e ainda não responderam;
--   lancadas  [{nome, fracao}] (a correção que a linha sugere: *diária Roberto meia*);
--   ultimo    "Hoje era o último dia do Lenine (OS-00074) no plano: terminou? *concluiu Lenine* fecha a OS (…)."
-- O dono (sócio) não tem diária e não entra.
create or replace function public._agenda_dia_da_equipe(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  p      record;
  o      record;
  v_a    record;
  v_m    record;
  v_ms   record;
  v_conf jsonb;
  v_frac numeric;
  v_lig  text[] := '{}';
  v_som  text[] := '{}';
  v_ids  jsonb := '[]'::jsonb;
  v_pend jsonb := '[]'::jsonb;
  v_ag   int := 0;
  v_lanc jsonb := '[]'::jsonb;
  v_ult  text[] := '{}';
begin
  for p in
    select a.payee_id, public._agenda_nome_curto(py.name) as nome, count(distinct a.turno)::int as meios
      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
     where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_hoje and py.kind is distinct from 'socio'
     group by a.payee_id, py.name
     order by min(lower(a.periodo)), py.name, a.payee_id
  loop
    -- a diária que a agenda lançou (ou lançaria, em sombra) pela resposta dele e ainda não contou
    select x.* into v_a from public.agenda_acoes x
     where x.tipo = 'diaria' and x.payee_id = p.payee_id and x.depois ->> 'dia' = p_hoje::text and x.origem = 'equipe'
       and x.desfeita_em is null and x.contada_em is null
     order by x.executada desc, x.criada_em desc, x.id desc limit 1;
    v_frac := (v_a.depois ->> 'fracao')::numeric;
    if v_a.id is not null and v_a.executada then
      v_lig := v_lig || format('O %s confirmou %s e lancei a %s dele (%s).', p.nome,
                               case when v_frac = 1 then 'o dia todo' else 'meio dia' end,
                               case when v_frac = 1 then 'diária' else 'meia diária' end,
                               public._brl((v_a.depois ->> 'valor')::numeric));
      v_ids := v_ids || to_jsonb(v_a.id);
      v_lanc := v_lanc || jsonb_build_object('nome', p.nome, 'fracao', v_frac);
      continue;
    end if;
    v_conf := public._agenda_confirmacao_do_dia(p.payee_id, p_hoje);
    if v_conf ->> 'estado' = 'confirmada' and v_conf ->> 'fonte' = 'equipe' then
      v_lig := v_lig || format('O %s confirmou %s.', p.nome, case when p.meios = 2 then 'o dia todo' else 'meio dia' end);
      if v_a.id is not null then
        v_som := v_som || format('Em teste: eu lançaria a %s do %s (%s).', case when v_frac = 1 then 'diária' else 'meia diária' end,
                                 p.nome, public._brl((v_a.depois ->> 'valor')::numeric));
      end if;
      continue;
    end if;
    -- respondeu diferente do plano ou não foi entendido: a linha diaria (crítica) pergunta; o dono já conferiu: nada
    continue when v_conf ->> 'estado' <> 'aguardando';
    select x.* into v_m from public.agenda_equipe_mensagens x
     where x.payee_id = p.payee_id and x.dia = p_hoje and x.tipo = 'como_foi' and x.modo = 'ligado'
     order by x.enviar_em desc, x.criada_em desc limit 1;
    if v_m.id is not null and v_m.estado = 'enfileirada' and cf.modo_equipe = 'ligado' then
      v_lig := v_lig || format('O %s ainda não respondeu como foi%s.', p.nome,
                               case when cf.modo_diaria = 'ligado' then '; quando responder, eu lanço a diária' else '' end);
      v_ag := v_ag + 1;
      continue;
    end if;
    select x.* into v_ms from public.agenda_equipe_mensagens x
     where x.payee_id = p.payee_id and x.dia = p_hoje and x.tipo = 'como_foi' and x.modo = 'sombra'
     order by x.enviar_em desc, x.criada_em desc limit 1;
    if v_ms.id is not null then
      v_som := v_som || format('Em teste: eu perguntaria ao %s como foi hoje (%s).', p.nome,
                               to_char(v_ms.enviar_em at time zone 'America/Sao_Paulo', 'HH24:MI'));
    end if;
    -- ninguém confirmou (sem telefone, fora da rotina ou com a equipe fora de ligado): só o *dia feito* do dono lança
    if cf.modo_diaria = 'ligado' then
      v_pend := v_pend || jsonb_build_object('nome', p.nome, 'meios', p.meios);
    end if;
  end loop;

  -- O último dia da OS no plano (sem dia depois de hoje, ainda não concluída, sem a pergunta de concluir aberta).
  for o in
    select a.service_order_id as os, so.service_order_number as numero, public._agenda_nome_curto(cl.name) as nome
      from public.agenda_alocacoes a
      join public.service_orders so on so.id = a.service_order_id
      left join public.clients cl on cl.id = so.client_id
     where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia = p_hoje
       and so.status in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client')
     group by a.service_order_id, so.service_order_number, cl.name
    having not exists (select 1 from public.agenda_alocacoes b
                        where b.service_order_id = a.service_order_id and b.estado in ('publicada', 'fixada')
                          and b.tipo <> 'reserva' and b.dia > p_hoje)
       and not exists (select 1 from public.agenda_perguntas q
                        where q.tipo = 'concluir' and q.estado = 'aberta' and q.service_order_id = a.service_order_id)
     order by min(lower(a.periodo)), so.service_order_number collate "C"
  loop
    v_ult := v_ult || format('Hoje era o último dia do %s no plano: terminou? *concluiu %s* fecha a OS (saída e cobranças da condição).',
                             public._agenda_rotulo_da_os(o.os), coalesce(o.nome, o.numero));
  end loop;

  return jsonb_build_object('lig', to_jsonb(v_lig), 'som', to_jsonb(v_som), 'ids', v_ids, 'pendentes', v_pend,
                            'aguardando', v_ag, 'lancadas', v_lanc, 'ultimo', to_jsonb(v_ult));
end;
$function$;

comment on function public._agenda_dia_da_equipe(date) is
  'Agenda de Produção (Fase 3, P6): o que a linha dia do fechamento conta da equipe e da diária de hoje — {lig (frases pelos modos ligados: a diária que a agenda lançou pela resposta do técnico, quem confirmou, quem ainda não respondeu ao "como foi hoje?"), som (o que a sombra diria), ids (as ações diaria que a linha conta), pendentes [{nome, meios}] (diaristas do plano sem confirmação: só o *dia feito* lança), aguardando, lancadas [{nome, fracao}], ultimo (o último dia da OS no plano: *concluiu <nome>*)}. O dono não tem diária e não entra.';

-- As linhas da agenda no fechamento: [{tipo, texto, perda (0–100), pergunta_id, acao_ids, modo}], da maior perda para a
-- menor. tipo: decisao (crítica: 100 se perde até amanhã útil, 80 até 2 dias úteis, 50 depois), dia (a conferência de
-- hoje e o que mudou sozinho: 70), semana (a publicação da quinta: 60), mudancas (o que mudou sozinho sem conferência:
-- 40), pergunta (chegou?, parada?, o que falta?, quantos dias?: 30, uma só, a que perde primeiro, com "e mais N em
-- *agenda pendências*"). modo = 'ligado' só quando o registro é de ligado E o modo que o governa está ligado agora
-- (decisão, semana e mudanças: modo_proposta; conferência e perguntas: modo_vigia); o resto é 'sombra' (o que diria).
-- A janela das mudanças: o que ainda não foi contado nos últimos 7 dias (o fechamento que não saiu não as perde).
-- FASE 3: diaria (a pergunta crítica da diária: 50, ou 80 com 2 dias úteis sem resposta; modo_diaria), conclusao (o que
-- o gestor concluiu pela palavra do técnico: 45; modo_proposta), ppc (o último dia útil da semana: 55; modo_vigia),
-- comissao (o 1º dia útil do mês: 20; modo_vigia); a linha dia ganha a equipe, a diária e o último dia da OS.
-- Corpo de 20261025100500 copiado; as mudanças estão marcadas "-- FASE 3:".
create or replace function public._agenda_linhas_do_fechamento(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  c_max   constant int := 480;   -- estrutural: uma linha da agenda no fechamento
  -- FASE 3: o fim do texto da conferência da vigia (é o que a linha dia troca quando tem o que contar da equipe)
  c_cauda constant text := ' Foi isso? Responda *dia feito* ou conte o que mudou.';
  v_ini   date;
  v_am1   date;
  v_am2   date;
  v_out   jsonb := '[]'::jsonb;
  q       record;
  g       jsonb;
  v_m     jsonb;
  v_ms    jsonb;
  v_conf  record;
  v_txts  text[];
  v_ids   jsonb;
  v_txt   text;
  v_mod   text;
  v_n     int;
  k       int;
  m       text;
  -- FASE 3
  v_eq    jsonb;
  v_base  text;
  v_dia   text;
  v_som   text;
  v_extra text;
  v_cauda text;
  v_pend  jsonb;
  v_tec   text;
  v_cob   text;
  v_ppc   jsonb;
  v_com   jsonb;
begin
  if p_hoje is null then
    raise exception 'agenda: sem o dia de hoje' using errcode = '22004';
  end if;
  if cf.modo_proposta = 'desligado' and cf.modo_vigia = 'desligado' then
    return '[]'::jsonb;
  end if;
  v_ini := p_hoje - 6;
  v_am1 := public.agenda_somar_du(p_hoje, 1);
  v_am2 := public.agenda_somar_du(p_hoje, 2);

  -- (a) as decisões críticas abertas
  -- FASE 3: menos a da diária, que tem a linha dela (b2)
  for q in select x.* from public.agenda_perguntas x where x.critica and x.estado = 'aberta' and x.tipo <> 'diaria'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'decisao',
      'texto', 'Agenda, preciso de você. ' || q.texto || ' Me responda aqui.',
      'perda', case when q.perda_em is not null and q.perda_em <= v_am1 then 100
                    when q.perda_em is not null and q.perda_em <= v_am2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 3 (a2): a diária que diverge do plano (crítica): as opções, a recomendação e as palavras que respondem.
  -- A perda: o banco não sabe quando o acerto fecha (o dono fecha quando quer); com 2 dias úteis sem resposta, 80.
  for q in select x.* from public.agenda_perguntas x where x.tipo = 'diaria' and x.estado = 'aberta'
            order by x.perda_em nulls last, x.criada_em, x.id loop
    v_out := v_out || jsonb_build_object('tipo', 'diaria',
      'texto', 'Diária, preciso de você: ' || public._agenda_texto_da_diaria(q.id),
      'perda', case when public.agenda_du_entre(coalesce(q.dia, q.perda_em, p_hoje), p_hoje) >= 2 then 80 else 50 end,
      'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when q.modo = 'ligado' and cf.modo_diaria = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- (b) o que mudou sozinho (de verdade e na sombra), ainda não contado
  v_m := public._agenda_mudancas(v_ini, p_hoje, true, true, null);
  v_ms := public._agenda_mudancas(v_ini, p_hoje, false, true, null);

  -- (c) a semana publicada
  for g in select x from jsonb_array_elements(v_m) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', (g ->> 'desfazivel')::boolean, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids',
      'modo', case when cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;
  for g in select x from jsonb_array_elements(v_ms) x where x ->> 'tipo' = 'publicacao' loop
    v_out := v_out || jsonb_build_object('tipo', 'semana',
      'texto', public._agenda_linha_da_semana((g ->> 'proposta_id')::uuid, g -> 'acao_ids', false, p_hoje),
      'perda', 60, 'pergunta_id', null, 'acao_ids', g -> 'acao_ids', 'modo', 'sombra');
  end loop;

  -- (d) a conferência de hoje, com o que mudou sozinho; sem ela, o que mudou numa linha só
  select x.* into v_conf from public.agenda_perguntas x
   where x.tipo = 'conferencia' and x.estado = 'aberta' and x.dia = p_hoje
   order by (x.modo = 'ligado') desc, x.criada_em desc, x.id desc limit 1;
  -- FASE 3: o que a equipe confirmou, a diária que a agenda lançou, quem falta confirmar e o último dia da OS
  v_eq := public._agenda_dia_da_equipe(p_hoje);
  v_pend := v_eq -> 'pendentes';
  v_extra := nullif(array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'lig') x
                                          union all select x from jsonb_array_elements_text(v_eq -> 'ultimo') x), ' '), '');
  for m in select unnest(array['ligado', 'sombra']) loop
    v_txts := array(select public._agenda_mudanca_texto(x, false)
                      from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o)
                     where x ->> 'tipo' = 'acao' order by o);
    v_ids := coalesce((select jsonb_agg(y order by o, o2)
                         from jsonb_array_elements(case when m = 'ligado' then v_m else v_ms end) with ordinality t(x, o),
                              jsonb_array_elements(x -> 'acao_ids') with ordinality u(y, o2)
                        where x ->> 'tipo' = 'acao'), '[]'::jsonb);
    v_mod := case when m = 'ligado' and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end;
    if v_conf.id is not null and v_conf.modo = m then
      -- FASE 3: o texto do dia com a equipe. Sem nada a contar, é o da conferência, byte a byte.
      v_dia := v_conf.texto;
      if v_extra is not null or jsonb_array_length(v_pend) > 0 then
        v_base := case when right(v_conf.texto, char_length(c_cauda)) = c_cauda
                       then left(v_conf.texto, char_length(v_conf.texto) - char_length(c_cauda)) else v_conf.texto end;
        v_cauda := case
          when jsonb_array_length(v_pend) = 1
            then format(' Foi isso para o %s? *dia feito* lança a %s dele, ou conte o que mudou.', v_pend -> 0 ->> 'nome',
                        case when (v_pend -> 0 ->> 'meios')::int = 1 then 'meia diária' else 'diária' end)
          when jsonb_array_length(v_pend) > 1
            then format(' Foi isso para %s? *dia feito* lança as diárias deles, ou conte o que mudou.',
                        public._agenda_lista(array(select 'o ' || (e ->> 'nome') from jsonb_array_elements(v_pend) with ordinality t(e, o)
                                                    order by o), null))
          when (v_eq ->> 'aguardando')::int > 0 and cf.modo_diaria = 'ligado' then ' Foi isso? *dia feito* lança agora.'
          else c_cauda end;
        v_dia := v_base || coalesce(' ' || v_extra, '') || v_cauda;
      end if;
      v_ids := v_ids || (v_eq -> 'ids');
      for k in reverse cardinality(v_txts) .. 0 loop
        v_txt := v_dia
                 || case when k > 0 then ' Mudei sozinho: ' || array_to_string(v_txts[1:k], ' ')
                                         || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end
                         when cardinality(v_txts) > 0 then format(' Mudei sozinho %s: *o que mudou* mostra.',
                                                                   public._agenda_plural(cardinality(v_txts), 'coisa', 'coisas'))
                         else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', v_txt, 'perda', 70, 'pergunta_id', v_conf.id, 'acao_ids', v_ids,
        'modo', case when v_conf.modo = 'ligado' and cf.modo_vigia = 'ligado' and v_mod = 'ligado' then 'ligado' else 'sombra' end);
      -- FASE 3: o que a sombra da equipe e da diária diria, só no detalhe
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_som := v_dia || ' ' || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' ');
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_som, c_max), 'perda', 70,
                                             'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    elsif cardinality(v_txts) > 0 then
      for k in reverse cardinality(v_txts) .. 1 loop
        v_txt := 'Agenda, mudei sozinho. ' || array_to_string(v_txts[1:k], ' ')
                 || case when k < cardinality(v_txts) then format(' (e mais %s em *o que mudou*)', cardinality(v_txts) - k) else '' end;
        exit when char_length(v_txt) <= c_max;
      end loop;
      v_out := v_out || jsonb_build_object('tipo', 'mudancas', 'texto', v_txt, 'perda', 40, 'pergunta_id', null, 'acao_ids', v_ids,
                                           'modo', v_mod);
    end if;
  end loop;
  -- a conferência na sombra sem nada a contar junto, ou de um modo sem mudança (o laço acima já cobriu quem teve)
  -- (nada a fazer: o laço passa pelos dois modos)

  -- FASE 3 (d1): sem a conferência aberta (todos confirmaram), o dia com o que a equipe e a diária contam numa linha
  -- própria: a diária que a agenda lançou ("*diária Roberto meia* corrige") e o último dia da OS.
  if v_conf.id is null and (v_extra is not null or jsonb_array_length(v_eq -> 'som') > 0) then
    v_base := public._agenda_texto_do_dia(p_hoje);
    if v_base is not null then
      v_cauda := case when jsonb_array_length(v_eq -> 'lancadas') > 0
                      then format(' *diária %s %s* corrige.', v_eq -> 'lancadas' -> 0 ->> 'nome',
                                  case when (v_eq -> 'lancadas' -> 0 ->> 'fracao')::numeric = 1 then 'meia' else 'inteira' end)
                      else '' end;
      if v_extra is not null then
        v_out := v_out || jsonb_build_object('tipo', 'dia', 'texto', public._agenda_corta(v_base || ' ' || v_extra || v_cauda, c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', v_eq -> 'ids',
          'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
      end if;
      if jsonb_array_length(v_eq -> 'som') > 0 then
        v_out := v_out || jsonb_build_object('tipo', 'dia',
          'texto', public._agenda_corta(v_base || coalesce(' ' || v_extra, '') || ' '
                                        || array_to_string(array(select x from jsonb_array_elements_text(v_eq -> 'som') x), ' '), c_max),
          'perda', 70, 'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', 'sombra');
      end if;
    end if;
  end if;

  -- FASE 3 (d2): o que o gestor concluiu pela palavra do técnico (o técnico disse que terminou e era o último dia do
  -- plano), ainda não contado: a cobrança que a conclusão disse e o *desfaz* pelo número (a OS saiu da carteira).
  for q in select x.* from public.agenda_acoes x
            where x.tipo = 'concluir' and x.origem = 'equipe' and x.contada_em is null and x.desfeita_em is null
              and x.dia between v_ini and p_hoje
            order by x.criada_em, x.id loop
    v_tec := (select public._agenda_nome_curto(py.name) from public.agenda_equipe_mensagens em
                join public.payees py on py.id = em.payee_id where em.acao_id = q.id
               order by em.resposta_em desc nulls last limit 1);
    if q.executada then
      v_cob := regexp_replace(q.texto, '^[^—]* — saída [^.]*\.\s*', '');
      if q.dia <> p_hoje then
        v_cob := replace(replace(v_cob, 'vencer hoje', 'vencer ' || public._dia_curto(q.dia)), 'vence hoje', 'vence ' || public._dia_curto(q.dia));
      end if;
      v_txt := format('Concluí o %s%s: o %s disse que terminou e era o último dia do plano.%s *desfaz %s* reabre.',
                      public._agenda_rotulo_da_os(q.service_order_id),
                      case when q.dia <> p_hoje then ' ' || public._dia_curto(q.dia) else '' end,
                      coalesce(v_tec, 'técnico'), coalesce(' ' || nullif(v_cob, q.texto), ''),
                      (select so.service_order_number from public.service_orders so where so.id = q.service_order_id));
    else
      v_txt := q.texto;
    end if;
    v_out := v_out || jsonb_build_object('tipo', 'conclusao', 'texto', public._agenda_corta(v_txt, c_max), 'perda', 45,
      'pergunta_id', null, 'acao_ids', jsonb_build_array(q.id),
      'modo', case when q.executada and cf.modo_proposta = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- (e) uma pergunta de fato, a que perde primeiro (cada pergunta aparece em até perguntas_vezes_max fechamentos)
  -- FASE 3: entram também concluir, entrega, equipe_resposta e diaria_ligar (não críticas)
  for m in select unnest(array['ligado', 'sombra']) loop
    select count(*) into v_n from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       and x.mostrada_vezes < cf.perguntas_vezes_max;
    continue when v_n = 0;
    select x.* into q from public.agenda_perguntas x
     where not x.critica and x.estado = 'aberta' and x.modo = m and x.tipo <> 'conferencia'
       and x.mostrada_vezes < cf.perguntas_vezes_max
     order by x.perda_em nulls last, x.criada_em, x.id limit 1;
    v_out := v_out || jsonb_build_object('tipo', 'pergunta',
      'texto', 'Agenda: ' || q.texto || case when v_n > 1 then format(' (e mais %s em *agenda pendências*)', v_n - 1) else '' end,
      'perda', 30, 'pergunta_id', q.id, 'acao_ids', '[]'::jsonb,
      'modo', case when m = 'ligado' and cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end loop;

  -- FASE 3 (f): o PPC no último dia útil da semana (sexta; com feriado, o dia útil antes), se a semana teve compromisso
  v_ppc := public.agenda_ppc(p_hoje, p_hoje);
  if (v_ppc ->> 'ultimo_dia_util')::boolean and (v_ppc ->> 'compromissos')::int > 0 and v_ppc ->> 'linha' is not null then
    v_out := v_out || jsonb_build_object('tipo', 'ppc', 'texto', public._agenda_corta(v_ppc ->> 'linha', c_max), 'perda', 55,
      'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
  end if;

  -- FASE 3 (g): a comissão do mês que fechou, no 1º dia útil do mês (só a conta: nada é pago). Quem não pode ver a
  -- comissão (42501) não ganha a linha.
  if p_hoje = public.agenda_somar_du(make_date(extract(year from p_hoje)::int, extract(month from p_hoje)::int, 1), 0) then
    begin
      v_com := public.comissao_resumo_do_mes(null, p_hoje);
    exception when sqlstate '42501' then
      v_com := null;
    end;
    if coalesce((v_com ->> 'primeiro_dia_util')::boolean, false) and nullif(v_com ->> 'linha', '') is not null then
      v_out := v_out || jsonb_build_object('tipo', 'comissao', 'texto', v_com ->> 'linha', 'perda', 20,
        'pergunta_id', null, 'acao_ids', '[]'::jsonb, 'modo', case when cf.modo_vigia = 'ligado' then 'ligado' else 'sombra' end);
    end if;
  end if;

  return coalesce((select jsonb_agg(x order by (x ->> 'perda')::int desc, x ->> 'tipo', x ->> 'texto')
                     from jsonb_array_elements(v_out) x), '[]'::jsonb);
end;
$function$;

comment on function public._agenda_linhas_do_fechamento(date) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6): as linhas da agenda no fechamento das 17:30 — [{tipo (decisao|diaria|dia|ppc|semana|conclusao|mudancas|pergunta|comissao), texto, perda, pergunta_id, acao_ids, modo}] da maior perda para a menor (decisão 100/80/50 pela perda_em; dia 70; semana 60; ppc 55; diaria 50 ou 80 com 2 dias úteis sem resposta; conclusao 45; mudanças 40; pergunta 30; comissao 20). FASE 3: a linha dia conta o que a equipe confirmou, a diária que a agenda lançou ("*diária Roberto meia* corrige"), quem falta confirmar ("Foi isso para o João? *dia feito* lança a meia diária dele") e o último dia da OS (*concluiu <nome>*); sem nada disso, sai byte a byte a da Fase 2. diaria = a pergunta crítica da diária com as opções e as palavras (modo_diaria); conclusao = o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número (modo_proposta); ppc = agenda_ppc().linha no último dia útil da semana com compromisso (modo_vigia); comissao = comissao_resumo_do_mes().linha no 1º dia útil do mês (modo_vigia). modo ligado só com o registro em ligado e o modo que o governa ligado agora; o resto sombra (o que diria; vai ao detalhe). O secretário mostra as ligadas que cabem nas vagas (REGRAS.maxManha − as que ficaram) e registra o que saiu (agenda_fechamento_registrar).';

-- ── 4. Os focos novos da agenda_ver ─────────────────────────────────────────────────────────────────────

-- "o que você precisa de mim?" (corpo de 20261025100500 copiado; a mudança marcada "-- FASE 3:"): a decisão da diária
-- vem com as opções, a recomendação e as palavras (a pergunta dela não as traz no texto, como a do motor traz).
create or replace function public._agenda_ver_decisoes(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_dec   jsonb := public.agenda_decisoes_abertas(p_agora);
  v_l     text[] := '{}';
  v_outra text[];
  v_som   text[];
  e       jsonb;
begin
  for e in select x from jsonb_array_elements(v_dec) x loop
    -- FASE 3: a da diária com as opções, a recomendação e as palavras
    v_l := v_l || format('Decisão %s: %s', e ->> 'n',
                         case when e ->> 'tipo' = 'diaria' then public._agenda_texto_da_diaria((e ->> 'id')::uuid) else e ->> 'texto' end);
  end loop;
  v_outra := array(select q.texto from public.agenda_perguntas q
                    where not q.critica and q.estado = 'aberta' and q.modo = 'ligado'
                      and (q.expira_em is null or q.expira_em > p_agora)
                    order by q.perda_em nulls last, q.criada_em, q.id);
  if jsonb_array_length(v_dec) > 0 then
    v_l := array[case when jsonb_array_length(v_dec) = 1 then 'Uma decisão espera você na agenda:'
                      else format('%s decisões esperam você na agenda:', jsonb_array_length(v_dec)) end]
           || v_l
           || 'Para responder, diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.'::text;
  end if;
  if cardinality(v_outra) > 0 then
    v_l := v_l || array(select 'Também quero saber: ' || x from unnest(v_outra) with ordinality u(x, o) order by o);
  end if;
  if cardinality(v_l) = 0 then
    v_som := array(select q.texto from public.agenda_perguntas q
                    where q.estado = 'aberta' and q.modo = 'sombra' and (q.expira_em is null or q.expira_em > p_agora)
                    order by q.critica desc, q.perda_em nulls last, q.criada_em, q.id);
    if cardinality(v_som) > 0 and (cf.modo_proposta = 'sombra' or cf.modo_vigia = 'sombra') then
      v_l := array['Em teste (nada foi perguntado de verdade): eu perguntaria isto.']
             || array(select '• ' || x from unnest(v_som) with ordinality u(x, o) order by o);
    else
      v_l := array['Nada esperando você na agenda agora.'];
    end if;
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('decisoes', v_dec, 'outras', cardinality(v_outra)));
end;
$function$;

comment on function public._agenda_ver_decisoes(date, timestamptz) is
  'Agenda de Produção (Fase 2, P5; Fase 3, P6: a da diária com as opções e as palavras): agenda_ver foco decisoes — as decisões críticas abertas numeradas por agenda_decisoes_abertas ("Decisão 1: <a pergunta com as opções e a recomendação>"), como responder, e o que mais a agenda quer saber (chegou?, parada?, o que falta?), uma linha cada; sem nada em ligado, o que a sombra perguntaria ("Em teste"); nada = "Nada esperando você na agenda agora.". {ok, texto, dados{decisoes, outras}}.';

-- O mês que o dono disse, para a comissão: "outubro", "outubro de 2026", "10/2026", "mês passado", "este mês". Vazio,
-- "mês" ou "do mês" = null (comissao_resumo_do_mes decide: o mês corrente, ou o anterior até o 1º dia útil). O nome do
-- mês sem ano é o último que já começou (em janeiro, "dezembro" é o do ano passado). Não entendeu = 22007 com a frase.
create or replace function public._agenda_mes_dito(p_texto text, p_hoje date)
 returns date
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c_meses constant text[] := array['janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho', 'julho', 'agosto',
                                   'setembro', 'outubro', 'novembro', 'dezembro'];
  v      text := public._agenda_normal(p_texto);
  v_mes0 date := make_date(extract(year from p_hoje)::int, extract(month from p_hoje)::int, 1);
  m      text[];
  v_n    int;
  v_ano  int;
begin
  if p_hoje is null then
    raise exception '_agenda_mes_dito: sem o dia de hoje' using errcode = '22004';
  end if;
  v := btrim(regexp_replace(v, '^(?:(?:a|o|da|do|de|em|no|na)\s+)?(?:comissao\s+)?', ''));
  v := btrim(regexp_replace(v, '^(?:da|do|de|em|no|na)\s+', ''));
  if v in ('', 'mes') then
    return null;
  end if;
  if v in ('este mes', 'esse mes', 'deste mes', 'desse mes', 'neste mes', 'nesse mes', 'mes atual', 'o mes atual') then
    return v_mes0;
  end if;
  if v in ('mes passado', 'o mes passado', 'ultimo mes', 'o ultimo mes', 'mes anterior', 'o mes anterior') then
    return (v_mes0 - interval '1 month')::date;
  end if;
  m := regexp_match(v, '^([a-z]+)(?:\s+(?:de\s+)?(\d{4}))?$');
  if m is not null and m[1] = any (c_meses) then
    v_n := array_position(c_meses, m[1]);
    v_ano := coalesce(m[2]::int, extract(year from p_hoje)::int);
    if m[2] is null and make_date(v_ano, v_n, 1) > v_mes0 then
      v_ano := v_ano - 1;
    end if;
    return make_date(v_ano, v_n, 1);
  end if;
  m := regexp_match(v, '^(\d{1,2})/(\d{2}|\d{4})$');
  if m is not null and m[1]::int between 1 and 12 then
    v_ano := case when char_length(m[2]) = 2 then 2000 + m[2]::int else m[2]::int end;
    return make_date(v_ano, m[1]::int, 1);
  end if;
  raise exception 'Não entendi o mês "%". Diga o mês pelo nome (por exemplo, "outubro") ou "mês passado".', btrim(coalesce(p_texto, ''))
    using errcode = '22007';
end;
$function$;

comment on function public._agenda_mes_dito(text, date) is
  'Agenda de Produção (Fase 3, P6): o 1º dia do mês que o dono disse para a comissão ("outubro", "outubro de 2026", "10/2026", "mês passado", "este mês"); vazio, "mês" e "do mês" = null (o resumo decide); o nome sem ano é o último que já começou. Não entendeu = 22007 com a frase ao dono.';

-- "como foi a semana?": o PPC da semana do período (sem período, a de hoje).
create or replace function public._agenda_ver_ppc(p_dia date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  r jsonb;
begin
  if (public._agenda_cfg()).modo_proposta = 'desligado' then
    return jsonb_build_object('ok', true, 'texto', 'A agenda automática está desligada: não há semana publicada para medir.',
                              'dados', '{}'::jsonb);
  end if;
  r := public.agenda_ppc(coalesce(p_dia, p_hoje), p_hoje);
  return jsonb_build_object('ok', true, 'texto', r ->> 'texto', 'dados', r - 'texto');
end;
$function$;

comment on function public._agenda_ver_ppc(date, date) is
  'Agenda de Produção (Fase 3, P6): agenda_ver foco ppc — o texto de agenda_ppc da semana de p_dia ("Semana de 03 a 06/11 (seg 02 é Finados): 4 de 5 dias de serviço cumpridos (80%; a meta é 70%). Não cumprido: … Sem conferência: …"); com a agenda automática desligada, diz que não há semana publicada. {ok, texto, dados}.';

-- "as diárias da semana": as que a agenda lançou (a última de cada pessoa e dia, com a correção) e as perguntas abertas.
create or replace function public._agenda_ver_diarias(p_de date, p_ate date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_seg  date := coalesce(p_de, p_hoje - (extract(isodow from p_hoje)::int - 1));
  v_fim  date := coalesce(p_ate, coalesce(p_de, p_hoje - (extract(isodow from p_hoje)::int - 1)) + 5);
  v_exe  boolean := cf.modo_diaria = 'ligado';
  v_lanc text[];
  v_perg text[];
  v_lig  text[];
  v_l    text[];
begin
  if cf.modo_diaria = 'desligado' then
    return jsonb_build_object('ok', true, 'texto', 'A diária automática está desligada: quem lança a diária é você, como sempre.',
                              'dados', '{}'::jsonb);
  end if;
  -- a última ação de cada pessoa e dia (a correção do dono vale sobre o que a agenda lançou), sem as desfeitas
  v_lanc := array(
    select x.texto || case when x.fracao is not null and x.executada
                           then format(' *diária %s %s* corrige.', x.nome, case when x.fracao = 1 then 'meia' else 'inteira' end)
                           else '' end
      from (select distinct on (a.payee_id, (a.depois ->> 'dia')::date)
                   a.texto, a.executada, (a.depois ->> 'fracao')::numeric as fracao, (a.depois ->> 'dia')::date as dia,
                   public._agenda_nome_curto(py.name) as nome, a.desfeita_em
              from public.agenda_acoes a
              join public.payees py on py.id = a.payee_id
             where a.tipo = 'diaria' and a.executada = v_exe
               and (a.depois ->> 'dia')::date between v_seg and v_fim
             order by a.payee_id, (a.depois ->> 'dia')::date, a.criada_em desc, a.id desc) x
     where x.desfeita_em is null
     order by x.dia, x.nome);
  v_perg := array(select 'Preciso de você: ' || public._agenda_texto_da_diaria(q.id)
                    from public.agenda_perguntas q
                   where q.tipo = 'diaria' and q.estado = 'aberta' and q.modo = case when v_exe then 'ligado' else 'sombra' end
                   order by q.dia, q.criada_em, q.id);
  v_lig := array(select 'Também quero saber: ' || q.texto
                   from public.agenda_perguntas q
                  where q.tipo = 'diaria_ligar' and q.estado = 'aberta' and q.modo = case when v_exe then 'ligado' else 'sombra' end
                  order by q.dia, q.criada_em, q.id);
  if cardinality(v_lanc) + cardinality(v_perg) + cardinality(v_lig) = 0 then
    v_l := array[format('Nenhuma diária %s pela agenda de %s a %s.', case when v_exe then 'lançada' else 'que eu lançaria (em teste)' end,
                        public._dia_curto(v_seg), public._dia_curto(v_fim))];
  else
    v_l := array[case when v_exe then format('Diárias que a agenda lançou de %s a %s:', public._dia_curto(v_seg), public._dia_curto(v_fim))
                      else format('Em teste (nada foi lançado): de %s a %s, eu lançaria:', public._dia_curto(v_seg), public._dia_curto(v_fim)) end]
           || array(select '• ' || x from unnest(v_lanc) with ordinality u(x, o) order by o)
           || v_perg || v_lig;
    if cardinality(v_lanc) = 0 then
      v_l := v_l[2:];
    end if;
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('de', v_seg, 'ate', v_fim, 'lancadas', cardinality(v_lanc),
                                                        'perguntas', cardinality(v_perg) + cardinality(v_lig)));
end;
$function$;

comment on function public._agenda_ver_diarias(date, date, date) is
  'Agenda de Produção (Fase 3, P6): agenda_ver foco diarias — as diárias que a agenda lançou no período (sem período, a semana de hoje; a última ação de cada pessoa e dia, sem as desfeitas, com *diária <nome> meia|inteira* corrige) e as perguntas abertas (a crítica com as opções e as palavras; a de ligar à OS); em sombra, o que ela lançaria ("Em teste (nada foi lançado)"); desligada, diz que quem lança é o dono. {ok, texto, dados{de, ate, lancadas, perguntas}}.';

-- "os marcos do Lenine": entrada, início, conclusão e entrega (agenda_marcos_da_os), com o nome da OS.
create or replace function public._agenda_ver_marcos(p_os uuid, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  r jsonb := public.agenda_marcos_da_os(p_os, p_hoje);
begin
  return jsonb_build_object('ok', true, 'texto', public._agenda_rotulo_da_os(p_os) || ': ' || (r ->> 'texto') || '.',
                            'dados', r - 'texto');
end;
$function$;

comment on function public._agenda_ver_marcos(uuid, date) is
  'Agenda de Produção (Fase 3, P6): agenda_ver foco marcos (com a OS) — "Lenine (OS-00074): Entrada qua 22/09 · início ter 03/11 (29 du) · conclusão — · entrega —." (agenda_marcos_da_os). {ok, texto, dados}.';

-- "a comissão de outubro": o resumo do mês (só a conta: nada é pago). Só administrador e financeiro (o resto, 42501).
create or replace function public._agenda_ver_comissao(p_mes date, p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  r jsonb := public.comissao_resumo_do_mes(p_mes, p_hoje);
begin
  return jsonb_build_object('ok', true, 'texto', r ->> 'texto',
                            'dados', jsonb_build_object('mes', r -> 'mes', 'ate', r -> 'ate', 'primeiro_dia_util', r -> 'primeiro_dia_util',
                                                        'linha', r -> 'linha'));
end;
$function$;

comment on function public._agenda_ver_comissao(date, date) is
  'Agenda de Produção (Fase 3, P6): agenda_ver foco comissao — o texto de comissao_resumo_do_mes(p_mes, p_hoje) ("Comissão de outubro (até 24/10), em teste — nada foi pago. …"); p_mes null = o resumo decide. Só a conta. {ok, texto, dados{mes, ate, primeiro_dia_util, linha}}.';

-- "o que a equipe respondeu": hoje e o próximo dia útil, por pessoa da rotina — a ficha, a confirmação e o "como foi
-- hoje?" (mandei, respondeu "…", não respondeu, não mandei e por quê), confirmou ou avisou que não vem; e quem do plano
-- não tem a rotina (o dia dele é pelo *dia feito*).
create or replace function public._agenda_ver_equipe(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config := public._agenda_cfg();
  v_am   date := public.agenda_somar_du(p_hoje, 1);
  v_modo text := case when cf.modo_equipe = 'ligado' then 'ligado' else 'sombra' end;
  v_l    text[] := '{}';
  v_sem  text[];
  p      record;
  d      date;
  v_p    text[];
begin
  if cf.modo_equipe = 'desligado' then
    return jsonb_build_object('ok', true, 'texto', 'A rotina da equipe está desligada: eu não mando nada à equipe.', 'dados', '{}'::jsonb);
  end if;
  for p in
    select py.id, public._agenda_nome_curto(py.name) as nome
      from public.payees py
     where py.id in (select c.payee_id from public.agenda_equipe_contato c where c.recebe_rotina)
        or py.id in (select m.payee_id from public.agenda_equipe_mensagens m where m.dia in (p_hoje, v_am) and m.modo = v_modo)
     order by py.name, py.id
  loop
    foreach d in array array[p_hoje, v_am] loop
      v_p := array(
        select case m.tipo when 'ficha' then 'a ficha' when 'confirmar' then 'a confirmação' else 'o "como foi hoje?"' end || ': '
               || case m.estado
                    when 'respondida' then format('respondeu "%s" às %s%s', public._agenda_corta(m.resposta_texto, 60),
                                                  to_char(m.resposta_em at time zone 'America/Sao_Paulo', 'HH24:MI'),
                                                  case when (m.resposta_em at time zone 'America/Sao_Paulo')::date <> p_hoje
                                                       then ' de ' || public._dia_curto((m.resposta_em at time zone 'America/Sao_Paulo')::date) else '' end)
                    when 'enfileirada' then format('mandei às %s%s e ele ainda não respondeu',
                                                   to_char(m.enviar_em at time zone 'America/Sao_Paulo', 'HH24:MI'),
                                                   case when (m.enviar_em at time zone 'America/Sao_Paulo')::date <> p_hoje
                                                        then ' de ' || public._dia_curto((m.enviar_em at time zone 'America/Sao_Paulo')::date) else '' end)
                    when 'sem_resposta' then format('mandei às %s e ele não respondeu', to_char(m.enviar_em at time zone 'America/Sao_Paulo', 'HH24:MI'))
                    when 'recusada' then 'não mandei (' || case m.recusa_motivo when 'teto' then 'já tinha as 2 mensagens do dia'
                                                                 when 'janela' then 'fora do horário' when 'domingo' then 'domingo'
                                                                 when 'sem_telefone' then 'sem telefone' when 'sem_plano' then 'sem plano'
                                                                 when 'parou' then 'ele pediu para parar' else 'a rotina não estava ligada' end || ')'
                    else format('eu mandaria às %s', to_char(m.enviar_em at time zone 'America/Sao_Paulo', 'HH24:MI')) end
          from public.agenda_equipe_mensagens m
         where m.payee_id = p.id and m.dia = d and m.modo = v_modo and m.tipo in ('ficha', 'confirmar', 'como_foi')
         order by m.enviar_em, m.criada_em, m.tipo)
        || array(select case when x.situacao = 'confirmada' then 'confirmou o dia' when x.origem = 'agente' then 'não respondeu: tirei do plano' else 'avisou que não vem' end
                   from public.agenda_disponibilidade x
                  where x.payee_id = p.id and x.substituida_em is null and x.periodo @> d
                    and x.situacao in ('confirmada', 'indisponivel') and x.origem in ('agente', 'diarista')
                  order by x.criado_em desc limit 1);
      if cardinality(v_p) > 0 then
        v_l := v_l || format('%s — %s: %s.', public._agenda_dia_rotulo(d, p_hoje), p.nome, array_to_string(v_p, '; '));
      elsif exists (select 1 from public.agenda_alocacoes a where a.payee_id = p.id and a.dia = d
                       and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') then
        v_l := v_l || format('%s — %s: nada mandado ainda.', public._agenda_dia_rotulo(d, p_hoje), p.nome);
      end if;
    end loop;
  end loop;
  -- quem está no plano de hoje ou do próximo dia útil e não tem a rotina
  v_sem := array(select distinct public._agenda_nome_curto(py.name)
                   from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                  where a.dia in (p_hoje, v_am) and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                    and py.kind is distinct from 'socio'
                    and not exists (select 1 from public.agenda_equipe_contato c where c.payee_id = py.id and c.recebe_rotina)
                  order by 1);
  if cardinality(v_sem) > 0 then
    v_l := v_l || ('Sem a rotina (o dia é pelo *dia feito*): ' || public._agenda_lista(v_sem, null) || '.');
  end if;
  if cardinality(v_l) = 0 then
    v_l := array['A equipe não tem plano hoje nem no próximo dia útil.'];
  elsif cf.modo_equipe = 'sombra' then
    v_l := array['Em teste (nada foi mandado à equipe):'] || v_l;
  end if;
  return jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, cf.texto_max),
                            'dados', jsonb_build_object('hoje', p_hoje, 'proximo', v_am, 'modo', cf.modo_equipe));
end;
$function$;

comment on function public._agenda_ver_equipe(date) is
  'Agenda de Produção (Fase 3, P6): agenda_ver foco equipe — hoje e o próximo dia útil, por pessoa da rotina: a ficha, a confirmação e o "como foi hoje?" (mandei às HH:MI e ele ainda não respondeu; respondeu "…" às HH:MI; não mandei e por quê; em sombra, eu mandaria), confirmou ou avisou que não vem; e quem do plano não tem a rotina ("Sem a rotina (o dia é pelo *dia feito*): João."). Desligada: "A rotina da equipe está desligada". {ok, texto, dados}.';

-- ── 5. O despacho único: agenda_ver (recriada, mesma assinatura) ────────────────────────────────────────
-- Corpo de 20261025100500 copiado; as mudanças estão marcadas "-- FASE 3:".

create or replace function public.agenda_ver(p_autor uuid default null, p_periodo text default null,
                                             p_pessoa text default null, p_foco text default null, p_os text default null,
                                             p_simular jsonb default null, p_simular_aprovacao boolean default false,
                                             p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_foco    text := coalesce(nullif(btrim(lower(p_foco)), ''), 'tudo');
  v_rp      jsonb;
  v_payee   uuid;
  v_eh_dono boolean := true;
  v_de      date;
  v_ate     date;
  v_ro      jsonb;
  v_r       jsonb;
  v_pn      jsonb;
  v_rota    text;
  v_max     int;
  v_l       text[];
  k         int;
  -- FASE 2: a hora de agora (desfazer ainda vale? a decisão venceu?). now(); a bancada fixa com agenda.agora.
  v_agora   timestamptz := coalesce(nullif(current_setting('agenda.agora', true), '')::timestamptz, now());
  -- FASE 3: o livre de verdade (a simulação do motor) e o mês da comissão
  v_lv      jsonb;
  v_mes     date;
begin
  -- FASE 2: os focos decisoes, mudancas e plano
  -- FASE 3: os focos ppc, diarias, marcos, comissao e equipe
  if v_foco not in ('tudo', 'livre', 'o_que_fazer', 'riscos', 'material', 'atrasos', 'aprontar', 'decisoes', 'mudancas', 'plano',
                    'ppc', 'diarias', 'marcos', 'comissao', 'equipe') then
    raise exception 'agenda_ver: foco "%" não existe (tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao ou equipe)', p_foco
      using errcode = '22023';
  end if;
  if p_hoje is null then
    raise exception 'agenda_ver: sem o dia de hoje' using errcode = '22004';
  end if;
  -- Desligada (agenda_config.modo_leitura), a agenda de produção não responde: o assistente volta à agenda de antes
  -- (my_agenda: tarefas e compromissos do dono). Quem não lê agenda_config continua recebendo erro (nunca "livre").
  if (public._agenda_cfg()).modo_leitura = 'desligado' then
    return jsonb_build_object('ok', false, 'rota', 'desligada', 'desligada', true,
                              'texto', 'A agenda de produção está desligada agora.');
  end if;

  -- Pessoa: "eu" ou o nome. Quem não existe ou é ambíguo volta a frase do resolvedor (nunca um erro cru).
  if nullif(btrim(p_pessoa), '') is not null then
    v_rp := public.agenda_resolver_pessoa(p_pessoa, p_autor, p_hoje);
    if v_rp ->> 'status' <> 'ok' then
      return jsonb_build_object('ok', false, 'rota', 'pessoa', 'texto', v_rp ->> 'texto', 'pergunta', v_rp ->> 'texto',
                                'opcoes', coalesce(v_rp -> 'opcoes', '[]'::jsonb));
    end if;
    v_payee := (v_rp ->> 'payee_id')::uuid;
    v_eh_dono := coalesce((v_rp ->> 'eh_dono')::boolean, false);
  end if;

  -- Período: hoje, amanhã, semana, próxima semana ou o que o dono disse.
  -- FASE 3: a comissão lê o mês ("outubro", "mês passado"), não um período de dias.
  if v_foco = 'comissao' then
    begin
      v_mes := public._agenda_mes_dito(p_periodo, p_hoje);
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  else
    begin
      select x.de, x.ate into v_de, v_ate from public._agenda_periodo(p_periodo, p_hoje) x;
    exception when sqlstate '22007' then
      return jsonb_build_object('ok', false, 'rota', 'periodo', 'texto', sqlerrm, 'pergunta', sqlerrm);
    end;
  end if;

  if coalesce(p_simular_aprovacao, false) and nullif(btrim(p_os), '') is null then
    return jsonb_build_object('ok', false, 'rota', 'ctp',
      'texto', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).',
      'pergunta', 'Diga qual orçamento: o nome do cliente ou o número (por exemplo, ORÇ-00119).');
  end if;

  if nullif(btrim(p_os), '') is not null then
    v_ro := public.agenda_resolver_os(p_os, p_hoje, coalesce(p_simular_aprovacao, false));
    if v_ro ->> 'status' in ('nao_achei', 'ambiguo') then
      return jsonb_build_object('ok', false, 'rota', 'os', 'texto', v_ro ->> 'texto',
                                'pergunta', case when v_ro ->> 'status' = 'ambiguo' then v_ro ->> 'texto' end,
                                'opcoes', coalesce(v_ro -> 'opcoes', '[]'::jsonb));
    end if;
    if coalesce(p_simular_aprovacao, false) then
      v_rota := 'ctp';
      v_r := public.agenda_ctp((v_ro ->> 'id')::uuid, p_hoje);
    -- FASE 3: os marcos da OS (dentro ou fora da carteira: a concluída e a entregue já saíram dela)
    elsif v_foco = 'marcos' then
      v_rota := 'marcos';
      v_r := public._agenda_ver_marcos((v_ro ->> 'id')::uuid, p_hoje);
    elsif v_ro ->> 'status' = 'fora_da_carteira' then
      v_rota := 'os';
      v_r := jsonb_build_object('ok', true, 'texto', v_ro ->> 'texto', 'dados', jsonb_build_object('numero', v_ro ->> 'numero'));
    elsif v_foco = 'material' then
      v_rota := 'material_os';
      v_r := public.agenda_ver_material((v_ro ->> 'id')::uuid, p_hoje);
    else
      v_rota := 'os';
      v_r := public._agenda_ver_os((v_ro ->> 'id')::uuid, p_hoje);
    end if;
  -- FASE 3: os marcos pedem a OS
  elsif v_foco = 'marcos' then
    return jsonb_build_object('ok', false, 'rota', 'marcos',
      'texto', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).',
      'pergunta', 'Diga qual OS: o nome do cliente ou o número (por exemplo, OS-00074).');
  elsif p_simular is not null and jsonb_typeof(p_simular) = 'object' then
    v_rota := 'simular';
    v_r := public.agenda_simular((p_simular ->> 'dias')::numeric, coalesce(p_simular -> 'com_quem', '[]'::jsonb),
                                 nullif(p_simular ->> 'dono', ''), p_autor, p_hoje);
  -- FASE 2: o que espera o dono, o que mudou sozinho e o plano publicado
  elsif v_foco = 'decisoes' then
    v_rota := 'decisoes';
    v_r := public._agenda_ver_decisoes(p_hoje, v_agora);
  elsif v_foco = 'mudancas' then
    v_rota := 'mudancas';
    v_r := public._agenda_ver_mudancas(p_hoje, v_agora);
  elsif v_foco = 'plano' then
    v_rota := 'plano';
    v_r := public._agenda_ver_plano(v_de, v_ate, p_hoje, v_agora);
  -- FASE 3: a semana medida, as diárias da agenda, a comissão do mês e o que a equipe respondeu
  elsif v_foco = 'ppc' then
    v_rota := 'ppc';
    v_r := public._agenda_ver_ppc(v_de, p_hoje);
  elsif v_foco = 'diarias' then
    v_rota := 'diarias';
    v_r := public._agenda_ver_diarias(v_de, v_ate, p_hoje);
  elsif v_foco = 'comissao' then
    v_rota := 'comissao';
    v_r := public._agenda_ver_comissao(v_mes, p_hoje);
  elsif v_foco = 'equipe' then
    v_rota := 'equipe';
    v_r := public._agenda_ver_equipe(p_hoje);
  elsif v_foco = 'o_que_fazer' then
    if v_payee is not null and not v_eh_dono then
      v_rota := 'dia_da_pessoa';
      v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
    else
      v_rota := 'o_que_fazer';
      v_r := public.agenda_o_que_fazer(coalesce(v_payee, public._agenda_dono(p_autor)), p_hoje);
    end if;
  elsif v_foco in ('atrasos', 'riscos') then
    v_rota := 'atrasos';
    v_r := public.agenda_atrasos(p_hoje);
  elsif v_foco = 'material' then
    v_rota := 'material';
    v_r := public.agenda_ver_material(null, p_hoje);
  elsif v_foco = 'livre' then
    v_rota := 'livre';
    v_r := public.agenda_semana(null, null, p_hoje);
    -- FASE 3: com a agenda automática ligada, o livre de verdade sai da simulação do motor (fora disso, a projeção)
    if (public._agenda_cfg()).modo_proposta = 'ligado' then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
    end if;
    v_r := jsonb_build_object('ok', true,
      'texto', public._agenda_juntar(array[v_r #>> '{dados,textos,resumo}',
                                           case when v_lv ->> 'fonte' = 'simulacao' then v_lv ->> 'texto'
                                                else v_r #>> '{dados,textos,livre}' end],
                                     (select texto_max from public._agenda_cfg())),
      'dados', jsonb_build_object('fila', v_r #> '{dados,fila}', 'livre', v_r #> '{dados,livre}',
                                  'capacidade', v_r #> '{dados,capacidade}',
                                  'livre_de_verdade', coalesce(v_lv, jsonb_build_object('fonte', 'projecao'))));
  elsif v_foco = 'aprontar' then
    v_rota := 'aprontar';
    v_r := public.agenda_aprontar(p_hoje);
  elsif v_payee is not null and not v_eh_dono and (v_de is null or v_de = v_ate) then
    v_rota := 'dia_da_pessoa';
    v_r := public.agenda_dia_da_pessoa(v_payee, coalesce(v_de, p_hoje), p_hoje);
  elsif v_de is not null and v_de = v_ate then
    v_rota := 'dia';
    v_pn := public._agenda_painel(p_hoje);
    v_max := (v_pn ->> 'texto_max')::int;
    for k in reverse 5 .. 1 loop
      v_l := public._agenda_dia_de(v_pn, v_de, k);
      exit when char_length(public._agenda_juntar(v_l, null)) <= v_max;
    end loop;
    v_r := jsonb_build_object('ok', true, 'texto', public._agenda_juntar(v_l, v_max), 'dados', jsonb_build_object('dia', v_de));
  else
    v_rota := 'semana';
    v_r := public.agenda_semana(v_de, v_ate, p_hoje);
    -- FASE 3: com a agenda automática ligada, a frase do livre da semana é a da simulação do motor
    if (public._agenda_cfg()).modo_proposta = 'ligado' and nullif(v_r #>> '{dados,textos,livre}', '') is not null
       and position((v_r #>> '{dados,textos,livre}') in (v_r ->> 'texto')) > 0 then
      v_lv := public.agenda_livre_de_verdade(p_hoje, v_agora);
      if v_lv ->> 'fonte' = 'simulacao' then
        v_r := jsonb_set(v_r, '{texto}', to_jsonb(replace(v_r ->> 'texto', v_r #>> '{dados,textos,livre}', v_lv ->> 'texto')));
        v_r := jsonb_set(v_r, '{dados,livre_de_verdade}', v_lv);
      end if;
    end if;
  end if;

  return v_r || jsonb_build_object('rota', v_rota);
end;
$function$;

comment on function public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date) is 'Agenda de Produção (Fase 1, P4; Fase 2, P5; Fase 3, P6): o despacho ÚNICO da ferramenta agenda_ver e dos comandos sem IA. os + simular_aprovacao → agenda_ctp; FASE 3: os + foco marcos → os 4 marcos (agenda_marcos_da_os, também fora da carteira); foco marcos sem os → pede a OS; os + foco material → agenda_ver_material; os → a visão da OS; simular {dias, com_quem, dono} → agenda_simular; FASE 2: foco decisoes → as decisões numeradas (agenda_decisoes_abertas; FASE 3: a da diária com as opções e as palavras) e o que mais a agenda quer saber; mudancas → o que mudou sozinho desde ontem com *desfaz*; plano → o publicado do período dia a dia (sombra: "Em teste"); FASE 3: ppc → agenda_ppc da semana do período; diarias → as diárias que a agenda lançou e as perguntas abertas; comissao → comissao_resumo_do_mes do mês dito em periodo ("outubro", "mês passado"; só a conta, nada é pago); equipe → o que a equipe respondeu hoje e no próximo dia útil; foco o_que_fazer → agenda_o_que_fazer (pessoa que não é o dono: o dia dela); atrasos/riscos → agenda_atrasos; material → agenda_ver_material(null); livre → resumo + livre de agenda_semana (FASE 3: com modo_proposta ligado, o livre de verdade pela simulação do motor, agenda_livre_de_verdade); aprontar → agenda_aprontar; pessoa (não o dono) + 1 dia → agenda_dia_da_pessoa; hoje/amanhã → o dia + o bloco 2 resumido; resto → agenda_semana (em ''ligado'' o marcado é o plano; FASE 3: e a frase do livre é a da simulação). periodo: hoje, amanha, semana, proxima_semana ou o que o dono disse. Referência que não existe (OS, pessoa, data, mês) → {ok:false, texto:"Não encontrei …"/a pergunta}; foco fora da lista lança 22023. Devolve {ok, texto, dados, rota}.';

-- ── 6. A carona ─────────────────────────────────────────────────────────────────────────────────────────

-- No fim de uma resposta do assistente ao dono sobre UMA OS: no máximo uma pergunta aberta dela (crítica primeiro, depois
-- a que perde primeiro), uma vez por OS a cada carona_por_os_dias. null quando não cabe.
create or replace function public.agenda_carona(p_autor uuid, p_os text[], p_canal text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf    public.agenda_config := public._agenda_cfg();
  v_ids uuid[] := '{}';
  v_ro  jsonb;
  v_ref text;
  v_os  uuid;
  q     record;
begin
  if p_hoje is null or p_agora is null then
    raise exception 'agenda_carona: sem o dia ou a hora de agora' using errcode = '22004';
  end if;
  if p_canal is null or p_canal not in ('whatsapp', 'painel') then
    raise exception 'Por onde: "%" (whatsapp ou painel).', coalesce(p_canal, '') using errcode = '22023';
  end if;
  -- só com a vigia ligada (a pergunta de fato é dela) e só para o dono
  if cf.modo_vigia <> 'ligado' then
    return null;
  end if;
  if p_autor is null or not exists (select 1 from public.app_users u where u.id = p_autor and u.active and u.role = 'admin') then
    return null;
  end if;
  -- as OS como o turno citou (número, nome ou id), resolvidas aqui; ref ambígua = nada (pode ser outra OS)
  foreach v_ref in array coalesce(p_os, '{}'::text[]) loop
    continue when nullif(btrim(v_ref), '') is null;
    v_ro := public.agenda_resolver_os(left(btrim(v_ref), 80), p_hoje, false);
    if v_ro ->> 'status' = 'ambiguo' then
      return null;
    end if;
    if v_ro ->> 'status' in ('ok', 'fora_da_carteira') and not ((v_ro ->> 'id')::uuid = any (v_ids)) then
      v_ids := v_ids || (v_ro ->> 'id')::uuid;
    end if;
  end loop;
  if cardinality(v_ids) <> 1 then
    return null;
  end if;
  v_os := v_ids[1];
  -- uma carona por OS a cada carona_por_os_dias
  if exists (select 1 from public.agenda_perguntas x
              where (x.service_order_id = v_os or v_os = any (x.os_ids))
                and x.carona_em is not null and x.carona_em >= p_agora - make_interval(days => cf.carona_por_os_dias)) then
    return null;
  end if;
  select x.* into q from public.agenda_perguntas x
   where x.estado = 'aberta' and x.modo = 'ligado' and (x.service_order_id = v_os or v_os = any (x.os_ids))
     and (x.expira_em is null or x.expira_em > p_agora)
     and (x.critica or x.tipo in ('chegou', 'parada', 'estouro', 'duracao', 'material_conferir', 'concluir', 'entrega', 'diaria_ligar'))
   order by x.critica desc, x.perda_em nulls last, x.id
   limit 1;
  if q.id is null then
    return null;
  end if;
  -- a que já saiu hoje no fechamento não vai de novo
  if q.mostrada_via = 'fechamento' and (q.mostrada_em at time zone 'America/Sao_Paulo')::date = p_hoje then
    return null;
  end if;
  update public.agenda_perguntas
     set carona_em = p_agora, mostrada_vezes = least(mostrada_vezes + 1, 50), mostrada_em = p_agora, mostrada_via = 'conversa'
   where id = q.id;
  return jsonb_build_object('pergunta_id', q.id, 'os', v_os, 'tipo', q.tipo, 'texto', 'Aproveitando: ' || q.texto);
end;
$function$;

comment on function public.agenda_carona(uuid, text[], text, date, timestamptz) is
  'Agenda de Produção (Fase 3, P6): a carona — no fim de uma resposta do assistente ao DONO (admin ativo) sobre UMA OS (p_os = as OS como o turno citou: número, nome ou id, resolvidas por agenda_resolver_os; ambígua ou mais de uma = null), uma pergunta aberta em ligado dela (crítica primeiro, depois a de perda_em mais cedo; tipos chegou, parada, estouro, duracao, material_conferir, concluir, entrega, diaria_ligar ou crítica), nunca de novo se alguma pergunta da OS teve carona nos últimos carona_por_os_dias, nem a que já saiu hoje no fechamento; só com modo_vigia ligado. Marca carona_em, mostrada_vezes + 1 e mostrada_via conversa. {pergunta_id, os, tipo, texto: "Aproveitando: <a pergunta>"} ou null. Só service_role.';

-- As OS que as ferramentas de um turno do Claude Max tocaram (o erp-mcp registra; a entrega no ai-agent lê para a carona).
create or replace function public.ai_job_registrar_os(p_job_id uuid, p_os text[])
 returns boolean
 language plpgsql
 volatile
 security definer
 set search_path = ''
as $function$
declare
  atual   jsonb;
  v_lista jsonb;
begin
  if p_job_id is null or coalesce(cardinality(p_os), 0) = 0 then
    return false;
  end if;
  select j.metadata into atual
    from public.ai_jobs j
   where j.id = p_job_id and j.status = 'processing'
     and j.metadata->>'tipo' in ('agente_whatsapp', 'agente_painel', 'agente_ensaio')
   for update;
  if not found then
    return false;
  end if;
  -- sem repetir, na ordem em que apareceram, até 10 (é só para a carona: mais de uma OS já não tem carona)
  select coalesce(jsonb_agg(to_jsonb(b.x) order by b.o), '[]'::jsonb) into v_lista
    from (select a.x, min(a.o) as o
            from (select t.x, t.o from jsonb_array_elements_text(coalesce(atual->'os_do_turno', '[]'::jsonb)) with ordinality t(x, o)
                  union all
                  select left(btrim(u.y), 80), 1000 + u.o2 from unnest(p_os) with ordinality u(y, o2)
                   where nullif(btrim(u.y), '') is not null) a
           group by a.x
           order by min(a.o)
           limit 10) b;
  update public.ai_jobs j set metadata = atual || jsonb_build_object('os_do_turno', v_lista) where j.id = p_job_id;
  return true;
end;
$function$;

comment on function public.ai_job_registrar_os(uuid, text[]) is
  'Agenda de Produção (Fase 3, P6): o erp-mcp guarda no job do Claude Max (processing, agente_whatsapp/painel/ensaio) as OS que as ferramentas do turno tocaram (metadata.os_do_turno: sem repetir, até 10); a entrega do turno no ai-agent lê para a carona (agenda_carona). Só service_role.';

-- ── Portas ─────────────────────────────────────────────────────────────────────────────────────────────
-- Leituras e textos (invoker, STABLE/IMMUTABLE) e a definer que só lê (agenda_livre_de_verdade, que confere quem vê):
-- authenticated (o painel) e service_role (o WhatsApp, o fechamento); nunca anon.
revoke all on function
  public._agenda_mudancas(date, date, boolean, boolean, timestamptz),
  public._agenda_titulo_da_semana(date), public.agenda_ppc(date, date),
  public._agenda_texto_da_diaria(uuid),
  public._agenda_segunda_seguinte(date), public.agenda_livre_de_verdade(date, timestamptz),
  public._agenda_texto_do_dia(date), public._agenda_dia_da_equipe(date), public._agenda_linhas_do_fechamento(date),
  public._agenda_ver_decisoes(date, timestamptz), public._agenda_mes_dito(text, date), public._agenda_ver_ppc(date, date),
  public._agenda_ver_diarias(date, date, date), public._agenda_ver_marcos(uuid, date), public._agenda_ver_comissao(date, date),
  public._agenda_ver_equipe(date), public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)
  from public, anon;
grant execute on function
  public._agenda_mudancas(date, date, boolean, boolean, timestamptz),
  public._agenda_titulo_da_semana(date), public.agenda_ppc(date, date),
  public._agenda_texto_da_diaria(uuid),
  public._agenda_segunda_seguinte(date), public.agenda_livre_de_verdade(date, timestamptz),
  public._agenda_texto_do_dia(date), public._agenda_dia_da_equipe(date), public._agenda_linhas_do_fechamento(date),
  public._agenda_ver_decisoes(date, timestamptz), public._agenda_mes_dito(text, date), public._agenda_ver_ppc(date, date),
  public._agenda_ver_diarias(date, date, date), public._agenda_ver_marcos(uuid, date), public._agenda_ver_comissao(date, date),
  public._agenda_ver_equipe(date), public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)
  to authenticated, service_role;

-- A carona escreve (carona_em) e o registro do job: só o service_role (o ai-agent e o erp-mcp).
revoke all on function public.agenda_carona(uuid, text[], text, date, timestamptz) from public, anon, authenticated;
grant execute on function public.agenda_carona(uuid, text[], text, date, timestamptz) to service_role;
revoke all on function public.ai_job_registrar_os(uuid, text[]) from public, anon, authenticated;
grant execute on function public.ai_job_registrar_os(uuid, text[]) to service_role;
