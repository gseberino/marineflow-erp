-- Agenda de Produção, Fase 7, etapa 7c ("quem sabe fazer o quê"), pacote P2: o motor — a escolha de pessoa. O motor passa a saber o
-- que cada pessoa faz (agenda_habilidades) e o que cada OS pede (os_exigencias), escolhe quem vai por isso (com modo_habilidade
-- ligado), segura o responsável da OS começada (com modo_lider ligado) e grava em toda alocação nova o critério que decidiu a pessoa
-- (em qualquer modo: é medida para o 7g).
-- Spec: scratchpad agenda-pesquisa/spec-fase7c.md (§R5.3, §R5.4, §R5.5 item 2, §R5.7-1/-6, §R5.10-12, §3.1, §3.4–§3.8, §5.2, §6.8,
-- §8.3 agenda_fase7c_motor.sql); nomes: fase7-registro.md §1 e §2 (7c P2); respostas do dono: fase7-padroes.md (AG7-03 "ajudante =
-- nunca sozinho em tarefa de risco"; AG7-04 uma pessoa, dupla só quando precisa; AG7-10 "sem etiqueta = pode tudo, menos
-- comissionar, que fica com o dono").
-- Depende das Fases 1 a 6, do lote de 30/10, da 7a e da 7b inteiras (20261101100000 .. 100500, as correções 100800, 100850 e 100860)
-- e da base da 7c (20261102100000: agenda_habilidades, os_exigencias, _agenda_atende, _agenda_lider_da_os, _agenda_du_h,
-- _agenda_exigencia_texto, as colunas agenda_alocacoes.criterio/criterio_detalhe e os 3 interruptores).
--
-- ═══ DDL — OK NOMEADO ═══ (8 funções recriadas, 1 nova e 1 de gatilho com o gatilho BEFORE INSERT agenda_alocacoes_criterio; nenhuma
-- coluna, nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK do dono. Este arquivo foi MONTADO por
-- scratchpad/agenda-pesquisa/f7c/p2/montar-migration.mjs: cada recriada é o corpo da definição MAIS NOVA (conferida a cada montagem: o
-- montador para se outra migration a definir depois da origem) — _agenda_contexto e agenda_propor de
-- 20261101100800_agenda_fase77b_correcao.sql; _agenda_tentar_bloco e _agenda_encaixar de 20261101100300_agenda_fase7b_motor.sql;
-- _agenda_so_diaristas e _agenda_alocs_do_bloco de 20261025100200_agenda_fase2_motor.sql; _agenda_por_que_nao de
-- 20261031100400_agenda_fase7a_teto.sql; _agenda_alocacoes_imutavel de 20261025100000_agenda_fase2_tabelas.sql —, e as mudanças estão só
-- em blocos "-- FASE 7c: … -- FASE 7c: fim" INSERIDOS (nenhuma linha de antes é trocada): tirados os blocos, o corpo é o da origem, byte
-- a byte (o montador e o M14 de supabase/tests/agenda_fase7c_motor.sql conferem).
--
-- POR QUE: a agenda escala hoje sem saber o que cada um sabe fazer: o ajudante pode ir sozinho no último dia do banco de lítio, o
-- novo pode ficar só num meio-dia, e ninguém sabe depois por que a pessoa X foi para a OS Y. Com a 7c ligada, o motor escolhe quem
-- atende o que o meio-dia pede; em teste, escala como antes e só grava o porquê.
--
-- O QUE MUDA:
--   1. _agenda_contexto: a saída ganha hab (4 por pessoa: o instala efetivo, comissiona, altura e o papel — 0 responsável, 1 ajudante,
--      2 novo — de agenda_habilidades em p_hoje), habf (os níveis que vieram do padrão, sem etiqueta) e custo (a diária vigente). A
--      pessoa a mais da 7b (o "quem chamar", que não é payee) leva o padrão (R5.3-4).
--   2. agenda_propor: a entrada da fila ganha o que a OS pede (ext em todos os meios-dias, exu no último, exf = pela linha, sempre) e,
--      com modo_lider ou modo_habilidade ligado, o responsável (lid, lid_duro, lid_plan, lid_fora); p_par ganha hab_modo, lid_modo, os
--      níveis, fcobre e lid_espera (sempre). Ligado: os motivos "pede … : vai …", "troquei o responsável: …" e "…, o responsável, não
--      está na equipe agora"; o aviso "— mas João iria sozinho, e o último dia pede …" onde o dono disse quem vai; o cancelar e o fora
--      habilidade; o "por que não cabe" com "ninguém que sobe no teto fica livre nesse dia".
--   3. _agenda_encaixar e _agenda_tentar_bloco (o coração): com os parâmetros da 7c, todo bloco grava o critério (cr) e a máscara (ex)
--      de cada alocação. Com modo_lider ligado: o responsável da OS começada (o que o dono disse ou quem fez o 1º dia) fica em todo
--      meio-dia; se esperar por ele atrasar o fim em mais de lider_espera_max_du dias úteis, o encaixe segue sem ele e diz (lt). Com
--      modo_habilidade ligado: os filtros 3 (quem o meio-dia pede: o responsável que falta entra, também acima do desejado) e 4 (o par:
--      o novo nunca sem um responsável nem o dono no turno), a ordem nova (o responsável planejado, quem estava no meio-dia anterior, o
--      menos qualificado que dá conta, o mesmo local, a carga, a diária, a posição) e a conferência por _agenda_atende (a lacuna); o
--      "novato nunca sozinho" da 7b não roda (o filtro 4 faz o papel dele, §R2); a OS que só não cabe pela habilidade vai ao fora
--      habilidade. A palavra do dono (os ditos, o pedido com pessoa) não passa pelos filtros 3 a 5.
--   4. _agenda_so_diaristas e _agenda_alocs_do_bloco: levam cr e ex; cada alocação do bloco ganha criterio e criterio_detalhe {regra
--      7c|antes, exigencias, suposicoes [pessoa_sem_etiqueta, exigencia_pelo_texto], lider_trocado}.
--   5. O gatilho agenda_alocacoes_criterio (_agenda_alocacao_criterio, BEFORE INSERT; o molde do agenda_alocacoes_fonte da 7a; R5.10-12):
--      toda alocação nova que chega sem critério ganha o do item da proposta do motor (a alocação do item pelo alocacao_id: é por ele
--      que o motor grava) ou, fora do motor, presenca_do_dono quando é do dono e criterio_detalhe.regra pela proposta — escada (a
--      escada da revisão da 7a), dupla (a 2ª pessoa da 7b), corte (o reestimar da 7a) — ou fora_do_motor (as refeitas pelos desfazer).
--   6. _agenda_alocacoes_imutavel: criterio e criterio_detalhe entram na tupla que a publicada não muda.
--   7. Nova: _agenda_aviso_da_habilidade(os, alocações, hoje) — "{nome} iria sozinho, e {o último dia|esse dia} pede {exigência}".
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7c_motor.sql; registradas em notas-fase77c.md, P2):
--   · o insert do agenda_propor NÃO muda (seria trocar linha, e 6 testes de antes conferem o corpo vivo dele com tiradores que não
--     devolvem linha trocada): o critério vai no item (a alocação, pelo alocacao_id) e o gatilho o grava — "o motor manda o dele"
--     pelo item, e o gatilho não mexe no que o motor mandou;
--   · o responsável que falta (§5.2 5b) repete enquanto o meio-dia ainda pede o que ninguém escolhido tem (no máximo 4 vezes, uma por
--     exigência): cada exigência ganha o seu responsável (a spec dizia uma vez; com energizado e teto, o 1º que zera o energizado pode
--     não subir no teto); e o resto até o desejado dá uma 2ª volta para quem foi pulado por ser novo (já com um responsável junto);
--   · a troca avisada é dita sempre que acontece (com modo_lider ligado), não só com modo_habilidade ligado;
--   · o fora habilidade começa pelo rótulo da OS ("Caio (OS-97173): pede …"), como as outras linhas do fora (a §6.8 dá "Caio: …");
--     no dia que o dono pediu (fixar), é o "não cabe <dia>: <o porquê>" de sempre, com o porquê da 7c ("Bia (OS-97172): não cabe ter
--     10/11: ninguém que sobe no teto fica livre nesse dia."): "nas próximas 6 semanas" não diz nada de um dia pedido;
--   · o critério de quem a escolha de antes pôs (fora de modo_habilidade ligado) conta também a ordem da 7b (quem nunca fica sozinho
--     vai depois: 3), e a companhia que a 7b acrescenta leva 3;
--   · o motor só lê o que a OS pede (os_exigencias) com a porta dela aberta — o service_role sem login ou o admin/financeiro logado —:
--     a técnica logada que marca pela tela (agenda_marcar_os, liberada a authenticated) chega ao motor, e o 42501 de os_exigencias
--     quebraria o agendamento dela. Para esse pedido, a OS "não pede ninguém em especial" (a regra de antes) e o aviso não sai; o pedido
--     dela tem a pessoa (a palavra de quem marca), e os filtros 3 a 5 não valem de todo jeito.
--
-- O QUE NÃO MUDA: com os 3 interruptores fora de ligado, as pessoas, os dias, os turnos e as presenças do motor, da vigia e das
-- simulações são os de antes (a projeção, §3.8 d8); só o critério aparece nas alocações e as 3 chaves novas no contexto. As
-- simulações que montam a própria entrada (agenda_encaixe_do_novo, agenda_ctp, agenda_simular) não mandam os parâmetros da 7c e
-- saem byte a byte (compatível por ausência, §3.1-5).
--
-- ORDEM DE LIGAR: nada a ligar aqui (os interruptores são do P1; a migration de dado 20261102100600 os põe em sombra; o ligar é
-- modo_habilidade e modo_lider = ligado, com o OK nomeado do dono, spec §10). PROVA: supabase/tests/agenda_fase7c_motor.sql na bancada
-- (node scripts/bancada-agenda/rodar.mjs). APLICAR: só pelo roteiro de publicação da 7c, depois da 20261102100000 e antes da
-- 20261102100200.
-- IDEMPOTENTE: create or replace function, drop/create trigger, revoke/grant e comment.

-- ── 1. O contexto: o que cada pessoa faz ─────────────────────────────────────────────────────────────────────────

-- _agenda_contexto (de 20261101100800_agenda_fase77b_correcao.sql)
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
  -- FASE 7b: (7b P4) o sábado da 7b (os índices dos sábados e a manhã livre de cada pessoa por semana), quem nunca fica sozinho, o
  -- dono técnico e o gancho da pessoa a mais (R4.4)
  v_7b_extra jsonb := '{}'::jsonb;
  v_7b_sab   int[];
  v_7b_bon   int[];
  v_7b_nov   int[];
  v_7b_d     int;
  v_7b_p     int;
  v_7b_util  boolean[];
  v_7b_cap   int[];
  -- FASE 7b: fim
  -- FASE 7c: (7c P2, §5.2) o que cada pessoa faz, na ordem da grade (hab, habf, custo)
  v_7c_hab   int[];
  v_7c_habf  int[];
  v_7c_custo int[];
  -- FASE 7c: fim
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
  -- FASE 7b: (7b P4, R4.4: o gancho do P6, inerte sem a variável) com agenda.pessoa_extra = tecnico — só _agenda_quem_chamar a liga,
  -- dentro da conta e sem gravar —, uma pessoa que não existe (_agenda_pessoa_extra_id, "mais uma pessoa") entra por último: livre
  -- nas manhãs e tardes de todo dia útil da grade (sem feriado nem recesso), não novato, não sob demanda, não o dono, com o teto de
  -- carga_max (_agenda_carga_da_pessoa) e contada no teto da equipe do 7a. Sem a variável, nada muda.
  if coalesce(current_setting('agenda.pessoa_extra', true), '') = 'tecnico' then
    v_pes := v_pes || public._agenda_pessoa_extra_id();
    v_nomes := v_nomes || 'mais uma pessoa'::text;
    v_np := v_np + 1;
    select v_cap || array_agg(case when public.agenda_dia_util(p_d_ini + (h - 1) / 2) then 1 else 0 end order by h),
           v_esp || array_agg(case when public.agenda_dia_util(p_d_ini + (h - 1) / 2) then 1::numeric else 0::numeric end order by h)
      into v_cap, v_esp
      from generate_series(1, v_nh) h;
  end if;
  -- FASE 7b: fim

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
  -- FASE 7b: (7b P4, §R2) o gancho do sábado do 7a (a pergunta crítica sabado, logo abaixo) só vale com modo_sabado desligado:
  -- com sombra ou ligado vale o sábado desta etapa (sab e sab_bonus: a manhã de quem se ofereceu). A grade de antes do gancho fica
  -- guardada e volta logo depois dele.
  v_7b_util := v_util;
  v_7b_cap := v_cap;
  -- FASE 7b: fim
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
  -- FASE 7b: (correção da revisão da 7b, achado 12) em teste (modo_sabado sombra) o gancho do sábado do 7a continua valendo: a pergunta
  -- crítica sabado da 7a ligada acha o sábado (antes, o modo em teste a desligava sem pôr nada visível no lugar). A grade guardada passa a
  -- ser a de depois dele, e a volta logo abaixo não muda nada. Só ligado o sábado é só o desta etapa.
  if cf.modo_sabado = 'sombra' then
    v_7b_util := v_util;
    v_7b_cap := v_cap;
  end if;
  -- FASE 7b: fim
  -- FASE 7b: (7b P4, §R2) com modo_sabado fora de desligado, o gancho do sábado do 7a não vale: a grade volta à de antes dele
  if cf.modo_sabado <> 'desligado' then
    v_util := v_7b_util;
    v_cap := v_7b_cap;
  end if;
  -- FASE 7b: fim

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

  -- FASE 7c: (7c P2, §5.2, R5.3-4) o que cada pessoa faz, numa leitura só de agenda_habilidades (em p_hoje, o dia em que a 7c mede o
  -- papel), na ordem de pessoas: hab = 4 por pessoa (o instala efetivo, comissiona, altura e o papel: 0 responsável, 1 ajudante, 2
  -- novo); habf = 1 por pessoa, os bits 1 (instala), 2 (comissiona) e 4 (altura) do que veio do padrão, sem etiqueta (a suposição
  -- pessoa_sem_etiqueta do critério); custo = a diária do perfil vigente (sem perfil, e o dono, 999999). Quem agenda_habilidades não
  -- acha (a pessoa a mais da 7b, que não é payee) leva o padrão: habilidade_padrao, papel responsável, os 3 bits e 999999. Vão para
  -- a saída pelo extra da 7b (a saída é a de antes || teto_equipe, quando há, || o extra): as outras chaves não mudam, e só o motor
  -- da 7c as lê.
  with h as materialized (select * from public.agenda_habilidades(p_hoje, v_pes)),
  pe as (select g.p, h.instala, h.comissiona, h.altura, h.papel, h.fonte, h.payee_id is not null as achou
           from generate_series(1, coalesce(v_np, 0)) g(p) left join h on h.payee_id = v_pes[g.p])
  select coalesce((select array_agg(case k.k when 1 then coalesce(pe.instala, (cf.habilidade_padrao ->> 'instala')::int)
                                            when 2 then coalesce(pe.comissiona, (cf.habilidade_padrao ->> 'comissiona')::int)
                                            when 3 then coalesce(pe.altura, (cf.habilidade_padrao ->> 'altura')::int)
                                            else coalesce(pe.papel, 0) end order by pe.p, k.k)
                      from pe cross join generate_series(1, 4) k(k)), '{}'::int[]),
         coalesce((select array_agg(case when not pe.achou then 7
                                         else (case when pe.fonte ->> 'instala' = 'padrao' then 1 else 0 end)
                                              + (case when pe.fonte ->> 'comissiona' = 'padrao' then 2 else 0 end)
                                              + (case when pe.fonte ->> 'altura' = 'padrao' then 4 else 0 end) end order by pe.p)
                      from pe), '{}'::int[]),
         coalesce((select array_agg(case when pe.p = v_dono then 999999
                                         else coalesce((select round(w.valor_diaria)::int from public.work_profiles w
                                                         where w.payee_id = v_pes[pe.p] and w.vigencia_inicio <= p_hoje
                                                           and (w.vigencia_fim is null or w.vigencia_fim >= p_hoje)
                                                         order by w.vigencia_inicio desc, w.id limit 1), 999999) end order by pe.p)
                      from pe), '{}'::int[])
    into v_7c_hab, v_7c_habf, v_7c_custo;
  v_7b_extra := v_7b_extra || jsonb_build_object('hab', to_jsonb(v_7c_hab), 'habf', to_jsonb(v_7c_habf), 'custo', to_jsonb(v_7c_custo));
  -- FASE 7c: fim
  -- FASE 7b: (7b P4, §5.3) o que o motor da 7b lê, só com os modos dela (sem eles, nenhuma chave nova: a saída de antes):
  -- (1) sab = os índices dos sábados do período sem feriado nem recesso de manhã, com modo_sabado fora de desligado e sabado_manha
  -- diferente de nunca; (2) sab_bonus por pessoa e semana ((pessoa − 1) × nw + semana) = as manhãs de sábado em que ela está livre
  -- (cap = 1: a manhã que ela ofereceu, a exceção "vem"): o encaixe soma ao teto dela só na tentativa com o sábado; (3) novato = os
  -- índices de quem nunca fica sozinho num meio-dia na 1ª data da grade — o novato (_agenda_e_novato, com novato_sozinho falso) e
  -- quem vem sob demanda (_agenda_e_sob_demanda, com sob_demanda_sozinho falso) —, com modo_dupla fora de desligado (a segurança,
  -- como a dupla em teste); nunca o dono nem a pessoa a mais; (4) dono_tec = dono_como_tecnico (com modo_dias fora de desligado: os
  -- dias de campo que ele disse). Os tetos não mudam aqui.
  if cf.modo_sabado <> 'desligado' and cf.sabado_manha <> 'nunca' then
    v_7b_sab := array(select g + 1 from generate_series(0, v_nd - 1) g
                       where extract(isodow from p_d_ini + g)::int = 6 and public.agenda_feriado(p_d_ini + g) is null
                         and not exists (select 1 from public.agenda_disponibilidade d
                                          where d.payee_id is null and d.situacao = 'indisponivel' and d.substituida_em is null
                                            and d.periodo @> (p_d_ini + g) and (d.turno is null or d.turno = 'manha'))
                       order by g);
    if cardinality(v_7b_sab) > 0 then
      v_7b_bon := array_fill(0, array[greatest(v_np * v_nw, 1)]);
      foreach v_7b_d in array v_7b_sab loop
        for v_7b_p in 1 .. coalesce(v_np, 0) loop
          if v_cap[(v_7b_p - 1) * v_nh + 2 * (v_7b_d - 1) + 1] = 1 then
            v_7b_bon[(v_7b_p - 1) * v_nw + v_sem[v_7b_d]] := v_7b_bon[(v_7b_p - 1) * v_nw + v_sem[v_7b_d]] + 1;
          end if;
        end loop;
      end loop;
      v_7b_extra := v_7b_extra || jsonb_build_object('sab', to_jsonb(v_7b_sab), 'sab_bonus', to_jsonb(v_7b_bon));
    end if;
  end if;
  if cf.modo_dupla <> 'desligado' then
    v_7b_nov := array(select g.p from generate_series(1, coalesce(v_np, 0)) g(p)
                       where g.p <> v_dono and v_pes[g.p] is distinct from public._agenda_pessoa_extra_id()
                         and ((not cf.novato_sozinho and public._agenda_e_novato(v_pes[g.p], p_d_ini))
                              or (not cf.sob_demanda_sozinho and public._agenda_e_sob_demanda(v_pes[g.p], p_d_ini)))
                       order by g.p);
    if cardinality(v_7b_nov) > 0 then
      v_7b_extra := v_7b_extra || jsonb_build_object('novato', to_jsonb(v_7b_nov));
    end if;
  end if;
  if cf.dono_como_tecnico and cf.modo_dias <> 'desligado' and v_dono > 0 then
    v_7b_extra := v_7b_extra || jsonb_build_object('dono_tec', true);
  end if;
  if v_7b_extra <> '{}'::jsonb then
    return jsonb_build_object(
      'd_ini', p_d_ini, 'd_fim', p_d_fim, 'seg', v_seg, 'nd', v_nd, 'nh', v_nh, 'np', v_np, 'nw', v_nw,
      'dono', v_dono, 'dono_tem_padrao', v_padrao,
      'pessoas', to_jsonb(v_pes), 'nomes', to_jsonb(v_nomes), 'oss', to_jsonb(v_oss),
      'util', to_jsonb(v_util), 'sem', to_jsonb(v_sem), 'cap', to_jsonb(v_cap), 'curta', to_jsonb(v_curta),
      'ocup', to_jsonb(v_ocup), 'fr', to_jsonb(v_fr), 'esperado', to_jsonb(coalesce(v_espw, '{}'::numeric[])),
      'teto80', to_jsonb(coalesce(v_t80, '{}'::int[])), 'teto100', to_jsonb(coalesce(v_t100, '{}'::int[])),
      'uso_c', to_jsonb(v_uc), 'uso_r', to_jsonb(v_ur), 'loc', to_jsonb(v_loc))
      || case when v_f7_teq then jsonb_build_object('teto_equipe', to_jsonb(coalesce(v_f7_te, '{}'::int[]))) else '{}'::jsonb end
      || v_7b_extra;
  end if;
  -- FASE 7b: fim
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
  'Agenda de Produção (Fase 2, P2): a grade do motor em arrays (agenda_grade de p_d_ini a p_d_fim, sem as alocações de p_ignorar): pessoas (você primeiro), dias úteis, semana ISO de cada dia, quem está livre em cada meio-dia (cap), as pontas livres do dono (curta: 1 abertura, 2 fechamento), o que o vigente ocupa (ocup, frentes: o índice da OS em oss, negativo = reserva), o uso por pessoa e semana (compromisso e reserva) e os tetos floor(carga_max × esperado) e floor(esperado) — o esperado só de dia útil (o sábado combinado não sobe o teto). As OS de p_fila vêm primeiro em oss. FASE 6 (P4): o teto80 de cada pessoa usa _agenda_carga_da_pessoa (o dono com capacidade_dono em uso: floor(carga dele × esperado); os outros, carga_max) — a posição (pp − 1) × nw + ww é a pessoa v_pes[pp] na semana ww; fora de ligado, a saída de antes. FASE 7 (7a P5), atrás do portão _agenda_gestor_regra(''teto_equipe'') (falso = a saída de antes, byte a byte): cada pessoa da equipe (todas menos o dono) pode chegar a 100% do esperado dela na semana (teto80 = teto100); a equipe inteira, a teto_equipe[semana] = floor(carga_max × a soma do esperado da equipe), arredondado uma vez, na soma; o dono mantém o teto dele (_agenda_carga_da_pessoa) e fica fora da soma (é presença, não capacidade de técnico); a saída ganha teto_equipe (um número por semana, na ordem de sem). O gancho do sábado (AG7-08): só com a variável agenda.sabado = ''on'' (a decisão da pergunta crítica sabado a liga) e sabado_manha diferente de nunca, a manhã de cada sábado que ainda não é útil e não é feriado vira útil, com lugar só para quem tem o padrão de sábado de manhã (sem exceção nem recesso naquele dia); a tarde fica sem ninguém; o sábado não entra no esperado (o teto não sobe). Sem a variável, nada muda. FASE 7b (P4, §5.3, §R2, R4.4): (0) o gancho do sábado do 7a (agenda.sabado) só com modo_sabado desligado; (1) sab = os sábados do período sem feriado nem recesso de manhã e (2) sab_bonus por pessoa e semana = as manhãs de sábado livres dela (a que ela ofereceu), com modo_sabado fora de desligado e sabado_manha diferente de nunca; (3) novato = os índices de quem nunca fica sozinho — o novato (_agenda_e_novato, novato_sozinho falso) e quem vem sob demanda (_agenda_e_sob_demanda, sob_demanda_sozinho falso) —, com modo_dupla fora de desligado, nunca o dono; (4) dono_tec = dono_como_tecnico com modo_dias fora de desligado. O gancho da pessoa a mais (R4.4, inerte sem a variável): com agenda.pessoa_extra = tecnico, "mais uma pessoa" (_agenda_pessoa_extra_id) entra por último, livre nas manhãs e tardes de todo dia útil, não novato nem sob demanda, com o teto de carga_max e contada no teto da equipe. Os tetos não mudam. Sem os modos e sem a variável, a saída de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achado 12): o gancho do sábado do 7a (agenda.sabado) vale também com modo_sabado em teste (sombra); só com modo_sabado ligado vale só o desta etapa. FASE 7c (P2, §5.2, R5.3-4): a saída ganha hab (4 por pessoa, na ordem de pessoas: o instala efetivo, comissiona, altura e o papel de agenda_habilidades em p_hoje), habf (1 por pessoa: os bits 1 instala, 2 comissiona, 4 altura do que veio do padrão) e custo (a diária do perfil vigente; sem perfil e o dono, 999999); a pessoa a mais da 7b leva o padrão. As outras chaves, as de antes.';

-- ── 2. O bloco: a escolha de pessoa ──────────────────────────────────────────────────────────────────────────────

-- _agenda_tentar_bloco (de 20261101100300_agenda_fase7b_motor.sql)
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
  -- FASE 7b: (7b P4, §5.3) as pessoas de cada passo (dk; o dono no turno só desconta quando conta como uma delas: dk_dono_conta), o
  -- sábado (os índices dos sábados: só na tentativa com ele), quem nunca fica sozinho (novato) e o dono técnico (dono_tec)
  v_dk    int[] := case when p_o ? 'dk' then public._agenda_ints(p_o -> 'dk') end;
  v_dkc   boolean := coalesce((p_o ->> 'dk_dono_conta')::boolean, true);
  v_sab   int[] := case when p_g ? 'sab' then public._agenda_ints(p_g -> 'sab') end;
  v_nov   int[] := case when p_g ? 'novato' then public._agenda_ints(p_g -> 'novato') end;
  v_dtec  boolean := coalesce((p_g ->> 'dono_tec')::boolean, false);
  v_nsab  int := 0;
  v_7b_x  int;
  -- FASE 7b: fim
  -- FASE 7c: (7c P2, §5.2, §3.4–§3.7) o que cada pessoa faz (hab: 4 por pessoa — instala, comissiona, altura, papel; custo, a diária),
  -- os modos (hab_modo: os filtros 3 e 4 e a ordem nova; lid_modo: o filtro 5), os níveis (n), o fechamento que cobre o último dia
  -- (fcobre), o que a OS pede (ext em todos os meios-dias, exu no último), o responsável (lid, duro só com lid_modo e fora da
  -- reserva; lid_plan, o planejado, só desempata), a palavra do dono (dita: os ditos ou a pessoa pedida) e, por meio-dia, a máscara,
  -- o dono no turno e a altura dele, o que falta, o critério de quem entra e as chaves da ordem. Sem hab no p_g (as simulações, a
  -- chamada de antes), nada disso: a regra de antes, byte a byte.
  v_7c       boolean := jsonb_typeof(p_g -> 'hab') = 'array';
  v_7c_hab   int[] := public._agenda_ints(p_g -> 'hab');
  v_7c_cus   int[] := public._agenda_ints(p_g -> 'custo');
  v_7c_hm    int := case when jsonb_typeof(p_g -> 'hab') = 'array' then coalesce((p_g ->> 'hab_modo')::int, 0) else 0 end;
  v_7c_lm    int := case when jsonb_typeof(p_g -> 'hab') = 'array' then coalesce((p_g ->> 'lid_modo')::int, 0) else 0 end;
  v_7c_n     jsonb := coalesce(p_g -> 'n', '{}'::jsonb);
  v_7c_fc    boolean := coalesce((p_g ->> 'fcobre')::boolean, false);
  v_7c_ext   int := coalesce((p_o ->> 'ext')::int, 0);
  v_7c_exu   int := coalesce((p_o ->> 'exu')::int, 0);
  v_7c_lid   int := coalesce((p_o ->> 'lid')::int, 0);
  v_7c_lidd  boolean := jsonb_typeof(p_g -> 'hab') = 'array' and coalesce((p_g ->> 'lid_modo')::int, 0) = 1 and not p_reserva
                        and coalesce((p_o ->> 'lid_duro')::boolean, false);
  v_7c_lidp  int := coalesce((p_o ->> 'lid_plan')::int, 0);
  v_7c_dita  boolean := coalesce(cardinality(v_pm), 0) + coalesce(cardinality(v_pt), 0) > 0 or v_fixa > 0;
  v_7c_ex    int := 0;
  v_7c_dt    boolean := false;
  v_7c_dalt  int := 0;
  v_7c_falta text;
  v_7c_acr   int[] := '{}';
  v_7c_aex   int[] := '{}';
  v_7c_ecr   int[] := '{}';
  v_7c_cq    int[];
  v_7c_k1    int[];
  v_7c_k2    int[];
  v_7c_k3    int[];
  v_7c_k4    int[];
  v_7c_k5    int[];
  v_7c_k6    int[];
  v_7c_x     int;
  v_7c_xj    int;
  v_7c_y     int;
  v_7c_j0    int;
  -- FASE 7c: fim
begin
  -- FASE 7c: (§R2, R5.3-2) com modo_habilidade ligado, quem nunca fica sozinho é o papel novo do filtro 4 (o par, de _agenda_atende):
  -- o "novato nunca sozinho" da 7b (a ordem dele e a companhia que ele acrescenta) não roda
  if v_7c_hm = 1 then
    v_nov := null;
  end if;
  -- FASE 7c: fim
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
      -- FASE 7b: (sábado) o sábado sem passo não conta como dia parado
      if v_sab is not null and v_dia = any (v_sab) then
        v_trab := false;
      end if;
      -- FASE 7b: fim
      if v_trab and v_prog = 0 then
        v_int := v_int + 1;
        if v_int > v_imax then return null; end if;
      end if;
      v_dia := v_d;
      v_prog := 0;
      v_trab := p_util[v_d] and not (v_d = any (v_bem));
      -- FASE 7b: (sábado) o sábado da grade é dia de trabalho na tentativa com ele (só a manhã, abaixo)
      if v_sab is not null and v_d = any (v_sab) and not (v_d = any (v_bem)) then
        v_trab := true;
      end if;
      -- FASE 7b: fim
    end if;
    if not v_trab or v_h < p_min_h then
      v_h := v_h + 1;
      continue;
    end if;
    -- FASE 7b: (sábado) só a manhã (a tarde é pulada sem contar) e nunca o 1º passo
    if v_sab is not null and v_d = any (v_sab) and (v_h % 2 = 0 or v_ini is null) then
      v_h := v_h + 1;
      continue;
    end if;
    -- FASE 7b: fim
    v_t := case when v_h % 2 = 1 then 1 else 2 end;
    v_w := p_sem[v_d];

    -- FASE 7c: (7c P2, §3.5) a máscara deste meio-dia: o que a OS pede em todos e, no último passo, o do último — menos quando o dono
    -- fecha a OS (o fecha do molde, também na reserva) e o fechamento dele cobre o último dia (fcobre). Na reserva o dono não entra no
    -- bloco: o que o turno dele cobriria no compromisso (dt_m/dt_t neste turno) conta como atendido, menos o teto (altura).
    if v_7c then
      v_7c_ex := v_7c_ext | case when v_k = v_n - 1 and not (v_7c_fc and coalesce((p_o ->> 'fecha')::boolean, false))
                                 then v_7c_exu else 0 end;
      if p_reserva and ((v_t = 1 and coalesce((p_o ->> 'dt_m')::boolean, false)) or (v_t = 2 and coalesce((p_o ->> 'dt_t')::boolean, false))) then
        v_7c_ex := v_7c_ex & 4;
      end if;
    end if;
    -- FASE 7c: fim
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
      -- FASE 7b: (dk) as pessoas deste passo do molde (k = v_k + 1); o dono no turno desconta 1 quando conta como uma delas (também
      -- na reserva, que guarda só os diaristas: o mesmo que o desejado de antes)
      if v_dk is not null and v_dk[v_k + 1] is not null then
        v_need := greatest(v_dk[v_k + 1] - case when v_dkc and ((v_t = 1 and coalesce((p_o ->> 'dt_m')::boolean, false))
                                                        or (v_t = 2 and coalesce((p_o ->> 'dt_t')::boolean, false))) then 1 else 0 end, 0);
      end if;
      -- FASE 7b: fim
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
      -- FASE 7c: (7c P2, §5.2 4–6, §3.4, §3.6, §3.7) depois de quem o dono disse (o critério 1):
      -- (a) o responsável da OS começada (duro: o dito pelo dono ou quem fez o 1º dia, com modo_lider ligado, fora da reserva e sem a
      --     palavra do dono sobre quem vai), quando nem ele nem o dono estão no turno: livre, entra com o critério 2; ocupado, o
      --     meio-dia não dá (a troca avisada é do encaixe);
      -- com modo_habilidade ligado, a escolha é a desta etapa — os candidatos livres (as 4 condições de sempre, sem o dono) na ordem
      -- da §3.4 (o responsável planejado, quem estava no meio-dia anterior desta OS, o menos qualificado que dá conta, o mesmo local
      -- no outro turno do dia, a menor carga da semana, a menor diária, a posição):
      -- (b) sem a palavra do dono, enquanto o meio-dia pede o que ninguém escolhido tem (energizado, comissionamento, diagnóstico ou
      --     teto), entra o 1º candidato que zera essa falta — também acima do desejado (a dupla de segurança, quando quem ocupa a vaga
      --     é o responsável) —, pulando o novo enquanto não há um responsável nem o dono no turno; o critério é 3 quando um candidato
      --     que não zerava vinha antes, senão a chave em que ele ganhou do próximo que zeraria (sem próximo, 8); sem ele, o meio-dia
      --     não dá;
      -- (c) o resto até o desejado, na mesma ordem, pulando o novo (papel 2) enquanto não há um responsável (papel 0, instala >= par)
      --     entre os escolhidos nem o dono no turno (o filtro 4, o par; uma 2ª volta põe quem ficou pulado); o critério de cada um é a
      --     1ª chave em que ele ganhou do próximo da lista que ficou de fora (2 líder, 4 continuidade, 3 nível, 5 local, 6 carga, 7
      --     custo, 10 empate; sem próximo, 8 único); o dono técnico da 7b entra por último, como na 7b.
      -- Faltando gente, o meio-dia não dá; a escolha de antes, logo abaixo, só roda fora de modo_habilidade ligado.
      if v_7c then
        v_7c_ecr := array_fill(1, array[coalesce(cardinality(v_esc), 0)]);
        v_7c_dt := case when p_reserva then (v_t = 1 and coalesce((p_o ->> 'dt_m')::boolean, false))
                                            or (v_t = 2 and coalesce((p_o ->> 'dt_t')::boolean, false))
                        else v_role = 1 end;
        v_7c_dalt := case when p_reserva or v_dono < 1 then 0 else coalesce(v_7c_hab[(v_dono - 1) * 4 + 3], 0) end;
        if v_7c_lidd and not v_7c_dita and v_7c_lid > 0 and v_7c_lid <> v_dono and v_role <> 1 and not (v_7c_lid = any (v_esc)) then
          v_cel := (v_7c_lid - 1) * v_nh + v_h;
          if p_cap[v_cel] = 1 and p_ocup[v_cel] in (0, -v_i)
             and v_uso[(v_7c_lid - 1) * v_nw + v_w] < p_teto[(v_7c_lid - 1) * v_nw + v_w]
             and v_rest[(v_7c_lid - 1) * v_nw + v_w] > 0 then
            v_esc := v_esc || v_7c_lid;
            v_7c_ecr := v_7c_ecr || 2;
          else
            v_ok := false;
          end if;
        end if;
        if v_ok and v_7c_hm = 1 then
          select coalesce(array_agg(z.q order by z.o), '{}'::int[]), coalesce(array_agg(z.k1 order by z.o), '{}'::int[]),
                 coalesce(array_agg(z.k2 order by z.o), '{}'::int[]), coalesce(array_agg(z.k3 order by z.o), '{}'::int[]),
                 coalesce(array_agg(z.k4 order by z.o), '{}'::int[]), coalesce(array_agg(z.k5 order by z.o), '{}'::int[]),
                 coalesce(array_agg(z.k6 order by z.o), '{}'::int[])
            into v_7c_cq, v_7c_k1, v_7c_k2, v_7c_k3, v_7c_k4, v_7c_k5, v_7c_k6
            from (select y.*, row_number() over (order by y.k1 desc, y.k2 desc, y.k3, y.k4 desc, y.k5, y.k6, y.q) as o
                    from (select g.q, (g.q = v_7c_lidp)::int as k1, (g.q = any (v_prev))::int as k2,
                                 coalesce(v_7c_hab[(g.q - 1) * 4 + 1], 0) as k3,
                                 case when v_loc > 0
                                       and coalesce(p_ocup[(g.q - 1) * v_nh + v_h + case when v_t = 1 then 1 else -1 end], 0) > 0
                                       and p_ocup[(g.q - 1) * v_nh + v_h + case when v_t = 1 then 1 else -1 end] <> v_i
                                       and p_loc[p_ocup[(g.q - 1) * v_nh + v_h + case when v_t = 1 then 1 else -1 end]] = v_loc
                                      then 1 else 0 end as k4,
                                 (v_uso)[(g.q - 1) * v_nw + v_w] as k5, coalesce(v_7c_cus[g.q], 999999) as k6
                            from generate_series(1, v_np) g(q)
                           where g.q <> v_dono and not (g.q = any (v_esc))
                             and (p_cap)[(g.q - 1) * v_nh + v_h] = 1 and (p_ocup)[(g.q - 1) * v_nh + v_h] in (0, -v_i)
                             and (v_uso)[(g.q - 1) * v_nw + v_w] < (p_teto)[(g.q - 1) * v_nw + v_w]
                             and (v_rest)[(g.q - 1) * v_nw + v_w] > 0) y) z;
          -- (b) o responsável que falta
          if not v_7c_dita and v_7c_ex <> 0 then
            for v_7c_it in 1 .. 4 loop
              v_7c_falta := public._agenda_atende(v_7c_ex,
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 1], 0) from unnest(v_esc) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 2], 0) from unnest(v_esc) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 3], 0) from unnest(v_esc) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 4], 0) from unnest(v_esc) with ordinality u(e, o) order by o),
                v_7c_dt, v_7c_dalt, v_7c_n);
              exit when v_7c_falta is null or v_7c_falta not in ('energizado', 'comissionamento', 'diagnostico', 'altura');
              v_7c_xj := null;
              for v_7c_j in 1 .. coalesce(cardinality(v_7c_cq), 0) loop
                continue when v_7c_cq[v_7c_j] = any (v_esc);
                continue when coalesce(v_7c_hab[(v_7c_cq[v_7c_j] - 1) * 4 + 4], 0) = 2
                              and not (v_7c_dt or exists (select 1 from unnest(v_esc) e where coalesce(v_7c_hab[(e - 1) * 4 + 4], 0) = 0
                                                and coalesce(v_7c_hab[(e - 1) * 4 + 1], 0) >= coalesce((v_7c_n ->> 'par')::int, 2)));
                if public._agenda_atende(v_7c_ex,
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 1], 0) from unnest(v_esc || v_7c_cq[v_7c_j]) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 2], 0) from unnest(v_esc || v_7c_cq[v_7c_j]) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 3], 0) from unnest(v_esc || v_7c_cq[v_7c_j]) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 4], 0) from unnest(v_esc || v_7c_cq[v_7c_j]) with ordinality u(e, o) order by o),
                v_7c_dt, v_7c_dalt, v_7c_n) is distinct from v_7c_falta then
                  v_7c_xj := v_7c_j;
                  exit;
                end if;
              end loop;
              if v_7c_xj is null then
                v_ok := false;
                exit;
              end if;
              if exists (select 1 from generate_series(1, v_7c_xj - 1) j where not (v_7c_cq[j] = any (v_esc))) then
                v_7c_y := 3;
              else
                v_7c_y := 8;
                for v_7c_j in v_7c_xj + 1 .. coalesce(cardinality(v_7c_cq), 0) loop
                  continue when v_7c_cq[v_7c_j] = any (v_esc);
                  continue when public._agenda_atende(v_7c_ex,
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 1], 0) from unnest(v_esc || v_7c_cq[v_7c_j]) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 2], 0) from unnest(v_esc || v_7c_cq[v_7c_j]) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 3], 0) from unnest(v_esc || v_7c_cq[v_7c_j]) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 4], 0) from unnest(v_esc || v_7c_cq[v_7c_j]) with ordinality u(e, o) order by o),
                v_7c_dt, v_7c_dalt, v_7c_n) is not distinct from v_7c_falta;
                  v_7c_y := case when v_7c_k1[v_7c_xj] is distinct from v_7c_k1[v_7c_j] then 2 when v_7c_k2[v_7c_xj] is distinct from v_7c_k2[v_7c_j] then 4
                                 when v_7c_k3[v_7c_xj] is distinct from v_7c_k3[v_7c_j] then 3 when v_7c_k4[v_7c_xj] is distinct from v_7c_k4[v_7c_j] then 5
                                 when v_7c_k5[v_7c_xj] is distinct from v_7c_k5[v_7c_j] then 6 when v_7c_k6[v_7c_xj] is distinct from v_7c_k6[v_7c_j] then 7
                                 else 10 end;
                  exit;
                end loop;
              end if;
              v_esc := v_esc || v_7c_cq[v_7c_xj];
              v_7c_ecr := v_7c_ecr || v_7c_y;
            end loop;
          end if;
          -- (c) o resto até o desejado
          if v_ok then
            v_7c_j0 := coalesce(cardinality(v_esc), 0);
            for v_7c_it in 1 .. 2 loop
              for v_7c_j in 1 .. coalesce(cardinality(v_7c_cq), 0) loop
                exit when cardinality(v_esc) >= v_need;
                continue when v_7c_cq[v_7c_j] = any (v_esc);
                continue when coalesce(v_7c_hab[(v_7c_cq[v_7c_j] - 1) * 4 + 4], 0) = 2
                              and not (v_7c_dt or exists (select 1 from unnest(v_esc) e where coalesce(v_7c_hab[(e - 1) * 4 + 4], 0) = 0
                                                and coalesce(v_7c_hab[(e - 1) * 4 + 1], 0) >= coalesce((v_7c_n ->> 'par')::int, 2)));
                v_esc := v_esc || v_7c_cq[v_7c_j];
              end loop;
            end loop;
            for v_7c_j in v_7c_j0 + 1 .. coalesce(cardinality(v_esc), 0) loop
              v_7c_x := array_position(v_7c_cq, v_esc[v_7c_j]);
              v_7c_y := 8;
              for v_7c_it in v_7c_x + 1 .. coalesce(cardinality(v_7c_cq), 0) loop
                continue when v_7c_cq[v_7c_it] = any (v_esc);
                v_7c_y := case when v_7c_k1[v_7c_x] is distinct from v_7c_k1[v_7c_it] then 2 when v_7c_k2[v_7c_x] is distinct from v_7c_k2[v_7c_it] then 4
                                 when v_7c_k3[v_7c_x] is distinct from v_7c_k3[v_7c_it] then 3 when v_7c_k4[v_7c_x] is distinct from v_7c_k4[v_7c_it] then 5
                                 when v_7c_k5[v_7c_x] is distinct from v_7c_k5[v_7c_it] then 6 when v_7c_k6[v_7c_x] is distinct from v_7c_k6[v_7c_it] then 7
                                 else 10 end;
                exit;
              end loop;
              v_7c_ecr := v_7c_ecr || v_7c_y;
            end loop;
            -- o dono técnico (dono_como_tecnico com modo_dias): as mesmas condições da 7b, logo abaixo
            if v_dtec and cardinality(v_esc) = v_need - 1 and v_dono > 0 and v_role = 0 and not (v_dono = any (v_esc))
               and not (v_fecha and v_k + 1 = v_n) and not coalesce((p_o ->> 'dono_nunca')::boolean, false)
               and p_cap[(v_dono - 1) * v_nh + v_h] = 1 and p_ocup[(v_dono - 1) * v_nh + v_h] in (0, -v_i)
               and v_uso[(v_dono - 1) * v_nw + v_w] < p_teto[(v_dono - 1) * v_nw + v_w]
               and v_rest[(v_dono - 1) * v_nw + v_w] > 0 then
              v_role := 1;
              v_need := v_need - 1;
            end if;
            if cardinality(v_esc) < v_need then
              v_ok := false;
            end if;
          end if;
        end if;
      end if;
      -- FASE 7c: fim
      if cardinality(v_esc) < v_need then
        select coalesce(array_agg(g.q order by (g.q = any (v_prev)) desc, (v_uso)[(g.q - 1) * v_nw + v_w], g.q), '{}'::int[])
          into v_cand
          from generate_series(1, v_np) g(q)
         where g.q <> v_dono and not (g.q = any (v_esc))
           and (p_cap)[(g.q - 1) * v_nh + v_h] = 1 and (p_ocup)[(g.q - 1) * v_nh + v_h] in (0, -v_i)
           and (v_uso)[(g.q - 1) * v_nw + v_w] < (p_teto)[(g.q - 1) * v_nw + v_w]
           and (v_rest)[(g.q - 1) * v_nw + v_w] > 0;
        -- FASE 7b: (quem nunca fica sozinho) o novato e quem vem sob demanda vão depois dos outros
        if v_nov is not null then
          v_cand := array(select u.c from unnest(v_cand) with ordinality u(c, o) order by u.c = any (v_nov), u.o);
        end if;
        -- FASE 7b: fim
        foreach q in array v_cand loop
          exit when cardinality(v_esc) >= v_need;
          v_esc := v_esc || q;
        end loop;
        -- FASE 7b: (o dono técnico, dono_como_tecnico) o dono entra por último, no lugar do diarista que falta: livre no meio-dia,
        -- abaixo do teto dele e sem estar já no meio-dia (nem no turno nem na abertura); nunca no último passo do serviço que ele fecha
        -- (o fechamento vai nele) nem no serviço "sem você" (dono_nunca). Ele vai como o dono no turno (o papel 1: conta nos turnos do
        -- dono e no teto dele, e fica fora da soma da equipe, como sempre).
        if v_dtec and cardinality(v_esc) = v_need - 1 and v_dono > 0 and v_role = 0 and not (v_dono = any (v_esc))
           and not (v_fecha and v_k + 1 = v_n) and not coalesce((p_o ->> 'dono_nunca')::boolean, false)
           and p_cap[(v_dono - 1) * v_nh + v_h] = 1 and p_ocup[(v_dono - 1) * v_nh + v_h] in (0, -v_i)
           and v_uso[(v_dono - 1) * v_nw + v_w] < p_teto[(v_dono - 1) * v_nw + v_w]
           and v_rest[(v_dono - 1) * v_nw + v_w] > 0 then
          v_role := 1;
          v_need := v_need - 1;
        end if;
        -- FASE 7b: fim
      end if;
      -- FASE 7c: (7c P2, §3.7) fora de modo_habilidade ligado, a escolha é a de antes (logo acima) e o critério de cada um que ela pôs
      -- sai das chaves de antes, contra o próximo da lista dela que ficou de fora: 3 quando ganhou por não ser de quem nunca fica
      -- sozinho (a ordem da 7b), 4 por estar no meio-dia anterior, 6 pela carga da semana, 10 pela posição; sem próximo, 8.
      if v_7c and v_7c_hm = 0 and coalesce(cardinality(v_esc), 0) > coalesce(cardinality(v_7c_ecr), 0) then
        for v_7c_j in coalesce(cardinality(v_7c_ecr), 0) + 1 .. cardinality(v_esc) loop
          v_7c_x := array_position(v_cand, v_esc[v_7c_j]);
          v_7c_y := 8;
          if v_7c_x is not null then
            for v_7c_it in v_7c_x + 1 .. coalesce(cardinality(v_cand), 0) loop
              continue when v_cand[v_7c_it] = any (v_esc);
              v_7c_y := case when v_nov is not null
                                  and (v_cand[v_7c_x] = any (v_nov)) is distinct from (v_cand[v_7c_it] = any (v_nov)) then 3
                             when (v_cand[v_7c_x] = any (v_prev)) is distinct from (v_cand[v_7c_it] = any (v_prev)) then 4
                             when (v_uso)[(v_cand[v_7c_x] - 1) * v_nw + v_w] is distinct from (v_uso)[(v_cand[v_7c_it] - 1) * v_nw + v_w]
                               then 6
                             else 10 end;
              exit;
            end loop;
          end if;
          v_7c_ecr := v_7c_ecr || v_7c_y;
        end loop;
      end if;
      -- FASE 7c: fim
      if cardinality(v_esc) < v_need then v_ok := false; end if;
    end if;

    -- FASE 7c: (7c P2, §5.2 7) com modo_habilidade ligado e sem a palavra do dono, a equipe do meio-dia tem de atender (_agenda_atende:
    -- o que ele pede e o par do novo); senão o meio-dia é lacuna, como a falta de gente
    if v_ok and v_7c_hm = 1 and not v_7c_dita
       and public._agenda_atende(v_7c_ex,
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 1], 0) from unnest(v_esc) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 2], 0) from unnest(v_esc) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 3], 0) from unnest(v_esc) with ordinality u(e, o) order by o),
                array(select coalesce(v_7c_hab[(e - 1) * 4 + 4], 0) from unnest(v_esc) with ordinality u(e, o) order by o),
                case when p_reserva then (v_t = 1 and coalesce((p_o ->> 'dt_m')::boolean, false))
                                         or (v_t = 2 and coalesce((p_o ->> 'dt_t')::boolean, false)) else v_role = 1 end,
                v_7c_dalt, v_7c_n) is not null then
      v_ok := false;
    end if;
    -- FASE 7c: fim
    -- FASE 7b: (quem nunca fica sozinho; R4.3(d)) o meio-dia que ficaria só com novatos ou quem vem sob demanda (e sem o dono no
    -- turno) ganha o 1º outro livre (vira dupla); sem ninguém, é lacuna. A equipe dita e a pessoa pedida pelo dono valem como ele disse.
    if v_ok and v_nov is not null and v_fixa = 0 and coalesce(cardinality(v_pm), 0) + coalesce(cardinality(v_pt), 0) = 0
       and v_role <> 1 and cardinality(v_esc) > 0 and not exists (select 1 from unnest(v_esc) e where not (e = any (v_nov))) then
      v_7b_x := null;
      select g.q into v_7b_x
        from generate_series(1, v_np) g(q)
       where g.q <> v_dono and not (g.q = any (v_esc)) and not (g.q = any (v_nov))
         and (p_cap)[(g.q - 1) * v_nh + v_h] = 1 and (p_ocup)[(g.q - 1) * v_nh + v_h] in (0, -v_i)
         and (v_uso)[(g.q - 1) * v_nw + v_w] < (p_teto)[(g.q - 1) * v_nw + v_w]
         and (v_rest)[(g.q - 1) * v_nw + v_w] > 0
       order by (g.q = any (v_prev)) desc, (v_uso)[(g.q - 1) * v_nw + v_w], g.q
       limit 1;
      if v_7b_x is null then
        v_ok := false;
      else
        v_esc := v_esc || v_7b_x;
      end if;
    end if;
    -- FASE 7b: fim
    -- FASE 7: (7a P5) o teto da equipe: os diaristas deste meio-dia só entram se a equipe (sem o dono) fica até o teto dela na
    -- semana — a soma de antes + os escolhidos agora <= teq, o mesmo que exigir, um a um, a soma abaixo do teto (o meio-dia é
    -- tudo ou nada: sem os diaristas que pede, é lacuna). Meio-dia sem diarista (só o dono no turno) não tem o que conferir.
    if v_ok and v_teq is not null and cardinality(v_esc) > 0
       and v_equ[v_w] + cardinality(v_esc) > coalesce(v_teq[v_w], 0) then
      v_ok := false;
    end if;
    -- FASE 7: fim
    if v_ok then
      -- FASE 7c: (7c P2, §5.2 8) o critério e a máscara de cada um que entra, na ordem em que entram (o dono, depois a equipe): o dono
      -- (turno ou abertura) 9; a equipe o da escolha (quem a 7b acrescentou para não deixar ninguém sozinho, 3: é a companhia)
      if v_7c then
        if v_role in (1, 2) then
          v_7c_acr := v_7c_acr || 9;
          v_7c_aex := v_7c_aex || v_7c_ex;
        end if;
        for v_7c_j in 1 .. coalesce(cardinality(v_esc), 0) loop
          v_7c_acr := v_7c_acr || coalesce(v_7c_ecr[v_7c_j], 3);
          v_7c_aex := v_7c_aex || v_7c_ex;
        end loop;
      end if;
      -- FASE 7c: fim
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
      -- FASE 7b: (sábado) quantos meios-dias do bloco caem no sábado
      if v_sab is not null and v_d = any (v_sab) then
        v_nsab := v_nsab + 1;
      end if;
      -- FASE 7b: fim
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
      -- FASE 7c: (7c P2, §5.2 9) o fechamento do dono: o critério 9, sem máscara
      if v_7c then
        v_7c_acr := v_7c_acr || 9;
        v_7c_aex := v_7c_aex || 0;
      end if;
      -- FASE 7c: fim
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
            -- FASE 7c: (7c P2, §5.2 9) o fechamento do dono: o critério 9, sem máscara
            if v_7c then
              v_7c_acr := v_7c_acr || 9;
              v_7c_aex := v_7c_aex || 0;
            end if;
            -- FASE 7c: fim
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

  -- FASE 7c: (7c P2, §5.2 10) com hab no p_g, a mesma saída mais cr (o critério de cada alocação, na ordem de p: 1 dono_disse, 2
  -- lider, 3 habilidade, 4 continuidade, 5 local, 6 carga, 7 custo, 8 unico, 9 presenca_do_dono, 10 empate) e ex (a máscara do
  -- meio-dia de cada uma); na tentativa com o sábado, mais sab, como logo abaixo
  if v_7c then
    return jsonb_build_object('d0', p_d0, 'ini', v_ini, 'fim', v_fim, 'int', v_int, 'md', v_md, 'mesmo', v_mesmo,
                              'p', to_jsonb(v_ap), 'h', to_jsonb(v_ah), 'pr', to_jsonb(v_apr),
                              'cr', to_jsonb(v_7c_acr), 'ex', to_jsonb(v_7c_aex))
           || case when v_sab is not null then jsonb_build_object('sab', v_nsab) else '{}'::jsonb end;
  end if;
  -- FASE 7c: fim
  -- FASE 7b: (sábado) na tentativa com o sábado, a mesma saída mais sab (quantos meios-dias caíram nele)
  if v_sab is not null then
    return jsonb_build_object('d0', p_d0, 'ini', v_ini, 'fim', v_fim, 'int', v_int, 'md', v_md, 'mesmo', v_mesmo,
                              'p', to_jsonb(v_ap), 'h', to_jsonb(v_ah), 'pr', to_jsonb(v_apr), 'sab', v_nsab);
  end if;
  -- FASE 7b: fim
  return jsonb_build_object('d0', p_d0, 'ini', v_ini, 'fim', v_fim, 'int', v_int, 'md', v_md, 'mesmo', v_mesmo,
                            'p', to_jsonb(v_ap), 'h', to_jsonb(v_ah), 'pr', to_jsonb(v_apr));
