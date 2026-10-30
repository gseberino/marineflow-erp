-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P5: o teto da equipe-semana — cada técnico até 100% do
-- que se espera dele, a equipe inteira até a carga da semana (arredonda uma vez, na soma) — e o gancho do sábado de manhã.
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R, §3.1, §3.3 d8 e d9, §5.5, §8.4 T1–T7); nomes: fase7-registro.md §1 e §2
-- (a regra teto_equipe; a variável agenda.sabado; sabado_manha, AG7-08); o dono: fase7-padroes.md (AG7-02 — o dono é presença,
-- não capacidade de técnico; a medição de 30/10, item 3: no teto da equipe-semana o dono NÃO entra).
-- Depende da 20261031100000 (7a P1: o portão _agenda_gestor_regra, marcar_regras com teto_equipe, sabado_manha).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (5 funções recriadas; nenhuma nova; nenhuma tabela, coluna, lista, dado, cron ou tela muda)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7a/p5/montar-migration.mjs: as recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote e nas 20261031* do P1 ao
-- P4): _agenda_contexto e _agenda_validar_itens de 20261029100400 (a Fase 6: o lote não as recriou), _agenda_encaixar de
-- 20261030100200 (o lote P3; a spec dizia 20261025100200, que o lote recriou), _agenda_tentar_bloco e _agenda_por_que_nao de
-- 20261025100200 (as únicas). As mudanças estão só nos blocos "-- FASE 7: … -- FASE 7: fim"; fora deles nenhuma linha muda (o
-- T7 de supabase/tests/agenda_fase7a_teto.sql confere).
--
-- POR QUE: o teto de compromisso é floor(carga_max × esperado) POR PESSOA. Com a equipe pequena e o esperado quebrado (a semente
-- de 8 semanas: João 4,25 meios-dias na semana; ou um técnico que vem só alguns dias), o arredondamento pessoa a pessoa tira
-- quase um dia de cada um (João 3 de 4,25; Roberto 1 de 2: juntos 4 de 6,25) e o serviço que cabia na semana vai para a
-- seguinte. A folga de 20% é da equipe, para imprevisto da semana, não de cada pessoa (spec-fase7a §0 item 4, d8).
--
-- O QUE MUDA (atrás do portão _agenda_gestor_regra('teto_equipe'); com o portão falso, a saída de cada função recriada é a de
-- antes, byte a byte — o T5 do teste confere com as definições de antes rodadas no lugar, numa subtransação desfeita):
--   1. _agenda_contexto: cada pessoa da equipe (todas menos o dono) vai até 100% do que se espera dela na semana (teto80 =
--      teto100); a equipe inteira, até teto_equipe[semana] = floor(carga_max × a soma do esperado da equipe). O dono mantém o
--      teto dele (_agenda_carga_da_pessoa, a Fase 6) e fica fora da soma: ele é presença (abrir, fechar, diagnóstico). A saída
--      ganha teto_equipe (só com o portão).
--   2. _agenda_encaixar: no compromisso (classes 1 e 2) da OS que não usa o teto de 100% (acima_da_carga, o pedido do dono), o
--      bloco leva o teto da equipe (teq). As reservas não levam.
--   3. _agenda_tentar_bloco: com teq (e não reserva), os diaristas de cada meio-dia só entram se a soma da equipe na semana (o
--      compromisso de todos menos o dono, o vigente e o já posto) mais eles fica até o teto dela.
--   4. _agenda_validar_itens: a regra 6 faz a mesma conta (o compromisso de cada um até 100%; o dono com o teto dele; a soma da
--      equipe por semana até o teto, com o texto "A equipe passaria do limite da semana de 09/11: 11 meios-dias de serviço
--      para 10."). As outras regras não mudam.
--   5. _agenda_por_que_nao: "a equipe já está com a semana cheia" quando o teto da equipe é o que impede.
--   6. O gancho do sábado (_agenda_contexto; AG7-08): com a variável agenda.sabado = 'on' (só a decisão da pergunta crítica
--      sabado do P12 a liga, dentro da transação) e sabado_manha diferente de 'nunca', as manhãs de sábado do período (as que
--      ainda não são úteis e não são feriado) viram úteis, com lugar só para quem tem o padrão de sábado de manhã; a tarde fica
--      sem ninguém; o sábado não entra no esperado (o teto não sobe). Sem a variável, nada muda. Hoje ninguém tem padrão de
--      sábado: inerte.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_teto.sql; registradas em notas-fase77a.md, P5):
--   · _agenda_encaixar copiada de 20261030100200 (o lote P3, a mais nova), não de 20261025100200.
--   · O validador não soma na equipe o compromisso novo pedido pelo dono (fixar_dono) e só confere a semana que tem compromisso
--     novo da equipe fora dele: o encaixe põe o pedido do dono sem o teto da equipe, e ele pode vir na fila depois de outra OS
--     da mesma semana; contá-lo recusaria uma proposta que o próprio motor montou (agenda_propor não solta proposta inválida).
--     Com acima_da_carga, nenhuma conta da equipe (o encaixe também não a faz).
--   · A soma da equipe é das pessoas da grade (agenda_capacidade) menos o dono, como o contexto: alocação vigente de quem saiu da
--     equipe não entra (o contexto também não a vê).
--   · No sábado, só a manhã de quem tem o PADRÃO de sábado (dias_semana com o sábado) ganha lugar; a exceção "vem" num sábado
--     sem o padrão não ganha (a spec: "de quem tem padrão de sábado"), e a pessoa com exceção ou recesso naquele sábado também
--     não. O sábado que já é útil (sabado_util) não muda.
--   · "a equipe já está com a semana cheia" só aparece para a OS sem o teto de 100%: o único chamador de hoje (agenda_propor, o
--     "não cabe no dia que você pediu") é o pedido do dono, que não leva o teto da equipe — ali o texto não aparece.
--
-- O QUE NÃO MUDA: nenhuma tabela, coluna, lista fechada, dado, cron, tela ou função de borda. Com o portão falso (a linha de
-- agenda_config nasce com modo_marcar_sozinho = 'desligado'; em sombra, só dentro da simulação), nada muda para ninguém.
--
-- ORDEM DE LIGAR: depois de 20261031100300 (P4). Aplicar sozinha não muda nada (o portão é falso até o *ligar* do roteiro da §10
-- da spec; a regra sai sozinha tirando teto_equipe de marcar_regras).
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7a_teto.sql (begin/rollback; T0 a T7). Na bancada:
-- node scripts/bancada-agenda/rodar.mjs --ate 20261031100400
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100400_agenda_fase7a_teto.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261031100400', 'agenda_fase7a_teto');"
--
-- DESFAZER: sem migration, o portão (spec §10: *gestor, só propor*, ou modo_marcar_sozinho fora de 'ligado', ou teto_equipe fora
-- de marcar_regras): com ele falso, a saída é a de antes. Para tirar o código: recriar _agenda_contexto e _agenda_validar_itens
-- com o corpo de 20261029100400, _agenda_encaixar com o de 20261030100200 e _agenda_tentar_bloco e _agenda_por_que_nao com o de
-- 20261025100200 (a cópia sem os blocos "-- FASE 7:").
--
-- IDEMPOTENTE: create or replace function, revoke/grant e comment.

-- ── As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7:") ──────────────────────────
-- Fora dos blocos nenhuma linha muda (o T7 de supabase/tests/agenda_fase7a_teto.sql confere). Quem recriar de novo qualquer
-- uma delas copia DESTA migration (fase7-registro.md §2: _agenda_contexto, _agenda_tentar_bloco, _agenda_encaixar e
-- _agenda_validar_itens no 7b P4; _agenda_por_que_nao no 7c P2).

-- _agenda_contexto (de 20261029100400_agenda_fase6_dono.sql)
create or replace function public._agenda_contexto(p_d_ini date, p_d_fim date, p_hoje date,
                                                   p_ignorar uuid[] default '{}'::uuid[], p_fila uuid[] default '{}'::uuid[])
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_nd    int;
  v_nh    int;
  v_seg   date;
  v_nw    int;
  v_g     jsonb;
  v_pes   uuid[];
  v_nomes text[];
  v_np    int;
  v_dono  int := 0;
  v_oss   uuid[] := coalesce(p_fila, '{}'::uuid[]);
  v_cap   int[];
  v_esp   numeric[];
  v_curta int[];
  v_ocup  int[];
  v_fr    int[];
  v_util  boolean[];
  v_sem   int[];
  v_espw  numeric[];
  v_t80   int[];
  v_t100  int[];
  v_uc    int[];
  v_ur    int[];
  v_loc   int[];
  v_padrao boolean;
  r       record;
  v_h     int;
  v_cel   int;
  v_mark  int;
  v_w     int;
  v_k     int;
  s       int;
  v_achou boolean;
  -- FASE 6: a carga de cada pessoa no teto de compromisso (o índice da pessoa e da semana; v_pp/v_ww: pp e ww são nomes de
  -- coluna da consulta do teto)
  v_pp    int;
  v_ww    int;
  v_carga numeric;
  -- FASE 6: fim
  -- FASE 7: (7a P5) o teto da equipe-semana (a regra teto_equipe do gestor) e o gancho do sábado (a variável agenda.sabado)
  v_f7_teq  boolean := public._agenda_gestor_regra('teto_equipe');
  v_f7_te   int[];
  v_f7_soma numeric;
  v_f7_sab  boolean;
  v_f7_cel  int;
  v_f7_quem int[];
  -- FASE 7: fim
