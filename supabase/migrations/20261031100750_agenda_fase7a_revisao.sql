-- Agenda de Produção, Fase 7, etapa 7a ("ele marca sozinho"), pacote P9 (7a-1): a revisão diária e a escada de reparo.
-- Todo dia útil, no 1º tique do gestor depois das 16:45, a agenda é revista a partir do publicado: o que pela estimativa do
-- orçamento ficou com dias a mais perde os últimos, o que ficou com dias a menos ganha o que falta, o que está pronto e sem dia é
-- encaixado (ou reservado) no mesmo dia, o diagnóstico feito vira pergunta e o orçamento que mudou depois dos dias do dono vira
-- pergunta com prazo. E quando alguém deixa de vir, o gestor conserta do jeito mais barato antes de remarcar: outra pessoa no
-- mesmo meio-dia, o outro turno, outro dia da mesma semana; só se nada disso der, o motor procura outra data.
-- Spec: scratchpad agenda-pesquisa/spec-fase7a.md (§R2, §3.3 d11, §5.9, §6.3, §6.4, §8.4); nomes: fase7-registro.md §1 e §2
-- (degraus pessoa, turno, dia; o motor é data); respostas do dono: fase7-padroes.md (D7-3: "revisa a agenda TODO DIA"; a medição
-- de 30/10, item 1: "tem de marcar/reservar no dia").
-- Depende da 20261031100000 (7a P1: os modos, a regra escada, os tipos reavaliar/reestimar, a ação reparar/reestimar, o motivo
-- reestimada, o portão), da 20261031100100 (7a P2: a estimativa e o diagnóstico), da 20261031100300 (7a P4: o prazo, o gravador
-- das perguntas e o despacho), da 20261031100600 (7a P7: a rodada acha o passo revisao por to_regprocedure; a sombra) e da
-- 20261031100700 (7a P8: a conta da onda e o despacho de onde esta copia); antes delas, das Fases 1 a 6 e do lote de 30/10.
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (6 funções novas e 4 recriadas; nenhuma tabela, coluna, lista, dado, cron ou tela muda)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f7a/p9/montar-migration.mjs: as 4 recriadas são o corpo
-- da definição MAIS NOVA (conferido a cada montagem em supabase/migrations, também nas 20261030* do lote e nas 20261031* dos
-- pacotes anteriores): agenda_replanejar de 20261025100300, agenda_aplicar de 20261029100900, _agenda_gestor_sombra de
-- 20261031100600 (7a P7) e _agenda_gestor_decidir de 20261031100700 (7a P8). As mudanças estão só nos blocos "-- FASE 7: (7a
-- P9 … -- FASE 7: fim"; fora deles nenhuma linha muda (o V7 de supabase/tests/agenda_fase7a_revisao.sql confere). Com o portão do
-- gestor falso (a regra escada fora, o gestor desligado, em sombra fora da simulação ou com *gestor, só propor*, ou a revisão
-- diária fora de ligado), agenda_replanejar é a de antes, byte a byte; agenda_aplicar só muda com a proposta que o gestor monta.
--
-- POR QUE: a vigia só encaixa o que acabou de ficar pronto, e a reserva espera a quinta (a medição de 30/10: a semana de 03 a 06/11
-- vazia com o Alex livre). E quando alguém falta, o motor põe o meio-dia que falta no FIM do plano: ele nunca troca a pessoa no
-- mesmo meio-dia (spec §3.3 d11). O gestor que revisa todo dia (D7-3) faz as duas coisas.
--
-- O QUE MUDA:
--   1. _agenda_gestor_revisao (o passo revisao da rodada do gestor, diário): (1) reestimar — a OS com compromisso pela estimativa
--      do orçamento cujo plano ficou maior que a conta de agora perde os últimos meios-dias (_agenda_gestor_reestimar: "Nelson
--      (OS-00112): o orçamento mudou e agora estimo 3 dias (eram 4). Tirei sex 13/11."), a que ficou menor entra no encaixe, e a
--      OS com os dias do dono e o orçamento mudado depois ganha a pergunta reestimar (prazo; sem resposta, ficam os dias do dono);
--      (2) encaixar — as OS da carteira sem compromisso nas classes 1 a 3 (a 3 sem reserva) e as do plano menor, pelo motor (a
--      onda vale); (3) reavaliar — o diagnóstico feito vira pergunta (sem prazo). Em teste, tudo seco no diário
--      (agenda_gestor_dia.sombra.revisao).
--   2. A escada de reparo (_agenda_gestor_reparo, a conta; _agenda_gestor_reparar, aplicada; e o bloco de agenda_replanejar):
--      quando quem ia não está mais livre, antes do motor — (1) outra pessoa no mesmo meio-dia ("Lenine qua 04/11 de manhã:
--      troquei João por Roberto (João não vem)."); (2) o outro turno do dia ("Lenine qua 04/11: passei a manhã para a tarde, com
--      Roberto."); (3) outro dia da mesma semana, sem passar do fim ("Lenine: passei qua 04/11 de manhã para sex 06/11 de manhã
--      (mesma semana; o fim não muda)."). Cada conserto passa nas 14 regras do motor; tudo ou nada por OS; o pedido do cliente pula
--      a escada; a onda vale. O 4º degrau é o motor, como sempre.
--   3. agenda_aplicar (recriada): a proposta que o gestor monta sem o motor (a escada e o corte) diz o tipo da ação (reparar,
--      reestimar) e a frase dela; sem isso, nada muda.
--   4. _agenda_gestor_decidir (recriada): reestimar — 1 fico com os dias do dono (o que vale no prazo); 2 uso a minha conta (os
--      dias ficam gravados como os do gestor, com o sim do dono e a ação estimar, e a agenda acompanha na hora); reavaliar — 1
--      "Use *concluiu Rodrigo*."; 2 "Me diga o que mais tem para fazer e quantos dias".
--   5. _agenda_gestor_sombra (recriada): o "eu marcaria assim" das 16:52 mantém o sombra.revisao que a revisão em teste gravou no
--      mesmo tique.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase7a_revisao.sql; registradas em notas-fase77a.md, P9):
--   · agenda_aplicar e _agenda_gestor_sombra são recriadas (fora da spec): a ação só se grava uma vez (agenda_acoes não muda
--     depois), e sem o tipo vindo da proposta a escada sairia "mover" com a frase "de qua 04/11 para qua 04/11"; e a sombra das
--     16:52 reescrevia o diário inteiro, apagando o que a revisão em teste acabou de calcular.
--   · Três funções novas fora do registro: _agenda_gestor_reparo (a conta da escada, sem gravar: a onda precisa dela antes de
--     consertar), _agenda_gestor_corte (a conta do corte) e _agenda_gestor_perguntas_da_revisao (as perguntas reestimar e
--     reavaliar, secas ou gravadas: o despacho confere a condição por ela). _agenda_gestor_reestimar ganhou p_autor (default
--     null): o dono que escolhe a conta do gestor na pergunta faz o corte dele.
--   · A escada também exige a revisão diária ligada (a saúde do P7 conta reparar como regra da revisão) e respeita a onda.
--   · O encaixe da revisão inclui a classe 3 sem reserva e a classe 1 sem dia (a spec dizia só a classe 2): a medição de 30/10
--     pede marcar ou reservar no dia, sem esperar a quinta.
--   · O texto da pergunta reestimar não diz o valor de antes do orçamento ("era R$ 3.100"): o banco não guarda o orçamento do dia
--     em que o dono disse os dias. Diz o de agora. Nomes sem artigo (§6): "Nelson (OS-00112): o orçamento mudou …".
--   · A opção 2 do reestimar ("Use 5,5 dias") grava os dias com a fonte orcamento (a conta do gestor, escolhida pelo dono), como
--     a opção 1 das perguntas do P4: o *desfaz* da ação estimar (P7) só volta dias dessa fonte, e a revisão segue acompanhando.
--   · O "acrescentei seg 16/11" do reestimar que falta é a ação do motor (a mesma frase de sempre, com "(estimativa minha: 5
--     dias)"): o que falta entra pelo encaixe.
--
-- ORDEM DE LIGAR (spec §10): nada liga aqui. A revisão roda com modo_revisao_diaria (a migration de dado 20261031100990 o põe em
-- sombra; o "OK ligar a revisão diária" o liga); a escada é a regra escada do gestor que marca (marcar_regras, com
-- modo_marcar_sozinho ligado) e só age com a revisão ligada. Desfazer: o modo para sombra; a regra fora de marcar_regras;
-- *gestor, só propor*; uma OS, *desfaz <nome>*.
--
-- PROVA: supabase/tests/agenda_fase7a_revisao.sql (V0–V7), na bancada (node scripts/bancada-agenda/rodar.mjs).
--
-- APLICAR (depois do OK nomeado, com as 20261031100000–100700 já aplicadas):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261031100750_agenda_fase7a_revisao.sql
--
-- DESFAZER: reaplicar as definições de antes (as migrations de origem citadas acima, na ordem) e
--   drop function if exists public._agenda_gestor_revisao(date, timestamptz),
--     public._agenda_gestor_reparar(uuid, date, timestamptz), public._agenda_gestor_reparo(uuid, date, timestamptz),
--     public._agenda_gestor_reestimar(uuid, date, timestamptz, uuid), public._agenda_gestor_corte(uuid, date, timestamptz),
--     public._agenda_gestor_perguntas_da_revisao(uuid, date, timestamptz, boolean);
--   (sem o passo revisao, a rodada do gestor o pula: "ainda não existe").
--
-- IDEMPOTENTE: create or replace function, comment, revoke e grant.

-- ── 1. As funções novas ──────────────────────────────────────────────────────────────────────────────────────────

-- A escada de reparo, a conta (spec §3.3 d11, §5.9 e §6.4), sem gravar nada: a OS com meio-dia de compromisso que não pode mais
-- acontecer porque quem ia não está mais livre (a violação pessoa de _agenda_violacoes) tenta, meio-dia violado por meio-dia
-- violado, o conserto mais barato antes do motor:
--   (1) pessoa — outro diarista livre no MESMO dia e turno, sem outra OS ali (quem já trabalha na OS primeiro; depois quem mais
--       vem no dia);
--   (2) turno — o outro turno do mesmo dia, em que a OS não tem meio-dia: a mesma pessoa se estiver livre, senão outra;
--   (3) dia — outro dia útil da mesma semana, depois do congelado (no congelado só com o evento real; nunca o que já começou),
--       não depois do último dia da OS, onde ela não tem meio-dia, sem deixar o serviço parado mais dias no meio do que ele já
--       ficava (ou interrupcoes_max): o que deixa menos dias parados primeiro, depois o mais perto, a mesma pessoa primeiro.
-- O 4º degrau é o motor (agenda_replanejar, a data ao dono). Cada candidato só vale se as 14 regras do motor
-- (_agenda_validar_itens) aceitam o conjunto inteiro: os tetos da pessoa e da equipe na semana, o choque, o "não antes de", o
-- congelado, a classe, o máximo de serviços no meio-dia. Os degraus 2 e 3 só para o meio-dia em que a OS tem só essa pessoa (sem
-- o dono abrindo ou fechando ali, sem outra pessoa junto), e o meio-dia novo nunca passa da abertura nem do fechamento do dono
-- (eles continuam no 1º e no último meio-dia do serviço). Tudo ou nada por OS: com algum meio-dia sem conserto, reparavel =
-- false (sobrou) e a OS vai inteira ao motor (que refaria, depois do congelado, o que a escada consertasse). A violação de outro
-- motivo (material, cliente, a OS saiu…), a da reserva, a do dono e a do que o dono fixou não são da escada. Saída: {os, numero,
-- reparavel, motivo?, degrau (pessoa | turno | dia: o mais caro dos consertos), itens (o formato de agenda_propor: um cancelar
-- com as violadas, motivo pessoa, violada; um criar por conserto, com o motivo "degrau …"), texto (spec §6.4), reparos [{alocacao_id,
-- degrau, de {payee_id, nome, dia, turno}, para {payee_id, nome, dia, turno}}], sobrou [alocacao_id], fim_antes, fim_depois,
-- evento_real}. STABLE, invoker, sem grant: só _agenda_gestor_reparar e agenda_replanejar (definer) a chamam.
create or replace function public._agenda_gestor_reparo(p_os uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  c_base   constant date := date '2000-01-03';   -- uma segunda: o meio-dia vira um número (2 por dia), para comparar a ordem
  c_tentar constant int := 12;                   -- estrutural: quantos candidatos o validador confere por meio-dia violado
  cf       public.agenda_config;
  v_cong   date;
  v_dono   uuid;
  v_numero text;
  v_cli    text;
  v_rot    text;
  v_pront  jsonb;
  v_meios  jsonb;
  v_canc   jsonb;
  v_viol   jsonb;
  v_ids    uuid[];
  v_base   jsonb;
  v_ev     boolean;
  v_d1     date;
  v_d2     date;
  v_cap    jsonb;
  v_ult    date;
  v_ab     int;
  v_fe     int;
  v_int0   int;
  v_lim    int;
  v_bem    datemultirange;
  v_ok     jsonb := '[]'::jsonb;
  v_sobra  jsonb := '[]'::jsonb;
  v_canc_i jsonb;
  v_itens  jsonb;
  v_val    jsonb;
  v_v      jsonb;
  v_c      record;
  v_achou  jsonb;
  v_so     boolean;
  v_seg    date;
  v_rdias  date[];
  v_rmin   date;
  v_rmax   date;
  v_n      int;
  v_fim    date;
  v_grau   int;
  v_frases text[] := '{}';
  r        record;
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_reparo: faltam a OS, o dia ou a hora' using errcode = '22004';
  end if;
  select so.service_order_number, coalesce(public._agenda_nome_curto(cl.name), so.service_order_number)
    into v_numero, v_cli
    from public.service_orders so left join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
  v_base := jsonb_build_object('os', p_os, 'numero', v_numero, 'reparavel', false, 'degrau', null, 'itens', '[]'::jsonb,
                               'texto', null, 'reparos', '[]'::jsonb, 'sobrou', '[]'::jsonb);
  if v_numero is null then
    return v_base || jsonb_build_object('motivo', 'sem_os');
  end if;
  cf := public._agenda_cfg();
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_dono := public._agenda_dono(null);
  v_rot := public._agenda_rotulo_da_os(p_os);
  v_pront := public.os_prontidao(p_os, p_hoje);
  v_meios := public.agenda_meios_da_os(p_os, p_hoje);
  v_canc := public._agenda_violacoes(array[p_os], array(select k.service_order_id from public.os_carteira(p_hoje) k), false,
              jsonb_build_object(p_os::text, jsonb_build_object('pront', v_pront, 'meios', v_meios)), p_hoje, v_cong);
  select coalesce(jsonb_agg(c order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'payee_id', c ->> 'alocacao_id'), '[]'::jsonb)
    into v_viol
    from jsonb_array_elements(v_canc) c
   where coalesce((c ->> 'violada')::boolean, false) and (c ->> 'os')::uuid = p_os;
  if jsonb_array_length(v_viol) = 0 then
    return v_base || jsonb_build_object('motivo', 'nada_violado');
  end if;
  if exists (select 1 from jsonb_array_elements(v_viol) c where c ->> 'motivo' <> 'pessoa') then
    return v_base || jsonb_build_object('motivo', 'outro_motivo',
             'motivos', (select jsonb_agg(distinct c ->> 'motivo') from jsonb_array_elements(v_viol) c));
  end if;
  if exists (select 1 from jsonb_array_elements(v_viol) c
              where c ->> 'tipo' = 'reserva' or coalesce(c ->> 'presenca', 'turno') <> 'turno'
                 or (c ->> 'payee_id')::uuid is not distinct from v_dono or c ->> 'fixado_por' = 'dono') then
    return v_base || jsonb_build_object('motivo', 'fora_da_escada');
  end if;

  v_ids := array(select (c ->> 'alocacao_id')::uuid from jsonb_array_elements(v_viol) c);
  v_ev := exists (select 1 from jsonb_array_elements(v_viol) c where coalesce((c ->> 'congelado')::boolean, false));
  select min((c ->> 'dia')::date), max((c ->> 'dia')::date) into v_d1, v_d2 from jsonb_array_elements(v_viol) c;
  v_d1 := v_d1 - (extract(isodow from v_d1)::int - 1);
  v_d2 := v_d2 + (7 - extract(isodow from v_d2)::int);
  select coalesce(jsonb_agg(to_jsonb(k)), '[]'::jsonb) into v_cap from public.agenda_capacidade(v_d1, v_d2, p_hoje) k;
  select pl.bem_indisponivel into v_bem from public.os_planejamento pl where pl.service_order_id = p_os;
  -- o que a OS tem de hoje em diante (o último dia; a abertura e o fechamento do dono, fora das violadas; os dias parados)
  select max(a.dia) into v_ult
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje;
  select min((a.dia - c_base) * 2 + case when a.turno = 'tarde' then 1 else 0 end) filter (where a.presenca = 'abertura'),
         max((a.dia - c_base) * 2 + case when a.turno = 'tarde' then 1 else 0 end) filter (where a.presenca = 'fechamento')
    into v_ab, v_fe
    from public.agenda_alocacoes a
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
     and a.resultado is null and not (a.id = any (v_ids));
  v_rdias := array(select distinct a.dia from public.agenda_alocacoes a
                    where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                      and a.presenca = 'turno' and a.dia >= p_hoje and a.resultado is null order by 1);
  select count(*)::int into v_int0
    from generate_series(v_rdias[1] + 1, v_rdias[cardinality(v_rdias)] - 1, interval '1 day') g
   where cardinality(v_rdias) > 1 and public.agenda_dia_util(g::date) and not (g::date = any (v_rdias))
     and not coalesce(v_bem @> g::date, false);
  v_lim := greatest(coalesce(v_int0, 0), cf.interrupcoes_max);

  -- o cancelar (todas as violadas da OS, de uma vez: é o que sai)
  v_canc_i := jsonb_build_object(
    'op', 'cancelar', 'os', p_os, 'numero', v_numero, 'cliente_curto', v_pront ->> 'cliente_curto',
    'tipo', (select min(c ->> 'tipo') from jsonb_array_elements(v_viol) c), 'motivo', 'pessoa', 'violada', true,
    'alocacoes', (select jsonb_agg(jsonb_build_object('alocacao_id', c -> 'alocacao_id', 'payee_id', c -> 'payee_id',
                                     'nome', (select public._agenda_nome_curto(py.name) from public.payees py
                                               where py.id = (c ->> 'payee_id')::uuid),
                                     'dia', c -> 'dia', 'turno', c -> 'turno', 'presenca', c -> 'presenca', 'estado', c -> 'estado',
                                     'fixado_por', c -> 'fixado_por')
                                   order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'payee_id')
                    from jsonb_array_elements(v_viol) c),
    'de', (select min(c ->> 'dia') from jsonb_array_elements(v_viol) c),
    'ate', (select max(c ->> 'dia') from jsonb_array_elements(v_viol) c),
    'critica', null, 'decisao', null, 'aplicado', false,
    'texto', format('%s: sai %s — quem ia não está mais livre.', v_rot,
                    public._agenda_dias_texto(array(select (c ->> 'dia')::date from jsonb_array_elements(v_viol) c))));

  for v_v in select c from jsonb_array_elements(v_viol) c
              order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'payee_id', c ->> 'alocacao_id' loop
    v_achou := null;
    -- os degraus 2 e 3 só para o meio-dia em que a OS tem só esta pessoa (sem o dono abrindo ou fechando, sem outra junto)
    v_so := not exists (select 1 from public.agenda_alocacoes a
                         where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                           and a.dia = (v_v ->> 'dia')::date and a.turno = v_v ->> 'turno'
                           and a.id <> (v_v ->> 'alocacao_id')::uuid);
    v_seg := (v_v ->> 'dia')::date - (extract(isodow from (v_v ->> 'dia')::date)::int - 1);
    -- os dias que ficam com a OS (os de turno, fora as violadas, com os consertos aceitos)
    v_rdias := array(select distinct d from (
                       select a.dia as d from public.agenda_alocacoes a
                        where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                          and a.presenca = 'turno' and a.dia >= p_hoje and a.resultado is null and not (a.id = any (v_ids))
                       union all
                       select (x #>> '{para,dia}')::date from jsonb_array_elements(v_ok) x) u order by 1);
    v_rmin := v_rdias[1];
    v_rmax := v_rdias[cardinality(v_rdias)];
    v_n := 0;
    for v_c in
      with k as (
        select * from jsonb_to_recordset(v_cap) as k(payee_id uuid, pessoa text, eh_dono boolean, dia date, turno text,
                                                     situacao text, meios_esperados numeric)
         where k.situacao = 'livre' and not coalesce(k.eh_dono, false) and k.payee_id is distinct from v_dono
      ),
      alvo as (
        select 1 as grau, (v_v ->> 'dia')::date as dia, v_v ->> 'turno' as turno
        union all
        select 2, (v_v ->> 'dia')::date, case when v_v ->> 'turno' = 'manha' then 'tarde' else 'manha' end where v_so
        union all
        select 3, g::date, t.t
          from generate_series(v_seg, v_seg + 6, interval '1 day') g, unnest(array['manha', 'tarde']) t(t)
         where v_so and g::date <> (v_v ->> 'dia')::date and public.agenda_dia_util(g::date) and g::date <= v_ult
      )
      select a.grau, a.dia, a.turno, k.payee_id, public._agenda_nome_curto(k.pessoa) as nome,
             case when a.grau = 3 then
               (select count(*)::int
                  from generate_series(least(v_rmin, a.dia) + 1, greatest(v_rmax, a.dia) - 1, interval '1 day') g
                 where public.agenda_dia_util(g::date) and g::date <> a.dia and not (g::date = any (coalesce(v_rdias, '{}'::date[])))
                   and not coalesce(v_bem @> g::date, false))
             else 0 end as parado
        from alvo a
        join k on k.dia = a.dia and k.turno = a.turno
       where (a.grau > 1 or k.payee_id <> (v_v ->> 'payee_id')::uuid)
         and lower(public.agenda_periodo(a.dia, a.turno, 'turno')) > p_agora
         and (a.dia > v_cong or v_ev)
         -- a OS não tem meio-dia ali (degraus 2 e 3)
         and (a.grau = 1 or not exists (select 1 from public.agenda_alocacoes x
                                         where x.service_order_id = p_os and x.estado in ('publicada', 'fixada')
                                           and x.tipo <> 'reserva' and x.dia = a.dia and x.turno = a.turno
                                           and not (x.id = any (v_ids))))
         and (a.grau = 1 or not exists (select 1 from jsonb_array_elements(v_ok) x
                                         where x #>> '{para,dia}' = a.dia::text and x #>> '{para,turno}' = a.turno))
         -- nem antes da abertura nem depois do fechamento do dono
         and (a.grau = 1 or ((v_ab is null or (a.dia - c_base) * 2 + case when a.turno = 'tarde' then 1 else 0 end > v_ab)
                             and (v_fe is null or (a.dia - c_base) * 2 + case when a.turno = 'tarde' then 1 else 0 end < v_fe)))
         -- a pessoa sem outra coisa no meio-dia (fora o que sai) nem outro conserto ali
         and not exists (select 1 from public.agenda_alocacoes x
                          where x.payee_id = k.payee_id and x.estado in ('publicada', 'fixada') and not (x.id = any (v_ids))
                            and x.periodo && public.agenda_periodo(a.dia, a.turno, 'turno'))
         and not exists (select 1 from jsonb_array_elements(v_ok) x
                          where x #>> '{para,payee_id}' = k.payee_id::text and x #>> '{para,dia}' = a.dia::text
                            and x #>> '{para,turno}' = a.turno)
       order by a.grau, 6, abs(a.dia - (v_v ->> 'dia')::date), a.dia, a.turno = 'tarde',
                k.payee_id = (v_v ->> 'payee_id')::uuid desc,
                exists (select 1 from public.agenda_alocacoes x where x.service_order_id = p_os and x.payee_id = k.payee_id
                           and x.estado in ('publicada', 'fixada') and not (x.id = any (v_ids))) desc,
                k.meios_esperados desc, k.pessoa, k.payee_id
    loop
      continue when v_c.grau = 3 and v_c.parado > v_lim;
      v_n := v_n + 1;
      exit when v_n > c_tentar;
      v_achou := jsonb_build_object(
        'alocacao_id', v_v -> 'alocacao_id', 'degrau', case v_c.grau when 1 then 'pessoa' when 2 then 'turno' else 'dia' end,
        'tipo', v_v ->> 'tipo',
        'fonte', coalesce((select a.duracao_fonte from public.agenda_alocacoes a where a.id = (v_v ->> 'alocacao_id')::uuid),
                          v_meios ->> 'fonte'),
        'de', jsonb_build_object('payee_id', v_v -> 'payee_id',
                                 'nome', (select public._agenda_nome_curto(py.name) from public.payees py
                                           where py.id = (v_v ->> 'payee_id')::uuid),
                                 'dia', v_v -> 'dia', 'turno', v_v -> 'turno'),
        'para', jsonb_build_object('payee_id', v_c.payee_id, 'nome', v_c.nome, 'dia', v_c.dia, 'turno', v_c.turno));
      v_itens := jsonb_build_array(v_canc_i) || (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'op', 'criar', 'os', p_os, 'numero', v_numero, 'cliente_curto', v_pront ->> 'cliente_curto',
                 'tipo', x ->> 'tipo', 'reserva_de', null,
                 'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', x #> '{para,payee_id}', 'nome', x #> '{para,nome}',
                                                                   'dia', x #> '{para,dia}', 'turno', x #> '{para,turno}',
                                                                   'presenca', 'turno')),
                 'de', x #> '{para,dia}', 'ate', x #> '{para,dia}', 'fim_antes', v_ult, 'fim_depois', null, 'atraso_du', null,
                 'condicao_tipo', null, 'critica', null, 'pergunta_chave', null, 'decisao', null, 'espera', false,
                 'interrupcoes', 0, 'meios_do_dono', 0, 'fonte', x ->> 'fonte', 'dias', v_meios -> 'dias', 'evento_real', v_ev,
                 'fixar_dono', false, 'aviso_material', null, 'abre', false, 'fecha', false,
                 'motivos', jsonb_build_array('degrau ' || (x ->> 'degrau')), 'texto', null, 'aplicado', false,
                 'degrau', x ->> 'degrau') order by o), '[]'::jsonb)
          from jsonb_array_elements(v_ok || jsonb_build_array(v_achou)) with ordinality t(x, o));
      v_val := public._agenda_validar_itens(v_itens, jsonb_build_object('p_restricoes', '{}'::jsonb), p_hoje, p_agora, false,
                                            jsonb_build_object(p_os::text, v_pront));
      exit when jsonb_array_length(v_val) = 0;
      v_achou := null;
    end loop;
    if v_achou is null then
      v_sobra := v_sobra || (v_v -> 'alocacao_id');
    else
      v_ok := v_ok || jsonb_build_array(v_achou);
    end if;
  end loop;

  if jsonb_array_length(v_sobra) > 0 then
    return v_base || jsonb_build_object('motivo', 'sem_lugar', 'sobrou', v_sobra, 'reparos', v_ok, 'evento_real', v_ev);
  end if;

  -- o fim: o último dia que a OS fica tendo (o fim nunca passa do de antes: os degraus não vão depois do último dia)
  select max(d) into v_fim from (
    select a.dia as d from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.dia >= p_hoje
       and not (a.id = any (v_ids))
    union all
    select (x #>> '{para,dia}')::date from jsonb_array_elements(v_ok) x) u;
  v_grau := (select max(case x ->> 'degrau' when 'pessoa' then 1 when 'turno' then 2 else 3 end) from jsonb_array_elements(v_ok) x);

  -- as frases (spec §6.4): a troca de pessoa nos dois turnos do mesmo dia vira uma só
  for r in
    select min(x #>> '{de,dia}') as dia_de, x ->> 'degrau' as degrau, x #>> '{de,nome}' as de_nome, x #>> '{para,nome}' as para_nome,
           count(*) as n, min(x #>> '{de,turno}') as turno_de, min(x #>> '{para,dia}') as dia_para,
           min(x #>> '{para,turno}') as turno_para, bool_or(x #>> '{de,payee_id}' = x #>> '{para,payee_id}') as mesma
      from jsonb_array_elements(v_ok) x
     group by x ->> 'degrau', x #>> '{de,dia}', x #>> '{de,payee_id}', x #>> '{de,nome}', x #>> '{para,payee_id}', x #>> '{para,nome}',
              case when x ->> 'degrau' = 'pessoa' then '' else x #>> '{de,turno}' end
     order by min(x #>> '{de,dia}'), min(x #>> '{de,turno}') = 'tarde'
  loop
    v_frases := v_frases || case r.degrau
      when 'pessoa' then format('%s %s: troquei %s por %s (%s não vem).', v_cli,
                                case when r.n > 1 then public._dia_curto(r.dia_de::date)
                                     else public._agenda_meio_texto(r.dia_de::date, r.turno_de) end,
                                r.de_nome, r.para_nome, r.de_nome)
      when 'turno' then format('%s %s: passei a %s para a %s, com %s.', v_cli, public._dia_curto(r.dia_de::date),
                               case when r.turno_de = 'manha' then 'manhã' else 'tarde' end,
                               case when r.turno_para = 'manha' then 'manhã' else 'tarde' end, r.para_nome)
      else format('%s: passei %s para %s%s (mesma semana%s).', v_cli, public._agenda_meio_texto(r.dia_de::date, r.turno_de),
                  public._agenda_meio_texto(r.dia_para::date, r.turno_para),
                  case when r.mesma then '' else ', com ' || r.para_nome end,
                  case when v_fim = v_ult then '; o fim não muda' else '' end) end;
  end loop;

  return v_base || jsonb_build_object(
    'reparavel', true, 'motivo', null,
    'degrau', case v_grau when 1 then 'pessoa' when 2 then 'turno' else 'dia' end,
    'itens', (select jsonb_agg(case when i ->> 'op' = 'criar'
                                    then i || jsonb_build_object('fim_depois', v_fim,
                                                                 'texto', array_to_string(v_frases, ' '))
                                    else i end order by k)
                from jsonb_array_elements(v_itens) with ordinality t(i, k)),
    'texto', public._agenda_corta(array_to_string(v_frases, ' '), 400),
    'reparos', v_ok, 'fim_antes', v_ult, 'fim_depois', v_fim, 'evento_real', v_ev);
end;
$function$;

comment on function public._agenda_gestor_reparo(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P9; spec §3.3 d11, §5.9, §6.4): a escada de reparo, a conta, sem gravar nada — para a OS com meio-dia de compromisso violado por pessoa (_agenda_violacoes: quem ia não está mais livre), cada meio-dia violado procura, nesta ordem, (1) pessoa: outro diarista livre no mesmo dia e turno, sem outra OS ali; (2) turno: o outro turno do mesmo dia, sem meio-dia da OS, a mesma pessoa se livre; (3) dia: outro dia útil da mesma semana ISO, depois do congelado (no congelado só com o evento real, nunca o que começou), não depois do último dia da OS, sem meio-dia dela, sem mais dias parados do que ela já tinha (ou interrupcoes_max). Cada candidato só vale com as 14 regras do motor (_agenda_validar_itens) sobre o conjunto. Degraus 2 e 3 só no meio-dia em que a OS tem só essa pessoa, nunca antes da abertura nem depois do fechamento do dono. Tudo ou nada por OS (sobrou = vai inteira ao motor). Violação de outro motivo, da reserva, do dono ou do fixado pelo dono: não é da escada. {os, numero, reparavel, motivo?, degrau, itens (o formato de agenda_propor), texto ("Lenine qua 04/11 de manhã: troquei João por Roberto (João não vem)."; "Lenine qua 04/11: passei a manhã para a tarde, com Roberto."; "Lenine: passei qua 04/11 de manhã para sex 06/11 de manhã (mesma semana; o fim não muda)."), reparos, sobrou, fim_antes, fim_depois, evento_real}. STABLE, invoker, sem grant.';

-- A escada de reparo, aplicada (spec §5.9): a conta de _agenda_gestor_reparo vira UMA proposta (escopo replano, criada_por vigia,
-- modo ligado, a versão do plano lida sob a trava do plano) com os itens no formato de agenda_propor, e agenda_aplicar a valida
-- (as 14 regras) e aplica: a ação sai com o tipo reparar e a frase da §6.4 (as parametros.gestor da proposta). Inválida no
-- aplicar = a proposta é descartada, nada muda e a OS vai ao motor (app_error_logs, warn). Fora de modo_proposta ligado, nada.
-- {os, reparado, degrau, acao_ids, sobrou, texto, proposta_id, motivo?}. Definer, sem grant a ninguém (nem service_role): só
-- agenda_replanejar a chama.
create or replace function public._agenda_gestor_reparar(p_os uuid, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  v      jsonb;
  v_pid  uuid;
  v_its  jsonb;
  v_exp  timestamptz;
  v_a    jsonb;
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_reparar: faltam a OS, o dia ou a hora' using errcode = '22004';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('os', p_os, 'reparado', false, 'motivo', 'em_teste', 'acao_ids', '[]'::jsonb, 'sobrou', '[]'::jsonb);
  end if;
  v := public._agenda_gestor_reparo(p_os, p_hoje, p_agora);
  if not coalesce((v ->> 'reparavel')::boolean, false) then
    return jsonb_build_object('os', p_os, 'reparado', false, 'motivo', v ->> 'motivo', 'degrau', null, 'acao_ids', '[]'::jsonb,
                              'sobrou', coalesce(v -> 'sobrou', '[]'::jsonb));
  end if;
  -- os ids das alocações novas entram no item (é por eles que o aplicar publica)
  select coalesce(jsonb_agg(case when i ->> 'op' = 'criar'
           then i || jsonb_build_object('alocacoes', (select jsonb_agg(a || jsonb_build_object('alocacao_id', gen_random_uuid()) order by j)
                                                        from jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)))
           else i end order by k), '[]'::jsonb)
    into v_its
    from jsonb_array_elements(v -> 'itens') with ordinality t(i, k);
  v_pid := gen_random_uuid();
  v_exp := least(p_agora + cf.proposta_validade,
                 coalesce((select min(lower(public.agenda_periodo((a ->> 'dia')::date, a ->> 'turno', a ->> 'presenca')))
                             from jsonb_array_elements(v_its) i, jsonb_array_elements(i -> 'alocacoes') a
                            where i ->> 'op' = 'criar'), p_agora + cf.proposta_validade));
  insert into public.agenda_propostas (id, escopo, periodo, os_alvo, versao_base, modo, estado, itens, fora, carga, textos,
                                       parametros, pontuacao, criada_por, autor, criada_em, expira_em)
  values (v_pid, 'replano',
          daterange((select min(least((i ->> 'de')::date, (i ->> 'ate')::date)) from jsonb_array_elements(v_its) i),
                    (select max(greatest((i ->> 'de')::date, (i ->> 'ate')::date)) from jsonb_array_elements(v_its) i), '[]'),
          array[p_os], cf.versao_plano, 'ligado', 'aberta', v_its, '[]'::jsonb, '{}'::jsonb,
          jsonb_build_object('titulo', 'Mudanças na agenda', 'linhas', jsonb_build_array(v ->> 'texto'), 'fora', '[]'::jsonb,
                             'resumo', v ->> 'texto'),
          jsonb_build_object('p_hoje', p_hoje, 'p_agora', p_agora, 'p_de', null, 'p_ate', null, 'p_os', jsonb_build_array(p_os),
                             'p_restricoes', '{}'::jsonb, 'escopo', 'replano', 'origem', 'vigia',
                             'gestor', jsonb_build_object('tipo', 'reparar', 'degrau', v ->> 'degrau',
                                                          'textos', jsonb_build_object(p_os::text, v ->> 'texto'))),
          null, 'vigia', null, p_agora, v_exp);
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id,
                                       duracao_fonte, motivos, criado_em)
  select (a ->> 'alocacao_id')::uuid, p_os, (a ->> 'payee_id')::uuid, (a ->> 'dia')::date, a ->> 'turno', 'turno', i ->> 'tipo',
         'proposta', 'motor', v_pid, nullif(i ->> 'fonte', ''), coalesce(i -> 'motivos', '[]'::jsonb), p_agora
    from jsonb_array_elements(v_its) with ordinality t(i, k), jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)
   where i ->> 'op' = 'criar'
   order by k, j;
  v_a := public.agenda_aplicar(v_pid, null, 'vigia', null, null, p_hoje, p_agora);
  if not coalesce((v_a ->> 'ok')::boolean, false) then
    perform public.agenda_descartar(v_pid, null, 'a escada não passou no aplicar');
    perform public.log_app_error('db', 'agenda: a escada de reparo não aplicou: ' || coalesce(v_a ->> 'texto', '?'),
                                 'agenda', 'gestor:reparar', 'warn',
                                 jsonb_build_object('os', p_os, 'proposta', v_pid, 'violacoes', v_a -> 'violacoes',
                                                    'p_hoje', p_hoje, 'p_agora', p_agora));
    return jsonb_build_object('os', p_os, 'reparado', false, 'motivo', 'nao_aplicou', 'degrau', v ->> 'degrau',
                              'acao_ids', '[]'::jsonb, 'sobrou', '[]'::jsonb, 'violacoes', v_a -> 'violacoes');
  end if;
  return jsonb_build_object('os', p_os, 'reparado', true, 'degrau', v ->> 'degrau', 'acao_ids', coalesce(v_a -> 'acoes', '[]'::jsonb),
                            'sobrou', '[]'::jsonb, 'texto', v_a ->> 'texto', 'proposta_id', v_pid,
                            'publicadas', coalesce((v_a ->> 'publicadas')::int, 0),
                            'canceladas', coalesce((v_a ->> 'canceladas')::int, 0));
end;
$function$;

comment on function public._agenda_gestor_reparar(uuid, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P9; spec §5.9): a escada de reparo aplicada — a conta de _agenda_gestor_reparo numa proposta (escopo replano, criada_por vigia, modo ligado, versao_base sob a trava agenda_plano; parametros.gestor = {tipo reparar, degrau, textos}) com as alocações em estado proposta, e agenda_aplicar (as 14 regras validam; a ação sai tipo reparar com a frase da §6.4, desfazível). Inválida no aplicar = descartada, nada muda (app_error_logs gestor:reparar, warn). Fora de modo_proposta ligado = {reparado false, motivo em_teste}. {os, reparado, degrau, acao_ids, sobrou, texto, proposta_id, publicadas, canceladas, motivo?}. Security definer, sem grant a ninguém (nem service_role): só agenda_replanejar a chama.';

-- O corte do reestimar, a conta (spec §5.9 item 1 e §6.4), sem gravar nada: com mais meios-dias no plano (os feitos + os de
-- hoje em diante) do que os dias da OS pedem (agenda_meios_da_os.total: a estimativa do orçamento, viva, quando a fonte é
-- orcamento), os N últimos meios-dias de compromisso saem (N = os de sobra, inteiros) — do fim para trás, parando no 1º que não
-- pode sair: o congelado, o que já começou, o fixado (pelo dono, pelo cliente, pela execução) e o dia já dito à equipe ou ao
-- cliente (_agenda_dia_avisado: esses o dono decide; ficam). O fechamento do dono que sai junto com o último meio-dia volta no
-- novo último. {os, numero, total, feitos, sobra, cortar, cortados [{dia, turno}], ficou, itens, texto ("Nelson (OS-00112): o
-- orçamento mudou e agora estimo 3 dias (eram 4). Tirei sex 13/11."), motivo?}. STABLE, invoker, sem grant.
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
  v_n := floor(v_feito - v_total)::int;
  if v_n < 1 then
    return v_base || jsonb_build_object('sobra', greatest(v_n, 0), 'motivo', 'nada_a_cortar');
  end if;
  cf := public._agenda_cfg();
  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_dono := public._agenda_dono(null);

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
  'Agenda de Produção (Fase 7a, P9; spec §5.9 item 1 e §6.4): o corte do reestimar, a conta, sem gravar — com o plano (os meios-dias feitos + os de hoje em diante) maior que agenda_meios_da_os.total, os N últimos meios-dias de compromisso saem (N = a sobra inteira), do fim para trás, parando no 1º que não pode sair (o congelado, o que começou, o fixado, o dia já dito à equipe ou ao cliente: esses ficam com o dono); o fechamento do dono que sai volta no novo último meio-dia. Validado pelas 14 regras (_agenda_validar_itens). {os, numero, fonte, total, feitos, sobra, cortar, cortados [{dia, turno}], ficou, itens (cancelar motivo reestimada; criar do fechamento), texto ("Nelson (OS-00112): o orçamento mudou e agora estimo 3 dias (eram 4). Tirei sex 13/11."), motivo?}. STABLE, invoker, sem grant.';

-- O reestimar, aplicado (spec §5.9): o corte de _agenda_gestor_corte numa proposta (escopo replano, criada_por vigia — ou dono,
-- quando p_autor vem: o dono escolheu "use a sua conta" na pergunta reestimar —, modo ligado; parametros.gestor = {tipo
-- reestimar, textos}) e agenda_aplicar (a ação reestimar, desfazível; as alocações saem com o motivo reestimada). Fora de
-- modo_proposta ligado, nada. {os, reestimado, cortados, ficou, texto, acao_ids, proposta_id, motivo?}. Definer, sem grant a
-- ninguém (nem service_role): só a revisão diária e o despacho das perguntas do gestor a chamam.
create or replace function public._agenda_gestor_reestimar(p_os uuid, p_hoje date, p_agora timestamptz, p_autor uuid default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf     public.agenda_config;
  c      jsonb;
  v_pid  uuid;
  v_its  jsonb;
  v_exp  timestamptz;
  v_a    jsonb;
  v_por  text := case when p_autor is null then 'vigia' else 'dono' end;
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_reestimar: faltam a OS, o dia ou a hora' using errcode = '22004';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  if cf.modo_proposta <> 'ligado' then
    return jsonb_build_object('os', p_os, 'reestimado', false, 'motivo', 'em_teste', 'acao_ids', '[]'::jsonb);
  end if;
  c := public._agenda_gestor_corte(p_os, p_hoje, p_agora);
  if coalesce((c ->> 'cortar')::int, 0) = 0 then
    return jsonb_build_object('os', p_os, 'reestimado', false, 'motivo', c ->> 'motivo', 'ficou', c -> 'ficou',
                              'acao_ids', '[]'::jsonb, 'violacoes', c -> 'violacoes');
  end if;
  select coalesce(jsonb_agg(case when i ->> 'op' = 'criar'
           then i || jsonb_build_object('alocacoes', (select jsonb_agg(a || jsonb_build_object('alocacao_id', gen_random_uuid()) order by j)
                                                        from jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)))
           else i end order by k), '[]'::jsonb)
    into v_its
    from jsonb_array_elements(c -> 'itens') with ordinality t(i, k);
  v_pid := gen_random_uuid();
  v_exp := least(p_agora + cf.proposta_validade,
                 coalesce((select min(lower(public.agenda_periodo((a ->> 'dia')::date, a ->> 'turno', a ->> 'presenca')))
                             from jsonb_array_elements(v_its) i, jsonb_array_elements(i -> 'alocacoes') a
                            where i ->> 'op' = 'criar'), p_agora + cf.proposta_validade));
  insert into public.agenda_propostas (id, escopo, periodo, os_alvo, versao_base, modo, estado, itens, fora, carga, textos,
                                       parametros, pontuacao, criada_por, autor, criada_em, expira_em)
  values (v_pid, 'replano',
          daterange((select min((i ->> 'de')::date) from jsonb_array_elements(v_its) i),
                    (select max((i ->> 'ate')::date) from jsonb_array_elements(v_its) i), '[]'),
          array[p_os], cf.versao_plano, 'ligado', 'aberta', v_its, '[]'::jsonb, '{}'::jsonb,
          jsonb_build_object('titulo', 'Mudanças na agenda', 'linhas', jsonb_build_array(c ->> 'texto'), 'fora', '[]'::jsonb,
                             'resumo', c ->> 'texto'),
          jsonb_build_object('p_hoje', p_hoje, 'p_agora', p_agora, 'p_de', null, 'p_ate', null, 'p_os', jsonb_build_array(p_os),
                             'p_restricoes', '{}'::jsonb, 'escopo', 'replano', 'origem', v_por,
                             'gestor', jsonb_build_object('tipo', 'reestimar', 'textos', jsonb_build_object(p_os::text, c ->> 'texto'))),
          null, v_por, p_autor, p_agora, v_exp);
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id,
                                       motivos, criado_em)
  select (a ->> 'alocacao_id')::uuid, p_os, (a ->> 'payee_id')::uuid, (a ->> 'dia')::date, a ->> 'turno', a ->> 'presenca',
         i ->> 'tipo', 'proposta', 'motor', v_pid, coalesce(i -> 'motivos', '[]'::jsonb), p_agora
    from jsonb_array_elements(v_its) with ordinality t(i, k), jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, j)
   where i ->> 'op' = 'criar'
   order by k, j;
  v_a := public.agenda_aplicar(v_pid, null, v_por, p_autor, null, p_hoje, p_agora);
  if not coalesce((v_a ->> 'ok')::boolean, false) then
    perform public.agenda_descartar(v_pid, p_autor, 'o corte do reestimar não passou no aplicar');
    perform public.log_app_error('db', 'agenda: o corte do reestimar não aplicou: ' || coalesce(v_a ->> 'texto', '?'),
                                 'agenda', 'gestor:reestimar', 'warn',
                                 jsonb_build_object('os', p_os, 'proposta', v_pid, 'violacoes', v_a -> 'violacoes',
                                                    'p_hoje', p_hoje, 'p_agora', p_agora));
    return jsonb_build_object('os', p_os, 'reestimado', false, 'motivo', 'nao_aplicou', 'acao_ids', '[]'::jsonb,
                              'violacoes', v_a -> 'violacoes');
  end if;
  return jsonb_build_object('os', p_os, 'reestimado', true, 'cortados', c -> 'cortados', 'ficou', c -> 'ficou',
                            'texto', v_a ->> 'texto', 'acao_ids', coalesce(v_a -> 'acoes', '[]'::jsonb), 'proposta_id', v_pid);
end;
$function$;

comment on function public._agenda_gestor_reestimar(uuid, date, timestamptz, uuid) is
  'Agenda de Produção (Fase 7a, P9; spec §5.9 e §6.4): o reestimar aplicado — o corte de _agenda_gestor_corte numa proposta (escopo replano, criada_por vigia; dono com p_autor, quando o dono escolheu a conta do gestor na pergunta reestimar; modo ligado; parametros.gestor = {tipo reestimar, textos}) e agenda_aplicar (as 14 regras; a ação reestimar, desfazível; o motivo reestimada nas alocações). Inválido no aplicar = descartado, nada muda (app_error_logs gestor:reestimar, warn). Fora de modo_proposta ligado = {reestimado false, motivo em_teste}. {os, reestimado, cortados, ficou, texto, acao_ids, proposta_id, motivo?}. Security definer, sem grant a ninguém.';

-- As perguntas da revisão diária para uma OS (spec §5.9 itens 1 e 3, §6.3):
--   reestimar — a OS com os dias ditos (ou aceitos) pelo dono e uma linha do orçamento criada ou mudada depois que ele disse, e a
--     conta pelo orçamento de agora (os_duracao_sugerida, o realista) diferente: "Nelson (OS-00112): o orçamento mudou depois que
--     você disse 4 dias (agora são R$ 4.200 de mão de obra). Pela minha conta seriam 5,5 dias. Se você não me disser nada até sex
--     30/10 às 18:00, fico com os 4 dias. 1) Fique com 4 dias (recomendo); 2) Use 5,5 dias." Com prazo (_agenda_veto_ate); a
--     opção que vale sem resposta é a 1 (ficar com os dias do dono). Chave reestimar:<os>:<a marca das linhas do orçamento>: o
--     mesmo orçamento não pergunta duas vezes; o orçamento que muda de novo pergunta de novo (a de antes sai).
--   reavaliar — a OS de diagnóstico (service_type ou a linha de maior valor, a régua de os_presenca_do_dono) com todos os
--     meios-dias do plano com resultado, algum feito, e ainda na carteira 1 dia útil depois: "O diagnóstico de Rodrigo (OS-00096)
--     foi feito qua 04/11. 1) Terminou: use *concluiu Rodrigo*; 2) Achou mais serviço: me diga o que é e quantos dias." Sem prazo.
--     Chave reavaliar:<os>:<o dia do diagnóstico>.
-- p_seco = só devolve {os, reestimar: {tipo, chave, texto, opcoes, recomendacao, opcao_padrao, veto_ate, dias_ditos, dias_conta,
-- mo} | null, reavaliar: {…} | null}; senão grava pelo modo da revisão (_agenda_gestor_modo('revisao'); desligado = nada) e a
-- aberta da mesma OS e tipo que não vale mais sai (resolvida). Invoker, sem grant (a revisão e o despacho a chamam).
create or replace function public._agenda_gestor_perguntas_da_revisao(p_os uuid, p_hoje date, p_agora timestamptz, p_seco boolean)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_seco boolean := coalesce(p_seco, false);
  v_modo text;
  v_out  jsonb;
  pl     public.os_planejamento%rowtype;
  v_sug  jsonb;
  v_e    numeric;
  v_mo   numeric;
  v_fp   text;
  v_veto timestamptz;
  v_ate  text;
  v_rot  text;
  v_nome text;
  v_perg text;
  v_ops  jsonb;
  v_rec  smallint;
  v_txt  text;
  v_diag boolean;
  v_n    int;
  v_pend int;
  v_dia  date;
  v_tipo text;
  v_q    jsonb;
  v_id   uuid;
begin
  if p_os is null or p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_perguntas_da_revisao: faltam a OS, o dia ou a hora' using errcode = '22004';
  end if;
  v_out := jsonb_build_object('os', p_os, 'reestimar', null, 'reavaliar', null);
  if not v_seco then
    v_modo := public._agenda_gestor_modo('revisao');
    if v_modo = 'desligado' then
      return v_out || jsonb_build_object('por', 'desligado');
    end if;
  end if;
  select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) into v_nome
    from public.service_orders so left join public.clients cl on cl.id = so.client_id
   where so.id = p_os;
  if v_nome is null then
    return v_out || jsonb_build_object('por', 'sem_os');
  end if;
  v_rot := public._agenda_rotulo_da_os(p_os);

  -- reestimar: os dias do dono e o orçamento mudou depois
  select * into pl from public.os_planejamento x where x.service_order_id = p_os;
  if pl.dias is not null and pl.estimativa_fonte in ('dono', 'aceita') and pl.estimativa_em is not null
     and exists (select 1 from public.service_order_services s
                  where s.service_order_id = p_os
                    and greatest(coalesce(s.created_at, '-infinity'::timestamptz), coalesce(s.updated_at, '-infinity'::timestamptz))
                        > pl.estimativa_em) then
    v_sug := public.os_duracao_sugerida(p_os);
    if coalesce((v_sug ->> 'ok')::boolean, false) and not coalesce((v_sug ->> 'sem_base')::boolean, false) then
      v_e := (v_sug ->> 'dias_realista')::numeric;
      v_mo := (v_sug ->> 'mo')::numeric;
      if v_e is not null and v_e <> pl.dias then
        v_fp := left(md5(coalesce((select string_agg(concat_ws('|', s.id, s.name_snapshot, s.quantity, s.unit_price_snapshot,
                                                               s.line_total), ',' order by s.id)
                                     from public.service_order_services s where s.service_order_id = p_os), '')), 12);
        v_veto := public._agenda_veto_ate(p_agora);
        v_ate := public._dia_curto((v_veto at time zone 'America/Sao_Paulo')::date) || ' às '
                 || to_char(v_veto at time zone 'America/Sao_Paulo', 'HH24:MI');
        v_perg := format('%s: o orçamento mudou depois que você disse %s (agora são %s de mão de obra). Pela minha conta seriam %s. Se você não me disser nada até %s, fico com %s.',
                         v_rot, public._agenda_dias(pl.dias),
                         'R$ ' || translate(to_char(round(coalesce(v_mo, 0)), 'FM999,999,990'), ',', '.'),
                         public._agenda_dias(v_e), v_ate,
                         case when pl.dias >= 2 then 'os ' else '' end || public._agenda_dias(pl.dias));
        v_ops := jsonb_build_array(
          jsonb_build_object('n', 1, 'texto', 'Fique com ' || public._agenda_dias(pl.dias),
                             'efeito', jsonb_build_object('manter', true, 'dias_ditos', trim_scale(pl.dias))),
          jsonb_build_object('n', 2, 'texto', 'Use ' || public._agenda_dias(v_e),
                             'efeito', jsonb_build_object('dias', trim_scale(v_e))));
        v_rec := 1;
        select v_perg || ' ' || string_agg(format('%s) %s%s', o ->> 'n', o ->> 'texto',
                                                  case when (o ->> 'n')::int = v_rec then ' (recomendo)' else '' end),
                                           '; ' order by (o ->> 'n')::int) || '.'
          into v_txt from jsonb_array_elements(v_ops) o;
        v_out := v_out || jsonb_build_object('reestimar', jsonb_build_object(
          'tipo', 'reestimar', 'chave', format('reestimar:%s:%s', p_os, v_fp), 'texto', v_txt, 'opcoes', v_ops,
          'recomendacao', v_rec, 'opcao_padrao', 1, 'veto_ate', v_veto, 'dias_ditos', trim_scale(pl.dias),
          'dias_conta', trim_scale(v_e), 'mo', v_mo));
      end if;
    end if;
  end if;

  -- reavaliar: o diagnóstico foi feito
  v_diag := exists (select 1 from public.service_orders so where so.id = p_os and so.service_type = 'diagnosis')
            or coalesce((select public._agenda_normal(s.name_snapshot) from public.service_order_services s
                          where s.service_order_id = p_os
                          order by s.line_total desc nulls last, s.created_at, s.id limit 1), '') ~ 'diagnost';
  if v_diag then
    select count(*)::int, count(*) filter (where a.resultado is null)::int,
           max(a.dia) filter (where a.resultado in ('cumprido', 'parcial'))
      into v_n, v_pend, v_dia
      from public.agenda_alocacoes a
     where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
    if v_n > 0 and v_pend = 0 and v_dia is not null and public.agenda_somar_du(v_dia, 1) <= p_hoje then
      v_ops := jsonb_build_array(
        jsonb_build_object('n', 1, 'texto', format('Terminou: use *concluiu %s*', v_nome), 'efeito', jsonb_build_object('terminou', true)),
        jsonb_build_object('n', 2, 'texto', 'Achou mais serviço: me diga o que é e quantos dias',
                           'efeito', jsonb_build_object('dizer', true)));
      select format('O diagnóstico de %s foi feito %s. ', v_rot, public._dia_curto(v_dia))
             || string_agg(format('%s) %s', o ->> 'n', o ->> 'texto'), '; ' order by (o ->> 'n')::int) || '.'
        into v_txt from jsonb_array_elements(v_ops) o;
      v_out := v_out || jsonb_build_object('reavaliar', jsonb_build_object(
        'tipo', 'reavaliar', 'chave', format('reavaliar:%s:%s', p_os, v_dia), 'texto', v_txt, 'opcoes', v_ops,
        'recomendacao', null, 'opcao_padrao', null, 'veto_ate', null, 'dia', v_dia));
    end if;
  end if;
  if v_seco then
    return v_out;
  end if;

  -- grava (pelo modo da revisão): a de antes da mesma OS e tipo com outra chave sai; a que não vale mais, também
  foreach v_tipo in array array['reestimar', 'reavaliar'] loop
    v_q := v_out -> v_tipo;
    if v_q is null or jsonb_typeof(v_q) = 'null' then
      update public.agenda_perguntas q
         set estado = 'resolvida', resolvida_motivo = 'não precisa mais: mudou o que falta saber'
       where q.estado = 'aberta' and q.modo = v_modo and q.service_order_id = p_os and q.tipo = v_tipo;
      continue;
    end if;
    update public.agenda_perguntas q
       set estado = 'resolvida',
           resolvida_motivo = case when v_tipo = 'reestimar' then 'o orçamento mudou de novo: perguntei de novo'
                                   else 'mudou o que falta saber: perguntei de novo' end
     where q.estado = 'aberta' and q.modo = v_modo and q.service_order_id = p_os and q.tipo = v_tipo
       and q.chave <> v_q ->> 'chave';
    v_id := public._agenda_gestor_perguntar(v_tipo, v_q ->> 'chave', p_os, v_q ->> 'texto', v_q -> 'opcoes',
                                            (v_q ->> 'recomendacao')::smallint, (v_q ->> 'veto_ate')::timestamptz,
                                            (v_q ->> 'opcao_padrao')::smallint, v_modo, p_agora);
    v_out := jsonb_set(v_out, array[v_tipo], v_q || jsonb_build_object('pergunta_id', v_id, 'modo', v_modo));
  end loop;
  return v_out;
end;
$function$;

comment on function public._agenda_gestor_perguntas_da_revisao(uuid, date, timestamptz, boolean) is
  'Agenda de Produção (Fase 7a, P9; spec §5.9 itens 1 e 3, §6.3): as perguntas da revisão diária para uma OS — reestimar (os dias ditos ou aceitos pelo dono, uma linha do orçamento criada ou mudada depois de estimativa_em, e a conta pelo orçamento de agora, os_duracao_sugerida realista, diferente: "Nelson (OS-00112): o orçamento mudou depois que você disse 4 dias (agora são R$ 4.200 de mão de obra). Pela minha conta seriam 5,5 dias. Se você não me disser nada até sex 30/10 às 18:00, fico com os 4 dias. 1) Fique com 4 dias (recomendo); 2) Use 5,5 dias."; prazo _agenda_veto_ate, opção padrão 1 = os dias do dono; chave reestimar:<os>:<marca das linhas>) e reavaliar (a OS de diagnóstico com todos os meios-dias com resultado, algum feito, ainda na carteira 1 dia útil depois: "O diagnóstico de Rodrigo (OS-00096) foi feito qua 04/11. 1) Terminou: use *concluiu Rodrigo*; 2) Achou mais serviço: me diga o que é e quantos dias."; sem prazo; chave reavaliar:<os>:<dia>). p_seco = só devolve {os, reestimar, reavaliar}; senão grava pelo modo da revisão (desligado = nada; _agenda_gestor_perguntar) e resolve a aberta da mesma OS e tipo que mudou de chave ou não vale mais. Invoker, sem grant.';

-- A revisão diária (spec §5.9; D7-3: "revisa a agenda todo dia"), passo diário da rodada do gestor (o 1º tique de dia útil a
-- partir de gestor_hora_revisao, 16:52; na quinta, depois da publicação das 16:30, só sobra o que ela não pegou). Desligado ou
-- fora de dia útil = {pulado}. Ligado:
--   (1) reestimar — a OS com compromisso e os dias pela estimativa do orçamento (a fonte orcamento): com o plano maior que a conta
--       de agora, o corte dos últimos meios-dias (_agenda_gestor_reestimar); com o plano menor, ela entra no encaixe (2); a OS com
--       os dias do dono e o orçamento mudado depois, a pergunta reestimar (_agenda_gestor_perguntas_da_revisao);
--   (2) encaixar — as OS da carteira sem compromisso de hoje em diante nas classes 1 a 3 (a 3 sem reserva: ela ganha a reserva no
--       dia, sem esperar a publicação da quinta) e as do item (1) com o plano menor, que a vigia não acabou de tentar:
--       _agenda_propor_e_aplicar('os', …, 'vigia') — a onda vale;
--   (3) reavaliar — o diagnóstico feito, a pergunta (sem prazo).
-- Em teste: tudo seco — as regras do gestor ligadas só aqui dentro (agenda.gestor = 'sombra'), o motor sem gravar, o corte e as
-- perguntas só calculados — no diário do dia, agenda_gestor_dia.sombra.revisao (o resto do objeto fica; o "eu marcaria" das
-- 16:52 o mantém). {modo, simulacao, reestimar {cortes, faltando, perguntas}, encaixe {candidatas, marcadas, reservadas, onda,
-- fora, por_os}, reavaliar, perguntas}. Invoker, sem grant: só a rodada do gestor o chama.
create or replace function public._agenda_gestor_revisao(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
#variable_conflict use_variable
declare
  v_modo   text;
  v_sim    boolean;
  r        record;
  v_m      jsonb;
  v_c      jsonb;
  v_q      jsonb;
  v_feito  numeric;
  v_falta  uuid[] := '{}';
  v_cand   uuid[] := '{}';
  v_cortes jsonb := '[]'::jsonb;
  v_faltas jsonb := '[]'::jsonb;
  v_pergs  jsonb := '[]'::jsonb;
  v_r      jsonb := '{}'::jsonb;
  v_p      jsonb := '{}'::jsonb;
  v_os     uuid;
  v_prim   date;
  v_res    text;
  v_mot    text;
  v_it     jsonb;
  v_por    jsonb := '[]'::jsonb;
  v_fora   jsonb := '{}'::jsonb;
  v_marc   int := 0;
  v_resv   int := 0;
  v_onda   boolean := false;
  v_som    jsonb;
  v_cl     int;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_revisao: sem o dia ou a hora' using errcode = '22004';
  end if;
  v_modo := public._agenda_gestor_modo('revisao');
  if v_modo = 'desligado' then
    return jsonb_build_object('pulado', true, 'motivo', 'desligado', 'modo', v_modo);
  end if;
  if not public.agenda_dia_util(p_hoje) then
    return jsonb_build_object('pulado', true, 'motivo', 'não é dia útil', 'modo', v_modo);
  end if;
  v_sim := v_modo <> 'ligado';
  if v_sim then
    -- em teste: as regras do gestor valem só aqui dentro; nada é gravado (só o diário)
    perform set_config('agenda.gestor', 'sombra', true);
  end if;
  begin
    -- (1) reestimar e (3) reavaliar, OS por OS da carteira
    for r in select k.service_order_id as os, k.numero from public.os_carteira(p_hoje) k
              order by k.numero collate "C", k.service_order_id loop
      if public._agenda_os_tem_dia(r.os, p_hoje) then
        v_m := public.agenda_meios_da_os(r.os, p_hoje);
        if v_m ->> 'fonte' = 'orcamento' and (v_m ->> 'total') is not null then
          v_feito := coalesce((v_m ->> 'cumpridos')::numeric, 0) + coalesce((v_m ->> 'vigentes')::numeric, 0);
          if (v_m ->> 'total')::numeric > v_feito then
            v_falta := v_falta || r.os;
            v_faltas := v_faltas || jsonb_build_object('os', r.os, 'numero', r.numero, 'total', (v_m ->> 'total')::int,
                                                       'feitos', v_feito);
          elsif v_feito - (v_m ->> 'total')::numeric >= 1 then
            if v_sim then
              v_c := public._agenda_gestor_corte(r.os, p_hoje, p_agora);
              v_cortes := v_cortes || jsonb_build_object('os', r.os, 'numero', r.numero, 'total', (v_m ->> 'total')::int,
                                                         'feitos', v_feito, 'cortaria', v_c -> 'cortar', 'motivo', v_c -> 'motivo',
                                                         'texto', v_c -> 'texto');
            else
              v_c := public._agenda_gestor_reestimar(r.os, p_hoje, p_agora, null);
              v_cortes := v_cortes || jsonb_build_object('os', r.os, 'numero', r.numero, 'total', (v_m ->> 'total')::int,
                                                         'feitos', v_feito, 'reestimado', v_c -> 'reestimado',
                                                         'cortados', v_c -> 'cortados', 'motivo', v_c -> 'motivo',
                                                         'texto', v_c -> 'texto', 'acao_ids', v_c -> 'acao_ids');
            end if;
          end if;
        end if;
      end if;
      v_q := public._agenda_gestor_perguntas_da_revisao(r.os, p_hoje, p_agora, v_sim);
      if jsonb_typeof(v_q -> 'reestimar') = 'object' then
        v_pergs := v_pergs || jsonb_build_object('os', r.os, 'numero', r.numero, 'tipo', 'reestimar',
                                                 'chave', v_q #>> '{reestimar,chave}', 'texto', v_q #>> '{reestimar,texto}',
                                                 'pergunta_id', v_q #> '{reestimar,pergunta_id}');
      end if;
      if jsonb_typeof(v_q -> 'reavaliar') = 'object' then
        v_pergs := v_pergs || jsonb_build_object('os', r.os, 'numero', r.numero, 'tipo', 'reavaliar',
                                                 'chave', v_q #>> '{reavaliar,chave}', 'texto', v_q #>> '{reavaliar,texto}',
                                                 'pergunta_id', v_q #> '{reavaliar,pergunta_id}');
      end if;
    end loop;

    -- (2) encaixar: o que está pronto e não tem dia (a classe 3 ganha a reserva no dia) e o que o plano tem a menos
    for r in select k.service_order_id as os, k.numero from public.os_carteira(p_hoje) k
              order by k.numero collate "C", k.service_order_id loop
      continue when public._agenda_vigia_ja_tentou(r.os, p_agora);
      if r.os = any (v_falta) then
        v_cand := v_cand || r.os;
        continue;
      end if;
      continue when public._agenda_os_tem_dia(r.os, p_hoje);
      v_cl := (public._agenda_classe_agora(r.os, p_hoje) ->> 'classe')::int;
      continue when v_cl is null or v_cl not in (1, 2, 3);
      continue when v_cl = 3 and exists (select 1 from public.agenda_alocacoes a
                                          where a.service_order_id = r.os and a.estado in ('publicada', 'fixada')
                                            and a.tipo = 'reserva' and a.dia >= p_hoje);
      v_cand := v_cand || r.os;
    end loop;
    if cardinality(v_cand) > 0 then
      if v_sim then
        v_p := public.agenda_propor('os', null, null, v_cand, '{}'::jsonb, false, 'vigia', null, p_hoje, p_agora);
      else
        v_r := public._agenda_propor_e_aplicar('os', v_cand, 'vigia', null, p_hoje, p_agora);
        v_onda := coalesce((v_r ->> 'onda')::boolean, false);
      end if;
      foreach v_os in array v_cand loop
        v_mot := null;
        v_prim := null;
        if v_sim then
          v_it := (select i from jsonb_array_elements(coalesce(v_p -> 'itens', '[]'::jsonb)) i
                    where i ->> 'op' = 'criar' and (i ->> 'os')::uuid = v_os
                    order by i ->> 'tipo' = 'reserva', i ->> 'de' limit 1);
          v_prim := (v_it ->> 'de')::date;
          v_res := case when v_it is null then 'fora' when v_it ->> 'tipo' = 'reserva' then 'reservada' else 'marcada' end;
          if v_it is null then
            v_mot := (select f ->> 'motivo' from jsonb_array_elements(coalesce(v_p -> 'fora', '[]'::jsonb)) f
                       where (f ->> 'os')::uuid = v_os limit 1);
          end if;
        else
          v_it := null;
          v_prim := (select min(a.dia) from public.agenda_alocacoes a
                      where a.service_order_id = v_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                        and a.dia >= p_hoje and a.resultado is null);
          if v_prim is not null then
            v_res := 'marcada';
          elsif exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado in ('publicada', 'fixada')
                         and a.tipo = 'reserva' and a.dia >= p_hoje) then
            v_res := 'reservada';
            v_prim := (select min(a.dia) from public.agenda_alocacoes a where a.service_order_id = v_os
                         and a.estado in ('publicada', 'fixada') and a.tipo = 'reserva' and a.dia >= p_hoje);
          elsif v_onda then
            v_res := 'onda';
          else
            v_res := 'fora';
            v_mot := (select f ->> 'motivo' from jsonb_array_elements(coalesce(v_r -> 'fora', '[]'::jsonb)) f
                       where (f ->> 'os')::uuid = v_os limit 1);
          end if;
        end if;
        if v_res = 'marcada' then v_marc := v_marc + 1; elsif v_res = 'reservada' then v_resv := v_resv + 1; end if;
        if v_res = 'fora' then
          v_fora := v_fora || jsonb_build_object(coalesce(v_mot, 'sem_motivo'),
                                                 coalesce((v_fora ->> coalesce(v_mot, 'sem_motivo'))::int, 0) + 1);
        end if;
        v_por := v_por || jsonb_build_object(
          'os', v_os, 'numero', (select so.service_order_number from public.service_orders so where so.id = v_os),
          'resultado', v_res, 'motivo', v_mot, 'primeiro_dia', v_prim, 'faltava', v_os = any (v_falta),
          'texto', case when v_sim then v_it ->> 'texto' end);
      end loop;
    end if;
  exception when others then
    if v_sim then
      perform set_config('agenda.gestor', '', true);
    end if;
    raise;
  end;
  if v_sim then
    perform set_config('agenda.gestor', '', true);
    select g.sombra into v_som from public.agenda_gestor_dia g where g.dia = p_hoje;
    perform public._agenda_gestor_dia_gravar(p_hoje, 'sombra', coalesce(v_som, '{}'::jsonb) || jsonb_build_object('revisao',
              jsonb_build_object('calculado_em', p_agora, 'cortes', v_cortes, 'faltando', v_faltas, 'perguntas', v_pergs,
                                 'encaixe', v_por)), p_agora);
  end if;
  return jsonb_build_object(
    'modo', v_modo, 'simulacao', v_sim,
    'reestimar', jsonb_build_object('cortes', v_cortes, 'faltando', v_faltas,
                                    'perguntas', (select count(*) from jsonb_array_elements(v_pergs) q where q ->> 'tipo' = 'reestimar')),
    'encaixe', jsonb_build_object('candidatas', coalesce(cardinality(v_cand), 0), 'marcadas', v_marc, 'reservadas', v_resv,
                                  'onda', v_onda, 'onda_pergunta', v_r -> 'pergunta_id', 'proposta_id', coalesce(v_r -> 'proposta_id', v_p -> 'proposta_id'),
                                  'fora', v_fora, 'por_os', v_por),
    'reavaliar', (select count(*) from jsonb_array_elements(v_pergs) q where q ->> 'tipo' = 'reavaliar'),
    'perguntas', v_pergs);
end;
$function$;

comment on function public._agenda_gestor_revisao(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P9; spec §5.9, D7-3): a revisão diária, passo diário do job agenda-gestor (o 1º tique de dia útil a partir de gestor_hora_revisao; na quinta, depois da publicação). Desligado (_agenda_gestor_modo(''revisao'')) ou fora de dia útil = {pulado}. Ligado: (1) reestimar — a OS com compromisso e os dias pela estimativa do orçamento (fonte orcamento): plano maior que a conta = o corte dos últimos meios-dias (_agenda_gestor_reestimar: ação reestimar, desfazível); plano menor = entra no encaixe; os dias do dono com o orçamento mudado depois = a pergunta reestimar (com prazo; padrão: os dias do dono); (2) encaixar — as OS da carteira sem compromisso de hoje em diante nas classes 1 a 3 (a 3 sem reserva vigente) e as do plano menor, não tentadas pela vigia: _agenda_propor_e_aplicar(''os'', …, ''vigia'') — a onda vale; (3) reavaliar — o diagnóstico feito, a pergunta sem prazo. Em teste: tudo seco (agenda.gestor = ''sombra'' só aqui dentro; o motor sem gravar; o corte e as perguntas só calculados) em agenda_gestor_dia.sombra.revisao = {calculado_em, cortes, faltando, perguntas, encaixe} (o resto do objeto fica). {modo, simulacao, reestimar {cortes, faltando, perguntas}, encaixe {candidatas, marcadas, reservadas, onda, onda_pergunta, proposta_id, fora, por_os}, reavaliar, perguntas}. Invoker, sem grant.';

-- ── 2. As funções recriadas (o corpo da definição mais nova; as mudanças marcadas "-- FASE 7: (7a P9") ─────────────────
-- Fora dos blocos nenhuma linha muda (o V7 de supabase/tests/agenda_fase7a_revisao.sql confere). Quem recriar de novo qualquer
-- uma delas copia DESTA migration (fase7-registro.md §2: _agenda_gestor_decidir no 7a P12; agenda_replanejar, agenda_aplicar e
-- _agenda_gestor_sombra, quem vier).

-- agenda_replanejar (de 20261025100300_agenda_fase2_conferencia_vigia.sql)
create or replace function public.agenda_replanejar(p_os uuid[], p_motivo text default null, p_origem text default 'vigia',
                                                    p_hoje date default public._hoje_brt(), p_agora timestamptz default now(),
                                                    p_autor uuid default null)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_r     jsonb;
  v_perg  text;
  -- FASE 7: (7a P9) a escada de reparo antes do motor
  v_f7_cf    public.agenda_config;
  v_f7_rep   jsonb;
  v_f7_its   jsonb := '[]'::jsonb;
  v_f7_cand  uuid[] := '{}';
  v_f7_conta jsonb;
  v_f7_os    uuid;
  v_f7_r     jsonb;
  v_f7_feito jsonb := '[]'::jsonb;
  -- FASE 7: fim
begin
  if coalesce(cardinality(p_os), 0) = 0 then
    raise exception 'Diga que OS replanejar.' using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null then
    raise exception 'Faltam o dia e a hora para replanejar.' using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  -- FASE 7: (7a P9, spec §3.3 d11 e §5.9) a escada de reparo, antes do motor. Com a regra escada e a revisão diária ligadas de
  -- verdade (fora da simulação), e o motivo que não é o do cliente (o dia que o cliente pediu e o desfazer dele vão direto ao
  -- motor), cada OS que perdeu um meio-dia porque quem ia não está mais livre passa antes pela escada: outra pessoa no mesmo
  -- meio-dia, o outro turno do dia, outro dia da mesma semana (_agenda_gestor_reparo). A onda vale também aqui (origem vigia, com a
  -- regra onda): se os consertos juntos mudariam o meio-dia de mais de gestor_k_os OS, ou mexeriam em mais de
  -- gestor_k_dias_avisados dias já avisados, nada é consertado aqui e tudo vai ao motor, que pergunta. A OS consertada inteira
  -- (_agenda_gestor_reparar: a ação reparar) sai da lista do motor; o texto e as ações vão juntos no fim. Sem a regra, a de
  -- antes, byte a byte.
  if public._agenda_gestor_regra('escada') and public._agenda_gestor_modo('revisao') = 'ligado'
     and coalesce(current_setting('agenda.gestor', true), '') <> 'sombra'
     and coalesce(p_motivo, '') not in ('o cliente pediu outro dia', 'desfeito o pedido do cliente') then
    v_f7_cf := public._agenda_cfg();
    foreach v_f7_os in array array(select distinct x from unnest(p_os) x order by 1) loop
      v_f7_rep := public._agenda_gestor_reparo(v_f7_os, p_hoje, p_agora);
      if coalesce((v_f7_rep ->> 'reparavel')::boolean, false) then
        v_f7_its := v_f7_its || (v_f7_rep -> 'itens');
        v_f7_cand := v_f7_cand || v_f7_os;
      end if;
    end loop;
    if cardinality(v_f7_cand) > 0 and p_origem = 'vigia' and public._agenda_gestor_regra('onda') then
      v_f7_conta := public._agenda_gestor_onda_conta(v_f7_its);
      if (v_f7_conta ->> 'os_n')::int > v_f7_cf.gestor_k_os
         or (v_f7_conta ->> 'dias_n')::int > v_f7_cf.gestor_k_dias_avisados then
        v_f7_cand := '{}';
      end if;
    end if;
    foreach v_f7_os in array v_f7_cand loop
      v_f7_r := public._agenda_gestor_reparar(v_f7_os, p_hoje, p_agora);
      if coalesce((v_f7_r ->> 'reparado')::boolean, false) then
        v_f7_feito := v_f7_feito || jsonb_build_array(v_f7_r);
        p_os := array_remove(p_os, v_f7_os);
      end if;
    end loop;
    if jsonb_array_length(v_f7_feito) > 0 and coalesce(cardinality(p_os), 0) = 0 then
      return jsonb_build_object(
        'ok', true, 'modo', 'ligado', 'simulacao', false, 'proposta_id', v_f7_feito -> -1 -> 'proposta_id',
        'texto', (select string_agg(e ->> 'texto', ' ' order by o) from jsonb_array_elements(v_f7_feito) with ordinality t(e, o)),
        'acoes', (select coalesce(jsonb_agg(a order by o, o2), '[]'::jsonb)
                    from jsonb_array_elements(v_f7_feito) with ordinality t(e, o),
                         jsonb_array_elements(e -> 'acao_ids') with ordinality u(a, o2)),
        'publicadas', (select sum((e ->> 'publicadas')::int) from jsonb_array_elements(v_f7_feito) e),
        'canceladas', (select sum((e ->> 'canceladas')::int) from jsonb_array_elements(v_f7_feito) e),
        'perguntas', '[]'::jsonb, 'fora', '[]'::jsonb, 'escada', v_f7_feito, 'motivo', p_motivo);
    end if;
  end if;
  -- FASE 7: fim
  v_r := public._agenda_propor_e_aplicar('replano', array(select distinct x from unnest(p_os) x order by 1), p_origem, p_autor,
                                         p_hoje, p_agora);
  -- FASE 7: (7a P9) o que a escada consertou antes do motor vai junto: as ações, as contas e o texto (o da escada primeiro)
  if jsonb_array_length(v_f7_feito) > 0 then
    v_r := v_r || jsonb_build_object(
      'texto', concat_ws(' ', (select string_agg(e ->> 'texto', ' ' order by o)
                                 from jsonb_array_elements(v_f7_feito) with ordinality t(e, o)),
                         nullif(v_r ->> 'texto', '')),
      'acoes', (select coalesce(jsonb_agg(a order by o, o2), '[]'::jsonb)
                  from jsonb_array_elements(v_f7_feito) with ordinality t(e, o),
                       jsonb_array_elements(e -> 'acao_ids') with ordinality u(a, o2)) || coalesce(v_r -> 'acoes', '[]'::jsonb),
      'publicadas', coalesce((v_r ->> 'publicadas')::int, 0)
                    + (select sum((e ->> 'publicadas')::int) from jsonb_array_elements(v_f7_feito) e),
      'canceladas', coalesce((v_r ->> 'canceladas')::int, 0)
                    + (select sum((e ->> 'canceladas')::int) from jsonb_array_elements(v_f7_feito) e),
      'escada', v_f7_feito);
  end if;
  -- FASE 7: fim
  -- a decisão que ficou com o dono vai junto, com as palavras da pergunta
  select string_agg(q ->> 'texto', ' ' order by q ->> 'chave') into v_perg
    from jsonb_array_elements(coalesce(v_r -> 'perguntas', '[]'::jsonb)) q;
  return v_r || jsonb_build_object('motivo', p_motivo,
    'texto', coalesce(v_r ->> 'texto', '') || coalesce(' Preciso de você: ' || v_perg, ''));
end;
$function$;

comment on function public.agenda_replanejar(uuid[], text, text, date, timestamptz, uuid) is
  'Agenda de Produção (Fase 2, P3): replaneja as OS de p_os pelo motor (agenda_propor replano, persistido). Em ligado aplica o que não é crítico (o cancelamento do que não pode mais acontecer entra; o novo encaixe crítico vira pergunta e o texto a traz); em sombra a proposta fica aberta em modo sombra e as ações que faria entram com executada = false. Origens: vigia, motor, conferencia, dono; p_autor (quem pediu) vale para a porta quando o replano vem do dono. Só service_role. FASE 7 (7a P9, spec §3.3 d11 e §5.9): a escada de reparo antes do motor — com a regra escada do gestor e a revisão diária ligadas de verdade (fora da simulação), e o motivo que não é o do cliente ("o cliente pediu outro dia" e "desfeito o pedido do cliente" vão direto ao motor), cada OS com meio-dia violado porque quem ia não está mais livre passa antes por _agenda_gestor_reparo: outra pessoa no mesmo meio-dia, o outro turno do dia, outro dia da mesma semana, cada conserto pelas 14 regras do motor e tudo ou nada por OS. A onda vale (origem vigia, regra onda): acima de gestor_k_os OS ou de gestor_k_dias_avisados dias avisados, nada é consertado e tudo vai ao motor, que pergunta. A OS consertada (_agenda_gestor_reparar: a ação reparar) sai da lista do motor; com todas consertadas, o motor nem roda; o texto, as ações e as contas juntam a escada (primeiro) e o motor, e a saída ganha escada. Sem a regra, a de antes, byte a byte.';

-- agenda_aplicar (de 20261029100900_agenda_fase6_correcao_calculo.sql)
create or replace function public.agenda_aplicar(p_proposta uuid, p_os uuid[] default null, p_via text default 'motor',
                                                 p_autor uuid default null, p_pergunta uuid default null,
                                                 p_hoje date default public._hoje_brt(), p_agora timestamptz default now())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  cf       public.agenda_config;
  v_p      public.agenda_propostas%rowtype;
  v_cong   date;
  v_sel    jsonb;
  v_viol   jsonb;
  v_nova   jsonb;
  v_via_p  text;
  v_origem text;
  v_va     bigint;
  v_vd     bigint;
  v_os     uuid;
  v_i      jsonb;
  v_a      jsonb;
  v_criadas uuid[];
  v_canc   uuid[];
  v_estado text;
  v_fix    text;
  v_acoes  uuid[] := '{}';
  v_acao   uuid;
  v_tipo   text;
  v_txt    text;
  v_linhas text[] := '{}';
  v_status text;
  v_porta  jsonb;
  v_desf   timestamptz;
  v_n_pub  int := 0;
  v_n_can  int := 0;
  v_motivo text;
  v_atraso int;
  v_tem    boolean;
  v_desfaz boolean := false;
  v_nomes  text[] := '{}';
  v_q      record;
  v_texto  text;
  -- CORREÇÃO FASE 6: (C1) item 3: a presença aprendida de cada OS publicada pela 1ª vez
  v_pa     jsonb;
  -- CORREÇÃO FASE 6: fim
begin
  if p_via is null or p_via not in ('motor', 'vigia', 'conferencia', 'dono', 'tela', 'aprovacao') then
    raise exception 'Caminho desconhecido para aplicar: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  perform set_config('agenda.hoje', p_hoje::text, true);
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  cf := public._agenda_cfg();
  select * into v_p from public.agenda_propostas where id = p_proposta for update;
  if not found then
    raise exception 'Não encontrei esse plano.' using errcode = 'P0002';
  end if;
  if cf.modo_proposta <> 'ligado' or v_p.modo <> 'ligado' then
    return jsonb_build_object('ok', false, 'texto', 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.');
  end if;
  if v_p.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'texto', case v_p.estado
      when 'aplicada' then 'Esse plano já foi publicado.' when 'expirada' then 'Esse plano venceu. Peça de novo que eu monto outro.'
      when 'obsoleta' then 'Esse plano foi trocado por outro.' else 'Esse plano foi descartado.' end);
  end if;
  if p_agora > v_p.expira_em then
    update public.agenda_propostas set estado = 'expirada', motivo_fim = 'passou da validade' where id = p_proposta;
    delete from public.agenda_alocacoes where proposta_id = p_proposta and estado = 'proposta';
    return jsonb_build_object('ok', false, 'texto', 'Esse plano venceu. Peça de novo que eu monto outro.');
  end if;
  if v_p.versao_base <> cf.versao_plano then
    update public.agenda_propostas set estado = 'obsoleta', motivo_fim = 'a agenda mudou' where id = p_proposta;
    delete from public.agenda_alocacoes where proposta_id = p_proposta and estado = 'proposta';
    -- o motor refaz com os mesmos parâmetros e aplica a nova (uma vez só por chamada)
    if p_via = 'motor' and coalesce(current_setting('agenda.reaplicando', true), '') <> 'on' then
      v_nova := public.agenda_propor(v_p.escopo, (v_p.parametros ->> 'p_de')::date, (v_p.parametros ->> 'p_ate')::date,
                  case when v_p.parametros -> 'p_os' is null or jsonb_typeof(v_p.parametros -> 'p_os') <> 'array' then null
                       else array(select x::uuid from jsonb_array_elements_text(v_p.parametros -> 'p_os') x) end,
                  coalesce(v_p.parametros -> 'p_restricoes', '{}'::jsonb), true, v_p.criada_por, v_p.autor, p_hoje, p_agora);
      perform set_config('agenda.reaplicando', 'on', true);
      v_nova := public.agenda_aplicar((v_nova ->> 'proposta_id')::uuid, p_os, p_via, p_autor, p_pergunta, p_hoje, p_agora);
      perform set_config('agenda.reaplicando', 'off', true);
      return v_nova || jsonb_build_object('refeita', true);
    end if;
    return jsonb_build_object('ok', false, 'texto', 'A agenda mudou desde que eu montei: peça de novo que eu refaço.');
  end if;
  if p_pergunta is not null and not exists (select 1 from public.agenda_perguntas q
                                             where q.id = p_pergunta and q.critica and q.estado = 'respondida'
                                               and q.opcao_escolhida is not null) then
    return jsonb_build_object('ok', false, 'texto', 'Essa decisão ainda não foi respondida: nada foi feito.');
  end if;
  v_viol := public.agenda_validar(p_proposta, p_os, p_hoje, p_agora, p_pergunta);
  if jsonb_array_length(v_viol) > 0 then
    return jsonb_build_object('ok', false, 'violacoes', v_viol,
      'texto', 'Não mudei nada: ' || (select string_agg(e ->> 'texto', ' ' order by o) from jsonb_array_elements(v_viol) with ordinality t(e, o)));
  end if;

  v_cong := public.agenda_somar_du(p_hoje, cf.congelamento_du);
  v_sel := public._agenda_itens_escolhidos(v_p.itens, p_os, p_pergunta);
  v_via_p := case p_via when 'tela' then 'tela_agendar' else p_via end;
  v_origem := p_via;
  v_va := cf.versao_plano;

  -- 1. Sai o que sai (o fixado só com a chave, e só no item autorizado).
  for v_i in select e from jsonb_array_elements(v_sel) e where e ->> 'op' = 'cancelar' loop
    for v_a in select x from jsonb_array_elements(v_i -> 'alocacoes') x loop
      if v_a ->> 'estado' = 'fixada' then perform set_config('agenda.mexe_fixado', 'on', true); end if;
      update public.agenda_alocacoes
         set estado = 'cancelada', cancelada_motivo = v_i ->> 'motivo'
       where id = (v_a ->> 'alocacao_id')::uuid and estado in ('publicada', 'fixada');
      perform set_config('agenda.mexe_fixado', 'off', true);
      v_n_can := v_n_can + 1;
    end loop;
  end loop;
  -- CORREÇÃO FASE 6: (C1) item 3: a presença do dono com que cada OS entra no plano pela 1ª vez fica guardada
  -- (os_planejamento.presenca_publicada e _motivo, só quando nulas): é a que o motor usou para montar estes meios-dias. Lida
  -- ANTES de as alocações virarem publicadas (depois, _agenda_presenca_aprendida devolveria a guardada). Só a aprendida
  -- (a regra e o que o dono disse não precisam: continuam onde estão).
  for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_sel) e
               where e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva' order by 1 loop
    v_pa := public._agenda_presenca_aprendida(v_os);
    if v_pa is not null and not coalesce((v_pa ->> 'guardada')::boolean, false) then
      insert into public.os_planejamento (service_order_id, presenca_publicada, presenca_publicada_motivo)
      values (v_os, v_pa ->> 'presenca', v_pa ->> 'motivo')
      on conflict (service_order_id) do update
        set presenca_publicada = excluded.presenca_publicada, presenca_publicada_motivo = excluded.presenca_publicada_motivo
        where public.os_planejamento.presenca_publicada is null;
    end if;
  end loop;
  -- CORREÇÃO FASE 6: fim
  -- 2. Entra o que entra: publicada; fixada no congelado (congelamento) e no pedido do dono (dono).
  for v_i in select e from jsonb_array_elements(v_sel) e where e ->> 'op' = 'criar' loop
    for v_a in select x from jsonb_array_elements(v_i -> 'alocacoes') x loop
      v_fix := case when (v_i ->> 'fixar_dono')::boolean and p_via in ('dono', 'tela', 'aprovacao') then 'dono'
                    when (v_a ->> 'dia')::date <= v_cong then 'congelamento' end;
      v_estado := case when v_fix is null then 'publicada' else 'fixada' end;
      update public.agenda_alocacoes
         set estado = v_estado, fixado_por = v_fix
       where id = (v_a ->> 'alocacao_id')::uuid and proposta_id = p_proposta and estado = 'proposta';
      if not found then
        raise exception 'agenda_aplicar: a alocação % da proposta sumiu.', v_a ->> 'alocacao_id';
      end if;
      v_n_pub := v_n_pub + 1;
    end loop;
  end loop;
  -- o que a proposta trazia e não foi escolhido sai (nunca vigorou)
  delete from public.agenda_alocacoes where proposta_id = p_proposta and estado = 'proposta';
  v_vd := (public._agenda_cfg()).versao_plano;

  -- 3. Por OS tocada: o status pela porta, o espelho das datas, a duração aceita e a ação (com o desfazer).
  for v_os in select distinct (e ->> 'os')::uuid from jsonb_array_elements(v_sel) e order by 1 loop
    v_criadas := array(select (x ->> 'alocacao_id')::uuid
                         from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar');
    v_canc := array(select (x ->> 'alocacao_id')::uuid
                      from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                     where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar');
    select so.status into v_status from public.service_orders so where so.id = v_os;
    v_tem := public._agenda_os_tem_dia(v_os, p_hoje);
    v_porta := null;
    if v_tem and v_status in ('open', 'approved', 'awaiting_parts', 'awaiting_client')
       and exists (select 1 from jsonb_array_elements(v_sel) e
                    where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva') then
      v_porta := public.os_transicionar_status(v_os, 'scheduled', v_via_p, null, p_autor, null, p_hoje, p_agora);
    elsif not v_tem and v_status = 'scheduled' then
      v_motivo := (select e ->> 'motivo' from jsonb_array_elements(v_sel) e
                    where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' order by e ->> 'motivo' = 'material' desc limit 1);
      v_porta := public.os_transicionar_status(v_os, case when v_motivo = 'material' then 'awaiting_parts' else 'approved' end,
                   case when p_via in ('motor', 'vigia') then p_via else 'dono' end, null, p_autor, null, p_hoje, p_agora);
    end if;
    perform public._agenda_espelhar_datas(v_os, p_hoje);
    -- a duração só sugerida que o dono pediu para marcar fica aceita
    if p_via in ('dono', 'tela', 'aprovacao') then
      insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, atualizado_por)
      select v_os, (e ->> 'dias')::numeric, 'aceita', p_agora, p_autor
        from jsonb_array_elements(v_sel) e
       where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar' and e ->> 'tipo' <> 'reserva' and e ->> 'fonte' = 'sugerida'
         and (e ->> 'dias') is not null
       limit 1
      on conflict (service_order_id) do update
        set dias = excluded.dias, estimativa_fonte = 'aceita', estimativa_em = excluded.estimativa_em,
            atualizado_por = excluded.atualizado_por, atualizado_em = now()
        where public.os_planejamento.dias is null;
    end if;

    v_tipo := case
      when v_p.escopo = 'semana' and cardinality(v_criadas) > 0 then 'publicar'
      when cardinality(v_criadas) > 0 and cardinality(v_canc) > 0
           and not exists (select 1 from jsonb_array_elements(v_sel) e
                            where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and e ->> 'motivo' <> 'promovida') then 'promover_reserva'
      when cardinality(v_criadas) > 0 and cardinality(v_canc) > 0 then 'mover'
      when cardinality(v_criadas) > 0 then 'criar'
      when not exists (select 1 from jsonb_array_elements(v_sel) e
                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and e ->> 'motivo' <> 'condicao_vencida') then 'soltar_reserva'
      else 'cancelar' end;
    v_motivo := (select string_agg(distinct e ->> 'motivo', ', ') from jsonb_array_elements(v_sel) e
                  where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar');
    v_atraso := (select max((e ->> 'atraso_du')::int) from jsonb_array_elements(v_sel) e
                  where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar');
    v_txt := case
      when v_tipo = 'mover' then
        format('%s: de %s para %s%s.', public._agenda_rotulo_da_os(v_os),
               public._agenda_dias_texto(array(select (x ->> 'dia')::date from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                                where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar')),
               public._agenda_dias_texto(array(select (x ->> 'dia')::date from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                                where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar')),
               coalesce(' — ' || (select regexp_replace(e ->> 'texto', '^.* — ', '') from jsonb_array_elements(v_sel) e
                                   where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar' and (e ->> 'violada')::boolean limit 1), '')
               -- o dia pedido pelo dono antes de o material estar garantido: o aviso vai junto
               || coalesce(' — mas ' || (select e ->> 'aviso_material' from jsonb_array_elements(v_sel) e
                                          where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar' and e ->> 'aviso_material' is not null
                                          limit 1), ''))
      else (select string_agg(rtrim(e ->> 'texto', '.'), '; ' order by e ->> 'op' = 'cancelar', e ->> 'de')
              from jsonb_array_elements(v_sel) e where (e ->> 'os')::uuid = v_os) || '.' end;
    v_txt := regexp_replace(v_txt, '\.\.$', '.');
    -- FASE 7: (7a P9, spec §5.9 e §6.4) a proposta que o gestor monta sem o motor (a escada de reparo e o corte do reestimar)
    -- diz o tipo da ação (reparar, reestimar) e a frase dela, por OS, em parametros.gestor. Sem isso na proposta (o motor, a
    -- tela, o dono), nada muda.
    if v_p.parametros #>> '{gestor,tipo}' in ('reparar', 'reestimar') then
      v_tipo := v_p.parametros #>> '{gestor,tipo}';
      v_txt := coalesce(v_p.parametros #>> array['gestor', 'textos', v_os::text], v_txt);
    end if;
    -- FASE 7: fim
    v_desf := case when p_via in ('tela', 'aprovacao') then null
                   else least(p_agora + cf.desfazer_validade,
                              coalesce((select min(lower(a.periodo)) from public.agenda_alocacoes a where a.id = any (v_criadas)),
                                       p_agora + cf.desfazer_validade)) end;
    if v_desf is not null then
      v_desfaz := true;
      v_nomes := v_nomes || coalesce((select public._agenda_nome_curto(cl.name) from public.service_orders so
                                        join public.clients cl on cl.id = so.client_id where so.id = v_os), '');
    end if;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, proposta_id, pergunta_id,
                                     critica, versao_antes, versao_depois, alocacoes_criadas, alocacoes_canceladas,
                                     status_antes, status_depois, atraso_du, antes, depois, texto, motivo, autor, desfazivel_ate)
    values (clock_timestamp(), p_hoje, true, v_origem, v_tipo, v_os, array[v_os], p_proposta, p_pergunta,
            p_pergunta is not null, v_va, v_vd, v_criadas, v_canc,
            v_status, (select so.status from public.service_orders so where so.id = v_os), case when v_atraso > 0 then v_atraso end,
            jsonb_build_object('alocacoes', (select coalesce(jsonb_agg(x order by x ->> 'dia', x ->> 'turno'), '[]'::jsonb)
                                               from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                              where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'cancelar'),
                               'fim', (select min(e ->> 'fim_antes') from jsonb_array_elements(v_sel) e
                                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar')),
            jsonb_build_object('alocacoes', (select coalesce(jsonb_agg(x order by x ->> 'dia', x ->> 'turno'), '[]'::jsonb)
                                               from jsonb_array_elements(v_sel) e, jsonb_array_elements(e -> 'alocacoes') x
                                              where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar'),
                               'fim', (select max(e ->> 'fim_depois') from jsonb_array_elements(v_sel) e
                                        where (e ->> 'os')::uuid = v_os and e ->> 'op' = 'criar'),
                               'porta', v_porta),
            left(v_txt, 400), left(v_motivo, 200), p_autor, v_desf)
    returning id into v_acao;
    update public.agenda_alocacoes set acao_id = v_acao where id = any (v_criadas);
    v_acoes := v_acoes || v_acao;
    v_linhas := v_linhas || v_txt;
  end loop;

  update public.agenda_propostas
     set estado = 'aplicada', decidida_em = p_agora,
         decidida_via = case p_via when 'tela' then 'tela' when 'aprovacao' then 'aprovacao' when 'dono' then null else 'motor' end,
         decidida_por = p_autor,
         itens = (select coalesce(jsonb_agg(case when exists (select 1 from jsonb_array_elements(v_sel) s where s = i)
                                                 then i || '{"aplicado": true}'::jsonb else i end order by k), '[]'::jsonb)
                    from jsonb_array_elements(v_p.itens) with ordinality t(i, k))
   where id = p_proposta;

  v_texto := case
    when cardinality(v_linhas) = 0 then 'Nada a mudar na agenda.'
    when v_p.escopo = 'semana' then format('Publiquei a %s: %s',
                                            lower(left(coalesce(v_p.textos ->> 'titulo', 'Semana'), 1))
                                            || substr(coalesce(v_p.textos ->> 'titulo', 'Semana'), 2),
                                            array_to_string(v_linhas, ' '))
    else 'Mudei: ' || array_to_string(v_linhas, ' ') end
    || case when not v_desfaz then ''
            when v_p.escopo = 'semana' then ' *desfaz semana* volta como estava.'
            when cardinality(v_nomes) = 1 then format(' *desfaz %s* volta como estava.', v_nomes[1])
            else ' *desfaz* e o nome volta como estava.' end;
  return jsonb_build_object('ok', true, 'texto', v_texto, 'acoes', to_jsonb(v_acoes), 'publicadas', v_n_pub, 'canceladas', v_n_can,
                            'fora', v_p.fora, 'proposta_id', p_proposta);
end;
$function$;

comment on function public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz) is
  'Agenda de Produção (Fase 2, P2): aplica uma proposta, só com modo_proposta ligado (fora dele: "ainda está em teste", nada muda). Trava o plano; proposta fechada, vencida (expirada) ou de outra versão do plano (obsoleta; com p_via motor, refaz com os mesmos parâmetros e aplica a nova, uma vez) não aplica. agenda_validar não vazia = recusa com a lista. Itens: os das OS de p_os (todas, sem lista), sem os críticos — esses só com p_pergunta respondida (e então toda ação sai critica = true com pergunta_id). Cancelar → cancelada (o fixado com agenda.mexe_fixado); criar → publicada, fixada no congelado (congelamento) e no pedido do dono pela tela, aprovação ou *grava* (dono); o que não foi escolhido é apagado. Por OS: a porta (agendada quando tem dia; de volta quando ficou sem nenhum, aguardando peças se foi o material), o espelho das datas, a duração só sugerida que o dono pediu fica aceita, e uma linha em agenda_acoes (publicar/criar/mover/cancelar/promover_reserva/soltar_reserva) com antes/depois, a frase e o desfazer (desfazer_validade, até o 1º meio-dia começar; não na tela nem na aprovação). Vias: motor, vigia, conferencia, dono, tela, aprovacao. CORREÇÃO FASE 6 (C1, item 3): antes de publicar, guarda em os_planejamento.presenca_publicada/_motivo (só quando nulas) a presença aprendida com que cada OS entra no plano pela 1ª vez. FASE 7 (7a P9, spec §5.9 e §6.4): a proposta que o gestor monta sem o motor (a escada de reparo, _agenda_gestor_reparar; o corte do reestimar, _agenda_gestor_reestimar) traz em parametros.gestor o tipo da ação (reparar, reestimar) e a frase dela por OS: a ação sai com esse tipo e essa frase (o resto do aplicar não muda: as 14 regras, a porta, o desfazer). Sem parametros.gestor, a de antes, byte a byte.';

-- _agenda_gestor_sombra (de 20261031100600_agenda_fase7a_rodada.sql)
create or replace function public._agenda_gestor_sombra(p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 set search_path to 'public'
as $function$
declare
  c_max    constant int := 640;
  v_modos  jsonb;
  v_cart   uuid[];
  v_p      jsonb := '{}'::jsonb;
  v_itens  jsonb := '[]'::jsonb;
  v_res    jsonb := '[]'::jsonb;
  v_fora   jsonb := '[]'::jsonb;
  v_perg   jsonb := '[]'::jsonb;
  v_marc   uuid[] := '{}';
  v_pos    uuid[] := '{}';
  v_os     uuid;
  x        jsonb;
  q        jsonb;
  v_cmp    jsonb;
  v_ti     text[];
  v_tp     text[];
  v_tf     text[];
  v_cab    text;
  v_txt    text;
  v_nf     int;
  ki       int;
  kp       int;
  v_som    jsonb;
begin
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_sombra: sem o dia ou a hora' using errcode = '22004';
  end if;
  v_modos := jsonb_build_object('marcar', public._agenda_gestor_modo('marcar'), 'encaixe', public._agenda_gestor_modo('encaixe'),
                                'revisao', public._agenda_gestor_modo('revisao'));
  if not ('sombra' = any (array[v_modos ->> 'marcar', v_modos ->> 'encaixe', v_modos ->> 'revisao'])) then
    return jsonb_build_object('pulado', true, 'motivo', 'nenhum modo do gestor em teste', 'modos', v_modos);
  end if;
  v_cart := array(select k.service_order_id from public.os_carteira(p_hoje) k
                   where not public._agenda_os_tem_dia(k.service_order_id, p_hoje)
                   order by k.numero, k.service_order_id);

  -- a simulação: as regras do gestor valem só aqui dentro
  perform set_config('agenda.gestor', 'sombra', true);
  begin
    if cardinality(v_cart) > 0 then
      v_p := public.agenda_propor('os', null, null, v_cart, '{}'::jsonb, false, 'vigia', null, p_hoje, p_agora);
    end if;
    for x in select e from jsonb_array_elements(coalesce(v_p -> 'itens', '[]'::jsonb)) e
              where e ->> 'op' = 'criar'
              order by (e ->> 'de')::date, e ->> 'numero' loop
      v_os := (x ->> 'os')::uuid;
      v_marc := v_marc || v_os;
      if x ->> 'tipo' = 'reserva' then
        v_res := v_res || jsonb_build_object('os', v_os, 'numero', x ->> 'numero', 'cliente', x ->> 'cliente_curto',
                                             'de', x ->> 'de', 'ate', x ->> 'ate', 'reserva_de', x ->> 'reserva_de',
                                             'pessoas', public._agenda_gestor_pessoas(x -> 'alocacoes'));
        continue;
      end if;
      v_cmp := public._agenda_gestor_compra_da_os(v_os, p_hoje);
      v_itens := v_itens || jsonb_build_object(
        'os', v_os, 'numero', x ->> 'numero', 'cliente', x ->> 'cliente_curto', 'de', x ->> 'de', 'ate', x ->> 'ate',
        'dias', x -> 'dias', 'pessoas', public._agenda_gestor_pessoas(x -> 'alocacoes'), 'fonte', x ->> 'fonte',
        'meios', (select count(*) from jsonb_array_elements(x -> 'alocacoes') a where coalesce(a ->> 'presenca', 'turno') = 'turno'),
        'compre_ate', case when (v_cmp ->> 'n')::int > 0 then v_cmp ->> 'compre_ate' end,
        'itens_a_comprar', (v_cmp ->> 'n')::int,
        'alerta_dupla', public.os_duracao_sugerida(v_os) -> 'alerta_dupla');
    end loop;
    -- as perguntas que o gestor faria antes de marcar (só das que ele não marcaria)
    foreach v_os in array coalesce(v_cart, '{}'::uuid[]) loop
      continue when v_os = any (v_marc);
      q := public._agenda_gestor_perguntas_da_os(v_os, p_hoje, p_agora, true);
      if q ? 'chave' then
        v_pos := v_pos || v_os;
        v_perg := v_perg || jsonb_build_object(
          'os', v_os, 'numero', (select so.service_order_number from public.service_orders so where so.id = v_os),
          'cliente', (select public._agenda_nome_curto(cl.name) from public.service_orders so
                        join public.clients cl on cl.id = so.client_id where so.id = v_os),
          'tipo', q ->> 'tipo', 'chave', q ->> 'chave', 'variante', q ->> 'variante', 'curto', q ->> 'curto',
          'proposta_dias', q -> 'proposta_dias', 'veto_ate', q -> 'veto_ate', 'texto', q ->> 'texto');
      end if;
    end loop;
  exception when others then
    perform set_config('agenda.gestor', '', true);
    raise;
  end;
  perform set_config('agenda.gestor', '', true);

  -- quem fica de fora (na carteira, sem a pergunta do gestor): o porquê do motor numa palavra
  select coalesce(jsonb_agg(jsonb_build_object('os', f ->> 'os', 'numero', f ->> 'numero', 'cliente', f ->> 'cliente_curto',
                                               'motivo', f ->> 'motivo', 'grupo', public._agenda_gestor_motivo_texto(f ->> 'motivo'),
                                               'texto', f ->> 'texto') order by o), '[]'::jsonb)
    into v_fora
    from jsonb_array_elements(coalesce(v_p -> 'fora', '[]'::jsonb)) with ordinality t(f, o)
   where f ->> 'motivo' is distinct from 'fora_da_carteira'
     and not ((f ->> 'os')::uuid = any (v_pos)) and not ((f ->> 'os')::uuid = any (v_marc));
  select coalesce(jsonb_agg(e order by e ->> 'numero' desc), '[]'::jsonb) into v_perg from jsonb_array_elements(v_perg) e;

  -- o texto do fechamento (spec §6.1), até 640 caracteres: até 3 marcadas e até 3 perguntas ("e mais N")
  v_ti := array(select format('%s %s, %s (%s%s%s)', e ->> 'cliente',
                              case when e ->> 'de' = e ->> 'ate' then 'em ' else 'de ' end
                                || public._agenda_gestor_faixa((e ->> 'de')::date, (e ->> 'ate')::date),
                              e ->> 'pessoas', public._agenda_dias((e ->> 'dias')::numeric),
                              case e ->> 'fonte' when 'orcamento' then ', estimativa minha' when 'dono' then ', você disse'
                                                 when 'aceita' then ', você disse' else '' end,
                              case when e ->> 'compre_ate' is not null
                                   then format('; compre até %s: %s',
                                               case when (e ->> 'compre_ate')::date <= p_hoje then 'hoje'
                                                    else public._dia_curto((e ->> 'compre_ate')::date) end,
                                               public._agenda_itens((e ->> 'itens_a_comprar')::int))
                                   else '' end)
                  from jsonb_array_elements(v_itens) with ordinality t(e, o) order by o);
  v_tp := array(select format('%s (%s)', e ->> 'cliente', e ->> 'curto')
                  from jsonb_array_elements(v_perg) with ordinality t(e, o) order by o);
  v_nf := jsonb_array_length(v_fora);
  v_tf := array(select g.grupo || case when g.n > 1 then format(' (%s)', g.n) else '' end
                  from (select f ->> 'grupo' as grupo, count(*) as n from jsonb_array_elements(v_fora) f group by f ->> 'grupo') g
                 order by public._agenda_gestor_motivo_ordem(g.grupo), g.grupo);
  <<curto>>
  for kp in reverse least(3, cardinality(v_tp)) .. 0 loop
    for ki in reverse least(3, cardinality(v_ti)) .. least(1, cardinality(v_ti)) loop
      v_cab := case when cardinality(v_ti) = 0 then 'Agenda em teste (nada mudou): eu não marcaria nada agora.'
                    else 'Agenda em teste (nada mudou): eu marcaria assim — ' || array_to_string(v_ti[1:ki], '; ')
                         || case when cardinality(v_ti) > ki then format(' (e mais %s)', cardinality(v_ti) - ki) else '' end || '.' end;
      v_txt := v_cab
        || case when jsonb_array_length(v_res) > 0
                then format(' Reservaria: %s.', public._agenda_lista(array(select e ->> 'cliente' from jsonb_array_elements(v_res) e), 3))
                else '' end
        || case when cardinality(v_tp) > 0 and kp > 0
                then ' Antes de marcar eu perguntaria: ' || array_to_string(v_tp[1:kp], ', ')
                     || case when cardinality(v_tp) > kp then format(' (e mais %s)', cardinality(v_tp) - kp) else '' end || '.'
                when cardinality(v_tp) > 0 then format(' Antes de marcar eu perguntaria sobre %s.',
                                                       public._agenda_plural(cardinality(v_tp), 'serviço', 'serviços'))
                else '' end
        || case when v_nf > 0 then format(' Continuam fora %s: %s.', v_nf, array_to_string(v_tf, ', ')) else '' end
        || ' *agenda gestor* mostra tudo.';
      exit curto when char_length(v_txt) <= c_max;
    end loop;
  end loop;
  v_txt := public._agenda_corta(v_txt, c_max);

  v_som := jsonb_build_object('calculado_em', p_agora, 'modos', v_modos, 'itens', v_itens, 'reservas', v_res, 'fora', v_fora,
                              'perguntas', v_perg);
  v_som := v_som || jsonb_build_object('md5', md5(jsonb_build_object(
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('os', e -> 'os', 'de', e -> 'de', 'ate', e -> 'ate', 'dias', e -> 'dias',
                                                           'pessoas', e -> 'pessoas') order by o), '[]'::jsonb)
                from jsonb_array_elements(v_itens) with ordinality t(e, o)),
    'reservas', (select coalesce(jsonb_agg(e -> 'os' order by o), '[]'::jsonb) from jsonb_array_elements(v_res) with ordinality t(e, o)),
    'fora', (select coalesce(jsonb_agg(jsonb_build_array(e -> 'os', e -> 'motivo') order by o), '[]'::jsonb)
               from jsonb_array_elements(v_fora) with ordinality t(e, o)),
    'perguntas', (select coalesce(jsonb_agg(e -> 'chave' order by o), '[]'::jsonb)
                    from jsonb_array_elements(v_perg) with ordinality t(e, o)))::text));
  -- FASE 7: (7a P9) o que a revisão diária em teste calculou no dia (sombra.revisao, gravado antes, no mesmo tique) fica
  v_som := v_som || coalesce((select jsonb_build_object('revisao', g.sombra -> 'revisao') from public.agenda_gestor_dia g
                               where g.dia = p_hoje and g.sombra ? 'revisao'), '{}'::jsonb);
  -- FASE 7: fim
  perform public._agenda_gestor_dia_gravar(p_hoje, 'sombra', v_som, p_agora);
  perform public._agenda_gestor_dia_gravar(p_hoje, 'texto_sombra', to_jsonb(v_txt), p_agora);
  return jsonb_build_object('itens', jsonb_array_length(v_itens), 'reservas', jsonb_array_length(v_res), 'fora', v_nf,
                            'perguntas', jsonb_array_length(v_perg), 'md5', v_som ->> 'md5', 'texto', v_txt);
end;
$function$;

comment on function public._agenda_gestor_sombra(date, timestamptz) is
  'Agenda de Produção (Fase 7a, P7; spec §3.1 item 3, §5.7, §6.1): o "eu marcaria assim" — com algum dos modos marcar, encaixe ou revisao em sombra (senão {pulado}), o mesmo motor com as regras do gestor ligadas só dentro da função (agenda.gestor = ''sombra''; desligada no fim e no erro): agenda_propor(''os'', a carteira sem compromisso de hoje em diante, persistir false) e as perguntas do gestor em modo seco. Grava no diário do dia: sombra = {calculado_em, modos, itens [{os, numero, cliente, de, ate, dias, pessoas, fonte, meios, compre_ate, itens_a_comprar, alerta_dupla}], reservas, fora [{os, numero, cliente, motivo, grupo, texto}], perguntas [{os, numero, cliente, tipo, chave, variante, curto, proposta_dias, veto_ate, texto}], md5} e texto_sombra ("Agenda em teste (nada mudou): eu marcaria assim — Lenine de ter 03 a ter 10/11, Roberto e João (6 dias, estimativa minha); … Antes de marcar eu perguntaria: Giancarlo (10 diárias pela estimativa), … Continuam fora 6: esperando o cliente (3), … *agenda gestor* mostra tudo.", ≤ 640). Nada mais é gravado (a simulação não grava alocação, proposta, ação nem pergunta). Invoker, sem grant: só a rodada do gestor a chama. FASE 7 (7a P9): o diário reescrito mantém o sombra.revisao que a revisão diária em teste (_agenda_gestor_revisao, o passo anterior do mesmo tique) gravou no dia; o md5 e o texto não mudam.';

-- _agenda_gestor_decidir (de 20261031100700_agenda_fase7a_encaixe.sql)
create or replace function public._agenda_gestor_decidir(p_pergunta uuid, p_opcao smallint, p_autor uuid, p_via text,
                                                         p_trecho text, p_hoje date, p_agora timestamptz)
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  c_tipos constant text[] := array['situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa', 'onda', 'sabado',
                                   'bem_livre', 'compre_ate', 'sinal'];
  v_prazo boolean := p_via = 'prazo';
  v_q     public.agenda_perguntas%rowtype;
  v_opc   jsonb;
  v_ef    jsonb;
  v_nome  text;
  v_agora jsonb;
  v_mot   text;
  v_ate   text;
  v_txt   text;
  v_acao  uuid;
  -- FASE 7: (7a P8) a onda
  v_f7_ap   text;
  v_f7_pr   public.agenda_propostas%rowtype;
  v_f7_np   jsonb;
  v_f7_oss  uuid[];
  v_f7_r    jsonb;
  -- FASE 7: fim
  -- FASE 7: (7a P9) a revisão diária: reestimar e reavaliar
  v_f9_rq   jsonb;
  v_f9_pl   public.os_planejamento%rowtype;
  v_f9_m    jsonb;
  v_f9_ft   numeric;
  v_f9_aj   jsonb;
  v_f9_dt   text;
  v_f9_ant  jsonb;
  v_f9_dep  jsonb;
  v_f9_cf   public.agenda_config;
  -- FASE 7: fim
begin
  if p_via is null or p_via not in ('whatsapp', 'painel', 'tela', 'prazo') then
    raise exception 'Canal desconhecido para a decisão: "%".', coalesce(p_via, '') using errcode = '22023';
  end if;
  if p_hoje is null or p_agora is null then
    raise exception '_agenda_gestor_decidir: sem o dia ou a hora' using errcode = '22004';
  end if;
  perform pg_advisory_xact_lock(hashtext('agenda_plano'));
  select * into v_q from public.agenda_perguntas where id = p_pergunta for update;
  if not found then
    raise exception 'Não encontrei essa pergunta.' using errcode = 'P0002';
  end if;
  if not (v_q.tipo = any (c_tipos)) then
    raise exception '_agenda_gestor_decidir: a pergunta "%" não é do gestor da agenda', v_q.tipo using errcode = '22023';
  end if;
  if v_q.estado <> 'aberta' then
    return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa pergunta já foi respondida ou resolvida.');
  end if;
  if v_q.modo <> 'ligado' or coalesce(public._agenda_modo_da_pergunta(v_q.tipo, v_q.chave), 'desligado') <> 'ligado' then
    return jsonb_build_object('ok', false, 'gestor', true,
                              'texto', 'O gestor da agenda está em teste: mostro o que eu faria, mas não mudo nada.');
  end if;
  -- FASE 7: (7a P8, spec §5.8 e §6.3) a onda — 1) faço tudo como montei; 2) mudo só o de hoje e amanhã (as OS de evento real); 3)
  -- não mudo nada. A conta é refeita agora pelo motor com os parâmetros da proposta da pergunta, só se a agenda não mudou desde
  -- ela (a mesma versão do plano: o motor dá o mesmo); se mudou, a pergunta resolve e a rodada seguinte refaz a conta (e pergunta
  -- de novo se ainda for muita mudança). O que entra vai com a pergunta (a ação crítica, com pergunta_id). Nunca tem prazo.
  if v_q.tipo = 'onda' then
    if v_prazo then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa pergunta não tem prazo: nada mudou.');
    end if;
    select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
    if v_opc is null then
      return jsonb_build_object('ok', false, 'gestor', true,
        'texto', 'Essa opção não existe. As opções são: '
                 || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                       from jsonb_array_elements(v_q.opcoes) o) || '.');
    end if;
    v_f7_ap := v_opc #>> '{efeito,aplicar}';
    if v_f7_ap is null or v_f7_ap not in ('tudo', 'so_evento_real', 'nada') then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
    end if;
    select * into v_f7_pr from public.agenda_propostas pr where pr.id = v_q.proposta_id;
    if v_f7_ap = 'nada' then
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      if v_f7_pr.id is not null and v_f7_pr.estado = 'aberta' then
        perform public.agenda_descartar(v_f7_pr.id, p_autor, 'você disse: não mudo nada');
      end if;
      return jsonb_build_object('ok', true, 'gestor', true,
        'texto', 'Combinado: não mudei nada. Me diga o que mudar (*agenda plano* mostra o que está marcado).');
    end if;
    if v_f7_pr.id is null or v_q.versao_base is distinct from (public._agenda_cfg()).versao_plano then
      update public.agenda_perguntas
         set estado = 'resolvida', resolvida_motivo = 'a agenda mudou desde a pergunta: refaço a conta na próxima rodada'
       where id = v_q.id;
      return jsonb_build_object('ok', false, 'gestor', true, 'mudou', true,
        'texto', 'A agenda mudou desde a pergunta: não mudei nada agora. Na próxima rodada eu refaço a conta e, se ainda for muita mudança, te pergunto de novo.');
    end if;
    begin
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      v_f7_np := public.agenda_propor(v_f7_pr.escopo, (v_f7_pr.parametros ->> 'p_de')::date, (v_f7_pr.parametros ->> 'p_ate')::date,
                   case when jsonb_typeof(v_f7_pr.parametros -> 'p_os') = 'array'
                        then array(select x::uuid from jsonb_array_elements_text(v_f7_pr.parametros -> 'p_os') x) end,
                   coalesce(v_f7_pr.parametros -> 'p_restricoes', '{}'::jsonb), true, 'dono', p_autor, p_hoje, p_agora);
      if not coalesce((v_f7_np ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0098', message = coalesce(v_f7_np ->> 'texto', 'não deu');
      end if;
      v_f7_oss := case when v_f7_ap = 'so_evento_real'
                       then array(select distinct (i ->> 'os')::uuid from jsonb_array_elements(v_f7_np -> 'itens') i
                                   where i ->> 'op' = 'criar' and coalesce((i ->> 'evento_real')::boolean, false) order by 1) end;
      if v_f7_ap = 'so_evento_real' and cardinality(v_f7_oss) = 0 then
        perform public.agenda_descartar((v_f7_np ->> 'proposta_id')::uuid, p_autor, 'nada de hoje e amanhã para mudar');
        return jsonb_build_object('ok', true, 'gestor', true,
                                  'texto', 'Não havia nada de hoje e amanhã para mudar: não mudei nada.');
      end if;
      v_f7_r := public.agenda_aplicar((v_f7_np ->> 'proposta_id')::uuid, v_f7_oss, 'dono', p_autor, v_q.id, p_hoje, p_agora);
      if not coalesce((v_f7_r ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0098', message = coalesce(v_f7_r ->> 'texto', 'não deu');
      end if;
    exception when sqlstate 'P0098' then
      -- nada fica: a pergunta continua aberta
      return jsonb_build_object('ok', false, 'gestor', true,
                                'texto', 'Não consegui fazer o que você escolheu: ' || sqlerrm || ' Nada mudou.');
    end;
    return jsonb_build_object('ok', true, 'gestor', true, 'texto', 'Feito: ' || (v_f7_r ->> 'texto'),
                              'acoes', v_f7_r -> 'acoes', 'proposta_id', v_f7_np ->> 'proposta_id');
  end if;
  -- FASE 7: fim
  -- FASE 7: (7a P9, spec §5.9 e §6.3) as perguntas da revisão diária.
  --   reavaliar (sem prazo): 1) "Use *concluiu Rodrigo*."; 2) "Me diga o que mais tem para fazer e quantos dias" — as duas
  --     respondem a pergunta; nada aqui conclui nem marca.
  --   reestimar: só se a pergunta que eu faria agora para a OS ainda é esta (a mesma chave: os dias do dono e o mesmo
  --     orçamento); senão ela resolve e nada muda. 1) fico com os dias do dono — o que vale sem resposta até o prazo (nada muda
  --     na agenda); 2) uso a minha conta pelo orçamento: os dias ficam gravados como os do gestor, com o sim do dono
  --     (estimativa_fonte orcamento, como a opção 1 das perguntas do P4; o histórico e a ação estimar, desfazível) e a
  --     agenda acompanha na hora — sobrando meio-dia, o corte dos últimos (_agenda_gestor_reestimar, do
  --     dono); faltando, o encaixe do que falta (_agenda_propor_e_aplicar, do dono).
  if v_q.tipo in ('reestimar', 'reavaliar') then
    select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
    if v_opc is null then
      return jsonb_build_object('ok', false, 'gestor', true,
        'texto', 'Essa opção não existe. As opções são: '
                 || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                       from jsonb_array_elements(v_q.opcoes) o) || '.');
    end if;
    if v_prazo and v_q.opcao_escolhida is not null then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Você já respondeu essa pergunta: o prazo não vale mais.');
    end if;
    v_ef := coalesce(v_opc -> 'efeito', '{}'::jsonb);
    select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) into v_nome
      from public.service_orders so left join public.clients cl on cl.id = so.client_id
     where so.id = v_q.service_order_id;
    if v_q.tipo = 'reavaliar' then
      if v_prazo then
        return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa pergunta não tem prazo: nada mudou.');
      end if;
      if not (v_ef ? 'terminou' or v_ef ? 'dizer') then
        return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
      end if;
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      return jsonb_build_object('ok', true, 'gestor', true,
        'texto', case when v_ef ? 'terminou' then format('Use *concluiu %s*.', v_nome)
                      else format('Me diga o que mais tem para fazer e quantos dias (ex.: ''%s 2 dias''): eu marco.', v_nome) end);
    end if;
    -- reestimar: a opção tem de ter o que fazer; depois, a condição de agora
    if not (v_ef ? 'manter' or v_ef ? 'dias') then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
    end if;
    v_f9_rq :=public._agenda_gestor_perguntas_da_revisao(v_q.service_order_id, p_hoje, p_agora, true) -> 'reestimar';
    if jsonb_typeof(v_f9_rq) is distinct from 'object' or (v_f9_rq ->> 'chave') is distinct from v_q.chave then
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'não precisa mais: mudou o que falta saber'
       where id = v_q.id;
      return jsonb_build_object('ok', false, 'gestor', true, 'sem_condicao', true,
                                'texto', 'Não mudei nada: não precisa mais (mudou o que falta saber).');
    end if;
    select * into v_f9_pl from public.os_planejamento x where x.service_order_id = v_q.service_order_id for update;
    v_f9_dt := case when v_f9_pl.dias >= 2 then 'os ' else '' end || public._agenda_dias(v_f9_pl.dias);
    if v_ef ? 'manter' then
      if v_prazo then
        v_ate := public._dia_curto((v_q.veto_ate at time zone 'America/Sao_Paulo')::date) || ' às '
                 || to_char(v_q.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI');
        update public.agenda_perguntas
           set estado = 'resolvida', opcao_escolhida = p_opcao,
               resolvida_motivo = left(format('sem resposta até %s: fiquei com os dias que você disse', replace(v_ate, ' às ', ' ')), 200)
         where id = v_q.id;
        return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id, 'via', p_via,
          'texto', format('Sem resposta sobre %s até %s: fiquei com %s que você disse.', v_nome, v_ate, v_f9_dt));
      end if;
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
      return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id,
                                'texto', format('Combinado, %s: fico com %s que você disse.', v_nome, v_f9_dt));
    end if;
    if v_prazo then
      return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não vale sem resposta: nada mudou.');
    end if;
    v_f9_cf := public._agenda_cfg();
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = v_q.id;
    v_f9_ant := jsonb_build_object('dias', v_f9_pl.dias, 'estimativa_fonte', v_f9_pl.estimativa_fonte,
                                   'estimativa_em', v_f9_pl.estimativa_em);
    v_f9_dep := jsonb_build_object('dias', (v_ef ->> 'dias')::numeric, 'estimativa_fonte', 'orcamento', 'estimativa_em', p_agora);
    v_txt := format('Combinado, %s: agora conto %s, pela minha conta do orçamento. *desfaz %s* volta.', v_nome,
                    public._agenda_dias((v_ef ->> 'dias')::numeric), v_nome);
    update public.os_planejamento
       set dias = (v_ef ->> 'dias')::numeric, estimativa_fonte = 'orcamento', estimativa_em = p_agora,
           historico = public._os_material_historico(v_f9_pl.historico, jsonb_build_object(
             'em', (p_agora at time zone 'America/Sao_Paulo')::date, 'quando', p_agora, 'autor', p_autor, 'por', 'dono',
             'motivo', 'você escolheu na pergunta reestimar', 'pergunta', v_q.id, 'antes', v_f9_ant, 'depois', v_f9_dep)),
           atualizado_em = p_agora, atualizado_por = p_autor
     where service_order_id = v_q.service_order_id;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, pergunta_id, antes, depois,
                                     texto, motivo, autor, desfazivel_ate)
    values (p_agora, p_hoje, true, 'dono', 'estimar', v_q.service_order_id, array[v_q.service_order_id], v_q.id, v_f9_ant, v_f9_dep,
            left(public._agenda_corta(v_txt, 400), 400), 'você escolheu na pergunta', p_autor, p_agora + v_f9_cf.desfazer_validade)
    returning id into v_acao;
    -- a agenda acompanha: o que sobra sai, o que falta entra
    v_f9_aj := null;
    if public._agenda_os_tem_dia(v_q.service_order_id, p_hoje) then
      v_f9_m := public.agenda_meios_da_os(v_q.service_order_id, p_hoje);
      v_f9_ft := coalesce((v_f9_m ->> 'cumpridos')::numeric, 0) + coalesce((v_f9_m ->> 'vigentes')::numeric, 0);
      if v_f9_ft - (v_f9_m ->> 'total')::numeric >= 1 then
        v_f9_aj := public._agenda_gestor_reestimar(v_q.service_order_id, p_hoje, p_agora, p_autor);
      elsif (v_f9_m ->> 'total')::numeric > v_f9_ft then
        v_f9_aj := public._agenda_propor_e_aplicar('os', array[v_q.service_order_id], 'dono', p_autor, p_hoje, p_agora);
      end if;
    end if;
    return jsonb_build_object('ok', true, 'gestor', true, 'os', v_q.service_order_id, 'acao_id', v_acao, 'dias', v_ef -> 'dias',
                              'texto', concat_ws(' ', v_txt, nullif(v_f9_aj ->> 'texto', '')), 'agenda', v_f9_aj);
  end if;
  -- FASE 7: fim
  if v_q.tipo not in ('situacao', 'estimativa') then
    return jsonb_build_object('ok', false, 'gestor', true,
      'texto', case when jsonb_array_length(v_q.opcoes) = 0 then 'Essa pergunta não tem opções: me responda com as suas palavras.'
                    else 'Ainda não sei decidir essa pergunta: nada mudou.' end);
  end if;
  select o into v_opc from jsonb_array_elements(v_q.opcoes) o where (o ->> 'n')::int = p_opcao;
  if v_opc is null then
    return jsonb_build_object('ok', false, 'gestor', true,
      'texto', 'Essa opção não existe. As opções são: '
               || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                     from jsonb_array_elements(v_q.opcoes) o) || '.');
  end if;
  if v_prazo and v_q.opcao_escolhida is not null then
    return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Você já respondeu essa pergunta: o prazo não vale mais.');
  end if;
  v_ef := coalesce(v_opc -> 'efeito', '{}'::jsonb);
  select coalesce(public._agenda_nome_curto(cl.name), so.service_order_number) into v_nome
    from public.service_orders so left join public.clients cl on cl.id = so.client_id
   where so.id = v_q.service_order_id;

  if v_ef ? 'dias' then
    -- a condição ainda vale: a pergunta que o gestor faria agora para a OS é esta (o mesmo motivo, os dias ainda não ditos)
    v_agora := public._agenda_gestor_perguntas_da_os(v_q.service_order_id, p_hoje, p_agora, true);
    if (v_agora ->> 'chave') is distinct from v_q.chave then
      v_mot := case when exists (select 1 from public.os_planejamento pl
                                  where pl.service_order_id = v_q.service_order_id and pl.dias is not null)
                    then 'você já disse os dias' else 'não precisa mais: mudou o que falta saber' end;
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = left(v_mot, 200) where id = v_q.id;
      return jsonb_build_object('ok', false, 'gestor', true, 'sem_condicao', true,
                                'texto', format('Não mudei nada: %s.', v_mot));
    end if;
    v_ate := public._dia_curto((v_q.veto_ate at time zone 'America/Sao_Paulo')::date) || ' às '
             || to_char(v_q.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI');
    if v_prazo then
      v_txt := format('Sem resposta sobre %s até %s: %s. *desfaz %s* volta.', v_nome, v_ate, v_ef ->> 'feito', v_nome);
      update public.agenda_perguntas
         set estado = 'resolvida', opcao_escolhida = p_opcao,
             resolvida_motivo = left(format('sem resposta até %s: ficou como eu disse', replace(v_ate, ' às ', ' ')), 200)
       where id = v_q.id;
    else
      v_txt := format('Combinado, %s: %s. *desfaz %s* volta.', v_nome, v_ef ->> 'feito', v_nome);
      update public.agenda_perguntas
         set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
             respondida_por = p_autor, respondida_via = p_via
       where id = v_q.id;
    end if;
    v_acao := public._agenda_gestor_gravar_dias(v_q.service_order_id, (v_ef ->> 'dias')::numeric, v_txt, v_q.id, p_agora);
    if v_acao is null then
      -- (não acontece: a condição acima já viu os dias do dono; se acontecer, nada fica — nem a pergunta respondida)
      raise exception '_agenda_gestor_decidir: os dias do dono já estão gravados' using errcode = 'P0001';
    end if;
    return jsonb_build_object('ok', true, 'gestor', true, 'texto', v_txt, 'acao_id', v_acao, 'os', v_q.service_order_id,
                              'dias', v_ef -> 'dias', 'via', p_via);
  end if;

  if v_prazo then
    -- (a opção que vale sem resposta é sempre a dos dias; outra não se aplica sozinha)
    return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não vale sem resposta: nada mudou.');
  end if;
  if v_ef ? 'dizer' then
    update public.agenda_perguntas set opcao_escolhida = p_opcao, resposta = left(p_trecho, 500) where id = v_q.id;
    return jsonb_build_object('ok', true, 'gestor', true, 'aberta', true,
                              'texto', format('Me diga os dias (ex.: ''%s 3 dias'').', v_nome));
  end if;
  if v_ef ? 'terminou' or v_ef ? 'nao_fazer' then
    update public.agenda_perguntas
       set estado = 'respondida', opcao_escolhida = p_opcao, resposta = left(p_trecho, 500), respondida_em = p_agora,
           respondida_por = p_autor, respondida_via = p_via
     where id = v_q.id;
    return jsonb_build_object('ok', true, 'gestor', true,
      'texto', case when v_ef ? 'terminou' then format('Use *concluiu %s*.', v_nome)
                    else format('Combinado: não marco %s. Para tirar o serviço da carteira, cancele a OS.', v_nome) end);
  end if;
  return jsonb_build_object('ok', false, 'gestor', true, 'texto', 'Essa opção não tem o que fazer: nada mudou.');
end;
$function$;

comment on function public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz) is
  'Agenda de Produção (Fase 7a, P4): o despacho das perguntas do gestor (situacao, estimativa, reavaliar, reestimar, ficha_estimativa, onda, sabado, bem_livre, compre_ate, sinal), chamado por agenda_decidir (o dono) e por _agenda_gestor_vetos (p_via prazo). Só situacao e estimativa decidem aqui (os outros tipos: "não tem opções" ou "ainda não sei decidir", até os pacotes P8, P9, P11 e P12 recriarem ESTA função). Opção com efeito dias: se a pergunta que o gestor faria agora para a OS ainda é esta, grava os dias (_agenda_gestor_gravar_dias; a pergunta respondida pelo dono, ou resolvida "sem resposta até sex 30/10 18:00: ficou como eu disse"); senão resolve a pergunta e nada muda. dizer: fica aberta com a escolha (o prazo não vale mais), "Me diga os dias (ex.: ''Nelson 3 dias'')."; terminou: "Use *concluiu Nelson*."; nao_fazer: "não marco". Só com a pergunta e o modo de quem a fez ligados. Trava agenda_plano. {ok, gestor true, texto, acao_id?, aberta?, sem_condicao?}. Security definer, sem grant a ninguém. FASE 7 (7a P8, spec §5.8): a onda — com a agenda na mesma versão do plano da pergunta, a conta é refeita pelo motor com os parâmetros da proposta dela (agenda_propor persistido, criada_por dono) e aplicada com a pergunta (ações críticas): 1 tudo ("Feito: …"); 2 só as OS de evento real, o de hoje e amanhã (sem nenhuma: "Não havia nada de hoje e amanhã para mudar: não mudei nada."); 3 nada (a proposta descartada; "Combinado: não mudei nada. …"). Com a agenda mudada desde a pergunta, a pergunta resolve e nada muda ("A agenda mudou desde a pergunta: …"). Falhou = nada fica, a pergunta continua aberta. Sem prazo (via prazo: "Essa pergunta não tem prazo"). O P9 e o P12 recriam esta função copiando DESTA migration. FASE 7 (7a P9, spec §5.9 e §6.3): reavaliar (sem prazo) — 1 "Use *concluiu Rodrigo*."; 2 "Me diga o que mais tem para fazer e quantos dias (ex.: ''Rodrigo 2 dias''): eu marco." (as duas respondem); reestimar — só com a condição de agora (a pergunta que a revisão faria para a OS é a mesma: _agenda_gestor_perguntas_da_revisao seco; senão resolve e nada muda): 1 fico com os dias do dono (o prazo: "Sem resposta sobre Nelson até sex 30/10 às 18:00: fiquei com os 4 dias que você disse."; o dono: "Combinado, Nelson: fico com os 4 dias que você disse."); 2 os dias da conta ficam gravados com o sim do dono (estimativa_fonte orcamento, como a opção 1 das perguntas do P4; o histórico e a ação estimar, desfazível) e a agenda acompanha na hora (o corte dos últimos meios-dias do dono, _agenda_gestor_reestimar; ou o encaixe do que falta, _agenda_propor_e_aplicar de origem dono). O P12 recria esta função copiando DESTA migration.';

-- ── 3. Portas ──────────────────────────────────────────────────────────────────────────────────────────────────
-- As contas (a escada, o corte) e as perguntas da revisão são internas: invoker e sem grant a ninguém (as funções definer do
-- gestor e da agenda as chamam). Os dois que escrevem (o conserto e o corte aplicados) são definer e sem grant a ninguém, nem
-- service_role: só agenda_replanejar, a revisão e o despacho os chamam. O passo da revisão é invoker e sem grant, como os outros
-- passos do gestor (a rodada, definer, o chama).
revoke all on function public._agenda_gestor_reparo(uuid, date, timestamptz), public._agenda_gestor_corte(uuid, date, timestamptz),
  public._agenda_gestor_perguntas_da_revisao(uuid, date, timestamptz, boolean), public._agenda_gestor_revisao(date, timestamptz),
  public._agenda_gestor_reparar(uuid, date, timestamptz), public._agenda_gestor_reestimar(uuid, date, timestamptz, uuid)
  from public, anon, authenticated, service_role;

-- As recriadas mantêm as portas de antes (create or replace não as muda; repetidas aqui para a migration valer sozinha).
revoke all on function public.agenda_replanejar(uuid[], text, text, date, timestamptz, uuid),
  public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz)
  from public, anon, authenticated;
grant execute on function public.agenda_replanejar(uuid[], text, text, date, timestamptz, uuid),
  public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz)
  to service_role;
revoke all on function public._agenda_gestor_sombra(date, timestamptz),
  public._agenda_gestor_decidir(uuid, smallint, uuid, text, text, date, timestamptz)
  from public, anon, authenticated, service_role;