end;
$function$;

comment on function public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer) is
  'Agenda de Produção (Fase 2, P2): tenta encaixar a OS p_o (i, passos, abre, fecha, dt_m/dt_t = o dono o turno inteiro, dm/dtd = diaristas desejados, pm/pt = os ditos por turno, fixa = a pessoa pedida, bem = dias com o bem fora) começando no dia p_d0. O bloco começa no 1º meio-dia de d0 em que o 1º passo sai inteiro; cada passo pede: no máximo wip_max OS no meio-dia (contando a própria), o dono conforme o molde (turno livre e abaixo do teto, ou a ponta da abertura no 1º), e os diaristas desejados (os ditos, senão trocados por quem estava no meio-dia anterior, a menor carga, o nome) livres, abaixo do teto (p_teto × p_uso) e com lugar na semana inteira (p_rest = 100% − compromisso − reserva); meio-dia sem o desejado = lacuna; dia útil inteiro sem passo depois de começar = interrupção (mais que interrupcoes_max = inválido); dia não útil e bem fora são pulados. O fechamento vai na última ponta ou desliza para a próxima ponta livre. Reserva (p_reserva) = só diaristas, sem o dono. Devolve {d0, ini, fim, int, md (turnos do dono), mesmo (local), p[], h[], pr[] (0 turno, 1 abertura, 2 fechamento)} ou null. FASE 7 (7a P5): com o teto da equipe em p_g (teq, que o encaixe só manda no compromisso da OS sem o teto de 100%) e fora da reserva, os diaristas de cada meio-dia só entram se a soma da equipe na semana (o uso de compromisso de todos menos o dono, o de partida e o já posto no bloco) mais eles fica até teq[semana]; senão o meio-dia é lacuna. Sem teq, o de antes. FASE 7b (P4, §5.3, R4.3(d)/(e)): dk (p_o) = as pessoas de cada passo do molde — o passo k pede dk[k], menos 1 quando o dono está no turno e conta como uma delas (dk_dono_conta; também na reserva, como o desejado de antes); sab (p_g, só na tentativa com o sábado) = o sábado é dia de trabalho só de manhã (a tarde é pulada sem contar), nunca o 1º passo e sem contar como dia parado, e o bloco devolve sab = quantos meios-dias caíram nele; novato (p_g) = quem nunca fica sozinho vai depois dos outros na escolha, e o meio-dia que ficaria só com eles (sem o dono no turno) ganha o 1º outro livre ou é lacuna (a equipe dita e a pessoa pedida valem como o dono disse); dono_tec (p_g) = o dono entra por último, livre no meio-dia, abaixo do teto dele e sem estar já nele. Sem essas chaves, o de antes, byte a byte. FASE 7c (P2, §5.2, §3.4–§3.7): com hab no p_g (o encaixe do agenda_propor da 7c), o bloco devolve também cr (o critério de cada alocação: 1 dono_disse, 2 lider, 3 habilidade, 4 continuidade, 5 local, 6 carga, 7 custo, 8 unico, 9 presenca_do_dono, 10 empate) e ex (a máscara do meio-dia: ext | o exu no último passo, menos com o fechamento do dono que cobre; na reserva, o que o turno do dono cobriria conta como atendido, menos o teto). Com lid_modo, o responsável duro (lid_duro, fora da reserva, sem a palavra do dono) entra antes (critério 2) ou o meio-dia não dá. Com hab_modo, a escolha da 7c: os candidatos na ordem (responsável planejado, anterior, o menos qualificado, mesmo local, carga, diária, posição), o responsável que falta (o que o meio-dia pede e ninguém tem; também acima do desejado), o novo nunca sem um responsável nem o dono no turno, e a conferência por _agenda_atende (a lacuna, como a falta de gente); o "novato nunca sozinho" da 7b não roda. Sem hab, o de antes, byte a byte.';