begin
  if p_d_ini is null or p_d_fim is null or p_d_fim < p_d_ini then
    raise exception 'agenda: período inválido para a grade (% a %)', p_d_ini, p_d_fim using errcode = '22023';
  end if;
  v_nd := p_d_fim - p_d_ini + 1;
  v_nh := 2 * v_nd;
  v_seg := p_d_ini - (extract(isodow from p_d_ini)::int - 1);
  v_nw := (p_d_fim - v_seg) / 7 + 1;

  select coalesce(jsonb_agg(to_jsonb(g) order by g.eh_dono desc, g.nome, g.payee_id, g.dia, g.turno = 'tarde'), '[]'::jsonb)
    into v_g
    from public.agenda_grade(p_d_ini, p_d_fim, p_hoje, coalesce(p_ignorar, '{}'::uuid[])) g;

  -- As pessoas: você primeiro, depois a equipe pelo nome (a ordem da grade).
  select coalesce(array_agg(q.payee_id order by q.eh_dono desc, q.nome, q.payee_id), '{}'::uuid[]),
         coalesce(array_agg(q.nome order by q.eh_dono desc, q.nome, q.payee_id), '{}'::text[]),
         coalesce(bool_or(q.eh_dono), false)
    into v_pes, v_nomes, v_padrao
    from (select distinct (e ->> 'payee_id')::uuid as payee_id, e ->> 'nome' as nome, (e ->> 'eh_dono')::boolean as eh_dono
            from jsonb_array_elements(v_g) e) q;
  v_np := cardinality(v_pes);
  if v_padrao then v_dono := 1; end if;

  -- O esperado só conta dia útil: o sábado combinado ("o Roberto vem sábado") a agenda automática não marca, e contá-lo
  -- subiria o teto dos dias úteis (10 meios + 2 do sábado = teto de 9, 90% da semana útil).
  select coalesce(array_agg(case when e ->> 'situacao' = 'livre' then 1 else 0 end order by o), '{}'::int[]),
         coalesce(array_agg(case when public.agenda_dia_util((e ->> 'dia')::date) then (e ->> 'meios_esperados')::numeric else 0 end
                            order by o), '{}'::numeric[])
    into v_cap, v_esp
    from jsonb_array_elements(v_g) with ordinality t(e, o);
  if coalesce(cardinality(v_cap), 0) <> v_np * v_nh then
    raise exception 'agenda: a grade veio incompleta (% células para % pessoas × % meios-dias)', cardinality(v_cap), v_np, v_nh;
  end if;

  -- As pontas livres do dono: bit 1 = abertura, bit 2 = fechamento.
  v_curta := array_fill(0, array[v_nh]);
  if v_dono > 0 then
    select array_agg((case when e -> 'curta_livre' ? 'abertura' then 1 else 0 end)
                     + (case when e -> 'curta_livre' ? 'fechamento' then 2 else 0 end) order by o)
      into v_curta
      from jsonb_array_elements(v_g) with ordinality t(e, o)
     where o <= v_nh;
  end if;
  v_padrao := v_dono > 0 and exists (select 1 from jsonb_array_elements(v_g) with ordinality t(e, o)
                                      where o <= v_nh and e ->> 'situacao' = 'livre');

  -- As OS: as da fila primeiro (o índice delas é a posição), depois as que já ocupam a grade.
  v_oss := v_oss || coalesce(array(
    select distinct a.service_order_id from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.dia between p_d_ini and p_d_fim
       and not (a.id = any (coalesce(p_ignorar, '{}'::uuid[]))) and not (a.service_order_id = any (v_oss))
     order by 1), '{}'::uuid[]);

  -- O que o plano vigente já ocupa: célula, frentes e uso da semana (compromisso e reserva).
  v_ocup := array_fill(0, array[greatest(v_np * v_nh, 1)]);
  v_fr := array_fill(0, array[v_nh * 4]);
  v_uc := array_fill(0, array[greatest(v_np * v_nw, 1)]);
  v_ur := array_fill(0, array[greatest(v_np * v_nw, 1)]);
  for r in
    select a.dia, a.turno, a.presenca, a.tipo, array_position(v_pes, a.payee_id) as pi,
           array_position(v_oss, a.service_order_id) as oi
      from public.agenda_alocacoes a
     where a.estado in ('publicada', 'fixada') and a.dia between p_d_ini and p_d_fim
       and not (a.id = any (coalesce(p_ignorar, '{}'::uuid[])))
     order by a.dia, a.turno = 'tarde', a.service_order_id, a.payee_id, a.id
  loop
    v_h := 2 * (r.dia - p_d_ini) + case when r.turno = 'tarde' then 2 else 1 end;
    v_mark := case when r.tipo = 'reserva' then -r.oi else r.oi end;
    if r.pi is not null then
      v_cel := (r.pi - 1) * v_nh + v_h;
      if v_ocup[v_cel] = 0 or (v_ocup[v_cel] < 0 and v_mark > 0) then v_ocup[v_cel] := v_mark; end if;
      if r.presenca = 'turno' then
        v_w := (r.dia - v_seg) / 7 + 1;
        v_k := (r.pi - 1) * v_nw + v_w;
        if r.tipo = 'reserva' then v_ur[v_k] := v_ur[v_k] + 1; else v_uc[v_k] := v_uc[v_k] + 1; end if;
      end if;
    end if;
    v_achou := false;
    for s in 1 .. 4 loop
      v_k := (v_h - 1) * 4 + s;
      if abs(v_fr[v_k]) = r.oi then
        if v_fr[v_k] < 0 and v_mark > 0 then v_fr[v_k] := v_mark; end if;
        v_achou := true;
        exit;
      end if;
    end loop;
    if not v_achou then
      for s in 1 .. 4 loop
        v_k := (v_h - 1) * 4 + s;
        if v_fr[v_k] = 0 then v_fr[v_k] := v_mark; exit; end if;
      end loop;
    end if;
  end loop;

  select array_agg(public.agenda_dia_util(p_d_ini + g) order by g), array_agg(((p_d_ini + g) - v_seg) / 7 + 1 order by g)
    into v_util, v_sem
    from generate_series(0, v_nd - 1) g;
  -- FASE 7: (7a P5) o gancho do sábado (AG7-08; spec-fase7a §5.5 e d9). Só com a variável agenda.sabado = 'on' — quem a liga
  -- é a decisão da pergunta crítica sabado (P12), dentro da transação, e a desliga em seguida — e com sabado_manha diferente de
  -- 'nunca': a manhã de cada sábado do período que ainda não é útil (sabado_util desligado) e não é feriado vira útil, com
  -- lugar só para quem tem o padrão de sábado de manhã (linha vigente de agenda_disponibilidade com dias_semana contendo o
  -- sábado, de manhã ou o dia todo, vem) e não tem exceção nem recesso que tire aquele dia (a grade já diz 'indisponivel'); a
  -- tarde fica sem ninguém. O sábado em que ninguém pode vir não muda (útil e vazio, ele contaria como dia parado de todo
  -- serviço que o atravessa). O sábado não entra no esperado: o teto da semana não sobe (o esperado já foi lido acima, só de
  -- dia útil). Sem a variável, nada muda.
  v_f7_sab := coalesce(current_setting('agenda.sabado', true), '') = 'on' and cf.sabado_manha <> 'nunca';
  if v_f7_sab then
    for f7_d in 1 .. v_nd loop
      continue when extract(isodow from p_d_ini + f7_d - 1)::int <> 6 or v_util[f7_d]
                    or public.agenda_feriado(p_d_ini + f7_d - 1) is not null;
      -- quem vem nessa manhã: o padrão de sábado, sem exceção nem recesso no dia (a célula da manhã na grade é a
      -- (pessoa − 1) × nh + 2 × (dia − 1) + 1; o jsonb conta de 0)
      v_f7_quem := array(select g.p from generate_series(1, coalesce(v_np, 0)) g(p)
                          where (v_g -> ((g.p - 1) * v_nh + 2 * (f7_d - 1)) ->> 'situacao') is distinct from 'indisponivel'
                            and exists (select 1 from public.agenda_disponibilidade d
                                         where d.payee_id = v_pes[g.p] and d.substituida_em is null
                                           and d.dias_semana @> array[6]::smallint[]
                                           and d.situacao in ('disponivel', 'confirmada')
                                           and (d.turno is null or d.turno = 'manha'))
                          order by g.p);
      continue when cardinality(v_f7_quem) = 0;
      v_util[f7_d] := true;
      for f7_p in 1 .. coalesce(v_np, 0) loop
        v_f7_cel := (f7_p - 1) * v_nh + 2 * (f7_d - 1) + 1;   -- a manhã de f7_p nesse sábado (a tarde é a célula seguinte)
        v_cap[v_f7_cel] := case when f7_p = any (v_f7_quem) then 1 else 0 end;
        v_cap[v_f7_cel + 1] := 0;
      end loop;
    end loop;
  end if;
  -- FASE 7: fim

  -- O esperado de cada pessoa por semana ISO e os dois tetos: compromisso (carga_max) e compromisso + reserva (100%).
  with cel as (
    select (u.o - 1) / v_nh + 1 as p, ((u.o - 1) % v_nh) / 2 + 1 as d, u.x as esp
      from unnest(v_esp) with ordinality u(x, o)
  ),
  soma as (select cel.p, (v_sem)[cel.d] as w, sum(cel.esp) as e from cel group by 1, 2)
  select coalesce(array_agg(coalesce(soma.e, 0) order by pp, ww), '{}'::numeric[]),
         coalesce(array_agg(floor(cf.carga_max * coalesce(soma.e, 0))::int order by pp, ww), '{}'::int[]),
         coalesce(array_agg(floor(coalesce(soma.e, 0))::int order by pp, ww), '{}'::int[])
    into v_espw, v_t80, v_t100
    from generate_series(1, greatest(v_np, 1)) pp
    cross join generate_series(1, v_nw) ww
    left join soma on soma.p = pp and soma.w = ww
   where v_np > 0;
  -- FASE 6: (P4) a carga de cada pessoa (spec-fase6 §5.4): o teto de compromisso da semana é floor(carga × esperado), com a
  -- carga de _agenda_carga_da_pessoa (o dono com capacidade_dono em uso; os outros, e o dono sem nada em uso, carga_max). A
  -- pessoa pp é v_pes[pp] (a mesma ordem da grade: você primeiro) e a célula dela na semana ww é (pp − 1) × nw + ww — a
  -- ordem "order by pp, ww" do array_agg de cima, a mesma de esperado. Só a pessoa com outra carga muda; com o modo fora de
  -- ligado (ou sem o item na lista, ou nada em uso), nada muda: a saída é a de antes, byte a byte.
  for v_pp in 1 .. coalesce(v_np, 0) loop
    v_carga := public._agenda_carga_da_pessoa(v_pes[v_pp]);
    continue when v_carga = cf.carga_max;
    for v_ww in 1 .. v_nw loop
      v_t80[(v_pp - 1) * v_nw + v_ww] := floor(v_carga * v_espw[(v_pp - 1) * v_nw + v_ww])::int;
    end loop;
  end loop;
  -- FASE 6: fim

  -- FASE 7: (7a P5) o teto da equipe-semana (a regra teto_equipe; spec-fase7a §5.5 e d8). Com o portão, cada pessoa da equipe
  -- (todas menos o dono) pode chegar a 100% do que se espera dela na semana (o teto de compromisso vira o de 100%: teto80 =
  -- teto100), e a equipe inteira, a floor(carga_max × a soma do esperado dela) — arredonda uma vez, na soma, e não pessoa a
  -- pessoa (João 4,25 e Roberto 2 esperados: por pessoa 3 + 1 = 4; a equipe, floor(0,8 × 6,25) = 5). O dono continua com o
  -- teto dele (_agenda_carga_da_pessoa, a Fase 6, logo acima) e fica fora da conta da equipe: ele é presença (abrir, fechar,
  -- diagnóstico), não capacidade de técnico. A saída ganha teto_equipe (um número por semana, na ordem de sem). Sem o portão,
  -- nada muda.
  if v_f7_teq then
    v_f7_te := '{}'::int[];
    for f7_w in 1 .. v_nw loop
      v_f7_soma := 0;
      for f7_p in 1 .. coalesce(v_np, 0) loop
        continue when f7_p = v_dono;
        v_f7_soma := v_f7_soma + coalesce(v_espw[(f7_p - 1) * v_nw + f7_w], 0);
        v_t80[(f7_p - 1) * v_nw + f7_w] := v_t100[(f7_p - 1) * v_nw + f7_w];
      end loop;
      v_f7_te := v_f7_te || floor(cf.carga_max * v_f7_soma)::int;
    end loop;
  end if;
  -- FASE 7: fim
  -- O local de cada OS (a marina, senão a cidade do cliente), para o desempate "mesmo local".
  select coalesce(array_agg(q.loc order by q.o), '{}'::int[]) into v_loc
    from (select k.o, case when k.chave is null then 0 else dense_rank() over (order by k.chave)::int end as loc
            from (select u.o, coalesce('m:' || so.marina_id::text, 'c:' || nullif(lower(btrim(cl.city)), '')) as chave
                    from unnest(v_oss) with ordinality u(os, o)
                    left join public.service_orders so on so.id = u.os
                    left join public.clients cl on cl.id = so.client_id) k) q;

  -- FASE 7: (7a P5) com o portão do teto da equipe, a mesma saída de baixo (chave a chave; o T7 de
  -- supabase/tests/agenda_fase7a_teto.sql confere que só teto80 e teto_equipe mudam) com o teto da equipe por semana.
  if v_f7_teq then
    return jsonb_build_object(
      'd_ini', p_d_ini, 'd_fim', p_d_fim, 'seg', v_seg, 'nd', v_nd, 'nh', v_nh, 'np', v_np, 'nw', v_nw,
      'dono', v_dono, 'dono_tem_padrao', v_padrao,
      'pessoas', to_jsonb(v_pes), 'nomes', to_jsonb(v_nomes), 'oss', to_jsonb(v_oss),
      'util', to_jsonb(v_util), 'sem', to_jsonb(v_sem), 'cap', to_jsonb(v_cap), 'curta', to_jsonb(v_curta),
      'ocup', to_jsonb(v_ocup), 'fr', to_jsonb(v_fr), 'esperado', to_jsonb(coalesce(v_espw, '{}'::numeric[])),
      'teto80', to_jsonb(coalesce(v_t80, '{}'::int[])), 'teto100', to_jsonb(coalesce(v_t100, '{}'::int[])),
      'uso_c', to_jsonb(v_uc), 'uso_r', to_jsonb(v_ur), 'loc', to_jsonb(v_loc),
      'teto_equipe', to_jsonb(coalesce(v_f7_te, '{}'::int[])));
  end if;
  -- FASE 7: fim
  return jsonb_build_object(
    'd_ini', p_d_ini, 'd_fim', p_d_fim, 'seg', v_seg, 'nd', v_nd, 'nh', v_nh, 'np', v_np, 'nw', v_nw,
    'dono', v_dono, 'dono_tem_padrao', v_padrao,
    'pessoas', to_jsonb(v_pes), 'nomes', to_jsonb(v_nomes), 'oss', to_jsonb(v_oss),
    'util', to_jsonb(v_util), 'sem', to_jsonb(v_sem), 'cap', to_jsonb(v_cap), 'curta', to_jsonb(v_curta),
    'ocup', to_jsonb(v_ocup), 'fr', to_jsonb(v_fr), 'esperado', to_jsonb(coalesce(v_espw, '{}'::numeric[])),
    'teto80', to_jsonb(coalesce(v_t80, '{}'::int[])), 'teto100', to_jsonb(coalesce(v_t100, '{}'::int[])),
    'uso_c', to_jsonb(v_uc), 'uso_r', to_jsonb(v_ur), 'loc', to_jsonb(v_loc));
