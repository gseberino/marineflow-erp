-- Agenda de Produção — Fase 7b, correção 2 (20261101100850): o achado 26 da revisão da 7b, que é da 7a. NÃO aplicada.
--
-- ═══ DDL — OK NOMEADO ═══ (3 funções recriadas com as mesmas assinaturas; nenhuma tabela, coluna, lista, job ou dado)
-- Vai DEPOIS da 20261101100800 (a correção da revisão) e ANTES do dado 20261101100900. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7b/a26/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (o montador para se outra
-- migration a definir depois da origem), e as mudanças estão só nos blocos "-- FASE 7b: (correção 2, achado 26 da 7a) … -- FASE 7b: fim (correção 2)" e, dentro de um
-- bloco da 7b de antes, "-- (correção 2, achado 26 da 7a) … -- (correção 2: fim)" (só acréscimo: nenhuma linha de antes muda; tirados esses blocos,
-- o corpo é o da origem, byte a byte: o montador e o W0 de supabase/tests/agenda_fase77b_correcao2.sql conferem). O fecho de cima
-- começa por "-- FASE 7b: fim": os testes de cópia de antes, que tiram todos os blocos "-- FASE 7b:", tiram este junto.
--
-- POR QUE: assim que existir a linha dos dias do dono (origem dono, seg a sex — a resposta à pergunta padrao_do_dono:sem_dias, aberta
-- em produção, ou o publicar/exec/dono-campo-3010.sql), o motor marca o serviço de presença "o tempo todo" (a marina nova: o Lenine
-- OS-00074 na bancada, a Kalmar OS-00033 em produção) com o técnico e o dono juntos, como manda a correção 2 da 7a (com a regra
-- uma_pessoa, a pessoa da estimativa é o técnico e o dono vai junto). A revisão diária da 7a contava o turno do dono no "tem" de
-- _agenda_gestor_pessoa_meios como uma pessoa que trabalha: o Lenine, marcado com o Alex e você nos 6 dias, tinha 24 meios-dias de
-- gente contra os 12 que a estimativa pede, e a revisão cortava metade com "Lenine (OS-00074): o orçamento mudou e agora estimo 6
-- dias (eram 6). Tirei sex 13/11, seg 16/11 e ter 17/11." — falso (o orçamento não mudou) e em todos os modos da 7b (desligada, em
-- teste e ligada; com a 7b em teste ou ligada, a conta com o dk somava o dono do mesmo jeito). Em teste (a 7a de hoje), o mesmo corte
-- ia para o diário do gestor.
--
-- O CRITÉRIO (o mesmo nas três): o turno do dono num meio-dia com outra pessoa só conta como uma das pessoas que a estimativa pede
-- quando o molde (agenda_meios_da_os) o conta como uma delas: o turno inteiro (dono_turno) e, além disso, a equipe dita (ele nela), a
-- regra uma_pessoa desligada (a de antes da correção 2 da 7a) ou o diagnóstico e o comissionamento (o trabalho é dele). Fora disso,
-- ele vai junto — com a regra uma_pessoa e a presença o tempo todo (a correção 2 da 7a), e também quando o molde de agora não o tem
-- no turno (você disse "abre e fecha" depois de marcado com você o tempo todo: o plano não é refeito). Sozinho no meio-dia, ele conta.
--
-- O QUE MUDA:
--   1. _agenda_gestor_pessoa_meios (de 20261101100300): o tem — e a conta com o dk em teste — não conta o turno do dono que vai junto
--      nos meios-dias em que ele vai com alguém. Sozinho no meio-dia (o diagnóstico, o que ele fez sem o técnico), conta como antes.
--   2. _agenda_gestor_corte (de 20261101100500): o mesmo dono não conta como pessoa do meio-dia que sai (a estimativa que caiu de 6
--      para 4 dias tira os 2 últimos dias, com o técnico e você, e não 4) nem como o "junto" da dupla completada; e o texto é honesto:
--      com o plano sem meio-dia além da estimativa na forma do plano (sem a dupla por meio-dia, o total; com o dk, o precisa menos os
--      meios-dias de dupla do molde que o plano já tem com a 2ª pessoa — com a 7b ligada o total vem encurtado pela dupla, e o plano
--      de 1 pessoa passava dele sem o orçamento mudar), a sobra é de gente a mais, e o texto diz isso ("o plano tem mais gente do que a
--      minha estimativa (6 dias com 1 pessoa), então o serviço acaba antes (são as mesmas diárias)"), nunca "o orçamento mudou e agora
--      estimo 6 dias (eram 6)" nem, com a 7b ligada, "estimo 5 dias (eram 6)" com o orçamento intacto. Com o dk e o plano maior, "agora
--      estimo N" é o que o plano tem depois do corte inteiro (o plano de 1 pessoa cujo orçamento caiu de 6 para 4 dias: "estimo 4
--      dias", não o total da dupla, 3). A dupla completada da 7b continua com o texto dela.
--   3. _agenda_ver_gestor (de 20261101100800): no foco *agenda gestor*, o "Marquei nos últimos 7 dias" conta os dias de cada OS sem
--      o turno do dono que vai junto (o Lenine marcado com o Alex e você nos 6 dias dizia "Alex — 12 dias (estimativa minha)").
--
-- O QUE NÃO MUDA: com o dono contado pelo molde (o Rodrigo OS-00096 do diagnóstico e o Vanderlei OS-00069 do comissionamento; a 7a
-- desligada ou em teste fora da revisão, com a presença o tempo todo), sem ele num meio-dia com outra pessoa (o motor só o põe no turno
-- quando o molde manda) e, sem o dk, com o plano maior que a estimativa, as três são as de antes, byte a byte; as Fases 1 a 6 não
-- chamam nenhuma das três. Sem a linha do dono, o motor não põe o dono no turno, e nada muda (o W4 do teste prova nos 3 modos da 7b).
--
-- A REVISÃO DESTA CORREÇÃO (3 achados, 31/10): (1) o critério vinha só da regra uma_pessoa com a presença o tempo todo; com a presença
-- mudada para "abre e fecha" depois de marcado, o dono voltava a contar e a revisão cortava metade dos dias do técnico ("são as mesmas
-- diárias", falso) — agora o critério é o do molde (acima; o W5 do teste); (2) com a 7b ligada, o texto comparava pelo total encurtado
-- pela dupla — "o orçamento mudou" com o orçamento intacto e "estimo 3 dias" deixando 4 — (o W2 e o W3b com a 7b ligada); (3) o
-- roteiro do ligar da 7a (fila-do-dono/fase77a-publicar.md, passo 6) conferia 107 iguais no md5 da 7a, que a 7b muda em 23: fora do
-- banco (sql/wf7c2_md5_sem7b.sql).
--
-- Quem recriar depois uma destas funções copia DESTA migration (spec-fase7b §R4.6, fim).
--
-- DESFAZER: recriar cada função com o corpo da definição de antes (a 20261101100300 para _agenda_gestor_pessoa_meios, a
-- 20261101100500 para _agenda_gestor_corte e a 20261101100800 para _agenda_ver_gestor). As portas não mudam.

-- _agenda_gestor_pessoa_meios (de 20261101100300_agenda_fase7b_motor.sql)
create or replace function public._agenda_gestor_pessoa_meios(p_os uuid, p_hoje date, p_meios jsonb)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with p as (
    select coalesce((p_meios ->> 'pessoas_sugeridas')::int,
                    greatest(coalesce((p_meios #>> '{por_turno,manha,desejado}')::int, 0)
                             + case when coalesce((p_meios #>> '{dono_turno,manha}')::boolean, false) then 1 else 0 end, 1)) as pessoas
  )
  -- FASE 7b: (correção 2, achado 26 da 7a) o dono que vai junto: o turno dele só é uma das pessoas que a estimativa pede quando o molde
  -- o conta como uma delas — o turno inteiro (dono_turno) e, além disso, a equipe dita (ele nela), a regra uma_pessoa desligada (a de
  -- antes da correção 2 da 7a: o dono é uma das pessoas) ou o diagnóstico e o comissionamento (o trabalho é dele). Fora disso, ele vai
  -- junto: com a regra uma_pessoa e a presença o tempo todo (a correção 2 da 7a em agenda_meios_da_os: a pessoa da estimativa é o
  -- técnico), e também quando o molde de agora não o tem no turno (a presença mudou para "abre e fecha" depois de marcado com ele o
  -- tempo todo: o plano não é refeito). Nos meios-dias em que ele vai com alguém, o turno dele não entra: sem isso, o Lenine marcado
  -- com o Alex e você nos 6 dias tinha 24 contra 12, e a revisão cortava metade dizendo "o orçamento mudou". Sozinho no meio-dia, ele
  -- conta como antes. O "tem" conta as mesmas pessoas que o "precisa".
  , j as (
    select public._agenda_dono(null) as dono
     where p_meios ? 'dono_turno'
       and not ((coalesce((p_meios #>> '{dono_turno,manha}')::boolean, false) or coalesce((p_meios #>> '{dono_turno,tarde}')::boolean, false))
                and (coalesce((p_meios ->> 'equipe_dita')::boolean, true) or not public._agenda_gestor_regra('uma_pessoa')
                     or coalesce(p_meios ->> 'regra_motivo', '') in ('diagnóstico', 'comissionamento')))
  )
  -- FASE 7b: fim (correção 2)
  select jsonb_build_object(
           'pessoas', p.pessoas,
           'precisa', case when (p_meios ->> 'total') is null then null else (p_meios ->> 'total')::int * p.pessoas end,
           -- FASE 7b: (7b P4, R4.3(a)6) com a dupla por meio-dia (dk de agenda_meios_da_os) o que a estimativa pede não é total × pessoas
           -- (com a duração que conserva, o total já é menor): ligado, as diárias-pessoa do molde (dupla.pm: o bloco de 1 pessoa e o em
           -- dupla têm o mesmo, nada é cortado nem falta; a dupla completada depois corta o que ela encurtou); em teste, entre o de 1
           -- pessoa (total × pessoas) e o com a dupla acrescentada (dupla.pm): nem corte nem falta nessa faixa. A chave repetida vale
           -- (no jsonb, a última); sem dk, o de antes.
           'precisa', case when not (p_meios ? 'dk') or (p_meios ->> 'total') is null or (p_meios #>> '{dupla,pm}') is null
                             then case when (p_meios ->> 'total') is null then null else (p_meios ->> 'total')::int * p.pessoas end
                           when (public._agenda_cfg()).modo_dupla = 'ligado' then (p_meios #>> '{dupla,pm}')::int
                           else greatest((p_meios ->> 'total')::int * p.pessoas,
                                         least(floor((select coalesce(sum(case when a.resultado in ('cumprido', 'sem_registro') then 1
                                                                               when a.resultado = 'parcial' then 0.5
                                                                               when a.resultado = 'nao_cumprido' then 0
                                                                               else 1 end), 0)
                                                        from public.agenda_alocacoes a
                                                       where a.service_order_id = p_os and a.estado in ('publicada', 'fixada')
                                                         -- (correção 2, achado 26 da 7a) sem o turno do dono que vai junto (j)
                                                         and not (exists (select 1 from j where j.dono = a.payee_id)
                                                                  and exists (select 1 from public.agenda_alocacoes b
                                                                               where b.service_order_id = a.service_order_id and b.dia = a.dia and b.turno = a.turno
                                                                                 and b.payee_id is distinct from a.payee_id and b.estado in ('publicada', 'fixada')
                                                                                 and b.tipo <> 'reserva' and b.presenca = 'turno' and b.resultado is distinct from 'nao_cumprido'))
                                                         -- (correção 2: fim)
                                                         and a.tipo <> 'reserva' and a.presenca = 'turno'))::int,
                                               (p_meios #>> '{dupla,pm}')::int)) end,
           -- FASE 7b: fim
           'tem', (select trim_scale(coalesce(sum(case when a.resultado in ('cumprido', 'sem_registro') then 1
                                                     when a.resultado = 'parcial' then 0.5
                                                     when a.resultado = 'nao_cumprido' then 0
                                                     else 1 end), 0))
                     from public.agenda_alocacoes a
                    where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      -- FASE 7b: (correção 2, achado 26 da 7a) sem o turno do dono que vai junto (j)
                      and not (exists (select 1 from j where j.dono = a.payee_id)
                               and exists (select 1 from public.agenda_alocacoes b
                                            where b.service_order_id = a.service_order_id and b.dia = a.dia and b.turno = a.turno
                                              and b.payee_id is distinct from a.payee_id and b.estado in ('publicada', 'fixada')
                                              and b.tipo <> 'reserva' and b.presenca = 'turno' and b.resultado is distinct from 'nao_cumprido'))
                      -- FASE 7b: fim (correção 2)
                      and a.presenca = 'turno'))
    from p;
$function$;

comment on function public._agenda_gestor_pessoa_meios(uuid, date, jsonb) is
  'Agenda de Produção (Fase 7a, correção da revisão; achado 16): {pessoas, precisa, tem} da OS em pessoa-meio-dia — precisa = agenda_meios_da_os.total × as pessoas da estimativa (pessoas_sugeridas; com a equipe dita, as da manhã, com o dono quando fica o turno); tem = os meios-dias de turno de cada pessoa no plano vigente, fora a reserva (cumprido e sem registro 1, parcial meio, não cumprido 0, o resto 1). A revisão diária e o corte do gestor comparam por aqui: a dupla dita depois de marcar não vira corte. STABLE, invoker, sem grant. FASE 7b (P4, R4.3(a)6): com a dupla por meio-dia (p_meios com dk), precisa = dupla.pm (ligado: as diárias-pessoa do molde — o bloco de 1 pessoa do Lenine, 12, e o em dupla, 2 × 2 + 8, não cortam nem faltam; a dupla completada depois, 14, corta 2) ou, em teste, greatest(total × pessoas, least(floor(tem), dupla.pm)) (entre o de 1 pessoa, 12, e o com a dupla acrescentada, 14, nada a cortar nem a acrescentar). Sem dk, a de antes, byte a byte. CORREÇÃO 2 DA 7b (achado 26 da revisão da 7b, que é da 7a): o tem — e, com o dk em teste, a conta entre o de 1 pessoa e o da dupla — conta o turno do dono nos meios-dias em que ele vai com alguém só quando o molde o conta como uma das pessoas (o turno inteiro e, além disso, a equipe dita, a regra uma_pessoa desligada, o diagnóstico ou o comissionamento); fora disso ele vai junto (com a regra uma_pessoa e a presença o tempo todo, o critério da correção 2 da 7a em agenda_meios_da_os; e também com a presença mudada para "abre e fecha" depois de marcado com ele o tempo todo) e o turno dele não entra (sozinho no meio-dia, conta como antes). Com a linha dos dias do dono, o Lenine marcado com o Alex e você nos 6 dias tinha 24 contra 12 e a revisão cortava metade com "o orçamento mudou e agora estimo 6 dias (eram 6)"; agora tem 12 e nada sai, também depois de você dizer que lá só abre e fecha. Com o dono contado pelo molde, ou sem ele num meio-dia com outra pessoa, a de antes, byte a byte.';

-- _agenda_gestor_corte (de 20261101100500_agenda_fase7b_quem_chamar.sql)
create or replace function public._agenda_gestor_corte(p_os uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  cf      public.agenda_config;
  v_cong  date;
  v_dono  uuid;
  v_m     jsonb;
  v_pront jsonb;
  v_numero text;
  v_total int;
  v_feito numeric;
  v_n     int;
  v_k     int := 0;
  v_cut   jsonb := '[]'::jsonb;
  v_meios jsonb := '[]'::jsonb;
  v_fe    boolean := false;
  v_ult   record;
  v_itens jsonb;
  v_partes text[];
  v_txt   text;
  v_base  jsonb;
  v_val   jsonb;
  r       record;
  -- (7a correção, achado 16) a conta em pessoa-meio-dia
  v_pm    jsonb;
  v_sobra numeric;
  v_kpm   numeric := 0;
  v_npm   int;
  -- FASE 7b: (7b P6) a sobra que vem da dupla completada
  v_7b_ni    int;
  v_7b_nf    int;
  v_7b_todos boolean;
  v_7b_conta boolean;
  v_7b_prin  uuid;
  v_7b_extra int;
  v_7b_quem  uuid[];
  v_7b_dias  date[];
  -- FASE 7b: fim
  -- FASE 7b: (correção 2, achado 26 da 7a) o dono que vai junto (o critério de _agenda_gestor_pessoa_meios) e a estimativa do texto
  v_c2_junto boolean;
  v_c2_dup   int;
  v_c2_est   int;
  v_c2_um    int;
  v_c2_x     numeric;
  -- FASE 7b: fim (correção 2)
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_corte: faltam a OS, o dia ou a hora' using errcode = '22004';
  end if;
  select so.service_order_number into v_numero from public.service_orders so where so.id = p_os;
  v_m := public.agenda_meios_da_os(p_os, p_hoje);
  v_total := (v_m ->> 'total')::int;
  v_feito := coalesce((v_m ->> 'cumpridos')::numeric, 0) + coalesce((v_m ->> 'vigentes')::numeric, 0);
  v_base := jsonb_build_object('os', p_os, 'numero', v_numero, 'fonte', v_m ->> 'fonte', 'total', v_total, 'feitos', v_feito,
                               'cortar', 0, 'cortados', '[]'::jsonb, 'itens', '[]'::jsonb, 'texto', null);
  if not coalesce((v_m ->> 'ok')::boolean, false) or v_total is null then
    return v_base || jsonb_build_object('motivo', 'sem_dias');
  end if;
  -- (7a correção, achado 16) a sobra em pessoa-meio-dia (_agenda_gestor_pessoa_meios), não em meio-dia de calendário: o plano
  -- de 1 pessoa × 6 dias que ganhou a dupla dita (2 pessoas × 3 dias) tem o que a estimativa pede, e nada sai. v_n é o teto de
  -- meios-dias de calendário (cada um tem ao menos uma pessoa); o laço para quando as pessoas do meio-dia não cabem na sobra.
  v_pm := public._agenda_gestor_pessoa_meios(p_os, p_hoje, v_m);
  v_sobra := coalesce((v_pm ->> 'tem')::numeric - (v_pm ->> 'precisa')::numeric, 0);
  v_n := floor(v_sobra)::int;
  if v_n < 1 then
    return v_base || jsonb_build_object('sobra', greatest(v_n, 0), 'motivo', 'nada_a_cortar');
  end if;
  cf := public._agenda_cfg();
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_dono := public._agenda_dono(null);
  -- FASE 7b: (correção 2, achado 26 da 7a) o dono que vai junto, o mesmo critério de _agenda_gestor_pessoa_meios: ele só é uma das
  -- pessoas quando o molde o conta (o turno inteiro e, além disso, a equipe dita, a regra uma_pessoa desligada, o diagnóstico ou o
  -- comissionamento); fora disso, vai junto
  v_c2_junto := v_m ? 'dono_turno'
                and not ((coalesce((v_m #>> '{dono_turno,manha}')::boolean, false) or coalesce((v_m #>> '{dono_turno,tarde}')::boolean, false))
                         and (coalesce((v_m ->> 'equipe_dita')::boolean, true) or not public._agenda_gestor_regra('uma_pessoa')
                              or coalesce(v_m ->> 'regra_motivo', '') in ('diagnóstico', 'comissionamento')));
  -- FASE 7b: fim (correção 2)

  -- do último meio-dia para trás: sai enquanto pode sair
  for r in
    select a.dia, a.turno,
           jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                        'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca, 'estado', a.estado,
                                        'fixado_por', a.fixado_por, 'tipo', a.tipo)
                     order by a.presenca <> 'turno', a.payee_id) as alocs,
           bool_and(a.estado = 'publicada') as pub,
           bool_or(public._agenda_dia_avisado(a.payee_id, a.service_order_id, a.dia) is not null) as avisado,
           min(lower(a.periodo)) as ini,
           bool_or(a.presenca = 'fechamento' and a.payee_id is not distinct from v_dono) as fecha,
           min(a.tipo) as tipo
      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
       and a.resultado is null
     group by a.dia, a.turno
     order by a.dia desc, a.turno = 'tarde' desc
  loop
    exit when v_k >= v_n;
    exit when not r.pub or r.avisado or r.dia <= v_cong or r.ini <= p_agora;
    -- (7a correção, achado 16) o meio-dia sai inteiro só se as pessoas de turno dele cabem na sobra em pessoa-meio-dia
    v_npm := (select count(*) from jsonb_array_elements(r.alocs) x where x ->> 'presenca' = 'turno')::int;
    -- FASE 7b: (correção 2, achado 26 da 7a) o dono que vai junto com alguém no meio-dia não é uma das pessoas dele (a sobra não
    -- o conta: sem isso, a estimativa que caiu de 6 para 4 dias tirava só 1 dia, não 2 — cada meio-dia valia 2 pessoas)
    if v_c2_junto and v_npm > 1
       and exists (select 1 from jsonb_array_elements(r.alocs) x where x ->> 'presenca' = 'turno' and (x ->> 'payee_id')::uuid = v_dono) then
      v_npm := v_npm - 1;
    end if;
    -- FASE 7b: fim (correção 2)
    exit when v_kpm + v_npm > v_sobra;
    v_kpm := v_kpm + v_npm;
    v_cut := v_cut || r.alocs;
    v_meios := v_meios || jsonb_build_object('dia', r.dia, 'turno', r.turno);
    v_fe := v_fe or r.fecha;
    v_k := v_k + 1;
  end loop;
  if v_k = 0 then
    return v_base || jsonb_build_object('sobra', v_n, 'ficou', v_n, 'motivo', 'nada_pode_sair');
  end if;
  v_pront := public.os_prontidao(p_os, p_hoje);
  v_itens := jsonb_build_array(jsonb_build_object(
    'op', 'cancelar', 'os', p_os, 'numero', v_numero, 'cliente_curto', v_pront ->> 'cliente_curto',
    'tipo', (select min(x ->> 'tipo') from jsonb_array_elements(v_cut) x), 'motivo', 'reestimada', 'violada', false,
    'alocacoes', v_cut, 'de', (select min(x ->> 'dia') from jsonb_array_elements(v_cut) x),
    'ate', (select max(x ->> 'dia') from jsonb_array_elements(v_cut) x), 'critica', null, 'decisao', null, 'aplicado', false,
    'texto', null));
  -- o fechamento do dono que saiu volta no novo último meio-dia de compromisso
  if v_fe then
    select a.dia, a.turno into v_ult
      from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
       and a.resultado is null and a.presenca = 'turno'
       and not exists (select 1 from jsonb_array_elements(v_cut) x where (x ->> 'alocacao_id')::uuid = a.id)
     order by a.dia desc, a.turno = 'tarde' desc limit 1;
    if v_ult.dia is not null
       and not exists (select 1 from public.agenda_alocacoes a
                        where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.dia = v_ult.dia
                          and a.turno = v_ult.turno and a.presenca = 'fechamento') then
      v_itens := v_itens || jsonb_build_object(
        'op', 'criar', 'os', p_os, 'numero', v_numero, 'cliente_curto', v_pront ->> 'cliente_curto',
        'tipo', (select min(x ->> 'tipo') from jsonb_array_elements(v_cut) x), 'reserva_de', null,
        'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_dono,
                       'nome', (select public._agenda_nome_curto(py.name) from public.payees py where py.id = v_dono),
                       'dia', v_ult.dia, 'turno', v_ult.turno, 'presenca', 'fechamento')),
        'de', v_ult.dia, 'ate', v_ult.dia, 'fim_antes', null, 'fim_depois', v_ult.dia, 'atraso_du', null, 'condicao_tipo', null,
        'critica', null, 'pergunta_chave', null, 'decisao', null, 'espera', false, 'interrupcoes', 0, 'meios_do_dono', 0,
        'fonte', v_m ->> 'fonte', 'dias', v_m -> 'dias', 'evento_real', false, 'fixar_dono', false, 'aviso_material', null,
        'abre', false, 'fecha', true, 'motivos', jsonb_build_array('o fechamento vai para o novo último meio-dia'),
        'texto', null, 'aplicado', false);
    end if;
  end if;
  -- "Tirei sex 13/11" (o dia inteiro) ou "Tirei qui 12/11 à tarde" (um turno só)
  v_partes := array(select case when count(*) > 1 then public._dia_curto((x ->> 'dia')::date)
                                else public._agenda_meio_texto((x ->> 'dia')::date, min(x ->> 'turno')) end
                      from jsonb_array_elements(v_meios) x group by x ->> 'dia' order by x ->> 'dia');
  v_txt := format('%s: o orçamento mudou e agora estimo %s (eram %s). Tirei %s.', public._agenda_rotulo_da_os(p_os),
                  public._agenda_dias(v_total::numeric / 2), public._agenda_num(v_feito / 2), public._agenda_lista(v_partes));
  -- FASE 7b: (correção 2, achado 26 da 7a) o texto honesto e o número certo. A estimativa em meios-dias de calendário na forma do
  -- plano (v_c2_est): sem a dupla por meio-dia (dk), o total; com o dk, o que a estimativa pede em pessoa-meio-dia (o precisa, com 1
  -- pessoa) menos os meios-dias de dupla do molde (as ni primeiras e as nf últimas de turno da OS, contando as cumpridas; o tempo todo =
  -- todas) que o plano já tem com a 2ª pessoa (cada um rende 2) — com a 7b ligada o total já vem encurtado pela dupla, e o plano de 1
  -- pessoa (só o Alex) passava dele sem o orçamento mudar. Com o plano sem meio-dia além disso (feitos <= v_c2_est), a sobra é de
  -- gente a mais em algum meio-dia, não do orçamento — "o orçamento mudou e agora estimo 6 dias (eram 6)" seria falso —, e o texto diz
  -- a estimativa com 1 pessoa (com a 7b ligada, as diárias-pessoa: dupla.pm_estimativa). Com o dk e o plano maior, o número é o que o
  -- plano tem depois do corte inteiro (do fim para trás, as pessoas de cada meio-dia sem o dono que vai junto, sem as travas): o total
  -- da dupla dizia "estimo 3 dias" num plano de 1 pessoa que ficava com 4. Sem o dk e com o plano maior, o texto de antes. A dupla
  -- completada (logo abaixo) tem o texto dela por cima deste.
  v_c2_est := v_total;
  v_c2_um := v_total;
  if v_m ? 'dk' and (v_pm ->> 'precisa') is not null then
    select count(*) filter (where k.tem >= 2 and (coalesce((v_m #>> '{dupla,todos}')::boolean, false)
                                                   or k.pos <= coalesce((v_m #>> '{dupla,ni}')::int, 0)
                                                   or k.pos > k.n - coalesce((v_m #>> '{dupla,nf}')::int, 0)))::int
      into v_c2_dup
      from (select s.tem, row_number() over (order by s.dia, s.turno) as pos, count(*) over () as n
              from (select a.dia, a.turno,
                           count(distinct a.payee_id) filter (where not (v_c2_junto and a.payee_id is not distinct from v_dono)) as tem
                      from public.agenda_alocacoes a
                     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                       and a.presenca = 'turno' and a.resultado is distinct from 'nao_cumprido'
                     group by a.dia, a.turno) s) k;
    v_c2_est := greatest((v_pm ->> 'precisa')::int / greatest(coalesce((v_pm ->> 'pessoas')::int, 1), 1)
                         - least(v_c2_dup, case when coalesce((v_m #>> '{dupla,todos}')::boolean, false) then v_total
                                                else coalesce((v_m #>> '{dupla,ni}')::int, 0) + coalesce((v_m #>> '{dupla,nf}')::int, 0) end), 1);
    v_c2_um := coalesce((v_m #>> '{dupla,pm_estimativa}')::int, v_total);
  end if;
  if v_feito <= v_c2_est then
    v_txt := format('%s: o plano tem mais gente do que a minha estimativa (%s com %s), então o serviço acaba antes (são as mesmas diárias). Tirei %s.',
                    public._agenda_rotulo_da_os(p_os), public._agenda_dias(v_c2_um::numeric / 2),
                    case when coalesce((v_pm ->> 'pessoas')::int, 1) = 1 then '1 pessoa' else (v_pm ->> 'pessoas') || ' pessoas' end,
                    public._agenda_lista(v_partes));
  elsif v_m ? 'dk' then
    select v_feito - least(count(*), v_n) into v_c2_x
      from (select sum(h.n) over (order by h.dia desc, h.turno = 'tarde' desc rows between unbounded preceding and current row) as acum
              from (select a.dia, a.turno,
                           count(*) filter (where a.presenca = 'turno')
                           - case when v_c2_junto and count(*) filter (where a.presenca = 'turno') > 1
                                       and bool_or(a.presenca = 'turno' and a.payee_id = v_dono) then 1 else 0 end as n
                      from public.agenda_alocacoes a
                     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                       and a.dia >= p_hoje and a.resultado is null
                     group by a.dia, a.turno) h) o
     where o.acum <= v_sobra;
    v_txt := format('%s: o orçamento mudou e agora estimo %s (eram %s). Tirei %s.', public._agenda_rotulo_da_os(p_os),
                    public._agenda_dias(v_c2_x / 2), public._agenda_num(v_feito / 2), public._agenda_lista(v_partes));
  end if;
  -- FASE 7b: fim (correção 2)
  -- FASE 7b: (7b P6, R4.3(f)) a sobra que vem da dupla completada depois de marcar (o dono disse os dias do ajudante e o passo dupla
  -- do gestor o pôs junto do técnico): com a duração que conserva as diárias-pessoa (o dk do molde), a dupla rende 2 e o serviço
  -- acaba antes. Quando a sobra não passa das pessoas a mais nos meios-dias da dupla do molde (as ni primeiras e as nf últimas de turno
  -- da OS, contando as cumpridas; o tempo todo = todas; o dono só conta com dk_dono_conta), o texto diz isso, não "o orçamento mudou":
  -- "Lenine (OS-00074): com Mateus junto em ter 10/11, o serviço acaba antes (são as mesmas diárias). Tirei ter 17/11." O corte é o mesmo.
  if v_m ? 'dk' then
    v_7b_ni := coalesce((v_m #>> '{dupla,ni}')::int, 0);
    v_7b_nf := coalesce((v_m #>> '{dupla,nf}')::int, 0);
    v_7b_todos := coalesce((v_m #>> '{dupla,todos}')::boolean, false);
    v_7b_conta := coalesce((v_m ->> 'dk_dono_conta')::boolean, true);
    -- (correção 2, achado 26 da 7a) o dono que vai junto (v_c2_junto) não conta na dupla completada
    v_7b_conta := v_7b_conta and not v_c2_junto;
    -- (correção 2: fim)
    -- quem vai no serviço (a pessoa com mais meios-dias de turno nele): o "junto" são os outros
    select a.payee_id into v_7b_prin
      from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
       and a.resultado is distinct from 'nao_cumprido'
     group by a.payee_id order by count(*) desc, min(a.dia), a.payee_id limit 1;
    with s as (
      select a.dia, a.turno,
             count(distinct a.payee_id) filter (where a.payee_id is distinct from v_dono or v_7b_conta)::int as tem,
             array_agg(distinct a.payee_id) filter (where a.payee_id is distinct from v_7b_prin
                                                     and (a.payee_id is distinct from v_dono or v_7b_conta)) as juntos
        from public.agenda_alocacoes a
       where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
         and a.resultado is distinct from 'nao_cumprido'
       group by a.dia, a.turno
    ), k as (
      select s.*, row_number() over (order by s.dia, s.turno) as pos, count(*) over () as n from s
    ), d as (
      select k.* from k where v_7b_todos or k.pos <= v_7b_ni or k.pos > k.n - v_7b_nf
    )
    select coalesce(sum(greatest(d.tem - 1, 0)), 0)::int,
           array(select distinct j from d d2 cross join lateral unnest(coalesce(d2.juntos, '{}'::uuid[])) j where d2.tem >= 2),
           array(select distinct d2.dia from d d2 where d2.tem >= 2 order by 1)
      into v_7b_extra, v_7b_quem, v_7b_dias
      from d;
    if v_7b_extra > 0 and v_sobra <= v_7b_extra and cardinality(v_7b_quem) > 0 then
      v_txt := format('%s: com %s junto em %s, o serviço acaba antes (são as mesmas diárias). Tirei %s.', public._agenda_rotulo_da_os(p_os),
                      public._agenda_lista(array(select case when q = v_dono then 'você' else public._agenda_nome_curto(py.name) end
                                                  from unnest(v_7b_quem) q join public.payees py on py.id = q order by py.name, q)),
                      regexp_replace(public._agenda_dias_texto(v_7b_dias), ' \([^()]*\)$', ''), public._agenda_lista(v_partes));
    end if;
  end if;
  -- FASE 7b: fim
  v_val := public._agenda_validar_itens(v_itens, jsonb_build_object('p_restricoes', '{}'::jsonb), p_hoje, p_agora, false,
                                        jsonb_build_object(p_os::text, v_pront));
  if jsonb_array_length(v_val) > 0 then
    return v_base || jsonb_build_object('sobra', v_n, 'ficou', v_n, 'motivo', 'validacao', 'violacoes', v_val);
  end if;
  return v_base || jsonb_build_object('sobra', v_n, 'cortar', v_k, 'cortados', v_meios, 'ficou', v_n - v_k,
    'itens', (select jsonb_agg(i || jsonb_build_object('texto', v_txt) order by k) from jsonb_array_elements(v_itens) with ordinality t(i, k)),
    'texto', public._agenda_corta(v_txt, 400), 'motivo', null);
end;
$function$;

comment on function public._agenda_gestor_corte(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P9; spec §5.9 item 1 e §6.4): o corte do reestimar, a conta, sem gravar — com o plano (os meios-dias feitos + os de hoje em diante) maior que agenda_meios_da_os.total, os N últimos meios-dias de compromisso saem (N = a sobra inteira), do fim para trás, parando no 1º que não pode sair (o congelado, o que começou, o fixado, o dia já dito à equipe ou ao cliente: esses ficam com o dono); o fechamento do dono que sai volta no novo último meio-dia. Validado pelas 14 regras (_agenda_validar_itens). {os, numero, fonte, total, feitos, sobra, cortar, cortados [{dia, turno}], ficou, itens (cancelar motivo reestimada; criar do fechamento), texto ("Nelson (OS-00112): o orçamento mudou e agora estimo 3 dias (eram 4). Tirei sex 13/11."), motivo?}. STABLE, invoker, sem grant. CORREÇÃO DA 7a (revisão da etapa; achado 16): a sobra é contada em pessoa-meio-dia (_agenda_gestor_pessoa_meios: o que o plano tem — os meios-dias de turno de cada pessoa, os passados pelo resultado — contra o que a estimativa pede — meios-dias × as pessoas dela), não em meio-dia de calendário: *<nome> com dupla* num serviço marcado com 1 pessoa não corta mais metade dos dias (as diárias são as mesmas; a dupla vale para a próxima marcação); o meio-dia de calendário só sai se as pessoas dele cabem na sobra. FASE 7b (P6, R4.3(f)): quando a sobra vem da dupla completada depois de marcar (com o dk do molde, a sobra não passa das pessoas a mais nos meios-dias da dupla: as ni primeiras e as nf últimas de turno da OS, contando as cumpridas; o tempo todo = todas), o texto diz isso — "Lenine (OS-00074): com Mateus junto em ter 10/11, o serviço acaba antes (são as mesmas diárias). Tirei ter 17/11." —, não "o orçamento mudou"; o corte é o mesmo. Sem dk, a de antes, byte a byte. CORREÇÃO 2 DA 7b (achado 26 da revisão da 7b, que é da 7a): o meio-dia em que o dono vai junto com alguém (o critério de _agenda_gestor_pessoa_meios: ele só é uma das pessoas quando o molde o conta) conta as pessoas sem ele — a estimativa que caiu de 6 para 4 dias tira os 2 últimos dias (o técnico e você), não 4 —, e na dupla completada da 7b ele não é o "junto"; e o texto é honesto: com o plano sem meio-dia além da estimativa na forma do plano (feitos <= total; com o dk, o precisa menos os meios-dias de dupla do molde que o plano já tem com a 2ª pessoa) a sobra é de gente a mais, e o texto diz "Lenine (OS-00074): o plano tem mais gente do que a minha estimativa (6 dias com 1 pessoa), então o serviço acaba antes (são as mesmas diárias). Tirei ter 17/11." — nunca "o orçamento mudou e agora estimo 6 dias (eram 6)"; com o dk e o plano maior, "agora estimo N" é o que o plano tem depois do corte inteiro (com a 7b ligada, o plano de 1 pessoa cujo orçamento caiu de 6 para 4 dias: "estimo 4 dias (eram 6)", não o total da dupla, 3); a dupla completada continua com o texto dela. Sem o dk, com o dono contado pelo molde e o plano maior que a estimativa, a de antes, byte a byte.';

-- _agenda_ver_gestor (de 20261101100800_agenda_fase77b_correcao.sql)
create or replace function public._agenda_ver_gestor(p_hoje date)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_ef    text := public._agenda_gestor_modo('marcar');
  v_l     text[] := '{}';
  v_desde date;
  v_sdia  date;
  v_s     jsonb;
  v_cart  uuid[];
  v_fora  jsonb := '[]'::jsonb;
  v_n     int;
  v_comp  jsonb;
  v_orc   jsonb;
  v_mo    numeric := public._agenda_mo_por_diaria_real();
  x       jsonb;
  r       record;
  -- (7a correção, achado 3) o "Como eu conto" à parte, sempre no fim
  v_como  text;
  v_k     int;
  -- FASE 7: (7a correção 2) quem a grade tem (a dupla sem a 2ª pessoa) e o fim do dia (o *desfaz* do dono)
  v_f72_tec   text[];
  v_f72_dup   text;
  v_f72_agora timestamptz;
  -- FASE 7: fim
  -- FASE 7b: (7b P6) a dupla de 1 pessoa no lugar do "Pode precisar de dupla" e o bloco "Quem chamar"
  v_7b_dupla boolean := (public._agenda_cfg()).modo_dupla <> 'desligado';
  v_7b_tf    text;
  v_7b_m     jsonb;
  v_7b_pl    jsonb;
  v_7b_d     jsonb;
  v_7b_fa    jsonb;
  v_7b_ni    int;
  v_7b_nf    int;
  v_7b_x     text;
  v_7b_y     text;
  v_7b_r1    text;
  v_7b_r2    text;
  v_7b_z     text;
  v_7b_ch    jsonb;
  v_7b_cdia  date;
  v_7b_cab   text;
  v_7b_pela  text;
  v_7b_bul   text[];
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 1, 5, 9, 11, 15 e 23) o bloco "Quem chamar" no fim que sempre entra, a dupla que é só
  -- nota e o exemplo com todos os dias. c_7bc_max é estrutural: o tamanho do bloco no fim (o resto, "(e mais N linhas)").
  c_7bc_max  constant int := 700;
  v_7bc_n    int := 0;
  v_7bc_ch   text[] := '{}';
  v_7bc_l0   text;
  v_7bc_dias text;
  v_7bc_mais int := 0;
  -- FASE 7b: fim
  -- FASE 7b: (correção 2, achado 26 da 7a) os dias do "Marquei nos últimos 7 dias" sem o turno do dono que vai junto
  v_c2_m     jsonb;
  v_c2_dono  uuid := public._agenda_dono(null);
  -- FASE 7b: fim (correção 2)
begin
  if p_hoje is null then
    raise exception '_agenda_ver_gestor: sem o dia de hoje' using errcode = '22004';
  end if;

  -- 1. o estado (uma linha)
  if cf.gestor_so_propor then
    v_l := v_l || case when cf.gestor_so_propor_em is not null
                       then format('Desde %s você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta.',
                                   public._dia_curto((cf.gestor_so_propor_em at time zone 'America/Sao_Paulo')::date))
                       else 'Você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta.' end;
  elsif cf.modo_marcar_sozinho = 'ligado' then
    v_l := v_l || case when cf.marcar_sozinho_desde is not null
                       then format('Eu marco sozinho desde %s e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz.',
                                   public._dia_curto((cf.marcar_sozinho_desde at time zone 'America/Sao_Paulo')::date))
                       else 'Eu marco sozinho e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz.' end;
  elsif cf.modo_marcar_sozinho = 'sombra' then
    select min(g.dia) into v_desde from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.modos ->> 'marcar' = 'sombra'
       and g.dia > coalesce((select max(h.dia) from public.agenda_gestor_dia h
                              where h.dia <= p_hoje and h.modos ->> 'marcar' is distinct from 'sombra'), date '-infinity');
    v_l := v_l || case when v_desde is not null
                       then format('O gestor está em teste desde %s: calcula o que marcaria, mas não muda nada.', public._dia_curto(v_desde))
                       else 'O gestor está em teste: calcula o que marcaria, mas não muda nada.' end;
  else
    v_l := v_l || 'O gestor da agenda está desligado: não marco nada sozinho.'::text;
  end if;

  -- FASE 7: (7a correção 2, a dupla sem a 2ª pessoa) com menos de 2 técnicos na grade, o "Pode precisar de dupla" diz que falta a
  -- 2ª pessoa e o que fazer antes do *<nome> com dupla* (sem isso a palavra tirava a OS da agenda, calada)
  v_f72_tec := public._agenda_tecnicos_da_grade(p_hoje);
  v_f72_dup := case when cardinality(v_f72_tec) < 2
                    then replace(format('hoje %s: para ir dupla, chame um ajudante e ', public._agenda_tecnicos_frase(v_f72_tec)), '%', '%%')
                    else '' end;
  v_f72_agora := (p_hoje + 1)::timestamp at time zone 'America/Sao_Paulo';
  -- FASE 7: fim
  -- FASE 7b: (7b P6) quem a grade tem, na frase da dupla de 1 pessoa (a da marcação do P4)
  v_7b_tf := case when cardinality(v_f72_tec) >= 2 then 'ninguém mais está livre nesses meios-dias'
                  else public._agenda_tecnicos_frase(v_f72_tec) end;
  -- FASE 7b: fim
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k
                   where not public._agenda_os_tem_dia(k.service_order_id, p_hoje));

  if v_ef = 'sombra' then
    -- 2–4 em teste: a última conta do "eu marcaria assim" (o diário do gestor)
    select g.dia, g.sombra into v_sdia, v_s from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.sombra <> '{}'::jsonb order by g.dia desc limit 1;
    if v_s is null then
      v_l := v_l || 'Eu marcaria: ainda não fiz a conta (faço todo dia útil no fim da tarde).'::text;
    else
      if jsonb_array_length(coalesce(v_s -> 'itens', '[]'::jsonb)) = 0 and jsonb_array_length(coalesce(v_s -> 'reservas', '[]'::jsonb)) = 0 then
        v_l := v_l || ('Eu marcaria' || case when v_sdia <> p_hoje then format(' (pela conta de %s)', public._dia_curto(v_sdia)) else '' end
                       || ': nada agora.');
      else
        v_l := v_l || ('Eu marcaria' || case when v_sdia <> p_hoje then format(' (pela conta de %s)', public._dia_curto(v_sdia)) else '' end
                       || ':');
        for x in select e from jsonb_array_elements(coalesce(v_s -> 'itens', '[]'::jsonb)) with ordinality t(e, o) order by o loop
          v_l := v_l || format('• %s: %s, %s — %s (%s)%s.%s', x ->> 'cliente',
                               public._agenda_gestor_faixa((x ->> 'de')::date, (x ->> 'ate')::date), x ->> 'pessoas',
                               public._agenda_dias((x ->> 'dias')::numeric),
                               case x ->> 'fonte' when 'orcamento' then 'estimativa minha' else 'você disse' end,
                               case when x ->> 'compre_ate' is not null
                                    then format('; compre até %s: %s',
                                                case when (x ->> 'compre_ate')::date <= p_hoje then 'hoje'
                                                     else public._dia_curto((x ->> 'compre_ate')::date) end,
                                                public._agenda_itens((x ->> 'itens_a_comprar')::int))
                                    else '' end,
                               case when jsonb_typeof(x -> 'alerta_dupla') = 'object'
                                    then format(' Pode precisar de dupla (%s): ' || v_f72_dup || 'diga *%s com dupla*.',  -- (7a correção 2) a 2ª pessoa
                                                public._agenda_gestor_dupla_texto(x -> 'alerta_dupla'), x ->> 'cliente')
                                    else '' end);
          -- FASE 7b: (correção da revisão da 7b, achados 5 e 9) a linha como o 7a a deixou (o bloco do P6, logo abaixo, a troca)
          v_7bc_l0 := v_l[cardinality(v_l)];
          -- FASE 7b: fim
          -- FASE 7b: (7b P6, R4.4 "agenda gestor") com modo_dupla fora de desligado, o "Pode precisar de dupla (…): … diga *Lenine com
          -- dupla*" do 7a sai: com a 7b, *com dupla* é "o tempo todo" e faz a OS esperar a 2ª pessoa. Em teste do gestor não há plano:
          -- a frase da dupla de 1 pessoa (R4.3(a)(3)) na forma curta, sem as datas ("Nos 2 primeiros meios-dias a troca do banco de
          -- baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga os dias dele."), pelos meios-dias do que
          -- a tarefa pede (_agenda_dupla_da_os: fora da simulação, o molde não tem o dk da regra uma_pessoa do gestor em teste)
          if v_7b_dupla and jsonb_typeof(x -> 'alerta_dupla') = 'object' then
            v_7b_m := public._agenda_dupla_da_os((x ->> 'os')::uuid);
            if v_7b_m ->> 'fonte' = 'regra' then
              v_7b_ni := coalesce((v_7b_m ->> 'inicio')::int, 0);
              v_7b_nf := coalesce((v_7b_m ->> 'fim')::int, 0);
              v_7b_x := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                     from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                                    where q ->> 'onde' = 'inicio' order by q ->> 'motivo'));
              v_7b_y := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                     from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                                    where q ->> 'onde' = 'fim' order by q ->> 'motivo'));
              v_7b_z := case
                when coalesce((v_7b_m ->> 'todos')::boolean, false)
                  then format(' O serviço todo pede 2 pessoas (%s) e %s: se chamar um ajudante, me diga os dias dele.',
                              coalesce((select q ->> 'rotulo' from jsonb_array_elements(coalesce(v_7b_m -> 'motivos', '[]'::jsonb)) q
                                         where q ->> 'onde' = 'todos' limit 1), 'o orçamento previu 2 técnicos'), v_7b_tf)
                when v_7b_ni > 0 and v_7b_nf > 0
                  then format(' %s %s e %s %s pedem 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x,
                              case when v_7b_nf = 1 then 'no último meio-dia' else format('nos %s últimos meios-dias', v_7b_nf) end, v_7b_y,
                              v_7b_tf)
                when v_7b_ni > 0
                  then format(' %s %s pede 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x,
                              v_7b_tf)
                when v_7b_nf > 0
                  then format(' %s %s pede 2 pessoas e %s: se chamar um ajudante, me diga os dias dele.',
                              case when v_7b_nf = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_nf) end, v_7b_y,
                              v_7b_tf)
                else '' end;
              v_l[cardinality(v_l)] := regexp_replace(v_l[cardinality(v_l)], ' Pode precisar de dupla \(.*$', '') || v_7b_z;
            end if;
          end if;
          -- FASE 7b: fim
          -- FASE 7b: (correção da revisão da 7b, achado 5) com modo_dupla fora de desligado, a OS em que a dupla é só nota (o espaço
          -- confinado: _agenda_dupla_da_os sem fonte de regra nem do dono) continua com o "Pode precisar de dupla" do 7a, mas dizendo o que
          -- *com dupla* quer dizer na 7b (o tempo todo: com só um técnico, a OS espera a 2ª pessoa) e, com menos de 2 técnicos, os dias do
          -- ajudante antes da palavra.
          if v_7b_dupla and jsonb_typeof(x -> 'alerta_dupla') = 'object' and v_l[cardinality(v_l)] like '% Pode precisar de dupla (%'
             and coalesce(public._agenda_dupla_da_os((x ->> 'os')::uuid) ->> 'fonte', '') not in ('regra', 'dono') then
            v_l[cardinality(v_l)] := replace(replace(v_l[cardinality(v_l)], 'chame um ajudante e diga *', 'chame um ajudante, me diga os dias dele e diga *'),
                                             ' com dupla*.', ' com dupla* (em dupla o tempo todo).');
          end if;
          -- (achado 9) o que a 7b acrescentou à linha da 7a não tira espaço das outras linhas da 7a (o "Fora:", o "Se aprovar:")
          v_7bc_mais := v_7bc_mais + char_length(v_l[cardinality(v_l)]) - char_length(v_7bc_l0);
          -- FASE 7b: fim
        end loop;
        for x in select e from jsonb_array_elements(coalesce(v_s -> 'reservas', '[]'::jsonb)) with ordinality t(e, o) order by o loop
          v_l := v_l || format('• %s: reservaria %s, %s.', x ->> 'cliente',
                               public._agenda_gestor_faixa((x ->> 'de')::date, (x ->> 'ate')::date), x ->> 'pessoas');
        end loop;
      end if;
      if jsonb_array_length(coalesce(v_s -> 'perguntas', '[]'::jsonb)) > 0 then
        v_l := v_l || 'Antes de marcar eu perguntaria:'::text;
        for x in select e from jsonb_array_elements(v_s -> 'perguntas') with ordinality t(e, o) order by o loop
          v_l := v_l || (format('• %s: %s', x ->> 'cliente', x ->> 'curto')
                         || case when right(x ->> 'curto', 1) in ('?', '.') then '' else '.' end);
        end loop;
      end if;
      v_fora := coalesce(v_s -> 'fora', '[]'::jsonb);
    end if;
  elsif v_ef = 'ligado' then
    -- 2. o que o gestor marcou nos últimos 7 dias: as OS com compromisso vigente pela estimativa (duracao_fonte orcamento)
    v_n := 0;
    v_l := v_l || 'Marquei nos últimos 7 dias:'::text;
    for r in select a.service_order_id as os, min(a.dia) as de, max(a.dia) as ate,
                    count(*) filter (where a.presenca = 'turno') as meios,
                    jsonb_agg(jsonb_build_object('payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name), 'dia', a.dia,
                                                 'turno', a.turno, 'presenca', a.presenca)) as alocs
               from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
              where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.duracao_fonte = 'orcamento'
                and a.dia >= p_hoje and a.resultado is null
              group by a.service_order_id
             having min((a.criado_em at time zone 'America/Sao_Paulo')::date) >= p_hoje - 7
              order by min(a.dia), a.service_order_id loop
      v_n := v_n + 1;
      -- FASE 7b: (correção 2, achado 26 da 7a) os dias sem o turno do dono que vai junto com alguém (o critério de
      -- _agenda_gestor_pessoa_meios: ele só é uma das pessoas quando o molde o conta): o Lenine marcado com o Alex e você nos 6 dias
      -- dizia "Alex — 12 dias (estimativa minha)"
      v_c2_m := public.agenda_meios_da_os(r.os, p_hoje);
      if v_c2_m ? 'dono_turno'
         and not ((coalesce((v_c2_m #>> '{dono_turno,manha}')::boolean, false) or coalesce((v_c2_m #>> '{dono_turno,tarde}')::boolean, false))
                  and (coalesce((v_c2_m ->> 'equipe_dita')::boolean, true) or not public._agenda_gestor_regra('uma_pessoa')
                       or coalesce(v_c2_m ->> 'regra_motivo', '') in ('diagnóstico', 'comissionamento'))) then
        r.meios := r.meios - (select count(*) from jsonb_array_elements(r.alocs) c2a(e)
                               where c2a.e ->> 'presenca' = 'turno' and (c2a.e ->> 'payee_id')::uuid = v_c2_dono
                                 and exists (select 1 from jsonb_array_elements(r.alocs) c2b(e)
                                              where c2b.e ->> 'presenca' = 'turno' and c2b.e ->> 'dia' = c2a.e ->> 'dia'
                                                and c2b.e ->> 'turno' = c2a.e ->> 'turno' and c2b.e ->> 'payee_id' <> c2a.e ->> 'payee_id'));
      end if;
      -- FASE 7b: fim (correção 2)
      v_l := v_l || format('• %s: %s, %s — %s (estimativa minha).%s',
                           coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                                       join public.clients cl on cl.id = so.client_id where so.id = r.os), 'serviço'),
                           public._agenda_gestor_faixa(r.de, r.ate), public._agenda_gestor_pessoas(r.alocs),
                           public._agenda_dias(r.meios::numeric / 2),
                           coalesce((select format(' Pode precisar de dupla (%s): ' || v_f72_dup || 'diga *%s com dupla*.',  -- (7a correção 2) a 2ª pessoa
                                                   public._agenda_gestor_dupla_texto(d.a), public._agenda_nome_curto(cl.name))
                                       from (select public.os_duracao_sugerida(r.os) -> 'alerta_dupla' as a) d,
                                            public.service_orders so join public.clients cl on cl.id = so.client_id
                                      where so.id = r.os and jsonb_typeof(d.a) = 'object'), ''));
      -- FASE 7b: (correção da revisão da 7b, achados 11 e 23) a linha como o 7a a deixou (o bloco do P6, logo abaixo, a troca)
      v_7bc_l0 := v_l[cardinality(v_l)];
      -- FASE 7b: fim
      -- FASE 7b: (7b P6, R4.4 "agenda gestor") com modo_dupla fora de desligado, o "Pode precisar de dupla" do 7a vira a frase da dupla
      -- de 1 pessoa (R4.3(a)(3), a da marcação do P4) com as datas do plano: os meios-dias em que a dupla pela tarefa ainda está sem a
      -- 2ª pessoa (_agenda_dupla_no_plano, fora da reserva). Com a 2ª pessoa em todos (a dupla completa), nada.
      if v_7b_dupla and v_l[cardinality(v_l)] like '% Pode precisar de dupla (%' then
        v_7b_pl := public._agenda_dupla_no_plano(r.os, p_hoje);
        v_7b_d := public._agenda_dupla_da_os(r.os);
        select coalesce(jsonb_agg(e order by (e ->> 'dia')::date, e ->> 'turno'), '[]'::jsonb) into v_7b_fa
          from jsonb_array_elements(coalesce(v_7b_pl -> 'faltam', '[]'::jsonb)) e
         where not coalesce((e ->> 'reserva')::boolean, false) and v_7b_pl ->> 'fonte' = 'regra';
        select public._agenda_lista(array(
                 select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                       when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                   from (select (e ->> 'dia')::date as d, e ->> 'turno' as t from jsonb_array_elements(v_7b_fa) e
                          where e ->> 'onde' in ('inicio', 'todos')) z
                  group by z.d order by z.d)),
               public._agenda_lista(array(
                 select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                       when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                   from (select (e ->> 'dia')::date as d, e ->> 'turno' as t from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'fim') z
                  group by z.d order by z.d))
          into v_7b_x, v_7b_y;
        v_7b_ni := (select count(*)::int from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'inicio');
        v_7b_nf := (select count(*)::int from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'fim');
        v_7b_r1 := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                               where q ->> 'onde' = 'inicio' order by q ->> 'motivo'));
        v_7b_r2 := public._agenda_lista(array(select distinct on (q ->> 'motivo') q ->> 'frase'
                                                from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                               where q ->> 'onde' = 'fim' order by q ->> 'motivo'));
        v_7b_z := case
          when jsonb_array_length(v_7b_fa) = 0 then ''
          when exists (select 1 from jsonb_array_elements(v_7b_fa) e where e ->> 'onde' = 'todos')
            then format(' O serviço todo pede 2 pessoas (%s) e %s: vai com 1 pessoa; se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        coalesce((select q ->> 'rotulo' from jsonb_array_elements(coalesce(v_7b_d -> 'motivos', '[]'::jsonb)) q
                                   where q ->> 'onde' = 'todos' limit 1), 'o orçamento previu 2 técnicos'), v_7b_tf,
                        public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          when v_7b_x <> '' and v_7b_y <> ''
            then format(' %s (%s) %s e %s (%s) %s pedem 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x, v_7b_r1,
                        case when v_7b_nf = 1 then 'no último meio-dia' else format('nos %s últimos meios-dias', v_7b_nf) end, v_7b_y, v_7b_r2,
                        v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          when v_7b_x <> ''
            then format(' %s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                        case when v_7b_ni = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_ni) end, v_7b_x, v_7b_r1,
                        v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date))
          else format(' %s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      case when v_7b_nf = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_nf) end, v_7b_y, v_7b_r2,
                      v_7b_tf, public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date)) end;
        v_l[cardinality(v_l)] := regexp_replace(v_l[cardinality(v_l)], ' Pode precisar de dupla \(.*$', '') || v_7b_z;
      end if;
      -- FASE 7b: fim
      -- FASE 7b: (correção da revisão da 7b, achados 11 e 23) a dupla que é só nota (o espaço confinado) não some: o bloco do P6 tirava o
      -- "Pode precisar de dupla" e não punha nada (sem dupla pela tarefa, a frase dele fica vazia) — volta a do 7a, dizendo que *com
      -- dupla* é o tempo todo e, com menos de 2 técnicos, os dias do ajudante antes. Na dupla pela tarefa, o exemplo diz todos os dias em
      -- que falta a 2ª pessoa, não só o 1º ("ex.: Mateus vem qua 18 e qui 19/11").
      if v_7b_dupla and v_7bc_l0 like '% Pode precisar de dupla (%' then
        if coalesce(v_7b_d ->> 'fonte', '') not in ('regra', 'dono') and coalesce(v_7b_pl ->> 'fonte', '') <> 'regra' then
          v_l[cardinality(v_l)] := replace(replace(v_7bc_l0, 'chame um ajudante e diga *', 'chame um ajudante, me diga os dias dele e diga *'),
                                           ' com dupla*.', ' com dupla* (em dupla o tempo todo).');
        elsif jsonb_array_length(coalesce(v_7b_fa, '[]'::jsonb)) > 0
              and (select count(distinct e ->> 'dia') from jsonb_array_elements(v_7b_fa) e) > 1 then
          v_7bc_dias := regexp_replace(public._agenda_dias_texto(array(select distinct (e ->> 'dia')::date from jsonb_array_elements(v_7b_fa) e order by 1)),
                                       ' \([^()]*\)$', '');
          v_l[cardinality(v_l)] := replace(v_l[cardinality(v_l)],
                                           format('(ex.: Mateus vem %s).', public._dia_curto((v_7b_fa -> 0 ->> 'dia')::date)),
                                           format('(ex.: Mateus vem %s).', v_7bc_dias));
        end if;
      end if;
      -- (achado 9) o que a 7b acrescentou à linha da 7a não tira espaço das outras linhas da 7a (o "Fora:", o "Se aprovar:")
      v_7bc_mais := v_7bc_mais + char_length(v_l[cardinality(v_l)]) - char_length(v_7bc_l0);
      -- FASE 7b: fim
    end loop;
    if v_n = 0 then
      v_l[cardinality(v_l)] := 'Marquei nos últimos 7 dias: nada.';
    end if;
    -- 3. o que ele perguntou antes de marcar (as abertas de verdade, com o prazo)
    v_n := 0;
    for r in select q.* from public.agenda_perguntas q
                     left join public.service_orders so on so.id = q.service_order_id
              where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo in ('situacao', 'estimativa')
              order by q.veto_ate nulls last, so.service_order_number desc nulls last, q.id loop
      if v_n = 0 then
        v_l := v_l || 'Perguntei antes de marcar:'::text;
      end if;
      v_n := v_n + 1;
      v_l := v_l || format('• %s: %s — %s',
        -- (7a correção 2) o número da OS junto quando o nome se repete nas perguntas abertas (Kalmar OS-00032 e OS-00033)
        case when (select count(*) from public.agenda_perguntas q2
                     join public.service_orders s2 on s2.id = q2.service_order_id
                     left join public.clients c2 on c2.id = s2.client_id
                    where q2.estado = 'aberta' and q2.modo = 'ligado' and q2.tipo in ('situacao', 'estimativa')
                      and public._agenda_nome_curto(c2.name) is not distinct from
                          (select public._agenda_nome_curto(cl.name) from public.service_orders so
                             join public.clients cl on cl.id = so.client_id where so.id = r.service_order_id)) > 1
             then public._agenda_rotulo_da_os(r.service_order_id)
             else coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                              join public.clients cl on cl.id = so.client_id where so.id = r.service_order_id), 'serviço') end,
        coalesce(nullif(public._agenda_gestor_estimativa(r.service_order_id, p_hoje) ->> 'texto', ''),
                 case split_part(r.chave, ':', 3) when 'comecada' then 'já começou?' when 'rastro' then 'quanto falta?'
                                                  when 'parada' then 'ainda é para fazer?' when 'grande' then 'muitas diárias pela estimativa'
                                                  when 'embutida' then 'pode ter peça junto'
                                                  else 'não tem mão de obra separada' end),
        case when r.opcao_escolhida is not null then 'você vai me dizer os dias.'
             when r.veto_ate is not null
               then format('sem resposta até %s %s, marco assim.',
                           public._dia_curto((r.veto_ate at time zone 'America/Sao_Paulo')::date),
                           to_char(r.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI'))
             else 'espero você.' end);
    end loop;
    -- 4. quem fica de fora: o porquê da última conta do motor (a proposta de verdade mais nova que falou da OS, em 8 dias),
    -- das OS da carteira sem compromisso e sem pergunta aberta do gestor
    select coalesce(jsonb_agg(jsonb_build_object('os', t.os, 'cliente', t.cliente, 'motivo', t.motivo,
                                                 'grupo', public._agenda_gestor_motivo_texto(
                                                   -- (7a correção 2) a OS que o dono desfez: o porquê é o *desfaz*, não "sem lugar"
                                                   case when public._agenda_gestor_desfeito(t.os::uuid, v_f72_agora) then 'desfeito'
                                                        else t.motivo end)) order by t.numero), '[]'::jsonb)
      into v_fora
      from (select distinct on (f ->> 'os') f ->> 'os' as os, f ->> 'cliente_curto' as cliente, f ->> 'motivo' as motivo,
                   f ->> 'numero' as numero
              from public.agenda_propostas pr cross join lateral jsonb_array_elements(coalesce(pr.fora, '[]'::jsonb)) f
             where pr.modo = 'ligado' and pr.criada_em >= ((p_hoje - 8)::timestamp at time zone 'America/Sao_Paulo')
               and f ->> 'motivo' is distinct from 'fora_da_carteira'
               and (f ->> 'os')::uuid = any (v_cart)
               and not exists (select 1 from public.agenda_perguntas q
                                where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo in ('situacao', 'estimativa')
                                  and q.service_order_id = (f ->> 'os')::uuid)
             order by f ->> 'os', pr.criada_em desc, pr.id desc) t;
  end if;

  -- FASE 7b: (correção da revisão da 7b, achados 1, 9 e 15) onde o bloco "Quem chamar" começa
  v_7bc_n := coalesce(cardinality(v_l), 0);
  -- FASE 7b: fim
  -- FASE 7b: (7b P6, R4.4 "Onde aparece") o bloco "Quem chamar" (depois de "Perguntei antes de marcar"), só com modo_chamar fora de
  -- desligado: o que o passo diário chamar do gestor gravou (agenda_gestor_dia.chamar, a conta mais nova de até 3 dias; "pela conta de
  -- …" quando não é de hoje). Em teste, "Em teste:" na frente. Só sugere: quem chama é o dono.
  if cf.modo_chamar <> 'desligado' then
    select g.dia, g.chamar into v_7b_cdia, v_7b_ch from public.agenda_gestor_dia g
     where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.chamar ? 'calculado_em' order by g.dia desc limit 1;
    v_7b_cab := case when cf.modo_chamar = 'sombra' then 'Em teste: quem chamar' else 'Quem chamar' end;
    v_7b_pela := case when v_7b_cdia is not null and v_7b_cdia <> p_hoje then format('pela conta de %s', public._dia_curto(v_7b_cdia)) end;
    if v_7b_ch is null then
      v_l := v_l || (v_7b_cab || ': ainda não fiz a conta (faço todo dia útil no fim da tarde).');
    else
      v_7b_bul := array(select u.l from unnest(string_to_array(coalesce(v_7b_ch ->> 'texto', ''), E'\n')) with ordinality u(l, o)
                         where u.l like '•%' order by u.o);
      if cardinality(v_7b_bul) = 0 then
        v_l := v_l || (v_7b_cab || coalesce(' (' || v_7b_pela || ')', '') || ': ninguém — a equipe de hoje dá conta da carteira que está pronta.');
      else
        v_l := v_l || (v_7b_cab || ' (' || concat_ws('; ', v_7b_pela, 'só sugiro; quem chama é você') || '):') || v_7b_bul;
      end if;
    end if;
  end if;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 1, 9 e 15) o bloco "Quem chamar" sai do meio do foco: o corte (_agenda_gestor_juntar,
  -- no meio) o escondia com o texto_max de sempre — em teste ele é o único lugar da sugestão — e, em teste, ele tomava o lugar das linhas
  -- da 7a ("Fora:", "Se aprovar:"). Vai para o fim que sempre entra, logo antes do "Como eu conto" (abaixo).
  if cf.modo_chamar <> 'desligado' and coalesce(cardinality(v_l), 0) > v_7bc_n then
    v_7bc_ch := v_l[v_7bc_n + 1 : cardinality(v_l)];
    v_l := v_l[1 : v_7bc_n];
  end if;
  -- FASE 7b: fim
  -- 4. Fora: agrupado pelo porquê, os nomes (o número junto quando o nome se repete)
  if jsonb_array_length(v_fora) > 0 then
    v_l := v_l || ('Fora: ' || (
      select string_agg(g.grupo || ': ' || g.nomes, '; ' order by public._agenda_gestor_motivo_ordem(g.grupo), g.grupo)
        from (select h.grupo, public._agenda_lista(array_agg(h.nome || case when h.n > 1 then format(' (%s)', h.n) else '' end
                                                             order by h.primeiro), 4) as nomes
                from (select f ->> 'grupo' as grupo, f ->> 'cliente' as nome, count(*) as n, min(o) as primeiro
                        from jsonb_array_elements(v_fora) with ordinality t(f, o)
                       group by f ->> 'grupo', f ->> 'cliente') h
               group by h.grupo) g) || '.');
  end if;

  -- 5. as compras da semana (o diário do gestor; o P10 grava) e 6. os orçamentos que caberiam (o P12 grava): de até 3 dias
  select g.compras into v_comp from public.agenda_gestor_dia g
   where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.compras <> '[]'::jsonb order by g.dia desc limit 1;
  if jsonb_array_length(coalesce(v_comp, '[]'::jsonb)) > 0 then
    v_l := v_l || 'Compras da semana:'::text;
    -- (7a correção, achado 3) até 3 por seção: toda seção cabe com o "Como eu conto"
    v_l := v_l || array(select '• ' || (e ->> 'texto') from jsonb_array_elements(v_comp) with ordinality t(e, o)
                         where nullif(btrim(e ->> 'texto'), '') is not null order by o limit 3);
    v_k := (select count(*) from jsonb_array_elements(v_comp) e where nullif(btrim(e ->> 'texto'), '') is not null)::int;
    if v_k > 3 then
      v_l := v_l || format('(e mais %s em *agenda compras*)', v_k - 3);
    end if;
  end if;
  select g.orcamentos into v_orc from public.agenda_gestor_dia g
   where g.dia <= p_hoje and g.dia >= p_hoje - 3 and g.orcamentos <> '[]'::jsonb order by g.dia desc limit 1;
  if jsonb_array_length(coalesce(v_orc, '[]'::jsonb)) > 0 then
    v_l := v_l || 'Se aprovar:'::text;
    -- (7a correção, achado 3) até 3 (os de maior valor)
    v_l := v_l || array(select '• ' || (e ->> 'texto') from jsonb_array_elements(v_orc) with ordinality t(e, o)
                         where nullif(btrim(e ->> 'texto'), '') is not null order by o limit 3);
    v_k := (select count(*) from jsonb_array_elements(v_orc) e where nullif(btrim(e ->> 'texto'), '') is not null)::int;
    if v_k > 3 then
      v_l := v_l || format('(e mais %s %s)', v_k - 3, case when v_k - 3 = 1 then 'orçamento' else 'orçamentos' end);
    end if;
  end if;

  -- 7. como eu conto (todos os números dos parâmetros)
  -- (7a correção, achado 3) o "Como eu conto" à parte: entra sempre, no fim (_agenda_gestor_juntar)
  v_como := format('Como eu conto: estimativa pelo valor do orçamento (R$ %s de mão de obra por diária, sem deslocamento); '
                       || '%s por serviço (dupla quando você marcar); peça sem fornecedor: %s; peça abaixo de R$ %s: separar na '
                       || 'véspera; entre decidir e comprar: %s%s; pergunto antes acima de %s diárias e quando o serviço já começou.',
                       replace(to_char(round(v_mo), 'FM999,999,990'), ',', '.'),
                       case when cf.equipe_padrao = 1 then '1 pessoa' else cf.equipe_padrao || ' pessoas' end,
                       public._agenda_plural(cf.prazo_sem_fornecedor_du, 'dia útil', 'dias úteis'),
                       replace(to_char(round(cf.critico_valor_min), 'FM999,999,990'), ',', '.'),
                       public._agenda_plural(cf.compra_interna_du, 'dia útil', 'dias úteis'),
                       case when cf.compra_urgente_du > 0
                            then format(' (com o serviço a menos de %s, a compra é para hoje)',
                                        public._agenda_plural(cf.compra_urgente_du, 'dia útil', 'dias úteis'))
                            else '' end,
                       public._agenda_num(cf.estimativa_max_diarias));

  -- (7a correção, achado 3) o conteúdo até texto_max, e o "Como eu conto" (os parâmetros, spec §6.2 item 7) depois dele: as 7 seções
  -- da spec não cabem em texto_max com ele dentro, e era ele que sumia
  -- FASE 7b: (correção da revisão da 7b, achados 1, 9 e 15) o bloco "Quem chamar" entra no fim, junto do "Como eu conto": o conteúdo da
  -- 7a continua com o texto_max inteiro, e o bloco vem depois dele, até c_7bc_max letras (o resto "(e mais N linhas)")
  if cardinality(v_7bc_ch) > 0 then
    v_como := public._agenda_juntar(v_7bc_ch, c_7bc_max) || E'\n' || v_como;
  end if;
  -- (achado 9) e o que a 7b acrescentou às linhas da 7a (a frase da dupla de 1 pessoa, a da dupla que é só nota) não tira lugar das
  -- outras linhas da 7a: o conteúdo ganha esse tanto (nunca perde)
  cf.texto_max := cf.texto_max + greatest(v_7bc_mais, 0);
  -- FASE 7b: fim
  return jsonb_build_object('ok', true, 'texto', public._agenda_gestor_juntar(v_l, cf.texto_max + 1 + char_length(v_como), v_como),
                            'dados', jsonb_build_object('modo', v_ef, 'so_propor', cf.gestor_so_propor, 'conta_de', v_sdia,
                                                        'sombra', v_s, 'fora', v_fora));
end;
$function$;

comment on function public._agenda_ver_gestor(date) is
  'Agenda de Produção (Fase 7a, P7; spec §6.2): o foco gestor de agenda_ver — (1) o estado: "O gestor está em teste desde qui 29/10: calcula o que marcaria, mas não muda nada." / "Eu marco sozinho desde ter 03/11 e te conto no fechamento; *desfaz <nome>* volta qualquer coisa que eu fiz." / "Desde sex 06/11 você pediu *gestor, só propor*: eu só sugiro. *gestor, pode marcar* volta." / desligado; (2) em teste, "Eu marcaria:" pela última conta do diário (agenda_gestor_dia.sombra), um por linha ("• Lenine: ter 03 a ter 10/11, Roberto e João — 6 dias (estimativa minha). Pode precisar de dupla (banco de baterias): diga *Lenine com dupla*."); ligado, "Marquei nos últimos 7 dias:" (as OS com compromisso vigente pela estimativa); (3) "Antes de marcar eu perguntaria:" (teste) ou "Perguntei antes de marcar:" com o prazo ("• Giancarlo: 10 diárias pela estimativa — sem resposta até sex 30/10 18:00, marco assim."); (4) "Fora:" agrupado pelo porquê ("esperando o cliente: Kalmar (2) e Rodrigo; …"; ligado, pela última conta de verdade do motor em 8 dias); (5) "Compras da semana:" e (6) "Se aprovar:" pelo diário (agenda_gestor_dia.compras e .orcamentos, [{texto}], de até 3 dias; o P10 e o P12 gravam); (7) "Como eu conto:" com os parâmetros. {ok, texto (≤ texto_max), dados}. STABLE, invoker. CORREÇÃO DA 7a (revisão da etapa; achado 3): o "Como eu conto" entra sempre, no fim (_agenda_gestor_juntar: o corte é no meio, nunca num título sem linha embaixo, como o "Se aprovar:" vazio); as compras da semana e o "Se aprovar" mostram até 3 cada (o resto: "(e mais 3 orçamentos)", "(e mais N em *agenda compras*)"). CORREÇÃO 2 DA 7a (a 2ª revisão da etapa): (a dupla sem a 2ª pessoa) com menos de 2 técnicos na grade, "Pode precisar de dupla (banco de baterias): hoje só Alex está na equipe: para ir dupla, chame um ajudante e diga *Lenine com dupla*."; (o desfaz) ligado, a OS de fora que o dono desfez vai no grupo "você desfez (me diga os dias para eu marcar de novo)", não em "sem lugar na agenda"; (o número) em "Perguntei antes de marcar", o número da OS junto quando o nome se repete ("Kalmar (OS-00032)"). FASE 7b (P6, R4.4): com modo_chamar fora de desligado, o bloco "Quem chamar" depois de "Perguntei antes de marcar" — o que o passo diário chamar do gestor gravou (agenda_gestor_dia.chamar, a conta mais nova de até 3 dias; "pela conta de …" quando não é de hoje): "Quem chamar (só sugiro; quem chama é você):" e uma linha por sugestão, ou "Quem chamar: ninguém — a equipe de hoje dá conta da carteira que está pronta."; em teste, "Em teste: quem chamar …". Com modo_dupla fora de desligado, o "Pode precisar de dupla (…): … diga *Lenine com dupla*" do 7a vira a frase da dupla de 1 pessoa (R4.3(a)(3)): ligado, com as datas do plano (_agenda_dupla_no_plano: "Nos 2 primeiros meios-dias (ter 10/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem ter 10/11)."; com a dupla completa, nada); em teste do gestor, a forma curta sem as datas. Com modo_chamar e modo_dupla desligados, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 1, 5, 9, 11, 15 e 23): o bloco "Quem chamar" vai para o fim que sempre entra, logo antes do "Como eu conto" (até 700 letras; o conteúdo da 7a continua com o texto_max inteiro) — antes ele ficava no meio e o corte o escondia, ou tomava o lugar do "Fora:" e do "Se aprovar:"; com modo_dupla fora de desligado, a OS em que a dupla é só nota (o espaço confinado) continua com o "Pode precisar de dupla (espaço apertado): … diga *Otávio com dupla* (em dupla o tempo todo)." (com menos de 2 técnicos, "chame um ajudante, me diga os dias dele e diga …"), também ligado (antes sumia); o exemplo da dupla de 1 pessoa diz todos os dias em que falta a 2ª pessoa. CORREÇÃO 2 DA 7b (achado 26 da revisão da 7b, que é da 7a): no "Marquei nos últimos 7 dias", os dias de cada OS não contam o turno do dono nos meios-dias em que ele vai junto com alguém (o critério de _agenda_gestor_pessoa_meios: ele só é uma das pessoas quando o molde o conta — o turno inteiro e, além disso, a equipe dita, a regra uma_pessoa desligada, o diagnóstico ou o comissionamento) — o Lenine marcado com o Alex e você nos 6 dias dizia "Alex — 12 dias (estimativa minha)"; agora "6 dias". Com o dono contado pelo molde, a de antes, byte a byte.';

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar): ninguém chama
-- direto as duas da revisão (só a revisão e o reestimar do gestor, invoker, por dentro); o foco é leitura do painel e do assistente.
revoke all on function public._agenda_gestor_pessoa_meios(uuid, date, jsonb), public._agenda_gestor_corte(uuid, date, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public._agenda_ver_gestor(date) from public, anon;
grant execute on function public._agenda_ver_gestor(date) to authenticated, service_role;