-- _agenda_so_diaristas (de 20261025100200_agenda_fase2_motor.sql)
create or replace function public._agenda_so_diaristas(p_b jsonb, p_dono int)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case when count(*) = 0 then null
              else p_b || jsonb_build_object('p', jsonb_agg(t.p order by t.k), 'h', jsonb_agg(t.h order by t.k),
                                             'pr', jsonb_agg(t.pr order by t.k), 'ini', min(t.h), 'fim', max(t.h), 'md', 0) end
    from unnest(public._agenda_ints(p_b -> 'p'), public._agenda_ints(p_b -> 'h'), public._agenda_ints(p_b -> 'pr'))
         with ordinality t(p, h, pr, k)
   where t.p <> p_dono and t.pr = 0;
  -- FASE 7c: (7c P2, §5.2) o bloco do motor da 7c (com cr) leva o critério e a máscara de cada turno da equipe junto, na mesma ordem;
  -- a função devolve o último select (sem cr, o mesmo de cima, byte a byte)
  select case when count(*) = 0 then null
              else p_b || jsonb_build_object('p', jsonb_agg(t.p order by t.k), 'h', jsonb_agg(t.h order by t.k),
                                             'pr', jsonb_agg(t.pr order by t.k), 'ini', min(t.h), 'fim', max(t.h), 'md', 0)
                   || case when p_b ? 'cr' then jsonb_build_object('cr', jsonb_agg(t.cr order by t.k), 'ex', jsonb_agg(t.ex order by t.k))
                           else '{}'::jsonb end end
    from unnest(public._agenda_ints(p_b -> 'p'), public._agenda_ints(p_b -> 'h'), public._agenda_ints(p_b -> 'pr'),
                public._agenda_ints(p_b -> 'cr'), public._agenda_ints(p_b -> 'ex'))
         with ordinality t(p, h, pr, cr, ex, k)
   where t.p <> p_dono and t.pr = 0;
  -- FASE 7c: fim
$function$;

comment on function public._agenda_so_diaristas(jsonb, integer) is
  'Agenda de Produção (Fase 2, P2): o bloco só com os turnos da equipe (sem o dono); null se não sobra ninguém. FASE 7c (P2): o bloco com cr leva cr e ex dos turnos da equipe junto, na mesma ordem; sem cr, o de antes.';

-- ── 3. O encaixe: os parâmetros, a troca avisada, o fora habilidade ──────────────────────────────────────────────

-- _agenda_encaixar (de 20261101100300_agenda_fase7b_motor.sql)
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
  -- FASE 7b: (7b P4) o bloco de 1 pessoa da dupla inferida e o sábado de manhã
  v_7b_sab   int[] := public._agenda_ints(p_ctx -> 'sab');
  v_7b_bon   int[] := public._agenda_ints(p_ctx -> 'sab_bonus');
  v_7b_o1    jsonb;
  v_7b_b1    jsonb;
  v_7b_b2    jsonb;
  v_7b_ok    boolean;
  v_7b_hs    int[];
  v_7b_tb    int[];
  v_7b_rb    int[];
  v_7b_gs    jsonb;
  v_7b_teste jsonb := '[]'::jsonb;
  -- FASE 7b: fim
  -- FASE 7c: (7c P2, §5.2) os modos da 7c (do p_par do agenda_propor; sem eles, a regra de antes), a espera pelo responsável e a
  -- tentativa sem ele (a troca avisada)
  v_7c       boolean := p_par ? 'hab_modo' and jsonb_typeof(p_ctx -> 'hab') = 'array';
  v_7c_hm    int := case when p_par ? 'hab_modo' and jsonb_typeof(p_ctx -> 'hab') = 'array' then coalesce((p_par ->> 'hab_modo')::int, 0) else 0 end;
  v_7c_lm    int := case when p_par ? 'hab_modo' and jsonb_typeof(p_ctx -> 'hab') = 'array' then coalesce((p_par ->> 'lid_modo')::int, 0) else 0 end;
  v_7c_le    int := coalesce((p_par ->> 'lid_espera')::int, 0);
  v_7c_sl    jsonb;
  -- FASE 7c: fim
begin
  if v_inicios is null or p_par -> 'wip' is null or p_par -> 'imax' is null then
    raise exception 'agenda: faltam os parâmetros do encaixe (inícios, frentes, interrupções)' using errcode = '22023';
  end if;
  -- FASE 7b: (7b P4) quem nunca fica sozinho e o dono técnico valem em todo bloco (do contexto, que só os põe com os modos da 7b)
  if p_ctx ? 'novato' then
    v_g := v_g || jsonb_build_object('novato', p_ctx -> 'novato');
  end if;
  if p_ctx ? 'dono_tec' then
    v_g := v_g || jsonb_build_object('dono_tec', p_ctx -> 'dono_tec');
  end if;
  -- FASE 7b: fim

  -- FASE 7c: (7c P2, §5.2 1) com os modos da 7c no p_par (o agenda_propor da 7c sempre os manda; as simulações não: a regra de antes,
  -- por ausência), todo bloco leva o que cada pessoa faz (hab, custo), os modos, os níveis, o fechamento que cobre e a espera pelo
  -- responsável — e grava o critério de cada alocação (em qualquer modo: é medida para o 7g)
  if v_7c then
    v_g := v_g || jsonb_build_object('hab', p_ctx -> 'hab', 'custo', p_ctx -> 'custo', 'hab_modo', v_7c_hm, 'lid_modo', v_7c_lm,
                                     'n', coalesce(p_par -> 'n', '{}'::jsonb), 'fcobre', coalesce((p_par ->> 'fcobre')::boolean, false),
                                     'lid_espera', v_7c_le);
  end if;
  -- FASE 7c: fim
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
    -- FASE 7c: (7c P2, §5.2 2, §3.6) a troca avisada do responsável: com modo_lider ligado e o responsável duro na entrada, o melhor
    -- bloco sem ele também; fica o sem ele (lt = true: "troquei o responsável") quando com ele não há bloco ou ele termina mais de
    -- lider_espera_max_du dias úteis depois — até lá, quem manda é o responsável
    if v_7c and v_7c_lm = 1 and coalesce((o ->> 'lid_duro')::boolean, false) then
      v_7c_sl := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_teto, v_uc, v_rest, v_loc,
                   o || '{"lid_duro": false}'::jsonb,
                   case when v_fixar then (o ->> 'fixar_de')::int else (o ->> 'est')::int end,
                   case when v_fixar then (o ->> 'fixar_ate')::int else v_nd end, v_inicios, false);
      if v_7c_sl is not null
         and (v_best is null or public._agenda_du_h(v_util, (v_7c_sl ->> 'fim')::int, (v_best ->> 'fim')::int) > v_7c_le) then
        v_best := v_7c_sl || '{"lt": true}'::jsonb;
      end if;
    end if;
    -- FASE 7c: fim
    -- FASE 7b: (só fora do pedido do dono: o dia dele vale como ele disse)
    if not v_fixar then
    -- FASE 7b: fim
    -- FASE 7b: (7b P4, R4.3(a)) a dupla inferida pela tarefa (fonte regra) nunca segura a OS: sem o bloco da dupla, com ele
    -- terminando mais de dupla_espera dias úteis depois do de 1 pessoa (em teste: depois dele), ou passando do prazo firme que o de
    -- 1 pessoa cumpre, vale o bloco de 1 pessoa em todos os meios-dias (passos1: o meio-dia que seria em dupla vai com 1 e rende 1),
    -- com dupla_falta = os meios-dias que pediam 2 ([{h, onde}]: os primeiros e os últimos de turno do bloco, ou todos). A dita pelo
    -- dono nunca cai aqui (espera a 2ª pessoa: a classe).
    if o ? 'dk' and o ->> 'dupla_fonte' = 'regra' and coalesce((o ->> 'passos1')::int, 0) > 0 then
      v_7b_o1 := (o - 'dk') || jsonb_build_object('passos', o -> 'passos1');
      v_7b_b1 := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_teto, v_uc, v_rest, v_loc, v_7b_o1,
                  case when v_fixar then (o ->> 'fixar_de')::int else (o ->> 'est')::int end,
                  case when v_fixar then (o ->> 'fixar_ate')::int else v_nd end, v_inicios, false);
      if v_7b_b1 is not null and (v_best is null
           or (p_par ->> 'dupla_modo' = 'sombra' and (v_best ->> 'fim')::int > (v_7b_b1 ->> 'fim')::int)
           or (p_par ->> 'dupla_modo' = 'ligado'
               and (select count(*) from generate_series(((v_7b_b1 ->> 'fim')::int + 1) / 2 + 1, ((v_best ->> 'fim')::int + 1) / 2) g
                     where v_util[g]) > coalesce((p_par ->> 'dupla_espera')::int, 0))
           or (o ? 'prazo_h' and (v_best ->> 'fim')::int > (o ->> 'prazo_h')::int
               and (v_7b_b1 ->> 'fim')::int <= (o ->> 'prazo_h')::int)) then
        v_7b_hs := array(select distinct x.h from unnest(public._agenda_ints(v_7b_b1 -> 'h'), public._agenda_ints(v_7b_b1 -> 'pr')) x(h, pr)
                          where x.pr = 0 order by x.h);
        v_best := v_7b_b1 || jsonb_build_object('um', true, 'dupla_falta', coalesce((
          select jsonb_agg(jsonb_build_object('h', v_7b_hs[k], 'onde', case when coalesce((o ->> 'dupla_todos')::boolean, false) then 'todos'
                                                                          when k <= coalesce((o ->> 'dupla_ni')::int, 0) then 'inicio'
                                                                          else 'fim' end) order by k)
            from generate_series(1, cardinality(v_7b_hs)) k
           where coalesce((o ->> 'dupla_todos')::boolean, false) or k <= coalesce((o ->> 'dupla_ni')::int, 0)
              or k > cardinality(v_7b_hs) - coalesce((o ->> 'dupla_nf')::int, 0)), '[]'::jsonb));
      end if;
    end if;
    -- FASE 7b: fim
    -- FASE 7b: (7b P4, §5.3, AG7-08) o sábado de manhã (modo_sabado fora de desligado, sabado_manha diferente de nunca): só de quem se
    -- ofereceu (a manhã livre na grade), nunca o 1º passo, nunca à tarde; so_prazo = só quando sem ele a OS passa do prazo firme e
    -- com ele cumpre; oferecido = quando ele termina antes. O teto de quem se ofereceu (e o da equipe, quando há) ganha as manhãs dele
    -- só nesta tentativa. Ligado: vale o bloco com o sábado (sabado true); em teste: fica o de sem sábado e o com sábado vai em
    -- sab_teste (a linha "Em teste"). As reservas nunca usam o sábado.
    if coalesce(p_par ->> 'sab_modo', 'desligado') <> 'desligado' and coalesce(p_par ->> 'sab_politica', 'nunca') <> 'nunca'
       and cardinality(v_7b_sab) > 0
       and (p_par ->> 'sab_politica' = 'oferecido'
            or (o ? 'prazo_h' and (v_best is null or (v_best ->> 'fim')::int > (o ->> 'prazo_h')::int))) then
      v_7b_tb := array(select t.x1 + coalesce(t.x2, 0) from unnest(v_teto, v_7b_bon) as t(x1, x2));
      v_7b_rb := array(select t.x1 + coalesce(t.x2, 0) from unnest(v_rest, v_7b_bon) as t(x1, x2));
      v_7b_gs := v_g || jsonb_build_object('sab', p_ctx -> 'sab');
      if v_7b_gs ? 'teq' then
        v_7b_gs := v_7b_gs || jsonb_build_object('teq', to_jsonb(array(
          select t.x + coalesce((select sum(v_7b_bon[(pp - 1) * (p_ctx ->> 'nw')::int + t.w]) from generate_series(1, (p_ctx ->> 'np')::int) pp
                                  where pp <> v_dono), 0)
            from unnest(public._agenda_ints(v_7b_gs -> 'teq')) with ordinality t(x, w) order by t.w)));
      end if;
      v_7b_b2 := public._agenda_melhor_bloco(v_7b_gs, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_7b_tb, v_uc, v_7b_rb, v_loc,
                   case when v_best ? 'um' then v_7b_o1 else o end, (o ->> 'est')::int, v_nd, v_inicios, false);
      v_7b_ok := v_7b_b2 is not null and coalesce((v_7b_b2 ->> 'sab')::int, 0) > 0
                 and case when p_par ->> 'sab_politica' = 'so_prazo' then (v_7b_b2 ->> 'fim')::int <= (o ->> 'prazo_h')::int
                          else v_best is null or public._agenda_melhor(v_7b_b2, v_best) end;
      if v_7b_ok then
        if p_par ->> 'sab_modo' = 'ligado' then
          -- (o bloco de 1 pessoa com o sábado: os meios-dias que pediam 2 são os deste bloco)
          if v_best ? 'um' then
            v_7b_hs := array(select distinct x.h from unnest(public._agenda_ints(v_7b_b2 -> 'h'), public._agenda_ints(v_7b_b2 -> 'pr')) x(h, pr)
                              where x.pr = 0 order by x.h);
            v_7b_b2 := v_7b_b2 || jsonb_build_object('um', true, 'dupla_falta', coalesce((
              select jsonb_agg(jsonb_build_object('h', v_7b_hs[k], 'onde', case when coalesce((o ->> 'dupla_todos')::boolean, false) then 'todos'
                                                                              when k <= coalesce((o ->> 'dupla_ni')::int, 0) then 'inicio'
                                                                              else 'fim' end) order by k)
                from generate_series(1, cardinality(v_7b_hs)) k
               where coalesce((o ->> 'dupla_todos')::boolean, false) or k <= coalesce((o ->> 'dupla_ni')::int, 0)
                  or k > cardinality(v_7b_hs) - coalesce((o ->> 'dupla_nf')::int, 0)), '[]'::jsonb));
          end if;
          v_best := v_7b_b2 || jsonb_build_object('sabado', true);
        else
          v_7b_teste := v_7b_teste || jsonb_build_object('i', v_i, 'b', v_7b_b2, 'prazo_h', o -> 'prazo_h');
        end if;
      end if;
    end if;
    -- (o fim do "fora do pedido do dono")
    end if;
    -- FASE 7b: fim
    -- FASE 7c: (7c P2, §5.2 3) com modo_habilidade ligado, a OS que pede alguém (ext ou exu) e não coube, mas cabe sem a habilidade
    -- (hab_modo 0): o fora é habilidade (falta quem o serviço pede), no lugar de sem_encaixe/fixar_nao_cabe; a pendência de reserva
    -- fica igual
    if v_best is null and v_7c and v_7c_hm = 1 and (coalesce((o ->> 'ext')::int, 0) | coalesce((o ->> 'exu')::int, 0)) > 0
       and public._agenda_melhor_bloco(v_g || '{"hab_modo": 0}'::jsonb, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_teto, v_uc,
             v_rest, v_loc, o, case when v_fixar then (o ->> 'fixar_de')::int else (o ->> 'est')::int end,
             case when v_fixar then (o ->> 'fixar_ate')::int else v_nd end, v_inicios, false) is not null then
      v_fora := v_fora || jsonb_build_object('i', v_i, 'motivo', 'habilidade');
      if (o ->> 'classe')::int = 2 and not v_fixar and not coalesce((o ->> 'tem_reserva')::boolean, false) then
        v_pend := v_pend || o;
      end if;
      continue;
    end if;
    -- FASE 7c: fim
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
    -- FASE 7c: (7c P2, §5.2 4) o bloco leva de onde veio o que a OS pede (exf: 1 = pela linha) e a regra (7c ligado; antes fora)
    if v_7c then
      v_best := v_best || jsonb_build_object('exf', coalesce((o ->> 'exf')::int, 0), 'regra', case when v_7c_hm = 1 then '7c' else 'antes' end);
    end if;
    -- FASE 7c: fim
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
    -- FASE 7b: (7b P4, R4.3(a)) a dupla inferida pela tarefa (fonte regra) nunca segura a OS: sem o bloco da dupla, com ele
    -- terminando mais de dupla_espera dias úteis depois do de 1 pessoa (em teste: depois dele), ou passando do prazo firme que o de
    -- 1 pessoa cumpre, vale o bloco de 1 pessoa em todos os meios-dias (passos1: o meio-dia que seria em dupla vai com 1 e rende 1),
    -- com dupla_falta = os meios-dias que pediam 2 ([{h, onde}]: os primeiros e os últimos de turno do bloco, ou todos). A dita pelo
    -- dono nunca cai aqui (espera a 2ª pessoa: a classe).
    if o ? 'dk' and o ->> 'dupla_fonte' = 'regra' and coalesce((o ->> 'passos1')::int, 0) > 0 then
      v_7b_o1 := (o - 'dk') || jsonb_build_object('passos', o -> 'passos1');
      v_7b_b1 := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_t100, v_tot, v_rest, v_loc, v_7b_o1,
                  greatest((o ->> 'est')::int, case when v_semana then v_jde else 1 end),
                  case when v_semana then v_jate else v_nd end, v_inicios, false);
      if v_7b_b1 is not null and (v_best is null
           or (p_par ->> 'dupla_modo' = 'sombra' and (v_best ->> 'fim')::int > (v_7b_b1 ->> 'fim')::int)
           or (p_par ->> 'dupla_modo' = 'ligado'
               and (select count(*) from generate_series(((v_7b_b1 ->> 'fim')::int + 1) / 2 + 1, ((v_best ->> 'fim')::int + 1) / 2) g
                     where v_util[g]) > coalesce((p_par ->> 'dupla_espera')::int, 0))
           or (o ? 'prazo_h' and (v_best ->> 'fim')::int > (o ->> 'prazo_h')::int
               and (v_7b_b1 ->> 'fim')::int <= (o ->> 'prazo_h')::int)) then
        v_7b_hs := array(select distinct x.h from unnest(public._agenda_ints(v_7b_b1 -> 'h'), public._agenda_ints(v_7b_b1 -> 'pr')) x(h, pr)
                          where x.pr = 0 order by x.h);
        v_best := v_7b_b1 || jsonb_build_object('um', true, 'dupla_falta', coalesce((
          select jsonb_agg(jsonb_build_object('h', v_7b_hs[k], 'onde', case when coalesce((o ->> 'dupla_todos')::boolean, false) then 'todos'
                                                                          when k <= coalesce((o ->> 'dupla_ni')::int, 0) then 'inicio'
                                                                          else 'fim' end) order by k)
            from generate_series(1, cardinality(v_7b_hs)) k
           where coalesce((o ->> 'dupla_todos')::boolean, false) or k <= coalesce((o ->> 'dupla_ni')::int, 0)
              or k > cardinality(v_7b_hs) - coalesce((o ->> 'dupla_nf')::int, 0)), '[]'::jsonb));
      end if;
    end if;
    -- FASE 7b: fim
    b := case when v_best is null then null else public._agenda_so_diaristas(v_best, v_dono) end;
    continue when b is null;
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, b, v_i, true, v_ocup, v_curta, v_fr, v_uc, v_ur) x;
    -- FASE 7c: (7c P2, §5.2 4) o bloco leva de onde veio o que a OS pede (exf: 1 = pela linha) e a regra (7c ligado; antes fora)
    if v_7c then
      b := b || jsonb_build_object('exf', coalesce((o ->> 'exf')::int, 0), 'regra', case when v_7c_hm = 1 then '7c' else 'antes' end);
    end if;
    -- FASE 7c: fim
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
    -- FASE 7b: (7b P4, R4.3(a)) a dupla inferida pela tarefa (fonte regra) nunca segura a OS: sem o bloco da dupla, com ele
    -- terminando mais de dupla_espera dias úteis depois do de 1 pessoa (em teste: depois dele), ou passando do prazo firme que o de
    -- 1 pessoa cumpre, vale o bloco de 1 pessoa em todos os meios-dias (passos1: o meio-dia que seria em dupla vai com 1 e rende 1),
    -- com dupla_falta = os meios-dias que pediam 2 ([{h, onde}]: os primeiros e os últimos de turno do bloco, ou todos). A dita pelo
    -- dono nunca cai aqui (espera a 2ª pessoa: a classe).
    if o ? 'dk' and o ->> 'dupla_fonte' = 'regra' and coalesce((o ->> 'passos1')::int, 0) > 0 then
      v_7b_o1 := (o - 'dk') || jsonb_build_object('passos', o -> 'passos1');
      v_7b_b1 := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_t100, v_tot, v_rest, v_loc, v_7b_o1,
                  greatest((o ->> 'est_cond')::int, case when v_semana then v_jde else 1 end),
                  case when v_semana then v_jate else v_nd end, v_inicios, true);
      if v_7b_b1 is not null and (v_best is null
           or (p_par ->> 'dupla_modo' = 'sombra' and (v_best ->> 'fim')::int > (v_7b_b1 ->> 'fim')::int)
           or (p_par ->> 'dupla_modo' = 'ligado'
               and (select count(*) from generate_series(((v_7b_b1 ->> 'fim')::int + 1) / 2 + 1, ((v_best ->> 'fim')::int + 1) / 2) g
                     where v_util[g]) > coalesce((p_par ->> 'dupla_espera')::int, 0))
           or (o ? 'prazo_h' and (v_best ->> 'fim')::int > (o ->> 'prazo_h')::int
               and (v_7b_b1 ->> 'fim')::int <= (o ->> 'prazo_h')::int)) then
        v_7b_hs := array(select distinct x.h from unnest(public._agenda_ints(v_7b_b1 -> 'h'), public._agenda_ints(v_7b_b1 -> 'pr')) x(h, pr)
                          where x.pr = 0 order by x.h);
        v_best := v_7b_b1 || jsonb_build_object('um', true, 'dupla_falta', coalesce((
          select jsonb_agg(jsonb_build_object('h', v_7b_hs[k], 'onde', case when coalesce((o ->> 'dupla_todos')::boolean, false) then 'todos'
                                                                          when k <= coalesce((o ->> 'dupla_ni')::int, 0) then 'inicio'
                                                                          else 'fim' end) order by k)
            from generate_series(1, cardinality(v_7b_hs)) k
           where coalesce((o ->> 'dupla_todos')::boolean, false) or k <= coalesce((o ->> 'dupla_ni')::int, 0)
              or k > cardinality(v_7b_hs) - coalesce((o ->> 'dupla_nf')::int, 0)), '[]'::jsonb));
      end if;
    end if;
    -- FASE 7b: fim
    if v_best is null then
      v_fora := v_fora || jsonb_build_object('i', v_i, 'motivo', 'sem_reserva');
      continue;
    end if;
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, v_best, v_i, true, v_ocup, v_curta, v_fr, v_uc, v_ur) x;
    -- FASE 7c: (7c P2, §5.2 4) o bloco leva de onde veio o que a OS pede (exf: 1 = pela linha) e a regra (7c ligado; antes fora)
    if v_7c then
      v_best := v_best || jsonb_build_object('exf', coalesce((o ->> 'exf')::int, 0), 'regra', case when v_7c_hm = 1 then '7c' else 'antes' end);
    end if;
    -- FASE 7c: fim
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
    -- FASE 7b: (7b P4) no pátio, sem a dupla por meio-dia: os passos do pátio não são os do molde (o que dá para adiantar sem o bem)
    o := o - 'dk';
    -- FASE 7b: fim
    v_best := public._agenda_melhor_bloco(v_g, v_util, v_sem, v_cap, v_curta, v_ocup, v_fr, v_t100, v_tot, v_rest, v_loc,
                o || jsonb_build_object('passos', o -> 'patio_passos', 'bem', o -> 'patio_bem', 'abre', false, 'fecha', false),
                greatest((o ->> 'est_patio')::int, case when v_semana then v_jde else 1 end),
                case when v_semana then v_jate else v_nd end, v_inicios, true);
    continue when v_best is null;
    select x.p_ocup, x.p_curta, x.p_fr, x.p_uc, x.p_ur into v_ocup, v_curta, v_fr, v_uc, v_ur
      from public._agenda_ocupar(v_g, v_sem, v_best, v_i, true, v_ocup, v_curta, v_fr, v_uc, v_ur) x;
    -- FASE 7c: (7c P2, §5.2 4) o bloco leva de onde veio o que a OS pede (exf: 1 = pela linha) e a regra (7c ligado; antes fora)
    if v_7c then
      v_best := v_best || jsonb_build_object('exf', coalesce((o ->> 'exf')::int, 0), 'regra', case when v_7c_hm = 1 then '7c' else 'antes' end);
    end if;
    -- FASE 7c: fim
    v_col := v_col || (v_best || jsonb_build_object('i', v_i, 'tipo', 'reserva', 'reserva_de', 'patio', 'na_janela', true));
  end loop;

  -- FASE 7b: (7b P4) o sábado em teste (a linha "Em teste" do resumo da proposta)
  if jsonb_array_length(v_7b_teste) > 0 then
    return jsonb_build_object('colocadas', v_col, 'fora', v_fora, 'sab_teste', v_7b_teste);
  end if;
  -- FASE 7b: fim
  return jsonb_build_object('colocadas', v_col, 'fora', v_fora);
end;
$function$;