end;
$function$;

comment on function public._agenda_contexto(date, date, date, uuid[], uuid[]) is
  'Agenda de Produção (Fase 2, P2): a grade do motor em arrays (agenda_grade de p_d_ini a p_d_fim, sem as alocações de p_ignorar): pessoas (você primeiro), dias úteis, semana ISO de cada dia, quem está livre em cada meio-dia (cap), as pontas livres do dono (curta: 1 abertura, 2 fechamento), o que o vigente ocupa (ocup, frentes: o índice da OS em oss, negativo = reserva), o uso por pessoa e semana (compromisso e reserva) e os tetos floor(carga_max × esperado) e floor(esperado) — o esperado só de dia útil (o sábado combinado não sobe o teto). As OS de p_fila vêm primeiro em oss. FASE 6 (P4): o teto80 de cada pessoa usa _agenda_carga_da_pessoa (o dono com capacidade_dono em uso: floor(carga dele × esperado); os outros, carga_max) — a posição (pp − 1) × nw + ww é a pessoa v_pes[pp] na semana ww; fora de ligado, a saída de antes. FASE 7 (7a P5), atrás do portão _agenda_gestor_regra(''teto_equipe'') (falso = a saída de antes, byte a byte): cada pessoa da equipe (todas menos o dono) pode chegar a 100% do esperado dela na semana (teto80 = teto100); a equipe inteira, a teto_equipe[semana] = floor(carga_max × a soma do esperado da equipe), arredondado uma vez, na soma; o dono mantém o teto dele (_agenda_carga_da_pessoa) e fica fora da soma (é presença, não capacidade de técnico); a saída ganha teto_equipe (um número por semana, na ordem de sem). O gancho do sábado (AG7-08): só com a variável agenda.sabado = ''on'' (a decisão da pergunta crítica sabado a liga) e sabado_manha diferente de nunca, a manhã de cada sábado que ainda não é útil e não é feriado vira útil, com lugar só para quem tem o padrão de sábado de manhã (sem exceção nem recesso naquele dia); a tarde fica sem ninguém; o sábado não entra no esperado (o teto não sobe). Sem a variável, nada muda.';

-- _agenda_tentar_bloco (de 20261025100200_agenda_fase2_motor.sql)
create or replace function public._agenda_tentar_bloco(
  p_g jsonb, p_util boolean[], p_sem int[], p_cap int[], p_curta int[], p_ocup int[], p_fr int[],
  p_teto int[], p_uso int[], p_rest int[], p_loc int[], p_o jsonb, p_d0 int, p_reserva boolean, p_min_h int)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_nh    int := (p_g ->> 'nh')::int;
  v_nd    int := (p_g ->> 'nd')::int;
  v_np    int := (p_g ->> 'np')::int;
  v_nw    int := (p_g ->> 'nw')::int;
  v_dono  int := (p_g ->> 'dono')::int;
  v_wip   int := (p_g ->> 'wip')::int;
  v_imax  int := (p_g ->> 'imax')::int;
  v_i     int := (p_o ->> 'i')::int;
  v_n     int := coalesce((p_o ->> 'passos')::int, 0);
  v_abre  boolean := not p_reserva and coalesce((p_o ->> 'abre')::boolean, false);
  v_fecha boolean := not p_reserva and coalesce((p_o ->> 'fecha')::boolean, false);
  v_dtm   boolean := not p_reserva and coalesce((p_o ->> 'dt_m')::boolean, false);
  v_dtt   boolean := not p_reserva and coalesce((p_o ->> 'dt_t')::boolean, false);
  v_dm    int := coalesce((p_o ->> 'dm')::int, 0);
  v_dtd   int := coalesce((p_o ->> 'dtd')::int, 0);
  v_pm    int[] := public._agenda_ints(p_o -> 'pm');
  v_pt    int[] := public._agenda_ints(p_o -> 'pt');
  v_fixa  int := coalesce((p_o ->> 'fixa')::int, 0);
  v_bem   int[] := public._agenda_ints(p_o -> 'bem');
  v_loc   int;
  v_uso   int[] := p_uso;
  v_rest  int[] := p_rest;   -- o que ainda cabe até 100% (compromisso + reserva), por pessoa e semana
  v_ap    int[] := '{}';
  v_ah    int[] := '{}';
  v_apr   int[] := '{}';
  v_prev  int[] := '{}';
  v_esc   int[];
  v_cand  int[];
  v_h     int;
  v_d     int;
  v_t     int;
  v_w     int;
  v_dia   int;
  v_prog  int := 0;
  v_trab  boolean := true;
  v_k     int := 0;
  v_ini   int;
  v_ult   int;
  v_fim   int;
  v_int   int := 0;
  v_md    int := 0;
  v_mesmo boolean := false;
  v_ok    boolean;
  v_role  int;
  v_need  int;
  v_nf    int;
  v_self  boolean;
  v_mh    boolean;
  v_cel   int;
  x       int;
  s       int;
  q       int;
  -- FASE 7: (7a P5) o teto da equipe-semana (teq, que o encaixe só manda no compromisso) e a soma da equipe (sem o dono) em
  -- cada semana, que anda com os diaristas postos no bloco
  v_teq   int[] := case when p_g ? 'teq' and not p_reserva then public._agenda_ints(p_g -> 'teq') end;
  v_equ   int[];
  -- FASE 7: fim
begin
  if v_n <= 0 or p_d0 is null or p_d0 < 1 or p_d0 > v_nd then return null; end if;
  if not p_util[p_d0] or p_d0 = any (v_bem) then return null; end if;
  v_loc := coalesce(p_loc[v_i], 0);
  v_h := 2 * (p_d0 - 1) + 1;
  v_dia := p_d0;
  -- FASE 7: (7a P5) a soma da equipe na semana, de partida: o uso de compromisso de todos menos o dono (p_uso, o mesmo que o
  -- teto de cada um lê)
  if v_teq is not null then
    v_equ := array_fill(0, array[greatest(v_nw, 1)]);
    for f7_x in 1 .. v_np loop
      continue when f7_x = v_dono;
      for f7_w in 1 .. v_nw loop
        v_equ[f7_w] := v_equ[f7_w] + coalesce(p_uso[(f7_x - 1) * v_nw + f7_w], 0);
      end loop;
    end loop;
  end if;
  -- FASE 7: fim

  while v_k < v_n loop
    if v_h > v_nh then return null; end if;
    v_d := (v_h + 1) / 2;
    if v_d <> v_dia then
      if v_ini is null then return null; end if;                -- o 1º passo tem de sair no dia d0
      if v_trab and v_prog = 0 then
        v_int := v_int + 1;
        if v_int > v_imax then return null; end if;
      end if;
      v_dia := v_d;
      v_prog := 0;
      v_trab := p_util[v_d] and not (v_d = any (v_bem));
    end if;
    if not v_trab or v_h < p_min_h then
      v_h := v_h + 1;
      continue;
    end if;
    v_t := case when v_h % 2 = 1 then 1 else 2 end;
    v_w := p_sem[v_d];

    -- As frentes: a OS já tem um passo nesse meio-dia (no vigente) = não; senão no máximo wip_max OS distintas.
    v_nf := 0;
    v_self := false;
    v_mh := false;
    for s in 1 .. 4 loop
      x := p_fr[(v_h - 1) * 4 + s];
      continue when x = 0;
      if abs(x) = v_i then
        if x > 0 then v_self := true; end if;
      else
        v_nf := v_nf + 1;
        if v_loc > 0 and p_loc[abs(x)] = v_loc then v_mh := true; end if;
      end if;
    end loop;
    v_ok := not v_self and v_nf < v_wip;

    -- O dono: o turno inteiro (sempre, ou nos turnos em que ele está na equipe) ou a abertura do 1º passo.
    v_role := 0;
    if v_ok and ((v_t = 1 and v_dtm) or (v_t = 2 and v_dtt)) then
      v_cel := (v_dono - 1) * v_nh + v_h;
      if v_dono > 0 and p_cap[v_cel] = 1 and p_ocup[v_cel] in (0, -v_i)
         and v_uso[(v_dono - 1) * v_nw + v_w] < p_teto[(v_dono - 1) * v_nw + v_w]
         and v_rest[(v_dono - 1) * v_nw + v_w] > 0 then
        v_role := 1;
      else
        v_ok := false;
      end if;
    elsif v_ok and v_k = 0 and v_abre then
      if v_dono > 0 and (p_curta[v_h] & 1) = 1 then v_role := 2; else v_ok := false; end if;
    end if;

    -- A equipe: quem o dono disse para o turno; quem faltar é trocado por outro diarista livre (quem estava no
    -- meio-dia anterior desta OS, a menor carga na semana, a ordem do nome); abaixo do desejado = lacuna.
    if v_ok then
      v_need := case when v_t = 1 then v_dm else v_dtd end;
      if v_fixa > 0 and v_fixa <> v_dono then v_need := greatest(v_need, 1); end if;
      if v_need = 0 and v_role <> 1 then v_ok := false; end if;
    end if;
    if v_ok then
      v_esc := '{}';
      if v_fixa > 0 and v_fixa <> v_dono then
        v_cel := (v_fixa - 1) * v_nh + v_h;
        if p_cap[v_cel] = 1 and p_ocup[v_cel] in (0, -v_i)
           and v_uso[(v_fixa - 1) * v_nw + v_w] < p_teto[(v_fixa - 1) * v_nw + v_w]
           and v_rest[(v_fixa - 1) * v_nw + v_w] > 0 then
          v_esc := array[v_fixa];
        else
          v_ok := false;
        end if;
      end if;
    end if;
    if v_ok then
      foreach q in array (case when v_t = 1 then v_pm else v_pt end) loop
        exit when cardinality(v_esc) >= v_need;
        continue when q = v_dono or q = any (v_esc);
        v_cel := (q - 1) * v_nh + v_h;
        if p_cap[v_cel] = 1 and p_ocup[v_cel] in (0, -v_i)
           and v_uso[(q - 1) * v_nw + v_w] < p_teto[(q - 1) * v_nw + v_w]
           and v_rest[(q - 1) * v_nw + v_w] > 0 then
          v_esc := v_esc || q;
        end if;
      end loop;
      if cardinality(v_esc) < v_need then
        select coalesce(array_agg(g.q order by (g.q = any (v_prev)) desc, (v_uso)[(g.q - 1) * v_nw + v_w], g.q), '{}'::int[])
          into v_cand
          from generate_series(1, v_np) g(q)
         where g.q <> v_dono and not (g.q = any (v_esc))
           and (p_cap)[(g.q - 1) * v_nh + v_h] = 1 and (p_ocup)[(g.q - 1) * v_nh + v_h] in (0, -v_i)
           and (v_uso)[(g.q - 1) * v_nw + v_w] < (p_teto)[(g.q - 1) * v_nw + v_w]
           and (v_rest)[(g.q - 1) * v_nw + v_w] > 0;
        foreach q in array v_cand loop
          exit when cardinality(v_esc) >= v_need;
          v_esc := v_esc || q;
        end loop;
      end if;
      if cardinality(v_esc) < v_need then v_ok := false; end if;
    end if;

    -- FASE 7: (7a P5) o teto da equipe: os diaristas deste meio-dia só entram se a equipe (sem o dono) fica até o teto dela na
    -- semana — a soma de antes + os escolhidos agora <= teq, o mesmo que exigir, um a um, a soma abaixo do teto (o meio-dia é
    -- tudo ou nada: sem os diaristas que pede, é lacuna). Meio-dia sem diarista (só o dono no turno) não tem o que conferir.
    if v_ok and v_teq is not null and cardinality(v_esc) > 0
       and v_equ[v_w] + cardinality(v_esc) > coalesce(v_teq[v_w], 0) then
      v_ok := false;
    end if;
    -- FASE 7: fim
    if v_ok then
      if v_role = 1 then
        v_ap := v_ap || v_dono; v_ah := v_ah || v_h; v_apr := v_apr || 0;
        v_uso[(v_dono - 1) * v_nw + v_w] := v_uso[(v_dono - 1) * v_nw + v_w] + 1;
        v_rest[(v_dono - 1) * v_nw + v_w] := v_rest[(v_dono - 1) * v_nw + v_w] - 1;
        v_md := v_md + 1;
      elsif v_role = 2 then
        v_ap := v_ap || v_dono; v_ah := v_ah || v_h; v_apr := v_apr || 1;
      end if;
      foreach q in array v_esc loop
        v_ap := v_ap || q; v_ah := v_ah || v_h; v_apr := v_apr || 0;
        v_uso[(q - 1) * v_nw + v_w] := v_uso[(q - 1) * v_nw + v_w] + 1;
        v_rest[(q - 1) * v_nw + v_w] := v_rest[(q - 1) * v_nw + v_w] - 1;
      end loop;
      v_prev := v_esc;
      -- FASE 7: (7a P5) a soma da equipe na semana anda com os diaristas postos neste meio-dia
      if v_teq is not null then
        v_equ[v_w] := v_equ[v_w] + cardinality(v_esc);
      end if;
      -- FASE 7: fim
      if v_mh then v_mesmo := true; end if;
      v_k := v_k + 1;
      v_prog := v_prog + 1;
      if v_ini is null then v_ini := v_h; end if;
      v_ult := v_h;
    end if;
    v_h := v_h + 1;
  end loop;

  -- O fechamento do dono: na última ponta do último passo; ocupada, desliza para o próximo meio-dia útil com a ponta
  -- livre (o bloco termina ali).
  v_fim := v_ult;
  if v_fecha then
    if (p_curta[v_ult] & 2) = 2 then
      v_ap := v_ap || v_dono; v_ah := v_ah || v_ult; v_apr := v_apr || 2;
    else
      v_fim := null;
      v_h := v_ult + 1;
      while v_h <= v_nh loop
        v_d := (v_h + 1) / 2;
        if p_util[v_d] and not (v_d = any (v_bem)) and v_h >= p_min_h and (p_curta[v_h] & 2) = 2 then
          v_nf := 0;
          v_self := false;
          for s in 1 .. 4 loop
            x := p_fr[(v_h - 1) * 4 + s];
            continue when x = 0;
            if abs(x) = v_i then
              if x > 0 then v_self := true; end if;
            else
              v_nf := v_nf + 1;
            end if;
          end loop;
          if not v_self and v_nf < v_wip then
            v_ap := v_ap || v_dono; v_ah := v_ah || v_h; v_apr := v_apr || 2;
            v_fim := v_h;
            exit;
          end if;
        end if;
        v_h := v_h + 1;
      end loop;
      if v_fim is null then return null; end if;
    end if;
  end if;

  return jsonb_build_object('d0', p_d0, 'ini', v_ini, 'fim', v_fim, 'int', v_int, 'md', v_md, 'mesmo', v_mesmo,
                            'p', to_jsonb(v_ap), 'h', to_jsonb(v_ah), 'pr', to_jsonb(v_apr));
end;
$function$;

comment on function public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer) is
  'Agenda de Produção (Fase 2, P2): tenta encaixar a OS p_o (i, passos, abre, fecha, dt_m/dt_t = o dono o turno inteiro, dm/dtd = diaristas desejados, pm/pt = os ditos por turno, fixa = a pessoa pedida, bem = dias com o bem fora) começando no dia p_d0. O bloco começa no 1º meio-dia de d0 em que o 1º passo sai inteiro; cada passo pede: no máximo wip_max OS no meio-dia (contando a própria), o dono conforme o molde (turno livre e abaixo do teto, ou a ponta da abertura no 1º), e os diaristas desejados (os ditos, senão trocados por quem estava no meio-dia anterior, a menor carga, o nome) livres, abaixo do teto (p_teto × p_uso) e com lugar na semana inteira (p_rest = 100% − compromisso − reserva); meio-dia sem o desejado = lacuna; dia útil inteiro sem passo depois de começar = interrupção (mais que interrupcoes_max = inválido); dia não útil e bem fora são pulados. O fechamento vai na última ponta ou desliza para a próxima ponta livre. Reserva (p_reserva) = só diaristas, sem o dono. Devolve {d0, ini, fim, int, md (turnos do dono), mesmo (local), p[], h[], pr[] (0 turno, 1 abertura, 2 fechamento)} ou null. FASE 7 (7a P5): com o teto da equipe em p_g (teq, que o encaixe só manda no compromisso da OS sem o teto de 100%) e fora da reserva, os diaristas de cada meio-dia só entram se a soma da equipe na semana (o uso de compromisso de todos menos o dono, o de partida e o já posto no bloco) mais eles fica até teq[semana]; senão o meio-dia é lacuna. Sem teq, o de antes.';

-- _agenda_encaixar (de 20261030100200_agenda_correcao_motor.sql)
create or replace function public._agenda_encaixar(p_ctx jsonb, p_fila jsonb, p_par jsonb)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  v_nd     int := (p_ctx ->> 'nd')::int;
  v_dono   int := (p_ctx ->> 'dono')::int;
  v_util   boolean[] := public._agenda_bools(p_ctx -> 'util');
  v_sem    int[] := public._agenda_ints(p_ctx -> 'sem');
  v_cap    int[] := public._agenda_ints(p_ctx -> 'cap');
  v_curta  int[] := public._agenda_ints(p_ctx -> 'curta');
  v_ocup   int[] := public._agenda_ints(p_ctx -> 'ocup');
  v_fr     int[] := public._agenda_ints(p_ctx -> 'fr');
  v_t80    int[] := public._agenda_ints(p_ctx -> 'teto80');
  v_t100   int[] := public._agenda_ints(p_ctx -> 'teto100');
  v_uc     int[] := public._agenda_ints(p_ctx -> 'uso_c');
  v_ur     int[] := public._agenda_ints(p_ctx -> 'uso_r');
  v_loc    int[] := public._agenda_ints(p_ctx -> 'loc');
  v_g      jsonb := jsonb_build_object('nh', p_ctx -> 'nh', 'nd', p_ctx -> 'nd', 'np', p_ctx -> 'np', 'nw', p_ctx -> 'nw',
                                       'dono', p_ctx -> 'dono', 'wip', p_par -> 'wip', 'imax', p_par -> 'imax');
  v_inicios int := (p_par ->> 'inicios')::int;
  v_semana boolean := coalesce((p_par ->> 'semana')::boolean, false);
  v_jde    int := coalesce((p_par ->> 'jan_de')::int, 1);
  v_jate   int := coalesce((p_par ->> 'jan_ate')::int, (p_ctx ->> 'nd')::int);
  v_acima  boolean := coalesce((p_par ->> 'acima')::boolean, false);
  v_col    jsonb := '[]'::jsonb;
  v_fora   jsonb := '[]'::jsonb;
  v_pend   jsonb := '[]'::jsonb;
  o        jsonb;
  b        jsonb;
  v_best   jsonb;
  v_teto   int[];
  v_tot    int[];
  v_rest   int[];
  v_i      int;
  v_fixar  boolean;
  v_ini    int;
  v_janela boolean;
  -- CORREÇÃO 29/10 (P3): a pessoa × semana de cada meio-dia da reserva da própria OS (res_propria)
  v_k      int;
  -- CORREÇÃO 29/10 (P3): fim