comment on function public._agenda_encaixar(jsonb, jsonb, jsonb) is
  'Agenda de Produção (Fase 2, P2): o guloso serial sobre a grade do contexto. 1) compromisso: classes 1 e 2 na ordem (ordem), cada uma no melhor início (_agenda_melhor_bloco) a partir do est (ou dentro de fixar_de..fixar_ate), com o teto de 80% (100% com acima_da_carga ou pedido do dono), gravando na grade; sem encaixe = fora (sem_encaixe, fixar_nao_cabe, padrao_do_dono). 2) reservas até 100%: teto (classe 2 que não coube na janela), condicionada (classe 3, a partir do est_cond) e pátio (patio_passos nos dias com o bem fora). Na semana (semana = true) só conta o que começa entre jan_de e jan_ate (na_janela). Devolve {colocadas[{i, tipo, reserva_de, d0, ini, fim, int, md, mesmo, p, h, pr, na_janela}], fora[{i, motivo}]}. CORREÇÃO 29/10 (P3): no compromisso, a OS com res_propria (a pessoa × semana de cada meio-dia da reserva DELA, da agenda_propor) tem esses meios-dias devolvidos ao lugar até 100% (teto100 − compromisso − reserva): a reserva dela não conta contra ela, e a promoção cabe. A reserva das outras continua contando; a grade das próximas da fila continua com a reserva (quem a tira é a aplicação). Sem res_propria, o de antes. FASE 7 (7a P5): com teto_equipe no contexto (a regra teto_equipe do gestor), o compromisso da OS que não usa o teto de 100% (acima_da_carga, o pedido do dono) leva o teto da equipe ao bloco (teq: a equipe, sem o dono, até o teto dela na semana; o teto de cada pessoa já vem a 100% do contexto). As reservas não levam. Sem teto_equipe, o de antes. FASE 7b (P4, R4.3(a), §5.3): quem nunca fica sozinho (novato) e o dono técnico (dono_tec) do contexto vão a todo bloco. A dupla inferida (dupla_fonte regra, com passos1), no compromisso e nas reservas por teto e condicionada: sem o bloco da dupla (dk), ou com ele terminando mais de dupla_espera dias úteis depois do bloco de 1 pessoa (em teste, depois dele), ou passando do prazo firme (prazo_h) que o de 1 pessoa cumpre, vale o bloco de 1 pessoa (sem o dk, passos1 passos) com um = true e dupla_falta [{h, onde}] (os primeiros dupla_ni e os últimos dupla_nf meios-dias de turno, ou todos) — a dupla inferida nunca segura nem tira a OS. O pátio, sem dk. O sábado de manhã (sab_modo e sab_politica em p_par; sab e sab_bonus no contexto), só no compromisso fora do pedido do dono: so_prazo = com prazo_h e o melhor bloco terminando depois dele (ou nenhum), a tentativa com o sábado (o teto de quem se ofereceu e o da equipe com as manhãs dele) vale se usa o sábado e termina até o prazo; oferecido = se usa o sábado e é melhor; ligado → o bloco com sabado = true; em teste → fica o de sem sábado e sai sab_teste [{i, b, prazo_h}]. Sem as chaves da 7b, o de antes, byte a byte. FASE 7c (P2, §5.2): com hab_modo no p_par (o agenda_propor da 7c sempre manda) e hab no contexto, todo bloco leva hab, custo, os modos, os níveis, fcobre e a espera, e grava o critério (exf e regra no bloco colocado). No compromisso, com lid_modo e o responsável duro, o bloco sem ele vale (lt = true) quando com ele não há bloco ou ele termina mais de lider_espera_max_du dias úteis depois (_agenda_du_h). Com hab_modo, a OS que pede alguém e não coube, mas cabe sem a habilidade, vai ao fora com o motivo habilidade (a pendência de reserva igual). Sem os modos no p_par (as simulações), o de antes, byte a byte.';

-- ── 4. As alocações do bloco: o critério ─────────────────────────────────────────────────────────────────────────

-- _agenda_alocs_do_bloco (de 20261025100200_agenda_fase2_motor.sql)
create or replace function public._agenda_alocs_do_bloco(p_ctx jsonb, p_b jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'payee_id', p_ctx -> 'pessoas' -> (t.p - 1), 'nome', p_ctx -> 'nomes' -> (t.p - 1),
           'dia', (p_ctx ->> 'd_ini')::date + (t.h - 1) / 2,
           'turno', case when t.h % 2 = 1 then 'manha' else 'tarde' end,
           'presenca', case t.pr when 1 then 'abertura' when 2 then 'fechamento' else 'turno' end)
           order by t.h, t.pr <> 0, t.p), '[]'::jsonb)
    from unnest(public._agenda_ints(p_b -> 'p'), public._agenda_ints(p_b -> 'h'), public._agenda_ints(p_b -> 'pr')) as t(p, h, pr);
  -- FASE 7c: (7c P2, §5.2, §3.7) no bloco do motor da 7c (com cr), cada alocação ganha o critério que decidiu a pessoa (dono_disse,
  -- lider, habilidade, continuidade, local, carga, custo, unico, presenca_do_dono, empate; 0 ou sem código = nulo) e o detalhe {regra
  -- (7c ou antes), exigencias (o que o meio-dia pedia, curto), suposicoes (pessoa_sem_etiqueta: o nível que o meio-dia pedia veio do
  -- padrão; exigencia_pelo_texto: o que a OS pede veio da linha), lider_trocado}; a função devolve o último select (sem cr, as
  -- mesmas alocações de cima, byte a byte)
  select coalesce(jsonb_agg(jsonb_build_object(
           'payee_id', p_ctx -> 'pessoas' -> (t.p - 1), 'nome', p_ctx -> 'nomes' -> (t.p - 1),
           'dia', (p_ctx ->> 'd_ini')::date + (t.h - 1) / 2,
           'turno', case when t.h % 2 = 1 then 'manha' else 'tarde' end,
           'presenca', case t.pr when 1 then 'abertura' when 2 then 'fechamento' else 'turno' end)
           || case when p_b ? 'cr' then jsonb_build_object(
                'criterio', case t.cr when 1 then 'dono_disse' when 2 then 'lider' when 3 then 'habilidade' when 4 then 'continuidade'
                                      when 5 then 'local' when 6 then 'carga' when 7 then 'custo' when 8 then 'unico'
                                      when 9 then 'presenca_do_dono' when 10 then 'empate' end,
                'criterio_detalhe', jsonb_build_object(
                  'regra', coalesce(p_b ->> 'regra', 'antes'),
                  'exigencias', case when coalesce(t.ex, 0) <> 0 then jsonb_build_array(public._agenda_exigencia_texto(t.ex, null, true))
                                     else '[]'::jsonb end,
                  'suposicoes', to_jsonb(array_remove(array[
                    case when coalesce(t.ex, 0) <> 0
                          and coalesce((p_ctx -> 'habf' ->> (t.p - 1))::int, 0) & ((t.ex & 7) | case when t.ex & 8 <> 0 then 3 else 0 end) <> 0
                         then 'pessoa_sem_etiqueta' end,
                    case when coalesce(t.ex, 0) <> 0 and coalesce((p_b ->> 'exf')::int, 0) = 1 then 'exigencia_pelo_texto' end], null)),
                  'lider_trocado', coalesce((p_b ->> 'lt')::boolean, false)))
              else '{}'::jsonb end
           order by t.h, t.pr <> 0, t.p), '[]'::jsonb)
    from unnest(public._agenda_ints(p_b -> 'p'), public._agenda_ints(p_b -> 'h'), public._agenda_ints(p_b -> 'pr'),
                public._agenda_ints(p_b -> 'cr'), public._agenda_ints(p_b -> 'ex')) as t(p, h, pr, cr, ex);
  -- FASE 7c: fim
$function$;

comment on function public._agenda_alocs_do_bloco(jsonb, jsonb) is
  'Agenda de Produção (Fase 2, P2): as alocações de um bloco do motor em ids e datas ({payee_id, nome, dia, turno, presenca}). FASE 7c (P2, §3.7): no bloco com cr, cada alocação ganha criterio (dono_disse, lider, habilidade, continuidade, local, carga, custo, unico, presenca_do_dono, empate) e criterio_detalhe {regra 7c|antes, exigencias [o que o meio-dia pedia, curto], suposicoes [pessoa_sem_etiqueta, exigencia_pelo_texto], lider_trocado}; sem cr, as de antes, byte a byte.';

-- ── 5. O porquê de não caber ─────────────────────────────────────────────────────────────────────────────────────

-- _agenda_por_que_nao (de 20261031100400_agenda_fase7a_teto.sql)
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
  -- FASE 7c: (7c P2) o que a OS pede, o que cada pessoa faz e os níveis (do contexto que o agenda_propor da 7c passa)
  v_7c_ex   int := coalesce((p_o ->> 'ext')::int, 0) | coalesce((p_o ->> 'exu')::int, 0);
  v_7c_hab  int[] := public._agenda_ints(p_ctx -> 'hab');
  v_7c_n    jsonb := coalesce(p_ctx -> 'n', '{}'::jsonb);
  v_7c_dt   boolean := coalesce((p_o ->> 'dt_m')::boolean, false);
  v_7c_dalt int := 0;
  -- FASE 7c: fim
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
  -- FASE 7c: (7c P2, §5.2, §6.8) com modo_habilidade ligado (hab_modo no contexto) e a OS pedindo alguém (ext ou exu): ninguém livre
  -- na manhã do dia que atenda sozinho o que ela pede (_agenda_atende, a regra única; o novo nunca atende sozinho), e o dono fora do
  -- turno (ou no turno sem dar conta: o teto), é o motivo — "ninguém que sobe no teto fica livre nesse dia"
  if coalesce((p_ctx ->> 'hab_modo')::int, 0) = 1 and jsonb_typeof(p_ctx -> 'hab') = 'array' and v_7c_ex > 0 then
    v_7c_dalt := case when v_dono > 0 then coalesce(v_7c_hab[(v_dono - 1) * 4 + 3], 0) else 0 end;
    if public._agenda_atende(v_7c_ex, '{}'::int[], '{}'::int[], '{}'::int[], '{}'::int[], v_7c_dt, v_7c_dalt, v_7c_n) is not null
       and not exists (select 1 from generate_series(1, coalesce((p_ctx ->> 'np')::int, 0)) g(q)
                        where g.q <> v_dono and v_cap[(g.q - 1) * v_nh + v_h] = 1 and v_ocup[(g.q - 1) * v_nh + v_h] in (0, -v_i)
                          and public._agenda_atende(v_7c_ex, array[coalesce(v_7c_hab[(g.q - 1) * 4 + 1], 0)],
                                array[coalesce(v_7c_hab[(g.q - 1) * 4 + 2], 0)], array[coalesce(v_7c_hab[(g.q - 1) * 4 + 3], 0)],
                                array[coalesce(v_7c_hab[(g.q - 1) * 4 + 4], 0)], v_7c_dt, v_7c_dalt, v_7c_n) is null) then
      return format('ninguém que %s fica livre nesse dia', public._agenda_exigencia_texto(v_7c_ex, null, true));
    end if;
  end if;
  -- FASE 7c: fim
  return 'falta gente nesse dia';
end;
$function$;

comment on function public._agenda_por_que_nao(jsonb, jsonb, integer, integer) is
  'Agenda de Produção (Fase 2, P2): o motivo, em palavras, de a OS não caber no dia pedido (a manhã do dia): feriado, fim de semana ("a agenda automática não marca sábado (sábado é só combinando direto com a equipe)"), o bem fora, você ocupado ou fora de campo, quem o dono disse ocupado ("o Roberto já está no Vanderlei"), fora ou com a semana cheia, as frentes cheias; senão "falta gente nesse dia". FASE 7 (7a P5): com teto_equipe no contexto (a regra teto_equipe) e a OS sem o teto de 100%, depois de quem o dono disse e antes das frentes: "a equipe já está com a semana cheia" quando a soma da equipe (sem o dono) na semana já chegou ao teto dela. Sem teto_equipe, o de antes. FASE 7c (P2, §6.8): com hab_modo = 1 no contexto e a OS pedindo alguém, antes do "falta gente": "ninguém que sobe no teto fica livre nesse dia" quando ninguém livre na manhã atende sozinho o que ela pede (_agenda_atende) e o dono no turno não cobre.';

-- ── 6. O aviso de quem o dono disse (nova) ───────────────────────────────────────────────────────────────────────
-- Onde o dono disse quem vai (o pedido com pessoa, a equipe dita), a palavra dele vale; o item diz o que ficaria faltando: a 1ª falta
-- (_agenda_atende, a regra única) dos meios-dias de turno das alocações (a forma de _agenda_alocs_do_bloco), com a máscara de cada um
-- (o que a OS pede em todos e, no último, o do último — menos quando o fechamento do dono cobre). STABLE, sem grant.
create or replace function public._agenda_aviso_da_habilidade(p_os uuid, p_alocs jsonb, p_hoje date)
 returns text
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c       public.agenda_config := public._agenda_cfg();
  v_dono  uuid := public._agenda_dono(null);
  v_exg   jsonb;
  v_todos int;
  v_ult   int;
  v_n     jsonb;
  v_fecha boolean;
  v_ids   uuid[];
  v_dalt  int;
  r       record;
  v_mask  int;
  v_falta text;
  v_bit   int;