begin
  if v_inicios is null or p_par -> 'wip' is null or p_par -> 'imax' is null then
    raise exception 'agenda: faltam os parâmetros do encaixe (inícios, frentes, interrupções)' using errcode = '22023';
  end if;

  -- 1. Compromisso, uma OS por vez, consumindo a grade.
  for o in select e from jsonb_array_elements(coalesce(p_fila, '[]'::jsonb)) e
            where (e ->> 'classe')::int in (1, 2) and not coalesce((e ->> 'tirar')::boolean, false)
            order by (e ->> 'ordem')::int, e ->> 'os'
  loop
    v_i := (o ->> 'i')::int;
    v_fixar := o ? 'fixar_de';
    continue when coalesce((o ->> 'passos')::int, 0) <= 0;
    if coalesce((o ->> 'dono_impossivel')::boolean, false) then
      v_fora := v_fora || jsonb_build_object('i', v_i, 'motivo', 'padrao_do_dono');
      continue;
    end if;
    v_teto := case when v_acima or coalesce((o ->> 'teto100')::boolean, false) then v_t100 else v_t80 end;
    v_rest := array(select t.x1 - t.x2 - t.x3 from unnest(v_t100, v_uc, v_ur) as t(x1, x2, x3));
    -- CORREÇÃO 29/10 (P3): a reserva desta mesma OS não conta contra ela. res_propria (da agenda_propor) é a pessoa × semana
    -- de cada meio-dia reservado dela: o lugar até 100% devolve esses meios-dias (o compromisso já podia usar a célula da
    -- própria reserva, ocup = −i; faltava a conta da semana). A reserva das OUTRAS continua contando. As próximas da fila
    -- continuam vendo a reserva (uso_r não muda aqui): quem a tira é a aplicação, que a cancela como promovida — o motor não
    -- presume a promoção antes de ela sair (a OS pode ficar esperando a decisão do dono, e a reserva fica).
    foreach v_k in array public._agenda_ints(o -> 'res_propria') loop
      v_rest[v_k] := v_rest[v_k] + 1;
    end loop;
    -- CORREÇÃO 29/10 (P3): fim
    -- FASE 7: (7a P5) o teto da equipe-semana (spec-fase7a §5.5): com teto_equipe no contexto (a regra teto_equipe do
    -- gestor, em _agenda_contexto), o compromisso da OS que não usa o teto de 100% (acima_da_carga, o pedido do dono) leva o
    -- teto da equipe ao bloco (teq): cada diarista posto num meio-dia exige a equipe (sem o dono) até o teto dela na semana.
    -- Sem teto_equipe, o v_g de sempre (tirar uma chave que não está lá não muda nada).
    if p_ctx ? 'teto_equipe' and not (v_acima or coalesce((o ->> 'teto100')::boolean, false)) then
      v_g := v_g || jsonb_build_object('teq', p_ctx -> 'teto_equipe');
    else
      v_g := v_g - 'teq';
    end if;
    -- FASE 7: fim
    v_best := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_teto, v_uc, v_rest, v_loc, o,
                case when v_fixar then (o ->> 'fixar_de')::int else (o ->> 'est')::int end,
                case when v_fixar then (o ->> 'fixar_ate')::int else v_nd end, v_inicios, false);
    if v_best is null then
      v_fora := v_fora || jsonb_build_object('i', v_i, 'motivo', case when v_fixar then 'fixar_nao_cabe' else 'sem_encaixe' end);
      if (o ->> 'classe')::int = 2 and not v_fixar and not coalesce((o ->> 'tem_reserva')::boolean, false) then
        v_pend := v_pend || o;
      end if;
      continue;
    end if;
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, v_best, v_i, false, v_ocup, v_curta, v_fr, v_uc, v_ur) x;
    v_ini := ((v_best ->> 'ini')::int + 1) / 2;
    -- (o evento real e o pedido do dono valem onde caírem, também antes da semana: é hoje ou amanhã)
    v_janela := not v_semana or v_ini between v_jde and v_jate
                or coalesce((o ->> 'evento_real')::boolean, false) or v_fixar;
    v_col := v_col || (v_best || jsonb_build_object('i', v_i, 'tipo', 'compromisso', 'na_janela', v_janela));
    if v_semana and v_ini > v_jate and (o ->> 'classe')::int = 2 and not v_fixar
       and not coalesce((o ->> 'tem_reserva')::boolean, false) then
      v_pend := v_pend || o;
    end if;
  end loop;

  -- FASE 7: (7a P5) as reservas não levam o teto da equipe (são até 100% de cada um, sem a carga)
  v_g := v_g - 'teq';
  -- FASE 7: fim
  -- 2a. Reserva por teto: a OS pronta que não coube nesta janela com 80% cabe com 100%? A equipe guarda o lugar.
  for o in select e from jsonb_array_elements(v_pend) e loop
    v_i := (o ->> 'i')::int;
    v_tot := array(select t.x1 + t.x2 from unnest(v_uc, v_ur) as t(x1, x2));
    v_rest := array(select t.x1 - t.x2 from unnest(v_t100, v_tot) as t(x1, x2));
    v_best := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_t100, v_tot, v_rest, v_loc, o,
                greatest((o ->> 'est')::int, case when v_semana then v_jde else 1 end),
                case when v_semana then v_jate else v_nd end, v_inicios, false);
    b := case when v_best is null then null else public._agenda_so_diaristas(v_best, v_dono) end;
    continue when b is null;
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, b, v_i, true, v_ocup, v_curta, v_fr, v_uc, v_ur) x;
    v_col := v_col || (b || jsonb_build_object('i', v_i, 'tipo', 'reserva', 'reserva_de', 'teto', 'na_janela', true));
  end loop;

  -- 2b. Reserva condicionada: a classe 3 no 1º encaixe depois do dia em que estaria pronta com a condição cumprida.
  for o in select e from jsonb_array_elements(coalesce(p_fila, '[]'::jsonb)) e
            where (e ->> 'classe')::int = 3 and not coalesce((e ->> 'tirar')::boolean, false)
              and not coalesce((e ->> 'tem_reserva')::boolean, false) and coalesce((e ->> 'passos')::int, 0) > 0
            order by (e ->> 'ordem')::int, e ->> 'os'
  loop
    v_i := (o ->> 'i')::int;
    -- o serviço que é só com o dono (nenhum diarista) não tem o que reservar: a equipe não guarda lugar para ele
    if coalesce((o ->> 'dm')::int, 0) = 0 and coalesce((o ->> 'dtd')::int, 0) = 0 then
      v_fora := v_fora || jsonb_build_object('i', v_i, 'motivo', 'so_com_voce');
      continue;
    end if;
    v_tot := array(select t.x1 + t.x2 from unnest(v_uc, v_ur) as t(x1, x2));
    v_rest := array(select t.x1 - t.x2 from unnest(v_t100, v_tot) as t(x1, x2));
    v_best := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_t100, v_tot, v_rest, v_loc, o,
                greatest((o ->> 'est_cond')::int, case when v_semana then v_jde else 1 end),
                case when v_semana then v_jate else v_nd end, v_inicios, true);
    if v_best is null then
      v_fora := v_fora || jsonb_build_object('i', v_i, 'motivo', 'sem_reserva');
      continue;
    end if;
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, v_best, v_i, true, v_ocup, v_curta, v_fr, v_uc, v_ur) x;
    v_col := v_col || (v_best || jsonb_build_object('i', v_i, 'tipo', 'reserva', 'reserva_de', 'condicionada', 'na_janela', true));
  end loop;

  -- 2c. Reserva no pátio: o que dá para adiantar sem o bem, nos dias em que ele está fora, só a equipe.
  for o in select e from jsonb_array_elements(coalesce(p_fila, '[]'::jsonb)) e
            where coalesce((e ->> 'patio_passos')::int, 0) > 0 and not coalesce((e ->> 'tirar')::boolean, false)
            order by (e ->> 'ordem')::int, e ->> 'os'
  loop
    v_i := (o ->> 'i')::int;
    v_tot := array(select t.x1 + t.x2 from unnest(v_uc, v_ur) as t(x1, x2));
    v_rest := array(select t.x1 - t.x2 from unnest(v_t100, v_tot) as t(x1, x2));
    v_best := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_t100, v_tot, v_rest, v_loc,
                o || jsonb_build_object('passos', o -> 'patio_passos', 'bem', o -> 'patio_bem', 'abre', false, 'fecha', false),
                greatest((o ->> 'est_patio')::int, case when v_semana then v_jde else 1 end),
                case when v_semana then v_jate else v_nd end, v_inicios, true);
    continue when v_best is null;
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, v_best, v_i, true, v_ocup, v_curta, v_fr, v_uc, v_ur) x;
    v_col := v_col || (v_best || jsonb_build_object('i', v_i, 'tipo', 'reserva', 'reserva_de', 'patio', 'na_janela', true));
  end loop;

  return jsonb_build_object('colocadas', v_col, 'fora', v_fora);
end;
$function$;

comment on function public._agenda_encaixar(jsonb, jsonb, jsonb) is
  'Agenda de Produção (Fase 2, P2): o guloso serial sobre a grade do contexto. 1) compromisso: classes 1 e 2 na ordem (ordem), cada uma no melhor início (_agenda_melhor_bloco) a partir do est (ou dentro de fixar_de..fixar_ate), com o teto de 80% (100% com acima_da_carga ou pedido do dono), gravando na grade; sem encaixe = fora (sem_encaixe, fixar_nao_cabe, padrao_do_dono). 2) reservas até 100%: teto (classe 2 que não coube na janela), condicionada (classe 3, a partir do est_cond) e pátio (patio_passos nos dias com o bem fora). Na semana (semana = true) só conta o que começa entre jan_de e jan_ate (na_janela). Devolve {colocadas[{i, tipo, reserva_de, d0, ini, fim, int, md, mesmo, p, h, pr, na_janela}], fora[{i, motivo}]}. CORREÇÃO 29/10 (P3): no compromisso, a OS com res_propria (a pessoa × semana de cada meio-dia da reserva DELA, da agenda_propor) tem esses meios-dias devolvidos ao lugar até 100% (teto100 − compromisso − reserva): a reserva dela não conta contra ela, e a promoção cabe. A reserva das outras continua contando; a grade das próximas da fila continua com a reserva (quem a tira é a aplicação). Sem res_propria, o de antes. FASE 7 (7a P5): com teto_equipe no contexto (a regra teto_equipe do gestor), o compromisso da OS que não usa o teto de 100% (acima_da_carga, o pedido do dono) leva o teto da equipe ao bloco (teq: a equipe, sem o dono, até o teto dela na semana; o teto de cada pessoa já vem a 100% do contexto). As reservas não levam. Sem teto_equipe, o de antes.';