begin
  if p_os is null or p_hoje is null or jsonb_typeof(p_alocs) is distinct from 'array' then
    return null;
  end if;
  -- a porta de os_exigencias (o service_role sem login, ou o admin/financeiro logado): a técnica logada que marca pela tela chega ao motor
  -- e receberia o 42501 dela; para ela, nenhum aviso (o que a OS pede é com o administrador)
  begin
    if (case when auth.uid() is not null then not public.is_admin_or_financial(auth.uid())
             else coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') not in ('', 'service_role') end) then
      return null;
    end if;
  exception when others then
    return null;
  end;
  v_exg := public.os_exigencias(p_os, p_hoje);
  v_todos := coalesce((v_exg ->> 'todos')::int, 0);
  v_ult := coalesce((v_exg ->> 'ultimo')::int, 0);
  v_n := jsonb_build_object('ene', c.habilidade_nivel_energizado, 'com', c.habilidade_nivel_comissionar,
                            'dia', c.habilidade_nivel_diagnostico, 'alt', c.habilidade_nivel_altura, 'par', c.habilidade_nivel_par);
  v_fecha := c.habilidade_fechamento_cobre
             and exists (select 1 from jsonb_array_elements(p_alocs) a
                          where a ->> 'presenca' = 'fechamento' and (a ->> 'payee_id')::uuid is not distinct from v_dono);
  v_ids := array(select distinct (a ->> 'payee_id')::uuid from jsonb_array_elements(p_alocs) a
                  where a ->> 'payee_id' is not null and (a ->> 'payee_id')::uuid is distinct from v_dono);
  v_dalt := coalesce((select h.altura from public.agenda_habilidades(p_hoje, array[v_dono]) h), (c.habilidade_dono ->> 'altura')::int, 0);
  for r in
    with h as materialized (select * from public.agenda_habilidades(p_hoje, v_ids)),
    al as (select (a ->> 'payee_id')::uuid as p, a ->> 'nome' as nome, (a ->> 'dia')::date as dia, a ->> 'turno' as turno, t.o
             from jsonb_array_elements(p_alocs) with ordinality t(a, o)
            where a ->> 'presenca' = 'turno'),
    m as (select al.dia, al.turno, bool_or(al.p is not distinct from v_dono) as dono_turno,
                 coalesce(array_agg(coalesce(h.instala, 0)::int order by al.o) filter (where al.p is distinct from v_dono), '{}') as inst,
                 coalesce(array_agg(coalesce(h.comissiona, 0)::int order by al.o) filter (where al.p is distinct from v_dono), '{}') as com,
                 coalesce(array_agg(coalesce(h.altura, 0)::int order by al.o) filter (where al.p is distinct from v_dono), '{}') as alt,
                 coalesce(array_agg(coalesce(h.papel, 0)::int order by al.o) filter (where al.p is distinct from v_dono), '{}') as pap,
                 coalesce(array_agg(al.nome order by al.o) filter (where al.p is distinct from v_dono), '{}') as nomes,
                 coalesce(array_agg(al.nome order by al.o) filter (where al.p is distinct from v_dono and h.papel = 2), '{}') as novos
            from al left join h on h.payee_id = al.p
           group by al.dia, al.turno)
    select m.*, row_number() over (order by m.dia desc, m.turno = 'tarde' desc) = 1 as ultimo
      from m order by m.dia, m.turno = 'tarde'
  loop
    continue when cardinality(r.inst) = 0;   -- só o dono no turno
    v_mask := v_todos | case when r.ultimo and not v_fecha then v_ult else 0 end;
    v_falta := public._agenda_atende(v_mask, r.inst, r.com, r.alt, r.pap, r.dono_turno, v_dalt, v_n);
    continue when v_falta is null;
    if v_falta = 'novato_sozinho' then
      return format('%s %s', public._agenda_lista(r.novos),
                    case when cardinality(r.novos) > 1 then 'são novos' else 'é novo' end
                    || case when cardinality(r.novos) = cardinality(r.nomes)
                            then case when cardinality(r.novos) > 1 then ' e iriam sozinhos' else ' e iria sozinho' end
                            else case when cardinality(r.novos) > 1 then ' e iriam sem um responsável junto'
                                      else ' e iria sem um responsável junto' end end);
    end if;
    v_bit := case v_falta when 'energizado' then 1 when 'comissionamento' then 2 when 'diagnostico' then 8 else 4 end;
    return format('%s %s, e %s pede %s', public._agenda_lista(r.nomes),
                  case when cardinality(r.nomes) > 1 then 'iriam sozinhos' else 'iria sozinho' end,
                  case when r.ultimo and v_ult & v_bit <> 0 and v_todos & v_bit = 0 then 'o último dia' else 'esse dia' end,
                  public._agenda_exigencia_texto(v_bit, null));
  end loop;
  return null;
end;
$function$;

comment on function public._agenda_aviso_da_habilidade(uuid, jsonb, date) is
  'Agenda de Produção (Fase 7c, P2; spec §5.2, §6.8): o aviso do item onde o dono disse quem vai (o pedido com pessoa, a equipe dita) — a 1ª falta (_agenda_atende) dos meios-dias de turno das alocações (a forma de _agenda_alocs_do_bloco), com a máscara de cada um (o que a OS pede em todos e, no último, o do último, menos quando o fechamento do dono cobre): "João iria sozinho, e o último dia pede quem instala sozinho com 220 V ou banco de bateria"; o novo: "Bruno é novo e iria sozinho"; nada faltando = nulo; com login de quem não é admin nem financeiro (a porta de os_exigencias), nulo. STABLE, sem grant (só o agenda_propor, definer, o chama).';

-- ── 7. O motor ───────────────────────────────────────────────────────────────────────────────────────────────────

-- agenda_propor (de 20261101100800_agenda_fase77b_correcao.sql)
create or replace function public.agenda_propor(
  p_escopo     text,
  p_de         date        default null,
  p_ate        date        default null,
  p_os         uuid[]      default null,
  p_restricoes jsonb       default '{}'::jsonb,
  p_persistir  boolean     default false,
  p_origem     text        default 'motor',
  p_autor      uuid        default null,
  p_hoje       date        default public._hoje_brt(),
  p_agora      timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  -- Os pesos da pontuação (plano §4.4, os do Timefold): estrutura para comparar alternativas, não parâmetro do dono.
  c_peso_atraso  constant int := 1000000;
  c_peso_mudanca constant int := 100;
  c_peso_dono    constant int := 10;
  c_peso_interr  constant int := 50;
  c_peso_fim     constant int := 1;
  -- "atrasar" leva a OS para o fim da classe: a ordem dela passa à frente de qualquer posição real da fila.
  c_fim_da_classe constant int := 1000000;
  -- quantas OS que X empurraria entram na pergunta "não cabe" (as mais próximas dela na fila)
  c_candidatas   constant int := 3;
  cf        public.agenda_config;
  v_r       jsonb := coalesce(p_restricoes, '{}'::jsonb);
  v_modo    text;
  v0        bigint;
  v_cong    date;
  v_seg     date;
  v_de      date;
  v_ate     date;
  v_hor     date;
  v_ini     date;
  v_fim     date;
  v_cart    uuid[];
  v_cartj   jsonb;
  v_escopo  uuid[];
  v_tirar   uuid[];
  v_atrasar uuid[];
  v_aceitar uuid[];
  v_acima   boolean;
  v_decisao uuid;
  v_fixar   jsonb;
  v_depois  jsonb;
  v_info    jsonb := '{}'::jsonb;
  v_canc    jsonb;
  v_ign     uuid[];
  v_fila_os uuid[];
  v_ctx     jsonb;
  v_pes     uuid[];
  v_fila    jsonb := '[]'::jsonb;
  v_ent     jsonb;
  v_par     jsonb;
  v_parh    jsonb;
  v_r0      jsonb;
  v_rf      jsonb;
  v_ctxf    jsonb;
  v_base    jsonb;
  v_sim     jsonb;
  v_minh_n  int;
  v_minh_a  int;
  v_os      uuid;
  v_i       int;
  v_e       jsonb;
  v_b       jsonb;
  v_pront   jsonb;
  v_meios   jsonb;
  v_pl      record;
  v_status  text;
  v_k       record;
  v_cl      jsonb;
  v_classe  int;
  v_fx      jsonb;
  v_fp      int;
  v_evento  boolean;
  v_passos  int;
  v_abre    boolean;
  v_fecha   boolean;
  v_dtm     boolean;
  v_dtt     boolean;
  v_fixa    int;
  v_pm      int[];
  v_pt      int[];
  v_est     date;
  v_estc    date;
  v_minh    int;
  v_bem     int[];
  v_pat_p   int;
  v_pat_b   int[];
  v_bem_tudo boolean;
  v_fora    jsonb := '[]'::jsonb;
  v_crit    jsonb := '{}'::jsonb;
  v_xnc     int[] := '{}';
  v_xoc     int[] := '{}';
  v_cands   jsonb := '{}'::jsonb;
  v_h       int[] := '{}';
  v_sem_q   int[] := '{}';
  v_tentativa int;
  v_usadas  jsonb;
  v_perg    jsonb := '[]'::jsonb;
  v_held    jsonb := '[]'::jsonb;
  v_itens   jsonb := '[]'::jsonb;
  v_opc     jsonb;
  v_rec     int;
  v_rec_txt text;
  v_txt     text;
  v_chave   text;
  v_tipo    text;
  v_fim_x   date;
  v_ini_x   date;
  v_fim_c   date;
  v_ini_c   date;
  v_x       int;
  v_c       int;
  v_cb      jsonb;
  v_xb      jsonb;
  v_canc_os uuid[];
  v_ini_antes date;
  v_fim_dep date;
  v_carga   jsonb;
  v_textos  jsonb;
  v_linhas  text[];
  v_tfora   text[];
  v_titulo  text;
  v_texto   text;
  v_pont    jsonb;
  v_viol    jsonb;
  v_pid     uuid;
  v_expira  timestamptz;
  v_dono    uuid := public._agenda_dono(null);
  v_feriados text[];
  v_q       jsonb;
  v_n       int;
  v_aviso   text;
  -- CORREÇÃO 29/10 (P3): a reserva da própria OS no encaixe do compromisso dela (res_propria) e o resumo que separa o
  -- marcado firme do reservado
  v_rp       int[];
  v_marc     text[];
  v_resv     text[];
  v_contagem text;
  -- CORREÇÃO 29/10 (P3): fim
  -- FASE 7: (7a P8) a zona travada: o que fica fora da conta do dia já avisado
  v_f7_fora uuid[];
  -- FASE 7: fim
  -- FASE 7b: (7b P4) a dupla por meio-dia, o prazo firme, o sábado e as linhas em teste
  v_7b_pk     int[];
  v_7b_dk     int[];
  v_7b_tot    int;
  v_7b_prazo  date;
  v_7b_n      int;
  v_7b_semtec int;
  v_7b_tec    text[];
  v_7b_teste  text[] := '{}';
  v_7b_b      jsonb;
  v_7b_e      jsonb;
  v_7b_x      text;
  v_7b_y      text;
  v_7b_dias   date[];
  v_7b_nomes  text[];
  v_7b_z      text;
  v_7b_n2     int;
  -- FASE 7b: fim
  -- FASE 7b: (correção da revisão da 7b, achados 22 e 23) o exemplo com todos os dias e a dupla dita antes de a OS ficar pronta
  v_7bc_dias date[];
  v_7bc_est  date;
  v_7bc_max  date;
  -- FASE 7b: fim
  -- FASE 7c: (7c P2) o que a OS pede, o responsável, os motivos e os textos da 7c
  v_7c_exg   jsonb;
  v_7c_ld    jsonb;
  v_7c_lp    int;
  v_7c_mot   text[];
  v_7c_txt   text;
  v_7c_d     int;
  v_7c_le    boolean;
  -- FASE 7c: fim
begin
  -- ── 0. Entrada ──
  if p_escopo is null or p_escopo not in ('semana', 'os', 'replano') then
    raise exception 'Escopo desconhecido: "%" (semana, os ou replano).', coalesce(p_escopo, '') using errcode = '22023';
  end if;
  if p_origem is null or p_origem not in ('motor', 'vigia', 'dono', 'assistente', 'tela', 'aprovacao') then
    raise exception 'Origem desconhecida: "%".', coalesce(p_origem, '') using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null or jsonb_typeof(v_r) <> 'object' then
    raise exception 'Faltam o dia, a hora ou as restrições do plano.' using errcode = '22023';
  end if;
  if p_escopo in ('os', 'replano') and coalesce(cardinality(p_os), 0) = 0 then
    raise exception 'Diga de que OS é o plano.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  if p_persistir then
    perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  end if;
  cf := public._agenda_cfg();
  v_modo := cf.modo_proposta;
  if p_persistir and v_modo = 'desligado' then
    return jsonb_build_object('ok', false, 'simulacao', false, 'texto', 'A agenda automática está desligada: não monto o plano.');
  end if;
  v0 := cf.versao_plano;
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);

  -- ── 1. A janela ──
  v_seg := p_hoje - (extract(isodow from p_hoje)::int - 1);
  if p_escopo = 'semana' then
    v_de := coalesce(p_de, public.agenda_somar_du(v_seg + 7, 0));
    v_ate := coalesce(p_ate, v_seg + 7 + 5);
  else
    v_de := coalesce(p_de, public.agenda_somar_du(v_cong, 1));
    v_ate := coalesce(p_ate, v_de + 7 * cf.horizonte_semanas);
  end if;
  if v_ate < v_de then
    raise exception 'O período do plano termina antes de começar (% a %).', v_de, v_ate using errcode = '22023';
  end if;
  v_hor := greatest(p_hoje + 7 * cf.horizonte_semanas, v_ate);
  v_ini := v_seg;
  v_fim := v_hor + (7 - extract(isodow from v_hor)::int);

  -- ── Restrições (ids e datas já resolvidos por quem chama) ──
  v_tirar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'tirar', '[]'::jsonb)) x);
  v_atrasar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'atrasar', '[]'::jsonb)) x);
  v_aceitar := array(select x::uuid from jsonb_array_elements_text(coalesce(v_r -> 'aceitar_atraso', '[]'::jsonb)) x);
  v_acima := coalesce((v_r ->> 'acima_da_carga')::boolean, false);
  v_decisao := nullif(v_r ->> 'decisao', '')::uuid;
  if exists (select 1 from jsonb_array_elements(coalesce(v_r -> 'fixar', '[]'::jsonb)) e
              where e ->> 'os' is null or e ->> 'de' is null) then
    raise exception 'fixar precisa da OS e do dia.' using errcode = '22023';
  end if;
  select coalesce(jsonb_object_agg(e ->> 'os', jsonb_build_object('de', e -> 'de', 'ate', coalesce(e -> 'ate', e -> 'de'),
                                                                  'pessoa', e -> 'pessoa')), '{}'::jsonb)
    into v_fixar from jsonb_array_elements(coalesce(v_r -> 'fixar', '[]'::jsonb)) e;
  select coalesce(jsonb_object_agg(e ->> 'os', e -> 'dia'), '{}'::jsonb)
    into v_depois from jsonb_array_elements(coalesce(v_r -> 'so_depois_de', '[]'::jsonb)) e;

  -- ── 2. A carteira, o escopo e o que se sabe de cada OS ──
  select coalesce(array_agg(k.service_order_id order by k.numero collate "C", k.service_order_id), '{}'::uuid[]),
         coalesce(jsonb_object_agg(k.service_order_id::text, jsonb_build_object('sinal', k.sinal_pago > 0, 'aprovada_em', k.aprovada_em)), '{}'::jsonb)
    into v_cart, v_cartj
    from public.os_carteira(p_hoje) k;
  if p_escopo = 'semana' then
    v_escopo := v_cart;
  else
    v_escopo := array(select distinct x from unnest(p_os) x order by 1);
  end if;
  for v_os in
    select x from (select unnest(v_escopo) as x
                   union
                   select a.service_order_id from public.agenda_alocacoes a
                    where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null
                      and p_escopo = 'semana' and not (a.service_order_id = any (v_cart))) q
     order by 1
  loop
    v_info := v_info || jsonb_build_object(v_os::text, jsonb_build_object(
                'pront', public.os_prontidao(v_os, p_hoje), 'meios', public.agenda_meios_da_os(v_os, p_hoje)));
  end loop;

  -- ── 3. Estabilidade: o que não pode mais acontecer sai (e o pedido do dono tira o que a OS tinha) ──
  v_canc := public._agenda_violacoes(v_escopo, v_cart, p_escopo = 'semana', v_info, p_hoje, v_cong);
  v_canc := v_canc || coalesce((
    select jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'os', a.service_order_id, 'motivo', 'dono', 'violada', false,
             'congelado', a.dia <= v_cong, 'tipo', a.tipo, 'estado', a.estado, 'fixado_por', a.fixado_por,
             'reserva_de', a.reserva_de, 'payee_id', a.payee_id, 'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca)
             order by a.service_order_id, a.dia, a.turno = 'tarde', a.payee_id, a.id)
      from public.agenda_alocacoes a
     where v_fixar ? a.service_order_id::text and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje
       and a.resultado is null and lower(a.periodo) > p_agora
       and not exists (select 1 from jsonb_array_elements(v_canc) c where (c ->> 'alocacao_id')::uuid = a.id)), '[]'::jsonb);
  v_ign := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c);

  -- ── 4. A grade e a fila ──
  v_fila_os := array(select x from unnest(v_escopo) x where not (x = any (v_tirar)) order by 1);
  v_ctx := public._agenda_contexto(v_ini, v_fim, p_hoje, v_ign, v_fila_os);
  v_pes := array(select x::uuid from jsonb_array_elements_text(v_ctx -> 'pessoas') x);
  -- o 1º meio-dia que dá: depois do congelado; e, para o evento real e o pedido do dono, o 1º que ainda não começou
  v_minh_n := 2 * (v_cong + 1 - v_ini) + 1;
  v_minh_a := case when lower(public.agenda_periodo(p_hoje, 'manha')) > p_agora then 2 * (p_hoje - v_ini) + 1
                   when lower(public.agenda_periodo(p_hoje, 'tarde')) > p_agora then 2 * (p_hoje - v_ini) + 2
                   else 2 * (p_hoje + 1 - v_ini) + 1 end;

  for v_os in select unnest(v_tirar) loop
    if v_os = any (v_escopo) then
      v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'tirado', 'texto', public._agenda_rotulo_da_os(v_os) || ': você tirou.');
    end if;
  end loop;

  for v_i in 1 .. coalesce(cardinality(v_fila_os), 0) loop
    v_os := v_fila_os[v_i];
    v_pront := v_info -> v_os::text -> 'pront';
    v_meios := v_info -> v_os::text -> 'meios';
    select pl.* into v_pl from public.os_planejamento pl where pl.service_order_id = v_os;
    select so.status into v_status from public.service_orders so where so.id = v_os;
    -- o que fica do plano dela (sem o que a proposta cancela)
    select count(distinct (a.dia, a.turno)) filter (where a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null) as fut,
           coalesce(bool_or(a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido'), false) as algum,
           max(a.dia) filter (where a.tipo <> 'reserva' and a.resultado is distinct from 'nao_cumprido') as ultimo,
           max(a.dia) filter (where a.tipo <> 'reserva' and a.dia >= p_hoje and a.resultado is null) as ultimo_fut,
           coalesce(bool_or(a.tipo <> 'reserva' and a.estado = 'fixada' and a.dia >= p_hoje and a.resultado is null), false) as fixada,
           coalesce(bool_or(a.tipo = 'reserva' and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje), false) as reserva,
           coalesce(bool_or(a.tipo = 'reserva' and a.reserva_de = 'patio' and a.dia >= p_hoje), false) as patio
      into v_k
      from public.agenda_alocacoes a
     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and not (a.id = any (v_ign));
    v_bem_tudo := (v_pl.bem_indisponivel is not null and not isempty(v_pl.bem_indisponivel)
                   and not exists (select 1 from generate_series(p_hoje + 1, v_hor, interval '1 day') g
                                    where not (v_pl.bem_indisponivel @> g::date)))
                  or coalesce(v_pl.nao_antes_de > v_hor, false);
    v_cl := public._agenda_classe_da_os(v_pront, v_meios, p_hoje, v_k.fixada, v_bem_tudo);
    v_classe := (v_cl ->> 'classe')::int;
    v_fx := v_fixar -> v_os::text;
    if v_fx is not null then
      if v_classe = 4 then
        v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'fixar_recusado',
                   'texto', format('%s: %s.', public._agenda_rotulo_da_os(v_os), rtrim(v_cl ->> 'texto', '.')));
        continue;
      end if;
      v_classe := 1;
    end if;
    v_evento := exists (select 1 from jsonb_array_elements(v_canc) c
                         where (c ->> 'os')::uuid = v_os and (c ->> 'violada')::boolean
                           and ((c ->> 'congelado')::boolean or (v_cl ->> 'classe')::int = 1));
    v_passos := case when (v_meios ->> 'total') is null then 0
                     else ceil(greatest((v_meios ->> 'total')::numeric - coalesce((v_meios ->> 'cumpridos')::numeric, 0)
                                        - coalesce(v_k.fut, 0), 0))::int end;
    v_fecha := v_meios ->> 'presenca' = 'abre_e_fecha';
    v_abre := v_fecha and not v_k.algum and coalesce((v_meios ->> 'cumpridos')::numeric, 0) = 0 and v_status <> 'in_progress';
    v_dtm := coalesce((v_meios #>> '{dono_turno,manha}')::boolean, false);
    v_dtt := coalesce((v_meios #>> '{dono_turno,tarde}')::boolean, false);
    v_fixa := 0;
    if v_fx is not null and v_fx ->> 'pessoa' is not null then
      v_fp := array_position(v_pes, (v_fx ->> 'pessoa')::uuid);
      if v_fp is null then
        v_fora := v_fora || jsonb_build_object('os', v_os, 'motivo', 'fixar_recusado',
                   'texto', format('%s: essa pessoa não está na equipe de agora.', public._agenda_rotulo_da_os(v_os)));
        continue;
      elsif v_fp = (v_ctx ->> 'dono')::int then
        v_dtm := true; v_dtt := true; v_abre := false; v_fecha := false;
      else
        v_fixa := v_fp;
      end if;
    end if;
    v_pm := array(select array_position(v_pes, (e ->> 'payee_id')::uuid)
                    from jsonb_array_elements(coalesce(v_meios #> '{por_turno,manha,pessoas}', '[]'::jsonb)) with ordinality t(e, o)
                   where array_position(v_pes, (e ->> 'payee_id')::uuid) is not null order by o);
    v_pt := array(select array_position(v_pes, (e ->> 'payee_id')::uuid)
                    from jsonb_array_elements(coalesce(v_meios #> '{por_turno,tarde,pessoas}', '[]'::jsonb)) with ordinality t(e, o)
                   where array_position(v_pes, (e ->> 'payee_id')::uuid) is not null order by o);
    -- EST': o dia em que fica pronta, depois do congelado (o evento real e o pedido do dono podem usar o que ainda não
    -- começou), depois do "só depois de" e depois do que ela já tem marcado.
    if v_fx is not null then
      v_est := greatest((v_fx ->> 'de')::date, p_hoje);
      v_minh := v_minh_a;
    elsif v_evento then
      v_est := greatest(coalesce((v_pront #>> '{material,inicio_mat}')::date, p_hoje), v_pl.nao_antes_de, p_hoje,
                        (v_depois ->> v_os::text)::date, v_k.ultimo_fut);
      v_minh := v_minh_a;
    else
      v_est := greatest(coalesce((v_pront ->> 'est')::date, (v_pront ->> 'est_sem_material')::date, p_hoje),
                        public.agenda_somar_du(v_cong, 1), (v_depois ->> v_os::text)::date, v_k.ultimo_fut);
      v_minh := v_minh_n;
    end if;
    v_estc := greatest(coalesce((v_pront ->> 'est')::date, (v_pront ->> 'est_sem_material')::date, p_hoje),
                       public.agenda_somar_du(v_cong, 1), (v_depois ->> v_os::text)::date);
    v_bem := array(select g + 1 from generate_series(0, v_fim - v_ini) g
                    where coalesce(v_pl.bem_indisponivel @> (v_ini + g), false));
    -- o pátio: o que dá para adiantar sem o bem, enquanto ele está fora (dentro da janela)
    v_pat_p := 0;
    v_pat_b := '{}';
    if v_pl.adiantavel_patio_dias is not null and not v_k.patio and v_classe in (1, 2, 3) and v_passos > 0
       and exists (select 1 from generate_series(greatest(v_de, public.agenda_somar_du(v_cong, 1)), v_ate, interval '1 day') g
                    where coalesce(v_pl.bem_indisponivel @> g::date, false)) then
      v_pat_p := (v_pl.adiantavel_patio_dias * 2)::int;
      v_pat_b := array(select g + 1 from generate_series(0, v_fim - v_ini) g
                        where not coalesce(v_pl.bem_indisponivel @> (v_ini + g), false));
    end if;
    v_e := jsonb_build_object(
      'i', v_i, 'os', v_os, 'numero', v_pront ->> 'numero', 'cliente_curto', v_pront ->> 'cliente_curto',
      'classe', v_classe, 'motivo', v_cl ->> 'motivo', 'texto', v_cl ->> 'texto', 'condicao_tipo', v_cl ->> 'condicao_tipo',
      'passos', v_passos, 'abre', v_abre, 'fecha', v_fecha, 'dt_m', v_dtm, 'dt_t', v_dtt,
      'dm', coalesce((v_meios #>> '{por_turno,manha,desejado}')::int, 0), 'dtd', coalesce((v_meios #>> '{por_turno,tarde,desejado}')::int, 0),
      'pm', to_jsonb(v_pm), 'pt', to_jsonb(v_pt), 'fixa', v_fixa,
      'est', v_est - v_ini + 1, 'est_cond', v_estc - v_ini + 1, 'est_patio', public.agenda_somar_du(v_cong, 1) - v_ini + 1,
      'min_h', v_minh, 'bem', to_jsonb(v_bem), 'patio_passos', v_pat_p, 'patio_bem', to_jsonb(v_pat_b),
      'tem_reserva', v_k.reserva, 'tem_fixada', v_k.fixada, 'evento_real', v_evento, 'teto100', v_fx is not null,
      'dono_impossivel', ((v_dtm or v_dtt) and not coalesce((v_ctx ->> 'dono_tem_padrao')::boolean, false))
                         or ((v_abre or v_fecha or v_dtm or v_dtt) and coalesce((v_ctx ->> 'dono')::int, 0) = 0),
      'atrasar', v_os = any (v_atrasar), 'prio', v_pl.prioridade_manual, 'razao', v_pront -> 'razao_critica',
      'sinal', coalesce((v_cartj -> v_os::text ->> 'sinal')::boolean, false), 'aprovada_em', v_pront ->> 'aprovada_em',
      'fonte', v_meios ->> 'fonte', 'dias', v_meios -> 'dias', 'precisa', v_pl.precisa_ate,
      'fim_antes', v_pront #>> '{plano,ultimo_dia}', 'kept_max', v_k.ultimo, 'tipo_os',
      -- o tipo do meio-dia: o motivo da regra d05 (diagnóstico, comissionamento), mesmo quando o dono está na equipe
      case v_meios ->> 'regra_motivo' when 'diagnóstico' then 'diagnostico' when 'comissionamento' then 'comissionamento'
           else 'execucao' end)
      || case when v_fx is not null then jsonb_build_object('fixar_de', greatest((v_fx ->> 'de')::date, p_hoje) - v_ini + 1,
                                                            'fixar_ate', (v_fx ->> 'ate')::date - v_ini + 1)
              else '{}'::jsonb end;
    -- CORREÇÃO 29/10 (P3): a reserva DELA (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira
    -- compromisso" cancela) não conta contra ela mesma no encaixe do compromisso. O encaixe já deixava o compromisso usar a
    -- célula da própria reserva, mas o lugar até 100% da semana (teto100 − compromisso − reserva) contava a reserva dela:
    -- com o teto apertado (o João, 4 de 4 meios-dias na semana, todos na reserva do Lenine) a promoção nunca cabia. Vai na
    -- entrada da fila só quando há: res_propria = a pessoa × semana ((pessoa − 1) × nw + semana, a posição de uso_r no
    -- contexto) de cada meio-dia reservado, uma vez por alocação.
    if v_k.reserva then
      v_rp := array(select (array_position(v_pes, a.payee_id) - 1) * (v_ctx ->> 'nw')::int + (a.dia - v_ini) / 7 + 1
                      from public.agenda_alocacoes a
                     where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva'
                       and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje and a.dia between v_ini and v_fim
                       and a.presenca = 'turno' and a.payee_id = any (v_pes) and not (a.id = any (v_ign))
                     order by 1);
      if cardinality(v_rp) > 0 then
        v_e := v_e || jsonb_build_object('res_propria', to_jsonb(v_rp));
      end if;
    end if;
    -- CORREÇÃO 29/10 (P3): fim
    -- FASE 7b: (7b P4, §5.3, R4.3) a entrada da fila, só com os modos da 7b: a dupla por meio-dia (dk = as pessoas dos passos que
    -- restam, os últimos v_passos do molde; dk_dono_conta; a fonte; o texto do cartão); da dupla inferida, o bloco de 1 pessoa
    -- (passos1: ligado com a duração que conserva as diárias-pessoa, a soma do dk — cada meio-dia de dupla vira dois de 1 pessoa —; em
    -- teste ou com os dias ditos pelo dono, os passos de antes), os meios-dias
    -- dela que restam no início e no fim (dupla_ni, dupla_nf; ou dupla_todos) e o nome do que a tarefa pede; o prazo firme (prazo_h =
    -- o índice da tarde de least(precisa_ate, o prometido firme) na grade); e a dupla dita que só passa pela régua dos técnicos com
    -- quem vem sob demanda (dupla_sd: sem eles, a classe daria 4; R4.3(c)).
    v_7b_dk := '{}'::int[];
    if v_meios ? 'dk' then
      v_7b_pk := public._agenda_ints(v_meios #> '{dupla,pk}');
      v_7b_tot := cardinality(v_7b_pk);
      v_7b_dk := case when v_passos > 0 then v_7b_pk[greatest(v_7b_tot - v_passos + 1, 1) : v_7b_tot] else '{}'::int[] end;
      v_e := v_e || jsonb_build_object('dk', to_jsonb(v_7b_dk), 'dk_dono_conta', v_meios -> 'dk_dono_conta',
                                       'dupla_fonte', v_meios #>> '{dupla,fonte}', 'dupla_texto', v_meios #>> '{dupla,texto}');
      if v_meios #>> '{dupla,fonte}' = 'regra' and v_passos > 0 then
        v_e := v_e || jsonb_build_object(
          'passos1', case when (v_meios #>> '{dupla,pm_estimativa}') is not null then (select sum(x)::int from unnest(v_7b_dk) x)
                          else v_passos end,
          'dupla_todos', coalesce((v_meios #>> '{dupla,todos}')::boolean, false),
          'dupla_ni', least(greatest(coalesce((v_meios #>> '{dupla,ni}')::int, 0) - (v_7b_tot - v_passos), 0), v_passos),
          'dupla_nf', least(coalesce((v_meios #>> '{dupla,nf}')::int, 0), v_passos),
          'dupla_rot_ini', public._agenda_lista(array(select distinct on (m ->> 'motivo') m ->> 'frase'
                                                        from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                                                       where m ->> 'onde' = 'inicio' order by m ->> 'motivo')),
          'dupla_rot_fim', public._agenda_lista(array(select distinct on (m ->> 'motivo') m ->> 'frase'
                                                        from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                                                       where m ->> 'onde' = 'fim' order by m ->> 'motivo')),
          'dupla_rot_todos', (select m ->> 'rotulo' from jsonb_array_elements(v_meios #> '{dupla,motivos}') m
                               where m ->> 'onde' = 'todos' limit 1));
      end if;
    end if;
    if cf.dono_como_tecnico and cf.modo_dias <> 'desligado' and v_meios ->> 'presenca' = 'nunca' then
      v_e := v_e || jsonb_build_object('dono_nunca', true);
    end if;
    if cf.modo_sabado <> 'desligado' or v_meios ? 'dk' then
      v_7b_prazo := least(v_pl.precisa_ate, case when v_pl.prometido_tipo = 'firme' then v_pl.prometido_ate end);
      if v_7b_prazo between v_ini and v_fim then
        v_e := v_e || jsonb_build_object('prazo_h', 2 * (v_7b_prazo - v_ini) + 2, 'prazo', v_7b_prazo);
      end if;
    end if;
    if cf.modo_dupla <> 'desligado' and v_pl.dupla_dita in ('todos', 'inicio', 'fim')
       and not coalesce((v_meios ->> 'equipe_dita')::boolean, false) and v_passos > 0 then
      v_7b_n := greatest(coalesce((v_meios #>> '{por_turno,manha,desejado}')::int, 0),
                         coalesce((v_meios #>> '{por_turno,tarde,desejado}')::int, 0),
                         coalesce((select max(x) from unnest(v_7b_dk) x), 0)
                         - case when coalesce((v_meios ->> 'dk_dono_conta')::boolean, true)
                                     and (coalesce((v_meios #>> '{dono_turno,manha}')::boolean, false)
                                          or coalesce((v_meios #>> '{dono_turno,tarde}')::boolean, false)) then 1 else 0 end);
      if v_7b_n >= 2 then
        v_7b_semtec := coalesce(v_7b_semtec, (select count(*)::int from jsonb_array_elements(coalesce(
                         public.agenda_capacidade_semanal(p_hoje) -> 'pessoas', '[]'::jsonb)) x
                        where not coalesce((x ->> 'eh_dono')::boolean, false)));
        if v_7b_semtec < v_7b_n then
          v_e := v_e || jsonb_build_object('dupla_sd', true, 'dupla_n', v_7b_n,
                                           'dupla_meios_n', case when cardinality(v_7b_dk) > 0
                                                                 then (select count(*)::int from unnest(v_7b_dk) x where x >= 2)
                                                                 else v_passos end);
        end if;
      end if;
    end if;
    -- FASE 7b: fim
    -- FASE 7c: (7c P2, §5.2 1) a entrada da fila ganha o que a OS pede (os_exigencias, sem IA: ext = em todos os meios-dias, exu = no
    -- último, exf 1 = pela linha, exig_texto) — em qualquer modo, porque o critério de cada alocação é gravado sempre — e, só com
    -- modo_lider ou modo_habilidade ligado, o responsável (_agenda_lider_da_os, sem as alocações que a proposta cancela): lid (a
    -- posição na grade; fora dela, 0), lid_duro (o dito ou quem fez, com modo_lider ligado e sem a palavra do dono sobre quem vai),
    -- lid_plan (o planejado: só desempata) e lid_fora (o responsável que não está na grade). Só a OS que vai ao encaixe (fora da
    -- classe 4, com passos ou o pátio) é lida. O que a OS pede só é lido com a porta de os_exigencias aberta (o service_role, sem
    -- login, ou o admin/financeiro logado): a técnica logada que marca pela tela (agenda_marcar_os, liberada a authenticated) chega
    -- aqui e receberia o 42501 dela no meio do motor; para ela, a OS "não pede ninguém em especial" (a escolha de antes; o pedido dela
    -- tem a pessoa, a palavra de quem marca, e os filtros 3 a 5 não valem de todo jeito).
    if v_7c_le is null then
      begin
        v_7c_le := case when auth.uid() is not null then public.is_admin_or_financial(auth.uid())
                        else coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') in ('', 'service_role') end;
      exception when others then
        v_7c_le := false;
      end;
    end if;
    if v_7c_le and v_classe <> 4 and (v_passos > 0 or v_pat_p > 0) then
      v_7c_exg := public.os_exigencias(v_os, p_hoje);
      v_e := v_e || jsonb_build_object('ext', coalesce((v_7c_exg ->> 'todos')::int, 0), 'exu', coalesce((v_7c_exg ->> 'ultimo')::int, 0),
                                       'exf', coalesce((v_7c_exg ->> 'fonte_texto')::int, 0), 'exig_texto', v_7c_exg ->> 'texto_curto');
      if cf.modo_lider = 'ligado' or cf.modo_habilidade = 'ligado' then
        v_7c_ld := public._agenda_lider_da_os(v_os, p_hoje, v_ign);
        if v_7c_ld is not null then
          v_7c_lp := array_position(v_pes, (v_7c_ld ->> 'payee_id')::uuid);
          v_e := v_e || jsonb_build_object('lid', coalesce(v_7c_lp, 0), 'lid_nome', v_7c_ld ->> 'nome',
                   'lid_duro', v_7c_ld ->> 'fonte' in ('dono', 'fez') and cf.modo_lider = 'ligado' and v_7c_lp is not null
                               and not (coalesce(cardinality(v_pm), 0) + coalesce(cardinality(v_pt), 0) > 0 or v_fixa > 0),
                   'lid_plan', case when v_7c_ld ->> 'fonte' = 'planejado' then coalesce(v_7c_lp, 0) else 0 end,
                   'lid_fora', v_7c_lp is null);
        end if;
      end if;
    end if;
    -- FASE 7c: fim
    v_fila := v_fila || v_e;
  end loop;

  -- A ordem: (classe, atrasar, prioridade do dono, razão crítica, sinal pago, aprovação, número, id).
  select coalesce(jsonb_agg(x.e || jsonb_build_object('ordem', x.rn) order by x.rn), '[]'::jsonb) into v_fila
    from (select e, row_number() over (order by (e ->> 'classe')::int, (e ->> 'atrasar')::boolean, (e ->> 'prio')::int nulls last,
                                                (e ->> 'razao')::numeric nulls last, (e ->> 'sinal')::boolean desc,
                                                (e ->> 'aprovada_em')::date nulls last, e ->> 'numero' collate "C", e ->> 'os') as rn
            from jsonb_array_elements(v_fila) e) x;
  select coalesce(jsonb_object_agg(e ->> 'i', e), '{}'::jsonb) into v_ent from jsonb_array_elements(v_fila) e;

  v_par := jsonb_build_object('wip', cf.wip_max, 'imax', cf.interrupcoes_max, 'inicios', cf.inicios_tentados_du,
                              'semana', p_escopo = 'semana', 'jan_de', v_de - v_ini + 1, 'jan_ate', v_ate - v_ini + 1,
                              'acima', v_acima);
  -- FASE 7b: (7b P4) os parâmetros do sábado (modo e política) e da dupla (modo; a espera: ligado, dupla_espera_max_du dias úteis;
  -- em teste, 0 — a dupla só entra quando não termina depois do bloco de 1 pessoa, d8), só com os modos da 7b
  if cf.modo_sabado <> 'desligado' or cf.modo_dupla <> 'desligado' then
    v_par := v_par || jsonb_build_object('sab_modo', cf.modo_sabado, 'sab_politica', cf.sabado_manha, 'dupla_modo', cf.modo_dupla,
                                         'dupla_espera', case when cf.modo_dupla = 'ligado' then cf.dupla_espera_max_du else 0 end);
  end if;
  -- FASE 7b: fim
  -- FASE 7c: (7c P2, §5.2 2) os parâmetros da 7c, sempre (o encaixe lê a presença deles como "grave o critério"): hab_modo (os
  -- filtros 3 e 4 e a ordem nova, só ligado), lid_modo (o filtro 5 e a troca avisada, só ligado), os níveis, o fechamento que cobre
  -- o último dia e a espera pelo responsável; o v_parh herda
  v_par := v_par || jsonb_build_object('hab_modo', (cf.modo_habilidade = 'ligado')::int, 'lid_modo', (cf.modo_lider = 'ligado')::int,
                                       'n', jsonb_build_object('ene', cf.habilidade_nivel_energizado, 'com', cf.habilidade_nivel_comissionar,
                                                               'dia', cf.habilidade_nivel_diagnostico, 'alt', cf.habilidade_nivel_altura,
                                                               'par', cf.habilidade_nivel_par),
                                       'fcobre', cf.habilidade_fechamento_cobre, 'lid_espera', cf.lider_espera_max_du);
  -- FASE 7c: fim
  v_parh := v_par || jsonb_build_object('semana', false);

  -- ── 5. O encaixe e a sobrecarga (o banco nunca escolhe quem atrasa) ──
  for v_tentativa in 1 .. 3 loop
    -- (quem ficou sem saída na volta anterior sai da fila: fica fora, sem encaixe)
    v_r0 := public._agenda_encaixar(v_ctx,
              (select jsonb_agg(case when (e ->> 'i')::int = any (v_sem_q) then e || '{"tirar": true}'::jsonb else e end)
                 from jsonb_array_elements(v_fila) e), v_par);
    -- o que é crítico em cada compromisso colocado
    v_crit := '{}'::jsonb;
    for v_b in select e from jsonb_array_elements(v_r0 -> 'colocadas') e where e ->> 'tipo' = 'compromisso' loop
      v_e := v_ent -> (v_b ->> 'i');
      continue when v_e ? 'fixar_de';
      v_os := (v_e ->> 'os')::uuid;
      v_ini_x := v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1;
      v_fim_x := greatest(v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1, (v_e ->> 'kept_max')::date);
      v_canc_os := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c where (c ->> 'os')::uuid = v_os);
      v_ini_antes := (select min((c ->> 'dia')::date) from jsonb_array_elements(v_canc) c
                       where (c ->> 'os')::uuid = v_os and c ->> 'tipo' <> 'reserva');
      v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_x, v_ini_x, p_hoje, v_canc_os, '{}');
      -- FASE 7: (7a P8, spec §3.2 e §5.8) a zona travada (a regra zona_travada): a criticidade de novo, agora sabendo o que fica
      -- fora da conta do dia já avisado — o que não pode mais acontecer, o resto do meio-dia dele e o que volta igual neste
      -- encaixe (_agenda_zona_fora; o fixado pelo dono nunca fica fora: a regra dele não muda).
      if public._agenda_gestor_regra('zona_travada') then
        v_f7_fora := public._agenda_zona_fora(v_canc, v_os, public._agenda_alocs_do_bloco(v_ctx, v_b));
        v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_x, v_ini_x, p_hoje, v_canc_os,
                                             v_f7_fora);
      end if;
      -- FASE 7: fim
      if v_tipo is not null then
        v_crit := v_crit || jsonb_build_object(v_b ->> 'i', jsonb_build_object('tipo', v_tipo, 'fim', v_fim_x, 'ini', v_ini_x));
      end if;
    end loop;
    -- as críticas ainda sem decisão
    v_xnc := array(select k::int from jsonb_each(v_crit) t(k, x)
                    where x ->> 'tipo' = 'nao_cabe' and v_decisao is null
                      and not ((v_ent -> k ->> 'os')::uuid = any (v_aceitar)) and not (k::int = any (v_sem_q)) order by 1);
    v_xoc := array(select k::int from jsonb_each(v_crit) t(k, x)
                    where x ->> 'tipo' <> 'nao_cabe' and v_decisao is null
                      and not ((v_ent -> k ->> 'os')::uuid = any (v_aceitar)) and not (k::int = any (v_sem_q)) order by 1);
    -- quem X empurraria: as da classe 2 colocadas antes dela, novas e sem fixado, as mais próximas
    v_cands := '{}'::jsonb;
    foreach v_x in array v_xnc loop
      v_cands := v_cands || jsonb_build_object(v_x::text, coalesce((
        select jsonb_agg(q.i order by q.ordem desc)
          from (select (b ->> 'i')::int as i, (v_ent -> (b ->> 'i') ->> 'ordem')::int as ordem
                  from jsonb_array_elements(v_r0 -> 'colocadas') b
                 where b ->> 'tipo' = 'compromisso'
                   and (v_ent -> (b ->> 'i') ->> 'classe')::int = 2 and not (v_ent -> (b ->> 'i')) ? 'fixar_de'
                   and not (v_ent -> (b ->> 'i') ->> 'tem_fixada')::boolean and v_ent -> (b ->> 'i') ->> 'fim_antes' is null
                   and (v_ent -> (b ->> 'i') ->> 'ordem')::int < (v_ent -> v_x::text ->> 'ordem')::int
                   and not ((b ->> 'i')::int = any (v_xnc || v_xoc))
                   -- (na 2ª volta, só as que deram opção: quem não faz X caber não fica esperando a decisão)
                   and (v_usadas is null or coalesce(v_usadas -> v_x::text, '[]'::jsonb) @> to_jsonb((b ->> 'i')::int))
                 order by 2 desc limit c_candidatas) q), '[]'::jsonb));
    end loop;
    v_h := array(select distinct x from (select unnest(v_xnc || v_xoc) as x
                                          union select (j)::int from jsonb_each(v_cands) t(k, v), jsonb_array_elements_text(v) j) u
                  order by 1);
    exit when cardinality(v_h) = 0;

    -- O que é publicado sem esperar sai desta mesma rodada (as reservas foram depois de todos os compromissos, e não
    -- tomam o lugar de quem espera a decisão); quem espera fica como item crítico (X, a que não cabe, sai).
    v_rf := v_r0;
    v_ctxf := public._agenda_ctx_com(v_ctx,
                (select coalesce(jsonb_agg(b), '[]'::jsonb) from jsonb_array_elements(v_r0 -> 'colocadas') b
                  where not ((b ->> 'i')::int = any (v_h) and b ->> 'tipo' = 'compromisso')));
    -- a decisão vai encontrar a grade já com o resto publicado: as opções são simuladas sobre ela
    v_base := public._agenda_encaixar(v_ctxf,
                (select jsonb_agg(e) from jsonb_array_elements(v_fila) e where (e ->> 'i')::int = any (v_h)), v_parh);
    v_perg := '[]'::jsonb;
    v_n := cardinality(v_sem_q);
    foreach v_x in array v_xnc || v_xoc loop
      v_e := v_ent -> v_x::text;
      v_os := (v_e ->> 'os')::uuid;
      v_tipo := v_crit -> v_x::text ->> 'tipo';
      v_xb := (select b from jsonb_array_elements(v_base -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso');
      v_fim_x := case when v_xb is null then null
                      else greatest(v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1, (v_e ->> 'kept_max')::date) end;
      v_opc := '[]'::jsonb;
      if v_tipo = 'nao_cabe' then
        if v_fim_x is not null then
          v_opc := v_opc || jsonb_build_object('n', 1, 'os', v_os, 'atraso_dito', public.agenda_du_entre((v_e ->> 'precisa')::date, v_fim_x),
                     'sem_data', false, 'atraso_du', public.agenda_du_entre((v_e ->> 'precisa')::date, v_fim_x), 'numero', v_e ->> 'numero',
                     'texto', format('%s atrasa: termina %s em vez de %s', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                                     public._dia_curto((v_e ->> 'precisa')::date)),
                     'efeito', jsonb_build_object('restricoes', jsonb_build_object('aceitar_atraso', jsonb_build_array(v_os))),
                     'espera', jsonb_build_object(v_os::text, v_fim_x));
        end if;
        for v_c in select (j)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) j loop
          v_sim := public._agenda_encaixar(v_ctxf,
                     (select jsonb_agg(case when (e ->> 'i')::int = v_c
                                            then e || jsonb_build_object('ordem', (e ->> 'ordem')::int + c_fim_da_classe) else e end)
                        from jsonb_array_elements(v_fila) e where (e ->> 'i')::int = any (v_h)), v_parh);
          v_xb := (select b from jsonb_array_elements(v_sim -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso');
          v_cb := (select b from jsonb_array_elements(v_sim -> 'colocadas') b where (b ->> 'i')::int = v_c and b ->> 'tipo' = 'compromisso');
          continue when v_xb is null or v_cb is null
                     or v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1 > (v_e ->> 'precisa')::date;
          v_ini_c := v_ini + ((v_cb ->> 'ini')::int + 1) / 2 - 1;
          v_fim_c := v_ini + ((v_cb ->> 'fim')::int + 1) / 2 - 1;
          v_b := (select b from jsonb_array_elements(v_base -> 'colocadas') b where (b ->> 'i')::int = v_c and b ->> 'tipo' = 'compromisso');
          v_opc := v_opc || jsonb_build_object('n', jsonb_array_length(v_opc) + 1, 'os', v_ent -> v_c::text -> 'os', 'c', v_c,
                     'atraso_dito', case when v_ent -> v_c::text ->> 'precisa' is null then 0
                                         else greatest(public.agenda_du_entre((v_ent -> v_c::text ->> 'precisa')::date, v_fim_c), 0) end,
                     'sem_data', v_ent -> v_c::text ->> 'precisa' is null,
                     'atraso_du', case when v_b is null then 0
                                       else greatest(public.agenda_du_entre(v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1, v_fim_c), 0) end,
                     'numero', v_ent -> v_c::text ->> 'numero',
                     'texto', format('%s passa para %s (%s)', public._agenda_rotulo_da_os((v_ent -> v_c::text ->> 'os')::uuid),
                                     public._agenda_dias_texto(array(select distinct v_ini + (h - 1) / 2
                                                                       from unnest(public._agenda_ints(v_cb -> 'h')) h)),
                                     case when v_ent -> v_c::text ->> 'precisa' is null then 'sem data dita pelo cliente'
                                          else 'precisa até ' || public._dia_curto((v_ent -> v_c::text ->> 'precisa')::date) end),
                     'efeito', jsonb_build_object('restricoes', jsonb_build_object('atrasar', jsonb_build_array(v_ent -> v_c::text -> 'os'))),
                     'espera', jsonb_build_object(v_os::text, v_ini + ((v_xb ->> 'fim')::int + 1) / 2 - 1,
                                                  v_ent -> v_c::text ->> 'os', v_fim_c));
          exit when jsonb_array_length(v_opc) >= 4;
        end loop;
      elsif v_fim_x is not null then
        v_opc := v_opc || jsonb_build_object('n', 1, 'os', v_os, 'atraso_dito', 0, 'sem_data', false, 'atraso_du', 0, 'numero', v_e ->> 'numero',
                   'texto', format('Sigo: %s termina %s em vez de %s', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                                   public._dia_curto((v_e ->> 'fim_antes')::date)),
                   'efeito', jsonb_build_object('restricoes', jsonb_build_object('aceitar_atraso', jsonb_build_array(v_os))),
                   'espera', jsonb_build_object(v_os::text, v_fim_x));
      end if;
      if jsonb_array_length(v_opc) = 0 then
        -- sem saída nenhuma: não é pergunta (fica fora, sem encaixe); a próxima volta refaz sem ela na espera
        v_sem_q := v_sem_q || v_x;
        continue;
      end if;
      if jsonb_array_length(v_opc) = 1 then
        v_opc := v_opc || jsonb_build_object('n', 2, 'os', v_os, 'atraso_dito', null, 'sem_data', false, 'atraso_du', null,
                   'numero', v_e ->> 'numero',
                   'texto', format('Deixo o %s fora do plano por enquanto', public._agenda_nome_curto(v_e ->> 'cliente_curto')),
                   'efeito', jsonb_build_object('restricoes', jsonb_build_object('tirar', jsonb_build_array(v_os))),
                   'espera', '{}'::jsonb);
      end if;
      -- a recomendação: o menor atraso sobre datas ditas; no empate, quem não tem data dita, o menor atraso, o número
      if v_tipo = 'nao_cabe' then
        select (o ->> 'n')::int into v_rec from jsonb_array_elements(v_opc) o
         where o ->> 'atraso_dito' is not null
         order by (o ->> 'atraso_dito')::int, (o ->> 'sem_data')::boolean desc, (o ->> 'atraso_du')::int, o ->> 'numero' collate "C"
         limit 1;
        v_rec := coalesce(v_rec, 1);
        v_q := v_opc -> (v_rec - 1);
        v_rec_txt := case when (v_q ->> 'sem_data')::boolean
                            then format('o %s não tem data dita pelo cliente', public._agenda_nome_curto((select cl.name from public.service_orders so
                                          join public.clients cl on cl.id = so.client_id where so.id = (v_q ->> 'os')::uuid)))
                          when v_rec = 1 then format('é o menor atraso (%s)', public._agenda_plural((v_q ->> 'atraso_du')::int, 'dia útil', 'dias úteis'))
                          else 'é o menor atraso sobre o que o cliente pediu' end;
        v_txt := format('Não cabe tudo até %s. Qual aceita atrasar? %s. Recomendo a %s: %s.',
                        public._dia_curto((v_e ->> 'precisa')::date),
                        (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int) from jsonb_array_elements(v_opc) o),
                        v_rec, v_rec_txt);
      else
        v_rec := 1;
        v_rec_txt := case v_tipo
          when 'atraso_longo' then 'Recomendo seguir e você ligar para o cliente hoje'
          when 'segundo_atraso' then 'É o 2º atraso desta OS: recomendo seguir e você ligar para o cliente hoje'
          when 'remarcar_confirmado' then 'O cliente tinha confirmado o dia: recomendo seguir e você ligar para ele hoje'
          else 'Você tinha fixado o dia, que não dá mais: recomendo seguir no novo dia' end;
        -- FASE 7: (7a P3) a recomendação das críticas da zona travada do gestor (P8: o dia que a equipe já recebeu na ficha e o
        -- que o cliente já ouviu); inertes até lá (_agenda_criticidade ainda não dá esses tipos)
        if v_tipo = 'dia_avisado' then
          v_rec_txt := 'A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia';
        elsif v_tipo = 'dia_prometido' then
          v_rec_txt := 'É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje';
        end if;
        -- FASE 7: fim
        v_txt := format('%s só dá para terminar em %s, %s depois do que estava no plano. 1) %s; 2) %s. %s.',
                        public._agenda_rotulo_da_os(v_os), public._dia_curto(v_fim_x),
                        public._agenda_plural(v_fim_x - (v_e ->> 'fim_antes')::date, 'dia', 'dias'),
                        v_opc -> 0 ->> 'texto', v_opc -> 1 ->> 'texto', v_rec_txt);
      end if;
      v_chave := format('%s:%s:%s', v_tipo, v_os, v0);
      v_perg := v_perg || jsonb_build_object(
        'tipo', v_tipo, 'chave', v_chave, 'service_order_id', v_os,
        'os_ids', (select jsonb_agg(v_ent -> j::text -> 'os' order by j) from unnest(array[v_x] || coalesce(
                     array(select (k)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) k), '{}'::int[])) j),
        'texto', left(v_txt, 600), 'opcoes', v_opc, 'recomendacao', v_rec, 'recomendacao_texto', left(v_rec_txt, 300),
        'perda_em', (select min(v_ini + ((b ->> 'ini')::int + 1) / 2 - 1) from jsonb_array_elements(v_base -> 'colocadas') b
                      where (b ->> 'i')::int = any (array[v_x] || coalesce(
                        array(select (k)::int from jsonb_array_elements_text(coalesce(v_cands -> v_x::text, '[]'::jsonb)) k), '{}'::int[]))),
        'x', v_x);
    end loop;
    -- quem ficou sem saída sai da espera e a conta é refeita
    continue when cardinality(v_sem_q) <> v_n;
    -- as que não fazem X caber não ficam esperando a decisão: a conta é refeita só com as que deram opção (uma vez)
    if v_usadas is null and exists (
         select 1 from jsonb_each(v_cands) t(k, v), jsonb_array_elements_text(t.v) j
          where not exists (select 1 from jsonb_array_elements(v_perg) q, jsonb_array_elements(q -> 'opcoes') o
                             where (q ->> 'x')::int = t.k::int and (o ->> 'c')::int = j::int)) then
      select coalesce(jsonb_object_agg(q ->> 'x', coalesce((select jsonb_agg((o ->> 'c')::int) from jsonb_array_elements(q -> 'opcoes') o
                                                             where o ? 'c'), '[]'::jsonb)), '{}'::jsonb)
        into v_usadas from jsonb_array_elements(v_perg) q;
      continue;
    end if;
    exit;
  end loop;
  if cardinality(v_h) = 0 then
    v_xnc := '{}';
    v_xoc := '{}';
    v_perg := '[]'::jsonb;
    v_rf := v_r0;
    v_ctxf := public._agenda_ctx_com(v_ctx, v_rf -> 'colocadas');
    v_base := jsonb_build_object('colocadas', '[]'::jsonb);
  end if;

  -- ── 6. Os itens: o que sai, o que entra, o que espera a decisão ──
  -- (a) o que sai (a violação, o resto do meio-dia, o pedido do dono)
  v_itens := v_itens || coalesce((
    select jsonb_agg(jsonb_build_object(
             'op', 'cancelar', 'os', g.os, 'numero', g.numero, 'cliente_curto', g.cliente_curto, 'tipo', g.tipo,
             'motivo', g.motivo, 'violada', g.violada, 'alocacoes', g.alocs, 'de', g.de, 'ate', g.ate,
             'critica', null, 'decisao', v_decisao, 'aplicado', false,
             'texto', format('%s: sai %s — %s.', public._agenda_rotulo_da_os(g.os), public._agenda_dias_texto(g.dias),
                             case g.motivo when 'pessoa' then 'quem ia não está mais livre' when 'material' then 'o material não chega a tempo'
                                           when 'cliente' then 'o cliente ou o bem não está liberado' when 'os_saiu' then 'a OS saiu da carteira'
                                           when 'condicao_vencida' then 'a condição da reserva venceu' when 'dono' then 'você pediu outro dia'
                                           when 'espera' then coalesce('você pôs em espera até ' || public._dia_curto(
                                             (select pl.congelada_ate from public.os_planejamento pl where pl.service_order_id = g.os)),
                                             'você pôs em espera')
                                           else 'replanejado junto' end))
             order by g.numero, g.os, g.motivo)
      from (select (c ->> 'os')::uuid as os, min(v_info -> (c ->> 'os') -> 'pront' ->> 'numero') as numero,
                   min(v_info -> (c ->> 'os') -> 'pront' ->> 'cliente_curto') as cliente_curto,
                   case when bool_and(c ->> 'tipo' = 'reserva') then 'reserva' else min(c ->> 'tipo') end as tipo,
                   c ->> 'motivo' as motivo, bool_or((c ->> 'violada')::boolean) as violada,
                   jsonb_agg(jsonb_build_object('alocacao_id', c -> 'alocacao_id', 'payee_id', c -> 'payee_id',
                               'nome', (select public._agenda_nome_curto(py.name) from public.payees py where py.id = (c ->> 'payee_id')::uuid),
                               'dia', c -> 'dia', 'turno', c -> 'turno', 'presenca', c -> 'presenca', 'estado', c -> 'estado',
                               'fixado_por', c -> 'fixado_por')
                             order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'payee_id') as alocs,
                   array_agg((c ->> 'dia')::date) as dias, min((c ->> 'dia')::date) as de, max((c ->> 'dia')::date) as ate
              from jsonb_array_elements(v_canc) c
             group by (c ->> 'os')::uuid, c ->> 'motivo') g), '[]'::jsonb);
  -- FASE 7c: (7c P2, §5.2 4, §6.8) o que sai pela violação habilidade (a do P3: a equipe do meio-dia não tem quem o serviço pede) diz
  -- o porquê, no lugar do "replanejado junto"
  if exists (select 1 from jsonb_array_elements(v_itens) i where i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'habilidade') then
    select coalesce(jsonb_agg(case when i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'habilidade'
                                   then i || jsonb_build_object('texto', format('%s: sai %s — a equipe do dia não tinha quem o serviço pede.',
                                          public._agenda_rotulo_da_os((i ->> 'os')::uuid),
                                          public._agenda_dias_texto(array(select (a ->> 'dia')::date from jsonb_array_elements(i -> 'alocacoes') a))))
                                   else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
  end if;
  -- FASE 7c: fim
  -- (b) a reserva que virou compromisso nesta proposta
  v_itens := v_itens || coalesce((
    select jsonb_agg(jsonb_build_object(
             'op', 'cancelar', 'os', g.os, 'numero', v_ent -> g.i ->> 'numero', 'cliente_curto', v_ent -> g.i ->> 'cliente_curto',
             'tipo', 'reserva', 'motivo', 'promovida', 'violada', false, 'alocacoes', g.alocs, 'de', g.de, 'ate', g.ate,
             'critica', null, 'decisao', v_decisao, 'aplicado', false,
             'texto', format('%s: a reserva vira compromisso.', public._agenda_rotulo_da_os(g.os)))
             order by v_ent -> g.i ->> 'numero')
      from (select b ->> 'i' as i, (v_ent -> (b ->> 'i') ->> 'os')::uuid as os,
                   (select jsonb_agg(jsonb_build_object('alocacao_id', a.id, 'payee_id', a.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                     'dia', a.dia, 'turno', a.turno, 'presenca', a.presenca, 'estado', a.estado, 'fixado_por', a.fixado_por)
                                     order by a.dia, a.turno = 'tarde', a.payee_id)
                      from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
                     where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid and a.estado in ('publicada', 'fixada')
                       and a.tipo = 'reserva' and a.reserva_de in ('teto', 'condicionada') and a.dia >= p_hoje
                       and not (a.id = any (v_ign))) as alocs,
                   (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid
                       and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje) as de,
                   (select max(a.dia) from public.agenda_alocacoes a where a.service_order_id = (v_ent -> (b ->> 'i') ->> 'os')::uuid
                       and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje) as ate
              from jsonb_array_elements(v_rf -> 'colocadas') b
             where b ->> 'tipo' = 'compromisso' and coalesce((b ->> 'na_janela')::boolean, true)
               and (v_ent -> (b ->> 'i') ->> 'tem_reserva')::boolean and not ((b ->> 'i')::int = any (v_h))) g
     where g.alocs is not null), '[]'::jsonb);
  -- (c) o que entra: publicável sem esperar, ou (d) esperando a decisão (a X que não cabe sai da proposta)
  for v_b in
    select b || jsonb_build_object('espera', (b ->> 'i')::int = any (v_h) and b ->> 'tipo' = 'compromisso')
      from jsonb_array_elements(v_rf -> 'colocadas') b
     where coalesce((b ->> 'na_janela')::boolean, true)
       and not ((b ->> 'i')::int = any (v_xnc) and b ->> 'tipo' = 'compromisso')
  loop
    v_e := v_ent -> (v_b ->> 'i');
    v_os := (v_e ->> 'os')::uuid;
    v_ini_x := v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1;
    v_fim_x := v_ini + ((v_b ->> 'fim')::int + 1) / 2 - 1;
    v_fim_dep := greatest(v_fim_x, (v_e ->> 'kept_max')::date);
    v_canc_os := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_canc) c where (c ->> 'os')::uuid = v_os);
    v_ini_antes := (select min((c ->> 'dia')::date) from jsonb_array_elements(v_canc) c
                     where (c ->> 'os')::uuid = v_os and c ->> 'tipo' <> 'reserva');
    v_tipo := case when v_b ->> 'tipo' = 'reserva' or v_e ? 'fixar_de' then null
                   else public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_dep, v_ini_x, p_hoje,
                                                   v_canc_os, '{}') end;
    -- FASE 7: (7a P8) a zona travada, como no encaixe acima (o que espera a decisão de outra OS segue a de antes)
    if v_b ->> 'tipo' <> 'reserva' and not v_e ? 'fixar_de' and not coalesce((v_b ->> 'espera')::boolean, false)
       and public._agenda_gestor_regra('zona_travada') then
      v_f7_fora := public._agenda_zona_fora(v_canc, v_os, public._agenda_alocs_do_bloco(v_ctx, v_b));
      v_tipo := public._agenda_criticidade(v_os, (v_e ->> 'fim_antes')::date, v_ini_antes, v_fim_dep, v_ini_x, p_hoje,
                                           v_canc_os, v_f7_fora);
    end if;
    -- FASE 7: fim
    -- quem espera a decisão de uma X: o tipo dela e a chave da pergunta
    v_chave := null;
    if (v_b ->> 'espera')::boolean then
      select q ->> 'chave', coalesce(v_tipo, q ->> 'tipo') into v_chave, v_tipo from jsonb_array_elements(v_perg) q
       where q -> 'os_ids' @> jsonb_build_array(v_os) order by q ->> 'chave' limit 1;
    elsif v_tipo is not null and v_decisao is null and not (v_os = any (v_aceitar)) then
      -- crítico sem pergunta (não deveria acontecer: a pergunta foi feita acima); fica esperando
      v_chave := format('%s:%s:%s', v_tipo, v_os, v0);
    end if;
    -- O pedido do dono num dia antes de o material estar garantido: fica (a decisão é dele), com o aviso na frase.
    v_aviso := case when v_e ? 'fixar_de' and v_b ->> 'tipo' <> 'reserva'
                    then public._agenda_aviso_do_material(v_info -> v_os::text -> 'pront', v_e ->> 'condicao_tipo', v_e ->> 'texto', v_ini_x) end;
    -- FASE 7c: (7c P2, §5.2 3, §3.1-3) com modo_habilidade ligado, onde o dono disse quem vai (o pedido com pessoa, a equipe dita), a
    -- palavra dele vale e o item ganha o aviso, ao lado do de material ("— mas João iria sozinho, e o último dia pede quem instala
    -- sozinho com 220 V ou banco de bateria")
    if cf.modo_habilidade = 'ligado' and v_b ->> 'tipo' <> 'reserva'
       and (v_e ? 'fixar_de' or coalesce((v_info -> v_os::text -> 'meios' ->> 'equipe_dita')::boolean, false)) then
      v_aviso := nullif(concat_ws('; ', v_aviso, public._agenda_aviso_da_habilidade(v_os, public._agenda_alocs_do_bloco(v_ctx, v_b), p_hoje)), '');
    end if;
    -- FASE 7c: fim
    v_txt := case
      when v_b ->> 'tipo' = 'reserva' then
        format('%s: %s, %s%s.',
               case v_b ->> 'reserva_de' when 'patio' then 'Reserva no pátio' when 'teto' then 'Reserva (acima da carga)' else 'Reserva' end
                 || ' ' || public._agenda_rotulo_da_os(v_os),
               public._agenda_faixa_texto(v_ini_x, case when (v_b ->> 'ini')::int % 2 = 1 then 'manha' else 'tarde' end,
                                          v_fim_x, case when (v_b ->> 'fim')::int % 2 = 1 then 'manha' else 'tarde' end),
               public._agenda_pessoas_texto(public._agenda_alocs_do_bloco(v_ctx, v_b), v_dono), '')
      else
        format('%s%s: %s, %s%s.', public._agenda_rotulo_da_os(v_os),
               case v_e ->> 'tipo_os' when 'diagnostico' then ', diagnóstico' when 'comissionamento' then ', comissionamento' else '' end,
               public._agenda_dias_texto(array(select distinct (a ->> 'dia')::date
                                                 from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a)),
               public._agenda_pessoas_texto(public._agenda_alocs_do_bloco(v_ctx, v_b), v_dono),
               coalesce(' — mas ' || v_aviso, '')) end;
    -- FASE 7: (7a P3, D7-1) o compromisso marcado pela estimativa do orçamento (a fonte 'orcamento' de agenda_meios_da_os, que
    -- só existe com a regra estimativa) diz isso no fim: "… com Roberto e João (estimativa minha: 6 dias)."
    if v_e ->> 'fonte' = 'orcamento' and v_b ->> 'tipo' <> 'reserva' and right(v_txt, 1) = '.' then
      v_txt := left(v_txt, -1) || format(' (estimativa minha: %s).', public._agenda_dias((v_e ->> 'dias')::numeric));
    end if;
    -- FASE 7: fim
    -- FASE 7b: (7b P4, §6.3, R4.3(a)(3)) ligado: o compromisso com o sábado diz qual e por quê (" — com sáb 14/11 de manhã (Rafael
    -- se ofereceu), para cumprir o prazo de qua 18/11."); o bloco de 1 pessoa da dupla inferida diz em que meios-dias a tarefa pede
    -- 2 e o que fazer (" Nos 2 primeiros meios-dias (qua 04/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex
    -- está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem qua 04/11)."). Em teste, nada aqui (a linha "Em teste" abaixo).
    if v_b ? 'sabado' and right(v_txt, 1) = '.' then
      select array_agg(distinct (a ->> 'dia')::date order by (a ->> 'dia')::date) into v_7b_dias
        from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) a
       where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno';
      v_7b_nomes := array(select y.x from (select a ->> 'nome' as x, min(o) as o
                                             from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_b)) with ordinality t(a, o)
                                            where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' group by 1) y
                           order by y.o);
      v_txt := left(v_txt, -1) || format(' — com %s de manhã (%s %s)%s.', public._agenda_dias_texto(v_7b_dias),
                 public._agenda_lista(v_7b_nomes), case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end,
                 case when v_e ? 'prazo' then ', para cumprir o prazo de ' || public._dia_curto((v_e ->> 'prazo')::date) else '' end);
    end if;
    if v_b ? 'dupla_falta' and cf.modo_dupla = 'ligado' and jsonb_array_length(v_b -> 'dupla_falta') > 0 then
      if v_7b_tec is null then
        v_7b_tec := public._agenda_tecnicos_da_grade(p_hoje);
      end if;
      -- os meios-dias de cada parte: "qua 04/11, manhã e tarde", "qua 04/11 de manhã"
      select public._agenda_lista(array(
               select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                     when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                 from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                         from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' in ('inicio', 'todos')) z
                group by z.d order by z.d)),
             public._agenda_lista(array(
               select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ', manhã e tarde'
                                                     when bool_or(z.t = 'manha') then ' de manhã' else ' à tarde' end
                 from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                         from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' = 'fim') z
                group by z.d order by z.d))
        into v_7b_x, v_7b_y;
      v_7b_n := (select count(*)::int from jsonb_array_elements(v_b -> 'dupla_falta') f where f ->> 'onde' = 'inicio');
      v_7b_z := case
        when coalesce((v_e ->> 'dupla_todos')::boolean, false)
          then format('O serviço todo pede 2 pessoas (%s) e %s: vai com 1 pessoa; se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      coalesce(v_e ->> 'dupla_rot_todos', 'o orçamento previu 2 técnicos'),
                      case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre' else public._agenda_tecnicos_frase(v_7b_tec) end,
                      public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1))
        when v_7b_x <> '' and v_7b_y <> ''
          then format('%s (%s) %s e %s (%s) %s pedem 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                      case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end, v_7b_x,
                      v_e ->> 'dupla_rot_ini',
                      case when jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n = 1 then 'no último meio-dia'
                           else format('nos %s últimos meios-dias', jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n) end, v_7b_y,
                      v_e ->> 'dupla_rot_fim',
                      case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_7b_tec) end,
                      public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1))
        else format('%s (%s) %s pede 2 pessoas e %s: se chamar um ajudante, me diga (ex.: Mateus vem %s).',
                    case when v_7b_x <> '' then case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end
                         when jsonb_array_length(v_b -> 'dupla_falta') = 1 then 'No último meio-dia'
                         else format('Nos %s últimos meios-dias', jsonb_array_length(v_b -> 'dupla_falta')) end,
                    case when v_7b_x <> '' then v_7b_x else v_7b_y end,
                    case when v_7b_x <> '' then v_e ->> 'dupla_rot_ini' else v_e ->> 'dupla_rot_fim' end,
                    case when cardinality(v_7b_tec) >= 2 then 'ninguém mais está livre nesses meios-dias' else public._agenda_tecnicos_frase(v_7b_tec) end,
                    public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1)) end;
      -- (correção da revisão da 7b, achado 23) o exemplo diz todos os dias em que falta a 2ª pessoa, não só o 1º ("ex.: Mateus vem
      -- qua 18 e qui 19/11"): quem seguisse o exemplo ao pé da letra deixava os outros meios-dias sem a 2ª pessoa
      v_7bc_dias := array(select distinct v_ini + ((f ->> 'h')::int + 1) / 2 - 1 from jsonb_array_elements(v_b -> 'dupla_falta') f order by 1);
      if cardinality(v_7bc_dias) > 1 then
        v_7b_z := replace(v_7b_z, format('(ex.: Mateus vem %s).', public._dia_curto(v_ini + ((v_b -> 'dupla_falta' -> 0 ->> 'h')::int + 1) / 2 - 1)),
                          format('(ex.: Mateus vem %s).', regexp_replace(public._agenda_dias_texto(v_7bc_dias), ' \([^()]*\)$', '')));
      end if;
      -- (correção da revisão da 7b: fim)
      -- o texto da ação (agenda_acoes.texto, até 400) junta os itens da mesma OS: com a frase da dupla, o item fica em até 320 — sem
      -- caber a frase inteira, a curta (sem os dias e sem quem está na equipe)
      if char_length(v_txt) + 1 + char_length(v_7b_z) > 320 then
        v_7b_n2 := jsonb_array_length(v_b -> 'dupla_falta') - v_7b_n;
        v_7b_z := case
          when coalesce((v_e ->> 'dupla_todos')::boolean, false) then 'O serviço todo pede 2 pessoas: se chamar um ajudante, me diga os dias dele.'
          when v_7b_x <> '' and v_7b_y <> ''
            then format('%s e %s pedem 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                        case when v_7b_n = 1 then 'O primeiro meio-dia' else format('Os %s primeiros meios-dias', v_7b_n) end,
                        case when v_7b_n2 = 1 then 'o último' else format('os %s últimos', v_7b_n2) end)
          when v_7b_x <> ''
            then format('%s %s pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                        case when v_7b_n = 1 then 'No primeiro meio-dia' else format('Nos %s primeiros meios-dias', v_7b_n) end, v_e ->> 'dupla_rot_ini')
          else format('%s %s pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
                      case when v_7b_n2 = 1 then 'No último meio-dia' else format('Nos %s últimos meios-dias', v_7b_n2) end, v_e ->> 'dupla_rot_fim') end;
      end if;
      v_txt := public._agenda_corta(v_txt || ' ' || v_7b_z, 320);
    end if;
    -- FASE 7b: fim
    v_itens := v_itens || jsonb_build_object(
      'op', 'criar', 'os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
      'tipo', case when v_b ->> 'tipo' = 'reserva' then 'reserva' else v_e ->> 'tipo_os' end,
      'reserva_de', v_b ->> 'reserva_de', 'alocacoes', public._agenda_alocs_do_bloco(v_ctx, v_b),
      'de', v_ini_x, 'ate', v_fim_x, 'fim_antes', v_e ->> 'fim_antes', 'fim_depois', v_fim_dep,
      'atraso_du', case when v_b ->> 'tipo' <> 'reserva' and v_e ->> 'fim_antes' is not null and v_fim_dep > (v_e ->> 'fim_antes')::date
                        then public.agenda_du_entre((v_e ->> 'fim_antes')::date, v_fim_dep) end,
      'condicao_tipo', case when v_b ->> 'reserva_de' = 'condicionada' then v_e ->> 'condicao_tipo' end,
      'critica', v_tipo, 'pergunta_chave', v_chave, 'decisao', v_decisao, 'espera', (v_b ->> 'espera')::boolean,
      'interrupcoes', (v_b ->> 'int')::int, 'meios_do_dono', (v_b ->> 'md')::int, 'fonte', v_e ->> 'fonte', 'dias', v_e -> 'dias',
      'evento_real', (v_e ->> 'evento_real')::boolean, 'fixar_dono', v_e ? 'fixar_de', 'aviso_material', v_aviso,
      'abre', (v_e ->> 'abre')::boolean and v_b ->> 'tipo' <> 'reserva', 'fecha', (v_e ->> 'fecha')::boolean and v_b ->> 'tipo' <> 'reserva',
      'motivos', to_jsonb(array_remove(array[
         case when v_e ->> 'classe' = '1' and not v_e ? 'fixar_de' then 'em andamento ou fixada' end,
         case when v_e ? 'fixar_de' then 'você pediu' end,
         case when (v_e ->> 'evento_real')::boolean then 'replanejado por um imprevisto de hoje ou amanhã' end,
         case when v_b ->> 'tipo' <> 'reserva' then v_e ->> 'texto' end,
         case when v_b ->> 'reserva_de' = 'teto' then 'não coube na carga de ' || public._agenda_num(cf.carga_max * 100, 0) || '%' end,
         case when v_b ->> 'reserva_de' = 'condicionada' then v_e ->> 'texto' end,
         case when v_b ->> 'reserva_de' = 'patio' then 'adiantar no pátio enquanto o bem está fora' end], null)),
      'texto', v_txt, 'aplicado', false);
    -- FASE 7c: (7c P2, §5.2 3, §6.8) os motivos do compromisso, nesta ordem: o que a OS pede e quem vai (com modo_habilidade ligado e
    -- algum meio-dia do bloco pedindo: "pede quem instala sozinho com 220 V ou banco de bateria, no último dia: vai Roberto" — quem
    -- vai é quem tem o que o meio-dia pede, ou você no turno), a troca avisada do responsável ("troquei o responsável: Roberto não
    -- está livre até qua 11/11; segui com João") e o responsável que saiu da equipe ("Roberto, o responsável, não está na equipe
    -- agora"). A troca e o responsável fora só existem com modo_lider ou modo_habilidade ligado.
    v_7c_mot := '{}';
    if v_b ->> 'tipo' <> 'reserva' then
      if cf.modo_habilidade = 'ligado' and v_e ->> 'exig_texto' is not null then
        v_7c_txt := public._agenda_lista(array(
          select y.nome
            from (select case when t.p = (v_ctx ->> 'dono')::int then 'você' else v_ctx -> 'nomes' ->> (t.p - 1) end as nome, min(t.h) as h
                    from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'), public._agenda_ints(v_b -> 'pr'),
                                public._agenda_ints(v_b -> 'ex')) t(p, h, pr, ex)
                   where t.pr = 0 and coalesce(t.ex, 0) <> 0
                     and (t.p = (v_ctx ->> 'dono')::int
                          or (t.ex & 9 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4))::int >= cf.habilidade_nivel_energizado)
                          or (t.ex & 2 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 1))::int >= cf.habilidade_nivel_comissionar)
                          or (t.ex & 8 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 1))::int >= cf.habilidade_nivel_diagnostico)
                          or (t.ex & 4 <> 0 and (v_ctx -> 'hab' ->> ((t.p - 1) * 4 + 2))::int >= cf.habilidade_nivel_altura))
                   group by 1) y
           order by y.h, y.nome));
        if coalesce(v_7c_txt, '') <> '' then
          v_7c_mot := v_7c_mot || format('pede %s: vai %s', v_e ->> 'exig_texto', v_7c_txt);
        end if;
      end if;
      if coalesce((v_b ->> 'lt')::boolean, false) then
        -- o 1º dia, do início do bloco em diante, em que o responsável está livre de manhã ou de tarde na grade de antes do encaixe
        v_7c_lp := coalesce((v_e ->> 'lid')::int, 0);
        v_7c_d := null;
        if v_7c_lp > 0 then
          select min(g) into v_7c_d from generate_series(((v_b ->> 'ini')::int + 1) / 2, (v_ctx ->> 'nd')::int) g
           where ((v_ctx -> 'cap' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 2))::int = 1
                  and (v_ctx -> 'ocup' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 2))::int in (0, -(v_b ->> 'i')::int))
              or ((v_ctx -> 'cap' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 1))::int = 1
                  and (v_ctx -> 'ocup' ->> ((v_7c_lp - 1) * (v_ctx ->> 'nh')::int + 2 * g - 1))::int in (0, -(v_b ->> 'i')::int));
        end if;
        v_7c_mot := v_7c_mot || format('troquei o responsável: %s não está livre %s; segui com %s', v_e ->> 'lid_nome',
                                       case when v_7c_d is null then format('nas próximas %s semanas', cf.horizonte_semanas)
                                            else 'até ' || public._dia_curto(v_ini + v_7c_d - 1) end,
                                       coalesce(nullif(public._agenda_lista(array(
                                         select y.nome from (select v_ctx -> 'nomes' ->> (t.p - 1) as nome, min(t.h) as h
                                                               from unnest(public._agenda_ints(v_b -> 'p'), public._agenda_ints(v_b -> 'h'),
                                                                           public._agenda_ints(v_b -> 'pr')) t(p, h, pr)
                                                              where t.pr = 0 and t.p <> (v_ctx ->> 'dono')::int group by 1) y
                                          order by y.h, y.nome)), ''), 'você'));
      end if;
      if coalesce((v_e ->> 'lid_fora')::boolean, false) then
        v_7c_mot := v_7c_mot || format('%s, o responsável, não está na equipe agora', v_e ->> 'lid_nome');
      end if;
    end if;
    if cardinality(v_7c_mot) > 0 then
      v_itens := jsonb_set(v_itens, '{-1,motivos}', coalesce(v_itens -> -1 -> 'motivos', '[]'::jsonb) || to_jsonb(v_7c_mot));
    end if;
    -- FASE 7c: fim
    -- FASE 7b: (7b P4, §6.4) o item leva a dupla da OS (o texto do cartão e do foco), os meios-dias que pediam 2 e não têm a 2ª pessoa
    -- (dupla_falta [{dia, turno, onde}]) e o sábado usado; só com os modos da 7b
    if v_e ? 'dk' or v_b ? 'sabado' then
      v_itens := jsonb_set(v_itens, '{-1}', (v_itens -> -1) || jsonb_strip_nulls(jsonb_build_object(
        'dupla', v_e ->> 'dupla_texto', 'dupla_fonte', v_e ->> 'dupla_fonte',
        'dupla_falta', (select jsonb_agg(jsonb_build_object('dia', v_ini + ((f ->> 'h')::int + 1) / 2 - 1,
                                                           'turno', case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end,
                                                           'onde', f ->> 'onde') order by (f ->> 'h')::int)
                          from jsonb_array_elements(v_b -> 'dupla_falta') f),
        'sabado', case when v_b ? 'sabado' then true end)));
    end if;
    -- FASE 7b: fim
    -- CORREÇÃO FASE 6: (C1) item 14: a reserva por teto da OS que precisa do dono (abre, fecha ou o turno dele), com a
    -- capacidade do dono em uso abaixo da carga de todos (_agenda_carga_da_pessoa), diz a parte da semana DELE: "não coube na
    -- sua parte da semana (56%)", e não "na carga de 80%". Sem nada em uso, o item é o de antes, byte a byte.
    if v_b ->> 'reserva_de' = 'teto'
       and (coalesce((v_e ->> 'abre')::boolean, false) or coalesce((v_e ->> 'fecha')::boolean, false)
            or coalesce((v_e ->> 'dt_m')::boolean, false) or coalesce((v_e ->> 'dt_t')::boolean, false))
       and public._agenda_carga_da_pessoa(v_dono) < cf.carga_max then
      v_itens := jsonb_set(v_itens, '{-1,motivos}',
                   (select coalesce(jsonb_agg(case when m #>> '{}' = 'não coube na carga de ' || public._agenda_num(cf.carga_max * 100, 0) || '%'
                                                   then to_jsonb('não coube na sua parte da semana ('
                                                                 || public._agenda_num(public._agenda_carga_da_pessoa(v_dono) * 100, 0) || '%)')
                                                   else m end order by o), '[]'::jsonb)
                      from jsonb_array_elements(v_itens -> -1 -> 'motivos') with ordinality t(m, o)));
    end if;
    -- CORREÇÃO FASE 6: fim
  end loop;

  -- A condição e a data-limite das reservas condicionadas (do 1º dia de cada uma: o "compre até" daquele início).
  select coalesce(jsonb_agg(case when i ->> 'reserva_de' = 'condicionada' then
             i || x.c || jsonb_build_object('texto', rtrim(i ->> 'texto', '.') || ' — ' || (x.c ->> 'condicao') || '.')
           else i end order by k), '[]'::jsonb)
    into v_itens
    from jsonb_array_elements(v_itens) with ordinality t(i, k)
    cross join lateral (select case when i ->> 'reserva_de' = 'condicionada'
                                    then public._agenda_condicao_da_reserva((i ->> 'os')::uuid, i ->> 'condicao_tipo', (i ->> 'de')::date,
                                                                            v_info -> (i ->> 'os') -> 'pront', p_hoje) end as c) x;

  -- FASE 7c: (7c P2, §5.2 7) o "por que não cabe" lê os modos e os níveis da 7c no contexto (o que cada pessoa faz já está nele)
  v_ctx := v_ctx || jsonb_build_object('hab_modo', (cf.modo_habilidade = 'ligado')::int, 'n', v_par -> 'n',
                                       'fcobre', cf.habilidade_fechamento_cobre);
  -- FASE 7c: fim
  -- ── 7. O que fica de fora, com quem trava ──
  for v_e in select e from jsonb_array_elements(v_fila) e order by (e ->> 'ordem')::int loop
    v_os := (v_e ->> 'os')::uuid;
    continue when exists (select 1 from jsonb_array_elements(v_itens) i where (i ->> 'os')::uuid = v_os and i ->> 'op' = 'criar');
    v_x := (v_e ->> 'i')::int;
    v_txt := null;
    v_chave := null;
    if v_x = any (v_xnc) and exists (select 1 from jsonb_array_elements(v_perg) q where (q ->> 'x')::int = v_x) then
      select q ->> 'chave' into v_chave from jsonb_array_elements(v_perg) q where (q ->> 'x')::int = v_x;
      v_txt := format('%s: não cabe até %s — preciso de você.', public._agenda_rotulo_da_os(v_os), public._dia_curto((v_e ->> 'precisa')::date));
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', 'nao_cabe', 'texto', v_txt, 'pergunta_chave', v_chave);
      continue;
    end if;
    if v_x = any (v_sem_q) then
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                 'motivo', 'sem_encaixe',
                 'texto', format('%s: sem encaixe com a equipe de hoje (nem atrasando outra OS).', public._agenda_rotulo_da_os(v_os)));
      continue;
    end if;
    if (v_e ->> 'classe')::int = 4 then
      v_txt := format('%s: %s.', public._agenda_rotulo_da_os(v_os), rtrim(v_e ->> 'texto', '.'));
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', v_e ->> 'motivo', 'texto', v_txt);
      continue;
    end if;
    continue when coalesce((v_e ->> 'passos')::int, 0) <= 0;
    -- FASE 7b: (7b P4, R4.3(c)) a dupla dita que só saiu da espera da classe 4 por quem vem sob demanda (dupla_sd) e não achou bloco:
    -- vai ao "fora" com o motivo dupla (o da classe 4: o aviso, o foco e o cartão dizem "falta a 2ª pessoa"), com as datas de quem
    -- vem — nunca o "sem lugar" calado.
    if coalesce((v_e ->> 'dupla_sd')::boolean, false)
       and exists (select 1 from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x and f ->> 'motivo' in ('sem_encaixe', 'sem_reserva')) then
      select public._agenda_lista(array_agg(format('%s só vem %s (%s)', x.nome, public._agenda_dias_texto(x.dias),
                                                  public._agenda_plural(x.n, 'meio-dia', 'meios-dias')) order by x.nome)),
             count(*)::int
        into v_7b_x, v_7b_n
        from (select k.pessoa as nome, k.payee_id, array_agg(distinct k.dia order by k.dia) as dias, count(*)::int as n
                from public.agenda_capacidade(p_hoje, p_hoje + 7 * cf.horizonte_semanas - 1, p_hoje) k
               where not k.eh_dono and k.situacao = 'livre' and public._agenda_e_sob_demanda(k.payee_id, p_hoje)
               group by k.pessoa, k.payee_id) x;
      v_txt := format('%s: precisa de %s pessoas em %s e %s: me diga mais dias %s ou chame outro ajudante.',
                      public._agenda_rotulo_da_os(v_os), v_e ->> 'dupla_n',
                      public._agenda_plural((v_e ->> 'dupla_meios_n')::int, 'meio-dia', 'meios-dias'),
                      coalesce(nullif(v_7b_x, ''), 'quem vem sob demanda não cobre'), case when v_7b_n > 1 then 'deles' else 'dele' end);
      -- (correção da revisão da 7b, achado 22) quando os dias de quem vem sob demanda são todos antes de a OS ficar pronta, o
      -- porquê é a data, não a falta de dias ("… e Mateus só vem seg 09 e qui 12/11 (4 meios-dias), antes de o serviço ficar pronto (qua
      -- 18/11): me diga dias dele a partir de qua 18/11 ou chame outro ajudante.")
      v_7bc_est := (public.os_prontidao(v_os, p_hoje) ->> 'est')::date;
      select max(k.dia) into v_7bc_max
        from public.agenda_capacidade(p_hoje, p_hoje + 7 * cf.horizonte_semanas - 1, p_hoje) k
       where not k.eh_dono and k.situacao = 'livre' and public._agenda_e_sob_demanda(k.payee_id, p_hoje);
      if v_7bc_est is not null and v_7bc_max is not null and v_7bc_max < v_7bc_est and nullif(v_7b_x, '') is not null then
        v_txt := format('%s: precisa de %s pessoas em %s e %s, antes de o serviço ficar pronto (%s): me diga dias %s a partir de %s ou chame outro ajudante.',
                        public._agenda_rotulo_da_os(v_os), v_e ->> 'dupla_n',
                        public._agenda_plural((v_e ->> 'dupla_meios_n')::int, 'meio-dia', 'meios-dias'), v_7b_x,
                        public._dia_curto(v_7bc_est), case when v_7b_n > 1 then 'deles' else 'dele' end, public._dia_curto(v_7bc_est));
      end if;
      -- (correção da revisão da 7b: fim)
      v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                             'motivo', 'dupla', 'texto', v_txt);
      continue;
    end if;
    -- FASE 7b: fim
    select f ->> 'motivo' into v_tipo from jsonb_array_elements(v_rf -> 'fora') f where (f ->> 'i')::int = v_x limit 1;
    if v_tipo is null then
      select b into v_b from jsonb_array_elements(v_rf -> 'colocadas') b where (b ->> 'i')::int = v_x and b ->> 'tipo' = 'compromisso';
      if v_b is not null and not coalesce((v_b ->> 'na_janela')::boolean, true) then
        v_tipo := 'depois';
        v_txt := format('%s: começa %s%s.', public._agenda_rotulo_da_os(v_os),
                        public._dia_curto(v_ini + ((v_b ->> 'ini')::int + 1) / 2 - 1),
                        coalesce(' (' || (select r ->> 'texto' from jsonb_array_elements(v_info -> v_os::text -> 'pront' -> 'restricoes') r
                                           where r ->> 'tipo' in ('bem', 'nao_antes') limit 1) || ')', ''));
      elsif v_x = any (v_h) then
        v_tipo := 'espera';
        v_txt := format('%s: espera a sua decisão.', public._agenda_rotulo_da_os(v_os));
      end if;
    end if;
    -- FASE 7c: (7c P2, §5.2 5, §6.8) o fora habilidade (do encaixe: não coube com quem o serviço pede, cabia sem ele): o que ela pede
    -- e que ninguém com isso fica livre junto no horizonte; no dia que o dono pediu, o "não cabe <dia>" de sempre, com o porquê do
    -- dia ("ninguém que sobe no teto fica livre nesse dia")
    if v_tipo = 'habilidade' and v_txt is null then
      v_txt := case when v_e ? 'fixar_de'
                    then format('%s: não cabe %s: %s.', public._agenda_rotulo_da_os(v_os), public._dia_curto(v_ini + (v_e ->> 'fixar_de')::int - 1),
                                public._agenda_por_que_nao(v_ctx, v_e, (v_e ->> 'fixar_de')::int, cf.wip_max))
                    else format('%s: pede %s e ninguém com isso fica livre junto nas próximas %s semanas.', public._agenda_rotulo_da_os(v_os),
                                concat_ws(' e ', public._agenda_exigencia_texto(nullif(coalesce((v_e ->> 'ext')::int, 0), 0),
                                                                                case when coalesce((v_e ->> 'passos')::int, 0) > 1 then 'todos' end),
                                                 public._agenda_exigencia_texto(nullif(coalesce((v_e ->> 'exu')::int, 0), 0), 'ultimo')),
                                cf.horizonte_semanas) end;
    end if;
    -- FASE 7c: fim
    continue when v_tipo is null;
    v_txt := coalesce(v_txt, format('%s: %s.', public._agenda_rotulo_da_os(v_os), case v_tipo
      when 'padrao_do_dono' then 'falta você dizer quais dias fica em campo'
      when 'fixar_nao_cabe' then format('não cabe %s: %s', public._dia_curto(v_ini + (v_e ->> 'fixar_de')::int - 1),
                                        public._agenda_por_que_nao(v_ctx, v_e, (v_e ->> 'fixar_de')::int, cf.wip_max))
      when 'sem_reserva' then rtrim(v_e ->> 'texto', '.') || ' (sem lugar para a reserva nesta semana)'
      when 'so_com_voce' then rtrim(v_e ->> 'texto', '.') || ' (é só com você: entra quando isso estiver respondido)'
      else format('sem encaixe em %s semanas com a equipe de hoje', cf.horizonte_semanas) end));
    v_fora := v_fora || jsonb_build_object('os', v_os, 'numero', v_e ->> 'numero', 'cliente_curto', v_e ->> 'cliente_curto',
                                           'motivo', v_tipo, 'texto', v_txt);
  end loop;
  -- (as que saíram da carteira e tinham plano)
  v_fora := v_fora || coalesce((
    select jsonb_agg(jsonb_build_object('os', x.os, 'numero', v_info -> x.os::text -> 'pront' ->> 'numero',
             'cliente_curto', v_info -> x.os::text -> 'pront' ->> 'cliente_curto', 'motivo', 'fora_da_carteira',
             'texto', format('%s: %s.', public._agenda_rotulo_da_os(x.os), v_info -> x.os::text -> 'pront' ->> 'estado_texto'))
             order by v_info -> x.os::text -> 'pront' ->> 'numero')
      from (select distinct (c ->> 'os')::uuid as os from jsonb_array_elements(v_canc) c where c ->> 'motivo' = 'os_saiu') x
     where not (x.os = any (v_escopo))), '[]'::jsonb);

  -- ── 8. A carga por pessoa e semana (o publicável sem esperar) ──
  select coalesce(jsonb_object_agg(p.id, jsonb_build_object('nome', p.nome, 'semanas', p.semanas)), '{}'::jsonb) into v_carga
    from (select (v_ctx -> 'pessoas' ->> (pp - 1)) as id, (v_ctx -> 'nomes' ->> (pp - 1)) as nome,
                 jsonb_agg(jsonb_build_object(
                   'semana', v_seg + 7 * (ww - 1),
                   'esperado', (v_ctxf -> 'esperado' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'teto80', (v_ctxf -> 'teto80' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'teto100', (v_ctxf -> 'teto100' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'compromisso', (v_ctxf -> 'uso_c' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1)),
                   'reserva', (v_ctxf -> 'uso_r' -> ((pp - 1) * (v_ctx ->> 'nw')::int + ww - 1))) order by ww) as semanas
            from generate_series(1, (v_ctx ->> 'np')::int) pp
            cross join generate_series((v_de - v_seg) / 7 + 1, (v_ate - v_seg) / 7 + 1) ww
           group by pp) p;

  -- ── 9. A pontuação (para comparar alternativas) ──
  select jsonb_build_object(
           'atraso_dias', coalesce(sum(greatest((i ->> 'fim_depois')::date - (v_ent -> x.ii ->> 'precisa')::date, 0))
                                     filter (where v_ent -> x.ii ->> 'precisa' is not null), 0),
           'mudancas', (select count(*) from jsonb_array_elements(v_canc) c where not (c ->> 'violada')::boolean and c ->> 'motivo' = 'replanejado'),
           'meios_do_dono', coalesce(sum((i ->> 'meios_do_dono')::int), 0),
           'interrupcoes', coalesce(sum((i ->> 'interrupcoes')::int), 0),
           'fim', coalesce(sum((i ->> 'ate')::date - v_ini), 0))
    into v_pont
    from jsonb_array_elements(v_itens) i
    cross join lateral (select (select e ->> 'i' from jsonb_array_elements(v_fila) e where e ->> 'os' = i ->> 'os') as ii) x
   where i ->> 'op' = 'criar' and not coalesce((i ->> 'espera')::boolean, false);
  v_pont := v_pont || jsonb_build_object('total',
    (v_pont ->> 'atraso_dias')::bigint * c_peso_atraso + (v_pont ->> 'mudancas')::bigint * c_peso_mudanca
    + (v_pont ->> 'meios_do_dono')::bigint * c_peso_dono + (v_pont ->> 'interrupcoes')::bigint * c_peso_interr
    + (v_pont ->> 'fim')::bigint * c_peso_fim);

  -- ── 10. Os textos prontos ──
  v_feriados := array(select format('%s é %s', public._agenda_dia_sem_mes(g::date), public.agenda_feriado(g::date))
                        from generate_series(v_de - (extract(isodow from v_de)::int - 1), v_ate, interval '1 day') g
                       where extract(isodow from g)::int <= 5 and public.agenda_feriado(g::date) is not null order by g);
  v_titulo := case when p_escopo = 'semana'
    then format('Semana de %s a %s', to_char(v_de, 'DD'),
                to_char(coalesce((select max(g::date) from generate_series(v_de, v_ate, interval '1 day') g
                                   where public.agenda_dia_util(g::date)), v_ate), 'DD/MM'))
         || coalesce(' (' || nullif(array_to_string(v_feriados, ', '), '') || ')', '')
    else 'Mudanças na agenda' end;
  v_linhas := array(select i ->> 'texto' || case when coalesce((i ->> 'espera')::boolean, false) then ' (espera a sua decisão)' else '' end
                      from jsonb_array_elements(v_itens) with ordinality t(i, k)
                     order by i ->> 'op' = 'cancelar', (i ->> 'de')::date, i ->> 'numero' collate "C", k);
  v_tfora := array(select f ->> 'texto' from jsonb_array_elements(v_fora) with ordinality t(f, k) order by k);
  v_textos := jsonb_build_object('titulo', v_titulo, 'linhas', to_jsonb(v_linhas), 'fora', to_jsonb(v_tfora),
    'carga', to_jsonb(array(
      select format('%s: %s de %s meios-dias de serviço na semana de %s',
                    case when p.key::uuid is not distinct from v_dono then 'Você' else p.value ->> 'nome' end,
                    s ->> 'compromisso', s ->> 'teto80', to_char((s ->> 'semana')::date, 'DD/MM'))
        from jsonb_each(v_carga) p, jsonb_array_elements(p.value -> 'semanas') s
       where (s ->> 'esperado')::numeric > 0
       order by (s ->> 'semana')::date, p.key::uuid is not distinct from v_dono desc, p.value ->> 'nome')),
    'resumo', format('%s: %s, %s.', v_titulo,
                     public._agenda_plural((select count(distinct i ->> 'os')::int from jsonb_array_elements(v_itens) i
                                             where i ->> 'op' = 'criar' and not (i ->> 'espera')::boolean), 'serviço marcado', 'serviços marcados'),
                     public._agenda_plural(jsonb_array_length(v_fora), 'de fora', 'de fora')));
  -- CORREÇÃO 29/10 (P3): o marcado firme e o reservado separados no resumo e no título da semana (com a agenda automática
  -- ligada). A reserva só guarda o lugar da equipe (nada está marcado até a condição dela se cumprir), e o resumo de antes
  -- contava como "serviço marcado" toda OS que entra: com só a reserva do Lenine, "1 serviço marcado". Com reserva no que
  -- entra (sem o que espera a decisão), o resumo diz quem: "1 reservado (Lenine), nada marcado firme, 10 de fora"; e o título
  -- da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme"): é ele que abre o
  -- "Publiquei a semana de …" da aplicação, do que mudou e do fechamento, que listam as OS logo depois. A OS com algum
  -- meio-dia firme conta como marcada. No resumo, o nome curto do cliente, com o número quando o nome se repete ("Kalmar
  -- OS-00032"); até 3 nomes, depois "e mais N". Sem reserva, ou fora de ligado, os dois são os de antes, byte a byte.
  if v_modo = 'ligado' then
    select coalesce(array_agg(x.nome order by x.de, x.numero collate "C") filter (where x.firme), '{}'::text[]),
           coalesce(array_agg(x.nome order by x.de, x.numero collate "C") filter (where not x.firme), '{}'::text[])
      into v_marc, v_resv
      from (select y.numero, y.de, y.firme,
                   case when count(*) over (partition by y.curto) > 1 then concat_ws(' ', y.curto, y.numero) else y.curto end as nome
              from (select min(i ->> 'numero') as numero, min((i ->> 'de')::date) as de, bool_or(i ->> 'tipo' <> 'reserva') as firme,
                           coalesce(public._agenda_nome_curto(min(i ->> 'cliente_curto')), min(i ->> 'numero')) as curto
                      from jsonb_array_elements(v_itens) i
                     where i ->> 'op' = 'criar' and not coalesce((i ->> 'espera')::boolean, false)
                     group by i ->> 'os') y) x;
  end if;
  if cardinality(v_resv) > 0 then
    v_contagem := case when cardinality(v_marc) > 0
                       then format('%s (%s), %s (%s)',
                                   public._agenda_plural(cardinality(v_marc), 'serviço marcado', 'serviços marcados'),
                                   public._agenda_lista(v_marc, 3),
                                   public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'), public._agenda_lista(v_resv, 3))
                       else format('%s (%s), nada marcado firme',
                                   public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'), public._agenda_lista(v_resv, 3))
                  end;
    v_textos := v_textos || jsonb_build_object('resumo', format('%s: %s, %s.', v_titulo, v_contagem,
                                                               public._agenda_plural(jsonb_array_length(v_fora), 'de fora', 'de fora')));
    if p_escopo = 'semana' then
      v_titulo := v_titulo || ' — '
                  || case when cardinality(v_marc) > 0
                          then format('%s, %s', public._agenda_plural(cardinality(v_marc), 'serviço marcado', 'serviços marcados'),
                                      public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'))
                          else format('%s, nada marcado firme', public._agenda_plural(cardinality(v_resv), 'reservado', 'reservados'))
                     end;
      v_textos := v_textos || jsonb_build_object('titulo', v_titulo);
    end if;
  end if;
  -- CORREÇÃO 29/10 (P3): fim
  v_texto := v_titulo
    || coalesce(E'\n' || nullif(array_to_string(array(select '• ' || x from unnest(v_linhas) x), E'\n'), ''), E'\nNada a mudar.')
    || coalesce(E'\nFora: ' || nullif(array_to_string(v_tfora, '; '), ''), '')
    || case when p_persistir then '' else E'\nÉ simulação: não muda nada.' end;

  -- FASE 7b: (7b P4, §6.3, R4.3(a)4) em teste, o que a 7b faria e não fez — o sábado ("Em teste: para cumprir o prazo de Vanderlei
  -- (qua 18/11), eu usaria sáb 14/11 de manhã com Rafael, que se ofereceu.") e a dupla de 1 pessoa ("Em teste: no Lenine eu pediria
  -- um ajudante em qua 04/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas."): textos.em_teste e no fim do texto.
  for v_7b_b in select e from jsonb_array_elements(coalesce(v_rf -> 'sab_teste', '[]'::jsonb)) e loop
    v_7b_e := v_ent -> (v_7b_b ->> 'i');
    select array_agg(distinct (a ->> 'dia')::date order by (a ->> 'dia')::date) into v_7b_dias
      from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_7b_b -> 'b')) a
     where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno';
    v_7b_nomes := array(select y.x from (select a ->> 'nome' as x, min(o) as o
                                           from jsonb_array_elements(public._agenda_alocs_do_bloco(v_ctx, v_7b_b -> 'b')) with ordinality t(a, o)
                                          where extract(isodow from (a ->> 'dia')::date) = 6 and a ->> 'presenca' = 'turno' group by 1) y
                         order by y.o);
    v_7b_teste := v_7b_teste || case when v_7b_e ? 'prazo'
      then format('Em teste: para cumprir o prazo de %s (%s), eu usaria %s de manhã com %s, que %s.',
                  public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'), public._dia_curto((v_7b_e ->> 'prazo')::date),
                  public._agenda_dias_texto(v_7b_dias), public._agenda_lista(v_7b_nomes),
                  case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end)
      else format('Em teste: %s terminaria antes com %s de manhã (%s %s).', public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'),
                  public._agenda_dias_texto(v_7b_dias), public._agenda_lista(v_7b_nomes),
                  case when cardinality(v_7b_nomes) > 1 then 'se ofereceram' else 'se ofereceu' end) end;
  end loop;
  if cf.modo_dupla = 'sombra' then
    for v_7b_b in select b from jsonb_array_elements(v_rf -> 'colocadas') b
                   where b ? 'dupla_falta' and jsonb_array_length(b -> 'dupla_falta') > 0 and coalesce((b ->> 'na_janela')::boolean, true)
                     and not ((b ->> 'i')::int = any (v_xnc) and b ->> 'tipo' = 'compromisso') loop
      v_7b_e := v_ent -> (v_7b_b ->> 'i');
      v_7b_teste := v_7b_teste || format('Em teste: no %s eu pediria um ajudante em %s: %s pede 2 pessoas.',
        public._agenda_nome_curto(v_7b_e ->> 'cliente_curto'),
        public._agenda_lista(array(
          select public._dia_curto(z.d) || case when bool_or(z.t = 'manha') and bool_or(z.t = 'tarde') then ' (manhã e tarde)'
                                                when bool_or(z.t = 'manha') then ' (manhã)' else ' (tarde)' end
            from (select v_ini + ((f ->> 'h')::int + 1) / 2 - 1 as d, case when (f ->> 'h')::int % 2 = 1 then 'manha' else 'tarde' end as t
                    from jsonb_array_elements(v_7b_b -> 'dupla_falta') f) z
           group by z.d order by z.d)),
        coalesce(case when coalesce((v_7b_e ->> 'dupla_todos')::boolean, false) then v_7b_e ->> 'dupla_rot_todos' end,
                 nullif(public._agenda_lista(array_remove(array[nullif(v_7b_e ->> 'dupla_rot_ini', ''), nullif(v_7b_e ->> 'dupla_rot_fim', '')], null)), ''),
                 'a tarefa'));
    end loop;
  end if;
  if cardinality(v_7b_teste) > 0 then
    v_textos := v_textos || jsonb_build_object('em_teste', to_jsonb(v_7b_teste));
    v_texto := v_texto || E'\n' || array_to_string(v_7b_teste, E'\n');
  end if;
  -- FASE 7b: fim
  -- ── 11. A validação: proposta inválida nunca sai ──
  v_viol := public._agenda_validar_itens(v_itens, jsonb_build_object('p_restricoes', v_r), p_hoje, p_agora, false,
              (select jsonb_object_agg(k, x -> 'pront') from jsonb_each(v_info) t(k, x)));
  if jsonb_array_length(v_viol) > 0 then
    raise exception 'agenda_propor: a proposta saiu inválida (erro do motor): %', v_viol::text
      using errcode = 'P0001', detail = left(v_texto, 2000);
  end if;

  -- ── 12. Persistir ──
  if p_persistir then
    -- a aberta anterior do mesmo escopo e modo (e das mesmas OS, fora da semana) fica obsoleta; as alocações dela saem
    for v_q in
      select to_jsonb(pr) from public.agenda_propostas pr
       where pr.estado = 'aberta' and pr.escopo = p_escopo and pr.modo = v_modo
         and (p_escopo = 'semana' or pr.os_alvo && v_escopo)
       order by pr.criada_em, pr.id
    loop
      update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'refeita' where id = (v_q ->> 'id')::uuid;
      delete from public.agenda_alocacoes where proposta_id = (v_q ->> 'id')::uuid and estado = 'proposta';
    end loop;
    v_pid := gen_random_uuid();
    -- os ids das alocações novas entram no item (é por eles que o aplicar publica)
    select coalesce(jsonb_agg(case when i ->> 'op' = 'criar'
             then i || jsonb_build_object('alocacoes', (select jsonb_agg(a || jsonb_build_object('alocacao_id', gen_random_uuid()) order by j)
                                                          from jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)))
             else i end order by k), '[]'::jsonb)
      into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(i, k);
    v_expira := least(p_agora + cf.proposta_validade,
                      coalesce((select min(lower(public.agenda_periodo((a ->> 'dia')::date, a ->> 'turno', a ->> 'presenca')))
                                  from jsonb_array_elements(v_itens) i, jsonb_array_elements(i -> 'alocacoes') a
                                 where i ->> 'op' = 'criar'), p_agora + cf.proposta_validade));
    insert into public.agenda_propostas (id, escopo, periodo, os_alvo, versao_base, modo, estado, itens, fora, carga, textos,
                                         parametros, pontuacao, criada_por, autor, criada_em, expira_em)
    values (v_pid, p_escopo, daterange(v_de, v_ate, '[]'), v_escopo, v0, v_modo, 'aberta', v_itens, v_fora, v_carga, v_textos,
            jsonb_build_object('p_hoje', p_hoje, 'p_agora', p_agora, 'p_de', p_de, 'p_ate', p_ate, 'p_os', to_jsonb(p_os),
                               'p_restricoes', v_r, 'escopo', p_escopo, 'origem', p_origem, 'de', v_de, 'ate', v_ate),
            v_pont, p_origem, p_autor, p_agora, v_expira);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id,
                                         reserva_de, condicao, condicao_tipo, condicao_ate, motivos, criado_em)
    select (a ->> 'alocacao_id')::uuid, (i ->> 'os')::uuid, (a ->> 'payee_id')::uuid, (a ->> 'dia')::date, a ->> 'turno',
           a ->> 'presenca', i ->> 'tipo', 'proposta', case when (i ->> 'fixar_dono')::boolean then 'dono' else 'motor' end, v_pid,
           i ->> 'reserva_de', case when a ->> 'presenca' = 'turno' then i ->> 'condicao' end,
           case when a ->> 'presenca' = 'turno' then i ->> 'condicao_tipo' end,
           case when a ->> 'presenca' = 'turno' then (i ->> 'condicao_ate')::date end,
           coalesce(i -> 'motivos', '[]'::jsonb), p_agora
      from jsonb_array_elements(v_itens) with ordinality t(i, k), jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)
     where i ->> 'op' = 'criar'
     order by k, j;
    -- as perguntas críticas (a mesma pergunta não abre duas vezes; a de uma versão anterior da mesma OS sai)
    for v_q in select q from jsonb_array_elements(v_perg) q loop
      update public.agenda_perguntas p
         set estado = 'descartada', resolvida_motivo = 'a agenda mudou: a pergunta foi refeita'
       where p.estado = 'aberta' and p.modo = v_modo and p.tipo = v_q ->> 'tipo'
         and p.service_order_id = (v_q ->> 'service_order_id')::uuid and p.chave <> v_q ->> 'chave';
      insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao,
                                           recomendacao_texto, proposta_id, versao_base, modo, criada_em)
      values (v_q ->> 'tipo', v_q ->> 'chave', (v_q ->> 'service_order_id')::uuid,
              array(select x::uuid from jsonb_array_elements_text(v_q -> 'os_ids') x), null, (v_q ->> 'perda_em')::date,
              v_q ->> 'texto', v_q -> 'opcoes', (v_q ->> 'recomendacao')::smallint, v_q ->> 'recomendacao_texto', v_pid, v0, v_modo, p_agora)
      on conflict (chave, modo) where estado = 'aberta' do nothing;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true, 'proposta_id', v_pid, 'versao_base', v0, 'escopo', p_escopo, 'modo', v_modo,
    'periodo', jsonb_build_object('de', v_de, 'ate', v_ate), 'simulacao', not p_persistir,
    'itens', v_itens, 'fora', v_fora, 'carga', v_carga,
    'perguntas', (select coalesce(jsonb_agg(q - 'x' order by q ->> 'chave'), '[]'::jsonb) from jsonb_array_elements(v_perg) q),
    'pontuacao', v_pont, 'textos', v_textos, 'texto', v_texto);
end;
$function$;

comment on function public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): o motor — guloso serial determinístico (mesma entrada, mesma saída). Escopo semana (publica os blocos que COMEÇAM de segunda a sábado da semana seguinte), os ou replano (as OS de p_os, depois do congelado, no horizonte). Etapas: estabilidade (_agenda_violacoes: só sai o que não pode mais acontecer; o publicado não violado nunca vira "mover"), a fila por classe (_agenda_classe_da_os) na ordem (classe, prioridade do dono, razão crítica, sinal pago, aprovação, número), o encaixe (_agenda_encaixar: congelamento hoje + o próximo dia útil, salvo evento real e pedido do dono; ≤ wip_max frentes; o dono como tambor; teto de carga_max por pessoa e semana; multi-dia com no máximo interrupcoes_max dias parados), a sobrecarga (a OS com data dita que não cabe vira a pergunta crítica nao_cabe, com as opções simuladas e a recomendação; o banco nunca escolhe), o atraso crítico de quem já tinha plano (_agenda_criticidade), as reservas (teto, condicionada com a data-limite, pátio), a validação (_agenda_validar_itens: inválida nunca sai), o diff (itens), as OS de fora com quem trava, a carga, a pontuação e os textos. Restrições: {fixar:[{os, de, ate, pessoa}], tirar:[os], so_depois_de:[{os, dia}], atrasar:[os], aceitar_atraso:[os], acima_da_carga, decisao}. Com p_persistir: agenda_propostas (modo = modo_proposta; a aberta anterior fica obsoleta), as alocações em estado proposta e as perguntas críticas. Sem persistir, o texto termina com "É simulação: não muda nada.". Só service_role. CORREÇÃO FASE 6 (C1, item 14): a reserva por teto da OS que precisa do dono, com a capacidade dele em uso abaixo de carga_max, diz "não coube na sua parte da semana (56%)" (a carga de _agenda_carga_da_pessoa), e não "na carga de 80%". CORREÇÃO 29/10 (P3): (a) a entrada da fila da OS com reserva vigente (por teto ou condicionada, de hoje em diante: a que o item "a reserva vira compromisso" cancela) leva res_propria (a pessoa × semana de cada meio-dia reservado), e o encaixe do compromisso dela não conta a própria reserva no lugar até 100% — a promoção da reserva cabe com o teto apertado (o João, 4 de 4 na semana); a reserva das outras OS continua contando. (b) Com a agenda automática ligada e reserva no que entra, o resumo separa o marcado firme do reservado e diz quem ("Semana de 03 a 06/11 (seg 02 é Finados): 1 reservado (Lenine), nada marcado firme, 10 de fora."), e o título da semana diz quantos ("Semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme", que abre o "Publiquei a semana de …"); sem reserva, ou fora de ligado, os de antes. FASE 7 (7a P3): o item de compromisso com a fonte orcamento (a estimativa do orçamento como dias firmes, só com a regra estimativa) termina "(estimativa minha: 6 dias)."; a recomendação das críticas dia_avisado ("A equipe já tinha recebido a ficha desse dia: recomendo seguir e você avisar quem ia") e dia_prometido ("É um dia que o cliente já ouviu: recomendo seguir e você falar com ele hoje"), que só nascem com a zona travada do P8. FASE 7 (7a P8, spec §3.2 e §5.8): com a regra zona_travada, a criticidade de cada compromisso colocado é refeita com p_violadas = _agenda_zona_fora (o que não conta para o dia já avisado: a violação, o resto do meio-dia dela e o que volta igual neste encaixe; nunca o fixado pelo dono): o meio-dia de um dia já dito à equipe ou ao cliente que sairia sem ter ficado impossível, e o fim que passaria do prometido firme, viram as críticas dia_avisado e dia_prometido, com a pergunta e a recomendação de sempre. Sem a regra, a de antes, byte a byte. FASE 7b (P4, §5.3, §6.3, R4.3): só com os modos da 7b — a entrada da fila ganha dk (as pessoas dos passos que restam), dk_dono_conta, dupla_fonte e o texto da dupla; da dupla inferida, passos1 (o bloco de 1 pessoa: ligado, a soma do dk; em teste, os passos de antes), dupla_ni/dupla_nf/dupla_todos e os nomes do que a tarefa pede; prazo_h (o índice da tarde de least(precisa_ate, o prometido firme)) e prazo; e dupla_sd na dupla dita que só passa pela régua dos técnicos com quem vem sob demanda. p_par ganha sab_modo, sab_politica, dupla_modo e dupla_espera. Ligado, o item com o sábado diz qual e por quê (" — com sáb 14/11 de manhã (Rafael se ofereceu), para cumprir o prazo de qua 18/11.") e o bloco de 1 pessoa da dupla inferida diz em que meios-dias chamar um ajudante (" Nos 2 primeiros meios-dias (qua 04/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem qua 04/11)."); o item leva dupla (o texto do cartão), dupla_fonte, dupla_falta [{dia, turno, onde}] e sabado. A dupla dita com dupla_sd sem bloco vai ao fora com o motivo dupla ("Lenine (OS-00074): precisa de 2 pessoas em 6 meios-dias e Mateus só vem qua 11 e qui 12/11 (4 meios-dias): me diga mais dias dele ou chame outro ajudante."), nunca sem_encaixe. Em teste, textos.em_teste e o fim do texto: "Em teste: para cumprir o prazo de Vanderlei (qua 18/11), eu usaria sáb 14/11 de manhã com Rafael, que se ofereceu." e "Em teste: no Lenine eu pediria um ajudante em qua 04/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas.". Sem os modos da 7b, a de antes, byte a byte. CORREÇÃO DA REVISÃO DA 7b (achados 22 e 23): o exemplo da dupla de 1 pessoa diz todos os dias em que falta a 2ª pessoa ("ex.: Mateus vem qua 18 e qui 19/11"); a dupla dita que só passou da espera por quem vem sob demanda e cujos dias livres são todos antes de a OS ficar pronta (os_prontidao.est) vai ao fora dupla com "…, antes de o serviço ficar pronto (qua 18/11): me diga dias dele a partir de qua 18/11 ou chame outro ajudante.". FASE 7c (P2, §5.2, R5.10-12): a entrada da fila ganha ext, exu, exf e exig_texto (os_exigencias, em qualquer modo) e, com modo_lider ou modo_habilidade ligado, lid, lid_nome, lid_duro, lid_plan e lid_fora (_agenda_lider_da_os); p_par ganha hab_modo, lid_modo, n, fcobre e lid_espera (sempre: o critério de cada alocação vai no item e o gatilho agenda_alocacoes_criterio o grava). Ligado: os motivos "pede … : vai …", "troquei o responsável: … não está livre até …; segui com …" e "…, o responsável, não está na equipe agora"; o aviso de habilidade (_agenda_aviso_da_habilidade) ao lado do de material onde o dono disse quem vai; o cancelar habilidade ("a equipe do dia não tinha quem o serviço pede") e o fora habilidade ("pede … e ninguém com isso fica livre junto nas próximas 6 semanas"); o contexto do "por que não cabe" leva hab_modo, n e fcobre. Com os 3 modos fora de ligado, as pessoas, os dias, os turnos e as presenças de antes (a projeção); só o critério aparece.';

-- ── 8. O critério de toda alocação nova (o gatilho) e a imutável ─────────────────────────────────────────────────
-- O gatilho do critério: BEFORE INSERT (o molde do agenda_alocacoes_fonte da 7a, que lê o item pelo proposta_id; pelo nome, ele roda
-- depois do agenda_alocacoes_antes e antes do agenda_alocacoes_fonte e do _agenda_alocacoes_porque do 7g). A alocação que já chega
-- com critério ou detalhe não muda. A do motor ganha o da alocação do item da proposta (pelo alocacao_id: o motor o põe lá, em
-- qualquer modo). As outras — os 5 escritores fora do motor —: a do dono (turno, abertura ou fechamento) ganha criterio
-- presenca_do_dono, e todas ganham criterio_detalhe.regra pela proposta: escada (parametros.gestor.tipo reparar, a escada da revisão da
-- 7a), dupla (reparar com o motivo dupla_completa, a 2ª pessoa da 7b), corte (reestimar, o corte da revisão da 7a) ou fora_do_motor
-- (sem proposta do gestor: as refeitas pelo agenda_desfazer e pelo _agenda_desfazer_cliente). Barato: lê o item pelo proposta_id e a
-- OS.
create or replace function public._agenda_alocacao_criterio()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_a jsonb;
  v_g jsonb;
begin
  if new.criterio is not null or coalesce(new.criterio_detalhe, '{}'::jsonb) <> '{}'::jsonb then
    return new;
  end if;
  if new.proposta_id is not null then
    select a into v_a
      from public.agenda_propostas p,
           jsonb_array_elements(case when jsonb_typeof(p.itens) = 'array' then p.itens else '[]'::jsonb end) i,
           jsonb_array_elements(case when jsonb_typeof(i -> 'alocacoes') = 'array' then i -> 'alocacoes' else '[]'::jsonb end) a
     where p.id = new.proposta_id and i ->> 'op' = 'criar' and i ->> 'os' = new.service_order_id::text
       and a ->> 'alocacao_id' = new.id::text
     limit 1;
    if jsonb_typeof(v_a -> 'criterio_detalhe') = 'object' then
      new.criterio := v_a ->> 'criterio';
      new.criterio_detalhe := v_a -> 'criterio_detalhe';
      return new;
    end if;
    select p.parametros -> 'gestor' into v_g from public.agenda_propostas p where p.id = new.proposta_id;
  end if;
  if new.payee_id is not distinct from public._agenda_dono(null) then
    new.criterio := 'presenca_do_dono';
  end if;
  new.criterio_detalhe := jsonb_build_object('regra', case when v_g ->> 'motivo' = 'dupla_completa' then 'dupla'
                                                           when v_g ->> 'tipo' = 'reparar' then 'escada'
                                                           when v_g ->> 'tipo' = 'reestimar' then 'corte'
                                                           else 'fora_do_motor' end);
  return new;
end;
$function$;

comment on function public._agenda_alocacao_criterio() is
  'Agenda de Produção (Fase 7c, P2; spec §R5.7-6, §R5.10-12): gatilho BEFORE INSERT de agenda_alocacoes — a alocação nova que chega sem critério: a do motor ganha o criterio e o criterio_detalhe da alocação do item da proposta (pelo alocacao_id); fora do motor, a do dono ganha criterio presenca_do_dono e todas ganham criterio_detalhe.regra pela proposta (parametros.gestor: reparar = escada, reparar com dupla_completa = dupla, reestimar = corte; sem gestor = fora_do_motor, as refeitas pelo desfazer). A que já chega com critério não muda.';

drop trigger if exists agenda_alocacoes_criterio on public.agenda_alocacoes;
create trigger agenda_alocacoes_criterio before insert on public.agenda_alocacoes
  for each row execute function public._agenda_alocacao_criterio();

-- _agenda_alocacoes_imutavel (de 20261025100000_agenda_fase2_tabelas.sql)
create or replace function public._agenda_alocacoes_imutavel()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_h jsonb;
  v_mudou_o_que boolean :=
    (new.service_order_id, new.payee_id, new.dia, new.turno, new.presenca, new.tipo, new.origem,
     new.condicao, new.condicao_tipo, new.condicao_ate)
    is distinct from
    (old.service_order_id, old.payee_id, old.dia, old.turno, old.presenca, old.tipo, old.origem,
     old.condicao, old.condicao_tipo, old.condicao_ate);
begin
  -- FASE 7c: (7c P2, §5.2) o critério que decidiu a pessoa (criterio e criterio_detalhe: a medida do 7g) também não muda na
  -- publicada, na fixada nem na cancelada
  v_mudou_o_que := v_mudou_o_que or (new.criterio, new.criterio_detalhe) is distinct from (old.criterio, old.criterio_detalhe);
  -- FASE 7c: fim
  if old.estado = 'cancelada' and (v_mudou_o_que or new.estado is distinct from old.estado) then
    raise exception 'Alocação cancelada não volta nem muda: crie outra.';
  end if;
  if old.estado in ('publicada', 'fixada') and v_mudou_o_que then
    raise exception 'Alocação publicada não muda: cancele e crie outra (fica o rastro).';
  end if;

  if new.estado is distinct from old.estado then
    if old.estado = 'fixada' and new.estado = 'cancelada'
       and coalesce(current_setting('agenda.mexe_fixado', true), '') <> 'on' then
      raise exception 'Esse meio-dia está fixado: só sai com a decisão de mexer no fixado.';
    end if;
    if not ((old.estado = 'proposta' and new.estado in ('publicada', 'fixada', 'cancelada'))
            or (old.estado = 'publicada' and new.estado in ('fixada', 'cancelada'))
            or (old.estado = 'fixada' and new.estado = 'cancelada')) then
      raise exception 'Essa troca de estado não existe: % → %.', old.estado, new.estado;
    end if;
    if new.estado = 'cancelada' and coalesce(old.resultado, new.resultado) is not null then
      raise exception 'Esse meio-dia já aconteceu: corrija o resultado, não cancele.';
    end if;
  end if;

  -- Corrigir o resultado é permitido e fica no histórico (os 20 mais novos).
  if old.resultado is not null and new.resultado is distinct from old.resultado then
    v_h := old.historico || jsonb_build_array(jsonb_build_object(
             'em', now(), 'de', old.resultado, 'para', new.resultado, 'via', new.resultado_via));
    if jsonb_array_length(v_h) > 20 then
      select jsonb_agg(e order by o) into v_h
        from jsonb_array_elements(v_h) with ordinality t(e, o)
       where o > jsonb_array_length(v_h) - 20;
    end if;
    new.historico := v_h;
  end if;

  return new;
end;
$function$;

comment on function public._agenda_alocacoes_imutavel() is
  'Agenda de Produção (Fase 2): gatilho BEFORE UPDATE — publicada/fixada não muda (cancela-se e cria-se outra); proposta → publicada|fixada|cancelada, publicada → fixada|cancelada, fixada → cancelada só com agenda.mexe_fixado = on; cancelada não volta; com resultado não se cancela; correção do resultado vai para o histórico. FASE 7c (P2): criterio e criterio_detalhe entram na tupla que a publicada, a fixada e a cancelada não mudam.';

-- ── 9. Portas ────────────────────────────────────────────────────────────────────────────────────────────────────
-- A nova (o aviso) e o gatilho: sem grant a ninguém (só o agenda_propor, definer, chama o aviso; o gatilho roda no insert).
revoke all on function public._agenda_aviso_da_habilidade(uuid, jsonb, date) from public, anon, authenticated, service_role;
revoke all on function public._agenda_alocacao_criterio() from public, anon, authenticated;

-- As recriadas mantêm as portas delas (create or replace não muda a ACL; repetidas aqui para a migration se bastar): o motor, só
-- service_role; o gatilho da imutável, ninguém.
revoke all on function
  public._agenda_contexto(date, date, date, uuid[], uuid[]),
  public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer),
  public._agenda_so_diaristas(jsonb, integer), public._agenda_encaixar(jsonb, jsonb, jsonb),
  public._agenda_alocs_do_bloco(jsonb, jsonb), public._agenda_por_que_nao(jsonb, jsonb, integer, integer),
  public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  from public, anon, authenticated;
grant execute on function
  public._agenda_contexto(date, date, date, uuid[], uuid[]),
  public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer),
  public._agenda_so_diaristas(jsonb, integer), public._agenda_encaixar(jsonb, jsonb, jsonb),
  public._agenda_alocs_do_bloco(jsonb, jsonb), public._agenda_por_que_nao(jsonb, jsonb, integer, integer),
  public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)
  to service_role;
revoke all on function public._agenda_alocacoes_imutavel() from public, anon, authenticated;