-- _agenda_validar_itens (de 20261029100400_agenda_fase6_dono.sql)
create or replace function public._agenda_validar_itens(p_itens jsonb, p_parametros jsonb, p_hoje date, p_agora timestamptz,
                                                        p_aplicar boolean default false, p_pront jsonb default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  cf      public.agenda_config := public._agenda_cfg();
  v_cong  date := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_acima boolean := coalesce((p_parametros #>> '{p_restricoes,acima_da_carga}')::boolean, false);
  v_dono  uuid := public._agenda_dono(null);
  v_login uuid;
  v_canc  uuid[];
  v_n     jsonb;
  v_v     jsonb := '[]'::jsonb;
  v_d1    date;
  v_d2    date;
  v_cap   jsonb;
  v_pr    jsonb := coalesce(p_pront, '{}'::jsonb);
  v_meios jsonb := '{}'::jsonb;
  v_cart  uuid[];
  v_os    uuid;
  r       record;
  q       record;
  v_cl    jsonb;
  v_m     jsonb;
begin
  select py.app_user_id into v_login from public.payees py where py.id = v_dono;
  select coalesce(array_agg(distinct (a ->> 'alocacao_id')::uuid), '{}'::uuid[]) into v_canc
    from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) i, jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) a
   where i ->> 'op' = 'cancelar' and a ->> 'alocacao_id' is not null;

  -- As alocações novas, uma linha cada (r = a ordem), com o que o item diz delas.
  select coalesce(jsonb_agg(x.a || jsonb_build_object(
           'r', x.r, 'k', x.k, 'os', x.i -> 'os', 'numero', x.i -> 'numero',
           'tipo', x.i -> 'tipo', 'evento_real', coalesce(x.i -> 'evento_real', 'false'::jsonb),
           'fixar_dono', coalesce(x.i -> 'fixar_dono', 'false'::jsonb), 'abre', coalesce(x.i -> 'abre', 'false'::jsonb),
           'fecha', coalesce(x.i -> 'fecha', 'false'::jsonb), 'critica', x.i -> 'critica', 'decisao', x.i -> 'decisao')
           order by x.r), '[]'::jsonb)
    into v_n
    from (select t.i, t.k, u.a, (row_number() over (order by t.k, u.j))::int as r
            from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) with ordinality t(i, k),
                 jsonb_array_elements(coalesce(t.i -> 'alocacoes', '[]'::jsonb)) with ordinality u(a, j)
           where t.i ->> 'op' = 'criar') x;

  if jsonb_array_length(v_n) > 0 then
    select min((e ->> 'dia')::date), max((e ->> 'dia')::date) into v_d1, v_d2 from jsonb_array_elements(v_n) e;
    v_d1 := v_d1 - (extract(isodow from v_d1)::int - 1);
    v_d2 := v_d2 + (7 - extract(isodow from v_d2)::int);
    select coalesce(jsonb_agg(to_jsonb(k)), '[]'::jsonb) into v_cap from public.agenda_capacidade(v_d1, v_d2, p_hoje) k;
    v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k);
    for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_n) e loop
      if not v_pr ? v_os::text then
        v_pr := v_pr || jsonb_build_object(v_os::text, public.os_prontidao(v_os, p_hoje));
      end if;
      v_meios := v_meios || jsonb_build_object(v_os::text, public.agenda_meios_da_os(v_os, p_hoje));
    end loop;
  end if;

  -- (1) A pessoa ativa e livre no turno (a ponta livre, na presença curta), sem feriado.
  v_v := v_v || coalesce((
    select jsonb_agg(jsonb_build_object('regra', 1, 'os', n.os, 'numero', n.numero, 'pessoa', n.nome, 'dia', n.dia, 'turno', n.turno,
             'texto', format('%s não está livre %s (%s).', n.nome, public._agenda_meio_texto(n.dia, n.turno),
                             coalesce(k.motivo, k.situacao, 'não está na equipe'))) order by n.r)
      from jsonb_to_recordset(v_n) as n(r int, os uuid, numero text, payee_id uuid, nome text, dia date, turno text, presenca text)
      left join jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, turno text, situacao text, motivo text)
        on k.payee_id = n.payee_id and k.dia = n.dia and k.turno = n.turno
     where (n.presenca = 'turno' and k.situacao is distinct from 'livre')
        or (n.presenca <> 'turno' and (k.situacao is null or k.situacao in ('indisponivel', 'feriado', 'fim_de_semana')
                                       or not public.agenda_dia_util(n.dia)
                                       or exists (select 1 from public.agenda_tasks t
                                                   where t.kind = 'appointment' and v_login is not null and t.assignee_user_id = v_login
                                                     and t.status not in ('cancelled', 'done') and t.scheduled_start_at is not null
                                                     and tstzrange(t.scheduled_start_at, coalesce(t.scheduled_end_at, t.scheduled_start_at), '[]')
                                                         && public.agenda_periodo(n.dia, n.turno, n.presenca))))), '[]'::jsonb);

  -- (2) Sem choque com o vigente de agora (menos o que a proposta cancela) nem dentro da proposta.
  v_v := v_v || coalesce((
    select jsonb_agg(jsonb_build_object('regra', 2, 'os', n.os, 'numero', n.numero, 'pessoa', n.nome, 'dia', n.dia, 'turno', n.turno,
             'texto', format('%s já está em outro serviço %s.', n.nome, public._agenda_meio_texto(n.dia, n.turno))) order by n.r)
      from jsonb_to_recordset(v_n) as n(r int, os uuid, numero text, payee_id uuid, nome text, dia date, turno text, presenca text)
     where exists (select 1 from public.agenda_alocacoes v
                    where v.payee_id = n.payee_id and v.estado in ('publicada', 'fixada') and not (v.id = any (v_canc))
                      and v.periodo && public.agenda_periodo(n.dia, n.turno, n.presenca))
        or exists (select 1 from jsonb_to_recordset(v_n) as m(r int, payee_id uuid, dia date, turno text, presenca text)
                    where m.r < n.r and m.payee_id = n.payee_id and m.dia = n.dia
                      and public.agenda_periodo(m.dia, m.turno, m.presenca) && public.agenda_periodo(n.dia, n.turno, n.presenca))), '[]'::jsonb);

  -- (3) Nada antes do dia em que a OS fica pronta (fora a reserva e o pedido do dono).
  v_v := v_v || coalesce((
    select jsonb_agg(jsonb_build_object('regra', 3, 'os', x.os, 'numero', x.numero, 'pessoa', null, 'dia', x.dia, 'turno', null,
             'texto', format('%s %s: antes do dia em que fica pronta.', x.numero, public._dia_curto(x.dia))) order by x.dia, x.numero)
      from (select distinct n.os, n.numero, n.dia
              from jsonb_to_recordset(v_n) as n(os uuid, numero text, dia date, tipo text, fixar_dono boolean)
              left join public.os_planejamento pl on pl.service_order_id = n.os
             where n.tipo <> 'reserva' and not n.fixar_dono
               and ((v_pr -> n.os::text) #>> '{material,estado}' in ('atrasado', 'sem_previsao')
                    or n.dia < ((v_pr -> n.os::text) #>> '{material,inicio_mat}')::date
                    or n.dia < pl.nao_antes_de
                    or coalesce(pl.bem_indisponivel @> n.dia, false))) x), '[]'::jsonb);

  -- (4) A presença do dono conforme a regra; (5) alguém em cada meio-dia de execução; (13) interrupções.
  for r in
    select (e ->> 'k')::int as k, min(e ->> 'os') as os, min(e ->> 'numero') as numero, bool_or((e ->> 'fixar_dono')::boolean) as fixar,
           bool_or((e ->> 'abre')::boolean) as abre, bool_or((e ->> 'fecha')::boolean) as fecha, min(e ->> 'tipo') as tipo
      from jsonb_array_elements(v_n) e
     group by (e ->> 'k')::int order by 1
  loop
    continue when r.tipo = 'reserva';
    v_m := v_meios -> r.os;
    -- os meios-dias do item, com quem está em cada um
    for q in
      with a as (select * from jsonb_to_recordset(v_n) as n(k int, payee_id uuid, dia date, turno text, presenca text) where n.k = r.k),
      meio as (select a.dia, a.turno,
                      bool_or(a.payee_id = v_dono and a.presenca = 'turno') as dono_turno,
                      bool_or(a.payee_id = v_dono and a.presenca = 'abertura') as dono_ab,
                      bool_or(a.payee_id = v_dono and a.presenca = 'fechamento') as dono_fe,
                      count(*) filter (where a.presenca = 'turno') as turnos,
                      count(*) filter (where a.presenca = 'turno' and a.payee_id is distinct from v_dono) as equipe
                 from a group by a.dia, a.turno)
      select m.*, row_number() over (order by m.dia, m.turno = 'tarde') as o, count(*) over () as n
        from meio m order by m.dia, m.turno = 'tarde'
    loop
      if not r.fixar then
        if v_m ->> 'presenca' = 'nunca' and (q.dono_turno or q.dono_ab or q.dono_fe) then
          v_v := v_v || jsonb_build_object('regra', 4, 'os', r.os, 'numero', r.numero, 'dia', q.dia, 'turno', q.turno,
                   'texto', format('%s: você foi posto %s, mas a OS é sem você.', r.numero, public._agenda_meio_texto(q.dia, q.turno)));
        elsif v_m ->> 'presenca' in ('sempre', 'equipe') and coalesce((v_m #>> array['dono_turno', q.turno])::boolean, false)
              and q.turnos > 0 and not q.dono_turno then
          v_v := v_v || jsonb_build_object('regra', 4, 'os', r.os, 'numero', r.numero, 'dia', q.dia, 'turno', q.turno,
                   'texto', format('%s: falta você %s.', r.numero, public._agenda_meio_texto(q.dia, q.turno)));
        elsif v_m ->> 'presenca' = 'abre_e_fecha' and (q.dono_turno
              or (q.o = 1 and r.abre and not q.dono_ab) or (q.o = q.n and r.fecha and not q.dono_fe)) then
          v_v := v_v || jsonb_build_object('regra', 4, 'os', r.os, 'numero', r.numero, 'dia', q.dia, 'turno', q.turno,
                   'texto', format('%s: a abertura e o fechamento não estão onde deviam (%s).', r.numero,
                                   public._agenda_meio_texto(q.dia, q.turno)));
        end if;
      end if;
      if q.turnos = 0 and not (q.o = q.n and q.dono_fe) then
        v_v := v_v || jsonb_build_object('regra', 5, 'os', r.os, 'numero', r.numero, 'dia', q.dia, 'turno', q.turno,
                 'texto', format('%s: ninguém trabalha %s.', r.numero, public._agenda_meio_texto(q.dia, q.turno)));
      end if;
    end loop;
    -- (13) os dias úteis inteiros sem a OS entre o 1º e o último meio-dia da equipe
    if (select count(*)
          from (select min(n.dia) as d1, max(n.dia) as d2
                  from jsonb_to_recordset(v_n) as n(k int, dia date, presenca text) where n.k = r.k and n.presenca = 'turno') b,
               generate_series(b.d1 + 1, b.d2 - 1, interval '1 day') g
         where public.agenda_dia_util(g::date)
           and not exists (select 1 from public.os_planejamento pl where pl.service_order_id = r.os::uuid and pl.bem_indisponivel @> g::date)
           and not exists (select 1 from jsonb_to_recordset(v_n) as n(k int, dia date, presenca text)
                            where n.k = r.k and n.presenca = 'turno' and n.dia = g::date)) > cf.interrupcoes_max then
      v_v := v_v || jsonb_build_object('regra', 13, 'os', r.os, 'numero', r.numero,
               'texto', format('%s: o serviço pararia mais de %s dia(s) no meio.', r.numero, cf.interrupcoes_max));
    end if;
  end loop;

  -- (6) O teto por pessoa e semana: compromisso até carga_max (100% com acima_da_carga ou pedido do dono); com a
  -- reserva, até 100%. A presença curta do dono não conta. Só a semana que a proposta toca.
  -- FASE 7: (7a P5) a regra 6 com o teto da equipe-semana (a regra teto_equipe; spec-fase7a §5.5), a mesma conta do encaixe.
  -- Com o portão: (a) o compromisso de cada pessoa da equipe vai até 100% do esperado dela (floor(esperado)); o dono continua
  -- com o teto dele (floor(carga dele × esperado), _agenda_carga_da_pessoa); acima_da_carga e o pedido do dono, 100% como
  -- antes; a semana inteira (com as reservas) não muda; o texto, o de antes. (b) Por semana, a soma da equipe — as pessoas da
  -- grade menos o dono; o vigente (menos o que a proposta cancela) + o novo, sem reserva — não passa de floor(carga_max × a
  -- soma do esperado dela, só de dia útil): "A equipe passaria do limite da semana de 09/11: 11 meios-dias de serviço para 10."
  -- O novo pedido pelo dono (fixar_dono) não entra na soma, e a semana só é conferida com algum compromisso novo da equipe fora
  -- dele: o encaixe põe o pedido do dono sem o teto da equipe, em qualquer ordem da fila, e contá-lo aqui recusaria o que o
  -- motor monta (agenda_propor não solta proposta inválida). Com acima_da_carga, sem o teto da equipe (como o encaixe). Sem o
  -- portão, a regra 6 da Fase 6, logo abaixo, como antes.
  if public._agenda_gestor_regra('teto_equipe') then
    v_v := v_v || coalesce((
      with nov as (
        select n.payee_id, min(n.nome) as nome, n.dia - (extract(isodow from n.dia)::int - 1) as seg,
               count(*) filter (where n.tipo <> 'reserva') as comp, count(*) filter (where n.tipo = 'reserva') as res,
               bool_and(n.fixar_dono) as fixar,
               case when n.payee_id is not distinct from v_dono then public._agenda_carga_da_pessoa(n.payee_id)
                    else 1::numeric end as cg
          from jsonb_to_recordset(v_n) as n(payee_id uuid, nome text, dia date, presenca text, tipo text, fixar_dono boolean)
         where n.presenca = 'turno'
         group by n.payee_id, 3
      ),
      esp as (
        select k.payee_id, k.dia - (extract(isodow from k.dia)::int - 1) as seg, sum(k.meios_esperados) as e
          from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, meios_esperados numeric)
         where public.agenda_dia_util(k.dia)
         group by 1, 2
      ),
      vig as (
        select v.payee_id, v.dia - (extract(isodow from v.dia)::int - 1) as seg,
               count(*) filter (where v.tipo <> 'reserva') as comp, count(*) filter (where v.tipo = 'reserva') as res
          from public.agenda_alocacoes v
         where v.estado in ('publicada', 'fixada') and v.presenca = 'turno' and not (v.id = any (v_canc))
           and v.dia between v_d1 and v_d2
         group by 1, 2
      )
      select jsonb_agg(jsonb_build_object('regra', 6, 'pessoa', nov.nome, 'dia', nov.seg,
               'texto', case when nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
                                    > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(nov.cg * coalesce(esp.e, 0)) end
                             then format('%s passaria do limite da semana de %s: %s meios-dias de serviço para %s.', nov.nome,
                                         to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp,
                                         case when v_acima or nov.fixar then floor(coalesce(esp.e, 0))::int
                                              else floor(nov.cg * coalesce(esp.e, 0))::int end)
                             else format('%s passaria da semana inteira de %s: %s meios-dias com as reservas para %s.', nov.nome,
                                         to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res,
                                         floor(coalesce(esp.e, 0))::int) end)
               order by nov.seg, nov.nome)
        from nov
        left join esp on esp.payee_id = nov.payee_id and esp.seg = nov.seg
        left join vig on vig.payee_id = nov.payee_id and vig.seg = nov.seg
       where (nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
                > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(nov.cg * coalesce(esp.e, 0)) end)
          or coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res > floor(coalesce(esp.e, 0))), '[]'::jsonb);
    if not v_acima then
      v_v := v_v || coalesce((
        with eq as (
          select distinct k.payee_id
            from jsonb_to_recordset(v_cap) as k(payee_id uuid)
           where k.payee_id is distinct from v_dono
        ),
        nov as (
          select n.dia - (extract(isodow from n.dia)::int - 1) as seg,
                 count(*) filter (where n.tipo <> 'reserva' and not n.fixar_dono) as comp
            from jsonb_to_recordset(v_n) as n(payee_id uuid, dia date, presenca text, tipo text, fixar_dono boolean)
           where n.presenca = 'turno' and n.payee_id in (select eq.payee_id from eq)
           group by 1
        ),
        esp as (
          select k.dia - (extract(isodow from k.dia)::int - 1) as seg, sum(k.meios_esperados) as e
            from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, meios_esperados numeric)
           where public.agenda_dia_util(k.dia) and k.payee_id is distinct from v_dono
           group by 1
        ),
        vig as (
          select v.dia - (extract(isodow from v.dia)::int - 1) as seg, count(*) as comp
            from public.agenda_alocacoes v
           where v.estado in ('publicada', 'fixada') and v.presenca = 'turno' and v.tipo <> 'reserva'
             and not (v.id = any (v_canc)) and v.dia between v_d1 and v_d2
             and v.payee_id in (select eq.payee_id from eq)
           group by 1
        )
        select jsonb_agg(jsonb_build_object('regra', 6, 'pessoa', null, 'dia', nov.seg,
                 'texto', format('A equipe passaria do limite da semana de %s: %s meios-dias de serviço para %s.',
                                 to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp,
                                 floor(cf.carga_max * coalesce(esp.e, 0))::int))
                 order by nov.seg)
          from nov
          left join esp on esp.seg = nov.seg
          left join vig on vig.seg = nov.seg
         where nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp > floor(cf.carga_max * coalesce(esp.e, 0))), '[]'::jsonb);
    end if;
  else
  -- FASE 7: fim
  -- FASE 6: (P4) a regra 6 com a carga de cada pessoa (spec-fase6 §5.4): o teto de compromisso é floor(carga × esperado),
  -- com a carga de _agenda_carga_da_pessoa (o dono com capacidade_dono em uso; os outros, carga_max) no lugar de carga_max;
  -- o texto não muda. O vigente conta, mas a violação só existe com alocação nova (nov.comp > 0): o publicado não muda. A
  -- regra de antes (logo abaixo) não roda mais: fica para a conferência da cópia.
  v_v := v_v || coalesce((
    with nov as (
      select n.payee_id, min(n.nome) as nome, n.dia - (extract(isodow from n.dia)::int - 1) as seg,
             count(*) filter (where n.tipo <> 'reserva') as comp, count(*) filter (where n.tipo = 'reserva') as res,
             bool_and(n.fixar_dono) as fixar, public._agenda_carga_da_pessoa(n.payee_id) as carga
        from jsonb_to_recordset(v_n) as n(payee_id uuid, nome text, dia date, presenca text, tipo text, fixar_dono boolean)
       where n.presenca = 'turno'
       group by n.payee_id, 3
    ),
    esp as (
      -- (só dia útil, como o teto do motor: o sábado combinado não sobe o teto da semana)
      select k.payee_id, k.dia - (extract(isodow from k.dia)::int - 1) as seg, sum(k.meios_esperados) as e
        from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, meios_esperados numeric)
       where public.agenda_dia_util(k.dia)
       group by 1, 2
    ),
    vig as (
      select v.payee_id, v.dia - (extract(isodow from v.dia)::int - 1) as seg,
             count(*) filter (where v.tipo <> 'reserva') as comp, count(*) filter (where v.tipo = 'reserva') as res
        from public.agenda_alocacoes v
       where v.estado in ('publicada', 'fixada') and v.presenca = 'turno' and not (v.id = any (v_canc))
         and v.dia between v_d1 and v_d2
       group by 1, 2
    )
    select jsonb_agg(jsonb_build_object('regra', 6, 'pessoa', nov.nome, 'dia', nov.seg,
             'texto', case when nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
                                  > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(nov.carga * coalesce(esp.e, 0)) end
                           then format('%s passaria do limite da semana de %s: %s meios-dias de serviço para %s.', nov.nome,
                                       to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp,
                                       case when v_acima or nov.fixar then floor(coalesce(esp.e, 0))::int
                                            else floor(nov.carga * coalesce(esp.e, 0))::int end)
                           else format('%s passaria da semana inteira de %s: %s meios-dias com as reservas para %s.', nov.nome,
                                       to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res,
                                       floor(coalesce(esp.e, 0))::int) end)
             order by nov.seg, nov.nome)
      from nov
      left join esp on esp.payee_id = nov.payee_id and esp.seg = nov.seg
      left join vig on vig.payee_id = nov.payee_id and vig.seg = nov.seg
     where (nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
              > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(nov.carga * coalesce(esp.e, 0)) end)
        or coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res > floor(coalesce(esp.e, 0))), '[]'::jsonb);
  if false then
  -- FASE 6: fim
  v_v := v_v || coalesce((
    with nov as (
      select n.payee_id, min(n.nome) as nome, n.dia - (extract(isodow from n.dia)::int - 1) as seg,
             count(*) filter (where n.tipo <> 'reserva') as comp, count(*) filter (where n.tipo = 'reserva') as res,
             bool_and(n.fixar_dono) as fixar
        from jsonb_to_recordset(v_n) as n(payee_id uuid, nome text, dia date, presenca text, tipo text, fixar_dono boolean)
       where n.presenca = 'turno'
       group by n.payee_id, 3
    ),
    esp as (
      -- (só dia útil, como o teto do motor: o sábado combinado não sobe o teto da semana)
      select k.payee_id, k.dia - (extract(isodow from k.dia)::int - 1) as seg, sum(k.meios_esperados) as e
        from jsonb_to_recordset(v_cap) as k(payee_id uuid, dia date, meios_esperados numeric)
       where public.agenda_dia_util(k.dia)
       group by 1, 2
    ),
    vig as (
      select v.payee_id, v.dia - (extract(isodow from v.dia)::int - 1) as seg,
             count(*) filter (where v.tipo <> 'reserva') as comp, count(*) filter (where v.tipo = 'reserva') as res
        from public.agenda_alocacoes v
       where v.estado in ('publicada', 'fixada') and v.presenca = 'turno' and not (v.id = any (v_canc))
         and v.dia between v_d1 and v_d2
       group by 1, 2
    )
    select jsonb_agg(jsonb_build_object('regra', 6, 'pessoa', nov.nome, 'dia', nov.seg,
             'texto', case when nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
                                  > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(cf.carga_max * coalesce(esp.e, 0)) end
                           then format('%s passaria do limite da semana de %s: %s meios-dias de serviço para %s.', nov.nome,
                                       to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp,
                                       case when v_acima or nov.fixar then floor(coalesce(esp.e, 0))::int
                                            else floor(cf.carga_max * coalesce(esp.e, 0))::int end)
                           else format('%s passaria da semana inteira de %s: %s meios-dias com as reservas para %s.', nov.nome,
                                       to_char(nov.seg, 'DD/MM'), coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res,
                                       floor(coalesce(esp.e, 0))::int) end)
             order by nov.seg, nov.nome)
      from nov
      left join esp on esp.payee_id = nov.payee_id and esp.seg = nov.seg
      left join vig on vig.payee_id = nov.payee_id and vig.seg = nov.seg
     where (nov.comp > 0 and coalesce(vig.comp, 0) + nov.comp
              > case when v_acima or nov.fixar then floor(coalesce(esp.e, 0)) else floor(cf.carga_max * coalesce(esp.e, 0)) end)
        or coalesce(vig.comp, 0) + nov.comp + coalesce(vig.res, 0) + nov.res > floor(coalesce(esp.e, 0))), '[]'::jsonb);
  -- FASE 6: a regra 6 de antes não roda mais (fica para a conferência da cópia)
  end if;
  -- FASE 6: fim
  -- FASE 7: (7a P5) o fim do "senão" de cima: sem o portão do teto da equipe, a regra 6 da Fase 6, como antes
  end if;
  -- FASE 7: fim

  -- (7) Nada novo no congelado (hoje + o próximo dia útil), salvo o evento real e o pedido do dono; nunca no que já
  -- passou ou começou.
  v_v := v_v || coalesce((
    select jsonb_agg(jsonb_build_object('regra', 7, 'os', n.os, 'numero', n.numero, 'pessoa', n.nome, 'dia', n.dia, 'turno', n.turno,
             'texto', case when lower(public.agenda_periodo(n.dia, n.turno, n.presenca)) <= p_agora
                           then format('%s %s: esse meio-dia já começou.', n.numero, public._agenda_meio_texto(n.dia, n.turno))
                           else format('%s %s: hoje e amanhã ficam como estão.', n.numero, public._agenda_meio_texto(n.dia, n.turno)) end)
             order by n.r)
      from jsonb_to_recordset(v_n) as n(r int, os uuid, numero text, nome text, dia date, turno text, presenca text,
                                         evento_real boolean, fixar_dono boolean)
     where lower(public.agenda_periodo(n.dia, n.turno, n.presenca)) <= p_agora
        or (n.dia <= v_cong and not (n.evento_real or n.fixar_dono))), '[]'::jsonb);

  -- (8) O fixado só sai com item autorizado (a violação registrada, o pedido do dono ou a decisão); o que vai sair tem
  -- de continuar em vigor e sem resultado.
  v_v := v_v || coalesce((
    select jsonb_agg(jsonb_build_object('regra', 8, 'os', i ->> 'os', 'numero', i ->> 'numero', 'dia', a.dia, 'turno', a.turno,
             'texto', case when a.estado not in ('publicada', 'fixada') or a.resultado is not null
                           then format('%s %s: esse meio-dia mudou desde que eu montei.', i ->> 'numero', public._agenda_meio_texto(a.dia, a.turno))
                           else format('%s %s: está fixado e só sai com a sua decisão.', i ->> 'numero', public._agenda_meio_texto(a.dia, a.turno)) end)
             order by a.dia, a.turno, a.id)
      from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) i
      cross join jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) x
      join public.agenda_alocacoes a on a.id = (x ->> 'alocacao_id')::uuid
     where i ->> 'op' = 'cancelar'
       and (a.estado not in ('publicada', 'fixada') or a.resultado is not null
            or (a.estado = 'fixada' and not (coalesce((i ->> 'violada')::boolean, false) or i ->> 'motivo' = 'dono'
                                              or i ->> 'decisao' is not null)))), '[]'::jsonb);

  -- (9) a OS na carteira; (10) classe 4 nunca; (11) reserva condicionada não vira compromisso sem a condição.
  for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_n) e where e ->> 'tipo' <> 'reserva' order by 1 loop
    if not (v_os = any (v_cart)) then
      v_v := v_v || jsonb_build_object('regra', 9, 'os', v_os, 'numero', v_pr -> v_os::text ->> 'numero',
               'texto', format('%s não está na carteira (%s).', v_pr -> v_os::text ->> 'numero', v_pr -> v_os::text ->> 'estado_texto'));
      continue;
    end if;
    v_cl := public._agenda_classe_da_os(v_pr -> v_os::text, v_meios -> v_os::text, p_hoje,
              exists (select 1 from public.agenda_alocacoes a
                       where a.service_order_id = v_os and a.estado = 'fixada' and a.tipo <> 'reserva' and a.dia >= p_hoje
                         and a.resultado is null and not (a.id = any (v_canc))), false);
    if (v_cl ->> 'classe')::int = 4 then
      v_v := v_v || jsonb_build_object('regra', 10, 'os', v_os, 'numero', v_pr -> v_os::text ->> 'numero',
               'texto', format('%s ainda não pode entrar na agenda: %s.', v_pr -> v_os::text ->> 'numero', v_cl ->> 'texto'));
    elsif (v_cl ->> 'classe')::int = 3 and not exists (select 1 from jsonb_array_elements(v_n) e
                                                         where (e ->> 'os')::uuid = v_os and (e ->> 'fixar_dono')::boolean) then
      v_v := v_v || jsonb_build_object('regra', 11, 'os', v_os, 'numero', v_pr -> v_os::text ->> 'numero',
               'texto', format('%s só pode ser reserva até: %s.', v_pr -> v_os::text ->> 'numero', v_cl ->> 'texto'));
    end if;
  end loop;

  -- (12) No máximo wip_max serviços por meio-dia.
  v_v := v_v || coalesce((
    with meio as (select distinct n.dia, n.turno from jsonb_to_recordset(v_n) as n(dia date, turno text)),
    os as (
      select m.dia, m.turno, x.os
        from meio m
        cross join lateral (
          select v.service_order_id as os from public.agenda_alocacoes v
           where v.estado in ('publicada', 'fixada') and not (v.id = any (v_canc)) and v.dia = m.dia and v.turno = m.turno
          union
          select n.os from jsonb_to_recordset(v_n) as n(os uuid, dia date, turno text) where n.dia = m.dia and n.turno = m.turno) x
    )
    select jsonb_agg(jsonb_build_object('regra', 12, 'dia', o.dia, 'turno', o.turno,
             'texto', format('Mais de %s serviços %s.', cf.wip_max, public._agenda_meio_texto(o.dia, o.turno))) order by o.dia, o.turno)
      from (select os.dia, os.turno from os group by 1, 2 having count(distinct os.os) > cf.wip_max) o), '[]'::jsonb);

  -- (14) Item crítico só com a decisão do dono (a pergunta crítica respondida, com a opção escolhida).
  if p_aplicar then
    v_v := v_v || coalesce((
      select jsonb_agg(jsonb_build_object('regra', 14, 'os', i ->> 'os', 'numero', i ->> 'numero',
               'texto', format('%s espera a sua decisão.', i ->> 'numero')) order by k)
        from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) with ordinality t(i, k)
       where i ->> 'critica' is not null
         and not exists (select 1 from public.agenda_perguntas p
                          where p.id = nullif(i ->> 'decisao', '')::uuid and p.critica and p.estado = 'respondida'
                            and p.opcao_escolhida is not null)), '[]'::jsonb);
  end if;

  return coalesce((select jsonb_agg(e order by (e ->> 'regra')::int, o) from jsonb_array_elements(v_v) with ordinality t(e, o)),
                  '[]'::jsonb);
end;
$function$;

comment on function public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb) is
  'Agenda de Produção (Fase 2, P2): as 14 regras duras sobre os itens (criar e cancelar) de uma proposta, contra o banco de agora — (1) pessoa ativa e livre no turno (a ponta livre na presença curta, sem compromisso com hora), sem feriado; (2) sem choque com o vigente nem dentro da proposta; (3) não antes do dia em que fica pronta; (4) a presença do dono conforme a regra; (5) alguém em cada meio-dia; (6) o teto por pessoa e semana; (7) nada no congelado (salvo evento real e pedido do dono) nem no que começou; (8) o fixado só sai autorizado; (9) a OS na carteira; (10) classe 4 nunca; (11) reserva condicionada não vira compromisso; (12) wip_max por meio-dia; (13) no máximo interrupcoes_max dias parados; (14) com p_aplicar, item crítico só com a pergunta respondida. Lista vazia = ok; cada violação {regra, os, numero, pessoa, dia, turno, texto}. FASE 6 (P4): a regra 6 usa a carga de cada pessoa (_agenda_carga_da_pessoa: o dono com capacidade_dono em uso; os outros, carga_max) no lugar de carga_max; o texto não muda. FASE 7 (7a P5), atrás do portão _agenda_gestor_regra(''teto_equipe''): a regra 6 faz a conta do encaixe — o compromisso de cada pessoa da equipe até 100% do esperado (o dono com o teto dele; a semana inteira com as reservas e o texto não mudam) e, por semana, a soma da equipe (as pessoas da grade menos o dono; o vigente menos o cancelado + o novo, sem reserva e sem o pedido do dono) até floor(carga_max × a soma do esperado dela): "A equipe passaria do limite da semana de 09/11: 11 meios-dias de serviço para 10." (pessoa nula). Só confere a semana com compromisso novo da equipe fora do pedido do dono; com acima_da_carga, sem a conta da equipe. Sem o portão, a regra 6 da Fase 6.';

-- _agenda_por_que_nao (de 20261025100200_agenda_fase2_motor.sql)
create or replace function public._agenda_por_que_nao(p_ctx jsonb, p_o jsonb, p_d0 int, p_wip int)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  v_nh   int := (p_ctx ->> 'nh')::int;
  v_nw   int := (p_ctx ->> 'nw')::int;
  v_dono int := (p_ctx ->> 'dono')::int;
  v_cap  int[] := public._agenda_ints(p_ctx -> 'cap');
  v_ocup int[] := public._agenda_ints(p_ctx -> 'ocup');
  v_fr   int[] := public._agenda_ints(p_ctx -> 'fr');
  v_uc   int[] := public._agenda_ints(p_ctx -> 'uso_c');
  v_t    int[] := public._agenda_ints(case when coalesce((p_o ->> 'teto100')::boolean, false) then p_ctx -> 'teto100' else p_ctx -> 'teto80' end);
  v_sem  int[] := public._agenda_ints(p_ctx -> 'sem');
  v_i    int := (p_o ->> 'i')::int;
  v_dia  date;
  v_h    int;
  v_w    int;
  v_cel  int;
  v_x    int;
  v_n    int := 0;
  q      int;
  v_pes  int[];
  -- FASE 7: (7a P5) o teto da equipe-semana (teto_equipe, só com a regra) e a soma da equipe (sem o dono) na semana
  v_teq  int[] := public._agenda_ints(p_ctx -> 'teto_equipe');
  v_equ  int := 0;
  -- FASE 7: fim
begin
  if p_d0 is null or p_d0 < 1 or p_d0 > (p_ctx ->> 'nd')::int then
    return 'é longe demais para eu ver a equipe';
  end if;
  v_dia := (p_ctx ->> 'd_ini')::date + p_d0 - 1;
  if not public.agenda_dia_util(v_dia) then
    -- O fim de semana combinado direto com a equipe ("o Roberto vem sábado") a agenda automática não marca.
    return coalesce(public._dia_curto(v_dia) || ' é ' || public.agenda_feriado(v_dia),
                    format('a agenda automática não marca %s (%s é só combinando direto com a equipe)',
                           case when extract(isodow from v_dia) = 6 then 'sábado' else 'domingo' end,
                           case when extract(isodow from v_dia) = 6 then 'sábado' else 'domingo' end));
  end if;
  if p_d0 = any (public._agenda_ints(p_o -> 'bem')) then
    return 'o bem está fora nesse dia';
  end if;
  v_h := 2 * (p_d0 - 1) + 1;
  v_w := v_sem[p_d0];
  if coalesce((p_o ->> 'dt_m')::boolean, false) and v_dono > 0 then
    v_cel := (v_dono - 1) * v_nh + v_h;
    if v_cap[v_cel] = 0 then return 'você não está em campo nesse dia'; end if;
    if v_ocup[v_cel] not in (0, -v_i) then
      return 'você já está no ' || coalesce(public._agenda_nome_curto((select cl.name from public.service_orders so
               join public.clients cl on cl.id = so.client_id where so.id = (p_ctx -> 'oss' ->> (abs(v_ocup[v_cel]) - 1))::uuid)), 'outro serviço');
    end if;
  end if;
  v_pes := public._agenda_ints(p_o -> 'pm');
  if coalesce((p_o ->> 'fixa')::int, 0) > 0 then v_pes := array[(p_o ->> 'fixa')::int] || v_pes; end if;
  foreach q in array v_pes loop
    v_cel := (q - 1) * v_nh + v_h;
    if v_cap[v_cel] = 0 then
      return 'o ' || (p_ctx -> 'nomes' ->> (q - 1)) || ' não vem nesse dia';
    end if;
    v_x := v_ocup[v_cel];
    if v_x not in (0, -v_i) then
      return 'o ' || (p_ctx -> 'nomes' ->> (q - 1)) || ' já está no '
             || coalesce(public._agenda_nome_curto((select cl.name from public.service_orders so
                  join public.clients cl on cl.id = so.client_id where so.id = (p_ctx -> 'oss' ->> (abs(v_x) - 1))::uuid)), 'outro serviço');
    end if;
    if v_uc[(q - 1) * v_nw + v_w] >= v_t[(q - 1) * v_nw + v_w] then
      return 'o ' || (p_ctx -> 'nomes' ->> (q - 1)) || ' já está com a semana cheia';
    end if;
  end loop;
  -- FASE 7: (7a P5) o teto da equipe: com teto_equipe no contexto (a regra teto_equipe) e a OS sem o teto de 100% (o pedido
  -- do dono não leva o teto da equipe no encaixe), a equipe (sem o dono) que já chegou ao teto dela na semana é o motivo
  if p_ctx ? 'teto_equipe' and not coalesce((p_o ->> 'teto100')::boolean, false) then
    for f7_q in 1 .. coalesce((p_ctx ->> 'np')::int, 0) loop
      continue when f7_q = v_dono;
      v_equ := v_equ + coalesce(v_uc[(f7_q - 1) * v_nw + v_w], 0);
    end loop;
    if v_equ >= coalesce(v_teq[v_w], 0) then
      return 'a equipe já está com a semana cheia';
    end if;
  end if;
  -- FASE 7: fim
  for q in 1 .. 4 loop
    if v_fr[(v_h - 1) * 4 + q] <> 0 and abs(v_fr[(v_h - 1) * 4 + q]) <> v_i then v_n := v_n + 1; end if;
  end loop;
  if v_n >= p_wip then
    return format('já tem %s serviços nesse meio-dia', v_n);
  end if;
  return 'falta gente nesse dia';
end;
$function$;

comment on function public._agenda_por_que_nao(jsonb, jsonb, integer, integer) is
  'Agenda de Produção (Fase 2, P2): o motivo, em palavras, de a OS não caber no dia pedido (a manhã do dia): feriado, fim de semana ("a agenda automática não marca sábado (sábado é só combinando direto com a equipe)"), o bem fora, você ocupado ou fora de campo, quem o dono disse ocupado ("o Roberto já está no Vanderlei"), fora ou com a semana cheia, as frentes cheias; senão "falta gente nesse dia". FASE 7 (7a P5): com teto_equipe no contexto (a regra teto_equipe) e a OS sem o teto de 100%, depois de quem o dono disse e antes das frentes: "a equipe já está com a semana cheia" quando a soma da equipe (sem o dono) na semana já chegou ao teto dela. Sem teto_equipe, o de antes.';

-- ── Portas ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- As recriadas mantêm as portas de antes (create or replace não muda a ACL; repetidas aqui para a migration valer sozinha): as
-- peças do motor (o contexto, o bloco, o encaixe e o porquê), só o service_role; o validador, leitura para quem tem login e o
-- service_role (o agenda_validar da tela o chama). Nunca anon.
revoke all on function
  public._agenda_contexto(date, date, date, uuid[], uuid[]),
  public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer),
  public._agenda_encaixar(jsonb, jsonb, jsonb),
  public._agenda_por_que_nao(jsonb, jsonb, integer, integer)
  from public, anon, authenticated;
grant execute on function
  public._agenda_contexto(date, date, date, uuid[], uuid[]),
  public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer),
  public._agenda_encaixar(jsonb, jsonb, jsonb),
  public._agenda_por_que_nao(jsonb, jsonb, integer, integer)
  to service_role;
revoke all on function public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb) from public, anon;
grant execute on function public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb) to authenticated, service_role;
